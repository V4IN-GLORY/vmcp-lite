---
name: vmcp-optimization
description: Finding and fixing frame-time problems in a Roblox game with VMCP — ranking scripts by size with count_lines, reading them for hot paths, hammering suspect functions under the MicroProfiler with profile_scripts (LibMP captures, .gprx dumps), reading self vs inclusive time, benchmarking a candidate fix against the original without touching the game, verifying nothing changed, and reporting it in plain words. Use for "why is this laggy", "optimize this script", "what's eating frame time", or any performance pass on a live place.
---

# Optimizing a game with VMCP

This is a loop, not a checklist. You run it on one script, report, then either run it on the next
script or stop and let the user playtest. The game must behave identically when you're done —
the only thing you're allowed to change is how long it takes.

```
count_lines                      -- who's big
  -> read the script + its callers/callees
  -> pick the functions/sections that look hot
  -> profile_scripts             -- hammer them under the MicroProfiler, get numbers + a .gprx
  -> read self time, worst frame, heap delta; dig with vmcp.Profile.Session() if needed
  -> write a candidate fix as a module that lives only in the playtest
  -> profile_scripts again: old vs new, same fake data, same call
  -> prove same outputs on the same inputs
  -> revert, report in plain words, offer to apply
  -> next script, or pause for the user to playtest
```

Load `vmcp-debugging` and `vmcp-timeline` alongside this — `vm = "game"`, `ctx`, `Remotes.WatchAll`
and `Bench` are all used below and explained there.

## Ground rules

- **Never change behaviour.** Not "mostly the same" — the same. Same return values, same order of
  side effects, same events fired, same errors on bad input. If the faster version can't do that,
  say so and let the user decide.
- **Every change gets named.** If you fix a bug you tripped over, or a fast path skips a `warn`
  that used to fire, the user hears about it even when it's irrelevant. They own the game; you
  don't get to decide what's irrelevant.
- **Revert by default.** The loop ends with the original code back in place and a written
  recommendation. Only apply the fix when the user says so, and then stop so they can playtest.
- **Measure before and after with the same load.** A fix without a before/after pair from the
  same `profile_scripts` call isn't a fix, it's a guess.
- **Read p95 and worst frame, not mean.** A function whose mean is fine and whose worst frame is
  30ms is the one players feel.
- **Don't hammer things that talk to the outside world.** DataStore, HttpService, MessagingService,
  MarketplaceService, TeleportService — 500 calls a second hits budget limits and can throw on a
  real player later. Stub them in `setup` or profile the part around them.

## Prerequisites

- **LibMP in the place.** `profile_scripts` looks for a `ModuleScript` named `LibMP` in
  `ReplicatedStorage` (then anywhere). Missing → pass `installLibMP = true` once; it inserts
  Creator Store asset `109009378620272` and tags it `excludeLOC`. That's a change to the place —
  tell the user, and tell them where it went. Or they can add it themselves from
  github.com/Roblox/libmp/releases.
- **Script injection allowed** for VMCP in Plugin Management, or `count_lines` can't read Source and
  `sections` can't be written.
- **A playtest.** `profile_scripts` starts one if none is running (Play Solo, 1 player, unless you
  pass `players`). It leaves it running. If `sections` are given and a playtest is already up, it
  stops and restarts it so the instrumented copies are what runs — say so before you call it if
  the user might be mid-test.

## Step 1 — find the big scripts

```
count_lines                                  -- whole place
count_lines { root = "ServerScriptService" } -- one side
count_lines { minLines = 200 }               -- only the ones that matter
```

It uses `QueryDescendants("LuaSourceContainer:not(.excludeLOC)")` and skips anything under an
instance tagged `excludeLOC`, so tag LibMP, vendored libraries, and the VMCP plugin folder
(`ServerStorage.VMCP` in this place) before reading the numbers. Output is sorted by total lines,
with a code-only count next to it so a script that's half comments doesn't outrank real logic.

Size is a heuristic, not a verdict. A 40-line `Heartbeat` handler can cost more than a 2000-line
shop. Use the list to order your reading, then look for the actual hot-path shapes below.

