--!strict

-- Hammers functions in the running game under the MicroProfiler and says what the frame time went
-- on. Two halves in one module, told apart by which DataModel it's running in:
--
--   edit session   instruments sections with debug.profilebegin/end, makes sure a playtest is up,
--                  hands the run to the live context, then puts every Source back how it was.
--   playtest       builds the load loop, runs it in the game's own VM under a LibMP capture,
--                  reads the capture, and posts it to the VMCP server as a .gprx dump.
--
-- Nothing here changes what the game does. Instrumentation is a pair of profiler calls around
-- lines you chose, applied in Studio only for as long as the tool is running, and the load calls
-- the same functions the game would with arguments you made up in `setup`.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Bridge = require(script.Parent.Parent.Bridge)
local Env = require(script.Parent.Parent.Env)
local GameVm = require(script.Parent.Parent.Exec.GameVm)
local Inject = require(script.Parent.Parent.Exec.Inject)
local Path = require(script.Parent.Parent.Path)
local Profile = require(script.Parent.Parent.Lib.Profile)
local Session = require(script.Parent.Parent.Playtest.Session)

local DEFAULT_CALLS = 500
local DEFAULT_SECONDS = 2
local DEFAULT_WARMUP = 5
local DEFAULT_FRAME_LIMIT = 128
local MAX_TARGETS = 8
local MAX_TOTAL_SECONDS = 120
local PEER_TIMEOUT = 90
local RESULT_NAME = "__VMCP_ProfileResult"
-- Base64 of the capture has to fit one socket message (VMCP_MAX_MESSAGE_MB, 8 by default).
local MAX_DUMP_BYTES = 4_500_000

type Result = {
	content: { { type: "text", text: string } },
	isError: boolean?,
}

