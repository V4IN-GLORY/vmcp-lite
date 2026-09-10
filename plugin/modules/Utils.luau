local ScriptEditorService = game:GetService("ScriptEditorService")
local LUAU_KEYWORDS = {
	["and"] = true,
	["break"] = true,
	["continue"] = true,
	["do"] = true,
	["else"] = true,
	["elseif"] = true,
	["end"] = true,
	["export"] = true,
	["false"] = true,
	["for"] = true,
	["function"] = true,
	["if"] = true,
	["in"] = true,
	["local"] = true,
	["nil"] = true,
	["not"] = true,
	["or"] = true,
	["repeat"] = true,
	["return"] = true,
	["then"] = true,
	["true"] = true,
	["type"] = true,
	["until"] = true,
	["while"] = true,
}
local function safeCall(func, ...)
	local args = { ... }
	local success, result = pcall(func, unpack(args))
	if success then
		return result
	else
		warn(`MCP Plugin Error: {result}`)
		return nil
	end
end
local function isSimplePathSegment(segment)
	return (string.match(segment, "^[%a_][%w_]*$")) ~= nil and not (LUAU_KEYWORDS[segment] ~= nil)
end
local function quotePathSegment(segment)
	local escaped = (string.gsub(segment, "\\", "\\\\"))
	escaped = (string.gsub(escaped, "\n", "\\n"))
	escaped = (string.gsub(escaped, "\r", "\\r"))
	escaped = (string.gsub(escaped, "\t", "\\t"))
	escaped = (string.gsub(escaped, '"', '\\"'))
	return `"{escaped}"`
end
local function unescapePathSegment(segment)
	local chars = {}
	local i = 1
	while i <= #segment do
		local ch = string.sub(segment, i, i)
		if ch == "\\" and i < #segment then
			local nextChar = string.sub(segment, i + 1, i + 1)
			if nextChar == "n" then
				table.insert(chars, "\n")
			elseif nextChar == "r" then
				table.insert(chars, "\r")
			elseif nextChar == "t" then
				table.insert(chars, "\t")
			else
				table.insert(chars, nextChar)
			end
			i += 2
		else
			table.insert(chars, ch)
			i += 1
		end
	end
	return table.concat(chars, "")
end
local function isCanonicalBracketStart(path, index)
	local quote = string.sub(path, index + 1, index + 1)
	return (quote == '"' or quote == "'") and string.sub(path, index - 1, index - 1) ~= "."
end
local function parseInstancePath(path)
	local i = 1
	local len = #path
	local parts = {}
	local current = ""
	if path == "" or path == "game" then
		return parts
	end
	if string.sub(path, 1, 5) == "game." then
		i = 6
	elseif string.sub(path, 1, 5) == "game[" then
		i = 5
	end
	while i <= len do
		local ch = string.sub(path, i, i)
		if ch == "." then
			if current ~= "" then
				table.insert(parts, current)
				current = ""
				i += 1
			else
				local condition = i > 1
				if condition then
					condition = string.sub(path, i - 1, i - 1) == "."
					if condition then
						condition = i < len
						if condition then
							condition = string.sub(path, i + 1, i + 1) ~= "["
						end
					end
				end
				if condition then
					-- Back-compat for previously emitted paths such as
					-- game.ServerScriptService..dir.ReproScript, where ".dir"
					-- was an actual instance name.
					current = "."
					i += 1
				else
					i += 1
				end
			end
		elseif ch == "[" and i < len and isCanonicalBracketStart(path, i) then
			if current ~= "" then
				table.insert(parts, current)
				current = ""
			end
			local quote = string.sub(path, i + 1, i + 1)
			if quote ~= '"' and quote ~= "'" then
				return nil
			end
			local j = i + 2
			local raw = ""
			while j <= len do
				local c = string.sub(path, j, j)
				if c == "\\" then
					if j >= len then
						return nil
					end
					raw ..= c .. string.sub(path, j + 1, j + 1)
					j += 2
				elseif c == quote then
					break
				else
					raw ..= c
					j += 1
				end
			end
			local condition = j > len
			if not condition then
				condition = string.sub(path, j, j) ~= quote
				if not condition then
					condition = string.sub(path, j + 1, j + 1) ~= "]"
				end
			end
			if condition then
				return nil
			end
			local arg0_1 = unescapePathSegment(raw)
			table.insert(parts, arg0_1)
			i = j + 2
		else
			current ..= ch
			i += 1
		end
	end
	if current ~= "" then
		table.insert(parts, current)
	end
	return parts
