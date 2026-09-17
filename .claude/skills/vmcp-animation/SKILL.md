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
- `angles` and `offset` are in **character space** on every rig: +X right, +Y up, +Z back.
  Pitch (X) + tips the top of a part back and swings a hanging limb forward; so a forward lean is
  `angles = [-5,0,0]` on the torso, a leg stepping forward is `[35,0,0]`, and `offset = [0,-0.2,0]`
  on the root-driven part (`Torso` on R6, `LowerTorso` on R15) is a crouch. Same numbers, same
  meaning, R6 or R15.
- The text under the picture is the check the picture can't do. Per keyed joint it prints the
  range every channel covers across the frames:
  ```
  Torso: y -0.2..0.15, pitch -5° constant (never at rest)
  Right Leg: pitch -35..35°
  ```
  Read it every time. `z` moving on a torso that was meant to bob is the wrong axis; a channel
  marked `constant` on a part you didn't mean to hold is a whole-body tilt; `Head: pitch 1..6°`
  is a nod that reads as wobble in motion. All three look fine on a filmstrip.
- `holding = "ReplicatedStorage.Katana"` draws a Tool (or a Model with a Handle) in the right hand
  exactly as the engine grips it. Parts already welded to the rig (accessories, a sheath) come
  along on their own.
- `times = [0, 0.1, 0.2, ...]` samples between keys to check the in-betweens (up to 16).
  `views` for other angles, `size = 768` when a rough check is enough.
- `animationId = "rbxassetid://..."` instead of tracks draws an existing animation and prints
  its tracks as editable angles, so "make the walk bouncier" is read, edit, re-render.
- `save = "ServerStorage.Animations"` also leaves the KeyframeSequence in the place. The folder
  has to exist already; the tool won't make one. `ServerStorage` itself works. Right-click
  it in Explorer > Save to Roblox and it becomes a real asset id for the game.

## What looks wrong in motion but fine on a sheet

A sheet is eight still poses; a player sees the 60 frames between them, so small persistent
things dominate. Before saving, ask of the motion readout:

- Does anything drift on an axis it shouldn't? A cycle's root part should show `y` for a bob
  and nothing on `z` -- forward/back on the root scrubs against the character's real movement
  and reads as stutter.
- Is anything `constant` that wasn't meant as a held pose? A 5 degree lean is a choice and gets
  written once; a 5 degree lean you didn't write is an axis mistake.
- Do the small joints stay still? In a cycle, head and hands either hold one value or do
  nothing. A 3..6 degree nod on a walk is nervous wobble, not life; leave the head out.
- Do both halves of a cycle mirror? Left/right ranges should match to the degree.
- On a Humanoid rig, leave the root part's `y` at 0 in a locomotion cycle. The root joint moves
  the torso, not HumanoidRootPart, so a bob doesn't change collision -- it just pushes the feet
  through the floor on the down and floats them on the up. Sell weight with the limbs instead.

## Working an animation up

0. Unfamiliar rig? One-frame probe first: a single joint at `[30,0,0]`, `views = ["front",
   "right"]`, `size = 256`. Ten seconds, and it settles which way is forward on this rig before
   any real key is written. Guessing the axis from a full sheet cost a whole round once.
1. Blockout: 2-4 keys on the joints that matter most (torso, the working arm). Render.
2. Read the sheet against the description: is the pose extreme enough, is the timing right,
   does anything clip (arm through torso, weapon through leg -- the top view shows that).
3. Add the supporting joints: opposite arm counter-swings, torso twists into the swing, head
   leads. Render.
4. Easing pass, then `times` sampled between keys to check the in-betweens move the way the
   description says.
5. `save` it, play the `id` in Studio via run_luau (Previewing below) if a moving check is wanted.

Keep keys few. Three to five per moving joint says most things; the engine interpolates the rest.

