-- Game-VM eval bridges, ported from chrrxs/roblox-mcp-primitives.
--
-- Our standard `execute_luau target=server/client-N` runs in the plugin VM
-- with a fresh ModuleScript per call. That gives a clean sandbox but means
-- `require(SomeModule)` returns a fresh copy, not the one the running game
-- scripts hold. So runtime-mutated module state is invisible to probes.
--
-- These bridges fix that by living inside the user's game scripts. Both
-- peers use the same symmetric shape:
--   - Server: a Script in ServerScriptService that creates a BindableFunction.
--     Plugin (server peer) invokes it with a fresh ModuleScript payload;
--     require() runs inside the Script VM so it shares the running server's
--     require cache.
--   - Client: a LocalScript in StarterPlayer.StarterPlayerScripts that
--     creates a BindableFunction. Plugin invokes it with a fresh ModuleScript
--     payload; require() runs inside the LocalScript VM so it shares the
--     game's require cache.
--
-- Why ModuleScript+require on both sides (no loadstring): require'd modules
-- run with the security level they were created at and don't need
-- ServerScriptService.LoadStringEnabled, so eval_server_runtime works even
-- when LoadStringEnabled=false (the default in fresh places).
--
-- Lifecycle: bridge scripts are created only in running play DataModels.
-- The server plugin peer creates the Script in runtime ServerScriptService;
-- each client plugin peer creates its LocalScript in that client's
-- PlayerScripts. Nothing is installed into the edit DataModel anymore.
-- Runtime-created scripts disappear naturally when the playtest stops.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local PeerRole = require(script.Parent.PeerRole)
local ScriptEditorService = game:GetService("ScriptEditorService")
local function getStarterPlayerScripts()
	return StarterPlayer:FindFirstChild("StarterPlayerScripts")
end
local SERVER_SCRIPT_NAME = "__MCP_ServerEvalBridge"
local CLIENT_SCRIPT_NAME = "__MCP_ClientEvalBridge"
-- Public so the eval_*_runtime tool wrappers can reference the same names.
local BRIDGE_NAMES = {
	serverScript = SERVER_SCRIPT_NAME,
	clientScript = CLIENT_SCRIPT_NAME,
	serverLocal = "__MCP_ServerEvalLocal",
	clientLocal = "__MCP_ClientEvalBridge",
}
-- Embedded Luau. The double `${...}` references our exported names so a
-- rename here propagates to both the script source and the tool wrappers.
local SERVER_BRIDGE_SOURCE = `\
-- Installed by @chrrxs/robloxstudio-mcp to power the eval_server_runtime MCP\
-- tool (shared-require-cache eval on the server during playtests). Inert\
-- outside Studio (no-ops in live games); safe to leave in place.\
\
local ServerScriptService = game:GetService("ServerScriptService")\
local RunService = game:GetService("RunService")\
\
if not RunService:IsStudio() then\
	return\
end\
\
local prevBf = ServerScriptService:FindFirstChild("{BRIDGE_NAMES.serverLocal}")\
if prevBf then prevBf:Destroy() end\
\
local bf = Instance.new("BindableFunction")\
bf.Name = "{BRIDGE_NAMES.serverLocal}"\
bf.Archivable = false\
bf.Parent = ServerScriptService\
bf.OnInvoke = function(payload)\
	if typeof(payload) ~= "Instance" or not payload:IsA("ModuleScript") then\
		return \{ ok = false, value = "payload must be a ModuleScript instance" \}\
	end\
	local ok, value = pcall(require, payload)\
	return \{ ok = ok, value = value \}\
end\
`
local CLIENT_BRIDGE_SOURCE = `\
-- Installed by @chrrxs/robloxstudio-mcp to power the eval_client_runtime MCP\
-- tool (shared-require-cache eval on the client during playtests). Inert\
-- outside Studio (no-ops in live games); safe to leave in place.\
\
local ReplicatedStorage = game:GetService("ReplicatedStorage")\
local RunService = game:GetService("RunService")\
\
if not RunService:IsStudio() then\
	return\
end\
\
local prevBf = ReplicatedStorage:FindFirstChild("{BRIDGE_NAMES.clientLocal}")\
if prevBf then prevBf:Destroy() end\
\
local bf = Instance.new("BindableFunction")\
bf.Name = "{BRIDGE_NAMES.clientLocal}"\
bf.Archivable = false\
bf.Parent = ReplicatedStorage\
bf.OnInvoke = function(payload)\
	if typeof(payload) ~= "Instance" or not payload:IsA("ModuleScript") then\
		return \{ ok = false, value = "payload must be a ModuleScript instance" \}\
	end\
	local ok, value = pcall(require, payload)\
	return \{ ok = ok, value = value \}\
end\
`
-- Stamp written onto each installed bridge Script so we can tell whether the
-- runtime bridge currently in the play DM was produced by THIS plugin build.
-- It's a djb2 hash of the actual bridge source plus the plugin version, so ANY
-- change to the source (or a version bump) yields a new stamp and triggers a
-- runtime refresh instead of keeping a stale bridge.
local STAMP_ATTR = "__MCPBridgeStamp"
local function computeBridgeStamp()
	local combined = `{SERVER_BRIDGE_SOURCE}|{CLIENT_BRIDGE_SOURCE}`
	local h = 5381
	for i = 1, #combined do
		h = (h * 33 + (string.byte(combined, i))) % 2147483647
	end
	-- "3.1.3" is replaced with the package version at package time
	-- (scripts/build-plugin.mjs injectVersion), so a release bump also restamps.
	return `{tostring(h)}-3.1.3`
