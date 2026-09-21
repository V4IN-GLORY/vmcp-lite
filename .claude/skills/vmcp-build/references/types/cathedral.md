# Cathedral / church / chapel

When this applies: churches, chapels, abbeys, cathedrals, crypts, and gothic ruins of any of
them. Anything with a nave, an aisle, a pointed arch or a bell.
Doesn't cover: castles and keeps (crenellations, curtain walls — different type), generic
"medieval building" (core is enough).

Written from a 1 500-part gothic ruin. The arch, gable, glass and material rules in
`geometry.md` and `materials.md` were all learned on it, so those files are the other half of
this one — load them.

## Masses and numbers

- **Nave**: the long box. Width : height ≈ 1 : 1.5–2 inside (a 16-wide nave is 24–32 tall to
  the ridge). Length is bays × bay width; 5–7 bays, bay width 8–12.
- **Aisles**: one each side, half to two-thirds the nave's height (10–14 tall), 6–8 wide,
  separated from the nave by an arcade of piers, one per bay.
- **Tower**: at the west end or over the crossing, footprint ≈ nave width square, height 2–3×
  the nave ridge. Tapers in the top stage or carries a spire — never the same section all the
  way up.
- **Porch**: south side, 8×8×6 to 10×10×8, its ridge below the aisle eave.
- **Chancel / apse**: east end, narrower and lower than the nave (0.7× both), square or a
  polygon of 5–7 flat faces (never a cylinder).
- Base numbers that derived cleanly: `W = 16, D = bays * 10, H = 28, T = 3, aisleW = 7,
  aisleH = 12, pitch = 50°`. Wall thickness 3–4 — a cathedral wall at 1 stud reads as a shed.

Reads from the front: tower + gable + great west door + rose or lancet window over it.
Reads from above: the cross plan and the stepped roof (aisle roofs below nave roof).

## Access

- West door: 8 wide × 12–14 tall, pointed, two leaves. Side doors in the porch and chancel
  6 × 8.
- Nave to aisle: the arcade openings *are* the access — each bay's arch, clear width ≥ 5 at
  the threshold.
- Nave to chancel: the chancel arch, full width of the chancel.
- Tower: door from the nave at floor level; a stair (rise ≤ 1, ≥ 1.5 tread) up the inside
  of one wall to the ringing floor; the bell chamber above it reachable or explicitly sealed.
- Headroom under every aisle vault ≥ 8; under the tower floor ≥ 10.

## Palette

```lua
local P = {
	wall    = { Enum.Material.Limestone,   Color3.fromRGB(122, 116, 106) }, -- dressed wall planes: piers, quoins, jambs, tower
	infill  = { Enum.Material.Cobblestone, Color3.fromRGB(104, 100, 92) },  -- rubble panels between piers (±5 RGB jitter per part)
	plinth  = { Enum.Material.Slate,       Color3.fromRGB(70, 68, 64) },    -- lowest 2.5 studs of every exterior wall
	trim    = { Enum.Material.Sandstone,   Color3.fromRGB(158, 148, 130) }, -- arch rings, string courses, sills, copings, impost bands
	roof    = { Enum.Material.Slate,       Color3.fromRGB(56, 58, 64) },    -- roof slabs and ridge only
	beam    = { Enum.Material.Wood,        Color3.fromRGB(58, 42, 30) },    -- rafters, wall plates, tie bars' wood, door leaves
	floor   = { Enum.Material.Marble,      Color3.fromRGB(98, 96, 92) },    -- nave flags, two tones alternating by (ix + iz) % 2
	warm    = { Enum.Material.Wood,        Color3.fromRGB(96, 66, 44) },    -- pews, altar rail, lectern -- the room's warm accent
	iron    = { Enum.Material.Metal,       Color3.fromRGB(38, 36, 36) },    -- hinges, straps, lantern brackets, tie bars
	glass   = { Enum.Material.Glass,       Color3.fromRGB(120, 140, 170) }, -- window panes, Transparency 0.5
}
```

`wall` / `infill` / `plinth` carried the build (dressed where the load is, rubble between);
`trim` is what makes it gothic; `warm` keeps the interior from reading as a cave.

## Details that make it read

In the order they earned their place:

1. **Arch rings on every opening** — `arch()` from `geometry.md`, pointed (two arcs centred on
   the opposite foot, 7–11 voussoirs a side, keystone taller and prouder). Every arcade bay,
   every window, both doors, the chancel arch.