## Step 2 — read for hot paths

Read the whole script. Then read what it requires and who requires it (`search_scripts` with the
module name finds callers). You need the stack — a function that looks cheap can be called 300
times a frame by something else.

What actually costs frame time, in rough order of how often it's the culprit:

| shape | why it hurts |
|---|---|
| work in `RunService.Heartbeat/RenderStepped/Stepped` or a `while true do task.wait() end` | runs every frame whether anything changed or not |
| `GetDescendants()` / `FindFirstChild(..., true)` / `GetChildren()` inside a loop or per frame | walks the tree every call; the tree is big |
| per-player or per-entity loops that do instance work (`CFrame`, `Position`, `Size` writes) | N writes × 60 fps, each a property change with replication |
| `Instance.new` / `:Clone()` / `:Destroy()` per frame or per call | allocation, tree mutation, replication |
| building strings in a loop (`..` in a `for`), `string.format` per frame | allocation; string interning |
| `table.insert` into a table that's cleared and rebuilt every frame | allocation + GC pressure — shows as Luau heap climbing |
| `Touched` handlers, `.Changed` on hot properties, `GetPropertyChangedSignal("CFrame")` | fire far more often than people think |
| raycasts / `GetPartBoundsInBox` / `GetPartsInPart` per entity per frame | physics queries; cost scales with parts overlapped |
| `TweenService:Create` per call, `:Play()` on a new tween each time | tween object churn |
| deep `game.Workspace.A.B.C.D` paths in hot code | each `.` is a child lookup |
| `pcall` around a hot inner call, `select("#", ...)`, `table.unpack` of big tables | call overhead in the wrong place |
| `require` inside a function | cache lookup + the first one runs the whole module |
| remotes fired per frame, or `FireAllClients` with big tables | serialisation, network |
| `wait()`, `spawn()`, `delay()` | legacy scheduler; `task.*` is cheaper and more predictable |

Mark **functions** (the unit `profile_scripts` hammers) and **sections** inside them (a loop, a
query, a block you suspect). Note what each function needs to be called: which arguments, what
module state must exist first, whether it needs a character in the world.

## Step 3 — build fake data

`setup` is a Luau body that runs once and `return`s the function to hammer. It runs in the
**game VM** by default, so `require(game.ServerScriptService.Combat)` gives you the live module
with whatever state the game built — the same instance the game's own scripts hold.

Ways to get realistic arguments, most to least realistic:

1. **Capture real ones.** Server-side `vmcp.Remotes.WatchAll(game.ReplicatedStorage.Remotes)`,
   play for a few seconds (or drive input from a client timeline event), then
   `vmcp.Remotes.Shapes()` gives a real sample argument set per remote. Copy those into `setup`.
2. **Use what's in the world.** In Play Solo there's a player and a character:
   `local char = game.Players:GetPlayers()[1].Character`. Rigs in `ServerStorage` can be
   `:Clone()`d into Workspace inside `setup` (they live in the playtest only; nothing is saved).
3. **Build tables shaped like the real state.** Read the module with `vm = "game"` first
   (`return SomeModule.State`) to see the real shape, then construct one.
4. **Vary per call.** The function you return receives the call index: `return function(i) ... end`
   — use it to pick a different entity, different position, or rotate through a pool, so a cache
   inside the function doesn't turn your benchmark into a cache-hit benchmark.

```lua
-- a setup body that hammers a hit-resolve against a pool of dummies
local Combat = require(game.ServerScriptService.Combat)
local pool = {}
for i = 1, 8 do
    local rig = game.ServerStorage.Rigs.Dummy:Clone()
    rig:PivotTo(CFrame.new(i * 6, 5, 0))
    rig.Parent = workspace
    pool[i] = rig
end
local attacker = game.Players:GetPlayers()[1].Character
return function(i)
    Combat.ResolveHit(attacker, pool[(i % #pool) + 1], "Sword")
end
```

Things that will bite:

- **Side effects accumulate.** 500 `ResolveHit`s might kill every dummy on call 3 and then
  early-return for the other 497 — then you've profiled the early return. Reset in the function
  (`humanoid.Health = 100`) or pick data that doesn't saturate.
