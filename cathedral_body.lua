--------------------------------------------------------------------
-- RuinedCathedralMap — builder body (runs inside function(root))
--------------------------------------------------------------------
local rng = Random.new(1906)
local function jit(a) return (rng:NextNumber() * 2 - 1) * a end
local function rr(lo, hi) return lo + rng:NextNumber() * (hi - lo) end

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

local function cyl(parent, name, dia, len, cf, m, props) -- axis along local X
	local p = ensure(parent, name, "Part")
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(len, dia, dia)
	p.CFrame = cf
	return finish(p, m, props)
end

local function col(parent, name, dia, h, cf, m, props) -- vertical cylinder
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

-- ============ constants (everything below derives from these) ============
local GT = 0.125                 -- map ground top
local WT = 2                     -- wall thickness
local ARC = 6.5                  -- nave arcade line (x)
local EXW = ARC + 5 + WT         -- 13.5 nave block exterior half-width (5 = aisle width)
local ZF, ZFI = 16, 14           -- front wall exterior / interior faces
local ZN = -8                    -- nave exterior north end (aisle closing band)
local TZ0, TZ1 = -10, -23        -- crossing interior z
local TW0, TW1 = -8, -25         -- tower/transept exterior z
local FL = GT + 0.9              -- cathedral floor top
local S = 150                    -- map size

local Ground = ensure(root, "Ground", "Model")
local Cathedral = ensure(root, "Cathedral", "Model")
local Shell = ensure(Cathedral, "Shell", "Model")
local Roofs = ensure(Cathedral, "Roofs", "Model")
local FrontM = ensure(Cathedral, "Front", "Model")
local TowerM = ensure(Cathedral, "Tower", "Model")
local ApseM = ensure(Cathedral, "Apse", "Model")
local Cemetery = ensure(root, "Cemetery", "Model")
local Forest = ensure(root, "Forest", "Model")

-- ============ generic masonry pieces ============
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

-- w = {ow, y0, sill, spring, rise}; cf sits at ground on the wall centreline, local Z along the wall
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

-- walls run as bays; spec[i] = number (plain top) or {h=..., win={...}} (lancet) / {h=..., win={door=true}}
local function bayFor(parent, nm, thick, L, h, cf, m, win)
	if win == nil then
		box(parent, nm, Vector3.new(thick, h, L), cf * CFrame.new(0, h / 2, 0), m)
	elseif win.door then
		doorBay(parent, nm, thick, L, h, cf, m)
	else
		lancetBay(parent, nm, thick, L, h, cf, m, win)
	end
end

local function wallZ(parent, tag, x, z0, z1, spec, thick, m) -- along Z, x0 > z1
	local n = #spec
	local L = (z0 - z1) / n
	for i = 1, n do
		local s = spec[i]
		local h = type(s) == "number" and s or s.h
		bayFor(parent, tag .. i, thick, L, h, CFrame.new(x, GT, z0 - (i - 0.5) * L), m, type(s) == "table" and s.win or nil)
	end
end

local function wallX(parent, tag, z, x0, x1, spec, thick, m) -- along X
	local n = #spec
	local L = (x1 - x0) / n
	for i = 1, n do
		local s = spec[i]
		local h = type(s) == "number" and s or s.h
		bayFor(parent, tag .. i, thick, L, h, CFrame.new(x0 + (i - 0.5) * L, GT, z) * CFrame.Angles(0, math.pi / 2, 0), m, type(s) == "table" and s.win or nil)
	end
end

local function buttress(parent, name, cf, h, m)
	box(parent, name .. "A", Vector3.new(1.3, h * 0.55, 3), cf * CFrame.new(0.5, h * 0.275, 0), m)
	box(parent, name .. "B", Vector3.new(0.8, h * 0.45, 2.2), cf * CFrame.new(0.25, h * 0.55 + h * 0.225, 0), m)
	wedge(parent, name .. "C", Vector3.new(0.8, 0.3, 2.2), cf * CFrame.new(0.25, h + 0.15, 0) * CFrame.Angles(0, math.pi / 2, 0), m)
end

-- ============ ground, paths, plaza ============
box(Ground, "Turf", Vector3.new(S, 6, S), CFrame.new(0, GT - 3, 0), P.grass)
local patches = { { 0, -44, 30, 10 }, { 2, 34, 12, 6 }, { -24, 8, 16, 10 }, { 40, -18, 14, 10 } }
for i, pd in patches do
	box(Ground, "Patch" .. i, Vector3.new(pd[3], 0.04, pd[4]), CFrame.new(pd[1], GT + 0.02, pd[2]), P.grassDk, { CanCollide = false })
