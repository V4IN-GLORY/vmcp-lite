-- Cyberpunk 2077 Character / Cyberware screens. Run with run_luau (plugin context); rebuilds StarterGui.CyberpunkUI.
local StarterGui = game:GetService("StarterGui")
local CS = game:GetService("CollectionService")

local old = StarterGui:FindFirstChild("CyberpunkUI")
if old then old:Destroy() end

local RED, CYAN, YELLOW, GREEN = Color3.fromRGB(255, 60, 60), Color3.fromRGB(70, 230, 255), Color3.fromRGB(255, 200, 40), Color3.fromRGB(80, 240, 120)
local DIMRED, NAVY, ORANGE = Color3.fromRGB(110, 25, 30), Color3.fromRGB(28, 26, 60), Color3.fromRGB(255, 120, 40)
local JURA = Font.new("rbxasset://fonts/families/Jura.json", Enum.FontWeight.SemiBold)
local MONO = Font.new("rbxasset://fonts/families/BuilderMono.json", Enum.FontWeight.Bold)

-- Canvas art, drawn once and shared through ImageContent
local art = {}
local function canvas(name, w, h, draw)
	local c = assert(vmcp.Canvas.new(w, h))
	c:Clear(Color3.new(0, 0, 0), 0)
	draw(c, w, h)
	vmcp.Render(c, "cp-" .. name)
	art[name] = c:Content()
end

-- flat top/bottom hexagon, points left and right: fill then outline
canvas("hex", 256, 160, function(c, w, h)
	local inset = 64
	for y = 0, h - 1 do
		local t = math.abs(y - h / 2) / (h / 2)
		local x0 = inset * t
		c:Line(x0, y, w - x0, y, Color3.fromRGB(70, 12, 18), 1, 0.5)
	end
	local pts = { { 0, h / 2 }, { inset, 0 }, { w - inset, 0 }, { w, h / 2 }, { w - inset, h }, { inset, h } }
	for i = 1, 6 do
		local a, b = pts[i], pts[i % 6 + 1]
		c:Line(a[1], a[2], b[1], b[2], RED, 2, 0.9)
	end
	-- top/bottom notch tabs
	c:Rect(w / 2 - 22, 0, 44, 4, RED, 0.9)
	c:Rect(w / 2 - 22, h - 4, 44, 4, RED, 0.9)
end)

-- cyberware slot: dark plate, red corner brackets, faint diagonal
canvas("slot", 128, 128, function(c, w, h)
	c:Rect(3, 3, w - 6, h - 6, Color3.fromRGB(40, 10, 14), 0.75)
	c:Line(10, h - 10, w - 10, 10, Color3.fromRGB(120, 30, 36), 1, 0.5)
	local L = 22
	for _, corner in { { 0, 0, 1, 1 }, { w, 0, -1, 1 }, { 0, h, 1, -1 }, { w, h, -1, -1 } } do
		local x, y, sx, sy = table.unpack(corner)
		c:Line(x, y + sy * 2, x + sx * L, y + sy * 2, RED, 3)
		c:Line(x + sx * 2, y, x + sx * 2, y + sy * L, RED, 3)
	end
end)

