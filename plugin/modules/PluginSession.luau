local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local State = require(script.Parent.State)
local PeerRole = require(script.Parent.PeerRole)
local TopologyId = require(script.Parent.TopologyId)
local CoreGui = game:GetService("CoreGui")
local MCP_PLACE_ID_ATTRIBUTE = "__MCPPlaceId"
local TOPOLOGY_MODE_ATTRIBUTE = "__MCPTopologyMode"
local TOPOLOGY_INSTANCE_ID_ATTRIBUTE = "__MCPTopologyInstanceId"
local TOPOLOGY_GROUP_ID_ATTRIBUTE = "__MCPTopologyGroupId"
local TOPOLOGY_TOKEN_ATTRIBUTE = "__MCPTopologyToken"
local SESSION_IDENTITY_NAME = "__MCPSessionIdentity"
local peerId = TopologyId.createPeerId()
local isEditSession = PeerRole.detect() == "edit"
local existingSessionIdentity = CoreGui:FindFirstChild(SESSION_IDENTITY_NAME)
local sessionInstanceId
local createdSessionIdentity = false
if
	existingSessionIdentity ~= nil
	and existingSessionIdentity:IsA("StringValue")
	and not existingSessionIdentity.Archivable
	and (
			string.match(existingSessionIdentity.Value, "^instance:[0-9a-z][0-9a-z][0-9a-z]%-[0-9a-z][0-9a-z][0-9a-z]$")
		)
		~= nil
then
	sessionInstanceId = existingSessionIdentity.Value
else
	local result = existingSessionIdentity
	if result ~= nil then
		result:Destroy()
	end
	sessionInstanceId = TopologyId.createInstanceId()
	local sessionIdentity = Instance.new("StringValue")
	sessionIdentity.Name = SESSION_IDENTITY_NAME
	sessionIdentity.Value = sessionInstanceId
	sessionIdentity.Archivable = false
	sessionIdentity.Parent = CoreGui
	createdSessionIdentity = true
end
local inheritedInstanceId
local cachedPlaceName
local cachedPlaceNamePlaceId
local function getMarkerMode()
	local mode = ReplicatedStorage:GetAttribute(TOPOLOGY_MODE_ATTRIBUTE)
	return if mode == "shared" or mode == "multiplayer" then mode else nil
end
local function getInstanceId()
	if inheritedInstanceId ~= nil then
		return inheritedInstanceId
	end
	if not isEditSession and getMarkerMode() == "shared" then
		local sharedInstanceId = ReplicatedStorage:GetAttribute(TOPOLOGY_INSTANCE_ID_ATTRIBUTE)
		if type(sharedInstanceId) == "string" and sharedInstanceId ~= "" then
			inheritedInstanceId = sharedInstanceId
			return sharedInstanceId
		end
	end
	return sessionInstanceId
end
local function getMultiplayerGroupId()
	if getMarkerMode() ~= "multiplayer" then
		return nil
	end
	local groupId = ReplicatedStorage:GetAttribute(TOPOLOGY_GROUP_ID_ATTRIBUTE)
	return if type(groupId) == "string" and groupId ~= "" then groupId else nil
end
local function getPlaceKey()
	if game.PlaceId ~= 0 then
		return `place:{tostring(game.PlaceId)}`
	end
	local existing = ServerStorage:GetAttribute(MCP_PLACE_ID_ATTRIBUTE)
	if type(existing) == "string" and existing ~= "" then
		return `anon:{existing}`
	end
	local fresh = HttpService:GenerateGUID(false)
	pcall(function()
		return ServerStorage:SetAttribute(MCP_PLACE_ID_ATTRIBUTE, fresh)
	end)
	return `anon:{fresh}`
