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

- `server/src/install-plugin.ts` — `installBundledPlugin()`: resolves `plugin/VMCP.rbxmx` next
  to `dist/`, compares with the installed copy, stages + renames if different.
  `VMCP_PLUGINS_DIR` overrides the destination folder.
- `server/src/index.ts` — runs it first when `--auto-install-plugin` is in argv. Failure is
  logged and the server still starts.
- `server/package.json`
  - `name`: `@v4in-glory/mcp-test` (npm scopes must be lowercase)
  - `private` removed
  - `files`: `dist`, `plugin/VMCP.rbxmx`
  - `build:plugin`: `rojo build ../plugin.project.json -o plugin/VMCP.rbxmx`
  - `prepack`: `npm run build && npm run build:plugin` — publish always bundles a fresh plugin
- `.gitignore` — `server/plugin/` is build output, not source.

The asset is named `VMCP.rbxmx` to match the file already in the Plugins folder, so the first
install overwrites instead of creating a duplicate. The auth token lives in plugin settings
(`plugin:SetSetting`), so replacing the file doesn't lose it.

## Release flow

```
cd server
npm version patch          # required — @latest only sees new versions
npm publish --access public
```

## Registering with Claude

```
claude mcp add vmcp -- npx -y @v4in-glory/mcp-test@latest --auto-install-plugin
```

Use a different name than `robloxstudio` if the chrrxs server should stay installed too.

## Verified

- First run: `[vmcp] installed VMCP.rbxmx to C:\Users\...\Roblox\Plugins\VMCP.rbxmx`
- Second run with no change: no install line, server starts normally.
