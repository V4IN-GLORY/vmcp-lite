--!strict

local Bridge = require(script.Parent.Parent.Bridge)
local Inject = require(script.Parent.Parent.Exec.Inject)
local Runtime = require(script.Parent.Parent.Timeline.Runtime)
local Session = require(script.Parent.Parent.Playtest.Session)

local MAX_PLAYERS = 8
local MAX_DURATION = 60
local MAX_EVENTS = 200
local PEER_TIMEOUT = 90

type Result = {
	content: { { type: "text", text: string } },
	isError: boolean?,
}

local Tool = {}

Tool.Definition = {
	name = "run_timeline",
	description = "Runs a batched test: one list of Luau snippets, each with a time and a context, "
		.. "fired on a shared clock across Studio itself, a real server and real clients, ending in "
		.. "an assertion. Contexts share ctx -- write ctx.thing = 1 anywhere and read ctx.thing "
		.. 'anywhere else, or ctx:Await("thing", 2) to wait for it rather than hope. Every event '
		.. "also gets vmcp: vmcp.Tool calls any other VMCP tool in any context, vmcp.Game.Require "
		.. "reads a live module's real state, vmcp.Remotes watches remote traffic, vmcp.Exploit "
		.. "spams and fuzzes remotes, vmcp.Bench times a function under load. Client events also "
		.. "get input, for real keys and clicks. Starts its own playtest if one isn't already open.",
	inputSchema = {
		type = "object",
		properties = {
			events = {
				type = "array",
				description = "What happens and when.",
				items = {
					type = "object",
					properties = {
						at = { type = "number", description = "Seconds after the start.", minimum = 0 },
						context = {
							type = "string",
							description = "plugin is Studio's edit session; server and client are the live game.",
							enum = { "plugin", "server", "client" },
						},
						player = {
							type = "integer",
							description = "Which client, 1-based. Client events only; defaults to 1.",
							minimum = 1,
							maximum = MAX_PLAYERS,
						},
						code = {
							type = "string",
							description = "Luau. Runs as a function body with ctx, input and vmcp in scope.",
						},
						blocking = {
							type = "boolean",
							description = "Hold the schedule until this finishes. For setup steps.",
						},
						label = { type = "string", description = "Name for the log." },
					},
					required = { "at", "context", "code" },
				},
			},
			duration = {
				type = "number",
				description = "Seconds to keep running after the last event, so trailing effects land.",
				minimum = 0,
				maximum = MAX_DURATION,
			},
			players = {
				type = "integer",
				description = "Test clients to launch, if a playtest isn't already open. Defaults to 1.",
				minimum = 1,
				maximum = MAX_PLAYERS,
			},
			assertion = {
				type = "string",
				description = "Luau run in Studio at the end, with ctx in scope. Return true to pass.",
			},
			keepOpen = {
				type = "boolean",
				description = "Leave the playtest running afterwards instead of stopping it.",
			},
		},
		required = { "events" },
	},
	tags = { title = "Run Timeline", destructive = true },
	timeoutMs = 300000,
}

local function text(body: string, isError: boolean?): Result
	return { content = { { type = "text", text = body } }, isError = isError }
end

local function validate(events: any): (number, string?)
	if type(events) ~= "table" or #events == 0 then
		return 0, "events must be a non-empty array"
	end
	if #events > MAX_EVENTS then
		return 0, `that's {#events} events; the cap is {MAX_EVENTS}`
	end

	local longest = 0
	for index, event in events do
		if type(event) ~= "table" then
			return 0, `events[{index}] must be an object`
		end
		if type(event.at) ~= "number" or event.at < 0 then
			return 0, `events[{index}].at must be a number of seconds`
		end
		local context = event.context
		if context ~= "plugin" and context ~= "server" and context ~= "client" then
			return 0, `events[{index}].context must be plugin, server or client`
		end
		if type(event.code) ~= "string" or event.code == "" then
			return 0, `events[{index}].code must be a non-empty string`
		end
		longest = math.max(longest, event.at)
	end
	return longest, nil
end

type Bundle = { context: string, player: number?, origin: string, events: { any } }

-- One bundle per DataModel. A client event names its player, so two clients are two bundles and
-- each one only ever hears about its own events.
local function split(events: { any }): { Bundle }
	local parts: { Bundle } = {}
	local byKey: { [string]: Bundle } = {}

	for _, event in events do
		local player = if event.context == "client" then (event.player or 1) else nil
		local key = if player then `client{player}` else event.context
		local part = byKey[key]
		if not part then
			local created: Bundle = {
				context = event.context,
				player = player,
				origin = if player then `client {player}` else event.context,
				events = {},
			}
			byKey[key] = created
			table.insert(parts, created)
			part = created
		end
		table.insert((part :: Bundle).events, event)
	end
	return parts
end

