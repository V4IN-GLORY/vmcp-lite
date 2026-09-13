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
		local head = o.y1 or o.apex
		piece(cursor, lo, 0, height, thick, nil, "P")
		if (o.y0 or 0) > 0.05 then piece(lo, hi, 0, o.y0, thick, nil, "S") end
		if head < height - 0.05 then piece(lo, hi, head, height, thick, nil, "H") end
		if o.lintel ~= false then
			n += 1
			box(parent, string.format("%sL%d", name, n), Vector3.new(o.w + 2 * PROUD, 1.1, thick + 2 * PROUD),
				frame * CFrame.new(o.u, head + 0.45, 0), trimRole or role)
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
		piece(cursor, lo, 0, height, thick, nil, "P")
		if (o.y0 or 0) > 0.05 then piece(lo, hi, 0, o.y0, thick, nil, "S") end
		if o.flat then   -- a doorway or a breach: square head, no arch
			piece(lo, hi, o.y1, height, thick, nil, "H")
			n += 1
			box(parent, string.format("%sL%d", name, n), Vector3.new(o.w + 2 * PROUD, 1.1, thick + 2 * PROUD),
				frame * CFrame.new(o.u, o.y1 + 0.45, 0), trimRole or P.trim)
			cursor = hi
			continue
		end
		local span, rise = o.w, o.apex - o.spring
		local r = (span * span / 4 + rise * rise) / (2 * rise)
		local cy = o.spring + rise - r
		local halfAt = function(y)  -- half width of the arc at height y
			local d = math.abs(y - cy)
			if d >= r then return 0 end
			return math.sqrt(math.max(r * r - d * d, 0))
		end
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

-- A moulding band along a wall face, split so it never crosses an opening: `gaps` are the world
-- positions of the holes along the wall's own axis, `centre` the wall's centre on that axis.
local function band(parent, name, frame, len, centre, gaps, thick, h, role)
	local holes = {}
	for _, g in ipairs(gaps or {}) do
		table.insert(holes, { g[1] - centre, g[2] - centre })
	end
	table.sort(holes, function(a, b) return a[1] < b[1] end)
	local cursor, n = -len / 2, 0
	local function piece(a, b)
		if b - a < 0.25 then return end
		n += 1
		box(parent, string.format("%s%d", name, n), Vector3.new(b - a, h, thick),
			frame * CFrame.new((a + b) / 2, 0, 0), role)
	end
	for _, g in ipairs(holes) do
		piece(cursor, math.min(g[1], len / 2))
		cursor = math.max(cursor, g[2])
	end
	piece(cursor, len / 2)
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
local FLOOR = PLINTH_TOP + TILE * 2 -- 3.24: field slab plus the slate tiles laid on it
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

-- (pass 1 blockout: bounds 150x49x150, groups matched the design, masses replaced by the real shell.)

--=====================================================================================
-- PHASE 2 -- SHELL. The real walls: openings cut as fill, layered masonry, towers, apse,
-- buttresses, porch. Every wall runs from its own frame; every opening is on the access list.
--=====================================================================================

-- A wall running along X has its own frame; one running along Z is the same wall turned, with
-- u = world z so opening positions stay readable in world coordinates.
local function wallX(x, y, z) return CFrame.new(x, y, z) end
local function wallZ(x, y, z) return CFrame.new(x, y, z) * CFrame.Angles(0, -math.pi / 2, 0) end

local function steps(parent, name, cx, cz, width, tread, count, role)
	-- steps descending in -Z from the platform edge at cz, top step level with the platform
	for i = 1, count do
		local top = PLINTH_TOP - (count - i)
		local z0 = cz - tread * (count - i + 1)
		box(parent, string.format("%s%d", name, i), Vector3.new(width, top, tread + 0.1),
			CFrame.new(cx, top / 2, z0 + (tread + 0.1) / 2), role)
	end
end

