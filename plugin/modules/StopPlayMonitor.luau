-- Cross-DataModel stop_playtest signaling via plugin settings. Solo edit and
-- runtime peers share one process instanceId through PluginSession's topology
-- marker, so only the intended Studio process can consume the request.
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local PluginSession = require(script.Parent.PluginSession)
local StudioTestService = game:GetService("StudioTestService")
local SETTING_KEY_PREFIX = "MCP_STOP_PLAY_"
-- Keep this conservative. plugin:GetSetting is backed by Studio's plugin
-- settings store, and this monitor runs during every play session, including
-- manually-started Play. The official reference implementation polls at 1s.
local POLL_INTERVAL_SEC = 1
-- Total time we wait for the matching play-server DM to consume the
-- signal. Must cover: monitor detection (<= POLL_INTERVAL_SEC) +
-- StudioTestService:EndTest teardown (several seconds on heavier places).
-- 8s is intentionally shorter than the MCP request timeout but long enough
-- for the 1s monitor cadence plus ordinary Studio teardown latency.
local WAIT_FOR_CONSUMPTION_TIMEOUT_SEC = 8.0
local WAIT_POLL_SEC = 0.1
local REQUEST_TTL_SEC = 12.0
local pluginRef
local endTestIssued = false
local transportLifecycle
local function init(p)
	pluginRef = p
end
local function settingKey()
	return SETTING_KEY_PREFIX .. PluginSession.getInstanceId()
end
local function readSetting(key)
	if not pluginRef then
		return nil
	end
	local ok, value = pcall(function()
		return pluginRef:GetSetting(key)
	end)
	return if ok then value else nil
end
local function writeSetting(key, value)
	if not pluginRef then
		return false
	end
	local ok = pcall(function()
		return pluginRef:SetSetting(key, value)
	end)
	return ok
end
local function decodePayload(value)
	local decoded = value
	if type(value) == "string" then
		local ok, result = pcall(function()
			return HttpService:JSONDecode(value)
		end)
		if not ok then
			return nil
		end
		decoded = result
	end
	if not (type(decoded) == "table") then
		return nil
	end
	local payload = decoded
	if not (type(payload.kind) == "string") or not (type(payload.id) == "string") then
		return nil
	end
	return payload
end
local function writePayload(key, payload)
	local encodedOk, encoded = pcall(function()
		return HttpService:JSONEncode(payload)
	end)
	if not encodedOk or not (type(encoded) == "string") then
		return false
	end
	return writeSetting(key, encoded)
end
local function writeResult(key, request, ok, errText)
	writePayload(key, {
		kind = "result",
		id = request.id,
		requestedAt = request.requestedAt,
		consumedAt = tick(),
		ok = ok,
		error = errText,
	})
end
local function handleStopRequest(key, request)
	if request.kind ~= "request" or not (type(request.id) == "string") then
		return nil
	end
	if not (type(request.requestedAt) == "number") then
		writeSetting(key, false)
		return nil
	end
	local age = tick() - request.requestedAt
	if age < -5 or age > REQUEST_TTL_SEC then
		writeSetting(key, false)
		return nil
	end
	if endTestIssued then
		writeResult(
			key,
			request,
			false,
			"StudioTestService:EndTest was already issued for this play session, but the runtime DataModel is still alive."
		)
		return nil
	end
	if not RunService:IsRunning() or not RunService:IsServer() then
		writeResult(key, request, false, "StopPlayMonitor is not running in the server DataModel.")
		return nil
	end
	endTestIssued = true
	local lifecycle = transportLifecycle
	if lifecycle ~= nil then
		local closeOk, closeError = pcall(lifecycle.beforeEndTest)
		if not closeOk then
			warn(`[robloxstudio-mcp] Failed to close the play-server transport before EndTest: {tostring(closeError)}`)
		end
	end
	local endOk, endErr = pcall(function()
		return StudioTestService:EndTest("stopped_by_mcp")
	end)
	writeResult(key, request, endOk, if endOk then nil else tostring(endErr))
	if not endOk then
		endTestIssued = false
		if lifecycle ~= nil then
			local restoreOk, restoreError = pcall(lifecycle.afterEndTestFailure)
			if not restoreOk then
				warn(
					`[robloxstudio-mcp] Failed to restore the play-server transport after EndTest failed: {tostring(
						restoreError
					)}`
				)
			end
		end
	end
end
local function startMonitor(lifecycle)
	transportLifecycle = lifecycle
	if not pluginRef then
		warn("[robloxstudio-mcp] StopPlayMonitor.startMonitor called before init; skipping")
		return nil
	end
	task.spawn(function()
		while true do
			local myKey = settingKey()
			local payload = decodePayload(readSetting(myKey))
			if payload then
				handleStopRequest(myKey, payload)
			end
			task.wait(POLL_INTERVAL_SEC)
		end
	end)
end
local function requestStop()
	if not pluginRef then
		return {
			ok = false,
		}
	end
	local requestId = HttpService:GenerateGUID(false)
	local payload = {
		kind = "request",
		id = requestId,
		requestedAt = tick(),
	}
	local ok = writePayload(settingKey(), payload)
	return {
		ok = ok,
		requestId = if ok then requestId else nil,
	}
end
local function waitForConsumption(requestId)
	if not pluginRef then
		return {
			ok = false,
			consumed = false,
			error = "Plugin reference is not initialized.",
		}
	end
	local start = tick()
	while tick() - start < WAIT_FOR_CONSUMPTION_TIMEOUT_SEC do
		local payload = decodePayload(readSetting(settingKey()))
		if payload and payload.kind == "result" and payload.id == requestId then
			return {
				ok = payload.ok == true,
				consumed = true,
				error = payload.error,
			}
		end
		task.wait(WAIT_POLL_SEC)
	end
	return {
		ok = false,
		consumed = false,
		error = "Timed out waiting for the play-server DataModel to acknowledge stop_playtest.",
	}
end
local function clearPending(requestId)
	if not pluginRef then
		return nil
	end
	local myKey = settingKey()
	if requestId ~= nil then
		local payload = decodePayload(readSetting(myKey))
		if payload and payload.id ~= requestId then
			return nil
		end
	end
	writeSetting(myKey, false)
end
return {
	init = init,
	startMonitor = startMonitor,
	requestStop = requestStop,
	waitForConsumption = waitForConsumption,
	clearPending = clearPending,
}
