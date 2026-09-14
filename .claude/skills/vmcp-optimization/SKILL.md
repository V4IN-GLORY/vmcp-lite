---
name: vmcp-optimization
description: Finding and fixing frame-time problems in a Roblox game with VMCP — a real-load MicroProfiler baseline (profile_scripts observe, multi-client load), a hot-path lint and line/hot-column ranking, per-function auto-instrumentation and targeted hammering with LibMP captures and .gprx dumps, self vs inclusive time and allocation per call, a candidate fix benchmarked and proven equivalent in one timeline (Profile.Hammer, Profile.Compare, Equiv.Check), handed to the user in a playtest before anything is written (try_scripts), applied with an automatic revert (apply_fix), and tracked per place (optimization_ledger). Use for "why is this laggy", "optimize this script", "what's eating frame time", or any performance pass on a live place.
---

# Optimizing a game with VMCP

This is a loop, not a checklist. Each pass takes one script from "suspect" to "applied or
rejected", and the game must behave identically when you're done — the only thing you're allowed
to change is how long it takes.

```
ask what to look at                 -- one question, up front; "just find it" is a valid answer
  -> optimization_ledger read       -- what a previous pass already did
  -> profile_scripts { observe }    -- the real-load baseline, with the game driven to the thing under test
  -> lint_hotpaths + count_lines    -- the shortlist, ranked by how often it runs
  -> read the script (from disk)    -- the callers, the callees, the state it needs
  -> profile_scripts { autoSections, targets }   -- which function, which lines, how much, how often
  -> write the candidate            -- whole module, same signature, same behaviour
  -> run_timeline                   -- Hammer old vs new, Compare, Equiv.Check, one call
  -> report, then try_scripts       -- the user plays the candidate; nothing is saved
  -> apply_fix { check }            -- only after yes; reverts itself if anything fails
  -> optimization_ledger write      -- close the script out; next one, or pause
```

Load `vmcp-debugging` and `vmcp-timeline` alongside this — `vm = "game"`, `ctx`, `input`,
`Remotes.WatchAll` and `Bench` are all used below and explained there.

## The tools and the library

| tool | what it does | when |
|---|---|---|
| `optimization_ledger` | per-place record: which scripts were profiled, proposed, applied, rejected, with numbers | first call of a pass; last call per script |
| `profile_scripts { observe }` | captures the game **running on its own** for N seconds and reports the top scopes | the baseline, before you touch anything |
| `lint_hotpaths` | static shortlist: tree walks / allocation / string building / physics queries / connections inside per-frame handlers and loops, polling loops, legacy `wait`, deep paths | right after the baseline; no playtest needed |
| `count_lines` | scripts by size with a hot column (per-frame connections, while-true loops) | same time as lint; ordering only |
| `profile_scripts { autoSections }` | every named function in a script gets its own scope, labelled `Script.fn` | "this script is slow" → "it's this function", one call |
| `profile_scripts { targets, sections }` | hammer named functions with fake data, bracket line ranges | zooming in; per-call cost, allocation per call, worst frame |
| `try_scripts` | playtest running your candidate Source; nothing saved anywhere | after the report, before the user says yes |
| `apply_fix` | writes the file on disk, waits for Rojo, restarts the playtest, runs your check with the previous version planted beside it, **reverts itself on any failure** | after the user says yes |

In `run_luau` and timeline events, `vmcp` carries the same machinery so a whole comparison is one
call:

| library | use |
|---|---|
| `vmcp.Profile.Hammer(targets, opts) -> text, failed, outcomes` | the playtest half of `profile_scripts`; `outcomes[label]` has `calls, allocatedKbPerCall, report` |
| `vmcp.Profile.Compare(outcomes.old, outcomes.new) -> delta` | ratios for per-call, worst frame, p95, allocation, heap; `delta.better`, `delta.text` |
| `vmcp.Profile.Observe(seconds, opts) -> text, report` | the baseline capture from inside a timeline |
| `vmcp.Profile.Session()` / `.LibMP()` / `.LastBuffer` | reopen the last capture and walk it with LibMP directly |
| `vmcp.Equiv.Check(old, new, generate, opts) -> result` | same inputs into both: returns, errors, state; plus broken-argument probes. In the game VM it's `require(<container>.__VMCP_Equiv)` next to the game bridge |
| `vmcp.Load.Wander(input, opts)` | client event: walk, jump, fire remotes for N seconds, so a capture has real players in it |
| `vmcp.Lint.Script(source)`, `vmcp.Instrument.Functions(source, prefix)` | the lint and the auto-instrumenter as functions, for a script that only exists in a timeline |

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

