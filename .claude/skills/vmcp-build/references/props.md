# Props and hero props

Load before the interior/exterior prop passes and before any hero prop pass.

**Floating and buried props.** Small props go on with `placeOn` and `size.Y = 0` (they sit, not
hover). Pews, seats, chests overlap their feet 0.05 into the floor rather than sitting on it
exactly. Nothing is placed by typing a Y.


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

