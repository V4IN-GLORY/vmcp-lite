# Additional Profiler Groups

<!-- from github.com/Roblox/libmp/docs/ALL-SCOPES.md -->
This file documents profiler groups that don't have their own dedicated file due to small scope count.

---

## Skeleton Group

Animation skeleton operations.

### SkeletonWatcher::createAndBindToSkeleton / SkeletonWatcher::create / SkeletonWatcher::bindToSkeleton

**Creates a skeleton watcher and binds it to a character's skeleton — monitors rig changes for animation invalidation.**


---

### allocatePose / getPosePrepare / fetchPhysics / fetchAnimation / buildSkeleton / getBoneIndicesBySortedBoneHashes

**Pose buffer management: allocates pose storage, prepares pose data, fetches physics/animation state, builds the skeleton structure, and maps bones by hash.**


---

## FaceAnimatorService Group

Face tracking and animation.

### A2cInference / V2cInference

**Audio-driven and video-driven face-animation inference — runs ML models to generate facial animation from audio or camera input.**


---

### completeSdkSetup_AudioOnly / completeSdkSetup_ForModelDelivery

**Completes face tracker SDK setup for audio-only or full model delivery modes.**


---

### initAsync_ModelDelivery_JIT / initAsync_ModelDelivery_SetupAndLaunchMDS

**Async initialization of the face tracking model delivery system — JIT setup and model download service launch.**


---

### FinalDMTask_ModelDelivery

**Final DataModel task for face tracking model delivery completion.**


---

## HSR Group

Hidden Surface Removal for layered clothing — precomputes which body-mesh surfaces are hidden beneath clothing so they can be skipped at render time.

### GenerateHSRData / generate HSR data

**Computes which mesh surfaces are occluded by cage geometry, using reference, cage, and parent mesh data to generate compression-optimized hidden-surface-removal metadata.**


---

### HSR data deserialize / HSR data serialization

**Serializes/deserializes HSR data for network transfer or disk caching.**


---

### generate WrapLayer HSR data / generate from inner cage HSR data / generate to outer cage HSR data

**Generates HSR data for specific deformation targets: wrap layers, inner cage, and outer cage.**


---

## Rbf Group

Mesh deformation for layered clothing.

### solutionBuild

**Builds the deformation solution for mesh fitting.**


---

### deduplication/masking

**Deduplicates control points and applies masking for interpolation.**


---

### distance_matrix / target_matrix

**Computes distance and target matrices for deformation interpolation.**


---

### factorize / solve_reuse_llt / llt_cache_hit

**Solver operations for the deformation system; cached for reuse across frames. solve_reuse_llt reuses the cached factorization. llt_cache_hit fires when the cache is valid.**


---

## Runtime Group

Engine runtime infrastructure.

### IO::Process / IO::Request

**I/O dispatcher: IO::Process runs a blocking call thread worker with thread monitoring disabled. IO::Request executes individual blocking call function requests in a background thread.**


---

### ProcessAppEvents / handleSDLMarshalledEvent

**Processes queued cross-thread work marshalled to the main thread. `handleSDLMarshalledEvent` runs a single marshalled callback delivered via the SDL event queue.** The same `ProcessAppEvents` step is also timed under the **App** group (see the App-group entry below); the group tag distinguishes the two.


---

### CallMessage / marshalledJob

**Platform-specific function marshalling — runs a callback on the thread it was marshalled to. On Android this is `CallMessage` (runs the callback on the main thread, with exception handling); some other platforms use `marshalledJob` instead.**


---

### parallelFor

**Generic parallel-for dispatch — distributes iterations across worker threads.**


---

## FroxelGrid Group

Light culling operations for the lighting system.

### cullLights / cullLightsCPU

**Culls lights against the froxel grid — determines which lights affect which screen regions. CPU variant for fallback path.**


---

### uploadGPULightCullData / uploadGPULightRenderData

**Uploads light culling data and rendering data to the GPU for the clustered lighting system.**


---

