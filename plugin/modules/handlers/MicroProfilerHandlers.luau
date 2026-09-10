local RunService = game:GetService("RunService")
local DEFAULT_DURATION_MS = 1000
local MIN_DURATION_MS = 100
local MAX_DURATION_MS = 5000
local DEFAULT_MAX_TIMERS = 20
local DEFAULT_MAX_GROUPS = 20
local DEFAULT_MAX_TIMERS_PER_GROUP = 5
local DEFAULT_MAX_RELATED_TIMERS = 3
local DEFAULT_MAX_EVENTS = 250000
local MAX_EVENTS = 1000000
local COOPERATIVE_CLOCK_CHECK_INTERVAL = 128
local MAX_COOPERATIVE_SLICE_SECONDS = 0.008
local DEFAULT_FRAME_WINDOW = 240
local BASE64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local PAD_BYTE = (string.byte("="))
local B64 = {}
for i = 0, 63 do
	B64[i + 1] = (string.byte(BASE64_CHARS, i + 1))
end
local FOCUS_GROUP_MASKS = {
	all = {},
	script = { "Script", "LuaBridge" },
	physics = { "Physics" },
	render = { "Render" },
	network = { "Network", "RbxTransport", "Replicator" },
	jobs = { "Jobs" },
}
local cachedLibMP
-- Sampling the clock avoids a timing call for every event while still bounding
-- each VM resumption. Sorting uses the same checkpoint so no full sort is atomic.
local function createCooperativeCheckpoint()
	local operationsSinceClockCheck = 0
	local sliceStartedAt = os.clock()
	return function()
		operationsSinceClockCheck += 1
		if operationsSinceClockCheck < COOPERATIVE_CLOCK_CHECK_INTERVAL then
			return nil
		end
		operationsSinceClockCheck = 0
		if os.clock() - sliceStartedAt < MAX_COOPERATIVE_SLICE_SECONDS then
			return nil
		end
		task.wait()
		sliceStartedAt = os.clock()
	end
end
local function cooperativeSort(values, comesBefore, checkpoint)
	local count = #values
	if count < 2 then
		return nil
	end
	local function siftDown(start, lastIndex)
		local root = start
		while root * 2 + 1 <= lastIndex do
			checkpoint()
			local candidate = root
			local left = root * 2 + 1
			if comesBefore(values[candidate + 1], values[left + 1]) then
				candidate = left
			end
			local right = left + 1
			if right <= lastIndex and comesBefore(values[candidate + 1], values[right + 1]) then
				candidate = right
			end
			if candidate == root then
				return nil
			end
			local value = values[root + 1]
			values[root + 1] = values[candidate + 1]
			values[candidate + 1] = value
			root = candidate
		end
	end
	do
		local start = math.floor((count - 2) / 2)
		local shouldIncrement = false
		while true do
			if shouldIncrement then
				start -= 1
			else
				shouldIncrement = true
			end
			if not (start >= 0) then
				break
			end
			siftDown(start, count - 1)
			checkpoint()
		end
	end
	do
		local lastIndex = count - 1
		local shouldIncrement = false
		while true do
			if shouldIncrement then
				lastIndex -= 1
			else
				shouldIncrement = true
			end
			if not (lastIndex > 0) then
				break
			end
			local value = values[1]
			values[1] = values[lastIndex + 1]
			values[lastIndex + 1] = value
			checkpoint()
			siftDown(0, lastIndex - 1)
		end
	end
end
local function normalizeDurationMs(value)
	if not (type(value) == "number") then
		return DEFAULT_DURATION_MS
	end
	return math.clamp(math.floor(value), MIN_DURATION_MS, MAX_DURATION_MS)
end
local function normalizeMaxTimers(value)
	if not (type(value) == "number") then
		return DEFAULT_MAX_TIMERS
	end
	return math.clamp(math.floor(value), 1, 100)
end
local function normalizeMaxGroups(value)
	if not (type(value) == "number") then
		return DEFAULT_MAX_GROUPS
	end
	return math.clamp(math.floor(value), 1, 100)
end
local function normalizeMaxTimersPerGroup(value)
	if not (type(value) == "number") then
		return DEFAULT_MAX_TIMERS_PER_GROUP
	end
	return math.clamp(math.floor(value), 0, 20)
end
local function normalizeMaxRelatedTimers(value)
	if not (type(value) == "number") then
		return DEFAULT_MAX_RELATED_TIMERS
	end
	return math.clamp(math.floor(value), 0, 10)
end
local function normalizeMaxEvents(value)
	if not (type(value) == "number") then
		return DEFAULT_MAX_EVENTS
	end
	return math.clamp(math.floor(value), 10000, MAX_EVENTS)
end
local function normalizeFrameWindow(value)
	if not (type(value) == "number") then
		return DEFAULT_FRAME_WINDOW
	end
	return math.clamp(math.floor(value), 1, 2000)
end
local function normalizeMinTotalUs(value)
	if not (type(value) == "number") then
		return 0
	end
	return math.max(0, value)
end
local function normalizeFocus(value)
	if not (type(value) == "string") or FOCUS_GROUP_MASKS[value] == nil then
		return "all"
	end
	return value
end
local function stringContains(haystack, needle)
	return (string.find(string.lower(haystack), string.lower(needle), 1, true)) ~= nil
end
local function rawToUs(raw)
	return math.floor(raw / 1000 + 0.5)
end
local function round2(value)
	return math.floor(value * 100 + 0.5) / 100
end
local function perSecond(value, durationMs)
	return if durationMs > 0 then round2(value / (durationMs / 1000)) else value
end
local function percent(part, whole)
	return if whole > 0 then round2((part / whole) * 100) else 0
end
local function ratio(numerator, denominator)
	if denominator <= 0 then
		return nil
	end
	return round2(numerator / denominator)
