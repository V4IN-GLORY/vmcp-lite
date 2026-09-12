--!strict

-- Plumbing: the half of run_timeline that runs inside one DataModel. Tagged internal, so it never
-- shows up in the tool list -- run_timeline invokes it once per context, and the server routes
-- each call to the right place.

local RunService = game:GetService("RunService")

local Bridge = require(script.Parent.Parent.Bridge)
local Buffer = require(script.Parent.Parent.Log.Buffer)
local Env = require(script.Parent.Parent.Env)
local Inject = require(script.Parent.Parent.Exec.Inject)
local Runtime = require(script.Parent.Parent.Timeline.Runtime)

local MAX_LOG_LINES = 60

type Result = {
	content: { { type: "text", text: string } },
	isError: boolean?,
}

local Tool = {}

Tool.Definition = {
	name = "timeline_part",
	description = "Internal. Runs one context's share of a timeline.",
	inputSchema = {
		type = "object",
		properties = {
			events = { type = "array", items = { type = "object" } },
			duration = { type = "number" },
			origin = { type = "string" },
			context = { type = "string", enum = { "plugin", "server", "client" } },
			player = { type = "integer", minimum = 1 },
		},
		required = { "events" },
	},
	tags = { title = "Timeline Part", internal = true },
	timeoutMs = 300000,
}

function Tool.Run(arguments: { events: any, duration: number?, origin: string? }): Result
	local events = arguments.events
	if type(events) ~= "table" then
		return { content = { { type = "text", text = "events must be an array" } }, isError = true }
	end

	local connection = Bridge.Connection()
	local origin = arguments.origin or connection.role
	local ctx = Runtime.Context(origin)

	-- Compiled up front, all of them, before the clock starts: an event that doesn't compile
	-- should stop the run rather than fire a hole in the middle of it.
	local compiled: { Runtime.Event } = {}
	for index, spec in events do
		local run, problem = Inject.Compile(spec.code, "ctx, input, vmcp")
		if not run then
			local label = spec.label or `events[{index}]`
			return {
				content = { { type = "text", text = `{label} didn't compile: {problem}` } },
				isError = true,
			}
		end
		table.insert(compiled, { at = spec.at, blocking = spec.blocking, label = spec.label, run = run })
	end

	-- Input only exists on a client: UserInputService is client-side, and a virtual keypress on
	-- the server would have nothing to press against.
	local input = if RunService:IsClient() then Runtime.Input() else nil
	local cursor = Buffer.written

	Runtime.Run(compiled, ctx, input, Env, arguments.duration or 0, function(text: string)
		ctx:Note(text)
	end)

	if input then
		input:ReleaseEverything()
		for _, problem in input.problems do
			ctx:Note(`input: {problem}`)
		end
	end

	-- Output goes back as context notes rather than in this reply, because run_timeline reads the
	-- context and never sees the individual replies.
	task.wait()
	local logged = Buffer.Since(cursor)
	for index, entry in logged do
		if index > MAX_LOG_LINES then
			ctx:Note(`... and {#logged - MAX_LOG_LINES} more lines of output`)
			break
		end
		ctx:Note(`[{entry.severity}] {entry.text}`)
	end

	return { content = { { type = "text", text = `{origin} ran {#compiled} event(s)` } } }
end

return Tool
