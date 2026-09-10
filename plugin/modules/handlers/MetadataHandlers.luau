local Utils = require(script.Parent.Parent.Utils)
local LuauExec = require(script.Parent.Parent.LuauExec)
local Selection = game:GetService("Selection")
local binding = Utils
local getInstancePath = binding.getInstancePath
local getInstanceByPath = binding.getInstanceByPath
local function serializeValue(value)
	local vType = typeof(value)
	if vType == "Vector3" then
		local v = value
		return {
			X = v.X,
			Y = v.Y,
			Z = v.Z,
			_type = "Vector3",
		}
	elseif vType == "Color3" then
		local v = value
		return {
			R = v.R,
			G = v.G,
			B = v.B,
			_type = "Color3",
		}
	elseif vType == "CFrame" then
		local v = value
		return {
			Position = {
				X = v.Position.X,
				Y = v.Position.Y,
				Z = v.Position.Z,
			},
			_type = "CFrame",
		}
	elseif vType == "UDim2" then
		local v = value
		return {
			X = {
				Scale = v.X.Scale,
				Offset = v.X.Offset,
			},
			Y = {
				Scale = v.Y.Scale,
				Offset = v.Y.Offset,
			},
			_type = "UDim2",
		}
	elseif vType == "BrickColor" then
		local v = value
		return {
			Name = v.Name,
			_type = "BrickColor",
		}
	end
	return value
end
local function getAttributes(requestData)
	local instancePath = requestData.instancePath
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
	local success, result = pcall(function()
		local attributes = instance:GetAttributes()
		local serializedAttributes = {}
		local count = 0
		for name, value in attributes do
			serializedAttributes[name] = {
				value = serializeValue(value),
				type = typeof(value),
			}
			count += 1
		end
		local response = {
			instancePath = instancePath,
			count = count,
		}
		if count > 0 then
			response.attributes = serializedAttributes
		end
		return response
	end)
	if success then
		return result
	end
	return {
		error = `Failed to get attributes: {result}`,
	}
