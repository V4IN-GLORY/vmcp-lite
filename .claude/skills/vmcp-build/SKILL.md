---
name: vmcp-build
description: Building and editing areas of a Roblox place as Luau with VMCP — the whole build lives in one source you write and re-apply, apply_build runs it and hands back the geometry as numbers plus one blockout picture, get_build reads an existing region back as that same kind of source. Use when making, moving, retexturing or restructuring part of a build.
---

# Builds as code

A build is a Luau source that makes it, and the source is the only thing you edit. Never place
parts one call at a time, and never decide where something goes from a picture.

Why: a picture is one angle of one moment. Two of them don't add up to a 3D model in your head —
you end up fixing the second one against the first and drifting. Code holds every part at once, so
"is this wall in the same place as that pillar" is a question you answer by reading two lines and
subtracting, not by squinting. The tools here exist to keep you in that mode.

The loop, one tool call per pass:

```
write the whole build as one source
apply_build { code, root }       -> runs it, measures it, lists what's wrong, draws it
edit the source from the numbers
apply_build again                 -> only what changed moves
```

## The source

`apply_build` runs the shape `get_build` produces: a chunk ending in `return function(root)`.
Everything inside is yours. Write it like build code, not like a dump:

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

local function box(parent, name, size, cframe, props)
	local part = ensure(parent, name, "Part")
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	for key, value in props or {} do part[key] = value end
	return part
end

return function(root)
	-- One set of numbers the rest derives from. Change the room here, not in twelve places.
	local W, D, H, T = 40, 30, 12, 1       -- width, depth, height, wall thickness
	local floorTop = 0

	local shell = ensure(root, "Shell", "Model")
	box(shell, "Floor", Vector3.new(W, T, D), CFrame.new(0, floorTop - T / 2, 0), { Material = Enum.Material.Concrete })

	-- Walls sit on the floor and meet at the corners by construction: their edges are computed
	-- from W, D and T, so they can't overlap or leave a gap unless the arithmetic is wrong.
	local wallY = floorTop + H / 2
	box(shell, "North", Vector3.new(W, H, T), CFrame.new(0, wallY, -D / 2 + T / 2))
	box(shell, "South", Vector3.new(W, H, T), CFrame.new(0, wallY,  D / 2 - T / 2))
	box(shell, "West",  Vector3.new(T, H, D - 2 * T), CFrame.new(-W / 2 + T / 2, wallY, 0))
	box(shell, "East",  Vector3.new(T, H, D - 2 * T), CFrame.new( W / 2 - T / 2, wallY, 0))

	local props = ensure(root, "Props", "Model")
	for i = 1, 4 do
		box(props, `Crate{i}`, Vector3.new(4, 4, 4), CFrame.new(-12 + i * 6, floorTop + 2, 8), { Material = Enum.Material.WoodPlanks })
	end
	return root
end
```

What makes that source good, and what to hold yourself to:

- **Derive positions, don't type them.** A part's position is `floorTop + size.Y / 2`, a wall's
  edge is `W / 2 - T / 2`. Every literal you type is a place two parts can disagree. When the
  problem list says something is floating or sunk in, the fix is nearly always a derivation that
  was typed as a number.
- **Name everything, and keep the names.** `ensure` updates by name, so re-applying moves only the
  lines you changed. Rename a part and the old one stays behind — pass `clear = true` on that pass.
- **Group into Models by what they are** — `Shell`, `Props`, `Stairs` — because the report
  measures each top-level group and you want those measurements to mean something.
- **Loops for repetition.** Four crates is a `for`, not four blocks. Fence posts, pillars,
  stair steps: compute the step from the count and the span, and the last one lands exactly on the
  far edge.
- **Helpers at the top, geometry at the bottom.** `box`, `wedge`, `cylinder` — a few lines each.
  The `return function(root)` body should read like a description of the place.
- **Wedges**: `WedgePart` is full height at its -Z face and slopes to nothing at +Z. Rotate with
  `CFrame.Angles` about Y in multiples of `math.pi / 2` to point it. Cylinders lie along X.
- **`ensure` a class change destroys and remakes** — that one is not an update.

Only properties that differ from a fresh instance need setting; `Anchored = true` on every part
because the default is false.

## Reading the result

`apply_build` answers in this order, and you should read it in this order:

```
applied: 14 instance(s) under Workspace.Arena, 12 of them parts
bounds: 40x13x30 spanning x -20..20, y -1..12, z -15..15
groups (direct children of the root):
  Shell  5 parts, 40x13x30 spanning x -20..20, y -1..12, z -15..15
  Props  4 parts, 22x4x4 spanning x -8..14, y 0..4, z 6..10

