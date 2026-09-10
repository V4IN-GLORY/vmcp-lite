local Utils = require(script.Parent.Parent.Utils)
local Recording = require(script.Parent.Parent.Recording)
local binding = Utils
local getInstancePath = binding.getInstancePath
local getInstanceByPath = binding.getInstanceByPath
local readScriptSource = binding.readScriptSource
local applyScriptSource = binding.applyScriptSource
local splitLines = binding.splitLines
local joinLines = binding.joinLines
local binding_1 = Recording
local beginRecording = binding_1.beginRecording
local finishRecording = binding_1.finishRecording
local SOURCE_TRUNCATE_CHAR_BUDGET = 25000
local SOURCE_TRUNCATE_LINE_BUDGET = 400
local SOURCE_TRUNCATE_TO_LINES = 300
local function getTopServiceName(instance)
	local topServiceInst = instance
	while topServiceInst.Parent and topServiceInst.Parent ~= game do
		topServiceInst = topServiceInst.Parent
	end
	return topServiceInst.Name
end
local function sliceLines(lines, startLine, endLine)
	local selectedLines = {}
	for i = startLine, endLine do
		local condition = lines[i]
		if condition == nil then
			condition = ""
		end
		table.insert(selectedLines, condition)
	end
	return selectedLines
end
local function numberLines(lines, lineOffset)
	local numberedLines = {}
	for i = 0, #lines - 1 do
		table.insert(numberedLines, `{i + lineOffset}: {lines[i + 1]}`)
	end
	return table.concat(numberedLines, "\n")