- **Yielding functions.** If the function yields (`task.wait`, `:WaitForChild`, a remote
  `InvokeClient`), the profiler scope ends at the yield and the call takes longer than a frame.
  You'll see small scopes and a long wall time. Use `vmcp.Bench.Run` for wall time on those, and
  profile the non-yielding sub-functions instead.
- **`vm = "plugin"`** gives a fresh module copy with none of the game's state. Only for pure
  functions. It does put `vmcp` in scope, if you want `vmcp.Bench` or `vmcp.Remotes` in `setup`.

## Step 4 — profile

```json
{
  "targets": [
    {
      "label": "Combat.ResolveHit",
      "setup": "...the body above...",
      "calls": 600,
      "seconds": 2
    }
  ],
  "sections": [
    { "script": "ServerScriptService.Combat", "fromLine": 88, "toLine": 104, "label": "ResolveHit.partScan" },
    { "script": "ServerScriptService.Combat", "fromLine": 110, "toLine": 131, "label": "ResolveHit.applyDamage" }
  ],
  "where": "server",
  "frameLimit": 128,
  "name": "combat-before"
}
```

What happens, in order: sections are written into the scripts' Source in Studio; a playtest is
started (or restarted); the load runs in the live context with every call wrapped in
`debug.profilebegin(label)`; LibMP snapshots the last `frameLimit` frames; the snapshot is read and
written to `~/.vmcp/profiles/<name>-<label>.gprx`; the Sources are put back. Each target is its own
capture, run one after another.

### Sizing the load

The capture holds `frameLimit` frames, max 256. At 60 fps 128 frames is ~2.1s, 256 is ~4.3s.
Anything earlier is evicted and you'll be reading the tail of your load. So:

- `seconds` ≤ frames / 60. Default 2s with 128 frames is the right pairing. (The 60 is a
  playtest's frame rate; the edit DataModel runs far faster, which is why a capture taken there
  covers less wall time than you'd expect.)
- `calls / (seconds * 60)` is calls per frame; the tool computes it unless you set `perFrame`.
  20 calls per frame at 0.5ms each is 10ms per frame — visible, but not a lockup. If you want
  the "one call a frame, what does it cost" number instead, set `perFrame = 1` and lower `calls`.
- More frames means a bigger dump. Past ~4.5 MB it won't fit one socket message and the tool
  says so; lower `frameLimit` or raise `VMCP_MAX_MESSAGE_MB` on the server.
- `warmup` (default 5) runs first so the first-call lazy init isn't in the numbers.

### Sections — what they can and can't do

A section is `debug.profilebegin(label)` inserted **before** `fromLine` and `debug.profileend()`
inserted **after** `toLine`, in the Source Studio currently shows. Rules:

- Lines are 1-based and inclusive, against the Source **before** any instrumentation — several
  sections on one script are merged in one pass and can nest or sit side by side.
- Wrap **whole statements**. Ending inside an `if`/`for`/`function` body produces a syntax error
  and the playtest script fails to compile — you'll see it in `get_logs { context = "server" }`.
- Don't put a section around a range that can `return` early: the `profileend` is skipped. The
  engine closes open scopes when the thread yields or finishes, so it won't wedge the profiler,
  but the scope you read is wrong. Put the section *inside* the branch instead.
- A section inside a loop body gives you per-iteration scopes (`n` = iterations); around the loop
  gives one scope per call. Both are useful; the inner one tells you the per-iteration cost, the
  outer one the total. Do both in one call.
- A section across a yield gets split at the yield.
- Line numbers in error stack traces during the run are off by the number of inserted lines
  above them. Only during the run.
- The running playtest keeps the instrumented copies until it stops; Studio's Source is already
  back. That's harmless (they're just profiler calls) but it means a second `profile_scripts`
  without `sections` still shows the old labels until the playtest restarts.

### Reading the report

