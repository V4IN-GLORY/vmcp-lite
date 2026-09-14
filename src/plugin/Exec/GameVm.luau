--!strict

-- Runs code inside the running game's own script VM, rather than the plugin's.
--
-- The plugin can already create a ModuleScript and require it anywhere it's loaded (see
-- Inject.luau). What it can't do that way is share the require cache: `require(SomeModule)` from
-- the plugin builds a *fresh* copy of that module, so whatever state the running game accumulated
-- in it is invisible. That makes the plugin VM useless for the thing you most want during a
-- playtest -- looking at what a module actually holds right now.
--
-- The fix is a short-lived Script living in the game, exposing a BindableFunction. The plugin
-- hands it a ModuleScript and the `require` happens on the game's side of the fence, against the
-- game's cache. Only strings come back: a BindableFunction copies tables and chokes on functions,
-- and a module table is usually full of functions, so it's rendered to text before it crosses.
--
-- Everything here is created at runtime inside a playtest DataModel, so it disappears when the
-- playtest stops. Nothing touches the saved place.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Inject = require(script.Parent.Inject)
local Serialize = require(script.Parent.Serialize)

local BRIDGE_NAME = "__VMCP_GameBridge"
local INVOKE_NAME = "__VMCP_GameInvoke"
local SERIALIZE_NAME = "__VMCP_Serialize"
-- Also copied in: an equivalence checker that game-VM snippets can require to compare two live
-- functions. See Lib/Equiv.
local EQUIV_NAME = "__VMCP_Equiv"
local READY_TIMEOUT = 5

local GameVm = {}

local BRIDGE_SOURCE = string.format(
	[[
local here = script.Parent
local Serialize = require(here:WaitForChild("%s"))

local previous = here:FindFirstChild("%s")
if previous then
	previous:Destroy()
end

local bindable = Instance.new("BindableFunction")
bindable.Name = "%s"
bindable.Archivable = false
bindable.Parent = here

bindable.OnInvoke = function(payload)
	if typeof(payload) ~= "Instance" or not payload:IsA("ModuleScript") then
		return { ok = false, text = "payload must be a ModuleScript" }
	end
	local ok, value = pcall(require, payload)
	return { ok = ok, text = if ok then Serialize.Render(value) else tostring(value) }
end
]],
	SERIALIZE_NAME,
	INVOKE_NAME,
	INVOKE_NAME
)

-- Server code goes in ServerScriptService; client code goes in this player's PlayerScripts, which
-- is the only container on a client where a LocalScript created at runtime will actually run.
local function container(): (Instance?, string?)
	if RunService:IsServer() then
		return ServerScriptService, nil
	end
	local player = Players.LocalPlayer
	if not player then
		return nil, "no LocalPlayer, so this isn't a client DataModel"
	end
	local scripts = player:FindFirstChild("PlayerScripts")
	return scripts, if scripts then nil else "this client has no PlayerScripts yet"
end

local function ensure(): (BindableFunction?, string?)
	if RunService:IsEdit() then
		return nil,
			"there's no game VM in edit mode -- this needs a playtest. Start one with the playtest "
				.. "tool, or use the plugin context, which runs in Studio itself."
	end

	local parent, problem = container()
	if not parent then
		return nil, problem
	end

	local existing = parent:FindFirstChild(INVOKE_NAME)
	if existing and existing:IsA("BindableFunction") then
		return existing, nil
	end

	local ok, failure = pcall(function()
		local previous = parent:FindFirstChild(BRIDGE_NAME)
		if previous then
			previous:Destroy()
		end

		local serializer = Instance.new("ModuleScript")
		serializer.Name = SERIALIZE_NAME
		serializer.Source = (script.Parent.Serialize :: ModuleScript).Source
		serializer.Archivable = false
		serializer.Parent = parent

		local equiv = Instance.new("ModuleScript")
		equiv.Name = EQUIV_NAME
		equiv.Source = (script.Parent.Parent.Lib.Equiv :: ModuleScript).Source
		equiv.Archivable = false
		equiv.Parent = parent

		local bridge: any = Instance.new(if RunService:IsServer() then "Script" else "LocalScript")
		bridge.Name = BRIDGE_NAME
		bridge.Source = BRIDGE_SOURCE
		bridge.Archivable = false
		bridge.Parent = parent
	end)
	if not ok then
		return nil, `couldn't install the game bridge: {failure}`
	end

	-- The bridge is an ordinary game script, so it starts on its own schedule, not ours.
	local deadline = os.clock() + READY_TIMEOUT
	repeat
		local bindable = parent:FindFirstChild(INVOKE_NAME)
		if bindable and bindable:IsA("BindableFunction") then
			return bindable, nil
		end
		task.wait()
	until os.clock() >= deadline

	return nil, "the game bridge script never started -- is the playtest actually running?"
end

-- Returns ok plus the rendered result. The snippet runs as a function body, so `return` works.
function GameVm.Run(source: string): (boolean, string)
	local bindable, problem = ensure()
	if not bindable then
		return false, problem :: string
	end

	local module, refusal = Inject.Module(`return (function() {source}\nend)()`)
	if not module then
		return false, refusal :: string
	end

	local ok, reply = pcall(function()
		return bindable:Invoke(module)
	end)
	pcall(function()
		module:Destroy()
	end)

	if not ok then
		return false, `the game bridge refused the call: {reply}`
	end
	if type(reply) ~= "table" then
		return false, "the game bridge answered with something unreadable"
	end
	return reply.ok == true, tostring(reply.text)
end

-- The reason this module exists: requires the module the *game* holds, with whatever state it has
-- built up by now, and renders it. `path` is a dotted DataModel path.
function GameVm.Require(path: string): (boolean, string)
	if type(path) ~= "string" or path == "" then
		return false, 'Require takes a dotted path, like "ReplicatedStorage.Modules.Combat"'
	end

	-- Resolved on the game's side rather than here, so a path pointing at something only the
	-- server can see still works.
	return GameVm.Run(table.concat({
		`local path = {string.format("%q", path)}`,
		"local current = game",
		'for segment in string.gmatch(path, "[^%.]+") do',
		"	local found = current:FindFirstChild(segment)",
		"	if not found and current == game then",
		"		found = (pcall(game.GetService, game, segment)) and game:GetService(segment) or nil",
		"	end",
		'	if not found then error("nothing at " .. path) end',
		"	current = found",
		"end",
		"return require(current)",
	}, "\n"))
end

-- Where a game-VM snippet finds the equivalence checker: `require(vmcp.Game.EquivPath())` isn't
-- possible across VMs, so it's a path string to splice into the snippet.
function GameVm.EquivPath(): string
	local parent = container()
	return if parent then `{parent:GetFullName()}.{EQUIV_NAME}` else EQUIV_NAME
end

-- Serialize is handed to snippets alongside this, so a caller that wants the plugin-side renderer
-- rather than the game-side one has it.
GameVm.Serialize = Serialize

return GameVm
