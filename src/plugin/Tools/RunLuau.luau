--!strict

-- The broad one. Everything the narrow builders would have done is a snippet through here.

local Bridge = require(script.Parent.Parent.Bridge)
local Buffer = require(script.Parent.Parent.Log.Buffer)
local Inject = require(script.Parent.Parent.Exec.Inject)
local Serialize = require(script.Parent.Parent.Exec.Serialize)
local Session = require(script.Parent.Parent.Playtest.Session)

-- What a snippet sees as its `vmcp` argument. The library is handed over rather than left to be
-- required, because a snippet has no sensible path to the plugin's own tree.
local Lib = {
	Anim = require(script.Parent.Parent.Lib.Anim),
	Canvas = require(script.Parent.Parent.Lib.Canvas),
	Rig = require(script.Parent.Parent.Lib.Rig),
	Serialize = Serialize,
	Style = require(script.Parent.Parent.Lib.Style),
}

local MAX_TIMEOUT = 60

type Result = {
	content: { { type: "text", text: string } },
	isError: boolean?,
	postProcess: { [string]: any }?,
}

local Tool = {}

Tool.Definition = {
	name = "run_luau",
	description = "Runs Luau and returns what it returned plus anything it printed. `return` a "
		.. "value to see it -- Instances, CFrames and nested tables all come back readable. "
		.. "Context \"plugin\" is Studio's edit session with the plugin's permissions: game, "
		.. 'Instance.new, the plugin APIs, the lot, but no running game. Context "server" is a '
		.. "real game server: instant if a playtest is already open, otherwise it starts one just "
		.. "for this call, which takes several seconds. Client code can't be sent to a running "
		.. "game at all -- use run_timeline for that.",
	inputSchema = {
		type = "object",
		properties = {
			code = {
				type = "string",
				description = "Luau source. Runs as a function body, so `return` works and is "
					.. "how you get a value back. `vmcp` holds the library: vmcp.Rig reads a model's "
					.. "real Motor6D graph, vmcp.Anim compiles per-joint tracks into a playable "
					.. "animation, vmcp.Canvas draws an image and records it for the server to write "
					.. "out as a PNG, vmcp.Style catches property names StyleRule would drop in "
					.. "silence, and vmcp.Serialize.Render makes any value readable.",
			},
			context = {
				type = "string",
				description = "Where to run it. Defaults to plugin.",
				enum = { "plugin", "server" },
			},
			timeoutSeconds = {
				type = "number",
				description = "Give up after this long. Defaults to 10, max 60.",
				minimum = 1,
				maximum = MAX_TIMEOUT,
			},
		},
		required = { "code" },
	},
	tags = { title = "Run Luau", destructive = true },
	timeoutMs = 70000,
}

-- Reached only when nobody has a playtest open -- with one running, the VMCP server routes a
-- server-context call to the live peer and this file never sees it. The code goes in as a
-- one-event timeline, which means a whole test DataModel spins up and tears down per call.
local function oneShotServer(code: string, timeout: number): Result
	local connection = Bridge.Connection()
	local report, failure = Session.Start({
		mode = "timeline",
		players = 1,
		duration = 0,
		events = {
			{
				at = 0,
				context = "server",
				blocking = true,
				label = "run_luau",
				-- Routed through ctx because a timeline only reports what the context holds at the
				-- end; the event's own return value has nowhere else to go.
				code = 'local S = require(game:GetService("ReplicatedStorage").VMCPHarness.Serialize)\n'
					.. "local ok, value = pcall(function() "
					.. code
					.. "\nend)\n"
					.. 'ctx.result = (if ok then "returned: " else "error: ") .. S.Render(value)',
			},
		},
		assertion = "return true",
		port = connection.port,
		token = connection.token,
		linkId = connection.sessionId,
	})
	if failure then
		return { content = { { type = "text", text = failure } }, isError = true }
	end

	local ok, decoded = pcall(function()
		return game:GetService("HttpService"):JSONDecode(report :: string)
	end)
	if not ok or type(decoded) ~= "table" then
		return {
			content = { { type = "text", text = `the test reported something unreadable: {report}` } },
			isError = true,
		}
	end

	local parts = { tostring((decoded.context or {}).result or "the code never reported a result") }
	if decoded.logs and #decoded.logs > 0 then
		table.insert(parts, "output during the run:\n  " .. table.concat(decoded.logs, "\n  "))
	end
	return { content = { { type = "text", text = table.concat(parts, "\n\n") } } }
end

function Tool.Run(arguments: { code: string?, context: string?, timeoutSeconds: number? }): Result
	local code = arguments.code
	if type(code) ~= "string" or code == "" then
		return { content = { { type = "text", text = "code must be a non-empty string" } }, isError = true }
	end

	local timeout = math.clamp(arguments.timeoutSeconds or 10, 1, MAX_TIMEOUT)
	if arguments.context == "client" then
		return {
			content = {
				{
					type = "text",
					text = "client code can't be injected into a running game -- a client DataModel "
						.. "has no loadstring and its scripts aren't writable from a plugin. Put it in "
						.. "a run_timeline payload instead, where it's baked in before the client starts.",
				},
			},
			isError = true,
		}
	end
	if arguments.context == "server" then
		return oneShotServer(code, timeout)
	end
	local cursor = Buffer.written
	local ok, produced = Inject.Run(code, Lib, timeout)

	-- MessageOut lands a frame after the print that caused it, so without this the snippet's last
	-- line of output is always missing.
	task.wait()
	local logged = Buffer.Since(cursor)

	-- A snippet asks for work on the VMCP server -- writing a Canvas recording out as a PNG, so
	-- far -- by returning a table with a postProcess field. It rides back on the result untouched.
	local directive = if ok and type(produced) == "table" then produced.postProcess else nil

	local parts = {}
	if directive then
		table.insert(parts, `returned a {tostring(directive.kind)} job for the VMCP server to finish.`)
	elseif ok then
		table.insert(parts, `returned: {Serialize.Render(produced)}`)
	else
		table.insert(parts, `error: {tostring(produced)}`)
	end

	if #logged > 0 then
		local lines = {}
		for _, entry in logged do
			table.insert(lines, `  [{entry.severity}] {entry.text}`)
		end
		-- Studio logs everything to one place, so a noisy game script can land in here too.
		table.insert(parts, `output during the run:\n{table.concat(lines, "\n")}`)
	end

	return {
		content = { { type = "text", text = table.concat(parts, "\n\n") } },
		isError = not ok,
		postProcess = directive,
	}
end

return Tool
