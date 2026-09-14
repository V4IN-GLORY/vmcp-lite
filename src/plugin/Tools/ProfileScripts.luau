--!strict

-- Hammers functions in the running game under the MicroProfiler and says what the frame time went
-- on. Two halves in one module, told apart by which DataModel it's running in:
--
--   edit session   builds instrumented Source for the sections, starts a playtest running it
--                  (Playtest/Swap -- the place never keeps it), hands the run to the live context.
--   playtest       builds the load loop, runs it in the game's own VM under a LibMP capture,
--                  reads the capture, and posts it to the VMCP server as a .gprx dump.
--
-- Nothing here changes what the game does. Instrumentation is a pair of profiler calls around
-- lines you chose, applied in Studio only for as long as the tool is running, and the load calls
-- the same functions the game would with arguments you made up in `setup`.

local RunService = game:GetService("RunService")

local Bridge = require(script.Parent.Parent.Bridge)
local Env = require(script.Parent.Parent.Env)
local Instrument = require(script.Parent.Parent.Lib.Instrument)
local Path = require(script.Parent.Parent.Path)
local Profile = require(script.Parent.Parent.Lib.Profile)
local Session = require(script.Parent.Parent.Playtest.Session)
local Swap = require(script.Parent.Parent.Playtest.Swap)

local DEFAULT_SECONDS = 2
local MAX_TARGETS = 8
local MAX_TOTAL_SECONDS = 120

type Result = {
	content: { { type: "text", text: string } },
	isError: boolean?,
}

type Section = {
	script: string,
	fromLine: number,
	toLine: number,
	label: string,
}

local Tool = {}