- **One call per question, not per step.** Every tool call re-sends the conversation. All the
  functions you want numbers for go in one `profile_scripts` (8 targets, every section, every
  `autoSections` script). Candidate + old/new hammer + Compare + Equiv + logs is **one**
  `run_timeline` (Step 6). Read scripts from disk with the Read tool — this is a Rojo project —
  instead of asking Studio. Three facts from the live game is one `run_luau` returning a table.
- **Measure the real thing first.** A hammered function tells you what a function *costs*; only
  the observed baseline tells you what the game *spends*. Optimizing the wrong function perfectly
  is the most expensive mistake this loop can make.
- **Never change behaviour.** Same return values, same order of side effects, same events fired,
  same errors on bad input. `Equiv.Check` is how you know, not how you feel about it.
- **Every change gets named.** A bug you tripped over, a `warn` that fires once instead of every
  time, an error message that reads differently — the user hears about it even when it's
  irrelevant. They own the game; you don't get to decide what's irrelevant.
- **Nothing is applied until the user has played it.** Report, `try_scripts`, wait. Then
  `apply_fix`, which reverts itself if the check or the logs say no.
- **Read p95 and worst frame, not mean.** A function whose mean is fine and whose worst frame is
  30ms is the one players feel.
- **Don't hammer things that talk to the outside world.** DataStore, HttpService, MessagingService,
  MarketplaceService, TeleportService — 500 calls a second hits budget limits and can throw on a
  real player later. Stub them in `setup` or profile the part around them.

## Prerequisites

- **LibMP in the place.** `profile_scripts` looks for a `ModuleScript` named `LibMP` in
  `ReplicatedStorage` (then anywhere). Missing → pass `installLibMP = true` once; it inserts
  Creator Store asset `109009378620272` and tags it `excludeLOC`. That's a change to the place —
  tell the user, and tell them where it went.
- **Script injection allowed** for VMCP in Plugin Management, or Source can't be read or swapped.
- **One Studio window.** Playtest DataModels attach to whichever window's plugin connected last;
  with two windows open the server context can be the other window's test and the first window's
  socket drops when a test starts.
- **Rojo connected** (`rojo serve` + the Rojo plugin) for `apply_fix` — it writes the file and
  waits for Studio to follow; without Rojo it times out and reverts.
- **A playtest** is started by the tools as needed. `sections`, `autoSections`, `try_scripts` and
  `apply_fix` **restart** a running one so their copies are what runs — warn the user before if
  they might be mid-test.

## Step 0 — ask, then read the ledger

One question before anything runs, because "optimize the game" and "the boss fight stutters"
are different passes. Ask it with AskUserQuestion, one call, all four at once:

1. **Where does it feel slow?** A place, a moment, a system, a player count — or "don't know,
   find it".
2. **What should I drive?** The flows you can script (walk, fight, open the shop, fire remotes)
   vs the ones you'll play yourself while I capture.
3. **What's off limits?** Scripts not to touch, systems mid-rewrite, anything that talks to the
   outside world I shouldn't hammer.
4. **How far on my own?** Stop after each report, or work the whole shortlist and only stop at
   `try_scripts`.

