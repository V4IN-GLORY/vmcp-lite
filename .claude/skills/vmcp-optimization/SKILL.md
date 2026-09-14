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
  -> report in plain words
  -> try_scripts: a playtest running the candidate, nothing saved -- the user plays it
  -> they say yes: apply to disk; they say no or find a break: stop the playtest, it's gone
  -> next script, or pause
```

Load `vmcp-debugging` and `vmcp-timeline` alongside this — `vm = "game"`, `ctx`, `Remotes.WatchAll`
and `Bench` are all used below and explained there.

## Reference files — open on demand, not up front

The full LibMP documentation ships next to this file under `references/`. It's ~400 KB, so it's
split by what you'd be asking. Read the one file you need with the Read tool when you reach that
point; don't load them all.

| when | open |
|---|---|
| you're writing your own LibMP snippet against `vmcp.Profile.Session()` and the cheat sheet in Step 4 isn't enough — iterator config flags, state getters, frame-boundary handling, `Get` vs `Fetch` | `references/libmp-guide.md` (concepts + the three reference iterators: simple, frame-local, full-reconstruct) |
| you need an exact method signature, return type, or a struct's fields | `references/libmp-api.md` |
| an engine scope you don't recognise is in the top list or a spike frame (`Physics/stepWorld`, `TS::JobStep`, `MegaReplicator::...`, `Lua/GC`, `Present`, `Sleep`) and you need to know what it is, what drives its cost, and whether the creator can do anything about it | `references/scopes/INDEX.md` first — grep the scope name there to find its group — then that group's file (`scopes/physics.md`, `scopes/render.md`, `scopes/script.md`, `scopes/network.md`, …) |
| you want a working end-to-end example rather than a fragment | `references/examples/` — `04-basic-iteration.luau` (one frame, one thread), `05-advanced-iteration.luau` (the reusable iterator module), `06-advanced-frame-stats.luau` (per-timer inclusive times, top 20), `07-advanced-counter.luau` (counter tree), `09-usecase-snapshot-analyzer.luau` (analysis spread over frames so it doesn't hitch) |

The scope files are the part that turns "this scope is 6ms" into "and here's why, and here's the
lever". `scopes/script.md` covers everything Luau-side: `$Script`, GC scopes, parallel VMs,
`CollectionService`, deferred events. `scopes/physics.md` is where `stepWorld`, broadphase,
humanoid stepping and raycasts live. `scopes/render.md` / `scopes/gpu.md` for anything under
`Render`/`Present`. `scopes/network.md` for replication and streaming. `scopes/jobs.md` for the
`TS::` task-scheduler scopes that wrap everything else. `scopes/profiler-runtime.md` explains
`Sleep` and the profiler's own overhead.

## Ground rules

- **One call per question, not per step.** Every tool call re-sends the conversation. Put all
  the functions you want numbers for in one `profile_scripts` (up to 8 targets, all the
  sections at once). Plant the candidate, hammer old and new, diff the outputs and check the
  logs in **one** `run_timeline` (Step 6 has the template). Read scripts from disk with the Read
  tool — this is a Rojo project, the source is right there — instead of asking Studio for it.
  When you need three facts from the live game, one `run_luau` that returns a table with three
  fields, never three calls. If you catch yourself about to make a second call to the same
  context, fold it into the first.
- **Never change behaviour.** Not "mostly the same" — the same. Same return values, same order of
  side effects, same events fired, same errors on bad input. If the faster version can't do that,
  say so and let the user decide.
- **Every change gets named.** If you fix a bug you tripped over, or a fast path skips a `warn`
  that used to fire, the user hears about it even when it's irrelevant. They own the game; you
  don't get to decide what's irrelevant.
- **Nothing is applied until the user has played it.** The loop ends with a written
  recommendation and a playtest running the candidate via `try_scripts` — the place, Studio and
  disk all still hold the original. The user plays; if it's fine they say so and *then* you edit
  the file. If they find a break, stopping the playtest is the whole revert.
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

Read the whole script **from disk** (Read tool on the file Rojo syncs it from — free, no tool
round-trip; `search_scripts { drift = true }` once if you doubt Studio matches). Then read what it
requires and who requires it (Grep on the repo for callers; `search_scripts` only when the thing
you're after was made in Studio and isn't on disk). You need the stack — a function that looks cheap can be called 300
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

Put **every** function from the script you're examining in the one call — up to 8 targets, each
its own capture — and every section you want, in the same call. A second `profile_scripts` for
the function you forgot costs a full round-trip of everything above it. If you want a deeper
LibMP walk of the capture as well, do it in the same reply's next `run_luau`, not after reading
the report and thinking about it: ask for `top = 40` up front instead.

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
(plugin VM — the default) gets these — and if you already know you'll want two of them, put both
in one snippet returning one table:

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

Write the candidate as the **whole module with the fix applied** — you'll paste it into the
timeline below as a long string. If the function depends on the module's private upvalues, the
whole-module copy is what makes those exist. If it depends on *live* state the game filled at
startup, read it from the live module in `setup` and pass it in.

## Step 6 — benchmark, compare, verify: one timeline

This is where token discipline pays. Planting the candidate, hammering old and new, proving the
outputs match, checking state, and checking logs is **one `run_timeline` call**, not five. The
candidate ModuleScript is created inside the playtest (never in the real place), `vmcp.Profile.Hammer`
is the same code `profile_scripts` runs, and the assertion judges the whole thing.

```json
{
  "players": 1,
  "keepOpen": true,
  "events": [
    {
      "at": 0, "context": "server", "blocking": true, "label": "plant + hammer + compare",
      "code": "local SS = game:GetService('ServerStorage')\nlocal HS = game:GetService('HttpService')\n\n-- 1. the candidate, playtest-only\nlocal m = Instance.new('ModuleScript')\nm.Name = 'Combat_Candidate'\nm.Source = [==[\n... the whole module with the fix applied ...\n]==]\nm.Parent = SS\n\n-- 2. shared fake data, built once so both versions see the same thing\nlocal setup = [[\n  local pool = {}\n  for i = 1, 8 do\n    local rig = game.ServerStorage.Rigs.Dummy:Clone()\n    rig:PivotTo(CFrame.new(i * 6, 5, 0)); rig.Parent = workspace; pool[i] = rig\n  end\n  local attacker = game.Players:GetPlayers()[1].Character\n  return function(i)\n    local target = pool[(i % #pool) + 1]\n    target.Humanoid.Health = 100\n    M.ResolveHit(attacker, target, 'Sword')\n  end\n]]\nlocal old = 'local M = require(game.ServerScriptService.Combat)\\n' .. setup\nlocal new = 'local M = require(game.ServerStorage.Combat_Candidate)\\n' .. setup\n\n-- 3. warm both (first run carries compile + lazy init), then the run that counts\nvmcp.Profile.Hammer({ { label = 'warm.old', setup = old, calls = 50, seconds = 0.5 }, { label = 'warm.new', setup = new, calls = 50, seconds = 0.5 } }, { dump = false, top = 1 })\nlocal report = vmcp.Profile.Hammer({\n  { label = 'ResolveHit.old', setup = old, calls = 600, seconds = 2 },\n  { label = 'ResolveHit.new', setup = new, calls = 600, seconds = 2 },\n}, { name = 'combat-compare', top = 12, labels = { 'ResolveHit.partScan', 'ResolveHit.applyDamage' } })\nctx.report = report\n\n-- 4. same inputs into both, compare results and the state they leave behind\nlocal ok, mismatches = vmcp.Game.Eval([[\n  local Old = require(game.ServerScriptService.Combat)\n  local New = require(game.ServerStorage.Combat_Candidate)\n  local HS = game:GetService('HttpService')\n  local bad = {}\n  for i = 1, 200 do\n    local a = { Old.ResolveHit(makeArgs(i)) }\n    local b = { New.ResolveHit(makeArgs(i)) }\n    if HS:JSONEncode(a) ~= HS:JSONEncode(b) then table.insert(bad, i) end\n  end\n  for _, args in { {nil}, {'x'}, {deadRig} } do  -- the error paths real callers can hit\n    local ea = select(2, pcall(Old.ResolveHit, table.unpack(args)))\n    local eb = select(2, pcall(New.ResolveHit, table.unpack(args)))\n    if tostring(ea) ~= tostring(eb) then table.insert(bad, 'err:' .. tostring(ea) .. ' vs ' .. tostring(eb)) end\n  end\n  return HS:JSONEncode(bad)\n]])\nctx.mismatches = if ok then HS:JSONDecode(mismatches) else { 'eval failed: ' .. tostring(mismatches) }\n\n-- 5. leave nothing behind\nfor _, rig in workspace:GetChildren() do if rig.Name == 'Dummy' then rig:Destroy() end end\nm:Destroy()"
    },
    {
      "at": 0.5, "context": "plugin", "label": "verify",
      "code": "local _, drift = vmcp.Tool('search_scripts', { drift = true })\nlocal _, logs = vmcp.Tool('get_logs', { context = 'server' })\nctx.drift = drift\nctx.serverErrors = select(2, logs:gsub('%[error%]', ''))"
    }
  ],
  "assertion": "return #ctx.mismatches == 0 and ctx.serverErrors == 0 and ctx.drift:find('agree') ~= nil"
}
```

What that buys you: one reply holding the old/new report, the output diff, the drift check and
the server error count. The event is `blocking` because `Hammer` yields for the whole load;
`0.5` on the plugin event is "after it", not a real delay.

Notes on the template:

- `keepOpen: true` because you'll likely run a second timeline (a different fix, a different
  script) and a playtest costs seconds to start. `try_scripts` in Step 7 restarts it anyway.
- The candidate goes in `ServerStorage` **inside the playtest**. Nothing is saved; `m:Destroy()`
  at the end is tidiness, not safety.
- `vmcp.Profile.Hammer(targets, { vm, env, frameLimit, top, dump, name, labels })` is the
  playtest half of `profile_scripts`. Same targets shape, same report text. `labels` adds section
  names to the "your labels" block — sections still need the `profile_scripts` tool once to be
  written in, since only the edit session can edit Source; after that the running playtest keeps
  them and every `Hammer` sees them.
- `vmcp.Game.Eval` runs in the game VM and only returns text — encode the answer as JSON on that
  side and decode it here.
- Side-effect functions: compare the **state after**, not the return. Read the humanoid, the
  module's table, `vmcp.Remotes.Calls()` for each version, and push those through `ctx` too.
- Run the timeline **twice** only if the numbers look off; the warm pass inside it already covers
  compile and lazy init.

Numbers to compare, in this order: worst frame, p95 frame time, avg per call, heap delta. A change
that improves the average and worsens the worst frame is a regression. A change that halves
per-call time and adds 4 MB of heap is trading CPU for GC and will show up as hitches later.

If the gain is under ~15% per call and nothing in the worst frame moved, it isn't worth the risk
of any change. Say that.

## Step 7 — let the user play the candidate

The report goes out first (Step 8 — write it now, hand it over with this). Then, in the same
reply, start the playtest that runs the fix:

```json
{ "scripts": [ { "script": "ServerScriptService.Combat", "source": "...the whole module with the fix..." } ] }
```

`try_scripts` writes the replacement into Studio for the few seconds the playtest takes to boot,
then puts the original back; the playtest keeps the swapped copy. The place isn't marked changed
in any way that survives, nothing reaches disk, and Rojo never sees it. Every script the fix
touches goes in the one call. If a playtest is already up, it's restarted — say so.

Then **stop and wait**. Tell the user what to try: the specific flows that go through the
changed function, plus whatever the error-path check in Step 6 covered. Ask them to hit Stop (or
say so, and you call `playtest { action = "stop" }`) when they're done — that's the revert.

- **They say it's fine** → edit the source file on disk (this is a Rojo project; Studio follows),
  then one `run_timeline`: `plugin` event for `search_scripts { drift = true }`, a `client` event
  that fires the real remote the way a player would, a `server` event that reads the result, an
  `assertion`. Report the outcome. Only now is anything changed.
- **They find a break** → the playtest gets stopped, the original is everywhere, and you have a
  bug report against the candidate. Fix it, back to Step 6, new `try_scripts`.
- **They don't answer** → nothing happened. That's the point.

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

Nothing is changed yet. I've started a playtest with the new version in — swing at a few dummies,
try a hit on a dead target, whatever you'd normally do. Hit Stop when you're done and the original
is back; tell me it's fine and I'll write it to Combat.luau.
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
- **Pause** after every `try_scripts`, and again after applying. Always. The checks in Step 6
  are not a substitute for a human playing the game with the new code in.

If you're continuing, reuse the running playtest — it's already up — unless the next script needs
`sections`, which restarts it. And batch across scripts too: if two scripts' suspect functions
are independent, they go in one `profile_scripts` call, and their candidates can share one
timeline with one `Hammer` call carrying four targets.

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
  `sections` or `try_scripts` restarted it. Warn before either when a playtest is already up.
- **Two Studio windows** → playtest DataModels attach to whichever window's plugin connected
  last, so `where = "server"` can point at the wrong window's test and the first window's socket
  can drop when a test starts. One Studio window while profiling.
- **Studio's copy of the script isn't the one on disk** → `search_scripts { drift = true }` before
  you read lines for `sections`; line numbers must match what Studio has.
- **The function is a method on an object** → `setup` builds or fetches the object and returns a
  closure: `return function() obj:Method(args) end`.
- **Time is in a yield** → profiler scopes end at yields. `vmcp.Bench.Run` for wall time; profile the
  non-yielding pieces separately.
- **Numbers look impossibly small** → the function early-returned on your fake data. Check the
  section labels inside it ran (`n` > 0).
