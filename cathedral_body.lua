--------------------------------------------------------------------
-- RuinedCathedralMap — builder body v3 (runs inside function(root))
--------------------------------------------------------------------
local rng = Random.new(1906)
local function jit(a) return (rng:NextNumber() * 2 - 1) * a end
local function rr(lo, hi) return lo + rng:NextNumber() * (hi - lo) end
local function rotY()
	local a = rng:NextNumber() * math.pi * 2
	local m = a % (math.pi / 2)
	if m < 0.1 then a += 0.1 - m elseif m > math.pi / 2 - 0.1 then a -= (m - (math.pi / 2 - 0.1)) end
	return a
end

local function ensure(parent, name, class)
	local found = parent:FindFirstChild(name)
	if found and found.ClassName ~= class then found:Destroy() found = nil end
	if not found then
		found = Instance.new(class)
		found.Name = name
		found.Parent = parent
	end
	return found
end

local P = {
	grass  = { Enum.Material.Grass, Color3.fromRGB(54, 68, 46) },
	grassDk= { Enum.Material.Grass, Color3.fromRGB(40, 54, 36) },
	leaf   = { Enum.Material.Grass, Color3.fromRGB(48, 66, 40) },
	leafDk = { Enum.Material.Grass, Color3.fromRGB(35, 50, 33) },
	leafLt = { Enum.Material.Grass, Color3.fromRGB(64, 84, 50) },
	dirt   = { Enum.Material.Ground, Color3.fromRGB(76, 64, 50) },
	wall   = { Enum.Material.Limestone, Color3.fromRGB(112, 108, 98) },
	wall2  = { Enum.Material.Limestone, Color3.fromRGB(97, 93, 85) },
	plinth = { Enum.Material.Cobblestone, Color3.fromRGB(78, 76, 70) },
	trim   = { Enum.Material.Sandstone, Color3.fromRGB(148, 140, 124) },
	roof   = { Enum.Material.Slate, Color3.fromRGB(56, 58, 64) },
	timber = { Enum.Material.Wood, Color3.fromRGB(58, 44, 32) },
	plank  = { Enum.Material.WoodPlanks, Color3.fromRGB(74, 58, 42) },
	floor  = { Enum.Material.Cobblestone, Color3.fromRGB(94, 92, 86) },
	marble = { Enum.Material.Marble, Color3.fromRGB(122, 120, 112) },
	rock   = { Enum.Material.Rock, Color3.fromRGB(90, 88, 82) },
	grave  = { Enum.Material.Rock, Color3.fromRGB(104, 102, 94) },
	grave2 = { Enum.Material.Slate, Color3.fromRGB(88, 90, 92) },
	bone   = { Enum.Material.SmoothPlastic, Color3.fromRGB(198, 192, 174) },
	iron   = { Enum.Material.Metal, Color3.fromRGB(56, 56, 62) },
	bronze = { Enum.Material.Metal, Color3.fromRGB(112, 84, 50) },
	bark   = { Enum.Material.Wood, Color3.fromRGB(56, 44, 34) },
	barkDk = { Enum.Material.Wood, Color3.fromRGB(44, 36, 28) },
	birch  = { Enum.Material.Wood, Color3.fromRGB(206, 202, 192) },
	cloth  = { Enum.Material.Fabric, Color3.fromRGB(96, 40, 36) },
	glass  = { Enum.Material.Glass, Color3.fromRGB(170, 190, 230) },
	flame  = { Enum.Material.Neon, Color3.fromRGB(255, 190, 110) },
}

local function finish(p, m, props)
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if m then p.Material = m[1] p.Color = m[2] end
	if props then for k, v in props do p[k] = v end end
	return p
end

local function box(parent, name, size, cf, m, props)
	local p = ensure(parent, name, "Part")
	p.Size = size
	p.CFrame = cf
	return finish(p, m, props)
end

local function wedge(parent, name, size, cf, m, props)
	local p = ensure(parent, name, "WedgePart")
	p.Size = size
	p.CFrame = cf
	return finish(p, m, props)
end

local function cyl(parent, name, dia, len, cf, m, props)
	local p = ensure(parent, name, "Part")
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(len, dia, dia)
	p.CFrame = cf
	return finish(p, m, props)
end

local function col(parent, name, dia, h, cf, m, props)
	return cyl(parent, name, dia, h, cf * CFrame.Angles(0, 0, math.pi / 2), m, props)
end

local function slabBetween(parent, name, a, b, wide, thick, m, props)
	local len = (b - a).Magnitude
	return box(parent, name, Vector3.new(wide, thick, len), CFrame.lookAt((a + b) / 2, b), m, props)
end

local function rodBetween(parent, name, a, b, dia, m, props)
	return cyl(parent, name, dia, (b - a).Magnitude,
		CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0), m, props)
end

-- ============ constants ============
local GT = 0.125
local WT = 2
local ARC = 6.5
local FL = GT + 0.9
local S = 150
local ZF = 14
local ZN = -7.1
local CLN = -6.15

local Ground = ensure(root, "Ground", "Model")
local Cathedral = ensure(root, "Cathedral", "Model")
local Shell = ensure(Cathedral, "Shell", "Model")
local Roofs = ensure(Cathedral, "Roofs", "Model")
local FrontM = ensure(Cathedral, "Front", "Model")
local TowerM = ensure(Cathedral, "Tower", "Model")
local ApseM = ensure(Cathedral, "Apse", "Model")
local Interior = ensure(Cathedral, "Interior", "Model")
local Cemetery = ensure(root, "Cemetery", "Model")
local Forest = ensure(root, "Forest", "Model")
local Vines = ensure(root, "Vines", "Model")
local Atmos = ensure(root, "Atmos", "Model")

-- ============ masonry helpers ============
local function archParts(parent, name, frame, span, rise, depth, thick, m)
	local half = span / 2
	local len, ang = math.sqrt(half * half + rise * rise), math.atan2(rise, half)
	for sd = -1, 1, 2 do
		box(parent, name .. (sd < 0 and "L" or "R"), Vector3.new(len, thick, depth),
			frame * CFrame.new(sd * half / 2, rise / 2, 0) * CFrame.Angles(0, 0, -sd * ang) * CFrame.new(0, -thick / 2, 0), m)
	end
	box(parent, name .. "Key", Vector3.new(thick * 1.3, thick * 1.5, depth + 0.3),
		frame * CFrame.new(0, rise - thick * 0.2, 0), m)
end

local function spandrels(parent, name, frame, span, rise, depth, m, upTo)
	for sd = -1, 1, 2 do
		wedge(parent, name .. (sd < 0 and "L" or "R"), Vector3.new(depth, rise, span / 2),
			frame * CFrame.new(sd * span / 4, rise / 2, 0) * CFrame.Angles(0, sd * math.pi / 2, 0) * CFrame.Angles(math.pi, 0, 0), m)
	end
	if upTo and upTo > rise - 0.2 then
		local hh = upTo - rise + 0.15
		box(parent, name .. "Head", Vector3.new(depth, hh, span),
			frame * CFrame.new(0, rise - 0.075 + hh / 2, 0), m)
	end
end

local function lancetBay(parent, name, thick, L, h, cf, m, w)
	local ow, y0 = w.ow, w.y0 or 0
	local sill, spring, rise = w.sill, w.spring, w.rise
	if y0 < sill - 0.01 then
		box(parent, name .. "Base", Vector3.new(thick, sill - y0, L), cf * CFrame.new(0, y0 + (sill - y0) / 2, 0), m)
	end
	local pw = (L - ow) / 2
	local ph = spring - sill
	box(parent, name .. "PL", Vector3.new(thick, ph, pw), cf * CFrame.new(0, sill + ph / 2, -(ow / 2 + pw / 2)), m)
	box(parent, name .. "PR", Vector3.new(thick, ph, pw), cf * CFrame.new(0, sill + ph / 2, (ow / 2 + pw / 2)), m)
	local af = cf * CFrame.new(0, spring, 0) * CFrame.Angles(0, math.pi / 2, 0)
	archParts(parent, name .. "Arch", af, ow, rise, thick, 0.7, m)
	spandrels(parent, name .. "Sp", af, ow, rise, thick, m, h - spring)
end

local function doorBay(parent, name, thick, L, h, cf, m)
	local ow, spring, rise = 3.8, 5.8, 1.2
	local pw = (L - ow) / 2
	box(parent, name .. "PL", Vector3.new(thick, h, pw), cf * CFrame.new(0, h / 2, -(ow / 2 + pw / 2)), m)
	box(parent, name .. "PR", Vector3.new(thick, h, pw), cf * CFrame.new(0, h / 2, (ow / 2 + pw / 2)), m)
	local af = cf * CFrame.new(0, spring, 0) * CFrame.Angles(0, math.pi / 2, 0)
	archParts(parent, name .. "Arch", af, ow, rise, thick, 0.8, m)
	spandrels(parent, name .. "Sp", af, ow, rise, thick, m, h - spring)
end

