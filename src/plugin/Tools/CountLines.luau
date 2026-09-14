--!strict

local Path = require(script.Parent.Parent.Path)

local DEFAULT_MAX_RESULTS = 50
local HARD_MAX_RESULTS = 500
local EXCLUDE_TAG = "excludeLOC"

type Result = {
	content: { { type: "text", text: string } },
	isError: boolean?,
}

local Tool = {}

Tool.Definition = {
	name = "count_lines",
	description = "Lines of code for every script under a root, biggest first, with totals. Skips any "
		.. `script tagged {EXCLUDE_TAG} and anything under an instance with that tag -- tag LibMP, `
		.. "vendored libraries and the VMCP plugin itself so they don't dominate the list. This is "
		.. "the first step of a performance pass: the long scripts are where the frame time usually "
		.. "is, so read the top of this list and hand the suspects to profile_scripts.",
	inputSchema = {
		type = "object",
		properties = {
			root = {
				type = "string",
				description = 'Dotted path to count under, like "ServerScriptService". Defaults to game.',
			},
			maxResults = {
				type = "integer",
				description = "How many scripts to list. Defaults to 50. Totals always cover everything.",
				minimum = 1,
				maximum = HARD_MAX_RESULTS,
			},
			minLines = {
				type = "integer",
				description = "Leave out scripts shorter than this. Defaults to 0.",
				minimum = 0,
			},
		},
	},
	tags = { title = "Count Lines", readOnly = true, idempotent = true },
}

type Entry = { path: string, className: string, lines: number, code: number }

-- Total lines and lines that aren't blank or a bare comment, so a script that's half header
-- comments doesn't outrank one that's all logic.
local function measure(source: string): (number, number)
	local lines, code = 0, 0
	for line in string.gmatch(source .. "\n", "([^\n]*)\n") do
		lines += 1
		local trimmed = string.match(line, "^%s*(.-)%s*$") :: string
		if trimmed ~= "" and string.sub(trimmed, 1, 2) ~= "--" then
			code += 1
		end
	end
	return lines, code
end

function Tool.Run(arguments: { root: string?, maxResults: number?, minLines: number? }): Result
	local root: Instance = game
	if type(arguments.root) == "string" and arguments.root ~= "" then
		local found, why = Path.Resolve(arguments.root :: string)
		if not found then
			return { content = { { type = "text", text = why :: string } }, isError = true }
		end
		root = found
	end

	local excluded: { [Instance]: boolean } = {}
	for _, instance in root:QueryDescendants(`.{EXCLUDE_TAG} >> LuaSourceContainer`) do
		excluded[instance] = true
	end

	local entries: { Entry } = {}
	local unreadable = 0
	local totalLines, totalCode = 0, 0
	for _, instance in root:QueryDescendants(`LuaSourceContainer:not(.{EXCLUDE_TAG})`) do
		if excluded[instance] then
			continue
		end
		-- Reading Source needs script injection allowed for the plugin.
		local readable, source = pcall(function()
			return (instance :: any).Source
		end)
		if not readable or type(source) ~= "string" then
			unreadable += 1
			continue
		end
		local lines, code = measure(source)
		totalLines += lines
		totalCode += code
		table.insert(
			entries,
			{ path = instance:GetFullName(), className = instance.ClassName, lines = lines, code = code }
		)
	end

	table.sort(entries, function(a, b)
		return a.lines > b.lines
	end)

	local minLines = arguments.minLines or 0
	local limit = math.clamp(arguments.maxResults or DEFAULT_MAX_RESULTS, 1, HARD_MAX_RESULTS)
	local out = {
		`{#entries} script(s) under {root:GetFullName()}: {totalLines} lines, {totalCode} of them code`,
		"",
	}
	local shown = 0
	for _, entry in entries do
		if entry.lines < minLines then
			break
		end
		if shown >= limit then
			table.insert(out, `-- {#entries - shown} more; raise maxResults or set minLines`)
			break
		end
		shown += 1
		table.insert(
			out,
			string.format("%6d  (%5d code)  %-12s %s", entry.lines, entry.code, entry.className, entry.path)
		)
	end
	if unreadable > 0 then
		table.insert(
			out,
			`-- {unreadable} script(s) couldn't be read (allow script injection for VMCP in Plugin Management)`
		)
	end

	return { content = { { type = "text", text = table.concat(out, "\n") } } }
end

return Tool
