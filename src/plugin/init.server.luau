--!strict

-- Plugin entry point. Being a Script rather than a Folder is what makes the built model
-- installable -- both "Save as Local Plugin" and the Plugins folder need a Script at the root.
--
-- Empty on purpose: the toolbar, the dock widget, the settings and the socket are yours.
-- When you have somewhere to put it, the panel goes in with:
--
--   local Panel = require(script.Panel)
--   Panel.Mount(widget)
--
-- Panel/init.luau documents the rest of its surface.

local Panel = require(script.Panel)

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