-- body silhouette; drawn opaque, the label carries the transparency (thick lines are stacked strokes, so per-op alpha adds up unevenly)
canvas("body", 512, 848, function(c, w, h)
	local skin = Color3.fromRGB(255, 130, 50)
	local cx = w / 2
	c:Circle(cx, h * 0.06, w * 0.07, skin)
	c:Rect(cx - 16, h * 0.095, 32, h * 0.03, skin)
	for y = math.floor(h * 0.125), math.floor(h * 0.5) do -- torso: shoulders taper to hips
		local t = (y - h * 0.125) / (h * 0.375)
		local half = w * (0.15 - 0.05 * math.sin(t * math.pi * 0.9) ^ 0.6)
		if t < 0.1 then half += w * 0.1 * (0.1 - t) end
		c:Rect(cx - half, y, half * 2, 1, skin) -- Rect, not Line: a 1px AA line is only half-covered
	end
	local function limb(x0, y0, x1, y1, r) -- stamped circles; a thick Line is parallel strokes and stripes on a diagonal
		local n = math.ceil(math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2) / (r * 0.4))
		for i = 0, n do local t = i / n; c:Circle(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, r, skin) end
	end
	limb(cx - 76, h * 0.16, cx - 150, h * 0.5, 13) -- arms
	limb(cx + 76, h * 0.16, cx + 150, h * 0.5, 13)
	limb(cx - 30, h * 0.5, cx - 44, h * 0.97, 18) -- legs
	limb(cx + 30, h * 0.5, cx + 44, h * 0.97, 18)
	c:Line(cx, h * 0.125, cx, h * 0.5, Color3.fromRGB(255, 220, 120), 3, 0.5) -- spine glow
	c:Line(cx - 150, h * 0.36, cx + 150, h * 0.36, GREEN, 3, 0.6) -- scan lines
	c:Line(cx - 120, h * 0.92, cx + 120, h * 0.92, YELLOW, 3, 0.6)
end)

-- attribute glyphs, white, tinted by rule
local W = Color3.new(1, 1, 1)
local function ring(c) -- annulus from dots; the canvas has no erase
	for i = 0, 71 do local a = i * math.pi / 36; c:Circle(64 + 45 * math.cos(a), 64 + 45 * math.sin(a), 3, W) end
end
canvas("icoReflex", 128, 128, function(c) ring(c); for i = 0, 2 do local a = i * 2.094; c:Circle(64 + 20 * math.cos(a), 64 + 20 * math.sin(a), 11, W) end end)
canvas("icoBody", 128, 128, function(c) ring(c); c:Rect(44, 48, 40, 32, W); c:Rect(39, 59, 7, 20, W) end)
canvas("icoTech", 128, 128, function(c) ring(c); c:Line(64, 35, 64, 93, W, 9); c:Line(40, 64, 88, 64, W, 9) end)
canvas("icoInt", 128, 128, function(c) ring(c); c:Circle(64, 64, 8, W); for i = 0, 3 do local a = i * math.pi / 2 + math.pi / 4; c:Line(64, 64, 64 + 26 * math.cos(a), 64 + 26 * math.sin(a), W, 5); c:Circle(64 + 26 * math.cos(a), 64 + 26 * math.sin(a), 6, W) end end)
canvas("icoCool", 128, 128, function(c) ring(c); c:Line(50, 40, 78, 88, W, 6); c:Circle(52, 76, 9, W); c:Circle(76, 52, 9, W) end)
canvas("icoWeight", 128, 128, function(c) c:Rect(20, 55, 88, 55, W); c:Line(64, 20, 64, 55, W, 20) end)
canvas("item", 128, 128, function(c) c:Circle(64, 64, 35, W); c:Line(30, 100, 100, 30, W, 11) end)

-- Stylesheet: tokens + rules by tag
local sheet = Instance.new("StyleSheet")
sheet.Name = "Theme"
sheet:SetAttribute("Red", RED)
sheet:SetAttribute("Cyan", CYAN)
sheet:SetAttribute("Yellow", YELLOW)
sheet:SetAttribute("Green", GREEN)
sheet:SetAttribute("Dim", Color3.fromRGB(150, 60, 66))

