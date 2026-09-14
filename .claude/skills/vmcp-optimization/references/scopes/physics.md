# Physics Group

<!-- from github.com/Roblox/libmp/docs/ALL-SCOPES.md -->
The Physics group contains scopes for the entire physics simulation pipeline: frame orchestration, world stepping, collision detection, constraint solving, sleep management, interpolation, and per-body computations. These scopes fire on the main thread (and worker threads for parallel phases) at the fixed physics rate (60 Hz by default).

---

## Frame-Level Orchestration

### gameFixedStepped

**Top-level fixed-rate simulation frame — orchestrates humanoids, animation, scripts, and physics at 60 Hz.**

This is the outermost scope for the fixed-rate simulation step. It sequences: PreAnimation scripts → humanoid step → animation → Stepped scripts → IK → PreSimulation scripts → world step → PostSimulation scripts. Multiple sub-steps may execute per render frame if the physics rate exceeds the render rate.

**Performance notes:** If this scope is wide, identify which nested phase dominates. Common culprits: worldStep (complex physics), stepAnimation (many characters), or script callbacks (RunService.PreSimulation doing heavy work).


---

### gameStepped

**Runs the frame's RunService script callbacks at the render (variable) rate.**

Fires the per-frame `RunService.PreAnimation`, `RunService.Stepped`, and `RunService.PreSimulation` events, then resumes any scripts that were waiting. Humanoid stepping, animation, and inverse kinematics run separately in the fixed-rate step `gameFixedStepped`.

`RunService.PostSimulation` fires from the physics step (after the world step), not in this scope. (The one exception is a **paused Studio playtest** — physics is halted, so this scope fires it instead; this does not happen on live clients or servers.)

**Performance notes:** Cost is the total work your scripts do in these callbacks; drill into the individual `RunService.*` sub-scopes to see which one dominates.


---

### physicsSteppedTotal

**The complete physics step including pre/post work (ISR sync, interpolation, callbacks).**

Wraps the entire physics step from start to finish, including instance state replicator synchronization, the actual world step, and post-step notifications.

**Performance notes:** This is the "total physics bill" per frame. If consistently above budget, the scene has too much physics work.


---

### physicsStepped

**Runs the physics simulation.**

The physics simulation step nested within physicsSteppedTotal.

**What game creators can do:**
- Reduce the amount and complexity of physically simulated bodies


---

## RunService Script Callbacks

### RunService.PreAnimation

**Fires the `RunService.PreAnimation` Lua event — runs before animation stepping.**

Script callbacks connected to `RunService.PreAnimation:Connect()` execute here. Intended for game logic that must run before animation evaluation.

**Performance notes:** Cost = game script work. Keep callbacks lightweight.


---

### RunService.Stepped

**Runs the functions connected to the `RunService.Stepped` event — fires every frame, before the physics simulation.**

This is the same point in the frame as `RunService.PreSimulation`, which has superseded it. `Stepped` is still fully supported and is **not** formally deprecated, but `PreSimulation` is the event recommended for new work.

**Performance notes:** Cost is the total work your scripts do in `Stepped` callbacks. It runs before the physics step, so heavy work here delays physics for the frame.

**What game creators can do:**
- Reduce the amount or workload of functions connected to this event
- Move expensive calculations to a less frequent event, or spread them across multiple frames


---

### RunService.PreSimulation

**Fires the `RunService.PreSimulation` Lua event — runs before physics solving.**

Script callbacks for game logic that must execute before the physics world step (e.g., applying forces, setting velocities).

**Performance notes:** Expensive Lua work here directly delays the physics step. Common for custom character controllers and force application.

**What game creators can do:**
- Minimize work in PreSimulation callbacks
- Cache values instead of recomputing every frame
- Avoid raycasts or spatial queries here


---

### RunService.PostSimulation

**Fires the `RunService.PostSimulation` Lua event — runs after physics solving.**

Script callbacks for game logic that reads physics results (e.g., checking velocities, detecting collisions).

**Performance notes:** Same as PreSimulation — keep callbacks fast.


---

## Humanoid & Character Stepping

### stepHumanoid

**Steps all Humanoid instances — computes character movement, state machines, and platform standing.**

