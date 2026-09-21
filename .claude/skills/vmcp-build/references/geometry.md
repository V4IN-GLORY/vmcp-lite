# Geometry rules

Load before the shell, opening and roof passes. Every rule here comes from a real bad build.

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
	local seg = 2 * r * math.sin(step / 2) + thick * math.tan(step / 2) + 0.1   -- chord + the V-notch the outer edge opens, + a hair
	for i = 1, n do
		local a = a0 + (i - 0.5) * step
		local cf = frame * CFrame.new(0, cy, 0) * CFrame.Angles(0, 0, a) * CFrame.new(r + thick / 2, 0, 0)   -- ring OUTSIDE the curve
		box(parent, `{name}{i}`, Vector3.new(thick, seg, depth), cf, P.trim)
	end
end
```

`n = 7–11` for a doorway, more for a big window. The voussoirs sit `thick` deep against the
opening; the wall fill above them (a box from the apex to the wall top plus a box each side
from the springing line up) is rectangular and tucks `PROUD` behind the arch's back face so
the curve is what you see. A keystone is one voussoir made taller and `PROUD` prouder.

Three things the ring gets wrong, in order of how often:

- **Which side of the curve the ring is on.** `r` is the *opening*. The ring's centreline is
  `r + thick/2`, outside it. Put it at `r - thick/2` and the opening shrinks by `thick` while
  every dependent piece (spandrel slabs, glass head slabs, imposts) is still computed for the
  full arch — the corners between ring and fill are open sky. Compute `r`, `thick` and the outer
  radius `r + thick` once and hand them down; nothing re-derives them.
- **Overlap is not `PROUD`.** Two rotated boxes meeting on the curve open a V-notch on the outer
  edge `thick * tan(step/2)` wide per side. `PROUD` (0.2) covers it only for `step ≤ ~6°`. With
  4–5 voussoirs per side (`step` 12–15°) and a 2-stud ring the notch is 0.4–0.5 studs: from inside
  the building every segment end sticks out as a dark sliver over the recessed spandrel. Overlap
  = `thick * tan(step/2) + 0.1`, always. The inner corners then bite into the opening by
  `sqrt(r² + (seg/2)²) - r`; keep that under 0.15 by adding voussoirs, not by shrinking overlap.
- **Pointed arcs centre on the opposite foot** and sweep 120°–180°. The apex is `r·sin(60°)`
  above the springing line; print that against the measured apex the first time and never
  trust the eye for it (an arc centred on its own foot rises *above* the foot and reads as a
  horseshoe).

A proud member shows every one of its corners. A rotated proud part therefore has to be small,
or have its corners inside the silhouette of an un-proud neighbour. Check one arch from *inside*
and at a quarter angle, not just front-on: front-on hides both the notches and the gap.

**Imposts, capitals, string courses: projection is small.** A capital that overhangs the pier by
more than ~0.15 of the pier's width, or a band deeper than `PROUD` past the wall face, reads as a
shelf bolted on, not stone. Impost: `PROUD` proud of each face, 0.1–0.15 into the opening, 0.5–0.7
tall; never longer than the pier plus that. String courses the same depth as the ring so the two
read as one system. If a band has to run across an opening's ring, stop it `0.1` short of the ring
instead of crossing it.

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

**Glass fills the whole opening.** A pane that stops at the springing line, or a rectangle in a
pointed window, reads as a window someone forgot to finish. One pane from the sill band to the
springing, then 3-4 stacked slabs up the head whose width follows the ring's *inner* curve
(measured 40-50% up each slab, so the slab's top corners bury themselves in the ring instead of
leaving a sliver of sky). Stack the slab depths 0.05 apart so no two share a face. A mullion and a
transom at the springing are what make it a window and not a hole. Ruin = whole windows left out
(`glass = false`), not half a pane.

**Gables are triangles, not staircases.** Courses stepped to the pitch read as a ziggurat from
30 studs away. Fill the triangle with thin courses (rise ~1) and run a raking coping in the trim
role up each slope over them (`CFrame.Angles(0, 0, -side * pitch)`, 0.5 proud of the wall, half a
stud past the eave); the coping hides every step and the silhouette is one clean line. A small
finial on the apex reads as the building's own, not the roof's.

**Cutaway flags go back off before the user looks.** `INSPECT = true` is a render tool. Every apply
that ships to the place is done with it `false`; a roof left at 0.75 transparency is the first thing
the user sees in Studio.

**Coplanar offenders, by class.** These pairs came back coplanar on every build until the offset
was designed in; put the offset in the helper, not the fix: sill band vs recessed fill (band is
proud, fill is recessed R); gable courses vs coping; glass vs mullion vs transom (stack depths
0.05 apart); lantern post vs cap; path slabs (each its own top plane, 0.02 stagger); shaft bases
on plinths; pilasters on tombs; pier caps vs impost band. The mechanical check (E = 0.02, key
`pos, size, XVector` for duplicates) is the gate; a render is not.

**When targeted render panels are ignored** (`at`/`radius`/`clip`/`view` have no effect, every
panel is the whole build), the VMCP server is stale — an old process owns the plugin. Don't spend
turns tuning panel params. Workaround: `run_luau` clones every part within `radius` of the point
into `Workspace.ClipX.Parts`, render that root, destroy `ClipX` after. Tell the user the server
needs a restart.