end
box(Ground, "PathMain1", Vector3.new(7, 0.12, 31), CFrame.new(2, GT + 0.06, 59.5), P.dirt)
box(Ground, "PathMain2", Vector3.new(6, 0.12, 12.5), CFrame.new(4, GT + 0.06, 37.75), P.dirt)
box(Ground, "Plaza", Vector3.new(18, 0.12, 10), CFrame.new(2, GT + 0.06, 26.5), P.dirt)
box(Ground, "PathSideA", Vector3.new(4.5, 0.12, 44.5), CFrame.new(26.5, GT + 0.06, 7.25), P.dirt)
box(Ground, "PathSideB", Vector3.new(4.5, 0.12, 39), CFrame.new(26.5, GT + 0.06, -34.5), P.dirt)
box(Ground, "PathPlazaLink", Vector3.new(13, 0.12, 4), CFrame.new(19.75, GT + 0.06, 29.5), P.dirt)
box(Ground, "PathGateLink", Vector3.new(15.75, 0.12, 3.5), CFrame.new(16.375, GT + 0.06, -54.5), P.dirt)
box(Ground, "PathCemInner", Vector3.new(13.5, 0.12, 3), CFrame.new(1.25, GT + 0.06, -54.5), P.dirt)
box(Ground, "Step1", Vector3.new(8, 0.3, 1.5), CFrame.new(0, GT + 0.3, 18.75), P.trim)
box(Ground, "Step2", Vector3.new(8, 0.3, 2), CFrame.new(0, GT + 0.6, 17), P.trim)

-- ============ plinth + floors ============
box(Shell, "PlinthNave", Vector3.new(EXW * 2, 0.9, 24), CFrame.new(0, GT + 0.45, 4), P.plinth)          -- z 16..-8
box(Shell, "PlinthCross", Vector3.new(17, 0.9, 17), CFrame.new(0, GT + 0.45, -16.5), P.plinth)          -- z -8..-25
box(Shell, "PlinthArmE", Vector3.new(13.5, 0.9, 17), CFrame.new(15.25, GT + 0.45, -16.5), P.plinth)
box(Shell, "PlinthArmW", Vector3.new(13.5, 0.9, 17), CFrame.new(-15.25, GT + 0.45, -16.5), P.plinth)
box(Shell, "PlinthChoir", Vector3.new(17, 0.9, 10), CFrame.new(0, GT + 0.45, -30), P.plinth)            -- z -25..-35
box(Shell, "PlinthApse", Vector3.new(13, 0.9, 4.4), CFrame.new(0, GT + 0.45, -37.2), P.plinth)
box(Shell, "PaveNaveC", Vector3.new(4.4, 0.06, 24), CFrame.new(0, FL + 0.03, 2), P.marble)
box(Shell, "PaveNaveE", Vector3.new(4.3, 0.06, 24), CFrame.new(4.35, FL + 0.03, 2), P.floor)
box(Shell, "PaveNaveW", Vector3.new(4.3, 0.06, 24), CFrame.new(-4.35, FL + 0.03, 2), P.floor)
box(Shell, "PaveAisleE", Vector3.new(5, 0.06, 22), CFrame.new(9, FL + 0.03, 3), P.floor)
box(Shell, "PaveAisleW", Vector3.new(5, 0.06, 22), CFrame.new(-9, FL + 0.03, 3), P.floor)
box(Shell, "PaveCross", Vector3.new(13, 0.06, 13), CFrame.new(0, FL + 0.03, -16.5), P.marble)
box(Shell, "PaveChoir", Vector3.new(13, 0.06, 8), CFrame.new(0, FL + 0.03, -29), P.marble)
box(Shell, "Dais", Vector3.new(7, 0.5, 5), CFrame.new(0, FL + 0.25, -30), P.marble)
box(Shell, "DaisStep", Vector3.new(7, 0.25, 1.2), CFrame.new(0, FL + 0.125, -26.9), P.marble)

-- ============ outer walls (ruined tops vary per bay) ============
local naveWin = { ow = 1.4, sill = 2.6, spring = 5.2, rise = 1.4 }
wallZ(Shell, "NaveWallE", 12.5, ZF, ZN, { 8.5, { h = 8, win = naveWin }, 9.5, 6.5, { h = 7.6, win = naveWin }, 9 }, WT, P.wall)
wallZ(Shell, "NaveWallW", -12.5, ZF, ZN, { 7.8, 9.2, { h = 8.8, win = naveWin }, { h = 7.2, win = naveWin }, 8.6, { h = 8.2, win = naveWin } }, WT, P.wall)
wallX(Shell, "AisleEndE", -9, 8.5, 11.5, { 8 }, WT, P.wall)
wallX(Shell, "AisleEndW", -9, -11.5, -8.5, { 7.5 }, WT, P.wall)

