local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UILabs = require(ReplicatedStorage.Packages.UILabs)
local CyberwareSlot = require(script.Parent)

local GOLD = Color3.fromRGB(230, 180, 60)
local PURPLE = Color3.fromRGB(170, 60, 230)

return {
	controls = {
		filled = UILabs.Boolean(true),
		item = UILabs.Datatype.Color3(GOLD),
		quality = UILabs.Datatype.Color3(PURPLE),
	},
	render = function(props)
		local controls = props.controls
		local slot = CyberwareSlot({
			x = 40,
			y = 40,
			item = if controls.filled then controls.item else nil,
			quality = if controls.filled then controls.quality else nil,
		})
		slot.Parent = props.target
		return function()
			slot:Destroy()
		end
	end,
}
