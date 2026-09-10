local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local RuntimeLogBuffer = require(script.Parent.RuntimeLogBuffer)
local MemoryHandlers = require(script.Parent.handlers.MemoryHandlers)
local SceneAnalysisHandlers = require(script.Parent.handlers.SceneAnalysisHandlers)
local CaptureHandlers = require(script.Parent.handlers.CaptureHandlers)
local InputHandlers = require(script.Parent.handlers.InputHandlers)
local MetadataHandlers = require(script.Parent.handlers.MetadataHandlers)
local EvalRuntimeHandlers = require(script.Parent.handlers.EvalRuntimeHandlers)
local BreakpointHandlers = require(script.Parent.handlers.BreakpointHandlers)
local ScriptProfilerHandlers = require(script.Parent.handlers.ScriptProfilerHandlers)
local MicroProfilerHandlers = require(script.Parent.handlers.MicroProfilerHandlers)
local LuauExec = require(script.Parent.LuauExec)
local HttpDiagnostics = require(script.Parent.HttpDiagnostics)
local PluginSession = require(script.Parent.PluginSession)
local TopologyId = require(script.Parent.TopologyId)
local PeerRole = require(script.Parent.PeerRole)
local StudioTestService = game:GetService("StudioTestService")
-- Client Peers cannot reach the MCP HTTP server, so the server transport
-- forwards requests over this RemoteFunction. The client supplies only its
-- VM Peer identity; the server broker assigns trusted process/group topology
-- from its own playtest context before publishing that Peer to MCP.
local DEFAULT_MCP_URL = "http://localhost:58741"
local mcpUrl = DEFAULT_MCP_URL
local BROKER_NAME = "__MCPClientBroker"
local BROKER_OWNER_ATTRIBUTE = "__MCPBrokerOwner"
local CLIENT_IDENTITY_KIND = "identity"
-- Endpoints the server-peer broker is allowed to forward to the client peer.
-- Each requires the client peer's plugin VM (because the buffer / require
-- cache / etc. lives there) so the server peer alone can't satisfy them.
local CLIENT_BROKER_ALLOWED_ENDPOINTS = {
	["/api/execute-luau"] = true,
	["/api/eval-runtime"] = true,
	["/api/get-runtime-logs"] = true,
	["/api/get-memory-breakdown"] = true,
	["/api/get-scene-analysis"] = true,
	["/api/breakpoints"] = true,
	["/api/capture-script-profiler"] = true,
	["/api/capture-micro-profiler"] = true,
	["/api/multiplayer-test-state"] = true,
	["/api/multiplayer-test-leave-client"] = true,
	["/api/capture-begin"] = true,
	["/api/simulate-mouse-input"] = true,
	["/api/simulate-keyboard-input"] = true,
	["/api/focus-viewport"] = true,
}
local function forkRole()
	return PeerRole.detect()
end
local function postJson(endpoint, body)
	return pcall(function()
		return HttpService:RequestAsync({
			Url = `{mcpUrl}{endpoint}`,
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
			},
			Body = HttpService:JSONEncode(body),
		})
	end)
end
local function formatPostJsonFailure(endpoint, ok, res)
	return HttpDiagnostics.formatRequestFailure(`{mcpUrl}{endpoint}`, ok, res)
end
local function setServerUrl(serverUrl)
	if serverUrl ~= nil and serverUrl ~= "" then
		mcpUrl = serverUrl
	end
