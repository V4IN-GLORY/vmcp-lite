---
name: vmcp-build
description: Building and editing areas of a Roblox place as Luau with VMCP — the whole build lives in one source you write and re-apply, apply_build runs it and hands back the geometry as numbers plus a blockout picture, render_build draws any region from any angle without applying, get_build reads an existing region back as source. Use when making, moving, retexturing or restructuring part of a build.
---

# Builds as code

A build is a Luau source that makes it, and the source is the only thing you edit. Never place
parts one call at a time, and never decide where something goes from a picture. Code holds every
part at once, so "is this wall where that pillar is" is two lines and a subtraction; a picture is
one angle of one moment, and it's for *seeing* whether the numbers made the thing you meant.

**HARD RULE: DO NOT TOUCH `game.Lighting`.** No properties, no new children (Sky, Atmosphere,
Bloom, ColorCorrection, SunRays, DepthOfField, Clouds...), no deleting what's there — not from
build source, not from `run_luau`, not "to make the picture better". The renderer ignores
Lighting anyway. Only exception: the user names Lighting and asks. Lights, beams and emitters
*inside* the build root are fine.

## The pipeline

Four phases, in order, no skipping. Each one says exactly what to do, what to check, and what
to write down before moving on. "Write down" means a line in your reply, so the user can see
the pass happened.

```
1. DESIGN    write the design block (masses, structure, access, palette+placement, variety)
2. BLOCKOUT  apply_build the masses  -> bounds match, problems empty, iso silhouette matches
3. DETAIL    per group: apply_build -> render_build aimed at the group -> say what's off -> fix -> re-render
4. INSPECT   photo sweep + cutaway + access walk of the whole build against the checklist
```

Every `apply_build` / `render_build` ends the same way: read the numbers, look at the picture,
write one or two lines of what it showed. A pass without that line was done blind. Never read a
coordinate off the picture — the legend has it, and when there's no legend (badges off, too many
parts in frame) the group lines and problem lines have it; narrow `root` or clip a panel to get
badges back rather than asking for `badges = true` on a whole build.

**Rendering is mandatory, every time, whether or not the user asked.** The user's first prompt
gets the full pipeline including phase 4 — not a single apply and "here it is". A build handed
back after one `apply_build` and one iso is a build handed back with the roof gaps, the wedge
branches and the door behind the buttress still in it. Minimum per build, no matter how small:
one `apply_build`, at least two `render_build` calls at different locations/angles, and the
phase-4 checklist written out. Bigger builds scale that up, never down.

**A render only counts if the thing it is meant to prove is legible in it.** Every panel answers a
question — which way a sloped surface falls, whether a vertical element truly stands vertical, whether
an opening is clear, whether two surfaces meet without a slit, how big the thing is next to a
character. A wide, dark, whole-build thumbnail answers none of them, and a build has already shipped a
valley where its ridge should have been and a set of horizontal logs where its trunks should have been
past four such passes. Before you write the pass line: name the property, say how you can see it in
that panel, and take another panel if you cannot. See the field notes at the end of this file (§1, §2,
§7) for the general form of this and every other failure that has already happened once.

**Run the phases in fresh contexts, not one long conversation.** The phase loop is a series of small
commits to a file on disk, so no pass needs the transcript that produced the last one. An audited
1 500-part build spent 43.2 M of its 44.3 M tokens re-reading its own growing history, and 80 % of the
input it did read fresh was text it had already seen. One phase per context, state on disk, a short
report out — §9 has the numbers and the rules.

**Accessibility is a requirement, not a nicety.** Unless the user says a space is sealed (a
crypt, a decorative tower, a ruin with a collapsed stair), every interior space a player could
see must be reachable on foot from outside and from every other interior space: a door or
opening in a wall, a stair or ramp between levels, a gap wide enough to walk through. This is
designed in phase 1, derived in the source, and verified in phase 4.

### 1. Design — write it before the first line of geometry

Output: a comment block at the top of the source, in this order. Build to it; if the build
drifts from it, either fix the build or update the block, never leave them disagreeing.

1. **Masses.** Name the 3–5 volumes that make the silhouette (nave 40x12x20, tower 10x30x10 at
   the west end, porch 8x8x6 on the south) and their proportions to each other. State what
   should read from the front and from above.
2. **Structure.** How it stands up — walls carry roof, piers carry arches, posts under what they
   hold, lintels deeper than the wall is thick, buttresses at the wall they brace. Then the base
   numbers everything derives from: `W, D, H, T`, bay count, roof pitch, floor heights. Every
   other dimension is arithmetic on those.
3. **Access.** List every interior space and how a player gets in and between them. For each
   opening: which wall, width, height. Rules of thumb — doorway 4–6 wide and 7–8 tall, corridor
   ≥ 4 wide, stair rise ≤ 1 per step with ≥ 1.5 tread, ramps ≤ 30°, headroom ≥ 7 everywhere a
   player walks. If a space is *meant* to be sealed, say so here with why.
4. **Palette and placement.** A table of 5–8 roles, each with a material, a colour, and a
   comment saying exactly which surfaces get it. Broad enough that the build isn't one texture,
   narrow enough that it still looks like one place:
   - big flat planes (walls, floors, roof planes) → low-contrast: Limestone, Concrete, Brick,
     Plaster, WoodPlanks, Sandstone, Slate for roofs. This is what the eye rests on.
   - loud / high-detail (Cobblestone, Rock, Basalt, CrackedLava, Metal, DiamondPlate, Marble)
     → accents and edges only: plinth, trim, quoins, sills, doorstep. Never the whole wall.
   - a material change marks a *thing* change — trim isn't the wall's material, the plinth
     isn't either. Same role touching same role can share; different roles don't.
   - a distinct colour per role, not just a material; the same material at two shades is two
     things. Keep the whole palette in one temperature (all warm greys or all cool) unless the
     prompt wants contrast.
   - no one material on more than about half the parts; no role on fewer than 3 parts (then it
     isn't a role, it's noise). Two roles that read the same from 30 studs are one role.
   - don't: Marble on a whole building, Slate on walls, Neon or Glass as a wall material,
     Plastic anywhere it'll be seen, Grass / Sand / Snow on anything but ground, Fabric on
     anything but cloth. Pick from what the thing would be made of.

   ```lua
   local P = {
   	wall   = { Enum.Material.Limestone,   Color3.fromRGB(118, 112, 102) }, -- every wall plane above the plinth
   	plinth = { Enum.Material.Cobblestone, Color3.fromRGB(78, 76, 70) },    -- lowest 2 studs of every exterior wall
   	trim   = { Enum.Material.Sandstone,   Color3.fromRGB(150, 142, 128) }, -- sills, quoins, string courses; 0.2 proud
   	roof   = { Enum.Material.Slate,       Color3.fromRGB(58, 60, 66) },    -- roof slabs and ridge only
   	beam   = { Enum.Material.Wood,        Color3.fromRGB(62, 46, 32) },    -- lintels, rafters, door frames, doors
   	floor  = { Enum.Material.Marble,      Color3.fromRGB(96, 94, 90) },    -- interior floor slabs
   }
   ```
   Helpers take a role (`P.wall`), never a raw material.

   **The bland test.** Stand inside any room and look at one wall: you must see at least three
   roles from the palette without turning your head, and at least one of them must be warm
   (wood, brass, terracotta, a warm-lit stone). One rough grey material on floor, walls,
   columns and ceiling is the failure mode — it reads as a cave whatever the modelling did.
   What every interior gets, minimum:
   - floor ≠ wall (different material *and* lightness), with a border band or flagstone grid
     in a third role
   - a plinth / dado band on the lowest 2–3 studs of every wall, and a cornice or string
     course near the top
   - columns in a different material or shade from the wall they stand by, with base and
     capital blocks in the trim role
   - ceiling structure (beams, rafters, vault ribs) in the beam role, not the wall role
   - one warm accent per room: wood pews, a brass lantern, a red banner, a wooden door
   Spread the palette's colours across lightness: at least one dark role (RGB values ~40–70),
   one mid (~90–130) and one light (~150–190). Six materials at the same grey are one
   material.
