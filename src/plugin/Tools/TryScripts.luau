--!strict

-- Starts a playtest in which some scripts run replacement Source, so the user can play a
-- candidate fix before it's written anywhere. The place, the file on disk and Studio's own copy
-- are all untouched by the time this returns; stopping the playtest is the whole revert.

local Path = require(script.Parent.Parent.Path)
local Swap = require(script.Parent.Parent.Playtest.Swap)

local MAX_SCRIPTS = 16

type Result = {
	content: { { type: "text", text: string } },
	isError: boolean?,
}

local Tool = {}

Tool.Definition = {
	name = "try_scripts",
	description = "Starts a playtest that runs the Source you pass in place of the named scripts -- "
		.. "for handing the user a candidate fix to play before anything is applied. The swap "
		.. "happens only for the seconds the playtest takes to boot; Studio's Source is back to "
		.. "the original before this returns, nothing is saved and nothing reaches disk. Stopping "
		.. 'the playtest (playtest { action = "stop" }, or the user\'s Stop button) is the revert. '
		.. "A playtest already running is stopped and restarted. Batch every script the fix "
		.. "touches into one call; pass the whole Source, not a diff.",
	inputSchema = {
		type = "object",
		properties = {
			scripts = {
				type = "array",
				minItems = 1,
				maxItems = MAX_SCRIPTS,
				items = {
					type = "object",
					properties = {
						script = { type = "string", description = 'Dotted path, like "ServerScriptService.Combat".' },
						source = { type = "string", description = "The complete replacement Source." },
					},
					required = { "script", "source" },
				},
			},
			players = {
				type = "integer",
				description = "Test clients to launch. Defaults to 1 (Play Solo).",
				minimum = 1,
				maximum = 8,
			},
		},
		required = { "scripts" },
	},
	tags = { title = "Try Scripts", destructive = true },
	timeoutMs = 150000,
}

local function text(body: string, isError: boolean?): Result
	return { content = { { type = "text", text = body } }, isError = isError }
end

function Tool.Run(arguments: { scripts: { { script: string, source: string } }?, players: number? }): Result
	local scripts = arguments.scripts
	if type(scripts) ~= "table" or #scripts == 0 then
		return text("scripts must be a non-empty array of { script, source }", true)
	end
	if #scripts > MAX_SCRIPTS then
		return text(`at most {MAX_SCRIPTS} scripts per call`, true)
	end

	local replacements: { Swap.Replacement } = {}
	local names = {}
	for index, entry in scripts do
		if type(entry.source) ~= "string" or entry.source == "" then
			return text(`script {index} needs a source`, true)
		end
		local instance, why = Path.Resolve(entry.script)
		if not instance then
			return text(why :: string, true)
		end
		local _, unreadable = Swap.ReadSource(instance)
		if unreadable then
			return text(unreadable, true)
		end
		table.insert(replacements, { instance = instance, source = entry.source })
		table.insert(names, instance:GetFullName())
	end

	local failure, restarted = Swap.Start(replacements, arguments.players or 1, "server")
	if failure then
		return text(failure, true)
	end

	local lines = {
		`Playtest running with replacement Source in {#replacements} script(s):`,
		"  " .. table.concat(names, "\n  "),
		"",
		"Studio, the place and disk all still hold the originals. Tell the user to play it; stop "
			.. 'the playtest with playtest { action = "stop" } to go back to the original everywhere.',
	}
	if restarted then
		table.insert(lines, "(a playtest was already running and was restarted)")
	end
	return text(table.concat(lines, "\n"))
end

return Tool
