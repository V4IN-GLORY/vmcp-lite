--!strict

local HttpService = game:GetService("HttpService")

local Bridge = require(script.Bridge)
local Panel = require(script.Panel)

local DEFAULT_PORT = "8791"

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

-- An unsaved place reports PlaceId 0, which the server refuses. This GUID stands in for it and
-- is stored per-machine so the place keeps its identity across sessions.
local function getPlaceGuid(): string
	local guid = plugin:GetSetting("placeGuid")
	if not guid then
		guid = HttpService:GenerateGUID(false)
		plugin:SetSetting("placeGuid", guid)
	end
	return guid
end

Bridge.Init(script.Tools, { GetPlaceGuid = getPlaceGuid })

Bridge.OnStatus(function(signal: string, word: string, line: string)
	Panel.SetSignal(signal)
	Panel.SetStatusWord(word)
	Panel.SetStatusLine(line)

	local live = signal == "Live" or signal == "Work"
	Panel.SetConnectEnabled(not live)
	Panel.SetDisconnectEnabled(live)
end)

local function connect()
	if not token or token == "" then
		Panel.SetSignal("Fault")
		Panel.SetStatusWord("no token")
		Panel.SetStatusLine("Paste the auth token from `npm run token` first.")
		Panel.SetTokenOpen(true)
		return
	end
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

button.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

plugin.Unloading:Connect(Bridge.Disconnect)

if token and token ~= "" then
	connect()
end
