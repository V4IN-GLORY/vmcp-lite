local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local State = require(script.Parent.State)
local Utils = require(script.Parent.Utils)
local UI = require(script.Parent.UI)
local cleanupEditBridgeArtifacts = require(script.Parent.EvalBridges).cleanupEditBridgeArtifacts
local QueryHandlers = require(script.Parent.handlers.QueryHandlers)
local PropertyHandlers = require(script.Parent.handlers.PropertyHandlers)
local ScriptHandlers = require(script.Parent.handlers.ScriptHandlers)
local MetadataHandlers = require(script.Parent.handlers.MetadataHandlers)
local TestHandlers = require(script.Parent.handlers.TestHandlers)
local AssetHandlers = require(script.Parent.handlers.AssetHandlers)
local CaptureHandlers = require(script.Parent.handlers.CaptureHandlers)
local InputHandlers = require(script.Parent.handlers.InputHandlers)
local LogHandlers = require(script.Parent.handlers.LogHandlers)
local SerializationHandlers = require(script.Parent.handlers.SerializationHandlers)
local MemoryHandlers = require(script.Parent.handlers.MemoryHandlers)
local SceneAnalysisHandlers = require(script.Parent.handlers.SceneAnalysisHandlers)
local BreakpointHandlers = require(script.Parent.handlers.BreakpointHandlers)
local ScriptProfilerHandlers = require(script.Parent.handlers.ScriptProfilerHandlers)
local MicroProfilerHandlers = require(script.Parent.handlers.MicroProfilerHandlers)
local GenerateModelHandlers = require(script.Parent.handlers.GenerateModelHandlers)
local EvalRuntimeHandlers = require(script.Parent.handlers.EvalRuntimeHandlers)
local ClientBroker = require(script.Parent.ClientBroker)
local ServerUrlSettings = require(script.Parent.ServerUrlSettings)
local PluginSession = require(script.Parent.PluginSession)
local StudioWebSocket = require(script.Parent.StudioWebSocket)
local assignedRole
local lastReadyPlaceKey
local initialRole = PluginSession.getRole()
local routeMap = {
	["/api/file-tree"] = QueryHandlers.getFileTree,
	["/api/search-files"] = QueryHandlers.searchFiles,
	["/api/place-info"] = QueryHandlers.getPlaceInfo,
	["/api/search-objects"] = QueryHandlers.searchObjects,
	["/api/instance-properties"] = QueryHandlers.getInstanceProperties,
	["/api/search-by-property"] = QueryHandlers.searchByProperty,
	["/api/class-info"] = QueryHandlers.getClassInfo,
	["/api/project-structure"] = QueryHandlers.getProjectStructure,
	["/api/grep-scripts"] = QueryHandlers.grepScripts,
	["/api/set-properties"] = PropertyHandlers.setProperties,
	["/api/get-script-source"] = ScriptHandlers.getScriptSource,
	["/api/set-script-source"] = ScriptHandlers.setScriptSource,
	["/api/edit-script-lines"] = ScriptHandlers.editScriptLines,
	["/api/insert-script-lines"] = ScriptHandlers.insertScriptLines,
	["/api/delete-script-lines"] = ScriptHandlers.deleteScriptLines,
	["/api/get-attributes"] = MetadataHandlers.getAttributes,
	["/api/get-selection"] = MetadataHandlers.getSelection,
	["/api/set-selection"] = MetadataHandlers.setSelection,
	["/api/focus-viewport"] = MetadataHandlers.focusViewport,
	["/api/execute-luau"] = MetadataHandlers.executeLuau,
	["/api/eval-runtime"] = EvalRuntimeHandlers.evalRuntime,
	["/api/start-playtest"] = TestHandlers.startPlaytest,
	["/api/stop-playtest"] = TestHandlers.stopPlaytest,
	["/api/multiplayer-test-start"] = TestHandlers.multiplayerTestStart,
	["/api/multiplayer-test-state"] = TestHandlers.multiplayerTestState,
	["/api/multiplayer-test-add-players"] = TestHandlers.multiplayerTestAddPlayers,
	["/api/multiplayer-test-leave-client"] = TestHandlers.multiplayerTestLeaveClient,
	["/api/multiplayer-test-end"] = TestHandlers.multiplayerTestEnd,
	["/api/insert-asset"] = AssetHandlers.insertAsset,
	["/api/preview-asset"] = AssetHandlers.previewAsset,
	["/api/capture-screenshot"] = CaptureHandlers.captureScreenshot,
	["/api/capture-begin"] = CaptureHandlers.captureBegin,
	["/api/capture-read"] = CaptureHandlers.captureRead,
	["/api/simulate-mouse-input"] = InputHandlers.simulateMouseInput,
	["/api/simulate-keyboard-input"] = InputHandlers.simulateKeyboardInput,
	["/api/find-and-replace-in-scripts"] = ScriptHandlers.findAndReplaceInScripts,
	["/api/get-runtime-logs"] = LogHandlers.getRuntimeLogs,
	["/api/breakpoints"] = BreakpointHandlers.breakpoints,
	["/api/capture-script-profiler"] = ScriptProfilerHandlers.captureScriptProfiler,
	["/api/capture-micro-profiler"] = MicroProfilerHandlers.captureMicroProfiler,
	["/api/generate-model"] = GenerateModelHandlers.generateModel,
	["/api/export-rbxm"] = SerializationHandlers.exportRbxm,
	["/api/import-rbxm"] = SerializationHandlers.importRbxm,
	["/api/get-memory-breakdown"] = MemoryHandlers.getMemoryBreakdown,
	["/api/get-scene-analysis"] = SceneAnalysisHandlers.getSceneAnalysis,
}
local function processRequest(request, context)
	local endpoint = request.endpoint
	local data = request.data or {}
	local handler = routeMap[endpoint]
	if handler then
		return handler(data, context)
	else
		return {
			error = `Unknown endpoint: {endpoint}`,
		}
	end
