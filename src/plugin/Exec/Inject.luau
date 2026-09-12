--!strict
--!optimize 2

-- Runs a chunk of Luau in the plugin's own context.
--
-- `loadstring` isn't available here, so the chunk becomes a ModuleScript that gets required and
-- thrown away. Fresh every call is the whole trick: `require` caches by instance, so reusing one
-- would hand back the first run's result forever no matter what the source says now.
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

local function build(source: string): (ModuleScript?, string?)
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
	return created, nil
end

-- Wrapping in a function is what lets a snippet with no `return` work at all -- a ModuleScript
-- body that returns nothing is a hard require error. The wrapper stays on line 1 so a syntax
-- error still reports the snippet's own line numbers.
local function wrap(source: string): string
	return `return function(vmcp) {source}\nend`
end

-- Compiles source without running anything past its top level. The timeline payload is nothing
-- but closures, so requiring it is a syntax check and nothing more -- which is the difference
-- between catching the model's typo here and watching a test start with a dead harness in it.
function Inject.Check(source: string): (boolean, string?)
	local module, refusal = build(source)
	if not module then
		return false, refusal
	end
	module.Parent = folder()

	local ok, failure = pcall(require, module)
	pcall(function()
		module:Destroy()
	end)
	return ok, if ok then nil else tostring(failure)
end

-- Returns ok plus either the snippet's return value or the failure text. `env` is handed to the
-- snippet as its `vmcp` argument.
function Inject.Run(source: string, env: { [string]: any }?, timeout: number?): (boolean, any)
	local module, refusal = build(wrap(source))
	if not module then
		return false, refusal
	end
	module.Parent = folder()

	local ok, produced = false, nil :: any
	local done = false
	local thread = task.spawn(function()
		local loaded, chunk = pcall(require, module)
		if loaded then
			ok, produced = pcall(chunk, env or {})
		else
			produced = chunk
		end
		done = true
	end)

	-- A snippet that yields forever would otherwise wedge the plugin until Studio restarts. A
	-- tight loop with no yield still hangs everything, and nothing in Luau can preempt that.
	local deadline = os.clock() + (timeout or DEFAULT_TIMEOUT)
	while not done and os.clock() < deadline do
		task.wait()
	end
	if not done then
		pcall(task.cancel, thread)
		ok, produced = false, `the snippet was still running after {timeout or DEFAULT_TIMEOUT}s and was cancelled`
	end

	pcall(function()
		module:Destroy()
	end)
	return ok, produced
end

return Inject
