---
name: vmcp-debugging
description: Debugging a running Roblox game with VMCP — reading a live module's real state, watching and hooking remote traffic, simulating an exploiter, and timing a function under load. Use when something misbehaves at runtime rather than in the code you can read.
---

# Debugging the running game

Everything here needs a playtest. Start one with `playtest { action = "start" }`, or just write a
`run_timeline` payload with `server` or `client` events and let it start its own.

## Reading a module's real state

This is the one that matters most, and the one with a trap in it.

The plugin loads into the playtest's DataModels, so it can run code there — but the plugin's VM has
its own `require` cache. `require(SomeModule)` from the plugin builds a **fresh copy**, so
everything the running game accumulated in that module is invisible. You'd see a module that looks
newly initialised and conclude nothing is wrong.

`vmcp.Game` runs on the game's side of that fence, against the game's own cache:

```lua
local ok, state = vmcp.Game.Require("ServerScriptService.Combat.StateModule")
ctx.combatState = state
```

```lua
-- arbitrary code in the game VM, same shared cache
local ok, text = vmcp.Game.Eval([[
    local Effects = require(game.ReplicatedStorage.Modules.Effects)
    return { active = Effects.Active, count = #Effects.Queue }
]])
```

Or from `run_luau` directly: `{ context = "server", vm = "game", code = "..." }`.

Only text comes back — the result is rendered on the game's side, because a module table is full of
functions and functions can't cross between VMs.

**Use `vm = "plugin"` (the default) for anything touching instances**; use `vm = "game"` when the
question is "what does this module actually hold right now".

## Watching remote traffic

```lua
vmcp.Remotes.WatchAll(game.ReplicatedStorage.Remotes)
-- ... later, in a later event ...
ctx.traffic = vmcp.Remotes.Report()
```

Two mechanisms, because remotes aren't symmetrical:

- **RemoteEvent** is *observed*. A second listener on `OnServerEvent` doesn't disturb the first, so
  watching one can't change behaviour.
- **RemoteFunction** is *hooked*. It has exactly one callback, so the watcher takes it, puts itself
  in front, and calls through. `vmcp.Remotes.Stop()` puts the original back.

`WatchAll` also picks up remotes created after it started. `Watch(remote)` does one.
`Calls()` gives the raw list, `Clear()` empties it.

Run `Watch` in the context you want to see: server-side to see what clients send, client-side to
see what the server pushes out.

## Simulating an exploiter

A remote handler is only as safe as its worst caller, and the worst caller doesn't use your UI.
These run from a **client** event, through the real network path.

### Tailored to the game — do this one first

Blind junk stops at the first argument the handler checks. What actually finds bugs is the game's
own traffic, replayed and broken one argument at a time. Two events and a `ctx` hop:

```lua
-- server, at 0: watch, and let the game play normally for a few seconds
vmcp.Remotes.WatchAll(game.ReplicatedStorage.Remotes)
```

```lua
-- server, later: hand the captured shapes over
ctx.shapes = vmcp.Remotes.Shapes()
```

```lua
-- client, last: replay every remote with its real arguments, then break them
ctx.attack = vmcp.Exploit.FromTraffic(ctx:Await("shapes", 10))
```

`Remotes.Shapes()` gives one entry per remote seen — class, call count, a one-word signature per
argument position, and a real sample set of arguments that survives the trip through `ctx`. An
Instance argument crosses as its path and is resolved again on the client, so "the sword you were
holding" is still that sword.

`FromTraffic` then runs `Exploit.Tailor` on each: **one argument changed per variant**, chosen for
the type that argument really is.

| real argument | what gets sent instead |
|---|---|
| number | negative, `math.huge`, `nan`, past `2^53`, the same number as a string |
| string | empty, 10k chars, a number, the same name with `_NOPE` on it |
| Instance | **another player's character or player**, a random part, its path as a string |
| table | empty, a number, a 10k-entry table |
| Vector3 | a million studs away, `nan` components |
| any | nil, plus "no arguments at all" and "one extra argument" |

The Instance row is the one that finds real bugs — it's the missing ownership check. The pool is
built from the live place: the other players, their characters, and things in Workspace and
ReplicatedStorage.

One change at a time is deliberate. Two wrong arguments tell you which check fired, not which one
is missing.

### Reading the result

A **RemoteFunction** answers you directly — a thrown error is the handler rejecting it, a returned
value is what it was willing to hand over. That's in the report.

A **RemoteEvent** gives the caller nothing back, so "sent" is all this side can say. What it did
shows up in the server's logs and state — so pair it with a server event afterwards that reads the
thing that shouldn't have changed:

```lua
-- server, after the attack
ctx.cashAfter = game.Players:GetPlayers()[1].leaderstats.Cash.Value
```

```json
"assertion": "return ctx.cashAfter == ctx.cashBefore"
```

### The blind versions

Still there for when there's no traffic to learn from, or when the question is rate limiting:

```lua
-- the same arguments, far too often: finds missing rate limiting
local report = vmcp.Exploit.Spam(remote, { "Fireball" }, { times = 500, perFrame = 20 })
ctx.spam = vmcp.Exploit.Summarise(report)

-- junk arguments every call, no knowledge of the shape
local report = vmcp.Exploit.Fuzz(remote, 3, { times = 200 })

-- one junk call at every remote under a folder, to see what falls over
ctx.sweep = vmcp.Exploit.FuzzAll(game.ReplicatedStorage.Remotes)
```

`Exploit.Tailor(remote, args)` is the direct form if you already know the arguments and don't need
to capture them — hand it a real call and it does the same breaking.

## Timing a function under load

```lua
local report = vmcp.Bench.Run(function()
    Combat.ResolveHit(dummyA, dummyB)
end, { times = 2000, perFrame = 50, warmup = 20 })

ctx.hit = vmcp.Bench.Summarise(report)
```

`{ times, seconds, perFrame, args, warmup }`. `perFrame` yields between batches, which reproduces
real load — a tight loop the scheduler never sees has a different shape entirely.

The report is `calls, errors, firstError, totalMs, meanMs, minMs, maxMs, p50Ms, p95Ms, p99Ms,
elapsedSeconds`. **Read p99, not mean.** A function whose mean is fine and whose p99 is forty times
its median is the one causing the hitch; an average hides that completely.

## Output and errors

`get_logs` reads a rolling buffer the plugin fills in whatever DataModel it's in, so
`{ context = "server" }` gives the live server's output including errors thrown by your own
scripts. A timeline also folds each context's output into its notes automatically.
