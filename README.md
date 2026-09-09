# VMCP

An MCP server that lets Claude drive Roblox Studio, where **the tools are written in Luau**.

Two halves:

- `server/` — the TypeScript MCP server. Talks MCP to Claude on one side, WebSocket to
  Studio on the other. Has no tools of its own and never needs editing to add one.
- `src/` — the Rojo place. The Studio plugin that registers tools lives on this side.

The plugin sends its tool list — names, descriptions, JSON schemas — when it connects, and
those become the tools Claude sees. Adding a tool means writing Luau, not TypeScript.

## Running it

```bash
cd server
npm install
npm run build
npm run token          # prints the auth token to paste into the plugin
```

Point Claude at it:

```bash
claude mcp add vmcp -- node "<path to repo>/server/dist/index.js"
```

The server writes its token and cached tool lists to `%USERPROFILE%\.vmcp\`.

| Env var | Default | What it does |
|---|---|---|
| `VMCP_PORT` | `8791` | Bridge port |
| `VMCP_TIMEOUT_MS` | `30000` | Default per-call timeout |
| `VMCP_MAX_MESSAGE_MB` | `8` | Largest single WebSocket message |
| `VMCP_LIST_OFFLINE` | off | Keep listing tools for places that aren't open |
| `VMCP_HOME` | `~/.vmcp` | Where the token and tool cache live |

## Building the plugin

The plugin lives in `src/plugin/` and builds from its own Rojo project, separate from the place:

```bash
rojo build plugin.project.json -o "$LOCALAPPDATA/Roblox/Plugins/VMCP.rbxm"
```

Restart Studio and the **VMCP** button appears on the Plugins tab. It opens a dock widget with
the bridge port, Connect/Disconnect, and a collapsed auth-token field that opens itself when the
socket closes with `1008`.

The panel is UI only right now. `src/plugin/init.server.luau` drives it through a stub that walks
the connection states on a timer; the real socket replaces the bodies of `Panel.OnConnect` and
`Panel.OnDisconnect` and nothing else. `Panel.SetState(kind, detail)` is how the transport
reports back — `"idle"`, `"connecting"`, `"connected"`, `"fault"`.

[`docs/protocol.md`](docs/protocol.md) is the full contract — handshake, message shapes,
error codes, Luau JSON gotchas. It's the only file you need.

## Testing without Claude

`npm run probe` stands in for Claude. It starts the server and gives you a prompt, so you
can drive your plugin by hand:

```
$ npm run probe
[vmcp] bridge listening on ws://127.0.0.1:8791

VMCP probe. The server is up on 8791 — connect your plugin now.

vmcp> list
  echo  [readOnly]
    Echoes the text back.
    args: text

vmcp> call echo {"text":"hi"}
  echo: hi
  ok in 3ms
```

It prints the server's own logs too, so you see handshakes, registrations and rejections as
they happen. Progress messages and revision notices show up live. Don't run `npm start`
alongside it — both want the same port, and the probe will tell you so if you do.

For a GUI instead, `npm run inspect` opens the official MCP Inspector against the same
server.

To watch the raw wire conversation without Studio at all:

```bash
npm run probe          # terminal 1
npm run fake-plugin    # terminal 2 — a Node stand-in that logs every message both ways
```

## The place itself

Standard Rojo project, built with [Rojo](https://rojo.space/) 7.7.0-rc.1:

```bash
rojo build -o "VMCP.rbxlx"
rojo serve
```
