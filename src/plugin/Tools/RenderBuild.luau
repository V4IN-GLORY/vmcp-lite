--!strict

local Build = require(script.Parent.Parent.Lib.Build)
local Path = require(script.Parent.Parent.Path)

local MAX_PARTS = 1500
-- Past this many parts the badges stop being readable and start being a grey fog, so they go off
-- unless asked for by name.
local BADGE_LIMIT = 40

type Result = {
	content: { { type: "text", text: string } },
	isError: boolean?,
	postProcess: { [string]: any }?,
}

local Tool = {}

Tool.Definition = {
	name = "render_build",
	description = "Draws a region of the place as a picture and writes it to a PNG, so you can "
		.. "look at what your build code actually made instead of reading it back and guessing. "
		.. "Studio sends the geometry; the VMCP server renders it, so this needs no camera, no "
		.. "playtest and no screenshot. Each part gets a number in the picture and a line in the "
		.. "legend naming it, so something you can see is something you can grep for in the "
		.. "get_build source. Also reports what's wrong in code rather than by eye: parts sunk "
		.. "into each other, floating, rotated a fraction off square, built twice, or stranded "
		.. "miles from everything else.",
	inputSchema = {
		type = "object",
		properties = {
			root = {
				type = "string",
				description = 'Dotted path to the region, like "Workspace.Arena". Defaults to Workspace.',
			},
			views = {
				type = "array",
				description = "Which angles to draw, tiled into one image. Defaults to iso alone. "
					.. "Named: iso, corner, front, back, left, right, top, bottom. Or an object "
					.. "{ yaw, pitch, name } in degrees for anything else.",
				items = { type = { "string", "object" } },
				maxItems = 9,
			},
			size = {
				type = "integer",
				description = "Pixels per view. Defaults to 512.",
				minimum = 128,
				maximum = 1024,
			},
			name = {
				type = "string",
				description = "File name, letters digits underscore hyphen. Defaults to a timestamp.",
			},
			badges = {
				type = "boolean",
				description = `Number each part in the picture. On by default up to {BADGE_LIMIT} parts.`,
			},
			problems = {
				type = "boolean",
				description = "Check the geometry and report what looks wrong. On by default.",
			},
			maxParts = {
				type = "integer",
				description = `Stop collecting after this many parts. Defaults to {MAX_PARTS}.`,
				minimum = 1,
				maximum = MAX_PARTS,
			},
		},
	},
	tags = { title = "Render Build", readOnly = true },
	timeoutMs = 60000,
}

local function shorten(part: Instance, root: Instance): string
	local full = part:GetFullName()
	local prefix = `{root:GetFullName()}.`
	if string.sub(full, 1, #prefix) == prefix then
		return string.sub(full, #prefix + 1)
	end
	return full
end

local function round(value: number): string
	return string.format(if value % 1 == 0 then "%d" else "%.1f", value)
end

function Tool.Run(arguments: {
	root: string?,
	views: { any }?,
	size: number?,
	name: string?,
	badges: boolean?,
	problems: boolean?,
	maxParts: number?,
}): Result
	local root: Instance = workspace
	if type(arguments.root) == "string" and arguments.root ~= "" then
		local found, problem = Path.Resolve(arguments.root :: string)
		if not found then
			return { content = { { type = "text", text = problem :: string } }, isError = true }
		end
		root = found
	end

	local parts, instances, capped = Build.Geometry(root, arguments.maxParts)
	local count = #instances
	if count == 0 then
		return {
			content = {
				{ type = "text", text = `{root:GetFullName()} has no parts in it, so there's nothing to draw` },
			},
			isError = true,
		}
	end

	local views = arguments.views or { "iso" }
	local badges = if arguments.badges ~= nil then arguments.badges else count <= BADGE_LIMIT
	local note = if capped then `, stopped at {count} -- there are more` else ""

	local lines = { `{count} part(s) under {root:GetFullName()}, {#views} view(s){note}`, "" }

	table.insert(lines, if badges then "legend (the number in the picture):" else "parts:")
	for index, part in instances do
		local size = part.Size
		local at = part.Position
		table.insert(
			lines,
			`  #{index} {shorten(part, root)}  {round(size.X)}x{round(size.Y)}x{round(size.Z)}`
				.. ` at ({round(at.X)}, {round(at.Y)}, {round(at.Z)})`
		)
	end

	if arguments.problems ~= false then
		local found = Build.Problems(root, arguments.maxParts, instances)
		table.insert(lines, "")
		if #found == 0 then
			table.insert(lines, "nothing looks wrong with the geometry")
		else
			table.insert(lines, `{#found} thing(s) worth a look:`)
			for _, problem in found do
				table.insert(lines, `  {shorten(problem.part, root)} -- {problem.kind}: {problem.detail}`)
			end
		end
	end

	return {
		content = { { type = "text", text = table.concat(lines, "\n") } },
		postProcess = {
			kind = "scene",
			name = arguments.name,
			size = arguments.size,
			views = views,
			badges = badges,
			parts = parts,
		},
	}
end

return Tool
