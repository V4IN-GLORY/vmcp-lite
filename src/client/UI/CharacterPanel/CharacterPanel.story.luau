local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Vide = require(ReplicatedStorage.Packages.Vide)
local UILabs = require(ReplicatedStorage.Packages.UILabs)
local CharacterPanel = require(script.Parent)

return {
	vide = Vide,
	controls = {
		level = UILabs.Number(12, 1, 50, 1),
		attributePoints = UILabs.Number(0, 0, 20, 1),
		reflex = UILabs.Number(7, 1, 20, 1),
		body = UILabs.Number(4, 1, 20, 1),
		tech = UILabs.Number(8, 1, 20, 1),
		int = UILabs.Number(8, 1, 20, 1),
		cool = UILabs.Number(6, 1, 20, 1),
	},
	story = function(props)
		local c = props.controls
		local page = CharacterPanel({
			level = c.level(),
			levelProgress = Vide.source(0.33),
			credProgress = Vide.source(0.77),
			attributePoints = c.attributePoints(),
			perkPoints = 6,
			attributes = { reflex = c.reflex, body = c.body, tech = c.tech, int = c.int, cool = c.cool },
		})
		page.Parent = props.target
	end,
}