end
local BRIDGE_STAMP = computeBridgeStamp()
local function setSource(scriptInst, source)
	-- ScriptEditorService is the cleaner API and integrates with Studio's
	-- edit history; fall back to direct Source mutation (allowed in plugin
	-- context with PluginSecurity) if the edit service rejects the call.
	local seOk = pcall(function()
		ScriptEditorService:UpdateSourceAsync(scriptInst, function()
			return source
		end)
	end)
	if not seOk then
		scriptInst.Source = source
	end
end
local function findEditBridgeArtifacts()
	local sps = getStarterPlayerScripts()
	return {
		server = ServerScriptService:FindFirstChild(SERVER_SCRIPT_NAME),
		client = if sps then sps:FindFirstChild(CLIENT_SCRIPT_NAME) else nil,
	}
end
local function destroyIfPresent(parent, name)
	local existing = parent:FindFirstChild(name)
	if existing then
		pcall(function()
			return existing:Destroy()
		end)
	end
end
local function cleanupEditBridgeArtifacts()
	if RunService:IsRunning() then
		return nil
	end
	local binding = findEditBridgeArtifacts()
	local server = binding.server
	local client = binding.client
	if server then
		pcall(function()
			return server:Destroy()
		end)
	end
	if client then
		pcall(function()
			return client:Destroy()
		end)
	end
end
local function serverRuntimeBridgeReady()
	local scriptInst = ServerScriptService:FindFirstChild(SERVER_SCRIPT_NAME)
	local bindable = ServerScriptService:FindFirstChild(BRIDGE_NAMES.serverLocal)
	return scriptInst ~= nil and scriptInst:GetAttribute(STAMP_ATTR) == BRIDGE_STAMP and bindable ~= nil and bindable:IsA("BindableFunction")
end
local function getPlayerScripts()
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return nil
	end
	local playerScripts = localPlayer:FindFirstChild("PlayerScripts")
	if not playerScripts then
		playerScripts = localPlayer:WaitForChild("PlayerScripts", 5)
	end
	return playerScripts
end
local function clientRuntimeBridgeReady()
	local playerScripts = getPlayerScripts()
	if not playerScripts then
		return false
	end
	local scriptInst = playerScripts:FindFirstChild(CLIENT_SCRIPT_NAME)
	local bindable = ReplicatedStorage:FindFirstChild(BRIDGE_NAMES.clientLocal)
	return scriptInst ~= nil and scriptInst:GetAttribute(STAMP_ATTR) == BRIDGE_STAMP and bindable ~= nil and bindable:IsA("BindableFunction")
end
local function installServerRuntimeBridge()
	if serverRuntimeBridgeReady() then
		return {
			installed = true,
		}
	end
	local ok, err = pcall(function()
		destroyIfPresent(ServerScriptService, SERVER_SCRIPT_NAME)
		destroyIfPresent(ServerScriptService, BRIDGE_NAMES.serverLocal)
		local serverScript = Instance.new("Script")
		serverScript.Name = SERVER_SCRIPT_NAME
		serverScript.Archivable = false
		setSource(serverScript, SERVER_BRIDGE_SOURCE)
		serverScript:SetAttribute(STAMP_ATTR, BRIDGE_STAMP)
		serverScript.Parent = ServerScriptService
	end)
	if not ok then
		return {
			installed = false,
			error = tostring(err),
		}
	end
	return {
		installed = true,
	}
end
local function installClientRuntimeBridge()
	if clientRuntimeBridgeReady() then
		return {
			installed = true,
		}
	end
	local playerScripts = getPlayerScripts()
	if not playerScripts then
		return {
			installed = false,
			error = "Players.LocalPlayer.PlayerScripts not found - cannot install client eval bridge",
		}
	end
	local ok, err = pcall(function()
		destroyIfPresent(playerScripts, CLIENT_SCRIPT_NAME)
		destroyIfPresent(ReplicatedStorage, BRIDGE_NAMES.clientLocal)
		local clientScript = Instance.new("LocalScript")
		clientScript.Name = CLIENT_SCRIPT_NAME
		clientScript.Archivable = false
		setSource(clientScript, CLIENT_BRIDGE_SOURCE)
		clientScript:SetAttribute(STAMP_ATTR, BRIDGE_STAMP)
		clientScript.Parent = playerScripts
	end)
	if not ok then
		return {
			installed = false,
			error = tostring(err),
		}
	end
	return {
		installed = true,
	}
end
local function ensureRuntimeBridgeInstalled()
	if PeerRole.detect() == "edit" then
		return {
			installed = false,
			error = "Eval bridges are installed only in play DataModels",
		}
	end
	if RunService:IsServer() then
		return installServerRuntimeBridge()
	end
	return installClientRuntimeBridge()
end
return {
	cleanupEditBridgeArtifacts = cleanupEditBridgeArtifacts,
	ensureRuntimeBridgeInstalled = ensureRuntimeBridgeInstalled,
	BRIDGE_NAMES = BRIDGE_NAMES,
}
