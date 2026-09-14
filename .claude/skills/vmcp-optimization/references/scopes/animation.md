# Animation Group

<!-- from github.com/Roblox/libmp/docs/ALL-SCOPES.md -->
The Animation group contains scopes related to skeletal animation playback, retargeting, inverse kinematics, and the animation graph system. These scopes fire during the physics/simulation step at the fixed rate (typically 60 Hz).

---

## Related Frame-Level Scopes (in Physics group)

The following scopes in the Physics group orchestrate animation at the frame level:
- `stepAnimationPrepare` — prepares animation state for the current step
- `stepAnimation` — runs all Animator instances (parallel or serial)
- `stepIK` — runs IK solvers after animation

---

## AnimationTrack::stepRetargeted

**Evaluates one animation track with retargeting applied — the main per-track step function.**

Advances an AnimationTrack by one time step, evaluates keyframes/curves at the current time, applies retargeting to map the source animation skeleton to the target rig, and accumulates the result into the pose buffer.

**Nesting:** Runs under `AnimatorParallelManager::stepAll` (parallel dispatch is per-Animator; each Animator steps all of its own tracks), which runs within the frame-level `stepAnimation` scope.

**Performance notes:** Called once per playing AnimationTrack per frame. Cost depends on:
- Number of keyframes/bones in the track
- Whether retargeting is active (adds IK solve overhead)
- Blending complexity (multiple overlapping tracks)

**What game creators can do:**
- Reduce the number of simultaneously playing animation tracks per character
- Use animation priorities to avoid unnecessary blending
- Stop animations that aren't visible on screen


---

## AnimationTrack::clipApply

**Applies the raw clip data (keyframes/curves) to produce joint transforms for one time sample.**

Evaluates the animation clip at the current playback time to produce local joint transforms. This is the raw keyframe interpolation step before retargeting.

**Performance notes:** Fast for simple animations. Can be expensive for dense keyframe sequences or many bones.


---

## stepRetargeted::accumulators

**Accumulates retargeted joint transforms into the final pose blend buffer.**

After retargeting computes the joint transforms for this track, this phase blends them into the accumulated pose using the track's weight and blend mode.

**Performance notes:** Fast — simple weighted accumulation.


---

## AnimationTrack::refreshTargetRig

**Rebuilds the retargeting mapping when the target rig changes (e.g., avatar changes body shape).**

This scope wraps the whole function, so it fires on every retargeted track step. Most frames it early-outs cheaply; the expensive work — scanning the rig hierarchy and rebuilding the retarget map — only runs when the target rig actually changes (avatar swap, body-shape change).

**Performance notes:** Expensive but rare — only triggers when the rig actually changes (avatar swap, body shape change). Should not fire every frame.

**What game creators can do:**
- Avoid frequently swapping character rigs mid-game
- If rig changes are expected, batch them rather than changing bones incrementally


---

## refreshTargetRig::checkCache

**Checks if the cached retargeting data is still valid for the current rig.**

Fast validation step that checks whether the existing retarget map can be reused or needs rebuilding.

**Performance notes:** Negligible. Early-exit path.


---

## refreshTargetRig::newRetargeter

**Builds a new retargeter for the current source-to-target rig pair — set up when an animation authored for one rig is played on a differently-proportioned rig.**

Constructs the retargeting object that maps one skeleton's proportions to another. This is the expensive path when the cache is invalid.

**Performance notes:** Moderate cost, but should be rare.


---

## AnimationTrack::createSrcRigForTrack

**Constructs the source rig representation from the animation clip's skeleton data.**

Builds a source skeleton model from the animation asset's bone structure. Required for retargeting to know what skeleton the animation was authored for.

**Performance notes:** One-time cost per unique animation-rig pairing. Cached after first creation.


---

## KeyframeSequence::apply

**Applies a KeyframeSequence (legacy animation format) to produce joint transforms.**

Evaluates the legacy KeyframeSequence format at the current time. This is the older animation format (pre-CurveAnimation).

**Performance notes:** Per-track cost. Legacy format is slightly less efficient than CurveAnimation.


---

## CurveAnimation::apply

**Applies a CurveAnimation (modern animation format) to produce joint transforms.**