Runs the Humanoid state machine for every character in the scene. Handles running, jumping, falling, climbing, swimming, and seated states. Updates movement forces.

**Nesting:** Contains HumanoidParallelManager::stepAll or fires the humanoidSteppedSignal.

**Performance notes:** Cost scales linearly with the number of active Humanoids. Each humanoid performs raycasts for floor detection and state transitions.

**What game creators can do:**
- Reduce the number of spawned NPCs with Humanoids
- Use SimplePath or custom movement for distant NPCs instead of full Humanoids
- Set Humanoid state to Dead or disable PlatformStanding for inactive characters
- Disable Humanoid states that NPCs don't need (e.g. Climbing or Swimming)
- Reduce callbacks to Humanoid.StateChanged, or state changes such as Running or Died


---

### HumanoidParallelManager::stepAll

**Parallel dispatch of all Humanoid steps — distributes work across worker threads.**

Coordinates parallel humanoid stepping with sub-phases for wake-up, force updates, collision toggles, and synchronization.

**Nesting:** Contains: wakeUpHumanoid, forceUpdate, setPartCanCollide, syncQueue, clear.


---

### HumanoidParallelManager::stepAll::wakeUpHumanoid

**Wakes (or prevents sleep of) local humanoids each step — those owned by the local player, or locally simulating and not in a ragdoll/physics state (legacy physics path only).**


---

### HumanoidParallelManager::stepAll::forceUpdate

**Computes and applies movement forces for all active humanoids.**


---

### HumanoidParallelManager::stepAll::setPartCanCollide

**Updates collision state for humanoid body parts (e.g., disable collision during certain states).**


---

### HumanoidParallelManager::stepAll::syncQueue

**Synchronizes parallel humanoid results back to the main thread.**


---

### HumanoidParallelManager::stepAll::clear

**Sizes the per-worker collision-map buffers for the parallel humanoid step (runs before the parallel work, not after).**


---

### HumanoidParallelManager::updateHumanoidOverlaps

**Detects overlapping player Humanoids using a sweep-and-prune AABB (optionally OBB) test and tracks how long each pair has overlapped.**

**Performance notes:** Cost increases significantly with many humanoids in close proximity. Expensive with many characters in close proximity.

**What game creators can do:**
- Avoid spawning many NPCs in the same location
- Spread NPC spawn points apart


---

### HumanoidState::doAutoJump

**Evaluates auto-jump conditions — raycasts ahead of the humanoid to detect obstacles that trigger automatic jumping.**

**Performance notes:** Two raycasts per humanoid per frame when auto-jump is enabled (a torso-height ray and a jump-height ray ahead of the character).


---

### Humanoid::computeForce

**Computes movement forces for all humanoid connectors in the physics kernel this step.**


---

### humanoidPlatformsMovement

**Corrects a character's position when it is standing on a moving platform that is owned or simulated by another peer, compensating for network-induced inaccuracies.**


---

## Animation (within Physics group)

### stepAnimationPrepare

**Fires the preparation signal just before animation evaluation, letting subscribers update their inputs before poses are computed.**


---

### stepAnimation

**Evaluates all Animator instances — steps animation tracks and produces skeletal poses.**

Runs AnimatorParallelManager::stepAll (parallel) or fires the animation signal (serial) to evaluate all playing animation tracks.

**Performance notes:** Cost = (number of characters) × (playing tracks per character) × (bones per track). The biggest animation cost in most games.

**What game creators can do:**
- Limit playing animation tracks per character (stop tracks that are fully blended out)
- Use animation priorities to prevent unnecessary blending
- Reduce animation on off-screen or distant characters
- Use fewer bones in rigs when possible
- Reduce the number of animated joints to lower the workload of this step
- Reduce callbacks to animation events such as AnimationTrack.KeyframeReached or AnimationTrack.Ended


---

### AnimatorParallelManager::stepAll

**Parallel dispatch of all Animator step operations across worker threads.**


---

### stepIK

**Runs inverse kinematics solvers after animation evaluation.**

Solves all active IkControl instances. Runs after FK animation so IK can override/adjust joint positions.

**Performance notes:** See Animation group → IkControlManager::update for details.


---

### stepLegacy

