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

local INSPECT = false -- true only for a look inside: draws the roof and one wall see-through
local NIGHT = true   -- false leaves game.Lighting exactly as it was found

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

local function at(v) return typeof(v) == "CFrame" and v.Position or v end

local function beamBetween(parent, name, a, b, w, h, role)  -- box with Z along a -> b
	a, b = at(a), at(b)
	local mid, len = (a + b) / 2, (b - a).Magnitude
	return box(parent, name, Vector3.new(w, h or w, len), CFrame.lookAt(mid, b), role)
end

local function rodBetween(parent, name, a, b, r, role)  -- cylinder with X along a -> b
	a, b = at(a), at(b)
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
		-- each step is a finger narrower and set a hair lower than the last, so no two faces line up
		local h = top + i * 0.07
		box(parent, string.format("%s%d", name, i), Vector3.new(width - i * 0.06, h, tread + 0.1),
			CFrame.new(cx, top - h / 2, z0 + (tread + 0.1) / 2), role)
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
				for k, edge in ipairs({ { -0.05, 0.4 }, { 0.6, 1.05 } }) do   -- d is distance down the slope from the ridge
					local segLen = (edge[2] - edge[1]) * len
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
		box(roof, string.format("Ridge%d", i), Vector3.new(2.2, 2.4, run[2] - run[1] + 0.3),
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
		for i = 1, 4 do   -- boughs first, so the crown has something to sit on
			local a = i * 1.57 + jit(0.3)
			box(parent, string.format("%sBough%d", name, i), Vector3.new(0.5 * scale, 0.5 * scale, 4.2 * scale),
				tilt * CFrame.new(math.cos(a), h * 0.85, math.sin(a)) * CFrame.Angles(0.5, -a, 0), bark)
		end
		for i = 1, 5 do
			local w = (8.0 + jitAbs(4.5)) * scale
			box(parent, string.format("%sCrown%d", name, i), Vector3.new(w, (3.2 + jitAbs(1.6)) * scale, w * (0.75 + jitAbs(0.4))),
				tilt * CFrame.new(jit(2.4), h * 0.92 + jitAbs(4.5) * scale, jit(2.4)) * CFrame.Angles(jit(0.25), jit(3.1), jit(0.25)), leaf)
		end
	end
end

phase(function(root)
	local ground = model(root, "Ground")
	-- the map floor: one slab, and a wider low skirt so the 150 stud edge reads as ground going on
	box(ground, "Slab", Vector3.new(MAP, 3, MAP), CFrame.new(0, -1.5, 0), P.ground)
	box(ground, "Skirt", Vector3.new(MAP + 40, 2, MAP + 40), CFrame.new(0, -3.4, 0), P.dirt)
	for i = 1, 10 do
		local w = 8 + jitAbs(14)
		box(ground, string.format("Mound%d", i), Vector3.new(w, 1.1 + jitAbs(1.4), w * 0.8),
			CFrame.new(jit(70), 0.4, jit(70)) * CFrame.Angles(0.03, jit(3.1), 0.03), P.ground)
	end
	-- worn paths: slabs laid a finger proud of the grass so they read as trodden ground
	local function path(name, x, z, w, d, rot)
		box(ground, name, Vector3.new(w, 0.14, d), CFrame.new(x, 0.07, z) * CFrame.Angles(0, math.rad(rot or 0), 0), P.dirt)
	end
	path("PathApproach", 0, -50, 13, 26)
	path("PathTurn", 12, -40, 22, 11, 11)
	path("PathSideE", 30, -6, 24, 11, -13)
	path("PathToGraves", 28, 24, 11, 26, 9)
	path("PathGrave", 12, 40, 30, 10)
	path("PathWest", -30, 8, 24, 10, -16)
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
		box(ground, string.format("MossPatch%d", i), Vector3.new(s, 0.16, s * (0.6 + jitAbs(0.6))),
			CFrame.new(18 + jitAbs(16) * (if i % 2 == 0 then 1 else -1), 0.07, -30 + jitAbs(50)) * CFrame.Angles(0, jit(3.1), 0), P.moss)
	end

	-- ---- cemetery: irregular rows, varied stones, several of them down ------------------
	local cem = model(root, "Cemetery")
	for i = 1, 7 do   -- grave earth, patchy, so the burying ground is not one flat board
		local w = 16 + jitAbs(14)
		box(cem, string.format("Earth%d", i), Vector3.new(w, 0.14, 10 + jitAbs(8)),
			CFrame.new(-24 + (i - 1) * 8 + jit(3), 0.07, 42 + (i % 3) * 9 + jit(3)) * CFrame.Angles(0, jit(0.5), 0), P.dirt)
	end
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

--=====================================================================================
-- PHASE 6 -- THE SOLDIER. The one prop the map is remembered by: a long-dead man slumped
-- against the broken tower, run through with his own sword. No rig, no mesh: bones are
-- boxes and thin cylinders laid along the pose, armour is layered plates over them.
--=====================================================================================
phase(function(root)
	local props = model(root, "Soldier")
	local ground = PLINTH_TOP
	-- he sits with his back to the tower's inner face, legs folded to his left, head rolled
	-- forward and down. `hip` is the root of the pose; everything else hangs off it.
	local hip = CFrame.new(9.1, ground + 0.55, -28.6) * CFrame.Angles(0, math.rad(-24), 0)
	local bone, steel, iron, leather = P.bone, P.bone, P.iron, P.beam
	-- pelvis and spine
	box(props, "Pelvis", Vector3.new(1.9, 0.9, 1.3), hip * CFrame.new(0, 0, 0), P.iron)
	box(props, "Belt", Vector3.new(2.1, 0.36, 1.5), hip * CFrame.new(0, 0.42, 0), leather)
	box(props, "Buckle", Vector3.new(0.42, 0.42, 0.22), hip * CFrame.new(0, 0.42, -0.78), P.brass)
	local spine = { { 0.55, 0.28, 0.5, 0.3 }, { 1.1, 0.5, 0.85, 0.34 }, { 1.6, 0.66, 1.15, 0.36 }, { 2.05, 0.72, 1.4, 0.36 } }
	for i, s in ipairs(spine) do
		box(props, string.format("Vertebra%d", i), Vector3.new(0.5, 0.42, 0.5),
			hip * CFrame.new(0, s[2], -s[1] * 0.5) * CFrame.Angles(-0.12 * i, 0, 0), bone)
	end
	-- ribcage: six pairs of thin bars curving forward off the spine, then the sternum
	local chest = hip * CFrame.new(0, 1.85, -0.55) * CFrame.Angles(-0.35, 0, 0.12)
	for i = 1, 6 do
		local w = 1.55 - i * 0.12
		local y = -i * 0.34 + 0.7
		for _, sx in ipairs({ 1, -1 }) do
			rod(props, string.format("Rib%d%s", i, if sx > 0 then "a" else "b"), 0.09, w,
				chest * CFrame.new(sx * w / 2, y, -0.35) * CFrame.Angles(0, 0, math.rad(90) + sx * 0.25), bone)
		end
	end
	box(props, "Sternum", Vector3.new(0.34, 1.5, 0.26), chest * CFrame.new(0, -0.35, -0.7), bone)
	box(props, "CollarL", Vector3.new(0.9, 0.2, 0.2), chest * CFrame.new(0.5, 0.85, -0.4) * CFrame.Angles(0, 0, -0.25), bone)
	box(props, "CollarR", Vector3.new(0.9, 0.2, 0.2), chest * CFrame.new(-0.5, 0.85, -0.4) * CFrame.Angles(0, 0, 0.25), bone)
	-- the sword: in through the right shoulder blade, out through the chest, into the ground
	local bladeCF = chest * CFrame.Angles(math.rad(58), 0, math.rad(14)) * CFrame.new(0, 0, -1.0)
	box(props, "Blade", Vector3.new(0.34, 0.12, 7.4), bladeCF, iron)
	box(props, "BladeTip", Vector3.new(0.24, 0.12, 0.6), bladeCF * CFrame.new(0, 0, 3.9), iron)
	box(props, "Guard", Vector3.new(1.5, 0.24, 0.24), bladeCF * CFrame.new(0, 0, -3.8), P.brass)
	rod(props, "Grip", 0.17, 1.1, bladeCF * CFrame.new(0, 0, -4.5) * CFrame.Angles(0, math.pi / 2, 0), leather)
	box(props, "Pommel", Vector3.new(0.4, 0.4, 0.4), bladeCF * CFrame.new(0, 0, -5.2), P.brass)
	-- armour: a shoulder plate still buckled on, the breastplate undone and hanging open
	box(props, "PauldronTop", Vector3.new(1.3, 0.4, 1.5), chest * CFrame.new(0.95, 1.0, -0.2) * CFrame.Angles(0, 0, -0.3), iron)
	box(props, "PauldronSkirt", Vector3.new(1.2, 0.9, 1.4), chest * CFrame.new(1.15, 0.45, -0.15) * CFrame.Angles(0, 0, -0.18), iron)
	box(props, "PauldronRim", Vector3.new(1.4, 0.16, 1.6), chest * CFrame.new(1.05, 1.22, -0.2) * CFrame.Angles(0, 0, -0.3), P.brass)
	box(props, "Breastplate", Vector3.new(1.9, 1.9, 0.3), chest * CFrame.new(-0.8, -0.5, -1.15) * CFrame.Angles(0.2, math.rad(38), 0.35), iron)
	box(props, "BreastplateRim", Vector3.new(2.0, 0.16, 0.34), chest * CFrame.new(-0.8, 0.4, -1.2) * CFrame.Angles(0.2, math.rad(38), 0.35), P.brass)
	box(props, "Tabard", Vector3.new(1.5, 1.3, 0.14), chest * CFrame.new(-0.15, -1.0, -0.75) * CFrame.Angles(0.15, 0, 0.1), P.flag)
	-- skull: cranium, brow, sockets, jaw, all tipped forward and to one side
	local neck = chest * CFrame.new(-0.1, 0.95, -0.55)
	box(props, "Neck", Vector3.new(0.4, 0.7, 0.4), neck * CFrame.new(0, 0.2, 0), bone)
	local skull = neck * CFrame.Angles(-0.55, math.rad(-16), 0.42) * CFrame.new(0, 0.85, -0.1)
	box(props, "Cranium", Vector3.new(0.95, 0.95, 1.0), skull, bone)
	box(props, "BrowRidge", Vector3.new(1.0, 0.24, 0.3), skull * CFrame.new(0, 0.2, -0.5), bone)
	box(props, "Face", Vector3.new(0.8, 0.62, 0.36), skull * CFrame.new(0, -0.2, -0.46), bone)
	box(props, "SocketL", Vector3.new(0.26, 0.28, 0.2), skull * CFrame.new(0.24, -0.12, -0.6), P.plinth)
	box(props, "SocketR", Vector3.new(0.26, 0.28, 0.2), skull * CFrame.new(-0.24, -0.12, -0.6), P.plinth)
	box(props, "Nose", Vector3.new(0.16, 0.24, 0.18), skull * CFrame.new(0, -0.34, -0.6), P.plinth)
	box(props, "Jaw", Vector3.new(0.78, 0.34, 0.62), skull * CFrame.new(0, -0.6, -0.28) * CFrame.Angles(0.35, 0, 0), bone)
	box(props, "Teeth", Vector3.new(0.6, 0.12, 0.5), skull * CFrame.new(0, -0.46, -0.34), bone)
	-- arms: the right one folded across the chest, the left hanging to the floor
	local function arm(name, shoulder, elbow, hand, r)
		rodBetween(props, name .. "Upper", shoulder, elbow, r, bone)
		rodBetween(props, name .. "Fore", elbow, hand, r * 0.85, bone)
		local hPos, ePos = hand.Position, elbow.Position
		box(props, name .. "Hand", Vector3.new(0.3, 0.22, 0.5), CFrame.lookAt(hPos, hPos + (hPos - ePos)), bone)
		for i = 1, 3 do
			box(props, string.format("%sFinger%d", name, i), Vector3.new(0.14, 0.14, 0.38),
				CFrame.lookAt(hPos + (hPos - ePos).Unit * 0.3, hPos + (hPos - ePos)) * CFrame.new((i - 2) * 0.16, 0, 0), bone)
		end
	end
	local shR = chest * CFrame.new(-0.15, 0.75, -0.85)
	local elR = chest * CFrame.new(-1.05, -0.35, -1.15)
	arm("ArmR", shR, elR, chest * CFrame.new(0.35, -1.15, -1.25), 0.17)
	local shL = chest * CFrame.new(0.15, 0.7, -0.8)
	arm("ArmL", shL, chest * CFrame.new(-0.45, -1.3, -0.35), hip * CFrame.new(-1.35, 0.35, -1.5), 0.17)
	box(props, "VambraceL", Vector3.new(0.5, 0.95, 0.5), chest * CFrame.new(-0.7, -1.6, -0.4) * CFrame.Angles(0.4, 0, 0.2), iron)
	-- legs folded under and to his left, one boot still laced, one lost
	local kneeR = hip * CFrame.new(-1.5, -0.15, -1.5)
	local footR = hip * CFrame.new(-2.6, 0.1, 0.15)
	rodBetween(props, "ThighR", hip * CFrame.new(-0.6, 0.1, 0), kneeR, 0.24, bone)
	rodBetween(props, "ShinR", kneeR, footR, 0.2, bone)
	box(props, "BootR", Vector3.new(0.62, 0.5, 1.5), CFrame.new(footR.Position + Vector3.new(-0.2, -0.05, 0.75)) * CFrame.Angles(0, math.rad(-70), 0), leather)
	local kneeL = hip * CFrame.new(-0.9, -0.25, 1.15)
	local footL = hip * CFrame.new(0.5, 0.1, 2.1)
	rodBetween(props, "ThighL", hip * CFrame.new(-0.4, 0.1, 0.4), kneeL, 0.24, bone)
	rodBetween(props, "ShinL", kneeL, footL, 0.2, bone)
	box(props, "GreaveL", Vector3.new(0.56, 0.56, 1.1), CFrame.lookAt((kneeL.Position + footL.Position) / 2, footL.Position), iron) -- guarded: both are CFrames here
	box(props, "BootL", Vector3.new(0.6, 0.5, 1.4), CFrame.new(footL.Position + Vector3.new(0.4, -0.04, 0.5)) * CFrame.Angles(0, math.rad(35), 0), leather)
	-- his helm came off and rolled: it lies a couple of studs away, dented
	box(props, "Helm", Vector3.new(1.1, 0.95, 1.2), CFrame.new(6.4, ground + 0.5, -27.2) * CFrame.Angles(0.2, math.rad(28), 1.5), iron)
	box(props, "HelmRim", Vector3.new(1.25, 0.16, 1.35), CFrame.new(6.4, ground + 0.12, -27.2) * CFrame.Angles(0.2, math.rad(28), 1.5), P.brass)
	box(props, "HelmNasal", Vector3.new(0.18, 0.9, 0.3), CFrame.new(6.0, ground + 0.35, -27.8) * CFrame.Angles(0.3, math.rad(28), 0.2), iron)
	-- his shield, dropped face up in the leaves beside him
	box(props, "Shield", Vector3.new(2.2, 0.28, 2.8), CFrame.new(5.2, ground + 0.2, -31.2) * CFrame.Angles(0, math.rad(24), 0.06), P.beam)
	box(props, "ShieldBoss", Vector3.new(0.7, 0.34, 0.7), CFrame.new(5.2, ground + 0.42, -31.2) * CFrame.Angles(0, math.rad(24), 0.06), P.brass)
	box(props, "ShieldRim", Vector3.new(2.4, 0.16, 3.0), CFrame.new(5.2, ground + 0.1, -31.2) * CFrame.Angles(0, math.rad(24), 0), P.iron)
	-- and the ground he fell on: leaves drifted against him, moss creeping over the boot
	box(props, "Leaves1", Vector3.new(2.6, 0.14, 2.0), CFrame.new(7.6, ground + 0.06, -29.6) * CFrame.Angles(0, math.rad(20), 0), P.moss)
	box(props, "Leaves2", Vector3.new(2.0, 0.12, 1.6), CFrame.new(10.2, ground + 0.05, -26.4) * CFrame.Angles(0, math.rad(-35), 0), P.moss)
end)

--=====================================================================================
-- PHASE 7 -- LIGHT AND AIR. Every light is a Light instance with a visible source; every
-- shaft is a Beam between two attachments; every emitter is set up for what it is.
--=====================================================================================

local function flame(parent, name, at, size, range, brightness, colour)
	local core = box(parent, name, Vector3.new(size, size, size), at, P.brass)
	core.Material = Enum.Material.Neon
	core.Color = colour or Color3.fromRGB(255, 206, 138)
	local light = ensure(core, "Glow", "PointLight")
	light.Brightness, light.Range, light.Color = brightness, range, colour or Color3.fromRGB(255, 196, 120)
	return core
end

local function candle(parent, name, at, h, lit)
	local wax = P.bone
	rod(parent, name .. "Wax", 0.16, h, at, wax)
	if lit then
		flame(parent, name .. "Flame", at * CFrame.new(0, 0, -(h / 2 + 0.28)) * CFrame.Angles(0, math.pi / 2, 0), 0.3, 9, 1.6)
	end
end

local function lantern(parent, name, at, scale)
	local s = scale or 1
	box(parent, name .. "Top", Vector3.new(0.9 * s, 0.16 * s, 0.9 * s), at * CFrame.new(0, 0.75 * s, 0), P.brass)
	box(parent, name .. "Base", Vector3.new(0.8 * s, 0.16 * s, 0.8 * s), at * CFrame.new(0, -0.7 * s, 0), P.brass)
	for _, c in ipairs({ { 0.34, 0.34 }, { -0.34, 0.34 }, { 0.34, -0.34 }, { -0.34, -0.34 } }) do
		box(parent, string.format("%sPost%d%d", name, c[1] > 0 and 1 or 0, c[2] > 0 and 1 or 0),
			Vector3.new(0.12 * s, 1.45 * s, 0.12 * s), at * CFrame.new(c[1] * s, 0, c[2] * s), P.brass)
	end
	box(parent, name .. "Ring", Vector3.new(0.24 * s, 0.3 * s, 0.24 * s), at * CFrame.new(0, 0.95 * s, 0), P.iron)
end

phase(function(root)
	local fx = model(root, "Effects")
	local cath = model(root, "Cathedral")
	local inside = model(cath, "Interior")
	-- ---- hanging lanterns, wall sconces, altar candles ---------------------------------
	local hang = { { -5.4, -10.5, 15.6 }, { 4.6, -1.5, 14.4 }, { -3.2, 9.5, 15.2 } }
	for i, h in ipairs(hang) do
		local at = CFrame.new(h[1], h[3], h[2])
		rod(inside, string.format("Chain%d", i), 0.1, 3.6, at * CFrame.new(0, 1.8, 0), P.iron)
		for k = 1, 4 do
			box(inside, string.format("Chain%dLink%d", i, k), Vector3.new(0.3, 0.1, 0.1), at * CFrame.new(0, 0.6 + k * 0.6, 0) * CFrame.Angles(0, 0, k * 0.8), P.iron)
		end
		lantern(inside, string.format("Lantern%d", i), at * CFrame.new(0, -0.4, 0), 1)
		flame(inside, string.format("Lantern%dGlow", i), at * CFrame.new(0, -0.35, 0), 0.42, 15, 2.2)
	end
	for i, s in ipairs({ { -11.2, -13.5, 8.6 }, { 11.2, 7.5, 8.6 } }) do
		local at = CFrame.new(s[1], s[3], s[2]) * CFrame.Angles(0, if s[1] > 0 then math.pi / 2 else -math.pi / 2, 0)
		box(inside, string.format("Sconce%d", i), Vector3.new(0.5, 0.4, 0.9), at * CFrame.new(0, 0, 0.45), P.brass)
		box(inside, string.format("Sconce%dBracket", i), Vector3.new(0.34, 0.9, 0.34), at * CFrame.new(0, -0.6, 0.2), P.iron)
		candle(inside, string.format("Sconce%dCandle", i), at * CFrame.new(0, 0.75, 0.55) * CFrame.Angles(0, -math.pi / 2, 0), 1.1, true)
	end
	-- candles on the altar and on the sanctuary step
	for i, c in ipairs({ { -3.4, 21.4, 1.2 }, { -2.2, 21.7, 0.9 }, { 2.6, 21.6, 1.1 }, { 3.8, 21.3, 0.8 } }) do
		candle(inside, string.format("AltarCandle%d", i), CFrame.new(c[1], 8.3 + c[3] / 2, c[2]), c[3], true)
	end
	for i, c in ipairs({ { -5.6, 16.4, 0.75 }, { 5.2, 16.8, 0.75 } }) do
		candle(inside, string.format("StepCandle%d", i), CFrame.new(c[1], 4.35 + c[2] * 0 + c[3] / 2, c[2]), c[3], i == 1)
	end
	-- a lantern left on the porch step, which is what lights the soldier outside
	lantern(model(cath, "Porch"), "PorchLantern", CFrame.new(8.2, PLINTH_TOP + 1.1, -28.4), 1.15)
	flame(model(cath, "Porch"), "PorchLanternGlow", CFrame.new(8.2, PLINTH_TOP + 1.05, -28.4), 0.5, 17, 2.4)
	box(model(cath, "Porch"), "PorchLanternBracket", Vector3.new(0.5, 0.5, 1.2), CFrame.new(9.5, PLINTH_TOP + 1.1, -28.4), P.iron)
	-- ---- light shafts through the broken roof and the aisle breach -----------------------
	local shafts = {
		{ { -7.6, 39.2, -8.0 }, { -3.4, FLOOR, -7.2 }, 11, 15, Color3.fromRGB(150, 172, 214) },
		{ { 7.6, 39.2, 8.0 }, { 3.6, FLOOR, 8.4 }, 10, 13, Color3.fromRGB(150, 172, 214) },
		{ { 19.5, 12.6, 0.0 }, { 15.0, FLOOR, 0.4 }, 8, 11, Color3.fromRGB(168, 184, 220) },
	}
	for i, s in ipairs(shafts) do
		local top, bottom = Vector3.new(s[1][1], s[1][2], s[1][3]), Vector3.new(s[2][1], s[2][2], s[2][3])
		local a0 = ensure(fx, string.format("Shaft%dTop", i), "Attachment")
		a0.WorldPosition = top
		local a1 = ensure(fx, string.format("Shaft%dFoot", i), "Attachment")
		a1.WorldPosition = bottom
		local beam = ensure(fx, string.format("Shaft%d", i), "Beam")
		beam.Attachment0, beam.Attachment1 = a0, a1
		beam.Width0, beam.Width1 = s[3], s[4]
		beam.Color = ColorSequence.new(s[5])
		beam.LightEmission = 1
		beam.FaceCamera = false
		beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.82), NumberSequenceKeypoint.new(0.45, 0.9), NumberSequenceKeypoint.new(1, 1) })
		beam.Texture = "rbxasset://textures/particles/smoke_main.dds"
		beam.TextureSpeed = 0.06
		-- the moonlight that makes the shaft readable, aimed down it
		local carrier = ensure(fx, string.format("Shaft%dLight", i), "Part")
		carrier.Size, carrier.Anchored, carrier.CanCollide = Vector3.new(1, 1, 1), true, false
		carrier.Transparency, carrier.CanQuery = 1, false
		carrier.CFrame = CFrame.lookAt(top, bottom)
		local spot = ensure(carrier, "Moon", "SpotLight")
		spot.Angle, spot.Range, spot.Brightness = 70, 70, 2.6
		spot.Face, spot.Color = Enum.NormalId.Front, Color3.fromRGB(158, 180, 224)
		local dust = ensure(carrier, "Motes", "ParticleEmitter")
		dust.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		dust.Color = ColorSequence.new(Color3.fromRGB(198, 210, 236))
		dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.09), NumberSequenceKeypoint.new(1, 0.02) })
		dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
		dust.Lifetime, dust.Rate, dust.Speed = NumberRange.new(7, 10), 9, NumberRange.new(0.1, 0.3)
		dust.SpreadAngle, dust.LightEmission, dust.Acceleration = Vector2.new(24, 24), 0.7, Vector3.new(0, -0.25, 0)
		dust.RotSpeed, dust.Rotation = NumberRange.new(-14, 14), NumberRange.new(0, 360)
	end
	-- ---- ground fog and candle smoke, restrained -----------------------------------------
	local fogs = { { -42, 1.3, -18, 34, 30 }, { 44, 1.3, 12, 32, 28 }, { 2, 1.3, -50, 40, 24 }, { 4, 1.3, 46, 40, 26 }, { 30, 1.3, 60, 34, 24 } }
	for i, f in ipairs(fogs) do
		local c = ensure(fx, string.format("FogCarrier%d", i), "Part")
		c.Size, c.Anchored, c.CanCollide = Vector3.new(f[4], 1, f[5]), true, false
		c.Transparency, c.CanQuery = 1, false
		c.CFrame = CFrame.new(f[1], f[2], f[3])
		local em = ensure(c, "Fog", "ParticleEmitter")
		em.Texture = "rbxasset://textures/particles/smoke_main.dds"
		em.Color = ColorSequence.new(Color3.fromRGB(126, 136, 152))
		em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 9), NumberSequenceKeypoint.new(0.4, 15), NumberSequenceKeypoint.new(1, 18) })
		em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.88), NumberSequenceKeypoint.new(1, 1) })
		em.Lifetime, em.Rate, em.Speed = NumberRange.new(10, 15), 1.4, NumberRange.new(0.3, 0.7)
		em.SpreadAngle, em.Drag, em.LightEmission = Vector2.new(180, 180), 1, 0
		em.RotSpeed, em.Rotation = NumberRange.new(-3, 3), NumberRange.new(0, 360)
		em.Shape, em.ShapeStyle = Enum.ParticleEmitterShape.Box, Enum.ParticleEmitterShapeStyle.Volume
	end
	for i, e in ipairs({ { -5.4, 15.2, -10.5 }, { 4.6, 14.0, -1.5 }, { -3.4, 8.9, 21.4 } }) do
		local c = ensure(fx, string.format("EmberCarrier%d", i), "Part")
		c.Size, c.Anchored, c.CanCollide = Vector3.new(0.6, 0.6, 0.6), true, false
		c.Transparency, c.CanQuery = 1, false
		c.CFrame = CFrame.new(e[1], e[2], e[3])
		local em = ensure(c, "Embers", "ParticleEmitter")
		em.Texture = "rbxasset://textures/particles/fire_main.dds"
		em.Color = ColorSequence.new(Color3.fromRGB(255, 186, 108), Color3.fromRGB(178, 92, 44))
		em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.14), NumberSequenceKeypoint.new(1, 0) })
		em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
		em.Lifetime, em.Rate, em.Speed = NumberRange.new(1.1, 2.0), 3.5, NumberRange.new(1.0, 2.4)
		em.SpreadAngle, em.LightEmission, em.Acceleration = Vector2.new(12, 12), 1, Vector3.new(0, -1.1, 0)
		em.RotSpeed, em.Rotation = NumberRange.new(-40, 40), NumberRange.new(0, 360)
	end
