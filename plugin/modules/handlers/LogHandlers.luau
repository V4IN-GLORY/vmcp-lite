local RuntimeLogBuffer = require(script.Parent.Parent.RuntimeLogBuffer)
local function getRuntimeLogs(requestData)
	local since = requestData.since
	local tail = requestData.tail
	local filter = requestData.filter
	return RuntimeLogBuffer.query({
		since = since,
		tail = tail,
		filter = filter,
	})
end
return {
	getRuntimeLogs = getRuntimeLogs,
}
