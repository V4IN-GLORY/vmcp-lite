# Shadows Group

<!-- from github.com/Roblox/libmp/docs/ALL-SCOPES.md -->
The Shadows group contains scopes for the shadow mapping system: frustum computation, caster gathering, culling, atlas management, and rendering. Shadow work runs on the main thread (preparation) and worker threads (culling, rendering).

---

## System-Level

### ShadowMapSystem::updatePrepare

**Top-level shadow system update — prepares all shadow maps for the current frame.**

Updates the frame's shadow distance parameters and the sun and terrain light descriptors (direction, distance, softness). Atlas allocation, frustum building, culling, and rendering happen in separate scopes later in the frame.

**Performance notes:** If consistently wide, the scene has too many shadow-casting lights or too many shadow casters. Parts cast shadows regardless of transparency, under the assumption they may contain decals. Shadow recalculation is reduced or skipped at lower graphics quality levels.

**What game creators can do:**
- Reduce the number of lights with `Shadows = true`
- Increase `Lighting.ShadowSoftness` to reduce resolution needs
- Reduce `Lighting.ShadowDistance` to limit shadow range
- Use fewer shadow-casting PointLights/SpotLights (they each need 6/1 shadow maps)


---

### ShadowMapSystemNew

**Alternate shadow map system entry point.**


---

## Shadow Object Types

### ShadowObjectDirectional / ShadowObjectDirectionalNew

**Updates the directional light (sun) shadow cascades.**

Computes cascade frustums and updates shadow maps for the sun. Multiple cascades provide detail close to the camera and coverage far away.

**Performance notes:** Directional shadows are the most common and often the most expensive shadow type. Cost depends on cascade count, resolution, and caster count.


---

### ShadowObjectPoint / ShadowObjectPointNew

**Updates a point light shadow map (6-face cube map).**

Point lights require rendering the scene 6 times (one per cube face) for omnidirectional shadows.

**Performance notes:** Very expensive — 6× the cost of a single shadow map. Limit point light shadows.

**What game creators can do:**
- Use SpotLights instead of PointLights where possible (1 map vs 6)
- Reduce point light shadow range
- Limit the number of shadow-casting PointLights to 1-2


---

### ShadowObjectSpot / ShadowObjectSpotNew

**Updates a spot light shadow map (single frustum).**

Spot lights only need one shadow map (a single frustum projection).

**Performance notes:** Cheapest local light shadow type. One frustum, one render pass.


---

## Frustum & Cascade Management

### buildFrustums / TerrainShadow::updateFrustums / Merge frustums

**Computes and merges shadow frustums for cascade shadow maps.**

Determines the view volume each cascade covers, accounting for camera position and shadow distance.


---

### allocateAndBuildViewports / allocateDispatchViewsSpawnCullJobs

**Allocates atlas viewport space for each shadow map and spawns parallel culling jobs.**


---

### invalidatePerformCascades / invalidatePerformLights

**Marks shadow data as invalid when lights or geometry change, triggering re-render.**


---

### tiledScrollAtlasChart

**Scrolls the shadow atlas when the camera moves — reuses existing shadow data where possible.**

The shadow atlas uses tiled scrolling to avoid re-rendering the entire shadow map when the camera moves slightly.

**Performance notes:** Efficient reuse mechanism. Only new regions need rendering.


---

## Caster Gathering

### Get shadow casters / getPotentialShadowCasters

**Gathers all objects that cast shadows within the shadow frustum.**

Queries the scene's spatial structures to find objects that are within shadow-casting range.

**Performance notes:** O(objects in range). Large shadow distances with many objects increase cost.


---

### Filter cascade casters / Sort cascade casters / Fill casters / Fill tiled casters

**Filters, sorts, and fills the caster list for each cascade — determines which objects to render into each cascade's shadow map.**


---

### buildVisibleShadowObjectsList

**Builds the list of shadow-casting lights that are actually visible, then priority-sorts them (nested 'Priority sort' scope) so nearer/larger lights are updated first.**


---

## Culling

### Perform culling / Precise culling / Spatial culling

**Culls shadow casters against the shadow frustum — determines which actually contribute to shadows.**

Multiple culling phases: broad spatial culling followed by precise per-object culling.


---

### ShadowCullJob

**Worker thread shadow culling job — tests objects against shadow frustums in parallel.**

**Performance notes:** Runs on worker threads. Cost proportional to caster count.


---

### TileClassification

**Computes, per shadow caster, which atlas tiles the caster overlaps (tile coverage bitmasks). The re-render-vs-reuse decision happens later in 'Fill tiled casters'.**


---

## Rendering

### depthPass / depthCachePass

**Renders objects into the shadow map depth buffer.**

The actual shadow rendering pass — draws geometry from the light's perspective to generate depth.

**Performance notes:** Cost proportional to caster triangle count × shadow resolution.


---

### dispatchView

**Dispatches one shadow view's render commands to the GPU.**


---

### renderShadowQueue

**Submits the shadow render queue to the GPU — all shadow draw calls for one light.**


---

### updateFrustumRenderQueue

**Updates the render queue for a specific shadow frustum.**


---

## Blur & Filtering

### horizontalBlur / verticalBlur

**Shadow map blur passes — multi-pass blur for soft shadows.**

Shadows use multi-pass blur for smooth penumbra (shadow edge softness).


---

## Sorting & Priority

### Sort / Priority sort / Priority sort throttling

**`Sort` orders each shadow render-queue by material and index buffer to reduce GPU state changes (a draw-order sort). `Priority sort` orders shadow casters by distance/priority to decide which get updated, and `Priority sort throttling` caps how many are updated per frame.**

The shadow system can throttle lower-priority shadow maps (update them less frequently) to save performance.


---

## Legacy

### LegacyRenderNodes

**Prepares sun-shadow casters for the legacy (non-new-pipeline) code path — gathers and culls shadow casters against the cascade frustums and updates the per-cascade shadow frustums.**

Issues no draw calls; it collects visible casters, sorts them for stable timestamp hashing, computes cascade/frustum timestamps, and creates or reuses (caches) the cascade shadow frustums for later rendering.


---

### drawFrustums

**Allocates atlas viewports and builds the frustum update list, then dispatches the per-frustum shadow draw passes into the shadow atlas.**


<br>
<br>

---