type Target = {
	label: string,
	setup: string,
	calls: number?,
	seconds: number?,
	perFrame: number?,
	warmup: number?,
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
	description = "Runs functions from the live game thousands of times under the MicroProfiler and "
		.. "reports what the frame time went on: your labels with per-call and worst-frame numbers, "
		.. "the top scopes by self time across every thread, the slowest frames and what filled them, "
		.. "and the Luau heap delta. Each target is a `setup` Luau body that runs once in the game's "
		.. "own VM (so require() returns the live module with its real state) and returns the "
		.. "function to hammer; the tool wraps every call in debug.profilebegin(label). `sections` "
		.. "additionally brackets line ranges inside scripts with profilebegin/profileend so a slow "
		.. "loop inside a function shows up as its own scope -- those edits live only in Studio while "
		.. "the tool runs and are reverted before it returns. Needs LibMP in the place (pass "
		.. "installLibMP to insert it). Starts a playtest if none is running; if sections are given "
		.. "and one is already running, restarts it so the instrumented code is what runs. Each "
		.. "capture is also written to disk as a .gprx dump for LibMP under Lute. Load the "
		.. "vmcp-optimization skill before using this.",
	inputSchema = {
		type = "object",
		properties = {
			targets = {
				type = "array",
				description = "What to hammer. Each runs as its own capture, one after another.",
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
		required = { "targets" },
	},
	tags = { title = "Profile Scripts", destructive = true },
	timeoutMs = 240000,
}

local function text(body: string, isError: boolean?): Result
	return { content = { { type = "text", text = body } }, isError = isError }
end

local function checkTargets(targets: any): (string?, number)
	if type(targets) ~= "table" or #targets == 0 then
		return "targets must be a non-empty array", 0
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

-- The load loop as source, because it runs in the game VM where nothing of ours is in scope.
local function loadSource(target: Target): string
	local calls = target.calls or DEFAULT_CALLS
	local seconds = target.seconds or DEFAULT_SECONDS
	local perFrame = target.perFrame or math.max(1, math.ceil(calls / (seconds * 60)))
	local warmup = target.warmup or DEFAULT_WARMUP
	return string.format(
		[[
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local label = %q
local result = { label = label }
local function setup()
%s
end
local ok, fn = pcall(setup)
if not ok then
	result.error = "setup errored: " .. tostring(fn)
elseif type(fn) ~= "function" then
	result.error = "setup must return a function, it returned " .. typeof(fn)
else
	for _ = 1, %d do
		pcall(fn, 0)
	end
	local made, errors, firstError = 0, 0, nil
	local inFrame = 0
	local started = os.clock()
	local deadline = started + %s
	while made < %d and os.clock() < deadline do
		made += 1
		debug.profilebegin(label)
		local passed, failure = pcall(fn, made)
		debug.profileend()
		if not passed then
			errors += 1
			firstError = firstError or tostring(failure)
		end
		inFrame += 1
		if inFrame >= %d then
			inFrame = 0
			RunService.Heartbeat:Wait()
		end
	end
	result.calls = made
	result.errors = errors
	result.firstError = firstError
	result.seconds = os.clock() - started
end
local holder = game:GetService("ReplicatedStorage"):FindFirstChild(%q) or Instance.new("StringValue")
holder.Name = %q
holder.Archivable = false
holder.Value = HttpService:JSONEncode(result)
holder.Parent = game:GetService("ReplicatedStorage")
]],
		target.label,
		target.setup,
		warmup,
		tostring(seconds),
		calls,
		perFrame,
		RESULT_NAME,
		RESULT_NAME
	)
end

local function runLoad(target: Target, vm: string?): (any?, string?)
	local source = loadSource(target)
	local ok, failure
	if vm == "plugin" then
		ok, failure = Inject.Run(source, Env, (target.seconds or DEFAULT_SECONDS) + 30)
	else
		ok, failure = GameVm.Run(source)
	end
	if not ok then
		return nil, tostring(failure)
	end
	local holder = ReplicatedStorage:FindFirstChild(RESULT_NAME)
	if not holder or not holder:IsA("StringValue") then
		return nil, "the load ran but left no result behind"
	end
	local decoded, result = pcall(HttpService.JSONDecode, HttpService, holder.Value)
	holder:Destroy()
	if not decoded then
		return nil, `couldn't read the load's result: {result}`
	end
	return result, nil
end

local function safeName(name: string): string
	return (string.gsub(name, "[^%w_%-]", "_"):sub(1, 48))
end

local function capture(arguments: any): Result
	local problem = checkTargets(arguments.targets)
	if problem then
		return text(problem, true)
	end

	local labels: { string } = {}
	for _, target in arguments.targets do
		table.insert(labels, target.label)
	end
	for _, section in arguments.sections or {} do
		table.insert(labels, section.label)
	end

	local prefix = safeName(arguments.name or os.date("%Y%m%d-%H%M%S"))
	local parts = {}
	local failed = false

	for _, target in arguments.targets :: { Target } do
		local loadResult: any = nil
		local loadProblem: string? = nil
		local buf, why = Profile.Capture(arguments.frameLimit or DEFAULT_FRAME_LIMIT, function()
			loadResult, loadProblem = runLoad(target, arguments.vm)
		end)

		local header = { `== {target.label} ==` }
		if loadProblem then
			table.insert(header, `load failed: {loadProblem}`)
			failed = true
		elseif loadResult.error then
			table.insert(header, loadResult.error)
			failed = true
		else
			local line = string.format("%d calls in %.2fs", loadResult.calls, loadResult.seconds)
			if loadResult.errors > 0 then
				line ..= ` -- {loadResult.errors} errored, first: {loadResult.firstError}`
			end
			table.insert(header, line)
		end

		if not buf then
			table.insert(header, `no capture: {why}`)
			table.insert(parts, table.concat(header, "\n"))
			failed = true
			continue
		end

		local report, analyzeProblem = Profile.Analyze(buf, { labels = labels, top = arguments.top })
		if not report then
			table.insert(header, `couldn't read the capture: {analyzeProblem}`)
		else
			table.insert(header, Profile.Summarise(report))
		end

		if arguments.dump ~= false then
			local size = buffer.len(buf)
			if size > MAX_DUMP_BYTES then
				table.insert(
					header,
					`(capture is {math.floor(size / 1024)} KB, too big to ship as one message -- lower frameLimit, or raise VMCP_MAX_MESSAGE_MB)`
				)
			else
				local posted, outcome = Bridge.Post({
					kind = "gprx",
					name = `{prefix}-{safeName(target.label)}`,
					data = Profile.Base64(buf),
				})
				table.insert(header, if posted then outcome else `dump failed: {outcome}`)
			end
		end

		table.insert(parts, table.concat(header, "\n"))
	end

	table.insert(
		parts,
		"The last capture is still open in this context: run_luau here with `local session = "
			.. "vmcp.Profile.Session()` to walk it with LibMP directly."
	)
	return text(table.concat(parts, "\n\n"), failed)
end

type Original = { instance: Instance, source: string }

local function splitLines(source: string): { string }
	local lines = {}
	for line in string.gmatch(source .. "\n", "([^\n]*)\n") do
		table.insert(lines, line)
	end
	return lines
end

-- Rewrites each script's Source with the profiler calls in, and hands back what to put back.
-- Sections on one script are merged in a single pass over the original line numbers, so they can
-- nest or overlap without shifting each other.
local function instrument(sections: { Section }): ({ Original }, string?)
	local byScript: { [Instance]: { Section } } = {}
	for index, section in sections do
		local instance, why = Path.Resolve(section.script)
		if not instance then
			return {}, why
		end
		if not instance:IsA("LuaSourceContainer") then
			return {}, `{section.script} is a {instance.ClassName}, not a script`
		end
		if type(section.label) ~= "string" or section.label == "" then
			return {}, `section {index} needs a label`
		end
		local list = byScript[instance]
		if not list then
			list = {}
			byScript[instance] = list
		end
		table.insert(list, section)
	end

	local originals: { Original } = {}
	for instance, list in byScript do
		local readable, source = pcall(function()
			return (instance :: any).Source
		end)
		if not readable or type(source) ~= "string" then
			return originals, `couldn't read {instance:GetFullName()} -- allow script injection for VMCP`
		end
		local lines = splitLines(source)
		for _, section in list do
			if section.fromLine > section.toLine or section.toLine > #lines then
				return originals,
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

		table.insert(originals, { instance = instance, source = source })
		local container: any = instance
		container.Source = table.concat(out, "\n")
	end
	return originals, nil
end

local function restore(originals: { Original })
	for _, original in originals do
		pcall(function()
			(original.instance :: any).Source = original.source
		end)
	end
end

local function waitForPeer(context: string, player: number?): string?
	local deadline = os.clock() + PEER_TIMEOUT
	local last = "never answered"
	repeat
		local reached, result = Bridge.Invoke("peer", { action = "ping", context = context, player = player }, 10)
		if reached and result ~= nil and result.isError ~= true then
			return nil
		end
		last = if reached then "not up yet" else tostring(result)
		task.wait(0.5)
	until os.clock() >= deadline
	return `the {context} never came up ({last})`
end

local function stopPlaytest(): string?
	Bridge.Invoke("peer", { action = "stop", context = "server" }, 20)
	Session.Forget()
	local deadline = os.clock() + 30
	while Session.IsRunning() and os.clock() < deadline do
		task.wait(0.25)
	end
	return if Session.IsRunning() then "the running playtest wouldn't stop" else nil
end

local function orchestrate(arguments: any): Result
	local problem, totalSeconds = checkTargets(arguments.targets)
	if problem then
		return text(problem, true)
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
	local originals: { Original } = {}

	if #sections > 0 then
		if Session.IsRunning() then
			local failure = stopPlaytest()
			if failure then
				return text(failure, true)
			end
			table.insert(notes, "stopped the running playtest so the instrumented scripts would be the ones that ran")
		end
		local why
		originals, why = instrument(sections)
		if why then
			restore(originals)
			return text(why, true)
		end
	end

	local context = arguments.where or "server"
	local startedHere = false
	if not Session.IsRunning() then
		local failure = Session.Start(math.clamp(arguments.players or 1, 1, 8))
		if failure then
			restore(originals)
			return text(failure, true)
		end
		startedHere = true
	end

	local notUp = waitForPeer(context, arguments.player)
	if notUp then
		restore(originals)
		return text(notUp, true)
	end

	local reached, result = Bridge.Invoke("profile_scripts", {
		context = context,
		player = arguments.player,
		targets = arguments.targets,
		sections = sections,
		vm = arguments.vm,
		frameLimit = arguments.frameLimit,
		top = arguments.top,
		dump = arguments.dump,
		name = arguments.name,
	}, totalSeconds + 60)

	restore(originals)

	if not reached then
		return text(`couldn't run the profile in the {context}: {tostring(result)}`, true)
	end

	local body = {}
	for _, item in result.content or {} do
		if type(item.text) == "string" then
			table.insert(body, item.text)
		end
	end
	if #originals > 0 then
		table.insert(
			notes,
			`{#originals} script(s) had their Source put back; the playtest still runs the instrumented copies until it stops`
		)
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
