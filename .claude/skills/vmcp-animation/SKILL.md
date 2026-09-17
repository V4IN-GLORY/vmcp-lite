---
name: vmcp-animation
description: Building Roblox animations with VMCP — the render_anim tool takes per-joint tracks, draws the rig posed at each keyframe as a filmstrip and returns a playable id with no upload, plus the Rig and Anim library underneath it and reading existing animations back as tracks. Use when asked to make, edit or inspect an animation.
---

# Animation as code

## The loop: `render_anim`

One call writes the animation, draws it and hands back a playable id. Send tracks, get one image:
the rig posed at every keyframe in reading order, four views (front, right, iso, top) tiled 2x2
into a 4k sheet. One picture per iteration is the whole token budget -- look, fix numbers, resend.

```
render_anim {
  tracks = {
    RightUpperArm = [ { time = 0, angles = [0,0,0], easing = "CubicV2/Out" },
                      { time = 0.25, angles = [0,0,-110], easing = "CubicV2/InOut" },
                      { time = 0.6, angles = [0,0,15] } ],
    RightLowerArm = [ { time = 0.25, angles = [-20,0,0], easing = "CubicV2/InOut" }, { time = 0.6, angles = [0,0,0] } ]
  }
}
-> Workspace.VMCPRigR15: 3 frame(s) in reading order, 2 per row: t=0  t=0.25  t=0.6
   id = rbxasset://...  length = 0.6  joints = RightUpperArm, RightLowerArm
   [picture]
```

- No `rig`: it spawns `Workspace.VMCPRigR15` (or `VMCPRigR6` with `rigType = "R6"`) in classic
  colours -- yellow head/arms, blue torso, green legs -- and reuses it. `rig = "Workspace.Enemy"`
  for anything else; any Motor6D rig works, joint names come from the rig's own parts.
- Joint names are part names. R15: `UpperTorso LowerTorso Head RightUpperArm RightLowerArm
  RightHand RightUpperLeg RightLowerLeg RightFoot` and Left. R6: `Torso Head "Right Arm" "Left
  Arm" "Right Leg" "Left Leg"`. R6 arms only bend at the shoulder, so a punch is one joint.
- `holding = "ReplicatedStorage.Katana"` draws a Tool (or a Model with a Handle) in the right hand
  exactly as the engine grips it. Parts already welded to the rig (accessories, a sheath) come
  along on their own.
- `times = [0, 0.1, 0.2, ...]` samples between keys to check the in-betweens (up to 16).
  `views` for other angles, `size = 768` when a rough check is enough.
- `animationId = "rbxassetid://..."` instead of tracks draws an existing animation and prints
  its tracks as editable angles, so "make the walk bouncier" is read, edit, re-render.
- `save = "ServerStorage.Animations"` also leaves the KeyframeSequence in the place. Right-click
  it in Explorer > Save to Roblox and it becomes a real asset id for the game.

## Working an animation up

1. Blockout: 2-4 keys on the joints that matter most (torso, the working arm). Render.
2. Read the sheet against the description: is the pose extreme enough, is the timing right,
   does anything clip (arm through torso, weapon through leg -- the top view shows that).
3. Add the supporting joints: opposite arm counter-swings, torso twists into the swing, head
   leads. Render.
4. Easing pass, then `times` sampled between keys to check the in-betweens move the way the
   description says.
5. `save` it, play the `id` in Studio via run_luau (Previewing below) if a moving check is wanted.

Keep keys few. Three to five per moving joint says most things; the engine interpolates the rest.

## Easing

`easing` goes on the key it *leaves from* and is `"Style/Direction"`. Real styles only
(`PoseEasingStyle`): `Linear`, `Constant`, `CubicV2`, `Elastic`, `Bounce` (`Cubic` is the old
one; use `CubicV2`). Directions: `In` (slow start, fast finish -- engine default), `Out` (fast
start, settles), `InOut`. Anything else is an error, not a silent Linear.

- Body motion between poses: `CubicV2/InOut`. Nearly always the right default.
- Wind-up into a strike: `CubicV2/In` into the hit, then `CubicV2/Out` or `Bounce/Out` out of it.
- Impacts, landings, recoil: `Bounce/Out` or `Elastic/Out`.
- Hard cuts, blinks, weapon swaps: `Constant`.
- `Linear` only for mechanical things (a turret, a conveyor). The tool flags a track set where
  every transition is Linear because it reads as robotic on a character.

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
        { time = 0.25, angles = { 0, 0, -110 }, easing = "CubicV2/Out" },
        { time = 0.6,  angles = { 0, 0, 15 },   easing = "CubicV2/InOut" },
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

`vmcp.Anim.Sequence(model, tracks, options)` returns the `KeyframeSequence` instance itself
(unparented) when you want to put it in the place rather than register it.

`angles` is degrees, XYZ. Pass `cframe = CFrame.new(...)` instead for anything angles can't say.

**Easing is written on the key it leaves from**, because `Pose.EasingStyle` describes how to reach
the *next* keyframe. The last key's easing is never used. See Easing above.

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