local function rule(selector, class, props, priority)
	local r = Instance.new("StyleRule")
	local err = vmcp.Style.Selector(r, selector)
	assert(not err, selector .. ": " .. tostring(err))
	local refused = vmcp.Style.Apply(r, class, props)
	assert(#refused == 0, selector .. " refused " .. table.concat(refused, ","))
	r.Priority = priority or 0
	r.Parent = sheet
end
rule("TextLabel", "TextLabel", { BackgroundTransparency = 1, FontFace = JURA, TextColor3 = "$Red", TextSize = 20 })
rule("TextLabel.Mono", "TextLabel", { FontFace = MONO })
rule("TextLabel.Cyan", "TextLabel", { TextColor3 = "$Cyan" })
rule("TextLabel.Yellow", "TextLabel", { TextColor3 = "$Yellow" })
rule("TextLabel.Green", "TextLabel", { TextColor3 = "$Green" })
rule("TextLabel.Dim", "TextLabel", { TextColor3 = "$Dim" })
rule("TextLabel.Tab", "TextLabel", { TextColor3 = "$Dim" })
rule("TextLabel.Tab.Active", "TextLabel", { TextColor3 = "$Cyan", TextSize = 22 }, 2)
rule("ImageLabel", "ImageLabel", { BackgroundTransparency = 1 })
rule("ImageLabel.Cyan", "ImageLabel", { ImageColor3 = "$Cyan" })
rule("ImageLabel.Red", "ImageLabel", { ImageColor3 = "$Red" })
rule("Frame", "Frame", { BorderSizePixel = 0 })
rule("Frame.Red", "Frame", { BackgroundColor3 = "$Red" })
rule("Frame.Cyan", "Frame", { BackgroundColor3 = "$Cyan" })
rule("Frame.Green", "Frame", { BackgroundColor3 = "$Green" })
rule("Frame.Plate", "Frame", { BackgroundColor3 = Color3.fromRGB(45, 12, 16), BackgroundTransparency = 0.35 })

-- Build
local gui = Instance.new("ScreenGui")
gui.Name = "CyberpunkUI"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.Parent = StarterGui -- styling only resolves for a tree that is already in StarterGui when linked
sheet.Parent = gui

local vp = workspace.CurrentCamera.ViewportSize
local scale = math.floor(math.min(vp.X / 1920, vp.Y / 1080) * 20) / 20
local backdrop = Instance.new("Frame") -- fills the whole viewport; the fixed-size stage sits centred on it
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = Color3.new(1, 1, 1) -- white so the gradient colours below come through unmultiplied
backdrop.BorderSizePixel = 0
backdrop.Parent = gui
local bg = Instance.new("UIGradient") -- red haze at the top fading to near-black
bg.Rotation = 90
bg.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(70, 18, 26)), ColorSequenceKeypoint.new(0.35, Color3.fromRGB(28, 10, 16)), ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 8, 14)) })
bg.Parent = backdrop
local stage = Instance.new("Frame")
stage.Name = "Stage"
stage.Size = UDim2.fromOffset(1920, 1080)
stage.Position = UDim2.fromOffset(math.floor((vp.X - 1920 * scale) / 2), math.floor((vp.Y - 1080 * scale) / 2))
stage.BackgroundTransparency = 1
stage.Parent = gui
local uiscale = Instance.new("UIScale")
uiscale.Scale = scale
uiscale.Parent = stage

local function tag(inst, tags) for _, t in tags do CS:AddTag(inst, t) end return inst end

local function label(parent, text, x, y, w, h, size, tags, xalign)
	local l = Instance.new("TextLabel")
	l.Text = text
	l.Position = UDim2.fromOffset(x, y)
	l.Size = UDim2.fromOffset(w, h)
	l.TextSize = size
	l.TextXAlignment = xalign or Enum.TextXAlignment.Left
	l.Parent = parent
	return tag(l, tags or {})
end
local function box(parent, x, y, w, h, tags, transparency)
	local f = Instance.new("Frame")
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.BackgroundTransparency = transparency or 0
	f.Parent = parent
	return tag(f, tags or {})
end
local function image(parent, name, x, y, w, h, tags)
	local i = Instance.new("ImageLabel")
	i.ImageContent = art[name]
	i.Position = UDim2.fromOffset(x, y)
	i.Size = UDim2.fromOffset(w, h)
	i.Parent = parent
	return tag(i, tags or {})
end
local function chip(parent, text, x, y)
	local f = box(parent, x, y, 30, 16, {}, 0)
	f.BackgroundColor3 = Color3.fromRGB(30, 110, 130)
	label(f, text, 0, 0, 30, 16, 11, { "Cyan", "Mono" }, Enum.TextXAlignment.Center)
end

local CENTER = Enum.TextXAlignment.Center
local RIGHT = Enum.TextXAlignment.Right

