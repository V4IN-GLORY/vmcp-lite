# GPU Group

<!-- from github.com/Roblox/libmp/docs/ALL-SCOPES.md -->
All scopes in this file are **hardware GPU-timed** — they measure actual GPU execution time using hardware queries, not CPU submission time. They appear on the GPU timeline in the profiler.

Many GPU scopes have a corresponding "Render" group scope that measures the CPU-side cost of submitting the same work. When you see both in a capture, the Render scope shows how long the CPU spent preparing/submitting commands, and the GPU scope shows how long the GPU spent executing them.

---

## Scene Rendering

### Scene

**The main GPU scene render — draws the 3D scene (geometry with full shading), typically the dominant GPU cost in a frame.** The same `Scene` scope name is also emitted for the 2D screen-space pass (BillboardGuis and screen-space adornments) and, in VR, for each eye's scene render. (The CPU cost of submitting this pass is the Render-group `Scene` scope.)

**Performance notes:** GPU vertex- and pixel-shading plus fill cost. Driven mainly by:
- Shader/material complexity — PBR materials and SurfaceAppearance cost more per pixel
- Overdraw — transparent objects and layered decals shade the same pixels repeatedly and prevent early-Z rejection
- Render resolution and how much of the screen shaded geometry covers

**What game creators can do:**
- Minimize transparent objects and overlapping/layered transparency (the biggest overdraw source)
- Use simpler materials and lower detail for distant objects
- Prefer simpler materials where full PBR / SurfaceAppearance detail isn't needed
- Keep visible triangle counts reasonable for objects that cover a large part of the screen

---

### Scene2D

**2D screen-space rendering on the GPU — BillboardGuis, particles in screen space.**

---

### GuiScene

**ViewportFrame GPU rendering — each ViewportFrame gets its own GPU render pass.**

---

### UI

**GPU rendering of all 2D user interface elements.**

---

### Window

**GPU rendering of the application window content.**

---

## Depth Passes

### DepthPrePass

**GPU depth-only rendering — populates the Z-buffer for early rejection.**

---

### Depth / DepthMip

**GPU depth downsampling for SSAO — halves depth resolution before ambient-occlusion computation.**

---

### OpaqueWithAlphaDepthPass / OpaqueWithAlphaLateDepthPass

**GPU depth passes for alpha-tested materials (foliage, fences) — early and late variants.**

---

## Shadows

### ShadowMap / Shadows / Shadow Blur

**GPU shadow map rendering and filtering.**

---

### StencilMark

**GPU stencil marking for shadow map regions.**

---

### EVSM Scroll (Copy) / EVSM Scroll (Remap) / EVSM VBlur

**GPU shadow atlas management — scrolling, remapping, and vertical blur for soft shadows.**

---

### Convert into EVSM and HBlur

**GPU conversion of depth maps to shadow format with horizontal blur.**

---

### clearShadowAtlas / clearChart

**GPU clear operations for shadow atlas regions.**

---

### depthPass / depthCachePass / dispatchView / renderShadowQueue

**GPU shadow rendering sub-passes — depth rendering from the light's perspective (`depthPass`), cached depth reuse (`depthCachePass`), per-view dispatch (`dispatchView`), and submission of all shadow-caster geometry for one light (`renderShadowQueue`).**

---

## Post-Processing

### Glow / BlurFx / BlurX / BlurY / blurRender

**GPU bloom and blur effects — multi-pass multi-pass blur.**

---

### DOF / Depth of Field / Bokeh Blur / Optimized Bokeh Full Resolution / Resolve Depth of Field Full Resolution

**GPU depth-of-field computation — blur based on depth distance from focus plane. Bokeh variants for high-quality circular blur shapes.**

---

### SunRays / SunRaysBlur / SunRaysCompute / SunRaysDownSample

**GPU god ray effect — radial blur from sun position, with downsample and blur passes.**

---

### ColorCorrection / Image Composition / FXCompositing

