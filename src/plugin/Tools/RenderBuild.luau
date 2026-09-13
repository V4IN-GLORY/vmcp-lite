--!strict

local Build = require(script.Parent.Parent.Lib.Build)
local Path = require(script.Parent.Parent.Path)

local MAX_PARTS = 1500

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
		.. "playtest and no screenshot. Orthographic blockout: flat shading, an outline on every "
		.. "part, all views at one scale so sizes stay comparable. Pair it with get_build -- read "
		.. "the region as code, edit it, run it back, render, look, edit again.",
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

function Tool.Run(arguments: {
	root: string?,
	views: { any }?,
	size: number?,
	name: string?,
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

	local parts, count, capped = Build.Geometry(root, arguments.maxParts)
	if count == 0 then
		return {
			content = {
				{ type = "text", text = `{root:GetFullName()} has no parts in it, so there's nothing to draw` },
			},
			isError = true,
		}
	end

	local views = arguments.views or { "iso" }
	local note = if capped then ` (stopped at {count}, there are more)` else ""

	return {
		content = {
			{ type = "text", text = `{count} part(s) under {root:GetFullName()}, {#views} view(s){note}` },
		},
		postProcess = {
			kind = "scene",
			name = arguments.name,
			size = arguments.size,
			views = views,
			parts = parts,
		},
	}
end

return Tool
