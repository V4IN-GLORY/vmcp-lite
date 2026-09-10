local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DEFAULT_DURATION_MS = 1000
local MIN_DURATION_MS = 100
local MAX_DURATION_MS = 15000
local DEFAULT_FREQUENCY = 1000
local DEFAULT_MAX_FUNCTIONS = 20
local function getProfilerService()
	local provider = game
	local ok, service = pcall(function()
		return provider:GetService("ScriptProfilerService")
	end)
	if not ok or not service then
		return {
			error = "script_profiler_unavailable",
			message = `ScriptProfilerService is unavailable: {tostring(service)}`,
		}
	end
	return service
end
local function normalizeDurationMs(value)
	if not (type(value) == "number") then
		return DEFAULT_DURATION_MS
	end
	return math.clamp(math.floor(value), MIN_DURATION_MS, MAX_DURATION_MS)
end
local function normalizeFrequency(value)
	if not (type(value) == "number") then
		return DEFAULT_FREQUENCY
	end
	return math.clamp(math.floor(value), 1, 10000)
end
local function normalizeMaxFunctions(value)
	if not (type(value) == "number") then
		return DEFAULT_MAX_FUNCTIONS
	end
	return math.clamp(math.floor(value), 1, 100)
end
local function normalizeMinTotalUs(requestData)
	local value = requestData.min_total_us
	if type(value) == "number" then
		return math.max(0, value)
	end
	return 0
end
local function stringContains(haystack, needle)
	return (string.find(string.lower(haystack), string.lower(needle), 1, true)) ~= nil
end
local function localPlayer()
	local player = Players.LocalPlayer
	local started = tick()
	while not player and tick() - started < 5 do
		task.wait(0.05)
		player = Players.LocalPlayer
	end
	return player
end
local function functionDisplayName(func)
	if type(func.Name) == "string" and func.Name ~= "" then
		return func.Name
	end
	if type(func.Source) == "string" and func.Source ~= "" then
		if type(func.Line) == "number" and func.Line > 0 then
			return `{func.Source}:{func.Line}`
		end
		return func.Source
	end
	return "<anonymous>"
end
local function flagsOf(func)
	return if type(func.Flags) == "number" then func.Flags else 0
end
local function isNativeFunction(func)
	return bit32.band(flagsOf(func), 1) ~= 0
end
local function isPluginFunction(func)
	if bit32.band(flagsOf(func), 2) ~= 0 then
		return true
	end
	return type(func.Source) == "string" and (string.find(func.Source, "MCPPlugin", 1, true)) ~= nil
end
local function isDebugLabel(func, filter)
	if filter == nil then
		return false
	end
	if not (type(func.Name) == "string") or func.Name == "" then
		return false
	end
	if not (type(func.Source) == "string") or (func.Source == "" or func.Source == "[C]" or func.Source == "GC") then
		return false
	end
	if func.Line ~= nil and func.Line ~= 0 then
		return false
	end
	if isNativeFunction(func) or isPluginFunction(func) then
		return false
	end
	return stringContains(func.Name, filter) or stringContains(func.Source, filter)
end
local function pctOfCapture(row, durationMs)
	local captureUs = durationMs * 1000
	if captureUs <= 0 then
		return nil
	end
	return math.floor((row.total_us / captureUs) * 10000 + 0.5) / 100
end
local function compactFunction(row, rank, durationMs)
	local out = {
		rank = rank,
		function_index = row.function_index,
		name = row.name,
		total_us = math.floor(row.total_us + 0.5),
	}
	local pct = pctOfCapture(row, durationMs)
	if pct ~= nil then
		out.pct_of_capture = pct
	end
	if row.source ~= nil then
		out.source = row.source
	end
	if row.line ~= nil then
		out.line = row.line
	end
	if row.is_native == true then
		out.is_native = true
	end
	if row.is_plugin == true then
		out.is_plugin = true
	end
	if row.is_debug_label == true then
		out.is_debug_label = true
	end
	return out