local function bayFor(parent, nm, thick, L, cf, m, s)
	if type(s) == "number" then
		box(parent, nm, Vector3.new(thick, s, L), cf * CFrame.new(0, s / 2, 0), m)
	elseif s.win == nil then
		local y0 = s.y0 or 0
		box(parent, nm, Vector3.new(thick, s.h - y0, L), cf * CFrame.new(0, y0 + (s.h - y0) / 2, 0), m)
	elseif s.win.door then
		doorBay(parent, nm, thick, L, s.h, cf, m)
	else
		lancetBay(parent, nm, thick, L, s.h, cf, m, s.win)
	end
end

local function wallZ(parent, tag, x, z0, z1, spec, thick, m)
	local n = #spec
	local L = (z0 - z1) / n
	for i = 1, n do
		bayFor(parent, tag .. i, thick, L, CFrame.new(x, GT, z0 - (i - 0.5) * L), m, spec[i])
	end
end

local function wallX(parent, tag, z, x0, x1, spec, thick, m)
	local n = #spec
	local L = (x1 - x0) / n
	for i = 1, n do
		bayFor(parent, tag .. i, thick, L, CFrame.new(x0 + (i - 0.5) * L, GT, z) * CFrame.Angles(0, math.pi / 2, 0), m, spec[i])
	end
end

local function buttress(parent, name, cf, h, m)
	box(parent, name .. "A", Vector3.new(1.3, h * 0.55, 2), cf * CFrame.new(0.5, h * 0.275, 0), m)
	box(parent, name .. "B", Vector3.new(0.8, h * 0.45, 1.6), cf * CFrame.new(0.25, h * 0.55 + h * 0.225, 0), m)
	wedge(parent, name .. "C", Vector3.new(0.8, 0.3, 1.6), cf * CFrame.new(0.25, h + 0.15, 0) * CFrame.Angles(0, math.pi / 2, 0), m)
end

-- ============ ground, paths, plaza ============
box(Ground, "Turf", Vector3.new(S, 6, S), CFrame.new(0, GT - 3, 0), P.grass)
local patches = { { 0, -42, 24, 7 }, { 2, 34, 12, 6 }, { -24, 8, 16, 10 }, { 40, -18, 14, 10 } }
for i, pd in patches do
	box(Ground, "Patch" .. i, Vector3.new(pd[3], 0.12, pd[4]), CFrame.new(pd[1], GT, pd[2]), P.grassDk, { CanCollide = false })
end
box(Ground, "PathMain1", Vector3.new(7, 0.12, 31), CFrame.new(2, GT + 0.06, 59.5), P.dirt)
box(Ground, "PathMain2", Vector3.new(6, 0.12, 12.5), CFrame.new(4, GT + 0.06, 37.75), P.dirt)
box(Ground, "Plaza", Vector3.new(18, 0.12, 10), CFrame.new(2, GT + 0.06, 26.5), P.dirt)
box(Ground, "PathSideA", Vector3.new(4.5, 0.12, 44.5), CFrame.new(26.5, GT + 0.06, 7.25), P.dirt)
box(Ground, "PathSideB", Vector3.new(4.5, 0.12, 39), CFrame.new(26.5, GT + 0.06, -34.5), P.dirt)
box(Ground, "PathPlazaLink", Vector3.new(13, 0.12, 4), CFrame.new(19.75, GT + 0.06, 29.5), P.dirt)
box(Ground, "PathGateLink", Vector3.new(15.75, 0.12, 3.5), CFrame.new(16.375, GT + 0.06, -54.5), P.dirt)
box(Ground, "PathCemInner", Vector3.new(13.5, 0.12, 3), CFrame.new(1.25, GT + 0.06, -54.5), P.dirt)
box(Ground, "Step1", Vector3.new(8, 0.275, 1.35), CFrame.new(0, GT + 0.1125, 19), P.trim)
box(Ground, "Step2", Vector3.new(8, 0.275, 1.35), CFrame.new(0, GT + 0.3625, 17.8), P.trim)
box(Ground, "Step3", Vector3.new(8, 0.275, 1.35), CFrame.new(0, GT + 0.6125, 16.7), P.trim)

-- ============ plinth + floors ============
box(Shell, "PlinthNave", Vector3.new(27, 0.84, 24), CFrame.new(0, GT + 0.42, 4), P.plinth)
box(Shell, "PlinthCross", Vector3.new(17, 0.84, 17), CFrame.new(0, GT + 0.42, -16.5), P.plinth)
box(Shell, "PlinthArmE", Vector3.new(13.5, 0.84, 17), CFrame.new(15.25, GT + 0.42, -16.5), P.plinth)
box(Shell, "PlinthArmW", Vector3.new(13.5, 0.84, 17), CFrame.new(-15.25, GT + 0.42, -16.5), P.plinth)
box(Shell, "PlinthChoir", Vector3.new(17, 0.84, 8), CFrame.new(0, GT + 0.42, -30), P.plinth)
box(Shell, "PlinthApse", Vector3.new(13, 0.84, 4.4), CFrame.new(0, GT + 0.42, -37.2), P.plinth)
box(Shell, "PaveNaveC", Vector3.new(4.4, 0.12, 22), CFrame.new(0, FL, 3), P.marble)
box(Shell, "PaveNaveE", Vector3.new(4.3, 0.12, 22), CFrame.new(4.35, FL, 3), P.floor)
box(Shell, "PaveNaveW", Vector3.new(4.3, 0.12, 22), CFrame.new(-4.35, FL, 3), P.floor)
box(Shell, "PaveAisleE", Vector3.new(5, 0.12, 22), CFrame.new(9, FL, 3), P.floor)
box(Shell, "PaveAisleW", Vector3.new(5, 0.12, 22), CFrame.new(-9, FL, 3), P.floor)
box(Shell, "PaveCross", Vector3.new(13, 0.12, 13), CFrame.new(0, FL, -16.5), P.marble)
box(Shell, "PaveChoir", Vector3.new(13, 0.12, 7), CFrame.new(0, FL, -30), P.marble)
box(Shell, "Dais", Vector3.new(7, 0.5, 5), CFrame.new(0, FL + 0.25, -30), P.marble)
box(Shell, "DaisStep", Vector3.new(7, 0.25, 1.2), CFrame.new(0, FL + 0.125, -26.9), P.marble)

-- ============ outer walls ============
local naveWin = { ow = 1.4, sill = 2.6, spring = 5.2, rise = 1.4 }
local naveBreach = { ow = 2.7, sill = 0.5, spring = 5.2, rise = 1.4 }
local naveHe = { 8.5, 8, 9.5, 6.5, 7.6, 9 }
local naveHw = { 7.8, 9.2, 8.8, 7.2, 8.6, 8.2 }
wallZ(Shell, "NaveWallE", 12.5, ZF, ZN, { naveHe[1], { h = naveHe[2], win = naveWin }, naveHe[3], naveHe[4], { h = naveHe[5], win = naveBreach }, naveHe[6] }, WT, P.wall)
wallZ(Shell, "NaveWallW", -12.5, ZF, ZN, { naveHw[1], naveHw[2], { h = naveHw[3], win = naveWin }, { h = naveHw[4], win = naveWin }, naveHw[5], { h = naveHw[6], win = naveBreach } }, WT, P.wall)

local clWin = { ow = 1.8, y0 = 13, sill = 13.4, spring = 15.8, rise = 2 }
local clHe = { 19.5, 18.6, 18.2, 16.5, 17.5 }
local clHw = { 19, 18.4, 17, 18.8, 16.5 }
wallZ(Shell, "ClerestE", 7.5, ZF, CLN, { { h = clHe[1], y0 = 13 }, { h = clHe[2], win = clWin }, { h = clHe[3], win = clWin }, { h = clHe[4], y0 = 13 }, { h = clHe[5], y0 = 13 } }, WT, P.wall)
wallZ(Shell, "ClerestW", -7.5, ZF, CLN, { { h = clHw[1], y0 = 13 }, { h = clHw[2], win = clWin }, { h = clHw[3], y0 = 13 }, { h = clHw[4], win = clWin }, { h = clHw[5], y0 = 13 } }, WT, P.wall)
box(Shell, "TriforiumE", Vector3.new(WT, 2, 20.15), CFrame.new(7.5, 12, 3.925), P.wall2)
box(Shell, "TriforiumW", Vector3.new(WT, 2, 20.15), CFrame.new(-7.5, 12, 3.925), P.wall2)
box(Shell, "JunctionFillE", Vector3.new(2, 8.0, 0.95), CFrame.new(9.5, 5.08, -6.625), P.wall)
box(Shell, "JunctionFillW", Vector3.new(2, 8.0, 0.95), CFrame.new(-9.5, 5.08, -6.625), P.wall)

-- front facade
local nich = { ow = 1.5, sill = 2.8, spring = 8, rise = 1.9 }
wallX(FrontM, "Front", 15, -13.5, 13.5, { 18, { h = 18, win = nich }, { h = 18, win = { door = true } }, { h = 18, win = nich }, 18 }, WT, P.wall)
wedge(FrontM, "GableL", Vector3.new(WT, 8, 6.75), CFrame.new(-3.375, GT + 22, 15) * CFrame.Angles(0, -math.pi / 2, 0), P.wall)
wedge(FrontM, "GableR", Vector3.new(WT, 8, 6.75), CFrame.new(3.375, GT + 22, 15) * CFrame.Angles(0, math.pi / 2, 0), P.wall)
box(FrontM, "RoseBand", Vector3.new(7, 1.2, 2.2), CFrame.new(0, GT + 18.6, 15), P.trim)
for i = 1, 8 do
	if not (i == 6 or i == 7 or i == 8) then
		local a = (i - 0.5) * math.pi / 4
		box(FrontM, "Rose" .. i, Vector3.new(1.2, 0.9, 1.6),
			CFrame.new(math.cos(a) * 2, GT + 21 + math.sin(a) * 2, 15) * CFrame.Angles(0, 0, a + math.pi / 2), P.trim)
	end