### Gather / Memcpy / WriteBack

**Gathers light data, copies to staging buffers, and writes back results from GPU.**


---

## Graphics Group

Low-level graphics API operations.

### Load font

**Loads a font into the graphics system.**


---

### commitChanges / commitCommandBuffer / makeCommandBuffer / queueSubmit

**GPU command buffer operations: creates command buffers, records commands, commits changes, and submits to the GPU queue.**


---

## RbxTransport Group

Network transport layer.

### BasePacketSender.processPendingTx / BasePacketSenderDeprecated.processPendingTx / PacketSenderDeprecated.processPendingTx

**Processes pending packet transmissions — sends queued network data.**


---

### ConnectionHandler.handle / ListenerHandler.handle

**Handles incoming connections and listener events at the transport layer.**


---

### QuicPacketReader.onRecv / LibuvEventLoop.runOnce / SysEventLoop.processAllEvents

**Transport I/O: reads QUIC packets, runs the libuv event loop, and processes system events.**


---

## ModelLOD Group

Model level-of-detail system.

### ModelLODComputation / GetGeometryForComputation / fetchModelMeshDependencies

**ModelLODComputation generates optimized mesh representations for model LOD rendering. GetGeometryForComputation collects geometry from CSG/MeshParts/BaseParts. fetchModelMeshDependencies async-loads all mesh/texture dependencies.**


---

## D3D11 Group

Direct3D 11 operations.

### commitChanges / new Texture

**D3D11-specific GPU operations: commits pending state changes and creates texture resources.**


---

## Ads Group

In-experience advertising.

### AdGuiHeartbeat / VisibilityHeartbeat

**Per-frame ad system heartbeats — updates ad GUI state and checks ad visibility.**


---

### AdPortalValidate / getPerfData

**Validates ad portal state and collects performance data for ad telemetry.**


---

### Raycasting / VisibilityCheck

**Ad visibility checks: `Raycasting` casts a ray to test whether the ad surface is occluded, while `VisibilityCheck` evaluates screen-space area coverage and tracks viewability history.**


---

## App Group

Application lifecycle and thread marshalling.

### ProcessAppEvents / UpdateAppState / WaitForEvents

**Application event loop: processes queued events, updates application state, and waits for new events.** Its `ProcessAppEvents` step is the same main-thread event processing documented under the **Runtime** group — the label appears in both groups.

---

### App / Submit

**Submits a marshalled function call from a background thread to the main thread.**

---

### App / Execute

**Executes a marshalled function call on the main thread.**

---

### App / ProcessMessages

**Processes all pending marshalled messages on the main thread.**

**Performance notes:** If wide, many background threads are queuing work for the main thread.

---

### App / ProcessMessagesOfType

**Processes messages of a specific type/priority.**

---

### App / OnAsyncEvent (Windows)

**Runs a function marshalled onto the main thread — the handler for an async Windows event.**

---

## Camera Group

### StepEngineCamera / StepSubject

**Steps the engine camera system and advances the camera subject (target tracking).**


---

## CageDeformer Group

### Initialize Scratch / deformVertices

**Initialize Scratch creates buffers for vertex normals, positions, and validity tracking. deformVertices applies cage deformation to mesh vertices using precomputed solutions.**


---

## SmoothCluster Group

### HashSetInsert / onTerrainRegionChanged

**Hash set insertion for terrain chunk tracking and terrain region change notifications.**

---

## AssetProvider Group

Asset loading pipeline operations.

### AssetProvider / AssetProviderWorkflowExecutorCycle

**One cycle of the asset provider workflow executor — processes asset loading steps.**

---

### AssetProvider / onWorkflowComplete

**Offloads asset workflow completion telemetry outside the hot loop.**

---

## CSG Group

Constructive Solid Geometry operations (Union, Intersect, Subtract).

### CSG / csgFunc

**Executes a CSG boolean operation (union, intersect, subtract) on meshes.**

Runs asynchronously when players or scripts use CSG operations.