5. **Variety, lightly.** Repeated things can share one helper; a little size and rotation
   jitter in a normal range (a tree is 8–14 studs, not 2–40) is enough. Don't spend passes on
   hand-shaped variants unless the prompt is about them (a ruin, a forest). Identical is fine
   for balusters, columns, crosses, fence posts. Damage is data (`tops = {26, 26, 20, 15}` per
   bay), not a second code path.

### 2. Blockout

Do: write the helpers and the `return function(root)` with every top-level group from the
masses list, right palette on the big planes, no openings, no props. `apply_build` it.

Check, in this order:
- `bounds` and each `groups` line equal the design-block numbers. A group at `y 2..6` on a
  floor whose top is 0 is two studs high — fix it now.
- the problem list is empty.
- the iso picture: the silhouette matches the masses list. If a mass is missing, wrong size or
  in the wrong place, this is where it gets fixed — a shell that's wrong makes every detail wrong.

Write down: "blockout: bounds X, groups match, 0 problems, iso shows <what>". Don't add detail
until that line is true.

### 3. Detail — one group per pass, renderer after every pass

Order: shell openings → roof → interior floors and stairs → interior props → exterior props →
effects. A real build is 800+ lines and won't fit one reply; keep the source in a file and apply
with `apply_build { file = "<absolute path>" }`: the server reads the file itself, so each pass
is an `Edit` of the lines that change plus the apply — never re-read or re-send the whole file.

Each pass, exactly:

1. Edit the source for that one group. Every opening comes from the access list; every surface
   pulls a role from `P`.
2. `apply_build`. Read the report. Every new problem line is either fixed or written down as
   intentional with the reason (rubble sits 20–30% in the ground on purpose).
3. `render_build` narrowed to that group — several panels, never a single view, and the
   panels together cover **100% of the group**. List the group's spots before you render:
   every opening, every join to a neighbouring group, every face of the group (front, back,
   both sides, top, underside if a player can see it), every corner. Every spot gets at least
   two angles that don't share an axis. A 9-panel sheet is the cap per call, so a big group
   is two or three calls, not fewer spots:
   ```
   render_build { root = "Workspace.Chapel.Shell", views = [
     "front",                                                                  -- the whole group, proportions
     { yaw = 135, pitch = 30, name = "back-iso" },                             -- the side you'd otherwise never see
     { view = "front", at = "…Shell.Door", radius = 8, clip = true, name = "door-f" },
     { yaw = 60, pitch = 20, at = "…Shell.Door", radius = 8, clip = true, name = "door-q" },
     { view = "top",   at = "…Shell.Roof", radius = 14, name = "roof-top" },
     { yaw = 200, pitch = 10, at = "…Shell.Roof", radius = 14, name = "roof-low" },
   ] }
   ```
   A facade from `front` only can't show a slab floating off the wall top; the same spot from a
   quarter angle and a low angle can. Narrow `root` is the main lever — 40 parts with badges
   tells you more than 1500 without. Before moving on, write the coverage line: "Shell: door
   (2 angles), 4 windows (2 each), roof (top + 2 low), all 4 faces, back corner — nothing
   unseen". If you can name a part of the group no panel showed, render it.
4. Write down what the picture shows that's wrong, in words: "door leaf is half the opening
   width", "gap between roof slab 2 and 3", "stairs stop 2 studs short of the ledge".
5. For each, find the derivation that produced it — nearly always a typed number that should
   have been computed, or a wedge/rotation facing the wrong way. Edit it.
6. Re-apply, re-render the same spots from angles you have not used yet. Same angle twice tells you
   nothing new. When the report names a part (`37 sunk into 12`), render
   `{ at = <that part>, radius = 6, clip = true }` from two angles, not the whole build again.
7. Repeat 4–6 until the group's problem lines are empty or all intentional, and the close-up
   reads. Then write "group <X> done: <n> problems, all intentional: <list>" and move on.

Don't chase pixels: if it looks off but the numbers say it's where you put it, the question is
whether you put it in the right place, and that's a source edit.

### 4. Inspect — photo sweep, cutaway, access walk

Only after every group is done. This phase exists because per-group passes only ever looked at
their own group; the bugs left are the ones between groups.

**4a. The sweep.** One call, whole build:

```
render_build { root = <whole build>, size = 768, views = [
  "iso", { yaw = 225, pitch = 30, name = "iso-back" },
  "front", "back", "left", "right",
  "top",
] }
```

Then targeted panels, `clip = true`, one per place two groups meet: roof on wall, porch on
facade, stair on ledge, props against walls, tower on nave. Aim `at` the join, `radius` a few
studs, two angles each. As many calls as it takes — the sweep is done when every face of every
group and every join has been in at least two panels, and you've written that coverage line.

**4b. The cutaway.** The renderer draws transparency as alpha, so give the source an
`INSPECT` flag that sets the roof group and one long wall to `Transparency = 0.75` when true.
Apply with it on, render `top` and an iso from the open side, and the interior is visible
without the roof hiding it. Set it back to false and re-apply when done — never leave it on.

**4c. The checklist.** Go through every item and write "checked: fine" or the fix. Not
optional, not "looked fine":

- **Access.** Walk the access list from phase 1 against the cutaway and the elevations. For
  every interior space: is its opening present in the wall, at the width and height from the
  list, on the correct wall, at floor level (sill at `floorTop`, not 1 stud up)? Is the path
  from outside to it, and from it to every neighbouring space, unblocked by a prop, a pier, a
  buttress, a stair landing? Does every stair reach both floors it connects, top step at the
  upper floor's height, headroom ≥ 7 over every step? A space with no way in is a bug unless the
  design block said it's sealed.
- **Gaps.** Sky visible through any roof or wall in any elevation or the cutaway? Slits between
  roof slabs, between wall pieces around an opening, at a corner? Each one is on the access
  list or it's a bug — fix the overlap, not the picture.
