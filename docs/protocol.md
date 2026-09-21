# VMCP bridge protocol

Everything the Studio plugin needs to do. You shouldn't have to open the TypeScript.

## The shape of it

```
  Claude  <--- MCP over stdio --->  VMCP server  <--- WebSocket --->  Studio plugin
                                  (node, on your PC)                   (your Luau)
```

The server listens on `ws://127.0.0.1:8791`. Your plugin dials in — the server never
reaches out, so it doesn't care whether Studio is open.

**Your plugin owns the tools.** You write them in Luau with their own names, descriptions
and schemas, hand the list to the server when you connect, and they show up in Claude. The
server has no tools of its own and never needs editing to add one.

Every message both ways is one JSON object, [JSON-RPC 2.0](https://www.jsonrpc.org/specification)
shaped: `{jsonrpc, id, method, params}` going out, `{jsonrpc, id, result}` or
`{jsonrpc, id, error}` coming back.

## What the plugin has to do

1. Get the token in (once, by hand — see below).
2. Open a WebSocket to `ws://127.0.0.1:8791`.
3. Send `session/hello` with the token, protocol version, your place identity, and your tools.
4. Wait for `tool/call` messages and reply to each with the matching `id`.
5. Reconnect with backoff when the socket drops.

That's the whole job. Everything after step 4 — progress, revisions, re-registering — is
optional and can wait until the basics work.

## Getting the token in

The server writes a random token to `%USERPROFILE%\.vmcp\token` and reuses it forever.
Anything that connects with it can drive your place, so the socket won't talk without it.

**A Studio plugin can't read files**, so the token has to get there by hand once:

```
cd server
npm run token
```

Copy that, and store it with `plugin:SetSetting` so you only do this once per machine:

```lua
-- one-time, from a plugin toolbar button with a text box
plugin:SetSetting("VmcpToken", pastedToken)

-- every run after that
local token = plugin:GetSetting("VmcpToken")
```

If the token is missing or wrong the socket closes with code `1008`. Don't retry that in a
loop — it won't start working.

## Opening the socket

```lua
local HttpService = game:GetService("HttpService")

local client = HttpService:CreateWebStreamClient(Enum.WebStreamClientType.WebSocket, {
	Url = "ws://127.0.0.1:8791",
})
```

Three things that matter here:

- The type has to be `WebSocket`. `Send()` is a **no-op** on `SSE` and `RawStream`, so the
  other two can't reply to a tool call at all.
- There's a cap of six live stream clients per session. `Close()` the old one before you
  reconnect or you'll run out.
- Don't add an `Origin` header. The server refuses any connection carrying one, because a
  webpage can reach localhost and a plugin never sends it.

You get four events: `Opened(statusCode, headers)`, `MessageReceived(message)`,
`Error(statusCode, message)`, `Closed()`.

## 1. `session/hello` — the handshake

Must be your **first** message, within 5 seconds of connecting, or the socket closes.

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "session/hello",
  "params": {
    "token": "…the token you pasted…",
    "protocolVersion": 3,
    "sessionId": "b1e7…",
    "placeId": "1234567890",
    "placeName": "My Game",
    "tools": [],
    "revision": 1
  }
}
```

The server replies:

```json
{ "jsonrpc": "2.0", "id": 1, "result": { "ok": true, "protocolVersion": 3 } }
```

**`protocolVersion` is required and must be `3`.** A mismatch is refused at the handshake
with an error naming both versions (`plugin speaks v2, this server speaks v3`) rather than
letting it turn into strange behaviour halfway through a session. Bump it in your plugin
when this doc's version changes.

**`sessionId` identifies this Studio window**, and it's what the server keys sessions on.
Generate one when your plugin loads and reuse it for every reconnect in that window:

```lua
local sessionId = HttpService:GenerateGUID(false)
```

Don't persist it with `plugin:SetSetting` — two Studio windows would share it and fight.
Keeping it per window is what lets you open the same place twice and have both show up.

Reconnecting with a `sessionId` that's already connected **replaces** the old session and
closes its socket with `4000`, so a plugin reload can't leave a zombie holding your tool
names.

`placeId` and `placeName` are for display and caching — how tools are named and grouped for
Claude. `placeId` must be a non-empty string; `tostring(game.PlaceId)` works, but an unsaved
place has a `PlaceId` of `0`, so fall back to a GUID stored in `plugin:GetSetting` for those.

## 2. Tool definitions

One entry per tool, in `hello` and in `tools/changed`:

```json
{
  "name": "insert_part",
  "description": "Inserts an anchored part at a world position.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "position": { "type": "array", "items": { "type": "number" }, "description": "x, y, z" }
    },
    "required": ["position"]
  },
  "outputSchema": {
    "type": "object",
    "properties": { "path": { "type": "string" } }
  },
  "tags": { "destructive": false, "idempotent": true },
  "timeoutMs": 60000
}
```

| Field | Rules |
|---|---|
| `name` | `[A-Za-z0-9_-]`, 1–64 chars, unique within your place |
| `description` | Non-empty. Claude reads this to decide when to use the tool — write it for a person |
| `inputSchema` | A JSON Schema object. Forwarded to Claude untouched and **not** enforced by the server |
| `outputSchema` | Optional JSON Schema for structured results. See `structuredContent` below |
| `tags` | Optional. What the tool does to the place — see the next section |
| `timeoutMs` | Optional. Overrides the 30s default for this one tool |

The server checks the envelope only. It never validates a tool's arguments — you're the
only thing that knows what valid means for your tool, so check them yourself and return an
error result when they're wrong.

A malformed entry rejects the **whole** registration, so nothing half-registers.

In Luau that definition is just a table:

```lua
{
	name = "insert_part",
	description = "Inserts an anchored part at a world position.",
	inputSchema = {
		type = "object",
		properties = {
			position = { type = "array", items = { type = "number" }, description = "x, y, z" },
		},
		required = { "position" },
	},
	tags = { idempotent = true },
}
```

## Tags — telling Claude what a tool does

All optional, all default to unset. They become MCP annotations, which clients use to decide
what to run freely and what to confirm first. Worth setting on anything that writes.

| Tag | Meaning |
|---|---|
| `title` | A friendlier display name than the tool's id |
| `readOnly` | The tool changes nothing. Safe to call whenever |
| `destructive` | It can destroy or overwrite existing work |
| `idempotent` | Running it twice with the same arguments is the same as running it once |
| `external` | It reaches outside the place — HTTP, the Creator Store, the filesystem |

```lua
tags = { title = "Insert Part", destructive = false, idempotent = true }
```

A misspelled tag is an error rather than being ignored, since a silently-dropped
`readonly` would be worse than a loud failure.

### `idempotent` also buys you retry safety

Tag a tool `idempotent` and the server adds a `retryKey` string argument to the schema
Claude sees, and remembers what each key returned for five minutes. If a call times out and
Claude retries with the same `retryKey`, it gets the first result back and **your tool
doesn't run again**.

You don't have to do anything for this — no `retryKey` handling in your Luau. It's just
there if the tool is tagged. Timeouts and dropped sessions are never cached, so a genuine
failure still retries for real.

## 3. `tool/call` — the server asks you to run something


```json
{ "jsonrpc": "2.0", "id": 42, "method": "tool/call",
  "params": { "name": "insert_part", "arguments": { "position": [0, 5, 0] } } }
