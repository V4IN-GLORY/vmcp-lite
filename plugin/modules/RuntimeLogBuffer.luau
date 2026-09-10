-- Bounded capture for one Peer VM's LogService callbacks.
-- Powers get_runtime_logs without parenting state to the DataModel.
--
-- A Studio process can host several Peer VMs, and its LogService callbacks are
-- delivered in those VM contexts. MCP reads every Peer buffer in an Instance
-- and merges them into that process's log stream. Multiplayer Group Instances
-- remain isolated and are returned independently.
local LogService = game:GetService("LogService")
local RunService = game:GetService("RunService")
local PeerRole = require(script.Parent.PeerRole)
local MAX_BYTES = 64 * 1024
local HARD_ENTRY_CAP = 50_000
local entries = {}
local totalBytes = 0
local totalDropped = 0
local nextSeq = 1
local installed = false
local function levelTag(t)
	if t == Enum.MessageType.MessageWarning then
		return "WARN"
	end
	if t == Enum.MessageType.MessageError then
		return "ERR"
	end
	if t == Enum.MessageType.MessageInfo then
		return "INFO"
	end
	return "OUT"
end
local function nowSec()
	return DateTime.now().UnixTimestampMillis / 1000
end
-- Studio occasionally exposes binary-bearing Output messages through
-- LogService (for example, plugin hydration diagnostics containing raw CSG
-- data). HttpService:JSONEncode rejects those strings outright. Preserve all
-- valid UTF-8 verbatim and make only malformed bytes JSON-safe and visible.
local function escapeInvalidUtf8(msg)
	local valid = utf8.len(msg)
	-- Roblox currently returns nil (not the false declared by @rbxts/types)
	-- when it encounters a malformed sequence. A numeric result is the only
	-- portable success discriminator across both representations.
	if type(valid) == "number" then
		return msg
	end
	local parts = {}
	local cursor = 1
	while cursor <= #msg do
		local suffixValid, invalidPosition = utf8.len(msg, cursor)
		if type(suffixValid) == "number" then
			local arg0 = string.sub(msg, cursor)
			table.insert(parts, arg0)
			break
		end
		if not (type(invalidPosition) == "number") then
			break
		end
		if invalidPosition > cursor then
			local arg0 = string.sub(msg, cursor, invalidPosition - 1)
			table.insert(parts, arg0)
		end
		local invalidByte = string.byte(msg, invalidPosition)
		local arg0 = string.format("\\x%02X", invalidByte)
		table.insert(parts, arg0)
		cursor = invalidPosition + 1
	end
	return table.concat(parts, "")
end
local function dropOldestUntilFits(incomingBytes)
	while #entries > 0 and (totalBytes + incomingBytes > MAX_BYTES or #entries >= HARD_ENTRY_CAP) do
		local dropped = table.remove(entries, 1)
		totalBytes -= #dropped.message
		totalDropped += 1
	end
end
local function pushEntry(msg, t, ts, data)
	if ts == nil then
		ts = nowSec()
	end
	local safeMessage = escapeInvalidUtf8(msg)
	local bytes = #safeMessage
	dropOldestUntilFits(bytes)
	local arg0 = {
		seq = nextSeq,
		ts = ts,
		level = levelTag(t),
		message = safeMessage,
		data = data,
	}
	table.insert(entries, arg0)
	nextSeq += 1
	totalBytes += bytes
end
local function seedRuntimeHistory()
	local ok, history = pcall(function()
		return LogService:GetLogHistory()
	end)
	if not ok then
		return nil
	end
	local isEdit = PeerRole.detect() == "edit"
	-- GetLogHistory timestamps and DateTime.now() share Unix time, while
	-- os.clock() is elapsed time for this Studio process. Their difference is
	-- therefore the process launch boundary. Edit-mode history is filtered to
	-- that boundary so startup errors from this launch are recovered without
	-- importing history left by an earlier Studio process.
	local processStartedAt = nowSec() - os.clock()
	for _, entry in history do
		if not (type(entry.message) == "string") then
			continue
		end
		local timestamp = if type(entry.timestamp) == "number" then entry.timestamp else nil
		if isEdit and (timestamp == nil or timestamp < processStartedAt - 1) then
			continue
		end
		pushEntry(entry.message, entry.messageType, timestamp)
	end
end
local function install()
	if installed then
		return nil
	end
	if not RunService:IsStudio() then
		return nil
	end
	installed = true
	-- Every peer can emit startup logs before the plugin finishes loading.
	-- Seed from per-DataModel LogHistory so get_runtime_logs can still see them;
	-- edit history is bounded to the current Studio process above.
	seedRuntimeHistory()
	LogService.MessageOut:Connect(function(msg, t, context)
		pushEntry(msg, t, nil, context)
	end)
end
local function query(opts)
	local _result
	if opts.since ~= nil then
		_result = {}
		for _, e in entries do
			if e.seq > opts.since then
				table.insert(_result, e)
			end
		end
	else
		local array = {}
		table.move(entries, 1, #entries, #array + 1, array)
		_result = array
	end
	local result = _result
	if opts.filter ~= nil then
		-- Plain substring search (4th arg = true). Pattern matching here was
		-- surprising in practice - Lua magic chars in messages would silently
		-- not match (e.g. filter="MARK-EDIT" against "MARK-EDIT-001" fails
		-- because '-' means "0+" in Lua patterns). Substring search matches
		-- most users' mental model of "filter messages containing this text".
		local needle = opts.filter
		result = {}
		for _, e in result do
			local start = string.find(e.message, needle, 1, true)
			if start ~= nil then
				table.insert(result, e)
			end
		end
	end
	if opts.tail ~= nil and #result > opts.tail then
		-- roblox-ts arrays don't expose .slice; manual tail copy.
		local tailed = {}
		local start = #result - opts.tail
		for i = start, #result - 1 do
			table.insert(tailed, result[i + 1])
		end
		result = tailed
	end
	local last = if #entries > 0 then entries[#entries] else nil
	local object = {
		entries = result,
		totalDropped = totalDropped,
	}
	local _result_1
	if last then
		_result_1 = last.seq
	else
		_result_1 = if opts.since ~= nil then opts.since else 0
	end
	object.nextSince = _result_1
	return object
end
return {
	install = install,
	query = query,
}
