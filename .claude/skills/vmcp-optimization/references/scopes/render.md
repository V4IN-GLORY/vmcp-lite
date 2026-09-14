# Render Group

<!-- from github.com/Roblox/libmp/docs/ALL-SCOPES.md -->
The Render group contains scopes for the CPU-side rendering pipeline: scene preparation, culling, draw call building, pass dispatch, post-processing setup, and presentation. GPU-side passes are tracked separately in the GPU group.

Many scopes appear in pairs: one in "Render" (CPU submission) and one in "GPU" (GPU execution).

---

## Frame-Level Entry Points

### RunService.RenderStepped

**Fires the `RunService.RenderStepped` Lua event — game scripts that need to run before rendering.**

`RunService.PreRender` is the recommended alternative. Scripts connected to RenderStepped execute here.

**Performance notes:** Same as any script callback. Keep lightweight.


---

### RunService.PreRender

**Fires the `RunService.PreRender` Lua event — the preferred pre-render callback.**

Modern replacement for RenderStepped. Game scripts that update visual state before rendering run here.

**What game creators can do:**
- Only put visual updates here (camera, UI state)
- Avoid physics or logic work (use PreSimulation instead)


---

### RenderSteppedInternal

**Internal engine render-step callback — updates engine visual systems before scene traversal.**

Engine-internal work that prepares the rendering state: camera updates, light parameter updates, particle system advances, etc.


---

### fireBindToRenderStepCallbacks

**Fires callbacks registered via `RunService:BindToRenderStep()` — priority-ordered pre-render callbacks.**

Invokes all callbacks registered with specific priorities. These run in priority order (lower number = earlier).

**Performance notes:** Cost = sum of all BindToRenderStep callbacks. If wide, specific callbacks are doing heavy work.

**What game creators can do:**
- Unbind render step callbacks when not needed
- Keep bound callbacks minimal (only visual updates)
- Use appropriate priorities to avoid unnecessary ordering


---

## Scene Preparation (Prepare Phase)

### Prepare

**Top-level preparation scope — updates the scene graph before rendering.**

Orchestrates all pre-render scene graph updates: coordinate frame syncing, part invalidation, lighting preparation, and cluster updates.

**Nesting:** Contains SceneUpdater scopes and UI Layout.


---

### Perform

**When actual rendering commands are created and issued.**


---

### SceneUpdater::UpdatePrepare

**Prepares scene state — processes pending part additions, removals, material changes, and attachments.**

Entry point for scene graph maintenance. Handles:
- New parts entering the scene
- Parts with changed materials
- Terrain updates
- Attachment constraint processing

**Performance notes:** Cost proportional to scene changes this frame. Static scenes are nearly free.

**What game creators can do:**
- Avoid creating/destroying many parts every frame
- Batch property changes rather than changing properties one at a time
- Reduce unique material count


---

### SceneUpdater::updateDynamicParts

**Updates the coordinate frames (world matrices) for all dynamic parts each frame — including Beams, ParticleEmitters, Trails, Lights, and Humanoids — so their rendering follows their latest positions.**

**Performance notes:** Cost scales with the number of visible dynamic parts (Beams, ParticleEmitters, Humanoids, etc.).

**Labels:** `"Total parts: {N}"` — shows the number of parts being updated.

**What game creators can do:**
- Reduce the number of visible Beams, ParticleEmitters, and Humanoids

---

### SceneUpdater::performUpdateCoordinateFrame / SceneUpdater::preparePerformUpdateCoordinateFrame

**Updates the GPU-visible coordinate frames (world matrices) for dynamic FastCluster parts.**

Writes updated transform matrices to the buffers that the GPU will read for rendering.

**Performance notes:** Cost proportional to moving objects. One matrix write per moving entity.


---

### SceneUpdater::computeLightingPerform / SceneUpdater::computeLightingPrepare

**Computes dynamic lighting — updates light grid, shadow parameters, and environment lighting.**

Prepares all lighting data needed for the current frame: updates light positions, recomputes the light grid, processes new/removed lights.

**Performance notes:** Cost depends on the number of dynamic lights. Many PointLights/SpotLights increase this.

**What game creators can do:**
- Reduce the number of dynamic lights
- Use static lighting where possible
- Set light `Enabled = false` for lights that aren't visible
- Move the camera less to reduce lighting recalculation near the camera


---

### SceneUpdater::updateInstancedClusters2

**Updates instanced cluster rendering state — the batching system for similar parts.**

Maintains the instanced rendering batches: adds/removes parts from clusters, updates transforms within clusters, and handles cluster splits/merges.

**Performance notes:** Cost depends on the number of cluster membership changes. Static scenes are free.

**Labels:** `clusters: {N}` — the number of instanced clusters updated.

**What game creators can do:**
- Reduce work that implicitly updates a part's bounding box (`BasePart.CFrame`, `BasePart.Size`, `Motor6D.Transform`)
- Prefer property updates that don't move the bounding box, such as `Bone.Transform`, where possible

---

### updateInvalidatedFastClusters / updateInvalidParts / updateWaitingParts

**Processes parts that were invalidated (material change, resize, etc.) and need visual updates.**

**updateInvalidParts** updates parts that had some property changed or added. **updateInvalidatedFastClusters** prepares "FastCluster" geometries used to render Humanoids and skinned MeshParts (labels specify the number of parts, vertices, and size of vertices).

**What game creators can do:**
- Reduce the amount of property changes on the world; if a script updates a large set of object properties, break it down across frames
- Reduce visual changes to models with Humanoids or skinned MeshParts


---

### sortObjects

