local Stats = game:GetService("Stats")
-- GetMemoryUsageMbAllCategories is gated by capability "InternalTest" and not
-- callable from plugin context. GetMemoryUsageMbForTag is not - so we iterate
-- Enum.DeveloperMemoryTag and ask per-tag.
local function getMemoryBreakdown(requestData)
	if not Stats.MemoryTrackingEnabled then
		return {
			error = "MemoryTrackingEnabled is false on this peer",
		}
	end
	local requested = requestData.tags
	local _result
	if requested and #requested > 0 then
		local set = {}
		for _, _v in requested do
			set[_v] = true
		end
		_result = set
	else
		_result = nil
	end
	local requestedSet = _result
	local categories = {}
	for _, item in Enum.DeveloperMemoryTag:GetEnumItems() do
		local name = item.Name
		if requestedSet and not (requestedSet[name] ~= nil) then
			continue
		end
		local ok, mb = pcall(function()
			return Stats:GetMemoryUsageMbForTag(item)
		end)
		categories[name] = if ok then mb else 0
	end
	local unknownTags = {}
	if requestedSet then
		local known = {}
		for _, i in Enum.DeveloperMemoryTag:GetEnumItems() do
			known[i.Name] = true
		end
		for t in requestedSet do
			if not (known[t] ~= nil) then
				table.insert(unknownTags, t)
				categories[t] = 0
			end
		end
	end
	local result = {
		total_mb = Stats:GetTotalMemoryUsageMb(),
		categories = categories,
		memory_tracking_enabled = true,
		timestamp = DateTime.now().UnixTimestampMillis,
	}
	if #unknownTags > 0 then
		result.unknown_tags = unknownTags
	end
	return result
end
return {
	getMemoryBreakdown = getMemoryBreakdown,
}
