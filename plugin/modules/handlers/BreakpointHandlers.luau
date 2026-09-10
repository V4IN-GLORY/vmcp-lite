local Utils = require(script.Parent.Parent.Utils)
local PeerRole = require(script.Parent.Parent.PeerRole)
local getInstanceByPath = Utils.getInstanceByPath
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local LOG_PREFIX = "Breakpoint"
local REGISTRY_KEY_PREFIX = "MCP_BREAKPOINTS_V1_"
local MCP_PLACE_ID_ATTRIBUTE = "__MCPPlaceId"
local pluginRef
local loadedRegistryKey
local loadedRegistryFromSettings = false
local breakpoints = {}
local function init(p)
	pluginRef = p
end
local function breakpointKey(scriptPath, line)
	return `{scriptPath}:{line}`
end
local function computePlaceKey()
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
local function detectRole()
	return PeerRole.detect()
end
local function requestedRole(requestData)
	local condition = type(requestData.__mcp_target_role) == "string" and requestData.__mcp_target_role ~= ""
	return if condition then requestData.__mcp_target_role else detectRole()
end
local function registryScope(requestData)
	local placeKey = computePlaceKey()
	local role = requestedRole(requestData)
	return {
		key = `{REGISTRY_KEY_PREFIX}{placeKey}:{role}`,
	}
end
local function readSetting(key)
	if not pluginRef then
		return nil
	end
	local ok, value = pcall(function()
		return pluginRef:GetSetting(key)
	end)
	return if ok then value else nil
end
local function writeSetting(key, value)
	if not pluginRef then
		return false
	end
	local ok = pcall(function()
		return pluginRef:SetSetting(key, value)
	end)
	return ok
end
local function decodePersistedBreakpointEntry(value)
	if not (type(value) == "table") then
		return nil
	end
	local data = value
	if not (type(data.script_path) == "string") or data.script_path == "" then
		return nil
	end
	if not (type(data.line) == "number") or data.line < 1 then
		return nil
	end
	return {
		script_path = data.script_path,
		line = math.floor(data.line),
	}
end
local function loadRegistry(requestData)
	local scope = registryScope(requestData)
	if loadedRegistryKey ~= scope.key then
		table.clear(breakpoints)
		loadedRegistryKey = scope.key
		loadedRegistryFromSettings = false
	end
	if loadedRegistryFromSettings then
		return scope
	end
	loadedRegistryFromSettings = true
	local stored = readSetting(scope.key)
	if stored == nil then
		return scope
	end
	local decoded = stored
	if type(stored) == "string" then
		local ok, result = pcall(function()
			return HttpService:JSONDecode(stored)
		end)
		if not ok then
			return scope
		end
		decoded = result
	end
	if not (type(decoded) == "table") then
		return scope
	end
	table.clear(breakpoints)
	for _, item in decoded do
		local entry = decodePersistedBreakpointEntry(item)
		if entry then
			local arg0 = breakpointKey(entry.script_path, entry.line)
			breakpoints[arg0] = entry
		end
	end
	return scope
end
local function persistRegistry(scope)
	if not pluginRef then
		return {
			ok = false,
			error = "Plugin settings are unavailable; managed breakpoint registry is memory-only.",
		}
	end
	local out = {}
	for _, entry in breakpoints do
		local arg0 = {
			script_path = entry.script_path,
			line = entry.line,
		}
		table.insert(out, arg0)
	end
	local encodedOk, encoded = pcall(function()
		return HttpService:JSONEncode(out)
	end)
	if not encodedOk or not (type(encoded) == "string") then
		return {
			ok = false,
			error = `Failed to encode managed breakpoint registry: {tostring(encoded)}`,
		}
	end
	if not writeSetting(scope.key, encoded) then
		return {
			ok = false,
			error = "Failed to persist managed breakpoint registry with plugin:SetSetting.",
		}
	end
	local stored = readSetting(scope.key)
	if stored ~= encoded then
		return {
			ok = false,
			error = "Failed to verify managed breakpoint registry persistence after plugin:SetSetting.",
		}
	end
	return {
		ok = true,
	}
end
local function attachPersistenceWarning(response, persist)
	if not persist.ok then
		response.managed_registry_persisted = false
		response.registry_error = persist.error
	end
	return response
end
local function serviceError(message)
	local object = {
		error = "script_debugger_unavailable",
	}
	object.message = if message ~= nil
		then message
		else "ScriptDebuggerService is unavailable. Enable the Studio Debugger Luau API beta feature and restart Studio."
	object.betaFeatureRequired = true
	return object