end
box(FrontM, "RoseMullV", Vector3.new(0.25, 3.5, 1.2), CFrame.new(0, GT + 21, 15), P.trim)
box(FrontM, "RoseMullH", Vector3.new(3.5, 0.25, 1.2), CFrame.new(0, GT + 21, 15), P.trim)
box(FrontM, "GlassA", Vector3.new(1.1, 1.1, 0.12), CFrame.new(-0.8, GT + 21.8, 15), P.iron, { Transparency = 0.45, Color = Color3.fromRGB(150, 60, 50) })
box(FrontM, "GlassB", Vector3.new(1.1, 1.1, 0.12), CFrame.new(0.9, GT + 20.4, 15), P.iron, { Transparency = 0.45, Color = Color3.fromRGB(60, 80, 160) })

-- tower: passage arches, jagged tops
local passNS = { ow = 9, y0 = 0, sill = 0.6, spring = 13, rise = 3.2 }
local passEW = { ow = 5, y0 = 0, sill = 0.6, spring = 13, rise = 2.5 }
wallX(TowerM, "TowerS", -9, -8.5, 8.5, { { h = 28, win = passNS } }, WT, P.wall2)
wallX(TowerM, "TowerN", -24, -8.5, 8.5, { { h = 27, win = passNS } }, WT, P.wall2)
wallZ(TowerM, "TowerE", 7.5, -11.85, -21.15, { { h = 26, win = passEW } }, WT, P.wall2)
wallZ(TowerM, "TowerW", -7.5, -11.85, -21.15, { { h = 22, win = passEW } }, WT, P.wall2)
for i, mx in { 1.8, 3.7 } do
	box(TowerM, "Merlon" .. i, Vector3.new(1.3, 1.5, 1.6), CFrame.new(mx, GT + 28.9, -9) * CFrame.Angles(0, jit(0.2), 0), P.wall2)
end
box(TowerM, "MerlonFallen", Vector3.new(1.3, 1.5, 1.6), CFrame.new(5.0, GT + 0.55, -28.4) * CFrame.Angles(0.2, 0.6, 0.35), P.wall2)
box(TowerM, "TowerLedgeS", Vector3.new(0.25, 0.5, 9), CFrame.new(8.6, GT + 21.5, -16.5), P.trim)
box(TowerM, "TowerLedgeN", Vector3.new(0.25, 0.5, 9), CFrame.new(-8.6, GT + 21.5, -20), P.trim)

-- transept arms
local trWin = { ow = 4, y0 = 0, sill = 0.6, spring = 7.2, rise = 2.6 }
local smWin = { ow = 1.3, sill = 2.4, spring = 5, rise = 1.3 }
wallX(Shell, "ArmES", -9, 8.5, 20, { { h = 10.5, win = { door = true } }, 10.5 }, WT, P.wall)
wallX(Shell, "ArmWS", -9, -20, -8.5, { 10.5, { h = 10.5, win = { door = true } } }, WT, P.wall)
wallX(Shell, "ArmEN", -24, 8.5, 20, { { h = 11.5, win = smWin }, 12.5, 9.5 }, WT, P.wall)
wallX(Shell, "ArmWN", -24, -20, -8.5, { 10.5, 8.5, { h = 11.5, win = smWin } }, WT, P.wall)
wallZ(Shell, "ArmEEnd", 21, -10.9, -22.1, { { h = 12.5, win = trWin } }, WT, P.wall)
wallZ(Shell, "ArmWEnd", -21, -10.9, -22.1, { { h = 12.5, win = trWin } }, WT, P.wall)

-- choir + apse
wallZ(Shell, "ChoirE", 7.5, -26.85, -33.15, { 14, 11, 14 }, WT, P.wall)
wallZ(Shell, "ChoirW", -7.5, -26.85, -33.15, { 13.5, 12, 9 }, WT, P.wall)
wallX(Shell, "ChoirClose", -34, -8.5, 8.5, { 13.5, { h = 15, win = { ow = 3.4, y0 = 0, sill = 0.5, spring = 6.5, rise = 2.2 } }, 13.5 }, WT, P.wall)
wallX(ApseM, "ApseC", -39.4, -3.9, 3.9, { { h = 16, win = { ow = 3.4, y0 = 0, sill = 0.5, spring = 7, rise = 2.8 } } }, WT, P.wall)
slabBetween(ApseM, "ApseDiagE", Vector3.new(5.9, GT + 7.25, -34.9), Vector3.new(3.85, GT + 7.25, -38.7), WT, 14.5, P.wall)
slabBetween(ApseM, "ApseDiagW", Vector3.new(-5.9, GT + 5.75, -34.9), Vector3.new(-3.85, GT + 5.75, -38.7), WT, 11.5, P.wall)

-- arcade
for sd = -1, 1, 2 do
	local ax = sd * ARC
	for i = 0, 5 do
		local z = 12.8 - i * 3.57
		local pf = CFrame.new(ax, FL, z)
		local tag = (sd < 0 and "W" or "E")
		if i > 0 then -- first bay stands open so both aisles are enterable from the nave
			box(Shell, `PierBase` .. tag .. i, Vector3.new(1.6, 0.8, 1.6), pf * CFrame.new(0, 0.4, 0), P.trim)
			col(Shell, `Pier` .. tag .. i, 1.2, 7.4, pf * CFrame.new(0, 4.5, 0), P.wall2)
			box(Shell, `PierCap` .. tag .. i, Vector3.new(1.6, 0.7, 1.6), pf * CFrame.new(0, 8.55, 0), P.trim)
		end
		if i > 0 and i < 5 then
			local af = CFrame.new(ax, FL + 8.9, z - 1.785) * CFrame.Angles(0, math.pi / 2, 0)
			archParts(Shell, `Arcade` .. tag .. i, af, 3, 1.6, 2.2, 0.7, P.wall2)
		end
	end
end

-- buttresses
local bz = { 10.48, 6.97, 3.45, -0.07, -3.59 }
for i = 1, 5 do
	buttress(Shell, `ButtE` .. i, CFrame.new(13.5, GT, bz[i]), 8.5, P.wall2)
	buttress(Shell, `ButtW` .. i, CFrame.new(-13.5, GT, bz[i]) * CFrame.Angles(0, math.pi, 0), 8.5, P.wall2)
end
buttress(FrontM, "CornerButtE", CFrame.new(14.25, GT, 15.85) * CFrame.Angles(0, -math.pi / 4, 0), 11, P.wall2)
buttress(FrontM, "CornerButtW", CFrame.new(-14.25, GT, 15.85) * CFrame.Angles(0, math.pi / 4, 0), 11, P.wall2)
slabBetween(Shell, "ButtFallen", Vector3.new(-16.2, GT + 0.7, -1.5), Vector3.new(-12.4, GT + 1.3, 1.5), 2.4, 1.2, P.wall2)

-- ============ roofs ============
local aisleE = { true, true, false, true, "half", true }
local aisleW = { true, false, true, "half", true, true }
for i = 1, 6 do
	local zc = 14 - (i - 0.5) * 3.517
	if aisleE[i] then
		local a = aisleE[i] == "half" and Vector3.new(11.25, 10.7, zc) or Vector3.new(8.5, 12.9, zc)
		slabBetween(Roofs, `AisleRoofE` .. i, a, Vector3.new(13.3, 8.9, zc), 3.5, 0.5, P.roof)
	end
	if aisleW[i] then
		local a = aisleW[i] == "half" and Vector3.new(-11.25, 10.7, zc) or Vector3.new(-8.5, 12.9, zc)
		slabBetween(Roofs, `AisleRoofW` .. i, a, Vector3.new(-13.3, 8.9, zc), 3.5, 0.5, P.roof)
	end
end
local naveS = { true, true, "half", true, false }
local naveN = { false, true, true, "half", true }
local navePitch = (ZF - 0.1 + 7.9) / 5
for i = 1, 5 do
	local zc = 13.9 - (i - 0.5) * 4.36
	local eS, eN = clHe[i] + 0.6, clHw[i] + 0.6
	if naveS[i] then
		local a = naveS[i] == "half" and Vector3.new(4.4, (eS + 24.8) / 2, zc) or Vector3.new(8.8, eS, zc)
		slabBetween(Roofs, `NaveRoofS` .. i, a, Vector3.new(0, 24.8, zc), 4.2, 0.5, P.roof)
	end
	if naveN[i] then
		local a = naveN[i] == "half" and Vector3.new(-4.4, (eN + 24.8) / 2, zc) or Vector3.new(-8.8, eN, zc)
		slabBetween(Roofs, `NaveRoofN` .. i, a, Vector3.new(0, 24.8, zc), 4.2, 0.5, P.roof)
	end