**Fires the internal per-frame step signal for engine objects that step each frame (Humanoid, BodyGyro, and similar). This is not Lua script stepping — scripts connected to `RunService.Stepped` are served under the separate `RunService.Stepped` scope.**


---

### stepLegacyControllers

**Steps legacy body movers (BodyVelocity, BodyForce, BodyGyro, etc.).**

Updates all legacy body mover constraints. Modern constraint-based movers (VectorForce, LinearVelocity, AlignOrientation) are the recommended alternative.

**Performance notes:** Cost proportional to the number of active legacy body movers.

**What game creators can do:**
- Migrate from BodyVelocity/BodyForce/BodyGyro to VectorForce/LinearVelocity/AlignOrientation
- Remove body movers from parts that don't need them


---

## World Step

### worldStep

**One full physics world step — the core simulation tick including broadphase, contacts, and solving.**

The main physics step. Broadly: midphase and contact generation (narrowphase), sleep management, joint stepping, constraint solving, and finally a broadphase update to prepare the next step.

**Performance notes:** This is the core physics cost. Wide worldStep means the scene is physics-heavy. Look at nested scopes to identify bottleneck (broadphase, contacts, or solver).

**What game creators can do:**
- Reduce part count in the workspace
- Anchor parts that don't need to move
- Use simpler collision fidelity (Box instead of Default/Hull/Decomposition)
- Reduce the number of unanchored assemblies
- Set NetworkOwnership appropriately so server doesn't simulate everything


---

### Kernel::stepWorld

**Steps the physics kernel — the low-level simulation engine.**

The kernel-level world step that coordinates assembly management, contact processing, and solver dispatch.


---

### Kernel::stepWorldThrottled

**Throttled world step — runs when the engine is overloaded and unable to simulate everything in real time.**

Same as stepWorld, but when throttled only "real-time assemblies" such as Humanoids are simulated.


---

## Broadphase & Collision Detection

### updateBroadphase / adaptiveUpdateBroadphase

**Updates the spatial acceleration structure for collision detection (grid hierarchy).**

Maintains the broadphase spatial data structure used to quickly find potentially colliding pairs. Moves objects in the grid when they move in the world.

**Performance notes:** Cost proportional to the number of moving assemblies. Anchored parts have zero cost.


---

### BroadPhase and primitiveMovementCallbackCollect

**Processes the results of the completed parallel broadphase update and fires primitive movement callbacks.**


---

### BroadPhaseIslandReprocess

**Reprocesses broadphase islands when topology changes (parts added/removed).**


---

### doBroadPhaseIslandAssemblyFilter

**Filters assemblies for broadphase island assignment based on movement and spatial proximity.**


---

### doBroadPhaseParallel MT Work

**Parallel broadphase work distributed across worker threads.**


---

### postParallelBroadphase

**Post-processing after parallel broadphase — merges results from worker threads.**


---

### expandByContacts

**Expands the Ik dragger's simulation set by walking contacts outward from the dragged primitives to pull in additional primitives that must be included in the drag solve.**


---

### stepMidPhase

**Mid-phase collision detection — spatial traversal for potential contact pairs within overlapping bounds.**

Narrows down broadphase pairs using spatial acceleration structures to find specific geometry pairs that may be in contact.

**Performance notes:** Expensive with complex MeshPart collision geometry (high triangle count).

**What game creators can do:**
- Use simpler CollisionFidelity (Box, Hull) instead of Default or PreciseConvexDecomposition
- Reduce mesh complexity for parts that collide frequently


---

### MidPhase processMidPhaseStepResults

**Processes results from parallel midphase work — notifies callbacks for assembly/terrain pairs that were added or removed this step.**


---

### stepContacts / newStepContacts / newStepContacts - Adaptive

**Narrow-phase contact generation — computes exact contact points and normals between colliding shapes.**

Runs specialized contact-generation algorithms for each shape-pair type to find contact manifolds.

**Performance notes:** Cost depends on the number of active contact pairs and shape complexity. Convex decomposition parts are the most expensive.


---

### stepContactsAsyncPrepare

**Builds the list of contacts to be processed asynchronously and flags their bodies for interpolation updates.**


---

### Finalize contacts / Finalize