**Sorts the render queue by material, distance, or Z-index for optimal draw order.**

Multiple calls per frame for different passes (main, depth, highlight).

**Performance notes:** O(n log n) where n = visible objects. Fast with modern sorting.


---

## Culling

### SpawnCullJobs

**Spawns frustum culling work on worker threads — determines which objects are visible.**

Kicks off parallel frustum culling: tests all potentially-visible objects against the camera frustum.


---

### CullJob

**One culling thread's work — tests a batch of objects against the view frustum.**

Per-thread culling computation. Tests bounding boxes/spheres against the frustum planes.

**Performance notes:** Cost = O(total objects / thread count). More objects = more culling work.

**What game creators can do:**
- Reduce the total number of parts/meshes in the workspace
- Use StreamingEnabled to limit loaded objects
- Group small objects into fewer larger ones (Union, MeshParts)


---

### CullableSceneUpdate

**Updates the cullable scene representation — maintains spatial acceleration structures for culling.**


---

### CullView

**Culls one view (camera) — produces the visible set for that view.**


---

### WaitOnRenderNodeQueryFence

**Waits for culling to complete — synchronizes the main thread with cull worker threads.**

The main thread blocks here until all culling work is done. If this scope is wide, culling is the bottleneck.

**Performance notes:** If consistently long, there are too many objects to cull or too few threads.


---

## Render Queue & Pass Building

### updateRenderQueue

**Updates render queue groups for all passes — assigns visible objects to their render pass slots.**

After culling determines visibility, this scope assigns objects to specific render passes (depth, opaque, transparent, etc.).

**Performance notes:** Cost scales with the number of visible objects and the number of distinct passes/materials they map to.

**What game creators can do:**
- Reduce the number of objects visible on screen (lower draw distance, fewer parts).
- Reduce the number of distinct materials so more objects group into the same pass.


---

### BuildView / BuildDraws

**Builds the draw call list for a view — creates GPU command data.**

Converts the high-level render queue into actual draw commands (shader binding, mesh binding, constant buffer setup).

**Performance notes:** Cost proportional to visible draw calls. Complex materials and many unique meshes increase cost.


---

### BuildPass.BatchAndSort

**Batches and sorts draw calls within a pass for state-change minimization.**

Groups draw calls by shader/material to minimize GPU state changes.


---

### Dispatch / DispatchScene.beginRender / DispatchScene.refreshMeshSubsets

**The render-command dispatch phase. `Dispatch` is the actual CPU→GPU submission of draw calls; `DispatchScene.beginRender` sets up per-frame state (clears frame data, refreshes technique caches, applies mip results) and `DispatchScene.refreshMeshSubsets` refreshes CPU-side mesh LOD/subset tables — neither submits GPU commands.**


---

### DispatchSceneFRMBudget

**Frame Rate Manager budget calculation for the legacy-pipeline emulation path.**

The FRM evaluates whether the current frame met its time budget and adjusts quality settings accordingly.

**Performance notes:** If rendering is over budget, FRM reduces quality (lower resolution, fewer effects).


---

## Main Render Passes

### DepthPrePass

**Depth-only pre-pass — renders opaque, terrain, and opaque-caster geometry to populate the depth buffer without color writes. Alpha-tested opaque geometry is handled separately by the OpaqueWithAlpha depth passes.**

Enables early-Z rejection for the main color pass, significantly reducing overdraw.

**Performance notes:** Cost proportional to visible opaque geometry vertex count.

**Labels:** `"NodeCount: {N}"` — number of objects rendered in this pass.

---

### OpaqueWithAlphaDepthPass / OpaqueWithAlphaLateDepthPass

**Depth pass for objects with alpha-tested materials (foliage, fences, etc.).**

Objects with transparency that still need depth-testing get separate depth passes.

**Labels:** `"NodeCount: {N}"`

---

### depthPrepass / alphaPrepass / mainView

**CPU-side scope for the respective depth and main render passes within UpdateView.**

**Labels:** `"NodeCount: {N}"`

---

### Scene

**Main 3D scene rendering (CPU side) — traverses the visible scene and submits the draw calls for its opaque and transparent geometry.** This measures the CPU cost of preparing the frame's 3D render; the matching GPU execution time is the GPU-group `Scene` scope.

**Performance notes:** Usually the largest CPU rendering cost. Driven mainly by:
- Number of draw calls — each unique mesh × material combination is a separate call
- Part / instance / object count that must be culled and submitted each frame
- Decal and adornment count (each adds submissions)

**What game creators can do:**
- Reduce the number of *unique* mesh × material combinations so more objects batch into fewer draw calls
- Reduce overall part / instance and decal count
- Reuse the same meshes and materials instead of many one-off variants
- Shading-side cost — material/shader complexity, transparency and overdraw, resolution — shows up on the GPU-group `Scene` scope, not here


---

### Scene2D

**2D screen-space rendering — draws the screen-space UI render queues (screen-space GUIs and adornments).**


---

### GuiScene

**ViewportFrame rendering — renders 3D content within ViewportFrame UI elements.**

Each ViewportFrame is a mini-scene that gets its own render pass.

**Performance notes:** Each ViewportFrame adds a full render pass. Many ViewportFrames are expensive.

**What game creators can do:**
- Minimize the number of visible ViewportFrames
- Reduce object complexity within ViewportFrames
- Set ViewportFrame.LightDirection to avoid dynamic lighting


---

### Highlight

**Highlight effect pass — populates the CPU-side render queues for the Highlight instance's passes. The actual GPU rendering of highlighted objects happens later in the frame.**


---

### Clear

