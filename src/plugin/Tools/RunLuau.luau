--!strict

-- The broad one. Everything the narrow builders would have done is a snippet through here.
--
-- Where it runs is the server's business, not this file's: a call naming a live context is routed
-- to the copy of the plugin loaded into that DataModel, and this same code runs there. So the only
-- choice left here is which VM inside that DataModel -- the plugin's, or the game's own.

local Buffer = require(script.Parent.Parent.Log.Buffer)
local Env = require(script.Parent.Parent.Env)
local GameVm = require(script.Parent.Parent.Exec.GameVm)
local Inject = require(script.Parent.Parent.Exec.Inject)
local Serialize = require(script.Parent.Parent.Exec.Serialize)

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
		.. "context picks the DataModel: plugin is Studio's edit session, server and client are a "
		.. "live playtest (start one with the playtest tool first). vm picks which VM inside it: "
		.. "plugin is the default and can reach everything, game shares the require cache with the "
		.. "running game's own scripts, which is the only way to see the real state a module has "
		.. "built up. `vmcp` holds the library, and vmcp.Tool calls any other VMCP tool.",
	inputSchema = {
		type = "object",
		properties = {
			code = {
				type = "string",
				description = "Luau source. Runs as a function body, so `return` works and is how "
					.. "you get a value back.",
			},
			context = {
				type = "string",
				description = "Which DataModel. Defaults to plugin.",
				enum = { "plugin", "server", "client" },
			},
			player = {
				type = "integer",
				description = "Which test client, 1-based. Only meaningful with context client.",
				minimum = 1,
				maximum = 8,
			},
			vm = {
				type = "string",
				description = "plugin (default) or game. game shares the running scripts' require "
					.. "cache, so require(SomeModule) hands back the live one rather than a fresh "
					.. "copy. Needs a playtest, and the result is rendered to text on the game's "
					.. "side, so only the text comes back.",
				enum = { "plugin", "game" },
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

function Tool.Run(arguments: { code: string?, vm: string?, timeoutSeconds: number? }): Result
	local code = arguments.code
	if type(code) ~= "string" or code == "" then
		return { content = { { type = "text", text = "code must be a non-empty string" } }, isError = true }
	end

	local timeout = math.clamp(arguments.timeoutSeconds or 10, 1, MAX_TIMEOUT)
	local cursor = Buffer.written

	local ok: boolean
	local rendered: string
	local directive: { [string]: any }? = nil

	if arguments.vm == "game" then
		ok, rendered = GameVm.Run(code)
	else
		local produced: any
		ok, produced = Inject.Run(code, Env, timeout)
		-- A snippet asks for work on the VMCP server -- writing a capture out as a file -- by
		-- returning a table with a postProcess field. It rides back untouched.
		directive = if ok and type(produced) == "table" then produced.postProcess else nil

		if directive then
			rendered = `a {tostring(directive.kind)} job for the VMCP server to finish`
		elseif ok then
			rendered = Serialize.Render(produced)
		else
			rendered = tostring(produced)
		end
	end

	-- MessageOut lands a frame after the print that caused it, so without this the snippet's last
	-- line of output is always missing.
	task.wait()
	local logged = Buffer.Since(cursor)

	local parts = { if ok then `returned: {rendered}` else `error: {rendered}` }
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
