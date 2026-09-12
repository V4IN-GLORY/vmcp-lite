--!strict

-- Turns a region of the DataModel into Luau that rebuilds it, and back again.
--
-- The reason is cost, not elegance. Reading a build as a tree dump tells you what's there but
-- nothing you can change; reading it as code means an edit is a diff on a few lines instead of a
-- description of every part in the area. One region comes back as code, the change happens in the
-- code, the code goes back.
--
-- The generated source is idempotent on purpose: it looks for a child by name before creating one,
-- so running it twice updates rather than duplicating, and running an edited version only moves
-- what actually changed. That's what makes "re-apply" safe without a differ.

local CollectionService = game:GetService("CollectionService")

local Build = {}

-- Properties worth capturing, by the class that owns them. An instance takes every entry it IsA,
-- so a MeshPart picks up the BasePart set and its own. There's no way to enumerate an instance's
-- properties from Luau, so this is a curated list and knows nothing about anything not on it.
local PROPERTIES: { { class: string, names: { string } } } = {
	{
		class = "BasePart",
		names = {
			"Size",
			"CFrame",
			"Anchored",
			"CanCollide",
			"CanTouch",
			"CanQuery",
			"Color",
			"Material",
			"Transparency",
			"Reflectance",
			"CastShadow",
			"CollisionGroup",
		},
	},
	{ class = "MeshPart", names = { "MeshId", "TextureID", "DoubleSided" } },
	{ class = "SpecialMesh", names = { "MeshId", "TextureId", "Scale", "Offset", "MeshType" } },
	{ class = "Decal", names = { "Texture", "Face", "Color3", "Transparency", "ZIndex" } },
	{ class = "Texture", names = { "StudsPerTileU", "StudsPerTileV" } },
	{ class = "Attachment", names = { "CFrame", "Visible" } },
	{ class = "Light", names = { "Brightness", "Color", "Enabled", "Shadows" } },
	{ class = "PointLight", names = { "Range" } },
	{ class = "SpotLight", names = { "Range", "Angle", "Face" } },
	{ class = "SurfaceLight", names = { "Range", "Angle", "Face" } },
	{
		class = "ParticleEmitter",
		names = { "Rate", "Lifetime", "Speed", "Texture", "Color", "Enabled", "SpreadAngle" },
	},
	{ class = "Beam", names = { "Texture", "Width0", "Width1", "Color", "Enabled" } },
	{ class = "SurfaceAppearance", names = { "ColorMap", "NormalMap", "MetalnessMap", "RoughnessMap" } },
	{
		class = "GuiObject",
		names = {
			"Size",
			"Position",
			"AnchorPoint",
			"BackgroundColor3",
			"BackgroundTransparency",
			"BorderSizePixel",
			"ZIndex",
			"Visible",
		},
	},
	{ class = "TextLabel", names = { "Text", "TextColor3", "TextSize", "Font", "TextWrapped", "TextXAlignment" } },
	{ class = "ImageLabel", names = { "Image", "ImageColor3", "ImageTransparency", "ScaleType" } },
	{ class = "UICorner", names = { "CornerRadius" } },
	{ class = "UIStroke", names = { "Thickness", "Color", "Transparency", "ApplyStrokeMode" } },
	{
		class = "UIListLayout",
		names = { "Padding", "FillDirection", "SortOrder", "HorizontalAlignment", "VerticalAlignment" },
	},
}

local MAX_DEPTH = 12
local MAX_NODES = 800

local function num(value: number): string
	if value ~= value then
		return "0 / 0"
	end
	if value == math.huge or value == -math.huge then
		return if value > 0 then "math.huge" else "-math.huge"
	end
	if value % 1 == 0 and math.abs(value) < 1e15 then
		return string.format("%d", value)
	end
	return string.format("%.4g", value)
end

-- Every value that can appear in the generated source, written the way you'd type it. Anything
-- not here is skipped rather than guessed at, which is why the property list above is curated.
local function literal(value: any): string?
	local kind = typeof(value)
	if kind == "string" then
		return string.format("%q", value)
	end
	if kind == "number" then
		return num(value)
	end
	if kind == "boolean" then
		return tostring(value)
	end
	if kind == "Vector3" then
		return `Vector3.new({num(value.X)}, {num(value.Y)}, {num(value.Z)})`
	end
	if kind == "Vector2" then
		return `Vector2.new({num(value.X)}, {num(value.Y)})`
	end
	if kind == "Color3" then
		return `Color3.new({num(value.R)}, {num(value.G)}, {num(value.B)})`
	end
	if kind == "UDim" then
		return `UDim.new({num(value.Scale)}, {num(value.Offset)})`
	end
	if kind == "UDim2" then
		return `UDim2.new({num(value.X.Scale)}, {num(value.X.Offset)}, {num(value.Y.Scale)}, {num(value.Y.Offset)})`
	end
	if kind == "NumberRange" then
		return `NumberRange.new({num(value.Min)}, {num(value.Max)})`
	end
	if kind == "EnumItem" then
		return tostring(value)
	end
	if kind == "BrickColor" then
		return `BrickColor.new("{value.Name}")`
	end
	if kind == "CFrame" then
		local position = value.Position
		local rx, ry, rz = value:ToEulerAnglesXYZ()
		local origin = `CFrame.new({num(position.X)}, {num(position.Y)}, {num(position.Z)})`
		if rx == 0 and ry == 0 and rz == 0 then
			return origin
		end
		return `{origin} * CFrame.Angles({num(rx)}, {num(ry)}, {num(rz)})`
	end
	return nil
