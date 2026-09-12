--!strict

-- Copied into the place as ReplicatedStorage.VMCPHarness.ClientHarness and called by a one-line
-- LocalScript in StarterPlayerScripts. One of these runs per test client.
--
-- Client code is baked in ahead of time rather than sent over during the run, because a client
-- DataModel has no loadstring and a LocalScript's Source is only writable from a plugin, which
-- this isn't. Whatever the timeline declares is all a client can ever do.

local LogService = game:GetService("LogService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MAX_LOG_LINES = 100
local START_TIMEOUT = 30

return function()
	local folder = ReplicatedStorage:WaitForChild("VMCPHarness")
	local Runtime = require(folder:WaitForChild("Runtime")) :: any
	local payload = require(folder:WaitForChild("Payload")) :: any
	local link = folder:WaitForChild("Link") :: RemoteEvent
	local config = payload.config

	-- A session has no client half: nothing can reach a running client with new code.
	if config.mode == "session" then
		return
	end

	local logs: { string } = {}
	local index: number? = nil
	local go = false
	-- Declared before the connection that reads it: the closure captures the variable, so the
	-- context it points at by the time a message arrives is the real one.
	local ctx: any = nil

	link.OnClientEvent:Connect(function(kind: string, a: any, b: any)
		if kind == "index" then
			index = a
		elseif kind == "go" then
			go = true
		elseif kind == "set" then
			Runtime.Receive(ctx, a, b)
		end
	end)

	ctx = Runtime.Context("client", function(key: string, value: any)
		link:FireServer("set", key, value)
	end, config.awaitTimeout)

	link:FireServer("ready")

	local deadline = os.clock() + START_TIMEOUT
	while (not go or index == nil) and os.clock() < deadline do
		task.wait()
	end
	if not go then
		link:FireServer("done", { "[client] never got the start signal" }, {}, {})
		return
	end

	local me = index or 1
	ctx:Note(`client {me} starting`)
	LogService.MessageOut:Connect(function(text: string, messageType: Enum.MessageType)
		if #logs < MAX_LOG_LINES then
			local tag = if messageType == Enum.MessageType.MessageError then "error" else `client{me}`
			table.insert(logs, `[{tag}] {text}`)
		end
	end)

	local input = Runtime.Input()
	local events = (payload.client or {})[me] or {}

	local function note(text: string)
		ctx:Note(`client {me}: {text}`)
	end

	local ok, err = pcall(Runtime.Run, events, ctx, input, config.duration or 0, note)
	if not ok then
		note(`the run itself failed: {err}`)
	end

	-- Always, however the run ended: a key still down here would carry into whatever the test
	-- does next, and there is no second chance to release it.
	input:ReleaseEverything()
	link:FireServer("done", Runtime.Notes(ctx), input.problems, logs)
end
