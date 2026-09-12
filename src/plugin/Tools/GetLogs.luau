--!strict

local Buffer = require(script.Parent.Parent.Log.Buffer)

local DEFAULT_COUNT = 50
local MAX_COUNT = 300

type Result = {
	content: { { type: "text", text: string } },
	isError: boolean?,
}

local Tool = {}

Tool.Definition = {
	name = "get_logs",
	description = "Reads Studio's output window from a buffer the plugin has been filling since "
		.. "it loaded. This is how you see an error thrown by the place's own scripts -- run_luau "
		.. "only ever shows you output from its own snippet.",
	inputSchema = {
		type = "object",
		properties = {
			count = {
				type = "integer",
				description = "How many of the most recent lines to return. Defaults to 50.",
				minimum = 1,
				maximum = MAX_COUNT,
			},
			severity = {
				type = "string",
				description = "Only lines at this level. Defaults to everything.",
				enum = { "print", "info", "warn", "error" },
			},
			sinceSeconds = {
				type = "number",
				description = "Only lines logged in the last this many seconds.",
				minimum = 1,
			},
			match = {
				type = "string",
				description = "Only lines matching this Luau string pattern (not a regex).",
			},
		},
	},
	tags = { title = "Get Logs", readOnly = true },
}

function Tool.Run(arguments: { count: number?, severity: string?, sinceSeconds: number?, match: string? }): Result
	local all, dropped = Buffer.Since(0)
	local severity = arguments.severity
	local match = arguments.match
	local cutoff = if arguments.sinceSeconds then os.time() - arguments.sinceSeconds else nil

	local kept = {}
	for _, entry in all do
		if severity and entry.severity ~= severity then
			continue
		end
		if cutoff and entry.time < cutoff then
			continue
		end
		if match then
			-- A bad pattern raises rather than returning nothing, and "malformed pattern" is a
			-- much more useful answer than an empty log.
			local ok, found = pcall(string.find, entry.text, match)
			if not ok then
				return {
					content = { { type = "text", text = `match isn't a valid pattern: {found}` } },
					isError = true,
				}
			end
			if not found then
				continue
			end
		end
		table.insert(kept, entry)
	end

	if #kept == 0 then
		return { content = { { type = "text", text = "no log lines matched" } } }
	end

	local count = math.clamp(arguments.count or DEFAULT_COUNT, 1, MAX_COUNT)
	local first = math.max(#kept - count + 1, 1)
	local lines = {}
	for index = first, #kept do
		local entry = kept[index]
		table.insert(lines, `{os.date("%H:%M:%S", entry.time)} [{entry.severity}] {entry.text}`)
	end

	if first > 1 or dropped > 0 then
		table.insert(lines, 1, `-- showing the last {#lines} of {#kept + dropped} lines`)
	end

	return { content = { { type = "text", text = table.concat(lines, "\n") } } }
end

return Tool