-- A playtest DataModel takes a few seconds to boot and connect, and there's no event for it: the
-- edit session only finds out by asking the server whether anyone has answered yet.
local function waitForPeers(parts: { Bundle }): string?
	local deadline = os.clock() + PEER_TIMEOUT
	for _, part in parts do
		if part.context == "plugin" then
			continue
		end

		local up = false
		local last = "never answered"
		repeat
			local reached, result = Bridge.Invoke("peer", {
				action = "ping",
				context = part.context,
				player = part.player,
			}, 10)
			up = reached and result ~= nil and result.isError ~= true
			if not up then
				last = if reached then "not up yet" else tostring(result)
				task.wait(0.5)
			end
		until up or os.clock() >= deadline

		if not up then
			return `{part.origin} never came up ({last})`
		end
	end
	return nil
end

-- Run in the edit session, after everything else has stopped, against the context as it finally
-- stands. Keeping it out of the timeline is the point: it judges the run, it isn't part of it.
local function runAssertion(source: string): (boolean, string)
	local run, problem = Inject.Compile(source, "ctx, input, vmcp")
	if not run then
		return false, `the assertion didn't compile: {problem}`
	end

	local env = require(script.Parent.Parent.Env)
	local ok, produced = pcall(run, Runtime.Context("assertion"), nil, env)
	if not ok then
		return false, `the assertion errored: {produced}`
	end
	if produced == true then
		return true, "assertion passed"
	end
	return false, `assertion returned {tostring(produced)}`
end

local function render(passed: boolean, verdict: string, snapshot: any): Result
	local lines = { if passed then `PASS -- {verdict}` else `FAIL -- {verdict}` }

	if snapshot and snapshot.values and next(snapshot.values) ~= nil then
		table.insert(lines, "")
		table.insert(lines, "context at the end:")
		for key, value in snapshot.values do
			table.insert(lines, `  {key} = {tostring(value)}`)
		end
	end

	if snapshot and snapshot.writes and #snapshot.writes > 0 then
		table.insert(lines, "")
		table.insert(lines, "writes, in the order they happened:")
		for _, write in snapshot.writes do
			table.insert(lines, `  {write.from} set {write.key}`)
		end
	end

	if snapshot and snapshot.notes and #snapshot.notes > 0 then
		table.insert(lines, "")
		table.insert(lines, "notes and output:")
		for _, note in snapshot.notes do
			table.insert(lines, `  {note}`)
		end
	end

	return { content = { { type = "text", text = table.concat(lines, "\n") } }, isError = not passed }
end

function Tool.Run(arguments: {
	events: any,
	duration: number?,
	players: number?,
	assertion: string?,
	keepOpen: boolean?,
}): Result
	local longest, problem = validate(arguments.events)
	if problem then
		return text(problem, true)
	end

	local parts = split(arguments.events)
	local needsGame = false
	for _, part in parts do
		needsGame = needsGame or part.context ~= "plugin"
	end

	-- Started only if the payload actually needs a running game, and stopped again only if this
	-- call is what started it. A playtest someone else opened stays open.
	local weStarted = false
	if needsGame and not Session.IsRunning() then
		local failure = Session.Start(math.clamp(arguments.players or 1, 1, MAX_PLAYERS))
		if failure then
			return text(failure, true)
		end
		weStarted = true
	end

	local function finish(result: Result): Result
		if weStarted and not arguments.keepOpen then
			Bridge.Invoke("peer", { action = "stop", context = "server" }, 20)
			Session.Forget()
		end
		return result
	end

	local waited = waitForPeers(parts)
	if waited then
		return finish(text(waited, true))
	end

	Bridge.CtxClear()
	-- The tail runs past the last event, so the two add up rather than the payload having to state
	-- a duration longer than its own schedule.
	local duration = longest + math.clamp(arguments.duration or 1, 0, MAX_DURATION)

	local running = 0
	local failures: { string } = {}
	for _, part in parts do
		running += 1
		task.spawn(function()
			local reached, result = Bridge.Invoke("timeline_part", {
				context = part.context,
				player = part.player,
				origin = part.origin,
				events = part.events,
				duration = duration,
			}, duration + 60)

			if not reached then
				table.insert(failures, `{part.origin}: {tostring(result)}`)
			elseif result.isError then
				table.insert(failures, `{part.origin}: {result.content[1].text}`)
			end
			running -= 1
		end)
	end

	local deadline = os.clock() + duration + 90
	while running > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
	if running > 0 then
		table.insert(failures, `{running} context(s) never finished`)
	end

	local snapshot = Bridge.CtxSnapshot()
	for _, failure in failures do
		if snapshot and snapshot.notes then
			table.insert(snapshot.notes, failure)
		end
	end

	local passed, verdict = true, "no assertion"
	if arguments.assertion then
		passed, verdict = runAssertion(arguments.assertion)
	elseif #failures > 0 then
		passed, verdict = false, "no assertion given, and a context failed"
	end

	return finish(render(passed, verdict, snapshot))
end

return Tool
