# Auto-installing the plugin from the MCP server

Goal: `claude mcp add vmcp -- npx -y @v4in-glory/mcp-test@latest --auto-install-plugin`
keeps both the server and the Studio plugin current on every Claude startup, the same way
`@chrrxs/robloxstudio-mcp` does.

## How chrrxs does it (and what we copied)

The plugin rbxmx ships *inside* the npm package. There is no GitHub release fetch at runtime.

1. `npx -y pkg@latest` runs on every Claude startup, so npm pulls the newest published version.
2. With `--auto-install-plugin`, the server byte-compares the bundled rbxmx against
   `%LOCALAPPDATA%\Roblox\Plugins\<name>.rbxmx` and overwrites it only when it differs
   (write to a temp file, then rename, so Studio never reads a half-written plugin).
3. Studio hot-reloads a changed local plugin file. Only a brand-new file needs a restart.

Updating the plugin therefore means: bump the package version, publish. Nothing else.

## What changed in VMCP

- `server/src/install-plugin.ts` — `installBundledPlugin()`: resolves `VMCP.rbxmx` next
  to `dist/`, compares with the installed copy, stages + renames if different.
  `VMCP_PLUGINS_DIR` overrides the destination folder.
- `server/src/index.ts` — runs it first when `--auto-install-plugin` is in argv. Failure is
  logged and the server still starts.
- `server/package.json`
  - `name`: `@v4in-glory/mcp-test` (npm scopes must be lowercase)
  - `private` removed
  - `files`: `dist`, `VMCP.rbxmx`
  - `build:plugin`: `rojo build ../plugin.project.json -o ../VMCP.rbxmx`
  - `prepack`: `npm run build && npm run build:plugin` — publish always bundles a fresh plugin
- `.gitignore` — `VMCP.rbxmx (repo root)` is build output, not source.

The asset is named `VMCP.rbxmx` to match the file already in the Plugins folder, so the first
install overwrites instead of creating a duplicate. The auth token lives in plugin settings
(`plugin:SetSetting`), so replacing the file doesn't lose it.

## Distribution: GitHub, not npm

Private npm scopes cost money, so the package is installed straight from the repo:

```
claude mcp add vmcp -- npx -y github:V4IN-GLORY/mcp-test --auto-install-plugin
```

npm resolves `main` to a commit on every startup, clones it, installs the root
`package.json` deps, and runs its `prepare` script (`tsc -p server` + `rojo build` to
`VMCP.rbxmx` at the repo root). `.npmignore` exists because npm would otherwise use
`.gitignore` and strip `server/dist/`. Requires `rojo` on PATH (`rokit install`).

The root `package.json` owns the runtime deps because npm git installs can't target a
subfolder; `server/package.json` is kept for the dev scripts only.

## Release flow

Push to `main`. That's it � the next Claude startup rebuilds and reinstalls the plugin.
