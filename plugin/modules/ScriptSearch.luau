local function splitLuaAlternation(pattern)
	local parts = {}
	local current = ""
	local index = 1
	local inCharacterClass = false
	while index <= #pattern do
		local character = string.sub(pattern, index, index)
		if character == "%" then
			if string.sub(pattern, index + 1, index + 1) == "b" then
				current ..= string.sub(pattern, index, math.min(index + 3, #pattern))
				index += 4
			else
				current ..= string.sub(pattern, index, index + 1)
				index += 2
			end
		elseif character == "[" then
			inCharacterClass = true
			current ..= character
			index += 1
		elseif character == "]" then
			inCharacterClass = false
			current ..= character
			index += 1
		elseif character == "|" and not inCharacterClass then
			table.insert(parts, current)
			current = ""
			index += 1
		else
			current ..= character
			index += 1
		end
	end
	table.insert(parts, current)
	return parts
end
local function findFirstPattern(line, alternatives, control)
	local earliest
	for _, alternative in alternatives do
		control:checkpoint()
		if alternative == "" then
			continue
		end
		local start = string.find(line, alternative)
		if start ~= nil and (earliest == nil or start < earliest) then
			earliest = start
		end
	end
	return earliest
end
local function readLine(source, start)
	local boundary = string.find(source, "[\r\n]", start)
	if boundary == nil then
		return { string.sub(source, start), nil }
	end
	local nextStart = boundary + 1
	if string.sub(source, boundary, boundary) == "\r" and string.sub(source, nextStart, nextStart) == "\n" then
		nextStart += 1
	end
	return { string.sub(source, start, boundary - 1), if nextStart <= #source then nextStart else nil }
end
local MAX_RESULTS = 10_000
local LITERAL_CHUNK_BYTES = 64 * 1024
local MAX_PATTERN_BYTES = 4096
local MAX_CONTEXT_LINES = 100
local function sourceCanMatchLiteral(source, pattern, caseSensitive, control)
	if #source == 0 then
		return false
	end
	local overlapBytes = math.max(#pattern - 1, 0)
	local chunkStart = 1
	while chunkStart <= #source do
		control:checkpoint()
		local chunkEnd = math.min(#source, chunkStart + LITERAL_CHUNK_BYTES + overlapBytes - 1)
		local chunk = string.sub(source, chunkStart, chunkEnd)
		local candidate = if caseSensitive then chunk else string.lower(chunk)
		if (string.find(candidate, pattern, 1, true)) ~= nil then
			return true
		end
		if chunkEnd >= #source then
			return false
		end
		chunkStart += LITERAL_CHUNK_BYTES
	end
	return false
end
local function createScriptSearch(corpus)
	local function search(requestData, control)
		local requestedPattern = requestData.pattern
		if not (type(requestedPattern) == "string") or requestedPattern == "" then
			return {
				error = "pattern is required",
			}
		end
		if #requestedPattern > MAX_PATTERN_BYTES then
			return {
				error = "invalid_request",
				message = `pattern must contain between 1 and {MAX_PATTERN_BYTES} bytes`,
			}
		end
		local pattern = requestedPattern
		for _, optionName in { "usePattern", "caseSensitive", "filesOnly" } do
			local option = requestData[optionName]
			if option ~= nil and not (type(option) == "boolean") then
				return {
					error = "invalid_request",
					message = `{optionName} must be a boolean`,
				}
			end
		end
		local condition = requestData.usePattern
		if condition == nil then
			condition = false
		end
		local usePattern = condition
		if usePattern and requestData.caseSensitive == false then
			return {
				error = "Case-insensitive Lua pattern search is not supported.",
			}
		end
		local _result
		if usePattern then
			_result = true
		else
			local condition_1 = requestData.caseSensitive
			if condition_1 == nil then
				condition_1 = false
			end
			_result = condition_1
		end
		local caseSensitive = _result
		local condition_1 = requestData.filesOnly
		if condition_1 == nil then
			condition_1 = false
		end
		local filesOnly = condition_1
		local requestedContextLines = requestData.contextLines
		if
			requestedContextLines ~= nil
			and (
				not (type(requestedContextLines) == "number")
				or math.floor(requestedContextLines) ~= requestedContextLines
				or requestedContextLines < 0
				or requestedContextLines > MAX_CONTEXT_LINES
			)
		then
			return {
				error = "invalid_request",
				message = `contextLines must be an integer between 0 and {MAX_CONTEXT_LINES}`,
			}
		end
		local contextLines = if requestedContextLines ~= nil then requestedContextLines else 0
		local requestedMaxResults = requestData.maxResults
		if
			requestedMaxResults ~= nil
			and (
				not (type(requestedMaxResults) == "number")
				or math.floor(requestedMaxResults) ~= requestedMaxResults
				or requestedMaxResults < 1
				or requestedMaxResults > MAX_RESULTS
			)
		then
			return {
				error = "invalid_request",
				message = `maxResults must be an integer between 1 and {MAX_RESULTS}`,
			}
		end
		local maxResults = if requestedMaxResults ~= nil then requestedMaxResults else 100
		local requestedMaxResultsPerScript = requestData.maxResultsPerScript
		if
			requestedMaxResultsPerScript ~= nil
			and (
				not (type(requestedMaxResultsPerScript) == "number")
				or math.floor(requestedMaxResultsPerScript) ~= requestedMaxResultsPerScript
				or requestedMaxResultsPerScript < 0
				or requestedMaxResultsPerScript > MAX_RESULTS
			)
		then
			return {
				error = "invalid_request",
				message = `maxResultsPerScript must be an integer between 0 and {MAX_RESULTS}`,
			}
		end
		local maxResultsPerScript = if requestedMaxResultsPerScript ~= nil then requestedMaxResultsPerScript else 0
		local classFilter = requestData.classFilter
		local condition_5 = requestData.path
		if condition_5 == nil then
			condition_5 = ""
		end
		local searchPath = condition_5
		local root = corpus:resolveRoot(searchPath)
		if root == nil then
			return {
				error = `Path not found: {searchPath}`,
			}
		end
		local searchPattern = if caseSensitive then pattern else string.lower(pattern)
		local patternAlternatives = if usePattern then splitLuaAlternation(searchPattern) else nil
		local results = {}
		local stack = { root }
		local totalMatches = 0
		local scriptsSearched = 0
		local hitLimit = false
		while #stack > 0 and not hitLimit do
			control:checkpoint()
			-- ▼ Array.pop ▼
			local length = #stack
			local result_1 = stack[length]
			stack[length] = nil
			-- ▲ Array.pop ▲
			local instance = result_1
			local snapshot = corpus:readScript(instance, classFilter)
			if snapshot ~= nil and (classFilter == nil or snapshot.className == classFilter) then
				scriptsSearched += 1
				local scriptMatches = {}
				local before = {}
				local pendingAfter = {}
				local scriptMatchCount = 0
				local lineNumber = 1
				local lineStart = 1
				local canMatch = usePattern
					or sourceCanMatchLiteral(snapshot.source, searchPattern, caseSensitive, control)
				if canMatch then
					while lineStart ~= nil and not hitLimit do
						control:checkpoint()
						local binding = readLine(snapshot.source, lineStart)
						local line = binding[1]
						local nextLineStart = binding[2]
						for _, pending in pendingAfter do
							if pending.remaining > 0 then
								table.insert(pending.match.after, line)
								pending.remaining -= 1
							end
						end
						while #pendingAfter > 0 and pendingAfter[1].remaining == 0 do
							table.remove(pendingAfter, 1)
						end
						local candidate = if caseSensitive then line else string.lower(line)
						local matchStart = if usePattern
							then findFirstPattern(candidate, patternAlternatives, control)
							else (string.find(candidate, searchPattern, 1, true))
						if
							matchStart ~= nil and (maxResultsPerScript == 0 or scriptMatchCount < maxResultsPerScript)
						then
							scriptMatchCount += 1
							totalMatches += 1
							if totalMatches > maxResults then
								hitLimit = true
								break
							end
							if not filesOnly then
								local object = {
									line = lineNumber,
									column = matchStart,
									text = line,
								}
								local array = {}
								table.move(before, 1, #before, #array + 1, array)
								object.before = array
								object.after = {}
								local lineMatch = object
								table.insert(scriptMatches, lineMatch)
								if contextLines > 0 then
									local arg0 = {
										match = lineMatch,
										remaining = contextLines,
									}
									table.insert(pendingAfter, arg0)
								end
							end
						end
						if
							maxResultsPerScript > 0
							and scriptMatchCount >= maxResultsPerScript
							and #pendingAfter == 0
						then
							break
						end
						if contextLines > 0 then
							table.insert(before, line)
							while #before > contextLines do
								table.remove(before, 1)
							end
						end
						lineStart = nextLineStart
						if nextLineStart == nil then
							break
						end
						lineNumber += 1
					end
				end
				if scriptMatchCount > 0 then
					local scriptResult = {
						instancePath = snapshot.instancePath,
						name = snapshot.name,
						className = snapshot.className,
						matches = scriptMatches,
					}
					if snapshot.enabled ~= nil then
						scriptResult.enabled = snapshot.enabled
					end
					table.insert(results, scriptResult)
				end
			end
			local children = {}
			for _, child in corpus:getChildren(instance) do
				table.insert(children, child)
			end
			for index = #children - 1, 0, -1 do
				table.insert(stack, children[index + 1])
			end
		end
		return {
			results = results,
			pattern = pattern,
			totalMatches = if hitLimit then `>{maxResults}` else totalMatches,
			scriptsSearched = scriptsSearched,
			scriptsMatched = #results,
			truncated = hitLimit,
			options = {
				caseSensitive = caseSensitive,
				contextLines = contextLines,
				usePattern = usePattern,
				filesOnly = filesOnly,
				maxResults = maxResults,
				maxResultsPerScript = maxResultsPerScript,
			},
		}
	end
	return {
		search = search,
	}
end
return {
	createScriptSearch = createScriptSearch,
}
