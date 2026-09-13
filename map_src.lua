--=====================================================================================
-- RUINED CATHEDRAL  --  a 150 x 150 stud fantasy map, generated as one script.
-- Workspace.RuinedCathedralMap.  Re-runnable: the root is rebuilt, never stacked.
--
-- 1. MASSES (studs; ground top y=0; map centred on the origin; the cathedral's long axis runs
--    on Z, its entrance front facing -Z, the apse facing +Z, the cemetery behind the apse.)
--      nave        42 wide x 46 long x 28 tall  (walls y 3..31, ridge 40)  -- the dominant mass
--      towers      two 10 x 10 shafts on the west front corners: -X one standing to 46 with an
--                  open belfry and a broken crown, +X one sheared off at 27 with a breach
--      aisles      6 wide, wall top 14, lean-to roofs climbing to 18.5 against the nave
--      apse        half-octagon, 16 wide, out to z=30, wall top 23, roof gone
--      porch       2 columns + broken lintel in the recess between the towers, broad worn steps
--      cemetery    irregular 70 x 36 field of stones behind the apse (z 34..68)
--      forest      ~24 trees ringing the site, crowns 18-30 up, deadwood mixed in
--    From the FRONT (-Z): two unequal towers, a gable between them, a dark arched doorway, the
--    wheel window above it, the porch fragment in front. From ABOVE: a Latin-cross footprint,
--    a striped ridge with two long holes in the +X slope and one in the -X slope, a stipple of
--    gravestones behind the apse, a ring of crowns at the map edge.
--
-- 2. STRUCTURE (every other dimension is arithmetic on these)
--      NAVE_HALF 9, PIER 3, AISLE_W 6, WALL 3 -> OUT_HALF 21 (42 wide overall)
--      BAYS 5, BAY 8 -> nave 40 long, arcade piers and aisle buttresses on every bay line
--      AISLE_TOP 14, AISLE_HI 18.5 (lean-to against the nave wall), NAVE_TOP 31, RIDGE 40
--      PLINTH_TOP 3 (the platform the whole cathedral stands on), FLOOR 3.12 (tiles on it)
--    Walls carry roofs, piers carry the arcade arches (voussoir runs), buttresses brace the
--    aisle walls into the plinth, the towers carry the west front, the nave walls carry the
--    clerestory and the roof. Nothing is held up by anything that is not modelled under it.
--
-- 3. ACCESS (a player is 5 tall and 2 wide; steps are 1 rise on a 1.5 tread)
--      ground -> porch landing   3 steps, 1 x 1.5, 12 wide, x -6..6, z -38..-35
--      landing -> nave           the great west door, 8 wide x 12 tall, x -4..4, z -23..-20
--      nave -> +X aisle          4 arcade openings, 6.25 wide, springing 14.12, apex 17.6
--      nave -> -X aisle          the same four, mirrored
--      nave -> apse              apse arch, 12 wide, springing 15.1, apex 19.5
--      +X aisle -> outside       side door, 4 wide x 8 tall, in the aisle wall at z 6..10
--      -X aisle -> tower base    doorway 4 x 8 through the west wall at x -18..-13.6
--      +X aisle -> broken tower  breach 5 wide x 9 tall in the tower's west wall at z -31..-26
--      +X aisle wall breach      8 wide x 11 tall collapse at z -6..2 (rubble ramp inside it)
--      cemetery                  walk round the +X side of the apse; the boundary wall has a
--                                10 wide gap on its west side and 8 wide on its south side
--      SEALED ON PURPOSE: the two towers' upper stages (their stairs came down with the belfry
--      floor) and the space above the apse vault. Nothing else is closed.
--
-- 4. PALETTE AND PLACEMENT  (one cool stone family, warm wood and brass as the accents)
--      STONE
--      wall    Limestone    (124,121,114)  every wall plane above the plinth band
--      plinth  Cobblestone  ( 72, 72, 68)  platform slab, lowest 3 studs of every wall, pier
--                                          bases, rubble, buttress footings, boundary wall
--      trim    Sandstone    (158,150,132)  sills, quoins, string courses, capitals, voussoirs,
--                                          impost blocks, gravestones, altar, steps
--      roof    Slate        ( 50, 52, 58)  nave slopes, aisle lean-tos, ridge caps, roof slabs
--      floor   Marble       (128,124,116)  the interior floor field
--      flag    Slate        ( 74, 74, 80)  the processional path and floor border band only
--      brass   Metal        (152,116, 56)  lantern frames, candlesticks, sconces, censer, hilt
--      iron    Metal        ( 86, 90, 98)  chains, gate, hinges, blade, nails, grave rail
--      bone    Limestone    (196,190,170)  the soldier's bones, a few skulls on graves
--      LIFE
--      ground  Ground       ( 60, 70, 48)  the map floor slab and everything under the forest
--      dirt    Ground       ( 86, 70, 50)  worn paths, grave earth, the clearing by the door
--      moss    Grass        ( 78, 96, 54)  overgrowth patches, wall creep, grave tops
--      leaf    Grass        ( 46, 74, 44)  tree crowns, bushes, ferns, ivy, vines
--      bark    Wood         ( 62, 48, 34)  trunks, roots, branches, logs, pews, rafters, boots
--    Dark (roof/leaf/ground), mid (wall/floor), light (trim/bone), warm (brass/bark) -- no
--    material on more than half the parts, and a role change marks a thing change.
--
-- 5. VARIETY  Damage is data, not a second code path: per-bay roof presence tables, per-buttress
--    heights, per-grave tilts. Trees come in three recipes (broadleaf / deadwood / conifer) with
--    seeded size and rotation jitter in a real range, placed by rejection sampling with keep-out
--    boxes so no two stand in a row.
--=====================================================================================