**GPU post-process compositing — `ColorCorrection` and `Image Composition` apply tonemapping and color grading, while `FXCompositing` composites the glow and sun-rays buffers.**

---

### SSAO / SSAOApply / Hbao PS / HbaoRenderCompute / Blur & upsample AO

**GPU ambient occlusion — computation, application, and blur/upsample passes.**

---

### Eye

**GPU per-eye scene render in VR — times the full scene render pass for one stereo eye (multiview or split-stereo).**

---

### MotionBuffer / MotionBuffer Fast Clusters / MotionBuffer Instanced Clusters / MotionBufferASW

**GPU motion vector rendering for temporal effects — separate passes for fast clusters and instanced clusters. ASW variant for VR reprojection.**

---

### Reproject / Reproject & filter

**GPU temporal reprojection — `Reproject` reprojects the previous frame's volumetric cloud data, while `Reproject & filter` reprojects and filters the previous frame's ambient-occlusion (SSAO) result for temporal stability.**

---

### Accum

**GPU accumulation pass in clustered light culling — accumulates per-froxel light visibility into the light grid.**

---

## Lighting

### FroxelGrid

**GPU clustered light culling — assigns lights to froxel tiles for efficient forward rendering.**

---

### ParticleLighting

**GPU particle lighting via a lighting atlas — draws particles as triangles to compute per-particle light contribution.**

---


## Sky & Environment

### AdvSky / Sky / Clouds / CloudsComp

**GPU atmospheric sky rendering and volumetric cloud computation.**

---

### EnvCapture / EnvMap / Generate Reflection / PrefilterSpecular

**GPU environment map capture (`EnvCapture`/`EnvMap`) and specular prefiltering (`PrefilterSpecular`); `Generate Reflection` is separate and generates the volumetric-clouds reflection texture.**

---

### IndoorSkybox

**GPU indoor skybox rendering — renders environment map faces converting sRGB to linear.**

---

### ViewportFrameSky

**GPU sky rendering within ViewportFrame contexts.**

---

## Terrain & Virtual Texturing

### TerrainFeedbackJittered / TerrainFeedbackTiled

**GPU virtual texture feedback — determines which texture tiles are needed at what resolution.**

---

### Draw Tiles / RenderTiles / Compress Tile

**GPU virtual texture tile management — renders and compresses the texture tiles for the material/terrain virtual texture.**

---

### Edge Expansion

**GPU virtual texture tile border expansion — expands tile edges to prevent seam artifacts between tiles.**

---

## Compute & Post-Processing Passes

### Compute

**GPU screen-space ambient occlusion (SSAO) buffer computation pass.**

---

### computeUploadFull / computeUploadStaging / computeUploadStagingOverflow

**GPU upload of per-instance transform/object data into the instance buffer — a full re-upload path, an incremental staging path, and a staging-overflow path.**

---

### Average tiles / Spread tiles / Spread vertical / Edge Fatten

**GPU Depth-of-Field near-field passes — average and spread the Circle-of-Confusion map, and fatten edges to hide disocclusion artifacts. (Tile here refers to DOF work tiles, not virtual-texture tiles.)**

---

### Count offsets

**GPU clustered-lighting step — counts the per-froxel light-list offsets while assigning lights to froxels (part of froxel light culling).**

---

## Resolution & Depth Management

### DownSample / UpSample / Upsample

**Shared post-processing downsample/upsample passes.** `DownSample`/`UpSample` are reused across the bloom/glow pipeline: `DownSample` builds the glow mip chain and also produces reduced-resolution buffers in the post-FX composite/tonemap stage; `UpSample` recombines the glow mip chain. The separate lowercase `Upsample` is the volumetric-clouds half-resolution upscale. They are not a single subsystem — the same scope names are emitted from different post-process passes.

---

### Upscale SmootherStep / Upscale Lanczos / Upscale Linear

**GPU upscaling algorithms for final image output.**

---

### Linearize Depth to color target / Linearize full resolution depth / Linearize half resolution depth

**GPU conversion of non-linear Z-buffer to linear depth for effects that need it.**

