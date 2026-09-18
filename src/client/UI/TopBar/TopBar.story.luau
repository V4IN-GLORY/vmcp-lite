local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Vide = require(ReplicatedStorage.Packages.Vide)
local UILabs = require(ReplicatedStorage.Packages.UILabs)
local TopBar = require(script.Parent)

return {
	vide = Vide,
	controls = {
		active = UILabs.Number(3, 1, 5, 1),
		level = UILabs.Number(12, 1, 50, 1),
		levelProgress = UILabs.Number(0.33, 0, 1, 0.01),
		credProgress = UILabs.Number(0.77, 0, 1, 0.01),
		money = UILabs.String("32214"),
	},
	story = function(props)
		local controls = props.controls
		local bar = TopBar({
			tabs = { "INVENTORY", "MAP", "CHARACTER", "JOURNAL", "CRAFTING" },
			active = controls.active(),
			level = controls.level(),
			cred = 19,
			levelProgress = controls.levelProgress,
			credProgress = controls.credProgress,
			weight = "112/240",
			money = controls.money(),
		})
		bar.Parent = props.target
	end,
}
