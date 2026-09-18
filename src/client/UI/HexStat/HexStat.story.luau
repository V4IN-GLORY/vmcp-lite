local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Vide = require(ReplicatedStorage.Packages.Vide)
local UILabs = require(ReplicatedStorage.Packages.UILabs)
local HexStat = require(script.Parent)

return {
	vide = Vide,
	controls = {
		name = UILabs.String("REFLEXES"),
		icon = UILabs.Choose({ "reflex", "body", "tech", "int", "cool" }),
		value = UILabs.Number(7, 0, 20, 1),
	},
	story = function(props)
		local controls = props.controls
		local hex = HexStat({
			name = controls.name(),
			icon = controls.icon(),
			value = controls.value,
			x = 200,
			y = 120,
		})
		hex.Parent = props.target
	end,
}
