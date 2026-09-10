--!strict

-- An example tool. A tool module is two things: a `Definition` that goes into the `tools`
-- list at handshake time, and a `Run` that takes the decoded arguments and returns the
-- result for the tool/call reply. docs/protocol.md has the rest.
--
-- Definition fields:
--   name          [A-Za-z0-9_-], 1-64 chars, unique in the place. What Claude calls.
--   description   Claude reads this to pick the tool -- write it for a person.
--   inputSchema   JSON Schema, passed to Claude untouched and never enforced by the
--                 server, so Run checks its own arguments.
--   outputSchema  optional; if you declare it, send structuredContent back too.
--   tags          optional; what the tool does to the place.
--   timeoutMs     optional; overrides the 30s default. A long job is better off sending
--                 tool/progress -- every progress message restarts the timeout.
--
-- Schema rules that bite:
--   `type = "object"` is required at the root of every schema.
--   An array needs `items`: { type = "array", items = { type = "string" } }.
--   A nested object needs its own `type` and `properties` -- never a bare {}, which
--   Luau encodes as [].
--   `required` is a list of names, not a string.
--
-- Tags, all optional:
--   title        friendlier display name than the id
--   readOnly     changes nothing
--   destructive  can overwrite or destroy existing work
--   idempotent   running it twice is the same as running it once
--   external     reaches outside the place: HTTP, Creator Store, filesystem
-- A misspelled tag is a hard error, not a silent no-op. `idempotent` also gets you retry
-- safety: the server caches the result under a retryKey it adds itself, nothing to handle.
--
-- Run returns { content = {...} }, plus `isError = true` for a failure Claude should read
-- and correct itself from -- bad arguments, nothing selected. A JSON-RPC error reads as
-- the plugin falling over instead. Anything that isn't a content table gets wrapped in a
-- text block, so `return "done"` is fine while prototyping.

export type Result = {
	content: { { type: "text", text: string } },
	structuredContent: { [string]: any }?,
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
			times = {
				type = "integer",
				description = "How many times to print it. Defaults to 1.",
				minimum = 1,
				maximum = 10,
			},
		},
		required = { "message" },
	},
	outputSchema = {
		type = "object",
		properties = {
			printed = { type = "integer", description = "How many lines were printed." },
		},
	},
	tags = { title = "Print", readOnly = true, idempotent = true },
}

function Tool.Run(arguments: { message: string?, times: number? }): Result
	local message = arguments.message
	if type(message) ~= "string" or message == "" then
		return {
			content = { { type = "text", text = "message must be a non-empty string" } },
			isError = true,
		}
	end

	local times = arguments.times or 1
	for _ = 1, times do
		print(`[VMCP] {message}`)
	end

	-- The text block goes out even with structuredContent -- some clients ignore structured
	-- output entirely.
	return {
		content = { { type = "text", text = `Printed {times}x: {message}` } },
		structuredContent = { printed = times },
	}
end

return Tool
