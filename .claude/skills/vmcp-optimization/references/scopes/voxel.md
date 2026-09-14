# Voxel Group

<!-- from github.com/Roblox/libmp/docs/ALL-SCOPES.md -->
The Voxel group contains scopes for the Smooth Terrain voxel system: reading/writing terrain data, LOD management (downsampling/upsampling), serialization, geometry generation for rendering, and terrain editing operations. Terrain operations run on both the main thread and worker threads.

---

## Reading & Writing

### read / read_vjm

**Reads voxel data from the terrain spatial structure for a given region.**

Fetches terrain cell data (material, occupancy) from the internal storage. The `vjm` variant uses the Voxel Job Manager path.

**Performance notes:** Fast for small regions. Cost proportional to the number of cells read.


---

### write

**Writes voxel data into terrain storage — the low-level write used both for terrain edits and for the writes that occur when terrain is loaded or streamed in.**

Applies terrain writes to the internal storage: player/script edits (fill, dig, paint) as well as writes produced when terrain data is loaded from a place or streamed in. Triggers invalidation of affected LOD levels and rendering geometry.

**Performance notes:** Fast per-cell. Batch writes are efficient. Triggers downstream work (LOD rebuilds, mesh regeneration).

**What game creators can do:**
- Batch terrain edits into fewer `WriteVoxels` calls
- Avoid modifying terrain every frame
- Use larger brush sizes instead of many small edits


---

### readRegionEmptyLod0

**Reads a terrain region, returning quickly if LOD0 shows the region is empty.**

Optimized read path that can early-exit when the finest LOD level indicates no terrain exists in the region.


---

## LOD Management (Downsampling/Upsampling)

### downsample / downsampleAll / downsampleAllVJM

**Downsamples terrain data to coarser LOD levels.**

Coarser LODs are produced in two situations: when terrain is modified at the finest level (so the coarser LODs reflect the change), and on demand when a region is read at a coarser LOD than is currently stored. This scope generates the lower-resolution representations.

**Performance notes:** Cost proportional to the affected region size. Large terrain edits trigger more downsampling.


---

### downsampleSdf

**Downsamples the SDF (Signed Distance Field) representation of terrain.**


---

### asyncDownsample / asyncUpsample

**Deferred, time-budgeted terrain LOD operations (downsampling / upsampling).**

Run from the terrain DataModel job with a per-frame time budget, so a large LOD backlog is spread across frames rather than done all at once. "async" here means budgeted/deferred, not a separate background thread.


---

### asyncDestroy

**Asynchronously destroys terrain data for regions that have been cleared.**


---

### rebuildAllLods

**Rebuilds all LOD levels from scratch — expensive full-terrain LOD regeneration.**

Called after major terrain topology changes or when loading a place.

**Performance notes:** Very expensive. Should only happen on place load or major terrain operations.


---

## SDF Operations

### compressedToSdf / sdfToCompressed / packSdf / unpackSdf

**Converts terrain between compressed storage format and SDF (Signed Distance Field) representation.**

The terrain system stores data in a compressed format internally but operates on SDF for smooth surface computation.


---

### unclampSdfBox / unclampSolid / unclampWater

**Unclamps SDF values for specific material types — restores full-range values from clamped storage.**


---

### upsampleCompressed / upsampleSolid

**Upsamples compressed terrain data to finer resolution levels.**


---

## Geometry Generation

### generateGeometry / generateGraphicsGeometry

**Generates triangle meshes from terrain voxel data for rendering.**

Generates renderable triangle meshes from terrain data.

**Performance notes:** One of the more expensive terrain operations. Cost proportional to the number of terrain cells that need mesh regeneration.


---

### generateGraphicsGeometryPacked / generateShadowGeometryPacked / generatefeedbackGeometryPacked

**Generates packed geometry for different render passes: main rendering, shadow maps, and virtual texture feedback.**

Optimized geometry generation for specific purposes (shadow geometry is simpler, feedback geometry is lower-resolution).


---

### compactMeshVertices

**Compacts mesh vertex arrays — removes unused vertices after geometry generation.**


---

### addEdges

**Builds the per-face edge-to-triangle adjacency map used to group terrain surface triangles into UV islands during texture unwrapping.**


---

## Spatial Structure Operations

### growOctree

**Adds another level to the terrain octree (increasing its depth) so it can hold coarser LOD levels.**

Expands the spatial data structure to accommodate terrain in a new area.

**Performance notes:** Rare but expensive when it happens. Triggers memory reallocation.


---

### isEmpty

**Checks if a terrain region is empty (no non-air cells).**

Fast early-exit check used by many operations.


---

### isHighLod / getAvailableNonEmptyLod

**Queries the LOD state of terrain regions.**


---

### getCellLevel / getNonEmptyIds / getNonEmptyRegions / getNonEmptyRegionsInside

**Spatial queries on the terrain structure — finds non-empty cells or regions.**


---

## Serialization

### serialize / serializeTerrainRegion / deserialize

**Serializes/deserializes terrain data for saving, networking, or streaming.**

Converts terrain data to/from wire format for replication or file storage.

**Performance notes:** Cost proportional to terrain volume being serialized.


---

### unzipCells

**Decompresses terrain cell data from compressed storage.**


---

## Terrain Editing Operations

### erase / eraseHigherResolution

**Erases terrain — sets cells to air material.**

`eraseHigherResolution` additionally clears finer LOD data that may exist above the erased level.


---

### sweep

**Runs the fast-sweep pass that propagates signed-distance-field values across the terrain voxel grid (part of unclamping SDF data for surface meshing/LOD).**


---

### processModifyOperations / processModifyWrite / processReadOperations

**Processes batched terrain modification and read operations from the job queue.**

The terrain system queues operations and processes them in batches for consistency.


---

## Texture Unwrapping

### getUnwrapData / getUnwrapDataHeightmap / getUnwrapDataOriented

**Generates texture unwrapping data for terrain — computes UV coordinates for virtual texturing.**

Calculates how terrain surface textures should be mapped. Used by the virtual texture system.


---

### placeUnwrappedCharts / buildAtlasTris

**Packs unwrapped texture charts into the atlas and builds atlas triangle data.**


---

## Miscellaneous

### GridJob

**The main terrain grid processing job — coordinates all per-frame terrain work.**

Top-level scope for the terrain worker thread's frame processing.


---

### On Fragment Loaded

**Processes a terrain fragment that has finished loading from disk or network.**


---

### Decode PBC Chunk

**Decodes a PBC (Packed Binary Chunk) of terrain data received from the network.**


---

### UpdateRegionChangeListeners

**Notifies listeners about terrain region changes (rendering, physics, streaming).**


---

### approximateRegionAtLevel

**Computes the bounding region (AABB) enclosing all terrain chunks present at a given LOD level.**


---

### fixupLimits

**Corrects sharp SDF transitions during unclamping — converts adjacent full/empty (±max) voxel pairs into ±0.5 boundary values.**


<br>
<br>

---
