-- Lute (github.com/luau-lang/lute) script: per-scope self and inclusive time for two .gprx
-- captures, side by side, biggest change first. Use it when a capture is too big to analyze in
-- Studio, or to compare two profile_scripts dumps after the fact.
--
--   lute diff-captures.luau before.gprx after.gprx [top]
--
-- Needs LibMP.luau next to this file (github.com/Roblox/libmp/releases).

local LibMP = require("./LibMP")
local process = require("@lute/process")

local args = process.args
local beforePath, afterPath = args[1], args[2]
local top = tonumber(args[3]) or 30
if not beforePath or not afterPath then
	error("usage: lute diff-captures.luau before.gprx after.gprx [top]")
end

-- Same frame-local walk profile_scripts uses: scopes crossing frame boundaries are split at the
-- boundary, self time is inclusive minus children.
local function aggregate(path: string)
	local session = LibMP.Session.OpenFromFile(path)
	if not session or not session:IsValid() then
		error(`couldn't open {path}`)
	end
	local tickToMs = session:FetchGlobalDesc().TickToMsCpu
	local frameMin, frameMax = session:GetFrameIdMin(), session:GetFrameIdMax()
	local rows = {}
	local childAcc = {}
	local function account(threadId, level, timerId, ms, closed)
		local acc = childAcc[threadId]
		if not acc then
			acc = {}
			childAcc[threadId] = acc
		end
		local children = acc[level + 1] or 0
		acc[level + 1] = 0
		acc[level] = (acc[level] or 0) + ms
		local row = rows[timerId]
		if not row then
			row = { name = session:FetchTimerDesc(timerId).TimerName, selfMs = 0, inclusiveMs = 0, count = 0 }
			rows[timerId] = row
		end
		row.inclusiveMs += ms
		row.selfMs += math.max(ms - children, 0)
		if closed then
			row.count += 1
		end
	end

	local iter = session:CreateLogIterator()
	iter:Configure({ SkipGpuThreads = true, SkipEvents = true, EmitThreadFrameEnd = true })
	local state = iter:GetState()
	iter:RewindTo(frameMin, frameMax)
	while iter:Step() do
		if state:IsThreadFrameEnd() then
			local exitAt = state:Timestamp()
			local depth = state:ThreadStackDepth()
			for level = depth - 1, 0, -1 do
				local element = iter:GetCurrentThreadStackElement(level)
				if element then
					account(state:ThreadId(), level, element:EnterTimerId(), (exitAt - element:EnterTimestampFrameLocal()) * tickToMs, false)
				end
			end
			childAcc[state:ThreadId()] = nil
		elseif state:IsExit() and not state:ThreadStackWasOverflowed() then
			local depth = state:ThreadStackDepth()
			local enterAt
			if state:ThreadStackIsUnderflowed() then
				enterAt = session:FetchFrameDesc(state:FrameId()).TickStartCpu
			else
				enterAt = iter:GetCurrentThreadStackElement(depth):EnterTimestampFrameLocal()
			end
			account(state:ThreadId(), depth, state:TimerId(), (state:Timestamp() - enterAt) * tickToMs, true)
		end
	end
	iter:Dispose()

	local frames = frameMax - frameMin + 1
	local byName = {}
	for _, row in rows do
		byName[row.name] = { selfMs = row.selfMs / frames, inclusiveMs = row.inclusiveMs / frames, count = row.count / frames }
	end
	session:Dispose()
	return byName, frames
end

local before, framesBefore = aggregate(beforePath)
local after, framesAfter = aggregate(afterPath)

local names = {}
local seen = {}
for name in before do
	seen[name] = true
	table.insert(names, name)
end
for name in after do
	if not seen[name] then
		table.insert(names, name)
	end
end

local function at(set, name)
	return set[name] or { selfMs = 0, inclusiveMs = 0, count = 0 }
end
table.sort(names, function(a, b)
	return math.abs(at(after, a).selfMs - at(before, a).selfMs) > math.abs(at(after, b).selfMs - at(before, b).selfMs)
end)

print(string.format("per-frame ms, %d frames before vs %d after", framesBefore, framesAfter))
print(string.format("%-44s %10s %10s %9s   %10s %10s", "scope", "self<", "self>", "delta", "incl<", "incl>"))
for index = 1, math.min(top, #names) do
	local name = names[index]
	local b, a = at(before, name), at(after, name)
	print(string.format("%-44s %10.3f %10.3f %+9.3f   %10.3f %10.3f", string.sub(name, 1, 44), b.selfMs, a.selfMs, a.selfMs - b.selfMs, b.inclusiveMs, a.inclusiveMs))
end
