local HttpService = game:GetService("HttpService")
local HttpDiagnostics = require(script.Parent.HttpDiagnostics)
local PluginSession = require(script.Parent.PluginSession)
local PROTOCOL_VERSION = 1
local INITIAL_RETRY_DELAY_SECONDS = 0.5
local MAX_RETRY_DELAY_SECONDS = 5
local SOCKET_SILENCE_TIMEOUT_SECONDS = 20
local RESPONSE_RETENTION_SECONDS = 5 * 60
local RESPONSE_ACK_TIMEOUT_SECONDS = 120
local MAX_TERMINAL_RESPONSES = 32768
local MAX_ACTIVE_RESPONSES = 128
local MAX_ADMISSION_REJECTIONS = 128
local MAX_FRAME_BYTES = 64 * 1024 * 1024
local MAX_PENDING_RESPONSE_BYTES = 64 * 1024 * 1024
local RESERVED_ERROR_BYTES = 4096
-- The bridge admits 128 UTF-16 code units; each can require three UTF-8 bytes.
local MAX_REQUEST_ID_BYTES = 128 * 3
local options
local active = false
local shutdownSuspended = false
local generation = 0
local reconnectAttempt = 0
local socketClient
local socketOpen = false
local socketConnections = {}
local lastValidEventAt = 0
local cachedReady
local readyRefreshPending = false
local pendingResponseBytes = 0
local inFlightRequestBytes = 0
local pendingRejectionCount = 0
local inFlightRequests = {}
local pendingResponses = {}
local terminalResponseIds = {}
local terminalResponseOrder = {}
local terminalHead = 0
local terminalCount = 0
local readyFailureLogKeys = {}
local function validRequestId(value)
	return type(value) == "string" and (#value > 0 and #value <= MAX_REQUEST_ID_BYTES)
end
local function decodeMessage(payload)
	local decodeOk, decoded = pcall(function()
		return HttpService:JSONDecode(payload)
	end)
	if not decodeOk or not (type(decoded) == "table") then
		return nil
	end
	local envelope = decoded
	if envelope.kind == "heartbeat" then
		if not (type(envelope.timestamp) == "number") then
			return nil
		end
		return {
			kind = "heartbeat",
			timestamp = envelope.timestamp,
		}
	end
	if envelope.kind == "status" then
		if not (type(envelope.knownPeer) == "boolean") or not (type(envelope.mcpConnected) == "boolean") then
			return nil
		end
		local object = {
			kind = "status",
			knownPeer = envelope.knownPeer,
			mcpConnected = envelope.mcpConnected,
		}
		object["serverVersion"] = if type(envelope.serverVersion) == "string" then envelope.serverVersion else nil
		object["pluginVersion"] = if type(envelope.pluginVersion) == "string" then envelope.pluginVersion else nil
		object["pluginVariant"] = if type(envelope.pluginVariant) == "string" then envelope.pluginVariant else nil
		return object
	end
	if not validRequestId(envelope.requestId) then
		return nil
	end
	if envelope.kind == "ack" then
		if
			envelope.disposition ~= "accepted"
			and envelope.disposition ~= "already_settled"
			and envelope.disposition ~= "unknown"
		then
			return nil
		end
		return {
			kind = "ack",
			requestId = envelope.requestId,
			disposition = envelope.disposition,
		}
	end
	if envelope.kind == "cancel" then
		if envelope.reason ~= "timeout" and envelope.reason ~= "aborted" and envelope.reason ~= "connection_closed" then
			return nil
		end
		return {
			kind = "cancel",
			requestId = envelope.requestId,
			reason = envelope.reason,
		}
	end
	if envelope.kind == "request" then
		local condition = not (type(envelope.peerId) == "string")
		if not condition then
			condition = not (type(envelope.target) == "string")
			if not condition then
				condition = not (type(envelope.endpoint) == "string")
				if not condition then
					condition = not (type(envelope.remainingMs) == "number")
					if not condition then
						condition = envelope.remainingMs < 0
							or envelope.remainingMs ~= envelope.remainingMs
							or envelope.remainingMs == math.huge
					end
				end
			end
		end
		if condition then
			return nil
		end
		local object = {
			kind = "request",
			requestId = envelope.requestId,
			peerId = envelope.peerId,
			target = envelope.target,
			endpoint = envelope.endpoint,
			remainingMs = envelope.remainingMs,
		}
		object["data"] = if type(envelope.data) == "table" then envelope.data else nil
		return object
	end
	return nil
end
local function closeCurrentSocket()
	local current = socketClient
	socketClient = nil
	socketOpen = false
	for _, connection in socketConnections do
		connection:Disconnect()
	end
	socketConnections = {}
	for _, entry in pendingResponses do
		if entry.ackTimer ~= nil then
			task.cancel(entry.ackTimer)
		end
		entry.ackTimer = nil
	end
	if current ~= nil then
		pcall(function()
			return current:Close()
		end)
	end
end
local function disconnectSession(currentOptions)
	pcall(function()
		return HttpService:RequestAsync({
			Url = `{currentOptions.serverUrl}/disconnect`,
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
			},
			Body = HttpService:JSONEncode({
				peerId = PluginSession.peerId,
			}),
		})
	end)