```

Reply with the **same `id`**:

```json
{ "jsonrpc": "2.0", "id": 42,
  "result": { "content": [{ "type": "text", "text": "Inserted Part at 0, 5, 0" }] } }
```

For a failure Claude should read and can react to — bad arguments, nothing selected, no
such instance — same shape with `isError`:

```json
{ "jsonrpc": "2.0", "id": 42,
  "result": { "content": [{ "type": "text", "text": "position needs 3 numbers" }], "isError": true } }
```

`isError: true` is almost always what you want. Claude sees the text and can correct itself.
A JSON-RPC `error` object works too but reads as a hard fault:

```json
{ "jsonrpc": "2.0", "id": 42, "error": { "code": -32602, "message": "position needs 3 numbers" } }
```

**Shorthand while prototyping:** any `result` that isn't a `{content: [...]}` object gets
wrapped in a text block for you, so `result = "done"` is fine.

If the tool declared an `outputSchema`, add `structuredContent` alongside the text:

```json
{ "jsonrpc": "2.0", "id": 42, "result": {
    "content": [{ "type": "text", "text": "Inserted Part at 0, 5, 0" }],
    "structuredContent": { "path": "Workspace.Part" } } }
```

Always send the text block too — some clients ignore structured output entirely. If you send
only `structuredContent`, the server fills the text in for you with its JSON.

`id` is per-connection and calls can overlap — match on the `id`, don't assume replies go
out in the order the calls came in. If a call takes longer than its timeout the server gives
up on it; a late reply is discarded, not misrouted.

## 4. `tool/progress` — say you're still working

A tool that takes a while should report progress. Two reasons: Claude sees it instead of
waiting blind, and **each progress message restarts that call's timeout**, so a long job
doesn't need a huge `timeoutMs` — it just needs to keep talking.

Send it as a notification (no `id` of its own) while the call is still running, with `id`
set to the **tool/call id** you're working on:

```json
{ "jsonrpc": "2.0", "method": "tool/progress",
  "params": { "id": 42, "progress": 3, "total": 10, "message": "welding parts" } }