end)

--=====================================================================================
-- PHASE 8 -- NIGHT, POST, AND THE QA PASS. Atmosphere is never touched: only Lighting's
-- own properties and two post effects this script owns by name.
--=====================================================================================
local function night()
	local Lighting = game:GetService("Lighting")
	Lighting.ClockTime = 0
	Lighting.GeographicLatitude = 12
	Lighting.Brightness = 1.5
	Lighting.Ambient = Color3.fromRGB(20, 22, 32)
	Lighting.OutdoorAmbient = Color3.fromRGB(30, 34, 50)
	Lighting.FogColor = Color3.fromRGB(17, 20, 30)
	Lighting.FogStart, Lighting.FogEnd = 40, 190
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.35
	Lighting.EnvironmentDiffuseScale = 0.25
	Lighting.EnvironmentSpecularScale = 0.2
	Lighting.ExposureCompensation = -0.1
	local bloom = Lighting:FindFirstChild("RuinedCathedralBloom") or Instance.new("BloomEffect")
	bloom.Name, bloom.Parent = "RuinedCathedralBloom", Lighting
	bloom.Intensity, bloom.Size, bloom.Threshold = 0.55, 26, 1.5
	local cc = Lighting:FindFirstChild("RuinedCathedralGrade") or Instance.new("ColorCorrectionEffect")
	cc.Name, cc.Parent = "RuinedCathedralGrade", Lighting
	cc.TintColor = Color3.fromRGB(198, 208, 238)
	cc.Contrast, cc.Saturation, cc.Brightness = 0.12, -0.06, -0.02
