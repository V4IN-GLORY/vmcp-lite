# Navigation Group

<!-- from github.com/Roblox/libmp/docs/ALL-SCOPES.md -->
The Navigation group contains scopes for the PathfindingService navmesh system: navmesh generation (heightfield generation, region building, and mesh construction), tile management, and path computation. Navmesh work runs on dedicated worker threads; pathfinding queries may run on the main thread or parallel threads.

---

## Path Computation

### computePath

**Computes a navigation path from start to goal on the navmesh.**

The main pathfinding query. Searches the navigation mesh to find the shortest walkable path between two points. Returns a series of waypoints.

**Performance notes:** Cost depends on path length and navmesh complexity. Long paths across large navmeshes are expensive. Can spike when many scripts call `PathfindingService:CreatePath()` simultaneously.

**What game creators can do:**
- Cache paths and reuse them rather than recomputing every frame
- Limit pathfinding frequency (compute every 0.5-1 second, not every frame)
- Keep path distances reasonable (don't pathfind across the entire map)
- Reduce PathfindingModifier usage on large areas
- Reduce the number and world extents of `Path:ComputeAsync()` calls; reuse paths for multiple agents that start/end at approximately similar locations


---

## Navmesh Generation

Navmesh generation runs in the background when the world changes. These scopes fire on the navigation worker thread.

### navmeshWorkerFunction

**Main navmesh worker loop — processes dirty tiles and regenerates their navigation meshes.**

The background thread that processes the navmesh generation queue. Picks up dirty tiles (areas where geometry changed) and regenerates their navigation data.

**Performance notes:** Runs in the background and shouldn't block the main thread. However, heavy generation work can compete for CPU time with other threads.


---

### rasterizeTile

**Updates navigation tiles needed for a pathfinding request, usually followed by computePath which requires those tiles be up-to-date.**

Updates the navigation tiles required for a pathfinding request, converting the parts and terrain within a tile into a heightfield representation. Usually followed by `computePath`, which requires those tiles to be up-to-date.

**Performance notes:** Cost depends on the number and complexity of parts in the tile. Dense areas with many parts take longer.

**What game creators can do:**
- Reduce the number of pathfinding tile invalidations, as this causes those paths to need recomputing. This is caused by non-navigable parts moving.


---

### getDirtyTilesForRegion

**Identifies which navigation tiles overlap a changed region and need regeneration.**

When parts are added/removed/moved, this scope determines which tiles are affected.


---

## Rasterization Sub-Phases

### preprocessParts

**Preprocesses part geometry for rasterization — collects and transforms part shapes.**

Gathers all parts in the tile's bounds and prepares their collision geometry for the rasterizer.


---

### preprocessTerrain

**Preprocesses terrain for rasterization — extracts terrain geometry in the tile's bounds.**


---

### ReadingTerrainBox

**Reads terrain voxel data for a region — queries the terrain spatial structure.**


---

### TerrainMeshWork

**Converts terrain voxels to triangle mesh for rasterization.**


---

### getPrimitivesOverlapping

**Broadphase query — finds all physics primitives overlapping a pathfinding tile's bounds.**

Finds all physics primitives overlapping the tile bounds using broadphase queries.

**What game creators can do:**
- Reduce the part count


---

### rasterize / rasterize/triangleMesh / rasterize/Terrain

**Core rasterization — converts triangles and terrain into heightfield voxels.**

The core rasterization step that processes triangles and terrain cells. The most expensive per-tile step.

**Performance notes:** Cost proportional to triangle count × tile resolution.


---

## Navmesh Construction

### buildCompactHeightfield

**Builds a compact heightfield from the rasterized data — compresses the voxel grid.**

Converts the raw heightfield into a compressed representation that the region builder can work with.


---

### buildOffMeshConnections

**Builds automatic off-mesh connections — jump, drop, and climb links derived from the heightfield geometry.**

Generates the engine's automatic jump/drop/climb connections across gaps and ledges. Creator-defined `PathfindingLink` instances are added in a separate step outside this scope.


---

### buildRegions

**Builds navigable regions by flood-filling connected walkable areas.**

Groups connected walkable voxels into contiguous regions that will become navmesh polygons.


---

### buildContours

**Builds contour outlines of navigable regions — extracts region boundaries.**

Traces the edges of each region to create polygon outlines for the navmesh.


---

### buildPolyMesh

**Builds the polygon mesh from contours — creates the final navmesh triangulation.**

Triangulates the region contours into a polygon mesh suitable for pathfinding queries.


---

### buildNavMeshTiles

**Assembles the final navmesh tile from the polygon mesh — creates the runtime query tile data.**

Packages the generated navmesh into the runtime format for pathfinding queries.


<br>
<br>

---