end
local function retryDelay(attempt)
	return math.min(INITIAL_RETRY_DELAY_SECONDS * math.pow(2, math.max(attempt - 1, 0)), MAX_RETRY_DELAY_SECONDS)
end
local function pruneTerminalResponses()
	local now = os.clock()
	while terminalCount > 0 do
		local oldest = terminalResponseOrder[terminalHead + 1]
		if oldest == nil or oldest.expiresAt > now then
			break
		end
		terminalResponseIds[oldest.requestId] = nil
		terminalResponseOrder[terminalHead + 1] = nil
		terminalHead = (terminalHead + 1) % MAX_TERMINAL_RESPONSES
		terminalCount -= 1
	end
end
local function rememberTerminalResponse(requestId)
	pruneTerminalResponses()
	if terminalResponseIds[requestId] ~= nil then
		return nil
	end
	-- Admission reserves this tombstone before any side effects can execute.
	terminalResponseOrder[(terminalHead + terminalCount) % MAX_TERMINAL_RESPONSES + 1] = {
		requestId = requestId,
		expiresAt = os.clock() + RESPONSE_RETENTION_SECONDS,
	}
	terminalCount += 1
	terminalResponseIds[requestId] = true
end
local scheduleReconnect
local function settleResponse(requestId, entry, disposition)
	if pendingResponses[requestId] ~= entry then
		return nil
	end
	pendingResponses[requestId] = nil
	if entry.admissionRejection then
		pendingRejectionCount -= 1
	else
		pendingResponseBytes -= #entry.body
	end
	if entry.ackTimer ~= nil then
		task.cancel(entry.ackTimer)
	end
	if entry.expiryTimer ~= nil then
		task.cancel(entry.expiryTimer)
	end
	entry.ackTimer = nil
	entry.expiryTimer = nil
	-- Release a queued native frame before making its capacity available again.
	if disposition == "expired" and socketOpen and entry.sentGeneration == generation then
		scheduleReconnect(generation, `WebSocket response {requestId} expired without acknowledgement`)
	end
	entry.body = ""
	rememberTerminalResponse(requestId)
	if disposition == "unknown" or disposition == "expired" then
		warn(
			`[robloxstudio-mcp] Response {requestId} outcome unknown ({disposition}); stored result released, mutation must not be replayed`
		)
	end
end
local function sendProgress(requestId, progress)
	local client = socketClient
	local condition = not active or not socketOpen or client == nil
	if not condition then
		local result = options
		if result ~= nil then
			result = result.serverUrl
		end
		condition = result ~= progress.serverUrl
		if not condition then
			condition = progress.phase == nil
		end
	end
	if condition then
		return nil
	end
	if progress.sentGeneration == generation and progress.sentPhase == progress.phase then
		return nil
	end
	local expectedGeneration = generation
	progress.sentGeneration = expectedGeneration
	progress.sentPhase = progress.phase
	local sent = pcall(function()
		return client:Send(HttpService:JSONEncode({
			kind = "progress",
			requestId = requestId,
			phase = progress.phase,
			outcome = progress.outcome,
		}))
	end)
	if not sent then
		scheduleReconnect(
			expectedGeneration,
			"WebSocket progress send failed; current observation retained for reconnect"
		)
	end