end
local function getScriptSource(requestData)
	local instancePath = requestData.instancePath
	local startLine = requestData.startLine
	local endLine = requestData.endLine
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
	if not instance:IsA("LuaSourceContainer") then
		return {
			error = `Instance is not a script-like object: {instance.ClassName}`,
		}
	end
	local success, result = pcall(function()
		local fullSource = readScriptSource(instance)
		local lines, hasTrailingNewline = splitLines(fullSource)
		local totalLineCount = #lines
		local explicitRange = startLine ~= nil or endLine ~= nil
		local shouldTruncate = not explicitRange
			and (#fullSource > SOURCE_TRUNCATE_CHAR_BUDGET or totalLineCount > SOURCE_TRUNCATE_LINE_BUDGET)
		local _result
		if explicitRange then
			_result = math.max(1, if startLine ~= nil then startLine else 1)
		else
			_result = 1
		end
		local returnedStartLine = _result
		local _result_1
		if shouldTruncate then
			_result_1 = math.min(SOURCE_TRUNCATE_TO_LINES, totalLineCount)
		else
			local _result_2
			if explicitRange then
				_result_2 = math.min(totalLineCount, if endLine ~= nil then endLine else totalLineCount)
			else
				_result_2 = totalLineCount
			end
			_result_1 = _result_2
		end
		local returnedEndLine = _result_1
		local selectedLines = if (explicitRange or shouldTruncate)
			then sliceLines(lines, returnedStartLine, returnedEndLine)
			else lines
		local sourceToReturn = if explicitRange
			then joinLines(selectedLines, hasTrailingNewline and returnedEndLine == totalLineCount)
			elseif shouldTruncate then table.concat(selectedLines, "\n")
			else fullSource
		local resp = {
			instancePath = instancePath,
			className = instance.ClassName,
			name = instance.Name,
			source = sourceToReturn,
			numberedSource = numberLines(selectedLines, returnedStartLine),
			sourceLength = #fullSource,
			lineCount = totalLineCount,
			startLine = returnedStartLine,
			endLine = returnedEndLine,
			isPartial = explicitRange,
			truncated = shouldTruncate,
		}
		if shouldTruncate then
			resp.note =
				`Script truncated to first {returnedEndLine} of {totalLineCount} lines ({#fullSource} chars). Use line_range to read specific sections.`
		end
		if instance:IsA("BaseScript") then
			resp.enabled = instance.Enabled
		end
		resp.topService = getTopServiceName(instance)
		return resp
	end)
	if success then
		return result
	else
		return {
			error = `Failed to get script source: {result}`,
		}
	end
end
local function setScriptSource(requestData)
	local instancePath = requestData.instancePath
	local newSource = requestData.source
	if not (instancePath ~= "" and instancePath) or not (type(newSource) == "string") then
		return {
			error = "Instance path and source are required",
		}
	end
	local instance = getInstanceByPath(instancePath)
	if not instance then
		return {
			error = `Instance not found: {instancePath}`,
		}
	end
	if not instance:IsA("LuaSourceContainer") then
		return {
			error = `Instance is not a script-like object: {instance.ClassName}`,
		}
	end
	-- Communication has already JSON-decoded the transport payload; source text is exact at this boundary.
	local sourceToSet = newSource
	local recordingId = beginRecording(`Set script source: {instance.Name}`)
	local readSuccess, readResult = pcall(function()
		return #readScriptSource(instance)
	end)
	if not readSuccess then
		finishRecording(recordingId, false)
		return {
			error = `Failed to read script source before updating: {readResult}`,
		}
	end
	local oldSourceLength = readResult
	local applyResult = applyScriptSource(instance, sourceToSet)
	if applyResult.success then
		finishRecording(recordingId, true)
		return {
			success = true,
			instancePath = instancePath,
			oldSourceLength = oldSourceLength,
			newSourceLength = #sourceToSet,
			method = applyResult.method,
			message = `Script source updated successfully ({if applyResult.method == "UpdateSourceAsync"
				then "editor-safe"
				else "direct assignment"})`,
		}
	end
	finishRecording(recordingId, false)
	return {
		error = `Failed to set script source: {applyResult.error}`,
	}
end
local function editScriptLines(requestData)
	local instancePath = requestData.instancePath
	local oldString = requestData.old_string
	local newString = requestData.new_string
	local startLine = requestData.startLine
	if not (instancePath ~= "" and instancePath) or oldString == nil or newString == nil then
		return {
			error = "Instance path, old_string, and new_string are required",
		}
	end
	local instance = getInstanceByPath(instancePath)
	if not instance then
		return {
			error = `Instance not found: {instancePath}`,
		}
	end
	if not instance:IsA("LuaSourceContainer") then
		return {
			error = `Instance is not a script-like object: {instance.ClassName}`,
		}
	end
	local recordingId = beginRecording(`Edit script: {instance.Name}`)
	local success, result = pcall(function()
		local source = readScriptSource(instance)
		local searchLen = #oldString
		local matchStart
		if startLine ~= nil then
			if startLine < 1 then
				error(`startLine must be >= 1 (got {startLine})`)
			end
			local lineStartByte = 1
			local currentLine = 1
			while currentLine < startLine do
				local nlPos = string.find(source, "\n", lineStartByte, true)
				if nlPos == nil then
					error(`startLine {startLine} is past end of script ({currentLine} lines)`)
				end
				lineStartByte = nlPos + 1
				currentLine += 1
			end
			local candidate = string.sub(source, lineStartByte, lineStartByte + searchLen - 1)
			if candidate ~= oldString then
				error(
					`old_string does not match at line {startLine}. Use get_script_source to verify the exact text at that line.`
				)
			end
			matchStart = lineStartByte
		else
			local count = 0
			local searchPos = 1
			local firstMatch
			while true do
				local foundStart = string.find(source, oldString, searchPos, true)
				if foundStart == nil then
					break
				end
				if firstMatch == nil then
					firstMatch = foundStart
				end
				count += 1
				if count > 1 then
					break
				end
				searchPos = foundStart + searchLen
			end
			if count == 0 then
				error(
					"old_string not found in script. If old_string contains repeated patterns (e.g. closing braces), pass startLine to anchor the edit."
				)
			end
			if count > 1 then
				error(
					"old_string matches multiple locations. Provide more surrounding context, or pass startLine to anchor the edit to a specific line."
				)
			end
			matchStart = firstMatch
		end
		-- Byte-slice replacement avoids Lua pattern escaping (safe for multi-byte chars like em dashes).
		local newSource = string.sub(source, 1, matchStart - 1)
			.. newString
			.. string.sub(source, matchStart + searchLen)
		local applyResult = applyScriptSource(instance, newSource, source)
		if not applyResult.success then
			error(applyResult.error)
		end
		return {
			success = true,
			instancePath = instancePath,
			method = applyResult.method,
			message = "Script edited successfully",
		}
	end)
	if success then
		finishRecording(recordingId, true)
		return result
	end
	finishRecording(recordingId, false)
	return {
		error = `Failed to edit script: {result}`,
	}
end
local function insertScriptLines(requestData)
	local instancePath = requestData.instancePath
	local condition = requestData.afterLine
	if condition == nil then
		condition = 0
	end
	local afterLine = condition
	local newContent = requestData.newContent
	if not (instancePath ~= "" and instancePath) or not (newContent ~= "" and newContent) then
		return {
			error = "Instance path and newContent are required",
		}
	end
	local instance = getInstanceByPath(instancePath)
	if not instance then
		return {
			error = `Instance not found: {instancePath}`,
		}
	end
	if not instance:IsA("LuaSourceContainer") then
		return {
			error = `Instance is not a script-like object: {instance.ClassName}`,
		}
	end
	local recordingId = beginRecording(`Insert script lines after line {afterLine}: {instance.Name}`)
	local success, result = pcall(function()
		local source = readScriptSource(instance)
		local lines, hadTrailingNewline = splitLines(source)
		local totalLines = #lines
		if afterLine < 0 or afterLine > totalLines then
			error(`afterLine out of range (0-{totalLines})`)
		end
		local newLines = splitLines(newContent)
		local resultLines = {}
		for i = 0, afterLine - 1 do
			table.insert(resultLines, lines[i + 1])
		end
		for _, line in newLines do
			table.insert(resultLines, line)
		end
		for i = afterLine, totalLines - 1 do
			table.insert(resultLines, lines[i + 1])
		end
		local newSource = joinLines(resultLines, hadTrailingNewline)
		local applyResult = applyScriptSource(instance, newSource, source)
		if not applyResult.success then
			error(applyResult.error)
		end
		return {
			success = true,
			instancePath = instancePath,
			insertedAfterLine = afterLine,
			linesInserted = #newLines,
			newLineCount = #resultLines,
			method = applyResult.method,
			message = "Script lines inserted successfully",
		}
	end)
	if success then
		finishRecording(recordingId, true)
		return result
	end
	finishRecording(recordingId, false)
	return {
		error = `Failed to insert script lines: {result}`,
	}
end
local function deleteScriptLines(requestData)
	local instancePath = requestData.instancePath
	local startLine = requestData.startLine
	local endLine = requestData.endLine
	if
		not (instancePath ~= "" and instancePath)
		or not (startLine ~= 0 and startLine == startLine and startLine)
		or not (endLine ~= 0 and endLine == endLine and endLine)
	then
		return {
			error = "Instance path, startLine, and endLine are required",
		}
	end
	local instance = getInstanceByPath(instancePath)
	if not instance then
		return {
			error = `Instance not found: {instancePath}`,
		}
	end
	if not instance:IsA("LuaSourceContainer") then
		return {
			error = `Instance is not a script-like object: {instance.ClassName}`,
		}
	end
	local recordingId = beginRecording(`Delete script lines {startLine}-{endLine}: {instance.Name}`)
	local success, result = pcall(function()
		local source = readScriptSource(instance)
		local lines, hadTrailingNewline = splitLines(source)
		local totalLines = #lines
		if startLine < 1 or startLine > totalLines then
			error(`startLine out of range (1-{totalLines})`)
		end
		if endLine < startLine or endLine > totalLines then
			error(`endLine out of range ({startLine}-{totalLines})`)
		end
		local resultLines = {}
		for i = 0, startLine - 1 - 1 do
			table.insert(resultLines, lines[i + 1])
		end
		for i = endLine, totalLines - 1 do
			table.insert(resultLines, lines[i + 1])
		end
		local newSource = joinLines(resultLines, hadTrailingNewline)
		local applyResult = applyScriptSource(instance, newSource, source)
		if not applyResult.success then
			error(applyResult.error)
		end
		return {
			success = true,
			instancePath = instancePath,
			deletedLines = {
				startLine = startLine,
				endLine = endLine,
			},
			linesDeleted = endLine - startLine + 1,
			newLineCount = #resultLines,
			method = applyResult.method,
			message = "Script lines deleted successfully",
		}
	end)
	if success then
		finishRecording(recordingId, true)
		return result
	end
	finishRecording(recordingId, false)
	return {
		error = `Failed to delete script lines: {result}`,
	}
end
local function escapeLuaPattern(s)
	return (string.gsub(s, "([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
end
local function escapeLuaReplacement(s)
	return (string.gsub(s, "%%", "%%%%"))
end
local function caseInsensitiveLiteralReplace(src, searchStr, repl)
	local lowerSrc = string.lower(src)
	local lowerSearch = string.lower(searchStr)
	local parts = {}
	local lastEnd = 1
	local searchLen = #lowerSearch
	local pos = 1
	local replCount = 0
	while true do
		local foundStart = string.find(lowerSrc, lowerSearch, pos, true)
		if foundStart == nil then
			break
		end
		local arg0 = string.sub(src, lastEnd, foundStart - 1)
		table.insert(parts, arg0)
		table.insert(parts, repl)
		lastEnd = foundStart + searchLen
		pos = foundStart + searchLen
		replCount += 1
	end
	local arg0 = string.sub(src, lastEnd)
	table.insert(parts, arg0)
	return { table.concat(parts, ""), replCount }
end
local function findAndReplaceInScripts(requestData)
	local searchPattern = requestData.pattern
	local replacement = requestData.replacement
	if not (searchPattern ~= "" and searchPattern) then
		return {
			error = "pattern is required",
		}
	end
	if replacement == nil then
		return {
			error = "replacement is required",
		}
	end
	local condition = requestData.caseSensitive
	if condition == nil then
		condition = false
	end
	local caseSensitive = condition
	local condition_1 = requestData.usePattern
	if condition_1 == nil then
		condition_1 = false
	end
	local usePattern = condition_1
	local condition_2 = requestData.path
	if condition_2 == nil then
		condition_2 = ""
	end
	local searchPath = condition_2
	local classFilter = requestData.classFilter
	local condition_3 = requestData.dryRun
	if condition_3 == nil then
		condition_3 = false
	end
	local dryRun = condition_3
	local condition_4 = requestData.maxReplacements
	if condition_4 == nil then
		condition_4 = 1000
	end
	local maxReplacements = condition_4
	if not caseSensitive and usePattern then
		return {
			error = "Case-insensitive Lua pattern replacement is not supported. Use caseSensitive: true with usePattern: true, or use literal matching.",
		}
	end
	local startInstance = if searchPath ~= "" then getInstanceByPath(searchPath) else game
	if not startInstance then
		return {
			error = `Path not found: {searchPath}`,
		}
	end
	local changes = {}
	local totalReplacements = 0
	local scriptsSearched = 0
	local hitLimit = false
	local recordingId = if dryRun then nil else beginRecording("Find and replace in scripts")
	local function processInstance(instance)
		if hitLimit then
			return nil
		end
		local condition_5 = classFilter == nil
		if not condition_5 then
			local exp = string.lower(instance.ClassName)
			local arg0 = string.lower(classFilter)
			condition_5 = (string.find(exp, arg0)) ~= nil
		end
		local matchesClass = condition_5
		if instance:IsA("LuaSourceContainer") and matchesClass then
			scriptsSearched += 1
			local source = readScriptSource(instance)
			local newSource
			local replCount
			if usePattern then
				local result, count = string.gsub(source, searchPattern, replacement)
				newSource = result
				replCount = count
			elseif caseSensitive then
				local escaped = escapeLuaPattern(searchPattern)
				local escapedRepl = escapeLuaReplacement(replacement)
				local result, count = string.gsub(source, escaped, escapedRepl)
				newSource = result
				replCount = count
			else
				local binding_2 = caseInsensitiveLiteralReplace(source, searchPattern, replacement)
				newSource = binding_2[1]
				replCount = binding_2[2]
			end
			if replCount > 0 then
				if totalReplacements + replCount > maxReplacements then
					hitLimit = true
					return nil
				end
				local applyResult = if dryRun then nil else applyScriptSource(instance, newSource, source)
				if applyResult ~= nil and not applyResult.success then
					local object = {
						instancePath = getInstancePath(instance),
						name = instance.Name,
						className = instance.ClassName,
						replacements = 0,
					}
					object.error = if applyResult.error ~= nil
						then applyResult.error
						else "Script write failed verification"
					table.insert(changes, object)
				else
					totalReplacements += replCount
					local arg0 = {
						instancePath = getInstancePath(instance),
						name = instance.Name,
						className = instance.ClassName,
						replacements = replCount,
					}
					table.insert(changes, arg0)
				end
			end
		end
		for _, child in instance:GetChildren() do
			if hitLimit then
				return nil
			end
			processInstance(child)
		end
	end
	local traversalSuccess, traversalResult = pcall(function()
		return processInstance(startInstance)
	end)
	local newValue = {}
	for _, change in changes do
		if change.error ~= nil then
			table.insert(newValue, change)
		end
	end
	local failedScripts = #newValue
	local scriptsModified = #changes - failedScripts
	if recordingId ~= nil then
		finishRecording(recordingId, scriptsModified > 0)
	end
	return {
		success = traversalSuccess and failedScripts == 0,
		error = if traversalSuccess then nil else `Script traversal failed: {traversalResult}`,
		dryRun = dryRun,
		pattern = searchPattern,
		replacement = replacement,
		totalReplacements = totalReplacements,
		scriptsSearched = scriptsSearched,
		scriptsModified = scriptsModified,
		scriptsFailed = failedScripts,
		changes = changes,
		truncated = hitLimit,
	}
end
return {
	getScriptSource = getScriptSource,
	setScriptSource = setScriptSource,
	editScriptLines = editScriptLines,
	insertScriptLines = insertScriptLines,
	deleteScriptLines = deleteScriptLines,
	findAndReplaceInScripts = findAndReplaceInScripts,
}