phase(function(root)
	local cath = model(root, "Cathedral")
	local found = model(cath, "Foundation")
	local shell = model(cath, "Shell")
	local base = PLINTH_TOP - 0.2                       -- walls sink 0.2 into the platform
	local top = NAVE_TOP - base

	-- ---- platform, moulding, worn steps -------------------------------------------------
	box(found, "Platform", Vector3.new(PLINTH_W, 2.4, PLINTH_D), CFrame.new(0, 1.2, PLINTH_Z), P.plinth)
	box(found, "PlatformCap", Vector3.new(PLINTH_W + 1.2, 0.66, PLINTH_D + 1.2),
		CFrame.new(0, 2.67, PLINTH_Z), P.trim)
	steps(found, "Step", 0, PLINTH_Z - PLINTH_D / 2, 12, 1.5, 3, P.trim)
	box(found, "StepCrack", Vector3.new(3.4, 1, 1.6), CFrame.new(3.2, PLINTH_TOP - 2.5, PLINTH_Z - PLINTH_D / 2 - 3.9), P.trim)
	box(found, "Forecourt", Vector3.new(22, 0.18, 14), CFrame.new(0, 0.09, PLINTH_Z - PLINTH_D / 2 - 11), P.dirt)

	-- ---- aisle outer walls: bays of lancets, a side door, a collapsed breach ------------
	-- heights per segment are the ruin data: the +X wall loses its north third, the -X wall
	-- keeps its south end and drops away to the north.
	local aisleWall = { { 19.5, 1 }, { -19.5, -1 } }
	for _, w in ipairs(aisleWall) do
		local cx, side = w[1], w[2]
		local tag = if side > 0 then "E" else "W"
		-- openings are listed in world z; the frame is centred on its segment, so subtract cz
		local function seg(name, cz, len, height, holes)
			local local_ = {}
			for i, o in ipairs(holes) do
				local_[i] = { u = o.z - cz, w = o.w, y0 = o.y0, y1 = o.y1, lintel = o.lintel }
			end
			wallWith(shell, name, wallZ(cx, base, cz), len, height, WALL, local_, P.wall, P.trim)
		end
		if side > 0 then
			seg("AisleWallS" .. tag, -4, 32, 11.2, {
				{ z = -16, w = 3, y0 = 2.8, y1 = 8.7 }, { z = -8, w = 3, y0 = 2.8, y1 = 8.7 },
				{ z = 0, w = 8, y0 = 0, y1 = 11.2, lintel = false },
				{ z = 8, w = 4, y0 = FLOOR - base, y1 = FLOOR - base + 8 },
			})
			seg("AisleWallN" .. tag, 16, 8, 9.7, { { z = 16, w = 3, y0 = 2.8, y1 = 7.0 } })
		else
			seg("AisleWallS" .. tag, -8, 24, 11.2, {
				{ z = -16, w = 3, y0 = 2.8, y1 = 8.7 }, { z = -8, w = 3, y0 = 2.8, y1 = 8.7 },
				{ z = 0, w = 3, y0 = 2.8, y1 = 8.7 },
			})
			seg("AisleWallN" .. tag, 12, 16, 8.6, {
				{ z = 8, w = 3, y0 = 2.8, y1 = 7.3 }, { z = 16, w = 3, y0 = 2.8, y1 = 7.3 },
			})
		end
		-- dado and eaves bands, split so they never cross a window, the door or the breach
		local function trimBand(name, cz, len, y, gaps, h)
			band(shell, name, wallZ(cx, y, cz), len, cz, gaps, WALL + 2 * PROUD, h or 0.5, P.trim)
		end
		if side > 0 then
			trimBand("AisleDado" .. tag, -4, 32, PLINTH_TOP + 2.6,
				{ { -17.5, -14.5 }, { -9.5, -6.5 }, { -4.2, 4.2 }, { 5.8, 10.2 } })
			trimBand("AisleDadoN" .. tag, 16, 7.6, PLINTH_TOP + 2.6, { { 14.5, 17.5 } })
			trimBand("AisleEaves" .. tag, -4, 32, AISLE_TOP - 0.3, { { -4.2, 4.2 } }, 0.6)
			trimBand("AisleEavesN" .. tag, 16, 7.6, 12.2, { { 14.5, 17.5 } }, 0.6)
		else
			trimBand("AisleDado" .. tag, -8, 24, PLINTH_TOP + 2.6, { { -17.5, -14.5 }, { -9.5, -6.5 }, { -1.5, 1.5 } })
			trimBand("AisleDadoN" .. tag, 12, 15.6, PLINTH_TOP + 2.6, { { 6.5, 9.5 }, { 14.5, 17.5 } })
			trimBand("AisleEaves" .. tag, -8, 24, AISLE_TOP - 0.3, {}, 0.6)
			trimBand("AisleEavesN" .. tag, 12, 15.6, 11.3, { { 6.5, 9.5 }, { 14.5, 17.5 } }, 0.6)
		end
	end

	-- ---- nave walls: arcade below (five arched openings), clerestory above ---------------
	local piers = { -16.75, -8, 0, 8, 16.75 }
	local arcade = {}
	for i, u in ipairs(piers) do
		arcade[i] = { u = u, w = (i == 1 or i == 5) and 6.5 or 5, y0 = FLOOR - base,
			spring = SPRING - base, apex = SPRING - base + 3.5 }
	end
	for _, side in ipairs({ 1, -1 }) do
		local tag = if side > 0 then "E" else "W"
		archWall(shell, "Arcade" .. tag, wallZ(side * (NAVE_HALF + PIER / 2), base, 0), 40, SPRING - base + 3.5, WALL,
			arcade, P.wall, P.trim)
		local clere = {}
		for i, u in ipairs({ -16, -8, 0, 8, 16 }) do
			local w = if i == 3 then 4.6 else 4
			clere[i] = { u = u, w = w, y0 = CLERE_Y0 - SPRING - 3.5, y1 = (if i == 4 then 26 else CLERE_Y1) - SPRING - 3.5,
				lintel = true }
		end
		wallWith(shell, "Clere" .. tag, wallZ(side * (NAVE_HALF + PIER / 2), SPRING + 3.5, 0), 40,
			NAVE_TOP - SPRING - 3.5, WALL, clere, P.wall, P.trim)
		-- string course over the arcade and cornice at the wall head
		box(shell, "ArcadeBand" .. tag, Vector3.new(WALL + 2 * PROUD, 0.7, 40.8),
			CFrame.new(side * (NAVE_HALF + PIER / 2), SPRING + 3.5 + 0.15, 0), P.trim)
		box(shell, "NaveCornice" .. tag, Vector3.new(WALL + 2 * PROUD, 0.5, 40.8),
			CFrame.new(side * (NAVE_HALF + PIER / 2), NAVE_TOP - 0.25, 0), P.trim)
	end

	-- ---- west front: two stacked walls (door arch below, wheel window above), gable, cross
	archWall(shell, "WestWallLow", wallX(0, base, BODY_Z0 + WALL / 2), 42, 15, WALL,
		{ { u = 0, w = 8, y0 = FLOOR - base, spring = 12.5 - base, apex = 16 - base },
		  { u = -15.8, w = 4.4, y0 = FLOOR - base, y1 = FLOOR - base + 8, flat = true } }, P.wall, P.trim)
	archWall(shell, "WestWallHigh", wallX(0, 17.8, BODY_Z0 + WALL / 2), 42, NAVE_TOP - 17.8, WALL,
		{ { u = 0, w = 10, y0 = 0, spring = 3.7, apex = 8.7 } }, P.wall, P.trim)
	band(shell, "WestBand", wallX(0, 17.8, BODY_Z0 + WALL / 2), 42, 0, { { -5.2, 5.2 } }, WALL + 2 * PROUD, 0.7, P.trim)
	band(shell, "WestDado", wallX(0, PLINTH_TOP + 2.6, BODY_Z0 + WALL / 2), 42, 0, { { -4.2, 4.2 } }, WALL + 2 * PROUD, 0.5, P.trim)

	-- the wheel window: hub, two rings, eight spokes, all in the west opening
	local wheelAt = CFrame.new(0, 21.8, BODY_Z0 + WALL / 2)   -- centred in the upper wall's arched opening
	col(shell, "WheelHub", 0.9, WALL + 0.9, wheelAt, P.trim)
	for i = 1, 8 do
		local a = (i - 1) * math.pi / 4
		box(shell, "WheelSpoke" .. i, Vector3.new(0.42, 8.2, WALL + 0.5),
			wheelAt * CFrame.Angles(0, 0, a + math.pi / 2), P.trim)
	end
	for i = 1, 16 do
		local a = (i - 0.5) * 2 * math.pi / 16
		local seg = 2 * 3.5 * math.sin(math.pi / 16) + PROUD
		box(shell, "WheelRing" .. i, Vector3.new(0.5, seg, WALL + 0.8),
			wheelAt * CFrame.Angles(0, 0, a) * CFrame.new(3.4, 0, 0), P.trim)
	end

	-- gable over the nave, stepped in courses, with a coping and a stone cross
	local gable = function(parent, name, z, courses, role)
		for k = 0, courses - 1 do
			local y0 = NAVE_TOP + k * 1.5
			local half = 12 - k * 2
			box(parent, string.format("%sC%d", name, k), Vector3.new(half * 2, 1.5, WALL),
				CFrame.new(0, y0 + 0.75, z), role)
			box(parent, string.format("%sCop%d", name, k), Vector3.new(half * 2 + 0.3, 0.4, WALL + 0.4),
				CFrame.new(0, y0 + 1.5, z), P.trim)
		end
	end
	gable(shell, "WestGable", BODY_Z0 + WALL / 2, 6, P.wall)
	box(shell, "CrossUp", Vector3.new(0.55, 4.0, 0.55), CFrame.new(0, NAVE_TOP + 9 + 2.4, BODY_Z0 + WALL / 2), P.trim)
	box(shell, "CrossArm", Vector3.new(2.6, 0.55, 0.55), CFrame.new(0, NAVE_TOP + 9 + 2.7, BODY_Z0 + WALL / 2), P.trim)
	gable(shell, "EastGable", BODY_Z1 - WALL / 2, 4, P.wall)

	-- ---- east wall (chancel arch) --------------------------------------------------------
	archWall(shell, "EastWall", wallX(0, base, BODY_Z1 - WALL / 2), 42, top, WALL,
		{ { u = 0, w = 12, y0 = FLOOR - base, spring = 15.1 - base, apex = 19.5 - base } }, P.wall, P.trim)
	band(shell, "EastBand", wallX(0, 16.4, BODY_Z1 - WALL / 2), 42, 0, { { -6.2, 6.2 } }, WALL + 2 * PROUD, 0.7, P.trim)

	-- ---- apse: five wall segments of a half octagon, uneven tops, narrow lancets ---------
	local APSE_R, APSE_T = 7.6, 2.5
	local v = {}
	for k = 0, 5 do
		local a = math.rad(-90 + k * 36)
		v[k + 1] = Vector3.new(APSE_R * math.sin(a), 0, BODY_Z1 + APSE_R * math.cos(a))
	end
	local apseTop = { 23, 20.5, 18.5, 22, 21 }
	for k = 1, 5 do
		local a, b = v[k], v[k + 1]
		local len = segOf(a, b) + 0.2
		local h = apseTop[k] - base
		local win = (k == 3) and { u = 0, w = 2.4, y0 = 3, y1 = 11 } or { u = 0, w = 2.4, y0 = 5, y1 = 14 }
		wallWith(shell, "Apse" .. k, segFrame(a, b, base), len, h, APSE_T, { win }, P.wall, P.trim)
		box(shell, "ApseBand" .. k, Vector3.new(len, 0.6, APSE_T + 2 * PROUD),
			segFrame(a, b, base + (if k == 3 then 1.4 else 4.4)), P.trim)
	end
	box(shell, "ApseButtress1", Vector3.new(1.6, 12, 1.8), CFrame.new(v[1].X - 1.2, base + 6, v[1].Z + 2.2), P.plinth)
	box(shell, "ApseButtress2", Vector3.new(1.6, 12, 1.8), CFrame.new(v[6].X + 1.2, base + 6, v[6].Z + 2.2), P.plinth)
end)

