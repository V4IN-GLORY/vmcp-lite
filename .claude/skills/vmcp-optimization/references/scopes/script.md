# Script Group

<!-- from github.com/Roblox/libmp/docs/ALL-SCOPES.md -->
The Script group contains scopes for Lua/Luau script execution, parallel VM management, garbage collection, and deferred operations. These scopes fire on the main thread (serial execution) and worker threads (parallel Luau).

---

## Core Execution

### runSerial

**Resumes threads scheduled for serial execution during the Parallel Luau work-queue iteration — the serial half of the parallel/serial orchestration.**

During each Parallel Luau work-queue iteration this drains the serial-thread queue: threads that were scheduled to run serially (e.g. work deferred back from the parallel phase) are resumed one at a time. It is one part of the parallel/serial orchestration, not the main script-execution loop.

**Performance notes:** Wide `runSerial` means scripts are doing expensive work on the main thread. This directly blocks the frame.

**What game creators can do:**
- Move expensive computations to `task.desynchronize()` for parallel execution
- Break large loops with `task.wait()` to spread across frames
- Use native Luau types and avoid excessive table allocations
- Profile individual scripts using the ScriptProfiler


---

### runParallel

**Executes Lua scripts across parallel VM threads — distributes Actor-isolated scripts to worker threads.**

Scripts inside Actor instances that have called `task.desynchronize()` execute here in parallel across multiple worker threads. Each Actor's VM runs independently.

