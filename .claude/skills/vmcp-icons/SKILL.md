---
name: vmcp-icons
description: Making image assets for Roblox UI with VMCP — original icons and plates drawn as SVG (make-icons.py, never Iconify or stock sets) through OpenPencil's core run headless (the open-pencil MCP server in .mcp.json, or icons.mjs), every PNG exported at 4096px and uploaded with upload_image so Roblox downsamples it, ids recorded in assets.json and Assets.luau, and screenshot_ui drawing the real picture. Use when asked for an icon, texture, plate, 9-slice, mockup or any image inside Roblox, or to get an rbxassetid for one.
---

# Icons and image assets

Nothing is drawn by hand in Luau any more. Art is vector (Iconify has ~200k icons; anything else
is an SVG file or JSX), OpenPencil's core rasterizes it headless in Node, and the PNG goes up as a
Roblox Image asset. Two front doors to the same engine:

- **`open-pencil` MCP tools** (`openpencil-headless/index.mjs`, wired in `.mcp.json`): the upstream
  tool set — `render` (JSX: `<Frame>`, `<Text>`, `<Icon name="mdi:heart"/>`, gradients), `search_icons`,
  `import_svg`, `set_fill`, `get_page_tree`, `export_svg`… — plus `new_document` / `open_file` /
  `save_file` and an `export_image` that writes a 4K PNG to `~/.vmcp/images`. One document in
  memory, no app. For anything one-off: a plate, a mockup, a badge with text.
- **`icons.mjs`** for a whole set at once from one JSON spec.

```
spec.json ──icons.mjs──▶ ~/.vmcp/design/<set>.fig + ~/.vmcp/images/<set>-<name>.png (4096px) + <set>-sheet.png
new_document → render/import_svg → export_image path=../images/<name>.png scale=16
                                                                          │
                                        upload_image file=<name>       ◀──┘ ──▶ rbxassetid, assets.json, Assets.luau
```

## Draw the icons yourself — no Iconify, no stock sets

Every icon is original art drawn for this project: a generator script (`src/client/UI/design/
make-icons.py`) emits one SVG per icon as polygons/bands, and `icons.mjs` rasterizes them through
OpenPencil's core. Don't pull `prefix:name` icons from Iconify (the API throttles and 403s bursts
anyway) or any other stock set; a `./file.svg` entry in the spec is the only kind to use. Keep
stroked *curves* out of the SVGs — the importer spikes stroked polylines at each vertex — draw
arcs and rings as filled bands (`band()`, `ring()`) and holes as reverse-wound subpaths.

## The one rule: 4096, and let Roblox downsample

Every uploaded image is **4096 on its long side**. Roblox's ceiling is 4096×4096; the engine
mipmaps and streams smaller levels itself, so a 4K source is crisp at 24px on a phone and at 128px
on a 4K monitor. An image rasterized at display size is a 2–3× upscale on most screens and looks
like mush. `upload_image` refuses anything smaller unless `allowSmall = true`, and the old Canvas
(`EditableImage`, 1024 max) can't meet the bar, which is why it's demoted to "pixel data only".

The cost: 4096² RGBA is ~64 MB in GPU memory before compression. Forty such icons in one HUD is
real memory on mobile. If a project hits that, atlas repeated small icons into one sheet.

## Making a set

One JSON per set, kept in the project next to the UI that uses it (e.g. `src/client/UI/design/icons.json`):

```json
{ "set": "cp", "icons": { "reflex": "mdi:lightning-bolt", "int": "mdi:brain", "hex": "./hex.svg", "slot": "./slot.svg" } }
```

```
node server/scripts/icons.mjs src/client/UI/design/icons.json
```

It prints one line per PNG and writes `<set>-sheet.png`, a dark contact sheet — look at that before
uploading anything.

- `prefix:name` is an Iconify icon (search at icon-sets.iconify.design; `mdi`, `lucide`,
  `tabler`, `game-icons`, `ph` are the big ones). Filled sets come out filled; stroke sets
  (lucide, tabler) keep their stroke, scaled with the icon.
- `./file.svg` is a local SVG (relative to the spec), paths and basic shapes; `fill-opacity` /
  `stroke-opacity` on `<path>` are honoured. A local SVG keeps its viewBox
  aspect (a 256×160 plate exports 4096×2560); Iconify icons get a square frame with an 8% inset
  so `ScaleType.Fit` never clips the anti-aliased edge.