--=====================================================================================
-- PHASE 2b -- TOWERS, BUTTRESSES, PORCH. The two unequal west towers, the weathered
-- buttresses that brace the aisle walls, and the fragmentary entrance porch.
--=====================================================================================
phase(function(root)
	local cath = model(root, "Cathedral")
	local shell = model(cath, "Shell")
	local base = PLINTH_TOP - 0.2

	-- ---- the two west towers ------------------------------------------------------------
	-- outer and inner walls run the full 10 studs and the front wall butts between them, so a
	-- corner is two long walls and one short one, never three crossing.
	local towers = {
		{ tag = "A", side = -1, hOuter = TWR_HI, hFront = TWR_HI, hInner = TWR_HI, belfry = true },
		{ tag = "B", side = 1, hOuter = TWR_LO, hFront = TWR_LO - 3, hInner = TWR_LO - 5, belfry = false },
	}
	for _, t in ipairs(towers) do
		local xOut = t.side * (OUT_HALF - TWR_WALL / 2)
		local xIn = t.side * (OUT_HALF - TWR_W - TWR_WALL / 2)
		local zc = (TWR_Z0 + TWR_Z1) / 2
		-- openings are given in world coordinates; each wall frame is centred, so subtract it
		local holesOut, holesFront, holesIn = {}, {}, {}
		if t.belfry then
			for _, z in ipairs({ -31, -25 }) do   -- two belfry arches on the outer face
				table.insert(holesOut, { u = z - zc, w = 3, y0 = 37.5, spring = 39.4, apex = 43 })
			end
			table.insert(holesFront, { u = 0, w = 3, y0 = 37.5, spring = 39.4, apex = 43 })  -- one on the front face
			holesIn = { { u = 0, w = 3.4, y0 = 37.5, spring = 39.4, apex = 43 } }
		else
			holesIn = { { u = -0.5, w = 5, y0 = 0, y1 = 9, flat = true } }          -- the breach
			holesOut = { { u = 2, w = 3, y0 = 12, y1 = 21, flat = true, lintel = false } }
		end
		archWall(shell, "Tower" .. t.tag .. "Outer", wallZ(xOut, base, zc), TWR_W, t.hOuter - base, TWR_WALL, holesOut, P.wall, P.trim)
		archWall(shell, "Tower" .. t.tag .. "Inner", wallZ(xIn, base, zc), TWR_W, t.hInner - base, TWR_WALL, holesIn, P.wall, P.trim)
		archWall(shell, "Tower" .. t.tag .. "Front", wallX(t.side * (OUT_HALF - TWR_W / 2), base, TWR_Z0 + TWR_WALL / 2),
			TWR_W - 2 * TWR_WALL, t.hFront - base, TWR_WALL, holesFront, P.wall, P.trim)
		-- corner pilasters, a plinth band and two string courses
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				box(shell, string.format("Tower%sQuoin%d%d", t.tag, (sx + 1) / 2, (sz + 1) / 2),
					Vector3.new(1.4, t.hOuter - base, 1.4),
					CFrame.new(t.side * (OUT_HALF - TWR_W / 2) + sx * (TWR_W / 2 - 0.2), (base + t.hOuter) / 2, zc + sz * (TWR_W / 2 - 0.2)),
					P.trim)
			end
		end
		box(shell, "Tower" .. t.tag .. "Plinth", Vector3.new(TWR_W + 0.6, 2.2, TWR_W + 0.6),
			CFrame.new(t.side * (OUT_HALF - TWR_W / 2), base + 1.1, zc), P.plinth)
		for _, y in ipairs({ 18.5, 30.5 }) do
			if y < t.hOuter - 2 then
				box(shell, string.format("Tower%sCourse%d", t.tag, y), Vector3.new(TWR_W + 0.5, 0.6, TWR_W + 0.5),
					CFrame.new(t.side * (OUT_HALF - TWR_W / 2), y, zc), P.trim)
			end
		end
		-- the crown: a broken parapet standing on whatever wall is under it, and a spire stub
		local cx = t.side * (OUT_HALF - TWR_W / 2)
		local corners = {
			{ -1, -1, math.min(t.hInner, t.hFront) }, { 1, -1, math.min(t.hOuter, t.hFront) },
			{ -1, 1, math.min(t.hInner, NAVE_TOP) }, { 1, 1, math.min(t.hOuter, NAVE_TOP) },
		}
		for i, c in ipairs(corners) do
			local h = if t.belfry then (if i % 2 == 0 then 1.9 else 1.2) else (if i % 2 == 1 then 1.5 else 0.8)
			box(shell, string.format("Tower%sParapet%d", t.tag, i), Vector3.new(4.4, h, 4.4),
				CFrame.new(cx + c[1] * 2.6, c[3] + h / 2 - 0.1, zc + c[2] * 2.6), P.wall)
		end
		if t.belfry then
			box(shell, "TowerASpireBase", Vector3.new(3.2, 2.4, 3.2), CFrame.new(cx, t.hOuter + 1.2, zc), P.wall)
			box(shell, "TowerASpireMid", Vector3.new(2.2, 2.2, 2.2), CFrame.new(cx, t.hOuter + 3.4, zc), P.wall)
			box(shell, "TowerASpireTip", Vector3.new(1.3, 1.8, 1.3), CFrame.new(cx, t.hOuter + 5.3, zc), P.trim)
			box(shell, "TowerAStub", Vector3.new(0.7, 1.6, 0.7), CFrame.new(cx, t.hOuter + 6.9, zc), P.trim)
			box(shell, "TowerABelfryFloor", Vector3.new(TWR_W - 2 * TWR_WALL + 0.6, 0.7, TWR_W - 2 * TWR_WALL + 0.6),
				CFrame.new(cx, 36.4, zc), P.beam)
		end
	end

	-- ---- buttresses: three weathered stages, some broken, one gone -----------------------
	local heights = { { z = -12, h = 14 }, { z = -4, h = 6.5 }, { z = 4, h = 0 }, { z = 12, h = 9.5 } }
	for _, side in ipairs({ 1, -1 }) do
		for _, b in ipairs(heights) do
			if b.h > 0 then
				local tag = string.format("%s%d", if side > 0 then "E" else "W", b.z + 20)
				local function stage(suffix, z0, z1, reach, y0, y1)
					box(shell, "Buttress" .. tag .. suffix, Vector3.new(reach - OUT_HALF + 0.2, y1 - y0, z1 - z0),
						CFrame.new(side * (OUT_HALF + (reach - OUT_HALF) / 2 - 0.05), (y0 + y1) / 2, (z0 + z1) / 2), P.wall)
				end
				local h1 = math.min(b.h, 8)
				stage("A", b.z - 1.3, b.z + 1.3, OUT_HALF + 2.4, 2.6, h1)
				if b.h > 8.4 then
					stage("B", b.z - 1.1, b.z + 1.1, OUT_HALF + 1.8, h1 - 0.1, math.min(b.h, 11.5))
				end
				if b.h > 11.9 then
					stage("C", b.z - 0.9, b.z + 0.9, OUT_HALF + 1.2, 11.4, b.h)
					box(shell, "Buttress" .. tag .. "Cap", Vector3.new(1.5, 0.45, 2.1),
						CFrame.new(side * (OUT_HALF + 0.6), b.h + 0.22, b.z), P.trim)
				else
					box(shell, "Buttress" .. tag .. "Cap", Vector3.new(1.8, 0.4, 2.4),
						CFrame.new(side * (OUT_HALF + 1.2), h1 + 0.2, b.z), P.trim)
				end
			end
		end
	end

	-- ---- the porch: two columns, a broken lintel, a fallen drum --------------------------
	local porch = model(cath, "Porch")
	for _, side in ipairs({ 1, -1 }) do
		local tag = if side > 0 then "E" else "W"
		box(porch, "ColBase" .. tag, Vector3.new(2.0, 1.1, 2.0), CFrame.new(side * 6, PLINTH_TOP + 0.55, -30.5), P.plinth)
		box(porch, "ColPlinth" .. tag, Vector3.new(1.7, 0.5, 1.7), CFrame.new(side * 6, PLINTH_TOP + 1.35, -30.5), P.trim)
		local top = if side < 0 then 8 else 12.5
		col(porch, "ColShaft" .. tag, 0.72, top - (PLINTH_TOP + 1.5), CFrame.new(side * 6, (PLINTH_TOP + 1.5 + top) / 2, -30.5), P.trim)
		if side < 0 then
			box(porch, "ColBreak" .. tag, Vector3.new(1.1, 0.6, 1.1), CFrame.new(side * 6, top + 0.2, -30.5), P.trim)
			cyl(porch, "ColDrum" .. tag, 0.72, 1.5, CFrame.new(side * 8.4, PLINTH_TOP + 0.72, -28.6), P.trim)
		else
			box(porch, "ColCap" .. tag, Vector3.new(1.8, 0.9, 1.8), CFrame.new(side * 6, top + 0.45, -30.5), P.trim)
		end
	end
	box(porch, "LintelE", Vector3.new(4.6, 1.7, 2.6), CFrame.new(3.6, 13.9, -30.5), P.trim)
	box(porch, "LintelW", Vector3.new(2.8, 1.7, 2.6), CFrame.new(-5.2, 9.3, -30.6), P.trim)   -- the fragment left on the broken column
	box(porch, "PorchStep", Vector3.new(11, 0.5, 3.4), CFrame.new(0, PLINTH_TOP - 0.25 + 0.5, -30.4), P.trim)
	box(porch, "Threshold", Vector3.new(9, 0.34, 2.2), CFrame.new(0, FLOOR - 0.17 + 0.34, BODY_Z0 - 1.0), P.trim)
	for _, side in ipairs({ 1, -1 }) do
		box(porch, "Pilaster" .. (if side > 0 then "E" else "W"), Vector3.new(1.7, 10.5, 0.7),
			CFrame.new(side * 6, PLINTH_TOP + 5.25, BODY_Z0 - 0.15), P.trim)
	end
end)

