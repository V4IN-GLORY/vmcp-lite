--!strict

-- What a snippet sees as `vmcp`. Built once and handed to every snippet and every timeline event,
-- so they all have the same vocabulary whichever DataModel they happen to be running in.

local Bridge = require(script.Parent.Bridge)

local Env = {
	Anim = require(script.Parent.Lib.Anim),
	Bench = require(script.Parent.Lib.Bench),
	Build = require(script.Parent.Lib.Build),
	Canvas = require(script.Parent.Lib.Canvas),
	Exploit = require(script.Parent.Lib.Exploit),
	Remotes = require(script.Parent.Lib.Remotes),
	Rig = require(script.Parent.Lib.Rig),
	Style = require(script.Parent.Lib.Style),
	Serialize = require(script.Parent.Exec.Serialize),
	-- Eval and Require, against the running game's own script VM rather than the plugin's.
	Game = require(script.Parent.Exec.GameVm),
}

-- Calls another VMCP tool and gives back its text. `arguments.context` picks the DataModel, so a
-- client event can ask the server a question, or ask the edit session for a tree dump, without
-- the payload having to be split into three separate calls first.
--
-- Returns ok plus the text; a tool that reported an error comes back as false with its own words.
function Env.Tool(name: string, arguments: { [string]: any }?): (boolean, string)
	local reached, result = Bridge.Invoke(name, arguments, 120)
	if not reached then
		return false, tostring(result)
	end

	local parts = {}
	for _, item in result.content or {} do
		if type(item.text) == "string" then
			table.insert(parts, item.text)
		end
	end
	return result.isError ~= true, table.concat(parts, "\n")
end

return Env