Tool.Definition = {
	name = "profile_scripts",
	description = "Profiles the live game with the MicroProfiler. Two modes, usable together: `observe` "
		.. "captures the game running on its own for N seconds (the real-load baseline -- what "
		.. "actually costs frame time while someone plays), and `targets` hammer specific functions "
		.. "thousands of times with fake data. Reports your labels with per-call, allocation-per-call "
		.. "and worst-frame numbers, "
		.. "the top scopes by self time across every thread, the slowest frames and what filled them, "
		.. "and the Luau heap delta. Each target is a `setup` Luau body that runs once in the game's "
		.. "own VM (so require() returns the live module with its real state) and returns the "
		.. "function to hammer; the tool wraps every call in debug.profilebegin(label). `sections` "
		.. "additionally brackets line ranges inside scripts with profilebegin/profileend so a slow "
		.. "loop inside a function shows up as its own scope, and `autoSections` does that for every "
		.. "named function in a script at once -- the edits live only in the playtest, never the place. "
		.. "Needs LibMP in the place (pass "
		.. "installLibMP to insert it). Starts a playtest if none is running; if sections are given "
		.. "and one is already running, restarts it so the instrumented code is what runs. Each "
		.. "capture is also written to disk as a .gprx dump for LibMP under Lute. Batch: put every "
		.. "function you want numbers for in one call's targets, and for old-vs-new comparisons or "
		.. "anything that also needs setup, output checks or state reads, call vmcp.Profile.Hammer "
		.. "from a run_timeline server event instead so the whole pass is one call. Load the "
		.. "vmcp-optimization skill before using this.",
	inputSchema = {
		type = "object",
		properties = {
			observe = {
				type = "object",
				description = "Capture the game as it runs, no hammering. Drive it yourself (play, or a "
					.. "client timeline event) during the window. Runs before any targets.",
				properties = {
					seconds = {
						type = "number",
						description = "How long to watch. Defaults to 3; 256 frames is the cap.",
						minimum = 0.5,
					},
				},
			},
			autoSections = {
				type = "array",
				description = "Scripts to instrument function-by-function: every named function gets its own "
					.. 'scope, labelled <ScriptName>.<function>. The fastest way from "this script is slow" to '
					.. '"it\'s this function".',
				items = { type = "string", description = 'Dotted path, like "ServerScriptService.Combat".' },
			},
			targets = {
				type = "array",
				description = "What to hammer. Each runs as its own capture, one after another. Optional when "
					.. "observe is given.",
				minItems = 1,
				maxItems = MAX_TARGETS,
				items = {
					type = "object",
					properties = {
						label = {
							type = "string",
							description = "Scope name in the profiler. Keep it short and unique, like Combat.ResolveHit.",
						},
						setup = {
							type = "string",
							description = "Luau body. Runs once, in the game VM by default, and must `return` the "
								.. "function to call. Build fake arguments here. The function gets the call "
								.. "index (1..calls) as its only argument, so it can vary its data.",
						},
						calls = {
							type = "integer",
							description = "How many calls. Defaults to 500. Stops early when seconds runs out.",
							minimum = 1,
						},
						seconds = {
							type = "number",
							description = "Spread the calls over this long. Defaults to 2 -- the capture only "
								.. "holds frameLimit frames (~2s at 60fps), so longer loads lose their start.",
							minimum = 0.1,
						},
						perFrame = {
							type = "integer",
							description = "Calls per frame before yielding. Defaults to calls / (seconds * 60), "
								.. "which spreads them evenly.",
							minimum = 1,
						},
						warmup = {
							type = "integer",
							description = "Calls thrown away first so lazy init isn't in the numbers. Defaults to 5.",
							minimum = 0,
						},
					},
					required = { "label", "setup" },
				},
			},
			sections = {
				type = "array",
				description = "Line ranges to wrap in debug.profilebegin(label)/profileend() while the run "
					.. "happens. Lines are 1-based and inclusive, in the script's current Source. Pick "
					.. "whole statements: a range that ends inside a block or contains an early return "
					.. "reads wrong.",
				items = {
					type = "object",
					properties = {
						script = { type = "string", description = 'Dotted path, like "ServerScriptService.Combat".' },
						fromLine = { type = "integer", minimum = 1 },
						toLine = { type = "integer", minimum = 1 },
						label = { type = "string" },
					},
					required = { "script", "fromLine", "toLine", "label" },
				},
			},
			where = {
				type = "string",
				description = "Which live context runs the load. Defaults to server.",
				enum = { "server", "client" },
			},
			player = {
				type = "integer",
				description = "Which test client, 1-based, when where is client.",
				minimum = 1,
				maximum = 8,
			},
			vm = {
				type = "string",
				description = "game (default) runs setup in the game's VM, sharing the require cache with the "
					.. "running scripts. plugin runs it in VMCP's VM with `vmcp` in scope -- fresh module "
					.. "copies, so only for pure functions.",
				enum = { "game", "plugin" },
			},
			frameLimit = {
				type = "integer",
				description = "Frames the profiler keeps, 8-256. Defaults to 128. More frames, bigger dump.",
				minimum = 8,
				maximum = 256,
			},
			top = {
				type = "integer",
				description = "How many scopes to list by self time. Defaults to 15.",
				minimum = 1,
				maximum = 60,
			},
			dump = {
				type = "boolean",
				description = "Write each capture to ~/.vmcp/profiles/<name>-<label>.gprx. Defaults to true.",
			},
			name = {
				type = "string",
				description = "Dump file prefix. Defaults to a timestamp.",
			},
			installLibMP = {
				type = "boolean",
				description = "Insert LibMP from the Creator Store into ReplicatedStorage if it isn't there.",
			},
			players = {
				type = "integer",
				description = "Players for the playtest this starts, if it has to. Defaults to 1.",
				minimum = 1,
				maximum = 8,
			},
		},
	},
	tags = { title = "Profile Scripts", destructive = true },
	timeoutMs = 240000,
}

local function text(body: string, isError: boolean?): Result
	return { content = { { type = "text", text = body } }, isError = isError }
end

