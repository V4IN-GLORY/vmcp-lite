# Network Group

<!-- from github.com/Roblox/libmp/docs/ALL-SCOPES.md -->
The Network group contains scopes for the replication system, instance streaming, join flow, packet processing, and bandwidth management. These scopes fire on the main thread (replication step) and on network worker threads (packet deserialization, HTTP).

---

## Replication Pipeline (MegaReplicator)

The MegaReplicator orchestrates all replication work each frame. These scopes run sequentially within the network step.

### Force World Assemble

**Forces all pending physics assemblies to be assembled before replication.**

Ensures the physics world is in a consistent state before replicating positions and velocities to clients.

**Performance notes:** Normally fast. Can spike after large batches of part additions.


---

### PrepopulateMRDs

**Pre-populates MegaReplicator Descriptors for new instances that need replication.**

Sets up the replication metadata for newly-created instances so they can be sent to clients.

**Performance notes:** Cost proportional to new instances per frame.


---

### RaiseCompleteness

**Propagates completeness state through the instance hierarchy — determines what clients can see.**

Completeness tracks which portions of the instance tree are fully replicated to a client. This scope propagates "complete" marks up the tree.

**Performance notes:** Can be expensive during initial join when large hierarchies become complete.

**Labels:** `"Completeness expected raised X/Y"` — shows how many instances had completeness raised vs total.

---

### Updating Mega World Extents

**Updates the spatial bounds of the replicated world for streaming calculations.**

Recalculates the bounding box of all streamable content to help the streaming solver determine what to send.


---

### Prepare Physics Rep Assembly List Sync

**Synchronizes the physics replication assembly list with the current world state.**

Ensures the list of physics assemblies that need replication matches what actually exists in the physics world.


---

### SharedQCleanUp

**Cleans up the shared replication queue — removes completed or expired items.**

Garbage-collects items from the shared data queue that have been sent to all relevant clients.

**Performance notes:** Normally fast. Can accumulate work if many items expire simultaneously.

**Labels:** `"SharedQueue: X (will clean up: Y)"` and `"Eligible Cleanup Items breakdown"` — shows queue size and cleanup volume.

---

### Deferred MotorAngles update

**Applies previously received, deferred Motor6D angle updates to the physics world (receive side).**

Runs in the physics receive job: iterates the deferred motor-angle entries and writes them onto each assembly's physics state. This is a receive-side application step, not a send-side batching step.


---

### GenerateJDIv2

**Generates Join Data Items v2 — prepares replication data for the join snapshot.**

Creates the data packets that form the initial state snapshot sent to newly-joining clients.

**Performance notes:** Expensive during player joins. Cost proportional to world size.


---

### Detect Join-Batchable Replicators

**Identifies replicators that can be batched together during join for efficiency.**

Groups related replication items that can be sent in a single batch rather than individually.


---

### Prebuild join cache

**Pre-builds cached data for the join snapshot to speed up subsequent joins.**

Caches serialized data that doesn't change between joins so it doesn't need re-serialization.


---

### ISR Update Timestamp Offsets

**Updates Instance State Replicator timestamp offsets for clock synchronization.**

Adjusts timestamps to account for clock differences between server and clients.


---

### Dispatch ISR Prep And Send

**Dispatches the ISR (Instance State Replicator) preparation and sending phase.**

The ISR handles fine-grained property replication. This scope prepares and sends property updates.

**Performance notes:** Cost proportional to the number of dirty properties this frame.


---

### Update and allocate bandwidth

**Allocates available network bandwidth to replicators based on priority.**

Distributes the frame's bandwidth budget across all pending replication items, prioritizing important data.


---

### Replicator Status Checks

**Checks replicator connection health — detects disconnects and timeout conditions.**


---

### Assign Network Object Priorities

**Assigns priorities to network objects based on distance, relevance, and importance.**

Determines which objects get bandwidth first based on their proximity to players, visibility, and game importance.

**Performance notes:** O(replicated objects). Can be expensive in large worlds.


---

### LR Pull Manager Notify / LR Pull Manager Generate

**Large Replicator pull manager — notifies and generates large data transfers.**

Handles the "pull" protocol for large objects that are requested by clients rather than pushed by the server.


---