end
local function dispatchSocketRequest(request, context)
	if request.peerId ~= PluginSession.peerId then
		return ClientBroker.dispatchClientRequest(request.peerId, request.target, request.endpoint, request.data)
	end
	local condition = if assignedRole ~= nil then assignedRole else PluginSession.getRole()
	local localRole = condition
	if request.target ~= localRole then
		return {
			error = `Transport peer is registered as {localRole}, not {request.target}.`,
		}
	end
	return processRequest({
		endpoint = request.endpoint,
		data = request.data,
	}, context)
end
local function handleReady(response)
	local conn = State.getActiveConnection()
	if not conn.isActive then
		return nil
	end
	assignedRole = response.assignedRole
	lastReadyPlaceKey = PluginSession.getPlaceKey()
	ServerUrlSettings.rememberServerUrl(conn.serverUrl)
	ClientBroker.refreshAllProxyRegistrations()
end
local function handleStatus(status)
	local conn = State.getActiveConnection()
	if not conn.isActive then
		return nil
	end
	conn.lastHttpOk = true
	conn.lastMcpOk = status.mcpConnected
	conn.consecutiveFailures = 0
	conn.currentRetryDelay = 0.5
	if status.mcpConnected then
		conn.mcpWaitStartTime = nil
	elseif conn.mcpWaitStartTime == nil then
		conn.mcpWaitStartTime = tick()
	end
	UI.updateUIState()
	UI.updateToolbarIcon()
end
local function handleHeartbeat(_timestamp)
	if not State.getActiveConnection().isActive then
		return nil
	end
	UI.updateUIState()
end
local function handleTransportUpdate(update)
	local conn = State.getActiveConnection()
	if not conn.isActive then
		return nil
	end
	if update.state == "open" then
		conn.lastHttpOk = true
		conn.lastMcpOk = false
		conn.consecutiveFailures = 0
		conn.currentRetryDelay = 0.5
		conn.mcpWaitStartTime = tick()
	else
		conn.lastHttpOk = false
		conn.lastMcpOk = false
		conn.consecutiveFailures = update.attempt
		if update.retryDelay > 0 then
			conn.currentRetryDelay = update.retryDelay
		end
		conn.mcpWaitStartTime = nil
	end
	UI.updateUIState()
	UI.updateToolbarIcon()
	if update.state == "waiting-duplicate" then
		local ui = UI.getElements()
		ui.statusLabel.Text = "Waiting for previous instance"
		ui.statusLabel.TextColor3 = Color3.fromRGB(245, 158, 11)
		ui.detailStatusLabel.Text = if update.detail ~= nil
			then update.detail
			else "The previous plugin instance is still active."
		ui.detailStatusLabel.TextColor3 = Color3.fromRGB(245, 158, 11)
	end
end
local nameChangeConn
local placeIdChangeConn
local function ensureIdentityWatchers()
	if not nameChangeConn then
		local signalOk, signal = pcall(function()
			return game:GetPropertyChangedSignal("Name")
		end)
		if signalOk and signal then
			nameChangeConn = signal:Connect(function()
				return StudioWebSocket.refresh()
			end)
		end
	end
	if not placeIdChangeConn then
		local signalOk, signal = pcall(function()
			return game:GetPropertyChangedSignal("PlaceId")
		end)
		if signalOk and signal then
			placeIdChangeConn = signal:Connect(function()
				PluginSession.invalidatePlaceName()
				lastReadyPlaceKey = PluginSession.getPlaceKey()
				StudioWebSocket.refresh()
			end)
		end
	end