end
local function operationError(errorCode, operation, raw)
	return {
		error = errorCode,
		message = `{operation} failed. The breakpoints tool requires the Studio Debugger Luau API beta feature. `
			.. "Enable it in Studio Beta Features and restart/reload Studio, then retry.",
		rawMessage = tostring(raw),
		betaFeatureRequired = true,
	}
end
local function getService()
	local provider = game
	local ok, service = pcall(function()
		return provider:GetService("ScriptDebuggerService")
	end)
	if not ok or not service then
		return serviceError(`ScriptDebuggerService unavailable: {tostring(service)}`)
	end
	return service
end
local function luauStringLiteral(value)
	local escaped = (string.gsub(value, "\\", "\\\\"))
	escaped = (string.gsub(escaped, "\n", "\\n"))
	escaped = (string.gsub(escaped, "\r", "\\r"))
	escaped = (string.gsub(escaped, "\t", "\\t"))
	escaped = (string.gsub(escaped, '"', '\\"'))
	return `"{escaped}"`
end
local function buildLogMessage(scriptPath, line, logMessage)
	local prefix = { luauStringLiteral(LOG_PREFIX), luauStringLiteral(`{scriptPath}:{line}`) }
	if type(logMessage) == "string" and logMessage ~= "" then
		table.insert(prefix, logMessage)
	end
	return table.concat(prefix, ", ")
end
local function listBreakpoints(requestData)
	loadRegistry(requestData)
	local out = {}
	for _, entry in breakpoints do
		table.insert(out, entry)
	end
	return {
		breakpoints = out,
		count = #out,
	}
end
local function setBreakpoint(requestData)
	local scope = loadRegistry(requestData)
	local serviceOrError = getService()
	local value = serviceOrError.IsA
	if not (value ~= 0 and value == value and value ~= "" and value) then
		return serviceOrError
	end
	local service = serviceOrError
	local scriptPath = requestData.script_path
	local lineRaw = requestData.line
	if not (type(scriptPath) == "string") or scriptPath == "" or not (type(lineRaw) == "number") then
		return {
			error = "invalid_args",
			message = "breakpoints action=set requires script_path and line",
		}
	end
	local requestedLine = math.floor(lineRaw)
	if requestedLine < 1 then
		return {
			error = "invalid_line",
			message = "line must be a 1-based positive number",
		}
	end
	local instance = getInstanceByPath(scriptPath)
	if not instance then
		return {
			error = "script_not_found",
			script_path = scriptPath,
		}
	end
	if not instance:IsA("LuaSourceContainer") then
		return {
			error = "not_a_script",
			message = `{scriptPath} is {instance.ClassName}, not a LuaSourceContainer`,
			script_path = scriptPath,
		}
	end
	local rawLogMessage = if type(requestData.log_message) == "string" then requestData.log_message else nil
	local hasLogMessage = rawLogMessage ~= nil and rawLogMessage ~= ""
	local continueExecution = if type(requestData.continue_execution) == "boolean"
		then requestData.continue_execution
		else hasLogMessage
	local enabled = if type(requestData.enabled) == "boolean" then requestData.enabled else true
	local effectiveLogMessage = if hasLogMessage or continueExecution
		then buildLogMessage(scriptPath, requestedLine, rawLogMessage)
		else nil
	local spec = {
		Line = requestedLine,
		Enabled = enabled,
		ContinueExecution = continueExecution,
	}
	if type(requestData.condition) == "string" and requestData.condition ~= "" then
		spec.Condition = requestData.condition
	end
	if effectiveLogMessage ~= nil then
		spec.LogMessage = effectiveLogMessage
	end
	local ok, result = pcall(function()
		return service:AddBreakpoint(instance, spec)
	end)
	if not ok then
		return operationError("add_breakpoint_failed", "ScriptDebuggerService:AddBreakpoint", result)
	end
	local breakpointResult = result
	local actualLine = if type(breakpointResult.Line) == "number" then breakpointResult.Line else requestedLine
	local verified = if type(breakpointResult.Verified) == "boolean" then breakpointResult.Verified else nil
	local message = if type(breakpointResult.Message) == "string" then breakpointResult.Message else nil
	local entry = {
		script_path = scriptPath,
		line = actualLine,
		requested_line = if actualLine ~= requestedLine then requestedLine else nil,
		enabled = enabled,
		condition = spec.Condition,
		log_message = rawLogMessage,
		continue_execution = continueExecution,
		verified = if verified == false then false else nil,
		message = message,
		created_at = DateTime.now().UnixTimestampMillis,
	}
	local arg0 = breakpointKey(scriptPath, actualLine)
	breakpoints[arg0] = entry
	return attachPersistenceWarning({
		ok = true,
		breakpoint = entry,
	}, persistRegistry(scope))
