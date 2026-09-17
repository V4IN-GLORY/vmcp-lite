--!strict
--!native

-- An EditableImage that writes everything down.
--
-- The drawing itself is the engine's -- DrawRectangle, DrawCircle, DrawLine all exist and are
-- faster than anything written here would be. What earns this module its place is the recording:
-- the same list of operations goes back to Node, which replays it into a PNG. So one snippet
-- gives a live preview in Studio and a file on disk, from one description.
--
-- Render also ships the real pixels (ReadPixelsBuffer, base64) when the image is small enough,
-- so anything drawn straight on `canvas.image` -- DrawImage, WritePixelsBuffer -- lands in the
-- PNG too. The recording stays as the portable description and the fallback for big images.

local AssetService = game:GetService("AssetService")

-- The engine's hard cap. An EditableImage can't be resized either, so a bigger one means a new
-- image and a DrawImageTransformed into it.
local MAX_SIZE = 1024
-- Past this many bytes of RGBA the base64 alone is most of the socket's message budget, so the
-- server replays the recording instead. 512x512 is 1 MB raw, 1.4 MB encoded.
local MAX_PIXEL_BYTES = 512 * 512 * 4

local BLEND = Enum.ImageCombineType.AlphaBlend
local SMOOTH = Enum.AntiAliasing.Enabled

local Canvas = {}

export type Op = { [string]: any }

export type Canvas = {
	image: EditableImage,
	width: number,
	height: number,
	ops: { Op },
	assetId: number?,
	Clear: (self: Canvas, color: Color3, alpha: number?) -> Canvas,
	Rect: (self: Canvas, x: number, y: number, w: number, h: number, color: Color3, alpha: number?) -> Canvas,
	Circle: (self: Canvas, x: number, y: number, radius: number, color: Color3, alpha: number?) -> Canvas,
	Line: (self: Canvas, x1: number, y1: number, x2: number, y2: number, color: Color3, thickness: number?) -> Canvas,
	Content: (self: Canvas) -> Content,
	Pixels: (self: Canvas) -> string?,
	Upload: (self: Canvas, name: string, description: string?) -> (number?, string?),
	Recording: (self: Canvas) -> { [string]: any },
}

local Methods = {}
Methods.__index = Methods

local function record(self: any, op: Op): any
	table.insert(self.ops, op)
	return self
end

local function rgb(color: Color3): { number }
	return { color.R, color.G, color.B }
end

function Methods.Clear(self: any, color: Color3, alpha: number?): any
	self.image:DrawRectangle(
		Vector2.zero,
		Vector2.new(self.width, self.height),
		color,
		1 - (alpha or 1),
		Enum.ImageCombineType.Overwrite
	)
	return record(self, { kind = "clear", color = rgb(color), alpha = alpha or 1 })
end

function Methods.Rect(self: any, x: number, y: number, w: number, h: number, color: Color3, alpha: number?): any
	self.image:DrawRectangle(Vector2.new(x, y), Vector2.new(w, h), color, 1 - (alpha or 1), BLEND)
	return record(self, { kind = "rect", x = x, y = y, w = w, h = h, color = rgb(color), alpha = alpha or 1 })
end

function Methods.Circle(self: any, x: number, y: number, radius: number, color: Color3, alpha: number?): any
	self.image:DrawCircle(Vector2.new(x, y), radius, color, 1 - (alpha or 1), BLEND, SMOOTH)
	return record(self, { kind = "circle", x = x, y = y, r = radius, color = rgb(color), alpha = alpha or 1 })
end

-- DrawLine is one pixel wide and refuses an endpoint outside the image, so a thick line is a
-- stack of parallel ones, each clamped inside.
function Methods.Line(self: any, x1: number, y1: number, x2: number, y2: number, color: Color3, thickness: number?): any
	local width = math.max(1, math.round(thickness or 1))
	local dx, dy = x2 - x1, y2 - y1
	local length = math.max(1e-3, math.sqrt(dx * dx + dy * dy))
	local nx, ny = -dy / length, dx / length
	local maxX, maxY = self.width - 1, self.height - 1
	for i = 1, width do
		local offset = (i - 1) - (width - 1) / 2
		self.image:DrawLine(
			Vector2.new(math.clamp(x1 + nx * offset, 0, maxX), math.clamp(y1 + ny * offset, 0, maxY)),
			Vector2.new(math.clamp(x2 + nx * offset, 0, maxX), math.clamp(y2 + ny * offset, 0, maxY)),
			color,
			0,
			BLEND,
			SMOOTH
		)
	end
	return record(self, { kind = "line", x1 = x1, y1 = y1, x2 = x2, y2 = y2, color = rgb(color), thickness = width })