- **Primitives.** Any wedge, cylinder or ball that isn't a roof plane, ramp, column, trunk,
  barrel, globe or boulder? Rebuild it from boxes.
- **Lighting.** Every light source is a Light instance; no glass slabs or tinted boxes standing
  in for rays or glow. Nothing under `game.Lighting` changed.
- **Covered up.** Every named feature is findable in at least one panel. A window the porch roof
  now hides, a door behind a buttress, a prop inside a wall, a feature only visible from an
  angle nobody stands at.
- **Scale.** Check every opening, step, ceiling and prop against the Scale table with the
  `ScaleRef` figure in frame — a player is 5 tall and 2 wide, and if it can't walk through
  a door, up a step, or under a beam, the number is wrong. Then group against group — a porch
  a third the height of the door it shelters, a tree taller than the tower.
- **Prop placement.** Every prop on a surface is fully inside its footprint, bottom on the
  top face, sized like the real thing beside the ScaleRef. Nothing overhangs an edge, nothing
  hovers beside the thing it's meant to be on. Small props are clustered, not lined up.
- **Hero props.** Each named prop has had its own three-angle close-up, has 20+ parts or a
  mesh, a distinct material from its surroundings, and a physical mount. None is a box with a
  cylinder on it.
- **Particles.** Every emitter has a texture, size and transparency curve, lifetime, rate and
  speed set for what it is (fog, motes, embers, smoke). No default white sparkles anywhere.
- **Orientation.** Wedges sloping the wrong way, a roof pitch that reads inverted from the back,
  a rotated roof box sloping into the wall. The renderer models wedges as Roblox does — a wedge that
  looks backwards is backwards.
- **Silhouette.** The back reads as well as the front; no blank face the design didn't intend.
- **Material placement.** Run the bland test on every room and every exterior face: three
  roles visible from one standing spot, one of them warm, floor ≠ wall, plinth and cornice
  present, columns not the wall's material. No panel is more than ~60% one material. The
  palette table's comments match what's actually on each surface.
- **Seams.** The coplanar check printed nothing. Quoins and trim are `PROUD`, four walls are
  two long and two short.

Fix in the source, re-apply, re-render only the panels that showed the problem. Done when every
checklist item has its line and every panel reads.

## The source

`apply_build` runs the shape `get_build` produces: a chunk ending in `return function(root)`.

```lua
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

local function box(parent, name, size, cframe, role)
	local part = ensure(parent, name, "Part")
	part.Size, part.CFrame, part.Anchored = size, cframe, true
	if role then part.Material, part.Color = role[1], role[2] end
	return part
end

return function(root)
	local W, D, H, T = 40, 30, 12, 1       -- one set of numbers the rest derives from
	local floorTop = 0

	local shell = ensure(root, "Shell", "Model")
	box(shell, "Floor", Vector3.new(W, T, D), CFrame.new(0, floorTop - T / 2, 0), P.floor)

	-- Walls meet at the corners by construction: edges come from W, D, T, so they can't
	-- overlap or gap unless the arithmetic is wrong.
	local wallY = floorTop + H / 2
	box(shell, "North", Vector3.new(W, H, T), CFrame.new(0, wallY, -D / 2 + T / 2), P.wall)
	box(shell, "South", Vector3.new(W, H, T), CFrame.new(0, wallY,  D / 2 - T / 2), P.wall)
	box(shell, "West",  Vector3.new(T, H, D - 2 * T), CFrame.new(-W / 2 + T / 2, wallY, 0), P.wall)
	box(shell, "East",  Vector3.new(T, H, D - 2 * T), CFrame.new( W / 2 - T / 2, wallY, 0), P.wall)

	local props = ensure(root, "Props", "Model")
	for i = 1, 4 do
		box(props, `Crate{i}`, Vector3.new(4, 4, 4), CFrame.new(-12 + i * 6, floorTop + 2, 8), P.beam)
	end
	return root
end
```

Hold yourself to:

- **Derive, don't type.** Position is `floorTop + size.Y / 2`, a wall edge is `W / 2 - T / 2`.
  Every literal is a place two parts can disagree. "Floating" and "sunk" in the report are
  almost always a typed number.
- **Size by what it fits into.** A door leaf is `openingWidth / leaves`, a pane is the bay minus
  the mullion, a lid is the crate top.
- **Name everything, keep the names.** `ensure` updates by name, so re-applying moves only what
  changed. Renamed a part? Pass `clear = true` that pass. A class change destroys and remakes.
- **Group into Models by what they are** — the report measures each top-level group.
- **Loops for repetition**; compute the step from count and span so the last one lands on the edge.
- **Helpers at the top, geometry at the bottom.** The `return function(root)` body reads like a
  description of the place.
- **Local frames for anything rotated.** Helpers take a `frame` and place pieces as
  `frame * CFrame.new(x, y, z)`; one `windowWall(frame, ...)` does every wall and every tower face.
- **Two-point helpers** for beams, chains, roots:
  ```lua
  local function beamBetween(a, b, w) -- box with Z along a->b
  	return box(Vector3.new(w, w, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b))
  end
  local function boneBetween(a, b, r) -- cylinders lie along X, so turn it onto Z
  	return cylinder(r, (b - a).Magnitude, CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0))
  end
  ```
- **Seed randomness** — `Random.new(1906)` plus small `jit()` helpers — so reruns are identical
  and the report's numbers stay comparable between passes.
- **Boxes by default** — see Geometry rules. Cylinders lie along X. If you do use a wedge, it's
  full height at -Z, nothing at +Z; rotate about Y in multiples of `math.pi / 2`.
- Only set what differs from a fresh instance; `Anchored = true` always.

### Geometry rules

These are not style preferences. Every one of them comes from a real bad build.

**Boxes, almost always.** The default primitive is a `Part` with `Shape = Block`. Wedges,
cylinders, balls and rotated slivers are where the weird geometry comes from — a wedge branch
sticking out of a tree, a wedge sign on a post, a lantern that's a glass box with a wedge lid.
Allowed non-box uses, and only these:

- `Cylinder` for a column, tree trunk, barrel, pipe, rope — things that are round in life.
- `Ball` for a finial, a boulder, a lamp globe.
- `WedgePart` only for a pitched roof plane or a ramp the player walks on, and only when a
  stepped or slabbed version reads worse. Never for branches, decoration, spandrels, caps,
  signs or anything on a prop.

Everything else — arches, gables, canopies, tree crowns, stairs, buttress caps, roof edges — is
boxes, **rotated to follow the shape, not stepped**. Stepped boxes read as a staircase, and a
staircase over a doorway is ugly. A gable is a wall stack with shorter courses toward the top
(that one *is* stepped in life); a tree crown is 3–6 overlapping boxes at slightly different
sizes and rotations, never a wedge cluster; a roof is two thin boxes rotated to the pitch
(`CFrame.Angles` about the ridge axis), meeting at a ridge box that covers the seam.