**Clears the framebuffer at the start of rendering.**

**Performance notes:** Nearly free — single GPU operation.


---

### UI

**Renders all 2D UI elements (ScreenGuis, adorns, text, images).**

Draws all on-screen GUI elements including text, images, frames, and other UI primitives.

**Performance notes:** Cost depends on the number and complexity of visible UI elements. Deep UI hierarchies with many elements increase draw call count.

**What game creators can do:**
- Reduce visible GuiObject count
- Use CanvasGroups to batch UI rendering
- Set Visible = false on off-screen elements
- Avoid excessive use of UIGradient (adds draw calls)


---

## Post-Processing Effects

### HBAO

**Screen-space ambient occlusion — screen-space AO computation.**

Computes ambient occlusion from the depth buffer to add contact shadows and depth perception.

**Performance notes:** Full-screen effect. Cost depends on resolution and quality setting. The FRM may reduce AO quality under pressure.


---

### Glow

**Bloom/glow post-processing — extracts bright areas and blurs them for glow effect.**

**What game creators can do:**
- Reduce the number of post-processing effects; usually not significant

**Performance notes:** Multi-pass blur. Usually not a bottleneck but contributes to post-processing budget.


---

### DOF / Depth of Field

**Depth of Field effect — blurs areas that are out of the camera's focus range.**

**Performance notes:** Full-screen effect. Heavier than glow due to depth-dependent kernel.


---

### BlurFx

**Blur effect — general-purpose screen blur (not DOF-specific).**

Used for the BlurEffect instance that game creators can add to the camera.


---

### SunRays

**Sun shaft (god ray) effect — computes volumetric light scattering from the sun.**

**Performance notes:** Full-screen radial blur. Moderate cost.


---

### ColorCorrection / Image Composition

**Final image composition — applies color correction, tonemapping, and combines all layers.**

The final pass that produces the output image: combines the lit scene with post-effects, applies tonemapping, and color grading.

**What game creators can do:**
- Reduce the number of post-processing effects; usually not significant


---

### VignetteEffect

**CPU-side update of the vignette effect parameters (aperture based on camera motion). The vignette darkening itself is applied later during image composition.**


---

### MSAA

**MSAA resolve pass — resolves multi-sample targets to single-sample for post-processing.**

**What game creators can do:**
- Reduce the number of post-processing effects; usually not significant


---

### DownSample

**Downsamples the framebuffer for lower-resolution effects (bloom, AO).**


---

## Upscaling

### Upscale SmootherStep / Upscale Lanczos / Upscale Linear

**Resolution upscaling — renders at lower resolution and upscales for performance.**

Different upscaling algorithms with quality/performance tradeoffs:
- Linear: fastest, lowest quality
- SmootherStep: balanced
- Lanczos: high quality, more expensive


---

## Shadows

### renderShadowMap

**Renders the shadow map atlas — generates depth maps from light perspectives.**

See the Shadows group for detailed shadow system scopes.


---

### Shadow Blur

**Blurs shadow maps for soft shadow edges.**


---

## Terrain & Virtual Texturing

### updateTerrainPrepare / updateTerrainPerform

**Prepares and executes terrain rendering updates (LOD transitions, texture streaming).**


---

### TerrainFeedbackJittered / TerrainFeedbackTiled

**Virtual texture feedback passes — determines which terrain texture tiles to load.**

Renders a feedback buffer that tells the texture streaming system which virtual texture tiles are needed at what resolution.


---

## Environment & Sky

### AdvSky / AdvSky/Compute

**Renders the advanced sky — skybox with atmospheric scattering (sky color, haze, glare). AdvSky/Compute is a background-thread step that tessellates the sky mesh and computes per-vertex scattering colors; it does no GPU rendering. Volumetric clouds are rendered separately (see Clouds / CloudsComp).**


---

### Clouds / CloudsComp

**Renders volumetric clouds.**

**Performance notes:** Can be expensive depending on cloud density and quality settings.


---

### EnvCapture

**Captures the environment map — renders a cube map for reflections.**

Periodically re-renders the environment for reflection probes.

**Performance notes:** Renders one face of the reflection cube map per invocation; the six faces are amortized across multiple frames (one face per frame).


---

## Mesh & Texture Management

### DynamicGeometryManager::processPendingRequests

**Processes pending geometry requests — loads/decodes mesh data for rendering.**

Processes queued EditableMesh updates (mesh edits submitted through the EditableMesh API) and uploads their vertex/index data to GPU buffers.


---

### DynamicGeometryManager::prepareMeshUpdates / prepareMeshUpdates::perEditableMesh

**Prepares mesh updates — processes EditableMesh changes and mesh LOD transitions.**


---

### DynamicGeometryManager::garbageCollectIncremental

**Incrementally garbage-collects unused mesh GPU resources.**


---

### DynamicGeometryManager::prepareConsumerUpdates / reallocateEditableMeshBinding

**Updates mesh consumer state and reallocates bindings for EditableMesh changes.**


---

### DynamicGeometryManager::transcodeVerticesAndCalculateBounds (and variants)

**Transcodes mesh vertices from asset format to GPU format and computes bounding boxes.**

Variants include: DynamicGeometryManager::transcodeBoxMappedVerticesAndCalculateBounds, DynamicGeometryManager::transcodeFaceFilteredVerticesAndCalculateBounds.


---

### TextureManager::processPendingRequests / DynamicTextureManager::prepareTextureUpdates / DynamicTextureManager::garbageCollectIncremental

**Texture management — loads textures, prepares updates, and garbage-collects unused textures.**


---

### MeshManager::processPendingRequests