Don't wait on a long answer. "Don't know, find it" is the common one and it's a real answer:
it means the pass starts with **exploration**, below. If they name a moment ("when a lot of
enemies are alive"), that moment is your load and everything else is context.

Then:

```
optimization_ledger { action = "read" }
```

Skip scripts marked `applied` or `rejected` unless the user asks; pick up `proposed` ones where
they stopped. An empty ledger is a fresh pass.

## Step 1 — the baseline, under real load

```json
{ "observe": { "seconds": 4 }, "top": 30, "name": "baseline" }
```

That captures the game **as it runs** — no hammering — and lists the top scopes by self time, the
slowest frames and what filled them. It answers the only question that matters at this point:
what does the game actually spend frame time on while someone plays it?

Something has to be driving it during those seconds — and by default **that's you**, not the
user. Idle observation is only a baseline of the idle game. In order of preference:

1. **The moment the user named.** Build it: a timeline whose `server` event puts the game into
   that state (spawn the enemies, set the wave, give the player the item) and whose `client`
   events act it out (`input:Tap`, `vmcp.Load.Wander`, the remotes the UI would fire), with the
   `Observe` inside it. Reproducible, so the after-fix capture is the same load.
2. **Exploration, when nobody named anything.** Learn the game before profiling it, all in a
   couple of calls: `get_tree` on `ReplicatedStorage.Remotes` (or wherever the remotes are) and
   `review_remotes` for what a player can trigger; `count_lines` + `lint_hotpaths` for what runs
   per frame; a short `Remotes.WatchAll` while `Load.Wander` runs for the real argument shapes.
   Then **drive every flow you found**, one `Observe` each, in one timeline: walk the map with 4
   clients, fire each remote at its real rate with captured arguments, spawn whatever the server
   spawns (enemies, drops, rounds), trigger the round loop if there is one. The flow whose capture
   has the worst frames is the pass. Say which flows you drove and which you couldn't reach.
3. **The user plays.** Start the playtest, tell them exactly what to do for ten seconds, and call
   `observe` while they do. Best fidelity, but it's their time — use it for the things you
   genuinely can't script (a real fight, real UI habits), not as the default.
4. **Scripted players, generic.** One timeline: `players = 4` (or 8), a `client` event per player running
   `vmcp.Load.Wander(input, { seconds = 6, seed = <player index>, remotes = { { remote = game.ReplicatedStorage.Remotes.Swing, args = {"Sword"}, perSecond = 2 } } })`,
   and a `server` event at 1s doing `ctx.baseline = vmcp.Profile.Observe(4, { top = 30 })`. Real
   movement, animation, replication and remote traffic, at the player count where per-player
   loops actually hurt.

Exploration is active: if reaching a state means calling the game's own module functions from a
`server` event (`Rounds.Start()`, `Spawner.Spawn("Boss", cf)`), do it — that's what `vm = "game"`
is for. Tell the user what you triggered, since a spawned boss in a test is still a spawned boss.

**When a real load isn't possible** — the state can't be reached from a timeline, it needs
something external (a DataStore full of real saves, a Discord bot, a live economy), or the user
can't play right now — fall back to hammering with the **most realistic fake data you can build**:
captured remote arguments (`Remotes.Shapes()`), rigs cloned from `ServerStorage`, tables shaped
like the real module state read via `vm = "game"`, and call rates matching what the game does
(per-frame handler → `perFrame = 1`; a remote → how often a player fires it). Say in the report
that the numbers are synthetic and why.

Read the baseline the way "Reading the report" below describes. What you're looking for: user
labels or `$Script` in the top rows (script work), a `Lua/GC` row with a heap climbing (allocation),
and whether the worst frames are script-shaped or engine-shaped (`Physics/stepWorld`,
`Render`, `MegaReplicator`). If the top of the list is engine work your scripts don't drive,
say so now — a script pass won't fix a map with 40k parts.

## Step 2 — the shortlist

```
lint_hotpaths { minSeverity = "medium" }
count_lines { minLines = 100 }
```

Both in the same reply as the baseline read. `lint_hotpaths` is the table below applied
mechanically, with context: `GetDescendants` inside a `Heartbeat` handler is high, the same call
in a function that runs once a match is low. Its "scripts by weight" line plus `count_lines`'s
hot column (`[2 per-frame, 1 while-true, 9 connect]`) is your order of reading. Cross it with the
baseline: a script that's heavy in lint *and* shows up in the capture's top rows is the first
one; a script that's heavy in lint and absent from the capture is a maybe.

Lint is a shortlist, not a verdict. It can't see how often a named function is called, only what
it does when it is.

## Step 3 — read the script

Read the whole script **from disk** (Read tool on the file Rojo syncs it from — free, no
round-trip; `search_scripts { drift = true }` once if you doubt Studio matches). Then what it
requires and who requires it (Grep the repo). You need the stack — a function that looks cheap can
be called 300 times a frame by something else.

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

Mark **functions** (what `targets` hammer), **sections** inside them (a loop, a query, a block),
and what each function needs to be called: which arguments, what module state must exist, whether
it needs a character in the world.

## Step 4 — zoom in

Two moves, usually one call each — and if you already know the function, one call total.

### Which function: `autoSections`

```json
{ "observe": { "seconds": 4 }, "autoSections": ["ServerScriptService.Combat"], "top": 30 }
```

Every named function in `Combat` gets a `debug.profilebegin("Combat.<name>")` scope for the
duration of the playtest (early returns handled; anonymous handlers skipped — name the function
you want seen). The observe then reports `::Combat.ResolveHit 3.02ms avg, worst frame 31ms`
instead of `$Script 40ms`. That's the whole "which function is it" step in one round-trip, under
real load. `autoSections` combines with `targets` and with `observe`; it restarts the playtest.

### How much and why: `targets` + `sections`

```json
{
  "targets": [
    { "label": "Combat.ResolveHit", "setup": "...", "calls": 600, "seconds": 2 }
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

Put **every** function from the script in the one call — up to 8 targets, each its own capture —
and every section you want. Ask for `top = 40` up front rather than a second call. Each target
reports calls made, **allocation per call** (`~11.2 KB allocated per call` — the number behind a
climbing heap), and the full capture report.

What happens, in order: sections and auto-instrumentation are written into the scripts' Source in
Studio; a playtest is started (or restarted); Studio's Source is put back the moment the test is
up; the load runs in the live context with every call wrapped in `debug.profilebegin(label)` and
`debug.setmemorycategory(label)`; LibMP snapshots the last `frameLimit` frames; the snapshot is
read and written to `~/.vmcp/profiles/<name>-<label>.gprx`.

### Building fake data

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

## Step 6 — benchmark, compare, prove: one timeline

Planting the candidate, hammering old and new, comparing, proving equivalence and checking logs
is **one `run_timeline` call**. `vmcp.Profile.Hammer` is the same code `profile_scripts` runs,
`Profile.Compare` turns two outcomes into ratios with a verdict, `Equiv.Check` runs the same
inputs through both versions, and the assertion judges all of it.

```json
{
  "players": 1,
  "keepOpen": true,
  "events": [
    {
      "at": 0, "context": "server", "blocking": true, "label": "plant + hammer + compare + prove",
      "code": "local SS = game:GetService('ServerStorage')\n\n-- 1. the candidate, playtest-only\nlocal m = Instance.new('ModuleScript')\nm.Name = 'Combat_Candidate'\nm.Source = [==[\n... the whole module with the fix applied ...\n]==]\nm.Parent = SS\n\n-- 2. one setup body, both versions -- only the require differs\nlocal setup = [[\n  local pool = {}\n  for i = 1, 8 do\n    local rig = game.ServerStorage.Rigs.Dummy:Clone()\n    rig:PivotTo(CFrame.new(i * 6, 5, 0)); rig.Parent = workspace; pool[i] = rig\n  end\n  local attacker = game.Players:GetPlayers()[1].Character\n  return function(i)\n    local target = pool[(i % #pool) + 1]\n    target.Humanoid.Health = 100\n    M.ResolveHit(attacker, target, 'Sword')\n  end\n]]\nlocal old = 'local M = require(game.ServerScriptService.Combat)\\n' .. setup\nlocal new = 'local M = require(game.ServerStorage.Combat_Candidate)\\n' .. setup\n\n-- 3. warm both, then the run that counts\nvmcp.Profile.Hammer({ { label = 'warm.old', setup = old, calls = 50, seconds = 0.5 }, { label = 'warm.new', setup = new, calls = 50, seconds = 0.5 } }, { dump = false, top = 1 })\nlocal text, failed, outcomes = vmcp.Profile.Hammer({\n  { label = 'ResolveHit.old', setup = old, calls = 600, seconds = 2 },\n  { label = 'ResolveHit.new', setup = new, calls = 600, seconds = 2 },\n}, { name = 'combat-compare', top = 12, labels = { 'ResolveHit.partScan', 'ResolveHit.applyDamage' } })\nctx.report = text\nlocal delta = vmcp.Profile.Compare(outcomes['ResolveHit.old'], outcomes['ResolveHit.new'])\nctx.delta = { text = delta.text, better = delta.better, perCall = delta.perCall, worstFrame = delta.worstFrame, allocation = delta.allocation }\n\n-- 4. same inputs into both: returns, errors, state, broken-argument probes\nlocal ok, equiv = vmcp.Game.Eval([[\n  local Equiv = require(game.ServerScriptService.__VMCP_Equiv)\n  local Old = require(game.ServerScriptService.Combat)\n  local New = require(game.ServerStorage.Combat_Candidate)\n  local rig = game.ServerStorage.Rigs.Dummy:Clone(); rig.Parent = workspace\n  local attacker = game.Players:GetPlayers()[1].Character\n  local result = Equiv.Check(Old.ResolveHit, New.ResolveHit, function(i)\n    rig.Humanoid.Health = 100\n    return { attacker, rig, if i % 2 == 0 then 'Sword' else 'Axe' }\n  end, { n = 200, state = function() return { health = rig.Humanoid.Health, combo = Old.State.combo } end })\n  rig:Destroy()\n  return game:GetService('HttpService'):JSONEncode({ passed = result.passed, text = result.text })\n]])\nctx.equiv = if ok then game:GetService('HttpService'):JSONDecode(equiv) else { passed = false, text = 'eval failed: ' .. tostring(equiv) }\n\n-- 5. leave nothing behind\nfor _, rig in workspace:GetChildren() do if rig.Name == 'Dummy' then rig:Destroy() end end\nm:Destroy()"
    },
    {
      "at": 0.5, "context": "plugin", "label": "verify",
      "code": "local _, drift = vmcp.Tool('search_scripts', { drift = true })\nlocal _, logs = vmcp.Tool('get_logs', { context = 'server', severity = 'error', sinceSeconds = 60 })\nctx.drift = drift\nctx.serverErrors = if logs:find('^no log lines') then 0 else 1"
    }
  ],
  "assertion": "return ctx.delta.better and ctx.equiv.passed and ctx.serverErrors == 0 and ctx.drift:find('agree') ~= nil"
}
```

One reply holds the old/new report, the Compare verdict, the Equiv result, the drift check and the
error count. The event is `blocking` because `Hammer` yields for the whole load; `0.5` on the
plugin event is "after it", not a real delay.

Notes:

- `Equiv` in the game VM: `require(game.ServerScriptService.__VMCP_Equiv)` on the server,
  `require(<LocalPlayer>.PlayerScripts.__VMCP_Equiv)` on a client — GameVm installs it next to its
  bridge the first time a game-VM snippet runs. In the plugin VM it's just `vmcp.Equiv`.
- `Equiv.Check` copies the arguments before each version sees them, so a function that mutates its
  input can't leak into the other run. `state` is a snapshot taken after each call and diffed — put
  whatever the function is supposed to change in it. Probes (`arg 2: nil`, `arg 1: string instead
  of table`, "no arguments") compare how both versions fail; a differing *error message* on a probe
  is a real finding — usually acceptable, always reported.
- `Compare` is ratios: `perCall 0.14` means the new one takes 14% of the time. `better` is "nothing
  got worse by more than noise and something got at least 15% better". A per-call win with a
  worse worst-frame is a regression and it says so.
- The candidate goes in `ServerStorage` **inside the playtest**. Nothing is saved; `m:Destroy()` is
  tidiness. If the function depends on the module's private upvalues, the whole-module copy is
  what makes those exist; if it depends on live state the game filled at startup, `require` the
  live module in `setup` and hand the candidate the same reference.
- Side-effect functions: `state` in `Equiv`, plus `vmcp.Remotes.WatchAll` before and
  `Remotes.Calls()` after each version if remotes are involved.
- `keepOpen: true` because you'll likely run a second timeline; `try_scripts` restarts it anyway.

Numbers to weigh, in this order: worst frame, p95 frame time, per call, allocation per call, heap
growth. If `Compare` says "no meaningful change", it isn't worth the risk of any change. Say that.

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

- **They say it's fine** → Step 9, `apply_fix`. Only now is anything changed.
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

Numbers (600 calls, 2s, same fake data; baseline under real play had ResolveHit at 28ms of the
41ms worst frame):
  old  avg 3.02ms/call   worst frame 31.1ms   11.2 KB allocated per call
  new  avg 0.41ms/call   worst frame  6.8ms    0.4 KB allocated per call

Behaviour: Equiv.Check passed — identical returns and state over 200 inputs and 9 broken-argument
probes. One thing you should know: the old code warned "no hitboxes" via warn()
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

## Step 9 — apply, with the net

Only after the user has played it and said yes.

```json
{
  "script": "ServerScriptService.Combat",
  "source": "...the whole module with the fix...",
  "check": "local Equiv = require(game.ServerScriptService.__VMCP_Equiv)\nlocal Old = require(game.ServerStorage.__VMCP_Previous_Combat)\nlocal New = require(game.ServerScriptService.Combat)\n... same generator as Step 6 ...\nlocal r = Equiv.Check(Old.ResolveHit, New.ResolveHit, gen, { n = 100 })\nreturn if r.passed then true else r.text"
}
```

`apply_fix` writes the file Rojo syncs the script from, waits for Studio to pick it up, restarts
the playtest with the **previous** version planted as `ServerStorage.__VMCP_Previous_<Name>`, runs
`check` in the game VM, and reads the server error log. `check` returning anything but `true`, an
error, a sync that never lands, or a logged server error → the old file is written back and the
reply starts with `NOT applied:` and why. On success the playtest stays up running the applied
code — tell the user to play it once more, and write the ledger:

```
optimization_ledger { action = "write", script = "ServerScriptService.Combat", entry = { status = "applied", summary = "tag hitboxes once, GetTagged in ResolveHit", worstFrameBefore = 31.1, worstFrameAfter = 6.8, perCallBefore = 3.02, perCallAfter = 0.41 } }
```

Rejected fixes get `status = "rejected"` and the reason; scripts you profiled and found fine get
`status = "profiled"` with the numbers, so nobody profiles them again next week.

## Then

After the ledger write, one of three things, and say which:

- **Continue** to the next script on the shortlist on your own, if the intake answer was "work
  the list" — and to the next *flow* if the current one is clean: exploration isn't finished
  until every flow you found has a capture. Say which one and why. Batch across scripts when their suspects are
  independent: one `profile_scripts` with both scripts' targets, one timeline whose `Hammer` call
  carries four targets.
- **Ask** where to go next when the shortlist is exhausted, or when the baseline says the cost is
  engine-side (physics, rendering, replication) and a script pass won't move it.
- **Pause** after every `try_scripts` and after every `apply_fix`. Always. The checks are not a
  substitute for a human playing the game with the new code in.

## Gotchas, all in one place

- **Observe shows nothing script-shaped** → nobody was playing during the window, or the load
  driver hadn't started yet. Put the `Observe` a second after the `Wander` events begin.
- **`autoSections` broke the script** → the instrumenter misread a body start (an exotic return
  type annotation, say). `get_logs` shows the compile error; fall back to hand `sections` for that
  script and tell me the construct.
- **`apply_fix` says the sync never landed** → the Rojo plugin isn't connected. It already reverted
  the file; connect Rojo and call it again.
- **Equiv reports differing error messages on probes only** → the two versions fail the same
  inputs differently (`attempt to iterate over nil` vs `attempt to get length of nil`). Behaviour
  change on bad input; usually fine, always in the report.
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