```

`total` and `message` are optional. Progress for a call that already finished or timed out
is ignored.

## 5. `place/revision` — flag that the place moved

Keep a counter and bump it whenever your tools change the place. Send it either as a
notification:

```json
{ "jsonrpc": "2.0", "method": "place/revision", "params": { "revision": 7 } }
```

or, more simply, alongside a tool result:

```json
{ "jsonrpc": "2.0", "id": 42, "result": { "content": [ … ], "revision": 7 } }
```

When the number changes, the server appends a line to the next result Claude sees:

```
[the place changed — now at revision 7; earlier reads may be stale]
```

That's the whole feature — it stops Claude acting on instance paths it read before an edit
moved them. It only fires when the number actually changes, and a plugin that never sends
one never sees the line. Send a starting `revision` in `session/hello` so the first call
after connecting doesn't report a change that didn't happen.

## 6. `tools/changed` — re-register

Send this any time after the handshake to replace your **entire** tool list. It's a full
replacement, not a merge. Claude's tool list updates without a reconnect, which makes it the
hot-reload path while you're iterating.

```json
{ "jsonrpc": "2.0", "id": 7, "method": "tools/changed", "params": { "tools": [ /* full list */ ] } }
```

Omit `id` if you don't want a reply.

## 7. `role` and `linkId` — one plugin, several DataModels

The plugin doesn't only run in the edit DataModel. Studio loads it into a playtest's server and
into each test client too, so one Studio window opens several sessions on this bridge — the same
code, detecting its own role:

```lua
local role = if RunService:IsEdit() then "plugin" elseif RunService:IsServer() then "server" else "client"
```

A playtest session sends that as `role`, plus `linkId` set to the **edit** session's `sessionId`.
That pairing is the whole point: it tells the server which Studio window the running game belongs
to. The edit session leaves both out and defaults to `"plugin"`.

Play Solo is one DataModel that is both server and client, so it sends `role: "server"` with
`alsoClient: true` and stands in as client 1 as well.

Only the edit session's tool list is advertised — a peer knows the same tools, and listing them
again would offer everything twice. What a peer gets instead is routing: a `tool/call` whose
arguments carry `"context": "server"` or `"client"` goes to that DataModel rather than to the edit
session. `context: "plugin"`, or no context at all, stays with the edit session.

The reply to a peer's `session/hello` carries `peerIndex`: `0` for the server, 1-based for each
client. Nothing inside a client DataModel can work out which player it is on its own.

A peer whose `linkId` matches nothing is refused with `-32003` and closed. An edit session
disconnecting closes its peers with `4000` — those DataModels die with the window anyway.

## 8. `tool/invoke` and `ctx/*` — tools calling tools, and shared state

Both of these exist because a timeline's contexts are separate processes. This socket is the only
thing they have in common.

**`tool/invoke`** lets a running tool call another one, in any context:

```json
{
  "jsonrpc": "2.0",
  "id": 9,
  "method": "tool/invoke",
  "params": { "name": "get_tree", "arguments": { "root": "Workspace.Arena", "context": "plugin" }, "depth": 0 }
}
```

The server resolves the name against the **edit** session's tools (peers resolve through their
`linkId`), routes on `arguments.context` exactly as an MCP call would, and replies with
`{ "ok": true, "result": <tool result> }`. `depth` counts how deep the chain is; past 4 it's
refused as a loop. Internal tools — anything tagged `internal` — are reachable here and never
advertised to the MCP client.

**`ctx/*`** is the timeline's shared context, held per edit session:

| method | params | result |
|---|---|---|
| `ctx/set` | `key`, `value`, `from` | `ok` |
| `ctx/get` | `key` | `value` |
| `ctx/note` | `text` | `ok` |
| `ctx/clear` | — | `ok` |
| `ctx/snapshot` | — | `values`, `writes`, `notes` |

Every write blocks until the server has it, so arrival order is write order and the server is the
one clock all three DataModels agree on. Values cross as JSON.

## 9. `source/drift` — the plugin asking the server

The one request that goes plugin to server. Studio can read its own scripts but not the disk; the
server can do both halves of the comparison, so the plugin sends what it has and gets back only the
disagreements.

```json
{
  "jsonrpc": "2.0",
  "id": 7,
  "method": "source/drift",
  "params": {
    "scripts": [
      { "path": "ReplicatedStorage.Shared.Hello", "className": "ModuleScript", "hash": 1709500481 }
    ]
  }
}
```

`hash` is FNV-1a 32-bit over the source with CRLF normalised to LF and trailing whitespace stripped.
The server hashes the file the same way, so the two only differ when the content really does.

```json
{
  "jsonrpc": "2.0",
  "id": 7,
  "result": {
    "ok": true,
    "projectPath": "D:\Studio Games\VMCP\default.project.json",
    "drift": [
      { "path": "ReplicatedStorage.Shared.Hello", "file": "…/src/shared/Hello.luau", "problem": "differs" }
    ]
  }
}
```

`problem` is `differs`, `not on disk` (a script made in Studio that Rojo has nowhere to write), or
`not in studio` (a file that never synced). Paths Rojo doesn't manage are skipped entirely. Refused
with `-32600` when the server can't find a `default.project.json` — start it from the project
folder, or point `VMCP_PROJECT` at one.

## 9b. `source/write` and `ledger/*` — the plugin asking the server to keep something

`source/write` writes a script's file on disk — the one Rojo syncs it from — so an applied fix lands
in the repo. Refused when the server can't see a Rojo project or Rojo has no file for that path
(a Studio-only script is Studio's business).

```json
{ "jsonrpc": "2.0", "id": 9, "method": "source/write",
  "params": { "path": "ServerScriptService.Combat", "className": "ModuleScript", "source": "..." } }
```

The reply is `{ "file": "<absolute path>", "previous": "<what the file held before>" }`, so the
caller can put it back.

`ledger/read` and `ledger/write` keep a per-place JSON record under
`~/.vmcp/optimization/<placeId>.json` for the optimization pass — one object per script path.
`ledger/write` takes `{ "key": "<script path>", "entry": { ... } }` and merges the fields in
(stamping `updatedAt`); an absent `entry` deletes the key. Both reply with `{ placeId, entries }`.

## 10. `postProcess` — asking the server to finish a result

A tool result may carry a `postProcess` object alongside `content`. It's for work the plugin
genuinely can't do, which means writing a file. Kinds: `scene` renders collected part geometry
as a blockout picture under `~/.vmcp/images/<name>.png`, and `gprx` writes a base64 `data` field
out as a MicroProfiler capture under `~/.vmcp/profiles/<name>.gprx`.

```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "result": {
    "content": [{ "type": "text", "text": "drew a 256x256 image" }],
    "postProcess": { "kind": "png", "name": "health-bar", "width": 256, "height": 256, "ops": [] }
  }
}
```

The server carries it out, appends a line of text saying what happened, and strips the directive —
the MCP client never sees it. When the job produced an image it's also appended as an MCP
`{ "type": "image", "data": <base64>, "mimeType": "image/png" }` block (skipped past 1.5 MB), so
the caller sees the picture in the same reply as the text without opening the file. An unrecognised `kind` says so in that line rather than failing the
call. This happens on every path a result takes out of the plugin, including a result travelling
back through `tool/invoke`, so a snippet gets its file whichever side asked for the tool.

### `post/process` — the same thing, without a result to ride on

A timeline event isn't a tool call, so it has nowhere to put a directive. Plugin to server:

```json
{ "jsonrpc": "2.0", "id": 7, "method": "post/process",
  "params": { "kind": "png", "name": "health-bar", "width": 256, "height": 256, "ops": [] } }
```

The reply is `{ "outcome": "[wrote the image to ...]" }` — the same line that would have been
appended to a tool result. Any session may call it, so an image drawn on a test client is written
by the same server that wrote one drawn in Studio.

Deliberately narrow: these two are the only places the relay acts on content instead of passing it
through.

## Luau gotchas

**Every schema needs `type = "object"` at its root.** MCP requires it. The server checks at
registration and refuses the whole list with a message naming the tool, because a bad schema
that slips through breaks the tool list for *every* tool, not just the bad one.

```lua
-- refused: "tools[0].inputSchema needs type: \"object\" at its root"
inputSchema = { properties = { text = { type = "string" } } }

-- fine
inputSchema = { type = "object", properties = { text = { type = "string" } } }

-- fine, for a tool that takes no arguments
inputSchema = { type = "object" }
```

**Empty tables encode as `[]`, not `{}`.** `HttpService:JSONEncode({})` gives you an array,
which isn't a valid schema. The server unpicks the two places this actually happens — a
wholly empty `inputSchema` becomes `{ type = "object" }`, and an empty `properties` is
dropped — so both of these work:

```lua
inputSchema = {}                                  -- becomes { type = "object" }
inputSchema = { type = "object", properties = {} } -- properties dropped
```

It can't fix a *nested* empty table, though, so don't write `properties = { opts = {} }` —
give every nested schema a `type` too.

**`required` is a list.** `required = { "position" }` encodes as `["position"]`, which is
right. A single string won't work.

**Decode gives you numbers.** `msg.id` comes back as a Luau number; send it straight back as
`id` and it round-trips fine.

**Guard your handler.** An error thrown inside `MessageReceived` kills that callback, not the
socket, and the server sits waiting until the call times out. `pcall` your tool and turn a
failure into an `isError` result.

## Reply reference

| Code | Meaning |
|---|---|
| `-32700` | Message wasn't valid JSON |
| `-32600` | Wrong message for the current state (a second `session/hello`, say) |
| `-32601` | Unknown method |
| `-32602` | Bad params — malformed tool definition, bad arguments |
| `-32603` | Internal error |
| `-32000` | Unauthorized — bad token |
| `-32001` | Timeout — you didn't answer in time |
| `-32002` | Session closed mid-call |
| `-32003` | No session for that place |
| `-32004` | Unsupported `protocolVersion` |

| Close code | Meaning | Retry? |
|---|---|---|
| `1008` | Bad token, bad handshake, wrong version, or non-JSON | **No** — fix it first |
| `1009` | A single message went over the size cap (8MB, `VMCP_MAX_MESSAGE_MB`) | No — send less |
| `4000` | Superseded by a newer connection for the same `sessionId` | No, that's the new one's job |
| anything else | Server stopped, network blip | Yes, with backoff |

## Reconnecting

Yours to handle — the server never dials out.

**You can't read any of those close codes.** `WebStreamClient.Closed` fires with no arguments at
all, so the table above describes what the server sent, not what your plugin can see. Only
`Error(statusCode, message)` carries anything, and that's for failures while connecting.

What you *can* see is whether the handshake ever succeeded, and that happens to split the table
the right way:

- **Closed before the `session/hello` reply** — every `1008` lands here, because a bad token,
  bad version or non-JSON is refused during the handshake. Treat it as a configuration problem:
  stop, say why, and make the user act. Retrying won't start working.
- **Closed after a successful handshake** — the server stopped or the connection blipped. Retry
  with backoff.

`4000` is the one case that crosses the line: a supersede also arrives after a good handshake,
so two Studio windows sharing a `sessionId` would retry each other forever. Cap it by counting
closes that happen within a few seconds of connecting, and give up after a handful. That ends the
fight without needing the code.

Generate the `sessionId` per window and never persist it and this stays theoretical — it's only
reachable when two windows genuinely share one.

While you're disconnected your tools disappear from Claude's list. The server still caches
your last registered list to `%USERPROFILE%\.vmcp\tools.json`, and setting
`VMCP_LIST_OFFLINE=1` makes it keep listing closed places — marked `[place not open in
Studio]`, and calling one returns an error telling Claude to open it.

That's off by default because a remembered place counts toward the naming rule below, so
listing closed places renames every tool as soon as the server has ever seen a second one.

## What Claude sees

With one place known, tool names pass through bare — `insert_part`. With two or more, they
get namespaced by sanitized place name (`My_Game__insert_part`), plus a 4-char suffix when
two of them would collide — either two places sharing a name, or the same place open in two
Studio windows (`My_Game_a3f1__insert_part`).

Only places that are actually connected count, so opening one place at a time keeps bare
names. (With `VMCP_LIST_OFFLINE=1`, remembered places count too.)

Your side never deals with any of this. You always send and receive the bare name.

## Driving your plugin without Claude

`npm run probe` starts the server and gives you a prompt that does what Claude would —
`list` to see what registered, `call <tool> <json>` to run one. It prints the server's logs
alongside, so a rejected handshake or a bad tool definition shows up immediately with its
reason.

```
vmcp> call insert_part {"position": [0, 5, 0]}
  progress 1/3 finding space
  Inserted Part at 0, 5, 0
  ok in 412ms
```

Use it to get your plugin working before wiring Claude up at all. `npm run inspect` is the
same thing with the official MCP Inspector GUI.

## Testing without Studio

[`server/scripts/fake-plugin.mjs`](../server/scripts/fake-plugin.mjs) is a ~60-line Node
client that does everything above — connect, handshake, register `echo`, answer calls. If
anything here is ambiguous, that file is the executable version of it.

```
cd server
npm start                  # terminal 1
npm run fake-plugin        # terminal 2 — prints every message both ways
```

Watching its `->` / `<-` log is the fastest way to see the exact byte-level conversation your
plugin needs to reproduce.
