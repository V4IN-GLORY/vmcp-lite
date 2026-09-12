--!strict

local HttpService = game:GetService("HttpService")

local Bridge = require(script.Parent.Parent.Bridge)
local Session = require(script.Parent.Parent.Playtest.Session)

local MAX_PLAYERS = 8
local MAX_DURATION = 60
local MAX_EVENTS = 100

type Result = {
	content: { { type: "text", text: string } },
	isError: boolean?,
}

local Tool = {}

Tool.Definition = {
	name = "run_timeline",
	description = "Runs a scheduled multi-context test: a list of Luau snippets, each with a time "
		.. "and a context, fired on one clock against a real server and real clients, ending in an "
		.. "assertion. Contexts share `ctx` -- write `ctx.thing = 1` anywhere and read `ctx.thing` "
		.. 'anywhere else, or `ctx:Await("thing", 2)` to wait for it rather than hope. Client '
		.. "events also get `input`, which drives real keys and clicks through the normal input "
		.. 'path: input:Tap("W"), input:Click(x, y), input:Type(text), input:Drag(x1, y1, x2, y2). '
		.. "Every run starts its own test and tears it down after.",
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
							description = "Where it runs.",
							enum = { "server", "client" },
						},
						player = {
							type = "integer",
							description = "Which client, 1-based. Client events only; defaults to 1.",
							minimum = 1,
							maximum = MAX_PLAYERS,
						},
						code = {
							type = "string",
							description = "Luau. Runs as a function body with ctx and input in scope.",
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
				description = "How many test clients. Defaults to 1, max 8.",
				minimum = 1,
				maximum = MAX_PLAYERS,
			},
			assertion = {
				type = "string",
				description = "Luau run on the server at the end. Return true to pass.",
			},
			awaitTimeout = {
				type = "number",
				description = "Default seconds ctx:Await waits before giving up. Defaults to 5.",
				minimum = 0.1,
			},
		},
		required = { "events" },
	},
	tags = { title = "Run Timeline", destructive = true },
	timeoutMs = 180000,
}

local function text(body: string, isError: boolean?): Result
	return { content = { { type = "text", text = body } }, isError = isError }
end

local function validate(events: any): (any, string?)
	if type(events) ~= "table" or #events == 0 then
		return nil, "events must be a non-empty array"
	end
	if #events > MAX_EVENTS then
		return nil, `that's {#events} events; the cap is {MAX_EVENTS}`
	end

	local longest = 0
	for index, event in events do
		if type(event) ~= "table" then
			return nil, `events[{index}] must be an object`
		end
		if type(event.at) ~= "number" or event.at < 0 then
			return nil, `events[{index}].at must be a number of seconds`
		end
		if event.context ~= "server" and event.context ~= "client" then
			return nil, `events[{index}].context must be "server" or "client"`
		end
		if type(event.code) ~= "string" or event.code == "" then
			return nil, `events[{index}].code must be a non-empty string`
		end
		longest = math.max(longest, event.at)
	end
	return longest, nil
end

-- The report crosses a DataModel boundary as JSON, so everything below is rebuilding readable
-- text from it. Ordering comes from the stamps the writes carry, not from arrival order.
local function render(raw: string): Result
	local ok, report = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or type(report) ~= "table" then
		return text(`the test reported something unreadable: {raw}`, true)
	end

	local lines = { if report.passed then `PASS -- {report.assertion}` else `FAIL -- {report.assertion}` }

	if report.context and next(report.context) ~= nil then
		table.insert(lines, "")
		table.insert(lines, "context at the end:")
		for key, value in report.context do
			table.insert(lines, `  {key} = {tostring(value)}`)
		end
	end

	if report.writes and #report.writes > 0 then
		table.sort(report.writes, function(a, b)
			return a.at < b.at
		end)
		table.insert(lines, "")
		table.insert(lines, "writes, in the order they happened:")
		for _, write in report.writes do
			table.insert(lines, `  {write.from} set {write.key}`)
		end
	end

	for _, section in { { "notes", report.notes }, { "input problems", report.problems }, { "output", report.logs } } do
		local entries = section[2] :: any
		if entries and #entries > 0 then
			table.insert(lines, "")
			table.insert(lines, `{section[1]}:`)
			for _, entry in entries do
				table.insert(lines, `  {entry}`)
			end
		end
	end

	return { content = { { type = "text", text = table.concat(lines, "\n") } }, isError = not report.passed }
end

function Tool.Run(arguments: {
	events: any,
	duration: number?,
	players: number?,
	assertion: string?,
	awaitTimeout: number?,
}): Result
	local longest, problem = validate(arguments.events)
	if problem then
		return text(problem, true)
	end

	local connection = Bridge.Connection()
	local report, failure = Session.Start({
		mode = "timeline",
		players = math.clamp(arguments.players or 1, 1, MAX_PLAYERS),
		-- The tail runs past the last event, so the two add up rather than the payload having to
		-- state a duration longer than its own schedule.
		duration = longest + math.clamp(arguments.duration or 1, 0, MAX_DURATION),
		awaitTimeout = arguments.awaitTimeout,
		events = arguments.events,
		assertion = arguments.assertion,
		port = connection.port,
		token = connection.token,
		linkId = connection.sessionId,
	})
	if failure then
		return text(failure, true)
	end
	return render(report :: string)
end

return Tool