-- clerestory walls over the arcade line
local clWin = { ow = 1.8, y0 = 13, sill = 13.4, spring = 15.8, rise = 2 }
wallZ(Shell, "ClerestE", 7.5, ZFI, -10, { 19.5, { h = 18.6, win = clWin }, { h = 18.2, win = clWin }, 12.5, 15 }, WT, P.wall)
wallZ(Shell, "ClerestW", -7.5, ZFI, -10, { 19, { h = 18.4, win = clWin }, 13, { h = 18.8, win = clWin }, 16.5 }, WT, P.wall)
box(Shell, "TriforiumE", Vector3.new(WT, 2, 24), CFrame.new(7.5, 12, 2), P.wall2)
box(Shell, "TriforiumW", Vector3.new(WT, 2, 24), CFrame.new(-7.5, 12, 2), P.wall2)

-- front facade
local nich = { ow = 1.5, y0 = 0.5, sill = 2.8, spring = 8, rise = 1.9 }
wallX(FrontM, "Front", 15, -13.5, 13.5, { 18, { h = 18, win = nich }, { h = 18, win = { door = true } }, { h = 18, win = nich }, 18 }, WT, P.wall)
wedge(FrontM, "GableL", Vector3.new(WT, 8, 6.75), CFrame.new(-3.375, GT + 22, 15) * CFrame.Angles(0, -math.pi / 2, 0), P.wall)
wedge(FrontM, "GableR", Vector3.new(WT, 8, 6.75), CFrame.new(3.375, GT + 22, 15) * CFrame.Angles(0, math.pi / 2, 0), P.wall)
box(FrontM, "RoseBand", Vector3.new(7, 1.2, 2.2), CFrame.new(0, GT + 18.6, 15), P.trim)
for i = 1, 8 do
	local missing = (i == 6 or i == 7 or i == 8)
	if not missing then
		local a = (i - 0.5) * math.pi / 4
		box(FrontM, "Rose" .. i, Vector3.new(1.34, 0.9, 1.6),
			CFrame.new(math.cos(a) * 1.75, GT + 21 + math.sin(a) * 1.75, 15) * CFrame.Angles(0, 0, a + math.pi / 2), P.trim)
	end
end
box(FrontM, "RoseMullV", Vector3.new(0.25, 3.5, 1.2), CFrame.new(0, GT + 21, 15), P.trim)
box(FrontM, "RoseMullH", Vector3.new(3.5, 0.25, 1.2), CFrame.new(0, GT + 21, 15), P.trim)
box(FrontM, "GlassA", Vector3.new(1.1, 1.1, 0.12), CFrame.new(-0.8, GT + 21.8, 15), P.iron, { Transparency = 0.45, Color = Color3.fromRGB(150, 60, 50) })
box(FrontM, "GlassB", Vector3.new(1.1, 1.1, 0.12), CFrame.new(0.9, GT + 20.4, 15), P.iron, { Transparency = 0.45, Color = Color3.fromRGB(60, 80, 160) })

-- tower (crossing), jagged tops, one breached bay
wallX(TowerM, "TowerS", -9, -8.5, 8.5, { 24, 28, 13 }, WT, P.wall2)
wallX(TowerM, "TowerN", -24, -8.5, 8.5, { 23, { h = 27, win = { ow = 1.1, y0 = 18, sill = 18.4, spring = 21, rise = 1.5 } }, 18 }, WT, P.wall2)
wallZ(TowerM, "TowerE", 7.5, TZ0, TZ1, { 26, { h = 29, win = { ow = 1.1, y0 = 17, sill = 17.4, spring = 20, rise = 1.5 } }, 22 }, WT, P.wall2)
wallZ(TowerM, "TowerW", -7.5, TZ0, TZ1, { 21, { h = 27, win = { ow = 1.1, y0 = 17, sill = 17.4, spring = 20, rise = 1.5 } }, 25 }, WT, P.wall2)
for i, mx in { -2, 0.2, 2.2 } do
	box(TowerM, "Merlon" .. i, Vector3.new(1.3, 1.5, 1.6), CFrame.new(mx, GT + 27.75, -24), P.wall2)
end
box(TowerM, "MerlonFallen", Vector3.new(1.3, 1.5, 1.6), CFrame.new(1.4, GT + 0.55, -27.5) * CFrame.Angles(0.2, 0.6, 0.35), P.wall2)
box(TowerM, "TowerLedgeS", Vector3.new(0.25, 0.5, 17), CFrame.new(8.6, GT + 21.5, -16.5), P.trim)
box(TowerM, "TowerLedgeN", Vector3.new(0.25, 0.5, 9), CFrame.new(-8.6, GT + 21.5, -20), P.trim)