end

local function qa(root)
	local parts, aligned, seen = {}, {}, {}
	local dupes, thin = {}, {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			if d.Transparency < 1 then
				table.insert(parts, d)
				local o = d.CFrame.Rotation
				if math.abs(o.XVector.X) > 0.999 or math.abs(o.XVector.Y) > 0.999 or math.abs(o.XVector.Z) > 0.999 then
					local h = d.CFrame:VectorToWorldSpace(d.Size / 2)
					h = Vector3.new(math.abs(h.X), math.abs(h.Y), math.abs(h.Z))
					table.insert(aligned, { p = d, lo = d.Position - h, hi = d.Position + h })
				end
			end
			if math.min(d.Size.X, d.Size.Y, d.Size.Z) < 0.1 then table.insert(thin, d.Name) end
			local key = string.format("%s|%.2f,%.2f,%.2f|%.1f,%.1f,%.1f", d.Name, d.Size.X, d.Size.Y, d.Size.Z,
				d.Position.X, d.Position.Y, d.Position.Z)
			if seen[key] then table.insert(dupes, d.Name) else seen[key] = true end
		end
	end
	-- one pass over the axis aligned parts: faces that coincide while the volumes overlap flicker
	local E, coplanar, unsupported = 0.02, {}, {}
	for i = 1, #aligned do
		local a = aligned[i]
		local touching = false
		for j = 1, #aligned do
			if i ~= j then
				local b = aligned[j]
				local ox = a.lo.X < b.hi.X - E and b.lo.X < a.hi.X - E
				local oy = a.lo.Y < b.hi.Y - E and b.lo.Y < a.hi.Y - E
				local oz = a.lo.Z < b.hi.Z - E and b.lo.Z < a.hi.Z - E
				if ox or oy or oz then touching = true end
				if ox and oy and oz then
					for _, ax in ipairs({ "X", "Y", "Z" }) do
						local rest = (ax == "X" and oy and oz) or (ax == "Y" and ox and oz) or (ax == "Z" and ox and oy)
						if rest and (math.abs(a.lo[ax] - b.lo[ax]) < E or math.abs(a.hi[ax] - b.hi[ax]) < E) then
							if #coplanar < 8 then
								table.insert(coplanar, string.format("%s / %s on %s", a.p.Name, b.p.Name, ax))
							end
						end
					end
				end
				-- a part resting on another: tops and bottoms within a hair, footprints overlapping
				if not touching and math.abs(a.lo.Y - b.hi.Y) < 0.35 and a.lo.X < b.hi.X and b.lo.X < a.hi.X and a.lo.Z < b.hi.Z and b.lo.Z < a.hi.Z then
					touching = true
				end
			end
		end
		if not touching and #unsupported < 8 then table.insert(unsupported, a.p.Name) end
	end
	local function count(className)
		local n = 0
		for _, d in root:GetDescendants() do if d:IsA(className) then n += 1 end end
		return n
	end
	print(string.format("[RuinedCathedral] QA  %d parts (%d axis aligned) | %d lights, %d emitters, %d beams",
		#parts, #aligned, count("Light"), count("ParticleEmitter"), count("Beam")))
	print(string.format("[RuinedCathedral] QA  coplanar-flicker pairs: %d | near-duplicates: %d | unsupported: %d | paper thin: %d",
		#coplanar, #dupes, #unsupported, #thin))
	if #coplanar > 0 then print("[RuinedCathedral] QA  flicker: " .. table.concat(coplanar, "; ")) end
	if #dupes > 0 then print("[RuinedCathedral] QA  near-duplicate names: " .. table.concat(dupes, ", ")) end
	if #unsupported > 0 then print("[RuinedCathedral] QA  nothing under: " .. table.concat(unsupported, ", ")) end
	if #thin > 0 then print("[RuinedCathedral] QA  paper thin: " .. table.concat(thin, ", ")) end
	if #coplanar == 0 and #dupes == 0 and #unsupported == 0 and #thin == 0 then
		print("[RuinedCathedral] QA  no flicker, no duplicates, nothing floating: clean")
	end
end

--@@SECTION@@


local function BUILD(root)
	for _, fn in ipairs(PHASES) do
		fn(root)
	end
	if INSPECT then   -- a look inside only: the roof and the east aisle wall go see-through
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				local group = d.Parent and d.Parent.Name or ""
				if group == "Roof" or (d.Position.X > 17.5 and d.Position.Y > 3 and d.Position.Y < 15 and group == "Shell") then
					d.Transparency = 0.75
				end
			end
		end
	end
	if NIGHT then night() end
	qa(root)
	return root
end

return BUILD
