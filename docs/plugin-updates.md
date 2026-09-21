# Plugin updates need a click in Studio

The server never writes the Studio plugin on its own. It used to (`--auto-install-plugin`
overwrote `%LOCALAPPDATA%\Roblox\Plugins\VMCP.rbxmx` on every launch), and combined with an
install that pulls `main` from GitHub on every startup, that meant one compromised commit could
put a new plugin — code that runs inside Studio with full DataModel and HttpService access — onto
every machine running VMCP, with nobody looking. So:

1. `VMCP.rbxmx` still ships in the repo next to `server/`, built by `rojo build plugin.project.json`.
2. When a Studio edit session connects, the server compares that file with the installed one. If
   they differ it sends `plugin/update-available { sha256, destination, fresh, bytes }` — a
   notification, nothing written.
3. The VMCP panel shows **Update plugin (sha)**. Nothing happens until a person clicks it.
4. The click sends `plugin/update-apply { sha256 }` with the sha it was shown. The server re-reads
   the bundled file, refuses if the sha no longer matches, and otherwise writes it (temp file +
   rename, so Studio never reads a half-written plugin). Studio hot-reloads a changed local plugin.

Only an authenticated edit session can send `update-apply`, and only for the exact bytes it was
offered. A proxy process, a playtest peer or a bare socket can't.

## Installing the server

Pin what you run. `npx -y github:V4IN-GLORY/vmcp-lite` resolves `main` on every launch and runs
whatever is there; a tag or commit doesn't move:

```
claude mcp add vmcp -- npx -y github:V4IN-GLORY/vmcp-lite#<tag>
```

or clone, build, and point Claude at the build:

```
claude mcp add vmcp -- node "<path to repo>/server/dist/index.js"
```

Updating is then a deliberate `git pull` + `npm run build` (or bumping the tag), and the plugin
half of that update still waits for the click.

`VMCP_PLUGINS_DIR` overrides where the plugin is written.
