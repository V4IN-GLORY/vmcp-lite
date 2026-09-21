# Materials, palette and accents

Load in phase 1 when writing the palette table, and again before the detail passes that texture walls.

## Palette and placement

A table of 5–8 roles, each with a material, a colour, and a
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

## Variety, accents and the ground

**Around the building is part of the build.** A ruin on a billiard-table lawn looks placed, not
found. Give the ground a `Grounds` group: shallow earth banks against the walls and corners
(bedded 1-stud boxes, a few degrees of yaw), moss tufts clustered at the wall feet, stones shed
from the walls within a few studs of them, a dressed block or two lying where a parapet fell.
Twenty to forty parts, seeded, never a grid.

**Material variety is by role, not by part.** One wall material over a 60-stud nave is a
blockout with a texture. Vary at three levels and stop there:

- *Two or three wall variants*, assigned per structural class: piers and quoins in the dressed
  variant (Limestone, lighter), infill panels in the rubble variant (Cobblestone or Slate, 8–12
  RGB darker), plinth in the darkest. The eye reads the construction — dressed stone where the
  load is — before it reads the texture.
- *Per-part colour jitter of ±4–6 RGB* on the infill role only (seeded, from `rng`), never on
  trim, never on anything with a straight run (bands, copings, floor slabs) — those show the
  seam.
- *Replaced stones*: 2–4 boxes per wall panel in a contrasting variant, flush with the panel
  minus `R`, named, seeded. Reads as repair and weathering. Not on piers.

Wood gets two shades (structural dark, furniture 15 RGB lighter); iron one; floor slabs 2 tones
alternating by `(ix + iz) % 2` with a 0.02 height stagger so no two share a plane.

**Accent pieces are a fixed vocabulary, placed by rule.** Add from this list, in this order,
until the walls stop looking like slabs — then stop:

1. Plinth band around every exterior wall (proud `PROUD`, 2–2.5 tall, darkest variant).
2. Pier bases (one slab 0.4 tall, 0.2 wider each side) and caps (impost, above). Every pier.
3. Quoins on every external corner: alternating long/short trim boxes, `PROUD` proud, 1.2 tall.
4. String course at the springing line on the outside, at the aisle-eave line inside.
5. Corbels under every wall plate and under any beam that meets a wall: 0.5 cube, trim, `PROUD`
   under the plate, one per rafter.
6. Coping on every wall top that's exposed: 0.4 tall, `PROUD` each side, ruin-broken where the
   top is broken.
7. Iron only where iron does a job: hinges and a strap on doors, a bracket under every lantern,
   tie bars across the nave at the wall plate (0.15 posts) — 3–6 pieces per building total.

Each of these is a helper called from the wall data, not hand-placed. Anything not on the list
(shields, statues, gargoyles) is a prop and is capped at three per building.

**Debug flags print in QA.** `INSPECT`, `SCALE_REF`, and any cutaway or transparency toggle must
default `false` in the file and be printed on the QA line (`flags INSPECT=false SCALE_REF=false`).
A stale flag then shows up in Output, not in the user's screenshot.

**Ruin comes from one table.** Wall tops per bay, which roof runs survive, which rafters, which
windows keep glass: all read from one `ruin` table keyed by bay. Never hand-place a broken edge.
Jitter the broken ends of paired planes (the two roof slopes, the two aisle walls) by ±1 so they
don't stop on one line.

**Floating and buried props.** Small props go on with `placeOn` and `size.Y = 0` (they sit, not
hover). Pews, seats, chests overlap their feet 0.05 into the floor rather than sitting on it
exactly. Nothing is placed by typing a Y.

