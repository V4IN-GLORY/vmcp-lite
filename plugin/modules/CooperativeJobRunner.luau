local DEADLINE_EXCEEDED = "__RSMCP_COOPERATIVE_JOB_DEADLINE_EXCEEDED__"
local CANCELLED = "__RSMCP_COOPERATIVE_JOB_CANCELLED__"
local MAX_SLICE_SECONDS = 0.008
local CLOCK_CHECK_INTERVAL = 64
local activeJobs = {}
local function runExclusive(key, execution, work)
	local activeRequestId = activeJobs[key]
	if activeRequestId ~= nil then
		return {
			error = "plugin_busy",
			activeRequestId = activeRequestId,
		}
	end
	activeJobs[key] = execution.requestId
	local sliceStartedAt = os.clock()
	local operationsUntilClockCheck = 0
	local control = {
		checkpoint = function(self)
			local result = execution.isCancelled
			if result ~= nil then
				result = result()
			end
			if result then
				error(CANCELLED, 0)
			end
			if operationsUntilClockCheck > 0 then
				operationsUntilClockCheck -= 1
				return nil
			end
			operationsUntilClockCheck = CLOCK_CHECK_INTERVAL - 1
			local now = os.clock()
			if execution.deadlineAt ~= nil and now >= execution.deadlineAt then
				error(DEADLINE_EXCEEDED, 0)
			end
			if now - sliceStartedAt >= MAX_SLICE_SECONDS then
				task.wait()
				sliceStartedAt = os.clock()
			end
		end,
	}
	local ok, result = pcall(function()
		return work(control)
	end)
	activeJobs[key] = nil
	if not ok then
		if result == DEADLINE_EXCEEDED then
			return {
				error = "deadline_exceeded",
				requestId = execution.requestId,
			}
		end
		if result == CANCELLED then
			return {
				error = "cancelled",
				requestId = execution.requestId,
			}
		end
		error(result, 0)
	end
	return result
end
return {
	runExclusive = runExclusive,
}
