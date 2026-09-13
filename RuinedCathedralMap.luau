--[[
RuinedCathedralMap -- 150x150 stud night scene: ruined cathedral in a forest, cemetery behind.
Paste into the Studio command bar and run (reruns replace the previous map), or apply with VMCP.

DESIGN
1. Masses (nave runs along Z, entrance faces +Z / south, cemetery at -Z / north)
   nave   22 inner x 54 long x 26 high, walls 2.5 thick, centred (0, ., 10)  -- the tall spine
   aisles 8 wide x 13 high each side of the nave, full nave length            -- low shoulders
   apse   half-octagon r 9, 20 high on the north end                          -- rounded tail
   tower  12x12 x 46 high on the south-east corner, top broken on two sides   -- the one tall vertical
   porch  15 wide x 5 deep x 11 high over the door on the facade
   From the front: coped gable + great window between tower (right) and low aisle (left).
   From above: cross of nave + aisles, tail of apse, cemetery oval to the north, forest ring.
2. Structure: aisle walls + buttresses carry the aisle lean-to roofs; arcade piers carry the
   clerestory wall and the nave roof; rafters at bay lines. 6 bays of 9. Roof pitch 38 deg.
   Base numbers: W=22 D=54 H=26 T=2.5 A=8 AH=13 AT=2 BAYS=6 BAY=9 floorTop=1.5 groundTop=0.
   Ruin is data: naveRoof = {1,1,0,0,1,1} per bay, eastAisleWall bays 4-5 breached, tower tops
   per side, clerestory top heights per bay.
3. Access (all on foot from ground level, floor is 1.5 up, 3 steps of 0.5 at the door)
   nave      <- front door, south facade, 8 wide x 12 tall, sill at floorTop, 3 steps in front
   aisles    <- nave through the arcade (each arch 6 clear x 9 tall)
   east aisle<- breach in the east aisle wall, bays 4-5, 9 wide, open to the sky; rubble ramp <= 30 deg
   west aisle<- west side door, bay 5, 4 wide x 8 tall, sill at floorTop with 3 steps outside
   chancel   <- nave, 2 steps of 0.5 rise up to the altar platform at floorTop + 1.5, 14 wide
   tower base<- east aisle, door 4 wide x 8 tall in the tower's west wall; tower is otherwise sealed
   (no stair -- the tower top is a decorative ruin, stated sealed).
   cemetery  <- around the apse from either side door; gate in the low wall 5 wide, no leaf
4. Palette (cool grey stone, warm wood and candle light)
   see P below -- comment on each role says which surfaces get it
5. Variety: bays share one helper, damage is a per-bay table; trees jitter 20% in size and spin;
   gravestones pick from 3 shapes with a lean; rubble is a seeded scatter.
]]

local PROUD = 0.2
local SCALE_REF = false -- true: a 2x5 neon figure stands on the path for scale renders
local INSPECT = false -- true: roof + east aisle wall go 0.75 transparent so renders show the interior

local P = {
	wall   = { Enum.Material.Limestone,   Color3.fromRGB(112, 106, 96) },   -- every wall plane above the plinth, piers
	plinth = { Enum.Material.Cobblestone, Color3.fromRGB(66, 62, 58) },     -- lowest 2.5 studs of every exterior wall, tower base
	trim   = { Enum.Material.Sandstone,   Color3.fromRGB(158, 148, 130) },  -- voussoirs, quoins, sills, string courses, capitals, tracery
	roof   = { Enum.Material.Slate,       Color3.fromRGB(50, 52, 58) },     -- roof planes and ridges only
	beam   = { Enum.Material.Wood,        Color3.fromRGB(64, 46, 30) },     -- rafters, doors, pews, fallen beams, coffin lids
	floor  = { Enum.Material.Concrete,    Color3.fromRGB(86, 82, 76) },     -- interior flagstones, altar platform, steps
	iron   = { Enum.Material.Metal,       Color3.fromRGB(56, 54, 58) },     -- lantern cages, gate, sword, armour, candle spikes
	bone   = { Enum.Material.Limestone,   Color3.fromRGB(198, 188, 168) },  -- the soldier's skeleton only
	wax    = { Enum.Material.Marble,      Color3.fromRGB(222, 212, 190) },  -- candle bodies
	flame  = { Enum.Material.Neon,        Color3.fromRGB(255, 176, 90) },   -- candle / lantern flames (light sources)
	glass  = { Enum.Material.Glass,       Color3.fromRGB(70, 48, 110) },    -- surviving stained-glass panes, 0.35 transparent
	ground = { Enum.Material.Grass,       Color3.fromRGB(46, 58, 36) },     -- the ground slab, grave mounds
	dirt   = { Enum.Material.Ground,      Color3.fromRGB(72, 62, 50) },     -- the path from the forest edge to the door
	leaf   = { Enum.Material.LeafyGrass,  Color3.fromRGB(38, 62, 34) },     -- tree crowns, ivy, bushes
	bark   = { Enum.Material.Wood,        Color3.fromRGB(46, 36, 28) },     -- trunks, boughs, roots
	rock   = { Enum.Material.Slate,       Color3.fromRGB(78, 76, 74) },     -- boulders, rubble, broken masonry chunks
	moss   = { Enum.Material.Grass,       Color3.fromRGB(58, 74, 40) },     -- moss caps on rubble and graves
}

local rng = Random.new(1906)
local function jit(a: number, b: number): number return rng:NextNumber(a, b) end

local function ensure(parent: Instance, name: string, class: string): Instance
	local found = parent:FindFirstChild(name)
	if found and found.ClassName ~= class then found:Destroy() found = nil end
	if not found then
		found = Instance.new(class)
		found.Name = name
		found.Parent = parent
	end
	return found
end

local function box(parent: Instance, name: string, size: Vector3, cframe: CFrame, role): Part
	local part = ensure(parent, name, "Part") :: Part
	part.Size, part.CFrame, part.Anchored = size, cframe, true
	part.Material, part.Color = role[1], role[2]
	part.Transparency = 0
	return part
end

-- Cylinder standing on Y: `h` tall, radius `r`. Cylinders lie along X, so this turns them once.
local function post(parent: Instance, name: string, r: number, h: number, cframe: CFrame, role): Part
	local part = ensure(parent, name, "Part") :: Part
	part.Shape = Enum.PartType.Cylinder
	part.Size, part.Anchored = Vector3.new(h, r * 2, r * 2), true
	part.CFrame = cframe * CFrame.Angles(0, 0, math.pi / 2)
	part.Material, part.Color = role[1], role[2]
	part.Transparency = 0
	return part
end

-- Box with its Z along a -> b; w is the square cross-section. Beams, boughs, roots, sword.
local function between(parent: Instance, name: string, a: Vector3, b: Vector3, w: number, role, d: number?): Part
	return box(parent, name, Vector3.new(w, d or w, (b - a).Magnitude + PROUD), CFrame.lookAt((a + b) / 2, b), role)
end

-- Bottom of a prop of `size` on the top face of `surface`; u, v in -1..1, kept inside by margin.
local function placeOn(surface: BasePart, size: Vector3, u: number, v: number, margin: number?): CFrame
	local m = margin or 0.3
	local x = u * (surface.Size.X / 2 - size.X / 2 - m)
	local z = v * (surface.Size.Z / 2 - size.Z / 2 - m)
	return surface.CFrame * CFrame.new(x, surface.Size.Y / 2 + size.Y / 2, z)
end

-- Pointed (gothic) arch: two arcs, each centred on the opposite foot, 2n voussoirs, proud both faces.
-- frame: centre of the springing line, X along the span, Y up. Voussoirs above `maxY` (frame-local) are skipped.
local function pointedArch(parent: Instance, name: string, frame: CFrame, span: number, depth: number, thick: number, n: number, role, maxY: number?)
	local r = span
	local step = (math.pi / 3) / n                           -- each arc runs from its foot (180) to the apex (120)
	local seg = 2 * r * math.sin(step / 2) + PROUD
	local limit = maxY or math.huge
	local rad = r + thick / 2                                -- ring sits outside the curve; the opening is the full pointed arch
	local size = Vector3.new(thick, seg, depth)
	for i = 1, n do
		local a = 2 * math.pi / 3 + (i - 0.5) * step
		local cfL = frame * CFrame.new(span / 2, 0, 0) * CFrame.Angles(0, 0, a) * CFrame.new(rad, 0, 0)
		local cfR = frame * CFrame.new(-span / 2, 0, 0) * CFrame.Angles(0, 0, math.pi - a) * CFrame.new(rad, 0, 0)
		if (frame:PointToObjectSpace(cfL.Position)).Y < limit then box(parent, `{name}L{i}`, size, cfL, role or P.trim) end
		if (frame:PointToObjectSpace(cfR.Position)).Y < limit then box(parent, `{name}R{i}`, size, cfR, role or P.trim) end
	end
end

-- A wall of bays built as fill around its openings -- there is no hole tool.
-- frame: the wall's left end at its base, X along the wall, Y up, +Z the outside face.
-- bays[i] = { top = height, openings = { { w, h, sill, at?, ring?, glass?, impost? } } } sorted by sill.
-- `h` is the clear height at the apex of the pointed head. Fill pieces are recessed `R` so no face
-- shares a plane with a pier; the ring is proud of both faces; the sill band is proud of both faces.
local R = 0.08
local function bayWall(parent: Instance, name: string, frame: CFrame, bayLen: number, thick: number, bays, role)
	role = role or P.wall
	local len = #bays * bayLen
	local function piece(pname: string, x0: number, x1: number, y0: number, y1: number, recess: boolean?, deeper: boolean?)
		if x1 - x0 < 0.05 or y1 - y0 < 0.05 then return nil end
		local d = if deeper then thick - 2 * R - 0.06 elseif recess then thick - 2 * R else thick
		return box(parent, pname, Vector3.new(x1 - x0, y1 - y0, d), frame * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, 0), role)
	end
	local imposts = {}
	for i, bay in ipairs(bays) do
		local top = bay.top
		local x0, x1 = (i - 1) * bayLen, i * bayLen
		local y = 0
		for k, o in ipairs(bay.openings or {}) do
			local ox = x0 + bayLen / 2 + (o.at or 0)
			local w, h = o.w, o.h
			local apex = w * math.sin(math.pi / 3)
			local ring = o.ring or (if w >= 5 then 2 else 1.2)
			local spring = o.sill + h - apex
			local lo, hi = ox - w / 2, ox + w / 2
			piece(`{name}{i}f{k}`, x0, x1, y, math.min(o.sill, top), true)
			if o.sill >= top then y = top break end
			local bandTop = math.min(o.sill + h, top)
			piece(`{name}{i}pl{k}`, x0, lo, o.sill, bandTop)
			piece(`{name}{i}pr{k}`, hi, x1, o.sill, bandTop)
			pointedArch(parent, `{name}{i}a{k}`, frame * CFrame.new(ox, spring, 0), w, thick + 2 * PROUD, ring, if w >= 5 then 4 else 3, P.trim, top - spring)
			local outerR = w + ring
			local function curve(t: number) return -w / 2 + math.sqrt(math.max(outerR * outerR - t * t, 0)) end
			local m = math.max(1, math.ceil((curve(0) - curve(apex)) / (ring - 0.3)))
			for sIdx = 1, m do
				local tb = sIdx * apex / m
				local ya, yb = spring + (sIdx - 1) * apex / m, math.min(spring + tb + (sIdx == m and 0.05 or 0), top)
				if ya < top then
					local inner = curve(tb) - 0.05
					piece(`{name}{i}sl{k}_{sIdx}`, lo - 0.04, ox - inner, ya, yb, true, true)
					piece(`{name}{i}sr{k}_{sIdx}`, ox + inner, hi + 0.04, ya, yb, true, true)
				end
			end
			if o.sill > 2 then
				box(parent, `{name}{i}sb{k}`, Vector3.new(w + 0.8, 0.5, thick + 2 * PROUD), frame * CFrame.new(ox, o.sill, 0), P.trim)
			end
			if o.glass and spring + apex <= top then
				-- glass fills the whole opening: one pane up to the springing, then slabs that follow the
				-- inner curve of the head, each wide enough at its middle to bury its top corners in the ring
				local paneH = spring - o.sill - 0.25
				local pane = box(parent, `{name}{i}g{k}`, Vector3.new(w - 0.1, paneH + 0.1, 0.3), frame * CFrame.new(ox, o.sill + 0.25 + paneH / 2, 0), P.glass)
				pane.Transparency = 0.35
				pane.CanCollide = false
				local function innerCurve(t: number) return -w / 2 + math.sqrt(math.max(w * w - t * t, 0)) end
				local headSlabs = 4
				for hs = 1, headSlabs do
					local ta, tb = (hs - 1) * apex / headSlabs, hs * apex / headSlabs
					local half = innerCurve(ta + (tb - ta) * 0.45)
					local head = box(parent, `{name}{i}gh{k}_{hs}`, Vector3.new(2 * half + 0.1, tb - ta + 0.04, 0.3 - hs * 0.05), frame * CFrame.new(ox, spring + (ta + tb) / 2, 0), P.glass)
					head.Transparency = 0.35
					head.CanCollide = false
				end
				local mullH = spring - o.sill - 0.25
				box(parent, `{name}{i}m{k}`, Vector3.new(0.35, mullH + 0.1, 0.5), frame * CFrame.new(ox, o.sill + 0.2 + mullH / 2, 0), P.trim)
				box(parent, `{name}{i}t{k}`, Vector3.new(w - 0.2, 0.3, 0.56), frame * CFrame.new(ox, spring, 0), P.trim)   -- transom at the springing
			end
			if o.impost then
				imposts[i - 1] = imposts[i - 1] or {}
				imposts[i - 1].right, imposts[i - 1].y = lo + 0.3, spring
				imposts[i] = imposts[i] or {}
				imposts[i].left, imposts[i].y = hi - 0.3, spring
			end
			y = o.sill + h
		end
		piece(`{name}{i}top`, x0, x1, y, top, true)
	end
	for j, im in imposts do
		local a, b = im.left or 0.1, im.right or len - 0.1
		if b - a > 0.1 and im.y < (bays[math.max(j, 1)].top) then
			box(parent, `{name}im{j}`, Vector3.new(b - a, 0.6, thick + 2 * PROUD), frame * CFrame.new((a + b) / 2, im.y, 0), P.trim)
		end
	end
