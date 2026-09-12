--!strict

-- Owns the one playtest a Studio window is allowed to have.
--
-- Plugins don't load into test DataModels, so nothing here can reach the running game directly.
-- What it can do is write into the place *before* the test starts, which is how the harness gets
-- there: a VMCPHarness folder in ReplicatedStorage plus a one-line boot script on each side. All
-- of it is removed afterwards, and none of it is ever saved.
--
-- Two modes. A timeline runs a fixed script and ends itself, so Start yields and hands back the
-- report. A session stays open so later run_luau calls are cheap, and ends when something tells
-- the peer to stop.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

local Codegen = require(script.Parent.Parent.Timeline.Codegen)
local Inject = require(script.Parent.Parent.Exec.Inject)

local FOLDER_NAME = "VMCPHarness"
local BOOT_NAME = "VMCPBoot"

local Session = {}

export type Spec = {
	mode: string,
	players: number,
	duration: number,
	awaitTimeout: number?,
	port: string?,
	token: string?,
	linkId: string?,
	events: { Codegen.Event },
	assertion: string?,
}

local state = {
	running = false,
	mode = "",
	players = 0,
	startedAt = 0,
	loadStringWas = nil :: boolean?,
}

-- The plugin's own modules, copied into the place so the test DataModel can require them. Source
-- rather than Clone: a clone would drag the plugin's script along with whatever Rojo thinks its
-- parent is, and Source is the only part that matters.
local function sources(): { [string]: ModuleScript }
	local root = script.Parent.Parent
	return {
		Runtime = root.Timeline.Runtime :: ModuleScript,
		ServerHarness = root.Timeline.ServerHarness :: ModuleScript,
		ClientHarness = root.Timeline.ClientHarness :: ModuleScript,
		Serialize = root.Exec.Serialize :: ModuleScript,
		LogBuffer = root.Log.Buffer :: ModuleScript,
		Peer = root.Playtest.Peer :: ModuleScript,
	}
end

local function clear()
	for _, target in { ReplicatedStorage:FindFirstChild(FOLDER_NAME), ServerScriptService:FindFirstChild(BOOT_NAME) } do
		if target then
			target:Destroy()
		end
	end
	local scripts = StarterPlayer:FindFirstChild("StarterPlayerScripts")
	local clientBoot = scripts and scripts:FindFirstChild(BOOT_NAME)
	if clientBoot then
		clientBoot:Destroy()
	end
end

local function teardown()
	clear()
	if state.loadStringWas ~= nil then
		ServerScriptService.LoadStringEnabled = state.loadStringWas
		state.loadStringWas = nil
	end
	state.running = false
	state.mode = ""
end

local function build(spec: Spec, payloadSource: string): string?
	clear()

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME

	local ok, failure = pcall(function()
		for name, module in sources() do
			local copy = Instance.new("ModuleScript")
			copy.Name = name
			copy.Source = module.Source
			copy.Parent = folder
		end

		local payload = Instance.new("ModuleScript")
		payload.Name = "Payload"
		payload.Source = payloadSource
		payload.Parent = folder

		local link = Instance.new("RemoteEvent")
		link.Name = "Link"
		link.Parent = folder

		local serverBoot = Instance.new("Script")
		serverBoot.Name = BOOT_NAME
		serverBoot.Source =
			Codegen.Boot("ServerHarness", { port = spec.port, token = spec.token, linkId = spec.linkId })
		serverBoot.Parent = ServerScriptService

		local clientBoot = Instance.new("LocalScript")
		clientBoot.Name = BOOT_NAME
		clientBoot.Source = Codegen.Boot("ClientHarness")
		clientBoot.Parent = StarterPlayer:WaitForChild("StarterPlayerScripts")
	end)

	if not ok then
		folder:Destroy()
		clear()
		return `couldn't write the harness into the place: {failure}`
	end

	folder.Parent = ReplicatedStorage

	-- Server code arrives over the socket after the test is already running, and the only thing in
	-- a live server that can turn a string into a function is loadstring. The old value goes back
	-- at teardown.
	if spec.mode == "session" then
		state.loadStringWas = ServerScriptService.LoadStringEnabled
		ServerScriptService.LoadStringEnabled = true
	end
	return nil
end

-- Returns the report string EndTest handed back for a timeline, or nil for a session, plus a
-- problem when there is one. A timeline yields here for its whole duration.
function Session.Start(spec: Spec): (string?, string?)
	if state.running then
		return nil, `a {state.mode} playtest is already running -- stop it first`
	end

	local testService = game:GetService("StudioTestService") :: any
	if not testService.EditModeActive then
		return nil, "Studio is already running or playing something; stop it and try again"
	end
	if spec.mode == "session" and not HttpService.HttpEnabled then
		return nil,
			"HttpService.HttpEnabled is off, so the test server can't open its socket back to VMCP. "
				.. "Turn it on in Game Settings > Security, or use run_timeline, which needs no socket."
	end

	local payloadSource = Codegen.Payload(spec)
	-- Requiring the payload only builds closures, so this catches a syntax error in the model's
	-- own code here, in edit mode, instead of as a dead harness inside a test nobody can see.
	local compiled, problem = Inject.Check(payloadSource)
	if not compiled then
		return nil, `the payload didn't compile: {problem}`
	end

	local failure = build(spec, payloadSource)
	if failure then
		return nil, failure
	end

	state.running = true
	state.mode = spec.mode
	state.players = spec.players
	state.startedAt = os.clock()

	if spec.mode == "session" then
		-- Wrapped in a coroutine because ExecuteMultiplayerTestAsync yields until the test ends,
		-- and the plugin has to stay answerable the whole time it's open.
		task.spawn(function()
			pcall(testService.ExecuteMultiplayerTestAsync, testService, spec.players, {})
			teardown()
		end)
		-- One frame, so an immediate failure to start is reported as one instead of looking fine.
		task.wait()
		if not state.running then
			return nil, "the test server stopped as soon as it started -- check the Output window"
		end
		return nil, nil
	end

	local ok, report = pcall(testService.ExecuteMultiplayerTestAsync, testService, spec.players, {})
	teardown()
	if not ok then
		return nil, `the test wouldn't start: {report}`
	end
	if type(report) ~= "string" then
		return nil, "the test ended without reporting -- something stopped it early, or the harness errored"
	end
	return report, nil
end

function Session.Status(): { [string]: any }
	return {
		running = state.running,
		mode = if state.running then state.mode else nil,
		players = if state.running then state.players else nil,
		seconds = if state.running then math.floor(os.clock() - state.startedAt) else nil,
	}
end

return Session