end
local function percentile(sortedValues, fraction)
	if #sortedValues == 0 then
		return 0
	end
	local index = math.clamp(math.ceil(#sortedValues * fraction), 1, #sortedValues) - 1
	return sortedValues[index + 1]
end
local function copyRecord(row)
	local out = {}
	for key, value in pairs(row) do
		out[key] = value
	end
	return out
end
local function pickFields(row, fields)
	local out = {}
	for _, field in fields do
		local value = row[field]
		if value ~= nil then
			out[field] = value
		end
	end
	return out
end
local function addFrameRaw(map, frameId, raw)
	if frameId <= 0 then
		return nil
	end
	local _map = map
	local exp = frameId
	local condition = map[frameId]
	if condition == nil then
		condition = 0
	end
	_map[exp] = condition + raw
end
local function summarizeFrameImpact(frameRawById, analyzedFrames, checkpoint)
	local condition = frameRawById == nil
	if not condition then
		-- ▼ ReadonlyMap.size ▼
		local _size = 0
		for _ in frameRawById do
			_size += 1
		end
		-- ▲ ReadonlyMap.size ▲
		condition = _size == 0
	end
	if condition then
		return {
			active_frame_count = 0,
			active_frame_pct = 0,
			inclusive_us_per_frame = 0,
			p95_active_frame_inclusive_us = 0,
			max_frame_inclusive_us = 0,
		}
	end
	local values = {}
	local totalUs = 0
	local maxUs = 0
	local maxFrameId = 0
	for frameId, raw in frameRawById do
		checkpoint()
		local us = rawToUs(raw)
		table.insert(values, us)
		totalUs += us
		if us > maxUs then
			maxUs = us
			maxFrameId = frameId
		end
	end
	cooperativeSort(values, function(a, b)
		return a < b
	end, checkpoint)
	return {
		active_frame_count = #values,
		active_frame_pct = percent(#values, analyzedFrames),
		inclusive_us_per_frame = if analyzedFrames > 0 then round2(totalUs / analyzedFrames) else totalUs,
		avg_active_frame_inclusive_us = if #values > 0 then round2(totalUs / #values) else 0,
		p95_active_frame_inclusive_us = percentile(values, 0.95),
		max_frame_inclusive_us = maxUs,
		max_frame_id = maxFrameId,
	}
end
local function encodeBase64(buf, checkpoint)
	local len = buffer.len(buf)
	local fullTriples = math.floor(len / 3)
	local remaining = len - fullTriples * 3
	local outLen = (fullTriples + (if remaining > 0 then 1 else 0)) * 4
	local out = buffer.create(outLen)
	local si = 0
	local di = 0
	for t = 0, fullTriples - 1 do
		local b0 = buffer.readu8(buf, si)
		local b1 = buffer.readu8(buf, si + 1)
		local b2 = buffer.readu8(buf, si + 2)
		buffer.writeu8(out, di, B64[bit32.rshift(b0, 2) + 1])
		buffer.writeu8(out, di + 1, B64[bit32.bor(bit32.lshift(bit32.band(b0, 3), 4), bit32.rshift(b1, 4)) + 1])
		buffer.writeu8(out, di + 2, B64[bit32.bor(bit32.lshift(bit32.band(b1, 15), 2), bit32.rshift(b2, 6)) + 1])
		buffer.writeu8(out, di + 3, B64[bit32.band(b2, 63) + 1])
		si += 3
		di += 4
		checkpoint()
	end
	if remaining == 2 then
		local b0 = buffer.readu8(buf, si)
		local b1 = buffer.readu8(buf, si + 1)
		buffer.writeu8(out, di, B64[bit32.rshift(b0, 2) + 1])
		buffer.writeu8(out, di + 1, B64[bit32.bor(bit32.lshift(bit32.band(b0, 3), 4), bit32.rshift(b1, 4)) + 1])
		buffer.writeu8(out, di + 2, B64[bit32.lshift(bit32.band(b1, 15), 2) + 1])
		buffer.writeu8(out, di + 3, PAD_BYTE)
	elseif remaining == 1 then
		local b0 = buffer.readu8(buf, si)
		buffer.writeu8(out, di, B64[bit32.rshift(b0, 2) + 1])
		buffer.writeu8(out, di + 1, B64[bit32.lshift(bit32.band(b0, 3), 4) + 1])
		buffer.writeu8(out, di + 2, PAD_BYTE)
		buffer.writeu8(out, di + 3, PAD_BYTE)
	end
	return buffer.tostring(out)
end
local function requireLibMP()
	if cachedLibMP ~= nil then
		return cachedLibMP
	end
	local includeFolder = script.Parent.Parent.Parent:FindFirstChild("include")
	local libModule = includeFolder and includeFolder:FindFirstChild("LibMP")
	if not libModule or not libModule:IsA("ModuleScript") then
		return {
			error = "libmp_missing",
			message = "The MCP plugin bundle does not contain include/LibMP.",
		}
	end
	local ok, libOrErr = pcall(function()
		return require(libModule)
	end)
	if not ok then
		return {
			error = "libmp_require_failed",
			message = tostring(libOrErr),
		}
	end
	cachedLibMP = libOrErr
	return cachedLibMP
end
local function safeCall(fn)
	local ok, value = pcall(fn)
	if ok then
		return true, value
	end
	return false, tostring(value)
end
local function isIdleTimer(info)
	local name = string.lower(info.name)
	if name == "sleep" or name == "idle" then
		return true
	end
	if (string.find(name, "sleep", 1, true)) ~= nil then
		return true
	end
	return false
end
local function recommendedToolsForGroups(groups, targetRole)
	local tools = {}
	local seen = {}
	for _, row in groups do
		local group = row.group
		if not (type(group) == "string") or seen[group] ~= nil then
			continue
		end
		seen[group] = true
		if group == "Script" or group == "LuaBridge" then
			local arg0 = {
				tool = "capture_script_profiler",
				arguments = {
					target = targetRole,
					duration_ms = 1000,
				},
				reason = "Script/LuaBridge timers are present.",
			}
			table.insert(tools, arg0)
		elseif group == "Physics" then
			table.insert(tools, {
				tool = "get_scene_analysis",
				reason = "Physics timers are present; inspect scene complexity.",
			})
		elseif group == "Render" then
			table.insert(tools, {
				tool = "capture_screenshot",
				reason = "Render timers are present; inspect visible scene/UI state.",
			})
		elseif group == "Network" or group == "RbxTransport" or group == "Replicator" then
			table.insert(tools, {
				tool = "get_runtime_logs",
				reason = "Network/replication timers are present; correlate with gameplay events.",
			})
		elseif group == "Jobs" then
			local arg0 = {
				tool = "capture_micro_profiler",
				arguments = {
					target = targetRole,
					focus = "jobs",
				},
				reason = "Jobs timers are present; narrow to job lanes if needed.",
			}
			table.insert(tools, arg0)
		end
		if #tools >= 3 then
			break
		end
	end
	return tools
end
local function collectFrameSummary(session, startFrame, frameMax, checkpoint)
	local frameRows = {}
	local durations = {}
	local incompleteFrames = 0
	local pausedFrames = 0
	do
		local _frameId = startFrame
		local shouldIncrement = false
		while true do
			local frameId = _frameId
			if shouldIncrement then
				frameId += 1
			else
				shouldIncrement = true
			end
			if not (frameId <= frameMax) then
				break
			end
			checkpoint()
			local ok, descOrErr = safeCall(function()
				return session:GetFrameDesc(frameId)
			end)
			if not ok or not (descOrErr ~= "" and descOrErr) then
				_frameId = frameId
				continue
			end
			local desc = descOrErr
			local tickStart = desc:TickStartCpu()
			local tickEnd = desc:TickEndCpu()
			local durationRaw = tickEnd - tickStart
			local isIncomplete = desc:IsIncomplete()
			local isPaused = desc:IsPaused()
			if isIncomplete then
				incompleteFrames += 1
			end
			if isPaused then
				pausedFrames += 1
			end
			if durationRaw <= 0 or durationRaw > 1000000000000 then
				_frameId = frameId
				continue
			end
			local durationUs = rawToUs(durationRaw)
			table.insert(durations, durationUs)
			local row = {
				frame_id = frameId,
				duration_us = durationUs,
			}
			if isIncomplete then
				row.incomplete = true
			end
			if isPaused then
				row.paused = true
			end
			table.insert(frameRows, row)
			_frameId = frameId
		end
	end
	cooperativeSort(durations, function(a, b)
		return a < b
	end, checkpoint)
	cooperativeSort(frameRows, function(a, b)
		return a.duration_us > b.duration_us
	end, checkpoint)
	local totalUs = 0
	for _, duration in durations do
		totalUs += duration
		checkpoint()
	end
	local topFrames = {}
	do
		local i = 0
		local shouldIncrement = false
		while true do
			if shouldIncrement then
				i += 1
			else
				shouldIncrement = true
			end
			if not (i < math.min(10, #frameRows)) then
				break
			end
			table.insert(topFrames, frameRows[i + 1])
		end
	end
	local count = #durations
	return {
		frames = count,
		total_duration_us = totalUs,
		avg_us = if count > 0 then round2(totalUs / count) else 0,
		p50_us = percentile(durations, 0.5),
		p95_us = percentile(durations, 0.95),
		max_us = if count > 0 then durations[count] else 0,
		incomplete_frames = incompleteFrames,
		paused_frames = pausedFrames,
		top_frames = topFrames,
	}
end
local function captureMicroProfiler(requestData)
	if not RunService:IsRunning() then
		return {
			error = "runtime_target_required",
			message = 'MicroProfiler capture requires a running playtest target such as target="server" or target="client-1".',
		}
	end
	local libOrError = requireLibMP()
	if libOrError.Control == nil then
		return libOrError
	end
	local LibMP = libOrError
	local durationMs = normalizeDurationMs(requestData.duration_ms)
	local maxTimers = normalizeMaxTimers(requestData.max_timers)
	local maxGroups = normalizeMaxGroups(requestData.max_groups)
	local maxTimersPerGroup = normalizeMaxTimersPerGroup(requestData.max_timers_per_group)
	local maxRelatedTimers = normalizeMaxRelatedTimers(requestData.max_related_timers)
	local maxEvents = normalizeMaxEvents(requestData.max_events)
	local frameWindow = normalizeFrameWindow(requestData.frame_window)
	local minTotalUs = normalizeMinTotalUs(requestData.min_total_us)
	local focus = normalizeFocus(requestData.focus)
	local condition = type(requestData.filter) == "string" and requestData.filter ~= ""
	local filter = if condition then requestData.filter else nil
	local includeIdle = requestData.include_idle == true
	local includeGpu = requestData.include_gpu == true
	local includeRawBuffer = requestData.__mcp_include_raw_buffer == true
	local includeComparisonIndex = requestData.__mcp_include_comparison_index == true
	local targetRole = if type(requestData.__mcp_target_role) == "string"
		then requestData.__mcp_target_role
		else "runtime"
	local backend = {
		accessible = LibMP.Control:IsBackendAccessible(),
		ready = LibMP.Control:IsBackendReady(),
		compatible = LibMP.Control:IsBackendVersionCompatible(),
		versions = LibMP.Versions,
	}
	if not backend.accessible or not backend.ready or not backend.compatible then
		return {
			error = "micro_profiler_backend_unavailable",
			message = "MicroProfilerService backend is not accessible, ready, and compatible in this runtime peer.",
			backend = backend,
		}
	end
	local profilerOk, profilerResult = safeCall(function()
		return LibMP.Control:EnableProfiler(true)
	end)
	if not profilerOk then
		return {
			error = "micro_profiler_enable_failed",
			message = tostring(profilerResult),
			backend = backend,
		}
	end
	local captureStartOk, captureStartResult = safeCall(function()
		return LibMP.Control:EnableCapture(true)
	end)
	if not captureStartOk then
		return {
			error = "micro_profiler_capture_start_failed",
			message = tostring(captureStartResult),
			backend = backend,
		}
	end
	task.wait(durationMs / 1000)
	local captureStopOk, captureStopResult = safeCall(function()
		return LibMP.Control:EnableCapture(false)
	end)
	if not captureStopOk then
		return {
			error = "micro_profiler_capture_stop_failed",
			message = tostring(captureStopResult),
			backend = backend,
		}
	end
	local bufferOk, snapshotOrErr = safeCall(function()
		return LibMP.Control:CaptureToBufferSync()
	end)
	if not bufferOk then
		return {
			error = "micro_profiler_snapshot_failed",
			message = tostring(snapshotOrErr),
			backend = backend,
		}
	end
	local snapshot = snapshotOrErr
	local sessionOk, sessionOrErr = safeCall(function()
		return LibMP.Session.OpenFromBuffer(snapshot)
	end)
	if not sessionOk or not (sessionOrErr ~= "" and sessionOrErr) then
		return {
			error = "micro_profiler_decode_failed",
			message = tostring(sessionOrErr),
			buffer_bytes = buffer.len(snapshot),
			backend = backend,
		}
	end
	local session = sessionOrErr
	if not session:IsValid() then
		session:Dispose()
		return {
			error = "micro_profiler_session_invalid",
			buffer_bytes = buffer.len(snapshot),
			backend = backend,
		}
	end
	local timerIds = session:FetchTimerIds() or {}
	local threadIds = session:FetchThreadIds() or {}
	local frameMin = session:GetFrameIdMin()
	local frameMax = session:GetFrameIdMax()
	local startFrame = math.max(frameMin, frameMax - frameWindow + 1)
	local framesConsidered = if frameMax >= startFrame then frameMax - startFrame + 1 else 0
	local groupCache = {}
	local timerCache = {}
	local threadCache = {}
	local function getGroupName(groupId)
		if groupId == nil then
			return nil
		end
		local cached = groupCache[groupId]
		if cached ~= nil then
			return cached
		end
		local ok, descOrErr = safeCall(function()
			return session:FetchGroupDesc(groupId)
		end)
		local desc = if ok then descOrErr else nil
		local condition_1 = desc
		if condition_1 then
			condition_1 = type(desc.GroupName) == "string"
			if condition_1 then
				condition_1 = desc.GroupName ~= ""
			end
		end
		local name = if condition_1 then desc.GroupName else tostring(groupId)
		groupCache[groupId] = name
		return name
	end
	local function getTimerInfo(timerId)
		local cached = timerCache[timerId]
		if cached ~= nil then
			return cached
		end
		local ok, descOrErr = safeCall(function()
			return session:FetchTimerDesc(timerId)
		end)
		local desc = if ok then descOrErr else nil
		local condition_1 = desc and type(desc.GroupId) == "number"
		local groupId = if condition_1 then desc.GroupId else nil
		local object = {
			timer_id = timerId,
		}
		local condition_2 = desc
		if condition_2 then
			condition_2 = type(desc.TimerName) == "string"
			if condition_2 then
				condition_2 = desc.TimerName ~= ""
			end
		end
		object.name = if condition_2 then desc.TimerName else tostring(timerId)
		object.group_id = groupId
		object.group = getGroupName(groupId)
		object.is_user_timer = if desc and desc.IsUserTimer == true then true else nil
		local info = object
		timerCache[timerId] = info
		return info
	end
	local function getThreadInfo(threadId)
		local cached = threadCache[threadId]
		if cached ~= nil then
			return cached
		end
		local ok, descOrErr = safeCall(function()
			return session:FetchThreadDesc(threadId)
		end)
		local desc = if ok then descOrErr else nil
		local object = {
			thread_id = threadId,
		}
		local condition_1 = desc
		if condition_1 then
			condition_1 = type(desc.ThreadName) == "string"
			if condition_1 then
				condition_1 = desc.ThreadName ~= ""
			end
		end
		object.name = if condition_1 then desc.ThreadName else tostring(threadId)
		local info = object
		if desc and desc.IsGpu == true then
			info.is_gpu = true
		end
		if desc and type(desc.BufferSize) == "number" then
			info.buffer_size = desc.BufferSize
		end
		threadCache[threadId] = info
		return info
	end
	local function addTimerAggregate(map, timerId, inclusiveRaw, exclusiveRaw)
		local aggregate = map[timerId]
		if aggregate == nil then
			aggregate = {
				timer_id = timerId,
				inclusive_raw = 0,
				exclusive_raw = 0,
				count = 0,
				max_raw = 0,
			}
			map[timerId] = aggregate
		end
		aggregate.inclusive_raw += inclusiveRaw
		aggregate.exclusive_raw += exclusiveRaw
		aggregate.count += 1
		if inclusiveRaw > aggregate.max_raw then
			aggregate.max_raw = inclusiveRaw
		end
	end
	local focusMasks = FOCUS_GROUP_MASKS[focus] or {}
	local focusGroupIds = {}
	for _, mask in focusMasks do
		local ok, idsOrErr = safeCall(function()
			return session:FindGroupIds(mask, false)
		end)
		if ok and type(idsOrErr) == "table" then
			for _1, id in idsOrErr do
				if not (table.find(focusGroupIds, id) ~= nil) then
					table.insert(focusGroupIds, id)
				end
			end
		end
	end
	local iteratorConfig = {
		StartFrameId = startFrame,
		EndFrameId = frameMax,
		SkipGpuThreads = not includeGpu,
		SkipEvents = true,
		SkipPausedFrames = true,
		SkipFrameBoundaries = true,
	}
	if #focusGroupIds > 0 then
		iteratorConfig.GroupIds = focusGroupIds
	end
	local iterator = session:CreateLogIterator()
	local configOk, configErr = safeCall(function()
		iterator:Configure(iteratorConfig)
		return true
	end)
	if not configOk then
		iterator:Dispose()
		session:Dispose()
		return {
			error = "micro_profiler_iterator_config_failed",
			message = tostring(configErr),
			backend = backend,
		}
	end
	local checkpoint = createCooperativeCheckpoint()
	local stacks = {}
	local aggregates = {}
	local timerThreadAggregates = {}
	local timerFrameAggregates = {}
	local edgeAggregates = {}
	local sampledFrames = {}
	local eventsSampled = 0
	local enterEvents = 0
	local exitEvents = 0
	local unmatchedExits = 0
	local droppedSpans = 0
	local sampledFrameMin
	local sampledFrameMax
	local lastProcessedFrameId
	local lastProcessedTimestampRaw
	while eventsSampled < maxEvents do
		checkpoint()
		if not iterator:Step() then
			break
		end
		eventsSampled += 1
		local state = iterator:GetState()
		if not state then
			continue
		end
		local frameId = state:FrameId()
		local threadId = state:ThreadId()
		local timerId = state:TimerId()
		local timestampRaw = state:Timestamp()
		lastProcessedFrameId = frameId
		lastProcessedTimestampRaw = timestampRaw
		if frameId > 0 then
			sampledFrames[frameId] = true
			if sampledFrameMin == nil or frameId < sampledFrameMin then
				sampledFrameMin = frameId
			end
			if sampledFrameMax == nil or frameId > sampledFrameMax then
				sampledFrameMax = frameId
			end
		end
		local stack = stacks[threadId]
		if stack == nil then
			stack = {}
			stacks[threadId] = stack
		end
		if state:IsEnter() then
			enterEvents += 1
			local _stack = stack
			local arg0 = {
				timerId = timerId,
				timestampRaw = timestampRaw,
				childRaw = 0,
				frameId = frameId,
			}
			table.insert(_stack, arg0)
		elseif state:IsExit() then
			exitEvents += 1
			local entry
			while #stack > 0 do
				checkpoint()
				-- ▼ Array.pop ▼
				local length = #stack
				local result = stack[length]
				stack[length] = nil
				-- ▲ Array.pop ▲
				local candidate = result
				if candidate and candidate.timerId == timerId then
					entry = candidate
					break
				end
			end
			if entry == nil then
				unmatchedExits += 1
				continue
			end
			local inclusiveRaw = timestampRaw - entry.timestampRaw
			if inclusiveRaw < 0 or inclusiveRaw > 1000000000000 then
				droppedSpans += 1
				continue
			end
			local exclusiveRaw = math.max(0, inclusiveRaw - entry.childRaw)
			local parent = stack[#stack]
			if parent ~= nil then
				parent.childRaw += inclusiveRaw
				local edgeKey = `{parent.timerId}:{timerId}`
				local edge = edgeAggregates[edgeKey]
				if edge == nil then
					edge = {
						parent_timer_id = parent.timerId,
						child_timer_id = timerId,
						inclusive_raw = 0,
						count = 0,
						max_raw = 0,
					}
					edgeAggregates[edgeKey] = edge
				end
				edge.inclusive_raw += inclusiveRaw
				edge.count += 1
				if inclusiveRaw > edge.max_raw then
					edge.max_raw = inclusiveRaw
				end
			end
			addTimerAggregate(aggregates, timerId, inclusiveRaw, exclusiveRaw)
			local frameMap = timerFrameAggregates[timerId]
			if frameMap == nil then
				frameMap = {}
				timerFrameAggregates[timerId] = frameMap
			end
			addFrameRaw(frameMap, if entry.frameId > 0 then entry.frameId else frameId, inclusiveRaw)
			local threadMap = timerThreadAggregates[timerId]
			if threadMap == nil then
				threadMap = {}
				timerThreadAggregates[timerId] = threadMap
			end
			addTimerAggregate(threadMap, threadId, inclusiveRaw, exclusiveRaw)
		end
	end
	-- ▼ ReadonlySet.size ▼
	local _size = 0
	for _ in sampledFrames do
		_size += 1
	end
	-- ▲ ReadonlySet.size ▲
	local sampledFrameCoveragePct = percent(_size, framesConsidered)
	local analysisFrameMin = if sampledFrameMin ~= nil then sampledFrameMin else startFrame
	local analysisFrameMax = if sampledFrameMax ~= nil then sampledFrameMax else frameMax
	local frameSummary = collectFrameSummary(session, analysisFrameMin, analysisFrameMax, checkpoint)
	local condition_3 = type(frameSummary.frames) == "number" and frameSummary.frames > 0
	local _result
	if condition_3 then
		_result = frameSummary.frames
	else
		-- ▼ ReadonlySet.size ▼
		local size_1 = 0
		for _ in sampledFrames do
			size_1 += 1
		end
		-- ▲ ReadonlySet.size ▲
		local _result_1
		if size_1 > 0 then
			-- ▼ ReadonlySet.size ▼
			local size_2 = 0
			for _ in sampledFrames do
				size_2 += 1
			end
			-- ▲ ReadonlySet.size ▲
			_result_1 = size_2
		else
			_result_1 = framesConsidered
		end
		_result = _result_1
	end
	local analysisFrameCount = _result
	local condition_4 = type(frameSummary.total_duration_us) == "number" and frameSummary.total_duration_us > 0
	local analysisDurationUs = if condition_4 then frameSummary.total_duration_us else durationMs * 1000
	local analysisDurationMs = analysisDurationUs / 1000
	local rows = {}
	local rowsByTimerId = {}
	local groupAggregates = {}
	local groupTimerRows = {}
	local groupFrameAggregates = {}
	local threadAggregates = {}
	local threadTimerRows = {}
	local omittedIdle = 0
	local omittedBelowThreshold = 0
	local omittedByFilter = 0
	for timerId, aggregate in aggregates do
		checkpoint()
		local info = getTimerInfo(timerId)
		local totalUs = rawToUs(aggregate.inclusive_raw)
		if not includeIdle and isIdleTimer(info) then
			omittedIdle += 1
			continue
		end
		if totalUs < minTotalUs then
			omittedBelowThreshold += 1
			continue
		end
		if filter ~= nil then
			local searchable = `{info.name} {if info.group ~= nil then info.group else ""}`
			if not stringContains(searchable, filter) then
				omittedByFilter += 1
				continue
			end
		end
		local group = if info.group ~= nil then info.group else "<unknown>"
		local inclusiveUs = rawToUs(aggregate.inclusive_raw)
		local exclusiveUs = rawToUs(aggregate.exclusive_raw)
		local avgUs = if aggregate.count > 0 then round2(totalUs / aggregate.count) else 0
		local maxUs = rawToUs(aggregate.max_raw)
		local groupAgg = groupAggregates[group]
		if groupAgg == nil then
			groupAgg = {
				group = group,
				inclusive_raw = 0,
				exclusive_raw = 0,
				count = 0,
			}
			groupAggregates[group] = groupAgg
		end
		groupAgg.inclusive_raw += aggregate.inclusive_raw
		groupAgg.exclusive_raw += aggregate.exclusive_raw
		groupAgg.count += aggregate.count
		local row = {
			timer_id = timerId,
			name = info.name,
			group = group,
			inclusive_us = inclusiveUs,
			inclusive_us_per_s = perSecond(inclusiveUs, analysisDurationMs),
			exclusive_us = exclusiveUs,
			exclusive_pct = percent(exclusiveUs, inclusiveUs),
			count = aggregate.count,
			count_per_s = perSecond(aggregate.count, analysisDurationMs),
			count_per_frame = if analysisFrameCount > 0
				then round2(aggregate.count / analysisFrameCount)
				else aggregate.count,
			avg_invocation_us = avgUs,
			max_invocation_us = maxUs,
			pct_of_analyzed_wall = percent(inclusiveUs, analysisDurationUs),
		}
		local maxToAvg = ratio(maxUs, avgUs)
		if maxToAvg ~= nil then
			row.max_to_avg = maxToAvg
		end
		local timerFrameImpact = summarizeFrameImpact(timerFrameAggregates[timerId], analysisFrameCount, checkpoint)
		for key, value in pairs(timerFrameImpact) do
			row[key] = value
		end
		if info.is_user_timer == true then
			row.is_user_timer = true
		end
		table.insert(rows, row)
		rowsByTimerId[timerId] = row
		local timerRows = groupTimerRows[group]
		if timerRows == nil then
			timerRows = {}
			groupTimerRows[group] = timerRows
		end
		table.insert(timerRows, row)
		local timerFrames = timerFrameAggregates[timerId]
		if timerFrames ~= nil then
			local groupFrames = groupFrameAggregates[group]
			if groupFrames == nil then
				groupFrames = {}
				groupFrameAggregates[group] = groupFrames
			end
			for frameId, raw in timerFrames do
				addFrameRaw(groupFrames, frameId, raw)
				checkpoint()
			end
		end
		local perThread = timerThreadAggregates[timerId]
		if perThread ~= nil then
			local timerThreadSummaryRows = {}
			for threadId, threadAggregate in perThread do
				checkpoint()
				local threadAggregateRow = threadAggregates[threadId]
				if threadAggregateRow == nil then
					threadAggregateRow = {
						timer_id = threadId,
						inclusive_raw = 0,
						exclusive_raw = 0,
						count = 0,
						max_raw = 0,
					}
					threadAggregates[threadId] = threadAggregateRow
				end
				threadAggregateRow.inclusive_raw += threadAggregate.inclusive_raw
				threadAggregateRow.exclusive_raw += threadAggregate.exclusive_raw
				threadAggregateRow.count += threadAggregate.count
				if threadAggregate.max_raw > threadAggregateRow.max_raw then
					threadAggregateRow.max_raw = threadAggregate.max_raw
				end
				local threadRows = threadTimerRows[threadId]
				if threadRows == nil then
					threadRows = {}
					threadTimerRows[threadId] = threadRows
				end
				local threadTotalUs = rawToUs(threadAggregate.inclusive_raw)
				local threadExclusiveUs = rawToUs(threadAggregate.exclusive_raw)
				local threadAvgUs = if threadAggregate.count > 0
					then round2(threadTotalUs / threadAggregate.count)
					else 0
				local threadInfo = getThreadInfo(threadId)
				local threadTimerRow = {
					thread_id = threadId,
					thread_name = threadInfo.name,
					is_gpu = threadInfo.is_gpu,
					timer_id = timerId,
					name = info.name,
					group = group,
					inclusive_us = threadTotalUs,
					inclusive_us_per_s = perSecond(threadTotalUs, analysisDurationMs),
					exclusive_us = threadExclusiveUs,
					count = threadAggregate.count,
					count_per_s = perSecond(threadAggregate.count, analysisDurationMs),
					avg_invocation_us = threadAvgUs,
					max_invocation_us = rawToUs(threadAggregate.max_raw),
				}
				local threadMaxToAvg = ratio(threadTimerRow.max_invocation_us, threadAvgUs)
				if threadMaxToAvg ~= nil then
					threadTimerRow.max_to_avg = threadMaxToAvg
				end
				table.insert(threadRows, threadTimerRow)
				local arg0 = {
					thread_id = threadId,
					thread_name = threadInfo.name,
					is_gpu = threadInfo.is_gpu,
					inclusive_us = threadTotalUs,
					exclusive_us = threadExclusiveUs,
					count = threadAggregate.count,
				}
				table.insert(timerThreadSummaryRows, arg0)
			end
			cooperativeSort(timerThreadSummaryRows, function(a, b)
				return a.inclusive_us > b.inclusive_us
			end, checkpoint)
			if maxRelatedTimers > 0 and #timerThreadSummaryRows > 0 then
				local topTimerThreads = {}
				do
					local i = 0
					local shouldIncrement = false
					while true do
						if shouldIncrement then
							i += 1
						else
							shouldIncrement = true
						end
						if not (i < math.min(maxRelatedTimers, #timerThreadSummaryRows)) then
							break
						end
						table.insert(topTimerThreads, timerThreadSummaryRows[i + 1])
					end
				end
				row.top_threads = topTimerThreads
			end
		end
	end
	cooperativeSort(rows, function(a, b)
		return a.inclusive_us > b.inclusive_us
	end, checkpoint)
	local edgeRows = {}
	local parentRelationsByChild = {}
	local childRelationsByParent = {}
	for _, edge in edgeAggregates do
		checkpoint()
		local parentRow = rowsByTimerId[edge.parent_timer_id]
		local childRow = rowsByTimerId[edge.child_timer_id]
		if parentRow == nil or childRow == nil then
			continue
		end
		local inclusiveUs = rawToUs(edge.inclusive_raw)
		local maxUs = rawToUs(edge.max_raw)
		local avgUs = if edge.count > 0 then round2(inclusiveUs / edge.count) else 0
		local edgeRow = {
			parent = {
				timer_id = edge.parent_timer_id,
				name = parentRow.name,
				group = parentRow.group,
			},
			child = {
				timer_id = edge.child_timer_id,
				name = childRow.name,
				group = childRow.group,
			},
			inclusive_us = inclusiveUs,
			inclusive_us_per_s = perSecond(inclusiveUs, analysisDurationMs),
			count = edge.count,
			count_per_s = perSecond(edge.count, analysisDurationMs),
			avg_invocation_us = avgUs,
			max_invocation_us = maxUs,
		}
		local maxToAvg = ratio(maxUs, avgUs)
		if maxToAvg ~= nil then
			edgeRow.max_to_avg = maxToAvg
		end
		table.insert(edgeRows, edgeRow)
		local parentRelations = parentRelationsByChild[edge.child_timer_id]
		if parentRelations == nil then
			parentRelations = {}
			parentRelationsByChild[edge.child_timer_id] = parentRelations
		end
		local _parentRelations = parentRelations
		local arg0 = {
			timer_id = edge.parent_timer_id,
			name = parentRow.name,
			group = parentRow.group,
			inclusive_us = inclusiveUs,
			count = edge.count,
			pct_of_timer_inclusive = percent(inclusiveUs, childRow.inclusive_us),
		}
		table.insert(_parentRelations, arg0)
		local childRelations = childRelationsByParent[edge.parent_timer_id]
		if childRelations == nil then
			childRelations = {}
			childRelationsByParent[edge.parent_timer_id] = childRelations
		end
		local _childRelations = childRelations
		local arg0_1 = {
			timer_id = edge.child_timer_id,
			name = childRow.name,
			group = childRow.group,
			inclusive_us = inclusiveUs,
			count = edge.count,
			pct_of_timer_inclusive = percent(inclusiveUs, parentRow.inclusive_us),
		}
		table.insert(_childRelations, arg0_1)
	end
	cooperativeSort(edgeRows, function(a, b)
		return a.inclusive_us > b.inclusive_us
	end, checkpoint)
	if maxRelatedTimers > 0 then
		for _, relationRows in parentRelationsByChild do
			checkpoint()
			cooperativeSort(relationRows, function(a, b)
				return a.inclusive_us > b.inclusive_us
			end, checkpoint)
		end
		for _, relationRows in childRelationsByParent do
			checkpoint()
			cooperativeSort(relationRows, function(a, b)
				return a.inclusive_us > b.inclusive_us
			end, checkpoint)
		end
		for _, row in rows do
			checkpoint()
			local timerId = row.timer_id
			local parents = parentRelationsByChild[timerId]
			local children = childRelationsByParent[timerId]
			if parents ~= nil and #parents > 0 then
				local topParents = {}
				do
					local i = 0
					local shouldIncrement = false
					while true do
						if shouldIncrement then
							i += 1
						else
							shouldIncrement = true
						end
						if not (i < math.min(maxRelatedTimers, #parents)) then
							break
						end
						table.insert(topParents, parents[i + 1])
					end
				end
				row.top_parents = topParents
			end
			if children ~= nil and #children > 0 then
				local topChildren = {}
				do
					local i = 0
					local shouldIncrement = false
					while true do
						if shouldIncrement then
							i += 1
						else
							shouldIncrement = true
						end
						if not (i < math.min(maxRelatedTimers, #children)) then
							break
						end
						table.insert(topChildren, children[i + 1])
					end
				end
				row.top_children = topChildren
			end
		end
	end
	local topTimers = {}
	do
		local i = 0
		local shouldIncrement = false
		while true do
			if shouldIncrement then
				i += 1
			else
				shouldIncrement = true
			end
			if not (i < math.min(maxTimers, #rows)) then
				break
			end
			local row = copyRecord(rows[i + 1])
			row.rank = i + 1
			table.insert(topTimers, row)
		end
	end
	local rowsByExclusive = {}
	for _, row in rows do
		table.insert(rowsByExclusive, row)
		checkpoint()
	end
	cooperativeSort(rowsByExclusive, function(a, b)
		return a.exclusive_us > b.exclusive_us
	end, checkpoint)
	local topTimersByExclusive = {}
	do
		local i = 0
		local shouldIncrement = false
		while true do
			if shouldIncrement then
				i += 1
			else
				shouldIncrement = true
			end
			if not (i < math.min(maxTimers, #rowsByExclusive)) then
				break
			end
			local row = copyRecord(rowsByExclusive[i + 1])
			row.rank = i + 1
			table.insert(topTimersByExclusive, row)
		end
	end
	local topEdges = {}
	do
		local i = 0
		local shouldIncrement = false
		while true do
			if shouldIncrement then
				i += 1
			else
				shouldIncrement = true
			end
			if not (i < math.min(maxTimers, #edgeRows)) then
				break
			end
			local row = copyRecord(edgeRows[i + 1])
			row.rank = i + 1
			table.insert(topEdges, row)
		end
	end
	local threadRows = {}
	for threadId, aggregate in threadAggregates do
		checkpoint()
		local info = getThreadInfo(threadId)
		local inclusiveUs = rawToUs(aggregate.inclusive_raw)
		local exclusiveUs = rawToUs(aggregate.exclusive_raw)
		local row = {
			thread_id = threadId,
			thread_name = info.name,
			is_gpu = info.is_gpu,
			inclusive_us = inclusiveUs,
			inclusive_us_per_s = perSecond(inclusiveUs, analysisDurationMs),
			exclusive_us = exclusiveUs,
			exclusive_pct = percent(exclusiveUs, inclusiveUs),
			count = aggregate.count,
			count_per_s = perSecond(aggregate.count, analysisDurationMs),
			max_invocation_us = rawToUs(aggregate.max_raw),
			pct_of_analyzed_wall = percent(inclusiveUs, analysisDurationUs),
		}
		local timerRows = threadTimerRows[threadId] or {}
		cooperativeSort(timerRows, function(a, b)
			return a.inclusive_us > b.inclusive_us
		end, checkpoint)
		local topThreadTimers = {}
		do
			local i = 0
			local shouldIncrement = false
			while true do
				if shouldIncrement then
					i += 1
				else
					shouldIncrement = true
				end
				if not (i < math.min(maxTimersPerGroup, #timerRows)) then
					break
				end
				local timerRow = copyRecord(timerRows[i + 1])
				table.insert(topThreadTimers, timerRow)
			end
		end
		if #topThreadTimers > 0 then
			row.top_timers = topThreadTimers
		end
		table.insert(threadRows, row)
	end
	cooperativeSort(threadRows, function(a, b)
		return a.inclusive_us > b.inclusive_us
	end, checkpoint)
	local topThreads = {}
	do
		local i = 0
		local shouldIncrement = false
		while true do
			if shouldIncrement then
				i += 1
			else
				shouldIncrement = true
			end
			if not (i < math.min(maxGroups, #threadRows)) then
				break
			end
			local row = threadRows[i + 1]
			row.rank = i + 1
			table.insert(topThreads, row)
		end
	end
	local groupRows = {}
	for _, aggregate in groupAggregates do
		checkpoint()
		local condition_5 = groupTimerRows[aggregate.group]
		if condition_5 == nil then
			condition_5 = {}
		end
		local timerRows = condition_5
		cooperativeSort(timerRows, function(a, b)
			return a.inclusive_us > b.inclusive_us
		end, checkpoint)
		local topGroupTimers = {}
		do
			local i = 0
			local shouldIncrement = false
			while true do
				if shouldIncrement then
					i += 1
				else
					shouldIncrement = true
				end
				if not (i < math.min(maxTimersPerGroup, #timerRows)) then
					break
				end
				local timerRow = timerRows[i + 1]
				local arg0 = {
					timer_id = timerRow.timer_id,
					name = timerRow.name,
					inclusive_us = timerRow.inclusive_us,
					inclusive_us_per_s = timerRow.inclusive_us_per_s,
					exclusive_us = timerRow.exclusive_us,
					count = timerRow.count,
					max_invocation_us = timerRow.max_invocation_us,
					max_frame_inclusive_us = timerRow.max_frame_inclusive_us,
				}
				table.insert(topGroupTimers, arg0)
			end
		end
		local inclusiveUs = rawToUs(aggregate.inclusive_raw)
		local exclusiveUs = rawToUs(aggregate.exclusive_raw)
		local groupRow = {
			group = aggregate.group,
			inclusive_us = inclusiveUs,
			inclusive_us_per_s = perSecond(inclusiveUs, analysisDurationMs),
			exclusive_us = exclusiveUs,
			exclusive_pct = percent(exclusiveUs, inclusiveUs),
			count = aggregate.count,
			count_per_s = perSecond(aggregate.count, analysisDurationMs),
			count_per_frame = if analysisFrameCount > 0
				then round2(aggregate.count / analysisFrameCount)
				else aggregate.count,
			timer_count = #timerRows,
			pct_of_analyzed_wall = percent(inclusiveUs, analysisDurationUs),
		}
		local groupFrameImpact =
			summarizeFrameImpact(groupFrameAggregates[aggregate.group], analysisFrameCount, checkpoint)
		for key, value in pairs(groupFrameImpact) do
			groupRow[key] = value
		end
		if #topGroupTimers > 0 then
			groupRow.top_timers = topGroupTimers
		end
		table.insert(groupRows, groupRow)
	end
	cooperativeSort(groupRows, function(a, b)
		return a.inclusive_us > b.inclusive_us
	end, checkpoint)
	local topGroups = {}
	do
		local i = 0
		local shouldIncrement = false
		while true do
			if shouldIncrement then
				i += 1
			else
				shouldIncrement = true
			end
			if not (i < math.min(maxGroups, #groupRows)) then
				break
			end
			local row = copyRecord(groupRows[i + 1])
			row.rank = i + 1
			table.insert(topGroups, row)
		end
	end
	local groupRowsByExclusive = {}
	for _, row in groupRows do
		table.insert(groupRowsByExclusive, row)
		checkpoint()
	end
	cooperativeSort(groupRowsByExclusive, function(a, b)
		return a.exclusive_us > b.exclusive_us
	end, checkpoint)
	local topGroupsByExclusive = {}
	do
		local i = 0
		local shouldIncrement = false
		while true do
			if shouldIncrement then
				i += 1
			else
				shouldIncrement = true
			end
			if not (i < math.min(maxGroups, #groupRowsByExclusive)) then
				break
			end
			local row = copyRecord(groupRowsByExclusive[i + 1])
			row.rank = i + 1
			table.insert(topGroupsByExclusive, row)
		end
	end
	local omitted = {}
	if omittedIdle > 0 then
		omitted.idle = omittedIdle
	end
	if omittedBelowThreshold > 0 then
		omitted.below_min_total_us = omittedBelowThreshold
	end
	if omittedByFilter > 0 then
		omitted.filtered_out = omittedByFilter
	end
	local openStackEntriesAtEnd = 0
	for _, stack in stacks do
		openStackEntriesAtEnd += #stack
		checkpoint()
	end
	local iteratorFinished = eventsSampled < maxEvents
	local partialReasons = {}
	if eventsSampled >= maxEvents then
		table.insert(partialReasons, "event_limit_hit")
	end
	if openStackEntriesAtEnd > 0 then
		table.insert(partialReasons, "open_stack_entries_at_end")
	end
	if sampledFrameCoveragePct < 100 then
		table.insert(partialReasons, "selected_frame_event_coverage_below_100")
	end
	local comparisonIndex
	if includeComparisonIndex then
		local timerFields = {
			"timer_id",
			"name",
			"group",
			"inclusive_us",
			"inclusive_us_per_s",
			"exclusive_us",
			"count",
			"count_per_s",
			"active_frame_count",
			"inclusive_us_per_frame",
			"max_frame_inclusive_us",
			"max_frame_id",
		}
		local groupFields = {
			"group",
			"inclusive_us",
			"inclusive_us_per_s",
			"exclusive_us",
			"count",
			"timer_count",
			"active_frame_count",
			"inclusive_us_per_frame",
			"max_frame_inclusive_us",
			"max_frame_id",
		}
		local threadFields =
			{ "thread_id", "thread_name", "is_gpu", "inclusive_us", "inclusive_us_per_s", "exclusive_us", "count" }
		local edgeFields = { "parent", "child", "inclusive_us", "inclusive_us_per_s", "count", "max_invocation_us" }
		local timerIndex = {}
		for _, row in rows do
			local arg0 = pickFields(row, timerFields)
			table.insert(timerIndex, arg0)
			checkpoint()
		end
		local groupIndex = {}
		for _, row in groupRows do
			local arg0 = pickFields(row, groupFields)
			table.insert(groupIndex, arg0)
			checkpoint()
		end
		local threadIndex = {}
		for _, row in threadRows do
			local arg0 = pickFields(row, threadFields)
			table.insert(threadIndex, arg0)
			checkpoint()
		end
		local edgeIndex = {}
		for _, row in edgeRows do
			local arg0 = pickFields(row, edgeFields)
			table.insert(edgeIndex, arg0)
			checkpoint()
		end
		comparisonIndex = {
			timers = timerIndex,
			groups = groupIndex,
			threads = threadIndex,
			call_edges = edgeIndex,
		}
	end
	local object = {
		schema_version = 1,
		ok = true,
		duration_ms = durationMs,
		target = targetRole,
		scope = "micro_profiler",
		time_unit = "microseconds",
		time_basis = "LibMP MicroProfiler timestamps converted from nanosecond ticks. inclusive_us is cumulative nested timer time and can overlap across nested timers/threads; do not sum rows as total frame time.",
	}
	local object_1 = {
		requested_duration_ms = durationMs,
		analysis_duration_us = analysisDurationUs,
		snapshot_frame_min = frameMin,
		snapshot_frame_max = frameMax,
		selected_frame_min = startFrame,
		selected_frame_max = frameMax,
		selected_frame_count = framesConsidered,
		analyzed_frame_min = analysisFrameMin,
		analyzed_frame_max = analysisFrameMax,
		analyzed_frame_count = analysisFrameCount,
		processed_frame_min = sampledFrameMin,
		processed_frame_max = sampledFrameMax,
	}
	-- ▼ ReadonlySet.size ▼
	local size_1 = 0
	for _ in sampledFrames do
		size_1 += 1
	end
	-- ▲ ReadonlySet.size ▲
	object_1.processed_frame_count = size_1
	object_1.selected_frame_event_coverage_pct = sampledFrameCoveragePct
	object_1.frame_window = frameWindow
	object.analysis_window = object_1
	local object_2 = {
		focus = focus,
	}
	object_2.filter = if filter ~= nil then filter else nil
	object_2.include_idle = includeIdle
	object_2.include_gpu = includeGpu
	object_2.min_total_us = minTotalUs
	object_2.max_groups = maxGroups
	object_2.max_timers = maxTimers
	object_2.max_timers_per_group = maxTimersPerGroup
	object_2.max_related_timers = maxRelatedTimers
	object_2.max_events = maxEvents
	object_2.frame_window = frameWindow
	object_2.sort = "inclusive_us_desc"
	object.applied = object_2
	local object_3 = {
		buffer_bytes = buffer.len(snapshot),
		timers = #timerIds,
		threads = #threadIds,
		frame_min = frameMin,
		frame_max = frameMax,
		frames_considered = framesConsidered,
		sampled_frame_min = sampledFrameMin,
		sampled_frame_max = sampledFrameMax,
	}
	-- ▼ ReadonlySet.size ▼
	local size_2 = 0
	for _ in sampledFrames do
		size_2 += 1
	end
	-- ▲ ReadonlySet.size ▲
	object_3.sampled_frames = size_2
	object_3.events_sampled = eventsSampled
	object_3.enter_events = enterEvents
	object_3.exit_events = exitEvents
	object_3.unmatched_exits = unmatchedExits
	object_3.dropped_spans = droppedSpans
	object_3.open_stack_entries_at_end = openStackEntriesAtEnd
	object_3.iterator_finished = iteratorFinished
	object_3.last_processed_frame_id = lastProcessedFrameId
	object_3.last_processed_timestamp_us = if lastProcessedTimestampRaw ~= nil
		then rawToUs(lastProcessedTimestampRaw)
		else nil
	object_3.event_limit_hit = eventsSampled >= maxEvents
	object.counts = object_3
	object.frame_summary = frameSummary
	object.top_groups = topGroups
	object.top_groups_by_exclusive = topGroupsByExclusive
	object.top_threads = topThreads
	object.top_call_edges = topEdges
	object.top_timers = topTimers
	object.top_timers_by_exclusive = topTimersByExclusive
	object.data_quality = {
		event_limit_hit = eventsSampled >= maxEvents,
		iterator_finished = iteratorFinished,
		unmatched_exits = unmatchedExits,
		dropped_spans = droppedSpans,
		open_stack_entries_at_end = openStackEntriesAtEnd,
		selected_frame_event_coverage_pct = sampledFrameCoveragePct,
		partial = #partialReasons > 0,
		partial_reasons = partialReasons,
		notes = if focus ~= "all"
			then {
				"focus filters events before stack aggregation; exclusive_us is exclusive within emitted focused events, not the full snapshot.",
			}
			else nil,
	}
	object.recommended_tools = recommendedToolsForGroups(topGroups, targetRole)
	local result = object
	if (next(omitted)) ~= nil then
		result.omitted = omitted
	end
	if comparisonIndex ~= nil then
		result.comparison_index = comparisonIndex
	end
	result.backend = backend
	if session:GetDataFormatVersion() ~= nil then
		result.libmp_data_format_version = session:GetDataFormatVersion()
	end
	if session:GetObjSize() ~= nil then
		result.snapshot_object_size_bytes = session:GetObjSize()
	end
	if includeRawBuffer then
		result.raw_snapshot_base64 = encodeBase64(snapshot, checkpoint)
	end
	iterator:Dispose()
	session:Dispose()
	return result
end
return {
	captureMicroProfiler = captureMicroProfiler,
}
