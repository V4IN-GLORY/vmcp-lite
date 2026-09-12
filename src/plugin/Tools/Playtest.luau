--!strict

local Bridge = require(script.Parent.Parent.Bridge)
local Session = require(script.Parent.Parent.Playtest.Session)

local MAX_PLAYERS = 8

type Result = {
	content: { { type: "text", text: string } },
	isError: boolean?,
}

local Tool = {}

Tool.Definition = {
	name = "playtest",
	description = "Starts, stops or reports on a live playtest, and leaves it running between "
		.. "calls. While one is open, run_luau with context server or client runs inside the real "
		.. "game instead of paying to start one each time, and run_timeline uses it rather than "
		.. "launching its own. One player gets Play Solo, which is much quicker to start; two or "
		.. "more gets a real multiplayer test. One playtest per Studio window.",
	inputSchema = {
		type = "object",
		properties = {
			action = {
				type = "string",
				description = "start opens a playtest, stop ends it, status says what's running.",
				enum = { "start", "stop", "status" },
			},
			players = {
				type = "integer",
				description = "How many test clients to launch. Defaults to 1, max 8.",
				minimum = 1,
				maximum = MAX_PLAYERS,
			},
		},
		required = { "action" },
	},
	tags = { title = "Playtest", destructive = true },
	-- Launching a server plus clients is slow enough that the default would trip on a cold start.
	timeoutMs = 120000,
}

local function text(body: string, isError: boolean?): Result
	return { content = { { type = "text", text = body } }, isError = isError }
end

function Tool.Run(arguments: { action: string?, players: number? }): Result
	local action = arguments.action

	if action == "status" then
		local status = Session.Status()
		if not status.running then
			return text("No playtest is running.")
		end
		local whose = if status.ours then "" else " (started outside VMCP)"
		return text(`A playtest has been running for {status.seconds}s{whose}.`)
	end

	if action == "stop" then
		if not Session.IsRunning() then
			return text("No playtest is running.")
		end
		-- EndTest only works from inside the test server, and the edit session isn't it. The call
		-- goes out to the VMCP server and back into the running game's own copy of the plugin.
		local reached, result = Bridge.Invoke("peer", { action = "stop", context = "server" }, 20)
		Session.Forget()
		if not reached then
			return text(`couldn't reach the test server to stop it: {tostring(result)}`, true)
		end
		return text("Asked the playtest to stop. Check status in a second or two.")
	end

	if action ~= "start" then
		return text(`action must be start, stop or status -- got "{tostring(action)}"`, true)
	end

	local failure = Session.Start(math.clamp(arguments.players or 1, 1, MAX_PLAYERS))
	if failure then
		return text(failure, true)
	end

	return text(
		"Playtest starting. Give it a few seconds, then run_luau with context server or client "
			.. "runs inside it, sharing the require cache with the game's own scripts when you ask "
			.. "for the game VM."
	)
end

return Tool
