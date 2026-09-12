--!strict

-- The broad one. Everything the narrow builders would have done is a snippet through here.

local Buffer = require(script.Parent.Parent.Log.Buffer)
local Inject = require(script.Parent.Parent.Exec.Inject)
local Serialize = require(script.Parent.Parent.Exec.Serialize)

local MAX_TIMEOUT = 60

type Result = {
	content: { { type: "text", text: string } },
	isError: boolean?,
}

local Tool = {}

Tool.Definition = {
	name = "run_luau",
	description = "Runs Luau inside Studio's edit session, with the plugin's permissions, and "
		.. "returns what it returned plus anything it printed. `return` a value to see it -- "
		.. "Instances, CFrames and nested tables all come back readable. Everything the plugin "
		.. "can reach is reachable: game, plugin APIs, Instance.new, the lot. This runs in edit "
		.. "mode only; it is not a running game server.",
	inputSchema = {
		type = "object",
		properties = {
			code = {
				type = "string",
				description = "Luau source. Runs as a function body, so `return` works and is "
					.. "how you get a value back. `vmcp.Serialize.Render(value)` is available.",
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

function Tool.Run(arguments: { code: string?, timeoutSeconds: number? }): Result
	local code = arguments.code
	if type(code) ~= "string" or code == "" then
		return { content = { { type = "text", text = "code must be a non-empty string" } }, isError = true }
	end

	local timeout = math.clamp(arguments.timeoutSeconds or 10, 1, MAX_TIMEOUT)
	local cursor = Buffer.written
	local ok, produced = Inject.Run(code, { Serialize = Serialize }, timeout)

	-- MessageOut lands a frame after the print that caused it, so without this the snippet's last
	-- line of output is always missing.
	task.wait()
	local logged = Buffer.Since(cursor)

	local parts = {}
	if ok then
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
	}
end

return Tool
