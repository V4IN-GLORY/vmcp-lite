--!strict

local Bridge = require(script.Parent.Parent.Bridge)
local Path = require(script.Parent.Parent.Path)

local DEFAULT_MAX_RESULTS = 40
local HARD_MAX_RESULTS = 200
local MAX_CONTEXT = 10

type Result = {
	content: { { type: "text", text: string } },
	isError: boolean?,
}

local Tool = {}

Tool.Definition = {
	name = "search_scripts",
	description = "Searches the source of every script under a root and returns the matching "
		.. "lines with their paths. The pattern is a Luau string pattern, not a regex -- use "
		.. "%w and %s, and escape a literal dot as %.. Reads what Studio currently has, which "
		.. "isn't always what's on disk -- pass drift = true instead of a pattern to get the "
		.. "list of scripts where the two disagree.",
	inputSchema = {
		type = "object",
		properties = {
			pattern = {
				type = "string",
				description = "Luau string pattern to search for. Required unless drift is set.",
			},
			drift = {
				type = "boolean",
				description = "Skip searching and instead report every script whose source no "
					.. 'longer matches the file Rojo syncs it from. Answers "is Studio showing '
					.. 'me the same code as the repo" in one call.',
			},
			root = {
				type = "string",
				description = 'Dotted path to search under, like "ServerScriptService". Defaults to game.',
			},
			contextLines = {
				type = "integer",
				description = "Lines of surrounding source to show around each hit. Defaults to 0.",
				minimum = 0,
				maximum = MAX_CONTEXT,
			},
			maxResults = {
				type = "integer",
				description = "Stop after this many matching lines. Defaults to 40.",
				minimum = 1,
				maximum = HARD_MAX_RESULTS,
			},
		},
	},
	tags = { title = "Search Scripts", readOnly = true, idempotent = true },
}

-- FNV-1a, 32 bit. The server runs the same thing over the file on disk; agreeing exactly with it
-- matters far more than the hash being a good one, since all either side ever does is compare a
-- file against itself.
local function mul32(a: number, b: number): number
	-- Split because a * 16777619 loses low bits once a is near 2^32 -- doubles run out of mantissa
	-- well before the product fits.
	local high = bit32.band(bit32.rshift(a, 16) * b, 0xFFFF)
	return bit32.band(bit32.lshift(high, 16) + bit32.band(a, 0xFFFF) * b, 0xFFFFFFFF)
end

local function fingerprint(source: string): number
	-- Line endings and a trailing newline are the editor's business, not a real difference.
	local text = source:gsub("\r\n", "\n"):gsub("%s+$", "")
	local hash = 2166136261
	for index = 1, #text do
		hash = mul32(bit32.bxor(hash, string.byte(text, index)), 16777619)
	end
	return hash
end

local function checkDrift(root: Instance): Result
	local scripts = {}
	local unreadable = 0
	for _, instance in root:GetDescendants() do
		if not instance:IsA("LuaSourceContainer") then
			continue
		end
		local readable, source = pcall(function()
			return (instance :: any).Source
		end)
		if not readable or type(source) ~= "string" then
			unreadable += 1
			continue
		end
		table.insert(scripts, {
			path = instance:GetFullName(),
			className = instance.ClassName,
			hash = fingerprint(source),
		})
	end

	local ok, payload = Bridge.Request("source/drift", { scripts = scripts }, 30)
	if not ok then
		return { content = { { type = "text", text = tostring(payload) } }, isError = true }
	end

	local drift = payload.drift or {}
	if #drift == 0 then
		local text = `Studio and {payload.projectPath} agree on all {#scripts} script(s).`
		if unreadable > 0 then
			text ..= ` {unreadable} couldn't be read -- allow script injection for VMCP in Plugin Management.`
		end
		return { content = { { type = "text", text = text } } }
	end

	local lines = { `{#drift} of {#scripts} script(s) disagree with {payload.projectPath}:` }
	for _, entry in drift do
		local where = if entry.file then ` -> {entry.file}` else ""
		table.insert(lines, `  {entry.problem}: {entry.path}{where}`)
	end
	table.insert(lines, "")
	table.insert(lines, '"not in studio" means the file exists but never synced; "not on disk"')
	table.insert(lines, "means the script was made in Studio and Rojo has nothing to write it to.")

	return { content = { { type = "text", text = table.concat(lines, "\n") } } }
end

local function splitLines(source: string): { string }
	local lines = {}
	for line in string.gmatch(source .. "\n", "([^\n]*)\n") do
		table.insert(lines, line)
	end
	return lines
end

function Tool.Run(
	arguments: { pattern: string?, root: string?, contextLines: number?, maxResults: number?, drift: boolean? }
): Result
	local root: Instance = game
	if type(arguments.root) == "string" and arguments.root ~= "" then
		local found, why = Path.Resolve(arguments.root :: string)
		if not found then
			return { content = { { type = "text", text = why :: string } }, isError = true }
		end
		root = found
	end

	if arguments.drift then
		return checkDrift(root)
	end

	local pattern = arguments.pattern
	if type(pattern) ~= "string" or pattern == "" then
		return {
			content = { { type = "text", text = "pass either a pattern to search for or drift = true" } },
			isError = true,
		}
	end
	local valid, problem = pcall(string.find, "", pattern)
	if not valid then
		return { content = { { type = "text", text = `pattern isn't valid: {problem}` } }, isError = true }
	end

	local context = math.clamp(arguments.contextLines or 0, 0, MAX_CONTEXT)
	local limit = math.clamp(arguments.maxResults or DEFAULT_MAX_RESULTS, 1, HARD_MAX_RESULTS)

	local out = {}
	local hits = 0
	local unreadable = 0
	local truncated = false

	for _, instance in root:GetDescendants() do
		if not instance:IsA("LuaSourceContainer") then
			continue
		end
		-- Reading Source needs the same script injection permission writing it does.
		local readable, source = pcall(function()
			return (instance :: any).Source
		end)
		if not readable or type(source) ~= "string" then
			unreadable += 1
			continue
		end
		if not string.find(source, pattern) then
			continue
		end

		local lines = splitLines(source)
		for number, line in lines do
			if not string.find(line, pattern) then
				continue
			end
			if hits >= limit then
				truncated = true
				break
			end
			hits += 1

			table.insert(out, `{instance:GetFullName()}:{number}`)
			for index = math.max(number - context, 1), math.min(number + context, #lines) do
				local marker = if index == number then ">" else " "
				table.insert(out, `{marker} {index}: {lines[index]}`)
			end
		end
		if truncated then
			break
		end
	end

	if hits == 0 then
		local text = `no script under {root:GetFullName()} matched`
		if unreadable > 0 then
			text ..= `. {unreadable} script(s) couldn't be read -- allow script injection for VMCP in Plugin Management`
		end
		return { content = { { type = "text", text = text } } }
	end

	if truncated then
		table.insert(out, `-- stopped at {limit} matches; narrow the pattern or the root`)
	end
	if unreadable > 0 then
		table.insert(out, `-- {unreadable} script(s) couldn't be read (script injection not allowed)`)
	end

	return { content = { { type = "text", text = table.concat(out, "\n") } } }
end

return Tool
