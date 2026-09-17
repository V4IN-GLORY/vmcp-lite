--!strict

-- Draws a GUI tree as a picture. Studio has no screenshot a plugin can take, so this walks the
-- GuiObjects in render order, reads every visual property through GetStyled (the only read that
-- sees StyleRules), and hands the flat list to the VMCP server, which rasterizes it.
--
-- What comes back is a layout check, not a render: boxes, strokes, gradients, corner radii and
-- rotation are exact; text is a bitmap font; EditableImage pixels are real, asset images are a
-- placeholder, and a ViewportFrame is a box naming what's inside it.

local Path = require(script.Parent.Parent.Path)

local MAX_NODES = 4000
-- Pixels for an ImageLabel backed by an EditableImage are shipped when it's this small or less;
-- bigger ones (a wall of previews) get the placeholder so the payload stays sane.
local MAX_IMAGE_SIDE = 128
local DEFAULT_MAX_SIDE = 1024

type Result = {
	content: { { type: "text", text: string } },
	isError: boolean?,
	postProcess: { [string]: any }?,
}

type Rect = { x: number, y: number, w: number, h: number }

local Tool = {}

Tool.Definition = {
	name = "screenshot_ui",
	description = "Draws a ScreenGui (or any GuiObject) as a PNG so you can look at the layout "
		.. "instead of reading AbsolutePosition numbers. Reads styled values, so StyleSheet rules "
		.. "show. Boxes, strokes, gradients, corners and rotation are exact; text is a bitmap "
		.. "font (check overflow with TextFits, not by eye); EditableImage icons are real pixels, "
		.. "asset images are a tinted placeholder, ViewportFrames are a box naming their contents. "
		.. "context plugin draws StarterGui as Studio lays it out; context client draws the "
		.. "player's live PlayerGui.",
	inputSchema = {
		type = "object",
		properties = {
			root = {
				type = "string",
				description = 'Dotted path to a ScreenGui, GuiObject, or a container of ScreenGuis. '
					.. "Defaults to StarterGui in the edit session and the local PlayerGui in a client.",
			},
			context = {
				type = "string",
				description = "Which DataModel. Defaults to plugin.",
				enum = { "plugin", "server", "client" },
			},
			player = {
				type = "integer",
				description = "Which test client, 1-based. Only meaningful with context client.",
				minimum = 1,
				maximum = 8,
			},
			scale = {
				type = "number",
				description = "Output pixels per screen pixel, 0.1 to 1. Defaults to whatever fits the longer side into 1024.",
				minimum = 0.1,
				maximum = 1,
			},
			name = {
				type = "string",
				description = "File name, letters digits underscore hyphen. Defaults to a timestamp.",
			},
		},
	},
	tags = { title = "Screenshot UI", readOnly = true },
	timeoutMs = 60000,
}

local function styled(instance: Instance, name: string): any
	local ok, value = pcall(function()
		return (instance :: any):GetStyled(name)
	end)
	if ok then
		return value
	end
	return (instance :: any)[name]
end

local function rgb(color: Color3): { number }
	return { color.R, color.G, color.B }
end

local function intersect(a: Rect?, b: Rect): Rect
	if not a then
		return b
	end
	local x1, y1 = math.max(a.x, b.x), math.max(a.y, b.y)
	local x2, y2 = math.min(a.x + a.w, b.x + b.w), math.min(a.y + a.h, b.y + b.h)
	return { x = x1, y = y1, w = math.max(x2 - x1, 0), h = math.max(y2 - y1, 0) }
end

local ALIGN_X = { [Enum.TextXAlignment.Left] = 0, [Enum.TextXAlignment.Center] = 0.5, [Enum.TextXAlignment.Right] = 1 }
local ALIGN_Y = { [Enum.TextYAlignment.Top] = 0, [Enum.TextYAlignment.Center] = 0.5, [Enum.TextYAlignment.Bottom] = 1 }

local base64: (buffer) -> string
do
	local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	local ENCODE = table.create(64)
	for i = 1, 64 do
		ENCODE[i - 1] = string.byte(ALPHABET, i)
	end
	base64 = function(bytes: buffer): string
		local length = buffer.len(bytes)
		local out = buffer.create(math.ceil(length / 3) * 4)
		local o = 0
		local full = length - length % 3
		for i = 0, full - 1, 3 do
			local n = buffer.readu8(bytes, i) * 65536 + buffer.readu8(bytes, i + 1) * 256 + buffer.readu8(bytes, i + 2)
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
end

-- One EditableImage's pixels are read once however many labels show it.
local pixelCache: { [EditableImage]: { px: string, pw: number, ph: number }? } = {}