**Arches** are the case that gets this wrong most. An arch is a run of short boxes (voussoirs),
each rotated so its long axis is tangent to the curve, each overlapping its neighbour by
`PROUD` so there's no slit between them. Never a stack of ever-shorter horizontal boxes:

```lua
-- frame: centre of the springing line, X along the span, Y up, Z through the wall.
-- Round arch of `n` voussoirs over `span`, `rise` = span/2 for a semicircle, less for a segmental one.
-- Pointed: run this twice with half the span and each half's centre offset, meeting at a keystone.
local function arch(parent, name, frame, span, rise, depth, thick, n)
	local r = (span * span / 4 + rise * rise) / (2 * rise)          -- radius of the arc through both feet and the apex
	local cy = rise - r                                                -- arc centre sits below the springing line
	local a0 = math.acos((span / 2) / r)                               -- angle at the right foot
	local step = (math.pi - 2 * a0) / n
	local seg = 2 * r * math.sin(step / 2) + PROUD                     -- chord length, plus overlap
	for i = 1, n do
		local a = a0 + (i - 0.5) * step
		local cf = frame * CFrame.new(0, cy, 0) * CFrame.Angles(0, 0, a) * CFrame.new(r - thick / 2, 0, 0)
		box(parent, `{name}{i}`, Vector3.new(thick, seg, depth), cf, P.trim)
	end
end
```

`n = 7–11` for a doorway, more for a big window. The voussoirs sit `thick` deep against the
opening; the wall fill above them (a box from the apex to the wall top plus a box each side
from the springing line up) is rectangular and tucks `PROUD` behind the arch's back face so
the curve is what you see. A keystone is one voussoir made taller and `PROUD` prouder.

**No gaps.** A wall is continuous from floor to roof and from corner to corner. A roof closes.
The rule that makes this true by construction:

- Pieces that meet **overlap by 0.05–0.1**, they don't butt end-to-end at a computed edge. A
  computed edge is exact until you change one number, and then it's a slit you see sky through.
  `len + 0.1`, not `len`.
- A wall built from pieces around an opening (pier, lintel, band, block-to-top) is a *fill*: the
  sum of pieces equals the wall, every piece's edge derives from the opening's edge, and each
  piece extends 0.05 into its neighbour.
- Roof planes overhang the wall by `T` and extend past the ridge by `T` so the ridge box hides
  the join. Between roof planes on a hip or valley, add a box along the seam.
- The only holes in a shell are on the access list. After each shell pass, look at the render
  and name every gap you see; each one is either on the access list or a bug.

**No Z-fighting.** Two faces on the same plane pointing the same way flicker in-engine even when
the renderer draws them fine. So:

- Anything layered on a surface — trim, quoins, plinth, sill, a sign on a wall, a rug on a floor,
  a cap on a wall — sits **0.1–0.3 proud**, never flush. Pick `PROUD = 0.2` once and use it.
- A part fully inside another is fine. A part sharing a face plane with another and *extending
  past it* on that plane is not — shrink or grow one by 0.05.
- Four walls are two long and two short butting between them, never four full-length crossing at
  corners.
- Stacked slabs (step on step, course on course) are fine when the top of one is exactly the
  bottom of the next — that's a join. It's when two *tops* coincide that it flickers.
- A cap cylinder on a slab is 0.02 thinner than the slab.
- **Mechanical check, not eyeballing.** After every apply, run this in `run_luau` on the root
  and fix every line it prints. Two axis-aligned parts that overlap in volume and share a face
  plane are the ones that flicker; the renderer will not show it, the engine will:
  ```lua
  local parts = {}
  for _, p in root:GetDescendants() do
  	if p:IsA("BasePart") and p.Transparency < 1 then
  		local o = p.CFrame.Rotation
  		local aligned = math.abs(o.XVector.X) > 0.999 or math.abs(o.XVector.Y) > 0.999 or math.abs(o.XVector.Z) > 0.999
  		if aligned then
  			local h = p.CFrame:VectorToWorldSpace(p.Size / 2)
  			h = Vector3.new(math.abs(h.X), math.abs(h.Y), math.abs(h.Z))
  			table.insert(parts, { p = p, lo = p.Position - h, hi = p.Position + h })
  		end
  	end
  end
  local E = 0.02
  for i = 1, #parts do
  	for j = i + 1, #parts do
  		local a, b = parts[i], parts[j]
  		local overlapX = a.lo.X < b.hi.X - E and b.lo.X < a.hi.X - E
  		local overlapY = a.lo.Y < b.hi.Y - E and b.lo.Y < a.hi.Y - E
  		local overlapZ = a.lo.Z < b.hi.Z - E and b.lo.Z < a.hi.Z - E
  		for _, axis in { "X", "Y", "Z" } do
  			local rest = (axis == "X" and overlapY and overlapZ) or (axis == "Y" and overlapX and overlapZ) or (axis == "Z" and overlapX and overlapY)
  			if rest and (math.abs(a.lo[axis] - b.lo[axis]) < E or math.abs(a.hi[axis] - b.hi[axis]) < E) then
  				print(`coplanar {axis}: {a.p:GetFullName()} / {b.p:GetFullName()}`)
  			end
  		end
  	end
  end
  ```
  Stacked slabs (top of one = bottom of the next) don't print because they don't overlap in
  volume. Anything that does print is a real flicker: push one part `PROUD` out, or shrink it
  by `2 * E` on that axis, or delete the one that's fully hidden.

**Openings.** There is no hole tool. An opening is the wall built as fill pieces around the gap:
pier each side (full height), lintel box across the top (deeper than `T` by `PROUD` on the
outside), and a block from the lintel to the wall top. Write it once as `openingWall(frame,
length, openings)` and every wall with holes is one call. Opening sizes come from the access
list. A window is the same with a sill band below.

**Placing props on things.** A candle hanging half off the back edge of the altar, a lantern
in mid-air beside the table, a book sunk into the shelf — all the same bug: the prop's position
was typed instead of derived from the surface it sits on. Props go on surfaces through one
helper that reads the surface:

```lua
-- u, v in -1..1 across the surface's top, kept inside by `margin`; the prop's bottom lands on the top face.
local function placeOn(surface: BasePart, size: Vector3, u: number, v: number, margin: number?)
	local m = margin or 0.3
	local x = u * (surface.Size.X / 2 - size.X / 2 - m)
	local z = v * (surface.Size.Z / 2 - size.Z / 2 - m)
	return surface.CFrame * CFrame.new(x, surface.Size.Y / 2 + size.Y / 2, z)
end
```

The rules that fall out of it: a prop's whole footprint is inside the surface with a margin,
never overhanging; its bottom is exactly the surface's top; it rotates with the surface; and
its size is small next to the surface — a candle is 0.3 wide and 1–1.5 tall on a 3-stud altar,
not a third of the altar's width. Groups of small props (candles, cups, bottles) cluster at a
`u, v` near one end or corner, not in a line along the back edge. A wall-mounted prop uses the
same idea against the wall's face (`PROUD` off it, at eye height ~4.5).