end
local function completeProgress(requestId, progress, outcome)
	progress.phase = "response_delivery"
	progress.outcome = outcome
	sendProgress(requestId, progress)
end
local function handlerOutcome(response)
	if not (type(response) == "table") then
		return "success"
	end
	local result = response
	if result.error ~= nil or result.success == false or result.ok == false then
		return "error"
	end
	if type(result.summary) == "table" then
		local summary = result.summary
		if type(summary.failed) == "number" and summary.failed > 0 then
			return "error"
		end
	end
	return "success"
end
local function sendPendingResponse(requestId, entry)
	sendProgress(requestId, entry.progress)
	local client = socketClient
	local condition = not active or not socketOpen or client == nil
	if not condition then
		local result = options
		if result ~= nil then
			result = result.serverUrl
		end
		condition = result ~= entry.serverUrl
		if not condition then
			condition = pendingResponses[requestId] ~= entry
		end
	end
	if condition then
		return nil
	end
	if os.clock() >= entry.expiresAt then
		settleResponse(requestId, entry, "expired")
		return nil
	end
	if entry.sentGeneration == generation then
		return nil
	end
	local expectedGeneration = generation
	entry.sentGeneration = expectedGeneration
	local sendOk, sendError = pcall(function()
		return client:Send(entry.body)
	end)
	if not sendOk then
		warn(
			`[robloxstudio-mcp] WebSocket response send failed for {requestId} ({#entry.body} bytes, stage=socket_send): {tostring(
				sendError
			)}`
		)
		scheduleReconnect(expectedGeneration, "WebSocket response send failed; retained for reconnect")
		return nil
	end
	if pendingResponses[requestId] ~= entry or (generation ~= expectedGeneration or socketClient ~= client) then
		return nil
	end
	-- Send only queues bytes. A heartbeat does not prove that this upload drained.
	-- Give large transfers a generous window, growing after reconnect; never put
	-- a second copy on the same socket, even when an acknowledgement is lost.
	entry.sendAttempt += 1
	local ackDelay = RESPONSE_ACK_TIMEOUT_SECONDS * math.pow(2, math.min(entry.sendAttempt - 1, 2))
	if os.clock() + ackDelay >= entry.expiresAt then
		return nil
	end
	entry.ackTimer = task.delay(ackDelay, function()
		entry.ackTimer = nil
		if generation ~= expectedGeneration or pendingResponses[requestId] ~= entry then
			return nil
		end
		scheduleReconnect(
			expectedGeneration,
			`WebSocket response {requestId} acknowledgement timed out; retained for reconnect`
		)
	end)
end
local function resumePendingResponses()
	for requestId, entry in inFlightRequests do
		sendProgress(requestId, entry.progress)
	end
	for requestId, entry in pendingResponses do
		sendPendingResponse(requestId, entry)
	end
end
local function encodeError(requestId, detail, executionOutcome)
	local encodeOk, encoded = pcall(function()
		return HttpService:JSONEncode({
			kind = "response",
			requestId = requestId,
			executionOutcome = executionOutcome,
			error = `Request {requestId}: {detail}`,
		})
	end)
	if encodeOk and #encoded <= RESERVED_ERROR_BYTES then
		return encoded
	end
	return HttpService:JSONEncode({
		kind = "response",
		requestId = requestId,
		executionOutcome = executionOutcome,
		error = `Request {requestId}: Plugin error could not be encoded within its reserved response capacity (stage=error_encode); handler outcome={executionOutcome}`,
	})
