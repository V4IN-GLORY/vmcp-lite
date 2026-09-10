local Utils = require(script.Parent.Parent.Utils)
local CooperativeJobRunner = require(script.Parent.Parent.CooperativeJobRunner)
local ScriptSearch = require(script.Parent.Parent.ScriptSearch)
local binding = Utils
local getInstancePath = binding.getInstancePath
local getInstanceByPath = binding.getInstanceByPath
local readScriptSource = binding.readScriptSource
local function getFileTree(requestData)
	local condition = requestData.path
	if condition == nil then
		condition = ""
	end
	local path = condition
	local startInstance = getInstanceByPath(path)
	if not startInstance then
		return {
			error = `Path not found: {path}`,
		}
	end
	local function buildTree(instance, depth)
		if depth > 10 then
			return {
				name = instance.Name,
				className = instance.ClassName,
				children = {},
			}
		end
		local node = {
			name = instance.Name,
			className = instance.ClassName,
			path = getInstancePath(instance),
			children = {},
		}
		if instance:IsA("LuaSourceContainer") then
			node.hasSource = true
			node.scriptType = instance.ClassName
			if instance:IsA("BaseScript") then
				node.enabled = instance.Enabled
			end
		end
		for _, child in instance:GetChildren() do
			local arg0 = buildTree(child, depth + 1)
			table.insert(node.children, arg0)
		end
		return node
	end
	return {
		tree = buildTree(startInstance, 0),
		timestamp = tick(),
	}
end
local function searchFiles(requestData)
	local query = requestData.query
	local condition = requestData.searchType
	if condition == nil then
		condition = "name"
	end
	local searchType = condition
	if not (query ~= "" and query) then
		return {
			error = "Query is required",
		}
	end
	local results = {}
	local function searchRecursive(instance)
		local match = false
		if searchType == "name" then
			local exp = string.lower(instance.Name)
			local arg0 = string.lower(query)
			match = (string.find(exp, arg0)) ~= nil
		elseif searchType == "type" then
			local exp = string.lower(instance.ClassName)
			local arg0 = string.lower(query)
			match = (string.find(exp, arg0)) ~= nil
		elseif searchType == "content" and instance:IsA("LuaSourceContainer") then
			local exp = string.lower(readScriptSource(instance))
			local arg0 = string.lower(query)
			match = (string.find(exp, arg0)) ~= nil
		end
		if match then
			local entry = {
				name = instance.Name,
				className = instance.ClassName,
				path = getInstancePath(instance),
				hasSource = instance:IsA("LuaSourceContainer"),
			}
			if instance:IsA("BaseScript") then
				entry.enabled = instance.Enabled
			end
			table.insert(results, entry)
		end
		for _, child in instance:GetChildren() do
			searchRecursive(child)
		end
	end
	searchRecursive(game)
	return {
		results = results,
		query = query,
		searchType = searchType,
		count = #results,
	}
end
local function getPlaceInfo(_requestData)
	local dataModelName = game.Name
	local placeName = dataModelName
	if game.PlaceId > 0 then
		local MarketplaceService = game:GetService("MarketplaceService")
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(game.PlaceId)
		end)
		if ok and info ~= nil then
			local name = info.Name
			if type(name) == "string" and name ~= "" then
				placeName = name
			end
		end
	end
	return {
		placeName = placeName,
		dataModelName = dataModelName,
		placeId = game.PlaceId,
		gameId = game.GameId,
		jobId = game.JobId,
		workspace = {
			name = game.Workspace.Name,
			className = game.Workspace.ClassName,
		},
	}
end
local function searchObjects(requestData)
	local query = requestData.query
	local condition = requestData.searchType
	if condition == nil then
		condition = "name"
	end
	local searchType = condition
	local propertyName = requestData.propertyName
	if not (query ~= "" and query) then
		return {
			error = "Query is required",
		}
	end
	local results = {}
	local function searchRecursive(instance)
		local match = false
		if searchType == "name" then
			local exp = string.lower(instance.Name)
			local arg0 = string.lower(query)
			match = (string.find(exp, arg0)) ~= nil
		elseif searchType == "class" then
			local exp = string.lower(instance.ClassName)
			local arg0 = string.lower(query)
			match = (string.find(exp, arg0)) ~= nil
		else
			local _value = searchType == "property" and propertyName
			if _value ~= "" and _value then
				local success, value = pcall(function()
					return tostring(instance[propertyName])
				end)
				if success then
					local exp = string.lower(value)
					local arg0 = string.lower(query)
					match = (string.find(exp, arg0)) ~= nil
				end
			end
		end
		if match then
			local arg0 = {
				name = instance.Name,
				className = instance.ClassName,
				path = getInstancePath(instance),
			}
			table.insert(results, arg0)
		end
		for _, child in instance:GetChildren() do
			searchRecursive(child)
		end
	end
	searchRecursive(game)
	return {
		results = results,
		query = query,
		searchType = searchType,
		count = #results,
	}
