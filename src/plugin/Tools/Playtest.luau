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
		.. 'calls. While one is open, run_luau with context = "server" goes straight to the '
		.. "running game instead of paying for a fresh test each time, and anything it leaves in "
		.. "the scratch table is still there on the next call. One test per Studio window.",
	inputSchema = {
		type = "object",
		properties = {
			action = {
				type = "string",
				description = "start opens a session, stop ends it, status says what's running.",
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
		return text(`A {status.mode} playtest has been running for {status.seconds}s with {status.players} client(s).`)
	end

	if action == "stop" then
		if not Session.Status().running then
			return text("No playtest is running.")
		end
		-- The long way round: plugin -> VMCP server -> the test's own socket, because nothing here
		-- can reach a test DataModel to stop it.
		if not Bridge.Notify("peer/stop", {}) then
			return text("couldn't reach the VMCP server to pass the stop along", true)
		end
		return text("Asked the playtest to stop. Check status in a second or two.")
	end

	if action ~= "start" then
		return text(`action must be start, stop or status -- got "{tostring(action)}"`, true)
	end

	local connection = Bridge.Connection()
	if not connection.port or not connection.token then
		return text("the plugin isn't connected, so the test server would have nothing to call back to", true)
	end

	local _, problem = Session.Start({
		mode = "session",
		players = math.clamp(arguments.players or 1, 1, MAX_PLAYERS),
		duration = 0,
		events = {},
		port = connection.port,
		token = connection.token,
		linkId = connection.sessionId,
	})
	if problem then
		return text(problem, true)
	end

	return text(
		'Playtest started. run_luau with context = "server" now runs against the live server; '
			.. "its second argument is a scratch table that survives between calls."
	)
end

return Tool
