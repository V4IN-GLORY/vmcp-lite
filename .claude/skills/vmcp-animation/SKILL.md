---
name: vmcp-animation
description: Building Roblox animations as code with VMCP's Rig and Anim library — per-joint tracks compiled to KeyframeSequences, previewed with no upload, and read back from existing animations. Use when asked to make, edit or inspect an animation.
---

# Animation as code

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