end
box(Roofs, "RidgeBeam", Vector3.new(0.8, 1, 18.3), CFrame.new(0, GT + 25.3, 4.75), P.timber)
local function armRoofs(tag, sx)
	local stS = sx > 0 and { true, false } or { false, false }
	local stN = sx > 0 and { true, true } or { true, false }
	for i = 1, 2 do
		local xc = sx * (11.875 + (i - 1) * 6.75)
		if stS[i] then
			local a = stS[i] == "half" and Vector3.new(xc, 13.1, -13.4) or Vector3.new(xc, 15.5, -16.5)
			slabBetween(Roofs, tag .. "S" .. i, a, Vector3.new(xc, 10.75, -10.9), 6.75, 0.5, P.roof)
		end
		if stN[i] then
			local a = stN[i] == "half" and Vector3.new(xc, 13.6, -19.6) or Vector3.new(xc, 15.5, -16.5)
			slabBetween(Roofs, tag .. "N" .. i, a, Vector3.new(xc, 11.7, -22.1), 6.75, 0.5, P.roof)
		end
	end
	box(Roofs, tag .. "Ridge", Vector3.new(13.5, 0.9, 0.8), CFrame.new(sx * 15.25, 15.9, -16.5), P.timber)
end
armRoofs("ArmRoofE", 1)
armRoofs("ArmRoofW", -1)
for i = 1, 2 do
	local zc = -25.9 - (i - 0.5) * 4
	if i == 1 then slabBetween(Roofs, `ChoirRoofS` .. i, Vector3.new(6.5, 14.2, zc), Vector3.new(0, 17.5, zc), 4.0, 0.5, P.roof) end
	if i == 2 then
		slabBetween(Roofs, `ChoirRoofN` .. i, Vector3.new(-3.2, 15.9, zc), Vector3.new(0, 17.5, zc), 4.0, 0.5, P.roof)
	end
end

-- crossing rubble + fallen bell
local rub = { { 1.2, -11.0 }, { 2.2, -12.6 }, { 0.4, -12.8 }, { 2.2, -14.5 }, { -2.2, -16.6 }, { 4.8, -13.5 } }
for i, rp in rub do
	local w = rr(1.2, 2.6)
	box(Shell, `RubbleX` .. i, Vector3.new(w, w * 0.5, w * rr(0.7, 1.2)),
		CFrame.new(rp[1], FL + w * 0.2, rp[2]) * CFrame.Angles(jit(0.4), rotY(), jit(0.4)), P.wall2)
end
local bellF = CFrame.new(2.5, FL + 0.85, -18.5) * CFrame.Angles(0, 0.5, 0.9)
col(Shell, "Bell", 2.4, 2.2, bellF, P.bronze)
col(Shell, "BellLip", 2.8, 0.5, bellF * CFrame.new(0, -1.4, 0), P.bronze)

-- ============ interior: pews, altar, beam ============
local function pew(parent, name, cf, state)
	local g = ensure(parent, name, "Model")
	if state == "ok" or state == "noback" then
		box(g, "Seat", Vector3.new(3.4, 0.15, 1.1), cf * CFrame.new(0, 0.85, 0), P.plank)
		box(g, "LegL", Vector3.new(0.18, 0.78, 0.95), cf * CFrame.new(-1.5, 0.39, 0), P.timber)
		box(g, "LegR", Vector3.new(0.18, 0.78, 0.95), cf * CFrame.new(1.5, 0.39, 0), P.timber)
		if state == "ok" then
			box(g, "Back", Vector3.new(3.4, 1.15, 0.14), cf * CFrame.new(0, 1.5, 0.48) * CFrame.Angles(0.05, 0, 0), P.timber)
		end
	elseif state == "toppled" then
		box(g, "Seat", Vector3.new(3.4, 0.15, 1.1), cf * CFrame.new(0.5, 0.58, -0.7) * CFrame.Angles(0, 0.15, 1.25), P.plank)
		box(g, "Back", Vector3.new(3.4, 1.15, 0.14), cf * CFrame.new(-0.6, 0.62, 0.4) * CFrame.Angles(1.55, 0, 0.2), P.timber)
		box(g, "LegL", Vector3.new(0.18, 0.78, 0.95), cf * CFrame.new(-1.4, 0.6, -1.6) * CFrame.Angles(0, 0.3, 0.5), P.timber)
	elseif state == "broken" then
		box(g, "SeatA", Vector3.new(2.0, 0.15, 1.1), cf * CFrame.new(-0.7, 0.85, 0), P.plank)
		box(g, "LegL", Vector3.new(0.18, 0.78, 0.95), cf * CFrame.new(-1.5, 0.39, 0), P.timber)
		box(g, "SeatB", Vector3.new(1.2, 0.15, 1.1), cf * CFrame.new(1.3, 0.14, 1.0) * CFrame.Angles(0, 0.3, 0.08), P.plank)
		box(g, "Back", Vector3.new(2.0, 1.15, 0.14), cf * CFrame.new(-0.7, 1.5, 0.48) * CFrame.Angles(0.05, 0, 0), P.timber)
	end
end
pew(Interior, "PewE1", CFrame.new(3.6, FL, 10.4) * CFrame.Angles(0, jit(0.06), 0), "ok")
pew(Interior, "PewE2", CFrame.new(3.6, FL, 6.8) * CFrame.Angles(0, jit(0.06), 0), "ok")
pew(Interior, "PewE3", CFrame.new(3.6, FL, 3.2) * CFrame.Angles(0, jit(0.06), 0), "broken")
pew(Interior, "PewW1", CFrame.new(-3.6, FL, 10.4) * CFrame.Angles(0, math.pi + jit(0.06), 0), "noback")
pew(Interior, "PewW2", CFrame.new(-3.6, FL, 6.8) * CFrame.Angles(0, math.pi + jit(0.06), 0), "toppled")
pew(Interior, "PewW3", CFrame.new(-3.6, FL, 3.2) * CFrame.Angles(0, math.pi + jit(0.06), 0), "ok")
-- broken altar on the dais
local daisT = FL + 0.5
box(Interior, "AltarPedL", Vector3.new(1.1, 1.9, 1.4), CFrame.new(-1.2, daisT + 0.95, -30.4) * CFrame.Angles(0, 0.08, 0), P.marble)
box(Interior, "AltarPedR", Vector3.new(1.0, 1.2, 1.3), CFrame.new(0.95, daisT + 0.6, -30.5) * CFrame.Angles(0, -0.12, 0.06), P.marble)
box(Interior, "AltarSlab", Vector3.new(3.4, 0.28, 1.7), CFrame.new(-1.3, daisT + 0.22, -29.0) * CFrame.Angles(-0.09, 0.2, 0.04), P.marble)
box(Interior, "AltarFallen", Vector3.new(1.7, 0.26, 1.5), CFrame.new(3.4, FL + 0.15, -32.3) * CFrame.Angles(0, 0.5, 0.04), P.marble)
box(Interior, "AltarCloth", Vector3.new(1.2, 0.06, 1.3), CFrame.new(-1.2, daisT + 1.93, -30.4) * CFrame.Angles(0, 0.08, 0), P.cloth)
-- fallen clerestory beam
slabBetween(Interior, "BeamFallen", Vector3.new(6.9, 12.6, -1.4), Vector3.new(-3.2, 1.15, -5.0), 1.0, 0.9, P.timber)
for i, bp in { { 4.6, 2.2, -2.6 }, { 1.2, 1.6, -4.1 }, { -1.9, 1.4, -4.9 } } do
	local w = rr(0.9, 1.7)
	box(Interior, `BeamRubble` .. i, Vector3.new(w, w * 0.5, w * 0.9),
		CFrame.new(bp[1], FL + w * 0.18, bp[2]) * CFrame.Angles(jit(0.3), rotY(), jit(0.3)), P.wall2)
end
-- aisle rubble
for i, bp in { { 10.6, 5.4 }, { -10.2, 8.6 }, { 10.9, -2.2 } } do
	local w = rr(0.8, 1.4)
	box(Interior, `AisleRubble` .. i, Vector3.new(w, w * 0.55, w * rr(0.7, 1.1)),
		CFrame.new(bp[1], FL + w * 0.2, bp[2]) * CFrame.Angles(jit(0.35), rotY(), jit(0.35)), P.wall2)
end