end
local function disconnectIdentityWatchers()
	if nameChangeConn then
		nameChangeConn:Disconnect()
		nameChangeConn = nil
	end
	if placeIdChangeConn then
		placeIdChangeConn:Disconnect()
		placeIdChangeConn = nil
	end
end
local deactivatePlugin
local function activatePlugin()
	local conn = State.getActiveConnection()
	if conn.isActive then
		return nil
	end
	local ui = UI.getElements()
	conn.isActive = true
	conn.consecutiveFailures = 0
	conn.currentRetryDelay = 0.5
	conn.lastHttpOk = false
	conn.lastMcpOk = false
	conn.mcpWaitStartTime = nil
	local normalizedUrl = ServerUrlSettings.normalizeServerUrl(ui.urlInput.Text)
	conn.serverUrl = if normalizedUrl ~= "" then normalizedUrl else conn.serverUrl
	if conn.serverUrl == "" then
		conn.serverUrl = ClientBroker.DEFAULT_MCP_URL
	end
	ui.urlInput.Text = conn.serverUrl
	local port = ServerUrlSettings.extractPort(conn.serverUrl)
	if port ~= nil then
		conn.port = port
	end
	ClientBroker.setServerUrl(conn.serverUrl)
	lastReadyPlaceKey = PluginSession.getPlaceKey()
	UI.updateUIState()
	StudioWebSocket.start({
		serverUrl = conn.serverUrl,
		dispatchRequest = dispatchSocketRequest,
		onStatus = handleStatus,
		onHeartbeat = handleHeartbeat,
		onReady = handleReady,
		onTransportUpdate = handleTransportUpdate,
	})
	if not conn.heartbeatConnection then
		conn.heartbeatConnection = RunService.Heartbeat:Connect(function()
			if initialRole == "server" and not RunService:IsRunning() then
				ClientBroker.disconnectAllProxies()
				deactivatePlugin()
				return nil
			end
			local currentPlaceKey = PluginSession.getPlaceKey()
			if lastReadyPlaceKey ~= nil and currentPlaceKey ~= lastReadyPlaceKey then
				lastReadyPlaceKey = currentPlaceKey
				PluginSession.invalidatePlaceName()
				StudioWebSocket.refresh()
			end
		end)
	end
	if initialRole == "edit" then
		task.spawn(cleanupEditBridgeArtifacts)
	end
	ensureIdentityWatchers()
end
function deactivatePlugin()
	local conn = State.getActiveConnection()
	if not conn.isActive then
		return nil
	end
	conn.isActive = false
	conn.lastHttpOk = false
	conn.lastMcpOk = false
	conn.mcpWaitStartTime = nil
	StudioWebSocket.stop()
	disconnectIdentityWatchers()
	if initialRole == "server" then
		ClientBroker.disconnectAllProxies()
	end
	if conn.heartbeatConnection then
		conn.heartbeatConnection:Disconnect()
		conn.heartbeatConnection = nil
	end
	lastReadyPlaceKey = nil
	assignedRole = nil
	conn.consecutiveFailures = 0
	conn.currentRetryDelay = 0.5
	UI.updateUIState()
end
local function deactivateAll()
	local conn = State.getActiveConnection()
	if conn.isActive then
		deactivatePlugin()
	end
end
local function checkForUpdates()
	task.spawn(function()
		local success, result = pcall(function()
			return HttpService:RequestAsync({
				Url = "https://registry.npmjs.org/@chrrxs/robloxstudio-mcp/latest",
				Method = "GET",
				Headers = {
					Accept = "application/json",
				},
			})
		end)
		if success and result.Success then
			local ok, data = pcall(function()
				return HttpService:JSONDecode(result.Body)
			end)
			local condition = ok
			if condition then
				local result = data
				if result ~= nil then
					result = result.version
				end
				condition = result
			end
			if condition ~= "" and condition then
				local latestVersion = data.version
				if Utils.compareVersions(State.CURRENT_VERSION, latestVersion) < 0 then
					UI.showBanner("update", `v{latestVersion} available - github.com/chrrxs/robloxstudio-mcp`)
				end
			end
		end
	end)
end
return {
	activatePlugin = activatePlugin,
	deactivatePlugin = deactivatePlugin,
	deactivateAll = deactivateAll,
	checkForUpdates = checkForUpdates,
}