local PROUD = 0.2     -- how far trim stands off the surface it decorates
local EPS = 0.06      -- how much a layer differs from the one under it, so no two faces coincide

local RNG = Random.new(1906)
local function jit(a) return (RNG:NextNumber() * 2 - 1) * a end
local function jitAbs(a) return RNG:NextNumber() * a end
local function chance(p) return RNG:NextNumber() < p end

-- One helper per role lookup: geometry asks for a role, never for a raw material.
local P = {
	-- STONE
	wall   = { Enum.Material.Limestone,   Color3.fromRGB(124, 121, 114) },
	plinth = { Enum.Material.Cobblestone, Color3.fromRGB( 72,  72,  68) },
	trim   = { Enum.Material.Sandstone,   Color3.fromRGB(158, 150, 132) },
	roof   = { Enum.Material.Slate,       Color3.fromRGB( 50,  52,  58) },
	floor  = { Enum.Material.Marble,      Color3.fromRGB(128, 124, 116) },
	flag   = { Enum.Material.Slate,       Color3.fromRGB( 74,  74,  80) },
	brass  = { Enum.Material.Metal,       Color3.fromRGB(152, 116,  56) },
	iron   = { Enum.Material.Metal,       Color3.fromRGB( 86,  90,  98) },
	bone   = { Enum.Material.Limestone,   Color3.fromRGB(196, 190, 170) },
	-- LIFE
	ground = { Enum.Material.Ground,      Color3.fromRGB( 60,  70,  48) },
	dirt   = { Enum.Material.Ground,      Color3.fromRGB( 86,  70,  50) },
	moss   = { Enum.Material.Grass,       Color3.fromRGB( 78,  96,  54) },
	leaf   = { Enum.Material.Grass,       Color3.fromRGB( 46,  74,  44) },
	bark   = { Enum.Material.Wood,        Color3.fromRGB( 62,  48,  34) },
}

