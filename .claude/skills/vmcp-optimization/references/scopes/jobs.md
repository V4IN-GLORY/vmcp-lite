# Jobs Group (TaskScheduler)

<!-- from github.com/Roblox/libmp/docs/ALL-SCOPES.md -->
The Jobs group contains scopes for all TaskScheduler jobs. Each job appears as a profiler scope whenever it runs, and the scope covers the job's entire per-frame execution.

Jobs appear in the profiler with the format: **`JobName(Priority;ArbiterName)`** — e.g., `Simulation(Simulation;LuaApp)`.

---

## TaskScheduler Infrastructure

### TS::Step

**One step of the TaskScheduler — selects and dispatches the next ready job.**


---

### TS::JobStep

**Executes one job's step() function — the inner scope of actual job work.**


---

### TS::JobWait

**A job is waiting for a condition (blocked by tryJobAgain mechanism).**


---

### TS::ArbiterStep

**Steps the arbiter — manages job ordering within one DataModel context.**


---

### TS::Reschedule

**Reschedules a job that has more work remaining.**


---

### TS::GC

**TaskScheduler garbage collection — removes completed or dead jobs.**


---

### AsyncTask

**Executes an asynchronous task from a task queue.**


---

## Frame-Defining Jobs

### Heartbeat

**The per-frame heartbeat job — runs all heartbeat subscribers and RunService.Heartbeat callbacks.**


---

### Simulation

**The physics simulation job — steps humanoids, animation, physics solver at fixed rate.**

**Performance notes:** An umbrella for the fixed-rate step — its width is the sum of the physics solve, humanoid stepping, and animation it runs.

**What game creators can do:**
- Reduce the number of moving physics bodies and constraints, and let bodies sleep when at rest.
- Reduce the number of actively-simulated `Humanoid`s and simultaneously-playing animations.
- Expand the scope to see whether physics, humanoids, or animation dominates, then target that.


---

### RenderJob

**The main rendering job — executes the full render pipeline (Perform phase).**

**Performance notes:** An umbrella for the whole render pipeline — its width is the sum of its passes (scene render, geometry updates, post-effects, GPU waits).

**What game creators can do:** Expand it and target the widest child pass — e.g. the `Scene` render, `updateRenderQueue`, or a GPU wait (`waitOnGpu` / `waitUntilCompleted`, which indicate a GPU-bound frame). Each of those entries has its own levers.


---

### PreRenderJob

**The pre-render job — runs the render step ahead of the main render job (and updates VR state on VR platforms).**


---

### SimpleRenderStepJob

**A render-step job used in headless / minimal rendering contexts. Calls the same render step as the main render jobs.**


---

## Input

### InputDispatch

**Dispatches input events — processes keyboard, mouse, touch, and gamepad input.**


---

## Script

### LuaGc

**Runs the Luau garbage collector as a scheduled job.**


---

### WaitingHybridScriptsJob

**Resumes scripts waiting on `Instance:WaitForChild()` or `task.wait()`.**

Usually runs ~30 times per second. It has an execution-time budget, so a heavy backlog of waiting scripts is spread across multiple runs.

**What game creators can do:**
- Reduce the number of waiting scripts, or shorten long computations before a script yields


---

## Network

### Allocate Bandwidth and Run Senders

**Allocates network bandwidth budget and sends replication data to clients.**


---

### Replicator ProcessPackets

**Processes received network packets — deserializes incoming replication data.**

Processes contents of network packets, such as motion, event invocations and property changes.

**What game creators can do:**
- Reduce the number or size of objects being replicated, or do this in incremental steps. May increase if map size increases.


---

### Replicator SendData

**Sends queued instance and property data to connected clients.**


---

### Replicator StreamData

**Streams instances to/from clients based on proximity.**


---

### Replicator GC Job

**Manages instance-streaming region lifecycle on the client — pauses, expands, and garbage-collects streamed regions based on the character's position.**


---

### Replicator StatsSender

**Sends replicator statistics for diagnostics.**


---

### receive physics Mega Job

**Receives and applies physics state updates from the server.**


---

### Streaming Solver V2

**Computes which instances each client should have streamed in.**


---

### InstanceObjectManager Job