end
local function setTopologyMarker(mode, instanceId, groupId)
	local token = HttpService:GenerateGUID(false)
	ReplicatedStorage:SetAttribute(TOPOLOGY_MODE_ATTRIBUTE, nil)
	ReplicatedStorage:SetAttribute(TOPOLOGY_INSTANCE_ID_ATTRIBUTE, instanceId)
	ReplicatedStorage:SetAttribute(TOPOLOGY_GROUP_ID_ATTRIBUTE, groupId)
	ReplicatedStorage:SetAttribute(TOPOLOGY_TOKEN_ATTRIBUTE, token)
	ReplicatedStorage:SetAttribute(TOPOLOGY_MODE_ATTRIBUTE, mode)
	return token
end
local function prepareSharedTopology()
	return setTopologyMarker("shared", sessionInstanceId, nil)
end
local function prepareMultiplayerTopology(groupId)
	return setTopologyMarker("multiplayer", nil, groupId)
end
local function clearTopologyMarker(token)
	if ReplicatedStorage:GetAttribute(TOPOLOGY_TOKEN_ATTRIBUTE) ~= token then
		return nil
	end
	if isEditSession then
		prepareSharedTopology()
		return nil
	end
	ReplicatedStorage:SetAttribute(TOPOLOGY_MODE_ATTRIBUTE, nil)
	ReplicatedStorage:SetAttribute(TOPOLOGY_INSTANCE_ID_ATTRIBUTE, nil)
	ReplicatedStorage:SetAttribute(TOPOLOGY_GROUP_ID_ATTRIBUTE, nil)
	ReplicatedStorage:SetAttribute(TOPOLOGY_TOKEN_ATTRIBUTE, nil)
end
local function getRole()
	return PeerRole.detect()
end
local function invalidatePlaceName()
	cachedPlaceName = nil
	cachedPlaceNamePlaceId = nil
end
local function getPlaceName()
	if cachedPlaceName ~= nil and cachedPlaceNamePlaceId == game.PlaceId then
		return cachedPlaceName
	end
	invalidatePlaceName()
	cachedPlaceNamePlaceId = game.PlaceId
	if game.PlaceId == 0 then
		cachedPlaceName = game.Name
		return cachedPlaceName
	end
	local MarketplaceService = game:GetService("MarketplaceService")
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(game.PlaceId)
	end)
	if ok and info ~= nil then
		-- GetProductInfo's generated type is broader than the place metadata returned here.
		local placeInfo = info
		local name = placeInfo.Name
		if type(name) == "string" and name ~= "" then
			cachedPlaceName = name
			return cachedPlaceName
		end
	end
	return game.Name
end
local function createReadyPayload(readyPeerId, role, instanceId, multiplayerGroupId)
	if instanceId == nil then
		instanceId = getInstanceId()
	end
	if multiplayerGroupId == nil then
		multiplayerGroupId = getMultiplayerGroupId()
	end
	return {
		peerId = readyPeerId,
		transportPeerId = peerId,
		instanceId = instanceId,
		multiplayerGroupId = multiplayerGroupId,
		role = role,
		placeId = game.PlaceId,
		placeName = getPlaceName(),
		placeKey = getPlaceKey(),
		dataModelName = game.Name,
		isRunning = RunService:IsRunning(),
		pluginVersion = State.CURRENT_VERSION,
		pluginVariant = State.PLUGIN_VARIANT,
		timestamp = tick(),
	}
end
-- CoreGui survives plugin reloads without saving or replicating this identity.
-- Preserve active test markers on reload; fresh edits replace saved place markers.
if isEditSession then
	if createdSessionIdentity or getMarkerMode() == nil then
		prepareSharedTopology()
	end
else
	getInstanceId()
end
return {
	peerId = peerId,
	getInstanceId = getInstanceId,
	getMultiplayerGroupId = getMultiplayerGroupId,
	getPlaceKey = getPlaceKey,
	getRole = getRole,
	getPlaceName = getPlaceName,
	invalidatePlaceName = invalidatePlaceName,
	prepareSharedTopology = prepareSharedTopology,
	prepareMultiplayerTopology = prepareMultiplayerTopology,
	clearTopologyMarker = clearTopologyMarker,
	createReadyPayload = createReadyPayload,
}