-- ============ the fallen soldier ============
local Soldier = ensure(Interior, "FallenSoldier", "Model")
local sf = CFrame.new(-3.2, FL, -13.4) * CFrame.Angles(0, -0.65, 0)
-- collapsed column drum he slumps against
col(Soldier, "Drum", 1.8, 2.4, CFrame.new(-4.7, FL + 0.75, -13.4) * CFrame.Angles(0, 0.5, math.pi / 2), P.wall2)
-- pelvis low, torso reclined against the drum
box(Soldier, "Pelvis", Vector3.new(0.8, 0.5, 0.55), sf * CFrame.new(0, 0.34, 0) * CFrame.Angles(-0.25, 0, 0.12), P.bone)
local spineA = sf * CFrame.new(0.1, 0.75, -0.28) * CFrame.Angles(-0.5, 0, 0.1)
box(Soldier, "Spine1", Vector3.new(0.34, 0.3, 0.3), spineA, P.bone)
box(Soldier, "Spine2", Vector3.new(0.32, 0.3, 0.3), spineA * CFrame.new(0, 0.3, -0.22), P.bone)
box(Soldier, "Spine3", Vector3.new(0.3, 0.28, 0.28), spineA * CFrame.new(0, 0.58, -0.43), P.bone)
-- ribcage: paired slats leaning with the spine
for i = 0, 2 do
	local rf = spineA * CFrame.new(0, 0.12 + i * 0.28, -0.1 - i * 0.2)
	box(Soldier, `RibL` .. i, Vector3.new(0.5, 0.09, 0.34), rf * CFrame.new(-0.3, 0, 0.02) * CFrame.Angles(0, 0, 0.35 - i * 0.08), P.bone)
	box(Soldier, `RibR` .. i, Vector3.new(0.5, 0.09, 0.34), rf * CFrame.new(0.3, 0, 0.02) * CFrame.Angles(0, 0, -0.35 + i * 0.08), P.bone)
end
box(Soldier, "Sternum", Vector3.new(0.22, 0.5, 0.1), spineA * CFrame.new(0, 0.35, 0.26) * CFrame.Angles(-0.15, 0, 0), P.bone)
-- neck vertebrae, then the skull — head stays connected to the spine
box(Soldier, "Neck1", Vector3.new(0.24, 0.22, 0.24), spineA * CFrame.new(0.01, 0.76, -0.56), P.bone)
box(Soldier, "Neck2", Vector3.new(0.22, 0.2, 0.22), spineA * CFrame.new(0.02, 0.92, -0.74), P.bone)
local skullF = spineA * CFrame.new(0.02, 1.16, -0.98) * CFrame.Angles(0.35, 0.3, -0.4)
box(Soldier, "Skull", Vector3.new(0.5, 0.55, 0.55), skullF, P.bone)
box(Soldier, "Jaw", Vector3.new(0.34, 0.16, 0.3), skullF * CFrame.new(0, -0.32, 0.16) * CFrame.Angles(0.5, 0, 0), P.bone)
-- arms: right hangs down the drum, left sprawled across the lap
rodBetween(Soldier, "ArmRU", Vector3.new(-2.4, 2.2, -13.3), Vector3.new(-2.75, 1.6, -12.6), 0.17, P.bone)
rodBetween(Soldier, "ArmRL", Vector3.new(-2.75, 1.6, -12.6), Vector3.new(-2.95, 1.12, -11.95), 0.15, P.bone)
box(Soldier, "HandR", Vector3.new(0.22, 0.12, 0.3), CFrame.new(-2.98, 1.12, -11.85) * CFrame.Angles(0.3, 0.4, 0), P.bone)
rodBetween(Soldier, "ArmLU", (spineA * CFrame.new(-0.5, 0.35, 0.2)).Position, (spineA * CFrame.new(-1.15, -0.5, 0.75)).Position, 0.17, P.bone)
rodBetween(Soldier, "ArmLL", (spineA * CFrame.new(-1.15, -0.5, 0.75)).Position, (spineA * CFrame.new(-0.35, -0.85, 1.15)).Position, 0.15, P.bone)
box(Soldier, "HandL", Vector3.new(0.2, 0.12, 0.28), spineA * CFrame.new(-0.25, -0.9, 1.25) * CFrame.Angles(0, 0.5, 0), P.bone)
-- legs folded under him, one knee up
rodBetween(Soldier, "LegLU", (sf * CFrame.new(-0.3, 0.35, 0.35)).Position, (sf * CFrame.new(-0.85, 0.5, 1.5)).Position, 0.2, P.bone)
rodBetween(Soldier, "LegLL", (sf * CFrame.new(-0.85, 0.5, 1.5)).Position, (sf * CFrame.new(-0.4, 0.28, 2.6)).Position, 0.17, P.bone)
box(Soldier, "FootL", Vector3.new(0.24, 0.14, 0.42), sf * CFrame.new(-0.35, 0.2, 2.9) * CFrame.Angles(0, 0.4, 0), P.bone)
rodBetween(Soldier, "LegRU", (sf * CFrame.new(0.35, 0.3, 0.3)).Position, (sf * CFrame.new(1.35, 0.32, 0.9)).Position, 0.2, P.bone)
rodBetween(Soldier, "LegRL", (sf * CFrame.new(1.35, 0.32, 0.9)).Position, (sf * CFrame.new(1.7, 0.2, 2.0)).Position, 0.17, P.bone)
box(Soldier, "FootR", Vector3.new(0.24, 0.14, 0.42), sf * CFrame.new(1.75, 0.14, 2.25) * CFrame.Angles(0, -0.5, 0), P.bone)
-- damaged armour: chest plate riding the ribcage, one pauldron, tassets
box(Soldier, "ChestPlate", Vector3.new(0.95, 0.85, 0.14), spineA * CFrame.new(-0.05, 0.4, 0.42) * CFrame.Angles(-0.2, 0.08, -0.12), P.iron)
box(Soldier, "Pauldron", Vector3.new(0.55, 0.28, 0.55), spineA * CFrame.new(0.62, 0.62, -0.05) * CFrame.Angles(0.2, 0, 0.35), P.iron)
box(Soldier, "TassetL", Vector3.new(0.4, 0.45, 0.1), sf * CFrame.new(-0.42, 0.3, 0.28) * CFrame.Angles(-0.4, 0, 0.1), P.iron)
box(Soldier, "Belt", Vector3.new(0.9, 0.16, 0.62), sf * CFrame.new(0, 0.5, 0.05) * CFrame.Angles(-0.2, 0, 0.1), P.iron)
-- the sword: driven through the chest, tip into the ground behind
local bladeA = (spineA * CFrame.new(0.12, 0.62, 0.75)).Position
local bladeB = (spineA * CFrame.new(-0.42, -1.45, -1.1)).Position
slabBetween(Soldier, "Blade", bladeA, bladeB, 0.3, 0.07, P.iron)
local dirUp = (bladeA - bladeB).Unit
rodBetween(Soldier, "Grip", bladeA + dirUp * 0.35, bladeA + dirUp * 1.05, 0.12, P.timber)
local cg = bladeA + dirUp * 0.18
box(Soldier, "Crossguard", Vector3.new(0.7, 0.09, 0.14), CFrame.lookAt(cg, cg + dirUp), P.bronze)
box(Soldier, "Pommel", Vector3.new(0.2, 0.2, 0.2), CFrame.new(bladeA + dirUp * 1.28), P.bronze)
-- helmet rolled off nearby + broken shield
box(Soldier, "Helmet", Vector3.new(0.56, 0.42, 0.58), CFrame.new(-0.4, FL + 0.24, -10.6) * CFrame.Angles(0.4, 1.2, 0.25), P.iron)
box(Soldier, "HelmetBrim", Vector3.new(0.66, 0.08, 0.68), CFrame.new(-0.4, FL + 0.1, -10.6) * CFrame.Angles(0.1, 1.2, 0.1), P.iron)
box(Soldier, "Shield", Vector3.new(1.5, 0.12, 1.5), CFrame.new(-5.6, FL + 0.07, -11.6) * CFrame.Angles(0, 0.3, 0.1), P.iron)
box(Soldier, "ShieldBoss", Vector3.new(0.4, 0.1, 0.4), CFrame.new(-5.85, FL + 0.15, -11.75) * CFrame.Angles(0, 0.3, 0.1), P.bronze)
box(Soldier, "ShieldHalf", Vector3.new(0.8, 0.1, 1.4), CFrame.new(-4.5, FL + 0.06, -12.9) * CFrame.Angles(0, 0.85, 0.04), P.iron)

-- ============ candles & lanterns ============
local function candle(parent, name, cf, h, range, bright)
	col(parent, name .. "Stick", 0.16, 0.5, cf * CFrame.new(0, 0.25, 0), P.bronze)
	col(parent, name .. "Wax", 0.12, h, cf * CFrame.new(0, 0.5 + h / 2, 0), P.bone)
	local fl = box(parent, name .. "Flame", Vector3.new(0.14, 0.22, 0.14), cf * CFrame.new(0, 0.55 + h, 0), P.flame)
	local light = ensure(parent, name .. "Light", "PointLight")
	light.Parent = fl
	light.Color = Color3.fromRGB(255, 175, 95)
	light.Range = range
	light.Brightness = bright
	light.Shadows = true
end
candle(Interior, "CandleAltarL", CFrame.new(-1.2, daisT + 1.9, -30.4), 0.35, 10, 0.9)
candle(Interior, "CandleAltarR", CFrame.new(-0.55, daisT + 1.9, -30.2), 0.25, 8, 0.7)
candle(Interior, "CandlePew", CFrame.new(3.6, FL + 0.93, 10.4), 0.3, 7, 0.6)
-- floor lantern near the soldier
local lantern = ensure(Interior, "Lantern", "Model")
local lf = CFrame.new(-1.4, FL, -11.2) * CFrame.Angles(0, 0.7, 0)
box(lantern, "Base", Vector3.new(0.7, 0.1, 0.7), lf * CFrame.new(0, 0.05, 0), P.iron)
for i, lp in { { -0.28, -0.28 }, { 0.28, -0.28 }, { -0.28, 0.28 }, { 0.28, 0.28 } } do
	rodBetween(lantern, `Post` .. i, (lf * CFrame.new(lp[1], 0.1, lp[2])).Position, (lf * CFrame.new(lp[1], 1.0, lp[2])).Position, 0.07, P.iron)