**Manages instance lifecycle for streaming — creates/destroys instances as they stream in/out.**


---

### Distributed Physics Ownership

**Determines whether the server or a client has authority over certain instances such as parts.**

**What game creators can do:**
- Reduce the amount of parts that frequently switch network ownership, especially those with common interaction


---

### Net PacketReceive

**Receives raw network packets from the transport layer.**

Receives network packets. If many objects or events are being replicated, this step takes longer.

**What game creators can do:**
- Replicate fewer objects or events


---

### Net Peer Send

**Sends raw network packets to connected peers.**


---

### Net Peer Stats

**Collects network peer statistics (latency, bandwidth, packet loss).**


---

### Network Join Processor

**Processes player join requests — builds the initial world snapshot.**


---

### Network Quality Processor / Network Quality Responder

**Periodic server-side per-connection maintenance jobs. Each runs over all client connections on a throttled interval (a few times per second).**


---

### Network Disconnect Clean Up

**Cleans up after a player disconnects.**


---

### ServerToClientSender

**Sends real-time text translations from the server to a specific client (server-side job).**


---

## Sound

### Sound / Sound Job Studio

**The runtime `Sound` job advances the audio mix each frame; `Sound Job Studio` is a Studio-only job that steps sound-asset loading into channels.**


---

## Navigation

### NavigationJob

**Processes navigation mesh generation on a background thread.**


---

### PathUpdateJob

**Updates computed paths when the navmesh changes.**


---

## Terrain

### GridJob

**The terrain worker job — processes terrain read/write/LOD operations.**


---

## Video

### Video

**Video playback job — steps VideoFrame playback each frame (VideoService clients, playback managers, and thumbnail generation).**


---

### VideoCaptureTimer

**Monitors elapsed time during video capture and stops capture when duration limit is reached or render buffer timeout occurs.**


---

### VideoStreamMonitor

