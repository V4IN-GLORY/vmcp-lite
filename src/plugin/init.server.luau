--!strict

-- This runs in every DataModel Studio has open. The edit one gets the panel and the toolbar; a
-- playtest's server and clients get the same tools with no UI at all, because the plugin is
-- loaded into those too and that is what makes a live context reachable.

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Bridge = require(script.Bridge)
local LogBuffer = require(script.Log.Buffer)

local DEFAULT_PORT = "8791"

-- Started before anything else can log: get_logs is only useful if it was already recording when
-- the interesting error happened.
LogBuffer.Start()

-- An unsaved place reports PlaceId 0, which the server refuses. This GUID stands in for it and is
-- stored per-machine so the place keeps its identity across sessions.
local function getPlaceGuid(): string
	local guid = plugin:GetSetting("placeGuid")
	if not guid then
		guid = HttpService:GenerateGUID(false)
		plugin:SetSetting("placeGuid", guid)
	end
	return guid
end

Bridge.Init(script.Tools, { GetPlaceGuid = getPlaceGuid })

if not RunService:IsEdit() then
	-- A playtest DataModel. It needs the edit session's id to attach to, which the edit session
	-- writes to plugin settings as it connects -- nothing inside a running DataModel can work out
	-- which Studio window spawned it.
	local linkId = plugin:GetSetting("linkId")
	local token = plugin:GetSetting("token")
	if linkId and token and token ~= "" then
		Bridge.Connect(plugin:GetSetting("port") or DEFAULT_PORT, token, {
			role = if RunService:IsServer() then "server" else "client",
			linkId = linkId,
			-- Play Solo is one DataModel wearing both hats, so it answers as client 1 as well.
			alsoClient = RunService:IsServer() and RunService:IsClient(),
		})
	end
	return
end

local Panel = require(script.Panel)

local toolbar = plugin:CreateToolbar("VMCP")
local button = toolbar:CreateButton("Panel", "Open the VMCP bridge panel", "rbxassetid://5325741572")

local widget = plugin:CreateDockWidgetPluginGuiAsync(
	"MCP_Panel",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 400, 400, 200, 200)
)
widget.Title = "VMCP"

local port = plugin:GetSetting("port") or DEFAULT_PORT
local token = plugin:GetSetting("token")

-- Mounted once, up front. The panel's setters all reach into widgets Mount creates, so touching
-- any of them beforehand is a nil index -- and remounting per click would stack whole trees.
Panel.Mount(widget)
Panel.PortInput.Text = port
Panel.TokenInput.Text = token or ""

local function connect()
	if not token or token == "" then
		Panel.SetSignal("Fault")
		Panel.SetStatusWord("no token")
		Panel.SetStatusLine("Paste the auth token from `npm run token` first.")
		Panel.SetTokenOpen(true)
		return
	end
	-- Left where a playtest DataModel can find it. Two Studio windows share plugin settings, so
	-- the last one to connect owns the playtests; one test per Studio instance anyway.
	plugin:SetSetting("linkId", Bridge.Connection().sessionId)
	Bridge.Connect(port, token)
end

Panel.PortChanged:Connect(function(new: string)
	port = if new ~= "" then new else DEFAULT_PORT
	plugin:SetSetting("port", port)
end)

Panel.TokenChanged:Connect(function(new: string)
	token = new
	plugin:SetSetting("token", new)
end)

Panel.ConnectRequested:Connect(connect)
Panel.DisconnectRequested:Connect(Bridge.Disconnect)

-- The server only reports what could be updated; nothing is pulled or written until a button in
-- this panel is clicked. The state arrives on connect and whenever Check is pressed.
local updates: Bridge.UpdatesState? = nil

local function short(commit: string?): string
	return if commit then string.sub(commit, 1, 8) else "?"
end

local function showUpdates()
	local u = updates
	if not u then
		Panel.SetUpdates({ server = "Server: connect to check", serverAction = false, plugin = "Plugin: connect to check", pluginAction = false })
		return
	end
	local server = if not u.git
		then `Server: can't self-update -- {u.gitProblem or "git unavailable"}`
		elseif u.server then `Server: {u.server.commits} commit{if u.server.commits == 1 then "" else "s"} behind ({short(u.server.to)})`
		else `Server: up to date ({short(u.head)})`
	local plugin = if u.plugin
		then `Plugin: {if u.plugin.fresh then "not installed" else "different build bundled"} ({string.sub(u.plugin.sha256, 1, 8)})`
		else "Plugin: up to date"
	local restart = if u.running and u.head and u.running ~= u.head
		then `Server on disk is {short(u.head)} but this session runs {short(u.running)} -- restart the Claude/MCP session.`
		else nil
	Panel.SetUpdates({ server = server, serverAction = u.server ~= nil, plugin = plugin, pluginAction = u.plugin ~= nil, restart = restart })
	if u.server then
		print(`[VMCP] server update available: {u.server.commits} commit(s) behind. Open the VMCP panel to apply it.`)
	end
	if u.plugin then
		print(`[VMCP] plugin update available ({string.sub(u.plugin.sha256, 1, 8)}). Open the VMCP panel to apply it.`)
	end
end

Bridge.OnStatus(function(signal: string, word: string, line: string)
	Panel.SetSignal(signal)
	Panel.SetStatusWord(word)
	Panel.SetStatusLine(line)

	local live = signal == "Live" or signal == "Work"
	Panel.SetConnectEnabled(not live)
	Panel.SetDisconnectEnabled(live)
	if signal ~= "Live" then
		updates = nil
		showUpdates()
	end
end)

Bridge.OnUpdates(function(state)
	updates = state
	showUpdates()
end)

Panel.CheckUpdatesRequested:Connect(function()
	Panel.SetUpdates({ server = "Server: checking...", serverAction = false, plugin = "Plugin: checking...", pluginAction = false, checking = true })
	local ok, state = Bridge.CheckUpdates()
	if ok then
		updates = state
	else
		Panel.SetStatusLine(`Couldn't check: {state}`)
	end
	showUpdates()
end)

Panel.ServerUpdateRequested:Connect(function()
	local u = updates
	if not u or not u.server then
		return
	end
	Panel.SetUpdates({ server = "Server: pulling and rebuilding...", serverAction = false, plugin = "Plugin: wait", pluginAction = false, checking = true })
	local ok, detail = Bridge.ApplyUpdate("server", u.server.to)
	Panel.SetStatusLine(if ok then `Server {detail}.` else `Server update failed: {detail}`)
	local checked, state = Bridge.CheckUpdates()
	updates = if checked then state else updates
	showUpdates()
end)

Panel.PluginUpdateRequested:Connect(function()
	local u = updates
	if not u or not u.plugin then
		return
	end
	local ok, detail = Bridge.ApplyUpdate("plugin", u.plugin.sha256)
	Panel.SetStatusLine(if ok then `Plugin installed to {detail}. Studio reloads a changed local plugin on its own.` else `Plugin update failed: {detail}`)
	local checked, state = Bridge.CheckUpdates()
	updates = if checked then state else updates
	showUpdates()
end)

button.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

plugin.Unloading:Connect(Bridge.Disconnect)

if token and token ~= "" then
	connect()
end
