--!strict

local Lint = require(script.Parent.Parent.Lib.Lint)
local Path = require(script.Parent.Parent.Path)

local DEFAULT_MAX_RESULTS = 60
local HARD_MAX_RESULTS = 400
local MAX_LINES = 15000
local EXCLUDE_TAG = "excludeLOC"

type Result = {
	content: { { type: "text", text: string } },
	isError: boolean?,
}

local Tool = {}

Tool.Definition = {
	name = "lint_hotpaths",
	description = "Static pass over every script under a root for the shapes that cost frame time, "
		.. "ranked by how often they'd run: tree walks, Instance.new/Clone, string building and "
		.. "physics queries inside Heartbeat/RenderStepped/Touched handlers or loops; polling "
		.. "while-true loops; legacy wait/spawn; deep game.X.Y.Z paths and require inside "
		.. "functions; connections made per run. Reads Studio's Source, so it sees Studio-only "
		.. "scripts too. No playtest needed. It's a shortlist for profile_scripts, not a verdict -- a "
		.. "high finding in code that runs once a match is fine. Skips anything tagged excludeLOC.",
	inputSchema = {
		type = "object",
		properties = {
			root = {
				type = "string",
				description = 'Dotted path to scan under, like "ServerScriptService". Defaults to game.',
			},
			minSeverity = {
				type = "string",
				description = "Lowest severity to list. Defaults to medium.",
				enum = { "high", "medium", "low" },
			},
			maxResults = {
				type = "integer",
				description = "Findings to list. Defaults to 60.",
				minimum = 1,
				maximum = HARD_MAX_RESULTS,
			},
		},
	},
	tags = { title = "Lint Hot Paths", readOnly = true, idempotent = true },
	timeoutMs = 60000,
}

type Row = { path: string, finding: Lint.Finding }

function Tool.Run(arguments: { root: string?, minSeverity: string?, maxResults: number? }): Result
	local root: Instance = game
	if type(arguments.root) == "string" and arguments.root ~= "" then
		local found, why = Path.Resolve(arguments.root :: string)
		if not found then
			return { content = { { type = "text", text = why :: string } }, isError = true }
		end
		root = found
	end
	local floor = Lint.Rank[arguments.minSeverity or "medium"] or 2
	local limit = math.clamp(arguments.maxResults or DEFAULT_MAX_RESULTS, 1, HARD_MAX_RESULTS)

	local excluded: { [Instance]: boolean } = {}
	for _, instance in root:QueryDescendants(`.{EXCLUDE_TAG} >> LuaSourceContainer`) do
		excluded[instance] = true
	end

	local rows: { Row } = {}
	local scanned, unreadable, skipped = 0, 0, 0
	local perScript: { [string]: number } = {}
	for _, instance in root:QueryDescendants(`LuaSourceContainer:not(.{EXCLUDE_TAG})`) do
		if excluded[instance] then
			continue
		end
		local readable, source = pcall(function()
			return (instance :: any).Source
		end)
		if not readable or type(source) ~= "string" then
			unreadable += 1
			continue
		end
		local _, newlines = string.gsub(source, "\n", "")
		if newlines > MAX_LINES then
			skipped += 1
			continue
		end
		scanned += 1
		local path = instance:GetFullName()
		for _, finding in Lint.Script(source) do
			if Lint.Rank[finding.severity] >= floor then
				table.insert(rows, { path = path, finding = finding })
				perScript[path] = (perScript[path] or 0) + Lint.Rank[finding.severity]
			end
		end
	end

	table.sort(rows, function(a, b)
		local ra, rb = Lint.Rank[a.finding.severity], Lint.Rank[b.finding.severity]
		if ra ~= rb then
			return ra > rb
		end
		if a.path ~= b.path then
			return a.path < b.path
		end
		return a.finding.line < b.finding.line
	end)

	local out = {
		`{#rows} finding(s) at {arguments.minSeverity or "medium"} or worse across {scanned} script(s) under {root:GetFullName()}`,
	}
	if #rows > 0 then
		-- Which scripts to open first: the sum of their severities.
		local ranked = {}
		for path, score in perScript do
			table.insert(ranked, { path = path, score = score })
		end
		table.sort(ranked, function(a, b)
			return a.score > b.score
		end)
		local names = {}
		for index = 1, math.min(8, #ranked) do
			table.insert(names, `{ranked[index].path} ({ranked[index].score})`)
		end
		table.insert(out, "scripts by weight: " .. table.concat(names, ", "))
		table.insert(out, "")
	end
	for index, row in rows do
		if index > limit then
			table.insert(out, `-- {#rows - limit} more; raise maxResults or minSeverity`)
			break
		end
		local finding = row.finding
		table.insert(
			out,
			string.format(
				"%-6s %s:%d  %s [%s] -- %s",
				finding.severity,
				row.path,
				finding.line,
				finding.pattern,
				finding.context,
				finding.detail
			)
		)
	end
	if skipped > 0 then
		table.insert(
			out,
			`-- {skipped} script(s) over {MAX_LINES} lines skipped; tag them {EXCLUDE_TAG} or lint them alone`
		)
	end
	if unreadable > 0 then
		table.insert(out, `-- {unreadable} script(s) couldn't be read (allow script injection for VMCP)`)
	end
	return { content = { { type = "text", text = table.concat(out, "\n") } } }
end

return Tool
