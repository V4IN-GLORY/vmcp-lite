local Utils = require(script.Parent.Parent.Utils)
local Recording = require(script.Parent.Parent.Recording)
local AssetSanitizationPolicy = require(script.Parent.Parent.AssetSanitizationPolicy)
local sanitizeLoadedAsset = AssetSanitizationPolicy.sanitizeLoadedAsset
local scanForbiddenImportedInstances = AssetSanitizationPolicy.scanForbiddenImportedInstances
local AssetService = game:GetService("AssetService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")
local binding = Utils
local getInstancePath = binding.getInstancePath
local getInstanceByPath = binding.getInstanceByPath
local binding_1 = Recording
local beginRecording = binding_1.beginRecording
local finishRecording = binding_1.finishRecording
local THIRD_PARTY_ASSET_SETTING_HINT =
	'\nTo load public Creator Store assets that you do not own, enable "Allow Loading Third Party Assets" in Game Settings > Security.'
local function destroyImportedRoot(root)
	pcall(function()
		root:Destroy()
	end)
end
local function formatAssetLoadFailure(assetId, loadError)
	local settingReadable, allowInsertFreeAssets = pcall(function()
		return AssetService.AllowInsertFreeAssets
	end)
	local settingHint = if settingReadable and allowInsertFreeAssets == true then "" else THIRD_PARTY_ASSET_SETTING_HINT
	return `Failed to load asset {assetId}: {tostring(loadError)}{settingHint}`
