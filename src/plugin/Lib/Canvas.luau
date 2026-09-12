--!strict

-- An EditableImage that writes everything down.
--
-- The drawing itself is the engine's -- DrawRectangle, DrawCircle, DrawLine all exist and are
-- faster than anything written here would be. What earns this module its place is the recording:
-- the same list of operations goes back to Node, which replays it into a PNG. So one snippet
-- gives a live preview in Studio and a file on disk, from one description.

local AssetService = game:GetService("AssetService")

-- The engine's hard cap. An EditableImage can't be resized either, so a bigger one means a new
-- image and a DrawImageTransformed into it.
local MAX_SIZE = 1024

local Canvas = {}

export type Op = { [string]: any }

export type Canvas = {
	image: EditableImage,
	width: number,
	height: number,
	ops: { Op },
	Clear: (self: Canvas, color: Color3, alpha: number?) -> Canvas,
	Rect: (self: Canvas, x: number, y: number, w: number, h: number, color: Color3, alpha: number?) -> Canvas,
	Circle: (self: Canvas, x: number, y: number, radius: number, color: Color3, alpha: number?) -> Canvas,
	Line: (self: Canvas, x1: number, y1: number, x2: number, y2: number, color: Color3, thickness: number?) -> Canvas,
	Content: (self: Canvas) -> Content,
	Recording: (self: Canvas) -> { [string]: any },
}

local Methods = {}
Methods.__index = Methods

local function record(self: any, op: Op): any
	table.insert(self.ops, op)
	return self
end

function Methods.Clear(self: any, color: Color3, alpha: number?): any
	self.image:DrawRectangle(Vector2.zero, Vector2.new(self.width, self.height), color, 1 - (alpha or 1))
	return record(self, { kind = "clear", color = { color.R, color.G, color.B }, alpha = alpha or 1 })
end

function Methods.Rect(self: any, x: number, y: number, w: number, h: number, color: Color3, alpha: number?): any
	self.image:DrawRectangle(Vector2.new(x, y), Vector2.new(w, h), color, 1 - (alpha or 1))
	return record(
		self,
		{ kind = "rect", x = x, y = y, w = w, h = h, color = { color.R, color.G, color.B }, alpha = alpha or 1 }
	)
end

function Methods.Circle(self: any, x: number, y: number, radius: number, color: Color3, alpha: number?): any
	self.image:DrawCircle(Vector2.new(x, y), radius, color, 1 - (alpha or 1))
	return record(
		self,
		{ kind = "circle", x = x, y = y, r = radius, color = { color.R, color.G, color.B }, alpha = alpha or 1 }
	)
end

function Methods.Line(self: any, x1: number, y1: number, x2: number, y2: number, color: Color3, thickness: number?): any
	local width = thickness or 1
	self.image:DrawLine(Vector2.new(x1, y1), Vector2.new(x2, y2), color, 0, Enum.ImageCombineType.Overwrite, width)
	return record(self, {
		kind = "line",
		x1 = x1,
		y1 = y1,
		x2 = x2,
		y2 = y2,
		color = { color.R, color.G, color.B },
		thickness = width,
	})
end

-- Assign to an ImageLabel's ImageContent to see it. Only one EditableImage refreshes per frame on
-- the display side, so a wall of live previews updates one at a time.
function Methods.Content(self: any): Content
	return Content.fromObject(self.image)
end

-- Hand this back from a run_luau snippet as `postProcess` and the VMCP server replays it to a PNG.
function Methods.Recording(self: any): { [string]: any }
	return { kind = "png", width = self.width, height = self.height, ops = self.ops }
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