**Monitors active video streams and closes a stream when no new frames have arrived for longer than a timeout (derived from the stream's frame rate).**


---

### Format Muxer

**Muxes audio/video streams into a container format.**


---

### LocalPlaybackJob

**Handles local video playback.**


---

## Data Services

### DataStoreJob

**Manages DataStore request execution including adding throttling budgets, executing throttled and retry requests, refetching cached keys, and refreshing locks.**


---

### MemoryStoreJob

**Processes MemoryStore requests.**


---

### PlayerDataJob

**Handles player-specific data operations.**


---

## Content & Assets

### ModelMesh

**Computes optimized mesh representations of 3D models for LOD rendering, processing changed models and managing async mesh generation.**


---

### ThumbnailFetchJob

**Fetches asset thumbnails.**


---

### BlockingRead / ReadAsync

**Synchronous and asynchronous terrain voxel-grid reads — read voxel channel data (material/volume) from the terrain grid via the VoxelJobManager.**


---

## Analytics & Services

### AnalyticsServiceJob

**Batches and sends analytics events.**


---

### CollectionServiceJob

**Collects per-frame CollectionService tag operation metrics, processes pending player disconnections for tag rule cleanup, and reports telemetry.**


---

### Romark Phase Tracking Job

**Tracks performance phases for telemetry.**


---

### ScreenTimeHeartbeatJob

**Executes a periodic heartbeat for screen time tracking.**


---

### DataModelSnapshotJob

**Captures DataModel state snapshots.**


---

### SoapMicroprofilingHeartbeatJob

**Profiling heartbeat for server diagnostics.**


---

## HTTP

### HttpRbxApiJob

**Processes HTTP API requests to Roblox services.**


---

## Logging & Diagnostics

### LogServiceJob

**Batches and processes log events for analytics/telemetry on a 1 Hz interval.**


---

### HangDetectionJob

**A per-frame heartbeat job that marks the main loop alive; a background watcher thread flags a hang if the heartbeat stops.**


---

### NotifyAliveJob

**Periodically signals that the main thread is responsive.**


---

### MemoryPrioritizationJob

**A periodic client-side job that monitors how much memory the app is using against what's available and tracks the current level of memory pressure. As memory runs low it asks memory-holding systems to release memory so the app stays within the device's memory budget. Runs on mobile and Windows clients, and matters most on memory-constrained devices such as phones and tablets.**

It ticks at a low fixed rate, so it is normally negligible in a capture. If it is doing noticeable work — or running its checks frequently — the client is under memory pressure (running low on available memory), which on constrained devices is what precedes out-of-memory problems.

**Performance notes:** Tiny under normal conditions. Elevated activity here is a *symptom* of high memory usage, not a frame-cost problem in the job itself.

**What game creators can do:**
- Reduce the client's memory footprint: fewer and smaller textures, meshes, and sounds; reuse assets; and keep resident instance counts down.
- Use instance streaming so distant content isn't all held in memory at once.
- Watch for memory leaks — memory that only ever grows (e.g. instances, connections, or tables never cleaned up).

Keeping memory usage low keeps pressure low, so the engine doesn't have to shed memory and is far less likely to run out of memory on constrained devices.


---

### TimerTickerJob

**Advances engine timer ticks.**


---

### PhysicsTrackerJob

**Collects physics state changes (position/rotation) for BaseParts that moved and batches them by frame intervals.**


---

## Configuration

### CreatorConfigProviderPollingJob / CreatorConfigProviderReportingJob / CreatorConfigPlatformProviderPollingJob / CreatorConfigPlatformProviderReportingJob

**Polls and reports creator configuration settings.**


---

## Platform-Specific

### PlayStationTerminateMsgDialogJob

**PlayStation platform — handles termination message dialogs.**


---

## Other

### RCCInstanceTrackingDMJob

**Server instance tracking.**


---

### PluginOTAJob

**Over-the-air plugin update checking.**


---

### ModifyResolveUnavailable

**Resolves unavailable terrain modification requests.**


---

### TextScraper::ScraperJob / TextScraper::ServiceScraperJob

**Text scraping jobs for automatic localization.**


---

### TotalPlayerCountJob_

**Tracks total player count for analytics services.**


---

### EventBroadcastrelayFireEventJob

**Fires queued events through the cross-DataModel event-relay system.**


---

## Task Queues

Task queues appear as jobs with "TaskQueue" in the name. They batch small operations.

### WorkspaceTaskQueue / ScriptContextTaskQueue / HumanoidParallelManagerTaskQueue / AnimatorParallelManagerTaskQueue / SlimReplicationTaskQueue / SmoothClusterTaskQueue / SceneUpdaterTaskQueue / DataModelCharacterTaskQueue

**Various task queues that batch operations for their respective subsystems.**


---

### MegaReplicatorTaskQueue / MegaReplicatorPPRTaskQueue

**Server-side replication task queues. `MegaReplicatorTaskQueue` runs the per-frame work of sending replicated state out to connected clients — property changes, physics and touch updates, instance streaming, and the initial snapshot sent to joining players; `MegaReplicatorPPRTaskQueue` processes incoming physics updates in parallel. Both run on the server, so a wide block here is server frame time, not the client's.**

The work is spread across worker threads and is fundamentally per-connected-player: for each client the server serializes that client's share of changed state. It gets wide when there is simply a lot to replicate. If it is wide, expand it — the widest child phase (sending property changes, sending physics/touch updates, instance streaming, or a joining player's snapshot) points to which cause below dominates.

**Performance notes:** Cost scales roughly with (connected players) × (amount of state changing per player each frame). Player joins add a bursty spike, since a large slice of the world is serialized for the joining client.

**What game creators can do:**
- Reduce how many properties change each frame on replicated instances — avoid rewriting properties every frame; batch or throttle updates, and change only what truly needs to replicate.
- Reduce the number of moving, network-simulated parts and unnecessary touch events; anchor parts that don't need to move.
- In large or dense worlds, lower `Workspace.StreamingTargetRadius` and reduce the total instance count so less is streamed to each player.
- Spread player joins out over time where possible — join bursts are the most expensive moments.
- Fewer simultaneously connected players is the single biggest lever, since every phase scales per player.


---

## Marshalled Jobs

### Write Marshalled / Read Marshalled / None Marshalled

**Thread-safe operations that are marshalled to the DataModel thread. Write requires write lock, Read requires read lock, None requires no lock.**


<br>
<br>

---
