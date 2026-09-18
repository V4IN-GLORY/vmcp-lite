---
name: vmcp-icons
description: Making image assets for Roblox UI with VMCP — icons from Iconify and plates from SVG through OpenPencil (headless CLI), every PNG exported at 4096px and uploaded with upload_image so Roblox downsamples it, ids recorded in assets.json and Assets.luau, and screenshot_ui drawing the real picture. Use when asked for an icon, texture, plate, 9-slice, mockup or any image inside Roblox, or to get an rbxassetid for one.
---

# Icons and image assets

Nothing is drawn by hand in Luau any more. Art is vector (Iconify has ~200k icons; anything else
is an SVG file), OpenPencil rasterizes it headless, and the PNG goes up as a Roblox Image asset.

```
spec.json ──icons.mjs──▶ ~/.vmcp/design/<set>.fig ──export -s 4──▶ ~/.vmcp/images/<set>-<name>.png (4096px)
                                                                          │
                                        upload_image file=<set>-<name> ◀──┘ ──▶ rbxassetid, assets.json, Assets.luau
```

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

- `prefix:name` is an Iconify icon (search at icon-sets.iconify.design; `mdi`, `lucide`,
  `tabler`, `game-icons`, `ph` are the big ones). Filled sets come out filled; stroke sets
  (lucide, tabler) keep their stroke, scaled with the icon.
- `./file.svg` is a local SVG (relative to the spec). Only `<path d>` is read: convert shapes to
  paths first. `fill-opacity` / `stroke-opacity` are honoured. A local SVG keeps its viewBox
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

## Anything that isn't an icon

`openpencil eval <file.fig> -o out.fig --stdin` runs JavaScript against a Figma-Plugin-API
document: `figma.createFrame()`, `createRectangle()`, `createEllipse()`, `createVector()` with
`vectorPaths`, fills with gradients, text. Export with `openpencil export out.fig --node <id> -s N
-o ~/.vmcp/images/<name>.png`, then `upload_image file=<name>`. Design at 1024 on the long side
and export `-s 4`; or design at any size and compute `-s = 4096 / longSide`.

`openpencil import page.html -o page.fig` turns HTML + inline CSS (flex, padding, borders,
gradients, text) into a document — the fastest way to mock a whole panel. Inline `<svg>` is
dropped by the importer; icons go through `icons.mjs`.

A mockup is a reference image, not an asset: export it at `-s 1`, keep it beside the story, and
compare the `mount_story` screenshot with it by eye and with the numeric alignment sweep from
`vmcp-styling`.

## Setup (once)

- `npm i -g @open-pencil/cli` (Node 24 is fine). `openpencil formats` should list png.
- **Windows path bug in 0.15.1**: `export` fails with `ENOENT ... C:\C:\Users\...canvaskit.wasm`.
  Fix `node_modules/@open-pencil/core/dist/io/formats/raster/headless.js` under the global npm
  root: `const binDir = new URL(".", ckPath).pathname` → `fileURLToPath(new URL(".", ckPath))`
  (import it from `node:url`). Upstream fix pending; re-apply after an upgrade.
- OpenPencil's MCP server (`@open-pencil/mcp`, wired in `.mcp.json`) only bridges to the
  **running desktop app** — it is not headless. Use it when the user has the app open and wants
  to see designs live (`render` takes JSX with `<Icon name="mdi:heart"/>`, `export_image` writes a
  PNG with `maxEdge 4096`); otherwise everything above is the CLI.
- Open Cloud key with assets read/write, once: `upload_image apiKey=...`, kept in
  `~/.vmcp/roblox-api-key`. Owner is the Studio user unless a group id is passed. The key's own
  user id is in the 403 message if an upload is refused for a different user.
- A key pasted into chat is a key to roll: store it, test it, tell the user to rotate it.

## OpenPencil's eval runtime, the parts that bit

- `vectorPaths` accepts **absolute M L C Q Z only**, each with its own letter. `icons.mjs` runs
  every path through `svgpath` (`abs().unarc().unshort()`), rewrites H/V as L and writes explicit
  commands; svgpath's own `toString` emits implicit repeats, which the parser rejects.
- `appendChild` keeps page coordinates: read a node's own x/y **before** parenting it, then
  position it relative to the frame after.
- `rescale()` multiplies an existing `strokeWeight`; set the weight after rescaling.
- A transparent frame exports cropped to its content. An invisible rectangle (`opacity: 0` fill)
  the size of the frame keeps the full canvas.
- Node ids are renumbered when the file is written; look frames up by name afterwards
  (`openpencil find file.fig --type FRAME --json`), never by the id `eval` printed.
- Node refuses to spawn `openpencil.cmd` without a shell; run `node <npm root -g>/@open-pencil/cli/bin/openpencil.js`.
- `.pen` is a different container from `.fig`; `import` writes `.fig` whatever extension you ask
  for. Stay on `.fig`.

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
