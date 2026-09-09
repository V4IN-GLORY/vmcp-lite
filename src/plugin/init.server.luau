--!strict

-- Studio plumbing only: toolbar, dock widget, saved settings. The panel is in Panel/, the
-- connection is in Transport.luau, and this file just wires the two together.

local Panel = require(script.Panel)
local Style = require(script.Panel.Style)
local Transport = require(script.Transport)

local PORT_SETTING = "VmcpPort"
local TOKEN_SETTING = "VmcpToken"

local toolbar = plugin:CreateToolbar("VMCP")
local button = toolbar:CreateButton("VMCP", "Open the VMCP bridge panel", "")
button.ClickableWhenViewportHidden = true

local widget = plugin:CreateDockWidgetPluginGuiAsync(
	"VmcpPanel",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 320, 248, 220, 212)
)
widget.Title = "VMCP"
widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

Panel.Mount(widget, tonumber(plugin:GetSetting(PORT_SETTING)), plugin:GetSetting(TOKEN_SETTING) ~= nil)

local studio = settings():GetService("Studio")
local function syncTheme()
	Style.SetTheme(studio.Theme.Name ~= "Light")
end
syncTheme()
studio.ThemeChanged:Connect(syncTheme)

button.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	button:SetActive(widget.Enabled)
end)

-- panel -> transport, transport -> panel
Panel.OnConnect = function(port: number)
	plugin:SetSetting(PORT_SETTING, port)
	Transport.Connect(port, plugin:GetSetting(TOKEN_SETTING))
end
Panel.OnDisconnect = Transport.Disconnect
Panel.OnToken = function(token: string)
	plugin:SetSetting(TOKEN_SETTING, token)
end
Transport.Report = Panel.SetState :: any

plugin.Unloading:Connect(Panel.Destroy)
