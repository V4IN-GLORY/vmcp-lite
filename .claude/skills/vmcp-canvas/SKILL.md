---
name: vmcp-canvas
description: Drawing images in Studio with VMCP's Canvas — an EditableImage wrapper that records every operation so the server can write the same picture out as a PNG. Use when asked to generate a texture, icon, chart or any image inside Roblox.
---

# Canvas

Reached from a `run_luau` snippet as `vmcp.Canvas`. It wraps `EditableImage`, so the drawing is
the engine's own and shows up live in Studio — and it **records** every call, so the VMCP server
can replay the same list into a PNG on disk. One description, two outputs.

```lua
local canvas, problem = vmcp.Canvas.new(256, 256)
if not canvas then return problem end

canvas:Clear(Color3.fromRGB(18, 18, 24))
canvas:Rect(16, 16, 96, 48, Color3.fromRGB(220, 60, 60))
canvas:Circle(180, 180, 40, Color3.fromRGB(80, 200, 120), 0.5)
canvas:Line(0, 255, 255, 0, Color3.new(1, 1, 1), 3)

-- See it in Studio
local label = Instance.new("ImageLabel")
label.Size = UDim2.fromOffset(256, 256)
label.ImageContent = canvas:Content()
label.Parent = game:GetService("StarterGui"):FindFirstChildOfClass("ScreenGui")

-- And write it to disk
vmcp.Render(canvas, "health-bar")
```

Every method chains and takes an optional trailing alpha (0-1, default 1). `Line` takes a
thickness instead.

## Getting a file out

`vmcp.Render(canvas, name)` sends the canvas to the VMCP server, which writes a PNG under
`~/.vmcp/images/` and hands back the path. It works from **any context and from inside a
timeline event**, which is the reason to prefer it. The real pixels go along (base64 of
`ReadPixelsBuffer`) whenever the image is 512x512 or smaller, so anything drawn straight on
`canvas.image` is in the file too; bigger images are replayed from the recording instead.

```lua
local ok, where = vmcp.Render(canvas, "health-bar")
ctx.icon = where
```

The other way is to return the directive from a `run_luau` snippet, which does the same thing on
the way out:

```lua
return { postProcess = canvas:Recording() }
```

Names are letters, digits, underscore and hyphen only — anything else gets a timestamp instead.

## Uploading it as an asset

An `EditableImage` only exists in the session that drew it, so a script that needs the picture at
runtime wants an asset id. Two ways to get one:

```lua
-- while drawing: render and upload in one go
local ok, text = vmcp.Render(canvas, "hud-icon", { upload = true })
-- "[wrote the image to ...hud-icon.png] (uploaded as rbxassetid://123456789)"

-- a group should own it
vmcp.Render(canvas, "hud-icon", { upload = true, groupId = 12345678 })
```

Or the `upload_image` tool afterwards, for a PNG Render already wrote (`file = "hud-icon"`) or
an image in the place (`root` = an ImageLabel showing an EditableImage). `owner` is the Studio
user unless you pass a group id.

**One-time setup**: the upload runs on the VMCP server over Open Cloud, so it needs an API key
with the assets read/write scope for the owner (Creator Hub → Open Cloud → API keys). Call
`upload_image` once with `apiKey` and it's kept in `~/.vmcp/roblox-api-key`; `ROBLOX_API_KEY`
in the environment works too. Studio's own `AssetService:CreateAssetAsync` is tried first where
Roblox has enabled it. Moderation runs after upload — the id is real at once, the picture shows
a little later.

## Limits that come from the engine

- **1024x1024 maximum**, and an `EditableImage` **cannot be resized**. A bigger one means a new
  image plus `DrawImageTransformed`.
- **Only one EditableImage refreshes per frame** on the display side, so a wall of live previews
  updates one at a time.
- Studio and plugins get unlimited editable-image memory; only clients are budgeted.

## When you want more than these four operations

`canvas.image` is the real `EditableImage`, so `DrawImage`, `DrawImageTransformed`,
`WritePixelsBuffer` and the rest are all there. Anything drawn that way is **not recorded**, but
it still reaches the PNG through the pixel copy as long as the image is 512x512 or smaller.

`Line` is one pixel wide in the engine; a thickness is drawn as that many parallel lines, with
the endpoints clamped inside the image because `DrawLine` refuses a point outside it.

## Icons for a UI, start to finish

1. Put the drawing in a ModuleScript under the ScreenGui (`Icons.draw[name] = function(c) ... end`),
   so the art is source, not a one-off snippet. Draw white; tint with `ImageColor3` (a StyleRule
   can do that per tag).
2. Generator: `vmcp.Canvas.new` → draw → `vmcp.Render(canvas, "hud-" .. name, { upload = true })`
   once per icon; keep the ids in a table in the generator and set `ImageLabel.Image =
   "rbxassetid://id"`. Only upload an icon that has no id yet, or every rerun makes another asset.
3. Leave the live `ImageContent` path as the fallback for icons that have no id.

Why not EditableImage everywhere:
- `ImageContent` from an EditableImage **is never saved** with the place, and the images
  themselves die when the plugin that made them reloads — every label goes blank.
- In play mode a client can't even draw one unless **Mesh & Image APIs** is enabled in Game
  Settings → Security.
- `AssetService:CreateAssetAsync` says "not available yet" on most Studio builds, which is why
  the upload goes through the server.

## Things that bite

- `EditableImage:DrawRectangle` / `DrawCircle` / `DrawLine` require the `ImageCombineType`
  argument now; `DrawLine` lost its thickness and refuses an endpoint outside the image. Canvas
  handles all three.
- A plugin reload does **not** happen just because the rbxmx changed — re-add the plugin in
  Studio, then check with `vmcp.Tool("upload_image", {})` that the new tools are there.
- `~/.vmcp/profiles/<name>.gprx` is a plain byte sink (`{ kind = "gprx", data = base64 }`), handy
  for getting a big table out of Studio when a return value would be truncated.
