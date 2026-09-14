--!strict

-- The one step that changes the game, with a net under it: write the script's file on disk, wait
-- for Rojo to carry it into Studio, start a fresh playtest with the previous version planted next
-- to it, run the caller's check in the game VM, and put the old file back if anything failed.
--
-- Everything before this in the loop was reversible by stopping a playtest. This is reversible
-- by the same tool, automatically, which is what lets it run unattended.

local ServerStorage = game:GetService("ServerStorage")

local Bridge = require(script.Parent.Parent.Bridge)
local Path = require(script.Parent.Parent.Path)
local Session = require(script.Parent.Parent.Playtest.Session)
local Swap = require(script.Parent.Parent.Playtest.Swap)

local SYNC_TIMEOUT = 20
local PREVIOUS_PREFIX = "__VMCP_Previous_"

type Result = {
	content: { { type: "text", text: string } },
	isError: boolean?,
}

local Tool = {}

Tool.Definition = {
	name = "apply_fix",
	description = "Applies a candidate to the real script: writes the file Rojo syncs it from, waits "
		.. "for Studio to pick it up, restarts the playtest, and runs your `check` in the game VM "
		.. "with the previous version available as ServerStorage.__VMCP_Previous_<Name> for an "
		.. "Equiv.Check against the live one. If the sync never lands, the check errors or returns "
		.. "anything but true, or the server logs an error, the old file is written back and the "
		.. "reply says why. On success the playtest stays up running the applied code -- hand it to "
		.. "the user. Only call this after the user has said yes.",
	inputSchema = {
		type = "object",
		properties = {
			script = { type = "string", description = 'Dotted path, like "ServerScriptService.Combat".' },
			source = { type = "string", description = "The complete new Source." },
			check = {
				type = "string",
				description = "Luau body run in the game VM after the restart. Return true to pass; "
					.. "anything else (a string, an Equiv result's text) fails and reverts. "
					.. "`require(game.ServerStorage.__VMCP_Previous_<Name>)` is the old module; "
					.. "`require(game.ServerScriptService.<path>.__VMCP_Equiv)` next to the game bridge "
					.. "has Equiv.Check. Optional but strongly encouraged.",
			},
			players = {
				type = "integer",
				minimum = 1,
				maximum = 8,
				description = "Players for the playtest. Defaults to 1.",
			},
		},
		required = { "script", "source" },
	},
	tags = { title = "Apply Fix", destructive = true },
	timeoutMs = 240000,
}

local function text(body: string, isError: boolean?): Result
	return { content = { { type = "text", text = body } }, isError = isError }
end

local function normalise(source: string): string
	return (source:gsub("\r\n", "\n"):gsub("%s+$", ""))
end

-- Rojo pushes disk changes into Studio on its own clock; this is the only way to know it did.
local function waitForSync(instance: Instance, wanted: string): boolean
	local target = normalise(wanted)
	local deadline = os.clock() + SYNC_TIMEOUT
	repeat
		local current = Swap.ReadSource(instance)
		if current and normalise(current) == target then
			return true
		end
		task.wait(0.5)
	until os.clock() >= deadline
	return false
end

local function writeFile(path: string, className: string, source: string): (boolean, any)
	return Bridge.Request("source/write", { path = path, className = className, source = source }, 15)
end

function Tool.Run(arguments: { script: string?, source: string?, check: string?, players: number? }): Result
	if type(arguments.script) ~= "string" or type(arguments.source) ~= "string" or arguments.source == "" then
		return text("apply_fix needs script and source", true)
	end
	local instance, why = Path.Resolve(arguments.script :: string)
	if not instance then
		return text(why :: string, true)
	end
	local before, unreadable = Swap.ReadSource(instance)
	if not before then
		return text(unreadable :: string, true)
	end

	local written, reply = writeFile(instance:GetFullName(), instance.ClassName, arguments.source :: string)
	if not written then
		return text(`couldn't write the file: {tostring(reply)}`, true)
	end
	local file: string = reply.file
	local previousOnDisk: string = reply.previous

	local function revert(reason: string): Result
		local restored, failure = writeFile(instance:GetFullName(), instance.ClassName, previousOnDisk)
		local note = if restored
			then `{file} is back to what it was`
			else `AND the revert failed ({tostring(failure)}) -- {file} holds the candidate, restore it by hand`
		if Session.IsRunning() then
			Bridge.Invoke("peer", { action = "stop", context = "server" }, 20)
			Session.Forget()
		end
		return text(`NOT applied: {reason}\n{note}`, true)
	end

	if not waitForSync(instance, arguments.source :: string) then
		return revert(
			`wrote {file} but Studio's copy didn't change within {SYNC_TIMEOUT}s -- is the Rojo plugin connected?`
		)
	end

	-- The previous version rides into the playtest as a sibling module, so a check can require
	-- both and compare them in the same VM. Archivable stays on: the playtest copies the place the
	-- way a save would, and Swap destroys it the moment the copy exists.
	local previous: Instance = Instance.new("ModuleScript")
	previous.Name = PREVIOUS_PREFIX .. instance.Name;
	(previous :: ModuleScript).Source = before
	previous.Parent = ServerStorage

	local failure = Swap.Start({}, math.clamp(arguments.players or 1, 1, 8), "server", nil, { previous })
	if failure then
		return revert(`the playtest wouldn't start: {failure}`)
	end

	local lines = { `applied to {file}; Studio synced; playtest restarted` }
	if type(arguments.check) == "string" and arguments.check ~= "" then
		local reached, result = Bridge.Invoke("run_luau", {
			context = "server",
			vm = "game",
			code = arguments.check,
			timeoutSeconds = 60,
		}, 90)
		if not reached then
			return revert(`the check couldn't run: {tostring(result)}`)
		end
		local body = ""
		for _, item in result.content or {} do
			if type(item.text) == "string" then
				body ..= item.text
			end
		end
		if result.isError or not string.match(body, "^returned: true") then
			return revert(`the check didn't pass:\n{body}`)
		end
		table.insert(lines, "check passed")
	end

	local _, logs = Bridge.Invoke("get_logs", { context = "server", severity = "error", sinceSeconds = 30 }, 10)
	local errorText = ""
	for _, item in (logs and logs.content) or {} do
		if type(item.text) == "string" then
			errorText ..= item.text
		end
	end
	if errorText ~= "" and not string.find(errorText, "^no log lines") then
		return revert(`the server logged errors after the restart:\n{errorText}`)
	end

	table.insert(lines, "no server errors since the restart")
	table.insert(lines, "The playtest is running the applied code -- have the user play it now.")
	return text(table.concat(lines, "\n"))
end

return Tool