end
local function summarizeProfile(rawJson, profile, requestData, durationMs, frequency, eventPlayerName)
	local funcs = if type(profile.Functions) == "table" then profile.Functions else {}
	local nodes = if type(profile.Nodes) == "table" then profile.Nodes else {}
	local categories = if type(profile.Categories) == "table" then profile.Categories else {}
	local maxFunctions = normalizeMaxFunctions(requestData.max_functions)
	local minTotalUs = normalizeMinTotalUs(requestData)
	local includeNative = requestData.include_native == true
	local includePlugin = requestData.include_plugin == true
	local condition = type(requestData.filter) == "string" and requestData.filter ~= ""
	local filter = if condition then requestData.filter else nil
	local rows = {}
	local debugRows = {}
	local omittedNative = 0
	local omittedPlugin = 0
	local omittedBelowThreshold = 0
	local omittedByFilter = 0
	for i = 0, #funcs - 1 do
		local func = funcs[i + 1]
		if not (type(func) == "table") then
			continue
		end
		local info = func
		local totalUs = if type(info.TotalDuration) == "number" then info.TotalDuration else 0
		local name = functionDisplayName(info)
		local object = {
			function_index = i + 1,
			name = name,
		}
		object["source"] = if type(info.Source) == "string" then info.Source else nil
		object["line"] = if type(info.Line) == "number" then info.Line else nil
		object.total_us = totalUs
		object.is_native = if isNativeFunction(info) then true else nil
		object.is_plugin = if isPluginFunction(info) then true else nil
		object.is_debug_label = if isDebugLabel(info, filter) then true else nil
		local row = object
		if not includeNative and row.is_native == true then
			omittedNative += 1
			continue
		end
		if not includePlugin and row.is_plugin == true then
			omittedPlugin += 1
			continue
		end
		if totalUs < minTotalUs then
			omittedBelowThreshold += 1
			continue
		end
		if filter ~= nil then
			local text = `{row.name} {if row.source ~= nil then row.source else ""}`
			if not stringContains(text, filter) then
				omittedByFilter += 1
				continue
			end
		end
		table.insert(rows, row)
		if row.is_debug_label == true then
			table.insert(debugRows, row)
		end
	end
	table.sort(rows, function(a, b)
		return a.total_us > b.total_us
	end)
	table.sort(debugRows, function(a, b)
		return a.total_us > b.total_us
	end)
	local topFunctions = {}
	for i = 0, math.min(maxFunctions, #rows) - 1 do
		local arg0 = compactFunction(rows[i + 1], i + 1, durationMs)
		table.insert(topFunctions, arg0)
	end
	local debugLabels = {}
	for i = 0, math.min(maxFunctions, #debugRows) - 1 do
		local arg0 = compactFunction(debugRows[i + 1], i + 1, durationMs)
		table.insert(debugLabels, arg0)
	end
	local categoryNames = {}
	for i = 0, #categories - 1 do
		local category = categories[i + 1]
		if type(category) == "table" then
			local name = category.Name
			if type(name) == "string" then
				table.insert(categoryNames, name)
			end
		end
	end
	local omitted = {}
	local hasOmitted = false
	if omittedNative > 0 then
		omitted.native = omittedNative
		hasOmitted = true
	end
	if omittedPlugin > 0 then
		omitted.plugin = omittedPlugin
		hasOmitted = true
	end
	if omittedBelowThreshold > 0 then
		omitted.below_min_total_us = omittedBelowThreshold
		hasOmitted = true
	end
	if omittedByFilter > 0 then
		omitted.filtered_out = omittedByFilter
		hasOmitted = true
	end
	local object = {
		ok = true,
		duration_ms = durationMs,
		frequency = frequency,
	}
	local object_1 = {}
	object_1.filter = if filter ~= nil then filter else nil
	object_1.min_total_us = minTotalUs
	object_1.include_native = includeNative
	object_1.include_plugin = includePlugin
	object_1.max_functions = maxFunctions
	object_1.sort = "total_us_desc"
	object.applied = object_1
	object.json_bytes = #rawJson
	object.counts = {
		categories = #categories,
		nodes = #nodes,
		functions = #funcs,
	}
	object.top_functions = topFunctions
	object.debug_labels = debugLabels
	local result = object
	if #categoryNames > 0 then
		result.categories = categoryNames
	end
	if hasOmitted then
		result.omitted = omitted
	end
	if profile.Version ~= nil then
		result.version = profile.Version
	end
	if profile.SessionStartTime ~= nil or profile.SessionEndTime ~= nil then
		result.session = {
			start_time = profile.SessionStartTime,
			end_time = profile.SessionEndTime,
		}
	end
	if eventPlayerName ~= nil then
		result.player = eventPlayerName
	end
	if requestData.__mcp_include_raw_json == true then
		result.raw_json = rawJson
	end
	return result
end
local function captureScriptProfiler(requestData)
	if not RunService:IsRunning() then
		return {
			error = "runtime_target_required",
			message = 'Script profiler capture requires a running playtest target such as target="server" or target="client-1".',
		}
	end
	local serviceOrError = getProfilerService()
	local value = serviceOrError.IsA
	if not (value ~= 0 and value == value and value ~= "" and value) then
		return serviceOrError
	end
	local service = serviceOrError
	local durationMs = normalizeDurationMs(requestData.duration_ms)
	local frequency = normalizeFrequency(requestData.frequency)
	local isServer = RunService:IsServer()
	local isClient = RunService:IsClient() and not isServer
	local player = if isClient then localPlayer() else nil
	if not isServer and not player then
		return {
			error = "client_player_unavailable",
			message = "Could not resolve Players.LocalPlayer for client profiling.",
		}
	end
	local rawJson
	local eventPlayerName
	local connection = service.OnNewData:Connect(function(playerArg, jsonString)
		if rawJson ~= nil then
			return nil
		end
		rawJson = jsonString
		if playerArg then
			eventPlayerName = playerArg.Name
		end
	end)
	local startOk, startErr = pcall(function()
		if isServer then
			service:ServerStart(frequency)
		else
			service:ClientStart(player, frequency)
		end
	end)
	if not startOk then
		connection:Disconnect()
		return {
			error = "script_profiler_start_failed",
			message = tostring(startErr),
		}
	end
	task.wait(durationMs / 1000)
	local stopOk, stopErr = pcall(function()
		if isServer then
			service:ServerStop()
			service:ServerRequestData()
		else
			service:ClientStop(player)
			service:ClientRequestData(player)
		end
	end)
	if not stopOk then
		connection:Disconnect()
		return {
			error = "script_profiler_stop_failed",
			message = tostring(stopErr),
		}
	end
	local requestedAt = tick()
	while rawJson == nil and tick() - requestedAt < 5 do
		task.wait(0.05)
	end
	connection:Disconnect()
	if rawJson == nil then
		return {
			error = "script_profiler_data_timeout",
			message = "ScriptProfilerService did not emit OnNewData after requesting profiler data.",
		}
	end
	local decodeOk, decoded = pcall(function()
		return HttpService:JSONDecode(rawJson)
	end)
	if not decodeOk then
		return {
			error = "script_profiler_decode_failed",
			message = tostring(decoded),
			json_bytes = #rawJson,
		}
	end
	return summarizeProfile(rawJson, decoded, requestData, durationMs, frequency, eventPlayerName)
end
return {
	captureScriptProfiler = captureScriptProfiler,
}