end
local function getRootSegment(instance)
	if instance.Parent == game then
		local ok, service = pcall(function()
			return game:GetService(instance.ClassName)
		end)
		if ok and service == instance then
			return instance.ClassName
		end
	end
	return instance.Name
end
local function getInstancePath(instance)
	if not instance or instance == game then
		return "game"
	end
	local pathParts = {}
	local current = instance
	while current and current ~= game do
		local arg0 = getRootSegment(current)
		table.insert(pathParts, 1, arg0)
		current = current.Parent
	end
	local path = "game"
	for _, part in pathParts do
		if isSimplePathSegment(part) then
			path ..= `.{part}`
		else
			path ..= `[{quotePathSegment(part)}]`
		end
	end
	return path
end
local function getRootInstance(segment)
	local ok, service = pcall(function()
		return game:GetService(segment)
	end)
	if ok and service then
		return service
	end
	return game:FindFirstChild(segment)
end
local function getInstanceByPath(path)
	local parts = parseInstancePath(path)
	if parts == nil then
		return nil
	end
	if #parts == 0 then
		return game
	end
	local current = getRootInstance(parts[1])
	for i = 1, #parts - 1 do
		local part = parts[i + 1]
		if not current then
			return nil
		end
		current = current:FindFirstChild(part)
	end
	return current
