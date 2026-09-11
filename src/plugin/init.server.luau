--!strict

local Panel = require(script.Panel)
local toolbar = plugin:CreateToolbar("VMCP")
local button = toolbar:CreateButton("Panel", "", "rbxassetid://5325741572", "nil")

local HttpService = game:GetService("HttpService")

local widgetinfo = DockWidgetPluginGuiInfo.new(
    Enum.InitialDockState.Float,
    false,
    false,
    400,
    400,
    200,
    200
)

local widget = plugin:CreateDockWidgetPluginGuiAsync("MCP_Panel", widgetinfo)

local port = plugin:GetSetting("port") or nil
local token = plugin:GetSetting("token") or nil

Panel.PortChanged:Connect(function(new)
    port = new
    plugin:SetSetting("port", new)
    print("changed port")
end)

Panel.TokenChanged:Connect(function(new)
    token = new
    plugin:SetSetting("token", new)
    print("changed token")
end)

Panel.ConnectRequested:Connect(function()
    
end)


button.Click:Connect(function()
    widget.Enabled = not widget.Enabled
    Panel.Mount(widget)
end)

if port then -- implement auto connect logic here
    Panel.PortInput.Text = port
end

if token then
    Panel.TokenInput.Text = token
end

if port and token then -- implement auto connect logic on plugin load
    P
end