**Processes pending mesh loading requests.**


---

### MeshJob

**Render-thread mesh upload — pops decoded mesh jobs from the upload queue and uploads their geometry to the GPU.**


---

### CheckAndGetAssets

**WrapDeformer (layered clothing) asset check — requests the WrapDeformer's body-part and cage meshes, initiating loading for any that are missing.**


---

## Fast Clusters & Instanced Rendering

### updateInvalidatedFastClusters

**Updates fast clusters that were invalidated (part moved, material changed, etc.).**

Fast clusters are the instanced rendering batches. When a part in a cluster changes, the cluster must be rebuilt.

**Performance notes:** Cost proportional to invalidated clusters. Frequent part property changes cause frequent rebuilds.

**What game creators can do:**
- Avoid changing Color/Material/Size of parts every frame
- Batch visual changes together
- Use BeamEffects or Particles instead of rapidly-changing parts


---

### BroadcastInvalidations

**Broadcasts rendering invalidations to all affected subsystems.**


---

## UI Rendering (within Render group)

### UpdateStyleQueries / UpdateUILayouts

**Updates CSS-like style queries and UI layout computations.**

**Performance notes:** Layout is expensive with deep or complex UI hierarchies. Cost scales with the number of GUI objects laid out and with the number and nesting of layout objects (`UIListLayout`, `UIGridLayout`, …) and constraints.

**What game creators can do:**
- Reduce the number of on-screen GUI objects; hide or remove UI that isn't currently visible.
- Flatten layout nesting — avoid a layout inside another layout where a single one would do.
- Use `AutomaticSize` only where it's actually needed (it adds measurement passes).
- Batch UI property changes into one frame instead of spreading them across frames — each change re-runs layout.
- Keep style rules and selectors simple (avoid deep descendant selectors).


---

### Pass2d / Pass3dAdorn

**Renders 2D GUI passes and 3D adornments (BillboardGuis, selection boxes, etc.).**

**Pass3dAdorn** renders 3D adornments — BillboardGuis and other labels above objects (Humanoid name/health labels), selection boxes, and debug adorns. For Humanoid labels that require line-of-sight, it raycasts to check whether the label is occluded. **Pass2d** readies 2D UI rendering (both player and Roblox UI).

**What game creators can do:**
- Reduce the number of visible adorned objects (BillboardGuis, Humanoid name/health labels)
- Reduce the number of visible parts
- Reduce the amount or complexity of UI elements


---

### AlwaysOnTopAdorns / CoreGuiAdorns / DebugAdorns / DebugAndEditAdorns

**Renders special adorn categories: always-on-top, core UI, debug, and edit mode.**


---

## Frame Lifecycle

### FrameRateManager::submitCurrentFrame

**Submits frame timing data to the Frame Rate Manager for adaptive quality decisions.**


---

### Present

**Presents the rendered frame — swaps the back buffer to the display.**

The final step that makes the rendered frame visible. May block if VSync is enabled and the GPU isn't done.

**Performance notes:** If Present is consistently wide, the application is GPU-bound (waiting for the GPU to finish). If it's consistently very fast, the application is CPU-bound.

**What game creators can do:**
- Reduce scene complexity; if Present is long, you may be GPU-limited


---

### waitUntilCompleted

**Waits for the GPU to finish rendering the previous frame.**

A sync point where the CPU waits for the GPU to complete the previous frame's rendering.

**Performance notes:** If this scope is wide, the application is GPU-bound — the GPU has not finished the previous frame's work.

**What game creators can do:** This is a *symptom*, not a cost in itself — the CPU is idle waiting for the GPU. Reducing CPU/script work won't help; reduce GPU load instead (see the GPU-group `Scene` scope): fewer transparent objects and less overdraw, simpler materials, and fewer/cheaper post-effects.


---

## Context / Low-Level

### Context::beginFrame / Context::endFrame() / Context::copyFramebuffer / Context::generateMipMaps / Context::resolveFramebuffer

**Low-level graphics context operations — frame boundaries and resource management.**


---

### uploadBufferData

**Uploads vertex/index/constant buffer data from CPU to GPU.**

**Performance notes:** Cost depends on data volume. High when many meshes change (EditableMesh, particles).


---

### RTPool::getRT

**Creates a new render target when the pool has no reusable match — used for off-screen rendering.**


---

### Copy / Copy Data / CopyTexture::LightMap / CopyTexture::Skylight

**GPU resource copy operations.**


---

## Highlights

### renderHighlightIdPass / renderMobileHighlightDepthMarkPass / renderMobileHighlightIdsPass

**Highlight system passes — renders object IDs for the Highlight effect.**


---

## Miscellaneous

### renderPerformanceOverlay

**Renders the performance debug overlay (light counts, draw call counts, etc.).**


---

### SortQueueJob

**Sorts the render queue on a worker thread.**


---

### meshTaskJobManager

**Terrain mesh generation job manager — generates terrain render meshes in the background.**


---

### TextureCompositorJob::update

**Updates the texture compositor — checks that all layer assets (meshes/textures) for avatar layered textures have loaded and updates their request priorities.**


---

### UITextureRenderer::renderJob / UITextureRendererBaseline::renderJob / UITextureJob::updateAndGetFramebuffer

**UI texture rendering jobs — renders off-screen UI textures (CanvasGroups, ViewportFrames).**


---

### EnvMapView::cullJob / EnvMapRaycastContext::raycastProcessingTask

**Environment map culling and raycast processing for reflections.**


---

### EditableImage::drawImageProjected / EditableMesh::updateRenderMesh / EditableMeshData::convertFileMeshDataToEditableMeshData / EditableMeshUpdateQueue::flushUpdates

