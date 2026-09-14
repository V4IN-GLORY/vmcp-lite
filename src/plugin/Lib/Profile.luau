--!strict
--!native
--!optimize 2

-- MicroProfiler captures through LibMP (github.com/Roblox/libmp), and the reading of them.
--
-- LibMP is the user's module, not ours: it's a few hundred KB of Luau wrapping a WASM blob, so it
-- lives in the place (ReplicatedStorage.LibMP by convention) and this just finds and requires it.
-- The MicroProfiler is per process, so a capture sees every DataModel in that process -- run the
-- capture in the context whose scripts you're loading and the load shows up.
--
-- The last capture stays in `Profile.LastBuffer` so a run_luau snippet in the same context can
-- open it again with `vmcp.Profile.Session()` and dig deeper than the summary went.

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Bridge = require(script.Parent.Parent.Bridge)
local GameVm = require(script.Parent.Parent.Exec.GameVm)
local Inject = require(script.Parent.Parent.Exec.Inject)

local Profile = {}

-- The Creator Store asset LibMP's README points at.
local LIBMP_ASSET_ID = 109009378620272
local MAX_FRAME_LIMIT = 256
local DEFAULT_TOP = 15
local DEFAULT_CALLS = 500
local DEFAULT_SECONDS = 2
local DEFAULT_WARMUP = 5
local DEFAULT_FRAME_LIMIT = 128
local RESULT_NAME = "__VMCP_ProfileResult"
-- Base64 of the capture has to fit one socket message (VMCP_MAX_MESSAGE_MB, 8 by default).
local MAX_DUMP_BYTES = 4_500_000

Profile.LastBuffer = nil :: buffer?

export type TimerRow = {
	timerId: number,
	name: string,
	group: string,
	selfMs: number,
	inclusiveMs: number,
	count: number,
	maxMs: number,
	worstFrameMs: number,
	worstFrameId: number,
	worstFrameAbsoluteId: number,
}

export type FrameRow = {
	frameId: number,
	absoluteId: number,
	cpuMs: number,
	top: { { name: string, selfMs: number } },
}

export type Target = {
	label: string,
	setup: string,
	calls: number?,
	seconds: number?,
	perFrame: number?,
	warmup: number?,
}

export type HammerOptions = {
	vm: string?,
	-- What a plugin-VM setup sees as `vmcp`. Ignored for the game VM.
	env: any?,
	frameLimit: number?,
	top: number?,
	dump: boolean?,
	name: string?,
	-- Extra scope names to report alongside the targets' own labels (section labels, usually).
	labels: { string }?,
}

export type Report = {
	frames: number,
	spanMs: number,
	frameMeanMs: number,
	frameP95Ms: number,
	frameMaxMs: number,
	frameMaxId: number,
	frameMaxAbsoluteId: number,
	heapStartMb: number?,
	heapEndMb: number?,
	labels: { TimerRow },
	top: { TimerRow },
	spikes: { FrameRow },
}

local cached: any = nil

-- The LibMP ModuleScript in this place, if there is one.
function Profile.Find(): ModuleScript?
	local direct = ReplicatedStorage:FindFirstChild("LibMP")
	if direct and direct:IsA("ModuleScript") then
		return direct
	end
	return game:QueryDescendants("ModuleScript#LibMP")[1] :: ModuleScript?
end

-- Requires LibMP, once. Returns the module table or the reason there isn't one.
function Profile.LibMP(): (any?, string?)
	if cached then
		return cached, nil
	end
	local module = Profile.Find()
	if not module then
		return nil,
			"LibMP isn't in this place. Put the LibMP ModuleScript in ReplicatedStorage (Creator Store "
				.. `asset {LIBMP_ASSET_ID}, or github.com/Roblox/libmp/releases), or pass installLibMP = true.`
	end
	local ok, lib = pcall(require, module)
	if not ok then
		return nil, `LibMP failed to load: {lib}`
	end
	if type(lib) ~= "table" or type(lib.Control) ~= "table" then
		return nil, `{module:GetFullName()} loaded but doesn't look like LibMP`
	end
	if not lib.Control:IsBackendReady() then
		return nil,
			"LibMP loaded but the MicroProfiler backend isn't reachable from here (version mismatch, "
				.. "or this build of Studio doesn't expose it)"
	end
	cached = lib
	return lib, nil
