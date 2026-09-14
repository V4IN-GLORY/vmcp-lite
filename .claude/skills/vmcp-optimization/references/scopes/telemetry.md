# Telemetry Group

<!-- from github.com/Roblox/libmp/docs/ALL-SCOPES.md -->
The telemetry group (labeled "telem" in code) contains scopes for gathering, aggregating, and transmitting performance telemetry data to Roblox's backend analytics systems. These scopes fire periodically (not every frame) and measure the overhead of the telemetry system itself.

---

## Gathering

### telem / perfdata_v2

**Gathers performance data v2 — collects per-frame timing samples from telemetry-enabled scopes.**

The main telemetry gathering pass. Reads accumulated timing data from telemetry-enabled scopes and packages them for transmission.

**Performance notes:** Runs periodically (not every frame). If it appears in a profiler capture, it's measuring the gather cost itself. Usually < 1ms.


---

### telem / perfdata_v2_sendphase

**Sends gathered performance data to the backend — the network transmission phase.**

Serializes and transmits the collected performance metrics to Roblox analytics endpoints.


---

### telem / prof_v2 / profileTelemetry_v2

**Aggregates performance-statistics telemetry — FPS and frame-time averages/min/max plus quality-level percentiles.**


---

## Category-Specific Gathering

### telem / gfx

**Gathers graphics/rendering telemetry — GPU/adapter info, display resolution, lighting counts, quality level, and render-pass stats.**


---

### telem / memory / memory_v2

**Gathers memory telemetry — heap usage, texture memory, mesh memory, Luau heap size.**


---

### telem / script

**Gathers script telemetry — Luau garbage-collection time (GC assist and step) and heap size, for the game and core-script VMs.**


---

### telem / avatar

**Gathers avatar memory telemetry — humanoid count, texture memory, and mesh memory usage.**


---

## Session Tracking

### telem / sessionTracking_v2 / sessionTracking_ph2

**Per-session telemetry aggregation — gathers and records the session's periodic perf-data and stability markers.**

Aggregates the session's performance data and records session markers used to determine whether a session ended cleanly.


---

## Transmission

### telem / send

**Sends a telemetry batch to the backend.**

**Performance notes:** May spike if many metrics are queued.


---

## Transport & Service Telemetry

### RbxTransport telemetry scopes

Transport-layer telemetry scopes (in the "RbxTransport" group):
- `BasePacketSender.processPendingTx`
- `LibuvEventLoop.runOnce`
- `QuicPacketReader.onRecv`
- `SysEventLoop.processAllEvents`

### SoundOutput telemetry scopes

Audio output telemetry:
- `renderAudio` — measures audio render callback duration

### LocalStorage / MemProfStorage telemetry scopes

Storage telemetry:
- `asyncFlushTask` — measures storage flush duration
- `mappedFileFlush` — measures memory-mapped file flush

---

### Counter::send / EphemeralCounter::send / EphemeralStat::send / Event::send / Stat::send

**Telemetry transmission operations — sends counters, ephemeral stats, events, and statistics to the analytics backend.**


<br>
<br>

---