local function checkTargets(targets: any, observing: boolean): (string?, number)
	if targets == nil and observing then
		return nil, 0
	end
	if type(targets) ~= "table" or #targets == 0 then
		return "targets must be a non-empty array (or pass observe)", 0
	end
	if #targets > MAX_TARGETS then
		return `at most {MAX_TARGETS} targets per call`, 0
	end
	local total = 0
	for index, target in targets do
		if type(target.label) ~= "string" or target.label == "" then
			return `target {index} needs a label`, 0
		end
		if type(target.setup) ~= "string" or target.setup == "" then
			return `target "{target.label}" needs a setup body`, 0
		end
		total += target.seconds or DEFAULT_SECONDS
	end
	if total > MAX_TOTAL_SECONDS then
		return `the targets add up to {total}s of load; keep it under {MAX_TOTAL_SECONDS}s per call`, 0
	end
	return nil, total
end

-- The playtest half. Everything real is Profile.Hammer, so a timeline event can do the same thing
-- without a tool call per target.
local function capture(arguments: any): Result
	local observe = arguments.observe
	local problem = checkTargets(arguments.targets, observe ~= nil)
	if problem then
		return text(problem, true)
	end
	local labels = {}
	for _, section in arguments.sections or {} do
		table.insert(labels, section.label)
	end
	for _, label in arguments.autoLabels or {} do
		table.insert(labels, label)
	end

	local parts = {}
	local failed = false
	if observe then
		local watched = Profile.Observe(observe.seconds, {
			frameLimit = arguments.frameLimit,
			top = arguments.top,
			labels = labels,
			dump = arguments.dump ~= false,
			name = arguments.name,
		})
		table.insert(parts, watched)
	end
	if arguments.targets then
		local body, hammerFailed = Profile.Hammer(arguments.targets, {
			vm = arguments.vm,
			env = Env,
			frameLimit = arguments.frameLimit,
			top = arguments.top,
			dump = arguments.dump,
			name = arguments.name,
			labels = labels,
		})
		table.insert(parts, body)
		failed = hammerFailed
	end
	table.insert(
		parts,
		"The last capture is still open in this context: a run_luau or timeline event here can "
			.. "reopen it with vmcp.Profile.Session() and walk it with LibMP directly."
	)
	return text(table.concat(parts, "\n\n"), failed)
end

local function splitLines(source: string): { string }
	local lines = {}
	for line in string.gmatch(source .. "\n", "([^\n]*)\n") do
		table.insert(lines, line)
	end
	return lines
end

-- Builds each script's Source with the profiler calls in. Sections on one script are merged in a
-- single pass over the original line numbers, so they can nest or overlap without shifting each
-- other. Nothing is written here -- Swap does that, briefly.
local function instrument(sections: { Section }, autoScripts: { string }): ({ Swap.Replacement }, { string }, string?)
	local byScript: { [Instance]: { Section } } = {}
	local autoLabels: { string } = {}
	local autoOn: { [Instance]: boolean } = {}
	for _, path in autoScripts do
		local instance, why = Path.Resolve(path)
		if not instance then
			return {}, {}, why
		end
		if not instance:IsA("LuaSourceContainer") then
			return {}, {}, `{path} is a {instance.ClassName}, not a script`
		end
		autoOn[instance] = true
		byScript[instance] = byScript[instance] or {}
	end
	for index, section in sections do
		local instance, why = Path.Resolve(section.script)
		if not instance then
			return {}, {}, why
		end
		if not instance:IsA("LuaSourceContainer") then
			return {}, {}, `{section.script} is a {instance.ClassName}, not a script`
		end
		if type(section.label) ~= "string" or section.label == "" then
			return {}, {}, `section {index} needs a label`
		end
		local list = byScript[instance]
		if not list then
			list = {}
			byScript[instance] = list
		end
		table.insert(list, section)
	end

	local replacements: { Swap.Replacement } = {}
	for instance, list in byScript do
		local source, why = Swap.ReadSource(instance)
		if not source then
			return {}, {}, why
		end
		-- Function scopes go in first; they're inserted inline, so the line numbers the sections
		-- were written against still hold.
		if autoOn[instance] then
			local labels
			source, labels = Instrument.Functions(source :: string, instance.Name)
			for _, label in labels do
				table.insert(autoLabels, label)
			end
		end
		local lines = splitLines(source :: string)
		for _, section in list do
			if section.fromLine > section.toLine or section.toLine > #lines then
				return {},
					{},
					`section "{section.label}" wants lines {section.fromLine}-{section.toLine} but {instance:GetFullName()} has {#lines}`
			end
		end

		local out = {}
		for number, line in lines do
			-- Outer sections open first, and close last.
			local opening = {}
			for _, section in list do
				if section.fromLine == number then
					table.insert(opening, section)
				end
			end
			table.sort(opening, function(a, b)
				return a.toLine > b.toLine
			end)
			for _, section in opening do
				table.insert(out, `debug.profilebegin({string.format("%q", section.label)})`)
			end
			table.insert(out, line)
			local closing = {}
			for _, section in list do
				if section.toLine == number then
					table.insert(closing, section)
				end
			end
			table.sort(closing, function(a, b)
				return a.fromLine > b.fromLine
			end)
			for _ in closing do
				table.insert(out, "debug.profileend()")
			end
		end

		table.insert(replacements, { instance = instance, source = table.concat(out, "\n") })
	end
	return replacements, autoLabels, nil