-- transept arms
local trWin = { ow = 3, y0 = 1.2, sill = 2.2, spring = 7.2, rise = 2.6 }
local smWin = { ow = 1.3, sill = 2.4, spring = 5, rise = 1.3 }
wallX(Shell, "ArmEEnd", -16.5, 20, 22, { 12, { h = 14.5, win = trWin }, 11 }, WT, P.wall)
wallX(Shell, "ArmWEnd", -16.5, -22, -20, { 11, { h = 13, win = trWin }, 12.5 }, WT, P.wall)
wallX(Shell, "ArmES", -9, 8.5, 20, { 10.5, { h = 9, win = smWin }, 11 }, WT, P.wall)
wallX(Shell, "ArmEN", -24, 8.5, 20, { { h = 11.5, win = smWin }, 12.5, 9.5 }, WT, P.wall)
wallX(Shell, "ArmWS", -9, -20, -8.5, { 9.5, 11, 10 }, WT, P.wall)
wallX(Shell, "ArmWN", -24, -20, -8.5, { 10.5, 8.5, { h = 11.5, win = smWin } }, WT, P.wall)

-- choir + apse
wallZ(Shell, "ChoirE", 7.5, -25, -33, { 14, 11, 15 }, WT, P.wall)
wallZ(Shell, "ChoirW", -7.5, -25, -33, { 13.5, 12, 9 }, WT, P.wall)
wallX(Shell, "ChoirClose", -34, -8.5, 8.5, { 13.5, { h = 15, win = { ow = 3.4, y0 = 1, sill = 1.2, spring = 6.5, rise = 2.2 } }, 13.5 }, WT, P.wall)
wallX(ApseM, "ApseC", -39.4, -3.9, 3.9, { 16, { h = 16, win = { ow = 3.4, y0 = 1, sill = 1.6, spring = 7, rise = 2.8 } }, 12.5 }, WT, P.wall)
box(ApseM, "ApseDiagE", Vector3.new(WT, 14.5, 4.3), CFrame.new(5.2, GT + 7.25, -36.7) * CFrame.Angles(0, 0.653, 0), P.wall)
box(ApseM, "ApseDiagW", Vector3.new(WT, 11.5, 4.3), CFrame.new(-5.2, GT + 5.75, -36.7) * CFrame.Angles(0, -0.653, 0), P.wall)

-- arcade: piers + arches down the nave
for sd = -1, 1, 2 do
	local ax = sd * ARC
	for i = 0, 5 do
		local z = 14 - i * 4.8
		local pf = CFrame.new(ax, FL, z)
		box(Shell, `PierBase` .. (sd < 0 and "W" or "E") .. i, Vector3.new(2.2, 0.8, 2.2), pf * CFrame.new(0, 0.4, 0), P.trim)
		col(Shell, `Pier` .. (sd < 0 and "W" or "E") .. i, 1.6, 7.4, pf * CFrame.new(0, 0.8 + 3.7, 0), P.wall2)
		box(Shell, `PierCap` .. (sd < 0 and "W" or "E") .. i, Vector3.new(2.2, 0.7, 2.2), pf * CFrame.new(0, 8.55, 0), P.trim)
		if i < 5 then
			local af = CFrame.new(ax, FL + 8.9, z - 2.4) * CFrame.Angles(0, math.pi / 2, 0)
			archParts(Shell, `Arcade` .. (sd < 0 and "W" or "E") .. i, af, 2.6, 1.6, 2.2, 0.7, P.wall2)
		end
	end
end

-- buttresses (aisle walls, front corners, fallen one)
local bz = { 14, 9.2, 4.4, -0.4, -5.2, -10 }
local bhE = { 8.5, 8.5, 5.5, 8.5, 8.5, 7 }
local bhW = { 8, 8.5, 8, 6, 8.5, 8 }
for i = 1, 6 do
	buttress(Shell, `ButtE` .. i, CFrame.new(13.5, GT, bz[i]), bhE[i], P.wall2)
	buttress(Shell, `ButtW` .. i, CFrame.new(-13.5, GT, bz[i]) * CFrame.Angles(0, math.pi, 0), bhW[i], P.wall2)
end
buttress(FrontM, "CornerButtE", CFrame.new(13.3, GT, 15.3) * CFrame.Angles(0, -math.pi / 4, 0), 11, P.wall2)
buttress(FrontM, "CornerButtW", CFrame.new(-13.3, GT, 15.3) * CFrame.Angles(0, math.pi / 4, 0), 11, P.wall2)
buttress(TowerM, "CornerButtNE", CFrame.new(-8.3, GT, -24.7) * CFrame.Angles(0, -math.pi / 4, 0), 18, P.wall2)
buttress(TowerM, "CornerButtNW", CFrame.new(8.3, GT, -24.7) * CFrame.Angles(0, math.pi / 4, 0), 15, P.wall2)
slabBetween(Shell, "ButtFallen", Vector3.new(-16.2, GT + 0.7, -1.5), Vector3.new(-12.4, GT + 1.3, 1.5), 2.4, 1.2, P.wall2)

