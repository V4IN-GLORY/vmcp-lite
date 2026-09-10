local HttpService = game:GetService("HttpService")
local BASE36_DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local TOKEN_LENGTH = 6
local TOKEN_MODULUS = 2_176_782_336
local function tokenFromNumber(value)
	local remaining = math.floor(math.abs(value)) % TOKEN_MODULUS
	local token = ""
	for index = 0, TOKEN_LENGTH - 1 do
		local digit = remaining % 36
		token = string.sub(BASE36_DIGITS, digit + 1, digit + 1) .. token
		remaining = math.floor(remaining / 36)
	end
	return `{string.sub(token, 1, 3)}-{string.sub(token, 4, 6)}`
end
local function formatId(kind, value)
	return `{kind}:{tokenFromNumber(value)}`
end
local function randomValue()
	local guidPrefix = string.sub(HttpService:GenerateGUID(false), 1, 8)
	local condition = tonumber(guidPrefix, 16)
	if condition == nil then
		condition = 0
	end
	return condition
end
local function createPeerId()
	return formatId("peer", randomValue())
end
local function createInstanceId()
	return formatId("instance", randomValue())
end
return {
	createPeerId = createPeerId,
	createInstanceId = createInstanceId,
}
