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

`vmcp.Render(canvas, name)` sends the recording to the VMCP server, which rasterizes it, writes a
PNG under `~/.vmcp/images/` and hands back the path. It works from **any context and from inside a
timeline event**, which is the reason to prefer it.

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
The recording is a few hundred bytes; the image itself never crosses the socket.

## Limits that come from the engine

- **1024x1024 maximum**, and an `EditableImage` **cannot be resized**. A bigger one means a new
  image plus `DrawImageTransformed`.
- **Only one EditableImage refreshes per frame** on the display side, so a wall of live previews
  updates one at a time.
- Studio and plugins get unlimited editable-image memory; only clients are budgeted.

## When you want more than these four operations

`canvas.image` is the real `EditableImage`, so `DrawImage`, `DrawImageTransformed`,
`WritePixelsBuffer` and the rest are all there. Anything drawn that way is **not recorded**, so it
appears in Studio and not in the PNG — use it for things that only need to exist in-engine.