-- ============ roofs (state tables: true / "half" / false) ============
local function roofBay(parent, name, a, b, wide, m)
	slabBetween(parent, name, a, b, wide, 0.5, m)
end
-- aisle shed roofs
local aisleE = { true, true, false, true, "half", true }
local aisleW = { true, false, true, "half", true, true }
for i = 1, 6 do
	local zc = 14 - (i - 0.5) * 4 - 2
	zc = 12 - (i - 1) * 4
	if aisleE[i] then
		local bb = aisleE[i] == "half" and Vector3.new(11.3, 11.1, zc) or Vector3.new(13.9, 9.2, zc)
		roofBay(Roofs, `AisleRoofE` .. i, Vector3.new(8.6, 13, zc), bb, 4.3, P.roof)
	end
	if aisleW[i] then
		local bb = aisleW[i] == "half" and Vector3.new(-11.3, 11.1, zc) or Vector3.new(-13.9, 9.2, zc)
		roofBay(Roofs, `AisleRoofW` .. i, Vector3.new(-8.6, 13, zc), bb, 4.3, P.roof)
	end
end
-- nave gable (5 bays)
local naveS = { true, true, "half", true, false }
local naveN = { false, true, true, "half", true }
for i = 1, 5 do
	local zc = 11.6 - (i - 1) * 4.8
	if naveS[i] then
		local bb = naveS[i] == "half" and Vector3.new(4, 21.7, zc) or Vector3.new(7.9, 19, zc)
		roofBay(Roofs, `NaveRoofS` .. i, bb, Vector3.new(0, 24.5, zc), 5.05, P.roof)
	end
	if naveN[i] then
		local bb = naveN[i] == "half" and Vector3.new(-4, 21.7, zc) or Vector3.new(-7.9, 19, zc)
		roofBay(Roofs, `NaveRoofN` .. i, bb, Vector3.new(0, 24.5, zc), 5.05, P.roof)
	end
end
box(Roofs, "RidgeBeam", Vector3.new(0.8, 1, 25), CFrame.new(0, 25, 2), P.timber)
-- transept gables (2 bays each slope)
local function armRoofs(tag, sx)
	local stS = sx > 0 and { true, false } or { false, "half" }
	local stN = sx > 0 and { true, true } or { true, false }
	for i = 1, 2 do
		local xc = sx * (11.875 + (i - 1) * 6.75)
		if stS[i] then
			local bb = stS[i] == "half" and Vector3.new(xc, 13.3, -12.5) or Vector3.new(xc, 11, -8.4)
			roofBay(Roofs, tag .. "S" .. i, bb, Vector3.new(xc, 15.5, -16.5), 6.75, P.roof)
		end
		if stN[i] then
			local bb = stN[i] == "half" and Vector3.new(xc, 13.3, -20.5) or Vector3.new(xc, 11, -24.6)
			roofBay(Roofs, tag .. "N" .. i, bb, Vector3.new(xc, 15.5, -16.5), 6.75, P.roof)
		end
	end
	box(Roofs, tag .. "Ridge", Vector3.new(13.5, 0.9, 0.8), CFrame.new(sx * 15.25, 15.9, -16.5), P.timber)
end
armRoofs("ArmRoofE", 1)
armRoofs("ArmRoofW", -1)
-- choir gable (2 bays)
local choirS = { true, false }
local choirN = { false, "half" }
for i = 1, 2 do
	local zc = -27.5 - (i - 1) * 5
	if choirS[i] then roofBay(Roofs, `ChoirRoofS` .. i, Vector3.new(7.9, 12.5, zc), Vector3.new(0, 17.5, zc), 5.25, P.roof) end
	if choirN[i] then
		local bb = choirN[i] == "half" and Vector3.new(-4, 15, zc) or Vector3.new(-7.9, 12.5, zc)
		roofBay(Roofs, `ChoirRoofN` .. i, bb, Vector3.new(0, 17.5, zc), 5.25, P.roof)
	end
end

-- crossing rubble + fallen bell
for i = 1, 6 do
	local w = rr(1.2, 2.6)
	box(Shell, `RubbleX` .. i, Vector3.new(w, w * 0.5, w * rr(0.7, 1.2)),
		CFrame.new(jit(4), FL + w * 0.1, -12 + (i - 1) * 1.7 + jit(1)) * CFrame.Angles(jit(0.4), rng:NextNumber() * math.pi, jit(0.4)), P.wall2)
end
local bellF = CFrame.new(2.5, FL + 1.2, -18) * CFrame.Angles(0, 0.5, 0.45)
col(Shell, "Bell", 2.4, 2.2, bellF * CFrame.new(0, 0, 0), P.bronze)
col(Shell, "BellLip", 2.8, 0.5, bellF * CFrame.new(0, -1.1, 0), P.bronze)

