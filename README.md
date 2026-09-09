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

`src/plugin/` holds the panel UI and nothing else — no toolbar, no dock widget, no socket. Add
your own entry `Script` beside `Panel/`, then build from the plugin's own Rojo project:

```bash
rojo build plugin.project.json -o "$LOCALAPPDATA/Roblox/Plugins/VMCP.rbxm"
```

The panel is a plain module that builds and styles the widgets. It holds no protocol, no state
machine and no validation — you mount it, then drive it:

```lua
local Panel = require(script.Panel)
Panel.Mount(widget)

Panel.ConnectButton.Activated:Connect(function() ... end)
Panel.DisconnectButton.Activated:Connect(function() ... end)
Panel.PortInput.FocusLost:Connect(function(enterPressed) ... end)
Panel.TokenInput.FocusLost:Connect(function() ... end)

Panel.StatusLine.Text = "Connected · 6 tools · rev 3"
Panel.StatusWord.Text = "connected"
Panel.SetSignal("Live")        -- Idle | Work | Live | Fault; Work animates the hairline
Panel.SetTokenOpen(true)       -- the auth-token drawer
```

It carries its own styling, so it looks right wherever you mount it — `PluginGui`, `ScreenGui`
or a plain `Frame`. For Studio's light/dark theme call
`require(script.Panel.Style).SetTheme(isDark)` off `settings():GetService("Studio").ThemeChanged`.

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