end

-- Wall frames: left end at the base, X along the wall, +Z out.
local function wallFrame(origin: Vector3, along: Vector3): CFrame
	return CFrame.fromMatrix(origin, along, Vector3.yAxis)
end

local function light(parent: Instance, name: string, class: string, range: number, brightness: number, color: Color3)
	local l = ensure(parent, name, class) :: PointLight
	l.Range, l.Brightness, l.Color, l.Shadows = range, brightness, color, true
	return l
end

local function build(root: Instance)
	local W, D, H, T = 22, 54, 26, 2.5
	local A, AH, AT = 8, 13, 2
	local BAYS = 6
	local BAY = D / BAYS
	local groundTop, floorTop = 0, 1.5
	local naveZ = 10                                          -- nave centre; front (south) face at naveZ + D/2
	local front = naveZ + D / 2
	local back = naveZ - D / 2
	local outerX = W / 2 + T + A + AT                          -- outside face of the aisle walls
	local towerS, towerH, towerT = 12, 46, 2
	local towerX, towerZ = outerX + towerS / 2, front + 1 - towerS / 2   -- butts the aisle wall, 1 stud proud of the facade
	local apseR, apseH = 9, 20

	------------------------------------------------------------------ ground
	local ground = ensure(root, "Ground", "Model")
	box(ground, "Slab", Vector3.new(150, 2, 150), CFrame.new(0, groundTop - 1, 0), P.ground)

	------------------------------------------------------------------ shell: walls as fill around openings
	local shell = ensure(root, "Shell", "Model")
	local L = D - 2 * T                                   -- bay span: between the chancel wall and the facade
	local z0, z1 = back + T, front - T                    -- back and front of the bay span
	BAY = L / BAYS
	local navePitch = math.rad(38)
	local halfSpan = W / 2 + T
	local ridgeY = groundTop + H + halfSpan * math.tan(navePitch)
	local aislePitch = math.rad(22)
	local aisleRun = A + AT
	local clerSill = groundTop + AH + aisleRun * math.tan(aislePitch) + 1.6

	local function window(sill, w, h, glass) return { w = w, h = h, sill = sill, glass = glass } end
	local function arcadeBay(top, winTop)
		return { top = top, openings = {
			{ w = 6, h = 10, sill = floorTop, ring = 2, impost = true },
			window(clerSill, 3.5, math.min(6, winTop - clerSill), winTop >= clerSill + 6),
		} }
	end
	-- nave walls: arcade below, clerestory above; east side broken where the roof fell
	local naveTops = { west = { H, H, H, H, H, H }, east = { H, H, 21, 19.5, H, H } }
	local naveBays = { west = {}, east = {} }
	for i = 1, BAYS do
		naveBays.west[i] = arcadeBay(naveTops.west[i], H)
		naveBays.east[i] = arcadeBay(naveTops.east[i], naveTops.east[i])
		if naveTops.east[i] < clerSill + 4 then table.remove(naveBays.east[i].openings, 2) end
	end
	bayWall(shell, "NaveW", wallFrame(Vector3.new(-W / 2 - T / 2, groundTop, z0), Vector3.zAxis), BAY, T, naveBays.west)
	bayWall(shell, "NaveE", wallFrame(Vector3.new( W / 2 + T / 2, groundTop, z1), -Vector3.zAxis), BAY, T, naveBays.east)

	-- aisle walls: a window per bay; west has the side door in bay 5; east is breached at bays 4-5
	-- and has the tower door in bay 1 (the east wall's bay 1 is at the front, its X runs front -> back)
	local sideDoor = { w = 4, h = 8, sill = floorTop, ring = 1.5 }
	local westBays, eastBays = {}, {}
	local aisleTopsW = { AH, AH, AH, AH, AH, AH }
	local aisleTopsE = { AH, AH, 10, 0, 0, AH }
	for i = 1, BAYS do
		westBays[i] = { top = aisleTopsW[i], openings = { window(floorTop + 3, 3, 8.5, i % 2 == 1) } }
		eastBays[i] = { top = aisleTopsE[i], openings = { window(floorTop + 3, 3, 8.5, i == 2) } }
	end
	westBays[5].openings = { sideDoor }
	local towerDoorAt = (z1 - towerZ) - BAY / 2
	eastBays[1].openings = { { w = 4, h = 8, sill = floorTop, ring = 1.5, at = towerDoorAt } }
	eastBays[4].openings, eastBays[5].openings = {}, {}
	bayWall(shell, "AisleW", wallFrame(Vector3.new(-outerX + AT / 2, groundTop, z0), Vector3.zAxis), BAY, AT, westBays)
	bayWall(shell, "AisleE", wallFrame(Vector3.new( outerX - AT / 2, groundTop, z1), -Vector3.zAxis), BAY, AT, eastBays)

	-- aisle back walls close the aisles at the chancel line (outside is -Z)
	bayWall(shell, "AisleBackW", wallFrame(Vector3.new(-W / 2 - T, groundTop, back + T / 2), -Vector3.xAxis), aisleRun, T,
		{ { top = AH, openings = { window(floorTop + 3, 3, 7, false) } } })
	bayWall(shell, "AisleBackE", wallFrame(Vector3.new(outerX, groundTop, back + T / 2), -Vector3.xAxis), aisleRun, T,
		{ { top = AH, openings = { window(floorTop + 3, 3, 7, false) } } })

	-- facade: three sections, the nave one carries the door, the great window and the gable
	local facadeZ = front - T / 2
	local naveFaceLen = W + 2 * T
	bayWall(shell, "FacadeNave", wallFrame(Vector3.new(-naveFaceLen / 2, groundTop, facadeZ), Vector3.xAxis), naveFaceLen, T, {
		{ top = H, openings = {
			{ w = 7, h = 10, sill = floorTop, ring = 2 },
			window(floorTop + 15, 7, 9, true),
		} } })
	for _, side in { -1, 1 } do
		local x0f = if side < 0 then -outerX else W / 2 + T
		bayWall(shell, side < 0 and "FacadeW" or "FacadeE", wallFrame(Vector3.new(x0f, groundTop, facadeZ), Vector3.xAxis), aisleRun, T,
			{ { top = AH + 1, openings = { window(floorTop + 3, 2.5, 6.5, false) } } })
	end
	-- gable: thin courses fill the triangle, a raking coping in the trim role runs up each slope and
	-- hides their steps, a small cross stands on the apex
	local function gable(parent, name, z, dir, baseY, halfW, pitch, thick, courses, finial)
		local rise = halfW * math.tan(pitch) / courses
		for k = 1, courses do
			local yb = baseY + (k - 1) * rise
			local half = halfW - (k - 0.5) * rise / math.tan(pitch)
			box(parent, `{name}{k}`, Vector3.new(2 * half, rise, thick - (k - 1) * 0.06), CFrame.new(0, yb + rise / 2, z), P.wall)
		end
		local slant = halfW / math.cos(pitch)
		for _, side in { -1, 1 } do
			local cf = CFrame.new(side * halfW / 2, baseY + halfW * math.tan(pitch) / 2, z) * CFrame.Angles(0, 0, -side * pitch) * CFrame.new(0, 0.3, 0)
			box(parent, `{name}Coping{side < 0 and "W" or "E"}`, Vector3.new(slant + 1, 0.7, thick + 0.5), cf, P.trim)
		end
		if finial then
			local apexY = baseY + halfW * math.tan(pitch)
			box(parent, name .. "Finial", Vector3.new(0.5, 2.4, 0.5), CFrame.new(0, apexY + 0.5 + 1.2, z), P.trim)
			box(parent, name .. "FinialArm", Vector3.new(1.4, 0.4, 0.56), CFrame.new(0, apexY + 0.5 + 1.7, z), P.trim)
		end
	end
	gable(shell, "GableS", facadeZ, 1, groundTop + H, halfSpan, navePitch, T, 10, true)

	-- chancel wall: the nave's back, one big pointed opening into the apse, gable over it (outside is -Z)
	local chancelZ = back + T / 2
	bayWall(shell, "Chancel", wallFrame(Vector3.new(naveFaceLen / 2, groundTop, chancelZ), -Vector3.xAxis), naveFaceLen, T, {
		{ top = H, openings = { { w = 12, h = 16, sill = floorTop, ring = 2.5, impost = true } } } })
	gable(shell, "GableN", chancelZ, -1, groundTop + H, halfSpan, navePitch, T, 10, true)

	-- plinth bands on the outside faces, cornice bands at the wall tops; both butt the face and stand PROUD of it
	local function band(parent, name, a: Vector3, b: Vector3, y, h, out: Vector3, role)
		local len = (b - a).Magnitude
		local bite = R + 0.03
		local mid = (a + b) / 2 + out * ((PROUD - bite) / 2)
		box(parent, name, Vector3.new(len, h, PROUD + bite), CFrame.fromMatrix(mid + Vector3.new(0, y + h / 2, 0), (b - a).Unit, Vector3.yAxis), role)
	end
	local plinthH = 2.5 + 0.05                                -- bands start 0.05 under the ground line
	band(shell, "PlinthW", Vector3.new(-outerX, 0, back - 0.05), Vector3.new(-outerX, 0, front - R - 0.03), groundTop - 0.05, plinthH, -Vector3.xAxis, P.plinth)
	band(shell, "PlinthE", Vector3.new(outerX, 0, back - 0.05), Vector3.new(outerX, 0, front - R - 0.03), groundTop - 0.05, plinthH, Vector3.xAxis, P.plinth)
	band(shell, "PlinthS", Vector3.new(-outerX - PROUD, 0, front), Vector3.new(outerX + PROUD, 0, front), groundTop - 0.05, plinthH, Vector3.zAxis, P.plinth)
	local function cornice(parent, name, a, b, y, out)
		band(parent, name, a, b, y - 0.75, 0.7, out, P.trim)
	end
	cornice(shell, "CorniceW", Vector3.new(-outerX, 0, back - 0.05), Vector3.new(-outerX, 0, front - R - 0.03), groundTop + AH, -Vector3.xAxis)
	cornice(shell, "CorniceE", Vector3.new(outerX, 0, front - R - 0.03), Vector3.new(outerX, 0, z1 - 2 * BAY - 0.15), groundTop + AH, Vector3.xAxis)
	cornice(shell, "CorniceS", Vector3.new(-halfSpan - 0.05, 0, front), Vector3.new(halfSpan + 0.05, 0, front), groundTop + H, Vector3.zAxis)
	cornice(shell, "CorniceN", Vector3.new(-halfSpan - 0.05, 0, back), Vector3.new(halfSpan + 0.05, 0, back), groundTop + H, -Vector3.zAxis)

	-- buttresses on the aisle walls at every bay line; heights are ruin data
	local butt = ensure(root, "Buttresses", "Model")
	local function buttress(name, frame: CFrame, h, capped)
		-- frame: on the wall's outer face at the base, +Z away from the wall; bedded 0.3 into the ground
		local depth, wdt = 3, 2
		box(butt, name .. "Base", Vector3.new(wdt + 0.6, 4.3, depth + 1), frame * CFrame.new(0, 4.3 / 2 - 0.3, (depth + 1) / 2), P.plinth)
		box(butt, name, Vector3.new(wdt, h - 4, depth), frame * CFrame.new(0, 4 + (h - 4) / 2, depth / 2), P.wall)
		if capped then
			local capLen = depth / math.cos(math.rad(45))
			box(butt, name .. "Cap", Vector3.new(wdt + 0.1, 0.8, capLen + 0.4),
				frame * CFrame.new(0, h + depth * math.tan(math.rad(45)) / 2 + 0.3, depth / 2) * CFrame.Angles(math.rad(45), 0, 0), P.trim)
		end
	end
	local buttH = { west = { 8.5, 8.5, 8.5, 8.5, 8.5, 8.5, 8.5 }, east = { 0, 0, 8.5, 6, 0, 4.5, 8.5 } }
	for j = 0, BAYS do
		local z = z1 - j * BAY
		if j == 0 then z = z1 - 1.2 elseif j == BAYS then z = z0 + 1.2 end
		if buttH.west[j + 1] > 0 then
			buttress(`W{j}`, CFrame.fromMatrix(Vector3.new(-outerX, groundTop, z), Vector3.zAxis, Vector3.yAxis), buttH.west[j + 1], buttH.west[j + 1] >= 8.5)
		end
		if buttH.east[j + 1] > 0 then
			buttress(`E{j}`, CFrame.fromMatrix(Vector3.new(outerX, groundTop, z), -Vector3.zAxis, Vector3.yAxis), buttH.east[j + 1], buttH.east[j + 1] >= 8.5)
		end
	end
	-- quoins on the facade's west corner
	for k = 1, 5 do
		local big = k % 2 == 1
		box(butt, `QuoinSW{k}`, Vector3.new(big and 2.2 or 1.4, 1.8, big and 1.4 or 2.2),
			CFrame.new(-outerX + (big and 1.1 or 0.7) - 0.05, groundTop + plinthH + (k - 0.5) * 1.85, front - (big and 0.7 or 1.1) + 0.05), P.trim)
	end

	------------------------------------------------------------------ apse: half octagon, windows, corner piers
	local apse = ensure(root, "Apse", "Model")
	local segLen = 2 * apseR * math.sin(math.pi / 8)
	local ext = T * math.tan(math.pi / 8)                    -- extend each segment so the mitre corners close
	local apseZ = back - segLen / 2 - ext - 0.1              -- end segments stop 0.1 short of the chancel wall; the corner piers cover the joint
	local apseTops = { apseH, apseH, apseH, 15.5, 12 }
	for i = 1, 5 do
		local a = (i - 3) * math.pi / 4
		local centre = CFrame.new(0, groundTop, apseZ) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -apseR + T / 2)
		local frame = centre * CFrame.Angles(0, math.pi, 0) * CFrame.new(-(segLen / 2 + ext), 0, 0)
		bayWall(apse, `Seg{i}`, frame, segLen + 2 * ext, T, { { top = apseTops[i], openings = { window(floorTop + 4, 3, 11, i ~= 4) } } })
	end
	-- corner piers over each mitre joint, plus the two chancel ends
	for j = 0, 5 do
		local ca = (j - 2.5) * math.pi / 4
		local ph = math.min(apseTops[math.max(j, 1)], apseTops[math.min(j + 1, 5)]) - 0.3
		local pierCF = CFrame.new(0, groundTop, apseZ) * CFrame.Angles(0, ca, 0) * CFrame.new(0, (ph - 0.3) / 2, -apseR - 0.5)
		box(apse, `Pier{j}`, Vector3.new(2, ph + 0.3, 2.2), pierCF, P.plinth)
	end
	local apseFloorD = apseR - T + segLen / 2 - 0.1
	box(apse, "Floor", Vector3.new(2 * apseR - 2 * T, floorTop - groundTop, apseFloorD), CFrame.new(0, (groundTop + floorTop) / 2, back - apseFloorD / 2), P.floor)

	------------------------------------------------------------------ tower: four walls, two rows of openings, broken top
	local tower = ensure(root, "Tower", "Model")
	local tIn = towerS - 2 * towerT
	local tTops = { S = towerH, W = towerH, N = 37, E = 31 }
	local function tWin(sill, w, h) return { w = w, h = h, sill = sill } end
	bayWall(tower, "S", wallFrame(Vector3.new(towerX - towerS / 2, groundTop, towerZ + towerS / 2 - towerT / 2), Vector3.xAxis), towerS, towerT,
		{ { top = tTops.S, openings = { tWin(14, 2.5, 6), tWin(30, 3, 8) } } })
	bayWall(tower, "N", wallFrame(Vector3.new(towerX + towerS / 2, groundTop, towerZ - towerS / 2 + towerT / 2), -Vector3.xAxis), towerS, towerT,
		{ { top = tTops.N, openings = { tWin(14, 2.5, 6), tWin(30, 3, 8) } } })
	bayWall(tower, "E", wallFrame(Vector3.new(towerX + towerS / 2 - towerT / 2, groundTop, towerZ + tIn / 2), -Vector3.zAxis), tIn, towerT,
		{ { top = tTops.E, openings = { tWin(14, 2.5, 6), tWin(30, 3, 8) } } })
	bayWall(tower, "W", wallFrame(Vector3.new(towerX - towerS / 2 + towerT / 2, groundTop, towerZ - tIn / 2), Vector3.zAxis), tIn, towerT,
		{ { top = tTops.W, openings = { { w = 4, h = 8, sill = floorTop, ring = 1.5 }, tWin(30, 3, 8) } } })
	box(tower, "Floor", Vector3.new(tIn, floorTop - groundTop, tIn), CFrame.new(towerX, (groundTop + floorTop) / 2, towerZ), P.floor)
	local tS, tN, tE, tW = towerZ + towerS / 2, towerZ - towerS / 2, towerX + towerS / 2, towerX - towerS / 2
	band(tower, "PlinthS", Vector3.new(tW - PROUD, 0, tS), Vector3.new(tE + PROUD, 0, tS), groundTop - 0.05, plinthH, Vector3.zAxis, P.plinth)
	band(tower, "PlinthE", Vector3.new(tE, 0, tS - R - 0.03), Vector3.new(tE, 0, tN + R + 0.03), groundTop - 0.05, plinthH, Vector3.xAxis, P.plinth)
	band(tower, "PlinthN", Vector3.new(tE + PROUD, 0, tN), Vector3.new(tW + PROUD + 0.03, 0, tN), groundTop - 0.05, plinthH, -Vector3.zAxis, P.plinth)
	-- string courses at the storey lines, merlons on the two whole walls, quoins on the two outer corners
	for _, y in { 12, 28 } do
		cornice(tower, `StringS{y}`, Vector3.new(tW - PROUD, 0, tS), Vector3.new(tE + PROUD, 0, tS), groundTop + y, Vector3.zAxis)
		cornice(tower, `StringE{y}`, Vector3.new(tE, 0, tS - R - 0.03), Vector3.new(tE, 0, tN + R + 0.03), groundTop + y, Vector3.xAxis)
	end
	cornice(tower, "StringN12", Vector3.new(tE + PROUD, 0, tN), Vector3.new(tW + 0.03, 0, tN), groundTop + 12, -Vector3.zAxis)
	for k = 1, 4 do
		box(tower, `MerlonS{k}`, Vector3.new(1.5, 2, towerT - 0.4), CFrame.new(tW + 1.5 + (k - 1) * 3, groundTop + towerH + 1, tS - towerT / 2), P.wall)
		box(tower, `MerlonW{k}`, Vector3.new(towerT - 0.4, 2, 1.2), CFrame.new(tW + towerT / 2, groundTop + towerH + 1, tN + towerT + 1 + (k - 1) * 2), P.wall)
	end
	for k = 1, 10 do
		local big = k % 2 == 1
		local y = groundTop + plinthH + (k - 0.5) * 1.85
		box(tower, `QuoinSE{k}`, Vector3.new(big and 2.2 or 1.4, 1.8, big and 1.4 or 2.2),
			CFrame.new(tE - (big and 1.1 or 0.7) + 0.05, y, tS - (big and 0.7 or 1.1) + 0.05), P.trim)
		if y + 0.9 < groundTop + tTops.E then
			box(tower, `QuoinNE{k}`, Vector3.new(big and 1.4 or 2.2, 1.8, big and 2.2 or 1.4),
				CFrame.new(tE - (big and 0.7 or 1.1) + 0.05, y, tN + (big and 1.1 or 0.7) - 0.05), P.trim)
		end
	end

	------------------------------------------------------------------ porch and steps
	local porch = ensure(root, "Porch", "Model")
	local porchW, porchD, porchH = 15, 5, 11
	local porchPitch = math.rad(30)
	bayWall(porch, "Front", wallFrame(Vector3.new(-porchW / 2, groundTop, front + porchD - 0.75), Vector3.xAxis), porchW, 1.5,
		{ { top = porchH, openings = { { w = 8, h = 9.2, sill = floorTop, ring = 1.5 } } } })
	local porchRun = porchW / 2 + 1
	for _, side in { -1, 1 } do
		box(porch, side < 0 and "SideW" or "SideE", Vector3.new(2, porchH, porchD - 1.5), CFrame.new(side * (porchW / 2 - 1), groundTop + porchH / 2, front + (porchD - 1.5) / 2), P.wall)
		local slant = porchRun / math.cos(porchPitch)
		local cf = CFrame.new(side * porchRun / 2, groundTop + porchH + porchRun * math.tan(porchPitch) / 2 + 0.5, front + porchD / 2) * CFrame.Angles(0, 0, -side * porchPitch)
		box(porch, side < 0 and "RoofW" or "RoofE", Vector3.new(slant + 0.6, 0.6, porchD + 0.4), cf * CFrame.new(0, 0, 0.2), P.roof)
	end
	local porchRidge = groundTop + porchH + porchRun * math.tan(porchPitch) + 0.5
	box(porch, "Ridge", Vector3.new(1, 1, porchD + 1), CFrame.new(0, porchRidge + 0.55, front + porchD / 2 + 0.2) * CFrame.Angles(0, 0, math.pi / 4), P.roof)
	gable(porch, "Gable", front + porchD - 0.75, 1, groundTop + porchH, porchW / 2, porchPitch, 1.5, 6, false)
	box(porch, "Floor", Vector3.new(porchW - 4, floorTop - groundTop, porchD - 1.5), CFrame.new(0, (groundTop + floorTop) / 2, front + (porchD - 1.5) / 2), P.floor)
	local steps = ensure(root, "Steps", "Model")
	local tread, rise = 1.7, (floorTop - groundTop) / 3
	for k = 1, 3 do
		local top = floorTop - (k - 1) * rise
		box(steps, `Front{k}`, Vector3.new(porchW + 1, top - groundTop, tread), CFrame.new(0, (groundTop + top) / 2, front + porchD + (k - 0.5) * tread), P.floor)
	end
	local sideDoorZ = z0 + 4.5 * BAY
	for k = 1, 3 do
		local top = floorTop - (k - 1) * rise
		box(steps, `Side{k}`, Vector3.new(tread, top - groundTop, 5), CFrame.new(-outerX - (k - 0.5) * tread, (groundTop + top) / 2, sideDoorZ), P.floor)
	end

	------------------------------------------------------------------ floors
	local floors = ensure(root, "Floors", "Model")
	local fh = floorTop - groundTop
	box(floors, "Nave", Vector3.new(W, fh, L), CFrame.new(0, groundTop + fh / 2, naveZ), P.floor)
	for _, side in { -1, 1 } do
		box(floors, side < 0 and "AisleW" or "AisleE", Vector3.new(A, fh, L), CFrame.new(side * (W / 2 + T + A / 2), groundTop + fh / 2, naveZ), P.floor)
		box(floors, side < 0 and "BorderW" or "BorderE", Vector3.new(1.2, 0.15, L - BAY - 5), CFrame.new(side * (W / 2 - 0.7), floorTop + 0.075, naveZ + BAY / 2 + 0.5), P.trim)
	end
	box(floors, "Aisle", Vector3.new(4, 0.15, L - 2 * BAY - 4), CFrame.new(0, floorTop + 0.075, naveZ + BAY / 2 + 1), P.plinth)
	local platD = BAY
	local platTop = floorTop + 1.5
	box(floors, "Platform", Vector3.new(W - 0.2, platTop - floorTop, platD), CFrame.new(0, (floorTop + platTop) / 2, z0 + platD / 2), P.floor)
	for k = 1, 2 do
		local top = platTop - k * 0.5
		box(floors, `ChancelStep{k}`, Vector3.new(14, top - floorTop, 2), CFrame.new(0, (floorTop + top) / 2, z0 + platD + (k - 0.5) * 2), P.floor)
	end

	------------------------------------------------------------------ roof: two intact runs, the middle fallen in
	local roof = ensure(root, "Roof", "Model")
	local slope = halfSpan / math.cos(navePitch)
	local eave = 1.5
	local tanP = math.tan(navePitch)
	-- underside of the nave roof plane at horizontal x (wall outer top corner is the reference)
	local function naveUnder(x: number) return groundTop + H + (halfSpan - math.abs(x)) * tanP end
	-- nave runs: z extents per side; the broken ends are jittered so the two slopes don't end on one line
	local naveRuns = {
		{ name = "Back",  z = { z0 - 0.1, z0 + 2 * BAY }, ragged = { 1.3, -0.8 } },     -- planes stop at the gables, which stand above them
		{ name = "Front", z = { z0 + 4 * BAY, z1 + 0.1 }, ragged = { -0.6, 1.1 } },
	}
	for _, run in naveRuns do
		for si, side in { -1, 1 } do
			local zA, zB = run.z[1], run.z[2]
			if run.name == "Back" then zB += run.ragged[si] else zA += run.ragged[si] end
			local len = slope + eave + 0.3
			local along = Vector3.new(-side * math.cos(navePitch), math.sin(navePitch), 0)     -- up the slope
			local normal = Vector3.new(side * math.sin(navePitch), math.cos(navePitch), 0)
			local corner = Vector3.new(side * halfSpan, groundTop + H, (zA + zB) / 2)
			local centre = corner + along * ((slope + 0.3 - eave) / 2) + normal * 0.4
			box(roof, `Nave{run.name}{side < 0 and "W" or "E"}`, Vector3.new(len, 0.8, zB - zA), CFrame.fromMatrix(centre, along, normal), P.roof)
		end
		local zA, zB = run.z[1], run.z[2]
		box(roof, `Ridge{run.name}`, Vector3.new(1.3, 1.3, zB - zA), CFrame.new(0, ridgeY + 0.8, (zA + zB) / 2) * CFrame.Angles(0, 0, math.pi / 4), P.roof)
		-- ridge beam and wall plates under the planes
		box(roof, `RidgeBeam{run.name}`, Vector3.new(0.7, 0.7, zB - zA - 1), CFrame.new(0, naveUnder(0) - 1.05, (zA + zB) / 2), P.beam)
	end
	for _, run in naveRuns do                                -- wall plates only where the wall still stands
		for _, side in { -1, 1 } do
			local zA, zB = math.max(run.z[1], z0 + 0.2), math.min(run.z[2], z1 - 0.2)
			box(roof, `Plate{run.name}{side < 0 and "W" or "E"}`, Vector3.new(1.1, 0.4, zB - zA), CFrame.new(side * (W / 2 + 0.65), groundTop + H + 0.2, (zA + zB) / 2), P.beam)
		end
	end
	-- rafters at the bay lines; the ones over the collapse are the charred survivors
	local rafters = { west = { 1, 1, 1, 0, 1, 1, 1 }, east = { 1, 1, 0, 0, 0, 1, 1 } }
	for j = 0, BAYS do
		local z = z0 + j * BAY + (j == 0 and 0.5 or (j == BAYS and -0.5 or 0))
		for _, side in { -1, 1 } do
			local present = (side < 0 and rafters.west or rafters.east)[j + 1] == 1
			if present then
				local xa = side * (W / 2 + 0.6)
				local a = Vector3.new(xa, naveUnder(xa) - 0.7, z)
				local b = Vector3.new(side * 0.45, naveUnder(0.45) - 0.7, z)
				between(roof, `Rafter{side < 0 and "W" or "E"}{j}`, a, b, 0.5, P.beam, 0.7)
			end
		end
	end
	-- broken slates hanging off the collapse edges
	for i, spec in { { z = z0 + 2 * BAY + 1.3, side = -1 }, { z = z0 + 2 * BAY - 0.8, side = 1 }, { z = z0 + 4 * BAY - 0.6, side = -1 }, { z = z0 + 4 * BAY + 1.1, side = 1 } } do
		local x = spec.side * (halfSpan * 0.55)
		box(roof, `Slate{i}`, Vector3.new(3, 0.5, 2.2), CFrame.new(x, naveUnder(x) - 0.9, spec.z + (i % 2 == 0 and 1 or -1) * 1.1) * CFrame.Angles(math.rad(i % 2 == 0 and 35 or -30), 0, -spec.side * navePitch), P.roof)
	end

	-- aisle lean-to roofs: west whole, east only over the front three bays (the rest fell with the wall)
	local tanA = math.tan(aislePitch)
	local aisleRuns = { { side = -1, z = { back - 0.5, z1 - 0.05 }, eave = 1.2 }, { side = 1, z = { z1 - 3 * BAY, z1 - 0.05 }, eave = -0.3 } }
	local function aisleUnder(x: number) return groundTop + AH + 0.7 + (outerX - math.abs(x)) * tanA end
	for _, run in aisleRuns do
		local side = run.side
		local runLen = aisleRun + run.eave
		local len = runLen / math.cos(aislePitch)
		local along = Vector3.new(-side * math.cos(aislePitch), math.sin(aislePitch), 0)
		local normal = Vector3.new(side * math.sin(aislePitch), math.cos(aislePitch), 0)
		local corner = Vector3.new(side * outerX, groundTop + AH + 0.7, (run.z[1] + run.z[2]) / 2)
		local centre = corner + along * ((runLen - 2 * run.eave) / 2 / math.cos(aislePitch)) + normal * 0.3
		local tag = side < 0 and "W" or "E"
		box(roof, `Aisle{tag}`, Vector3.new(len, 0.6, run.z[2] - run.z[1]), CFrame.fromMatrix(centre, along, normal), P.roof)
		box(roof, `AislePlate{tag}`, Vector3.new(AT - 0.2, 0.7, run.z[2] - run.z[1] - 0.6), CFrame.new(side * (outerX - AT / 2), groundTop + AH + 0.35, (run.z[1] + run.z[2]) / 2), P.beam)
		-- flashing strip where the plane meets the nave wall
		local xf = side * (W / 2 + T + 0.2)
		local fz0, fz1 = math.max(run.z[1] + 0.15, z0 + 0.1), math.min(run.z[2], z1 - 0.1)
		box(roof, `Flashing{tag}`, Vector3.new(0.6, 0.5, fz1 - fz0), CFrame.new(xf, aisleUnder(xf) + 0.35, (fz0 + fz1) / 2), P.trim)
		for j = 0, BAYS do
			local z = z0 + j * BAY + (j == 0 and 0.6 or (j == BAYS and -0.6 or 0))
			if z > run.z[1] + 0.3 and z < run.z[2] - 0.3 then
				local xa = side * (outerX - AT / 2)
				local xb = side * (W / 2 + T + 0.1)
				between(roof, `AisleRafter{tag}{j}`, Vector3.new(xa, aisleUnder(xa) - 0.33, z), Vector3.new(xb, aisleUnder(xb) - 0.33, z), 0.5, P.beam, 0.6)
			end
		end
	end

	-- apse roof: a half cone over the three whole segments, hip ribs on the seams, cap at the apex
	local apexY = groundTop + apseH + apseR * math.tan(math.rad(24))
	local apex = Vector3.new(0, apexY, back - 0.3)              -- the cone apex sits on the chancel wall
	local apseEave = apseR + 0.8
	local function apseDir(angle: number) return Vector3.new(-math.sin(angle), 0, -math.cos(angle)) end
	for i = 1, 3 do
		local a = (i - 3) * math.pi / 4
		local baseMid = Vector3.new(0, groundTop + apseH, apseZ) + apseDir(a) * apseEave
		local centre = (baseMid + apex) / 2
		local slant = (apex - baseMid).Magnitude
		local width = 2 * apseEave * math.tan(math.pi / 8)
		local cf = CFrame.lookAt(centre, apex)
		-- two boxes approximate the trapezoid; the upper one stops short of the apex, where the cap takes over
		box(roof, `ApseLow{i}`, Vector3.new(width, 0.6, slant / 2 + 0.3), cf * CFrame.new(0, 0.3, slant / 4), P.roof)
		local upper = slant / 2 - 2.5
		box(roof, `ApseHigh{i}`, Vector3.new(width * 0.45, 0.62, upper + 0.3), cf * CFrame.new(0, 0.31, -(slant / 2 - upper / 2) + 0.15), P.roof)
	end
	for j = 0, 3 do
		local a = (j - 2.5) * math.pi / 4
		local foot = Vector3.new(0, groundTop + apseH - 0.1, apseZ) + apseDir(a) * (apseEave / math.cos(math.pi / 8))
		between(roof, `ApseHip{j}`, foot, apex + Vector3.new(0, 0.3, 0), 1.1, P.roof)
	end
	box(roof, "ApseCap", Vector3.new(6, 2.4, 4.6), CFrame.new(0, apexY + 0.6, back - 2.6), P.roof)

	------------------------------------------------------------------ interior: shafts, pews, altar, candles, lanterns, collapse
	local interior = ensure(root, "Interior", "Model")
	-- respond shafts on the nave face of every arcade pier, base block in the trim role
	local springY = floorTop + 10 - 6 * math.sin(math.pi / 3)
	for j = 0, BAYS do
		local z = z0 + j * BAY + (j == 0 and 0.7 or (j == BAYS and -0.7 or 0))
		for _, side in { -1, 1 } do
			local x = side * (W / 2 - 0.45)
			local tag = `{side < 0 and "W" or "E"}{j}`
			box(interior, `ShaftBase{tag}`, Vector3.new(1.1, 0.55, 1.1), CFrame.new(x, floorTop + 0.225, z), P.trim)   -- 0.05 into the floor so no face meets the pier foot
			post(interior, `Shaft{tag}`, 0.42, springY - 0.3 - (floorTop + 0.45), CFrame.new(x, (floorTop + 0.45 + springY - 0.3) / 2, z), P.trim)
		end
	end

	-- pews: seat, back, two end panels; the back faces the door so the pew looks at the altar
	local function pew(name: string, cf: CFrame, variant: string)
		local len, depth = 5, 1.4
		local seatY = 1.5
		local f = cf
		if variant == "tilted" then f = cf * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(14)) end
		for _, e in { -1, 1 } do
			box(interior, `{name}End{e > 0 and "R" or "L"}`, Vector3.new(0.3, seatY + 0.6, depth), f * CFrame.new(e * (len / 2 - 0.15), (seatY + 0.6) / 2, 0), P.beam)
		end
		if variant == "broken" then
			box(interior, `{name}SeatA`, Vector3.new(len * 0.55, 0.3, depth - 0.1), f * CFrame.new(-len * 0.21, seatY - 0.15, 0), P.beam)
			box(interior, `{name}SeatB`, Vector3.new(len * 0.4, 0.3, depth - 0.1), f * CFrame.new(len * 0.3, seatY - 0.7, 0.1) * CFrame.Angles(0, 0, math.rad(-28)), P.beam)
		else
			box(interior, `{name}Seat`, Vector3.new(len - 0.5, 0.3, depth - 0.1), f * CFrame.new(0, seatY - 0.15, 0), P.beam)
			box(interior, `{name}Back`, Vector3.new(len - 0.5, 1.6, 0.25), f * CFrame.new(0, seatY + 0.8, depth / 2 - 0.145), P.beam)
		end
	end
	local pewVariants = { west = { "whole", "whole", "tilted", "whole" }, east = { "whole", "broken", "whole", "whole" } }
	for k = 1, 4 do
		local z = z0 + 4 * BAY + 1 + (k - 1) * 3.4                -- the two front bays, under the roof that still stands
		pew(`PewW{k}`, CFrame.new(-5.2, floorTop, z), pewVariants.west[k])
		pew(`PewE{k}`, CFrame.new(5.2, floorTop, z), pewVariants.east[k])
	end

	-- altar on the platform: plinth, body, a top slab that has cracked and slid, cloth, candles
	local altarZ = z0 + platD / 2
	box(interior, "AltarPlinth", Vector3.new(6.4, 0.5, 3), CFrame.new(0, platTop + 0.25, altarZ), P.trim)
	box(interior, "AltarBody", Vector3.new(5.6, 2, 2.4), CFrame.new(0, platTop + 0.5 + 1, altarZ), P.wall)
	box(interior, "AltarBand", Vector3.new(5.8, 0.4, 2.6), CFrame.new(0, platTop + 0.5 + 1.3, altarZ), P.trim)
	local slabTop = platTop + 2.5
	local altarSlab = box(interior, "AltarSlab", Vector3.new(3.6, 0.4, 2.9), CFrame.new(-1.3, slabTop + 0.2, altarZ), P.trim)
	box(interior, "AltarSlabFallen", Vector3.new(2.6, 0.4, 2.9), CFrame.new(2.9, platTop + 1.4, altarZ) * CFrame.Angles(0, 0, math.rad(52)), P.trim)
	box(interior, "AltarCloth", Vector3.new(2.6, 0.12, 2.6), placeOn(altarSlab, Vector3.new(2.6, 0.12, 2.6), -0.6, 0), { Enum.Material.Fabric, Color3.fromRGB(88, 24, 30) })
	box(interior, "AltarClothDrop", Vector3.new(2.6, 1.4, 0.14), altarSlab.CFrame * CFrame.new(-0.3, -0.5, 1.45 + 0.05), { Enum.Material.Fabric, Color3.fromRGB(88, 24, 30) })

	-- candles: wax body, neon flame, a point light in the flame
	local function candle(parent: Instance, name: string, cf: CFrame, h: number)
		post(parent, name, 0.16, h, cf * CFrame.new(0, h / 2, 0), P.wax)
		local flame = box(parent, name .. "Flame", Vector3.new(0.2, 0.3, 0.2), cf * CFrame.new(0, h + 0.15, 0), P.flame)
		flame.CanCollide = false
		light(flame, "Light", "PointLight", 9, 1.6, Color3.fromRGB(255, 170, 90))
	end
	local altarCloth = interior.AltarCloth
	candle(interior, "AltarCandle1", placeOn(altarCloth, Vector3.new(0.32, 0, 0.32), 0.6, -0.7), 1.05)
	candle(interior, "AltarCandle2", placeOn(altarCloth, Vector3.new(0.32, 0, 0.32), 0.85, 0.1), 1.2)
	candle(interior, "AltarCandle3", placeOn(altarSlab, Vector3.new(0.32, 0, 0.32), 1, 0.7), 0.8)
	-- a fallen candlestick on the platform beside the slid slab
	box(interior, "CandlestickFallen", Vector3.new(0.2, 0.2, 2.2), CFrame.new(3.6, platTop + 0.1, altarZ + 2) * CFrame.Angles(0, math.rad(25), 0), P.iron)
	-- floor candle cluster by the west pier at bay 2, on an iron stand plus two on the floor
	local clusterCF = CFrame.new(-W / 2 + 2.6, floorTop, z0 + 2 * BAY + 0.9)
	post(interior, "StandSpike", 0.08, 2.6, clusterCF * CFrame.new(0, 1.35, 0), P.iron)
	post(interior, "StandPan", 0.55, 0.1, clusterCF * CFrame.new(0, 2.65, 0), P.iron)
	post(interior, "StandFoot", 0.5, 0.12, clusterCF * CFrame.new(0, 0.06, 0), P.iron)
	candle(interior, "StandCandle", clusterCF * CFrame.new(0, 2.7, 0), 0.8)
	candle(interior, "FloorCandle1", clusterCF * CFrame.new(0.9, 0, 0.4), 0.7)
	candle(interior, "FloorCandle2", clusterCF * CFrame.new(0.5, 0, -0.8), 0.5)

	-- hanging lanterns on iron brackets off two arcade piers
	local function lantern(parent: Instance, name: string, top: Vector3)
		local body = 1.3
		local base = top - Vector3.new(0, body, 0)
		for k, d in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
			box(parent, `{name}Post{k}`, Vector3.new(0.1, body - 0.1, 0.1), CFrame.new(base + Vector3.new(d[1] * 0.4, body / 2, d[2] * 0.4)), P.iron)
		end
		box(parent, name .. "Cap", Vector3.new(1, 0.16, 1), CFrame.new(top + Vector3.new(0, 0.08, 0)), P.iron)
		box(parent, name .. "Peak", Vector3.new(0.5, 0.25, 0.5), CFrame.new(top + Vector3.new(0, 0.28, 0)), P.iron)
		box(parent, name .. "Foot", Vector3.new(1, 0.16, 1), CFrame.new(base + Vector3.new(0, 0.08, 0)), P.iron)
		local flame = box(parent, name .. "Flame", Vector3.new(0.3, 0.45, 0.3), CFrame.new(base + Vector3.new(0, 0.16 + 0.22, 0)), P.flame)
		flame.CanCollide = false
		light(flame, "Light", "PointLight", 14, 1.4, Color3.fromRGB(255, 160, 80))
	end
	for _, spec in { { side = -1, j = 2 }, { side = 1, j = 4 } } do
		local z = z0 + spec.j * BAY
		local x0b = spec.side * (W / 2)
		local arm = Vector3.new(x0b - spec.side * 1.6, floorTop + 8.2, z)
		between(interior, `Bracket{spec.j}`, Vector3.new(x0b + spec.side * 0.2, floorTop + 8.2, z), arm, 0.14, P.iron)
		between(interior, `BracketBrace{spec.j}`, Vector3.new(x0b + spec.side * 0.2, floorTop + 7.1, z), arm - Vector3.new(spec.side * 0.2, 0, 0), 0.1, P.iron)
		box(interior, `Chain{spec.j}`, Vector3.new(0.26, 0.5, 0.26), CFrame.new(arm - Vector3.new(0, 0.28, 0)), P.iron)
		lantern(interior, `Lantern{spec.j}`, arm - Vector3.new(0, 0.6, 0))
	end

	-- the collapse: rubble under the open roof, fallen rafters, roof slabs on the floor
	local collapse = ensure(root, "Collapse", "Model")
	local function rubble(name: string, at: Vector3, size: Vector3, role)
		local cf = CFrame.new(at) * CFrame.Angles(math.rad(jit(-12, 12)), math.rad(jit(0, 180)), math.rad(jit(-12, 12)))
		return box(collapse, name, size, cf, role or P.rock)
	end
	local heapZ = z0 + 3 * BAY
	for i = 1, 9 do
		local sz = Vector3.new(jit(1.2, 3), jit(0.8, 1.8), jit(1.2, 2.6))
		local at = Vector3.new(jit(-7, 7), floorTop + sz.Y * 0.35, heapZ + jit(-6, 6))
		rubble(`Stone{i}`, at, sz)
	end
	for i, k in { 3, 7 } do                                    -- moss caps sit on two of the stones
		local stone = collapse:FindFirstChild(`Stone{k}`) :: Part
		local cap = Vector3.new(stone.Size.X * 0.7, 0.3, stone.Size.Z * 0.7)
		box(collapse, `MossStone{i}`, cap, placeOn(stone, cap, 0.2, -0.2), P.moss)
	end
	box(collapse, "FloorSlate1", Vector3.new(4, 0.5, 3), CFrame.new(-4, floorTop + 0.9, heapZ + 4) * CFrame.Angles(math.rad(18), math.rad(30), 0), P.roof)
	box(collapse, "FloorSlate2", Vector3.new(3.2, 0.5, 2.6), CFrame.new(5, floorTop + 0.3, heapZ - 5) * CFrame.Angles(0, math.rad(-20), math.rad(6)), P.roof)
	-- rafters that came down: one leaning on the west wall, one across the floor, one on a pew
	between(collapse, "FallenRafter1", Vector3.new(-W / 2 + 0.3, groundTop + H - 3, z0 + 3 * BAY + 0.4), Vector3.new(-3, floorTop + 0.35, z0 + 2.4 * BAY), 0.6, P.beam, 0.8)
	between(collapse, "FallenRafter2", Vector3.new(-8, floorTop + 0.4, heapZ + 5.5), Vector3.new(7, floorTop + 1.3, heapZ + 3.2), 0.6, P.beam, 0.8)
	between(collapse, "FallenRafter3", Vector3.new(W / 2 - 0.5, floorTop + 4.2, z0 + 3.6 * BAY), Vector3.new(3, floorTop + 0.4, z0 + 4.4 * BAY), 0.55, P.beam, 0.7)
	-- the east breach: a rubble ramp from the ground up to the floor, loose blocks on the broken wall tops
	local breachZ = z0 + 2 * BAY                                -- east wall bays 4-5 run from z0 + BAY to z0 + 3 BAY (its X runs front -> back)
	local rampLen, rampRise = 5, floorTop - groundTop + 0.6
	local rampAng = math.atan(rampRise / rampLen)
	box(collapse, "BreachRamp", Vector3.new(rampLen / math.cos(rampAng) + 0.4, 0.8, 8), CFrame.new(outerX + 1.2, groundTop + rampRise / 2 - 0.1, breachZ) * CFrame.Angles(0, 0, -rampAng), P.rock)          -- +X (outward) runs downhill
	for i = 1, 6 do
		local sz = Vector3.new(jit(1, 2.4), jit(0.6, 1.4), jit(1, 2))
		rubble(`BreachStone{i}`, Vector3.new(outerX + jit(-3, 4), groundTop + sz.Y * 0.3, breachZ + jit(-6, 6)), sz)
	end
	for i, spec in { { x = outerX - AT / 2, y = 10, z = z0 + 3 * BAY + 2 }, { x = outerX - AT / 2, y = 13, z = z0 + BAY - 2.5 }, { x = W / 2 + T / 2, y = 21, z = z0 + 3.5 * BAY }, { x = W / 2 + T / 2, y = 19.5, z = z0 + 2.3 * BAY }, { x = W / 2 + T / 2, y = 19.5, z = z0 + 2.8 * BAY } } do
		box(collapse, `TopBlock{i}`, Vector3.new(jit(1.2, 2), jit(0.7, 1.1), jit(1.2, 2)), CFrame.new(spec.x, spec.y + 0.45, spec.z) * CFrame.Angles(0, math.rad((i % 2 == 0 and 1 or -1) * jit(8, 20)), 0), P.wall)
	end

	------------------------------------------------------------------ paths
	local paths = ensure(root, "Paths", "Model")
	local pathCount = 0
	local function pathSlab(name: string, a: Vector3, b: Vector3, wdt: number)
		pathCount += 1
		local mid = (a + b) / 2
		local y = groundTop + 0.1 + (pathCount % 2) * 0.05                 -- neighbours overlap at the joints, so their tops must differ
		return box(paths, name, Vector3.new(wdt, 0.3, (b - a).Magnitude + 1), CFrame.lookAt(Vector3.new(mid.X, y, mid.Z), Vector3.new(b.X, y, b.Z)), P.dirt)
	end
	local pathPts = { Vector3.new(4, 0, 74), Vector3.new(-2, 0, 63), Vector3.new(3, 0, 55), Vector3.new(0, 0, front + porchD + 3 * tread + 1.6) }
	for i = 1, #pathPts - 1 do pathSlab(`Main{i}`, pathPts[i], pathPts[i + 1], 9 - i * 0.8) end
	local westPts = { Vector3.new(-6, 0, 51), Vector3.new(-24, 0, 49), Vector3.new(-31, 0, 44), Vector3.new(-31.2, 0, sideDoorZ) }
	for i = 1, #westPts - 1 do pathSlab(`West{i}`, westPts[i], westPts[i + 1], 5) end
	local backPts = { Vector3.new(-31.2, 0, sideDoorZ), Vector3.new(-34.5, 0, 12), Vector3.new(-31, 0, -12), Vector3.new(-26, 0, -30), Vector3.new(-8, 0, -36) }
	for i = 1, #backPts - 1 do pathSlab(`Back{i}`, backPts[i], backPts[i + 1], 4.5) end

	------------------------------------------------------------------ cemetery: low wall with a gate, graves, two monuments
	local cem = ensure(root, "Cemetery", "Model")
	local cx, cz, cw, cd = 0, -52, 46, 28                         -- centre and size of the plot
	local wallH, wallT = 1.4, 0.8
	local function cemWall(name: string, a: Vector3, b: Vector3, capTrim: number?)
		local mid = (a + b) / 2
		box(cem, name, Vector3.new(wallT, wallH + 0.3, (b - a).Magnitude), CFrame.lookAt(Vector3.new(mid.X, groundTop + wallH / 2 - 0.15, mid.Z), Vector3.new(b.X, groundTop + wallH / 2 - 0.15, b.Z)), P.plinth)
		box(cem, name .. "Cap", Vector3.new(wallT + 0.3, 0.25, (b - a).Magnitude + 0.1 - (capTrim or 0)), CFrame.lookAt(Vector3.new(mid.X, groundTop + wallH + 0.125, mid.Z), Vector3.new(b.X, groundTop + wallH + 0.125, b.Z)), P.trim)
	end
	local gateX, gateW = -8, 5
	local n, s, e, w = cz - cd / 2, cz + cd / 2, cx + cw / 2, cx - cw / 2
	cemWall("North", Vector3.new(w, 0, n), Vector3.new(e, 0, n))
	cemWall("East", Vector3.new(e, 0, n + wallT / 2), Vector3.new(e, 0, s - wallT / 2), 0.6)   -- short caps stop clear of the long walls' caps
	cemWall("West", Vector3.new(w, 0, s - wallT / 2), Vector3.new(w, 0, n + wallT / 2), 0.6)
	cemWall("SouthW", Vector3.new(w, 0, s), Vector3.new(gateX - gateW / 2 - 0.6, 0, s))
	cemWall("SouthE", Vector3.new(gateX + gateW / 2 + 0.6, 0, s), Vector3.new(e, 0, s))
	for _, side in { -1, 1 } do
		local x = gateX + side * (gateW / 2 + 0.6)
		box(cem, `GatePost{side < 0 and "W" or "E"}`, Vector3.new(1.2, 3.2, 1.2), CFrame.new(x, groundTop + 1.6 - 0.1, s), P.plinth)
		box(cem, `GateCap{side < 0 and "W" or "E"}`, Vector3.new(1.5, 0.35, 1.5), CFrame.new(x, groundTop + 3.1 + 0.175, s), P.trim)
	end
	-- an iron gate leaf hanging open on the east post
	local leafCF = CFrame.new(gateX + gateW / 2, groundTop + 1.4, s) * CFrame.Angles(0, math.rad(-55), 0) * CFrame.new(-gateW / 2 * 0.5, 0, 0)
	box(cem, "GateRailTop", Vector3.new(gateW * 0.5, 0.12, 0.12), leafCF * CFrame.new(0, 1.05, 0), P.iron)
	box(cem, "GateRailBottom", Vector3.new(gateW * 0.5, 0.12, 0.12), leafCF * CFrame.new(0, -0.9, 0), P.iron)
	for k = 1, 4 do
		box(cem, `GateBar{k}`, Vector3.new(0.1, 2.4, 0.1), leafCF * CFrame.new(-gateW * 0.25 + (k - 0.5) * gateW * 0.5 / 4, 0.1, 0), P.iron)
	end

	-- graves: three shapes, each with a lean; positions are a jittered grid with holes
	local function grave(name: string, cf: CFrame, kind: string)
		if kind == "slab" then
			box(cem, name, Vector3.new(1.6, 2.6, 0.4), cf * CFrame.new(0, 1.3 - 0.3, 0), P.trim)
			box(cem, name .. "Top", Vector3.new(1.1, 0.35, 0.34), cf * CFrame.new(0, 2.6 - 0.3 + 0.175, 0), P.trim)
			box(cem, name .. "Foot", Vector3.new(2, 0.4, 0.8), cf * CFrame.new(0, 0.2 - 0.15, 0), P.plinth)
		elseif kind == "cross" then
			box(cem, name .. "Base", Vector3.new(1.4, 0.6, 1.0), cf * CFrame.new(0, 0.3 - 0.15, 0), P.plinth)
			box(cem, name, Vector3.new(0.4, 2.8, 0.4), cf * CFrame.new(0, 0.45 + 1.4, 0), P.trim)
			box(cem, name .. "Arm", Vector3.new(1.5, 0.4, 0.44), cf * CFrame.new(0, 0.45 + 2.1, 0), P.trim)
		else
			box(cem, name .. "Base", Vector3.new(1.8, 0.7, 1.8), cf * CFrame.new(0, 0.35 - 0.15, 0), P.plinth)
			box(cem, name, Vector3.new(0.9, 3.2, 0.9), cf * CFrame.new(0, 0.55 + 1.6, 0), P.trim)
			box(cem, name .. "Tip", Vector3.new(0.6, 0.6, 0.6), cf * CFrame.new(0, 0.55 + 3.2 + 0.3, 0) * CFrame.Angles(0, math.pi / 4, 0), P.trim)
		end
	end
	local kinds = { "slab", "cross", "slab", "obelisk", "slab", "cross" }
	local gi = 0
	for row = 1, 4 do
		for col = 1, 6 do
			gi += 1
			if gi % 5 == 0 or (row == 2 and col == 4) then continue end        -- holes in the grid
			local gx = w + 5 + (col - 1) * 7 + jit(-1.5, 1.5)
			local gz = n + 4 + (row - 1) * 6 + jit(-1.2, 1.2)
			if math.abs(gx - gateX) < 4 and row == 4 then continue end         -- keep the gate approach clear
			local near = false
			for _, spot in { Vector3.new(12, 0, -47), Vector3.new(-13, 0, -52), Vector3.new(-16, 0, -44) } do
				if (Vector3.new(gx, 0, gz) - spot).Magnitude < 5 then near = true end
			end
			if near then continue end
			local lean = CFrame.Angles(math.rad(jit(-14, 14)), math.rad(jit(-20, 20)), math.rad(jit(-6, 6)))
			local kind = kinds[(gi % 6) + 1]
			local gcf = CFrame.new(gx, groundTop, gz)
			grave(`Grave{gi}`, gcf * lean, kind)
			if kind == "slab" and row % 2 == 1 then                               -- a grassed-over mound in front of some slabs
				box(cem, `Mound{gi}`, Vector3.new(1.8, 0.5, 3.4), gcf * CFrame.new(0, 0.1, 2.3) * CFrame.Angles(0, math.rad(jit(-8, 8)), 0), P.moss)
			end
		end
	end
	-- a cross that has come off its base
	box(cem, "FallenCross", Vector3.new(0.4, 0.4, 2.6), CFrame.new(-16, groundTop + 0.35, -44) * CFrame.Angles(math.rad(-8), math.rad(30), math.rad(90)), P.trim)
	box(cem, "FallenCrossArm", Vector3.new(1.4, 0.4, 0.44), CFrame.new(-16, groundTop + 0.35, -44) * CFrame.Angles(math.rad(-8), math.rad(30), math.rad(90)) * CFrame.new(0, 0, -0.6), P.trim)
	box(cem, "FallenCrossBase", Vector3.new(1.4, 0.6, 1.0), CFrame.new(-17.5, groundTop + 0.15, -42) * CFrame.Angles(0, math.rad(20), math.rad(6)), P.plinth)

	-- tomb chest with a cracked lid
	local tombCF = CFrame.new(12, groundTop, -47) * CFrame.Angles(0, math.rad(12), 0)
	box(cem, "TombPlinth", Vector3.new(5.4, 0.5, 3.4), tombCF * CFrame.new(0, 0.25 - 0.1, 0), P.plinth)
	box(cem, "TombChest", Vector3.new(4.6, 2, 2.6), tombCF * CFrame.new(0, 0.4 + 1, 0), P.wall)
	for k, d in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		box(cem, `TombPilaster{k}`, Vector3.new(0.5, 2.1, 0.5), tombCF * CFrame.new(d[1] * 2.15, 0.35 + 1.05, d[2] * 1.15), P.trim)
	end
	box(cem, "TombLid", Vector3.new(3.2, 0.4, 3), tombCF * CFrame.new(-0.9, 2.4 + 0.2, 0), P.trim)
	box(cem, "TombLidBroken", Vector3.new(1.9, 0.4, 3), tombCF * CFrame.new(1.9, 2.4 + 0.2 - 0.35, 0.3) * CFrame.Angles(math.rad(6), 0, math.rad(-18)), P.trim)
	-- tall monument: stepped base, pedestal, broken column with an urn beside it
	local monCF = CFrame.new(-13, groundTop, -52) * CFrame.Angles(0, math.rad(-8), 0)
	box(cem, "MonBase", Vector3.new(4.4, 0.6, 4.4), monCF * CFrame.new(0, 0.3 - 0.1, 0), P.plinth)
	box(cem, "MonStep", Vector3.new(3.2, 0.5, 3.2), monCF * CFrame.new(0, 0.5 + 0.25, 0), P.trim)
	box(cem, "MonPedestal", Vector3.new(2.2, 3, 2.2), monCF * CFrame.new(0, 1 + 1.5, 0), P.wall)
	box(cem, "MonCap", Vector3.new(2.6, 0.4, 2.6), monCF * CFrame.new(0, 4 + 0.2, 0), P.trim)
	post(cem, "MonColumn", 0.55, 3.2, monCF * CFrame.new(0, 4.4 + 1.6, 0), P.trim)
	box(cem, "MonColumnBreak", Vector3.new(1.2, 0.5, 1.2), monCF * CFrame.new(0, 7.6 + 0.2, 0) * CFrame.Angles(math.rad(8), 0, math.rad(-6)), P.trim)
	post(cem, "MonUrn", 0.6, 1.2, monCF * CFrame.new(2.6, 0.6 - 0.15, 1.6) * CFrame.Angles(math.rad(70), math.rad(20), 0), P.trim)

	------------------------------------------------------------------ forest: a ring of trees, rocks, bushes, ivy on the walls
	local forest = ensure(root, "Forest", "Model")
	local function tree(name: string, at: Vector3, scale: number, spin: number)
		local trunkR, trunkH = 1.3 * scale, 12 * scale
		local base = CFrame.new(at) * CFrame.Angles(0, spin, 0)
		post(forest, name .. "Trunk", trunkR, trunkH + 0.6, CFrame.new(at) * CFrame.new(0, trunkH / 2 - 0.3, 0), P.bark)
		post(forest, name .. "TrunkFlare", trunkR * 1.35, 1.6, CFrame.new(at) * CFrame.new(0, 0.5, 0), P.bark)
		for k = 1, 3 do
			local a = (k - 1) * 2 * math.pi / 3 + 0.4
			local foot = base * CFrame.new(math.cos(a) * 3.2 * scale, -0.4, math.sin(a) * 3.2 * scale)
			between(forest, `{name}Root{k}`, base * CFrame.new(math.cos(a) * trunkR * 0.6, 1.1, math.sin(a) * trunkR * 0.6).Position, foot.Position, 0.6 * scale, P.bark, 0.8 * scale)
		end
		local crown = base * CFrame.new(0, trunkH + 2.5 * scale, 0)
		for k = 1, 3 do
			local a = (k - 1) * 2 * math.pi / 3 + 1.1
			local tip = crown * CFrame.new(math.cos(a) * 4.5 * scale, 1.5 * scale, math.sin(a) * 4.5 * scale)
			between(forest, `{name}Bough{k}`, (base * CFrame.new(0, trunkH - 1.5 * scale, 0)).Position, tip.Position, 0.55 * scale, P.bark)
		end
		local crownSizes = { Vector3.new(11, 6, 10), Vector3.new(9, 7, 11), Vector3.new(8, 5.5, 8), Vector3.new(7, 5, 7) }
		local crownOff = { Vector3.new(0, 0, 0), Vector3.new(2.2, 1.6, -1.4), Vector3.new(-2.6, 2.8, 1.6), Vector3.new(0.8, 4.4, 0.6) }
		for k = 1, 4 do
			local cf = crown * CFrame.new(crownOff[k] * scale) * CFrame.Angles(math.rad(jit(-14, 14)), math.rad(jit(0, 90)), math.rad(jit(-14, 14)))
			box(forest, `{name}Crown{k}`, crownSizes[k] * scale, cf, P.leaf)
		end
	end
	local treeSpots = {
		{ -52, 62 }, { -64, 30 }, { -62, -8 }, { -58, -50 }, { -32, -64 }, { 30, -66 }, { 50, -56 }, { 60, -20 }, { 59, 22 }, { 50, 58 }, { 24, 64 },
		{ -40, 18 }, { -44, -30 }, { 44, -4 }, { 34, 50 },
	}
	for i, sp in treeSpots do
		tree(`Tree{i}`, Vector3.new(sp[1], groundTop, sp[2]), jit(0.85, 1.25), jit(0, math.pi * 2))
	end
	-- rocks: angular clusters of 3 bedded boxes
	for i, sp in { { -36, 56 }, { 42, 32 }, { -50, -20 }, { 30, -40 }, { -31, 8 }, { 56, 0 } } do
		for k = 1, 3 do
			local sz = Vector3.new(jit(1.6, 3.6), jit(1.2, 2.6), jit(1.6, 3.2))
			local off = Vector3.new(jit(-2, 2), 0, jit(-2, 2))
			box(forest, `Rock{i}_{k}`, sz, CFrame.new(sp[1] + off.X, groundTop + sz.Y * 0.32, sp[2] + off.Z) * CFrame.Angles(math.rad(jit(-18, 18)), math.rad(jit(0, 180)), math.rad(jit(-18, 18))), P.rock)
		end
	end
	-- bushes: two overlapping leaf boxes
	for i, sp in { { -34, 44 }, { 30, 44 }, { -30, -40 }, { 27, -34 }, { 40, 14 }, { -36, -6 }, { 12, 60 } } do
		local sz = Vector3.new(jit(3, 4.5), jit(1.8, 2.6), jit(3, 4.5))
		box(forest, `Bush{i}A`, sz, CFrame.new(sp[1], groundTop + sz.Y * 0.4, sp[2]) * CFrame.Angles(0, math.rad(jit(0, 90)), math.rad(jit(-8, 8))), P.leaf)
		box(forest, `Bush{i}B`, sz * 0.7, CFrame.new(sp[1] + jit(-1.5, 1.5), groundTop + sz.Y * 0.55, sp[2] + jit(-1.5, 1.5)) * CFrame.Angles(math.rad(jit(-10, 10)), math.rad(jit(0, 90)), 0), P.leaf)
	end
	-- ivy: thin leaf strips proud of the west aisle wall, the apse and the tower
	local function ivy(name: string, frame: CFrame, h: number, wdt: number)
		box(forest, name, Vector3.new(wdt, h, 0.3), frame * CFrame.new(0, h / 2, 0), P.leaf)   -- half in the wall, 0.15 proud; clear of the band faces either side
	end
	for i, spec in { { z = z0 + 0.6 * BAY, h = 9, w = 1.6 }, { z = z0 + 1.4 * BAY, h = 6, w = 1.1 }, { z = z0 + 2.55 * BAY, h = 11, w = 2.2 }, { z = z0 + 3.4 * BAY, h = 5, w = 0.9 } } do
		ivy(`IvyW{i}`, CFrame.fromMatrix(Vector3.new(-outerX, groundTop + 0.3, spec.z), Vector3.zAxis, Vector3.yAxis), spec.h, spec.w)
	end
	ivy("IvyTower1", CFrame.fromMatrix(Vector3.new(tE, groundTop + 0.5, towerZ + 3.5), -Vector3.zAxis, Vector3.yAxis), 16, 1.8)
	ivy("IvyTower2", CFrame.fromMatrix(Vector3.new(tE, groundTop + 6, towerZ - 2.5), -Vector3.zAxis, Vector3.yAxis), 9, 1.2)
	ivy("IvyApse", CFrame.new(0, groundTop, apseZ) * CFrame.Angles(0, math.pi / 4, 0) * CFrame.new(-2.2, 0.4, -apseR) * CFrame.Angles(0, math.pi, 0), 10, 1.5)


	------------------------------------------------------------------ grounds: the earth around the walls is not a flat lawn
	local grounds = ensure(root, "Grounds", "Model")
	-- shallow banks of earth against the walls and at the corners
	for i, spec in { { -30, 0, 22, 10, 14 }, { 30, -8, 20, 9, 12 }, { -18, 50, 12, 10, 8 }, { 12, -30, 14, 8, 20 }, { -38, 56, 10, 12, 0 } } do
		box(grounds, `Bank{i}`, Vector3.new(spec[3], 1.2, spec[4]), CFrame.new(spec[1], groundTop - 0.35, spec[2]) * CFrame.Angles(0, math.rad(spec[5]), 0), P.ground)
	end
	-- grass tufts: low moss boxes clustered along the wall feet and between the graves
	local tuftSpots = {}
	for k = 1, 9 do table.insert(tuftSpots, Vector3.new(-outerX - jit(1, 5), 0, z0 + jit(2, L - 2))) end
	for k = 1, 5 do table.insert(tuftSpots, Vector3.new(outerX + jit(1, 5), 0, z0 - jit(-2, 6) + k * 3)) end
	for k = 1, 4 do table.insert(tuftSpots, Vector3.new(jit(-9, 9), 0, back - apseR - jit(1, 4))) end
	for k = 1, 4 do table.insert(tuftSpots, Vector3.new(jit(-22, 22), 0, front + jit(3, 8))) end
	for i, sp in tuftSpots do
		local sz = Vector3.new(jit(1.4, 3.2), jit(0.35, 0.6), jit(1.4, 3.2))
		box(grounds, `Tuft{i}`, sz, CFrame.new(sp.X, groundTop + sz.Y * 0.35, sp.Z) * CFrame.Angles(math.rad(jit(-6, 6)), math.rad(jit(0, 180)), math.rad(jit(-6, 6))), P.moss)
	end
	-- stones shed from the walls, and two dressed blocks that came off the facade
	for i = 1, 8 do
		local sz = Vector3.new(jit(0.7, 1.6), jit(0.5, 1.0), jit(0.7, 1.5))
		local side = if i % 2 == 0 then 1 else -1
		box(grounds, `Shed{i}`, sz, CFrame.new(side * (outerX + jit(0.8, 4)), groundTop + sz.Y * 0.3, z0 + jit(0, L)) * CFrame.Angles(math.rad(jit(-15, 15)), math.rad(jit(0, 180)), math.rad(jit(-15, 15))), P.rock)
	end
	box(grounds, "FacadeBlock1", Vector3.new(2.2, 1.4, 1.8), CFrame.new(-16, groundTop + 0.5, front + 6) * CFrame.Angles(math.rad(-10), math.rad(25), math.rad(6)), P.wall)
	box(grounds, "FacadeBlock2", Vector3.new(1.6, 1.2, 1.6), CFrame.new(-14.5, groundTop + 0.4, front + 8.5) * CFrame.Angles(math.rad(8), math.rad(-40), 0), P.trim)

	------------------------------------------------------------------ the soldier: a skeleton in half a harness, slumped against the front-west buttress, run through
	local soldier = ensure(root, "Soldier", "Model")
	local buttFace = Vector3.new(-outerX - 4, groundTop, z1 - BAY)      -- outer face of buttress W1's base block
	local sf = CFrame.fromMatrix(buttFace, -Vector3.zAxis, Vector3.yAxis) -- +Z into the stone, -Z is where the legs go, X along the wall
	local bone, iron = P.bone, P.iron
	local function sbox(name, size, cf, role) return box(soldier, name, size, sf * cf, role or bone) end
	local function sbetween(name, a: Vector3, b: Vector3, wdt, role, d)
		return between(soldier, name, (sf * CFrame.new(a)).Position, (sf * CFrame.new(b)).Position, wdt, role or bone, d)
	end
	-- pelvis and belt, sat on the ground with the back to the stone
	sbox("Pelvis", Vector3.new(1.6, 0.9, 1.1), CFrame.new(0, 0.5, -0.5) * CFrame.Angles(math.rad(-12), 0, 0))
	sbox("Belt", Vector3.new(1.75, 0.28, 1.25), CFrame.new(0, 0.82, -0.45) * CFrame.Angles(math.rad(-12), 0, 0), iron)
	-- spine curving forward, ribs off it, sternum
	local spine = { Vector3.new(0, 1.2, -0.35), Vector3.new(0.05, 1.7, -0.25), Vector3.new(0.1, 2.2, -0.1), Vector3.new(0.15, 2.65, 0.05) }
	for k, v in spine do
		sbox(`Vertebra{k}`, Vector3.new(0.42, 0.5, 0.42), CFrame.new(v) * CFrame.Angles(math.rad(-16), 0, 0))
	end
	for k = 1, 5 do
		local y = 1.45 + (k - 1) * 0.3
		local zk = -0.3 + (k - 1) * 0.07
		local spread = 0.8 - math.abs(k - 3) * 0.12
		sbetween(`RibL{k}`, Vector3.new(-0.2, y, zk), Vector3.new(-spread, y - 0.3, zk - 0.85), 0.14)
		sbetween(`RibR{k}`, Vector3.new(0.2, y, zk), Vector3.new(spread, y - 0.28, zk - 0.85), 0.14)
	end
	sbox("Sternum", Vector3.new(0.3, 1.2, 0.16), CFrame.new(0.05, 1.75, -1.05) * CFrame.Angles(math.rad(-18), 0, 0))
	-- what is left of the harness: a dented breastplate, a lower plate, one pauldron, one greave
	sbox("Breastplate", Vector3.new(1.8, 1.35, 0.32), CFrame.new(0.05, 2.05, -1.2) * CFrame.Angles(math.rad(-20), 0, math.rad(4)), iron)
	sbox("PlateLower", Vector3.new(1.7, 0.7, 0.3), CFrame.new(0, 1.3, -1.05) * CFrame.Angles(math.rad(-8), 0, 0), iron)
	sbox("Clavicle", Vector3.new(1.9, 0.2, 0.22), CFrame.new(0.1, 2.85, -0.05), bone)
	sbox("PauldronL1", Vector3.new(0.95, 0.28, 1.0), CFrame.new(-1.0, 3.0, -0.15) * CFrame.Angles(0, 0, math.rad(28)), iron)
	sbox("PauldronL2", Vector3.new(0.85, 0.24, 0.9), CFrame.new(-1.25, 2.7, -0.2) * CFrame.Angles(0, 0, math.rad(42)), iron)
	-- skull dropped forward and to the right: cranium, brow ridge, jaw, two dark sockets
	local skull = CFrame.new(0.3, 3.35, -0.25) * CFrame.Angles(math.rad(38), math.rad(-10), math.rad(-22))
	sbox("Cranium", Vector3.new(0.78, 0.7, 0.85), skull)
	sbox("Brow", Vector3.new(0.72, 0.22, 0.3), skull * CFrame.new(0, -0.1, -0.5))
	sbox("Jaw", Vector3.new(0.5, 0.26, 0.55), skull * CFrame.new(0, -0.45, -0.15) * CFrame.Angles(math.rad(12), 0, 0))
	sbox("SocketL", Vector3.new(0.2, 0.2, 0.12), skull * CFrame.new(-0.18, -0.12, -0.5), iron)
	sbox("SocketR", Vector3.new(0.2, 0.2, 0.12), skull * CFrame.new(0.18, -0.12, -0.5), iron)
	-- left arm hangs to the ground; right arm still up on the sword grip
	sbetween("UpperArmL", Vector3.new(-0.95, 2.8, -0.1), Vector3.new(-1.35, 1.55, -0.55), 0.3)
	sbetween("ForearmL", Vector3.new(-1.35, 1.55, -0.55), Vector3.new(-1.3, 0.25, -1.5), 0.26)
	sbox("HandL", Vector3.new(0.42, 0.16, 0.55), CFrame.new(-1.3, 0.08, -1.8) * CFrame.Angles(0, math.rad(15), 0))
	local guard = Vector3.new(0.45, 2.6, -1.95)
	local tip = Vector3.new(-0.1, 1.0, 0.8)
	local grip = guard + (guard - tip).Unit * 0.7                     -- where the right hand closed on the hilt
	sbetween("UpperArmR", Vector3.new(1.0, 2.8, -0.1), Vector3.new(1.85, 2.3, -1.3), 0.3)
	sbetween("ForearmR", Vector3.new(1.85, 2.3, -1.3), grip + Vector3.new(0.2, 0.05, 0.15), 0.26)
	sbox("HandR", Vector3.new(0.5, 0.45, 0.45), CFrame.new(grip) * CFrame.Angles(math.rad(30), 0, math.rad(20)), bone)
	-- the sword: in through the breastplate, out the back, tip in the stone
	sbetween("Blade", guard, tip, 0.12, iron, 0.6)
	sbox("Crossguard", Vector3.new(1.7, 0.2, 0.3), CFrame.lookAt(guard, tip) * CFrame.Angles(0, 0, math.rad(8)), iron)
	local pommel = guard + (guard - tip).Unit * 1.5
	sbetween("Grip", guard, pommel, 0.24, P.beam)
	sbox("Pommel", Vector3.new(0.45, 0.45, 0.45), CFrame.new(pommel) * CFrame.Angles(math.rad(30), math.rad(30), 0), iron)
	-- legs folded: left knee up, right leg fallen open; one greave still buckled on the right shin
	sbetween("ThighL", Vector3.new(-0.55, 0.55, -0.7), Vector3.new(-1.1, 1.25, -2.4), 0.4)
	sbetween("ShinL", Vector3.new(-1.1, 1.25, -2.4), Vector3.new(-0.95, 0.3, -3.7), 0.34)
	sbox("FootL", Vector3.new(0.5, 0.3, 1.0), CFrame.new(-0.95, 0.15, -4.15) * CFrame.Angles(0, math.rad(-8), 0))
	sbetween("ThighR", Vector3.new(0.6, 0.5, -0.7), Vector3.new(1.7, 0.45, -2.2), 0.4)
	sbetween("ShinR", Vector3.new(1.7, 0.45, -2.2), Vector3.new(2.5, 0.25, -3.4), 0.34)
	sbetween("GreaveR", Vector3.new(1.75, 0.5, -2.3), Vector3.new(2.4, 0.3, -3.2), 0.5, iron, 0.42)
	sbox("FootR", Vector3.new(0.5, 0.3, 1.0), CFrame.new(2.65, 0.15, -3.85) * CFrame.Angles(0, math.rad(35), 0))
	-- a lantern on the ground beside the left hand, still lit
	lantern(soldier, "SoldierLantern", (sf * CFrame.new(-2.6, 1.3, -1.6)).Position)

	------------------------------------------------------------------ effects: fog, motes, moon shafts
	local fx = ensure(root, "Effects", "Model")
	local function carrier(name: string, size: Vector3, cf: CFrame): Part
		local p = ensure(fx, name, "Part") :: Part
		p.Size, p.CFrame, p.Anchored, p.CanCollide, p.Transparency, p.CastShadow = size, cf, true, false, 1, false
		return p
	end
	local function emitter(parent: Instance, name: string, props)
		local e = ensure(parent, name, "ParticleEmitter") :: ParticleEmitter
		for k, v in props do (e :: any)[k] = v end
		return e
	end
	local fogProps = {
		Texture = "rbxasset://textures/particles/smoke_main.dds", Color = ColorSequence.new(Color3.fromRGB(150, 168, 200)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 8), NumberSequenceKeypoint.new(1, 14) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.88), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(8, 14), Rate = 1.5, Speed = NumberRange.new(0.3, 0.8), SpreadAngle = Vector2.new(20, 20),
		Drag = 1, RotSpeed = NumberRange.new(-4, 4), Rotation = NumberRange.new(0, 360), LightEmission = 0, LightInfluence = 1,
		EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0.1, 0, 0),
	}
	emitter(carrier("FogCemetery", Vector3.new(cw - 4, 1, cd - 4), CFrame.new(cx, groundTop + 0.8, cz)), "Fog", fogProps)
	emitter(carrier("FogNave", Vector3.new(W - 2, 1, L - 6), CFrame.new(0, floorTop + 0.6, naveZ)), "Fog", fogProps)
	emitter(carrier("FogForest", Vector3.new(60, 1, 30), CFrame.new(-35, groundTop + 0.8, 30)), "Fog", fogProps)
	local moteProps = {
		Texture = "rbxasset://textures/particles/sparkles_main.dds", Color = ColorSequence.new(Color3.fromRGB(210, 220, 255)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.06), NumberSequenceKeypoint.new(0.5, 0.14), NumberSequenceKeypoint.new(1, 0.05) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.3), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(6, 10), Rate = 9, Speed = NumberRange.new(0.1, 0.3), SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -0.05, 0), LightEmission = 0.6, RotSpeed = NumberRange.new(-10, 10),
	}
	emitter(carrier("MotesNave", Vector3.new(14, 18, 2 * BAY - 2), CFrame.new(0, floorTop + 10, z0 + 3 * BAY)), "Motes", moteProps)
	emitter(carrier("MotesAltar", Vector3.new(10, 6, 6), CFrame.new(0, platTop + 4, altarZ)), "Motes", { Texture = moteProps.Texture, Color = ColorSequence.new(Color3.fromRGB(255, 200, 150)), Size = moteProps.Size, Transparency = moteProps.Transparency, Lifetime = moteProps.Lifetime, Rate = 4, Speed = moteProps.Speed, SpreadAngle = moteProps.SpreadAngle, Acceleration = Vector3.new(0, 0.05, 0), LightEmission = 0.8, RotSpeed = moteProps.RotSpeed })
	-- moon shafts: beams from the roof gap and two west clerestory windows down to the floor
	local function shaft(name: string, from: Vector3, to: Vector3, w0: number, w1: number)
		local a = carrier(name .. "Top", Vector3.new(1, 1, 1), CFrame.new(from))
		local b = carrier(name .. "Floor", Vector3.new(1, 1, 1), CFrame.new(to))
		local a0 = ensure(a, "A0", "Attachment") :: Attachment
		local a1 = ensure(b, "A1", "Attachment") :: Attachment
		a0.CFrame = CFrame.Angles(0, 0, math.rad(90))
		a1.CFrame = CFrame.Angles(0, 0, math.rad(90))
		local beam = ensure(a, "Beam", "Beam") :: Beam
		beam.Attachment0, beam.Attachment1 = a0, a1
		beam.Width0, beam.Width1 = w0, w1
		beam.Color = ColorSequence.new(Color3.fromRGB(170, 190, 240))
		beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.86), NumberSequenceKeypoint.new(0.7, 0.93), NumberSequenceKeypoint.new(1, 1) })
		beam.LightEmission, beam.LightInfluence, beam.Segments, beam.FaceCamera = 1, 0, 1, true
		beam.Texture = "rbxasset://textures/particles/smoke_main.dds"
		beam.TextureLength, beam.TextureSpeed, beam.TextureMode = 20, 0.02, Enum.TextureMode.Stretch
	end
	shaft("ShaftGap1", Vector3.new(-3, groundTop + H + 6, z0 + 2.6 * BAY), Vector3.new(2, floorTop + 0.2, z0 + 2.2 * BAY), 5, 9)
	shaft("ShaftGap2", Vector3.new(4, groundTop + H + 6, z0 + 3.4 * BAY), Vector3.new(7, floorTop + 0.2, z0 + 3.9 * BAY), 4, 8)
	shaft("ShaftWindow1", Vector3.new(-W / 2, clerSill + 3.5, z0 + 1.5 * BAY), Vector3.new(4, floorTop + 0.2, z0 + 1.2 * BAY), 2.5, 5)
	shaft("ShaftWindow2", Vector3.new(-W / 2, clerSill + 3.5, z0 + 4.5 * BAY), Vector3.new(4, floorTop + 0.2, z0 + 4.2 * BAY), 2.5, 5)
	-- a cool fill light in the roof gap and a spot through the east breach so the moon reads on the floor
	local moon = carrier("MoonFill", Vector3.new(1, 1, 1), CFrame.new(0, groundTop + H + 4, z0 + 3 * BAY))
	local fill = light(moon, "Light", "PointLight", 40, 0.5, Color3.fromRGB(150, 175, 235))
	fill.Shadows = false

	-- cutaway for inspection renders: roof and the east walls go see-through
	if INSPECT then
		for _, part in root:GetDescendants() do
			if part:IsA("BasePart") and (part.Parent == roof or (part.Parent == shell and (part.Name:match("^NaveE") or part.Name:match("^AisleE")))) then
				part.Transparency = 0.75
			end
		end
	end

	-- scale reference on the path
	if SCALE_REF then
		box(root, "ScaleRef", Vector3.new(2, 5, 1), CFrame.new(-8, groundTop + 2.5, front + 12), P.flame)
	else
		local ref = root:FindFirstChild("ScaleRef") if ref then ref:Destroy() end
	end

	------------------------------------------------------------------ lighting: night, cool moon, warm flames (Atmosphere is left alone)
	local Lighting = game:GetService("Lighting")
	Lighting.ClockTime = 0.4
	Lighting.Brightness = 1.2
	Lighting.Ambient = Color3.fromRGB(22, 26, 38)
	Lighting.OutdoorAmbient = Color3.fromRGB(38, 46, 68)
	Lighting.ColorShift_Top = Color3.fromRGB(150, 170, 220)
	Lighting.ColorShift_Bottom = Color3.fromRGB(20, 22, 34)
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 0.35
	Lighting.EnvironmentSpecularScale = 0.35
	Lighting.ShadowSoftness = 0.3
	local bloom = ensure(Lighting, "RuinedCathedralBloom", "BloomEffect") :: BloomEffect
	bloom.Intensity, bloom.Size, bloom.Threshold = 0.55, 28, 1.1
	local grade = ensure(Lighting, "RuinedCathedralGrade", "ColorCorrectionEffect") :: ColorCorrectionEffect
	grade.Brightness, grade.Contrast, grade.Saturation, grade.TintColor = -0.02, 0.14, -0.18, Color3.fromRGB(205, 215, 255)

	------------------------------------------------------------------ QA: numbers the eye cannot check
	local qa = {}
	local all, aligned = {}, {}
	for _, part in root:GetDescendants() do
		if part:IsA("BasePart") then
			table.insert(all, part)
			if part.Transparency < 1 then
				local o = part.CFrame.Rotation
				local ax = (math.abs(o.XVector.X) > 0.999 or math.abs(o.XVector.Y) > 0.999 or math.abs(o.XVector.Z) > 0.999)
					and (math.abs(o.YVector.X) > 0.999 or math.abs(o.YVector.Y) > 0.999 or math.abs(o.YVector.Z) > 0.999)
				if ax then
					local h = part.CFrame:VectorToWorldSpace(part.Size / 2)
					h = Vector3.new(math.abs(h.X), math.abs(h.Y), math.abs(h.Z))
					table.insert(aligned, { p = part, lo = part.Position - h, hi = part.Position + h })
				end
			end
		end
	end
	-- coplanar: two axis-aligned parts overlapping in volume and sharing a face plane will flicker
	local coplanar, E = 0, 0.02
	for i = 1, #aligned do
		for j = i + 1, #aligned do
			local a, b = aligned[i], aligned[j]
			local ox = a.lo.X < b.hi.X - E and b.lo.X < a.hi.X - E
			local oy = a.lo.Y < b.hi.Y - E and b.lo.Y < a.hi.Y - E
			local oz = a.lo.Z < b.hi.Z - E and b.lo.Z < a.hi.Z - E
			for _, axis in { "X", "Y", "Z" } do
				local rest = (axis == "X" and oy and oz) or (axis == "Y" and ox and oz) or (axis == "Z" and ox and oy)
				if rest and (math.abs(a.lo[axis] - b.lo[axis]) < E or math.abs(a.hi[axis] - b.hi[axis]) < E) then
					coplanar += 1
					if coplanar <= 5 then table.insert(qa, `  coplanar {axis}: {a.p:GetFullName()} / {b.p:GetFullName()}`) end
				end
			end
		end
	end
	-- near-duplicates: same size at (almost) the same spot
	local seen, dupes = {}, 0
	for _, part in all do
		local x = part.CFrame.XVector                                 -- mirrored voussoirs meet at an apex; their rotation tells them apart
		local key = string.format("%.1f,%.1f,%.1f|%.1f,%.1f,%.1f|%.2f,%.2f,%.2f", part.Position.X, part.Position.Y, part.Position.Z, part.Size.X, part.Size.Y, part.Size.Z, x.X, x.Y, x.Z)
		if seen[key] then dupes += 1 if dupes <= 5 then table.insert(qa, `  duplicate: {part:GetFullName()} ~ {seen[key]:GetFullName()}`) end else seen[key] = part end
	end
	-- orientation: roof planes climb toward the ridge, posts stand up, the breach ramp is walkable
	local badRoof, badPost = 0, 0
	for _, part in roof:GetChildren() do
		if part:IsA("BasePart") and part.Name:match("^Nave") then
			local x = part.CFrame.XVector
			if not (x.Y > 0.3 and x.X * part.Position.X < 0) then badRoof += 1 end
		end
	end
	for _, part in all do
		if part:IsA("Part") and part.Shape == Enum.PartType.Cylinder and (part.Name:match("^Shaft") or part.Name:match("Trunk$") or part.Name == "MonColumn") then
			if math.abs(part.CFrame.XVector.Y) < 0.97 then badPost += 1 end
		end
	end
	local ramp = collapse.BreachRamp
	local rampDeg = math.deg(math.asin(math.abs(ramp.CFrame.XVector.Y)))
	-- access: nothing solid stands in the doorway or the arcade aisle at walking height
	local blocked = 0
	for _, part in all do
		local pos = part.Position
		if part.Transparency < 1 and part.Parent ~= floors and part.Parent ~= steps and part.Parent ~= porch and part.Parent ~= shell
			and math.abs(pos.X) < 3.5 and pos.Y > floorTop and pos.Y < floorTop + 7 and pos.Z > front - T and pos.Z < front + porchD + 3 * tread then
			blocked += 1
		end
	end
	print(string.format("[RuinedCathedralMap] %d parts, %d checked for coplanar faces: %d coplanar, %d near-duplicates", #all, #aligned, coplanar, dupes))
	print(string.format("[RuinedCathedralMap] roof planes wrong way: %d, posts not vertical: %d, breach ramp %.0f deg (<= 30), parts blocking the door: %d", badRoof, badPost, rampDeg, blocked))
	for _, line in qa do print(line) end
	if coplanar + dupes + badRoof + badPost + blocked == 0 and rampDeg <= 30 then print("[RuinedCathedralMap] QA PASS") else print("[RuinedCathedralMap] QA FAULT -- see above") end

	return root
end

-- Command bar: `script` is nil there, so the map is rebuilt from scratch (the previous one is destroyed
-- first). Under VMCP apply_build the returned function is called with the root instead.
if script == nil then
	local old = workspace:FindFirstChild("RuinedCathedralMap")
	if old then old:Destroy() end
	build(ensure(workspace, "RuinedCathedralMap", "Model"))
end
return build
