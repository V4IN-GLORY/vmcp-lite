# Slop game (stylised low-poly map)

When this applies: the fast, bright, flat-colour look of obbies, tycoons, simulators, tower
defense lobbies — "make me a spawn area", "a lobby with shops", "an obby with 10 stages",
"a starter zone". The user wants it playable and readable, not realistic.
Doesn't cover: anything the user calls realistic, detailed, atmospheric, or names a real
building type — those want the core rules and a real type file.

**Starter file.** Written from the core rules and the conventions these games share, not yet
from an audited build. Replace sections with measured numbers the first time a slop-game build
goes through all four phases; keep the structure.

## What changes from the core

The core's material and accent rules are tuned for stone buildings. Here they invert:

- **Flat, not textured.** `SmoothPlastic` on nearly everything; `Neon` for anything that
  glows or marks a goal; `Grass` / `Sand` only on the ground. No Cobblestone, no Limestone, no
  ±RGB jitter — jitter reads as dirt in this style.
- **Colour does the work materials did.** The palette is 6–10 saturated colours, each meaning
  one thing everywhere (ground, path, platform, hazard, goal, shop, wall, accent). Same colour =
  same gameplay meaning. That's the whole readability system.
- **Bigger, fewer parts.** Masses are 2–4× what they'd be in a realistic build. A shop is a
  12×10×10 box with a 6-wide opening and a sign, not a building with trim. Part budget: a lobby
  is 100–300 parts; an obby stage is 5–30.
- **No plinth, no quoins, no string course.** The accent vocabulary is: a coloured band or
  outline around edges, a sign, a Neon strip, a `UIGradient`-free flat billboard. Stop there.
- **The bland test still applies**, as a colour test: from any spot a player stands, at least
  three distinct palette colours in view, one of them the accent.

## Masses and numbers

- **Spawn plaza**: 60–100 square, flat, at `y = 0`, `SpawnLocation` in the middle on a 1-stud
  raised disc or pad (the pad is a `Part` with `Shape = Cylinder` lying along Y — rotate it —
  or a box; never a `WedgePart`).
- **Paths**: 8–12 wide, 0.5 tall, sitting 0.25 into the ground, in the path colour. They
  connect spawn to every zone; a zone without a path isn't found.
- **Zones / shops / stations**: 12–20 square footprints around the plaza at 30–50 from spawn,
  fronts facing the plaza. Openings 8 wide × 10 tall — bigger than the character table says,
  because players run through them at speed and on mobile.
- **Obby stages**: platforms 6–8 wide, gaps 6–8 (a default jump clears ~7 flat; ~10 with a
  running start — keep ≤ 8 unless the stage is meant to be hard), rise ≤ 4 per platform.
  Checkpoints every 5–10 platforms on a 8×1×8 pad in the goal colour.
- **Walls / boundaries**: invisible (`Transparency = 1`, `CanCollide = true`) at the map edge,
  10+ tall, in a `Bounds` group so the report doesn't flag them.
- Base numbers: `plaza = 80, pathW = 10, zoneW = 16, zoneH = 12, gap = 7, platW = 7`.

## Access

Everything is walkable by construction — this style has no interiors that aren't open boxes.
What still needs checking: every zone opening faces a path; every obby platform is reachable
from the previous one (gap ≤ 8 at platform height, rise ≤ 4); nothing stands on a path.

## Palette

```lua
local P = {
	ground  = { Enum.Material.Grass,         Color3.fromRGB(96, 178, 84) },   -- the plaza and any open ground
	path    = { Enum.Material.SmoothPlastic, Color3.fromRGB(226, 214, 176) }, -- every walkway; 0.25 into the ground
	wall    = { Enum.Material.SmoothPlastic, Color3.fromRGB(240, 240, 236) }, -- zone/shop boxes
	roof    = { Enum.Material.SmoothPlastic, Color3.fromRGB(226, 84, 74) },   -- zone roofs; one colour per zone kind is fine
	trim    = { Enum.Material.SmoothPlastic, Color3.fromRGB(58, 58, 66) },    -- outlines, sign posts, edge bands
	platform= { Enum.Material.SmoothPlastic, Color3.fromRGB(78, 140, 232) },  -- obby platforms
	hazard  = { Enum.Material.Neon,          Color3.fromRGB(240, 60, 60) },   -- kill bricks, lava; always Neon
	goal    = { Enum.Material.Neon,          Color3.fromRGB(90, 230, 120) },  -- checkpoints, spawn pad, finish
	accent  = { Enum.Material.Neon,          Color3.fromRGB(250, 200, 60) },  -- signs, coins, shop markers -- the warm one
}
```

## Details that make it read

1. **A band in `trim` around the top edge of every zone box** (0.4 tall, `PROUD` proud). It's
   the only trim and it's what makes a box look drawn instead of dropped.
2. **A sign on every zone front**: a `trim` post + a flat `accent` board with a `SurfaceGui`
   `TextLabel`, at 8–10 up so it reads over players' heads.
3. **Neon underglow**: a `goal`-colour slab 0.2 tall under the spawn pad and each checkpoint,
   0.1 wider each side.
4. **Repeated props at plaza scale**: 3–6 of one tree helper (trunk cylinder + 2–3 stacked
   boxes in two greens, 10–16 tall), a bench helper, a lamp post with a `PointLight`. Cluster
   them at plaza corners, not in a ring.
5. **Hazards are Neon and flat** (`hazard`, 0.5 tall) with `CanCollide = false` — the touch is
   what kills, and a raised lava block trips the player instead.

## Failure modes seen on this type

Fill in from the first audited build. Expected from the core rules:

- Openings at character-table size (5 × 8) feel cramped at run speed on this style — use 8 × 10.
- Obby gaps typed from a picture instead of derived from `gap` — one unjumpable stage. Derive
  every platform's position from the previous one's edge + `gap`.
- Textured materials from the core palette creeping in on walls. Everything flat except
  ground.

## Source snippets

```lua
-- Obby run: platforms from `start`, each `gap` past the last one's far edge, rising `rise` per step.
local function obbyRun(parent, start: Vector3, count: number, platW: number, gap: number, rise: number)
	local x = start.X
	for i = 1, count do
		local pos = Vector3.new(x + platW / 2, start.Y + (i - 1) * rise, start.Z)
		box(parent, `Plat{i}`, Vector3.new(platW, 1, platW), CFrame.new(pos), P.platform)
		x += platW + gap
	end
	return x
end
```