end
box(lantern, "Cap", Vector3.new(0.8, 0.12, 0.8), lf * CFrame.new(0, 1.06, 0), P.iron)
wedge(lantern, "CapTop", Vector3.new(0.8, 0.25, 0.8), lf * CFrame.new(0, 1.24, 0) * CFrame.Angles(0, math.pi / 4, 0), P.iron)
for i, lp in { { 0, -0.34 }, { 0, 0.34 }, { -0.34, 0 }, { 0.34, 0 } } do
	box(lantern, `Pane` .. i, Vector3.new(lp[1] == 0 and 0.62 or 0.05, 0.8, lp[1] == 0 and 0.05 or 0.62),
		lf * CFrame.new(lp[1], 0.55, lp[2]), P.glass, { Transparency = 0.45 })
end
candle(lantern, "Candle", lf * CFrame.new(0, 0.1, 0), 0.3, 13, 1.2)

-- ============ vines & overgrowth ============
local function vineStrip(parent, name, a, b)
	slabBetween(parent, name, a, b, 0.2, 0.14, P.leafDk)
	local n = math.max(2, math.floor((b - a).Magnitude / 1.6))
	for i = 1, n do
		local pt = a:Lerp(b, i / (n + 1))
		box(parent, name .. "Leaf" .. i, Vector3.new(rr(0.4, 0.7), 0.12, rr(0.3, 0.5)),
			CFrame.new(pt) * CFrame.Angles(jit(0.4), rotY(), jit(0.4)), P.leaf)
	end
end
vineStrip(Vines, "VineFront1", Vector3.new(-8.6, GT + 1.2, 13.94), Vector3.new(-8.9, GT + 6.4, 13.9))
vineStrip(Vines, "VineFront2", Vector3.new(-2.8, GT + 0.9, 13.94), Vector3.new(-3.1, GT + 5.2, 13.9))
vineStrip(Vines, "VineTowerE", Vector3.new(8.62, GT + 2.5, -12.6), Vector3.new(8.7, GT + 9.5, -13.2))
vineStrip(Vines, "VineApse", Vector3.new(-2.2, GT + 1.4, -40.52), Vector3.new(-2.6, GT + 6.8, -40.6))
vineStrip(Vines, "VineNaveW", Vector3.new(-13.62, GT + 2.2, 8.2), Vector3.new(-13.7, GT + 6.9, 8.0))
vineStrip(Vines, "VineCem", Vector3.new(-20.2, GT + 0.8, -45.94), Vector3.new(-19.6, GT + 2.1, -45.9))
vineStrip(Vines, "VineButt", Vector3.new(14.2, GT + 0.9, 4.9), Vector3.new(14.5, GT + 4.6, 4.6))
-- grass tufts in the cemetery
for i, tp in { { -26, -49 }, { -30, -53 }, { -22, -55 }, { -17, -60 }, { -25, -64 }, { -12, -57 }, { -8, -60 }, { -19, -68 } } do
	box(Cemetery, `Tuft` .. i, Vector3.new(rr(0.6, 1.0), rr(0.3, 0.5), rr(0.4, 0.7)),
		CFrame.new(tp[1] + jit(0.8), GT + 0.2, tp[2] + jit(0.8)) * CFrame.Angles(0, rotY(), jit(0.1)), P.leafDk, { CanCollide = false })
end

-- ============ cemetery ============
box(Cemetery, "CemGround", Vector3.new(41, 0.55, 23), CFrame.new(-13.175, GT - 0.225, -58), P.grassDk)
local function cemWall(parent, name, size, cf, h)
	box(parent, name, size, cf, P.plinth)
	if h > 1.6 then box(parent, name .. "Cap", Vector3.new(size.X + 0.2, 0.15, size.Z + 0.2), cf * CFrame.new(0, h / 2 + 0.075, 0), P.rock) end
end
local hs = { 2.1, 1.7, 2.3, 1.3, 2.0, 1.8, 2.2 }
local hn = { 2, 2.4, 1.6, 2.2, 1.8, 2.1, 1.7 }
for i = 1, 7 do
	local x = -34 + (i - 0.5) * 6
	cemWall(Cemetery, `CemS` .. i, Vector3.new(6, hs[i], 0.7), CFrame.new(x, GT + hs[i] / 2, -46.35), hs[i])
	cemWall(Cemetery, `CemN` .. i, Vector3.new(6, hn[i], 0.7), CFrame.new(x, GT + hn[i] / 2, -69.65), hn[i])
end
cemWall(Cemetery, "CemE1", Vector3.new(0.7, 1.9, 6), CFrame.new(8.35, GT + 0.95, -49), 1.9)
cemWall(Cemetery, "CemE2", Vector3.new(0.7, 2.1, 6), CFrame.new(8.35, GT + 1.05, -59), 2.1)
cemWall(Cemetery, "CemE3", Vector3.new(0.7, 1.5, 6), CFrame.new(8.35, GT + 0.75, -65), 1.5)
cemWall(Cemetery, "CemE4", Vector3.new(0.7, 0.8, 2), CFrame.new(8.35, GT + 0.4, -69), 0.8)
local hw = { 1.8, 2.2, 1.4, 2 }
for i = 1, 4 do
	local z = -46 - (i - 0.5) * 6
	cemWall(Cemetery, `CemW` .. i, Vector3.new(0.7, hw[i], 6), CFrame.new(-34.35, GT + hw[i] / 2, z), hw[i])
end
for i, cp in { { -34, -46 }, { 8, -46 }, { -34, -70 }, { 8, -70 } } do
	box(Cemetery, `CemPost` .. i, Vector3.new(1.2, 2.7, 1.2), CFrame.new(cp[1], GT + 1.35, cp[2]), P.rock)
	box(Cemetery, `CemPostCap` .. i, Vector3.new(1.5, 0.25, 1.5), CFrame.new(cp[1], GT + 2.8, cp[2]), P.rock)
end
box(Cemetery, "GatePostS", Vector3.new(1.3, 3.6, 1.3), CFrame.new(8.35, GT + 1.8, -51.5), P.rock)
wedge(Cemetery, "GatePostCapS", Vector3.new(1.6, 0.5, 1.6), CFrame.new(8.35, GT + 3.85, -51.5) * CFrame.Angles(0, math.pi / 4, 0), P.rock)
box(Cemetery, "GatePostN", Vector3.new(1.3, 3.2, 1.3), CFrame.new(8.35, GT + 1.6, -56.5), P.rock)

local function grave(parent, name, x, z, yaw, kind)
	if math.abs(yaw) < 7 then yaw += (yaw >= 0 and 7 or -7) end
	local f = CFrame.new(x, GT, z) * CFrame.Angles(0, math.rad(yaw), 0)
	local h = rr(1.7, 2.3)
	local m = rng:NextNumber() < 0.5 and P.grave or P.grave2
	if kind == "slab" then
		box(parent, name, Vector3.new(1.4, h, 0.32), f * CFrame.new(0, h / 2 - 0.15, 0) * CFrame.Angles(jit(0.05), 0, jit(0.05)), m)
		box(parent, name .. "Base", Vector3.new(1.7, 0.3, 0.55), f * CFrame.new(0, 0.05, 0), P.rock)
	elseif kind == "cross" then
		box(parent, name .. "U", Vector3.new(0.38, h + 0.6, 0.38), f * CFrame.new(0, (h + 0.6) / 2 - 0.15, 0) * CFrame.Angles(jit(0.05), 0, jit(0.05)), m)
		box(parent, name .. "Arm", Vector3.new(1.5, 0.38, 0.38), f * CFrame.new(0, h * 0.62, 0), m)
		box(parent, name .. "Base", Vector3.new(1.3, 0.35, 1.3), f * CFrame.new(0, 0.03, 0), P.rock)
	elseif kind == "chip" then
		box(parent, name, Vector3.new(1.4, h, 0.32), f * CFrame.new(0, h / 2 - 0.15, 0), m)
		box(parent, name .. "Chip", Vector3.new(0.6, 0.5, 0.3), f * CFrame.new(0.35, h - 0.35, 0) * CFrame.Angles(0, 0, 0.5), m)
	elseif kind == "lean" then
		box(parent, name, Vector3.new(1.4, h, 0.32), f * CFrame.new(0, h / 2 - 0.35, 0.18) * CFrame.Angles(jit(0.04), 0, rr(0.16, 0.26)), m)
		box(parent, name .. "Base", Vector3.new(1.7, 0.3, 0.55), f * CFrame.new(0, 0.05, 0), P.rock)
	elseif kind == "fall" then
		box(parent, name, Vector3.new(1.4, 0.32, h), f * CFrame.new(0, 0.16, h * 0.2) * CFrame.Angles(jit(0.06), 0, jit(0.06)), m)
		box(parent, name .. "Base", Vector3.new(1.7, 0.3, 0.55), f * CFrame.new(0, 0.05, -h * 0.32), P.rock)
	elseif kind == "ped" then
		box(parent, name .. "Pl", Vector3.new(1.9, 0.5, 1.1), f * CFrame.new(0, 0.1, 0), P.rock)
		col(parent, name .. "U", 0.7, h - 0.4, f * CFrame.new(0, 0.35 + (h - 0.4) / 2, 0) * CFrame.Angles(jit(0.04), 0, jit(0.04)), m)
		col(parent, name .. "Lip", 0.95, 0.25, f * CFrame.new(0, h - 0.2, 0), m)
	end
