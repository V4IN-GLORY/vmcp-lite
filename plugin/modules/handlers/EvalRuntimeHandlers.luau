local LogService = game:GetService("LogService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local EvalBridges = require(script.Parent.Parent.EvalBridges)
local BRIDGE_NAMES = EvalBridges.BRIDGE_NAMES
local ensureRuntimeBridgeInstalled = EvalBridges.ensureRuntimeBridgeInstalled
local LuauExec = require(script.Parent.Parent.LuauExec)
local PAYLOAD_INSTANCE_NAME = "__MCPEvalPayload"
local function findBridge(config)
	local bridge = config.service:FindFirstChild(config.bridgeName)
	return if bridge and bridge:IsA("BindableFunction") then bridge else nil
end
local function waitForBridge(config, timeoutSec)
	if timeoutSec == nil then
		timeoutSec = 2
	end
	local deadline = tick() + timeoutSec
	local bridge = findBridge(config)
	while not bridge and tick() < deadline do
		task.wait(0.05)
		bridge = findBridge(config)
	end
	return bridge
end
local function getBridgeConfig()
	if not RunService:IsRunning() then
		return {
			error = "eval_*_runtime requires a running playtest.",
		}
	end
	if RunService:IsServer() then
		return {
			service = ServerScriptService,
			bridgeName = BRIDGE_NAMES.serverLocal,
			missingError = "ServerEvalBridge not found. The bridge runs inside the play DM, so a playtest must be running. The bridge installs automatically in the runtime server peer, including for manually-started playtests.",
		}
	end
	return {
		service = ReplicatedStorage,
		bridgeName = BRIDGE_NAMES.clientLocal,
		missingError = "ClientEvalBridge not found. The bridge runs inside the play DM, so a playtest must be running. The bridge installs automatically in the runtime client peer, including for manually-started playtests.",
	}
end
local function evalRuntime(requestData)
	local code = requestData.code
	if not (code ~= "" and code) or code == "" then
		return {
			error = "Code is required",
		}
	end
	local config = getBridgeConfig()
	if config.error ~= nil then
		return {
			bridge = "missing",
			error = config.error,
		}
	end
	local bridge = findBridge(config)
	if not bridge then
		local install = ensureRuntimeBridgeInstalled()
		if not install.installed then
			return {
				bridge = "missing",
				error = `{config.missingError} Runtime bridge install failed: {install.error}`,
			}
		end
		bridge = waitForBridge(config)
	end
	if not bridge then
		return {
			bridge = "missing",
			error = `{config.missingError} Runtime bridge was installed but did not become ready.`,
		}
	end
	local m = Instance.new("ModuleScript")
	m.Name = PAYLOAD_INSTANCE_NAME
	local userLines = LuauExec.countLines(code)
	local wrapped = LuauExec.buildWrapper(code, PAYLOAD_INSTANCE_NAME)
	local okSet, setErr = pcall(function()
		m.Source = wrapped
	end)
	if not okSet then
		m:Destroy()
		return {
			bridge = "ok",
			ok = false,
			error = `ModuleScript Source set failed: {tostring(setErr)}`,
		}
	end
	m.Parent = game:GetService("Workspace")
	local historyStart = #LogService:GetLogHistory()
	local invokeOk, invokeResult = pcall(function()
		return bridge:Invoke(m)
	end)
	m:Destroy()
	if not invokeOk then
		return {
			bridge = "ok",
			ok = false,
			error = tostring(invokeResult),
		}
	end
	if not (type(invokeResult) == "table") then
		return {
			bridge = "ok",
			ok = false,
			error = `Eval bridge returned invalid result: {tostring(invokeResult)}`,
		}
	end
	local bridgeResult = invokeResult
	if bridgeResult.ok ~= true then
		return {
			bridge = "ok",
			ok = false,
			error = LuauExec.recoverPayloadRequireError(
				bridgeResult.value,
				userLines,
				PAYLOAD_INSTANCE_NAME,
				historyStart
			),
		}
	end
	local inner = bridgeResult.value
	if not (type(inner) == "table") then
		return {
			bridge = "ok",
			ok = true,
			result = if inner == nil then nil else LuauExec.formatReturnValue(inner),
		}
	end
	local r = inner
	local ok = r.ok == true
	local object = {
		bridge = "ok",
		ok = ok,
		result = if ok and r.value ~= nil then LuauExec.formatReturnValue(r.value) else nil,
		error = if not ok then tostring(r.value) else nil,
	}
	object.output = if r.output ~= nil then r.output else {}
	return object
end
return {
	evalRuntime = evalRuntime,
}
