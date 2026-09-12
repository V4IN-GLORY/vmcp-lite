--!strict
--!optimize 2

-- Routes one decoded message from the server. Everything here is guarded: an error thrown out
-- of the socket's MessageReceived callback kills the callback, not the socket, and the server
-- then sits waiting until the call times out. A crash has to become an isError reply instead.

local Registry = require(script.Parent.Registry)

local Dispatch = {}

-- Returns false plus the reason when the message could not be encoded, which is the only way
-- sending fails and would otherwise be silent.
type Send = (message: { [string]: any }) -> (boolean, string?)

local function textResult(text: string, isError: boolean?): { [string]: any }
	local result: { [string]: any } = { content = { { type = "text", text = text } } }
	if isError then
		result.isError = true
	end
	return result
end

-- How deep the tool on this thread already is. A tool calling another tool passes the count on so
-- the server can tell a chain from a loop. Weak keys so a finished call isn't held alive.
local depthByThread: { [thread]: number } = setmetatable({}, { __mode = "k" }) :: any

function Dispatch.CurrentDepth(): number
	return depthByThread[coroutine.running()] or 0
end

local function runTool(send: Send, id: any, name: string, arguments: any)
	depthByThread[coroutine.running()] = if type(arguments) == "table" and type(arguments.__depth) == "number"
		then arguments.__depth
		else 0

	local tool = Registry.byName[name]
	if not tool then
		send({ jsonrpc = "2.0", id = id, result = textResult(`no tool named "{name}"`, true) })
		return
	end

	local ok, returned = pcall(tool.Run, arguments or {})
	if not ok then
		send({ jsonrpc = "2.0", id = id, result = textResult(`{name} errored: {returned}`, true) })
		return
	end

	-- A non-table result rides the server's documented shorthand; a table goes through untouched
	-- and the server coerces it. Encoding can still fail -- a tool returning an Instance, say --
	-- and Claude would otherwise just see the call time out.
	local result = if type(returned) == "table" then returned else textResult(tostring(returned or "done"))
	local encoded, failure = send({ jsonrpc = "2.0", id = id, result = result })
	if not encoded then
		send({ jsonrpc = "2.0", id = id, result = textResult(`{name} returned something unencodable: {failure}`, true) })
	end
end

function Dispatch.Handle(send: Send, message: { [string]: any })
	if message.method == "tool/call" then
		local params = message.params or {}
		-- Spawned: a yielding tool would otherwise block every later message on this socket.
		task.spawn(runTool, send, message.id, params.name, params.arguments)
		return
	end

	if message.error then
		warn(`[VMCP] server refused request {message.id}: {message.error.message}`)
	end
end

return Dispatch
