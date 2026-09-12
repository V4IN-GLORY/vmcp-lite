---
name: vmcp-timeline
description: Writing run_timeline payloads for VMCP — scheduling events across server and client, sharing state with ctx, driving real input, and asserting the result. Use when testing game behaviour that needs a running server, a real player, or timing.
---

# Writing a timeline

`run_timeline` starts its own playtest, plays a list of snippets on one clock, and ends with an
assertion. Every run costs a few seconds of startup, so put everything you want to learn into one
timeline rather than running several.

## Shape

```json
{
  "players": 1,
  "duration": 1,
  "events": [
    { "at": 0,   "context": "server", "blocking": true, "code": "..." },
    { "at": 0.5, "context": "client", "player": 1,      "code": "..." },
    { "at": 1.2, "context": "server", "code": "..." }
  ],
  "assertion": "return ctx.hit == true"
}
```

`at` is seconds from the start. `duration` is extra time held **after** the last event, for effects
that land late — it is added to the schedule, not a total.

Each `code` runs as a function body with `ctx` and `input` in scope. `return` works.

## ctx: the only way contexts talk

Write anywhere, read anywhere:

```lua
ctx.spawnedAt = workspace:GetServerTimeNow()
```

Reading is the trap. `ctx.thing` reads a local mirror, so a context always sees its own writes
instantly but another context's write only once it has arrived. If you're reading something set
somewhere else, **wait for it explicitly**:

```lua
-- wrong: races, and reads nil about half the time
if ctx.ready then ... end

-- right: declares the dependency, and a miss is recorded in the report
local ready = ctx:Await("ready", 2)
if ready == nil then return end
```

`Await` returns nil on timeout and writes a line into the report's notes, so an assertion that
fails for that reason says so instead of just looking wrong.

Also on `ctx`: `ctx:Note("text")` adds a line to the report, `ctx:Snapshot()` copies the whole
table. A key named `Await`, `Note` or `Snapshot` collides with the method — pick another name.

Every write is stamped at its origin, so the report's write list is in real order even when a
client's message reaches the server after a later server write.

## input: client events only

`input` drives the real input path, so keybinds, ContextActionService and UI all see it exactly as
they'd see a person. Calling a handler directly skips all of that, which is usually the bug.

```lua
input:Tap("W", 0.4)              -- press and release, always released
input:Hold("LeftShift")          -- released at teardown if you forget
input:Release("LeftShift")
input:Click(640, 400)            -- "left" | "right" | "middle"
input:Drag(100, 100, 300, 200)
input:Type("hello")
input:Scroll(640, 400, -3)
```

Every one of these can throw — a click that lands on the topbar, a core-bound key like `Escape`, a
button that's already down. Failures are recorded in the report's "input problems" and the run
carries on; nothing kills the timeline.

## blocking

An event normally fires and the schedule moves on, so a yielding event never delays the next one.
`"blocking": true` makes the schedule wait for it. Use it for setup at `at: 0`, not for ordinary
steps — a blocking event that runs long pushes everything after it, and the report says so.

## Worked example

Press a movement key and check the character actually moved, rather than trusting the handler:

```json
{
  "players": 1,
  "duration": 1,
  "events": [
    { "at": 0, "context": "server", "blocking": true,
      "code": "local p = game.Players:GetPlayers()[1]\nrepeat task.wait() until p.Character and p.Character.PrimaryPart\nctx.startX = p.Character.PrimaryPart.Position.X" },
    { "at": 0.2, "context": "client", "player": 1,
      "code": "ctx:Await('startX', 3)\ninput:Tap('W', 0.6)" },
    { "at": 1.2, "context": "server",
      "code": "local p = game.Players:GetPlayers()[1]\nctx.endX = p.Character.PrimaryPart.Position.X" }
  ],
  "assertion": "return math.abs(ctx:Await('endX', 2) - ctx.startX) > 1"
}
```

## What you get back

PASS or FAIL with the assertion's own words, then the context at the end, the writes in order,
any notes (including Await misses and late events), input problems, and output from both sides.

## Limits worth knowing before you write

- **Client code cannot be sent to a running game.** A client DataModel has no `loadstring` and its
  scripts aren't writable from a plugin. Anything a client does has to be in the payload. This is
  why `run_luau` has no client context.
- One playtest per Studio window. `run_timeline` refuses while a `playtest` session is open.
- The whole payload is compiled before the test starts, so a syntax error is reported straight
  away rather than turning into a test that silently does nothing.