2. **Plinth band + string course at the springing line**, outside and in. Two horizontal lines
   turn a slab into a wall.
3. **Buttresses** on every exterior pier line: a box `T` wide, `1.5T` deep at the base, stepped
   back once at the string course, capped with a sloped coping box (rotated, not a wedge).
4. **Quoins** on every external corner, alternating long/short, `PROUD` proud.
5. **Windows with glass to the head** — one pane sill-to-springing, mullion + transom, 3–4
   stacked slabs following the ring's inner curve up to the apex (`geometry.md`, "Glass fills
   the whole opening").
6. **Gable at each end**: thin courses filling the triangle, a raking coping up each slope in
   `trim`, a finial at the apex.
7. **Roof structure visible from inside**: wall plates on corbels, rafters per bay in `beam`,
   collar beams or tie bars across the nave at the plate.
8. **Floor flags** two-tone with the 0.02 stagger; a border band in `trim` along the walls.
9. **Pews** (hero-adjacent: 6–10 parts each, `warm`), an altar (hero: 20+ parts, lighter stone,
   cloth, candle rail), a lectern.
10. **Candles and lanterns**: Neon flame 0.2 + `PointLight` warm, Range 8; a `SpotLight`
    inward from the big east window.
11. **Grounds**: earth banks at the wall feet, moss tufts, shed stones within 3 studs of the
    walls (20–40 seeded parts).

For a **ruin**: one `ruin` table keyed by bay — wall top height, which roof runs survive, which
rafters, which windows keep glass. Jitter paired planes' broken ends by ±1. Fallen dressed blocks
in `Grounds` where the parapet went.

## Failure modes seen on this type

- **Valley instead of a ridge.** Roof slopes written `CFrame.Angles(0, 0, side * pitch)` where
  `-side * pitch` was needed. Every number in the report was right. Fix: assert in the build's
  QA that each slope's long axis climbs toward the centre line; render the roof from a low
  angle at each gable end.
- **Arch ring inside the curve.** Voussoirs placed at `r - thick/2`; the opening shrank by
  `thick` while spandrels and glass heads were computed for the full arch — open sky at the
  corners from inside. Fix: compute `r`, `thick`, `r + thick` once and hand them down.
- **V-notches between voussoirs.** `PROUD` overlap isn't enough past ~6° per step. Overlap =
  `thick * tan(step/2) + 0.1`.
- **Stepped gable.** Courses stepped to the pitch read as a ziggurat from 30 studs. The raking
  coping over them fixes it.
- **Impost shelves.** Capitals overhanging the pier by more than ~0.15 of its width read as
  bolted-on shelves. Keep projection to `PROUD`.
- **Cave interior.** Six materials at the same grey. The bland test (three roles visible from
  one spot, one warm) is what caught it; `warm` on pews and doors fixed it.
- **Tie bars and rafters lying down.** The two-point helper already orients along a→b; adding a
  quarter turn put them horizontal at chest height. Rotate a thing once.

## Source snippets

```lua
-- Buttress against a wall at `frame` (X along the wall, Z out), stepped once at `stringY`.
local function buttress(parent, name, frame, T, H, stringY)
	local base = box(parent, name .. "Base", Vector3.new(T, stringY, 1.5 * T), frame * CFrame.new(0, stringY / 2, 0.75 * T + PROUD), P.wall)
	local upper = box(parent, name .. "Upper", Vector3.new(T, H * 0.8 - stringY, T), frame * CFrame.new(0, stringY + (H * 0.8 - stringY) / 2, 0.5 * T + PROUD), P.wall)
	-- sloped cap: a box rotated to the pitch, not a wedge
	box(parent, name .. "Cap", Vector3.new(T + 0.4, 0.4, 1.5 * T + 0.4), frame * CFrame.new(0, stringY + 0.2, 0.75 * T + PROUD) * CFrame.Angles(math.rad(-35), 0, 0), P.trim)
	box(parent, name .. "Top", Vector3.new(T + 0.4, 0.4, T + 0.4), frame * CFrame.new(0, H * 0.8 + 0.2, 0.5 * T + PROUD) * CFrame.Angles(math.rad(-35), 0, 0), P.trim)
	return base, upper
end
```