end
local function encodeResponse(requestId, response, executionOutcome)
	local encodeOk, encoded = pcall(function()
		return HttpService:JSONEncode({
			kind = "response",
			requestId = requestId,
			response = response,
			executionOutcome = executionOutcome,
		})
	end)
	if not encodeOk then
		return encodeError(
			requestId,
			`Plugin response serialization failed (stage=response_encode): {string.sub(tostring(encoded), 1, 512)}`,
			executionOutcome
		)
	end
	if #encoded > MAX_FRAME_BYTES then
		return encodeError(
			requestId,
			`Plugin response exceeds WebSocket frame limit (stage=response_encode, bytes={#encoded}, maxBytes={MAX_FRAME_BYTES}); execution completed but result cannot be delivered`,
			executionOutcome
		)
	end
	return encoded
end
local function retainResponse(requestId, body, serverUrl, progress, admissionRejection)
	if admissionRejection == nil then
		admissionRejection = false
	end
	-- Admission errors have their own bounded 128 x 4KiB reserve so a full-size
	-- result never consumes the capacity required to retain a rejection.
	-- ▼ ReadonlyMap.size ▼
	local _size = 0
	for _ in inFlightRequests do
		_size += 1
	end
	-- ▲ ReadonlyMap.size ▲
	-- ▼ ReadonlyMap.size ▼
	local size_1 = 0
	for _ in pendingResponses do
		size_1 += 1
	end
	-- ▲ ReadonlyMap.size ▲
	local reservedBytes = (_size + size_1 - pendingRejectionCount) * RESERVED_ERROR_BYTES
	if not admissionRejection and pendingResponseBytes + #body + reservedBytes > MAX_PENDING_RESPONSE_BYTES then
		body = encodeError(
			requestId,
			`Plugin response exceeds retained-result capacity (stage=response_retention, bytes={#body}, retainedBytes={pendingResponseBytes}, maxBytes={MAX_PENDING_RESPONSE_BYTES}); execution completed but result cannot be retained`,
			progress.outcome or "unknown"
		)
	end
	local entry = {
		body = body,
		serverUrl = serverUrl,
		progress = progress,
		expiresAt = os.clock() + RESPONSE_RETENTION_SECONDS,
		admissionRejection = admissionRejection,
		sendAttempt = 0,
	}
	pendingResponses[requestId] = entry
	if admissionRejection then
		pendingRejectionCount += 1
	else
		pendingResponseBytes += #body
	end
	entry.expiryTimer = task.delay(RESPONSE_RETENTION_SECONDS, function()
		entry.expiryTimer = nil
		if pendingResponses[requestId] == entry then
			settleResponse(requestId, entry, "expired")
		end
	end)
	sendPendingResponse(requestId, entry)
end
local function rejectAdmission(requestId, detail)
	local currentOptions = options
	if currentOptions == nil then
		return nil
	end
	local condition = pendingRejectionCount >= MAX_ADMISSION_REJECTIONS
	if not condition then
		local exp = terminalCount
		-- ▼ ReadonlyMap.size ▼
		local _size = 0
		for _ in inFlightRequests do
			_size += 1
		end
		-- ▲ ReadonlyMap.size ▲
		local exp_1 = exp + _size
		-- ▼ ReadonlyMap.size ▼
		local size_1 = 0
		for _ in pendingResponses do
			size_1 += 1
		end
		-- ▲ ReadonlyMap.size ▲
		condition = exp_1 + size_1 >= MAX_TERMINAL_RESPONSES
	end
	if condition then
		-- No execution and no unretained "result". Reconnect drains existing
		-- outcomes so their acknowledgements can release rejection reservations.
		scheduleReconnect(generation, "Plugin admission rejection reserve exhausted; execution not started")
		return nil
	end
	local progress = {
		serverUrl = currentOptions.serverUrl,
	}
	completeProgress(requestId, progress, "not_executed")
	retainResponse(requestId, encodeError(requestId, detail, "not_executed"), currentOptions.serverUrl, progress, true)
end
local function cancelRequest(event)
	local inFlight = inFlightRequests[event.requestId]
	if inFlight ~= nil then
		inFlight.cancelled = true
	end
	-- Cancellation only changes execution context. Completed results still need
	-- recording, including results produced by already-running side effects.
