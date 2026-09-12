--!strict

local Path = require(script.Parent.Parent.Path)

local DEFAULT_DEPTH = 3
local DEFAULT_MAX_NODES = 300
local HARD_MAX_NODES = 2000

type Result = {
	content: { { type: "text", text: string } },
	isError: boolean?,
}

local Tool = {}

Tool.Definition = {
	name = "get_tree",
	description = "Lists what's under an instance, as an indented tree of name and class. Takes "
		.. "a root so you can look at one model instead of the whole place; the default depth is "
		.. "shallow on purpose. Use the className filter to answer 'where are the Motor6Ds' "
		.. "without reading everything in between.",
	inputSchema = {
		type = "object",
		properties = {
			root = {
				type = "string",
				description = 'Dotted path to start from, like "Workspace.Rig". Defaults to game.',
			},
			depth = {
				type = "integer",
				description = "How many levels below the root to show. Defaults to 3.",
				minimum = 1,
				maximum = 20,
			},
			className = {
				type = "string",
				description = "Only list instances that IsA this class. Their ancestors are still "
					.. "shown so the paths make sense.",
			},
			maxNodes = {
				type = "integer",
				description = "Stop after this many instances. Defaults to 300.",
				minimum = 1,
				maximum = HARD_MAX_NODES,
			},
		},
	},
	tags = { title = "Get Tree", readOnly = true, idempotent = true },
}

type Walk = {
	lines: { string },
	className: string?,
	maxNodes: number,
	depth: number,
	visited: number,
	skipped: number,
}

-- Returns whether anything at or below `instance` matched, so a filtered walk can drop branches
-- that contain nothing interesting instead of printing the whole skeleton.
local function walk(state: Walk, instance: Instance, depth: number): boolean
	if state.visited >= state.maxNodes then
		state.skipped += 1
		return false
	end
	state.visited += 1

	local matched = state.className == nil or instance:IsA(state.className :: string)
	local mark = #state.lines + 1
	table.insert(state.lines, `{string.rep("  ", depth)}{instance.Name} ({instance.ClassName})`)

	if depth < state.depth then
		for _, child in instance:GetChildren() do
			matched = walk(state, child, depth + 1) or matched
		end
	end

	if not matched then
		table.remove(state.lines, mark)
	end
	return matched
end

function Tool.Run(arguments: { root: string?, depth: number?, className: string?, maxNodes: number? }): Result
	local rootPath = arguments.root
	local root: Instance = game
	if type(rootPath) == "string" and rootPath ~= "" then
		local found, problem = Path.Resolve(rootPath)
		if not found then
			return { content = { { type = "text", text = problem :: string } }, isError = true }
		end
		root = found
	end

	local className = arguments.className
	if className ~= nil and type(className) ~= "string" then
		return { content = { { type = "text", text = "className must be a string" } }, isError = true }
	end

	local state: Walk = {
		lines = {},
		className = className,
		maxNodes = math.clamp(arguments.maxNodes or DEFAULT_MAX_NODES, 1, HARD_MAX_NODES),
		depth = math.clamp(arguments.depth or DEFAULT_DEPTH, 1, 20),
		visited = 0,
		skipped = 0,
	}

	walk(state, root, 0)

	if #state.lines == 0 then
		-- IsA returns false for a misspelled class rather than erroring, so an empty result and a
		-- typo are the same thing from here. Saying both beats guessing which one it was.
		local why = if className
			then `nothing under {root:GetFullName()} is a {className} -- check the spelling if you expected hits`
			else `{root:GetFullName()} is empty`
		return { content = { { type = "text", text = why } } }
	end

	if state.skipped > 0 then
		table.insert(state.lines, `-- stopped at {state.maxNodes} instances; raise maxNodes or narrow the root`)
	end

	return { content = { { type = "text", text = table.concat(state.lines, "\n") } } }
end

return Tool
