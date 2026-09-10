--!strict

-- An example tool, written out with the protocol rules it depends on. Every tool module is
-- this shape: a `Definition` that goes into the `tools` list at handshake time, and a `Run`
-- that takes the decoded `arguments` and returns the `result` for the tool/call reply.
-- docs/protocol.md is the full reference.

-- The result shape the server expects back. `content` is what Claude reads; `isError = true`
-- marks a failure Claude can see and correct itself from, rather than a hard fault.
export type Result = {
	content: { { type: "text", text: string } },
	structuredContent: { [string]: any }?,
	isError: boolean?,
}

local Tool = {}

Tool.Definition = {
	-- [A-Za-z0-9_-], 1-64 chars, unique within the place. This is what Claude calls.
	name = "print",

	-- Claude reads this to decide when to use the tool, so write it for a person. Say what it
	-- does and when it's the right choice -- not how it's implemented.
	description = "Prints a message to the Studio output window.",

	-- Plain JSON Schema, forwarded to Claude untouched. The server never validates arguments
	-- against it, so `Run` checks its own.
	inputSchema = {
		-- Required at the root, on every tool. A schema without it is refused at registration.
		type = "object",
		properties = {
			-- Every property wants a `type` and a `description` -- the description is the only
			-- thing telling Claude what goes in the field.
			message = { type = "string", description = "The text to print." },

			-- An array needs `items` too, or Claude has no idea what goes in it:
			--   words = { type = "array", items = { type = "string" }, description = "..." }
			-- Same for a nested object -- `type = "object"` plus its own `properties`. Never
			-- leave a nested schema as a bare `{}`; Luau encodes an empty table as `[]`.

			-- Optional, so it stays out of `required` below.
			times = {
				type = "integer",
				description = "How many times to print it. Defaults to 1.",
				minimum = 1,
				maximum = 10,
			},
		},
		-- A list of names, not a single string. Leave it out entirely if nothing is required.
		required = { "message" },
	},

	-- Optional. Declare it and the reply should carry `structuredContent` matching it, next to
	-- the text block -- some clients ignore structured output, so the text always goes too.
	outputSchema = {
		type = "object",
		properties = {
			printed = { type = "integer", description = "How many lines were printed." },
		},
	},

	-- What the tool does to the place. Clients use these to decide what to run without asking.
	--   title       friendlier display name than the id
	--   readOnly    changes nothing -- true here, printing doesn't touch the place
	--   destructive can overwrite or destroy existing work
	--   idempotent  running it twice with the same arguments is the same as running it once
	--   external    reaches outside the place: HTTP, Creator Store, filesystem
	-- `idempotent` also buys retry safety for free: the server adds a `retryKey` argument and
	-- replays the cached result instead of running the tool again. Nothing to handle here.
	-- A misspelled tag is a hard error, not a silent no-op.
	tags = { title = "Print", readOnly = true, idempotent = true },

	-- Optional, overrides the server's 30s default for this one tool. A long job is better off
	-- sending tool/progress instead -- each progress message restarts the timeout.
	-- timeoutMs = 60000,
}

function Tool.Run(arguments: { message: string?, times: number? }): Result
	local message = arguments.message
	if type(message) ~= "string" or message == "" then
		-- Wrong arguments come back as a normal result with `isError`, so Claude reads the text
		-- and tries again. A JSON-RPC error object would read as the plugin falling over.
		return {
			content = { { type = "text", text = "message must be a non-empty string" } },
			isError = true,
		}
	end

	local times = arguments.times or 1
	for _ = 1, times do
		print(`[VMCP] {message}`)
	end

	-- Anything that isn't a `{content = {...}}` table gets wrapped in a text block for you, so
	-- `return "done"` is fine while prototyping. This is the long form.
	return {
		content = { { type = "text", text = `Printed {times}x: {message}` } },
		structuredContent = { printed = times },
	}
end

return Tool