end
local function handleExecuteLuau(data)
	local code = data and data.code
	if type(code) == "string" == false or code == "" then
		return {
			success = false,
			error = "code is required",
		}
	end
	-- Shared with edit/server (MetadataHandlers.executeLuau). Adds the IIFE
	-- wrapper (so `print("hi")` with no return doesn't fail the
	-- ModuleScript's "must return one value" rule) and JSON-encodes table
	-- returns instead of yielding "table: 0xaddr".
	return LuauExec.execute(code)
end
local function handleGetRuntimeLogs(data)
	local d = data or {}
	local since = d.since
	local tail = d.tail
	local filter = d.filter
	return RuntimeLogBuffer.query({
		since = since,
		tail = tail,
		filter = filter,
	})
end
local function handleMultiplayerTestState()
	local argsOk, args = pcall(function()
		return StudioTestService:GetTestArgs()
	end)
	local canLeaveOk, canLeave = pcall(function()
		return StudioTestService:CanLeaveTest()
	end)
	local exp = Players:GetPlayers()
	local players = table.create(#exp)
	for i, player in exp do
		players[i] = {
			name = player.Name,
			userId = player.UserId,
			displayName = player.DisplayName,
		}
	end
	table.sort(players, function(a, b)
		return a.name < b.name
	end)
	return {
		success = true,
		peer = "client",
		isRunning = RunService:IsRunning(),
		isRunMode = RunService:IsRunMode(),
		editModeActive = StudioTestService.EditModeActive,
		testArgsOk = argsOk,
		testArgs = if argsOk then args else nil,
		testArgsError = if argsOk then nil else tostring(args),
		players = players,
		playerCount = #players,
		localPlayer = if Players.LocalPlayer then Players.LocalPlayer.Name else nil,
		canLeaveOk = canLeaveOk,
		canLeave = if canLeaveOk then canLeave else false,
		canLeaveError = if canLeaveOk then nil else tostring(canLeave),
	}
end
local function handleMultiplayerTestLeaveClient()
	local canLeaveOk, canLeave = pcall(function()
		return StudioTestService:CanLeaveTest()
	end)
	if not canLeaveOk then
		return {
			error = tostring(canLeave),
			canLeaveOk = false,
		}
	end
	if not canLeave then
		return {
			error = "This client cannot leave the current test session.",
			canLeaveOk = true,
			canLeave = false,
		}
	end
	local localPlayer = if Players.LocalPlayer then Players.LocalPlayer.Name else nil
	task.defer(function()
		pcall(function()
			return StudioTestService:LeaveTest()
		end)
	end)
	return {
		success = true,
		message = "Client leave requested.",
		localPlayer = localPlayer,
	}
end
local proxyRetryDelay
local function sendClientIdentity(rf, attempt)
	if PeerRole.detect() ~= "client" or rf.Parent == nil then
		return nil
	end
	local identity = {
		kind = "identity",
		peerId = PluginSession.peerId,
	}
	local ok, response = pcall(function()
		return rf:InvokeServer(identity)
	end)
	if ok and type(response) == "table" then
		local acknowledgement = response
		if acknowledgement.success == true then
			return nil
		end
	end
	if attempt == 0 then
		warn(`[robloxstudio-mcp] client identity handshake failed; retrying`)
	end
	task.delay(proxyRetryDelay(attempt + 1), sendClientIdentity, rf, attempt + 1)
end
local function setupClientBroker(attempt)
	if attempt == nil then
		attempt = 0
	end
	if PeerRole.detect() ~= "client" then
		return nil
	end
	local rf = ReplicatedStorage:WaitForChild(BROKER_NAME, 10)
	if not rf or not rf:IsA("RemoteFunction") then
		if attempt == 0 then
			warn(`[robloxstudio-mcp] client: {BROKER_NAME} not found; retrying`)
		end
		if RunService:IsRunning() then
			task.delay(proxyRetryDelay(attempt + 1), setupClientBroker, attempt + 1)
		end
		return nil
	end
	rf.OnClientInvoke = function(payload)
		if not payload or not (type(payload.endpoint) == "string") then
			return {
				error = "Client broker request is missing its endpoint.",
			}
		end
		if payload and payload.endpoint == "/api/get-runtime-logs" then
			return handleGetRuntimeLogs(payload.data)
		end
		if payload and payload.endpoint == "/api/get-memory-breakdown" then
			return MemoryHandlers.getMemoryBreakdown(payload.data or {})
		end
		if payload and payload.endpoint == "/api/get-scene-analysis" then
			return SceneAnalysisHandlers.getSceneAnalysis(payload.data or {})
		end
		if payload and payload.endpoint == "/api/breakpoints" then
			return BreakpointHandlers.breakpoints(payload.data or {})
		end
		if payload and payload.endpoint == "/api/capture-script-profiler" then
			return ScriptProfilerHandlers.captureScriptProfiler(payload.data or {})
		end
		if payload and payload.endpoint == "/api/capture-micro-profiler" then
			return MicroProfilerHandlers.captureMicroProfiler(payload.data or {})
		end
		if payload and payload.endpoint == "/api/multiplayer-test-state" then
			return handleMultiplayerTestState()
		end
		if payload and payload.endpoint == "/api/multiplayer-test-leave-client" then
			return handleMultiplayerTestLeaveClient()
		end
		if payload and payload.endpoint == "/api/capture-begin" then
			return CaptureHandlers.captureBegin()
		end
		if payload and payload.endpoint == "/api/simulate-mouse-input" then
			return InputHandlers.simulateMouseInput(payload.data or {})
		end
		if payload and payload.endpoint == "/api/simulate-keyboard-input" then
			return InputHandlers.simulateKeyboardInput(payload.data or {})
		end
		if payload and payload.endpoint == "/api/focus-viewport" then
			return MetadataHandlers.focusViewport(payload.data or {})
		end
		if payload and payload.endpoint == "/api/execute-luau" then
			return handleExecuteLuau(payload.data)
		end
		if payload and payload.endpoint == "/api/eval-runtime" then
			return EvalRuntimeHandlers.evalRuntime(payload.data or {})
		end
		return {
			error = `Unsupported client broker endpoint: {payload.endpoint}`,
		}
	end
	task.spawn(sendClientIdentity, rf, 0)
end
local INITIAL_PROXY_RETRY_DELAY_SECONDS = 0.5
local MAX_PROXY_RETRY_DELAY_SECONDS = 5
local proxyByPlayer = {}
local proxyByPeerId = {}
local proxyRegisterFailuresByPlayer = {}
local pendingProxyDisconnects = {}
local serverBrokerStarted = false
local queueProxyDisconnect
local function unregisterProxy(player, entry)
	local proxy = if entry ~= nil then entry else proxyByPlayer[player]
	if not proxy then
		return nil
	end
	proxy.generation += 1
	proxyByPlayer[player] = nil
	proxyByPeerId[proxy.peerId] = nil
	proxyRegisterFailuresByPlayer[player] = nil
	queueProxyDisconnect(proxy.peerId)
end
local function disconnectAllProxies()
	for player, entry in proxyByPlayer do
		unregisterProxy(player, entry)
	end
	table.clear(proxyByPlayer)
	table.clear(proxyByPeerId)
	table.clear(proxyRegisterFailuresByPlayer)
end
function proxyRetryDelay(attempt)
	return math.min(
		INITIAL_PROXY_RETRY_DELAY_SECONDS * math.pow(2, math.max(attempt - 1, 0)),
		MAX_PROXY_RETRY_DELAY_SECONDS
	)
end
local function deliverProxyDisconnect(peerId, attempt)
	if not (pendingProxyDisconnects[peerId] ~= nil) then
		return nil
	end
	local ok, response = postJson("/disconnect", {
		peerId = peerId,
	})
	if ok and response and response.Success then
		pendingProxyDisconnects[peerId] = nil
		return nil
	end
	task.delay(proxyRetryDelay(attempt + 1), function()
		deliverProxyDisconnect(peerId, attempt + 1)
	end)
end
function queueProxyDisconnect(peerId)
	if pendingProxyDisconnects[peerId] ~= nil then
		return nil
	end
	pendingProxyDisconnects[peerId] = true
	task.spawn(deliverProxyDisconnect, peerId, 0)
end
local function parseAssignedRole(body, entry)
	local decodeOk, decoded = pcall(function()
		return HttpService:JSONDecode(body)
	end)
	if not decodeOk or not (type(decoded) == "table") then
		return nil
	end
	local ready = decoded
	if
		ready.success ~= true
		or ready.peerId ~= entry.peerId
		or ready.instanceId ~= entry.instanceId
		or ready.multiplayerGroupId ~= entry.multiplayerGroupId
	then
		return nil
	end
	local condition = type(ready.assignedRole) == "string" and ready.assignedRole ~= ""
	return if condition then ready.assignedRole else nil
end
local registerProxyEntry
local function scheduleProxyRetry(entry)
	entry.retryAttempt += 1
	local expectedGeneration = entry.generation
	task.delay(proxyRetryDelay(entry.retryAttempt), function()
		if
			proxyByPlayer[entry.player] ~= entry
			or (
				entry.generation ~= expectedGeneration
				or entry.registered
				or entry.registering
				or entry.player.Parent == nil
				or not RunService:IsRunning()
			)
		then
			return nil
		end
		registerProxyEntry(entry)
	end)
end
local function failProxyRegistration(entry, detail)
	entry.registered = false
	if not (proxyRegisterFailuresByPlayer[entry.player] ~= nil) then
		proxyRegisterFailuresByPlayer[entry.player] = true
		warn(`[robloxstudio-mcp] proxy register failed for {entry.player.Name}: {detail}`)
	end
	scheduleProxyRetry(entry)
end
function registerProxyEntry(entry)
	local condition = entry.registering
	if not condition then
		condition = proxyByPlayer[entry.player] ~= entry
		if not condition then
			condition = entry.player.Parent == nil or not RunService:IsRunning()
		end
	end
	if condition then
		return nil
	end
	entry.registering = true
	local expectedGeneration = entry.generation
	local requestedRole = if entry.role == "client" then "client" else entry.role
	local readyPayload =
		PluginSession.createReadyPayload(entry.peerId, requestedRole, entry.instanceId, entry.multiplayerGroupId)
	local ok, res = postJson("/ready", readyPayload)
	if proxyByPlayer[entry.player] ~= entry then
		if ok and res and res.Success then
			queueProxyDisconnect(entry.peerId)
		end
		return nil
	end
	if entry.generation ~= expectedGeneration then
		entry.registering = false
		if not entry.registered then
			task.spawn(registerProxyEntry, entry)
		end
		return nil
	end
	entry.registering = false
	if not ok or not res or not res.Success then
		failProxyRegistration(entry, formatPostJsonFailure("/ready", ok, res))
		return nil
	end
	local assignedRole = parseAssignedRole(res.Body, entry)
	if assignedRole == nil then
		failProxyRegistration(entry, "invalid /ready response for client Peer topology")
		return nil
	end
	entry.role = assignedRole
	entry.registered = true
	entry.retryAttempt = 0
	if proxyRegisterFailuresByPlayer[entry.player] ~= nil then
		proxyRegisterFailuresByPlayer[entry.player] = nil
		print(`[robloxstudio-mcp] proxy registered for {entry.player.Name} as {assignedRole} via {mcpUrl}`)
	end
end
local function parseClientIdentity(payload)
	if not (type(payload) == "table") then
		return nil
	end
	local identity = payload
	local condition = identity.kind ~= CLIENT_IDENTITY_KIND
	if not condition then
		condition = not (type(identity.peerId) == "string")
		if not condition then
			condition = identity.peerId == ""
		end
	end
	if condition then
		return nil
	end
	return {
		kind = "identity",
		peerId = identity.peerId,
	}
end
local function registerProxy(player, rf, identity)
	local peerOwner = proxyByPeerId[identity.peerId]
	if peerOwner ~= nil and peerOwner.player ~= player then
		return false
	end
	local current = proxyByPlayer[player]
	local multiplayerGroupId = PluginSession.getMultiplayerGroupId()
	-- Managed multiplayer launches one client Player per Studio process. The
	-- server creates that process identity instead of trusting replicated game
	-- code to claim an Instance or Multiplayer Group. Solo clients use the
	-- server's process Instance because their VMs share one Studio process.
	local retainedMultiplayerInstanceId = if current ~= nil
			and current.multiplayerGroupId == multiplayerGroupId
		then current.instanceId
		else nil
	local _result
	if multiplayerGroupId ~= nil then
		local condition = if retainedMultiplayerInstanceId ~= nil
			then retainedMultiplayerInstanceId
			else TopologyId.createInstanceId()
		_result = condition
	else
		_result = PluginSession.getInstanceId()
	end
	local instanceId = _result
	if current ~= nil then
		if current.peerId ~= identity.peerId then
			unregisterProxy(player, current)
		else
			if current.instanceId ~= instanceId or current.multiplayerGroupId ~= multiplayerGroupId then
				current.generation += 1
				current.instanceId = instanceId
				current.multiplayerGroupId = multiplayerGroupId
				current.role = "client"
				current.registered = false
				current.registering = false
				current.retryAttempt = 0
				task.spawn(registerProxyEntry, current)
			end
			return true
		end
	end
	local entry = {
		player = player,
		remote = rf,
		peerId = identity.peerId,
		instanceId = instanceId,
		multiplayerGroupId = multiplayerGroupId,
		role = "client",
		registered = false,
		registering = false,
		retryAttempt = 0,
		generation = 0,
	}
	proxyByPlayer[player] = entry
	proxyByPeerId[entry.peerId] = entry
	task.spawn(registerProxyEntry, entry)
	return true
end
local function refreshAllProxyRegistrations()
	for _, entry in proxyByPlayer do
		entry.generation += 1
		entry.registered = false
		entry.registering = false
		entry.retryAttempt = 0
		task.spawn(registerProxyEntry, entry)
	end
end
local function dispatchClientRequest(peerId, target, endpoint, data)
	local entry = proxyByPeerId[peerId]
	if not entry or proxyByPlayer[entry.player] ~= entry then
		return {
			error = `Client proxy {target} ({peerId}) is not registered.`,
		}
	end
	if entry.role == "client" then
		local assignedClientRole = string.match(target, "^client%-%d+$")
		if assignedClientRole ~= nil then
			entry.role = target
		end
	end
	if entry.role ~= target then
		return {
			error = `Client proxy {peerId} is registered as {entry.role}, not {target}.`,
		}
	end
	if entry.player.Parent == nil or not RunService:IsRunning() then
		unregisterProxy(entry.player, entry)
		return {
			error = `Client proxy {target} is no longer available.`,
		}
	end
	if not (CLIENT_BROKER_ALLOWED_ENDPOINTS[endpoint] ~= nil) then
		local allowed = {}
		for allowedEndpoint in CLIENT_BROKER_ALLOWED_ENDPOINTS do
			table.insert(allowed, allowedEndpoint)
		end
		return {
			error = `Client-proxy does not forward {endpoint}. Allowed: {table.concat(allowed, ", ")}.`,
		}
	end
	local envelope = {
		endpoint = endpoint,
		data = data,
	}
	local invokeOk, invokeResult = pcall(function()
		return entry.remote:InvokeClient(entry.player, envelope)
	end)
	if not invokeOk then
		return {
			success = false,
			error = `InvokeClient failed: {tostring(invokeResult)}`,
		}
	end
	return if invokeResult ~= nil
		then invokeResult
		else {
			success = false,
			error = "nil response",
		}
end
local function setupServerBroker()
	if serverBrokerStarted then
		return nil
	end
	local existing = ReplicatedStorage:FindFirstChild(BROKER_NAME)
	local rf
	if existing ~= nil then
		if not existing:IsA("RemoteFunction") then
			warn(`[robloxstudio-mcp] server: {BROKER_NAME} exists but is not a RemoteFunction`)
			return nil
		end
		rf = existing
	else
		rf = Instance.new("RemoteFunction")
	end
	if rf:GetAttribute(BROKER_OWNER_ATTRIBUTE) ~= nil then
		return nil
	end
	rf.Name = BROKER_NAME
	rf:SetAttribute(BROKER_OWNER_ATTRIBUTE, PluginSession.peerId)
	rf.OnServerInvoke = function(player, payload)
		local identity = parseClientIdentity(payload)
		if identity == nil then
			return {
				success = false,
				error = "Invalid client Peer identity handshake.",
			}
		end
		if not registerProxy(player, rf, identity) then
			return {
				success = false,
				error = "Client Peer identity is already registered by another player.",
			}
		end
		return {
			success = true,
		}
	end
	if rf.Parent == nil then
		rf.Parent = ReplicatedStorage
	end
	serverBrokerStarted = true
	Players.PlayerRemoving:Connect(function(player)
		unregisterProxy(player)
	end)
	game:BindToClose(function()
		disconnectAllProxies()
	end)
end
return {
	DEFAULT_MCP_URL = DEFAULT_MCP_URL,
	setServerUrl = setServerUrl,
	disconnectAllProxies = disconnectAllProxies,
	refreshAllProxyRegistrations = refreshAllProxyRegistrations,
	dispatchClientRequest = dispatchClientRequest,
	forkRole = forkRole,
	setupClientBroker = setupClientBroker,
	setupServerBroker = setupServerBroker,
}