end
local graves = {
	{ -28, -50, 15, "slab" }, { -24, -52, -8, "cross" }, { -31, -55, 4, "slab" }, { -19, -50, 22, "chip" },
	{ -14, -53, -15, "slab" }, { -27, -58, -5, "cross" }, { -21, -57, 12, "lean" }, { -15, -59, -20, "slab" },
	{ -30, -62, 8, "fall" }, { -23, -63, -12, "ped" }, { -17, -61, 18, "slab" }, { -12.5, -60.5, -7, "cross" },
	{ -26, -67, 10, "chip" }, { -20, -66, -18, "slab" }, { -13, -68, 5, "lean" }, { -6, -52, -10, "slab" },
	{ -3, -57, 14, "cross" }, { -7, -62, -4, "fall" }, { -1, -65, 9, "slab" }, { -33, -58, -14, "slab" },
}
for i, gd in graves do
	grave(Cemetery, `Grave` .. i, gd[1], gd[2], gd[3], gd[4])
end
box(Cemetery, "TombPlinth", Vector3.new(6, 1, 3), CFrame.new(-8, GT + 0.5, -66), P.rock)
for i, cp in { { -10.5, -67.2 }, { -5.5, -67.2 }, { -10.5, -64.8 }, { -5.5, -64.8 } } do
	box(Cemetery, `TombPost` .. i, Vector3.new(0.7, 1.6, 0.7), CFrame.new(cp[1], GT + 1.8, cp[2]), P.rock)
end
box(Cemetery, "TombLid", Vector3.new(5.6, 0.45, 2.6), CFrame.new(-8, GT + 2.75, -66), P.marble)
box(Cemetery, "TombEffigy", Vector3.new(4, 0.3, 1.3), CFrame.new(-8.2, GT + 3.1, -66) * CFrame.Angles(0, 0.12, 0.06), P.grave2)
box(Cemetery, "ColBase", Vector3.new(2.2, 0.6, 2.2), CFrame.new(-31, GT + 0.3, -48), P.rock)
col(Cemetery, "ColShaft", 1.4, 3.2, CFrame.new(-31, GT + 2.1, -48) * CFrame.Angles(0.1, 0.4, 0.08), P.grave)
cyl(Cemetery, "ColCap", 1.7, 0.4, CFrame.new(-30.7, GT + 3.75, -47.8) * CFrame.Angles(0.1, 0.4, 0.08), P.grave)
cyl(Cemetery, "ColDrum", 1.4, 1.1, CFrame.new(-29, GT + 0.4, -46.6) * CFrame.Angles(0, 0.3, math.pi / 2), P.grave)

-- ============ forest ============
local function tree(parent, name, x, z, kind, s)
	s = s or 1
	local g = ensure(parent, name, "Model")
	local f = CFrame.new(x, GT - 0.25, z) * CFrame.Angles(0, rotY(), 0)
	if kind == "oak" then
		local lean = rng:NextNumber() < 0.5 and rr(0.1, 0.16) or 0
		local h = rr(9, 12) * s
		col(g, "Trunk", rr(1.7, 2.3) * s, h, f * CFrame.new(0, h / 2, 0) * CFrame.Angles(lean, 0, lean * 0.7), P.bark)
		col(g, "TrunkTop", 1.1 * s, 2.6, f * CFrame.new(jit(0.4), h + 1, jit(0.4)) * CFrame.Angles(jit(0.25), 0, jit(0.25)), P.barkDk)
		for i = 1, 3 do
			local a = i * 2.1 + rng:NextNumber()
			rodBetween(g, `Branch` .. i,
				(f * CFrame.new(math.cos(a) * rr(0.7, 1), h * rr(0.5, 0.72), math.sin(a) * rr(0.7, 1))).Position,
				(f * CFrame.new(math.cos(a) * rr(3.2, 4.6), h * rr(0.92, 1.2), math.sin(a) * rr(3.2, 4.6))).Position, 0.65 * s, P.barkDk)
		end
		local pads = { { 0, h + 2.4, 0, 10.5, 3 }, { 3.4, h + 1.3, 1.6, 7.5, 2.4 }, { -3.2, h + 1.7, -2.4, 7.2, 2.3 }, { 0.8, h + 4, -0.9, 6, 2 } }
		local mats = { P.leaf, P.leafDk, P.leaf, P.leafLt }
		for i, pd in pads do
			box(g, `Canopy` .. i, Vector3.new(pd[4] * s, pd[5], pd[4] * rr(0.72, 0.95) * s),
				f * CFrame.new(pd[1], pd[2], pd[3]) * CFrame.Angles(0, rotY(), jit(0.12)), mats[i])
		end
	elseif kind == "pine" then
		local h = rr(11, 15) * s
		col(g, "Trunk", rr(1.1, 1.5) * s, h, f * CFrame.new(0, h / 2, 0), P.barkDk)
		local widths = { 8.5, 6.8, 5.2, 3.6 }
		for i, w in widths do
			box(g, `Tier` .. i, Vector3.new(w * s, 1.9, w * s),
				f * CFrame.new(0, h * (0.35 + 0.16 * (i - 1)), 0) * CFrame.Angles(0, rotY(), 0), i % 2 == 0 and P.leafDk or P.leaf)
		end
	elseif kind == "birch" then
		local h = rr(8, 10.5) * s
		col(g, "Trunk", 0.9 * s, h, f * CFrame.new(0, h / 2, 0), P.birch)
		box(g, "Mark", Vector3.new(0.98, 0.5, 0.98), f * CFrame.new(0.05, h * 0.5, 0), P.barkDk, { Transparency = 0.35 })
		for i = 1, 2 do
			local a = rotY()
			rodBetween(g, `Branch` .. i, (f * CFrame.new(0, h - 1, 0)).Position, (f * CFrame.new(math.cos(a) * 2.4, h + 0.6, math.sin(a) * 2.4)).Position, 0.4, P.birch)
		end
		box(g, "Canopy1", Vector3.new(6 * s, 2, 5 * s), f * CFrame.new(0, h + 1.6, 0) * CFrame.Angles(0, rotY(), 0), P.leafLt)
		box(g, "Canopy2", Vector3.new(4.5 * s, 1.8, 4 * s), f * CFrame.new(1.4, h + 3, -0.8) * CFrame.Angles(0, rotY(), jit(0.1)), P.leaf)
	elseif kind == "snag" then
		local h = rr(6.5, 9) * s
		col(g, "Trunk", rr(1.2, 1.6) * s, h, f * CFrame.new(0, h / 2, 0), P.barkDk)
		wedge(g, "Break", Vector3.new(1.4 * s, 1.6, 1.4 * s), f * CFrame.new(0, h + 0.7, 0) * CFrame.Angles(math.pi, 0, 0), P.barkDk)
		rodBetween(g, "Stub1", (f * CFrame.new(0, h * 0.6, 0)).Position, (f * CFrame.new(1.8, h * 0.6 + 1.4, 0.6)).Position, 0.5, P.bark)
		rodBetween(g, "Stub2", (f * CFrame.new(0, h * 0.4, 0)).Position, (f * CFrame.new(-1.5, h * 0.4 + 1, -1.2)).Position, 0.4, P.bark)
	end
end
local trees = {
	{ -58, 38, "oak" }, { -47, 20, "pine" }, { -64, 2, "oak" }, { -52, -14, "snag" }, { -38, -30, "pine" }, { -70, -34, "oak" },
	{ 50, 28, "oak" }, { 40, 12, "birch" }, { 62, -8, "pine" }, { 46, -24, "oak" }, { 58, -42, "snag" }, { 36, -50, "pine" },
	{ -26, 54, "pine" }, { 16, 60, "oak" }, { 34, 50, "birch" }, { -6, 66, "oak" }, { -50, 62, "pine" },
	{ -50, -58, "snag" }, { 64, -62, "pine" }, { -16, -74.5, "oak" }, { 24, -64, "birch" },
	{ 68, 52, "pine" }, { -66, 54, "oak" }, { 56, 62, "oak" }, { -64, -66, "pine" }, { 44, -66, "snag" },
}
for i, td in trees do
	tree(Forest, `Tree` .. i, td[1], td[2], td[3], rr(0.9, 1.15))
end
local function stump(parent, name, x, z)
	local g = ensure(parent, name, "Model")
	local d = rr(2, 2.8)
	col(g, "Stump", d, 1.2, CFrame.new(x, GT + 0.35, z) * CFrame.Angles(0, rotY(), 0), P.bark)
	for i = 1, 3 do
		local a = rotY()
		rodBetween(g, `Root` .. i, Vector3.new(x, GT + 0.5, z),
			Vector3.new(x + math.cos(a) * rr(1.8, 2.6), GT - 0.25, z + math.sin(a) * rr(1.8, 2.6)), 0.45, P.barkDk)
	end
	box(g, "Top", Vector3.new(d * 0.7, 0.14, d * 0.7), CFrame.new(x, GT + 1.02, z) * CFrame.Angles(0, rotY(), 0), P.plank)