---

### Capture Depth to R32F

**GPU depth buffer capture into R32F format texture.**

---

### Downsample & mask 1/4th or 1/2  / Downsample & mask 1/4th or 1/2 width

**GPU depth-of-field preparation — downsamples and masks at quarter/half resolution.**

---

### Extract Alpha and spread width wise

**GPU DOF alpha extraction and horizontal spreading.**

---

### Copy and Compute CoC Full Resolution

**GPU computes Circle of Confusion at full resolution for depth-of-field.**

---

## Copy & Clear Operations

### Clear / ClearColor / ClearColorCmask / ClearDepthStencil / ClearTexture / Context::clearFramebuffer

**GPU clear operations: `ClearColor`/`ClearColorCmask` clear color render targets, `ClearDepthStencil` clears depth/stencil, `ClearTexture` clears textures, and `Context::clearFramebuffer` clears the framebuffer; `Clear` clears the clustered light-culling buffers via a compute pass.**

---

### Copy / Copy Color / Copy Color Full Resolution / Copy from Scratch

**GPU resource copy operations between render targets.**

---

### CopyTexture::LightMap / CopyTexture::Skylight

**GPU copies of light map and skylight texture data.**

**Performance notes:** Fires when lighting/skylight data is recomputed and re-uploaded; cost scales with how much of the light data changed — driven by dynamic lighting and skylight / time-of-day changes.

**What game creators can do:**
- Keep lighting static where possible — moving, adding, or removing lights forces light-texture re-uploads.
- Avoid rapid or continuous skylight / time-of-day changes; step them less often rather than every frame.

---

### ResolveColor / msaaResolveFrameBuffer / Software Depth Resolve

**GPU MSAA resolve — converts multi-sample targets to single-sample. Software depth resolve for platforms without hardware resolve.**

---

## Normal & Spatial

### Gen Normals / Sample World Pos

**`Gen Normals` generates normals for screen-space effects; `Sample World Pos` is a debug tool that samples the depth buffer to compute a single world-space point on demand (not a per-frame pass).**

---

### Dilate Temporal

**GPU SSAO temporal-stability pass — spreads less-stable areas of the ambient-occlusion result so moving objects get fresh AO values.**

---

### Gather

**GPU light-culling gather pass — assigns visible lights into the clustered light-grid tiles.**

---

## Instanced Rendering

### InstanceGlob

**GPU buffer uploads of instance data — handles stable-slot uploads and overflow entries via compute shaders.**

---

### TextureCompositor::render

**GPU texture compositing — layers avatar clothing and decal textures.**

---

### gpuCompress

**GPU real-time texture compression for dynamically generated textures.**

---

### Generate Mips Custom

**GPU custom mipmap generation for font atlas textures through downsampling passes.**

---

## Highlights

### Outline Effect

**GPU highlight outline computation with color LUT and MSAA handling.**

---

### renderHighlightIdPass / renderMobileHighlightDepthMarkPass / renderMobileHighlightIdsPass

**GPU highlight ID rendering for the Highlight instance effect (desktop and mobile variants).**

---

## Miscellaneous

### MSAA

**GPU MSAA resolve pass.**

---

### AlwaysOnTopAdorns

**GPU rendering of always-on-top adorns into the resolved color buffer, after bloom sampling but before image composition.**

---

### PerformanceOverlay

**GPU performance debug overlay rendering.**

---

### WaitUntilSafeForRendering

**GPU fence wait — ensures previous frame work is complete before starting new frame.**

---

### Dispatch / Cull / CullCPU

**GPU command dispatch, GPU-side culling, and CPU-side culling fallback.**

---

### UITextureRenderer::renderJob / UITextureRendererBaseline::renderJob

**GPU off-screen UI texture rendering for CanvasGroups.**

---

### Capture Depth to R32F / Context::clearFramebuffer

**GPU operations: captures the depth buffer to R32F format and clears the framebuffer via the graphics context.**


<br>
<br>

---