end

local function propertiesFor(instance: Instance): { string }
	local names: { string } = {}
	for _, entry in PROPERTIES do
		if not instance:IsA(entry.class) then
			continue
		end
		for _, name in entry.names do
			if not table.find(names, name) then
				table.insert(names, name)
			end
		end
	end
	return names
end

-- Only what differs from a fresh instance of the same class. A part dump that spells out every
-- default is mostly noise, and noise is the thing this module exists to remove.
local function defaults(className: string): Instance?
	local ok, fresh = pcall(Instance.new, className)
	return if ok then fresh else nil
end

local HEADER = [[
-- Generated by VMCP. Edit freely and run it again: `ensure` updates what's already there rather
-- than making a second copy, so only what you changed moves.

local function ensure(parent, name, class)
	local found = parent:FindFirstChild(name)
	if found and found.ClassName ~= class then
		found:Destroy()
		found = nil
	end
	if not found then
		found = Instance.new(class)
		found.Name = name
		found.Parent = parent
	end
	return found
end

return function(root)
]]

export type Options = {
	depth: number?,
	maxNodes: number?,
	-- Include attributes and CollectionService tags. On by default; they're usually the part that
	-- actually drives behaviour.
	tags: boolean?,
}

-- Returns the source, plus how many instances it covered.
function Build.Dump(root: Instance, options: Options?): (string, number)
	local settings = options or ({} :: Options)
	local depthLimit = math.clamp(settings.depth or MAX_DEPTH, 1, MAX_DEPTH)
	local nodeLimit = math.clamp(settings.maxNodes or MAX_NODES, 1, MAX_NODES)
	local wantTags = settings.tags ~= false

	local lines = { HEADER }
	local count = 0
	local truncated = false

	local function emit(instance: Instance, parentVar: string, depth: number)
		if count >= nodeLimit then
			truncated = true
			return
		end
		count += 1
		local variable = `n{count}`

		table.insert(
			lines,
			`\tlocal {variable} = ensure({parentVar}, {string.format("%q", instance.Name)}, {string.format(
				"%q",
				instance.ClassName
			)})`
		)

		local fresh = defaults(instance.ClassName)
		for _, name in propertiesFor(instance) do
			local ok, value = pcall(function()
				return (instance :: any)[name]
			end)
			if not ok then
				continue
			end
			if fresh then
				local sameOk, same = pcall(function()
					return (fresh :: any)[name] == value
				end)
				if sameOk and same then
					continue
				end
			end
			local written = literal(value)
			if written then
				table.insert(lines, `\t{variable}.{name} = {written}`)
			end
		end

		if wantTags then
			for name, value in instance:GetAttributes() do
				local written = literal(value)
				if written then
					table.insert(lines, `\t{variable}:SetAttribute({string.format("%q", name)}, {written})`)
				end
			end
			for _, tag in CollectionService:GetTags(instance) do
				table.insert(
					lines,
					`\tgame:GetService("CollectionService"):AddTag({variable}, {string.format("%q", tag)})`
				)
			end
		end

		if fresh then
			fresh:Destroy()
		end
		if depth >= depthLimit then
			return
		end
		for _, child in instance:GetChildren() do
			emit(child, variable, depth + 1)
		end
	end

	for _, child in root:GetChildren() do
		emit(child, "root", 1)
	end

	if truncated then
		table.insert(lines, `\t-- stopped at {nodeLimit} instances; narrow the root or raise maxNodes`)
	end
	table.insert(lines, "\treturn root")
	table.insert(lines, "end")
	return table.concat(lines, "\n"), count
end

-- Runs a dump against a root. The source returns a function taking the root, so applying it
-- somewhere else is how you copy a region -- same code, different parent.
function Build.Apply(source: string, root: Instance): (boolean, string?)
	local Inject = require(script.Parent.Parent.Exec.Inject)
	local chunk, problem = Inject.Compile(source, "")
	if not chunk then
		return false, problem
	end

	local ok, produced = pcall(chunk)
	if not ok then
		return false, tostring(produced)
	end
	if type(produced) ~= "function" then
		return false, "that source didn't return a function -- a Build dump ends with `return function(root)`"
	end

	local ran, failure = pcall(produced, root)
	return ran, if ran then nil else tostring(failure)
end

return Build
