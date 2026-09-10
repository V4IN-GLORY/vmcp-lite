--!strict

-- An example tool. Every tool module is this shape: a `Definition` table that goes into the
-- `tools` list at handshake time, and a `Run` that gets the decoded `arguments` and returns
-- the `result` for the tool/call reply. See docs/protocol.md.

export type Result = {
	content: { { type: "text", text: string } },
	isError: boolean?,
}

local Tool = {}

Tool.Definition = {
	name = "print",
	description = "Prints a message to the Studio output window.",
	inputSchema = {
		type = "object",
		properties = {
			message = { type = "string", description = "The text to print." },
		},
		required = { "message" },
	},
	tags = { title = "Print", readOnly = true, idempotent = true },
}

function Tool.Run(arguments: { message: string? }): Result
	local message = arguments.message
	-- The server forwards arguments untouched, so the tool checks its own.
	if type(message) ~= "string" or message == "" then
		return {
			content = { { type = "text", text = "message must be a non-empty string" } },
			isError = true,
		}
	end

	print(`[VMCP] {message}`)

	return {
		content = { { type = "text", text = `Printed: {message}` } },
	}
end

return Tool