--=====================================================================================
-- PHASE 3 -- ROOF. Two nave slopes with real holes, lean-tos over the aisles, ridge caps,
-- rafters under every slope that is still there. Damage is a per-bay table, not a new path.
--=====================================================================================
phase(function(root)
	local cath = model(root, "Cathedral")
	local roof = model(cath, "Roof")
	local base = PLINTH_TOP - 0.2
	local EAVE_X, EAVE_Y = 13.5, NAVE_TOP - 0.7      -- nave eaves, one stud past the wall face
	local run, rise = EAVE_X, RIDGE - EAVE_Y
	local len = math.sqrt(run * run + rise * rise)
	local pitch = math.atan2(rise, run)
	-- per bay, west (+Z index 1) to east: is the slope still up there?
	local slopeUp = { [1] = { true, true }, [2] = { true, "half" }, [3] = { true, true }, [4] = { true, true }, [5] = { true, true } }
	local function naveSlope(side, bay)
		local zc = NAVE_Z0 + (bay - 0.5) * BAY
		local midX, midY = side * run / 2, (EAVE_Y + RIDGE) / 2
		local cf = CFrame.new(midX, midY, zc) * CFrame.Angles(0, 0, side * pitch)
		box(roof, string.format("Slope%s%d", if side > 0 then "E" else "W", bay),
			Vector3.new(len + PROUD, 0.9, BAY + 0.2), cf, P.roof)
		for k = -1, 1, 2 do   -- two rafters under each slab
			box(roof, string.format("Rafter%s%d%s", if side > 0 then "E" else "W", bay, if k > 0 then "b" else "a"),
				Vector3.new(len - 1.5, 0.5, 0.6),
				CFrame.new(midX, midY - 0.7, zc + k * (BAY / 2 - 0.4)) * CFrame.Angles(0, 0, side * pitch), P.beam)
		end
	end
	for bay = 1, BAYS do
		for side, up in ipairs(slopeUp[bay]) do
			local s = if side == 1 then 1 else -1
			if up == true then
				naveSlope(s, bay)
			elseif up == "half" then
				-- this bay came down through the middle: two torn ends still hang from ridge and eave
				local zc = NAVE_Z0 + (bay - 0.5) * BAY
				for k, edge in ipairs({ { -1, -0.22 }, { 0.22, 1 } }) do
					local segLen = len * 0.38
					local mid = (edge[1] + edge[2]) / 2 * len
					box(roof, string.format("SlopeTorn%d%s", bay, if k == 1 then "a" else "b"),
						Vector3.new(segLen, 0.9, BAY + 0.2),
						CFrame.new(s * mid * math.cos(pitch), RIDGE - mid * math.sin(pitch), zc)
							* CFrame.Angles(0, 0, s * pitch), P.roof)
				end
			end
		end
	end
	-- the ridge: two lengths of cap with one break where the fallen bay took it down
	for i, run in ipairs({ { -20.5, -6.4 }, { -5.6, 20.5 } }) do
		box(roof, string.format("Ridge%d", i), Vector3.new(2.0, 1.5, run[2] - run[1] + 0.3),
			CFrame.new(0, RIDGE - 0.25, (run[1] + run[2]) / 2), P.roof)
	end
	-- aisle lean-tos: from the outer wall head up to the nave wall foot
	local aRun, aRise = OUT_HALF - (NAVE_HALF + PIER), AISLE_HI - AISLE_TOP
	local aLen = math.sqrt(aRun * aRun + aRise * aRise)
	local aPitch = math.atan2(aRise, aRun)
	local aisleUp = { [1] = { { -20, -4.2 }, { -4.2, 4.2 }, { 4.2, 12 } }, [2] = { { -20, 4 } } }
	for side, spans in ipairs(aisleUp) do
		local s = if side == 1 then 1 else -1
		for i, span in ipairs(spans) do
			local z0, z1 = span[1], span[2]
			if not (s > 0 and z0 == -4.2) then   -- the +X bay over the breach is gone
				local zc = (z0 + z1) / 2
				local midX, midY = s * (OUT_HALF - aRun / 2), (AISLE_TOP + AISLE_HI) / 2
				box(roof, string.format("Lean%d%d", side, i), Vector3.new(aLen + PROUD, 0.75, z1 - z0 + 0.2),
					CFrame.new(midX, midY, zc) * CFrame.Angles(0, 0, -s * aPitch), P.roof)
				local n = math.max(1, math.floor((z1 - z0) / 4))
				for k = 1, n do
					box(roof, string.format("LeanRaft%d%d%d", side, i, k), Vector3.new(aLen - 1, 0.4, 0.5),
						CFrame.new(midX, midY - 0.6, z0 + (k - 0.5) * (z1 - z0) / n) * CFrame.Angles(0, 0, -s * aPitch), P.beam)
				end
			end
		end
	end
	-- wall plates where the lean-tos meet the nave wall, and the seam boxes at the eaves
	for _, side in ipairs({ 1, -1 }) do
		box(roof, "WallPlate" .. (if side > 0 then "E" else "W"), Vector3.new(1.1, 0.8, 46.5),
			CFrame.new(side * (NAVE_HALF + PIER - 0.4), AISLE_HI - 0.2, 0), P.beam)
	end
end)

