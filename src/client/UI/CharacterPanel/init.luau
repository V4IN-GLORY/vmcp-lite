--!strict

-- The character attributes screen: top bar, point counters, five attribute hexes around a level
-- diamond, and the circuit traces between them. Attribute values are Vide sources so the hexes
-- count up when a point is spent.

local Assets = require(script.Parent.Assets)
local HexStat = require(script.Parent.HexStat)
local Make = require(script.Parent.Make)

type Source<T> = () -> T
local TopBar = require(script.Parent.TopBar)

local CENTER = Enum.TextXAlignment.Center
local NAVY = Color3.fromRGB(28, 26, 60)

export type Attributes = {
	reflex: Source<number>,
	body: Source<number>,
	tech: Source<number>,
	int: Source<number>,
	cool: Source<number>,
}

export type Props = {
	level: number,
	levelProgress: Source<number>,
	credProgress: Source<number>,
	attributePoints: number,
	perkPoints: number,
	attributes: Attributes,
}

-- name, icon/attribute key, centre x, centre y
local HEXES: { { any } } = {
	{ "REFLEXES", "reflex", 960, 258 },
	{ "BODY", "body", 762, 368 },
	{ "TECHNICAL ABILITY", "tech", 1156, 368 },
	{ "INTELLIGENCE", "int", 760, 738 },
	{ "COOL", "cool", 1156, 738 },
}

local function pointsRow(page: Instance, y: number, count: number, color: string, line1: string, line2: string)
	Make.Label(page, tostring(count), 108, y, 30, 40, 32, { "Mono", color })
	Make.Box(page, 140, y + 4, 36, 32, { if color == "Cyan" then "Outline" else "OutlineYellow" }, 1)
	Make.Label(page, line1, 186, y, 200, 22, 18, { color })
	Make.Label(page, line2, 186, y + 22, 200, 22, 18, { color })
end

local function diamond(
	page: Instance,
	cx: number,
	cy: number,
	size: number,
	color: Color3,
	transparency: number,
	tags: { string }?
)
	local d = Make.Box(page, cx - size / 2, cy - size / 2, size, size, tags, transparency)
	d.BackgroundColor3 = color
	d.Rotation = 45
end

local function trace(page: Instance, x: number, y: number, w: number, h: number)
	Make.Box(page, x, y, w, h, { "Trace" })
end

local function CharacterPanel(props: Props): Frame
	local page = Make.Box(nil, 0, 0, 1920, 1080, nil, 1)
	page.Name = "Character"

	local bar = TopBar({
		tabs = { "INVENTORY", "MAP", "CHARACTER", "JOURNAL", "CRAFTING" },
		active = 3,
		level = props.level,
		cred = 19,
		levelProgress = props.levelProgress,
		credProgress = props.credProgress,
		weight = "112/240",
		money = "32214",
	})
	bar.Parent = page

	pointsRow(page, 206, props.attributePoints, "Cyan", "ATTRIBUTE POINTS", "AVAILABLE")
	pointsRow(page, 272, props.perkPoints, "Yellow", "PERK POINTS", "AVAILABLE")

	for _, hex in HEXES do
		local name: string, key: string, x: number, y: number = hex[1], hex[2], hex[3], hex[4]
		HexStat({ name = name, icon = key, value = (props.attributes :: any)[key], x = x, y = y }).Parent = page
	end
	Make.Image(page, Assets.hex, 958 - 120, 842 - 75, 240, 150) -- the empty sixth hex

	diamond(page, 865, 570, 90, NAVY, 0.15)
	diamond(page, 1050, 560, 90, NAVY, 0.15)
	diamond(page, 958, 560, 140, Color3.fromRGB(20, 20, 45), 0, { "OutlineNavy" })
	Make.Label(page, tostring(props.level), 930, 480, 60, 40, 26, { "Cyan", "Mono" }, CENTER)
	Make.Label(page, "LEVEL", 900, 618, 120, 30, 20, { "Cyan" }, CENTER)
	local cursor = Make.Box(page, 1170, 492, 34, 30, { "Outline" }, 1)
	Make.Box(cursor, 8, 12, 18, 3, { "Cyan" })

	trace(page, 940, 335, 2, 150)
	trace(page, 978, 335, 2, 150)
	trace(page, 958, 700, 2, 70)
	trace(page, 940, 640, 2, 60)
	trace(page, 978, 640, 2, 60)
	trace(page, 760, 440, 2, 60)
	trace(page, 760, 500, 100, 2)
	trace(page, 1156, 440, 2, 60)
	trace(page, 1058, 500, 100, 2)
	trace(page, 760, 600, 100, 2)
	trace(page, 760, 600, 2, 65)
	trace(page, 1058, 600, 100, 2)
	trace(page, 1156, 600, 2, 65)
	for i = 0, 5 do
		trace(page, 716 + i * 12, 458, 2, 24)
		trace(page, 1160 + i * 12, 458, 2, 24)
		trace(page, 716 + i * 12, 630, 2, 24)
		trace(page, 1160 + i * 12, 630, 2, 24)
	end
	return page
end

return CharacterPanel