-- ============ cemetery ============
box(Cemetery, "CemGround", Vector3.new(41, 0.55, 23), CFrame.new(-13.175, GT - 0.225, -58), P.grassDk)
local function cemWall(parent, name, size, cf, h)
	box(parent, name, size, cf, P.plinth)
	if h > 1.6 then box(parent, name .. "Cap", Vector3.new(size.X + 0.2, 0.15, size.Z + 0.2), cf * CFrame.new(0, h / 2 + 0.075, 0), P.rock) end
end
for i = 1, 7 do
	local x = -34 + (i - 0.5) * 6
	local h = ({ 2.1, 1.7, 2.3, 1.3, 2.0, 1.8, 2.2 })[i]
	cemWall(Cemetery, `CemS` .. i, Vector3.new(6, h, 0.7), CFrame.new(x, GT + h / 2, -46.35), h)
	local hn = ({ 2, 2.4, 1.6, 2.2, 1.8, 2.1, 1.7 })[i]
	cemWall(Cemetery, `CemN` .. i, Vector3.new(6, hn, 0.7), CFrame.new(x, GT + hn / 2, -69.65), hn)
end
cemWall(Cemetery, "CemE1", Vector3.new(0.7, 1.9, 6), CFrame.new(8.35, GT + 0.95, -49), 1.9)
cemWall(Cemetery, "CemE2", Vector3.new(0.7, 2.1, 6), CFrame.new(8.35, GT + 1.05, -59), 2.1)
cemWall(Cemetery, "CemE3", Vector3.new(0.7, 1.5, 6), CFrame.new(8.35, GT + 0.75, -65), 1.5)
cemWall(Cemetery, "CemE4", Vector3.new(0.7, 0.8, 2), CFrame.new(8.35, GT + 0.4, -69), 0.8)
for i = 1, 4 do
	local z = -46 - (i - 0.5) * 6
	local h = ({ 1.8, 2.2, 1.4, 2 })[i]
	cemWall(Cemetery, `CemW` .. i, Vector3.new(0.7, h, 6), CFrame.new(-34.35, GT + h / 2, z), h)
end
for i, cp in { { -34, -46 }, { 8, -46 }, { -34, -70 }, { 8, -70 } } do
	box(Cemetery, `CemPost` .. i, Vector3.new(1.2, 2.7, 1.2), CFrame.new(cp[1], GT + 1.35, cp[2]), P.rock)
	box(Cemetery, `CemPostCap` .. i, Vector3.new(1.5, 0.25, 1.5), CFrame.new(cp[1], GT + 2.8, cp[2]), P.rock)
end
box(Cemetery, "GatePostS", Vector3.new(1.3, 3.6, 1.3), CFrame.new(8.35, GT + 1.8, -51.5), P.rock)
wedge(Cemetery, "GatePostCapS", Vector3.new(1.6, 0.5, 1.6), CFrame.new(8.35, GT + 3.85, -51.5) * CFrame.Angles(0, math.pi / 4, 0), P.rock)
box(Cemetery, "GatePostN", Vector3.new(1.3, 3.2, 1.3), CFrame.new(8.35, GT + 1.6, -56.5), P.rock)