end
local function dispatchRequest(request, requestBytes)
	pruneTerminalResponses()
	local condition = terminalResponseIds[request.requestId] ~= nil
	if not condition then
		condition = pendingResponses[request.requestId] ~= nil
		if not condition then
			condition = inFlightRequests[request.requestId] ~= nil
		end
	end
	if condition then
		return nil
	end
	local dispatchOptions = options
	if not active or dispatchOptions == nil then
		return nil
	end
	-- ▼ ReadonlyMap.size ▼
	local _size = 0
	for _ in inFlightRequests do
		_size += 1
	end
	-- ▲ ReadonlyMap.size ▲
	-- ▼ ReadonlyMap.size ▼
	local size_1 = 0
	for _ in pendingResponses do
		size_1 += 1
	end
	-- ▲ ReadonlyMap.size ▲
	local activeCount = _size + size_1 - pendingRejectionCount
	if
		activeCount >= MAX_ACTIVE_RESPONSES
		or terminalCount + activeCount + MAX_ADMISSION_REJECTIONS >= MAX_TERMINAL_RESPONSES
		or pendingResponseBytes + (activeCount + 1) * RESERVED_ERROR_BYTES > MAX_PENDING_RESPONSE_BYTES
		or inFlightRequestBytes + requestBytes > MAX_FRAME_BYTES
	then
		rejectAdmission(
			request.requestId,
			`Plugin request admission capacity exceeded (stage=request_admission, bytes={requestBytes}, inFlightBytes={inFlightRequestBytes}, activeResponses={activeCount}, maxActiveResponses={MAX_ACTIVE_RESPONSES}, terminalIds={terminalCount}, maxTerminalIds={MAX_TERMINAL_RESPONSES}, retainedBytes={pendingResponseBytes}, maxBytes={MAX_PENDING_RESPONSE_BYTES}); execution not started`
		)
		return nil
	end
	local inFlight = {
		cancelled = false,
		progress = {
			serverUrl = dispatchOptions.serverUrl,
		},
	}
	local context = {
		requestId = request.requestId,
		deadlineAt = os.clock() + request.remainingMs / 1000,
		isCancelled = function()
			return inFlight.cancelled
		end,
	}
	inFlightRequests[request.requestId] = inFlight
	inFlightRequestBytes += requestBytes
	task.spawn(function()
		if inFlight.cancelled or not active or os.clock() >= context.deadlineAt then
			completeProgress(request.requestId, inFlight.progress, "not_executed")
			inFlightRequests[request.requestId] = nil
			inFlightRequestBytes -= requestBytes
			retainResponse(
				request.requestId,
				encodeError(
					request.requestId,
					"Request cancelled or admission deadline expired before execution started",
					"not_executed"
				),
				dispatchOptions.serverUrl,
				inFlight.progress
			)
			return nil
		end
		-- This observes handler entry, including broker dispatch, not a user Luau
		-- instruction. The waiter's deadline/cancellation is not a rollback.
		inFlight.progress.phase = "executing"
		sendProgress(request.requestId, inFlight.progress)
		local dispatchOk, response = pcall(function()
			return dispatchOptions.dispatchRequest(request, context)
		end)
		local executionOutcome = if dispatchOk then handlerOutcome(response) else "error"
		-- Report handler return before JSON encoding or result retention can fail.
		completeProgress(request.requestId, inFlight.progress, executionOutcome)
		local body = if dispatchOk
			then encodeResponse(request.requestId, response, executionOutcome)
			else encodeError(
				request.requestId,
				`Plugin request execution failed: {string.sub(tostring(response), 1, 512)}`,
				executionOutcome
			)
		inFlightRequests[request.requestId] = nil
		inFlightRequestBytes -= requestBytes
		retainResponse(request.requestId, body, dispatchOptions.serverUrl, inFlight.progress)
	end)