end
stump(Forest, "Stump1", -44, 30)
stump(Forest, "Stump2", 32, 20.5)
local function rocks(parent, name, x, z, n, s)
	local g = ensure(parent, name, "Model")
	for i = 1, n do
		local w = rr(1.6, 3.4) * s
		box(g, `Rock` .. i, Vector3.new(w, w * rr(0.55, 0.8), w * rr(0.7, 1.1)),
			CFrame.new(x + jit(2.2) * s, GT + w * 0.18, z + jit(2.2) * s)
				* CFrame.Angles(jit(0.3), rotY(), jit(0.3)), P.rock)
	end
	box(g, "Moss", Vector3.new(rr(1.5, 2.5), 0.12, rr(1.5, 2.5)),
		CFrame.new(x + jit(1), GT + 0.06, z + jit(1)) * CFrame.Angles(0, rotY(), 0), P.leafDk, { CanCollide = false })
end
local rockSpots = { { -30, 8, 3, 1 }, { -28, -18, 2, 1.2 }, { 21, 5, 2, 1 }, { 33, -16.5, 3, 1 }, { 44, 8, 2, 1.1 }, { -14, 40, 2, 0.9 }, { 12, 38, 2, 0.8 }, { -44, -20, 3, 1.1 }, { 54, -30, 2, 1 }, { -60, 48, 3, 1.2 }, { 14, -56, 2, 0.8 }, { -30, -44, 2, 0.9 } }
for i, rd in rockSpots do
	rocks(Forest, `Rocks` .. i, rd[1], rd[2], rd[3], rd[4])
end
-- ferns, log, undergrowth
local function fern(parent, name, x, z)
	local g = ensure(parent, name, "Model")
	for i = 1, 3 do
		local a = rotY() + (i - 2) * 1.05
		box(g, `Frond` .. i, Vector3.new(0.9, 0.06, 0.3),
			CFrame.new(x, GT + 0.28, z) * CFrame.Angles(jit(0.15), a, 0.5), i == 2 and P.leaf or P.leafDk, { CanCollide = false })
	end
	box(g, "Core", Vector3.new(0.22, 0.4, 0.22), CFrame.new(x, GT + 0.2, z), P.leafDk, { CanCollide = false })
end
local fernSpots = { { -22, 16 }, { 10, 34 }, { -12, -36 }, { 31, -30 }, { -36, 44 }, { 48, -12 }, { -42, -8 }, { 8, 46 } }
for i, fp in fernSpots do
	fern(Forest, `Fern` .. i, fp[1], fp[2])
end
local logF = CFrame.new(-20, GT + 0.5, 26) * CFrame.Angles(0, 0.6, math.pi / 2)
cyl(Forest, "FallenLog", 1.0, 7.5, logF, P.bark)
box(Forest, "LogMoss", Vector3.new(2.6, 0.18, 1.1), logF * CFrame.new(0, 0.28, 0.25) * CFrame.Angles(0, 0.2, 0), P.leafDk, { CanCollide = false })
cyl(Forest, "LogEnd", 1.0, 0.12, logF * CFrame.new(0, 0, 3.82), P.plank)
tree(Cemetery, "CemTree", -16, -48.5, "snag", 0.8)

-- ============ atmosphere: shafts, dust, moon ============
local function shaft(parent, name, a, b, wide, thick)
	local sh = slabBetween(parent, name, a, b, wide, thick, P.glass,
		{ Transparency = 0.88, CanCollide = false, CastShadow = false, CanQuery = false, CanTouch = false })
	return sh
end
shaft(Atmos, "ShaftTower", Vector3.new(1.8, 26.5, -14.8), Vector3.new(-1.6, 1.4, -18.2), 5.2, 5.2)
shaft(Atmos, "ShaftNaveS", Vector3.new(2.2, 15.5, -5.2), Vector3.new(-0.6, 1.4, -6.8), 3.0, 2.6)
shaft(Atmos, "ShaftNaveN", Vector3.new(-1.8, 20.5, 11.4), Vector3.new(0.7, 1.4, 9.9), 3.0, 2.6)
shaft(Atmos, "ShaftApse", Vector3.new(0.5, 15.5, -38.6), Vector3.new(-0.9, 2.0, -37.6), 2.6, 2.2)
local function dust(parent, name, cf)
	local holder = box(parent, name, Vector3.new(0.4, 0.4, 0.4), cf, nil,
		{ Transparency = 1, CanCollide = false, CastShadow = false, CanQuery = false, CanTouch = false })
	local pe = ensure(holder, "Dust", "ParticleEmitter")
	pe.Rate = 6
	pe.Lifetime = NumberRange.new(5, 9)
	pe.Speed = NumberRange.new(0.1, 0.3)
	pe.Size = NumberSequence.new(0.3, 0.12)
	pe.Transparency = NumberSequence.new(0.82, 1)
	pe.LightEmission = 0.5
	pe.Color = ColorSequence.new(Color3.fromRGB(205, 220, 245))
	pe.Acceleration = Vector3.new(0.03, 0.06, 0)
	pe.RotSpeed = NumberRange.new(-25, 25)
	pe.SpreadAngle = Vector2.new(15, 15)
	pe.EmissionDirection = Enum.NormalId.Top
end
dust(Atmos, "DustTower", CFrame.new(0.2, 14, -16.4))
dust(Atmos, "DustNave", CFrame.new(0.8, 11, -5.4))
dust(Atmos, "DustNaveN", CFrame.new(-0.6, 11, 10.6))
dust(Atmos, "DustCemetery", CFrame.new(-14, 2.2, -58))
local moonAnchor = box(Atmos, "MoonAnchor", Vector3.new(1, 1, 1), CFrame.new(14, 60, 26) * CFrame.Angles(-0.72, 0.55, 0), nil,
		{ Transparency = 1, CanCollide = false, CastShadow = false, CanQuery = false, CanTouch = false })
local moon = ensure(moonAnchor, "Moonlight", "SpotLight")
moon.Face = Enum.NormalId.Bottom
moon.Angle = 60
moon.Range = 220
moon.Brightness = 0.5
moon.Color = Color3.fromRGB(185, 205, 255)
moon.Shadows = true

-- ============ night lighting (Atmosphere untouched) ============
local Lighting = game:GetService("Lighting")
local function lightProp(prop, value)
	if Lighting[prop] ~= value then Lighting[prop] = value end
end
lightProp("ClockTime", 0.2)
lightProp("Brightness", 1.1)
lightProp("Ambient", Color3.fromRGB(28, 32, 44))
lightProp("OutdoorAmbient", Color3.fromRGB(38, 46, 66))
lightProp("FogColor", Color3.fromRGB(20, 26, 40))
lightProp("FogStart", 90)
lightProp("FogEnd", 420)
lightProp("GlobalShadows", true)
for _, nm in { "RCM_Bloom", "RCM_Color" } do
	local oldFx = Lighting:FindFirstChild(nm)
	if oldFx then oldFx:Destroy() end
end
local bloom = Instance.new("BloomEffect")
bloom.Name = "RCM_Bloom"
bloom.Intensity = 0.35
bloom.Size = 24
bloom.Threshold = 0.92
bloom.Parent = Lighting
local cc = Instance.new("ColorCorrectionEffect")
cc.Name = "RCM_Color"
cc.Brightness = -0.03
cc.Contrast = 0.1
cc.Saturation = -0.12
cc.TintColor = Color3.fromRGB(214, 224, 255)
cc.Parent = Lighting

-- ============ QA summary ============
local counts, total = {}, 0
local sigs, dupes = {}, {}
for _, d in root:GetDescendants() do
	if d:IsA("BasePart") then
		total += 1
		local g = d:FindFirstAncestorOfClass("Model")
		while g and g.Parent ~= root do g = g.Parent end
		local nm = g and g.Name or "?"
		counts[nm] = (counts[nm] or 0) + 1
		local p, sz = d.Position, d.Size
		local sig = d.ClassName .. "|" .. math.floor(p.X * 4 + 0.5) .. "," .. math.floor(p.Y * 4 + 0.5) .. "," .. math.floor(p.Z * 4 + 0.5)
			.. "|" .. math.floor(sz.X * 4 + 0.5) .. "," .. math.floor(sz.Y * 4 + 0.5) .. "," .. math.floor(sz.Z * 4 + 0.5)
		if sigs[sig] then
			table.insert(dupes, d.Name)
		else
			sigs[sig] = true
		end
	end
end
local parts = {}
for k, v in counts do table.insert(parts, k .. "=" .. v) end
table.sort(parts)
print(("[QA] %s: %d parts | %s"):format(root.Name, total, table.concat(parts, ", ")))
if #dupes > 0 then
	print(("[QA] WARNING near-duplicate parts (%d): %s"):format(#dupes, table.concat(dupes, ", ", 1, math.min(8, #dupes))))
else
	print("[QA] no near-duplicate parts detected")
end
print("[QA] note: sloped slabs & rotated cylinders show fat boxes in overlap checks; seated joints there are by design")