**EditableImage and EditableMesh rendering updates — processes changes to editable assets.**

**Performance notes:** Frequent EditableMesh/EditableImage updates are expensive.

**What game creators can do:**
- Batch EditableMesh modifications
- Minimize per-frame pixel writes to EditableImage
- Use lower-resolution EditableImages


---

### FACSRigCFrameProvider::prepare / FACSRigCFrameProvider::update

**FACS (Facial Action Coding System) rig updates — face tracking data to bone transforms.**


---

### updateAvatarMemoryTracking / updateAvatarMemoryTrackingSummary

**Tracks avatar rendering memory usage for budget management.**


---

### updateEffectBoundings

**Updates bounding volumes for trail effects.**


---

### LightGrid::createCPU / LightGridCPU:: (variants)

**CPU-side light grid operations — computes lighting for the voxel-based light grid.**


---

### DM

**Syncs VR device state into the DataModel (VRService) — VREnabled and head/floor/hand UserCFrame poses each frame while VR is active.**


---

## Scene Update Details

### (Lookup)Build list of new tiles

**Diffs currently loaded virtual texture tiles against requested tiles and returns the list of new tiles to load.**


---

### BuildDeformedMeshPart

**Builds deformed mesh geometry for the wrap deformer system using target and cage vertices.**


---

### Dedup sampled chunks

**Deduplicates sampled terrain chunks to avoid redundant processing.**


---

### DrawBlockFilter

**Filters visible opaque blocks by render queue ID — removes already-rendered handles.**


---

### DynamicGeometryManager::prepareMeshUpdates::perEditableMesh

**Processes per-editable-mesh binding updates for all consumers.**


---

### DynamicGeometryManager::reallocateEditableMeshBinding

**Reallocates GPU buffers for editable mesh vertices and indices when size changes.**


---

### DynamicGeometryManager::transcodeBoxMappedVerticesAndCalculateBounds

**Transcodes box-mapped vertices from editable mesh format and calculates bounding volumes.**


---

### DynamicGeometryManager::transcodeFaceFilteredVerticesAndCalculateBounds

**Transcodes face-filtered vertices from editable mesh data and calculates bounds.**


---

### EditableMeshUpdateQueue::flushUpdates::perEditableMesh

**Updates the render mesh for each queued editable mesh modification.**


---

### EnvMapSampleRaycastStep

**Performs indoor raycasting for environment map sampling — determines room boundaries.**


---

### EnvMapUpdateStep

**Updates environment map with filtered raycast results to determine indoor/outdoor candidates.**


---

### FastCluster::finalizeSkinningAndEntities

**Clears the cluster's existing entities before new avatar-cluster geometry is generated.**


---

### FastCluster::finishUpdatingGeometry

**Completes geometry update and records telemetry for avatar loading state.**


---

### FastCluster::updateEntity

**Updates entity data, handles invalidations and failsafe avatar fallback.**


---

### FastCluster::updateGeometry

**Updates geometry for fast cluster avatars including skinning and asset loading.**

**Performance notes:** Rebuilds when an avatar's parts, meshes, or skeleton change; cost scales with the number of parts on the avatar and is re-triggered by runtime mesh changes, rescaling, and active layered-clothing deformation.

**What game creators can do:**
- Keep avatar/model part and accessory counts reasonable.
- Avoid changing avatar meshes or rescaling avatars at runtime — each forces a geometry rebuild; set them up once.
- Limit the number of layered-clothing items, which add deformation work to each rebuild.


---

### FastCluster::updateInstanceData

**Updates per-instance data (transforms, colors) for all fast cluster entities.**


---

### FillSubmitThreadData

**Fills submission thread data for multi-threaded GPU command submission.**


---

### Generate tile update commands

**Generates tile update commands from changed terrain tiles for virtual texturing.**


---

### GeometryGenerator::fetchResources

**Fetches geometry resources — loads file meshes and handles asset loading for parts.**


---

### GetBestTechniques

**Retrieves best rendering techniques/shaders for materials per pass based on capability flags.**


---

### HumanoidAdornRaycasts

**Performs raycasts to determine humanoid name/health bar visibility.**


---

### HumanoidHealth

**Renders the humanoid health bar GUI adornment above characters.**


---

### HumanoidName

**Renders the humanoid name plate GUI adornment above characters.**


---

### Image::scale

**Scales an image texture by resampling all mip levels to new dimensions.**


---

### InsertRenderQueue

**Inserts items from the render queue into the dispatch scene view for submission.**


---

### LightExtentsQuery

**Queries lights within spatial extents using the light octree spatial structure.**


---

### LightFrustumQuery

**Queries lights visible within a frustum using the light octree spatial structure.**


---

### LightGridCPU::updatePrepare

**Prepares CPU light grid updates each frame — activates lighting for global shadows, refreshes lighting technology/brightness settings, and selects which dirty chunks to update within the per-frame budget.**


---

### Octree::maintenance

**Performs spatial structure maintenance — validates nodes and rebalances the spatial tree.**


---

### RenderWorkspaceAdorns

**Renders 3D adornments for workspace content (selection boxes, handles, etc.).**


---

### StandardAdorns

**Renders standard adornments including humanoid name cache raycasts.**


---

### PlayerAdorns

**Renders 3D adornments for player GUI content.**


---

### SceneUpdater::checkFastClusters

**Checks fast clusters for geometry changes that require visual updates.**


---

### SceneUpdater::processPendingAttachments

**Processes newly added Attachment instances for rendering (beam/constraint anchors).**


---