end

-- Edit mode only: pulls the module off the Creator Store into ReplicatedStorage. Tagged excludeLOC
-- so count_lines doesn't report LibMP as the biggest script in the game.
function Profile.Install(): (ModuleScript?, string?)
	local existing = Profile.Find()
	if existing then
		return existing, nil
	end
	local ok, container = pcall(InsertService.LoadAsset, InsertService, LIBMP_ASSET_ID)
	if not ok then
		return nil, `couldn't insert LibMP from the Creator Store: {container}`
	end
	local module = container:FindFirstChildWhichIsA("ModuleScript", true)
	if not module then
		container:Destroy()
		return nil, "the LibMP asset didn't contain a ModuleScript"
	end
	module.Name = "LibMP"
	module.Parent = ReplicatedStorage
	CollectionService:AddTag(module, "excludeLOC")
	container:Destroy()
	cached = nil
	return module, nil
end

-- Turns the profiler on, runs `load`, and snapshots the last `frameLimit` frames. The buffer is
-- what everything else reads; the live session is never touched after this.
function Profile.Capture(frameLimit: number?, load: () -> ()): (buffer?, string?)
	local lib, why = Profile.LibMP()
	if not lib then
		return nil, why
	end
	local control = lib.Control
	local limit = math.clamp(frameLimit or 128, 8, MAX_FRAME_LIMIT)

	control:EnableProfiler(true)
	control:SetFrameLimit(limit)
	control:EnableCapture(true)
	-- Two frames so the first frame of the load isn't also the frame the profiler woke up in.
	RunService.Heartbeat:Wait()
	RunService.Heartbeat:Wait()

	local ok, failure = pcall(load :: any)

	-- The last call's scope closes in the frame after it ran.
	RunService.Heartbeat:Wait()
	local captured, buf = pcall(function()
		return control:CaptureToBufferSync()
	end)
	if not ok then
		return nil, `the load errored: {failure}`
	end
	if not captured or typeof(buf) ~= "buffer" then
		return nil, `CaptureToBufferSync failed: {buf}`
	end
	Profile.LastBuffer = buf
	return buf, nil
end

-- A fresh session over the last capture (or a buffer you pass). Dispose it when you're done.
function Profile.Session(buf: buffer?): (any?, string?)
	local lib, why = Profile.LibMP()
	if not lib then
		return nil, why
	end
	local source = buf or Profile.LastBuffer
	if not source then
		return nil, "nothing captured yet -- run profile_scripts first"
	end
	local session = lib.Session.OpenFromBuffer(source)
	if not session or not session:IsValid() then
		return nil, "LibMP couldn't open the capture"
	end
	return session, nil
end