end
local sanitizationOperations = {
	forceUnparent = function(root)
		local instance = root
		local unparentedOk = pcall(function()
			instance.Parent = nil
		end)
		return unparentedOk and instance.Parent == nil
	end,
	destroy = function(instance)
		local destroyed = pcall(function()
			instance:Destroy()
		end)
		return destroyed
	end,
}
local function insertAsset(requestData)
	local assetId = requestData.assetId
	local condition = requestData.parentPath
	if condition == nil then
		condition = "game.Workspace"
	end
	local parentPath = condition
	local position = requestData.position
	if not (assetId ~= 0 and assetId == assetId and assetId) then
		return {
			error = "assetId is required",
		}
	end
	local parentInstance = getInstanceByPath(parentPath)
	if not parentInstance then
		return {
			error = `Parent instance not found: {parentPath}`,
		}
	end
	local recordingId = beginRecording(`Insert asset {assetId}`)
	local wrapperModel
	local insertedInstances = {}
	local insertSuccess, insertResult = pcall(function()
		local loadSuccess, loadResult = pcall(function()
			return AssetService:LoadAssetAsync(assetId)
		end)
		if not loadSuccess or not loadResult then
			error(formatAssetLoadFailure(assetId, loadResult), 0)
		end
		local loadedWrapper = loadResult
		wrapperModel = loadedWrapper
		local sanitization = sanitizeLoadedAsset(loadedWrapper, sanitizationOperations)
		if not sanitization.success then
			error(if sanitization.error ~= nil then sanitization.error else "Asset sanitization failed.", 0)
		end
		local children = loadedWrapper:GetChildren()
		-- Position while every sanitized child is still contained by the
		-- unparented wrapper. Nothing reaches the DataModel before verification.
		if position then
			local pos = Vector3.new(
				if position.x ~= nil then position.x else 0,
				if position.y ~= nil then position.y else 0,
				if position.z ~= nil then position.z else 0
			)
			for _, inst in children do
				if inst:IsA("BasePart") then
					inst.Position = pos
				elseif inst:IsA("Model") then
					if inst.PrimaryPart then
						inst:PivotTo(CFrame.new(pos))
					else
						local firstPart = inst:FindFirstChildWhichIsA("BasePart", true)
						if firstPart then
							inst:PivotTo(CFrame.new(pos))
						end
					end
				end
			end
		end
		-- This is the first point at which imported content is parented into
		-- Studio. Both unlimited-depth scans have already passed.
		for _, child in children do
			child.Parent = parentInstance
			table.insert(insertedInstances, child)
		end
		pcall(function()
			Selection:Set(insertedInstances)
		end)
		-- ▼ ReadonlyArray.map ▼
		local newValue = table.create(#insertedInstances)
		local callback = function(inst)
			return {
				name = inst.Name,
				className = inst.ClassName,
				path = getInstancePath(inst),
			}
		end
		for _k, _v in insertedInstances do
			newValue[_k] = callback(_v, _k - 1, insertedInstances)
		end
		-- ▲ ReadonlyArray.map ▲
		local resultInstances = newValue
		return {
			success = true,
			assetId = assetId,
			parentPath = parentPath,
			insertedCount = #insertedInstances,
			instances = resultInstances,
			sanitization = {
				removedScriptCount = sanitization.removedScriptCount,
				removedPackageLinkCount = sanitization.removedPackageLinkCount,
				verifiedClean = true,
			},
		}
	end)
	if not insertSuccess then
		-- Roll back any partially-parented children if a later operation failed.
		for _, inserted in insertedInstances do
			pcall(function()
				inserted:Destroy()
			end)
		end
	end
	if wrapperModel then
		pcall(function()
			wrapperModel:Destroy()
		end)
	end
	finishRecording(recordingId, insertSuccess)
	if not insertSuccess then
		return {
			error = `Failed to insert asset {assetId}: {tostring(insertResult)}`,
		}
	end
	return insertResult
end
local function previewAsset(requestData)
	local assetId = requestData.assetId
	local condition = requestData.includeProperties
	if condition == nil then
		condition = false
	end
	local includeProperties = condition
	local condition_1 = requestData.maxDepth
	if condition_1 == nil then
		condition_1 = 4
	end
	local maxDepth = condition_1
	if not (assetId ~= 0 and assetId == assetId and assetId) then
		return {
			error = "assetId is required",
		}
	end
	local loadSuccess, wrapperModel = pcall(function()
		return AssetService:LoadAssetAsync(assetId)
	end)
	if not loadSuccess or not wrapperModel then
		return {
			error = formatAssetLoadFailure(assetId, wrapperModel),
		}
	end
	-- Previewed assets never enter the DataModel.
	local unparentedOk = pcall(function()
		wrapperModel.Parent = nil
	end)
	if not unparentedOk or wrapperModel.Parent ~= nil then
		destroyImportedRoot(wrapperModel)
		return {
			error = `Failed to keep asset {assetId} unparented for preview`,
		}
	end
	-- Security and visual-capability tracking always scan the full descendant
	-- hierarchy. maxDepth only affects the display tree below.
	local totalInstances = 0
	local classCounts = {}
	local hasAnimations = false
	local hasSounds = false
	local hasParticles = false
	local hasVfx = false
	local hasDecalsOrTextures = false
	local hasMeshes = false
	local hasLights = false
	local hasAttachments = false
	local soundReferences = {}
	local uniqueSoundContentIds = {}
	local function recordSummary(instance)
		totalInstances += 1
		local className = instance.ClassName
		local condition_2 = classCounts[className]
		if condition_2 == nil then
			condition_2 = 0
		end
		classCounts[className] = condition_2 + 1
		if className == "Animation" or className == "AnimationController" or className == "Animator" then
			hasAnimations = true
		end
		if instance:IsA("Sound") then
			hasSounds = true
			local sound = instance
			local soundId = sound.SoundId
			if soundId ~= "" then
				uniqueSoundContentIds[soundId] = true
			end
			local arg0 = {
				path = sound:GetFullName(),
				name = sound.Name,
				className = className,
				soundId = soundId,
				volume = sound.Volume,
				playbackSpeed = sound.PlaybackSpeed,
				looped = sound.Looped,
				isLoaded = sound.IsLoaded,
				timeLength = sound.TimeLength,
				rollOffMode = tostring(sound.RollOffMode),
				rollOffMinDistance = sound.RollOffMinDistance,
				rollOffMaxDistance = sound.RollOffMaxDistance,
			}
			table.insert(soundReferences, arg0)
		elseif instance:IsA("AudioPlayer") then
			hasSounds = true
			local audioPlayer = instance
			local soundId = tostring(audioPlayer.Asset)
			if soundId ~= "" then
				uniqueSoundContentIds[soundId] = true
			end
			local arg0 = {
				path = audioPlayer:GetFullName(),
				name = audioPlayer.Name,
				className = className,
				soundId = soundId,
				volume = audioPlayer.Volume,
				playbackSpeed = audioPlayer.PlaybackSpeed,
				looped = audioPlayer.Looping,
				autoPlay = audioPlayer.AutoPlay,
				isLoaded = audioPlayer.IsReady,
				timeLength = audioPlayer.TimeLength,
			}
			table.insert(soundReferences, arg0)
		end
		if
			instance:IsA("ParticleEmitter")
			or className == "Fire"
			or className == "Smoke"
			or className == "Sparkles"
		then
			hasParticles = true
			hasVfx = true
		end
		if instance:IsA("Beam") or instance:IsA("Trail") then
			hasVfx = true
		end
		if instance:IsA("Decal") or instance:IsA("Texture") then
			hasDecalsOrTextures = true
		end
		if instance:IsA("MeshPart") or instance:IsA("SpecialMesh") then
			hasMeshes = true
		end
		if instance:IsA("Light") then
			hasLights = true
		end
		if instance:IsA("Attachment") then
			hasAttachments = true
		end
	end
	recordSummary(wrapperModel)
	for _, descendant in wrapperModel:GetDescendants() do
		recordSummary(descendant)
	end
	local forbiddenScan = scanForbiddenImportedInstances(wrapperModel)
	local function buildHierarchy(instance, depth)
		local className = instance.ClassName
		local node = {
			name = instance.Name,
			className = className,
		}
		if includeProperties then
			local props = {}
			if instance:IsA("BasePart") then
				props.size = {
					x = instance.Size.X,
					y = instance.Size.Y,
					z = instance.Size.Z,
				}
				props.position = {
					x = instance.Position.X,
					y = instance.Position.Y,
					z = instance.Position.Z,
				}
				props.material = tostring(instance.Material)
				props.color = `{instance.Color.R}, {instance.Color.G}, {instance.Color.B}`
				props.transparency = instance.Transparency
				props.anchored = instance.Anchored
			end
			if instance:IsA("MeshPart") then
				local meshPart = instance
				props.meshId = meshPart.MeshId
				props.textureId = meshPart.TextureID
			end
			if instance:IsA("Model") then
				local model = instance
				if model.PrimaryPart then
					props.primaryPart = model.PrimaryPart.Name
				end
			end
			if className == "Decal" or className == "Texture" then
				local ok, texId = pcall(function()
					return instance.Texture
				end)
				if ok then
					props.texture = texId
				end
			end
			if instance:IsA("Sound") then
				props.soundId = instance.SoundId
			elseif instance:IsA("AudioPlayer") then
				props.soundId = tostring(instance.Asset)
			end
			-- Only include props if there are any
			local hasProps = false
			for _element, _element_1 in pairs(props) do
				local _ = { _element, _element_1 }
				hasProps = true
				break
			end
			if hasProps then
				node.properties = props
			end
		end
		if depth < maxDepth then
			local childNodes = {}
			for _, child in instance:GetChildren() do
				local arg0 = buildHierarchy(child, depth + 1)
				table.insert(childNodes, arg0)
			end
			if #childNodes > 0 then
				node.children = childNodes
			end
		else
			local childCount = #instance:GetChildren()
			if childCount > 0 then
				node.childCount = childCount
				node.truncated = true
			end
		end
		return node
	end
	local previewSuccess, previewResult = pcall(function()
		local hierarchyRoots = {}
		for _, child in wrapperModel:GetChildren() do
			local arg0 = buildHierarchy(child, 0)
			table.insert(hierarchyRoots, arg0)
		end
		local object = {
			success = true,
			assetId = assetId,
			hierarchy = hierarchyRoots,
			sounds = soundReferences,
		}
		local object_1 = {
			totalInstances = totalInstances,
			classCounts = classCounts,
			hasScripts = #forbiddenScan.scripts > 0,
			scriptCount = #forbiddenScan.scripts,
			hasPackageLinks = #forbiddenScan.packageLinks > 0,
			packageLinkCount = #forbiddenScan.packageLinks,
			hasAnimations = hasAnimations,
			hasSounds = hasSounds,
			soundCount = #soundReferences,
		}
		-- ▼ ReadonlySet.size ▼
		local _size = 0
		for _ in uniqueSoundContentIds do
			_size += 1
		end
		-- ▲ ReadonlySet.size ▲
		object_1.uniqueSoundContentIdCount = _size
		object_1.hasParticles = hasParticles
		object_1.hasVfx = hasVfx
		object_1.hasDecalsOrTextures = hasDecalsOrTextures
		object_1.hasMeshes = hasMeshes
		object_1.hasLights = hasLights
		object_1.hasAttachments = hasAttachments
		object_1.securityScanDepth = "unlimited"
		object_1.scriptSourceExposed = false
		object_1.insertPolicy =
			"All LuaSourceContainer and PackageLink instances are stripped and verified before insertion."
		object.summary = object_1
		return object
	end)
	pcall(function()
		wrapperModel:Destroy()
	end)
	if not previewSuccess then
		return {
			error = `Failed to preview asset {assetId}: {tostring(previewResult)}`,
		}
	end
	return previewResult
end
return {
	insertAsset = insertAsset,
	previewAsset = previewAsset,
}