-- top bar shared by both pages
local function topBar(page, tabs, activeIndex, money)
	label(page, "12", 78, 20, 40, 40, 34, { "Cyan", "Mono" })
	label(page, "LEVEL", 118, 26, 80, 30, 22, { "Cyan" })
	box(page, 118, 60, 90, 3, {}, 0).BackgroundColor3 = Color3.fromRGB(40, 80, 90)
	box(page, 118, 60, 30, 3, { "Cyan" })
	label(page, "19", 232, 20, 40, 40, 34, { "Green", "Mono" })
	label(page, "STREET CRED", 272, 26, 160, 30, 22, { "Green" })
	box(page, 272, 60, 130, 3, {}, 0).BackgroundColor3 = Color3.fromRGB(30, 80, 45)
	box(page, 272, 60, 100, 3, { "Green" })

	local n = #tabs
	local spacing = 150
	local x0 = 960 - (n - 1) * spacing / 2
	chip(page, "L1", x0 - 130, 34)
	chip(page, "R1", x0 + (n - 1) * spacing + 100, 34)
	for i, name in tabs do
		local cx = x0 + (i - 1) * spacing
		local tags = { "Tab" }
		if i == activeIndex then table.insert(tags, "Active") end
		image(page, "icoTech", cx - 72, 32, 22, 22, i == activeIndex and { "Cyan" } or { "Red" })
		label(page, name, cx - 44, 28, 130, 30, 20, tags)
	end

	image(page, "icoWeight", 1568, 34, 22, 22, { "Red" })
	label(page, "112/240", 1600, 26, 120, 34, 26, { "Mono" })
	label(page, "€$", 1730, 30, 40, 30, 22, { "Yellow" })
	label(page, money, 1770, 26, 100, 34, 28, { "Yellow", "Mono" })
	box(page, 50, 70, 1820, 2, { "Red" })
	box(page, 50, 72, 1820, 6, { "Red" }, 0.7)

	label(page, "Close", 1822, 1028, 80, 30, 22, { "Cyan" })
	local c = box(page, 1786, 1032, 24, 24, {}, 1)
	local s = Instance.new("UIStroke") s.Color = CYAN s.Thickness = 2 s.Parent = c
	local cc = Instance.new("UICorner") cc.CornerRadius = UDim.new(0.5, 0) cc.Parent = c
end

-- Page 1: character attributes
local p1 = box(stage, 0, 0, 1920, 1080, {}, 1)
p1.Name = "Character"
topBar(p1, { "INVENTORY", "MAP", "CHARACTER", "JOURNAL", "CRAFTING" }, 3, "32214")

local function pointsRow(y, count, tags, l1, l2)
	label(p1, count, 108, y, 30, 40, 32, { "Mono", tags })
	local f = box(p1, 140, y + 4, 36, 32, {}, 1)
	local s = Instance.new("UIStroke") s.Color = tags == "Cyan" and CYAN or YELLOW s.Thickness = 2 s.Parent = f
	label(p1, l1, 186, y, 200, 22, 18, { tags })
	label(p1, l2, 186, y + 22, 200, 22, 18, { tags })
end
pointsRow(206, "0", "Cyan", "ATTRIBUTE POINTS", "AVAILABLE")
pointsRow(272, "6", "Yellow", "PERK POINTS", "AVAILABLE")

local function attrHex(name, icon, value, cx, cy)
	local w, h = 240, 150
	local h0 = image(p1, "hex", cx - w / 2, cy - h / 2, w, h)
	h0.Name = name
	if name ~= "" then
		label(h0, name, 0, 22, w, 30, 20, { "Cyan" }, CENTER)
		image(h0, icon, w / 2 - 44, 66, 40, 40, { "Cyan" })
		label(h0, value, w / 2 + 6, 62, 40, 40, 30, { "Cyan", "Mono" })
		label(h0, "VALUE", w / 2 + 2, 100, 50, 16, 12, { "Cyan" })
	end
end
attrHex("REFLEXES", "icoReflex", "7", 960, 258)
attrHex("BODY", "icoBody", "4", 762, 368)
attrHex("TECHNICAL ABILITY", "icoTech", "8", 1156, 368)
attrHex("INTELLIGENCE", "icoInt", "8", 760, 738)
attrHex("COOL", "icoCool", "6", 1156, 738)
attrHex("", nil, nil, 958, 842)

