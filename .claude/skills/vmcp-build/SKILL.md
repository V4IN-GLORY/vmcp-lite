---
name: vmcp-build
description: Building and editing areas of a Roblox place as Luau with VMCP — the whole build lives in one source you write and re-apply, apply_build runs it and hands back the geometry as numbers plus a blockout picture, render_build draws any region from any angle without applying, get_build reads an existing region back as source. Use when making, moving, retexturing or restructuring part of a build.
---

# Builds as code

A build is a Luau source that makes it, and the source is the only thing you edit. Never place
parts one call at a time, and never decide where something goes from a picture. Code holds every
part at once; a picture is one angle of one moment, and it's for *seeing* whether the numbers made
the thing you meant.

**HARD RULE: DO NOT TOUCH `game.Lighting`.** No properties, no new children, no deleting what's
there — not from build source, not from `run_luau`, not "to make the picture better". Only
exception: the user names Lighting and asks. Lights, beams and emitters *inside* the build root
are fine.

## This file is the core; the rest is a library

This file has what every build needs. Everything else lives in `references/` and is loaded when
the step that needs it comes up — read `references/INDEX.md` once at the start of a build and
pull files from it as you go. Don't load the whole library up front; a 1 500-part build spent
97 % of its tokens re-reading context it already had.

`references/types/` holds per-build-type tips (cathedral, slop game, …) written from real builds.
**At the end of phase 1, name the build's type.** If a matching file exists, load it before the
blockout; if it doesn't, build from the core and, when the build is done, offer to turn what you
learned into a new type file — `references/types/README.md` has the template and how to submit
it as a PR.

## The pipeline

Four phases, in order, no skipping. "Write down" means a line in your reply, so the user can see
the pass happened.

```
1. DESIGN    write the design block (masses, structure, access, palette+placement, variety)
2. BLOCKOUT  apply_build the masses  -> bounds match, problems empty, iso silhouette matches
3. DETAIL    per group: apply_build -> render_build aimed at the group -> say what's off -> fix -> re-render
4. INSPECT   photo sweep + cutaway + access walk of the whole build against the checklist
```

Every `apply_build` / `render_build` ends the same way: read the numbers, look at the picture,
write one or two lines of what it showed. Never read a coordinate off the picture — the legend
and the group/problem lines have it.

**Rendering is mandatory, every time, whether or not the user asked.** Minimum per build: one
`apply_build`, at least two `render_build` calls at different locations/angles, and the phase-4
checklist written out. A render only counts if the thing it's meant to prove is legible in it —
name the property, say how the panel shows it, take another panel if it can't.

**Run the phases in fresh contexts.** State lives in the source file on disk; each phase reads
the ranges it needs, edits, applies, reports a few lines. `references/context-budget.md` has the
numbers and the rules.

**Accessibility is a requirement.** Unless the user says a space is sealed, every interior a
player could see is reachable on foot from outside and from every other interior. Designed in
phase 1, derived in the source, verified in phase 4.

### 1. Design — a comment block at the top of the source, in this order

1. **Masses.** The 3–5 volumes that make the silhouette, with sizes and proportions. What reads
   from the front and from above.
2. **Structure.** How it stands up, then the base numbers everything derives from: `W, D, H, T`,
   bay count, roof pitch, floor heights. Every other dimension is arithmetic on those.
3. **Access.** Every interior space and how a player gets in and between them; each opening's
   wall, width, height. Doorway 4–6 wide × 7–8 tall, corridor ≥ 4, step rise ≤ 1, headroom ≥ 7.
   A sealed space is named here with why.
4. **Palette and placement.** A table `P` of 5–8 roles, each `{ material, colour }` with a comment
   naming exactly which surfaces get it. Helpers take a role (`P.wall`), never a raw material.
   Load `references/materials.md` for the placement rules and the bland test.
5. **Variety, lightly.** Shared helpers with seeded jitter in a normal range. Damage is data
   (`tops = {26, 26, 20, 15}` per bay), not a second code path.
6. **Type.** One line: `-- type: cathedral` (or `none`). Load `references/types/<type>.md` if it
   exists.

### 2. Blockout

Helpers and `return function(root)` with every top-level group from the masses list, right
palette on the big planes, no openings, no props. `apply_build`, then check in this order:
`bounds` and each `groups` line equal the design numbers; the problem list is empty; the iso
silhouette matches the masses. Write "blockout: bounds X, groups match, 0 problems, iso shows
<what>". No detail until that line is true.

### 3. Detail — one group per pass, render after every pass

Order: shell openings → roof → interior floors and stairs → interior props → exterior props →
hero props → effects. Keep the source in a file and apply with
`apply_build { file = "<absolute path>" }`; each pass is an `Edit` plus the apply, never a
re-send of the whole file.

Each pass:

1. Edit the source for that one group. Every opening comes from the access list; every surface
   pulls a role from `P`.
2. `apply_build`. Every new problem line is fixed or written down as intentional with the reason.
3. `render_build` narrowed to that group — several panels, covering 100 % of the group: every
   opening, every join to a neighbour, every face, every corner, each from two angles that don't
   share an axis. 9 panels per call is the cap; a big group is two or three calls. Write the
   coverage line ("Shell: door (2 angles), 4 windows (2 each), roof (top + 2 low), all faces").
