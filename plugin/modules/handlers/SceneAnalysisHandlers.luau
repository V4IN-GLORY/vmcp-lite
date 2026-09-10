local MODE_CONFIGS = {
	instance_composition = {
		method = "GetInstanceCompositionAsync",
		query = function(service)
			return service:GetInstanceCompositionAsync()
		end,
	},
	script_memory = {
		method = "GetScriptMemoryAsync",
		query = function(service)
			return service:GetScriptMemoryAsync()
		end,
	},
	unparented_instances = {
		method = "GetUnparentedInstancesAsync",
		query = function(service)
			return service:GetUnparentedInstancesAsync()
		end,
	},
	triangle_composition = {
		method = "GetTriangleCompositionAsync",
		query = function(service)
			return service:GetTriangleCompositionAsync()
		end,
		sortByTriangles = true,
	},
	animation_memory = {
		method = "GetAnimationMemoryAsync",
		query = function(service)
			return service:GetAnimationMemoryAsync()
		end,
	},
	audio_memory = {
		method = "GetAudioMemoryAsync",
		query = function(service)
			return service:GetAudioMemoryAsync()
		end,
	},
}
local ALL_MODES = {
	"instance_composition",
	"script_memory",
	"unparented_instances",
	"triangle_composition",
	"animation_memory",
	"audio_memory",
}
local function betaDisabledError()
	return {
		error = "scene_analysis_not_enabled",
		message = "SceneAnalysisService is not enabled. Enable Scene Analysis in Studio Beta Features and restart Studio.",
		betaFeatureRequired = true,
	}
end
local function isBetaDisabledError(value)
	return type(value) == "string" and (string.find(value, "SceneAnalysisService is not enabled", 1, true)) ~= nil
end
local function getSceneAnalysisService()
	local provider = game
	local ok, service = pcall(function()
		return provider:GetService("SceneAnalysisService")
	end)
	if not ok or not service then
		return {
			error = "scene_analysis_unavailable",
			message = `SceneAnalysisService is unavailable: {tostring(service)}`,
		}
	end
	return service
end
local function normalizeMode(mode)
	if mode == nil or mode == "all" then
		return "all"
	end
	if not (type(mode) == "string") or MODE_CONFIGS[mode] == nil then
		return {
			error = "invalid_mode",
			message = `mode must be one of: all, {table.concat(ALL_MODES, ", ")}`,
		}
	end
	return mode
end
local function normalizeTopN(topN)
	if not (type(topN) == "number") then
		return 10
	end
	return math.clamp(math.floor(topN), 1, 100)
end
local function countLeaves(node)
	local children = node.Children
	if children and #children > 0 then
		local total = 0
		for _, child in children do
			total += countLeaves(child)
		end
		return total
	end
	return 1
end
local function flattenLeaves(node, out)
	local children = node.Children
	if children and #children > 0 then
		for _, child in children do
			flattenLeaves(child, out)
		end
		return nil
	end
	table.insert(out, node)
end
local function compactEntry(node)
	local entry = {
		name = node.Name,
	}
	if node.Size ~= nil then
		entry.size = node.Size
	end
	if node.Sizes ~= nil then
		entry.sizes = node.Sizes
	end
	if node.AssetId ~= nil then
		entry.asset_id = node.AssetId
	end
	return entry
end
local function compactRoot(node, leafCount)
	local children = node.Children
	local root = {
		name = node.Name,
		child_count = if children then #children else 0,
		leaf_count = leafCount,
	}
	if node.Size ~= nil then
		root.size = node.Size
	end
	if node.Sizes ~= nil then
		root.sizes = node.Sizes
	end
	return root
end
local function metric(node, sortByTriangles)
	if sortByTriangles then
		local sizes = node.Sizes
		local triangles = if sizes then sizes.Triangles else nil
		return if triangles ~= nil then triangles else 0
	end
	return if node.Size ~= nil then node.Size else 0
end
local function summarizeMode(mode, config, service, topN, raw)
	local started = os.clock()
	local ok, result = pcall(function()
		return config.query(service)
	end)
	local elapsedMs = math.floor((os.clock() - started) * 1000)
	if not ok then
		if isBetaDisabledError(result) then
			return betaDisabledError()
		end
		return {
			error = "scene_analysis_query_failed",
			mode = mode,
			method = config.method,
			message = tostring(result),
		}
	end
	local tree = result
	local leaves = {}
	flattenLeaves(tree, leaves)
	table.sort(leaves, function(a, b)
		return metric(a, config.sortByTriangles == true) > metric(b, config.sortByTriangles == true)
	end)
	local top = {}
	do
		local i = 0
		local shouldIncrement = false
		while true do
			if shouldIncrement then
				i += 1
			else
				shouldIncrement = true
			end
			if not (i < math.min(topN, #leaves)) then
				break
			end
			local arg0 = compactEntry(leaves[i + 1])
			table.insert(top, arg0)
		end
	end
	local body = {
		mode = mode,
		method = config.method,
		elapsed_ms = elapsedMs,
		root = compactRoot(tree, #leaves),
		top = top,
	}
	if raw then
		body.tree = tree
	end
	return body
end
local function getSceneAnalysis(requestData)
	local mode = normalizeMode(requestData.mode)
	if not (type(mode) == "string") then
		return mode
	end
	local serviceOrError = getSceneAnalysisService()
	local value = serviceOrError.IsA
	if not (value ~= 0 and value == value and value ~= "" and value) then
		return serviceOrError
	end
	local service = serviceOrError
	local topN = normalizeTopN(requestData.topN)
	local raw = requestData.raw == true
	if mode ~= "all" then
		return summarizeMode(mode, MODE_CONFIGS[mode], service, topN, raw)
	end
	local body = {}
	for _, m in ALL_MODES do
		local result = summarizeMode(m, MODE_CONFIGS[m], service, topN, raw)
		if result.error == "scene_analysis_not_enabled" then
			return result
		end
		body[m] = result
	end
	return body
end
return {
	getSceneAnalysis = getSceneAnalysis,
}