end

local function orchestrate(arguments: any): Result
	local problem, totalSeconds = checkTargets(arguments.targets, arguments.observe ~= nil)
	if problem then
		return text(problem, true)
	end
	if arguments.observe then
		totalSeconds += (arguments.observe.seconds or 3)
	end

	if not Profile.Find() then
		if not arguments.installLibMP then
			return text(
				"LibMP isn't in this place. Put the LibMP ModuleScript in ReplicatedStorage (Creator "
					.. "Store asset 109009378620272, or github.com/Roblox/libmp/releases), or call again "
					.. "with installLibMP = true.",
				true
			)
		end
		local _, why = Profile.Install()
		if why then
			return text(why, true)
		end
	end

	local notes = {}
	local sections: { Section } = arguments.sections or {}
	local autoScripts: { string } = arguments.autoSections or {}
	local autoLabels: { string } = {}
	local context = arguments.where or "server"
	local players = math.clamp(arguments.players or 1, 1, 8)
	local startedHere = false

	if #sections > 0 or #autoScripts > 0 then
		local replacements, labels, why = instrument(sections, autoScripts)
		if why then
			return text(why, true)
		end
		autoLabels = labels
		local failure, restarted = Swap.Start(replacements, players, context, arguments.player)
		if failure then
			return text(failure, true)
		end
		startedHere = true
		if restarted then
			table.insert(notes, "stopped the running playtest so the instrumented scripts would be the ones that ran")
		end
		table.insert(
			notes,
			`{#replacements} script(s) run instrumented in this playtest only; Studio's Source was never left changed`
		)
	elseif Session.IsRunning() then
		local notUp = Swap.WaitFor(context, arguments.player)
		if notUp then
			return text(notUp, true)
		end
	else
		local failure = Swap.Start({}, players, context, arguments.player)
		if failure then
			return text(failure, true)
		end
		startedHere = true
	end

	local reached, result = Bridge.Invoke("profile_scripts", {
		context = context,
		player = arguments.player,
		targets = arguments.targets,
		sections = sections,
		autoLabels = autoLabels,
		observe = arguments.observe,
		vm = arguments.vm,
		frameLimit = arguments.frameLimit,
		top = arguments.top,
		dump = arguments.dump,
		name = arguments.name,
	}, totalSeconds + 60)

	if not reached then
		return text(`couldn't run the profile in the {context}: {tostring(result)}`, true)
	end

	local body = {}
	for _, item in result.content or {} do
		if type(item.text) == "string" then
			table.insert(body, item.text)
		end
	end
	if startedHere then
		table.insert(notes, 'the playtest is still open -- stop it with playtest { action = "stop" } when you\'re done')
	end
	if #notes > 0 then
		table.insert(body, "-- " .. table.concat(notes, "\n-- "))
	end
	return text(table.concat(body, "\n\n"), result.isError == true)
end

function Tool.Run(arguments: any): Result
	if RunService:IsEdit() then
		return orchestrate(arguments)
	end
	return capture(arguments)
end

return Tool