end
local function splitLines(source)
	local normalized = (string.gsub((string.gsub(if source ~= nil then source else "", "\r\n", "\n")), "\r", "\n"))
	local endsWithNewline = string.sub(normalized, -1) == "\n"
	local lines = string.split(normalized, "\n")
	-- split() includes a final empty field for a trailing newline. Keep the
	-- existing splitLines contract, which tracks that newline separately.
	if endsWithNewline and lines[#lines] == "" then
		lines[#lines] = nil
	end
	if #lines == 0 then
		table.insert(lines, "")
	end
	return lines, endsWithNewline
end
local function joinLines(lines, hadTrailingNewline)
	local source = table.concat(lines, "\n")
	if hadTrailingNewline and string.sub(source, -1) ~= "\n" then
		source ..= "\n"
	end
	return source
end
local function readScriptSource(instance)
	local editorOk, editorSource = pcall(function()
		return ScriptEditorService:GetEditorSource(instance)
	end)
	if editorOk then
		return editorSource
	end
	local documentOk, documentSource = pcall(function()
		local doc = ScriptEditorService:FindScriptDocument(instance)
		if doc then
			return doc:GetText()
		end
		return nil
	end)
	if documentOk and documentSource ~= nil then
		return documentSource
	end
	-- @rbxts/types does not expose PluginSecurity Source reads.
	local readableScript = instance
	return readableScript.Source
end
--[[
	*
	 * Writes newSource to instance and verifies the live editor text before
	 * reporting success. expectedSource turns line-based edits into a
	 * compare-and-set operation: if the document changes while
	 * UpdateSourceAsync yields or before the direct fallback runs, the write is
	 * rejected instead of overwriting the newer draft.
	 
]]
local function applyScriptSource(instance, newSource, expectedSource)
	local updateSuccess, updateResult = pcall(function()
		ScriptEditorService:UpdateSourceAsync(instance, function(currentSource)
			if expectedSource ~= nil and currentSource ~= expectedSource then
				error("Script source changed while the edit was being applied; read the script again and retry")
			end
			return newSource
		end)
		if readScriptSource(instance) ~= newSource then
			error("UpdateSourceAsync completed without updating the live script source")
		end
	end)
	if updateSuccess then
		return {
			success = true,
			method = "UpdateSourceAsync",
		}
	end
	local directSuccess, directResult = pcall(function()
		if expectedSource ~= nil and readScriptSource(instance) ~= expectedSource then
			error("Script source changed before direct assignment; read the script again and retry")
		end
		-- @rbxts/types does not expose PluginSecurity Source writes.
		local writableScript = instance
		writableScript.Source = newSource
		if readScriptSource(instance) ~= newSource then
			error("Direct assignment completed without updating the live script source")
		end
	end)
	if directSuccess then
		return {
			success = true,
			method = "direct",
		}
	end
	return {
		success = false,
		method = "direct",
		error = `UpdateSourceAsync failed: {updateResult}. Direct assignment failed: {directResult}`,
	}
end
local function convertPropertyValue(instance, propertyName, propertyValue)
	if propertyValue == nil then
		return nil
	end
	local inst = instance
	if type(propertyValue) == "table" then
		local arr = propertyValue
		local tbl = propertyValue
		if type(arr) == "table" and #arr > 0 then
			local len = #arr
			if len == 3 then
				local prop = string.lower(propertyName)
				if
					prop == "position"
					or prop == "size"
					or prop == "orientation"
					or prop == "velocity"
					or prop == "angularvelocity"
				then
					local condition = arr[1]
					if condition == nil then
						condition = 0
					end
					local condition_1 = arr[2]
					if condition_1 == nil then
						condition_1 = 0
					end
					local condition_2 = arr[3]
					if condition_2 == nil then
						condition_2 = 0
					end
					return Vector3.new(condition, condition_1, condition_2)
				elseif prop == "color" or prop == "color3" then
					local condition = arr[1]
					if condition == nil then
						condition = 0
					end
					local condition_1 = arr[2]
					if condition_1 == nil then
						condition_1 = 0
					end
					local condition_2 = arr[3]
					if condition_2 == nil then
						condition_2 = 0
					end
					return Color3.new(condition, condition_1, condition_2)
				else
					local success, currentVal = pcall(function()
						return inst[propertyName]
					end)
					if success then
						if typeof(currentVal) == "Vector3" then
							local condition = arr[1]
							if condition == nil then
								condition = 0
							end
							local condition_1 = arr[2]
							if condition_1 == nil then
								condition_1 = 0
							end
							local condition_2 = arr[3]
							if condition_2 == nil then
								condition_2 = 0
							end
							return Vector3.new(condition, condition_1, condition_2)
						elseif typeof(currentVal) == "Color3" then
							local condition = arr[1]
							if condition == nil then
								condition = 0
							end
							local condition_1 = arr[2]
							if condition_1 == nil then
								condition_1 = 0
							end
							local condition_2 = arr[3]
							if condition_2 == nil then
								condition_2 = 0
							end
							return Color3.new(condition, condition_1, condition_2)
						end
					end
				end
			elseif len == 2 then
				local success, currentVal = pcall(function()
					return inst[propertyName]
				end)
				if success and typeof(currentVal) == "Vector2" then
					local condition = arr[1]
					if condition == nil then
						condition = 0
					end
					local condition_1 = arr[2]
					if condition_1 == nil then
						condition_1 = 0
					end
					return Vector2.new(condition, condition_1)
				end
			elseif len == 4 then
				local success, currentVal = pcall(function()
					return inst[propertyName]
				end)
				if success and typeof(currentVal) == "UDim2" then
					local condition = arr[1]
					if condition == nil then
						condition = 0
					end
					local condition_1 = arr[2]
					if condition_1 == nil then
						condition_1 = 0
					end
					local condition_2 = arr[3]
					if condition_2 == nil then
						condition_2 = 0
					end
					local condition_3 = arr[4]
					if condition_3 == nil then
						condition_3 = 0
					end
					return UDim2.new(condition, condition_1, condition_2, condition_3)
				end
			end
		end
		if tbl.X ~= nil or tbl.Y ~= nil or tbl.Z ~= nil then
			if type(tbl.X) == "table" and type(tbl.Y) == "table" then
				local xTbl = tbl.X
				local yTbl = tbl.Y
				return UDim2.new(
					if xTbl.Scale ~= nil then xTbl.Scale else 0,
					if xTbl.Offset ~= nil then xTbl.Offset else 0,
					if yTbl.Scale ~= nil then yTbl.Scale else 0,
					if yTbl.Offset ~= nil then yTbl.Offset else 0
				)
			end
			local success, currentVal = pcall(function()
				return inst[propertyName]
			end)
			if success then
				local currentType = typeof(currentVal)
				if currentType == "Vector2" then
					local condition_1 = tbl.X
					if condition_1 == nil then
						condition_1 = 0
					end
					local condition_2 = tbl.Y
					if condition_2 == nil then
						condition_2 = 0
					end
					return Vector2.new(condition_1, condition_2)
				end
				if currentType == "Vector3" then
					local condition_1 = tbl.X
					if condition_1 == nil then
						condition_1 = 0
					end
					local condition_2 = tbl.Y
					if condition_2 == nil then
						condition_2 = 0
					end
					local condition_3 = tbl.Z
					if condition_3 == nil then
						condition_3 = 0
					end
					return Vector3.new(condition_1, condition_2, condition_3)
				end
			end
			local condition_1 = tbl.X
			if condition_1 == nil then
				condition_1 = 0
			end
			local condition_2 = tbl.Y
			if condition_2 == nil then
				condition_2 = 0
			end
			local condition_3 = tbl.Z
			if condition_3 == nil then
				condition_3 = 0
			end
			return Vector3.new(condition_1, condition_2, condition_3)
		end
		if tbl.R ~= nil or tbl.G ~= nil or tbl.B ~= nil then
			local condition = tbl.R
			if condition == nil then
				condition = 0
			end
			local condition_1 = tbl.G
			if condition_1 == nil then
				condition_1 = 0
			end
			local condition_2 = tbl.B
			if condition_2 == nil then
				condition_2 = 0
			end
			return Color3.new(condition, condition_1, condition_2)
		end
	end
	if type(propertyValue) == "string" then
		local success, currentVal = pcall(function()
			return inst[propertyName]
		end)
		if success and typeof(currentVal) == "EnumItem" then
			local enumItem = currentVal
			local enumTypeName = tostring(enumItem.EnumType)
			local enumSuccess, enumVal = pcall(function()
				return Enum[enumTypeName][propertyValue]
			end)
			if enumSuccess and enumVal then
				return enumVal
			end
		end
		if propertyName == "BrickColor" then
			return BrickColor.new(propertyValue)
		end
		if propertyValue == "true" then
			return true
		end
		if propertyValue == "false" then
			return false
		end
	end
	return propertyValue
end
local function evaluateFormula(formula, variables, instance, index)
	local value = formula
	local arg1 = tostring(index)
	value = (string.gsub(value, "index", arg1))
	if instance and instance:IsA("BasePart") then
		local pos = instance.Position
		local sz = instance.Size
		local arg1_1 = tostring(pos.X)
		value = (string.gsub(value, "Position%.X", arg1_1))
		local arg1_2 = tostring(pos.Y)
		value = (string.gsub(value, "Position%.Y", arg1_2))
		local arg1_3 = tostring(pos.Z)
		value = (string.gsub(value, "Position%.Z", arg1_3))
		local arg1_4 = tostring(sz.X)
		value = (string.gsub(value, "Size%.X", arg1_4))
		local arg1_5 = tostring(sz.Y)
		value = (string.gsub(value, "Size%.Y", arg1_5))
		local arg1_6 = tostring(sz.Z)
		value = (string.gsub(value, "Size%.Z", arg1_6))
		local arg1_7 = tostring(pos.Magnitude)
		value = (string.gsub(value, "magnitude", arg1_7))
	end
	if variables then
		for k, v in pairs(variables) do
			local arg1_1 = tostring(v)
			value = (string.gsub(value, k, arg1_1))
		end
	end
	value = (
		string.gsub(value, "sin%(([%d%.%-]+)%)", function(x)
			local condition = tonumber(x)
			if condition == nil then
				condition = 0
			end
			return tostring(math.sin(condition))
		end)
	)
	value = (
		string.gsub(value, "cos%(([%d%.%-]+)%)", function(x)
			local condition = tonumber(x)
			if condition == nil then
				condition = 0
			end
			return tostring(math.cos(condition))
		end)
	)
	value = (
		string.gsub(value, "sqrt%(([%d%.%-]+)%)", function(x)
			local condition = tonumber(x)
			if condition == nil then
				condition = 0
			end
			return tostring(math.sqrt(condition))
		end)
	)
	value = (
		string.gsub(value, "abs%(([%d%.%-]+)%)", function(x)
			local condition = tonumber(x)
			if condition == nil then
				condition = 0
			end
			return tostring(math.abs(condition))
		end)
	)
	value = (
		string.gsub(value, "floor%(([%d%.%-]+)%)", function(x)
			local condition = tonumber(x)
			if condition == nil then
				condition = 0
			end
			return tostring(math.floor(condition))
		end)
	)
	value = (
		string.gsub(value, "ceil%(([%d%.%-]+)%)", function(x)
			local condition = tonumber(x)
			if condition == nil then
				condition = 0
			end
			return tostring(math.ceil(condition))
		end)
	)
	local directResult = tonumber(value)
	if directResult ~= nil then
		return directResult, nil
	end
	local success, evalResult = pcall(function()
		local num = tonumber(value)
		if num ~= nil then
			return num
		end
		do
			local a, b = string.match(value, "^([%d%.%-]+)%s*%*%s*([%d%.%-]+)$")
			local condition = a
			if condition ~= "" and condition then
				condition = b
			end
			if condition ~= "" and condition then
				local condition_1 = tonumber(a)
				if condition_1 == nil then
					condition_1 = 0
				end
				local condition_2 = tonumber(b)
				if condition_2 == nil then
					condition_2 = 0
				end
				return condition_1 * condition_2
			end
		end
		do
			local a, b = string.match(value, "^([%d%.%-]+)%s*%+%s*([%d%.%-]+)$")
			local condition = a
			if condition ~= "" and condition then
				condition = b
			end
			if condition ~= "" and condition then
				local condition_1 = tonumber(a)
				if condition_1 == nil then
					condition_1 = 0
				end
				local condition_2 = tonumber(b)
				if condition_2 == nil then
					condition_2 = 0
				end
				return condition_1 + condition_2
			end
		end
		do
			local a, b = string.match(value, "^([%d%.%-]+)%s*%-%s*([%d%.%-]+)$")
			local condition = a
			if condition ~= "" and condition then
				condition = b
			end
			if condition ~= "" and condition then
				local condition_1 = tonumber(a)
				if condition_1 == nil then
					condition_1 = 0
				end
				local condition_2 = tonumber(b)
				if condition_2 == nil then
					condition_2 = 0
				end
				return condition_1 - condition_2
			end
		end
		do
			local a, b = string.match(value, "^([%d%.%-]+)%s*/%s*([%d%.%-]+)$")
			local condition = a
			if condition ~= "" and condition then
				condition = b
			end
			if condition ~= "" and condition then
				local condition_1 = tonumber(b)
				if condition_1 == nil then
					condition_1 = 1
				end
				local divisor = condition_1
				if divisor ~= 0 then
					local condition_2 = tonumber(a)
					if condition_2 == nil then
						condition_2 = 0
					end
					return condition_2 / divisor
				end
			end
		end
		error(`Unsupported formula pattern: {value}`)
	end)
	if success and type(evalResult) == "number" then
		return evalResult, nil
	else
		return index, "Complex formulas not supported - using index value"
	end
end
local function compareVersions(v1, v2)
	local function parseVersion(v)
		local parts = {}
		for num in string.gmatch(v, "%d+") do
			local condition = tonumber(num)
			if condition == nil then
				condition = 0
			end
			table.insert(parts, condition)
		end
		return parts
	end
	local p1 = parseVersion(v1)
	local p2 = parseVersion(v2)
	local maxLen = math.max(#p1, #p2)
	do
		local i = 0
		local shouldIncrement = false
		while true do
			if shouldIncrement then
				i += 1
			else
				shouldIncrement = true
			end
			if not (i < maxLen) then
				break
			end
			local condition = p1[i + 1]
			if condition == nil then
				condition = 0
			end
			local n1 = condition
			local condition_1 = p2[i + 1]
			if condition_1 == nil then
				condition_1 = 0
			end
			local n2 = condition_1
			if n1 < n2 then
				return -1
			end
			if n1 > n2 then
				return 1
			end
		end
	end
	return 0
end
return {
	safeCall = safeCall,
	getInstancePath = getInstancePath,
	getInstanceByPath = getInstanceByPath,
	splitLines = splitLines,
	joinLines = joinLines,
	readScriptSource = readScriptSource,
	applyScriptSource = applyScriptSource,
	convertPropertyValue = convertPropertyValue,
	evaluateFormula = evaluateFormula,
	compareVersions = compareVersions,
}