end
local function getInstanceProperties(requestData)
	local instancePath = requestData.instancePath
	local condition = requestData.excludeSource
	if condition == nil then
		condition = false
	end
	local excludeSource = condition
	if not (instancePath ~= "" and instancePath) then
		return {
			error = "Instance path is required",
		}
	end
	local instance = getInstanceByPath(instancePath)
	if not instance then
		return {
			error = `Instance not found: {instancePath}`,
		}
	end
	local properties = {}
	local success, result = pcall(function()
		local basicProps = { "Name", "ClassName", "Parent" }
		for _, prop in basicProps do
			local propSuccess, propValue = pcall(function()
				local val = instance[prop]
				local value = prop == "Parent" and val
				if value ~= 0 and value == value and value ~= "" and value then
					return getInstancePath(val)
				end
				if val == nil then
					return "nil"
				end
				return tostring(val)
			end)
			if propSuccess then
				properties[prop] = propValue
			end
		end
		local commonProps = {
			"Size",
			"Position",
			"Rotation",
			"CFrame",
			"Anchored",
			"CanCollide",
			"Transparency",
			"BrickColor",
			"Material",
			"Color",
			"Text",
			"TextColor3",
			"BackgroundColor3",
			"Image",
			"ImageColor3",
			"Visible",
			"Active",
			"ZIndex",
			"BorderSizePixel",
			"BackgroundTransparency",
			"ImageTransparency",
			"TextTransparency",
			"Value",
			"Enabled",
			"Brightness",
			"Range",
			"Shadows",
			"Face",
			"SurfaceType",
		}
		for _, prop in commonProps do
			local propSuccess, propValue = pcall(function()
				local val = instance[prop]
				if typeof(val) == "UDim2" then
					local udim = val
					return {
						X = {
							Scale = udim.X.Scale,
							Offset = udim.X.Offset,
						},
						Y = {
							Scale = udim.Y.Scale,
							Offset = udim.Y.Offset,
						},
						_type = "UDim2",
					}
				end
				return tostring(val)
			end)
			if propSuccess then
				properties[prop] = propValue
			end
		end
		if instance:IsA("LuaSourceContainer") then
			if not excludeSource then
				properties.Source = readScriptSource(instance)
			else
				local src = readScriptSource(instance)
				properties.SourceLength = #src
				properties.LineCount = #(Utils.splitLines(src))
			end
			if instance:IsA("BaseScript") then
				properties.Enabled = tostring(instance.Enabled)
			end
		end
		if instance:IsA("Part") then
			properties.Shape = tostring(instance.Shape)
		end
		if instance:IsA("BasePart") then
			properties.TopSurface = tostring(instance.TopSurface)
			properties.BottomSurface = tostring(instance.BottomSurface)
		end
		if instance:IsA("MeshPart") then
			properties.MeshId = tostring(instance.MeshId)
			properties.TextureID = tostring(instance.TextureID)
		end
		if instance:IsA("SpecialMesh") then
			properties.MeshId = tostring(instance.MeshId)
			properties.TextureId = tostring(instance.TextureId)
			properties.MeshType = tostring(instance.MeshType)
		end
		if instance:IsA("Sound") then
			properties.SoundId = tostring(instance.SoundId)
			properties.TimeLength = tostring(instance.TimeLength)
			properties.IsPlaying = tostring(instance.IsPlaying)
		end
		if instance:IsA("Animation") then
			properties.AnimationId = tostring(instance.AnimationId)
		end
		if instance:IsA("Decal") or instance:IsA("Texture") then
			properties.Texture = tostring(instance.Texture)
		end
		if instance:IsA("Shirt") then
			properties.ShirtTemplate = tostring(instance.ShirtTemplate)
		elseif instance:IsA("Pants") then
			properties.PantsTemplate = tostring(instance.PantsTemplate)
		elseif instance:IsA("ShirtGraphic") then
			properties.Graphic = tostring(instance.Graphic)
		end
		properties.ChildCount = tostring(#instance:GetChildren())
	end)
	if success then
		return {
			instancePath = instancePath,
			className = instance.ClassName,
			properties = properties,
		}
	else
		return {
			error = `Failed to get properties: {result}`,
		}
	end
end
local function searchByProperty(requestData)
	local propertyName = requestData.propertyName
	local propertyValue = requestData.propertyValue
	if not (propertyName ~= "" and propertyName) or not (propertyValue ~= "" and propertyValue) then
		return {
			error = "Property name and value are required",
		}
	end
	local results = {}
	local function searchRecursive(instance)
		local success, value = pcall(function()
			return tostring(instance[propertyName])
		end)
		local condition = success
		if condition then
			local exp = string.lower(value)
			local arg0 = string.lower(propertyValue)
			condition = (string.find(exp, arg0)) ~= nil
		end
		if condition then
			local arg0 = {
				name = instance.Name,
				className = instance.ClassName,
				path = getInstancePath(instance),
				propertyValue = value,
			}
			table.insert(results, arg0)
		end
		for _, child in instance:GetChildren() do
			searchRecursive(child)
		end
	end
	searchRecursive(game)
	return {
		propertyName = propertyName,
		propertyValue = propertyValue,
		results = results,
		count = #results,
	}
end
local function getClassInfo(requestData)
	local className = requestData.className
	if not (className ~= "" and className) then
		return {
			error = "Class name is required",
		}
	end
	local success, tempInstance = pcall(function()
		return Instance.new(className)
	end)
	local isService = false
	if not success then
		local serviceSuccess, serviceInstance = pcall(function()
			return game:GetService(className)
		end)
		if serviceSuccess and serviceInstance then
			success = true
			tempInstance = serviceInstance
			isService = true
		end
	end
	if not success then
		return {
			error = `Invalid class name: {className}`,
		}
	end
	local classInfo = {
		className = className,
		isService = isService,
		properties = {},
		methods = {},
		events = {},
	}
	local commonProps = {
		"Name",
		"ClassName",
		"Parent",
		"Size",
		"Position",
		"Rotation",
		"CFrame",
		"Anchored",
		"CanCollide",
		"Transparency",
		"BrickColor",
		"Material",
		"Color",
		"Text",
		"TextColor3",
		"BackgroundColor3",
		"Image",
		"ImageColor3",
		"Visible",
		"Active",
		"ZIndex",
		"BorderSizePixel",
		"BackgroundTransparency",
		"ImageTransparency",
		"TextTransparency",
		"Value",
		"Enabled",
		"Brightness",
		"Range",
		"Shadows",
	}
	for _, prop in commonProps do
		local propSuccess = pcall(function()
			return tempInstance[prop]
		end)
		if propSuccess then
			table.insert(classInfo.properties, prop)
		end
	end
	local commonMethods = {
		"Destroy",
		"Clone",
		"FindFirstChild",
		"FindFirstChildOfClass",
		"GetChildren",
		"IsA",
		"IsAncestorOf",
		"IsDescendantOf",
		"WaitForChild",
	}
	for _, method in commonMethods do
		local methodSuccess = pcall(function()
			return tempInstance[method]
		end)
		if methodSuccess then
			table.insert(classInfo.methods, method)
		end
	end
	if not isService then
		tempInstance:Destroy()
	end
	return classInfo
end
local function getProjectStructure(requestData)
	local condition = requestData.path
	if condition == nil then
		condition = ""
	end
	local startPath = condition
	local condition_1 = requestData.maxDepth
	if condition_1 == nil then
		condition_1 = 3
	end
	local maxDepth = condition_1
	local condition_2 = requestData.scriptsOnly
	if condition_2 == nil then
		condition_2 = false
	end
	local showScriptsOnly = condition_2
	if startPath == "" or startPath == "game" then
		local services = {}
		local mainServices = {
			"Workspace",
			"ServerScriptService",
			"ServerStorage",
			"ReplicatedStorage",
			"StarterGui",
			"StarterPack",
			"StarterPlayer",
			"Players",
		}
		for _, serviceName in mainServices do
			local svcOk, service = pcall(function()
				return game:GetService(serviceName)
			end)
			if svcOk and service then
				local arg0 = {
					name = service.Name,
					className = service.ClassName,
					path = getInstancePath(service),
					childCount = #service:GetChildren(),
					hasChildren = #service:GetChildren() > 0,
				}
				table.insert(services, arg0)
			end
		end
		return {
			type = "service_overview",
			services = services,
			timestamp = tick(),
			note = "Use path parameter to explore specific locations (e.g., 'game.ServerScriptService')",
		}
	end
	local startInstance = getInstanceByPath(startPath)
	if not startInstance then
		return {
			error = `Path not found: {startPath}`,
		}
	end
	local function getStructure(instance, depth)
		if depth > maxDepth then
			return {
				name = instance.Name,
				className = instance.ClassName,
				path = getInstancePath(instance),
				childCount = #instance:GetChildren(),
				hasMore = true,
				note = "Max depth reached - use this path to explore further",
			}
		end
		local node = {
			name = instance.Name,
			className = instance.ClassName,
			path = getInstancePath(instance),
		}
		if instance:IsA("LuaSourceContainer") then
			node.hasSource = true
			node.scriptType = instance.ClassName
			if instance:IsA("BaseScript") then
				node.enabled = instance.Enabled
			end
		end
		if instance:IsA("GuiObject") then
			node.visible = instance.Visible
			if instance:IsA("Frame") or instance:IsA("ScreenGui") then
				node.guiType = "container"
			elseif instance:IsA("TextLabel") or instance:IsA("TextButton") then
				node.guiType = "text"
				local textInst = instance
				if textInst.Text ~= "" then
					node.text = textInst.Text
				end
			elseif instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
				node.guiType = "image"
			end
		end
		local children = instance:GetChildren()
		if showScriptsOnly then
			children = {}
			for _, child in children do
				if child:IsA("BaseScript") or child:IsA("Folder") or child:IsA("ModuleScript") then
					table.insert(children, child)
				end
			end
		end
		local nodeChildren = {}
		local childCount = #children
		if childCount > 20 and depth < maxDepth then
			local classGroups = {}
			for _, child in children do
				local cn = child.ClassName
				if not (classGroups[cn] ~= nil) then
					classGroups[cn] = {}
				end
				table.insert(classGroups[cn], child)
			end
			local childSummary = {}
			for cn, classChildren in classGroups do
				local first, second = classChildren[1], classChildren[2]
				table.insert(childSummary, {
					className = cn,
					count = #classChildren,
					examples = { if first then first.Name else nil, if second then second.Name else nil },
				})
			end
			node.childSummary = childSummary
			for cn, classChildren in classGroups do
				for i = 1, math.min(3, #classChildren) do
					table.insert(nodeChildren, getStructure(classChildren[i], depth + 1))
				end
				if #classChildren > 3 then
					table.insert(nodeChildren, {
						name = `... {#classChildren - 3} more {cn} objects`,
						className = "MoreIndicator",
						path = `{getInstancePath(instance)} [{cn} children]`,
						note = "Use specific path to explore these objects",
					})
				end
			end
		else
			for _, child in children do
				local arg0 = getStructure(child, depth + 1)
				table.insert(nodeChildren, arg0)
			end
		end
		if #nodeChildren > 0 then
			node.children = nodeChildren
		end
		return node
	end
	local result = getStructure(startInstance, 0)
	result.requestedPath = startPath
	result.maxDepth = maxDepth
	result.scriptsOnly = showScriptsOnly
	result.timestamp = tick()
	return result
end
local scriptSearch = ScriptSearch.createScriptSearch({
	resolveRoot = function(self, path)
		return getInstanceByPath(path)
	end,
	getChildren = function(self, instance)
		return instance:GetChildren()
	end,
	readScript = function(self, instance, classFilter)
		if not instance:IsA("LuaSourceContainer") or (classFilter ~= nil and instance.ClassName ~= classFilter) then
			return nil
		end
		local snapshot = {
			instancePath = getInstancePath(instance),
			name = instance.Name,
			className = instance.ClassName,
			source = readScriptSource(instance),
		}
		if instance:IsA("BaseScript") then
			snapshot.enabled = instance.Enabled
		end
		return snapshot
	end,
})
local function grepScripts(requestData, execution)
	local result = CooperativeJobRunner.runExclusive("script-source-search", execution, function(control)
		return scriptSearch.search(requestData, control)
	end)
	if result.error == "plugin_busy" then
		local object = table.clone(result)
		setmetatable(object, nil)
		object.message =
			"Another grep_scripts request is already running in this Studio DataModel. Retry after it completes."
		return object
	end
	if result.error == "deadline_exceeded" then
		local object = table.clone(result)
		setmetatable(object, nil)
		object.message = "grep_scripts exceeded its bridge deadline before the scan completed."
		return object
	end
	return result
end
return {
	getFileTree = getFileTree,
	searchFiles = searchFiles,
	getPlaceInfo = getPlaceInfo,
	searchObjects = searchObjects,
	getInstanceProperties = getInstanceProperties,
	searchByProperty = searchByProperty,
	getClassInfo = getClassInfo,
	getProjectStructure = getProjectStructure,
	grepScripts = grepScripts,
}
