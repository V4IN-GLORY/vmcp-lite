# Systems Group

<!-- from github.com/Roblox/libmp/docs/ALL-SCOPES.md -->
The Systems group contains scopes for system-level engine operations: async asset loading, dynamic flag reloading, storage operations, timer services, CPU frequency probing, and other infrastructure tasks that run as background jobs or on the main thread.

---

## Asset Loading

### Async_Mesh

**Background mesh asset loading — decodes and prepares mesh data from downloaded assets.**

Runs on a worker thread to build GPU-ready vertex/index data for part geometry — basic part shapes (blocks, spheres, cylinders, wedges, trusses), solid-modeling meshes (unions/negations), and MeshPart meshes.

**Performance notes:** Background work. Doesn't block the main thread but competes for CPU time.


---

### Async_Texture

**Background texture asset loading — decodes image data into GPU textures.**

Runs on a worker thread to decode image formats (PNG, JPEG, WebP) into GPU texture data.

**Performance notes:** Background work. Image decoding can be CPU-intensive for large textures.


---

## Configuration

### Dynamic Flag Reloader

**Reloads dynamic fast flags from the CDN — checks for updated flag values.**

Periodically fetches the latest dynamic flag configuration to apply live-tuning changes.

**Performance notes:** Network I/O. Runs infrequently (minutes between reloads).


---

### InstallDefaultScripts

**Initializes the default StarterPlayerScripts (PlayerModule: control, camera, and player-script loader) once at service startup.**

Loads the built-in scripts/PlayerScripts project into StarterPlayerScripts. Runs a single time, not per character spawn. The Animate and Health character scripts are installed elsewhere.

**Performance notes:** One-time setup cost at startup. Negligible.


---

## Storage

### RbxStorage::asyncWrite

**Asynchronously writes data to RbxStorage, the engine's internal storage backend.**

Background file I/O for internal engine storage.


---

### RbxStorage::cleanupThreadFunc

**Background cleanup thread for RbxStorage — removes expired entries.**


---

### RbxStorage::rollingTelemetry

**Emits rolling telemetry about storage usage and performance.**


---

### read_or_mmap

**Reads or memory-maps a file from storage.**


---

## Timer Service

### timerServiceOnHeartbeat

**Steps the timer service — fires any timers whose deadlines have passed.**

Processes the engine-internal timer queue, executing callbacks for expired timers.

**Performance notes:** O(expired timers). Usually fast.


---

### timerServiceDelay / timerServiceCancel

**Schedules or cancels a timer in the timer service.**


---

## Diagnostics

### ProbeCPUFrequency

**Measures CPU frequency — used for accurate timing calibration.**

Runs periodically to detect CPU frequency scaling that could affect profiler timing.


---

### notifyHeartbeatAlive

**Pings the hang detector to indicate the heartbeat is still running.**

Prevents the hang detector from triggering a false alarm by confirming the main thread is alive.


---

### print

**Scope for engine print/log output (when profiled).**


<br>
<br>

---
