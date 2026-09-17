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
	Game = require(script.Parent.Exec.GameVm),
}

function Env.Render(canvas: any, name: string?, options: { upload: boolean?, groupId: number? }?): (boolean, string)
	local serverUpload = false
	if options and options.upload then
		if type(canvas) ~= "table" or not canvas.Upload then
			return false, "upload needs a Canvas, not a recording"
		end
		-- Studio's own upload when it's enabled and the user owns it; otherwise the server does
		-- it over Open Cloud.
		serverUpload = options.groupId ~= nil or canvas:Upload(name or "vmcp-canvas") == nil
	end
	local recording = if type(canvas) == "table" and canvas.Recording then canvas:Recording() else canvas
	if type(recording) ~= "table" then
		return false, "Render wants a Canvas, or the table its Recording() gave you"
	end
	recording.name = name
	if serverUpload then
		recording.upload = true
		recording.groupId = options and options.groupId
		local ok, userId = pcall(function()
			return game:GetService("StudioService"):GetUserId()
		end)
		recording.userId = if ok then userId else nil
	end
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