end
local function invokeCallback(name, callback)
	local callbackOk, callbackError = pcall(callback)
	if not callbackOk then
		warn(`[robloxstudio-mcp] {name} callback failed: {tostring(callbackError)}`)
	end
end
local function reportTransport(update)
	local currentOptions = options
	if active and currentOptions ~= nil then
		invokeCallback("WebSocket transport", function()
			return currentOptions.onTransportUpdate(update)
		end)
	end
end
local connect
function scheduleReconnect(expectedGeneration, detail, duplicate)
	if duplicate == nil then
		duplicate = false
	end
	if not active or generation ~= expectedGeneration then
		return nil
	end
	generation += 1
	closeCurrentSocket()
	reconnectAttempt += 1
	local delay = if duplicate then 1 else retryDelay(reconnectAttempt)
	reportTransport({
		state = if duplicate then "waiting-duplicate" else "retrying",
		attempt = reconnectAttempt,
		retryDelay = delay,
		detail = detail,
	})
	local nextGeneration = generation
	task.delay(delay, function()
		if active and generation == nextGeneration then
			connect(nextGeneration)
		end
	end)
end
local function watchForSilence(expectedGeneration, expectedClient)
	local elapsed = tick() - lastValidEventAt
	task.delay(math.max(SOCKET_SILENCE_TIMEOUT_SECONDS - elapsed, 0.1), function()
		if not active or generation ~= expectedGeneration or socketClient ~= expectedClient then
			return nil
		end
		local silentFor = tick() - lastValidEventAt
		if silentFor >= SOCKET_SILENCE_TIMEOUT_SECONDS then
			scheduleReconnect(expectedGeneration, `WebSocket silent for {math.floor(silentFor)} seconds`)
			return nil
		end
		watchForSilence(expectedGeneration, expectedClient)
	end)
end
local function parseReadyResponse(body)
	local decodeOk, decoded = pcall(function()
		return HttpService:JSONDecode(body)
	end)
	if not decodeOk or not (type(decoded) == "table") then
		return nil
	end
	local value = decoded
	local condition = value.success ~= true
	if not condition then
		condition = not (type(value.assignedRole) == "string")
		if not condition then
			condition = value.assignedRole == ""
			if not condition then
				condition = not (type(value.peerId) == "string")
				if not condition then
					condition = value.peerId == ""
					if not condition then
						condition = not (type(value.instanceId) == "string")
						if not condition then
							condition = value.instanceId == "" or value.protocolVersion ~= PROTOCOL_VERSION
							if not condition then
								condition = not (type(value.transportToken) == "string")
								if not condition then
									condition = value.transportToken == ""
									if not condition then
										local condition_1 = value.multiplayerGroupId ~= nil
											and not (type(value.multiplayerGroupId) == "string")
										condition = condition_1
									end
								end
							end
						end
					end
				end
			end
		end
	end
	if condition then
		return nil
	end
	return {
		success = true,
		assignedRole = value.assignedRole,
		peerId = value.peerId,
		instanceId = value.instanceId,
		multiplayerGroupId = value.multiplayerGroupId,
		protocolVersion = PROTOCOL_VERSION,
		transportToken = value.transportToken,
	}
