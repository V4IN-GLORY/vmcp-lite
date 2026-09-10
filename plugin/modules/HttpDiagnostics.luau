local HttpService = game:GetService("HttpService")
local function encodeForLog(value)
	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(value)
	end)
	return if ok then encoded else tostring(value)
end
local function formatBody(body)
	if body == "" then
		return ""
	end
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(body)
	end)
	if ok and type(decoded) == "table" then
		local data = decoded
		local parts = {}
		if type(data.error) == "string" and data.error ~= "" then
			table.insert(parts, `error={data.error}`)
		end
		if type(data.message) == "string" and data.message ~= "" then
			table.insert(parts, `message={data.message}`)
		end
		if data.missingFields ~= nil then
			local arg0 = `missingFields={encodeForLog(data.missingFields)}`
			table.insert(parts, arg0)
		end
		if data.request ~= nil then
			local arg0 = `request={encodeForLog(data.request)}`
			table.insert(parts, arg0)
		end
		if data.existing ~= nil then
			local arg0 = `existing={encodeForLog(data.existing)}`
			table.insert(parts, arg0)
		end
		if data.details ~= nil then
			local arg0 = `details={encodeForLog(data.details)}`
			table.insert(parts, arg0)
		end
		if #parts > 0 then
			return table.concat(parts, " ")
		end
	end
	return `body={body}`
end
local function formatRequestFailure(url, ok, res)
	if not ok then
		return `RequestAsync threw for {url}: {tostring(res)}`
	end
	if res == nil then
		return `RequestAsync returned no response for {url}`
	end
	local response = res
	local statusMessage = if response.StatusMessage ~= "" then ` {response.StatusMessage}` else ""
	local body = formatBody(response.Body)
	local suffix = if body ~= "" then `: {body}` else ""
	return `HTTP {response.StatusCode}{statusMessage} from {url}{suffix}`
end
return {
	formatRequestFailure = formatRequestFailure,
}