--=====================================================================================
-- PHASE 4 -- INTERIOR. Floor and flagstones, tie beams, pews, the sanctuary and its altar,
-- rubble, fallen timber, and the few lights that are actually lit.
--=====================================================================================
phase(function(root)
	local cath = model(root, "Cathedral")
	local inside = model(cath, "Interior")

	-- ---- floor: a marble field with a slate processional path and a border band ----------
	box(inside, "FloorField", Vector3.new(36, TILE, 40), CFrame.new(0, PLINTH_TOP + TILE / 2, 0), P.floor)
	box(inside, "FloorApse", Vector3.new(13, TILE, 7.6), CFrame.new(0, PLINTH_TOP + TILE / 2, 26.4), P.floor)
	box(inside, "PathCentre", Vector3.new(8, TILE, 40), CFrame.new(0, FLOOR + TILE / 2, 0), P.flag)
	for _, side in ipairs({ 1, -1 }) do
		box(inside, "PathEdge" .. (if side > 0 then "E" else "W"), Vector3.new(1.0, TILE, 40),
			CFrame.new(side * 4.5, FLOOR + TILE / 2, 0), P.trim)
	end
	box(inside, "ApseFloor", Vector3.new(11, TILE, 6.6), CFrame.new(0, FLOOR + TILE / 2, 26.6), P.flag)
	-- a handful of tiles have come up, and the hole shows the older floor under it
	for i, t in ipairs({ { -6, -14 }, { 5.5, -6 }, { -8.5, 2 }, { 8, 9 }, { 2.5, 17 }, { -3, 20.5 } }) do
		box(inside, string.format("TileOut%d", i), Vector3.new(2.6, 0.12, 2.6),
			CFrame.new(t[1], FLOOR + 0.06, t[2]) * CFrame.Angles(0, math.rad(8 * i), 0), P.flag)
	end
	-- ---- tie beams across the nave -------------------------------------------------------
	for i, z in ipairs({ -16, -8, 0, 8, 16 }) do
		box(inside, string.format("Tie%d", i), Vector3.new(24.4, 0.75, 0.75), CFrame.new(0, SPRING + 4.6, z), P.beam)
		for _, side in ipairs({ 1, -1 }) do
			box(inside, string.format("Corbel%d%s", i, if side > 0 then "E" else "W"), Vector3.new(1.4, 1.1, 1.4),
				CFrame.new(side * 11.2, SPRING + 3.7, z), P.trim)
		end
	end
	-- ---- pews: two blocks facing the altar, some of them down ----------------------------
	local pewZ = { -14, -11, -8, -5, -2 }
	local broken = { [2] = 1, [4] = -1, [5] = 2 }   -- row -> how it is ruined
	for r, z in ipairs(pewZ) do
		for _, side in ipairs({ 1, -1 }) do
			local cx = side * 6.4
			local ruin = broken[r] or 0
			if not (ruin == 2 and side > 0) then
				local tag = string.format("Pew%d%s", r, if side > 0 then "E" else "W")
				local tilt = if ruin == 1 then CFrame.Angles(0, 0, math.rad(14 * side)) else CFrame.new()
				local pivot = CFrame.new(cx, FLOOR, z) * tilt
				box(inside, tag .. "Seat", Vector3.new(3.8, 0.36, 1.5), pivot * CFrame.new(0, 1.5, 0), P.beam)
				box(inside, tag .. "Back", Vector3.new(3.8, 1.6, 0.32), pivot * CFrame.new(0, 2.3, 0.75), P.beam)
				box(inside, tag .. "Kneeler", Vector3.new(3.8, 0.3, 0.7), pivot * CFrame.new(0, 0.5, -1.0), P.beam)
				for k = -1, 1, 2 do
					box(inside, string.format("%sLeg%s", tag, if k > 0 then "a" else "b"), Vector3.new(0.36, 1.5, 1.4),
						pivot * CFrame.new(k * 1.6, 0.75, 0), P.beam)
				end
			end
		end
	end
	-- the two pews that came apart, lying where they fell
	box(inside, "PewFallenSeat", Vector3.new(3.8, 0.4, 1.5), CFrame.new(-2.4, FLOOR + 0.2, -19.4) * CFrame.Angles(0, math.rad(24), 0), P.beam)
	box(inside, "PewFallenBack", Vector3.new(3.8, 0.4, 1.6), CFrame.new(4.6, FLOOR + 0.2, 3.4) * CFrame.Angles(0, math.rad(-38), 0), P.beam)
	-- ---- sanctuary: two steps, a raised altar, the broken table --------------------------
	box(inside, "SanctStep1", Vector3.new(15, 1.1, 8.4), CFrame.new(0, FLOOR + 0.55, 15.6), P.trim)
	box(inside, "SanctStep2", Vector3.new(13, 1.1, 5.0), CFrame.new(0, FLOOR + 1.65, 17.4), P.trim)
	local altarY = FLOOR + 2.2
	box(inside, "AltarMensaW", Vector3.new(3.4, 0.55, 3.0), CFrame.new(-2.0, altarY + 2.6, 20.6), P.trim)
	box(inside, "AltarMensaE", Vector3.new(2.6, 0.55, 3.0), CFrame.new(2.2, altarY + 2.6, 20.7) * CFrame.Angles(0, math.rad(6), 0), P.trim)
	box(inside, "AltarChunk", Vector3.new(1.8, 0.55, 2.2), CFrame.new(6.4, FLOOR + 0.3, 21.6) * CFrame.Angles(0, math.rad(28), 0), P.trim)
	for _, x in ipairs({ -3.0, 3.2 }) do
		box(inside, string.format("AltarLeg%d", x > 0 and 1 or 0), Vector3.new(0.9, 2.6, 2.6),
			CFrame.new(x, altarY + 1.3, 20.6), P.trim)
	end
	box(inside, "AltarCloth", Vector3.new(6.0, 0.16, 3.3), CFrame.new(-0.2, altarY + 2.95, 20.6), P.floor)
	box(inside, "AltarClothTorn", Vector3.new(1.5, 0.14, 2.2), CFrame.new(3.9, FLOOR + 0.1, 19.2) * CFrame.Angles(0, math.rad(-18), 0), P.floor)
	-- the cross that stood behind it, down and leaning on the step
	box(inside, "CrossDown", Vector3.new(0.5, 5.2, 0.5), CFrame.new(-4.6, FLOOR + 2.2, 22.4) * CFrame.Angles(math.rad(22), 0, math.rad(-8)), P.trim)
	box(inside, "CrossDownArm", Vector3.new(2.4, 0.5, 0.5), CFrame.new(-4.6, FLOOR + 3.4, 22.4) * CFrame.Angles(math.rad(22), 0, math.rad(-8)), P.trim)
	-- ---- rubble, fallen timber -----------------------------------------------------------
	local rubbleAt = { { 9.5, -20.5 }, { 12.5, -13 }, { 14.5, -6.5 }, { 6.2, 12.5 }, { -13.5, 4.5 }, { -9.5, 18.5 } }
	for i, r in ipairs(rubbleAt) do
		for k = 1, 4 do
			local s = 1.0 + jitAbs(1.6)
			box(inside, string.format("Rubble%d_%d", i, k), Vector3.new(s, s * 0.7, s * 1.2),
				CFrame.new(r[1] + jit(2.2), FLOOR + s * 0.22, r[2] + jit(2.2))
					* CFrame.Angles(0.14 + jit(0.22), jit(3.1), 0.1 + jit(0.22)), P.plinth)
		end
	end
	for i, b in ipairs({ { -8, 6, 34 }, { 3, -9, -52 }, { -11.5, -16, 18 }, { 8.5, 15, 74 }, { 0.5, -21, -12 } }) do
		box(inside, string.format("FallenBeam%d", i), Vector3.new(0.8, 0.8, b[3] > 0 and 15 or 12),
			CFrame.new(b[1], FLOOR + 0.6, b[2]) * CFrame.Angles(0, math.rad(b[3]), math.rad(6)), P.beam)
	end
end)

