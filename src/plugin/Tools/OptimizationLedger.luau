--!strict

-- The memory of an optimization pass, kept on the VMCP server per place: what's been profiled,
-- what was found, what was proposed, what the user said. Read it at the start of a pass so a
-- second session doesn't redo the first one's work, and write it as each script is closed out.

local Bridge = require(script.Parent.Parent.Bridge)

type Result = {
	content: { { type: "text", text: string } },
	isError: boolean?,
}

local Tool = {}

Tool.Definition = {
	name = "optimization_ledger",
	description = "Per-place record of the optimization pass, stored by the VMCP server under "
		.. "~/.vmcp/optimization/<place>.json. read lists every script touched so far with its status "
		.. "and numbers; write merges fields into one script's entry (status: profiled | proposed | "
		.. "tried | applied | rejected | skipped, plus whatever else is worth keeping -- worst frame "
		.. "before/after, the fix in one line, why it was rejected); clear removes an entry. Read it "
		.. "before starting a pass and write it before moving to the next script, so the final report "
		.. "can total what the pass saved.",
	inputSchema = {
		type = "object",
		properties = {
			action = { type = "string", enum = { "read", "write", "clear" } },
			script = { type = "string", description = "Dotted path of the script the entry is about (write/clear)." },
			entry = {
				type = "object",
				description = "Fields to merge for write. Free-form; `status` and `summary` are the ones the "
					.. "listing shows.",
				additionalProperties = true,
			},
		},
		required = { "action" },
	},
	tags = { title = "Optimization Ledger", idempotent = true },
}

local function text(body: string, isError: boolean?): Result
	return { content = { { type = "text", text = body } }, isError = isError }
end

local function render(entries: { [string]: any }): string
	local keys = {}
	for key in entries do
		table.insert(keys, key)
	end
	if #keys == 0 then
		return "the ledger is empty for this place"
	end
	table.sort(keys)
	local lines = { `{#keys} script(s) in the ledger:` }
	for _, key in keys do
		local entry = entries[key]
		local extras = {}
		for field, value in entry do
			if field ~= "status" and field ~= "summary" and field ~= "updatedAt" then
				table.insert(extras, `{field}={tostring(value)}`)
			end
		end
		table.sort(extras)
		table.insert(
			lines,
			string.format(
				"  %-10s %s -- %s%s",
				tostring(entry.status or "?"),
				key,
				tostring(entry.summary or ""),
				if #extras > 0 then " (" .. table.concat(extras, ", ") .. ")" else ""
			)
		)
	end
	return table.concat(lines, "\n")
end

function Tool.Run(arguments: { action: string?, script: string?, entry: { [string]: any }? }): Result
	local action = arguments.action
	if action == "read" then
		local ok, payload = Bridge.Request("ledger/read", {}, 10)
		if not ok then
			return text(tostring(payload), true)
		end
		return text(render(payload.entries or {}))
	end

	if type(arguments.script) ~= "string" or arguments.script == "" then
		return text(`{tostring(action)} needs a script path`, true)
	end
	if action == "write" then
		if type(arguments.entry) ~= "table" then
			return text("write needs an entry object", true)
		end
	elseif action ~= "clear" then
		return text(`action must be read, write or clear -- got "{tostring(action)}"`, true)
	end

	local ok, payload = Bridge.Request("ledger/write", {
		key = arguments.script,
		-- Absent on the wire for clear; the server reads that as "delete".
		entry = if action == "clear" then nil else arguments.entry,
	}, 10)
	if not ok then
		return text(tostring(payload), true)
	end
	return text(render(payload.entries or {}))
end

return Tool
