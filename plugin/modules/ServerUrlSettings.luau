local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local SETTING_KEY_PREFIX = "MCP_LAST_SUCCESSFUL_SERVER_URL_"
local GLOBAL_SETTING_KEY = "MCP_LAST_SUCCESSFUL_SERVER_URL_GLOBAL_V1"
local pluginRef
local function init(p)
	pluginRef = p
end
local function normalizeServerUrl(serverUrl)
	local normalized = (string.gsub((string.gsub(if serverUrl ~= nil then serverUrl else "", "^%s+", "")), "%s+$", ""))
	if normalized == "" then
		return ""
	end
	if (string.match(normalized, "^%a[%w+.-]*://")) == nil then
		normalized = `http://{normalized}`
	end
	while
		#normalized > 0
		and string.sub(normalized, -1) == "/"
		and (string.match(normalized, "^%a[%w+.-]*://$")) == nil
	do
		normalized = string.sub(normalized, 1, -2)
	end
	return normalized
end
local function extractPort(serverUrl)
	local portStr = string.match(serverUrl, ":(%d+)$")
	if portStr == nil then
		return nil
	end
	return tonumber(portStr)
end
local function addUnique(values, value)
	if not (table.find(values, value) ~= nil) then
		table.insert(values, value)
	end
end
local function computePlaceKeys(options)
	local placeKeys = {}
	if game.PlaceId ~= 0 then
		addUnique(placeKeys, `place:{tostring(game.PlaceId)}`)
	end
	local existing = ServerStorage:GetAttribute("__MCPPlaceId")
	if type(existing) == "string" and existing ~= "" then
		addUnique(placeKeys, `anon:{existing}`)
	else
		local condition = game.PlaceId == 0
		if condition then
			local result = options
			if result ~= nil then
				result = result.createAnonymous
			end
			condition = result == true
		end
		if condition then
			local fresh = HttpService:GenerateGUID(false)
			pcall(function()
				return ServerStorage:SetAttribute("__MCPPlaceId", fresh)
			end)
			addUnique(placeKeys, `anon:{fresh}`)
		end
	end
	return placeKeys
end
local function settingKey(placeKey)
	return SETTING_KEY_PREFIX .. placeKey
end
local function readSettingString(key)
	if not pluginRef then
		return nil
	end
	local ok, value = pcall(function()
		return pluginRef:GetSetting(key)
	end)
	if not ok or not (type(value) == "string") then
		return nil
	end
	local normalized = normalizeServerUrl(value)
	return if normalized ~= "" then normalized else nil
end
local function writeSettingString(key, serverUrl)
	if not pluginRef then
		return nil
	end
	pcall(function()
		return pluginRef:SetSetting(key, serverUrl)
	end)
end
local function rememberServerUrl(serverUrl)
	local normalized = normalizeServerUrl(serverUrl)
	if not pluginRef or normalized == "" then
		return nil
	end
	writeSettingString(GLOBAL_SETTING_KEY, normalized)
	for _, placeKey in computePlaceKeys({
		createAnonymous = true,
	}) do
		writeSettingString(settingKey(placeKey), normalized)
	end
end
local function readServerUrl()
	if not pluginRef then
		return nil
	end
	-- Reading settings should not mint a place key. Client play DataModels have
	-- their own ServerStorage; creating a key there would not match the
	-- edit/server place-scoped setting.
	for _, placeKey in computePlaceKeys() do
		local remembered = readSettingString(settingKey(placeKey))
		if remembered ~= nil then
			return remembered
		end
	end
	local globalRemembered = readSettingString(GLOBAL_SETTING_KEY)
	if globalRemembered ~= nil then
		return globalRemembered
	end
	return nil
end
return {
	init = init,
	normalizeServerUrl = normalizeServerUrl,
	extractPort = extractPort,
	rememberServerUrl = rememberServerUrl,
	readServerUrl = readServerUrl,
}