end

-- Assign to an ImageLabel's ImageContent to see it. Only one EditableImage refreshes per frame on
-- the display side, so a wall of live previews updates one at a time.
function Methods.Content(self: any): Content
	return Content.fromObject(self.image)
end

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local ENCODE = table.create(64)
for i = 1, 64 do
	ENCODE[i - 1] = string.byte(ALPHABET, i)
end

-- JSON has no bytes, so the RGBA buffer goes over as base64. Three input bytes to four output
-- bytes, written straight into a second buffer; no string concatenation on the way.
local function base64(bytes: buffer): string
	local length = buffer.len(bytes)
	local out = buffer.create(math.ceil(length / 3) * 4)
	local o = 0
	local full = length - length % 3
	for i = 0, full - 1, 3 do
		local a, b, c = buffer.readu8(bytes, i), buffer.readu8(bytes, i + 1), buffer.readu8(bytes, i + 2)
		local n = a * 65536 + b * 256 + c
		buffer.writeu8(out, o, ENCODE[n // 262144])
		buffer.writeu8(out, o + 1, ENCODE[n // 4096 % 64])
		buffer.writeu8(out, o + 2, ENCODE[n // 64 % 64])
		buffer.writeu8(out, o + 3, ENCODE[n % 64])
		o += 4
	end
	local rest = length - full
	if rest == 1 then
		local a = buffer.readu8(bytes, full)
		buffer.writeu8(out, o, ENCODE[a // 4])
		buffer.writeu8(out, o + 1, ENCODE[a % 4 * 16])
		buffer.writeu8(out, o + 2, 61)
		buffer.writeu8(out, o + 3, 61)
	elseif rest == 2 then
		local a, b = buffer.readu8(bytes, full), buffer.readu8(bytes, full + 1)
		buffer.writeu8(out, o, ENCODE[a // 4])
		buffer.writeu8(out, o + 1, ENCODE[a % 4 * 16 + b // 16])
		buffer.writeu8(out, o + 2, ENCODE[b % 16 * 4])
		buffer.writeu8(out, o + 3, 61)
	end
	return buffer.tostring(out)
end

-- Any EditableImage's real RGBA as base64, or nil when it's over the size the socket is happy
-- carrying or can't be read (Mesh & Image APIs off).
function Canvas.Base64Pixels(image: EditableImage): string?
	local size = image.Size
	if size.X * size.Y * 4 > MAX_PIXEL_BYTES then
		return nil
	end
	local ok, bytes = pcall(function()
		return image:ReadPixelsBuffer(Vector2.zero, size)
	end)
	if not ok then
		return nil
	end
	return base64(bytes)
end

function Methods.Pixels(self: any): string?
	return Canvas.Base64Pixels(self.image)
end

-- Publishes the image as an Image asset owned by whoever is logged into Studio and remembers the
-- id, so a script can use rbxassetid://id with no EditableImage at runtime. Moderation runs after
-- upload, so the id exists at once and the picture follows a little later.
function Methods.Upload(self: any, name: string, description: string?): (number?, string?)
	local ok, result, id = pcall(function()
		return AssetService:CreateAssetAsync(self.image, Enum.AssetType.Image, {
			Name = name,
			Description = description or "Generated with VMCP Canvas",
		})
	end)
	if not ok then
		return nil, `upload failed: {result}`
	end
	if result ~= Enum.CreateAssetResult.Success then
		return nil, `upload refused: {result}`
	end
	self.assetId = id
	return id, nil
end

-- What vmcp.Render sends to the VMCP server, which writes it as a PNG. Returning it from a
-- run_luau snippet as `postProcess` does the same thing on the way out. Carries the real pixels
-- when they fit, and the op list either way.
function Methods.Recording(self: any): { [string]: any }
	return {
		kind = "png",
		width = self.width,
		height = self.height,
		ops = self.ops,
		pixels = self:Pixels(),
		assetId = self.assetId,
	}
end

function Canvas.new(width: number, height: number): (Canvas?, string?)
	if width < 1 or height < 1 or width > MAX_SIZE or height > MAX_SIZE then
		return nil, `an EditableImage is 1 to {MAX_SIZE} pixels on a side; asked for {width}x{height}`
	end

	local ok, image = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(width, height) })
	end)
	if not ok then
		return nil, `couldn't create the image: {image}`
	end

	return setmetatable({ image = image, width = width, height = height, ops = {} }, Methods) :: any, nil
end

return Canvas