--=====================================================================================
-- PHASE 5 -- GROUND, CEMETERY, FOREST. The cathedral's setting: worn paths, an irregular
-- graveyard behind the apse, and a ring of trees around the whole 150 x 150.
--=====================================================================================

-- One tree, three recipes. Trunks are cylinders, roots and branches are boxes set at an
-- angle, crowns are overlapping boxes at slightly different sizes and rotations.
local function tree(parent, name, x, z, scale, kind, lean)
	local bark, leaf = P.bark, P.leaf
	local h = (10 + jitAbs(4)) * scale
	local tilt = CFrame.new(x, 0, z) * CFrame.Angles(jit(0.05) + lean * 0.5, jit(3.1), jit(0.05) + lean)
	rod(parent, name .. "Trunk1", 1.15 * scale, h * 0.62, tilt * CFrame.new(0, h * 0.31, 0) * CFrame.Angles(0, math.pi / 2, 0), bark)
	rod(parent, name .. "Trunk2", 0.85 * scale, h * 0.55, tilt * CFrame.new(jit(0.5), h * 0.82, jit(0.5)) * CFrame.Angles(0, math.pi / 2, 0), bark)
	for i = 1, 5 do
		local a = i * 1.256
		local r = 1.5 * scale
		box(parent, string.format("%sRoot%d", name, i), Vector3.new(0.7 * scale, 0.6 * scale, 2.6 * scale),
			tilt * CFrame.new(math.cos(a) * r, 0.5, math.sin(a) * r) * CFrame.Angles(0.35, -a, 0), bark)
	end
	if kind == "dead" then
		for i = 1, 5 do
			local a = i * 1.9 + jit(0.4)
			local up = h * (0.72 + 0.07 * i)
			box(parent, string.format("%sBranch%d", name, i), Vector3.new(0.42 * scale, 0.42 * scale, 5.5 * scale),
				tilt * CFrame.new(math.cos(a) * 1.2, up, math.sin(a) * 1.2) * CFrame.Angles(0.75, -a, 0), bark)
		end
	elseif kind == "pine" then
		for i = 1, 5 do
			local w = (7 - i) * 1.5 * scale
			box(parent, string.format("%sTier%d", name, i), Vector3.new(w, 1.5 * scale, w),
				tilt * CFrame.new(0, h * 0.55 + i * 2.2 * scale, 0) * CFrame.Angles(jit(0.08), jit(0.5), jit(0.08)), leaf)
		end
	else
		for i = 1, 6 do
			local w = (7.5 + jitAbs(4)) * scale
			box(parent, string.format("%sCrown%d", name, i), Vector3.new(w, 2.6 * scale, w),
				tilt * CFrame.new(jit(2.2), h * 0.95 + jitAbs(3.5) * scale, jit(2.2)) * CFrame.Angles(jit(0.25), jit(3.1), jit(0.25)), leaf)
		end
	end
