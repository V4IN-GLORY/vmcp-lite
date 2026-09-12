--!nocheck

-- Copied into the place as ReplicatedStorage.VMCPHarness.Peer, started by the server harness when a
-- playtest is opened as a session rather than run as a timeline.
--
-- This is the second socket in the system. The plugin's socket speaks for the edit DataModel; this
-- one speaks for the live server, which the plugin cannot reach at all. It registers no tools --
-- Node routes a call here when the caller asked for a running game, and to the plugin otherwise.
--
-- nocheck because this runs somewhere the plugin's type definitions don't describe: `loadstring`
-- only exists when ServerScriptService.LoadStringEnabled is on, which the plugin sets before the
-- test starts and puts back after.

local HttpService = game:GetService("HttpService")

local PROTOCOL_VERSION = 3

return function(secrets)
	local folder = game:GetService("ReplicatedStorage"):WaitForChild("VMCPHarness")
	local Serialize = require(folder:WaitForChild("Serialize"))
	local LogBuffer = require(folder:WaitForChild("LogBuffer"))

	LogBuffer.Start()

	-- Survives across calls for as long as the session is open, which is the whole reason for
	-- keeping a session open instead of paying for a fresh test every time.
	local scratch = {}

	local socket = HttpService:CreateWebStreamClient(Enum.WebStreamClientType.WebSocket, {
		Url = `ws://127.0.0.1:{secrets.port}`,
	})

	local function send(message)
		local ok, encoded = pcall(HttpService.JSONEncode, HttpService, message)
		if ok then
			socket:Send(encoded)
		end
		return ok, encoded
	end

	local function textResult(text, isError)
		local result = { content = { { type = "text", text = text } } }
		if isError then
			result.isError = true
		end
		return result
	end

	local function runServerCode(code, timeout)
		if not loadstring then
			return textResult(
				"loadstring is off in this test server, so arbitrary server code can't run. "
					.. "Stop the playtest and start it again -- the plugin turns it on as it starts.",
				true
			)
		end

		local chunk, syntax = loadstring(code, "=vmcp")
		if not chunk then
			return textResult(`that didn't compile: {syntax}`, true)
		end

		local cursor = LogBuffer.written
		local done, ok, produced = false, false, nil
		local thread = task.spawn(function()
			ok, produced = pcall(chunk, scratch)
			done = true
		end)

		local deadline = os.clock() + (timeout or 10)
		while not done and os.clock() < deadline do
			task.wait()
		end
		if not done then
			pcall(task.cancel, thread)
			return textResult(`the code was still running after {timeout or 10}s and was cancelled`, true)
		end

		task.wait()
		local logged = LogBuffer.Since(cursor)
		local parts = { if ok then `returned: {Serialize.Render(produced)}` else `error: {tostring(produced)}` }
		if #logged > 0 then
			local lines = {}
			for _, entry in logged do
				table.insert(lines, `  [{entry.severity}] {entry.text}`)
			end
			table.insert(parts, `output during the run:\n{table.concat(lines, "\n")}`)
		end

		local result = textResult(table.concat(parts, "\n\n"))
		result.isError = not ok
		return result
	end

	local function handleCall(id, params)
		local arguments = params.arguments or {}
		if arguments.context == "client" then
			send({
				jsonrpc = "2.0",
				id = id,
				result = textResult(
					"client code can't be sent to a running test -- a client DataModel has no "
						.. "loadstring and its scripts aren't writable from here. Put client work in a "
						.. "run_timeline payload, which is baked in before the clients start.",
					true
				),
			})
			return
		end

		local ok, result = pcall(runServerCode, arguments.code, arguments.timeoutSeconds)
		if not ok then
			result = textResult(`the harness itself failed: {result}`, true)
		end

		local encoded, failure = send({ jsonrpc = "2.0", id = id, result = result })
		if not encoded then
			send({ jsonrpc = "2.0", id = id, result = textResult(`the result wouldn't encode: {failure}`, true) })
		end
	end

	socket.Opened:Connect(function()
		send({
			jsonrpc = "2.0",
			id = 1,
			method = "session/hello",
			params = {
				token = secrets.token,
				protocolVersion = PROTOCOL_VERSION,
				-- Its own id, but the plugin's in linkId: that pairing is what lets Node send a
				-- call for the running game here instead of to the edit session.
				sessionId = `{secrets.linkId}-peer`,
				linkId = secrets.linkId,
				role = "playtest-server",
				placeId = tostring(game.PlaceId),
				placeName = "playtest server",
				tools = {},
			},
		})
	end)

	socket.MessageReceived:Connect(function(raw)
		local decoded, message = pcall(HttpService.JSONDecode, HttpService, raw)
		if not decoded then
			return
		end
		if message.method == "tool/call" then
			-- Spawned, so a slow call doesn't hold up every message behind it.
			task.spawn(handleCall, message.id, message.params or {})
			return
		end
		if message.method == "peer/stop" then
			-- The only way a session ends from outside. The plugin can't stop a test DataModel, so
			-- the message goes the long way round and the harness ends itself.
			pcall(function()
				socket:Close()
			end);
			(game:GetService("StudioTestService") :: any):EndTest("stopped")
		end
	end)

	socket.Error:Connect(function(status, reason)
		warn(`[VMCP peer] socket error {status}: {reason}`)
	end)
end
