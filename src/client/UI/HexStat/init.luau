--!strict

-- One attribute hex: plate, name, icon, value. The value is a Vide source so a level-up
-- animates the number; everything else is static instances.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Vide = require(ReplicatedStorage.Packages.Vide)
local Assets = require(script.Parent.Assets)
local Make = require(script.Parent.Make)

type Source<T> = () -> T

local W, H = 240, 150
local CENTER = Enum.TextXAlignment.Center

export type Props = {
	name: string,
	icon: string,
	value: Source<number>,
	-- stage coordinates of the hex centre
	x: number,
	y: number,
}

local function HexStat(props: Props): ImageLabel
	local hex = Make.Image(nil, Assets.hex, props.x - W / 2, props.y - H / 2, W, H)
	hex.Name = props.name
	Make.Label(hex, props.name, 0, 22, W, 30, 20, { "Cyan" }, CENTER)
	Make.Image(hex, Assets[props.icon], W / 2 - 44, 66, 40, 40, { "Cyan" })
	local value = Make.Label(hex, "", W / 2 + 6, 62, 40, 40, 30, { "Cyan", "Mono" })
	Make.Label(hex, "VALUE", W / 2 + 2, 100, 50, 16, 12, { "Cyan" })

	-- Spring the displayed number so a change counts up instead of snapping.
	local shown = Vide.spring(props.value, 0.4)
	Vide.effect(function()
		value.Text = tostring(math.round(shown()))
	end)
	return hex
end

return HexStat