### Dispatch Data Senders

**Dispatches all data sender tasks — sends queued replication data to clients.**

The main data sending phase. Iterates over all connected clients and sends their pending replication data. Sends property changes, remote event invocations, Humanoid state changes, animation state changes, and replication of new instances.

**Performance notes:** Cost = (connected players) × (data per player). The primary network bandwidth consumer.

**What game creators can do:**
- Reduce the number of replicated changes to the data model

**Labels:** `"Connected Players : X"` refers to the total number of players who finished joining the game, and `"Pending Players : X"` refers to the total number of players currently joining the game. These are frame-level Network labels emitted once per network step, not inside this scope.

---

### Send clusters

**Sends terrain data to clients.**

Serializes and sends terrain voxel data that clients need but don't have yet.

**Performance notes:** Expensive when players move into new terrain areas that haven't been streamed yet.

**What game creators can do:**
- Reduce the amount or size of terrain changes


---

### Cluster: insufficient buffer to send

**Diagnostic scope — fires when a cluster's data exceeds the send buffer.**

Indicates that terrain data is too large for the current buffer allocation.


---

### Dispatch PhysicsSenders and TouchSenders

**Sends physics state updates (positions, velocities) and touch events to clients.**

The physics replication sending phase. Sends CFrame/Velocity data for moving objects. This will soon be deprecated as Roblox transitions to use `ISRSendStep` to replicate physics data.

**Performance notes:** Cost proportional to moving physics objects × connected clients.

**What game creators can do:**
- Reduce the amount of moving objects and/or touches


---

### CompletenessPropagation / CompletenessFinalization / CompletenessUpdateExpectedChildren

**Multi-phase completeness state propagation and finalization.**

Propagates the completeness state through the instance tree and finalizes it for this frame.


---

### Preserialize network streams

**Pre-serializes network data streams — encodes data ahead of the send phase.**

Serializes replication data into the wire format before the actual network send. This allows serialization to happen separately from I/O.

**Performance notes:** CPU-bound serialization work. Cost proportional to data volume.

**Labels:** `"Items to preserialize : X"` — shows the work volume.

---

### Data Senders / Send Item

**Sends individual replication items to a specific client.**

Per-item, per-client send operation.


---

### Sending Globals / Sending Network Schema

**Two distinct join-flow scopes: `Sending Globals` sends global setup data to a newly-joining client; `Sending Network Schema` sends the serialization schema.**

Part of the join flow. `Sending Network Schema` transmits only the serialization schema (so the client can decode future messages), while `Sending Globals` transmits initial global setup data — the two are separate operations.


---

## Streaming System

### Dispatch StreamJob

**Dispatches the streaming job — determines what to stream in/out based on player position.**

The main streaming orchestrator. Calculates which instances should be streamed to or from each client based on their focus position and streaming radius.

**Performance notes:** Cost depends on world size and streaming density. Runs every frame on the server.

**What game creators can do:**
- Lower `Workspace.StreamingTargetRadius` — the main lever for streaming workload (`StreamingMinRadius` is the always-loaded floor that never streams out, so lowering it mainly reduces resident content rather than this dispatch cost)


---

### StreamJob

**The actual streaming computation — priority-based instance streaming decisions.**

Computes streaming priorities and makes send/remove decisions for each client's stream region.

**Performance notes:** Can be expensive in large worlds with many streamable instances.

**What game creators can do:**
- Set appropriate `StreamingMinRadius` and `StreamingTargetRadius` on Workspace
- Use `ModelStreamingMode` to control per-model streaming behavior
- Reduce the total number of instances in the workspace


---

### StreamingSolverV2

**The streaming solver — spatial computation for which instances are in range.**

Uses spatial data structures to efficiently determine which instances fall within each player's streaming radius.


---

### InstanceObjectManager

**Manages instance lifecycle for streaming — creates/destroys instances as they stream in/out.**

Handles the actual creation and teardown of instances on the client as they enter or leave the streaming radius.


---

### Replication Foci Streaming / Foci and Set Changes / Refresh Tracked Location

**Manages streaming focus points — where each client is "looking" for streaming purposes.**

Updates the spatial positions that define each client's area of interest.


---

### StreamingObserver processBatchedSetMoves / StreamingObserver sets change