4. Write what's wrong in words. Find the derivation that produced it — nearly always a typed
   number or a wrong-way rotation. Edit it.
5. Re-apply, re-render the same spots from angles you haven't used. When the report names a part,
   render `{ at = <that part>, radius = 6, clip = true }` from two angles, not the whole build.
6. Repeat until the group's problems are empty or all intentional. Write "group <X> done: <n>
   problems, all intentional: <list>".

`references/geometry.md` before the shell and roof passes, `references/props.md` before the prop
passes, `references/lighting.md` before effects.

### 4. Inspect

Load `references/inspect.md` and do all of it: the whole-build sweep, the cutaway (`INSPECT` flag
in the source, back to `false` before you finish), and the checklist with a line per item. Done
when every item has its line and every panel reads.

## The source

`apply_build` runs a chunk ending in `return function(root)` — the shape `get_build` produces.

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
	return root
end
```

Hold yourself to:

- **Derive, don't type.** Position is `floorTop + size.Y / 2`; a wall edge is `W / 2 - T / 2`.
  "Floating" and "sunk" in the report are almost always a typed number.
- **Size by what it fits into.** A door leaf is `openingWidth / leaves`, a lid is the crate top.
- **Name everything, keep the names.** `ensure` updates by name, so re-applying moves only what
  changed. Renamed a part? Pass `clear = true` that pass.
- **Group into Models by what they are** — the report measures each top-level group.
- **Loops for repetition**; step from count and span so the last one lands on the edge.
- **Local frames for anything rotated**: helpers take a `frame` and place pieces as
  `frame * CFrame.new(x, y, z)`. Two-point helpers (`CFrame.lookAt`) for beams, chains, roots.
- **Seed randomness** (`Random.new(1906)`) so reruns are identical and reports compare.
- **Boxes by default.** Cylinders lie along X. A wedge is full height at -Z, nothing at +Z.
- **Pieces that meet overlap by 0.05–0.1**; anything layered on a surface sits `PROUD = 0.2`
  proud, never flush. Four walls are two long and two short.
- **Debug flags** (`INSPECT`, `SCALE_REF`) default `false` and print on the QA line.
- Only set what differs from a fresh instance; `Anchored = true` always.

## Reading the report

```
applied: 14 instance(s) under Workspace.Arena, 12 of them parts
bounds: 40x13x30 spanning x -20..20, y -1..12, z -15..15
groups (direct children of the root):
  Shell  5 parts, 40x13x30 spanning x -20..20, y -1..12, z -15..15
2 thing(s) worth a look:
  Props.Crate3 -- overlapping: sunk about 2.00 studs into Workspace.Arena.Props.Crate2 along X
  Shell.East -- floating: 0.50 studs above Workspace.Arena.Shell.Floor
legend: #1 Shell.Floor 40x1x30 at (0, -0.5, 0) ...
```

`apply_build` lists only problems new since the last apply of that root; `render_build` lists
everything. Flush contact isn't an overlap. Particle carriers overlap everything by design.

| kind | the fix |
|---|---|
| overlapping, sunk `d` on axis A | move or shrink by `d` — usually a typed position |
| floating `g` above X | lower by `g`, or it hangs on purpose. **Structural + floating = real bug, always.** |
| off axis (< 5°) | degrees where radians were meant |
| duplicate | loop ran twice, or two `ensure` share a name |
| paper thin (< 0.1) | a size subtracted to nothing |
| stranded (250+ studs) | a `*` that should be `+` |

## Tools, in one breath

- `apply_build { root, file | source, clear?, inspect? }` — runs it, measures, draws an iso.
- `render_build { root, views, size?, badges? }` — views are `iso`/`front`/`top`/… or
  `{ yaw, pitch, name }`, targeted with `{ at = "<dotted path>", radius, clip = true }`. Up to
  9 per call. `references/renderer.md` for the full contract.
- `get_build { root, depth }` — existing region back as source. `render_build` first, before
  touching anything that exists.
- **Always pass `root`.** The default is the whole Workspace and it hits the cap on any real place.
- Keep an apply under ~20 KB; never pair a big first apply with `clear`.
- Mechanical coplanar check after every apply (`references/geometry.md`) — the renderer won't
  show Z-fighting, the engine will.

## The six rules

1. Anything whose meaning depends on which way it faces can be exactly wrong while every number in
   the report is right. Assert the direction in the build's own QA; don't eyeball it.
2. A render only counts if the property it's meant to prove is legible in the panel.
3. A floating report on a structural part is a real defect. Never close a build with one unexplained.
4. Learn each helper's built-in orientation and never apply a second turn about the same axis.
5. Always pass `root`, batch applies under ~20 KB, never pair a big first apply with `clear`.
6. Cost is `steps × context size`. Run the loop in fresh contexts with the state on disk.

Each has a worked failure in `references/field-notes.md`. Read it the first time any of them
bites, and before phase 4 on anything over ~300 parts.
