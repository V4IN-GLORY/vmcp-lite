local State = require(script.modules.State)
local UI = require(script.modules.UI)
local Communication = require(script.modules.Communication)
local ClientBroker = require(script.modules.ClientBroker)
local ServerUrlSettings = require(script.modules.ServerUrlSettings)
local EvalBridges = require(script.modules.EvalBridges)
local cleanupEditBridgeArtifacts = EvalBridges.cleanupEditBridgeArtifacts
local ensureRuntimeBridgeInstalled = EvalBridges.ensureRuntimeBridgeInstalled
local RuntimeLogBuffer = require(script.modules.RuntimeLogBuffer)
local StopPlayMonitor = require(script.modules.StopPlayMonitor)
local StudioWebSocket = require(script.modules.StudioWebSocket)
local BreakpointHandlers = require(script.modules.handlers.BreakpointHandlers)
local RenderMonitor = require(script.modules.RenderMonitor)
-- Track render-loop liveness so input/screenshot tools can report "window
-- minimized / not rendering" instead of silently no-op'ing. No-op in the
-- server DM (RenderStepped can't connect there).
RenderMonitor.start()
-- Attach the per-peer LogService.MessageOut listener as early as possible so
-- boot-time prints from the user's place scripts are captured. Powers the
-- get_runtime_logs MCP tool. Idempotent; safe to call before UI.init().
RuntimeLogBuffer.install()
-- Share the plugin reference with the stop-play signaling module so both the
-- edit DM (write the flag) and the play-server DM (read+act on the flag) can
-- access plugin:SetSetting/GetSetting.
StopPlayMonitor.init(plugin)
BreakpointHandlers.init(plugin)
ServerUrlSettings.init(plugin)
local startupRole = ClientBroker.forkRole()
local function applyRememberedServerUrl()
	if startupRole == "client" then
		return nil
	end
	local rememberedServerUrl = ServerUrlSettings.readServerUrl()
	if rememberedServerUrl == nil then
		return nil
	end
	local conn = State.getActiveConnection()
	conn.serverUrl = rememberedServerUrl
	local port = ServerUrlSettings.extractPort(rememberedServerUrl)
	if port ~= nil then
		conn.port = port
	end
	ClientBroker.setServerUrl(rememberedServerUrl)
end
applyRememberedServerUrl()
-- Play DataModels do not reliably fire Plugin.Unloading before Studio tears
-- down their VM. Close the persistent WebStreamClient while BindToClose still
-- gives this server peer a live execution context; otherwise each play cycle
-- can retain one native WebSocket until Studio itself is restarted. The
-- transport releases that native socket before yielding to unregister the
-- logical server peer.
if startupRole == "server" then
	game:BindToClose(StudioWebSocket.suspendForShutdown)
end
UI.init(plugin)
local elements = UI.getElements()
local ICON_DISCONNECTED = "rbxassetid://75876056391496"
local ICON_CONNECTING = "rbxassetid://71302583919560"
local ICON_CONNECTED = "rbxassetid://130958234173611"
local TOOLBAR_REGISTRATION_DELAY_SECONDS = 1
local toolbarButtonRegistered = false
local function registerToolbarButton()
	if toolbarButtonRegistered then
		return nil
	end
	toolbarButtonRegistered = true
	local toolbar = plugin:CreateToolbar("MCP Integration")
	local button = toolbar:CreateButton("MCP Server", "Connect to MCP Server for AI Integration", ICON_DISCONNECTED)
	UI.setToolbarButton(button, {
		disconnected = ICON_DISCONNECTED,
		connecting = ICON_CONNECTING,
		connected = ICON_CONNECTED,
	})
	button.Click:Connect(function()
		elements.screenGui.Enabled = not elements.screenGui.Enabled
	end)
end
elements.connectButton.Activated:Connect(function()
	local conn = State.getActiveConnection()
	if conn and conn.isActive then
		Communication.deactivatePlugin()
	else
		Communication.activatePlugin()
	end
end)
plugin.Unloading:Connect(function()
	Communication.deactivateAll()
end)
UI.updateUIState()
Communication.checkForUpdates()
task.delay(TOOLBAR_REGISTRATION_DELAY_SECONDS, registerToolbarButton)
-- Auto-activate per Peer. Runtime plugin VMs can load before their first
-- Heartbeat; task.delay() would then wait behind the very multiplayer startup
-- that needs this Peer to register. Start runtime initialization immediately,
-- while retaining the short UI settling delay for the edit Peer.
local function autoActivatePeer()
	local role = startupRole
	if role == "edit" then
		cleanupEditBridgeArtifacts()
	else
		local result = ensureRuntimeBridgeInstalled()
		if not result.installed then
			warn(`[robloxstudio-mcp] Runtime eval bridge install failed: {result.error}`)
		end
	end
	if role == "edit" or role == "server" then
		local activationOk, activationError = pcall(function()
			local conn = State.getActiveConnection()
			if not conn.isActive then
				if role == "server" then
					local condition = ServerUrlSettings.readServerUrl()
					if condition == nil then
						condition = ClientBroker.DEFAULT_MCP_URL
					end
					local inheritedServerUrl = condition
					conn.serverUrl = ServerUrlSettings.normalizeServerUrl(inheritedServerUrl)
					elements.urlInput.Text = conn.serverUrl
					local port = ServerUrlSettings.extractPort(conn.serverUrl)
					if port ~= nil then
						conn.port = port
					end
					ClientBroker.setServerUrl(conn.serverUrl)
				end
				-- Defensive default: in invisible play-DM UIs, the input field
				-- may not be populated by the time we activate.
				if conn.serverUrl == nil or conn.serverUrl == "" then
					conn.serverUrl = ClientBroker.DEFAULT_MCP_URL
					elements.urlInput.Text = conn.serverUrl
				end
				Communication.activatePlugin()
			end
		end)
		if not activationOk then
			warn(`[robloxstudio-mcp] Automatic {role} Peer activation failed: {activationError}`)
		end
	end
	if role == "server" then
		ClientBroker.setupServerBroker()
		-- The play-server DM is the only one where StudioTestService:EndTest is
		-- legal, so the stop-play monitor lives here. It consumes tokenized
		-- stop requests from plugin settings and acknowledges EndTest results.
		StopPlayMonitor.startMonitor({
			beforeEndTest = StudioWebSocket.suspendForShutdown,
			afterEndTestFailure = StudioWebSocket.resumeAfterShutdownFailure,
		})
	elseif role == "client" then
		ClientBroker.setupClientBroker()
	end
end
if startupRole == "edit" then
	task.delay(2, autoActivatePeer)
else
	autoActivatePeer()
end