```
== Combat.ResolveHit ==
600 calls in 2.01s
capture: 128 frames over 2140ms -- CPU frame mean 16.7ms, p95 24.1ms, max 41.3ms (frame 87 / abs 12345)
Luau heap: 41.2 MB -> 47.9 MB (+6.7)

your labels (inclusive):
  ::Combat.ResolveHit        600 calls  total 1810.20ms  avg 3.02ms  max 9.80ms  worst frame 31.10ms (frame 87 / abs 12345)
  ::ResolveHit.partScan      600 calls  total 1602.11ms  avg 2.67ms  max 9.10ms  worst frame 28.00ms (frame 87 / abs 12345)
  ::ResolveHit.applyDamage   600 calls  total   96.40ms  avg 0.16ms  max 0.90ms  worst frame  2.10ms (frame 40 / abs 12298)

top 15 scopes by self time, all CPU threads (inclusive in brackets):
   1.  1590.30ms  ::ResolveHit.partScan   [Script]  (incl 1602.11ms)  n=600  max 9.10ms
   2.   402.10ms  Physics/stepWorld       [Physics] (incl 640.00ms)   n=128  max 8.20ms
   3.   210.55ms  $Script                 [Script]  (incl 2030.00ms)  n=1930 max 12.00ms
   4.   180.00ms  Lua/GC                  [Lua]     ...
   ...

slowest frames and what filled them (self time):
  frame 87 / abs 12345: 41.30ms -- ::ResolveHit.partScan 28.00ms, Physics/stepWorld 6.10ms, Lua/GC 3.20ms, ...
```

How to read it:

- **Self time** is what a scope spent *not* in a child scope. Inclusive is self + children. Rank by
  self; a parent with big inclusive and small self is just a container. Your function label's
  inclusive is the whole call; the section labels under it tell you which part.
- **Worst frame** is the number a player feels. 3ms average with a 31ms worst frame is a hitch,
  not a steady cost — look at what else is in that frame (the "slowest frames" list) before
  blaming the function: GC, physics, a replication burst, all land in the same frame.
- **Your labels come back as `::label`** — the engine files every `debug.profilebegin` scope
  under a `::` prefix. The report's "your labels" block matches them with or without it; when you
  search a session yourself, `FindTimerId("::ResolveHit.partScan", true)` is the exact name.
- **`Sleep` [Runtime] at the top of the self-time list** is the engine idling until the next
  frame — headroom, not cost. If it's the biggest thing, the load you sent wasn't heavy enough to
  matter at this frame rate. Ignore it and read the next rows; don't try to optimize it away.
- **`$Script`** is every un-labelled Luau scope — the engine can't tell you which script.
  Big `$Script` self time means there's hot code you haven't labelled yet. Add sections.
- **`Lua/GC` / `Luau/GC`** climbing with a rising heap delta means the function allocates. The fix is
  in the allocation, not in the GC.
- **Heap delta** over 2 seconds is a leak or churn. +6.7 MB for 600 calls is ~11 KB a call —
  look for tables/strings/instances created per call.
- **Frame ids**: `frame N` is the index in the capture, `abs M` is the engine's frame number. Use
  both when you tell the user; abs is what the MicroProfiler UI shows.
- **Physics/Render/Network groups** in the top list that have nothing to do with your load are
  the baseline cost of the place. Note them but don't chase them in a script pass; if
  `Physics/stepWorld` is 40% of every frame, that's a separate conversation about the map.
- `n=` is closed scope instances; scopes still open at a frame boundary count their time in that
  frame but not in `n`.
- `errored` in the load line means your fake data hit an error path — you profiled the error
  path. Fix `setup` and rerun.

### Digging deeper

The last capture stays in memory in the context that took it. `run_luau { context = "server" }`
(plugin VM — the default) gets:

```lua
local session = vmcp.Profile.Session()          -- LibMP session over the last capture
local lib = vmcp.Profile.LibMP()                -- the LibMP module itself
local report = vmcp.Profile.Analyze(vmcp.Profile.LastBuffer, { labels = { "X" }, top = 40 })
return vmcp.Profile.Summarise(report)
```

Useful LibMP snippets against that session (everything on `session` is `:` calls; constructors are `.`):