local function imagePixels(image: EditableImage): { px: string, pw: number, ph: number }?
	local cached = pixelCache[image]
	if cached ~= nil then
		return cached
	end
	local size = image.Size
	local result = nil
	if size.X <= MAX_IMAGE_SIDE and size.Y <= MAX_IMAGE_SIDE then
		local ok, bytes = pcall(function()
			return image:ReadPixelsBuffer(Vector2.zero, size)
		end)
		if ok then
			result = { px = base64(bytes), pw = size.X, ph = size.Y }
		end
	end
	pixelCache[image] = result
	return result
end

type Walk = { nodes: { any }, origin: Vector2, count: number, skipped: number, global: boolean }

local function describe(state: Walk, gui: GuiObject, clip: Rect?)
	local pos = gui.AbsolutePosition - state.origin
	local size = gui.AbsoluteSize
	local node: { [string]: any } = {
		k = "rect",
		x = pos.X,
		y = pos.Y,
		w = size.X,
		h = size.Y,
		rot = gui.AbsoluteRotation,
		bg = rgb(styled(gui, "BackgroundColor3")),
		a = 1 - styled(gui, "BackgroundTransparency"),
		clip = clip,
		z = styled(gui, "ZIndex"),
	}

	for _, child in gui:GetChildren() do
		if child:IsA("UIStroke") and styled(child, "Enabled") and styled(child, "ApplyStrokeMode") == Enum.ApplyStrokeMode.Border then
			node.stroke = { color = rgb(styled(child, "Color")), a = 1 - styled(child, "Transparency"), t = styled(child, "Thickness") }
		elseif child:IsA("UICorner") then
			local radius: UDim = styled(child, "CornerRadius")
			node.corner = radius.Offset + radius.Scale * math.min(size.X, size.Y)
		elseif child:IsA("UIGradient") and styled(child, "Enabled") then
			local colors, alphas = {}, {}
			for _, key in (styled(child, "Color") :: ColorSequence).Keypoints do
				table.insert(colors, { key.Time, key.Value.R, key.Value.G, key.Value.B })
			end
			for _, key in (styled(child, "Transparency") :: NumberSequence).Keypoints do
				table.insert(alphas, { key.Time, key.Value })
			end
			node.grad = { rot = styled(child, "Rotation"), colors = colors, alphas = alphas }
		end
	end

	if gui:IsA("TextLabel") or gui:IsA("TextButton") or gui:IsA("TextBox") then
		node.k = "text"
		local text: string = styled(gui, "Text")
		if gui:IsA("TextBox") and text == "" then
			text = styled(gui, "PlaceholderText")
		end
		local textSize: number = if styled(gui, "TextScaled") then math.min(gui.TextBounds.Y, size.Y) else styled(gui, "TextSize")
		node.text = {
			s = text,
			size = textSize,
			color = rgb(styled(gui, "TextColor3")),
			a = 1 - styled(gui, "TextTransparency"),
			ax = ALIGN_X[styled(gui, "TextXAlignment")] or 0.5,
			ay = ALIGN_Y[styled(gui, "TextYAlignment")] or 0.5,
			wrap = styled(gui, "TextWrapped") == true,
		}
	elseif gui:IsA("ImageLabel") or gui:IsA("ImageButton") then
		node.k = "image"
		local image: { [string]: any } = {
			color = rgb(styled(gui, "ImageColor3")),
			a = 1 - styled(gui, "ImageTransparency"),
		}
		local content: Content = styled(gui, "ImageContent")
		local object = if content.SourceType == Enum.ContentSourceType.Object then content.Object else nil
		if object and object:IsA("EditableImage") then
			local pixels = imagePixels(object)
			if pixels then
				image.px, image.pw, image.ph = pixels.px, pixels.pw, pixels.ph
			end
		elseif content.SourceType == Enum.ContentSourceType.None and (styled(gui, "Image") :: string) == "" then
			image.a = 0
		end
		if styled(gui, "ScaleType") == Enum.ScaleType.Tile then
			local tile: UDim2 = styled(gui, "TileSize")
			image.tile = { w = tile.X.Offset + tile.X.Scale * size.X, h = tile.Y.Offset + tile.Y.Scale * size.Y }
		end
		node.image = image
	elseif gui:IsA("ViewportFrame") then
		node.k = "viewport"
		local parts = 0
		for _, d in gui:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
		node.label = if parts > 0 then `VIEWPORT: {parts} PARTS` else "VIEWPORT: EMPTY"
	end

	return node
end

