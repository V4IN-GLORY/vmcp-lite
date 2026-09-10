local Utils = require(script.Parent.Parent.Utils)
local Recording = require(script.Parent.Parent.Recording)
local binding = Utils
local getInstanceByPath = binding.getInstanceByPath
local convertPropertyValue = binding.convertPropertyValue
local binding_1 = Recording
local beginRecording = binding_1.beginRecording
local finishRecording = binding_1.finishRecording
-- Native StringValue rejects UTF-8 strings of 200000 bytes or more.
local STRING_VALUE_MAX_BYTES = 199999
local function setProperties(requestData)
	local instancePath = requestData.instancePath
	local properties = requestData.properties
	if not (instancePath ~= "" and instancePath) or not properties or not (type(properties) == "table") then
		return {
			error = "Instance path and properties object are required",
		}
	end
	local instance = getInstanceByPath(instancePath)
	if not instance then
		return {
			error = `Instance not found: {instancePath}`,
		}
	end
	local recordingId = beginRecording("Set multiple properties")
	local inst = instance
	local results = {}
	local successCount = 0
	local failureCount = 0
	for propName, propValue in pairs(properties) do
		local success, err = pcall(function()
			if propName == "Parent" or propName == "PrimaryPart" then
				if type(propValue) == "string" then
					local refInstance = getInstanceByPath(propValue)
					if not refInstance then
						error(`{propName} reference not found: {propValue}`)
					end
					inst[propName] = refInstance
				end
			elseif propName == "Name" then
				instance.Name = tostring(propValue)
			elseif propName == "Source" and instance:IsA("LuaSourceContainer") then
				instance.Source = tostring(propValue)
			else
				local converted = convertPropertyValue(instance, propName, propValue)
				inst[propName] = if converted ~= nil then converted else propValue
			end
		end)
		if success then
			successCount += 1
			local arg0 = {
				property = propName,
				success = true,
			}
			table.insert(results, arg0)
		else
			failureCount += 1
			local failure = {
				property = propName,
				success = false,
				error = tostring(err),
			}
			if instance:IsA("StringValue") and propName == "Value" and type(propValue) == "string" then
				local object = table.clone(failure)
				setmetatable(object, nil)
				object.details = {
					stage = "property_write",
					bytes = #propValue,
					limitBytes = STRING_VALUE_MAX_BYTES,
				}
				table.insert(results, object)
			else
				table.insert(results, failure)
			end
		end
	end
	-- This tool is not a rollback transaction. Cancel can undo earlier unrecorded
	-- execute_luau edits as well, even when every assignment in this call failed.
	finishRecording(recordingId, true)
	return {
		instancePath = instancePath,
		summary = {
			total = successCount + failureCount,
			succeeded = successCount,
			failed = failureCount,
		},
		results = results,
	}
end
return {
	setProperties = setProperties,
}
