--!strict

-- Plumbing, not a tool anyone calls directly: it's tagged internal, so the server keeps it out of
-- the list it advertises but still routes tool/invoke to it.
--
-- Everything here is something only a DataModel can answer about itself. "ping" is how the edit
-- session finds out a playtest's DataModels have finished connecting, and "stop" is how a playtest
-- ends -- EndTest only works from inside the test server, which the edit session isn't.

local Bridge = require(script.Parent.Parent.Bridge)

type Result = {
	content: { { type: "text", text: string } },
	isError: boolean?,
}

local Tool = {}

Tool.Definition = {
	name = "peer",
	description = "Internal. Reports on, or ends, the DataModel it runs in.",
	inputSchema = {
		type = "object",
		properties = {
			action = { type = "string", enum = { "ping", "stop" } },
			context = { type = "string", enum = { "plugin", "server", "client" } },
			player = { type = "integer", minimum = 1 },
		},
		required = { "action" },
	},
	tags = { title = "Peer", internal = true },
}

function Tool.Run(arguments: { action: string? }): Result
	if arguments.action == "stop" then
		local ok, failure = pcall(function()
			(game:GetService("StudioTestService") :: any):EndTest("stopped by VMCP")
		end)
		if not ok then
			return { content = { { type = "text", text = `couldn't end the test: {failure}` } }, isError = true }
		end
		return { content = { { type = "text", text = "ended the playtest" } } }
	end

	local connection = Bridge.Connection()
	local index = connection.peerIndex
	local who = if index == nil then connection.role else `{connection.role} {index}`
	return { content = { { type = "text", text = `{who} is up` } } }
end

return Tool