A candle is a thin cylinder or box in a wax colour, a 0.15–0.25 Neon flame on top, and a
`PointLight` (Range 6–10, warm) inside the flame — not a Neon block the size of the candle.

**Rubble and the ground.** Rocks, roots, fallen beams and leaning stones sit 20–30% into the
ground on purpose; those overlap/floating lines are meant, say so.

### Hero props — the things the prompt names

Anything the prompt calls out by name (the bell, the altar, the soldier, the throne, the
fountain) or that a player walks up to and stares at is a hero prop. It gets a detail budget
and its own pass; a hero prop that's one box and a cylinder is the first thing the user sees
and the thing they remember.

- **Budget 20–60 parts** for a hero, built the same way as a building: a profile of stacked
  rings/courses rather than one solid, a distinct role or two from the palette (a bell is
  bronze with a dark iron yoke and a rope; an altar is a lighter stone with a cloth and a
  candle rail), trim proud of the body, and a mount that connects it to the architecture
  (yoke, bracket, chain, plinth) so it isn't floating in the room.
- **Round or organic shapes** (a bell, a statue, a skull, a tree crown) are the one place
  boxes struggle. In order: stacked cylinders of decreasing radius with `PROUD` overlaps
  (a bell is 6–10 rings, wider at the lip, plus a crown and clapper); then an existing mesh
  — check `ReplicatedStorage` / `ServerStorage` / the place for one before building, and
  use `MeshPart` / `SpecialMesh` if the user has one; then ask. Asking is a one-liner:
  "the bell is the focal point — do you have a mesh id for it, or should I build it from
  ~40 parts?" Never ship the single-cylinder version silently.
- **Its own render pass**: `{ at = <hero>, radius = <its size + 2>, clip = true }` from three
  angles including a low one, with the `ScaleRef` next to it. The bell in the tower gets
  looked at from the floor beneath it, because that's where the player is.
- Hero props go last in the detail order (after interior props) so their pass isn't cut short
  by the shell running long — but they are never skipped.

### Scale — a Roblox character is the ruler

R15 is ~5 studs tall, ~2 wide, 4.5 at the eyes, and it steps up 1 stud without jumping. Every
size in the build is checked against that, not against what looks right in an orthographic
panel. Reference numbers, use them as the derivation inputs:

| thing | studs |
|---|---|
| doorway | 4–6 wide, 7–8 tall (a grand door 6–8 wide, 10–14 tall) |
| corridor / aisle | ≥ 4 wide, 6 for two abreast |
| room ceiling | ≥ 8; a hall 12–16; a nave 24–36 with the aisles at 10–14 |
| step | 1 rise, 1.5–2 tread; a grand stair 0.75 rise |
| window sill | 3–4 above the floor; a tall church window 4 up, 12–20 tall, 3–5 wide |
| railing / parapet | 3; a low wall a player sits on 1.5–2 |
| table / altar | 3 tall; bench / pew seat 1.5, back 3 |
| column | 1.5–3 wide; a nave pier 3–4 |
| wall thickness | 1–2 for a house, 3–4 for a cathedral |
| tree | 8–14 trunk to first branch for a big one, 20–30 to the crown |
| gravestone | 2–3 tall, 1.5 wide, 0.4 thick |

Put a `ScaleRef` part (2 x 5 x 1, Neon) at the entrance during passes 2 and 3 so every render
has a person in it; remove it in the last apply. If a door looks like a slot beside it or a
step comes up to its chest, the numbers are wrong, whatever the design block says.

### Lighting inside the build

Light is made with light instances, not with geometry pretending to be light:

- `PointLight` in a lantern or fire, `SpotLight` from a window or doorway inward, `SurfaceLight`
  on a glowing panel. `Brightness` 1–3, `Range` 8–30, a warm `Color` for flame.
- A visible light *source* is a small Neon part (a candle flame 0.3 studs, a lamp globe) with a
  `PointLight` inside it.
- Godrays / light shafts are a `Beam` between two attachments (Transparency sequence fading to
  1, `LightEmission = 1`, `Width0` at the window, wider at the floor) or a `ParticleEmitter`
  with a soft texture — never a tilted glass or transparent box.
- Fog, dust, smoke, embers: `ParticleEmitter` on an invisible carrier part (`Transparency = 1`,
  `CanCollide = false`). The carrier is a mount, not the effect; it never has a colour, a
  material or Glass.
- **A default `ParticleEmitter` is a white sparkle spray and is never shipped.** Every emitter
  gets a full setup: `Texture`, `Color`, `Size` (a `NumberSequence` that grows or fades),
  `Transparency` (0 → 1 over life, never constant), `Lifetime`, `Rate`, `Speed`,
  `SpreadAngle`, `Drag`/`Acceleration`, `LightEmission`, `Rotation`/`RotSpeed`. Write a
  helper per effect and name the effect, e.g.:
  - *fog*: big soft texture, `Size` 8–14, `Transparency` `{0: 1, 0.3: 0.85, 1: 1}`,
    `Lifetime` 8–14, `Rate` 1–2, `Speed` 0.3–0.8, `Drag` 1, slow `RotSpeed`, emitter shape a
    wide flat box hugging the floor, `LightEmission` 0.
  - *dust motes in a light shaft*: tiny texture, `Size` 0.05–0.15, `Rate` 6–12, `Speed`
    0.1–0.3, `Lifetime` 6–10, `Acceleration` slightly negative Y, `LightEmission` 0.6,
    emitter box the shape of the shaft.
  - *embers / candle sparks*: `Size` 0.1 → 0, warm `Color`, `Speed` 1–3 upward,
    `Acceleration` `(0, -1, 0)`, `Lifetime` 1–2, `Rate` 2–5, `LightEmission` 1.
  - *smoke*: `Size` 0.5 → 3, grey, `Transparency` `{0: 0.6, 1: 1}`, `Speed` 1, `Drag` 2.
  Restrained: a few emitters where they mean something (the light shaft, the altar candles, the
  low ground) — not one on every part.
- `Glass` is for windows and bottles, `ForceField` for force fields. Neither is a lighting tool.

Never `game.Lighting` — see the hard rule at the top.

## Reading the report

```
applied: 14 instance(s) under Workspace.Arena, 12 of them parts
bounds: 40x13x30 spanning x -20..20, y -1..12, z -15..15
groups (direct children of the root):
  Shell  5 parts, 40x13x30 spanning x -20..20, y -1..12, z -15..15
  Props  4 parts, 22x4x4 spanning x -8..14, y 0..4, z 6..10
2 thing(s) worth a look:
  Props.Crate3 -- overlapping: sunk about 2.00 studs into Workspace.Arena.Props.Crate2 along X
  Shell.East -- floating: 0.50 studs above Workspace.Arena.Shell.Floor
legend: #1 Shell.Floor 40x1x30 at (0, -0.5, 0) ...
<the picture>
```