The sheet judges poses and timing. The user judges motion, in the Animation Editor or in game,
and will catch things the sheet can't (a nod, a drift, a lean). So: hand over the `save`d
sequence by name, and when they report something wrong ask what they played -- an id from an
earlier render and the saved sequence can differ.

### A walk cycle, from the four-pose reference

One second, loop, 0.5 per step. Times are the classic contact / down / pass / up beats:

| t     | beat    | leading leg | trailing leg | arms (opposite to legs) |
|-------|---------|-------------|--------------|-------------------------|
| 0     | contact | +35         | -35          | ∓35                     |
| 0.125 | down    | +28         | -25          | (interpolated)          |
| 0.25  | pass    | 0           | +5           | 0                       |
| 0.375 | up      | -22         | +25          | (interpolated)          |
| 0.5   | contact | -35         | +35          | ±35                     |

then the same again with the legs swapped to 1.0. Easing `CubicV2/Out` leaving a contact,
`CubicV2/In` into the next one, `CubicV2/InOut` between. The left track is the right track with
every angle negated; write one and mirror it. R6 has no knees, so the lifted passing leg in a
drawn reference is just the trailing leg going 5 degrees past vertical. Leave the torso and head
alone (see the checklist) -- the reference's bounce is for a drawn character, not a Humanoid.

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

`angles` is degrees XYZ and `offset` is studs XYZ, both in character space (above). Pass
`cframe = CFrame.new(...)` instead for a raw `Motor6D.Transform` -- that's the joint's C0
space, which is what Decompile hands back and what nobody should write by hand (see below).

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

- **`Motor6D.Transform` is applied inside C0, and C0 is rotated on most rigs.** Every R6 joint
  has one: shoulders and hips are turned 90 about Y, RootJoint and Neck are -90 about X and 180
  about Z. Raw angles there mean "Z swings the arm forward", and a raw `CFrame.new(0, 0.2, 0)`
  on the torso slides it *backwards*, not up. That is exactly how a walk once shipped with the
  body tilted back, the root sliding fore and aft, and a nodding head -- the sheet looked right
  because the poses were all plausible, just on the wrong axes. `Anim` now conjugates
  `angles`/`offset` by `C0.Rotation` so they mean the same thing on every rig, and `render_anim`
  prints the per-joint ranges in that same space so a wrong axis shows up as text. Only
  `cframe` keys bypass this.
- **A saved sequence is whatever plugin was running when it was saved.** Studio does not
  hot-reload a rebuilt `VMCP.rbxmx`; the plugin requires its tools from its own copy loaded at
  startup, not from `ServerStorage.VMCP`. After changing `Anim` or `RenderAnim`: build, restart
  Studio, then re-render and confirm the new output (the motion readout is a cheap tell) before
  re-saving anything the user will play. Saving with the old plugin after re-authoring for the
  new one is how "make the R6 walk" turned into a floss.
- Don't infer a sign from a perspective render of a symmetric pose. Two legs at ±35 look the
  same as two legs at ∓35 from most angles; the motion readout gives the number, and for the
  world-space result `run_luau` can compose `Part0.CFrame * C0 * T * C1:Inverse()` and dot the
  UpVector against the root's LookVector -- that is how the lean sign was actually settled.
- The sheet steps frames along `(1,0,1)`, which reads left-to-right in front, right and the
  anim-specific iso/top presets. `left`, `back` and custom yaws can read right-to-left; the text
  says so when they do. Rows also slide along `(-1,0,1)` so the top view is a grid, so a row's
  frames sit at slightly different depths in the side views -- that is layout, not motion.

- `KeyframeSequence.Length` reads 0 until the sequence is loaded. `Compile` returns the real length
  (the highest keyframe time) instead.
- `Loop` and `Priority` on the sequence can be overridden by the `AnimationTrack` at playback.
- Naming a Keyframe emits an animation marker for `KeyframeReached`.
- `Pose.Weight` is per-pose blend weight; for whole-track weight use `AnimationTrack:AdjustWeight`.
