--!strict

-- One pass of the build loop in one call: run the code, measure what it made, say what's wrong,
-- draw it. The code is the thing being iterated on -- it's the only description of the build that
-- holds every part at once -- so everything this returns is meant to be read next to the source
-- and turned into an edit to it.

local Build = require(script.Parent.Parent.Lib.Build)
local Path = require(script.Parent.Parent.Path)

local BADGE_LIMIT = 40
local MAX_PARTS = 1500

type Result = {
	content: { { type: "text", text: string } },
	isError: boolean?,
	postProcess: { [string]: any }?,
}

local Tool = {}

Tool.Definition = {
	name = "apply_build",
	description = "Runs build code against a root, then checks the geometry and draws it -- one "
		.. "call per pass of the write, check, fix loop. The code is the `return function(root)` "
		.. "shape get_build produces, and it should hold the whole build: a build lives in its "
		.. "source, not in a picture, so keep the full source and edit it between passes rather "
		.. "than placing parts one call at a time. What comes back is numbers first -- bounds, "
		.. "the extent of each top-level group, and a problem list with the depth and axis of "
		.. "every overlap, gaps under floating parts, near-square rotations, duplicates and "
		.. "strays -- then a legend and one blockout picture. Fix from the numbers; use the "
		.. "picture for proportions and whether the layout reads.",
	inputSchema = {
		type = "object",
		properties = {
			code = {
				type = "string",
				description = "Luau source ending in `return function(root) ... end`. `ensure(parent, "
					.. "name, class)` inside it updates by name, so re-applying moves only what changed.",
			},
			file = {
				type = "string",
				description = "Path to a file holding the source, read by the VMCP server on the machine "
					.. "it runs on; absolute or relative to the server's working directory. Use this "
					.. "instead of code once the build lives in a file: edit the file, apply by path, "
					.. "and the source never has to be re-sent.",
			},
			root = {
				type = "string",
				description = 'Dotted path, like "Workspace.Arena". If the last segment is missing a '
					.. "Model with that name is made under its parent. Defaults to Workspace.",
			},
			clear = {
				type = "boolean",
				description = "Destroy everything under the root before applying, so renamed or "
					.. "removed parts don't linger. Off by default.",
			},
			views = {
				type = "array",
				description = "Angles to draw, tiled into one image. Defaults to iso. Named: iso, "
					.. "corner, front, back, left, right, top, bottom; or { yaw, pitch, name } in degrees. "
					.. "Add at ({x, y, z} or a dotted path to a part or model) and radius (studs) to "
					.. "centre and scale a panel on one spot; clip = true hides parts further than "
					.. "radius from it.",
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
				description = "Image file name, letters digits underscore hyphen. Defaults to a timestamp.",
			},
			render = {
				type = "boolean",
				description = "Draw the picture. On by default; off saves the image when only the "
					.. "numbers are needed.",
			},
			badges = {
				type = "boolean",
				description = `Number each part in the picture and list it in the legend. On by default when the panels show up to {BADGE_LIMIT} parts (clipped panels count only what's in frame).`,
			},
		},
		-- One of code or file; the server turns file into code before it gets here.
		required = {},
	},
	tags = { title = "Apply Build", destructive = true },
	timeoutMs = 60000,
}

local function resolveOrCreate(path: string): (Instance?, string?)
	local found, problem = Path.Resolve(path)
	if found then
		return found, nil
	end
	local parentPath, name = string.match(path, "^(.*)%.([^%.]+)$")
	if not parentPath then
		return nil, problem
	end
	local parent = Path.Resolve(parentPath :: string)
	if not parent then
		return nil, problem
	end
	local model = Instance.new("Model")
	model.Name = name :: string
	model.Parent = parent
	return model, nil
end

function Tool.Run(arguments: {
	code: string?,
	root: string?,
	clear: boolean?,
	views: { any }?,
	size: number?,
	name: string?,
	render: boolean?,
	badges: boolean?,
}): Result
	local code = arguments.code
	if type(code) ~= "string" or code == "" then
		return { content = { { type = "text", text = "pass code or file" } }, isError = true }
	end

	local root: Instance = workspace
	if type(arguments.root) == "string" and arguments.root ~= "" then
		local found, problem = resolveOrCreate(arguments.root :: string)
		if not found then
			return { content = { { type = "text", text = problem :: string } }, isError = true }
		end
		root = found
	end

	if arguments.clear then
		root:ClearAllChildren()
	end

	local ok, failure = Build.Apply(code, root)
	local parts, instances, capped = Build.Geometry(root, MAX_PARTS)
	local count = #instances

	local lines = {}
	if ok then
		table.insert(
			lines,
			`applied: {#root:GetDescendants()} instance(s) under {root:GetFullName()}, {count} of them parts`
		)
	else
		-- The failure line comes first and the report still follows: whatever ran before the
		-- error is in the place now, and knowing what that looks like is how you fix the code.
		table.insert(lines, `error: {failure}`)
		table.insert(lines, `{count} part(s) under {root:GetFullName()} after the partial run`)
	end
	if capped then
		table.insert(lines, `stopped measuring at {count} parts -- there are more`)
	end

	if count == 0 then
		table.insert(lines, "no parts to check or draw")
		return { content = { { type = "text", text = table.concat(lines, "\n") } }, isError = not ok }
	end

	local render = arguments.render ~= false
	local views, missing = Build.ResolveViews(arguments.views or { "iso" })
	local shown = Build.Shown(instances, views)
	local shownCount = 0
	for _ in shown do
		shownCount += 1
	end
	local badges = if arguments.badges ~= nil then arguments.badges else shownCount <= BADGE_LIMIT
	table.insert(
		lines,
		Build.Report(
			root,
			instances,
			if badges and render then shown else nil,
			Build.Problems(root, MAX_PARTS, instances)
		)
	)
	for _, problem in missing do
		table.insert(lines, `view target not found, drawing the whole build instead: {problem}`)
	end

	return {
		content = { { type = "text", text = table.concat(lines, "\n") } },
		isError = not ok,
		postProcess = if render
			then {
				kind = "scene",
				name = arguments.name,
				size = arguments.size,
				views = views,
				badges = badges,
				parts = parts,
			}
			else nil,
	}
end

return Tool