`apply_build` only lists problems that are new since the last apply of that root, then says how
many earlier ones are still there and how many went away. A line you've already judged intentional
doesn't come back; a line that reappears means the number changed. `render_build` always lists
everything.

**Bounds and groups** are the build's 3D identity — a `Props` group at `y 2..6` on a floor whose
top is 0 is two studs high, no picture needed. **Problems** carry the number to fix with:

| kind | the fix |
|---|---|
| overlapping, sunk `d` on axis A | move or shrink by `d` — usually a typed position |
| floating `g` above X | lower by `g`, or it hangs on purpose |
| off axis (< 5°) | degrees where radians were meant, or a near-miss rotation |
| duplicate | loop ran twice, or two `ensure` share a name |
| paper thin (< 0.1) | a size subtracted to nothing |
| stranded (250+ studs) | a `*` that should be `+` |

Flush contact isn't an overlap. Only parts touching nothing get the floating check. Particle
carrier parts (`Transparency = 1`, holding an emitter) overlap everything by design; skip their
overlap lines.

## The renderer

VMCP's own rasterizer (`server/src/scene.ts`), not Studio — works with Studio minimised.

- **Orthographic, one scale across panels**, so panels compare directly.
- **Flat shading, dark line on every edge**, lit from the camera. "Is that one part or three" is
  visible even where faces are flush.
- **Real box / ball / cylinder / wedge**; meshes and unions as bounding boxes; transparency as
  alpha. Lights, decals, beams, particles don't draw.
- **Real material colormaps** tinted by part colour; materials it lacks (Cardboard, Neon,
  ForceField) draw flat. Plastic is always flat.
