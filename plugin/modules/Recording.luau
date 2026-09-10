local ChangeHistoryService = game:GetService("ChangeHistoryService")
local function beginRecording(actionName)
	local success, result = pcall(function()
		return ChangeHistoryService:TryBeginRecording(`MCP: {actionName}`)
	end)
	if success then
		return result
	end
	return nil
end
local function finishRecording(recordingId, shouldCommit)
	if recordingId == nil then
		return nil
	end
	local operation = if shouldCommit
		then Enum.FinishRecordingOperation.Commit
		else Enum.FinishRecordingOperation.Cancel
	pcall(function()
		ChangeHistoryService:FinishRecording(recordingId, operation)
	end)
end
return {
	beginRecording = beginRecording,
	finishRecording = finishRecording,
}