local function ensure(parent, name, class)
	local found = parent:FindFirstChild(name)
	if found and found.ClassName ~= class then
		found:Destroy()
		found = nil
	end
	if not found then
		found = Instance.new(class)
		found.Name = name
		found.Parent = parent
	end
	return found
end

local function model(parent, name)
	return ensure(parent, name, "Model")
end

local function box(parent, name, size, cf, role)
	local p = ensure(parent, name, "Part")
	if p.Shape ~= Enum.PartType.Block then p.Shape = Enum.PartType.Block end
	p.Size = Vector3.new(math.max(size.X, 0.12), math.max(size.Y, 0.12), math.max(size.Z, 0.12))
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = true
	p.Transparency = 0
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	if role then p.Material, p.Color = role[1], role[2] end
	return p
end

-- A cylinder's own axis is X, so every round thing states its axis by how it is turned.
local function cyl(parent, name, r, len, cf, role)
	local p = ensure(parent, name, "Part")
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(math.max(len, 0.12), r * 2, r * 2)
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = true
	p.Transparency = 0
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	if role then p.Material, p.Color = role[1], role[2] end
	return p
end

local function col(parent, name, r, h, cf, role)  -- vertical post
	return cyl(parent, name, r, h, cf * CFrame.Angles(0, 0, math.pi / 2), role)
end

local function rod(parent, name, r, len, cf, role)  -- axis through the wall (Z)
	return cyl(parent, name, r, len, cf * CFrame.Angles(0, math.pi / 2, 0), role)
end

local function wedge(parent, name, size, cf, role)  -- roofs and ramps only
	local p = ensure(parent, name, "WedgePart")
	p.Size = Vector3.new(math.max(size.X, 0.12), math.max(size.Y, 0.12), math.max(size.Z, 0.12))
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = true
	p.Transparency = 0
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	if role then p.Material, p.Color = role[1], role[2] end
	return p
end

local function beamBetween(parent, name, a, b, w, h, role)  -- box with Z along a -> b
	local mid, len = (a + b) / 2, (b - a).Magnitude
	return box(parent, name, Vector3.new(w, h or w, len), CFrame.lookAt(mid, b), role)
end

local function rodBetween(parent, name, a, b, r, role)  -- cylinder with X along a -> b
	local mid, len = (a + b) / 2, (b - a).Magnitude
	return cyl(parent, name, r, len, CFrame.lookAt(mid, b) * CFrame.Angles(0, math.pi / 2, 0), role)
end

-- u, v in -1..1 across a surface top, kept inside by margin; the prop's bottom lands on the top face.
local function placeOn(surface, size, u, v, margin)
	local m = margin or 0.3
	local sx, sz = surface.Size.X / 2 - size.X / 2 - m, surface.Size.Z / 2 - size.Z / 2 - m
	local x = u * math.max(sx, 0)
	local z = v * math.max(sz, 0)
	return surface.CFrame * CFrame.new(x, surface.Size.Y / 2 + size.Y / 2, z)
end

-- An arch: a run of voussoirs, each rotated so its long axis is tangent to the curve, each
-- overlapping its neighbour so there is no slit between them. frame is the springing line.
local function arch(parent, name, frame, span, rise, depth, thick, n, role, keystone)
	local r = (span * span / 4 + rise * rise) / (2 * rise)
	local cy = rise - r
	local a0 = math.acos(math.clamp((span / 2) / r, -1, 1))
	local step = (math.pi - 2 * a0) / n
	local seg = 2 * r * math.sin(step / 2) + PROUD
	local keyAt = math.ceil(n / 2)
	for i = 1, n do
		local a = a0 + (i - 0.5) * step
		local t = thick
		if keystone and i == keyAt then t = thick + 0.5 end
		local cf = frame * CFrame.new(0, cy, 0) * CFrame.Angles(0, 0, a) * CFrame.new(r - thick / 2, 0, 0)
		box(parent, string.format("%s%d", name, i), Vector3.new(t, seg, depth), cf, role)
	end
	return r, cy
