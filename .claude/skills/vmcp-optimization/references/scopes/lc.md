# LC Group (Layered Clothing / Cage Deformers)

<!-- from github.com/Roblox/libmp/docs/ALL-SCOPES.md -->
The LC group contains scopes for the layered clothing (LC) and cage deformer system: mesh deformation for clothing layers, body wraps, and avatar shape customization. These scopes fire on the main thread and worker threads during avatar rendering preparation.

---

## Core Deformation

### deformBase

**Builds RBF deformation solutions for WrapDeformer-equipped parts in the base layer — computes how each body part's cage transforms from its rest pose to the deformed pose.**

Runs the core deformation algorithm for each avatar body part, producing the deformation field that will be used to deform the avatar body mesh.

**Performance notes:** Cost per avatar with layered clothing. More layers = more deformation work.

**What game creators can do:**
- Limit the number of layered clothing items per character
- Use fewer NPCs with full layered clothing in close proximity
- Characters far from the camera may have deformation LOD applied


---

### deformFileMeshData

**Deforms a file mesh (asset mesh) using cage data — reshapes a clothing mesh to fit the body.**

Applies the cage deformation to a specific clothing mesh asset, warping it to conform to the avatar's body shape.


---

### wrapDeformers

**Processes all WrapDeformer instances — applies layered clothing deformations.**

Iterates all active wrap deformers and applies their deformation stack.


---

### solvePose / solver / fitting

**Runs the layered-clothing deformation for one avatar — from pose setup through fitting the clothing to the body.**

The numerical solver that determines how clothing deforms to fit the body without interpenetration.


---

### finalSolution

**Computes the final solution for the deformation — output mesh positions.**


---

## Layer Processing

### createLayers / layer

**Creates and processes individual clothing layers in the deformation stack.**

Each piece of layered clothing is a separate layer. Layers are processed from inside out.


---

### createPieces

**Creates deformation pieces from the clothing mesh — segments the mesh for independent deformation.**


---

### expand / expand layer / puffines

**Expands clothing layers outward from the body — adds thickness and prevents interpenetration.**

"Puffiness" applies volume to thin clothing layers.


---

### target

**Builds the deformation field for body target parts — maps the original cage to the compressed cage positions so the body mesh deforms inward under clothing.**


---

## Mesh Operations

### createAlternateMeshes

**Creates deformed mesh for fitted layered clothing.**


---

### compress / compressBody

**Geometrically compresses stacked clothing layers — fits lower cage layers to the deformed upper layers so layers don't interpenetrate.**


---

### writeFileMesh

**Serializes a deformed layered-clothing mesh into the file-mesh format so it can be written to the persistent cache and evicted from memory.**


---

### serializeEvictableMeshes

**Serializes mesh data that can be evicted from memory and reloaded later.**


---

## HSR (Cage System)

### applyHSR

**Applies the HSR (Hidden Surface Removal) pass — removes body-mesh surfaces fully hidden beneath clothing layers so they aren't rendered.**


---

## System Operations

### Dispatcher::tick

**Ticks the deformation job dispatcher — processes queued deformation work.**


---

### SceneUpdater::forceUpdateAllExistingDeformers

**Forces every existing layered-clothing deformer to re-run in one pass.**

Runs when the scene is (re)prepared for a render — for example a capture or thumbnail pass — rather than during normal per-frame play.

**Performance notes:** Cost scales with the number of layered-clothing avatars, since every deformer is refreshed at once.


---

### invalidate instances

**Invalidates deformation instances that need recalculation (body shape changed, clothing added).**


---

### forceSyncUpdate

**Forces a synchronous (blocking) deformation update — waits for results immediately.**

**Performance notes:** Can stall the frame if deformation is complex. Normally, deformation is async.


---

### rbxStorageSet

**Stores deformation cache data in RbxStorage for persistence.**


<br>
<br>

---