end

phase(function(root)
	local ground = model(root, "Ground")
	-- worn paths: slabs laid a finger proud of the grass so they read as trodden ground
	local function path(name, x, z, w, d, rot)
		box(ground, name, Vector3.new(w, 0.14, d), CFrame.new(x, 0.07, z) * CFrame.Angles(0, math.rad(rot or 0), 0), P.dirt)
	end
	path("PathApproach", 0, -50, 13, 26)
	path("PathTurn", 12, -40, 22, 11, 6)
	path("PathSideE", 30, -6, 24, 11, 4)
	path("PathToGraves", 28, 24, 11, 26, -3)
	path("PathGrave", 12, 40, 30, 10)
	path("PathWest", -30, 8, 24, 10, -5)
	-- the plinth edge is a three stud step: give the player a way up on both busy sides
	steps(ground, "SideStep", 26.5, 8, 6, 1.2, 3, P.trim)
	steps(ground, "BreachRamp", 24.6, 0, 9, 1.3, 3, P.plinth)
	for i = 1, 4 do
		local s = 1.4 + jitAbs(1.2)
		box(ground, string.format("BreachRubble%d", i), Vector3.new(s, s * 0.8, s * 1.4),
			CFrame.new(23.5 + jit(1.5), 1.2 + jitAbs(1.5), jit(4)) * CFrame.Angles(0.2 + jit(0.3), jit(3.1), 0.15 + jit(0.3)), P.plinth)
	end
	-- moss and leaf litter where the canopy is thick, and along the north wall
	for i = 1, 10 do
		local s = 2.5 + jitAbs(4)
		box(ground, string.format("MossPatch%d", i), Vector3.new(s, 0.12, s * (0.6 + jitAbs(0.6))),
			CFrame.new(jit(64) * (if i % 2 == 0 then 1 else -1), 0.06, -46 + jitAbs(90)) * CFrame.Angles(0, jit(3.1), 0), P.moss)
	end

	-- ---- cemetery: irregular rows, varied stones, several of them down ------------------
	local cem = model(root, "Cemetery")
	box(cem, "Field", Vector3.new(66, 0.16, 32), CFrame.new(1, 0.08, 51), P.dirt)
	local graves = {
		{ -24, 39, "slab", -8 }, { -18, 44, "cross", 12 }, { -11, 38, "stub", 4 },
		{ -4, 45, "slab", -14 }, { 4, 39, "fallen", 20 }, { 11, 46, "cross", -6 },
		{ 19, 40, "tomb", 0 }, { 26, 47, "obelisk", 5 }, { -26, 51, "stub", -11 },
		{ -15, 55, "slab", 9 }, { -6, 60, "cross", -4 }, { 3, 54, "fallen", -18 },
		{ 13, 61, "slab", 15 }, { 22, 56, "tomb", 3 }, { 30, 62, "stub", 7 },
		{ -22, 63, "cross", -13 },
	}
	for i, g in ipairs(graves) do
		local x, z, kind, tilt = g[1], g[2], g[3], math.rad(g[4])
		local name = string.format("Grave%d", i)
		local cf = CFrame.new(x, 0.1, z) * CFrame.Angles(0, jit(0.5), 0)
		if kind == "slab" then
			box(cem, name, Vector3.new(1.5, 2.6, 0.42), cf * CFrame.Angles(tilt, 0, jit(0.06)) * CFrame.new(0, 1.2, 0), P.trim)
			box(cem, name .. "Foot", Vector3.new(1.7, 0.5, 0.6), cf * CFrame.new(0, 0.15, 1.6), P.plinth)
		elseif kind == "cross" then
			box(cem, name .. "Up", Vector3.new(0.45, 2.9, 0.45), cf * CFrame.Angles(tilt, 0, jit(0.05)) * CFrame.new(0, 1.4, 0), P.trim)
			box(cem, name .. "Arm", Vector3.new(1.6, 0.45, 0.45), cf * CFrame.Angles(tilt, 0, 0) * CFrame.new(0, 2.2, 0), P.trim)
			box(cem, name .. "Base", Vector3.new(1.5, 0.6, 1.2), cf * CFrame.new(0, 0.2, 0), P.plinth)
		elseif kind == "stub" then
			box(cem, name, Vector3.new(1.3, 1.1, 0.4), cf * CFrame.Angles(tilt * 1.6, 0, jit(0.1)) * CFrame.new(0, 0.5, 0), P.trim)
			box(cem, name .. "Chunk", Vector3.new(1.1, 0.9, 0.4), cf * CFrame.Angles(0.1, jit(0.6), math.rad(84)) * CFrame.new(1.9, 0.28, 0.6), P.trim)
		elseif kind == "fallen" then
			box(cem, name, Vector3.new(1.4, 0.42, 2.4), cf * CFrame.Angles(0, 0, 0) * CFrame.new(0, 0.12, 0), P.trim)
			box(cem, name .. "Base", Vector3.new(1.4, 0.5, 0.6), cf * CFrame.new(0, 0.14, -1.8), P.plinth)
		elseif kind == "tomb" then
			box(cem, name .. "Chest", Vector3.new(3.6, 1.3, 1.9), cf * CFrame.new(0, 0.75, 0), P.plinth)
			box(cem, name .. "Lid", Vector3.new(3.9, 0.35, 2.2), cf * CFrame.Angles(tilt * 0.6, 0, 0) * CFrame.new(0, 1.55, 0), P.trim)
			box(cem, name .. "Kerb", Vector3.new(4.6, 0.3, 2.8), cf * CFrame.new(0, 0.15, 0), P.plinth)
		elseif kind == "obelisk" then
			box(cem, name .. "Base", Vector3.new(2.4, 0.7, 2.4), cf * CFrame.new(0, 0.35, 0), P.plinth)
			box(cem, name .. "Block", Vector3.new(1.8, 1.0, 1.8), cf * CFrame.new(0, 1.2, 0), P.trim)
			box(cem, name .. "Shaft", Vector3.new(1.2, 3.4, 1.2), cf * CFrame.Angles(tilt * 0.4, 0, 0) * CFrame.new(0, 3.4, 0), P.trim)
			box(cem, name .. "Cap", Vector3.new(0.9, 0.9, 0.9), cf * CFrame.new(0, 5.5, 0), P.trim)
		end
		if i % 3 == 0 then
			local s = 1.6 + jitAbs(1.4)
			box(cem, name .. "Ivy", Vector3.new(s, 0.4, s * 0.7), cf * CFrame.new(jit(0.8), 0.25, jit(0.8)), P.moss)
		end
	end
	-- the boundary wall: three runs with a gap for the gate, and the gate itself down
	for i, run in ipairs({ { -33, 36, -33, 66 }, { -33, 36, 20, 36 }, { -20, 68, 33, 68 } }) do
		local a = Vector3.new(run[1], 0, run[2])
		local b = Vector3.new(run[3], 0, run[4])
		seg(cem, string.format("Wall%d", i), a, b, 0, 3, 1.1, P.plinth)
		seg(cem, string.format("WallCap%d", i), a, b, 3, 3.5, 1.5, P.trim)
	end
	for _, p in ipairs({ { 20, 36 }, { 33, 45 } }) do
		box(cem, string.format("GatePost%d", p[1]), Vector3.new(1.6, 5.2, 1.6), CFrame.new(p[1], 2.6, p[2]), P.trim)
		box(cem, string.format("GateCap%d", p[1]), Vector3.new(2.1, 0.6, 2.1), CFrame.new(p[1], 5.4, p[2]), P.trim)
	end
	box(cem, "GateDown", Vector3.new(10.5, 2.6, 0.3), CFrame.new(26.5, 0.5, 38) * CFrame.Angles(0, math.rad(-24), 0), P.iron)
	for i = 1, 6 do
		box(cem, string.format("GateBar%d", i), Vector3.new(0.22, 2.2, 0.22),
			CFrame.new(21.6 + i * 1.55, 1.5, 38.6 + i * 0.35) * CFrame.Angles(0.1, 0, 0), P.iron)
	end
	-- ---- forest: seeded rejection sampling, so no two trees line up ----------------------
	local forest = model(root, "Forest")
	local keepOut = {
		{ -30, 30, -38, 34 },   -- cathedral and its platform
		{ -36, 36, 34, 70 },    -- cemetery
		{ -18, 18, -60, -38 },  -- the approach
	}
	local placed = {}
	local function free(x, z, r)
		if math.abs(x) > 71 or math.abs(z) > 71 then return false end
		for _, k in ipairs(keepOut) do
			if x > k[1] - r and x < k[2] + r and z > k[3] - r and z < k[4] + r then return false end
		end
		for _, p in ipairs(placed) do
			if (Vector3.new(x, 0, z) - Vector3.new(p[1], 0, p[2])).Magnitude < r + p[3] then return false end
		end
		return true
	end
	local kinds = { "oak", "oak", "oak", "pine", "pine", "dead" }
	local made = 0
	for attempt = 1, 900 do
		if made >= 24 then break end
		local ring = 44 + jitAbs(26)
		local ang = jitAbs(6.28)
		local x, z = math.cos(ang) * ring, math.sin(ang) * ring
		local r = 4.5
		if free(x, z, r) then
			made += 1
			table.insert(placed, { x, z, r })
			local kind = kinds[1 + (made * 7) % #kinds]
			tree(forest, string.format("Tree%d", made), x, z, 0.85 + jitAbs(0.5), kind, jit(0.06))
		end
	end
	-- undergrowth: rocks, bushes, ferns, a couple of logs, mushrooms
	for i = 1, 16 do
		local x, z = jit(66), jit(66)
		if math.abs(x) > 26 or math.abs(z) > 30 then
			local s = 1.6 + jitAbs(2.4)
			box(forest, string.format("Rock%d", i), Vector3.new(s, s * 0.72, s * 1.3),
				CFrame.new(x, s * 0.22, z) * CFrame.Angles(0.16 + jit(0.3), jit(3.1), 0.12 + jit(0.3)), P.plinth)
		end
	end
	for i = 1, 14 do
		local x, z = jit(68), jit(68)
		if math.abs(x) > 24 or math.abs(z) > 28 then
			local s = 2.2 + jitAbs(1.6)
			box(forest, string.format("Bush%d", i), Vector3.new(s, s * 0.8, s), CFrame.new(x, s * 0.4, z) * CFrame.Angles(jit(0.3), jit(3.1), jit(0.3)), P.leaf)
			box(forest, string.format("BushTop%d", i), Vector3.new(s * 0.7, s * 0.6, s * 0.7),
				CFrame.new(x + jit(0.8), s * 0.9, z + jit(0.8)) * CFrame.Angles(jit(0.4), jit(3.1), jit(0.4)), P.moss)
		end
	end
	for i = 1, 10 do
		local x, z = jit(70), jit(70)
		if math.abs(x) > 22 or math.abs(z) > 26 then
			for k = 1, 3 do
				box(forest, string.format("Fern%d_%d", i, k), Vector3.new(0.28, 0.28, 2.4),
					CFrame.new(x + jit(1), 0.9, z + jit(1)) * CFrame.Angles(0.55, k * 2.1 + jit(0.4), 0), P.leaf)
			end
		end
	end
	for i, l in ipairs({ { -52, -20, 34 }, { 46, 30, -28 }, { -40, 44, 62 } }) do
		box(forest, string.format("Log%d", i), Vector3.new(1.7, 1.7, 13),
			CFrame.new(l[1], 0.8, l[2]) * CFrame.Angles(0, math.rad(l[3]), 0.05), P.bark)
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