```lua
-- the scope tree of one frame, one thread, indented -- what actually ran in the spike
local frameId = 87
local tickToMs = session:FetchGlobalDesc().TickToMsCpu
local iter = session:CreateLogIterator()
iter:Configure({ SkipGpuThreads = true, SkipEvents = true, EmitThreadFrameEnd = true })
local state = iter:GetState()
local lines = {}
iter:RewindTo(frameId, frameId)
while iter:Step() do
    if state:IsExit() and not state:ThreadStackIsUnderflowed() and not state:ThreadStackWasOverflowed() then
        local depth = state:ThreadStackDepth()
        local el = iter:GetCurrentThreadStackElement(depth)
        local ms = (state:Timestamp() - el:EnterTimestampFrameLocal()) * tickToMs
        if ms > 0.2 then
            local name = session:FetchTimerDesc(state:TimerId()).TimerName
            local thread = session:FetchThreadDesc(state:ThreadId()).ThreadName
            table.insert(lines, string.rep("  ", depth) .. string.format("%.2fms %s [%s]", ms, name, thread))
        end
    end
end
iter:Dispose()
session:Dispose()
return table.concat(lines, "\n")
```

```lua
-- every counter under Luau, last value -- memory by category
local out = {}
local cIter = session:CreateCounterIterator()
local cState = cIter:GetState()
cIter:Configure({ RootCounterIds = { session:FindCounterId("**/Luau") } })
while cIter:Step() do
    local id = cState:CounterId()
    local sample = session:FetchLastCounterSample(id)
    table.insert(out, string.rep("  ", cState:RelativeLevel()) .. session:FetchCounterDesc(id).CounterName
        .. " = " .. (sample and string.format("%.2f", sample.Value) or "-"))
end
cIter:Dispose()
session:Dispose()
return table.concat(out, "\n")
```

```lua
-- per-frame time of one timer across the capture, to see whether it's steady or spiky
local timerId = session:FindTimerId("ResolveHit.partScan", true)
local tickToMs = session:FetchGlobalDesc().TickToMsCpu
local perFrame = {}
local iter = session:CreateLogIterator()
iter:Configure({ SkipGpuThreads = true, SkipEvents = true, EmitThreadFrameEnd = true, TimerIds = { timerId } })
local state = iter:GetState()
iter:RewindTo(session:GetFrameIdMin(), session:GetFrameIdMax())
while iter:Step() do
    if state:IsExit() and not state:ThreadStackIsUnderflowed() then
        local el = iter:GetCurrentThreadStackElement(state:ThreadStackDepth())
        local f = state:FrameId()
        perFrame[f] = (perFrame[f] or 0) + (state:Timestamp() - el:EnterTimestampFrameLocal()) * tickToMs
    end
end
iter:Dispose()
session:Dispose()
return perFrame
```

LibMP cheat sheet, the parts you'll use:

- `LibMP.Control` — `:EnableProfiler(b)`, `:EnableCapture(b)`, `:SetFrameLimit(n ≤ 256)`,
  `:CaptureToBufferSync() -> buffer`, `:ShowUI(b)` (Studio overlay), `:IsBackendReady()`.
- `LibMP.Session.OpenFromBuffer(buf)` / `.OpenFromLiveData()` / `.OpenFromFile(path)` (Lute only).
  Always `session:Dispose()`; iterators first.
- `session:GetFrameIdMin()/Max()`, `:FetchFrameDesc(id)` → `TickStartCpu, TickEndCpu, FrameAbsoluteId,
  IsIncomplete`; `:FetchGlobalDesc().TickToMsCpu` converts ticks to ms.
- `:FindTimerId(mask, caseSensitive)`, `:FindTimerIds("*physics*|*render*")`, `:FetchTimerDesc(id)`
  → `TimerName, GroupId`; `:FetchGroupDesc(id).GroupName`; `:FetchThreadDesc(id).ThreadName`.
- `:FindCounterId("**/Luau/heap")` (glob paths: `*` one level, `**` any depth, `name$` leaf,
  `a|b` union); `:FetchCounterSamples(id)` → `{ {FrameId, Value} }`; `:FetchLastCounterSample(id)`.