### SceneUpdater::processPendingMegaClusters

**Processes newly added terrain chunks for rendering.**


---

### SceneUpdater::processPendingParts

**Processes newly added parts into instanced rendering clusters.**


---

### SceneUpdater::updateModelClusters

**Updates model-level clusters and removes empty ones.**


---

### WaitForRenderThread

**Waits for the render thread to complete frame rendering before proceeding.**

**Performance notes:** If wide, the render thread is still busy with GPU work from the current/previous frame.


---

### TransferControlToRenderThread

**Submits rendering work to the dedicated render thread for processing.**


---

### updateInvalidParts / updateWaitingParts

**Processes parts that were invalidated or are waiting for resource loading.**


---

### updateLightingAsyncTask

**Sequential per-chunk light-grid propagation on the calling thread, after the parallel occupancy pass has finished.**


---

### updateTerrainPrepareChangedChunks

**Identifies and prepares terrain chunks that changed since last frame for mesh regeneration.**


---

### updateUsedChunkMaterials

**Updates the set of materials used by visible terrain chunks.**


---

### updateWater / updateWaterMaterialConstants / updateWaterMaterialParams

**Updates water surface rendering state and shader parameters, plus terrain material constants (tiling/atlas/blend/emissive) for all terrain materials.**


---

### processGizmos

**Processes constraint and attachment gizmos (hover/selection state and detail display).**


---

### queryExtents / queryFrustum / queryFrustumOrdered / queryOcclusion

**Spatial queries: extent-based, frustum-based (ordered and unordered), and occlusion queries.**

**queryFrustumOrdered** applies frustum culling so objects not visible are not rendered.

**What game creators can do:**
- High cost means lots of elements — use larger meshes with more detail rather than many small pieces


---

### relocateGrid

**Relocates the light grid when the camera moves to a new region.**


---

### smoothClusterGetOrCreateChunk / smoothClusterMarkDirty

**Terrain rendering chunk management — creates chunks or marks them for regeneration.**


---

### Draw Tiles

**Draws virtual texture tile content into a staging texture (later copied into the atlas).**


---

### Edge Expansion

**Renders tile border expansion using radial shader to expand edges of virtual texture tiles.**


---

### Emitter estimated boundings

**Estimates bounding volumes for particle emitters for culling purposes.**

**Performance notes:** Recomputed for a particle emitter whenever its properties change; cost scales with the number of active particle emitters being (re)estimated in a frame.

**What game creators can do:**
- Reduce the number of active `ParticleEmitter`s; pool and reuse them instead of constantly creating new ones.
- Batch emitter property changes rather than changing them every frame — each change re-triggers a bounds estimate.
- Avoid continuously varying an emitter's motion properties (speed, acceleration, spread), which keep re-triggering estimation.


---

### FXCompositing

**Composites glow and sun rays effects: binds source, glow, and sun rays textures and renders a fullscreen compositing pass.**


---

### Generate Mips Custom

**Generates custom mipmap levels for font atlas textures through downsampling and copying passes.**


---

### HbaoRenderCompute

**Computes HBAO (Screen-space ambient occlusion) using compute shaders.**


---

### IndoorSkybox

**Renders a fallback indoor environment cubemap (per cube face) used as a reflection/image-based-lighting source for indoor areas — not a visible sky replacement.**


---

### InstanceGlob

**Performs GPU buffer uploads of instance data, handling both stable-slot path uploads and overflow entries via compute shaders.**


---

### LightGridCPU::LightGridCPU / LightGridCPU::updatePerform / LightGridCPU::updateChunksAsyncTask / LightGridCPU::updateChunkOccupancy

**CPU light grid lifecycle and update phases: construction, per-frame update, async chunk updates, and occupancy tracking.**

Updates the voxel lighting, which is used at lower quality levels.

**What game creators can do:**
- Reduce chunk occupancy (the amount of geometry occupying light-grid chunks)
- Use fewer lights
- Prefer non-shadow-casting geometry where shadows aren't needed


---

### LoadImage

**Loads and decodes an image file into a GPU texture.**

**What game creators can do:**
- Reduce the use of large images


---

### MaterialGenerator::garbageCollectIncremental

**Incrementally garbage-collects unused material GPU resources.**


---

### MeshReceived

**Processes a mesh asset that finished downloading — decodes and prepares for rendering.**


---

### MotionBuffer / MotionBuffer Fast Cluster Dispatch / MotionBuffer Instanced Cluster Dispatch / MotionBuffer update fast cluster movement / MotionBuffer update non fast cluster movement

**Motion vector generation for temporal effects — computes per-pixel motion for TAA, motion blur, and reprojection. Separate passes for fast clusters and instanced clusters.**


---

### OpenXrBeginFrame / OpenXrEndFrame / UpdateOpenXr

**OpenXR VR frame lifecycle — begins/ends the VR frame and updates tracking state.**


---

### Outline Effect

**Renders outline effects (Highlight instance outlines).**


---

### Parallel FastClusters

**Updates fast cluster rendering data in parallel across worker threads.**


---

### Parse and Layout RichText

**Parses rich text markup and computes layout for styled text content.**


---

### ParticleLighting

**Renders particle lighting via a lighting atlas: clears the atlas framebuffer, binds lighting resources, and draws particles as triangles to generate per-particle lighting.**


---

### Prepare2dWindow / PrepareBound / PrepareStandalone

**Prepares different window/surface types for rendering (2D window, bound surface, standalone).**


---

### ProcessUpdaterQueue

**Processes queued scene updater operations.**


---

### Processes Feedback / Processes Feedback (bypass)