end
local function registerReady(currentOptions, expectedGeneration, reconnectOnFailure)
	local instanceId = PluginSession.getInstanceId()
	local multiplayerGroupId = PluginSession.getMultiplayerGroupId()
	local transportRole = PluginSession.getRole()
	local readyUrl = `{currentOptions.serverUrl}/ready`
	local readyPayload =
		PluginSession.createReadyPayload(PluginSession.peerId, transportRole, instanceId, multiplayerGroupId)
	if not active or generation ~= expectedGeneration or options ~= currentOptions then
		return nil
	end
	local readyOk, readyResult = pcall(function()
		return HttpService:RequestAsync({
			Url = readyUrl,
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
			},
			Body = HttpService:JSONEncode(readyPayload),
		})
	end)
	if not active or generation ~= expectedGeneration or options ~= currentOptions then
		return nil
	end
	local readyLogKey = `{currentOptions.serverUrl}|{PluginSession.peerId}`
	if not readyOk or not readyResult.Success then
		local detail = if readyOk
			then HttpDiagnostics.formatRequestFailure(readyUrl, true, readyResult)
			else HttpDiagnostics.formatRequestFailure(readyUrl, false, readyResult)
		if not (readyFailureLogKeys[readyLogKey] ~= nil) then
			readyFailureLogKeys[readyLogKey] = true
			warn(`[robloxstudio-mcp] /ready failed for {instanceId}/{transportRole}: {detail}`)
		end
		if reconnectOnFailure then
			scheduleReconnect(expectedGeneration, detail, readyOk and readyResult.StatusCode == 409)
		end
		return nil
	end
	local readyData = parseReadyResponse(readyResult.Body)
	if
		readyData == nil
		or readyData.peerId ~= PluginSession.peerId
		or readyData.instanceId ~= instanceId
		or readyData.multiplayerGroupId ~= multiplayerGroupId
	then
		if reconnectOnFailure then
			scheduleReconnect(
				expectedGeneration,
				"Invalid /ready response: expected Peer topology and WebSocket protocol credentials"
			)
		end
		return nil
	end
	if readyFailureLogKeys[readyLogKey] ~= nil then
		readyFailureLogKeys[readyLogKey] = nil
		print(
			`[robloxstudio-mcp] /ready connected for {instanceId}/{readyData.assignedRole} via {currentOptions.serverUrl}`
		)
	end
	cachedReady = readyData
	invokeCallback("WebSocket ready", function()
		return currentOptions.onReady(readyData)
	end)
	return readyData
end
local function credentialsRejected(statusCode)
	return statusCode == 401 or statusCode == 403 or statusCode == 404