- `:CreateLogIterator()` → `:Configure({ StartFrameId, EndFrameId, SkipGpuThreads, SkipEvents,
  EmitThreadFrameEnd, ThreadIds, GroupIds, TimerIds, SkipTimerIds })`, `:RewindTo(a, b)`, `:Step()`,
  `:GetState()` (one view, read on every step: `IsEnter/IsExit/IsThreadFrameEnd/IsFrameBoundary`,
  `FrameId/FrameAbsoluteId/ThreadId/TimerId/Timestamp/ThreadStackDepth/ThreadStackIsUnderflowed/
  ThreadStackWasOverflowed`), `:GetCurrentThreadStackElement(level)` → `EnterTimerId/EnterTimestamp/
  EnterTimestampFrameLocal/EnterFrameId`.
- Scopes cross frames: use `EnterTimestampFrameLocal` (clamped to the frame start) and handle
  `IsThreadFrameEnd` for scopes still open — that's what `Profile.Analyze` does.
- `Fetch*` returns plain tables (use these). `Get*` returns views invalidated by the next call —
  don't hold them.
- Automatic script scopes are `$Script`; only `debug.profilebegin` labels carry your names.

Offline: the `.gprx` in `~/.vmcp/profiles/` opens in Lute (github.com/luau-lang/lute) with
`require("./LibMP").Session.OpenFromFile(path)` and the same API. Use it when the capture is
bigger than you want to hold in Studio, or to diff two captures side by side.

## Step 5 — write the fix

Order of things to try, cheapest and safest first. Each one keeps behaviour identical when done
right; the note says what to watch.

1. **Do it less often.** Move per-frame work to an event (`:GetPropertyChangedSignal`,
   `.Changed`, `CollectionService` tag signals, `PlayerAdded`), or throttle to every N frames
   with an accumulator. Watch: things that relied on "eventually every frame" ordering.
2. **Hoist out of the loop.** Property reads (`part.CFrame`, `humanoid.Health`), service
   lookups, `GetDescendants`, `require`, `string.format` of constants, `Vector3.new` of constants.
   Watch: a property that the loop body itself mutates.
3. **Replace the tree walk.** `GetDescendants()` + `IsA` filter → `QueryDescendants("Class.Tag")`
   once, or `CollectionService:GetTagged` kept in a set updated by `GetInstanceAddedSignal`/
   `RemovedSignal`. Watch: instances added mid-frame.
4. **Replace the linear scan.** `table.find` / `for ... if v.Name ==` inside a hot path → a dict
   keyed by the thing you look up, built once and maintained. Watch: keys that change.
5. **Stop allocating.** Reuse a scratch table (`table.clear`), `table.create(n)` when the size is
   known, a `buffer` for dense numeric data, `string.format` once instead of `..` in a loop,
   `Vector3` math via the `vector` library. Watch: a reused table escaping to a caller who keeps it.
6. **Batch instance writes.** One `PivotTo` instead of per-part `CFrame`, `BulkMoveTo` for many
   parts, set `Parent` last when building. Watch: order-dependent replication (a client seeing
   the part before its properties).
7. **Cheaper primitives.** `WorldRoot:Raycast` with a tight `RaycastParams` and a filter list
   instead of a broad one; `GetPartBoundsInBox` with `OverlapParams.MaxParts`; `workspace:
   GetPartsInPart` avoided on complex meshes. Watch: results that differ at the edges.
8. **Move it off the main thread.** `Actor` + `task.desynchronize` for pure computation over
   many entities (pathing scores, LOS checks). Watch: anything touching instances must be inside
   `task.synchronize`.
9. **`--!native` and `--!optimize 2`** at the top of a hot module. Free for numeric loops; doesn't
   help instance-heavy code. Watch: nothing, but measure — sometimes it's zero.
10. **`pcall` in the wrong place.** Wrap the batch, not the element. Watch: an element that
    errors now aborts the batch — different behaviour, name it.