**Processes virtual texture feedback requests — determines which tiles need loading. Bypass path skips when no feedback is available.**


---

### Profiler / ProfilerAdorn

**Renders the profiler UI and profiler adornments.**


---

### RaycastIndoorSingleRay / RaycastPointsClear

**Indoor environment raycasting for the PBR reflection probe: sampling rays to determine room boundaries, plus line-of-sight checks between two points.**


---

### Render feedback / RenderTiles

**Renders virtual texture feedback and tile content.**


---

### RenderView

**Renders one complete view (the main camera view or a secondary view).**


---

### Reproject

**Reprojects previous frame cloud data for temporal coherence: swaps cloud framebuffers and renders a reproject + filter pass.**


---

### SSAO / SSAOApply

**Screen-space ambient occlusion computation and application to the scene.**

**What game creators can do:**
- Reduce the number of post-processing effects; usually not significant


---


### SceneUpdater::invalidatePartMaterial

**Marks parts with material changes for shader/batch reassignment.**


---

### SceneUpdater::preparePerformUpdateCoordinateFrame

**Updates coordinate frame matrices for part transformation data.**


---

### ShadowMapSystem::updatePerform

**Performs shadow map rendering — the GPU-side shadow pass execution.**

Updates shadow maps. Skipped or reduced at lower graphics quality levels.

**What game creators can do:**
- Reduce the number of lights
- Use `Light.Shadows` and `BasePart.CastShadow` to disable shadow casting on less important instances


---

### Sort active chunks

**Sorts active terrain chunks by priority for rendering/streaming.**


---

### SunRaysBlur / SunRaysCompute / SunRaysDownSample

**Sun ray effect sub-passes: computes light shafts, blurs them, and downsamples for efficiency.**


---

### SwOcc main loop / SwOcc setup

**Software occlusion culling — rasterizes simplified occluders on the CPU to cull hidden objects before GPU submission.**

These are the top-level scopes for the software occlusion system. `SwOcc main loop` is the per-frame orchestrator and `SwOcc setup` prepares candidate occluders.

**Performance notes:** Runs on CPU threads and benefits scenes with high depth complexity. If these scopes are collectively wide, the scene has many potential occluders/occludees.


---

### Synthetic feedback

**Generates synthetic virtual texture feedback for tiles that weren't rendered but are needed.**


---

### Text Shaping+Layout / Typesetter::layout / Typesetter::shape / getHbFont / hb_shape

**Text rendering pipeline: font lookup, text shaping (glyph selection and positioning), and layout computation.**

**Performance notes:** Runs when text or its layout changes; cost scales with the amount of text shaped and with the number of separate font runs in a string (each distinct font is shaped separately).

**What game creators can do:**
- Reduce the total amount of on-screen text, and avoid re-setting `Text` every frame — each change re-shapes it.
- Update only what changes (e.g. a single number) rather than rewriting a whole label, so unchanged text isn't re-shaped.
- Minimize font changes within a single rich-text string; each distinct font becomes a separate shaping run.


---

### TextureAtlas::upload

**Uploads texture atlas data to the GPU.**


---

### TextureCompositor::render / TextureCompositor::update

**Composites layered textures (avatar clothing, decals) and updates compositor state.**


---

### TextureManager::loadImage / TextureManager::processTextureQualityChange

**Loads image textures and processes texture quality changes from the performance control system.**


---

### TreeTraversal

**Traverses terrain spatial structure for LOD chunk activation: processes destroy handles, updates chunks based on point of interest, and activates/deactivates chunks by camera distance.**


---

### UITextureRenderer::compositeUITextures / UITextureRendererBaseline::compositeUITextures / UITextureRendererBaseline::recurseDependencyTree

**Composites UI textures (CanvasGroups) and resolves their dependency trees.**


---

### UpSample / Upsample

**Upsamples a lower-resolution render target back up the mip chain: bloom (Glow) combines its blurred mip levels, and volumetric clouds upsample their half-resolution buffer.**


---

### UploadingMeshSizeBucketTelemetry / UploadingMeshTTMQTelemetry / UploadingMeshTimeToServeTelemetry / UploadingRenderFidelityTelemetry

**Telemetry scopes for mesh metrics: size distribution and time-to-serve of mesh uploads, plus render-fidelity (LOD/detail-level) analytics that are not upload measurements.**


---

### VertexStreamer::renderPrepare / WorldSpaceStreamer::renderPrepare

**Prepares streaming vertex data and world-space streamer for the render pass.**


---

### ViewportFrameSky

**Renders sky within ViewportFrame contexts.**


---

### VisibleQuery

**Performs a visibility query to determine which objects are in view.**


---

### VrSubmitFrame / vrPrepareFrame / waitVR / xrWaitFrame

**VR frame lifecycle — prepares, submits, and synchronizes VR frames.**


---

### WaitForLock

**Waits for a rendering lock to be released.**


---

### acquireFramebuffer / acquireSwapchains

**Acquires the framebuffer and swap chain images for the current frame.**


---

### add tile mips / applyMipResults / computeMipRequirements

**Virtual texture mipmap management — adds mip levels, applies results, and computes requirements.**


---

### asyncGrassTask / generateGrass / uploadGrass

**Grass rendering: generates grass geometry asynchronously and uploads to GPU.**


---

### blurRender

**Generic screen-space Gaussian blur pass used by post-processing effects (e.g. depth of field, bloom).**


---

### cameraOnHeartbeat

**Updates camera state on the heartbeat — drives constant-speed interpolation (Studio) and signals when a smooth transition is complete.**


---

### clear