**Processes batched set membership changes in the streaming observer.**

Handles instances moving between streaming sets (e.g., entering/leaving a client's radius).

**Performance notes:** Server-side. Cost scales with how many instances move across streaming regions and how often instances are created or destroyed.

**What game creators can do:**
- Reduce the number of parts that continuously move across large distances (fast projectiles, vehicles) — each region crossing is work here.
- Weld moving parts into a single assembly so they move as one unit rather than many.
- Reduce runtime instance creation/destruction churn.


---

### Collect Parts For Min Area

**Collects parts that are within the minimum streaming area (always loaded).**

Identifies parts that must always be present regardless of streaming radius.


---

### Prefetch Gather From Uncollected Regions

**Prefetches data from regions that haven't been collected yet for proactive streaming.**


---

## Garbage Collection (Network)

### Replication Foci GC / GC Loop / Process Deferred GC

**Garbage-collects stale replication data — removes objects that are no longer relevant.**

Cleans up replication state for instances that have been destroyed or streamed out.

**Performance notes:** Normally fast. Can spike after large batch removals.


---

### Part/Model Removals / Foci Removals / Model Removals / Container Removals

**Processes pending removal of parts, models, and containers from the replication system.**

Batch-removes instances that are no longer relevant to any client.

**Performance notes:** Cost scales with how many instances stream out at once — driven by instance density and by players moving far/fast (which streams large regions out).

**What game creators can do:**
- Reduce instance density so fewer instances stream out per move.
- Avoid very fast or very long player movement/teleports, which stream large regions out (and back in) at once.
- Use `Model.ModelStreamingMode` (e.g. Atomic / Persistent) to control how a model streams as a unit.


---

### GC Version Tracking / DeallocateInstanceVersionsAsync / DecayInstanceSyncMap

**Manages version tracking for GC'd instances and cleans up synchronization maps.**


---

## Join Flow

### Join Snapshot / Server Join Snapshot

**Captures the current world state as a snapshot for a joining player.**

Creates the initial state snapshot that will be sent to a newly-joining client. Contains all instances not subject to Streaming system.


---

### GameLoad

**Client-side join-completion handler — fires when the top replication container's 'finished' tag arrives, marking initial game data fully received.**

Records join timing/telemetry, updates join state, signals that the DataModel is loaded, and marks the game as loaded. The initial join snapshot is deserialized and instances are created earlier, not in this scope.

**Performance notes:** Determines load time. Cost = snapshot size.


---

### Container Queue

**Processes the container queue during join — creates instance hierarchies in order.**

Ensures instances are created in the correct parent-child order during the join snapshot application.


---

### Performing player install / Install Remote Player

**Server-side scope for setting up a new player's Player Instance.**


---

### Getting Replication Cache and Queue JDI

**Retrieves cached replication data and queues Join Data Items for the new player.**


---

## Packet Processing

### RakNetUpdate

**Processes incoming and outgoing network packets — the transport layer tick.**

The low-level network update that sends queued outgoing packets and processes received packets. Runs on the network thread.

**Performance notes:** Cost depends on packet volume. High bandwidth usage increases this scope's duration.

**What game creators can do:**
- Reduce network traffic so there are fewer/smaller packets to process — send fewer and smaller replicated updates, lower the rate of frequently-firing `RemoteEvent`s, and reduce the number of network-owned moving parts.


---

### deserializeItem / deserializeClientItem

**Deserializes individual replication items from the network bitstream.**

Decodes received network data back into instance property changes, creations, and deletions. (`decompressBitStream` is a separate step that zstd-decompresses a compressed bitstream before these deserialize it.)

**Performance notes:** CPU-bound deserialization. Cost proportional to received data volume.


---

### Tag deserialized

**Reads a replication flow-control tag item from the stream (e.g. join-milestone markers).**

Decodes an internal replication control tag (not a CollectionService tag); for the join-completion tag, it records join timing and marks that join is complete.


---

### SettingInstanceAlive

**Marks replication-data instances as alive and complete for a replicator during the join flow.**


---

## HTTP & Content

### asyncHttpQueueOnHeartbeat

**Processes the legacy async HTTP request queue.**

Handles a legacy HTTP system; asset requests go through AssetProvider rather than this scope.

**Performance notes:** If many HTTP responses arrive simultaneously, processing them can take time.


---

### contentProviderOnHeartbeat / cacheableContentProviderOnHeartbeat

**Processes content provider asset loading — handles asset request completion.**

Updates the ContentProvider state machine: checks for completed downloads, fires loaded callbacks, and starts new requests. (This describes `contentProviderOnHeartbeat`; `cacheableContentProviderOnHeartbeat` only performs LRU-cache maintenance for cacheable content.)

**Performance notes:** Busy when preloaded content is being processed; preloading more content can increase this heartbeat work while those preloads are active.


---

### HttpRequestAsync / HttpClientReq / HttpClientTC

**Individual HTTP request processing scopes.**


---

### HttpHandleCacheAsyncWriter

**Writes HTTP response data to RbxStorage asynchronously for caching.**


---

### WsClient::workerThreadProcess

**WebSocket client worker thread — processes incoming WebSocket messages.**


---

## Physics & Input Replication

### ParallelPhysicsReceive

**Processes received physics state in parallel — applies server physics corrections.**

Deserializes and applies physics state updates from the server (positions, velocities, CFrames).

**Performance notes:** Cost proportional to the number of physics objects receiving updates.


---

### InputReplicator::sendInputs / InputReplicator::receiveInputs

**Sends local player inputs to the server / receives remote player inputs from the server.**


---

### Sort Priorities / Further Prioritization

**Sorts and refines physics-assembly send priorities for the physics state replication sender.**


---

## Network Quality

### Network Quality Checks / NetworkQualityResponder

**Monitors network connection quality and responds to quality-of-service queries.**

Performs periodic per-connection quality checks and maintenance.


---

## ISR (Instance State Replicator)

### ISRFinalizeStep

**Finalizes the ISR send step — resets the per-frame change tracking after all replicators have sent.**


---

### IsrPartialSortMetrics

**Collects metrics about ISR partial sorting performance.**


---

## Bandwidth & Metadata

### GroupManager / SetManager

**Manages replication groups and sets — organizes instances into replication units.**


---

### Game Services Reporting / GetJobStats

**Reports game service status and collects job statistics for diagnostics.**


---

### Network Quality Checks / Disconnect Cleanup

**Handles disconnection cleanup — removes all replication state for a disconnected client.**


---

### updateMemoryStats

**Updates network memory usage statistics for telemetry.**


---

### GenerateDataBlobsCacheable / GenerateDataBlobsNotCacheable / GenerateDataBlobsCharacterModelRoots / GenerateDataBlobsParts

**Generates serialized data blobs for different categories of replication data.**

Separates replication data into cacheable (static) and non-cacheable (dynamic) categories for efficient serialization.


---

## Data Sender & Packet Details

### Packet Processing

- `processPacket` — processes a single received packet
- `deserializePacket` — deserializes one packet from the bitstream. Low-level packet processing that prepares for **Replicator ProcessPackets**. Advice: send fewer or smaller updates.
- `deserializeBufferedPackets` — deserializes all buffered packets

**What game creators can do:** These scale with how much replicated data the client receives. Reduce it by sending fewer and smaller replicated updates, coalescing frequent property changes, using `RemoteEvent`s sparingly for high-rate data, and using instance streaming to keep fewer instances active.


---

### ISR Details

- `ISR::preProcessFramePropertyChanges` — pre-processes property changes before filtering
- `ISR::stepFilterAndApplyPropertyChanges` — filters and applies property changes for replication
- `Physics Send` / `Physics Send Touches` — sends physics state and touch events


---

### Tracker Data

- `Collect TrackerData` / `Deferred TrackerData update` / `Preserialize TrackerData` — collects, defers, and pre-serializes tracker data for face/body tracking replication. (`Gather Post Join` is a separate instance-streaming step — it collects instance sets that must be sent after a player joins — not tracker data.)


---

### Streaming Details

- `Streaming Invalidated Caches` — invalidates streaming caches after topology changes
- `Resolve Metadata` — resolves deferred replication data and queues newly streamed instances to be added to the replication set
- `UpdateDecayabilityToSyncMap` — updates instance decay eligibility


<br>
<br>

---
