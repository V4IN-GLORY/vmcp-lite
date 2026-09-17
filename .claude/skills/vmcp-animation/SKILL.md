---
name: vmcp-animation
description: Building Roblox animations with VMCP — the render_anim tool takes per-joint tracks, draws the rig posed at each keyframe as a filmstrip and returns a playable id with no upload, plus the Rig and Anim library underneath it and reading existing animations back as tracks. Use when asked to make, edit or inspect an animation.
---

# Animation as code

## The loop: `render_anim`

One tool call writes the animation, draws it and hands back a playable id. Send tracks, get a
filmstrip: the rig posed at every keyframe, left to right, front and right views. Look, fix the
numbers, send again. No Luau snippet, no playtest, nothing uploaded.

```
render_anim {
  tracks = {
    RightUpperArm = [ { time = 0, angles = [0,0,0] }, { time = 0.25, angles = [0,0,-110], easing = "Cubic/Out" }, { time = 0.6, angles = [0,0,15] } ],
    RightLowerArm = [ { time = 0.25, angles = [-20,0,0] }, { time = 0.6, angles = [0,0,0] } ]
  }
}
-> Workspace.VMCPRig: 3 frame(s) left to right: t=0  t=0.25  t=0.6
   id = rbxasset://...  length = 0.6  joints = RightUpperArm, RightLowerArm
   [picture]
```

- No `rig` given: it spawns `Workspace.VMCPRig`, an R15 dummy in classic colours (yellow head
  and arms, blue torso, green legs) and reuses it. Pass `rig = "Workspace.Enemy"` for anything else.
- `times = [0, 0.1, 0.2, ...]` to sample between keys and check the in-betweens; `views` for
  other angles; `size` down to 384 when a quick check is enough.
- `animationId = "rbxassetid://..."` instead of tracks draws an existing animation and prints
  its tracks as editable angles, so "make the walk bouncier" is read, edit, re-render.
- Keep the key count small. Three to five keys per moving joint says most things; the engine
  interpolates the rest. More frames cost more picture and rarely more information.

Play the id back with `run_luau` when it looks right (see Previewing). Everything below is the
library the tool is built on, for when you need it from a snippet.

## Library

Reached from a `run_luau` snippet through `vmcp.Rig` and `vmcp.Anim`. Nothing is uploaded: the
compiler registers a temporary id you can play immediately.

## The trap this library exists for

A `Pose` is **named after a BasePart**, but its CFrame drives the `Motor6D` joining that part to
its **parent pose's** part. A Pose named `LowerTorso` drives the motor named `Root`. Write a pose
tree that looks sensible but doesn't mirror the rig's actual Motor6D graph and the wrong joints
animate, with no error.

So never hand-build a pose tree. `Rig.Build` reads the graph the model really has:

```lua
local rig, problem = vmcp.Rig.Build(workspace.Dummy)
if not rig then return problem end
return vmcp.Rig.Describe(rig)   -- every joint, parents before children
```

Nothing in it is hardcoded to a skeleton, so R6, R15 and custom rigs all work.

## Authoring

Tracks are per joint over time, which is how animation is thought about. The compiler turns that
into the engine's format, which is "at t=0.3, here is the entire body".

```lua
local tracks = {
    RightUpperArm = {
        { time = 0,    angles = { 0, 0, 0 } },
        { time = 0.25, angles = { 0, 0, -110 }, easing = "Cubic/Out" },
        { time = 0.6,  angles = { 0, 0, 15 },   easing = "Quad/InOut" },
    },
    RightLowerArm = {
        { time = 0.25, angles = { -20, 0, 0 } },
        { time = 0.6,  angles = { 0, 0, 0 } },
    },
}

local built, problem = vmcp.Anim.Compile(workspace.Dummy, tracks, { loop = false, priority = "Action" })
if not built then return problem end
return built   -- { id = "rbxasset://...", length = 0.6, joints = {...}, keyframes = 3 }
```

`angles` is degrees, XYZ. Pass `cframe = CFrame.new(...)` instead for anything angles can't say.

**Easing is written on the key it leaves from**, because `Pose.EasingStyle` describes how to reach
the *next* keyframe. The last key's easing is never used. Format is `"Style/Direction"`, e.g.
`"Cubic/Out"`, `"Quad/InOut"`, `"Linear"`.

A joint with no key at a keyframe some other joint introduced is interpolated, not reset — a joint
keyed only at the ends still poses correctly in between.

A misspelled joint name is an error naming the joint and listing the rig, not an animation that
quietly does nothing.

## Previewing

`render_anim` already gives you the `id`; this plays it on the rig.

```lua
local animation = Instance.new("Animation")
animation.AnimationId = built.id
local track = workspace.Dummy.Humanoid.Animator:LoadAnimation(animation)
track:Play()
```

## Reading an existing animation back

```lua
local clip = game:GetService("AnimationClipProvider"):GetAnimationClipAsync("rbxassetid://507771019")
local tracks = vmcp.Anim.Decompile(clip)
```

Edit the tracks, recompile, preview. The whole loop stays in Studio.

## Gotchas

- `KeyframeSequence.Length` reads 0 until the sequence is loaded. `Compile` returns the real length
  (the highest keyframe time) instead.
- `Loop` and `Priority` on the sequence can be overridden by the `AnimationTrack` at playback.
- Naming a Keyframe emits an animation marker for `KeyframeReached`.
- `Pose.Weight` is per-pose blend weight; for whole-track weight use `AnimationTrack:AdjustWeight`.