**Performance notes:** CSG operations are expensive. Complex meshes with many faces take longer.

**What game creators can do:**
- Avoid runtime CSG operations in performance-critical paths
- Pre-compute CSG at edit time rather than runtime
- Use simpler meshes for CSG operands

---

### CSG / commit

**Commits CSG results — finalizes the computed mesh and updates the PartOperation.**

---

### CSG / getInstancesThatNeedFetching

**Categorizes CSG operand instances into those needing validation, asset fetching, or rebuilding.**

---

### CSG / collision geometry / Generate physics data / dcd convert

**Generates physics collision geometry from CSG results.**

---

### CSG / planesForVertex

**Collects the BSP planes that pass through a given vertex during CSG computation.**

---

## Terrain Group

Terrain editing operations (distinct from Voxel group which handles voxel storage).

### Terrain / castRay

**Casts a ray against terrain geometry.**

---

### Terrain / generateTilesWorker / generateTile / SDFFromHeightMap

**Generates terrain tiles from heightmap data.**

Used by terrain import tools.

---

### Terrain / importHeightmapSetup / drainImportQueue

**Sets up and processes heightmap import operations.**

---

## Micro-Groups

These groups have only 1-2 scopes each. The header shows the profiler group name.

### GameplayNet

- `UpdatePlayerLocations` — updates player spatial locations for gameplay networking
- `updateNOUOwners` — updates Network Ownership Unit owners

### RakNet

- `RakPeer::ProcessNetworkPacket` — processes buffered incoming transport-layer packets
- `RakPeer::HandleActiveSystemList` — manages the list of active peer connections

### LightGrid

- `gatherLights` — gathers the visible lights for the light-grid update

### GizmoManager

- `collectGizmos` — gathers the active constraint/attachment visualization gizmos to draw
- `preprocessBudgetedGizmos` — prepares those gizmos for drawing; capped per frame — when more constraints are visible than the budget allows, the closest ones are prioritized by distance

### VertexNormals

- `initializeAndResize` — initializes and resizes vertex normal computation buffers
- `solveSmoothingGroups` — computes smoothing groups for vertex normal averaging

### LuauExpression

- `LuauExpression::evaluate` — evaluates a Luau expression
- `LuauExpression::parse` — parses a Luau expression string

### ScriptContext

- `WaitForLuauGcThread` — waits for the Luau GC thread to finish before proceeding

### Humanoid

- `getContactRepelForceInBalancing` — computes repulsion force to prevent humanoid overlap

### CaptureService

- `onVideoCaptureContentReadyAsyncTask` — background task that runs after a `CaptureService` video recording finishes; reads the recorded video file to prepare it for the capture-ready flow (`CaptureService:StartVideoCaptureAsync`)

### TaskQueue

- `addTasks` — adds multiple tasks to a task queue

### Content

- `processTask` — processes a content loading task

### LOD

- `updateLODLevels` — updates script-level-of-detail levels for script instances (not model geometry LOD)

### Texture

- `GenerateComponents` — generates texture component data

### FileMeshData

- `computeUniformBoxmap` — computes uniform box-map texture coordinates for a mesh
- `ReadFileMesh` — reads and decodes a mesh file asset

### VoiceControlPlane

- Voice chat control plane operations

### SoundOutput

- `renderAudio` — audio render output callback

### MemProfStorage

- `mappedFileFlush` — flushes memory profiler storage

### LocalStorage

- `asyncFlushTask` — async local storage flush

### System

- System-level operation

### Compress

- Data compression operation

### CodeGen

- Luau native code generation

### Copy

- Copy operation

### Debug

- Debug operation

### (OverflowGroup)

- `(OverflowTimer)` — overflow bucket for CPU engine scopes when the profiler runs out of available scope slots; the real engine scope name is not recorded

### (OverflowGroupGpu)

- `(OverflowTimerGpu)` — overflow bucket for GPU engine scopes when the profiler runs out of available scope slots; the real engine scope name is not recorded