local function percentile(sorted: { number }, fraction: number): number
	if #sorted == 0 then
		return 0
	end
	return sorted[math.clamp(math.ceil(fraction * #sorted), 1, #sorted)]
end

-- Walks every CPU thread's log frame by frame and attributes each scope's time to the frame it ran
-- in -- the frame-local iteration from LibMP's own SKILL.md, plus a self-time pass on top, because
-- inclusive time makes every parent scope look as expensive as its slowest child.
type AnalyzeOptions = { labels: { string }?, top: number? }

function Profile.Analyze(buf: buffer, options: AnalyzeOptions?): (Report?, string?)
	local settings: AnalyzeOptions = options or {}
	local session, why = Profile.Session(buf)
	if not session then
		return nil, why
	end

	local tickToMs = session:FetchGlobalDesc().TickToMsCpu
	local frameMin = session:GetFrameIdMin()
	local frameMax = session:GetFrameIdMax()
	if frameMin == 0 and frameMax == 0 then
		session:Dispose()
		return nil, "the capture holds no frames"
	end

	local frameDescs: { [number]: any } = {}
	local frameTimes: { number } = {}
	local spanMs = 0
	for id = frameMin, frameMax do
		local desc = session:FetchFrameDesc(id)
		frameDescs[id] = desc
		local ms = (desc.TickEndCpu - desc.TickStartCpu) * tickToMs
		table.insert(frameTimes, ms)
		spanMs += ms
	end

	-- Per timer totals, and per frame per timer so spikes can say what filled them.
	local rows: { [number]: TimerRow } = {}
	local selfByFrame: { [number]: { [number]: number } } = {}
	local inclByFrame: { [number]: { [number]: number } } = {}
	-- childAcc[thread][level] is how much of the scope currently open at that level went to its
	-- children, so self = inclusive - children when it closes.
	local childAcc: { [number]: { [number]: number } } = {}

	local function rowFor(timerId: number): TimerRow
		local known = rows[timerId]
		if known then
			return known
		end
		local desc = session:FetchTimerDesc(timerId)
		local groupOk, group = pcall(function()
			return session:FetchGroupDesc(desc.GroupId).GroupName
		end)
		local row: TimerRow = {
			timerId = timerId,
			name = desc.TimerName,
			group = if groupOk then group else "?",
			selfMs = 0,
			inclusiveMs = 0,
			count = 0,
			maxMs = 0,
			worstFrameMs = 0,
			worstFrameId = 0,
			worstFrameAbsoluteId = 0,
		}
		rows[timerId] = row
		return row
	end

	local function account(
		frameId: number,
		threadId: number,
		level: number,
		timerId: number,
		ms: number,
		closed: boolean
	)
		local acc = childAcc[threadId]
		if not acc then
			acc = {}
			childAcc[threadId] = acc
		end
		local children = acc[level + 1] or 0
		acc[level + 1] = 0
		acc[level] = (acc[level] or 0) + ms
		local selfMs = math.max(ms - children, 0)

		local row = rowFor(timerId)
		row.inclusiveMs += ms
		row.selfMs += selfMs
		if closed then
			row.count += 1
			if ms > row.maxMs then
				row.maxMs = ms
			end
		end

		local frameSelf = selfByFrame[frameId]
		if not frameSelf then
			frameSelf = {}
			selfByFrame[frameId] = frameSelf
			inclByFrame[frameId] = {}
		end
		frameSelf[timerId] = (frameSelf[timerId] or 0) + selfMs
		local frameIncl = inclByFrame[frameId]
		frameIncl[timerId] = (frameIncl[timerId] or 0) + ms
	end

	local iter = session:CreateLogIterator()
	iter:Configure({ SkipGpuThreads = true, SkipEvents = true, EmitThreadFrameEnd = true })
	local state = iter:GetState()
	iter:RewindTo(frameMin, frameMax)

	while iter:Step() do
		if state:IsThreadFrameEnd() then
			local frameId = state:FrameId()
			local threadId = state:ThreadId()
			local exitAt = state:Timestamp()
			local depth = state:ThreadStackDepth()
			for level = depth - 1, 0, -1 do
				local element = iter:GetCurrentThreadStackElement(level)
				if element then
					local ms = (exitAt - element:EnterTimestampFrameLocal()) * tickToMs
					account(frameId, threadId, level, element:EnterTimerId(), ms, false)
				end
			end
			-- Whatever is still open starts the next frame with no children counted against it.
			childAcc[threadId] = nil
		elseif state:IsExit() and not state:ThreadStackWasOverflowed() then
			local frameId = state:FrameId()
			local depth = state:ThreadStackDepth()
			local enterAt
			if state:ThreadStackIsUnderflowed() then
				enterAt = frameDescs[frameId].TickStartCpu
			else
				enterAt = iter:GetCurrentThreadStackElement(depth):EnterTimestampFrameLocal()
			end
			local ms = (state:Timestamp() - enterAt) * tickToMs
			account(frameId, state:ThreadId(), depth, state:TimerId(), ms, true)
		end
	end
	iter:Dispose()

	-- Worst single frame for every timer, by inclusive time -- that's the number that maps to a
	-- hitch a player felt.
	for frameId, perTimer in inclByFrame do
		local desc = frameDescs[frameId]
		for timerId, ms in perTimer do
			local row = rows[timerId]
			if ms > row.worstFrameMs then
				row.worstFrameMs = ms
				row.worstFrameId = frameId
				row.worstFrameAbsoluteId = desc.FrameAbsoluteId
			end
		end
	end

	local all: { TimerRow } = {}
	for _, row in rows do
		table.insert(all, row)
	end
	table.sort(all, function(a, b)
		return a.selfMs > b.selfMs
	end)

	local wanted: { [string]: boolean } = {}
	for _, label in settings.labels or ({} :: { string }) do
		wanted[label] = true
	end
	-- The engine files debug.profilebegin scopes under "::label".
	local labels: { TimerRow } = {}
	for _, row in all do
		if wanted[row.name] or wanted[string.gsub(row.name, "^::", "")] then
			table.insert(labels, row)
		end
	end

	local top: { TimerRow } = {}
	for index = 1, math.min(settings.top or DEFAULT_TOP, #all) do
		top[index] = all[index]
	end

	-- The three slowest frames and what filled them.
	local order = {}
	for id = frameMin, frameMax do
		table.insert(order, id)
	end
	table.sort(order, function(a, b)
		return frameTimes[a - frameMin + 1] > frameTimes[b - frameMin + 1]
	end)
	local spikes: { FrameRow } = {}
	for index = 1, math.min(3, #order) do
		local frameId = order[index]
		local perTimer = selfByFrame[frameId] or ({} :: { [number]: number })
		local filled = {}
		for timerId, ms in perTimer do
			table.insert(filled, { name = rows[timerId].name, selfMs = ms })
		end
		table.sort(filled, function(a, b)
			return a.selfMs > b.selfMs
		end)
		for trim = #filled, 5, -1 do
			filled[trim] = nil
		end
		table.insert(spikes, {
			frameId = frameId,
			absoluteId = frameDescs[frameId].FrameAbsoluteId,
			cpuMs = frameTimes[frameId - frameMin + 1],
			top = filled,
		})
	end

	local heapStart, heapEnd
	local heapId = session:FindCounterId("**/Luau/heap", false)
	if heapId ~= 0 then
		local samples = session:FetchCounterSamples(heapId)
		if #samples > 0 then
			heapStart = samples[1].Value / (1024 * 1024)
			heapEnd = samples[#samples].Value / (1024 * 1024)
		end
	end

	local sorted = table.clone(frameTimes)
	table.sort(sorted)
	local worst = order[1]

	session:Dispose()

	return {
		frames = #frameTimes,
		spanMs = spanMs,
		frameMeanMs = spanMs / #frameTimes,
		frameP95Ms = percentile(sorted, 0.95),
		frameMaxMs = frameTimes[worst - frameMin + 1],
		frameMaxId = worst,
		frameMaxAbsoluteId = frameDescs[worst].FrameAbsoluteId,
		heapStartMb = heapStart,
		heapEndMb = heapEnd,
		labels = labels,
		top = top,
		spikes = spikes,
	},
		nil
end

local function fmtMs(value: number): string
	return string.format("%.2fms", value)
end

function Profile.Summarise(report: Report): string
	local lines = {
		string.format(
			"capture: %d frames over %.0fms -- CPU frame mean %s, p95 %s, max %s (frame %d / abs %d)",
			report.frames,
			report.spanMs,
			fmtMs(report.frameMeanMs),
			fmtMs(report.frameP95Ms),
			fmtMs(report.frameMaxMs),
			report.frameMaxId,
			report.frameMaxAbsoluteId
		),
	}
	if report.heapStartMb and report.heapEndMb then
		table.insert(
			lines,
			string.format(
				"Luau heap: %.1f MB -> %.1f MB (%+.1f)",
				report.heapStartMb,
				report.heapEndMb,
				report.heapEndMb - report.heapStartMb
			)
		)
	end

	if #report.labels > 0 then
		table.insert(lines, "")
		table.insert(lines, "your labels (inclusive):")
		for _, row in report.labels do
			local avg = if row.count > 0 then row.inclusiveMs / row.count else 0
			table.insert(
				lines,
				string.format(
					"  %-32s %5d calls  total %s  avg %s  max %s  worst frame %s (frame %d / abs %d)",
					row.name,
					row.count,
					fmtMs(row.inclusiveMs),
					fmtMs(avg),
					fmtMs(row.maxMs),
					fmtMs(row.worstFrameMs),
					row.worstFrameId,
					row.worstFrameAbsoluteId
				)
			)
		end
	end

	table.insert(lines, "")
	table.insert(lines, `top {#report.top} scopes by self time, all CPU threads (inclusive in brackets):`)
	for index, row in report.top do
		table.insert(
			lines,
			string.format(
				"  %2d. %9s  %-36s [%s]  (incl %s)  n=%d  max %s",
				index,
				fmtMs(row.selfMs),
				row.name,
				row.group,
				fmtMs(row.inclusiveMs),
				row.count,
				fmtMs(row.maxMs)
			)
		)
	end

	table.insert(lines, "")
	table.insert(lines, "slowest frames and what filled them (self time):")
	for _, frame in report.spikes do
		local parts = {}
		for _, entry in frame.top do
			table.insert(parts, `{entry.name} {fmtMs(entry.selfMs)}`)
		end
		table.insert(
			lines,
			string.format(
				"  frame %d / abs %d: %s -- %s",
				frame.frameId,
				frame.absoluteId,
				fmtMs(frame.cpuMs),
				table.concat(parts, ", ")
			)
		)
	end

	return table.concat(lines, "\n")
end

-- The load loop as source, because it runs in the game VM where nothing of ours is in scope.
local function loadSource(target: Target): string
	local calls = target.calls or DEFAULT_CALLS
	local seconds = target.seconds or DEFAULT_SECONDS
	local perFrame = target.perFrame or math.max(1, math.ceil(calls / (seconds * 60)))
	local warmup = target.warmup or DEFAULT_WARMUP
	return string.format(
		[[
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local label = %q
local result = { label = label }
local function setup()
%s
end
local ok, fn = pcall(setup)
if not ok then
	result.error = "setup errored: " .. tostring(fn)
elseif type(fn) ~= "function" then
	result.error = "setup must return a function, it returned " .. typeof(fn)
else
	for _ = 1, %d do
		pcall(fn, 0)
	end
	local made, errors, firstError = 0, 0, nil
	local inFrame = 0
	local started = os.clock()
	local deadline = started + %s
	while made < %d and os.clock() < deadline do
		made += 1
		debug.profilebegin(label)
		local passed, failure = pcall(fn, made)
		debug.profileend()
		if not passed then
			errors += 1
			firstError = firstError or tostring(failure)
		end
		inFrame += 1
		if inFrame >= %d then
			inFrame = 0
			RunService.Heartbeat:Wait()
		end
	end
	result.calls = made
	result.errors = errors
	result.firstError = firstError
	result.seconds = os.clock() - started
end
local holder = game:GetService("ReplicatedStorage"):FindFirstChild(%q) or Instance.new("StringValue")
holder.Name = %q
holder.Archivable = false
holder.Value = HttpService:JSONEncode(result)
holder.Parent = game:GetService("ReplicatedStorage")
]],
		target.label,
		target.setup,
		warmup,
		tostring(seconds),
		calls,
		perFrame,
		RESULT_NAME,
		RESULT_NAME
	)
end

local function runLoad(target: Target, vm: string?, env: any?): (any?, string?)
	local source = loadSource(target)
	local ok, failure
	if vm == "plugin" then
		ok, failure = Inject.Run(source, env or {}, (target.seconds or DEFAULT_SECONDS) + 30)
	else
		ok, failure = GameVm.Run(source)
	end
	if not ok then
		return nil, tostring(failure)
	end
	local holder = ReplicatedStorage:FindFirstChild(RESULT_NAME)
	if not holder or not holder:IsA("StringValue") then
		return nil, "the load ran but left no result behind"
	end
	local decoded, result = pcall(HttpService.JSONDecode, HttpService, holder.Value)
	holder:Destroy()
	if not decoded then
		return nil, `couldn't read the load's result: {result}`
	end
	return result, nil
end

local function safeName(name: string): string
	return (string.gsub(name, "[^%w_%-]", "_"):sub(1, 48))
end

-- Runs every target under its own capture, one after another, and hands back the report text for
-- all of them. This is what profile_scripts does in the playtest; a timeline `server` event calls
-- it directly as vmcp.Profile.Hammer so old-vs-new plus the output check fit in one run.
function Profile.Hammer(targets: { Target }, options: HammerOptions?): (string, boolean)
	local settings: HammerOptions = options or {}
	local labels: { string } = {}
	for _, target in targets do
		table.insert(labels, target.label)
	end
	for _, label in settings.labels or ({} :: { string }) do
		table.insert(labels, label)
	end

	local prefix = safeName(settings.name or os.date("%Y%m%d-%H%M%S"))
	local parts = {}
	local failed = false

	for _, target in targets do
		local loadResult: any = nil
		local loadProblem: string? = nil
		local buf, why = Profile.Capture(settings.frameLimit or DEFAULT_FRAME_LIMIT, function()
			loadResult, loadProblem = runLoad(target, settings.vm, settings.env)
		end)

		local header = { `== {target.label} ==` }
		if loadProblem then
			table.insert(header, `load failed: {loadProblem}`)
			failed = true
		elseif loadResult.error then
			table.insert(header, loadResult.error)
			failed = true
		else
			local line = string.format("%d calls in %.2fs", loadResult.calls, loadResult.seconds)
			if loadResult.errors > 0 then
				line ..= ` -- {loadResult.errors} errored, first: {loadResult.firstError}`
			end
			table.insert(header, line)
		end

		if not buf then
			table.insert(header, `no capture: {why}`)
			table.insert(parts, table.concat(header, "\n"))
			failed = true
			continue
		end

		local report, analyzeProblem = Profile.Analyze(buf, { labels = labels, top = settings.top })
		if not report then
			table.insert(header, `couldn't read the capture: {analyzeProblem}`)
		else
			table.insert(header, Profile.Summarise(report))
		end

		if settings.dump ~= false then
			local size = buffer.len(buf)
			if size > MAX_DUMP_BYTES then
				table.insert(
					header,
					`(capture is {math.floor(size / 1024)} KB, too big to ship as one message -- lower frameLimit, or raise VMCP_MAX_MESSAGE_MB)`
				)
			else
				local posted, outcome = Bridge.Post({
					kind = "gprx",
					name = `{prefix}-{safeName(target.label)}`,
					data = Profile.Base64(buf),
				})
				table.insert(header, if posted then outcome else `dump failed: {outcome}`)
			end
		end

		table.insert(parts, table.concat(header, "\n"))
	end

	return table.concat(parts, "\n\n"), failed
end

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local CHARS = {}
for index = 1, 64 do
	CHARS[index - 1] = string.sub(ALPHABET, index, index)
end

-- The capture has to cross the socket as JSON to get written to disk, and JSON has no bytes.
function Profile.Base64(buf: buffer): string
	local length = buffer.len(buf)
	local out = table.create(math.ceil(length / 3))
	local index = 0
	while index + 3 <= length do
		local a, b, c = buffer.readu8(buf, index), buffer.readu8(buf, index + 1), buffer.readu8(buf, index + 2)
		local word = a * 65536 + b * 256 + c
		table.insert(
			out,
			CHARS[bit32.rshift(word, 18)]
				.. CHARS[bit32.band(bit32.rshift(word, 12), 63)]
				.. CHARS[bit32.band(bit32.rshift(word, 6), 63)]
				.. CHARS[bit32.band(word, 63)]
		)
		index += 3
	end
	local rest = length - index
	if rest == 1 then
		local a = buffer.readu8(buf, index)
		table.insert(out, CHARS[bit32.rshift(a, 2)] .. CHARS[bit32.band(bit32.lshift(a, 4), 63)] .. "==")
	elseif rest == 2 then
		local a, b = buffer.readu8(buf, index), buffer.readu8(buf, index + 1)
		local word = a * 256 + b
		table.insert(
			out,
			CHARS[bit32.rshift(word, 10)]
				.. CHARS[bit32.band(bit32.rshift(word, 4), 63)]
				.. CHARS[bit32.band(bit32.lshift(word, 2), 63)]
				.. "="
		)
	end
	return table.concat(out)
end

return Profile