end
function connect(expectedGeneration)
	local currentOptions = options
	if not active or generation ~= expectedGeneration or currentOptions == nil then
		return nil
	end
	reportTransport({
		state = "connecting",
		attempt = reconnectAttempt,
		retryDelay = 0,
	})
	task.spawn(function()
		local readyData = cachedReady or registerReady(currentOptions, expectedGeneration, true)
		if readyData == nil or not active or generation ~= expectedGeneration or options ~= currentOptions then
			return nil
		end
		local socketBaseUrl = string.gsub(currentOptions.serverUrl, "^http", "ws")
		local createOk, createdClient = pcall(function()
			return HttpService:CreateWebStreamClient(Enum.WebStreamClientType.WebSocket, {
				Url = `{socketBaseUrl}/studio?peerId={HttpService:UrlEncode(PluginSession.peerId)}&protocolVersion={PROTOCOL_VERSION}`,
				Headers = {
					["X-Studio-Token"] = readyData.transportToken,
				},
			})
		end)
		if not createOk then
			scheduleReconnect(expectedGeneration, `Failed to create WebSocket: {tostring(createdClient)}`)
			return nil
		end
		if not active or generation ~= expectedGeneration or options ~= currentOptions then
			pcall(function()
				return createdClient:Close()
			end)
			return nil
		end
		socketClient = createdClient
		socketConnections = {
			createdClient.Opened:Connect(function(statusCode, _headers)
				if not active or generation ~= expectedGeneration or socketClient ~= createdClient then
					return nil
				end
				if statusCode ~= 101 and (statusCode < 200 or statusCode >= 300) then
					if credentialsRejected(statusCode) then
						cachedReady = nil
					end
					scheduleReconnect(expectedGeneration, `WebSocket opened with HTTP {statusCode}`)
					return nil
				end
				socketOpen = true
				lastValidEventAt = tick()
				reconnectAttempt = 0
				reportTransport({
					state = "open",
					attempt = 0,
					retryDelay = 0,
				})
				resumePendingResponses()
			end),
			createdClient.MessageReceived:Connect(function(message)
				if not active or generation ~= expectedGeneration or socketClient ~= createdClient then
					return nil
				end
				if not (type(message) == "string") then
					scheduleReconnect(
						expectedGeneration,
						"Unsupported binary WebSocket frame (stage=request_receive); text JSON required"
					)
					return nil
				end
				if #message > MAX_FRAME_BYTES then
					local detail =
						`WebSocket request frame exceeds limit (stage=request_receive, bytes={#message}, maxBytes={MAX_FRAME_BYTES}); execution not started`
					warn(`[robloxstudio-mcp] {detail}`)
					scheduleReconnect(expectedGeneration, detail)
					return nil
				end
				local event = decodeMessage(message)
				if event == nil then
					return nil
				end
				lastValidEventAt = tick()
				if event.kind == "ack" then
					local pending = pendingResponses[event.requestId]
					if pending ~= nil and pending.serverUrl == currentOptions.serverUrl then
						settleResponse(event.requestId, pending, event.disposition)
					end
				elseif event.kind == "heartbeat" then
					invokeCallback("WebSocket heartbeat", function()
						return currentOptions.onHeartbeat(event.timestamp)
					end)
				elseif event.kind == "cancel" then
					cancelRequest(event)
				elseif event.kind == "request" then
					dispatchRequest(event, #message)
				else
					invokeCallback("WebSocket status", function()
						return currentOptions.onStatus(event)
					end)
					if not event.knownPeer then
						cachedReady = nil
						scheduleReconnect(expectedGeneration, "WebSocket session is no longer registered")
					end
				end
			end),
			createdClient.Error:Connect(function(statusCode, message)
				if not active or generation ~= expectedGeneration or socketClient ~= createdClient then
					return nil
				end
				if credentialsRejected(statusCode) then
					cachedReady = nil
				end
				scheduleReconnect(expectedGeneration, `WebSocket error {statusCode}: {message}`)
			end),
			createdClient.Closed:Connect(function()
				if not active or generation ~= expectedGeneration or socketClient ~= createdClient then
					return nil
				end
				scheduleReconnect(expectedGeneration, "WebSocket closed")
			end),
		}
		lastValidEventAt = tick()
		watchForSilence(expectedGeneration, createdClient)
	end)
end
local stop
local function start(newOptions)
	if active or shutdownSuspended then
		stop()
	end
	options = newOptions
	active = true
	shutdownSuspended = false
	reconnectAttempt = 0
	generation += 1
	connect(generation)
end
local function refresh()
	local currentOptions = options
	if not active or currentOptions == nil or readyRefreshPending then
		return nil
	end
	-- Metadata changes must not close a healthy socket or make its reconnect
	-- depend on RequestAsync quota. Proxy registration remains independent.
	readyRefreshPending = true
	local expectedGeneration = generation
	task.spawn(function()
		registerReady(currentOptions, expectedGeneration, false)
		readyRefreshPending = false
	end)
end
-- EndTest may tear down this VM without an Unloading callback. Release the
-- native socket before yielding to unregister; a failed EndTest can resume.
local function suspendForShutdown()
	local currentOptions = options
	if not active or currentOptions == nil then
		return nil
	end
	active = false
	shutdownSuspended = true
	generation += 1
	reconnectAttempt = 0
	closeCurrentSocket()
	cachedReady = nil
	disconnectSession(currentOptions)
end
local function resumeAfterShutdownFailure()
	if not shutdownSuspended or options == nil then
		return nil
	end
	shutdownSuspended = false
	active = true
	generation += 1
	reconnectAttempt = 0
	connect(generation)
end
function stop()
	if not active and not shutdownSuspended then
		return nil
	end
	local currentOptions = options
	active = false
	shutdownSuspended = false
	generation += 1
	for _, inFlight in inFlightRequests do
		inFlight.cancelled = true
	end
	closeCurrentSocket()
	cachedReady = nil
	table.clear(readyFailureLogKeys)
	options = nil
	reconnectAttempt = 0
	if currentOptions ~= nil then
		disconnectSession(currentOptions)
	end
end
return {
	start = start,
	refresh = refresh,
	suspendForShutdown = suspendForShutdown,
	resumeAfterShutdownFailure = resumeAfterShutdownFailure,
	stop = stop,
}
