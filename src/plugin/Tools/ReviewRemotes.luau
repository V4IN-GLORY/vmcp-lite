--!strict

local Audit = require(script.Parent.Parent.Lib.Audit)
local Path = require(script.Parent.Parent.Path)

type Result = {
	content: { { type: "text", text: string } },
	isError: boolean?,
}

local Tool = {}

Tool.Definition = {
	name = "review_remotes",
	description = "Hands you the code to security-review the game's remotes. Finds every "
		.. "RemoteEvent/RemoteFunction and the server scripts that handle them, traces which "
		.. "remote each handler serves, and returns those scripts' full source -- so you read "
		.. "the real handlers, not a summary. Review each for exploitable holes (missing type or "
		.. "ownership or range checks, client-authoritative currency/damage, no rate limit, "
		.. "loadstring, client-steered DataStore writes), then abuse the ones you flag from a "
		.. "client with run_timeline + vmcp.Exploit.AbuseAll. Reads Studio's current source, so "
		.. "run it against the edit session or a live server, not a real client.",
	inputSchema = {
		type = "object",
		properties = {
			root = {
				type = "string",
				description = 'Dotted path to scan under, like "ServerScriptService". Defaults to '
					.. "game. Narrow it when the game is large and you know where the remotes live.",
			},
		},
	},
	tags = { title = "Review Remotes", readOnly = true, idempotent = true },
}

function Tool.Run(arguments: { root: string? }): Result
	local root: Instance? = nil
	if arguments.root then
		local found, problem = Path.Resolve(arguments.root)
		if not found then
			return { content = { { type = "text", text = problem :: string } }, isError = true }
		end
		root = found
	end

	local surface = Audit.Surface(root)
	if #surface.handlers == 0 and #surface.remotes == 0 then
		return { content = { { type = "text", text = "no remotes found under that root" } } }
	end
	return { content = { { type = "text", text = Audit.Render(surface) } } }
end

return Tool
