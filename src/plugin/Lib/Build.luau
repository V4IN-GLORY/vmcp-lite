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

-- Every part in a region as plain numbers, for the VMCP server to draw.
--
-- Studio can't hand out a picture -- a viewport screenshot needs a real camera, a real frame and a
-- place saved somewhere -- but it can hand out the geometry, and the geometry is tiny. What comes
-- back is roughly forty bytes per part, and the server renders it into something you can look at.
--
-- Shape names here are the four the renderer knows. Everything with a mesh or a union becomes its
-- bounding box, which is right for a blockout and honest about what it is.
local SHAPES: { [Enum.PartType]: string } = {
	[Enum.PartType.Block] = "box",
	[Enum.PartType.Ball] = "ball",
	[Enum.PartType.Cylinder] = "cylinder",
	[Enum.PartType.Wedge] = "wedge",
	[Enum.PartType.CornerWedge] = "wedge",
}

local function shapeOf(part: BasePart): string
	if part:IsA("WedgePart") or part:IsA("CornerWedgePart") then
		return "wedge"
	end
	if part:IsA("Part") then
		return SHAPES[part.Shape] or "box"
	end
	return "box"
end

local function round(value: number): number
	return math.floor(value * 1000 + 0.5) / 1000
end

export type Geometry = { { [string]: any } }

local function describe(part: BasePart, index: number): { [string]: any }
	local components = { part.CFrame:GetComponents() }
	for at, value in components do
		components[at] = round(value)
	end

	local size = part.Size
	local color = part.Color
	return {
		i = index,
		n = part.Name,
		s = shapeOf(part),
		m = components,
		d = { round(size.X), round(size.Y), round(size.Z) },
		c = { round(color.R), round(color.G), round(color.B) },
		t = if part.Transparency > 0 then round(part.Transparency) else nil,
	}
end

