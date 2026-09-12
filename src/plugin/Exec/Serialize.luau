--!strict
--!optimize 2

-- Renders an arbitrary Luau value as readable text, so a snippet can `return` anything and the
-- other end sees it instead of "table: 0x55f1c0". Roblox datatypes come back as the constructor
-- you would type to rebuild them; Instances as their class and full path.
--
-- The caps are the point as much as the formatting: `return workspace` should cost a few lines,
-- not the whole place over the socket.

local MAX_DEPTH = 5
local MAX_ELEMENTS = 60
local MAX_STRING = 400
local INDENT = "  "

local Serialize = {}

local function num(value: number): string
	if value % 1 == 0 and math.abs(value) < 1e15 then
		return string.format("%d", value)
	end
	return string.format("%.4g", value)
end

local function quote(text: string): string
	local clipped = text
	if #text > MAX_STRING then
		clipped = `{string.sub(text, 1, MAX_STRING)}... (+{#text - MAX_STRING} more)`
	end
	-- %q escapes a newline as backslash-newline, which is valid Luau but wraps the output.
	return (string.format("%q", clipped):gsub("\\n", "\n"))
end

local RENDERERS: { [string]: (any) -> string } = {
	Vector3 = function(v): string
		return `Vector3.new({num(v.X)}, {num(v.Y)}, {num(v.Z)})`
	end,
	Vector2 = function(v): string
		return `Vector2.new({num(v.X)}, {num(v.Y)})`
	end,
	Color3 = function(c): string
		return `Color3.new({num(c.R)}, {num(c.G)}, {num(c.B)})`
	end,
	UDim = function(u): string
		return `UDim.new({num(u.Scale)}, {num(u.Offset)})`
	end,
	UDim2 = function(u): string
		return `UDim2.new({num(u.X.Scale)}, {num(u.X.Offset)}, {num(u.Y.Scale)}, {num(u.Y.Offset)})`
	end,
	Rect = function(r): string
		return `Rect.new({num(r.Min.X)}, {num(r.Min.Y)}, {num(r.Max.X)}, {num(r.Max.Y)})`
	end,
	NumberRange = function(r): string
		return `NumberRange.new({num(r.Min)}, {num(r.Max)})`
	end,
	BrickColor = function(b): string
		return `BrickColor.new("{b.Name}")`
	end,
	CFrame = function(c): string
		local position = c.Position
		local rx, ry, rz = c:ToEulerAnglesXYZ()
		local origin = `CFrame.new({num(position.X)}, {num(position.Y)}, {num(position.Z)})`
		if rx == 0 and ry == 0 and rz == 0 then
			return origin
		end
		return `{origin} * CFrame.Angles({num(rx)}, {num(ry)}, {num(rz)})`
	end,
	Instance = function(instance): string
		return `<{instance.ClassName} {instance:GetFullName()}>`
	end,
	EnumItem = function(item): string
		return tostring(item)
	end,
	Enum = function(enum): string
		return `Enum.{tostring(enum)}`
	end,
	buffer = function(b): string
		return `<buffer, {buffer.len(b)} bytes>`
	end,
}

local function isIdentifier(key: any): boolean
	return type(key) == "string" and string.match(key, "^[%a_][%w_]*$") ~= nil
end

local function render(value: any, depth: number, open: { [any]: boolean }): string
	local kind = typeof(value)
	if kind == "string" then
		return quote(value)
	end
	if kind == "number" then
		return num(value)
	end
	if kind == "boolean" or kind == "nil" then
		return tostring(value)
	end
	if kind ~= "table" then
		local renderer = RENDERERS[kind]
		return if renderer then renderer(value) else `<{kind} {tostring(value)}>`
	end

	-- `open` holds the tables on the path to here, not every table already seen -- the same table
	-- twice in a list is fine to print twice, only a loop is a problem.
	if open[value] then
		return "<cycle>"
	end
	if depth >= MAX_DEPTH then
		return "<table, too deep>"
	end
	open[value] = true

	local lines = {}
	local pad = string.rep(INDENT, depth + 1)
	local arrayLength = #value
	local truncated = false

	for index = 1, arrayLength do
		if #lines >= MAX_ELEMENTS then
			truncated = true
			break
		end
		table.insert(lines, `{pad}{render(value[index], depth + 1, open)},`)
	end
	for key, item in value do
		if type(key) == "number" and key % 1 == 0 and key >= 1 and key <= arrayLength then
			continue
		end
		if #lines >= MAX_ELEMENTS then
			truncated = true
			break
		end
		local name = if isIdentifier(key) then key else `[{render(key, depth + 1, open)}]`
		table.insert(lines, `{pad}{name} = {render(item, depth + 1, open)},`)
	end
	open[value] = nil

	if #lines == 0 then
		return "{}"
	end
	if truncated then
		table.insert(lines, `{pad}-- more entries not shown`)
	end
	return "{\n" .. table.concat(lines, "\n") .. "\n" .. string.rep(INDENT, depth) .. "}"
end

function Serialize.Render(value: any): string
	return render(value, 0, {})
end

return Serialize