- Everything is drawn **white on transparent** and tinted at runtime with `ImageColor3` (a
  StyleRule per tag: `ImageLabel.Cyan { ImageColor3 = "$Cyan" }`). One asset, every colour.
- The `.fig` under `~/.vmcp/design/` is the editable source: `openpencil` (desktop app) opens it.

Then upload each one — `upload_image file=cp-reflex` (name = `<set>-<icon>`) — and put the ids in
`Assets.luau`, the only file that knows ids. Only upload an icon that has no id yet; every rerun
would make another asset. Uploads are remembered in `~/.vmcp/images/assets.json`
(`{ "<id>": "<png path>" }`), which is how `screenshot_ui` draws the real picture for an
`rbxassetid://` instead of the placeholder.

## Anything that isn't an icon: the MCP tools

```
new_document path=cp-badge.fig
render jsx='<Frame name="badge" w={256} h={64} flex="row" items="center" gap={8} p={12} rounded={8} bg="#FFFFFF">
  <Icon name="mdi:chip" size={32} color="#000000"/><Text size={20} weight="bold" color="#000000">CYBERWARE</Text></Frame>'
export_image ids=["<id>"] path=../images/cp-badge.png scale=16     → 4096x1024
save_file
upload_image file=cp-badge
```

`export_image` without `path` returns the picture inline (capped at 1280px) — the way to look
before committing to 4K. Design at any size; `scale` may upscale and `maxEdge` (default 4096
when writing a file) is the ceiling, so `scale=16` on a 256px frame is exactly the asset. Draw
white for anything an `ImageColor3` rule will tint; draw real colours for a plate that is one
picture.

Reading in vector art: `import_svg svg="<svg …>"` (strip `width="1em"` first — the importer
reads it as a 1×1 frame; the viewBox is the size) or `search_icons` → `insert_icon`. The
importer drops `fill-opacity`; set it after with `set_fill` / `set_opacity`.

A mockup of a whole panel is a reference image, not an asset: render it at the Roblox pixel size,
export inline or at `scale=1`, and compare the `mount_story` screenshot with it by eye and with
the numeric alignment sweep from `vmcp-styling`.

The desktop app can open any `.fig` under `~/.vmcp/design` for hand edits; save, and
`open_file` picks the change up.

## Setup (once)

- `npm install` at the repo root runs `prepare`, which installs `openpencil-headless/`
  (`@open-pencil/core` 0.15.1 + the MCP SDK). Its postinstall patches core's Windows path bug
  (`canvaskit.wasm` resolved as `C:\C:\…`); nothing to do by hand.