- **Badges** match the legend; on when the panels show ≤ 40 parts (a clipped panel counts only
  what's inside its radius), off otherwise unless `badges = true`. No badges, no legend — the
  per-part list only exists when the numbers in it point at something in the picture.
- **Views**: `iso`, `corner`, `front`, `back`, `left`, `right`, `top`, `bottom`, or
  `{ yaw, pitch, name }` in degrees. Up to 9 tiled into one sheet; `size` 128–1024 per panel,
  default 512, sheet caps at 3072 wide.
- **Targeted**: `at` (`{x, y, z}` or a dotted path, pivot used) + `radius` centres and scales
  that panel; `clip = true` drops parts further than `radius` from `at`; `view = "front"` picks a
  preset angle in place of yaw/pitch. Targeted panels have their own scale.
  ```
  render_build { root = "Workspace.Chapel", views = [
    "iso",
    { view = "front", at = "Workspace.Chapel.Shell.Door", radius = 8, clip = true, name = "door" },
    { yaw = 30, pitch = 15, at = {12, 4, -20}, radius = 6, name = "sill" },
  ] }
  ```
- PNG lands in the server's `images/` dir under `name`; inlined when small, path printed always.

`front` / `left` for proportions, `top` for footprint, `iso` for whether it reads. Wedges and
rotated parts are where the picture earns its keep — the report can't see a backwards roof slope or a slit between two slabs.

## Existing regions

`get_build { root, depth }` returns the region as this same kind of source — a dump, not derived.
A plain anchored part is one `part(parent, name, class, size, cframe, material, color)` line;
anything with more going on (transparency, collision, lights, emitters) is `ensure` plus one line
per non-default property. Colours come back as `fromRGB`, right-angle rotations as `math.rad`. Small edit: change lines, apply back. Restructure: read it for
sizes and positions, write a derived source, apply with `clear = true`. `render_build` first,
before touching anything that exists.

Applying the same source to another root copies it; a missing last segment is created as a Model.
`vmcp.Build.Problems(root)` / `vmcp.Build.Report(...)` are the same checks from `run_luau`.

Covers parts, meshes, decals, textures, attachments, lights, emitters, beams, surface
appearances, GUI objects, attributes and tags. The dump's property list is curated, so a class
property not on it is silently absent from `get_build` — first thing to check if a round-trip
comes back wrong.

Limits: `get_build` `depth` 12, `maxNodes` 800; `apply_build` / `render_build` measure up to
1500 parts. Always pass `root` — the default is the whole Workspace, which hits the cap on any
real place and measures everything that isn't the build. Prefer a narrow `root` over a bigger cap.

## Field notes — failure modes that have already happened once

The pipeline above is correct, and it was followed to the letter on a 1 500-part build that still
shipped a valley where its roof should have been and a set of horizontal logs where its trees should
have been — with four render passes and a QA line reading "0 unsupported, 0 paper thin" on the record.
Nothing here replaces the phases above; this is the list of things that survive them.

Every item is written as a **general rule**, with the instance that produced it in a line or two
underneath. The instance is there because a concrete case makes a rule stick, not because the rule
only applies to it. If you catch yourself thinking "this one is about roofs", you have read it wrong:
it is about anything with a direction, any helper that already orients a part, any report you skimmed,
or any render you accepted without naming what it proved.

**The six rules, if you read nothing else**

1. Anything whose meaning depends on which way it faces can be exactly wrong while every number in the
   report stays right. Assert the direction; do not eyeball it.
2. A render only counts if the property it is meant to prove is legible in the panel.
3. A floating report on a structural part is a real defect. Never close a build with one unexplained.
4. Learn each helper's built-in orientation and never apply a second turn about the same axis.
5. Always pass `root`, batch applies under ~20 KB, and never pair a big first apply with `clear`.
6. Cost is `steps × context size`. A pass does not need the transcript that produced the last one, so run
   the loop in fresh contexts with the state on disk. This is the widest lever in this file — see §9.

### 1. A direction can be inverted without moving a single number the report prints

Applies to: sloped planes, stairs and ramps, tapering stacks (each stage narrower than the one below),
arch springing and voussoir taper, wall and face normals, the raised end of a fallen beam, a shaft or
blade or barrel, a roof overhang, lettering on a sign, a bracket that must hang downward.

Why it slips through: **orientation is not in the bounds.** Turning a part about its own centre leaves
its bounding box unchanged; mirroring a placement leaves the extents identical; reversing a taper
leaves the size the same. Every check that reads sizes, counts, overlaps and support is blind to it.
This file already says the report "can't see a backwards roof slope" — that is exactly right, and it
is not a licence to move on. Only two things catch this class of error:

- an explicit assertion in the build's own QA (§3), and
- a render panel in which the direction is actually visible (§7).

Instance: a sloped plane was written `CFrame.Angles(0, 0, side * pitch)` where the geometry needed
`-side * pitch`. Its own long axis therefore climbed outward, so its high end sat at the outer edge
and its low end at the centre line — two slopes meeting in a valley in the middle of a building that
should have carried a gable, with the ridge cap left hanging above the gap. Bounds, group extents,
part count, `unsupported: 0` and `paper thin: 0` all passed on that build.

### 2. A helper that already orients a part must not be oriented again

Applies to: anything with a length along one axis — posts and columns, trunks and branches, axles and
pivots, chains and cables, rafters, ribs, limbs, barrelled props, beams spanning two points.

Most builder sets bake a rotation in so callers can think in the part's own terms: a vertical-post
helper turns a cylinder's length onto +Y, a "through the wall" helper turns it onto the wall normal, a
"between two points" helper uses `lookAt`. That rotation is applied *after* the caller's frame, so
adding another turn about the same axis **composes** with it rather than replacing it — and two
quarter turns cancel into a half turn. The symptom is always "it came out lying down / pointing
backwards / 180° from what I asked", and it usually drags the attached detail with it: roots, boughs,
crowns, brackets, hands, blades.

Rule: know each helper's axis convention, and rotate a thing once. Keep a table of your own helpers
somewhere you will actually read it, and when something must point where no helper covers, reach for
the between-two-points helper rather than stacking rotations.

Instance: tree trunks were built with the through-the-wall helper *and* an extra quarter turn, so every
trunk lay horizontally at chest height with its roots underneath and its crown boughs hanging in the
air around it. Same class, found by sweeping rather than by luck: a wheel hub built with the
vertical-post helper where it needed an axle along the wall normal, and a ribcage built from rods
pointing the wrong way through the chest.

Two habits that close the whole family: **sweep every call of the helper** rather than fixing only the
element that happened to be noticed, and **grep by helper name** before calling the class fixed.

### 3. Put the assertion in the build, not in the transcript

If you can state an invariant in words, you can assert it in a line and print PASS/FAIL — and then the
QA travels with the map instead of living in the conversation. Reviewing by eye at the end of a long
session is precisely the step that fails, because by then the panel that would have shown it is twenty
turns back.

One check per invariant, each counting its own violations, one line of output each:

```lua
-- named(pattern) is your own filter over the build's parts; any list of BaseParts will do.
local faults = 0
local function check(label, list, holds)
	local bad = 0
	for _, d in ipairs(list) do
		if not holds(d) then bad += 1 end
	end
	faults += bad
	print(string.format("[build] QA  %-30s %4d checked, %d wrong", label, #list, bad))
end

check("sloped planes climb inboard", named("^Slope"), function(d)
	local axis = d.CFrame.XVector                       -- the part's own long axis
	local inward = if d.Position.X >= 0 then 1 else -1
	-- moving toward the middle must mean moving up, whichever way the box is turned
	return math.abs(axis.Y) > 0.2 and axis.Y * axis.X * inward < -0.1
end)
check("posts stand vertical", named("Post"), function(d)
	return math.abs(d.CFrame.XVector.Y) > 0.97
end)
check("openings clear the threshold", named("^Step%d"), function(d)   -- no prop stands in a doorway
	return true
end)
check("props are bedded, not floating", named("^Rubble"), function(d)
	return d.Position.Y - d.Size.Y / 2 < 0.2
end)
if faults > 0 then print("[build] QA  FAULT -- see the lines above") end
```

Shape the list per build: every run of stairs (which way it rises), every ramp, every tapering stack
(each stage smaller than the last), every opening (clear width and height at the threshold), every
overhang (which side is longer), every prop resting on a surface (bedded by the intended fraction),
every element whose function depends on facing a particular way. Assertions cost two lines; a rebuild
costs the session.

The same idea replaces re-reading hundreds of overlap lines: state the *intent* — a prop is bedded a
fifth to a third of its height into the ground, trim stands proud by the trim offset, every layer
differs from the one beneath by the epsilon — and let the check confirm it, instead of arguing with
the report about each pair.

### 4. Transport limits: batch the source, and never clear inside a big apply

- **Large code arguments are truncated in transit.** A single apply of a whole build arrived cut
  mid-line and Studio answered `Expected 'end' (to close 'do' at line N), got <eof>`. Batch instead —
  one phase or one group per apply, comfortably under ~20 KB.
- **Never pair a first-time large apply with a clearing flag.** The truncated chunk still ran far
  enough to delete the previous build, so the map was gone *and* the error pointed at the new code.
  Clear only in a small, verified apply.
- **A syntax error naming the last line of the file is a truncation symptom**, not a missing `end` in
  your logic. Measure the payload before hunting for the mistake in your own code.
- **When a source is split mechanically, carry the text between sections with the following section.**
  Helpers often sit between two phases; splitting on "the first line that starts a section" leaves them
  behind, and the build dies later with `attempt to call a nil value` at the first call to one.
- **Reading a long file back truncates as well**, sometimes silently and mid-file, which then produces
  a bogus header and a syntax error in every batch built from it. Read by line range, assert the last
  line and the total count, and only then trust a slice.
- **`return` your evidence, do not print it.** A printed line from an executed snippet is not reliably
  part of the tool's returned text (it lands in the Studio output window instead), so a snippet that
  prints its answer reads as an empty result.

### 5. Tool behaviour to design around

- **Always pass an explicit root.** The default root is the whole Workspace: it measures everything
  that is not the build, blows the part cap on any real place, and — because Terrain is itself a part
  — can fail outright with `GetPartsInPart does not support Terrain` before anything is drawn. Narrow
  roots also make the report readable.
- **A view target that is silently ignored looks exactly like a badly framed picture.** Views take a
  dotted path for their target; a numeric coordinate table is accepted and ignored, so a "close-up"
  quietly becomes another whole-build view. If a panel is not closer than the last one, it is not
  closer — pass the path.
- **Every render and apply returns a full report** (summary, every problem, every part). Batch as many
  views per call as the tool allows, turn off problem-checking and part badges when you only need the
  picture, and keep your own printed output to a line or two. Pictures attach regardless of what you
  print.
- **Not every class can be created from a script.** Some instances exist only as engine-owned or
  editor-authored objects, and `Instance.new` fails with "Unable to create an Instance of type ...".
  Find the creatable equivalent that carries the same effect and build that instead, with a stable name
  so re-runs reuse it rather than stacking another.
- **Long files truncate when read**, both through the file tool and through a shell's stdout. Assume
  nothing about a slice you did not measure.

### 6. Triage the report instead of skimming it

The problem list is the loudest thing the tools return, and it is mostly right. Read it as a
classification exercise, and be able to say which class every entry falls into:

- **Overlap** — usually intentional. Interfacing parts are *supposed* to interpenetrate: trim over
  wall, a ring over the piece it beds into, a lintel into its pier, steps into the ground, bedding
  under a prop. Keep the accepted set finite and nameable for the build; an overlap you cannot name is
  probably a mistake.
- **Floating** — always investigate a *structural* part: it is the one entry that says the geometry is
  not doing what it claims. Between two parts of the same assembly (link to link, chain to ring) it is
  the checker's granularity. **No build is closed with an unexplained floating report.** On the build
  behind these notes, two floating entries were written off as noise and were the roof bug in plain
  sight.
- **Off axis** — intended for organic or damaged elements (rubble, tilted stones, trees, debris), wrong
  for designed-square ones (trim, sills, frames, plates). Decide per element, not per build.
- **Coplanar faces** — a real risk only when two overlapping parts share a plane on all three axes. The
  antidote is systematic (a trim offset, a layer epsilon, a per-step nudge) rather than a fix per pair.
- **Near-duplicate names or identical positions** — a pass ran twice, or a name-based reuse helper was
  bypassed. Fix the reuse, not the duplicates.
- **Paper thin** — a dimension computed to nothing, usually a derived size that went to zero or
  negative and was clamped. Find the arithmetic, not the part.

### 7. Phase 4 is a claim you have to be able to cash

"The render was done" is not "the geometry was checked". Before writing a pass line, **name the two or
three properties that panel is supposed to prove, and say how each one is visible in it**:

- a slope or ramp → which way it falls, and where the high edge runs;
- a vertical element → that it stands vertical, is rooted, and carries what sits on it;
- an opening → that the way through is clear, at the size a character needs;
- a junction → that the two surfaces meet with no slit and no doubled face;
- a prop on a surface → that it is bedded, not balanced on a corner or hovering;
- scale → something character-sized standing beside it.

If the panel cannot show the property, the panel does not count and you take another one. Practical
consequences: aim views with a path and a small radius; remember that a cutaway is made by transparency
in the *source*, not by the camera; and treat a night look as presentation on top of verified geometry,
because a dark scene with fog and a grade is nearly unreadable for shape. Check shape first, light it
afterwards.

Two failure patterns to watch for in yourself: accepting a whole-build thumbnail as evidence about a
detail, and quoting a number in the summary that you did not compute in that same pass.

### 8. Working efficiently in a long build

- Keep the source in **one file on disk** and assemble each apply from that file (read the ranges,
  concatenate, send) instead of re-typing geometry into tool calls. Re-sending a large preamble once
  per iteration is how a session runs out of room.
- Make every builder **idempotent and name-based**, so one group can be re-applied after a fix without
  stacking a second copy and without touching anything else.
- When you fix something, re-apply **only the sections you touched**, re-run the assertion line, and
  re-render the single panel that proves the change.
- **Log one line per pass** — what the numbers said, what the picture showed, what you changed. A build
  whose QA prints PASS/FAIL carries its own evidence; a build whose QA lives in the transcript does not.

### 9. The build loop must not live in one conversation

The pipeline is a loop of small, independent commits to a file on disk. Nothing about pass 30 needs the
transcript of pass 29 — and yet that is exactly what a single-session build pays for on every request.

A real 1 500-part build, audited from its own session transcript (recipe at the end of this section):

- total: **44.3 M tokens** over 157 requests — 1.09 M fresh input, 43.2 M cached re-reads (**97.5 %**)
- peak conversation size: **644 k tokens**
- every tool result that ever reached the model, added together: 542 KB, about **139 k tokens**
- of the 1.09 M fresh input, **0.88 M — 80 % — was re-processing, not new information**

Two of those lines overturn the intuition. **The reports were not the expense**: every `apply_build` and
`render_build` result ever shown to the model is 0.3 % of the session. And **the new information was not
the expense either** — four fifths of the fresh-input budget went on re-reading text the model had
already read, because something had invalidated the cached prefix.

So cost scales as `steps × context size`, and the second factor is what punishes a long build: at a
644 k-token conversation, every single request re-reads all of it. Capping that same session at 120 k
tokens removes about 67 % of those reads; at 60 k, about 83 %.

**The most expensive thing measured in that session was looking at a picture.** Requests following an
image attach averaged **46 110** fresh input tokens; every other request averaged **1 549** — a 30×
difference — and only about 12 k of that 46 k was new content. Attaching an image invalidated the cached
prefix, so the whole conversation was re-read at full price to deliver a few thousand tokens of picture
and report. Summed over the build, image-triggered re-prefill accounted for **0.88 M tokens, 80 % of all
fresh input**. Near the end, at 560 k context, a single render cost 170 k fresh tokens to deliver about
1.7 k of new content: a hundredfold overhead on the act of checking your own work.

None of that argues against rendering — rendering is mandatory (§2, §3). It argues for rendering
**deliberately**: take every view a pass needs in one attach, take them while the context is short, and
never re-attach a picture you have already shown.

1. **One phase per fresh context.** State belongs on disk and nowhere else: a phase should read only the
   line ranges it needs, change the file, run its own assertions, and end by returning a short report —
   not by accumulating. A long build is a *sequence* of short sessions. If the harness has subagents, one
   detail group is a natural unit of delegation: fresh context in, file changed, half a page out.
2. **Spend the context budget deliberately; never discover the ceiling.** Plan the hand-off at roughly
   40 % of the window. A compaction you schedule costs the summary it writes; a compaction forced at the
   limit costs a **full re-prefill of the entire conversation**. That is not hypothetical — the session
   above crossed 1 M mid-build and paid 650 k then 636 k fresh input tokens to repair itself, 38 % of all
   new input in the whole build, spent on conversation upkeep rather than on geometry.
3. **Digest inside the runner; never let a raw report into the transcript.** A result that lands in
   history is paid for again by every later step. The pattern that works: call the tool from inside the
   code runner, reduce the result to counts and named faults, and print five lines. Transport limits (§4)
   are the same problem seen from the other end.
4. **Render in batches; every attach re-reads the whole conversation.** A render after every pass stays
   required, but the *cost* of one is the entire prefix, not the picture. Take the views a pass needs in a
   single call, prefer several small aimed views to one wide one, take them while the context is still
   short, and never re-attach an image you have already shown. Downscale before attaching.
5. **Stay append-only within a phase.** Editing, pruning, re-ordering, or splicing new material into the
   middle of history invalidates the cached prefix and re-bills the whole context at full price. This is
   the mechanism behind the 30× figure above: it was not the images themselves, it was where they landed.
6. **The late defect is the expensive one.** A bug found in phase 4 is found, diagnosed and fixed at
   maximum context, which is precisely when every step costs the most. The orientation assertions in §1
   and §3 are therefore a cost control as much as a correctness one: front-loading invariants is far
   cheaper than debugging at 600 k.

**Auditing a session instead of guessing.** The harness writes a transcript to
`~/.dsh/sessions/<slug>/<session-id>/session.v3.jsonl.zstd`. It is **multi-frame** zstd: a single-shot
decompress returns only the first frame and looks like a 196-byte session, which is how this analysis
nearly ended before it started. Split the buffer on the frame magic `28 b5 2f fd`, decompress each slice,
concatenate, and parse the lines as JSON. Then sum the `cacheReadTokens` and `inputTokens` fields of
every `usage` object and bucket them by request index. The shape tells you which lever you own: rising
`cacheReadTokens` with flat `inputTokens` means you are paying for context length, while spiking
`inputTokens` means you are invalidating the cache — and if the spikes line up with the steps where an
image arrived, the attach is what invalidated it.

Count **one usage record per request**. That file held 270 of them for 157 requests, and adding up all
270 overstates a session by about 2×. It is a cheap mistake to make and it was made here: the first
version of this section reported 88.5 M and called 95 % of it cache reads before the duplicate records
were noticed. The deduplicated figure is 44.3 M and 97.5 %.

