# VMCP Lite

An MCP server that lets Claude drive Roblox Studio, where **the tools are written in Luau**.

This is the scripts-and-building cut of [VMCP](https://github.com/V4IN-GLORY/mcp-test): the
same server and plugin with the UI, styling, icon and animation tooling removed. What's left:

| area | tools |
|---|---|
| scripts | `run_luau`, `search_scripts`, `get_tree`, `get_logs`, `print`, `count_lines`, `try_scripts`, `apply_fix` |
| building | `apply_build`, `render_build`, `get_build` |
| runtime | `playtest`, `run_timeline`, `review_remotes` |
| performance | `profile_scripts`, `lint_hotpaths`, `optimization_ledger` |

Skills under `.claude/skills/`: `vmcp-build`, `vmcp-debugging`, `vmcp-optimization`, `vmcp-timeline`.
`vmcp-build` is a short core plus a `references/` library the model loads per phase, with
`references/types/` for per-build-type tips you can add to by PR.

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

## When Claude lists the tools but can't reach your place

Call `vmcp_status` (it's served by the Node side, so it's always listed). It says which process
owns the port, every Studio session connected to it with place name and id, and where the token
file is. Then:

- **No connected sessions** — look at the VMCP panel in Studio. `refused` is a wrong token or an
  old plugin build; `connecting` that never resolves means nothing is listening on that port;
  `not connected` means Connect wasn't pressed. The server prints the reason for every connection
  it refuses to stderr (`claude mcp` shows it with `--debug`).
- **Connected, but it's a different place / window** — two Studio windows each connect as their
  own session; tools get a place prefix once the server knows two places. Close the one you're
  not using or call the prefixed name.
- **`this MCP process is a proxy`** — another VMCP owns the port (a second Claude session, or an
  old process). That's normal; the primary's sessions are what you're seeing. If the primary is
  stale, end it and the proxy takes over.
- **A socket error in Studio's Output like `Failed ws recv ... forcibly closed`** — the server
  process died or was replaced mid-session. The plugin reconnects on its own with backoff (up to
  30s); if it gives up with `superseded`, press Connect again.

## Building the plugin

`src/plugin/` holds the panel UI and nothing else — no toolbar, no dock widget, no socket.
`init.server.luau` is the entry point and is deliberately empty; fill it in, then build from the
plugin's own Rojo project:

```bash
rojo build plugin.project.json -o "$LOCALAPPDATA/Roblox/Plugins/VMCP.rbxm"
```

Restart Studio afterwards — it only picks up newly installed plugins on load.

After that, updates are offered, not pushed: when the bundled `VMCP.rbxmx` differs from the
installed one, the panel shows an **Update plugin** button and nothing is written until it's
clicked. [`docs/plugin-updates.md`](docs/plugin-updates.md) has the why and how to pin the server.

Or work from the place instead: `rojo serve`, then right-click **ServerStorage → VMCP** and pick
*Save as Local Plugin*. That menu item only appears on a `Script`, which is why `src/plugin` has
an `init.server.luau` at its root rather than being a bare folder.

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
