--!strict

local Build = require(script.Parent.Parent.Lib.Build)
local Path = require(script.Parent.Parent.Path)

type Result = {
	content: { { type: "text", text: string } },
	isError: boolean?,
}

local Tool = {}

Tool.Definition = {
	name = "get_build",
	description = "Returns a region of the place as Luau that rebuilds it -- one line per property "
		.. "that differs from the class default, plus attributes and tags. Use it instead of "
		.. "get_tree when you intend to change something: a tree dump tells you what's there, this "
		.. "gives you something you can edit and run back. The generated code updates what's "
		.. "already there rather than duplicating it, so applying an edited version only moves "
		.. "what actually changed. Run it back with run_luau.",
	inputSchema = {
		type = "object",
		properties = {
			root = {
				type = "string",
				description = 'Dotted path to the region, like "Workspace.Arena". Defaults to Workspace.',
			},
			depth = {
				type = "integer",
				description = "How many levels below the root to include. Defaults to 12.",
				minimum = 1,
				maximum = 12,
			},
			maxNodes = {
				type = "integer",
				description = "Stop after this many instances. Defaults to 800.",
				minimum = 1,
				maximum = 800,
			},
			tags = {
				type = "boolean",
				description = "Include attributes and CollectionService tags. On by default.",
			},
		},
	},
	tags = { title = "Get Build", readOnly = true, idempotent = true },
}

function Tool.Run(arguments: { root: string?, depth: number?, maxNodes: number?, tags: boolean? }): Result
	local root: Instance = workspace
	if type(arguments.root) == "string" and arguments.root ~= "" then
		local found, problem = Path.Resolve(arguments.root :: string)
		if not found then
			return { content = { { type = "text", text = problem :: string } }, isError = true }
		end
		root = found
	end

	local source, count = Build.Dump(root, {
		depth = arguments.depth,
		maxNodes = arguments.maxNodes,
		tags = arguments.tags,
	})
	if count == 0 then
		return { content = { { type = "text", text = `{root:GetFullName()} has nothing in it` } } }
	end

	return {
		content = {
			{ type = "text", text = `{count} instance(s) under {root:GetFullName()}:\n\n{source}` },
		},
	}
end

return Tool
