local Utils = require(script.Parent.Parent.Utils)
local Recording = require(script.Parent.Parent.Recording)
local GenerationService = game:GetService("GenerationService")
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local Selection = game:GetService("Selection")
local getInstancePath = Utils.getInstancePath
local binding_1 = Recording
local beginRecording = binding_1.beginRecording
local finishRecording = binding_1.finishRecording
local OUTPUT_FOLDER_NAME = "__MCPGeneratedModels"
local GENERATE_MODEL_MODERATION_RETRIES = 2
local function fail(message)
	return {
		success = false,
		error = message,
	}
end
local function contentFromAssetId(assetId)
	return Content.fromUri(`rbxassetid://{assetId}`)
end
local function imageToContent(image)
	local payload = image
	local condition = payload.kind ~= "asset"
	if not condition then
		condition = not (type(payload.asset_id) == "number")
		if not condition then
			condition = payload.asset_id <= 0
		end
	end
	if condition then
		error("generate_model image input must be an asset-backed Roblox image ID", 0)
	end
	return contentFromAssetId(math.floor(payload.asset_id))
end
local function outputFolder()
	local existing = ServerStorage:FindFirstChild(OUTPUT_FOLDER_NAME)
	if existing ~= nil then
		if existing:IsA("Folder") then
			return existing
		end
		return `game.ServerStorage.{OUTPUT_FOLDER_NAME} already exists and is not a Folder`
	end
	local folder = Instance.new("Folder")
	folder.Name = OUTPUT_FOLDER_NAME
	folder.Parent = ServerStorage
	return folder
end
local function sanitizeName(value)
	local condition = type(value) == "string" and value ~= ""
	local raw = if condition then value else "GeneratedModel"
	local name = (string.gsub(raw, "[%c]", " "))
	name = (string.gsub((string.gsub(name, "^%s+", "")), "%s+$", ""))
	if name == "" then
		name = "GeneratedModel"
	end
	if #name > 80 then
		name = string.sub(name, 1, 80)
	end
	return name
end
local function uniqueName(parent, baseName)
	if parent:FindFirstChild(baseName) == nil then
		return baseName
	end
	for i = 2, 999 do
		local candidate = `{baseName}_{i}`
		if parent:FindFirstChild(candidate) == nil then
			return candidate
		end
	end
	return `{baseName}_{HttpService:GenerateGUID(false)}`
end
local function buildInputs(requestData)
	local inputs = {}
	local prompt = requestData.prompt
	if type(prompt) == "string" and prompt ~= "" then
		inputs.TextPrompt = prompt
	end
	local image = requestData.image
	if image ~= nil then
		inputs.Image = imageToContent(image)
	end
	local size = requestData.size
	if size ~= nil then
		inputs.Size = Vector3.new(
			if size.x ~= nil then size.x else 1,
			if size.y ~= nil then size.y else 1,
			if size.z ~= nil then size.z else 1
		)
	end
	local maxTriangles = requestData.max_triangles
	if type(maxTriangles) == "number" then
		inputs.MaxTriangles = math.floor(maxTriangles)
	end
	local generateTextures = requestData.generate_textures
	if type(generateTextures) == "boolean" then
		inputs.GenerateTextures = generateTextures
	end
	return inputs
end
local function buildSchema(requestData)
	local schemaGroups = requestData.schema_groups
	if schemaGroups ~= nil then
		return {
			SchemaDefinition = {
				Groups = schemaGroups,
			},
		}
	end
	local condition = type(requestData.schema) == "string" and requestData.schema ~= ""
	local schema = if condition then requestData.schema else "Body1"
	return {
		PredefinedSchema = schema,
	}
end
local function isModerationFailure(value)
	return (string.find(tostring(value), "Moderation failed", 1, true)) ~= nil
end
local function generateModel(requestData)
	local inputOk, inputsOrError = pcall(function()
		return buildInputs(requestData)
	end)
	if not inputOk then
		return fail(`Failed to prepare model input: {tostring(inputsOrError)}`)
	end
	local schema = buildSchema(requestData)
	local recordingId = beginRecording("Generate model")
	local createdModel
	local generateOk = false
	local generateResult
	for attempt = 0, GENERATE_MODEL_MODERATION_RETRIES do
		local ok, result = pcall(function()
			return GenerationService:GenerateModelAsync(inputsOrError, schema, {})
		end)
		generateOk = ok
		generateResult = result
		if ok or not isModerationFailure(result) or attempt == GENERATE_MODEL_MODERATION_RETRIES then
			break
		end
		task.wait(0.25)
	end
	if not generateOk then
		finishRecording(recordingId, false)
		if isModerationFailure(generateResult) then
			return fail("Moderation failed after 3 attempts.")
		end
		return fail(tostring(generateResult))
	end
	if not (typeof(generateResult) == "Instance") or not generateResult:IsA("Model") then
		finishRecording(recordingId, false)
		return fail("GenerationService did not return a Model.")
	end
	createdModel = generateResult
	local folder = outputFolder()
	if type(folder) == "string" then
		createdModel:Destroy()
		finishRecording(recordingId, false)
		return fail(folder)
	end
	createdModel.Name = uniqueName(folder, sanitizeName(requestData.name))
	createdModel.Parent = folder
	pcall(function()
		return Selection:Set({ createdModel })
	end)
	finishRecording(recordingId, true)
	return {
		success = true,
		modelPath = getInstancePath(createdModel),
	}
end
return {
	generateModel = generateModel,
}