2 thing(s) worth a look:
  Props.Crate3 -- overlapping: sunk about 2.00 studs into Workspace.Arena.Props.Crate2 along X
  Shell.East -- floating: 0.50 studs above Workspace.Arena.Shell.Floor

legend (the number in the picture):
  #1 Shell.Floor  40x1x30 at (0, -0.5, 0)
  ...
[wrote the image to .../images/arena.png]
<the picture>
```

**Bounds and groups** are the 3D identity of the build. Check them against what you meant: a
`Props` group spanning `y 0..4` on a floor whose top is 0 is right; one spanning `y 2..6` is two
studs high and you can see it without the picture. A group wider than the shell is poking through
a wall.

**Problems** are the fix list, and each one carries the number to fix with:

| kind | what it means | the fix |
|---|---|---|
| overlapping | sunk `d` studs into X along axis A | move or shrink by `d` on A — usually a typed position that should have been derived |
| floating | `g` studs above X, or nothing under it | lower by `g`, or it's meant to hang and that's fine |
| off axis | rotated under 5 degrees off square | a rotation computed from a near-miss, or a `CFrame.Angles` in degrees instead of radians |
| duplicate | same name, size, position twice | the loop ran twice or two `ensure` calls share a name under different parents |
| paper thin | a dimension under 0.1 | a size computed to nothing — check the subtraction |
| stranded | 250+ studs from the rest | a coordinate off by a factor, or a `*` that should be `+` |

Flush contact is not an overlap: parts sharing a face are fine. Only parts touching nothing at all
get the floating check, so walls against walls don't cry wolf.

**The picture** is for what numbers can't say: does the layout read, are the proportions right,
is that shape what you pictured. It's an orthographic blockout at one scale across every panel —
flat shading, a dark line on every edge, a badge number on each part matching the legend. Meshes
and unions draw as their bounding box. Lights, decals and particles don't draw at all.

Look at it, note what's off in words ("the crates are too small for the room", "the stairs don't
reach the ledge"), then go back to the source and change the derivation. Don't read a coordinate
off the picture — you have the legend for that.

Default is one `iso` view. Add `"top"` when the question is footprint, `"front"` when it's height.
Don't ask for many views by habit; more panels is more to reconcile, and the numbers already agree
with themselves.

## Passes

First pass: the whole build, blocked out — every group, rough sizes, no detail. Get the bounds and
the problem list clean before adding anything. A shell that's right is cheap to detail and a shell
that's wrong makes every detail wrong.

Later passes: edit the source, re-apply. Because `ensure` updates by name, a pass that changes one
group's numbers moves only that group. Keep the full source in your working memory across passes;
it's the build.

Stop when the problem list is empty or every remaining line is something you meant, and the
picture reads. Don't chase the picture pixel by pixel — if a thing looks off but the numbers say
it's where you put it, the question is whether you put it in the right place, and that's a source
edit.

## Reading a build that already exists

`get_build` returns a region as this same kind of source:

```
get_build { root = "Workspace.Arena", depth = 4 }
```

It's a dump, one line per non-default property, `n1`, `n2` locals — readable but not derived.
For a small edit, change the lines and `apply_build` it back. For a real restructure, read it for
the sizes and positions, then write a derived source of your own and apply that with
`clear = true`.

`render_build` draws and measures a region without applying anything — same report, same picture,
for looking at what's there before you touch it:

```
render_build { root = "Workspace.Arena", views = ["iso", "top"] }
```

`vmcp.Build.Problems(root)` and `vmcp.Build.Report(root, parts, badges, problems)` are the same
checks from a `run_luau` snippet.

## Copying a region

The source is `function(root)`, so applying it elsewhere copies it:

```
apply_build { code = <the same source>, root = "Workspace.Arena2" }
```

A missing last segment is created as a Model.

## What it covers

Parts and their geometry, material and appearance; meshes; decals and textures; attachments;
lights; particle emitters and beams; surface appearances; GUI objects, text and image labels, and
the common UI modifiers. Attributes and tags on everything.

The dump's property list is curated — there's no way to enumerate properties from Luau — so a
class property not on it is silently absent from `get_build`. If a region round-trips wrong,
that's the first thing to check. Your own source has no such limit; set whatever you like.

## Limits

`get_build`: `depth` defaults to 12, `maxNodes` to 800. `apply_build` / `render_build` measure up
to 1500 parts and say so if they stop early. Badges go off above 40 parts unless forced with
`badges`. Prefer a narrow `root` over a big cap.