**Performance notes:** Wide `runParallel` on worker threads is generally fine (doesn't block the main thread). However, the main thread waits for all parallel work to complete before continuing.

**What game creators can do:**
- Balance work across Actors (avoid one Actor doing all the work)
- Keep parallel code free of calls that force synchronization
- Use SharedTable for data sharing instead of BindableEvents


---

### runSignals

**Delivers signal results from parallel execution back to the main thread.**

After parallel work completes, signals that were queued during parallel execution are delivered on the main thread. This includes BindableEvent signals and other cross-Actor communication.

**Performance notes:** Cost depends on the number of signals queued during parallel execution.


---

### resumeVMThreads

**Resumes Luau coroutines/threads that are ready to continue.**

Core VM thread resumption — wakes up coroutines that were yielded by task.wait(), events, or other yielding operations and have become ready.

**Performance notes:** Per-thread overhead is minimal. Total cost = number of threads being resumed × their execution time.


---

### resumeParallelWaitingScripts

**Orchestrates resumption of scripts waiting for parallel execution results.**

Coordinates the parallel → serial transition: collects parallel work, distributes to workers, waits for completion, then delivers results.

**Nesting:** Contains: collectParallel → runParallel → runSignals → runSerial.


---

### collectParallel

**Collects and buckets parallel-ready scripts into per-thread work queues.**

Organizes scripts that are ready for parallel execution into thread-safe buckets for distribution to worker threads.

**Performance notes:** Fast organizational pass. Cost proportional to the number of parallel-ready scripts.


---

### executeParallelHybridCallback

**Executes a hybrid parallel/serial callback — scripts that partially run in parallel.**

Used by the hybrid parallel queue where some work is parallel-safe but the callback needs both parallel and serial phases.


---

## Scheduling

### delayedThreads

**Resumes threads whose `task.wait(N)` or `task.delay(N)` timers have expired.**

Checks all sleeping threads and resumes any whose delay timer has elapsed. Runs at the start of each frame before other script work.

**Performance notes:** Cost proportional to the number of threads with expired timers. If many scripts use short delays (task.wait(0)), they all wake up every frame.

**What game creators can do:**
- Use longer delay values when possible
- Avoid task.wait(0) in tight loops (use task.defer instead if appropriate)
- Consolidate periodic logic into fewer scripts


---

### deferredThreads

**Processes callbacks queued with `task.defer()` — runs them at the end of the current resumption cycle.**

Executes all deferred callbacks that were queued during the current frame's script execution. Deferred callbacks run after the current batch of signal handlers completes.

**Performance notes:** Same as general script execution. Too many deferred callbacks can extend frame time.

**What game creators can do:**
- Reduce how much work you queue with `task.defer()` each frame; run work directly when deferral isn't needed.
- Avoid deferred callbacks that themselves queue more deferred work — this can snowball within a frame.
- Disconnect event connections you no longer need, and debounce or batch very high-frequency signal handlers.


---

### deleteDeferred

**Releases instances that were queued for deferred deletion, freeing them at a GC-safe point.**

Instances whose destruction must be delayed for safe Lua lifetime management are held in a pending free-list and released here; the list and each script VM's deferred-deletion list are cleared. This is unrelated to the deferred signal-behavior (event delivery) mode.

**Performance notes:** Typically fast. Can spike when destroying large instance hierarchies.


---

## Garbage Collection

### GC

**Runs one step of the Luau garbage collector — reclaims unused memory.**

Performs incremental garbage collection on the Luau heap. The GC runs in steps to avoid long pauses, but each step still takes time proportional to the amount of memory being scanned/collected.

**Performance notes:** GC cost is driven by:
- Total Luau heap size (more objects = more to scan)
- Allocation rate (more allocations = more frequent GC)
- Object connectivity (deeply linked tables are expensive to trace)

**What game creators can do:**
- Reduce table allocations in hot loops (reuse tables)
- Set unused references to nil so they can be collected
- Avoid creating closures in tight loops
- Use buffer/string.buffer for binary data instead of tables of numbers
- Profile memory with the Luau Heap Profiler


---

## Server Authority Script Execution

These scopes drive script execution under the **Server Authority** simulation system (opt-in Beta). Under Server Authority the client runs script logic ahead of server confirmation (client-side prediction) and re-runs it after a rollback when the server's authoritative state differs. `AuroraScript`/`AuroraScriptService` is the internal name for this system, so the scope strings carry that prefix.

### AuroraScriptService::onPreAnimation / onPreSimulation / onPostSimulation / onFixedHeartbeat / onPresentation

**Lifecycle hooks that drive Server Authority script execution at specific points in the frame.**

Each hook invokes scripts at the corresponding phase:
- `onPreAnimation` — before animation evaluation
- `onPreSimulation` — before physics
- `onPostSimulation` — after physics
- `onFixedHeartbeat` — fixed-rate heartbeat
- `onPresentation` — before rendering

**Performance notes:** Cost = script execution at that phase.


---

### AuroraScriptService::stepAllObjects

**Steps all Server-Authority-managed objects through one simulation frame.**


---

### AuroraScriptService::startAuroraServiceStep / completeAuroraServiceStep

**Bookends for a service step — initialization and completion phases.**


---

### AuroraScriptService::finishFrame

**Finalizes the frame — commits state changes and prepares for the next frame.**


---

### AuroraScriptService::iterativelyProcessMessages

**Processes inter-object messages iteratively until stable.**

Messages between objects can trigger cascading state changes. This scope iterates until no new messages are generated.

**Performance notes:** Normally fast. Can spike if objects create long message chains.


---

### AuroraScriptService::rollback / rollbackToWorldStep / rollbackEffectedObjectsAtFrame

**Reverts script state when the server's authoritative state diverges from the client's prediction.**

**Performance notes:** See Simulation group → `AuroraService::rollback` for full details. Frequent rollbacks usually indicate high latency or diverging client/server simulations.


---

### AuroraScriptService::snapshotRollback / simulateEngineHook

**Captures state snapshots for rollback support and hooks into the engine simulation.**


---

### AuroraScript::start / AuroraScript::stop

**Lifecycle management for individual scripts — initialization and teardown.**


---

### AuroraScript::invokeCallback

**Invokes a Lua callback function from the script system.**


---

### AuroraScript::processUpdate / processUpdates / processMessages

**Processes state updates and messages for one script.**


---

### AuroraScript::onStartFrame / onSendScheduledMessages / onSimulate / stepObjectsAtFrame / onFinishFrame

**Per-frame lifecycle hooks for individual scripts.**


---

### AuroraScript::readStateObject

**Reads a state object from the state store for script access.**


---

### AuroraScript::snapshotRollback

**Captures a rollback snapshot for one script.**


---

### AuroraScriptRuntime::invoke

**Low-level Luau callback invocation wrapper.**

**Labels:** Emits the function name being invoked — visible on hover in the timeline.


---

## CollectionService & Tags

These scopes fire when game code uses CollectionService (tagging system). They are typically called from Lua via `CollectionService:GetTagged()`, `:AddTag()`, etc.

### getCollection

**Retrieves the internal instance collection for a given class/type name — an engine-internal registry, distinct from the CollectionService tag query (`GetTagged`).**

**Performance notes:** Fast for small collections. Can be expensive if a tag has thousands of instances.


---

### addInstance / addTag / addTagHelper / addTagLua

**Adds a tag to an instance — registers it with CollectionService.**

**Performance notes:** Negligible per-call.


---

### removeTag / removeTagLua

**Removes a tag from an instance. (The `removeTagLua` label is reused by a few other CollectionService operations — reading an instance's tags (`GetTags`), listing every tag in use (`GetAllTags`), and instance teardown — so a `removeTagLua` block in a capture may be one of those rather than a tag removal.)**


---

### computeAddedAndRemoved

**Computes the tag diff for a single instance — which tag names were added or removed between its previous and current tag strings.**

Called from onTagsChanged when an instance's tags change, so that per-tag added/removed signals can be fired for that instance.

**Performance notes:** O(collection size). Fast for small collections.


---

### getTagged / getAllTags / getTagsLua

**Tag-query APIs backing the Lua `GetTagged` and `GetTags` calls (and the enumerate-all-tags query).**


---

### hasTag / hasTagLua

**Checks if an instance has a specific tag.**

**Performance notes:** O(n) in the number of tags on the instance — a linear scan of the instance's tag list, not a hash lookup.


---

### getInstanceAddedSignal / getInstanceRemovedSignal

**Returns the signal for tag add/remove events.**


---

### iterateCollection

**Iterates all instances in a collection, invoking a callback for each.**

**Performance notes:** Cost proportional to collection size.


---

### connectToSignal / connectPropertyChangedCallback / connectAttributeChangedCallback

**Connects Lua callbacks to instance signals within the collection system.**


---

### match / unmatch

**Matches or unmatches an instance against collection query criteria.**


---

### onTaggedInstanceServiceProvider / onTagsChanged / tagRemoved

**Internal event handlers for tag system state changes.**


---

### CollectionWatcherConstructor

**Constructs a CollectionWatcher — sets up monitoring for a tag collection.**


---

## Heap Profiling

These scopes fire when using the Luau Heap Profiler (ScriptProfiler). They are diagnostic and should not appear during normal gameplay.

### LuauHeapMemoryReport::runProcessAsync / runProcessImmediate

**Runs the heap memory report generation — either async (non-blocking) or immediate (blocking).**

**Performance notes:** Expensive — pauses Luau VMs and traverses the entire heap. Only used for diagnostics.


---

### LuauHeapMemoryReport::runGc / gc

**Forces a full GC cycle as part of heap profiling to get accurate live-object counts.**


---

### LuauHeapMemoryReport::collectInstances / collectBasicStats / prepareGraph / linkHeap / aggregate / collect / createResultTable / reportTelemetry / processCoroutineBody

**Sub-phases of heap analysis: collecting instance data, building the object graph, linking references, aggregating statistics, and generating the report.**


---

### LuauUniqueReferenceReportProcess:: (same sub-phases + walkRoots)

**Unique/leaked reference report — flags instances held by exactly one reference, and also instances not parented under the DataModel. Its sub-phases are collectInstances, prepareGraph, linkHeap, walkRoots, collectBasicStats, createResultTable, reportTelemetry, processCoroutineBody.**


---

### getLuauHeapMemoryReport / getLuauHeapInstanceReferenceReport / getLuauHeapJSONDataAsync / getRootObjectsMemoryAsync

**Top-level API entry points for heap profiling features.**


---

## Script Execution Scopes (Script Group)

### Script_*Name*

**Identifies which script is currently executing.**

When you see `Script_Animate`, `Script_CameraModule`, or any `Script_*` scope, it means that particular script's code is running. The name matches the script's `Name` property in the Explorer. The script can be yours or one of Roblox's internal or core scripts.

**Performance notes:** If a specific `Script_*` scope is wide, that script is consuming significant frame time. Open it in the Script Profiler for line-level detail.

---

### $ScriptOverflow / $ProfileBeginOverflow

**The profiler ran out of available scope slots for this category.**

When more unique script scopes are active than the pool can track, additional scopes are grouped into overflow buckets depending on their type:

- **`$ScriptOverflow`:** Used for scopes representing unique scripts. Viewers typically replace this technical name with the real script name stored in the scope's first label, prepended with an asterisk (e.g., `*Script_MyGameScript`).
- **`$ProfileBeginOverflow`:** Used for custom `debug.profilebegin` scopes. Viewers typically replace this technical name with the real scope name stored in the scope's first label, prepended with an asterisk (e.g., `*MyCustomLuauScope`).

**What game creators can do:**
- Reduce the number of `debug.profilebegin` regions in game scripts
- Avoid generating dynamic scope names
- Avoid having hundreds of single-function scripts

---

### ::*CoreScriptScope*

**A scope belonging to an internal or core script rather than game scripts.**

Scopes with names starting with `::` belong to scripts that are not directly included as part of your game (such as CoreScripts). The name of the script is always shown in its parent scope.

---

### debug.profilebegin / debug.profileend scopes

**Custom profiler scopes created by game scripts using `debug.profilebegin("name")` and `debug.profileend()`.**

These always appear nested inside the `Script_*` scope of the script that created them. Any scope name that doesn't match a known engine scope is likely a custom scope from game scripts. Developers use these to measure specific sections of their code.


<br>
<br>

---
