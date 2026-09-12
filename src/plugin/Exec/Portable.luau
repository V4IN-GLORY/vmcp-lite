--!strict

-- Turns arbitrary Luau values into something that survives a trip through JSON, and back again.
--
-- This exists because the interesting values in VMCP are captured in one DataModel and used in
-- another: the server sees what a client really sent to a remote, and the client is where you
-- replay it. Serialize.Render is for reading; this is for round-tripping.
--
-- Instances cross as their path and are resolved again on the far side, so a captured argument
-- naming the local player's character comes back as *that* DataModel's copy of it.

local Path = require(script.Parent.Parent.Path)

local Portable = {}

local MAX_DEPTH = 4
local MAX_ELEMENTS = 40
local MAX_STRING = 2000

-- A hole in an array can't be expressed in JSON, and remote arguments are full of them.
local NIL = { __t = "nil" }

local function capture(value: any, depth: number): any
	local kind = typeof(value)
	if kind == "nil" then
		return NIL
	end
	if kind == "boolean" or kind == "number" then
		return value
	end
	if kind == "string" then
		return if #value > MAX_STRING then string.sub(value, 1, MAX_STRING) else value
	end
	if kind == "Instance" then
		return { __t = "Instance", path = value:GetFullName(), class = value.ClassName }
	end
	if kind == "Vector3" then
		return { __t = "Vector3", x = value.X, y = value.Y, z = value.Z }
	end
	if kind == "Vector2" then
		return { __t = "Vector2", x = value.X, y = value.Y }
	end
	if kind == "CFrame" then
		return { __t = "CFrame", components = { value:GetComponents() } }
	end
	if kind == "Color3" then
		return { __t = "Color3", r = value.R, g = value.G, b = value.B }
	end
	if kind == "UDim2" then
		return { __t = "UDim2", xs = value.X.Scale, xo = value.X.Offset, ys = value.Y.Scale, yo = value.Y.Offset }
	end
	if kind == "EnumItem" then
		return { __t = "EnumItem", enum = tostring(value.EnumType), name = value.Name }
	end
	if kind ~= "table" then
		return { __t = "opaque", kind = kind, text = tostring(value) }
	end

	if depth >= MAX_DEPTH then
		return { __t = "opaque", kind = "table", text = "too deep" }
	end

	local out: { [any]: any } = {}
	local count = 0
	for key, item in value do
		count += 1
		if count > MAX_ELEMENTS then
			break
		end
		local name = if type(key) == "string" or type(key) == "number" then key else tostring(key)
		out[name] = capture(item, depth + 1)
	end
	return out
end

local RESTORERS: { [string]: (any) -> any } = {
	["nil"] = function(): any
		return nil
	end,
	Instance = function(entry): any
		local found = Path.Resolve(entry.path)
		return found
	end,
	Vector3 = function(entry): any
		return Vector3.new(entry.x, entry.y, entry.z)
	end,
	Vector2 = function(entry): any
		return Vector2.new(entry.x, entry.y)
	end,
	CFrame = function(entry): any
		return CFrame.new(table.unpack(entry.components))
	end,
	Color3 = function(entry): any
		return Color3.new(entry.r, entry.g, entry.b)
	end,
	UDim2 = function(entry): any
		return UDim2.new(entry.xs, entry.xo, entry.ys, entry.yo)
	end,
	EnumItem = function(entry): any
		local enum = (Enum :: any)[entry.enum]
		return if enum then enum[entry.name] else nil
	end,
	opaque = function(): any
		return nil
	end,
}

local function restore(entry: any): any
	if type(entry) ~= "table" then
		return entry
	end

	local tag = entry.__t
	if type(tag) == "string" then
		local restorer = RESTORERS[tag]
		return if restorer then restorer(entry) else nil
	end

	local out: { [any]: any } = {}
	for key, item in entry do
		out[key] = restore(item)
	end
	return out
end

-- A packed argument list (table.pack, so `n` is the real length holes and all) in, a JSON-safe
-- array out. The length is kept separately for the same reason table.pack keeps it.
function Portable.CaptureArgs(packed: { any }): { any }
	local out = {}
	for index = 1, (packed :: any).n or #packed do
		out[index] = capture(packed[index], 0)
	end
	out.n = (packed :: any).n or #packed
	return out
end

function Portable.RestoreArgs(captured: { any }): ({ any }, number)
	local out = {}
	local count = (captured :: any).n or #captured
	for index = 1, count do
		out[index] = restore(captured[index])
	end
	return out, count
end

Portable.Capture = function(value: any): any
	return capture(value, 0)
end

Portable.Restore = restore

-- What an argument *is*, in one word, for a report. Reads off the captured form so it works on
-- arguments that came from another DataModel.
function Portable.Describe(entry: any): string
	if type(entry) ~= "table" then
		return typeof(entry)
	end
	local tag = entry.__t
	if type(tag) == "string" then
		if tag == "Instance" then
			return `{entry.class} {entry.path}`
		end
		return tag
	end
	return "table"
end

return Portable
