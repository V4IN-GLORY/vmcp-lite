--!strict

-- What a snippet sees as `vmcp`. Built once and handed to every snippet and every timeline event,
-- so they all have the same vocabulary whichever DataModel they happen to be running in.

local Bridge = require(script.Parent.Bridge)

local Env = {
	Audit = require(script.Parent.Lib.Audit),
	Bench = require(script.Parent.Lib.Bench),
	Build = require(script.Parent.Lib.Build),
	Equiv = require(script.Parent.Lib.Equiv),
	Exploit = require(script.Parent.Lib.Exploit),
	Instrument = require(script.Parent.Lib.Instrument),
	Lint = require(script.Parent.Lib.Lint),
	Load = require(script.Parent.Lib.Load),
	Profile = require(script.Parent.Lib.Profile),
	Remotes = require(script.Parent.Lib.Remotes),
	Serialize = require(script.Parent.Exec.Serialize),
	Game = require(script.Parent.Exec.GameVm),
}

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
