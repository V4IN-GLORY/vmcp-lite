---
name: vmcp-timeline
description: Writing batched run_timeline payloads for VMCP — scheduling Luau across Studio, a live server and live clients on one clock, sharing state through ctx, calling other tools mid-run, driving real input, and asserting the result. Use when debugging or testing anything that needs a running game, timing, or more than one context.
---

# Timelines

`run_timeline` takes one JSON payload and plays it across three kinds of context at once. It is the
cheapest thing in VMCP per unit of information: one call starts a playtest, runs code in Studio and
in the real game, collects everything into a shared table, and judges the result.

Prefer one timeline with ten events over ten separate `run_luau` calls. That's the whole point.

## Shape

```json
{
  "players": 1,
  "duration": 1,
  "events": [
    { "at": 0,   "context": "plugin", "blocking": true, "code": "..." },
    { "at": 0.2, "context": "server", "code": "..." },
    { "at": 0.5, "context": "client", "player": 1, "code": "..." }
  ],
  "assertion": "return ctx.stunned == false"
}
```

`at` is seconds from the start. `duration` is extra time held **after** the last event, for effects
that land late — it's added to the schedule, not a total.

Each `code` runs as a function body with `ctx`, `input` and `vmcp` in scope. `return` works.

## The three contexts

| context | where it runs | what it's for |
|---|---|---|
| `plugin` | Studio's edit DataModel | anything needing plugin permissions — reading Source, `Instance.new` into the place, `get_build` |
| `server` | the live playtest server | player state, server modules, remote handlers, authority checks |
| `client` | a live test client | input, UI, local effects, sending remotes the way a player would |

`plugin`-only payloads don't start a playtest at all. Any `server` or `client` event makes one start
if none is open, and it's stopped again afterwards unless you pass `"keepOpen": true` or a playtest
was already running when you called.

## ctx: how contexts talk

These are separate processes. `ctx` is held by the VMCP server and every read and write is a round
trip — correct across all three, and **not free**. Pull a value into a local if you'll use it twice.

```lua
ctx.startHealth = humanoid.Health          -- write from anywhere
local before = ctx:Await("startHealth", 2) -- read from anywhere else
```

Reading is where payloads go wrong. `ctx.thing` reads whatever is there *right now*, which may be
nothing yet:

```lua
-- wrong: races, and reads nil about half the time
if ctx.ready then ... end

-- right: declares the dependency, and a miss is recorded in the report
if ctx:Await("ready", 2) == nil then return end
```

`Await` returns nil on timeout and writes a line into the report's notes, so an assertion that
fails for that reason says so rather than just looking wrong.

Also: `ctx:Note("text")` adds a line to the report, `ctx:Snapshot()` copies the whole table. A key
named `Await`, `Note` or `Snapshot` collides with the method — pick another name.

## The assertion

Runs in Studio **after** every context has finished, with `ctx` and `vmcp` in scope. Return `true`
to pass. It is deliberately outside the timeline: it judges the run rather than being part of it.

```json
"assertion": "return ctx.stunEndedAt ~= nil and ctx.stunEndedAt - ctx.stunStartedAt < 3"
```

With no assertion the run passes unless a context outright failed.

## vmcp: the library, in every event

`vmcp.Tool(name, arguments)` calls **any other VMCP tool, in any context**, and returns `ok, text`.
This is what makes a payload able to do more than one thing:

```lua
local ok, tree = vmcp.Tool("get_tree", { root = "Workspace.Arena", depth = 2 })
ctx.arena = tree
```

```lua
-- from a client event, ask the server something and read the answer here
local ok, health = vmcp.Tool("run_luau", {
    context = "server",
    code = "return game.Players:GetPlayers()[1].Character.Humanoid.Health",
})
```

`vmcp.Game.Require(path)` is the one for module debugging — see the `vmcp-debugging` skill.
`vmcp.Remotes`, `vmcp.Exploit` and `vmcp.Bench` live there too; `vmcp.Profile` (MicroProfiler
captures) is in `vmcp-optimization`. `vmcp.Build` and `vmcp.Serialize` are in scope as well.

## input: client events only

Drives the real input path, so keybinds, ContextActionService and UI see it exactly as they'd see a
person. Calling a handler directly skips everything the input path does on the way, which is
usually where the bug is.

```lua
input:Tap("W", 0.4)              -- press and release, always released
input:Hold("LeftShift")          -- released at teardown if you forget
input:Click(640, 400)            -- "left" | "right" | "middle"
input:Drag(100, 100, 300, 200)
input:Type("hello")
input:Scroll(640, 400, -3)
```

Every one of these can throw — a click on the topbar, a core-bound key like `Escape`, a button
already down. Failures land in the report's notes and the run carries on.

## blocking

An event normally fires and the schedule moves on, so a yielding event never delays the next.
`"blocking": true` makes the schedule wait. Use it for setup at `at: 0`, not for ordinary steps: a
blocking event that runs long pushes everything after it, and the report says so.

## Worked example — the stun bug

"After using this skill the player is permanently stunned; find out why." One call:

```json
{
  "players": 1,
  "duration": 4,
  "events": [
    { "at": 0, "context": "server", "blocking": true, "code":
      "local p = game.Players:GetPlayers()[1]\nrepeat task.wait() until p.Character\nctx.ready = true" },

    { "at": 0.3, "context": "client", "code":
      "ctx:Await('ready', 5)\ninput:Tap('Q')" },

    { "at": 0.5, "context": "server", "code":
      "local ok, state = vmcp.Game.Require('ServerScriptService.Combat.StateModule')\nctx.rightAfter = state" },

    { "at": 3.5, "context": "server", "code":
      "local ok, state = vmcp.Game.Require('ServerScriptService.Combat.StateModule')\nctx.later = state\nlocal p = game.Players:GetPlayers()[1]\nctx.walkSpeed = p.Character.Humanoid.WalkSpeed" }
  ],
  "assertion": "return ctx.walkSpeed > 0"
}
```

Both module snapshots and the final WalkSpeed come back in one result, and `vmcp.Game.Require`
reads the module the *running server* holds, not a fresh copy of it.

## Limits worth knowing

- One playtest per Studio window.
- `ctx` values cross as JSON: strings, numbers, booleans and plain tables. An Instance or a
  function won't survive — render it first with `vmcp.Serialize.Render(value)`.
- Events are all compiled before the clock starts, so a syntax error stops the run up front
  instead of blowing a hole in the middle of it.
- 200 events per payload.