end
local function getSelection(_requestData)
	local selection = Selection:Get()
	if #selection == 0 then
		return {
			success = true,
			selection = {},
			count = 0,
			message = "No objects selected",
		}
	end
	local selectedObjects = table.create(#selection)
	for i, instance in selection do
		selectedObjects[i] = {
			name = instance.Name,
			className = instance.ClassName,
			path = getInstancePath(instance),
			parent = if instance.Parent then getInstancePath(instance.Parent) else nil,
		}
	end
	return {
		success = true,
		selection = selectedObjects,
		count = #selection,
		message = `{#selection} object(s) selected`,
	}
end
-- The counterpart to getSelection: this sets it. Selecting what the agent just
-- built shows the user the result and puts the instance under Studio's own
-- move/scale handles, which is why it is a tool and not left to execute_luau.
local function setSelection(requestData)
	local rawPaths = requestData.paths
	if not (type(rawPaths) == "table") then
		return {
			error = "paths is required (an empty array clears in set mode)",
		}
	end
	local condition = requestData.mode
	if condition == nil then
		condition = "set"
	end
	local mode = condition
	if mode ~= "set" and mode ~= "add" and mode ~= "remove" then
		return {
			error = `mode must be "set", "add" or "remove" (got: {mode})`,
		}
	end
	local paths = rawPaths
	if #paths == 0 and mode ~= "set" then
		return {
			error = `paths cannot be empty in {mode} mode`,
		}
	end
	local targets = {}
	local missing = {}
	for _, entry in paths do
		if not (type(entry) == "string") or entry == "" then
			return {
				error = "paths must contain non-empty instance path strings",
			}
		end
		local instance = getInstanceByPath(entry)
		if instance then
			table.insert(targets, instance)
		else
			table.insert(missing, entry)
		end
	end
	local clearsSelection = mode == "set" and #paths == 0
	if #targets == 0 and not clearsSelection then
		return {
			error = "No matching instances found for any path",
			missingPaths = missing,
		}
	end
	local ok, err = pcall(function()
		if mode == "add" then
			Selection:Add(targets)
		elseif mode == "remove" then
			Selection:Remove(targets)
		else
			Selection:Set(targets)
		end
	end)
	if not ok then
		return {
			error = `Selection.{mode} failed: {tostring(err)}`,
		}
	end
	return {
		success = true,
		mode = mode,
		selected = #targets,
		missingPaths = missing,
		message = if clearsSelection
			then "Selection cleared"
			elseif mode == "remove" then `Deselected {#targets} object(s)`
			else `{#targets} object(s) {if mode == "add" then "added to" else "in"} the selection`,
	}
end
-- Aims the Studio camera at an instance and frames it from a sensible angle.
-- This completes the screenshot loop capture_screenshot documents: build,
-- focus, screenshot. Framing distance comes from the bounding box and the
-- camera's own field of view so any subject fills a similar share of frame.
local function focusViewport(requestData)
	local instancePath = requestData.path
	local instance
	if instancePath == nil then
		local selection = Selection:Get()
		if #selection == 0 then
			return {
				error = "No objects selected. Select a BasePart or Model, or provide path.",
			}
		end
		if #selection ~= 1 then
			return {
				error = "Select exactly one BasePart or Model to frame, or provide path.",
			}
		end
		instance = selection[1]
	else
		if not (type(instancePath) == "string") or instancePath == "" then
			return {
				error = "path must be a non-empty instance path when provided",
			}
		end
		local resolved = getInstanceByPath(instancePath)
		if not resolved then
			return {
				error = `Instance not found: {instancePath}`,
			}
		end
		instance = resolved
	end
	local workspace = game:GetService("Workspace")
	local camera = workspace.CurrentCamera
	if not camera then
		return {
			error = "Workspace.CurrentCamera is unavailable right now",
		}
	end
	local condition = tonumber(requestData.padding)
	if condition == nil then
		condition = 1
	end
	local padding = condition
	if padding <= 0 or padding > 10 then
		return {
			error = "padding must be greater than 0 and at most 10",
		}
	end
	local compassOverride = if requestData.from == nil then nil else tonumber(requestData.from)
	if requestData.from ~= nil and compassOverride == nil then
		return {
			error = "from must be a compass angle in degrees",
		}
	end
	local elevationOverride = if requestData.angleY == nil then nil else tonumber(requestData.angleY)
	if
		requestData.angleY ~= nil and (elevationOverride == nil or elevationOverride < -89 or elevationOverride > 89)
	then
		return {
			error = "angleY must be between -89 and 89",
		}
	end
	local originalCameraType = camera.CameraType
	local ok, err = pcall(function()
		local boundsCF
		local boundsSize
		if instance:IsA("Model") then
			boundsCF, boundsSize = instance:GetBoundingBox()
		elseif instance:IsA("BasePart") then
			boundsCF = instance.CFrame
			boundsSize = instance.Size
		else
			return error(
				`Cannot frame a {instance.ClassName}: it has no 3D bounding box. Frame a part or model instead.`
			)
		end
		local center = boundsCF.Position
		local direction = camera.CFrame.LookVector * -1
		local currentHorizontal = Vector3.new(direction.X, 0, direction.Z)
		local horizontalDirection = if currentHorizontal.Magnitude < 0.001
			then Vector3.new(1, 0, 0)
			else currentHorizontal.Unit
		if compassOverride ~= nil then
			local yaw = math.rad(compassOverride)
			horizontalDirection = Vector3.new(math.cos(yaw), 0, math.sin(yaw))
		end
		local vertical = direction.Y
		local horizontalMagnitude = math.sqrt(math.max(0, 1 - vertical * vertical))
		if elevationOverride ~= nil then
			local pitch = math.rad(elevationOverride)
			vertical = math.sin(pitch)
			horizontalMagnitude = math.cos(pitch)
		end
		local vector3 = Vector3.new(0, vertical, 0)
		direction = (horizontalDirection * horizontalMagnitude + vector3).Unit
		camera.CameraType = Enum.CameraType.Scriptable
		local arg0 = math.max(boundsSize.Magnitude, 1)
		camera.CFrame = CFrame.lookAt(center + (direction * arg0), center)
		camera.Focus = CFrame.new(center)
		camera:ZoomToExtents(boundsCF, boundsSize)
		if padding ~= 1 then
			local fittedOffset = camera.CFrame.Position - center
			camera.CFrame = CFrame.lookAt(center + fittedOffset * padding, center)
		end
		camera.Focus = CFrame.new(center)
	end)
	local restored, restoreError = pcall(function()
		camera.CameraType = originalCameraType
	end)
	if not restored then
		return {
			error = `{if ok then "focus completed" else `focus failed: {tostring(err)}`}; failed to restore camera type: {tostring(
				restoreError
			)}`,
		}
	end
	if not ok then
		return {
			error = `focus failed: {tostring(err)}`,
		}
	end
	return {
		success = true,
		path = getInstancePath(instance),
		cameraPosition = {
			X = camera.CFrame.Position.X,
			Y = camera.CFrame.Position.Y,
			Z = camera.CFrame.Position.Z,
		},
	}
end
local function executeLuau(requestData)
	local code = requestData.code
	if not (code ~= "" and code) or code == "" then
		return {
			error = "Code is required",
		}
	end
	-- All wrapping, print/warn capture, loadstring fallback, JSON-encoding
	-- of table returns, and parse-error recovery live in LuauExec so the
	-- edit/server (this handler) and the play-client (ClientBroker) take
	-- the same code path and produce identical output shapes.
	return LuauExec.execute(code)
end
return {
	getAttributes = getAttributes,
	getSelection = getSelection,
	setSelection = setSelection,
	focusViewport = focusViewport,
	executeLuau = executeLuau,
}
