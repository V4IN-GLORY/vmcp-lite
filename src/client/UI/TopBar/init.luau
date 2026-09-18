--!strict

-- The bar both screens share: level + street cred with progress bars, the tab strip with
-- L1/R1 chips, carry weight and money on the right, the red rule under it, and Close.
-- Level and cred progress are Vide sources so the bars animate when they change.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Vide = require(ReplicatedStorage.Packages.Vide)
local Assets = require(script.Parent.Assets)
local Make = require(script.Parent.Make)

type Source<T> = () -> T

local CENTER = Enum.TextXAlignment.Center
local TAB_SPACING = 150

export type Props = {
	tabs: { string },
	active: number,
	level: number,
	cred: number,
	-- 0-1 progress toward the next level / cred rank
	levelProgress: Source<number>,
	credProgress: Source<number>,
	weight: string,
	money: string,
}

local function chip(parent: Instance, text: string, x: number, y: number)
	local frame = Make.Box(parent, x, y, 30, 16)
	frame.BackgroundColor3 = Color3.fromRGB(30, 110, 130)
	Make.Label(frame, text, 0, 0, 30, 16, 11, { "Cyan", "Mono" }, CENTER)
end

-- number, caption and a progress bar whose fill springs to the source
local function stat(
	parent: Instance,
	x: number,
	value: number,
	caption: string,
	width: number,
	color: string,
	track: Color3,
	progress: Source<number>
)
	Make.Label(parent, tostring(value), x, 20, 40, 40, 34, { color, "Mono" })
	Make.Label(parent, caption, x + 40, 26, width + 40, 30, 22, { color })
	Make.Box(parent, x + 40, 60, width, 3).BackgroundColor3 = track
	local fill = Make.Box(parent, x + 40, 60, 0, 3, { color })
	local shown = Vide.spring(progress, 0.5)
	Vide.effect(function()
		fill.Size = UDim2.fromOffset(math.round(width * math.clamp(shown(), 0, 1)), 3)
	end)
end

local function TopBar(props: Props): Frame
	local bar = Make.Box(nil, 0, 0, 1920, 90, nil, 1)
	bar.Name = "TopBar"

	stat(bar, 78, props.level, "LEVEL", 90, "Cyan", Color3.fromRGB(40, 80, 90), props.levelProgress)
	stat(bar, 232, props.cred, "STREET CRED", 130, "Green", Color3.fromRGB(30, 80, 45), props.credProgress)

	local n = #props.tabs
	local x0 = 960 - (n - 1) * TAB_SPACING / 2
	chip(bar, "L1", x0 - 130, 34)
	chip(bar, "R1", x0 + (n - 1) * TAB_SPACING + 100, 34)
	for i, name in props.tabs do
		local cx = x0 + (i - 1) * TAB_SPACING
		local isActive = i == props.active
		Make.Image(bar, Assets.tab, cx - 72, 32, 22, 22, if isActive then { "Cyan" } else nil)
		Make.Label(bar, name, cx - 44, 28, 130, 30, 20, if isActive then { "Tab", "Active" } else { "Tab" })
	end

	Make.Image(bar, Assets.weight, 1568, 34, 22, 22)
	Make.Label(bar, props.weight, 1600, 26, 120, 34, 26, { "Mono" })
	Make.Label(bar, "€$", 1730, 30, 40, 30, 22, { "Yellow" })
	Make.Label(bar, props.money, 1770, 26, 100, 34, 28, { "Yellow", "Mono" })
	Make.Box(bar, 50, 70, 1820, 2, { "Accent" })
	Make.Box(bar, 50, 72, 1820, 6, { "Accent" }, 0.7)

	Make.Label(bar, "Close", 1822, 1028, 80, 30, 22, { "Cyan" })
	Make.Image(bar, Assets.close, 1786, 1032, 24, 24, { "Cyan" })
	return bar
end

return TopBar