-- centre level diamond with two wings
local function diamond(cx, cy, size, color, transparency, stroke)
	local d = box(p1, cx - size / 2, cy - size / 2, size, size, {}, transparency)
	d.BackgroundColor3 = color
	d.Rotation = 45
	if stroke then local s = Instance.new("UIStroke") s.Color = stroke s.Thickness = 2 s.Parent = d end
	return d
end
diamond(865, 570, 90, NAVY, 0.15)
diamond(1050, 560, 90, NAVY, 0.15)
diamond(958, 560, 140, Color3.fromRGB(20, 20, 45), 0, Color3.fromRGB(60, 60, 120))
label(p1, "12", 930, 480, 60, 40, 26, { "Cyan", "Mono" }, CENTER)
label(p1, "LEVEL", 900, 618, 120, 30, 20, { "Cyan" }, CENTER)
local cursor = box(p1, 1170, 492, 34, 30, {}, 1)
local cs = Instance.new("UIStroke") cs.Color = CYAN cs.Thickness = 2 cs.Parent = cursor
box(cursor, 8, 12, 18, 3, { "Cyan" })

-- circuit traces between hexes
local function trace(x, y, w, h) box(p1, x, y, w, h, { "Red" }, 0.55) end
trace(940, 335, 2, 150); trace(978, 335, 2, 150); trace(958, 700, 2, 70)
trace(940, 640, 2, 60); trace(978, 640, 2, 60)
trace(760, 440, 2, 60); trace(760, 500, 100, 2); trace(1156, 440, 2, 60); trace(1058, 500, 100, 2)
trace(760, 600, 100, 2); trace(760, 600, 2, 65); trace(1058, 600, 100, 2); trace(1156, 600, 2, 65)
for i = 0, 5 do trace(716 + i * 12, 458, 2, 24); trace(1160 + i * 12, 458, 2, 24); trace(716 + i * 12, 630, 2, 24); trace(1160 + i * 12, 630, 2, 24) end

-- Page 2: cyberware
local p2 = box(stage, 0, 0, 1920, 1080, {}, 1)
p2.Name = "Cyberware"
p2.Visible = false
topBar(p2, { "TRADE", "CYBERWARE", "TRADE" }, 2, "33564")

image(p2, "body", 700, 130, 520, 860).ImageTransparency = 0.3
local ring1 = box(p2, 790, 330, 340, 340, {}, 1)
local rs = Instance.new("UIStroke") rs.Color = RED rs.Thickness = 1 rs.Transparency = 0.5 rs.Parent = ring1
local rc = Instance.new("UICorner") rc.CornerRadius = UDim.new(0.5, 0) rc.Parent = ring1
box(p2, 890, 800, 140, 3, { "Green" }, 0.4)
box(p2, 870, 812, 180, 3, {}, 0.4).BackgroundColor3 = YELLOW
local sel = box(p2, 944, 522, 34, 34, {}, 1)
local ss = Instance.new("UIStroke") ss.Color = CYAN ss.Thickness = 2 ss.Parent = sel

local SLOT = 105
local function slot(x, y, filled, quality)
	local s = image(p2, "slot", x, y, SLOT, SLOT)
	if filled then
		local it = image(s, "item", 18, 18, SLOT - 36, SLOT - 36)
		it.ImageColor3 = filled
		if quality then box(s, 4, 10, 6, SLOT - 20, {}, 0).BackgroundColor3 = quality end
	else
		label(s, "+", 0, 0, SLOT, SLOT, 44, { "Dim" }, CENTER)
	end
	box(s, 8, SLOT - 6, SLOT - 16, 2, { "Cyan" }, 0.6)
end
local function countBadge(x, y, n)
	local f = box(p2, x, y, 26, 22, {}, 0)
	f.BackgroundColor3 = Color3.fromRGB(20, 90, 100)
	label(f, tostring(n), 0, 0, 26, 22, 16, { "Cyan", "Mono" }, CENTER)
