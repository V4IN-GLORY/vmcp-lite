--!strict
--!optimize 2

-- Compiles and runs a chunk of Luau in the plugin's own context.
--
-- `loadstring` isn't involved and doesn't need to be: a plugin has PluginSecurity in whatever
-- DataModel it's loaded into, so it can write a ModuleScript's Source and require it. That works
-- in the edit DataModel and in a playtest alike, with LoadStringEnabled off.
--
-- Fresh every call is the whole trick: `require` caches by instance, so reusing one would hand
-- back the first run's result forever no matter what the source says now.
--
-- The scratch folder lives in CoreGui, not the place. CoreGui isn't saved, so a crash mid-run
-- leaves nothing behind to commit and nothing for Rojo to fight with.

local CoreGui = game:GetService("CoreGui")

local FOLDER_NAME = "VMCP_Exec"
local DEFAULT_TIMEOUT = 10

local Inject = {}

local scratch: Folder? = nil
local counter = 0

local function folder(): Folder
	local existing = scratch
	if existing and existing.Parent then
		return existing
	end

	-- First call of the session also sweeps: anything already here is an orphan from a plugin
	-- reload or a Studio crash, and nothing in it was worth keeping.
	local stale = CoreGui:FindFirstChild(FOLDER_NAME)
	if stale then
		stale:Destroy()
	end

	local created = Instance.new("Folder")
	created.Name = FOLDER_NAME
	created.Parent = CoreGui
	scratch = created
	return created
end

local INJECTION_DENIED = "Studio won't let VMCP create scripts, so run_luau can't work. Open the "
	.. "Plugins ribbon, click Plugin Management, and allow script injection for VMCP."

-- Returns a ModuleScript holding `source`, parented into the scratch folder.
function Inject.Module(source: string): (ModuleScript?, string?)
	counter += 1
	local ok, created = pcall(function()
		local module = Instance.new("ModuleScript")
		module.Name = `chunk{counter}`
		module.Source = source
		return module
	end)
	if not ok then
		return nil, `{INJECTION_DENIED} ({created})`
	end

	local module = created :: ModuleScript
	module.Parent = folder()
	return module, nil
end

-- Wrapping in a function is what lets a snippet with no `return` work at all -- a ModuleScript
-- body that returns nothing is a hard require error. The wrapper stays on line 1 so a syntax
-- error still reports the snippet's own line numbers.
local function wrap(source: string, parameters: string): string
	return `return function({parameters}) {source}\nend`
end

-- Compiles without running past the top level, and hands back the callable. Separating this from
-- running is what lets a timeline check its whole payload before the playtest starts, and compile
-- each event once instead of once per firing.
function Inject.Compile(source: string, parameters: string?): (((...any) -> ...any)?, string?)
	local module, refusal = Inject.Module(wrap(source, parameters or "vmcp"))
	if not module then
		return nil, refusal
	end

	local ok, chunk = pcall(require, module)
	pcall(function()
		module:Destroy()
	end)
	if not ok then
		return nil, tostring(chunk)
	end
	return chunk :: any, nil
end

-- Returns ok plus either the snippet's return value or the failure text. `env` is handed to the
-- snippet as its `vmcp` argument.
function Inject.Run(source: string, env: { [string]: any }?, timeout: number?): (boolean, any)
	local chunk, refusal = Inject.Compile(source)
	if not chunk then
		return false, refusal
	end

	local ok, produced = false, nil :: any
	local done = false
	local thread = task.spawn(function()
		ok, produced = pcall(chunk, env or {})
		done = true
	end)

	-- A snippet that yields forever would otherwise wedge the plugin until Studio restarts. A
	-- tight loop with no yield still hangs everything, and nothing in Luau can preempt that.
	local limit = timeout or DEFAULT_TIMEOUT
	local deadline = os.clock() + limit
	while not done and os.clock() < deadline do
		task.wait()
	end
	if not done then
		pcall(task.cancel, thread)
		return false, `the snippet was still running after {limit}s and was cancelled`
	end

	return ok, produced
end

return Inject