end

-- A straight wall as a fill around its openings. Local frame: X along the wall (centred on the
-- frame), Y up from the frame origin, Z through the thickness. Every piece's edge derives from
-- an opening edge, and neighbours butt exactly, so no two pieces share a face plane.
local function wallWith(parent, name, frame, length, height, thick, openings, role, trimRole)
	local list = {}
	for _, o in ipairs(openings or {}) do table.insert(list, o) end
	table.sort(list, function(a, b) return a.u < b.u end)
	local n = 0
	local function piece(a, b, y0, y1, t, r, tag)
		if b - a < 0.05 or y1 - y0 < 0.05 then return end
		n += 1
		box(parent, string.format("%s%s%d", name, tag, n), Vector3.new(b - a, y1 - y0, t),
			frame * CFrame.new((a + b) / 2, (y0 + y1) / 2, 0), r or role)
	end
	local cursor = -length / 2
	for _, o in ipairs(list) do
		local lo, hi = o.u - o.w / 2, o.u + o.w / 2
		piece(cursor, lo, 0, height, thick, nil, "P")
		if (o.y0 or 0) > 0.05 then piece(lo, hi, 0, o.y0, thick, nil, "S") end
		if o.y1 < height - 0.05 then piece(lo, hi, o.y1, height, thick, nil, "H") end
		if o.lintel ~= false then
			n += 1
			box(parent, string.format("%sL%d", name, n), Vector3.new(o.w + 2 * PROUD, 1.1, thick + 2 * PROUD),
				frame * CFrame.new(o.u, o.y1 + 0.45, 0), trimRole or role)
		end
		cursor = hi
	end
	piece(cursor, length / 2, 0, height, thick, nil, "P")
	return n
end

-- The same wall where the openings are arched: piers to the springing, voussoir rings, and the
-- fill above stepped and tucked just behind the ring so the curve is the edge you see.
-- Opening: {u, w, y0 = sill, spring =, apex =}
local function archWall(parent, name, frame, length, height, thick, openings, role, trimRole)
	local list = {}
	for _, o in ipairs(openings or {}) do table.insert(list, o) end
	table.sort(list, function(a, b) return a.u < b.u end)
	local n = 0
	local function piece(a, b, y0, y1, t, r, tag)
		if b - a < 0.05 or y1 - y0 < 0.05 then return end
		n += 1
		box(parent, string.format("%s%s%d", name, tag, n), Vector3.new(b - a, y1 - y0, t),
			frame * CFrame.new((a + b) / 2, (y0 + y1) / 2, 0), r or role)
	end
	local cursor = -length / 2
	for _, o in ipairs(list) do
		local lo, hi = o.u - o.w / 2, o.u + o.w / 2
		local span, rise = o.w, o.apex - o.spring
		local r = (span * span / 4 + rise * rise) / (2 * rise)
		local cy = o.spring + rise - r
		local halfAt = function(y)  -- half width of the arc at height y
			local d = math.abs(y - cy)
			if d >= r then return 0 end
			return math.sqrt(math.max(r * r - d * d, 0))
		end
		piece(cursor, lo, 0, height, thick, nil, "P")
		if (o.y0 or 0) > 0.05 then piece(lo, hi, 0, o.y0, thick, nil, "S") end
		-- stepped fill from the springing to the apex, then one block from the apex to the top
		local bands = 5
		for k = 0, bands - 1 do
			local ya = o.spring + rise * k / bands
			local yb = o.spring + rise * (k + 1) / bands
			local hw = halfAt(yb)
			piece(lo - 0.1, lo + (span / 2 - hw) - 0.05, ya, yb, thick - EPS, nil, "F")
			piece(hi - (span / 2 - hw) + 0.05, hi + 0.1, ya, yb, thick - EPS, nil, "F")
		end
		piece(lo - 0.1, hi + 0.1, o.apex, height, thick - EPS, nil, "H")
		-- the ring itself, proud on both faces, plus impost blocks at the springing
		arch(parent, name .. "A", frame * CFrame.new(o.u, o.spring, 0), span, rise, thick + 2 * PROUD, 1.1, 9, trimRole or P.trim, true)
		n += 2
		box(parent, string.format("%sI%d", name, n), Vector3.new(1.3, 0.7, thick + 2 * PROUD),
			frame * CFrame.new(lo + 0.35, o.spring - 0.35, 0), trimRole or P.trim)
		n += 1
		box(parent, string.format("%sI%d", name, n), Vector3.new(1.3, 0.7, thick + 2 * PROUD),
			frame * CFrame.new(hi - 0.35, o.spring - 0.35, 0), trimRole or P.trim)
		cursor = hi
	end
	piece(cursor, length / 2, 0, height, thick, nil, "P")
	return n
