# Profiler & Runtime Scopes

<!-- from github.com/Roblox/libmp/docs/ALL-SCOPES.md -->
This file documents three groups of scopes: the **MicroProfiler's own overhead** (its data collection and, when open, UI rendering); the **Runtime** group (fiber scheduling — background/foreground fibers, sleeping, and switching between fibers); and the **LuaBridge** group (Luau-to-engine property and method access). The data-collection and fiber scopes appear in essentially every capture; the profiler-UI scopes appear only while the profiler UI is open, and LuaBridge scopes only when scripts read or call engine instances.

---

## MicroProfiler Group

The profiler's own overhead — its UI rendering and data collection.

### MicroProfileFlip

**The profiler's per-frame housekeeping — collects timing data and advances the frame counter.**

Always present. Its duration is the profiler's own overhead.

---

### Draw / DrawBarView / Draw Graph / Detailed View

**Renders the profiler's on-screen UI (bar view, graph view, detailed view).**

Only present when the profiler UI is visible. Closing the profiler UI eliminates these.

---

### ThreadLoop

**The profiler's data collection thread loop.**

---

### Clear / Accumulate

**Clears per-frame data and accumulates statistics across frames.**

---

### ContextSwitchSearch

**Searches for OS thread context switches for the profiler's context-switch visualization.**

---

### FrameCheck / CPUFreq

**FrameCheck flags profiler frames whose capture data is incomplete (a thread's log buffer wrapped mid-frame); CPUFreq samples the CPU clock speed each frame.**

---

### MpDataUpdate

**Processes completed frames into the profiler's live data view — updates timer/thread registrations and feeds frame timing data into the timeline buffer.**

---

### WebServerUpdate

**Updates the profiler web server (for remote viewing via browser).**

---

## Runtime Group (Fiber Lifecycle)

Cooperative fiber runtime — the low-level scheduling layer that TaskScheduler Jobs run on. Engine jobs (including script execution, physics, rendering) execute inside these fibers. `(BG)` = background-group fiber, `(FG)` = foreground-group fiber.

### Thread (BG) / Thread (FG)

**A fiber is actively executing.**

This covers both script coroutines and engine async work. (FG) = foreground group — short-lived work that runs to completion (e.g. a task). (BG) = background group — long-lived work that may run indefinitely (e.g. a generator, or a loop that waits and wakes periodically).

---

### Sleep

**A worker thread is idle — waiting for new work to be scheduled.**

---

### Sched

**The scheduler is between fibers — selecting the next fiber to resume.**

---

## LuaBridge Group

Fires when Luau scripts interact with Roblox instances (method calls, property access). These nest inside the `Script_*` scope of the calling script.

### $namecall

**A `:Method()` call on a Roblox instance.**

If this is wide, a method call on a Roblox instance is taking a long time. Hover over the scope to see labels showing the **method name** and **class name** (e.g., `FindFirstChild`, `Model`).

---

### $index

**A `.Property` or `[key]` read on a Roblox instance.**

Hover to see labels showing the **property/field name** (or **child name**) and **class name**. `$index` covers both property/field reads and lookups of a child instance by name.

---

### $newindex

**A `.Property = value` or `[key] = value` write on a Roblox instance.**

Hover to see labels showing the **property name** and **class name**.

---

### $call

**Executes a Roblox instance member function or yielding function that was already resolved.**

Unlike `$namecall` which includes method lookup, `$call` fires when calling a pre-resolved function closure. Hover to see the function name and class.


<br>
<br>

---