end
local GOLD, BRAIN, PURPLE, BLUE, GREENQ = Color3.fromRGB(230, 180, 60), Color3.fromRGB(230, 70, 70), Color3.fromRGB(170, 60, 230), Color3.fromRGB(60, 120, 255), Color3.fromRGB(60, 220, 120)

-- left column: label right-aligned to the slots
local function leftGroup(y, title, subtitle, avail, slots)
	local ty = y + 6
	for _, t in title do label(p2, t, 100, ty, 280, 30, 24, {}, RIGHT); ty += 30 end
	if avail then
		label(p2, "AVAILABLE ITEMS", 100, ty + 2, 250, 22, 18, { "Cyan" }, RIGHT)
		countBadge(354, ty + 2, avail)
	else
		label(p2, subtitle, 60, ty + 2, 320, 22, 16, { "Dim" }, RIGHT)
	end
	for i, s in slots do slot(390 + (i - 1) * (SLOT + 8), y, s[1], s[2]) end
end
leftGroup(200, { "FRONTAL CORTEX" }, nil, 10, { { GOLD, PURPLE }, { BRAIN, BLUE }, { false } })
leftGroup(300, { "OCULAR SYSTEM" }, nil, 1, {})
slot(616, 300, GREENQ, PURPLE)
leftGroup(478, { "CIRCULATORY", "SYSTEM" }, nil, 4, { { false }, { false }, { false } })
leftGroup(612, { "IMMUNE SYSTEM" }, nil, 1, { { false }, { false } })
leftGroup(716, { "NERVOUS", "SYSTEM" }, nil, 3, { { GOLD, GREENQ }, { false } })
leftGroup(818, { "INTEGUMENTARY", "SYSTEM" }, "NO CYBERWARE TO INSTALL", nil, { { ORANGE }, { false }, { false } })

-- right column: slots first, labels to their right
local function rightGroup(y, title, avail, subtitle, slots)
	for i, s in slots do slot(1190 + (i - 1) * (SLOT + 8), y, s[1], s[2]) end
	local tx = 1190 + #slots * (SLOT + 8) + 4
	local ty = y + 6
	for _, t in title do label(p2, t, tx, ty, 300, 30, 24); ty += 30 end
	if avail then
		label(p2, "AVAILABLE ITEMS", tx, ty + 2, 200, 22, 18, { "Cyan" })
		countBadge(tx + 180, ty + 2, avail)
	else
		label(p2, subtitle, tx, ty + 2, 320, 22, 16, { "Dim" })
	end
end
rightGroup(300, { "OPERATING", "SYSTEM" }, 4, nil, { { GOLD, PURPLE } })
rightGroup(512, { "SKELETON" }, nil, "NO CYBERWARE TO INSTALL", { { false }, { BRAIN } })
rightGroup(614, { "HANDS" }, 1, nil, { { ORANGE, BLUE } })
rightGroup(716, { "ARMS" }, 4, nil, { { false } })
rightGroup(814, { "LEGS" }, 2, nil, { { false } })

-- vendor card
label(p2, "CASSIUS", 1400, 128, 200, 30, 24)
local card = box(p2, 1398, 168, 114, 96, { "Plate" })
local cst = Instance.new("UIStroke") cst.Color = RED cst.Thickness = 2 cst.Parent = card
image(card, "icoTech", 32, 20, 50, 50, { "Red" })
label(p2, "RIPPER_STORE_SS201", 1660, 186, 140, 18, 11, { "Dim" }, CENTER)
local cb = box(p2, 1656, 184, 148, 22, {}, 1)
local cbs = Instance.new("UIStroke") cbs.Color = DIMRED cbs.Thickness = 1 cbs.Parent = cb
label(p2, "€$", 1660, 220, 40, 30, 22, { "Yellow" })
label(p2, "14852", 1700, 216, 120, 34, 28, { "Yellow", "Mono" })

local link = Instance.new("StyleLink")
link.Parent = gui
link.StyleSheet = sheet
return { scale = scale, stagePos = stage.Position, labels = #gui:GetDescendants() }
