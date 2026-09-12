--!strict

-- Copied into the place as ReplicatedStorage.VMCPHarness.ServerHarness and called by a one-line
-- Script in ServerScriptService. Runs inside the test server DataModel, which the plugin cannot reach at
-- all -- everything the plugin knows about a run comes back through EndTest.
--
-- Never required by the plugin; it only reads the Source. It stays a ModuleScript here so
-- luau-lsp checks it like anything else.

local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MAX_LOG_LINES = 300
-- How long to wait for the clients to say hello before giving up and running without them.
local READY_TIMEOUT = 20
-- Grace after the server's own events finish, for clients still working through theirs.
local CLIENT_GRACE = 10

type Report = {
	passed: boolean,
	assertion: string,
	notes: { string },
	writes: { { at: number, from: string, key: string } },
	problems: { string },
	logs: { string },
	context: { [string]: any },
}

-- `secrets` carries the socket details, handed over by the boot script rather than read from the
-- payload: the payload replicates to clients and the token has no business going there.
return function(secrets: { [string]: any }?)
	local folder = ReplicatedStorage:WaitForChild("VMCPHarness")
	local Runtime = require(folder:WaitForChild("Runtime")) :: any
	local payload = require(folder:WaitForChild("Payload")) :: any
	local link = folder:WaitForChild("Link") :: RemoteEvent
	local config = payload.config

	-- Two ways to run: a timeline plays a fixed script and reports through EndTest, a session
	-- opens a socket and waits to be told what to do. Everything below here is the timeline.
	if config.mode == "session" then
		(require(folder:WaitForChild("Peer")) :: any)(secrets or {})
		return
	end

	local logs: { string } = {}
	LogService.MessageOut:Connect(function(text: string, messageType: Enum.MessageType)
		if #logs < MAX_LOG_LINES then
			local tag = if messageType == Enum.MessageType.MessageError then "error" else "server"
			table.insert(logs, `[{tag}] {text}`)
		end
	end)

	-- The server is the only holder of the real context; a client's write arrives here, lands in
	-- the table, and goes back out to the others. That keeps one ordering for everyone.
	local ctx
	ctx = Runtime.Context("server", function(key: string, value: any)
		link:FireAllClients("set", key, value)
	end)

	local indexByPlayer: { [Player]: number } = {}
	local ready = 0
	local finished = 0
	local clientProblems: { string } = {}

	link.OnServerEvent:Connect(function(player: Player, kind: string, a: any, b: any, c: any)
		if kind == "ready" then
			ready += 1
			indexByPlayer[player] = ready
			link:FireClient(player, "index", ready)
			return
		end
		if kind == "set" then
			Runtime.Receive(ctx, a, b)
			-- Back out to everyone else so all contexts converge, the sender included: its own
			-- mirror already has it, so a second copy changes nothing.
			link:FireAllClients("set", a, b)
			return
		end
		if kind == "done" then
			finished += 1
			for _, note in a or {} do
				table.insert(Runtime.Notes(ctx), note)
			end
			for _, problem in b or {} do
				table.insert(clientProblems, problem)
			end
			for _, line in c or {} do
				if #logs < MAX_LOG_LINES then
					table.insert(logs, line)
				end
			end
		end
	end)

	local function note(text: string)
		table.insert(Runtime.Notes(ctx), `[server] {text}`)
	end

	local expected = math.max(config.players or 1, 0)
	local deadline = os.clock() + READY_TIMEOUT
	while ready < expected and os.clock() < deadline do
		task.wait()
	end
	if ready < expected then
		note(`only {ready} of {expected} client(s) ever connected`)
	end

	link:FireAllClients("go")
	Runtime.Run(payload.server or {}, ctx, nil, config.duration or 0, note)

	-- The clients run the same duration but started a moment later, so a short grace here is the
	-- difference between collecting their results and reporting a run that looks half-empty.
	local clientDeadline = os.clock() + CLIENT_GRACE
	while finished < ready and os.clock() < clientDeadline do
		task.wait()
	end
	if finished < ready then
		note(`{ready - finished} client(s) never reported back`)
	end

	local passed, assertion = true, "no assertion"
	if payload.assertion then
		local ok, result = pcall(payload.assertion, ctx, nil)
		if not ok then
			passed, assertion = false, `assertion errored: {result}`
		else
			passed = result == true
			assertion = if passed then "assertion passed" else `assertion returned {tostring(result)}`
		end
	end

	local report: Report = {
		passed = passed,
		assertion = assertion,
		notes = Runtime.Notes(ctx),
		writes = Runtime.Writes(ctx),
		problems = clientProblems,
		logs = logs,
		context = ctx:Snapshot(),
	}

	-- EndTest crosses a DataModel boundary, so the value goes over as a string rather than
	-- trusting a table to survive the trip intact.
	local encoded = HttpService:JSONEncode(report)
	local testService = game:GetService("StudioTestService") :: any
	testService:EndTest(encoded)
end