-- The parts to draw, and the list that says which drawn part is which. The badge number in the
-- picture is this part's place in `found`, so a thing you can see has a path you can grep for.
function Build.Geometry(root: Instance, maxParts: number?): (Geometry, { BasePart }, boolean)
	local limit = maxParts or 1500
	local parts: Geometry = {}
	local found: { BasePart } = {}
	local skipped = false

	local function take(part: BasePart)
		if #parts >= limit then
			skipped = true
			return
		end
		table.insert(found, part)
		table.insert(parts, describe(part, #found))
	end

	if root:IsA("BasePart") then
		take(root)
	end
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			take(descendant)
		end
	end

	return parts, found, skipped
end

-- What's wrong with a build, in code rather than by eye.
--
-- A picture shows you a part in the wrong place; it can't tell you the rotation is 0.4 degrees off
-- true, and that's the kind of thing build code produces and nobody notices. Each of these is a
-- mistake that comes from generating geometry rather than placing it by hand.

export type Problem = { part: BasePart, kind: string, detail: string }

local NEAR_MISS_DEGREES = 5
local SUPPORTED_GAP = 0.25
local THIN = 0.1
local OUTLIER_STUDS = 250
-- Two parts sharing a face are touching, not sunk in; a build made of flush boxes would otherwise
-- report every wall against its floor.
local FLUSH = 0.05

-- World-space box around a part, rotation and all. Rotated parts get a box bigger than they are,
-- which makes the depth below an estimate -- still a number you can subtract from a position.
local function aabb(part: BasePart): (Vector3, Vector3)
	local cframe = part.CFrame
	local half = part.Size / 2
	local right, up, look = cframe.RightVector, cframe.UpVector, cframe.LookVector
	local extent = Vector3.new(
		math.abs(right.X) * half.X + math.abs(up.X) * half.Y + math.abs(look.X) * half.Z,
		math.abs(right.Y) * half.X + math.abs(up.Y) * half.Y + math.abs(look.Y) * half.Z,
		math.abs(right.Z) * half.X + math.abs(up.Z) * half.Y + math.abs(look.Z) * half.Z
	)
	return cframe.Position - extent, cframe.Position + extent
end

-- How far one box is sunk into another and along which axis the shortest way out is.
local function penetration(a: BasePart, b: BasePart): (number, string)
	local aMin, aMax = aabb(a)
	local bMin, bMax = aabb(b)
	local overlap = aMax:Min(bMax) - aMin:Max(bMin)
	local depth = math.min(overlap.X, overlap.Y, overlap.Z)
	local axis = if depth == overlap.X then "X" elseif depth == overlap.Y then "Y" else "Z"
	return depth, axis
end

local function degreesOffAxis(cframe: CFrame): number
	local worst = 0
	for _, direction in { cframe.RightVector, cframe.UpVector, cframe.LookVector } do
		local nearest = math.max(math.abs(direction.X), math.abs(direction.Y), math.abs(direction.Z))
		worst = math.max(worst, math.deg(math.acos(math.clamp(nearest, -1, 1))))
	end
	return worst
end

function Build.Problems(root: Instance, maxParts: number?, known: { BasePart }?): { Problem }
	local parts: { BasePart } = known or ({} :: { BasePart })
	if not known then
		local _, walked = Build.Geometry(root, maxParts)
		parts = walked
	end
	local problems: { Problem } = {}

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = (parts :: any) :: { Instance }
	overlap.MaxParts = 4

	local rays = RaycastParams.new()
	rays.FilterType = Enum.RaycastFilterType.Exclude

	local reportedOverlap: { [BasePart]: boolean } = {}
	local stacked: { [string]: BasePart } = {}
	local centre = Vector3.zero

	for _, part in parts do
		centre += part.Position
	end
	centre = if #parts > 0 then centre / #parts else Vector3.zero

	for _, part in parts do
		local size = part.Size

		if math.min(size.X, size.Y, size.Z) < THIN then
			table.insert(problems, {
				part = part,
				kind = "paper thin",
				detail = `{size.X} x {size.Y} x {size.Z} -- probably a size that was computed to nothing`,
			})
		end

		local tilt = degreesOffAxis(part.CFrame)
		if tilt > 0.02 and tilt < NEAR_MISS_DEGREES then
			table.insert(problems, {
				part = part,
				kind = "off axis",
				detail = `rotated {string.format("%.2f", tilt)} degrees off square -- meant to be flat?`,
			})
		end

		local key = `{part.Name}|{size}|{round(part.Position.X)},{round(part.Position.Y)},{round(part.Position.Z)}`
		local twin = stacked[key]
		if twin then
			table.insert(problems, {
				part = part,
				kind = "duplicate",
				detail = `same name, size and position as {twin:GetFullName()} -- build code run twice?`,
			})
		else
			stacked[key] = part
		end

		local touching = workspace:GetPartsInPart(part, overlap)
		local connected = false
		for _, other in touching do
			if other == part then
				continue
			end
			connected = true
			local depth, axis = penetration(part, other)
			if depth > FLUSH and not reportedOverlap[part] and not reportedOverlap[other] then
				reportedOverlap[part] = true
				table.insert(problems, {
					part = part,
					kind = "overlapping",
					detail = `sunk about {string.format("%.2f", depth)} studs into {other:GetFullName()} along {axis}`,
				})
			end
		end

		-- Only parts that touch nothing at all are worth checking for support: a wall welded to
		-- its neighbour has nothing underneath it either, and that's not a mistake.
		if not connected then
			rays.FilterDescendantsInstances = { part }
			local hit = workspace:Raycast(part.Position, Vector3.new(0, -(size.Y / 2 + 512), 0), rays)
			if not hit then
				table.insert(problems, { part = part, kind = "floating", detail = "nothing under it at all" })
			else
				local gap = hit.Distance - size.Y / 2
				if gap > SUPPORTED_GAP then
					table.insert(problems, {
						part = part,
						kind = "floating",
						detail = `{string.format("%.2f", gap)} studs above {hit.Instance:GetFullName()}`,
					})
				end
			end
		end

		local away = (part.Position - centre).Magnitude
		if away > OUTLIER_STUDS then
			table.insert(problems, {
				part = part,
				kind = "stranded",
				detail = `{math.floor(away)} studs from the middle of the build`,
			})
		end
	end

	return problems
end

-- The build as numbers: where it sits, how big each top-level group is, what's wrong, and which
-- badge is which part. This is the part of a render that survives being read -- a picture can't be
-- held in your head next to the code, a list of extents can.

local function fmt(value: number): string
	return string.format(if value % 1 == 0 then "%d" else "%.1f", value)
end

local function v3(value: Vector3): string
	return `({fmt(value.X)}, {fmt(value.Y)}, {fmt(value.Z)})`
end

local function span(min: Vector3, max: Vector3): string
	local size = max - min
	return `{fmt(size.X)}x{fmt(size.Y)}x{fmt(size.Z)} spanning x {fmt(min.X)}..{fmt(max.X)}, y {fmt(min.Y)}..{fmt(max.Y)}, z {fmt(min.Z)}..{fmt(max.Z)}`
end

local function shorten(instance: Instance, root: Instance): string
	local full = instance:GetFullName()
	local prefix = `{root:GetFullName()}.`
	if string.sub(full, 1, #prefix) == prefix then
		return string.sub(full, #prefix + 1)
	end
	return full
end

type Extent = { min: Vector3, max: Vector3, count: number }

local function grow(extent: Extent?, min: Vector3, max: Vector3): Extent
	if not extent then
		return { min = min, max = max, count = 1 }
	end
	extent.min = extent.min:Min(min)
	extent.max = extent.max:Max(max)
	extent.count += 1
	return extent
end

function Build.Report(root: Instance, parts: { BasePart }, badges: boolean, problems: { Problem }?): string
	local lines = {}

	local whole: Extent? = nil
	local groups: { [Instance]: Extent } = {}
	local order: { Instance } = {}
	for _, part in parts do
		local min, max = aabb(part)
		whole = grow(whole, min, max)
		-- The group is whichever child of the root this part lives under -- a loose part is its own.
		local top: Instance = part
		while top.Parent ~= root and top.Parent ~= nil do
			top = top.Parent :: Instance
		end
		if not groups[top] then
			table.insert(order, top)
		end
		groups[top] = grow(groups[top], min, max)
	end

	if whole then
		table.insert(lines, `bounds: {span(whole.min, whole.max)}`)
	end
	if #order > 1 then
		table.insert(lines, "groups (direct children of the root):")
		for _, top in order do
			local extent = groups[top]
			local plural = if extent.count == 1 then "part" else "parts"
			table.insert(lines, `  {top.Name}  {extent.count} {plural}, {span(extent.min, extent.max)}`)
		end
	end

	if problems then
		table.insert(lines, "")
		if #problems == 0 then
			table.insert(lines, "nothing looks wrong with the geometry")
		else
			table.insert(lines, `{#problems} thing(s) worth a look:`)
			for _, problem in problems do
				table.insert(lines, `  {shorten(problem.part, root)} -- {problem.kind}: {problem.detail}`)
			end
		end
	end

	table.insert(lines, "")
	table.insert(lines, if badges then "legend (the number in the picture):" else "parts:")
	for index, part in parts do
		local size = part.Size
		table.insert(lines, `  #{index} {shorten(part, root)}  {fmt(size.X)}x{fmt(size.Y)}x{fmt(size.Z)} at {v3(part.Position)}`)
	end

	return table.concat(lines, "\n")
end

return Build