end

-- A wall running between two points on the map (for the polygonal apse, the boundary wall, the
-- porch). Local X runs a -> b, Y is up, Z is the thickness.
local function segFrame(a, b, y)
	local mid = Vector3.new((a.X + b.X) / 2, y, (a.Z + b.Z) / 2)
	return CFrame.lookAt(mid, Vector3.new(b.X, y, b.Z)) * CFrame.Angles(0, -math.pi / 2, 0)
end

local function seg(parent, name, a, b, y0, y1, thick, role)
	local len = (Vector3.new(b.X, 0, b.Z) - Vector3.new(a.X, 0, a.Z)).Magnitude
	return box(parent, name, Vector3.new(len, y1 - y0, thick),
		segFrame(a, b, (y0 + y1) / 2), role)
end

local function segOf(a, b)  -- length of a plan segment
	return (Vector3.new(b.X, 0, b.Z) - Vector3.new(a.X, 0, a.Z)).Magnitude
end

-- The build is a list of phases: each one owns a group of the map, and they run in this order.
local PHASES = {}
local function phase(fn) table.insert(PHASES, fn) end

--=====================================================================================
-- BASE NUMBERS -- everything below is arithmetic on these.
--=====================================================================================
local MAP = 150                     -- the map's footprint, a square centred on the origin
local HALF = MAP / 2                -- 75

local NAVE_HALF = 9                 -- nave interior half width (18 wide)
local PIER = 3                      -- arcade pier width, in x
local AISLE_W = 6                   -- aisle interior width
local WALL = 3                      -- cathedral wall thickness
local OUT_HALF = NAVE_HALF + PIER + AISLE_W + WALL      -- 21: outer face of the aisle walls
local BAYS, BAY = 5, 8              -- five 8 stud bays = a 40 stud nave
local NAVE_LEN = BAYS * BAY
local NAVE_Z0, NAVE_Z1 = -NAVE_LEN / 2, NAVE_LEN / 2    -- -20 .. 20, interior
local BODY_Z0, BODY_Z1 = NAVE_Z0 - WALL, NAVE_Z1 + WALL -- -23 .. 23, outer face of gable walls

local PLINTH_TOP = 3                -- the platform the cathedral stands on
local TILE = 0.12                   -- floor tiles laid on it
local FLOOR = PLINTH_TOP + TILE     -- 3.12: the level a player walks on indoors
local PLINTH_W, PLINTH_D = OUT_HALF * 2 + 6, 66
local PLINTH_Z = -3                 -- platform spans z -36 .. 30

local AISLE_TOP = 14                -- top of the aisle walls
local AISLE_HI = 18.5               -- lean-to roofs climb to here against the nave wall
local NAVE_TOP = 31                 -- top of the nave (clerestory) walls
local RIDGE = 40                    -- the nave ridge
local CLERE_Y0, CLERE_Y1 = 19.5, 29.5   -- clerestory window band
local SPRING = AISLE_TOP + 0.12     -- 14.12: arcade arches spring here