local function grave(parent, name, x, z, yaw, kind)
	local f = CFrame.new(x, GT, z) * CFrame.Angles(0, math.rad(yaw), 0)
	local h = rr(1.7, 2.3)
	local m = rng:NextNumber() < 0.5 and P.grave or P.grave2
	if kind == "slab" then
		box(parent, name, Vector3.new(1.4, h, 0.32), f * CFrame.new(0, h / 2 - 0.15, 0) * CFrame.Angles(jit(0.05), 0, jit(0.05)), m)
		box(parent, name .. "Base", Vector3.new(1.7, 0.3, 0.55), f * CFrame.new(0, 0.05, 0), P.rock)
	elseif kind == "cross" then
		box(parent, name .. "U", Vector3.new(0.38, h + 0.6, 0.38), f * CFrame.new(0, (h + 0.6) / 2 - 0.15, 0) * CFrame.Angles(jit(0.06), 0, jit(0.06)), m)
		box(parent, name .. "Arm", Vector3.new(1.5, 0.38, 0.38), f * CFrame.new(0, h * 0.62, 0), m)
		box(parent, name .. "Base", Vector3.new(1.3, 0.35, 1.3), f * CFrame.new(0, 0.03, 0), P.rock)
	elseif kind == "chip" then
		box(parent, name, Vector3.new(1.4, h, 0.32), f * CFrame.new(0, h / 2 - 0.15, 0), m)
		box(parent, name .. "Chip", Vector3.new(0.6, 0.5, 0.3), f * CFrame.new(0.35, h - 0.35, 0) * CFrame.Angles(0, 0, 0.5), m)
	elseif kind == "lean" then
		box(parent, name, Vector3.new(1.4, h, 0.32), f * CFrame.new(0, h / 2 - 0.35, 0.18) * CFrame.Angles(jit(0.05), 0, rr(0.16, 0.26)), m)
		box(parent, name .. "Base", Vector3.new(1.7, 0.3, 0.55), f * CFrame.new(0, 0.05, 0), P.rock)
	elseif kind == "fall" then
		box(parent, name, Vector3.new(1.4, 0.32, h), f * CFrame.new(0, 0.16, h * 0.2) * CFrame.Angles(jit(0.08), 0, jit(0.08)), m)
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
	{ -30, -62, 8, "fall" }, { -23, -63, -12, "ped" }, { -17, -61, 18, "slab" }, { -11, -64, -7, "cross" },
	{ -26, -67, 10, "chip" }, { -20, -66, -18, "slab" }, { -13, -68, 5, "lean" }, { -6, -52, -10, "slab" },
	{ -3, -57, 14, "cross" }, { -7, -62, -4, "fall" }, { -1, -65, 9, "slab" }, { -33, -58, -14, "slab" },
}
for i, gd in graves do
	grave(Cemetery, `Grave` .. i, gd[1], gd[2], gd[3], gd[4])
end
-- tomb monument
box(Cemetery, "TombPlinth", Vector3.new(6, 1, 3), CFrame.new(-8, GT + 0.5, -66), P.rock)
for i, cp in { { -10.5, -67.2 }, { -5.5, -67.2 }, { -10.5, -64.8 }, { -5.5, -64.8 } } do
	box(Cemetery, `TombPost` .. i, Vector3.new(0.7, 1.6, 0.7), CFrame.new(cp[1], GT + 1.8, cp[2]), P.rock)
end
box(Cemetery, "TombLid", Vector3.new(5.6, 0.45, 2.6), CFrame.new(-8, GT + 2.75, -66), P.marble)
box(Cemetery, "TombEffigy", Vector3.new(4, 0.3, 1.3), CFrame.new(-8.2, GT + 3.1, -66) * CFrame.Angles(0, 0.06, 0.03), P.grave2)
-- broken column monument
box(Cemetery, "ColBase", Vector3.new(2.2, 0.6, 2.2), CFrame.new(-31, GT + 0.3, -48), P.rock)
col(Cemetery, "ColShaft", 1.4, 3.2, CFrame.new(-31, GT + 2.1, -48) * CFrame.Angles(0.1, 0.4, 0.08), P.grave)
cyl(Cemetery, "ColCap", 1.7, 0.4, CFrame.new(-30.7, GT + 3.75, -47.8) * CFrame.Angles(0.1, 0.4, 0.08), P.grave)
cyl(Cemetery, "ColDrum", 1.4, 1.1, CFrame.new(-29, GT + 0.4, -46.6) * CFrame.Angles(0, 0.3, math.pi / 2), P.grave)

-- ============ forest ============
local function tree(parent, name, x, z, kind, s)
	s = s or 1
	local g = ensure(parent, name, "Model")
	local f = CFrame.new(x, GT - 0.25, z) * CFrame.Angles(jit(0.06), rng:NextNumber() * 6.28, jit(0.06))
	if kind == "oak" then
		local h = rr(9, 12) * s
		col(g, "Trunk", rr(1.7, 2.3) * s, h, f * CFrame.new(0, h / 2, 0), P.bark)
		col(g, "TrunkTop", 1.1 * s, 2.6, f * CFrame.new(jit(0.4), h + 1, jit(0.4)) * CFrame.Angles(jit(0.2), 0, jit(0.2)), P.barkDk)
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
				f * CFrame.new(pd[1], pd[2], pd[3]) * CFrame.Angles(0, rng:NextNumber() * math.pi, jit(0.12)), mats[i])
		end
	elseif kind == "pine" then
		local h = rr(11, 15) * s
		col(g, "Trunk", rr(1.1, 1.5) * s, h, f * CFrame.new(0, h / 2, 0), P.barkDk)
		local widths = { 8.5, 6.8, 5.2, 3.6 }
		for i, w in widths do
			box(g, `Tier` .. i, Vector3.new(w * s, 1.9, w * s),
				f * CFrame.new(0, h * (0.35 + 0.16 * (i - 1)), 0) * CFrame.Angles(0, (i % 2) * math.pi / 4 + jit(0.2), 0), i % 2 == 0 and P.leafDk or P.leaf)
		end
	elseif kind == "birch" then
		local h = rr(8, 10.5) * s
		col(g, "Trunk", 0.9 * s, h, f * CFrame.new(0, h / 2, 0), P.birch)
		box(g, "Mark", Vector3.new(0.98, 0.5, 0.98), f * CFrame.new(0.05, h * 0.5, 0), P.barkDk, { Transparency = 0.35 })
		for i = 1, 2 do
			local a = rng:NextNumber() * 6.28
			rodBetween(g, `Branch` .. i, (f * CFrame.new(0, h - 1, 0)).Position, (f * CFrame.new(math.cos(a) * 2.4, h + 0.6, math.sin(a) * 2.4)).Position, 0.4, P.birch)
		end
		box(g, "Canopy1", Vector3.new(6 * s, 2, 5 * s), f * CFrame.new(0, h + 1.6, 0) * CFrame.Angles(0, rng:NextNumber() * math.pi, 0), P.leafLt)
		box(g, "Canopy2", Vector3.new(4.5 * s, 1.8, 4 * s), f * CFrame.new(1.4, h + 3, -0.8) * CFrame.Angles(0, rng:NextNumber() * math.pi, jit(0.1)), P.leaf)
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
	{ -26, 54, "pine" }, { 16, 60, "oak" }, { 34, 50, "birch" }, { 2, 68, "oak" }, { -50, 62, "pine" },
	{ -50, -58, "snag" }, { 64, -62, "pine" }, { -16, -74.5, "oak" }, { 24, -64, "birch" },
}
for i, td in trees do
	tree(Forest, `Tree` .. i, td[1], td[2], td[3], rr(0.9, 1.15))