- Why our own server: upstream `@open-pencil/mcp` is a relay whose executor is the desktop app's
  webview (`openpencil-mcp --help`: "this bridge only forwards stdio JSON-RPC to it"). Every
  tool, `open_file` included, answers "app is not connected" without the app. Core's tools are
  plain `execute(figma, args)` functions, so `index.mjs` builds a `FigmaAPI` over a `.fig` in
  memory (the same object the CLI's `eval` uses) and serves the upstream definitions unchanged.
  Skipped on purpose: viewport/selection tools, `list_documents`, `close_file`. `eval` needs
  `OPENPENCIL_MCP_EVAL=1`.
- Open Cloud key with assets read/write, once: `upload_image apiKey=...`, kept in
  `~/.vmcp/roblox-api-key`. Owner is the Studio user unless a group id is passed. The key's own
  user id is in the 403 message if an upload is refused for a different user.
- A key pasted into chat is a key to roll: store it, test it, tell the user to rotate it.

## OpenPencil core, the parts that bit

- A transparent frame exports cropped to its content. An invisible rectangle (`opacity: 0` fill)
  the size of the frame keeps the full canvas. `clipsContent = true` is **not** the fix — a clipping
  frame exports opaque.
- Strokes on a frame's edge grow the export past the frame (a 4096 plate came out 4192). Inset the
  art; `icons.mjs` keeps 3% clear on plates.
- `createSVGNodes` / `import_svg`: `width="1em"` → a 1×1 frame, strip it; `fill-opacity` and
  `stroke-opacity` are dropped, one vector per `<path>` in order, set the paint opacity after.
- `rescale()` multiplies an existing `strokeWeight`; set weights after rescaling.
- `appendChild` keeps page coordinates: read a node's own x/y **before** parenting it.
- Node ids are renumbered when a file is written and read back; look frames up by name after
  `save_file` + `open_file`, not by an id from before.
- `.pen` is a different container from `.fig`; everything here is `.fig`.
- Imports of core in a script need file URLs on Windows (`pathToFileURL(require.resolve(...))`).

## Canvas, for pixel data only

`vmcp.Canvas` (an `EditableImage` wrapper that records its Rect/Circle/Line/Clear calls and
`vmcp.Render`s them into a PNG) still exists for things that are genuinely pixels — a heightmap, a
noise tile, a chart drawn from live data in a timeline. It is 1024 max, its `ImageContent` is
never saved with the place, and a plugin reload kills every live image, so nothing shown to a
player should come from it. `upload_image root=<ImageLabel>` uploads one with `allowSmall`.

## Lessons kept from the Canvas era

- **A plugin reload killed every EditableImage**, every icon label went blank, and no property
  read said why. The fix was never "redraw them" — it was assets. Same answer today.
- **"The icon looks off" was the number beside it.** A rule value equal to the class default never
  reached the client (see `vmcp-styling`). Inspect the label next to the icon (`inspect_style`,
  `context = "client"`) before touching the art.
- **A running VMCP server doesn't have code you just wrote.** Server changes are live after a
  push *and* a Claude restart; test `dist` with `node -e 'import("file:///…/dist/x.js")'` until
  then. Plugin changes need `rojo build plugin.project.json -o %LOCALAPPDATA%/Roblox/Plugins/VMCP.rbxmx`
  and a re-add through Plugins → Manage; `luau-lsp analyze` a new tool first, the loader accepts a
  type error and you find out at call time.
- **Big data out of Studio** is the gprx sink: `vmcp.Render({ kind = "gprx", data = base64 }, name)`
  writes bytes to `~/.vmcp/profiles/name.gprx` when a return value would be truncated.

## Struggles and lessons, in the order they happened

- **"Headless" in OpenPencil's README meant the CLI, not the MCP.** `@open-pencil/mcp` probed with
  the SDK: 115 tools listed, every call including `open_file` returned "app is not connected".
  Its `--help` says so. The headless parts are `core` (engine, tools, IO, renderer), `cli`, and
  `dom-css`; `vue` is headless in the UI sense only.
- **First attempt was the CLI**: `import` (HTML→.fig) for a blank document, `eval` (Figma
  Plugin API JS) to build vectors, `export -s` to rasterize. It worked but cost a day of quirks:
  `vectorPaths` wants absolute M/L/C/Q/Z with explicit letters (svgpath's `toString` writes
  implicit repeats the parser rejects), H/V unsupported, ids renumbered on save so `--node <id>`
  from `eval`'s output pointed at the invisible plate, Node refusing `openpencil.cmd` without a
  shell, `.pen` vs `.fig`. All gone once core ran in-process: `createSVGNodes` reads SVG itself.
- **Core's raster export failed on Windows** with `ENOENT C:\C:\Users\...canvaskit.wasm`
  (`new URL(".", ckPath).pathname`). Patched in place; `openpencil-headless/patch-canvaskit.mjs`
  reapplies it on every install. Upstream 0.15.1.
- **`new SceneGraph()` has no page**; the blank document is a committed `blank.fig` (made once from
  an HTML import, children stripped through `FigmaAPI`). `new_document` reads it.
- **`isToolExposed` isn't on core's main export**; it's `@open-pencil/core/tools`. Dynamic
  `import()` of a resolved path on Windows needs `pathToFileURL(...).href`.
- **The contact sheet lied twice**: first it was all transparent (the plate's `opacity: 0`
  rectangle was exported *as* the icon because ids had renumbered), then all-white (an HTML
  `<div>` left in the blank doc; `clipsContent` making frames opaque). Decode and count opaque
  pixels (`decodePng` in `server/dist/image.js`) before trusting a viewer that shows transparent
  as white.
- **The `\b` in a regex became a backspace byte** when written through a shell heredoc; the file
  looked right in `grep` and matched nothing. `cat -A` shows `^H`. Write regex-bearing edits with
  the Write/Edit tools, not `sed`/heredocs.
- **Re-upload when the picture changes, and change `Assets.luau`.** The 3% plate inset altered
  `cp-hex.png` / `cp-slot.png` after they were uploaded; `assets.json` would have mapped the old
  ids to new pixels. New ids, old ones orphaned on Roblox (fine).