local function walk(state: Walk, gui: GuiObject, clip: Rect?, order: { any })
	if state.count >= MAX_NODES then
		state.skipped += 1
		return
	end
	if not styled(gui, "Visible") then
		return
	end
	state.count += 1
	local node = describe(state, gui, clip)
	table.insert(order, node)

	local childClip = clip
	if styled(gui, "ClipsDescendants") then
		childClip = intersect(clip, { x = node.x, y = node.y, w = node.w, h = node.h })
	end

	local children = {}
	for index, child in gui:GetChildren() do
		if child:IsA("GuiObject") then
			table.insert(children, { child = child, z = styled(child, "ZIndex"), index = index })
		end
	end
	if not state.global then
		table.sort(children, function(a, b)
			if a.z ~= b.z then
				return a.z < b.z
			end
			return a.index < b.index
		end)
	end
	for _, entry in children do
		walk(state, entry.child, childClip, order)
	end
end

-- ScreenGuis in a container draw by DisplayOrder, then by the order they were added.
local function screenGuisUnder(container: Instance): { ScreenGui }
	local guis = {}
	for _, child in container:GetChildren() do
		if child:IsA("ScreenGui") and child.Enabled then
			table.insert(guis, child)
		end
	end
	table.sort(guis, function(a, b)
		return a.DisplayOrder < b.DisplayOrder
	end)
	return guis
end

function Tool.Run(arguments: { root: string?, scale: number?, name: string? }): Result
	local root: Instance
	if type(arguments.root) == "string" and arguments.root ~= "" then
		local found, problem = Path.Resolve(arguments.root)
		if not found then
			return { content = { { type = "text", text = problem :: string } }, isError = true }
		end
		root = found
	else
		local player = game:GetService("Players").LocalPlayer
		local playerGui = if player then player:FindFirstChild("PlayerGui") else nil
		root = playerGui or game:GetService("StarterGui")
	end

	-- Every list of GuiObjects to draw, each with the ScreenGui whose ZIndexBehavior governs it.
	local layers: { { guis: { GuiObject }, global: boolean } } = {}
	local reference: GuiBase2d? = nil
	if root:IsA("GuiObject") then
		local screen = root:FindFirstAncestorWhichIsA("ScreenGui")
		local global = screen ~= nil and screen.ZIndexBehavior == Enum.ZIndexBehavior.Global
		table.insert(layers, { guis = { root }, global = global })
		reference = root
	elseif root:IsA("ScreenGui") then
		local guis = {}
		for _, child in root:GetChildren() do
			if child:IsA("GuiObject") then
				table.insert(guis, child)
			end
		end
		table.insert(layers, { guis = guis, global = root.ZIndexBehavior == Enum.ZIndexBehavior.Global })
		reference = root
	else
		for _, screen in screenGuisUnder(root) do
			local guis = {}
			for _, child in screen:GetChildren() do
				if child:IsA("GuiObject") then
					table.insert(guis, child)
				end
			end
			table.insert(layers, { guis = guis, global = screen.ZIndexBehavior == Enum.ZIndexBehavior.Global })
			reference = reference or screen
		end
	end
	if not reference then
		return {
			content = { { type = "text", text = `{root:GetFullName()} has no ScreenGui or GuiObject to draw` } },
			isError = true,
		}
	end

	local origin = reference.AbsolutePosition
	local size = reference.AbsoluteSize
	if size.X < 1 or size.Y < 1 then
		return {
			content = { { type = "text", text = `{reference:GetFullName()} has no size yet -- nothing is laid out` } },
			isError = true,
		}
	end

	table.clear(pixelCache)
	local state: Walk = { nodes = {}, origin = origin, count = 0, skipped = 0, global = false }
	for _, layer in layers do
		state.global = layer.global
		local order = {}
		local children = {}
		for index, gui in layer.guis do
			table.insert(children, { child = gui, z = styled(gui, "ZIndex"), index = index })
		end
		table.sort(children, function(a, b)
			if a.z ~= b.z then
				return a.z < b.z
			end
			return a.index < b.index
		end)
		for _, entry in children do
			walk(state, entry.child, nil, order)
		end
		if layer.global then
			-- Global: every descendant sorts by ZIndex alone, ties keep tree order.
			for index, node in order do
				node.i = index
			end
			table.sort(order, function(a, b)
				if a.z ~= b.z then
					return a.z < b.z
				end
				return a.i < b.i
			end)
		end
		for _, node in order do
			node.z, node.i = nil, nil
			table.insert(state.nodes, node)
		end
	end
	table.clear(pixelCache)

	local scale = arguments.scale or math.min(1, DEFAULT_MAX_SIDE / math.max(size.X, size.Y))
	local note = if state.skipped > 0 then `, stopped after {MAX_NODES} elements` else ""
	return {
		content = {
			{
				type = "text",
				text = `{state.count} element(s) under {root:GetFullName()}, {size.X}x{size.Y} at {string.format("%.2f", scale)}x{note}`,
			},
		},
		postProcess = {
			kind = "ui",
			name = arguments.name,
			width = size.X,
			height = size.Y,
			scale = scale,
			nodes = state.nodes,
		},
	}
end

return Tool