**Clears invalidation event queue and merged invalidate events in dispatch scene.**


---

### computeUploadFull / computeUploadStaging / computeUploadStagingOverflow

**GPU compute upload passes — full upload, staging area, and overflow handling.**


---

### copyLockedContent

**Copy-on-write clone of voxelizer occupancy data when a write is needed while readers hold it.**


---

### copySkylight

**Copies combined skylight+sunlight data into a destination texture buffer for processing.**


---

### count covered pixels

**Counts how many feedback-buffer pixels each virtual texture tile covers, driving which terrain texture tiles to stream in.**


---

### destroyGeometry

**Destroys geometry resources that are no longer needed.**


---

### encodeDXT5 / encodeETC2

**Real-time texture compression — DXT5 (desktop) and ETC2 (mobile) formats.**


---

### endBatcher

**Completes instance handle batch upload and allocates buffer if needed.**


---

### filterRequests

**Filters pending terrain/mesh requests by priority and budget.**


---

### fitIntoMeshesBudget

**Manages mesh LOD promotion within video memory budget: assigns priorities, sorts, promotes LODs within budget, unloads lower priority, and applies requests.**


---

### gpuVoxelsPerform / gpuVoxelsPrepare / gpuVoxelsProcessChunkTableUpdates / gpuVoxelsProcessFeedback / gpuVoxelsProcessRequestedChunks / gpuVoxelsUpdateCompressedChunkPriorityQueue / gpuVoxelsUploadSubtree

**GPU voxel terrain system — prepares, processes feedback, updates chunk tables, handles requests, and uploads subtrees.**


---

### invalidateFailedResource

**Invalidates a resource that failed to load — marks it for retry or fallback.**


---

### lightingClearSkylightSunlightChunk / lightingComposit / lightingGetLights / lightingUpdateChunkGlobal / lightingUpdateChunkLocal / lightingUpdateChunkSkylight / lightingUploadChunk / lightingUploadCommit

**Light grid computation sub-phases: clears skylight data, composites lighting, computes shadow masks, gathers lights, updates chunks (local/global/skylight), updates individual light types, and uploads/commits results to GPU.**


---

### meshChunk / readChunk / readChunkBorder / readChunk_async / readTask

**Terrain mesh chunk operations — generates, reads, and processes terrain mesh chunks and their borders.**


---

### occupancyUpdateChunkPerform / occupancyUpdateChunkPrepare

**Updates light grid chunk occupancy — determines which grid cells contain geometry.**


---

### plantGrass

**Plants grass decoration geometry on terrain surfaces.**


---

### prepareProfiler

**Prepares profiler data for on-screen rendering.**


---

### processDestroyQueue

**Destroys terrain render chunks queued for teardown.**


---

### processTextureQuality

**Adjusts texture mip levels up or down each frame based on GPU memory pressure against configured budget thresholds.**


---

### queryFrustumEnvMap / queryResults / querySphere

**Reads back GPU timer-query results to compute the previous frame's GPU time.**


---

### queuePresent / submitAndFlip

**Queues the present operation and submits/flips the swap chain.**


---

### releaseResources

**Releases GPU resources that are no longer referenced.**


---

### remove overflow tiles

**Removes virtual texture tiles that exceeded the atlas capacity.**


---

### render2D / render3D

**VertexStreamer adorn rendering — render3D draws world-space adorn geometry; render2D draws screen-space adorn geometry via an orthographic camera.**


---

### requestMeshContent

**Applies pending mesh LOD requests within the memory budget — both unloading/evicting LODs and requesting new LOD downloads from the asset system.**


---

### resetCommandPool

**Resets the GPU command pool for reuse in the next frame.**


---

### sampleGpuCounters / sampleGpuCountersImplementation

**Samples GPU hardware performance counters.**


---

### sortUpdates

**Sorts pending updates by priority before processing.**


---

### synthesize tile requests

**Synthesizes virtual texture tile requests from visible renderables — the CPU fallback path used when the GPU feedback buffer is not consumed.**


---

### trimMemory

**Trims GPU memory by evicting low-priority resources.**


---

### updateChunk / updateChunkSkirtMasks

**Updates terrain rendering chunks and their skirt masks (LOD seam hiding).**


---

### updateDynamicObjectList

**Removes old dynamic object status after 32 frames by checking entry age.**


---

### updateLod / updateTransitionState

**Updates terrain LOD levels and transition blending state.**


---

### updateParticles / updateParticlesNonVisible / updateParticlesVisible / updateParticleBoundings

**Updates particle simulations — visible particles, non-visible particles (for streaming back), and their bounding volumes.**


---

### updatePlaneEffect

**Updates plane-based visual effects.**


---

### updateTerrainPrepareChangedChunksFilter

**Sorts the changed-terrain-chunk list by LOD and coordinate, then deduplicates it before preparation.**


---

### updateVR

**Updates VR-specific rendering state (head tracking, eye buffers).**


---

### uploadChunk

**Uploads a single terrain chunk's mesh data to the GPU (vertex/index buffers). Queue iteration is handled by the caller.**


---

### videoPresent

**Presents a video frame to the display.**


---

### waitOnGpu

**Synchronization points — waits for async worker thread or GPU completion.**

**Performance notes:** A wide wait means the CPU is idle waiting for something else to finish — most often the GPU (the frame is GPU-bound), sometimes a worker thread.

**What game creators can do:** This is a *symptom* of being GPU-bound, not a cost to optimize directly. Reduce GPU load (see the GPU-group `Scene` scope): fewer transparent objects and less overdraw, simpler materials, and fewer post-effects.


<br>
<br>

---