Keep the fix **local**: same file, same function, same signature. A fix that needs a new module,
a changed call site, or a different data shape is a design change; propose it, don't do it inside
this loop.

### Where the candidate lives

Never edit the real script to test the fix. Put the candidate in a ModuleScript **created inside
the playtest** via `run_luau { context = "server" }` — it exists only in that DataModel and is gone
when the playtest stops:

```lua
local m = Instance.new("ModuleScript")
m.Name = "Combat_Candidate"
m.Source = [==[
-- the whole original module, with the fix applied
...
]==]
m.Parent = game:GetService("ServerStorage")
return m:GetFullName()
```

If the function depends on the module's private state, copy the entire module so the candidate
has the same upvalues, not just the function. If it depends on *live* state (a table the game
filled at startup), read it from the live module in `setup` and pass it in — or, if it's a plain
data table, `require` the live module and hand the candidate the same reference.

## Step 6 — benchmark old vs new

One `profile_scripts` call, two targets, **identical** `setup` apart from which module they require,
same `calls`, same `seconds`, same pool of fake data. Label them so the report reads itself:

```json
{
  "targets": [
    { "label": "ResolveHit.old", "setup": "local M = require(game.ServerScriptService.Combat) ...", "calls": 600, "seconds": 2 },
    { "label": "ResolveHit.new", "setup": "local M = require(game.ServerStorage.Combat_Candidate) ...", "calls": 600, "seconds": 2 }
  ],
  "name": "combat-compare"
}
```

Run it **twice** and use the second run. The first run after creating the candidate includes its
compile and whatever lazy init your change has.

Numbers to compare, in this order: worst frame, p95 frame time, avg per call, heap delta. A change
that improves the average and worsens the worst frame is a regression. A change that halves
per-call time and adds 4 MB of heap is trading CPU for GC and will show up as hitches later.

If the gain is under ~15% per call and nothing in the worst frame moved, it isn't worth the risk
of any change. Say that.

### Prove the outputs match

Same inputs into both, compare results. Deterministic functions: one `run_luau` in the game VM:

```lua
local Old = require(game.ServerScriptService.Combat)
local New = require(game.ServerStorage.Combat_Candidate)
local mismatches = {}
for i = 1, 200 do
    local args = makeArgs(i)           -- the same generator setup used
    local a = { Old.ResolveHit(table.unpack(args)) }
    local b = { New.ResolveHit(table.unpack(args)) }
    if game:GetService("HttpService"):JSONEncode(a) ~= game:GetService("HttpService"):JSONEncode(b) then
        table.insert(mismatches, i)
    end
end
return #mismatches == 0 and "identical over 200 inputs" or mismatches
```

Functions with side effects: compare the **state after**, not the return — humanoid health, the
table the module holds, instances created, remotes fired (`vmcp.Remotes.WatchAll` then
`Remotes.Calls()` for each version). A `run_timeline` with a `server` event per version and an
`assertion` at the end is the tidy way; `vmcp-timeline` has the shape.

Error paths too: feed both versions the bad input the real callers can send (nil, wrong type, a
dead character). Same error, or same silent return. Different is a behaviour change — name it.

## Step 7 — verify the game still works

Even though the real script hasn't changed yet, do a pass as if it had — you're about to
recommend it:

- `search_scripts { drift = true }` — Studio and disk agree, i.e. the instrumentation really was
  reverted and nothing else moved.
- `get_logs { context = "server" }` and `{ context = "client" }` — no errors from the profiling run
  left behind (a dummy that never got cleaned up, a candidate module something else found by name).
- Destroy anything `setup` created in the world, or just stop the playtest.

If the user asked you to **apply** the fix (Step 8 said yes): edit the source file on disk — this is
a Rojo project, Studio's copy follows — then `search_scripts { drift = true }` to confirm it synced,
then a `run_timeline` that exercises the real call path (a client firing the real remote, a
server event reading the result), then stop and **tell the user to playtest**. Don't start the
next script until they've come back.

## Step 8 — report

Written for the user, not for you. Plain words, no jargon they'd have to look up, the numbers
inline. Shape:

```
**ServerScriptService.Combat — ResolveHit**

What's slow: the part scan on lines 88–104 walks every descendant of the target rig on every hit
to find hitboxes. That's ~2.7ms a call, and with a few players swinging it was the biggest thing
in the worst frames (28ms of a 41ms frame).

Fix: tag hitbox parts once when a rig spawns (CollectionService "Hitbox") and read
GetTagged inside ResolveHit instead of GetDescendants + IsA. Same parts come back, same order
they're found in the rig. 14 lines change, all inside ResolveHit.

Numbers (600 calls, 2s, same fake data):
  old  avg 3.02ms/call   worst frame 31.1ms   heap +6.7 MB
  new  avg 0.41ms/call   worst frame  6.8ms   heap +0.4 MB

Behaviour: identical over 200 random inputs and the three error cases (nil target, dead target,
target with no hitboxes). One thing you should know: the old code warned "no hitboxes" via warn()
on every miss; the new code warns once per rig. Not a gameplay change, but it's a change.

Risk: rigs created without the tag won't register hits. Everything that creates a rig goes through
Spawner.Make, so tagging there covers it — but if there's a path I couldn't see, that's the hole.

The original code is back in place. Want me to apply this? I'll make the change and stop so you
can playtest.
```

Every report has those six parts: what's slow (with lines), the fix, before/after numbers, the
behaviour statement (including "identical" and every deviation however small), the risk, and the
offer. If you found a bug on the way — even one you didn't fix — it goes in a seventh line.

## Then

After the report, one of three things, and say which:

- **Continue** to the next script in the `count_lines` list on your own, if the user told you to
  work through the list. Say which one you're doing next and why.
- **Ask** where to go next when the list has no obvious next candidate, or when the next candidate
  is a different kind of problem (physics, rendering, network) that a script pass won't fix.
- **Pause** after applying any fix, so the user can playtest. Always. The verification in Step 7
  is not a substitute for a human playing the game.

If you're continuing, reuse the running playtest — it's already up — unless the next script needs
`sections`, which restarts it.

## Gotchas, all in one place

- **No labels in the report** → the function never ran (setup errored, check the load line), the
  label has a typo, the capture evicted it (load longer than frameLimit), or the scope was in a
  context you didn't capture (`where`). In Play Solo server and client are one DataModel, so
  `where = "server"` sees both.
- **`$Script` dominates** → un-labelled Luau. Add sections, or the cost is in a script you haven't
  looked at yet: use `get_logs` and `search_scripts` for other `Heartbeat` connections.
- **Worst frame is nowhere near your label** → your function isn't the problem; the spike is
  physics, GC, rendering, or a different script. Say so; don't optimize the thing you were asked
  about if it isn't the thing.
- **Heap climbs every run and never drops** → leak. Connections not disconnected, tables keyed by
  instances that are gone, `Clone()` without `Destroy()`. Profile the *cleanup* path too.
- **LibMP won't load** → wrong version for this Studio build (`IsBackendReady()` false), or it was
  pasted into a script with script analysis on and Studio truncated it. Get the release file.
- **Capture too big** → lower `frameLimit`, or fewer threads' worth of work in the frame (stop
  other test clients).
- **`sections` failed with a syntax error** → the range ended mid-block. `get_logs` shows the
  script's compile error with the (shifted) line.
- **Playtest restart lost state** → the user had something set up in a running playtest and
  `sections` restarted it. Warn before calling with `sections` when a playtest is already up.
- **Studio's copy of the script isn't the one on disk** → `search_scripts { drift = true }` before
  you read lines for `sections`; line numbers must match what Studio has.
- **The function is a method on an object** → `setup` builds or fetches the object and returns a
  closure: `return function() obj:Method(args) end`.
- **Time is in a yield** → profiler scopes end at yields. `vmcp.Bench.Run` for wall time; profile the
  non-yielding pieces separately.
- **Numbers look impossibly small** → the function early-returned on your fake data. Check the
  section labels inside it ran (`n` > 0).
- **Two Studio windows** → the plugin's playtest belongs to whichever window connected last. Close
  the other one.
