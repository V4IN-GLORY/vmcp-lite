--!strict

-- Turns a timeline request into the source of one ModuleScript, which the plugin injects as
-- ReplicatedStorage.VMCPPayload and both harnesses require.
--
-- The events come out as real Luau functions rather than strings to be compiled later, because
-- the contexts that run them can't compile anything: a client DataModel has no loadstring, and a
-- Script's Source is only writable from a plugin. Baking it also means the plugin can check the
-- whole payload for syntax errors before the test starts, by requiring this module in edit mode
-- where building the closures does nothing on its own.

local Codegen = {}

export type Event = {
	at: number,
	context: string,
	player: number?,
	blocking: boolean?,
	label: string?,
	code: string,
}

export type Spec = {
	mode: string,
	players: number,
	duration: number,
	awaitTimeout: number?,
	-- Not part of the payload: these go into the server boot script. See Codegen.Boot.
	port: string?,
	token: string?,
	linkId: string?,
	events: { Event },
	assertion: string?,
}

local function quoted(value: any): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	if type(value) == "number" or type(value) == "boolean" then
		return tostring(value)
	end
	return "nil"
end

local function eventSource(event: Event): string
	local parts = {
		`\tat = {event.at},`,
		`\tblocking = {event.blocking == true},`,
		`\tlabel = {quoted(event.label or event.context)},`,
		"\trun = function(ctx, input)",
		event.code,
		"\tend,",
	}
	return "{\n" .. table.concat(parts, "\n") .. "\n},"
end

-- The generated module is written, never read by a person, so it gets no comments and only enough
-- indentation to keep an error message's line number meaningful.
function Codegen.Payload(spec: Spec): string
	local lines = { "local payload = {}", "", "payload.config = {" }
	for _, field in { "mode", "players", "duration", "awaitTimeout" } do
		table.insert(lines, `\t{field} = {quoted((spec :: any)[field])},`)
	end
	table.insert(lines, "}")

	local byClient: { [number]: { Event } } = {}
	local server: { Event } = {}
	for _, event in spec.events do
		if event.context == "server" then
			table.insert(server, event)
		else
			local index = event.player or 1
			byClient[index] = byClient[index] or {}
			table.insert(byClient[index], event)
		end
	end

	table.insert(lines, "")
	table.insert(lines, "payload.server = {")
	for _, event in server do
		table.insert(lines, eventSource(event))
	end
	table.insert(lines, "}")

	table.insert(lines, "")
	table.insert(lines, "payload.client = {}")
	for index, events in byClient do
		table.insert(lines, `payload.client[{index}] = ` .. "{")
		for _, event in events do
			table.insert(lines, eventSource(event))
		end
		table.insert(lines, "}")
	end

	table.insert(lines, "")
	if spec.assertion then
		table.insert(lines, "payload.assertion = function(ctx, input)")
		table.insert(lines, spec.assertion)
		table.insert(lines, "end")
	else
		table.insert(lines, "payload.assertion = nil")
	end

	table.insert(lines, "")
	table.insert(lines, "return payload")
	return table.concat(lines, "\n")
end

-- The injected Scripts are one line each: everything real lives in a ModuleScript so it can be
-- type-checked in the plugin's own tree instead of hiding inside a generated string.
--
-- `secrets` is how the auth token reaches the peer without being replicated. A ServerScriptService
-- script is server-only; the payload module in ReplicatedStorage is not.
function Codegen.Boot(moduleName: string, secrets: { [string]: any }?): string
	local folder = 'game:GetService("ReplicatedStorage"):WaitForChild("VMCPHarness")'
	local argument = ""
	if secrets then
		local fields = {}
		for name, value in secrets do
			table.insert(fields, `{name} = {quoted(value)}`)
		end
		argument = "{" .. table.concat(fields, ", ") .. "}"
	end
	return `require({folder}:WaitForChild("{moduleName}"))({argument})`
end

return Codegen