end
local function removeBreakpoint(requestData)
	local scope = loadRegistry(requestData)
	local serviceOrError = getService()
	local value = serviceOrError.IsA
	if not (value ~= 0 and value == value and value ~= "" and value) then
		return serviceOrError
	end
	local service = serviceOrError
	local scriptPath = requestData.script_path
	local lineRaw = requestData.line
	if not (type(scriptPath) == "string") or scriptPath == "" or not (type(lineRaw) == "number") then
		return {
			error = "invalid_args",
			message = "breakpoints action=remove requires script_path and line",
		}
	end
	local line = math.floor(lineRaw)
	if line < 1 then
		return {
			error = "invalid_line",
			message = "line must be a 1-based positive number",
		}
	end
	local instance = getInstanceByPath(scriptPath)
	if not instance then
		return {
			error = "script_not_found",
			script_path = scriptPath,
		}
	end
	if not instance:IsA("LuaSourceContainer") then
		return {
			error = "not_a_script",
			message = `{scriptPath} is {instance.ClassName}, not a LuaSourceContainer`,
			script_path = scriptPath,
		}
	end
	local ok, removed = pcall(function()
		return service:RemoveBreakpoint(instance, line)
	end)
	if not ok then
		return operationError("remove_breakpoint_failed", "ScriptDebuggerService:RemoveBreakpoint", removed)
	end
	local arg0 = breakpointKey(scriptPath, line)
	breakpoints[arg0] = nil
	return attachPersistenceWarning({
		ok = true,
		removed = removed,
		script_path = scriptPath,
		line = line,
	}, persistRegistry(scope))
end
local function clearManagedBreakpoints(requestData)
	local scope = loadRegistry(requestData)
	local serviceOrError = getService()
	local value = serviceOrError.IsA
	if not (value ~= 0 and value == value and value ~= "" and value) then
		return serviceOrError
	end
	local service = serviceOrError
	local cleared = 0
	local errors = {}
	for key, entry in breakpoints do
		local instance = getInstanceByPath(entry.script_path)
		if not instance or not instance:IsA("LuaSourceContainer") then
			breakpoints[key] = nil
			cleared += 1
			continue
		end
		local ok, removedOrError = pcall(function()
			return service:RemoveBreakpoint(instance, entry.line)
		end)
		if ok then
			breakpoints[key] = nil
			cleared += 1
		else
			local arg0 = {
				script_path = entry.script_path,
				line = entry.line,
				error = tostring(removedOrError),
			}
			table.insert(errors, arg0)
		end
	end
	if #errors > 0 then
		return {
			ok = false,
			cleared = cleared,
			errors = errors,
		}
	end
	return attachPersistenceWarning({
		ok = true,
		cleared = cleared,
	}, persistRegistry(scope))
end
local function clearAllBreakpoints(requestData)
	local scope = loadRegistry(requestData)
	local serviceOrError = getService()
	local value = serviceOrError.IsA
	if not (value ~= 0 and value == value and value ~= "" and value) then
		return serviceOrError
	end
	local service = serviceOrError
	local _size = Utils.countKeys(breakpoints)
	local managedCount = _size
	local ok, err = pcall(function()
		return service:ClearBreakpoints()
	end)
	if not ok then
		return operationError("clear_breakpoints_failed", "ScriptDebuggerService:ClearBreakpoints", err)
	end
	table.clear(breakpoints)
	return attachPersistenceWarning({
		ok = true,
		cleared_managed = managedCount,
	}, persistRegistry(scope))
end
local function clearBreakpoints(requestData)
	if requestData.clear_all == true then
		return clearAllBreakpoints(requestData)
	end
	return clearManagedBreakpoints(requestData)
end
local function breakpointsTool(requestData)
	local action = requestData.action
	if not (type(action) == "string") or action == "" then
		return {
			error = "invalid_args",
			message = "breakpoints requires action=set|remove|clear|list",
		}
	end
	repeat
		if action == "set" then
			return setBreakpoint(requestData)
		end
		if action == "remove" then
			return removeBreakpoint(requestData)
		end
		if action == "clear" then
			return clearBreakpoints(requestData)
		end
		if action == "list" then
			return listBreakpoints(requestData)
		end
		return {
			error = "unknown_action",
			message = `breakpoints action must be one of: set, remove, clear, list (got {action})`,
		}
	until true
end
return {
	breakpoints = breakpointsTool,
	init = init,
}