**Finalize contacts** applies narrowphase contact results to the physics kernel — adding, updating, or removing contact data and firing touch/untouch events. **Finalize** completes a solver batch: it applies the solver's impulse corrections, runs the final constraint iterations, and integrates the updated positions and velocities back into the simulated bodies.


---

### Finalize With Malformed Output Checks

**Integrates the solved positions into the simulated bodies while checking for numerically unstable (exploded) solver output.**


---

## Sleep Management

### preContactStepSleepStage

**Pre-contact sleep evaluation — determines which assemblies can remain sleeping this frame.**

Checks whether sleeping assemblies have been disturbed (new contacts, applied forces) and need to wake up.

**Performance notes:** Fast per-assembly check. Total cost = O(sleeping assemblies with potential contacts).


---

### postContactStepSleepStage

**Post-contact sleep evaluation — puts assemblies to sleep that have settled.**

After solving, checks whether active assemblies have come to rest (velocity below threshold for enough frames) and can be put to sleep.


---

### stepAssembliesWakePending / stepAssembliesRecursiveWakePending

**Wakes assemblies that have pending wake requests (touched by a moving object, force applied, etc.). The recursive variant also propagates waking through connected assemblies up to a bounded depth.**


---

### stepAwakeAssemblies

**Iterates over all awake assemblies to check if they should continue being awake.**


---

### sampleAwakeNonSimulatingAssemblies

**Samples awake assemblies that aren't actively simulating to check if they need to start simulating.**


---

### updateContactSleepState

**Updates the sleep state of contacts — removes contacts for sleeping pairs, activates for waking pairs.**


---

### updateVisuallySleeping

**Advances each visually-moving part's "steps to sleep" countdown and moves parts that have stopped moving into a visually-sleeping state — the second part of the moving-assemblies (`notifyMovingAssembliesAndPrimMovementCallbacks`) tracking. Parts marked visually sleeping no longer need per-frame transform updates on the render side.**


---

## Island Generation & Solver

### Generating Islands

**Partitions the awake world into independent islands for parallel solving.**

Groups connected assemblies (via contacts or joints) into independent islands that can be solved in parallel without synchronization.

**Performance notes:** Cost depends on connectivity. Highly connected scenes (many parts touching) produce fewer, larger islands that can't parallelize well.


---

### Repack Islandizer

**Compacts island data structures after topology changes.**


---

### Generating Tasks

**Creates solver tasks for each island — prepares work items for the constraint solver.**


---

### Init Batch Solve

**Initializes batch solving — prepares shared data structures for parallel island solving.**


---

### Solve Batch

**Solves a batch of constraint islands using the constraint solver.**

The main solver work for the traditional physics solver. Iterates over constraints to find forces that satisfy all contacts and joints.

**Performance notes:** This is often the most expensive physics scope. Cost depends on:
- Number of awake constraint rows (contacts + joints)
- Solver iteration count
- Island size and connectivity

**What game creators can do:**
- Reduce the number of unanchored parts
- Anchor parts that don't need physics
- Avoid large piles of parts (creates big islands with many constraints)
- Use simpler collision fidelity


---

### Solve Batch Primal

**Solves a batch of constraint islands using the alternate constraint solver.**

An alternate constraint solver that uses iterative methods for robust convergence on complex systems.


---

### Sort Constraints

**Partitions an island's constraints into interior versus exterior groups as a preparation step for the alternate (Primal) solver path.**


---

## Constraint Solver Details

### LDLPGSSolver::solve

**Main constraint solver iteration loop — iterates to convergence.**

The core constraint solver. Projects constraints iteratively to find equilibrium forces.


---

### LDL Decomp

**Decomposes the constraint matrix for efficient solving.**


---

### Apply forces

**Evaluates active force objects (such as VectorForce and the legacy body-force movers) and accumulates their force and torque onto bodies for later integration. These are user-created forces, not constraint forces, and velocities are not updated here.**


---

### ConstructLDLProgram / ConstructLDLMxVProgram

**Constructs the solver program — builds the computation graph for constraint solving.**


---

### LDLMxVProgram::applyInverse / LDLMxVProgram::applyInverseLDL

**Applies the inverse of the factored constraint matrix to a residual vector, producing impulse corrections during constraint solving.**