local APSE_OUT = 30                 -- the apse reaches z = 30
local APSE_TOP = 23                 -- its broken wall top

local TWR_W = 10                    -- tower footprint
local TWR_WALL = 2
local TWR_Z0, TWR_Z1 = -33, -23     -- towers stand in front of the west wall
local TWR_HI, TWR_LO = 46, 27       -- standing tower, sheared-off tower

local CHAPEL_W = 7                  -- the +X side chapel / aisle extension

--=====================================================================================
-- PHASE 1 -- BLOCKOUT. The masses from the design block, the right palette on the big planes,
-- no openings and no props. Everything here is replaced by the real shell in the next phase.
--=====================================================================================
phase(function(root)
	local ground = model(root, "Ground")
	box(ground, "Slab", Vector3.new(MAP, 3, MAP), CFrame.new(0, -1.5, 0), P.ground)

	local cath = model(root, "Cathedral")
	local found = model(cath, "Foundation")
	box(found, "Platform", Vector3.new(PLINTH_W, PLINTH_TOP, PLINTH_D),
		CFrame.new(0, PLINTH_TOP / 2, PLINTH_Z), P.plinth)

	local shell = model(cath, "Shell")
	-- nave: interior 18 wide plus a 3 stud arcade each side, from the platform to the wall top
	box(shell, "NaveMass", Vector3.new((NAVE_HALF + PIER) * 2, NAVE_TOP - PLINTH_TOP, BODY_Z1 - BODY_Z0),
		CFrame.new(0, (PLINTH_TOP + NAVE_TOP) / 2, 0), P.wall)
	-- aisles: 6 wide interior + the 3 stud outer wall, wall top 14
	local aisleX = NAVE_HALF + PIER + (AISLE_W + WALL) / 2
	local aisleH = AISLE_TOP - PLINTH_TOP
	for _, s in ipairs({ { 1, "E" }, { -1, "W" } }) do
		box(shell, "Aisle" .. s[2], Vector3.new(AISLE_W + WALL, aisleH, BODY_Z1 - BODY_Z0),
			CFrame.new(s[1] * aisleX, PLINTH_TOP + aisleH / 2, 0), P.wall)
	end
	-- twin towers on the west front corners
	local twrX = OUT_HALF - TWR_W / 2
	box(shell, "TowerA", Vector3.new(TWR_W, TWR_HI - PLINTH_TOP, TWR_W),
		CFrame.new(-twrX, (PLINTH_TOP + TWR_HI) / 2, (TWR_Z0 + TWR_Z1) / 2), P.wall)
	box(shell, "TowerB", Vector3.new(TWR_W, TWR_LO - PLINTH_TOP, TWR_W),
		CFrame.new(twrX, (PLINTH_TOP + TWR_LO) / 2, (TWR_Z0 + TWR_Z1) / 2), P.wall)
	-- apse: half octagon out to z = 30
	box(shell, "ApseMass", Vector3.new(16, APSE_TOP - PLINTH_TOP, APSE_OUT - BODY_Z1),
		CFrame.new(0, (PLINTH_TOP + APSE_TOP) / 2, (BODY_Z1 + APSE_OUT) / 2), P.wall)

	local cem = model(root, "Cemetery")
	box(cem, "Field", Vector3.new(70, 0.16, 34), CFrame.new(0, 0.08, 51), P.dirt)

	local forest = model(root, "Forest")
	local ring = { { -58, -58 }, { 0, -62 }, { 58, -58 }, { -62, 0 }, { 62, 0 }, { -52, 52 }, { 52, 52 }, { 0, 66 } }
	for i, at in ipairs(ring) do
		box(forest, "TreeMass" .. i, Vector3.new(12, 24, 12), CFrame.new(at[1], 12, at[2]), P.leaf)
	end
end)

--@@SECTION@@


local function BUILD(root)
	for _, fn in ipairs(PHASES) do
		fn(root)
	end
	return root
end

return BUILD
