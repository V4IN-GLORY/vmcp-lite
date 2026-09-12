--!strict
--!optimize 2

-- Runs a function a lot of times and says how long it took.
--
-- The point isn't the total -- that you could time yourself. It's the distribution: a function
-- whose mean is fine and whose p99 is forty times the median is the one causing the hitch, and an
-- average hides that completely. Pair it with `perFrame` to reproduce the shape of real load
-- instead of a tight loop the scheduler never sees.

local RunService = game:GetService("RunService")

local Bench = {}

export type Options = {
	-- Total calls. Defaults to 1000, or unlimited when `seconds` is set.
	times: number?,
	-- Stop after this long however many calls that took.
	seconds: number?,
	-- Calls per frame. Without it the calls run back to back with no yielding at all.
	perFrame: number?,
	-- Passed to the function on every call.
	args: { any }?,
	-- Calls to make and throw away first, so JIT warmup and lazy init don't skew the numbers.
	warmup: number?,
}

export type Report = {
	calls: number,
	errors: number,
	firstError: string?,
	totalMs: number,
	meanMs: number,
	minMs: number,
	maxMs: number,
	p50Ms: number,
	p95Ms: number,
	p99Ms: number,
	elapsedSeconds: number,
}

local DEFAULT_TIMES = 1000
local MAX_SAMPLES = 20000

local function percentile(sorted: { number }, fraction: number): number
	if #sorted == 0 then
		return 0
	end
	local index = math.clamp(math.ceil(fraction * #sorted), 1, #sorted)
	return sorted[index]
end

function Bench.Run(fn: (...any) -> ...any, options: Options?): Report
	local settings = options or ({} :: Options)
	local args = settings.args or {}
	local limit = settings.times or (if settings.seconds then math.huge else DEFAULT_TIMES)
	local perFrame = settings.perFrame
	local deadline = if settings.seconds then os.clock() + settings.seconds else math.huge

	for _ = 1, settings.warmup or 0 do
		pcall(fn, table.unpack(args))
	end

	local samples: { number } = {}
	local errors = 0
	local firstError: string? = nil
	local calls = 0
	local started = os.clock()
	local thisFrame = 0

	while calls < limit and os.clock() < deadline do
		local before = os.clock()
		local ok, failure = pcall(fn, table.unpack(args))
		local took = (os.clock() - before) * 1000

		calls += 1
		if #samples < MAX_SAMPLES then
			table.insert(samples, took)
		end
		if not ok then
			errors += 1
			firstError = firstError or tostring(failure)
		end

		if perFrame then
			thisFrame += 1
			if thisFrame >= perFrame then
				thisFrame = 0
				RunService.Heartbeat:Wait()
			end
		end
	end

	local elapsed = os.clock() - started
	table.sort(samples)

	local total = 0
	for _, sample in samples do
		total += sample
	end

	return {
		calls = calls,
		errors = errors,
		firstError = firstError,
		totalMs = total,
		meanMs = if #samples > 0 then total / #samples else 0,
		minMs = if #samples > 0 then samples[1] else 0,
		maxMs = if #samples > 0 then samples[#samples] else 0,
		p50Ms = percentile(samples, 0.5),
		p95Ms = percentile(samples, 0.95),
		p99Ms = percentile(samples, 0.99),
		elapsedSeconds = elapsed,
	}
end

-- One line, because the full report in a timeline note is unreadable.
function Bench.Summarise(report: Report): string
	local shape = string.format(
		"mean %.3fms, p50 %.3f, p95 %.3f, p99 %.3f, max %.3f",
		report.meanMs,
		report.p50Ms,
		report.p95Ms,
		report.p99Ms,
		report.maxMs
	)
	local failures = if report.errors > 0 then `, {report.errors} errored ({report.firstError})` else ""
	return `{report.calls} calls in {string.format("%.2f", report.elapsedSeconds)}s -- {shape}{failures}`
end

return Bench