---

### ConstructBodyShattering

**Constructs body shattering data — splits a body with a large constraint dimension into smaller shards to reduce the cost of the direct solve.**


---

### ConstructConnectedComponent

**Identifies connected components in the constraint graph for island decomposition.**


---

### ConstructLinearForceModel

**Builds a part's aerodynamic force model — precomputing the coefficient matrices used to evaluate fluid (aerodynamic) forces from the part's surface geometry.**


---

### CreateMinimumLocalFillElimination

**Computes a fill-reducing elimination ordering for the solver by greedily eliminating the node with the fewest resulting fill-in edges.**


---

### buildLDLComponents / buildLDLProgram

**Builds the solver's factorization structures from the constraint topology: `buildLDLComponents` splits the constraint graph into independent components, and `buildLDLProgram` builds the solve plan for a single component.**


---

### constructLineGraph

**Constructs the line graph representation of constraint connectivity.**


---

### orderEdgeReductionsInPivotOrder / orderPivotsInDepthFirstOrder

**Prepares the solver's elimination ordering: `orderPivotsInDepthFirstOrder` reorders pivots by a depth-first walk of the elimination tree, while `orderEdgeReductionsInPivotOrder` orients each edge reduction so the factorization uses only the lower-triangular blocks.**


---

### applyDiagonalPreconditioner

**Applies diagonal preconditioning to improve solver convergence rate.**


---

## Alternate Constraint Solver

### Primal::solve2

**Alternate constraint solver entry point — iterates to convergence.**

An alternate solver used for complex constraint systems.


---

### Primal::newton

**One iteration of the alternate solver.**


---

### Primal::buildSystem / Primal::buildEquations

**Constructs the linearized system of equations for the solver step.**


---

### Primal::linearSolve (variants)

**Solves the linear system within a solver iteration.**

Multiple variants exist:
- `(Partition Blocks By Row, Unpack Diagonal)` — general (non-SIMD) path
- `(SIMD Partition Blocks By Row, Unpack Diagonal)` — SIMD-accelerated variant, used when the island's block layout allows it
- `(pure block-diagonal direct solve)` — fast path used when the system has no off-diagonal blocks (empty lower triangle)
- `(two-body direct solve)` — optimized for simple two-body contacts


---

### Primal::velocityStage / Primal::positionStage

**Velocity and position correction stages of the alternate solver.**


---

### Primal::explicitForces

**Applies explicit (non-constraint) forces before the solve; in the current path this is limited to buoyancy for submerged bodies, and the scope does no work when fluid forces are disabled.**


---

### Primal::buoyancy

**Computes buoyancy forces for submerged bodies in the alternate solver path.**


---

### Primal::convergence

**Checks convergence criteria — determines if the solver has reached an acceptable solution.**


---

### Primal::warmstart / Primal::warmstartPositionStage

**Initializes the solver's iteration start point. `Primal::warmstart` carries the velocity-stage solution forward (blending toward the integrated velocity) as a warm start; `Primal::warmstartPositionStage` instead zeroes the position-stage solution (a cold start).**


---

### Primal::sortLowerTriangularBlocks

**Sorts lower-triangular blocks for efficient forward/back substitution.**


---

### Primal::bodyData

**Gathers body data (mass, inertia, position) for the solver.**


---

### Primal::DualUpdateTerm / Primal::InitializeNewtonIteration

**Solver iteration steps for the primal solver — DualUpdateTerm advances the augmented-Lagrangian dual (force) variables per constraint; InitializeNewtonIteration sets up per-iteration solver state.**


---

### Primal::NewtonIterationApplyAero

**Applies aerodynamic forces within a solver iteration.**


---

### Primal::StoreOutput / Primal::StoreOutputForConstraints / Primal::StoreOutputForSimBodies

**Stores solver output — packs per-body velocity and position virtual displacements, and stores the solved constraint forces.**


---

### PrimalSolverContext::PrimalSolverContext

**Constructs the primal solver context — allocates working memory and initializes state.**


---

## Raycasting

### RaycastBatched

**Performs a batch of raycasts against the physics world (used by humanoids, sensors, scripts).**

**Performance notes:** Cost = O(rays × scene complexity). Raycasts are one of the most common script-driven physics costs.