end
local function stump(parent, name, x, z)
	local g = ensure(parent, name, "Model")
	local d = rr(2, 2.8)
	col(g, "Stump", d, 1.2, CFrame.new(x, GT + 0.35, z) * CFrame.Angles(jit(0.06), 0, jit(0.06)), P.bark)
	for i = 1, 3 do
		local a = rng:NextNumber() * 6.28
		rodBetween(g, `Root` .. i, Vector3.new(x, GT + 0.5, z),
			Vector3.new(x + math.cos(a) * rr(1.8, 2.6), GT - 0.25, z + math.sin(a) * rr(1.8, 2.6)), 0.45, P.barkDk)
	end
	box(g, "Top", Vector3.new(d * 0.7, 0.14, d * 0.7), CFrame.new(x, GT + 1.02, z) * CFrame.Angles(0, jit(1), 0), P.plank)
end
stump(Forest, "Stump1", -44, 30)
stump(Forest, "Stump2", 30, 22)
local function rocks(parent, name, x, z, n, s)
	local g = ensure(parent, name, "Model")
	for i = 1, n do
		local w = rr(1.6, 3.4) * s
		box(g, `Rock` .. i, Vector3.new(w, w * rr(0.55, 0.8), w * rr(0.7, 1.1)),
			CFrame.new(x + jit(2.2) * s, GT + w * 0.18, z + jit(2.2) * s)
				* CFrame.Angles(jit(0.35), rng:NextNumber() * math.pi, jit(0.35)), P.rock)
	end
	box(g, "Moss", Vector3.new(rr(1.5, 2.5), 0.1, rr(1.5, 2.5)),
		CFrame.new(x + jit(1), GT + 0.12, z + jit(1)) * CFrame.Angles(0, rng:NextNumber() * math.pi, 0), P.leafDk, { CanCollide = false })
end
local rockSpots = { { -30, 8, 3, 1 }, { -28, -18, 2, 1.2 }, { 24, 4, 2, 1 }, { 30, -18, 3, 1 }, { 44, 8, 2, 1.1 }, { -14, 40, 2, 0.9 }, { 12, 38, 2, 0.8 }, { -44, -20, 3, 1.1 }, { 54, -30, 2, 1 }, { -60, 48, 3, 1.2 }, { 14, -56, 2, 0.8 }, { -30, -44, 2, 0.9 } }
for i, rd in rockSpots do
	rocks(Forest, `Rocks` .. i, rd[1], rd[2], rd[3], rd[4])
end
-- dead tree inside cemetery
tree(Cemetery, "CemTree", -16, -48.5, "snag", 0.8)

-- ============ QA summary ============
local counts, total = {}, 0
for _, d in root:GetDescendants() do
	if d:IsA("BasePart") then
		total += 1
		local g = d:FindFirstAncestorOfClass("Model")
		while g and g.Parent ~= root do g = g.Parent end
		local nm = g and g.Name or "?"
		counts[nm] = (counts[nm] or 0) + 1
	end
end
local parts = {}
for k, v in counts do table.insert(parts, k .. "=" .. v) end
table.sort(parts)
print(("[QA] %s: %d parts | %s"):format(root.Name, total, table.concat(parts, ", ")))