Evaluates the modern curve-based animation format. More efficient and higher quality than KeyframeSequence.

**Performance notes:** Per-track cost. Generally fast with binary search on sorted keyframe arrays.


---

## ClipEvaluator::evaluate

**Evaluates a generic animation clip — dispatches to the appropriate format handler.**

Entry point for clip evaluation that delegates to either KeyframeSequence::apply or CurveAnimation::apply based on the clip type.

**Performance notes:** Adds minimal overhead on top of the actual clip evaluation.


---

## IkControlManager::update

**Updates all IkControl instances — runs inverse kinematics for each active IK chain.**

Iterates over all active IkControl objects and solves their IK chains. IK is solved after forward kinematics (animation) to apply procedural constraints.

**Nesting:** Called inside `stepIK` at the frame level.

**Performance notes:** Cost = O(IK controls × chain length × iterations). Expensive with:
- Many active IkControl instances
- Long IK chains (many bones)
- High iteration counts

**What game creators can do:**
- Limit the number of active IkControl instances
- Disable IK on characters that are far from the camera
- Use shorter IK chains when possible
- Reduce `IkControl.SmoothTime` to converge faster with fewer iterations


---

## AnimationRig::bindRigToR15Joints

**Binds the animation rig to the R15 joint hierarchy of a character model.**

Scans the character model's Motor6D joints and maps them to the animation rig's bone names. This establishes the connection between animation data and the actual rig.

**Performance notes:** One-time cost per character. Not a per-frame scope.


---

## R15ToR15Retargeter::initialize / R15ToR15Retargeter::newInitialize

**Initializes the R15-to-R15 retargeting system for a source/target rig pair.**

Computes the skeletal proportions ratio between source and target rigs, and builds the joint-level retarget transforms.

**Performance notes:** One-time cost per unique rig pair. Cached.


---

## retarget

**Performs the actual retargeting computation — maps source joint transforms to target proportions.**

The core retargeting algorithm that takes source-skeleton local transforms and produces target-skeleton local transforms accounting for different limb lengths and proportions.

**Performance notes:** Per-track, per-frame cost when retargeting is active. Moderate — involves per-bone matrix math.


---

## RetargetFK

**Forward kinematics phase of retargeting — transforms joints from source to target space.**

Applies the FK (forward kinematics) portion of the retarget: straightforward joint-to-joint mapping with proportion scaling.

**Performance notes:** Fast linear pass over the skeleton.


---

## RetargetIK

**Inverse kinematics phase of retargeting — corrects end-effector positions after FK mapping.**

After FK retargeting, IK corrections are applied to maintain foot/hand contact positions. This ensures that retargeted animations still have feet touching the ground.

**Performance notes:** More expensive than FK phase due to IK correction passes. Only runs when the retargeter detects that IK correction is needed.


---

## AnimationGraph::update

**Updates the animation graph state machine — evaluates transitions and advances node states.**

Processes the animation state machine: checks transition conditions, advances active states, and determines which animation nodes should be evaluated this frame.

**Performance notes:** Cost depends on graph complexity (number of states, transitions, blend trees). Typically fast for simple graphs.


---

## AnimationGraph::evaluate

**Evaluates the animation graph output — produces the final blended pose from all active nodes.**

Walks the active animation graph nodes and blends their outputs together to produce the final skeletal pose. This is where multi-layer blending and additive animations combine.

**Performance notes:** Cost proportional to the number of active nodes in the graph. Deep blend trees with many simultaneous animations are more expensive.


---

## ModelSkinningTransformsView::reset

**Resets the skinning transforms view, clearing cached bone transforms.**

Invalidates the cached skinning matrix palette, forcing a recomputation on the next frame. Called when the model's skeleton changes.

**Performance notes:** Negligible one-time cost.


---

## ModelSkinningTransformsView::rebuildView

**Rebuilds the complete skinning transforms view for a model — maps bones to GPU-ready transform matrices.**

Reconstructs the full bone-to-transform mapping for skinned mesh rendering. This produces the matrix palette that the GPU uses for vertex skinning.

**Performance notes:** Cost proportional to bone count. Triggers when rig hierarchy changes.


<br>
<br>

---