**What game creators can do:**
- Reduce raycast frequency (don't raycast every frame if not needed)
- Use shorter ray lengths
- Use RaycastParams FilterDescendantsInstances to reduce traversal
- Avoid raycasting against complex MeshPart geometry


---

### RaycastBroadphase

**Broadphase traversal for raycasts — finds candidate objects along the ray path.**


---

### RaycastTerrain / RaycastTerrainBatched / raycastAgainstCachedTerrain

**Raycasts against Smooth Terrain voxel data.**

**Performance notes:** Terrain raycasts traverse the terrain spatial structure. Long rays across large terrain areas are expensive.


---

### Shapecast

**Performs a shape cast (swept volume test) — tests if a shape would collide moving along a path.**

More expensive than raycasts because the swept shape must test against all potential contacts, not just a thin ray.

**Performance notes:** Significantly more expensive than Raycast. Use sparingly.


---

### buildKDTree / createKDTreeAsyncAndLaunchRaycastTasks

**Builds a KDTree and launches batched raycasts used to compute mesh self-occlusion for aerodynamic force calculations.**


---

### getHitLocationPartFilterDescendents

**Filters raycast results by part hierarchy (respects FilterDescendantsInstances).**


---

### buildClientRegion3d

**Builds the local player's client-side simulation region — computes the simulation radius and replication focus used to filter physics networking.**


---

## Integration & Interpolation

### Interpolation

**Interpolates network-replicated assemblies toward their latest received state — the per-task worker inside `interpolateNetworkedAssemblies`.**

This runs in parallel across networked assemblies (bucketed so only a fraction update each step), smoothly advancing each replicated assembly and its children toward the state received over the network so remote-owned objects move smoothly between updates.

**Performance notes:** Cost = O(moving assemblies). Fast per-body (simple lerp/slerp).


---

### interpolateAfterWorldsteps

**Post-world-step interpolation — updates visual positions after all physics steps in a frame.**


---

### interpolateNetworkedAssemblies

**Interpolates network-replicated assemblies between received server states.**

Smoothly transitions physics objects from their predicted state to server-corrected state.

**What game creators can do:**
- Set the network owner of parts to the current player to reduce this, although this will usually cause more physics work to be done elsewhere


---

## Callbacks & Notifications

### notifyMovingAssembliesAndPrimMovementCallbacks

**Fires movement callbacks for all assemblies that moved this step.**

Notifies the rendering system and other listeners that assemblies have new positions.

**Performance notes:** Cost proportional to moving assemblies. If this is expensive, many parts are moving.


---

### notifyVisuallyMovingPrimitives

**Notifies the visual system about primitives that are visually moving (for rendering updates).**

**Performance notes:** Runs once per part that moved this frame; cost scales with the number of continuously-moving parts.

**What game creators can do:**
- Reduce the number of parts moving every frame; let physics bodies come to rest (sleep) instead of jittering.
- Weld groups of parts into a single assembly so they move as one unit rather than many.
- When moving things from scripts, move a container/model rather than many individual parts.


---

### primitiveMovedCallback / onPrimitiveMovementCallbacks

**Per-primitive movement callback — updates rendering, streaming, and other systems.**


---

### movedPrimitives / collectPrimitivesFromMovingAssemblies

**Processes primitives that moved during parallel interpolation — fires post-move updates and wakes touching assemblies.**


---

### prepareCallbacks

**Prepares callback data structures before firing movement notifications.**


---

### WorldStepSignal

**Fires the world step signal — notifies all world step observers.**


---

### fireStateChangeEvents

**Fires Humanoid state change events (e.g., Landing, Freefall, Running transitions).**


---

### queueJointGuidsForPropChangedSignals

**Queues property-changed signals for joints that were modified by the solver.**


---

## Terrain & Deferred Updates

### applyDeferredTerrainChanges / applyDeferredUpdates

**Applies queued terrain modifications to the physics representation.**

When terrain is edited, changes are batched and applied during the physics step to maintain consistency.


---

### deletedTerrainChunks / updatedTerrainChunks

**Processes removed and updated terrain chunks for the physics representation.**


---

### cacheCurrentTerrain / readGrid

**Reads and caches terrain voxel data for physics queries.**


---

### testClearTerrainWeldsForGatheredCells

**Clears terrain weld constraints for cells that have been modified.**


---

## Assembly Management

### assemble

**Updates a tree of connected objects (assemblies) used by the physics engine.**

**What game creators can do:**
- Reduce the amount of joints being created or destroyed


---

### GatherAssemblies

**Gathers the actively-simulating assemblies (and, when not throttling, moving dynamic assemblies) into the broadphase set for this step.**


---

### processPendingCollisionAssemblies

**Processes assemblies with pending collision changes — CanCollide changes, geometry/CollisionFidelity changes, size changes, and NoCollision joint add/remove.**


---

### ResetBroadIslandForAssembly

**Resets the broadphase island assignment for an assembly that changed connectivity.**


---

### getAdaptiveBodiesInSolver

**Retrieves bodies that use adaptive simulation quality (LOD for physics).**


---

### computeMassAndIntertia

**Computes mass properties (centroid, volume, inertia tensor) for a single mesh-based part from its own mesh geometry.**


---

## Aerodynamics

Building a body's aerodynamic model (the `*Construction` scopes below and `generateAeroMesh`) is one-time setup — it runs when a part gains fluid forces or its mesh changes, not every frame. For MeshParts and unions this setup cost grows with the mesh's triangle count, so very high-poly meshes take longer to prepare. The per-frame aerodynamic force itself runs on a reduced (simplified) model, so its cost stays bounded regardless of the source mesh's complexity.

### AerodynamicInterpolatorConstruction

**Constructs the aerodynamic force interpolator for wind/drag simulation.**


---

### ReducedMeshAeroForceModelConstruction

**Builds a reduced mesh model for efficient aerodynamic force computation.**


---

### extractAeroMeshFromPrimitive

**Extracts the aerodynamic mesh surface from a primitive shape for drag calculation.**


---

### generateAeroMesh

**Generates the full aerodynamic mesh for a body.**


---

### TurbulenceCoefficientsUpdate

**Updates turbulence coefficients for wind simulation.**


---

### getOccludedMeshDataMTLimited

**Computes wind occlusion data for aerodynamic surfaces (which faces are sheltered).**


---

## Sensors & Force Computation

### BuoyancyAccumulator::computeForce

**Applies the buoyancy force to each body that is in water (floating or submerged).**

Each body's buoyancy force for the frame is computed earlier; this step just adds that force into the physics solver for every buoyant body. The per-body cost is constant — it does **not** depend on how complex the body's shape is.

**Performance notes:** Cost scales with the *number* of buoyant bodies (parts touching water), not their shape complexity. The physics step shows a `buoyancyAccumulators: N` label with this count. Normally cheap; only notable when a very large number of parts are in water at once.

**What game creators can do:**
- Reduce the number of parts simultaneously in water


---

### KernelJoint::computeForce

**Computes constraint forces for one joint (Motor6D, HingeConstraint, etc.).**


---

### AtmosphereSensor / BuoyancySensor / ControllerPartSensor / FluidForceSensor

**Sensor scopes for various force-computation systems — gather environmental data for force calculations.**


---

## Miscellaneous

### workspaceOnHeartbeat

**Workspace heartbeat handler — performs per-frame physics housekeeping.**


---

### handleFallenParts

**Detects and destroys parts that have fallen below the workspace's FallenPartsDestroyHeight.**

**Performance notes:** Checks all moving parts against the destroy threshold. Normally fast.

**What game creators can do:**
- Lower the destroy height or reduce the amount of parts that fall to the destroy height


---

### updateBones

**Updates dirty attachment-hierarchy constraints after physics solving — refreshes bones and attachment-attached constraints.**


---

### updatePhysicsInstructions

**Updates physics instruction state for adaptive simulation.**


---

### updatePartCollisions

**Recomputes character part collision data when avatar scaling changes (R15 scaling defaults).**


---

### SafeMove / MoveCoarse / MoveFine

**Kinematic movement functions — move parts safely without tunneling through geometry.**

SafeMove is the high-level entry point; MoveCoarse does large steps; MoveFine does sub-step refinement.


---

### collectCharacterParts

**Collects all parts belonging to a character model for physics grouping.**


---

### Batch Expansion

**Reserves and populates an island batch's working buffers (sim bodies, anchored bodies, constraints) for the current solver step.**


---

### ContactManagerPhysicalPropertiesChanged

**Handles physical property changes (friction, elasticity) on existing contacts.**


---

### ContactManagerOnAssemblyAdded / ContactManagerOnAssemblyRemoving

**Handles assembly addition/removal from the contact manager.**


---

## ISR-Related (Instance State Replication)

### ISR-PhysicsStep::notifyMovingNOURoots

**Notifies the Instance State Replicator about moving Network Owner Unit roots for replication.**


---

### ISR-WorkspaceSynchHelper::processQueuedSynchData

**Processes queued synchronization data from the ISR system for physics state.**


---

### SpatialFilter::filterStep

**Updates simulation islands, arranging parts according to network ownership and local simulation. Islands are non-interacting groups of parts which can be simulated independently.**

**What game creators can do:**
- Avoid setting network ownership frequently
- Keep groups of parts far enough away from each other so they can be simulated separately


---

## UpdateControllers

**Steps all constraint controllers (VectorForce, LinearVelocity, AlignOrientation, etc.).**

Evaluates modern constraint-based body movers and applies their forces/velocities to the solver.

**Performance notes:** Cost proportional to active constraints. Generally well-optimized.


---

## MeshAssembly-Task / MeshProcessing-Task

**Builds a body's aerodynamic mesh data on a worker thread (used by fluid-force / buoyancy models), not collision geometry.**

Runs asynchronously on worker threads to build/process a body's aerodynamic mesh data (e.g. triangle-set occlusion weighting), not collision meshes. Fires when a part gains fluid forces or its mesh changes.


---

## generateCollisionGeometry

**Generates the collision representation for a part (e.g. convex decomposition of a mesh) used by the physics broad/narrowphase.**

**Performance notes:** One-time cost per unique mesh. Cached after generation.


---

## generateShape / generate

**Generates the collision mesh for a Terrain chunk (smooth-voxel geometry).**

**Performance notes:** Runs when terrain is edited or streamed in; cost scales with the amount of terrain being (re)meshed.


---

## Shapecast & Raycast Details

### Aerodynamic Integrator

**Integrates rigid body velocities with aerodynamic force models.**


---

### LadderRaycast

**Raycast used to detect ladder surfaces for character climbing state transitions.**

**Performance notes:** One spatial query per climbing check. Cost rises with dense collision geometry in the character's vicinity.


---

### Kernel::stepIkSolver

**Executes inverse kinematics solving on connectors for kinematic chains.**


---

### NOUSignals

**Processes deferred Network Ownership Unit (NOU) signals and joint change callbacks for ownership and spanning tree modifications.**


---

### PGS Solve

**Executes iterative constraint solving on contacts and collisions.**


---

### Primal::linearSolve (Partition Blocks By Row, Unpack Diagonal)

**Solves the linear system using row-partitioned blocks with diagonal unpacking.**


---

### Primal::linearSolve (SIMD Partition Blocks By Row, Unpack Diagonal)

**SIMD-accelerated variant of the row-partitioned linear solve — used when the island's diagonal blocks can be processed with SIMD.**


---

### Primal::linearSolve (pure block-diagonal direct solve)

**Direct solve for block-diagonal systems — fast path for simple constraint topologies.**


---

### Primal::linearSolve (two-body direct solve)

**Optimized direct solve for two-body contact constraints.**


---

### applyInnerBox

**Updates part collision data for avatars to enforce inner box collision constraints based on R15 scaling models.**


---

### applyJointTransforms

**Applies kinematic joint transformations to moving assemblies and updates their primitive positions in parallel.**


---

### primitiveMovementCallbacks

**Invokes movement callbacks for primitives whose extents changed due to assembly operations or joint transformations.**


---

### stepIk

**Executes the IK dragger physics step including contact stepping and solver updates for IK-controlled bodies.**


---

### stepUiLegacyJoints

**Updates legacy kinematic joints (VehicleSeat, SkateBoardPlatform, DynamicRotateJoint) using their stepUi callbacks.**


<br>
<br>

---
