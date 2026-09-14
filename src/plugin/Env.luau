--!strict

-- What a snippet sees as `vmcp`. Built once and handed to every snippet and every timeline event,
-- so they all have the same vocabulary whichever DataModel they happen to be running in.

local Bridge = require(script.Parent.Bridge)

local Env = {
	Anim = require(script.Parent.Lib.Anim),
	Audit = require(script.Parent.Lib.Audit),
	Bench = require(script.Parent.Lib.Bench),
	Build = require(script.Parent.Lib.Build),
	Canvas = require(script.Parent.Lib.Canvas),
	Equiv = require(script.Parent.Lib.Equiv),
	Exploit = require(script.Parent.Lib.Exploit),
	Instrument = require(script.Parent.Lib.Instrument),
	Lint = require(script.Parent.Lib.Lint),
	Load = require(script.Parent.Lib.Load),
	Profile = require(script.Parent.Lib.Profile),
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
-- Writes a Canvas out as a PNG on the VMCP server, which is the only side with a filesystem.
-- Works from any context and from inside a timeline event, where returning a directive isn't an
-- option. `name` becomes the file name; leave it out and it gets a timestamped one.
function Env.Render(canvas: any, name: string?): (boolean, string)
	local recording = if type(canvas) == "table" and canvas.Recording then canvas:Recording() else canvas
	if type(recording) ~= "table" then
		return false, "Render wants a Canvas, or the table its Recording() gave you"
	end
	recording.name = name
	return Bridge.Post(recording)
end

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
