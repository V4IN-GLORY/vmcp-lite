-- eslint-disable 
-- Shared execute_luau machinery for edit/server (MetadataHandlers.executeLuau)
-- and the play-client peer (ClientBroker.handleExecuteLuau). Three things this
-- module owns:
--
--   1. The IIFE wrapper that captures print/warn, wraps require() so nested
--      ModuleScript load failures can recover the real LogService diagnostic,
--      runs user code in xpcall, and always returns { ok, value, output } so
--      the ModuleScript itself always returns exactly one value (otherwise
--      `print("hi")` with no return would fail with "Module code did not
--      return exactly one value").
--
--   2. The loadstring-then-ModuleScript-require fallback, with the parse-error
--      recovery hack that pulls the real diagnostic from LogService.
--
--   3. Return-value formatting: tables get HttpService:JSONEncode'd so the
--      caller sees `{"x":1,"y":2}` instead of `table: 0xaddr`; primitives
--      pass through tostring. The encode is pcall'd so cycles or
--      non-serializable values gracefully fall back to tostring.
--
-- Before this module existed, the client peer used a stripped-down
-- require-only execution path that lacked both the wrapper and the JSON
-- formatting, producing two well-known papercuts:
--   - `print("hi")` (no return) failed with "Module code did not return..."
--   - Returning a table yielded `table: 0xaddr` instead of structured data.
local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")
local PAYLOAD_INSTANCE_NAME = "__MCPExecLuauPayload"
local REQUIRE_GENERIC_ERROR = "Requested module experienced an error while loading"
-- Number of lines the wrapper emits BEFORE the first line of user code.
-- Used both inside the wrapper (Luau __mcp_LINE_OFFSET) and on the TS side
-- (remapPayloadLines, for compile errors recovered from LogService) so user
-- code errors report user-relative line numbers instead of the inflated
-- "line 49" the wrapper would otherwise expose. If you reorder buildWrapper's
-- prefix lines, update this constant.
local WRAPPER_LINE_OFFSET = 84
-- Count source lines so the wrapper can filter traceback frames that fall
-- outside the user code range (the wrapper's own preamble/postamble lines).
local function countLines(s)
	local n = 1
	local size = #s
	do
		local i = 1
		local shouldIncrement = false
		while true do
			if shouldIncrement then
				i += 1
			else
				shouldIncrement = true
			end
			if not (i <= size) then
				break
			end
			if string.sub(s, i, i) == "\n" then
				n += 1
			end
		end
	end
	return n
end
local function luaPatternEscape(s)
	local escaped = string.gsub(s, "([^%w])", "%%%1")
	return escaped
end
local function buildWrapper(code, payloadInstanceName)
	if payloadInstanceName == nil then
		payloadInstanceName = PAYLOAD_INSTANCE_NAME
	end
	-- If you reorder the prefix lines below, update WRAPPER_LINE_OFFSET to
	-- match the number of lines emitted BEFORE the ${code} substitution.
	-- The constant is mirrored inside the wrapper (__mcp_LINE_OFFSET) and
	-- used by remapPayloadLines on the TS side.
	local userLines = countLines(code)
	local payloadPattern = luaPatternEscape(payloadInstanceName)
	return `return ((function()\
\tlocal __mcp_traceback\
\tlocal __mcp_remap\
\tlocal __mcp_LINE_OFFSET = {WRAPPER_LINE_OFFSET}\
\tlocal __mcp_USER_LINES = {userLines}\
\tlocal __mcp_LogService = game:GetService("LogService")\
\tlocal __mcp_REQUIRE_GENERIC = "{REQUIRE_GENERIC_ERROR}"\
\tlocal __mcp_output = \{\}\
\tlocal __mcp_real_print = print\
\tlocal __mcp_real_warn = warn\
\tlocal __mcp_real_require = require\
\tlocal print = function(...)\
\t\t__mcp_real_print(...)\
\t\tlocal args = \{...\}\
\t\tlocal parts = table.create(#args)\
\t\tfor i, a in ipairs(args) do parts[i] = tostring(a) end\
\t\ttable.insert(__mcp_output, table.concat(parts, "\\t"))\
\tend\
\tlocal warn = function(...)\
\t\t__mcp_real_warn(...)\
\t\tlocal args = \{...\}\
\t\tlocal parts = table.create(#args)\
\t\tfor i, a in ipairs(args) do parts[i] = tostring(a) end\
\t\ttable.insert(__mcp_output, "[warn] " .. table.concat(parts, "\\t"))\
\tend\
\tlocal function __mcp_is_stack_noise(msg)\
\t\treturn msg == "Stack Begin" or msg == "Stack End" or string.sub(msg, 1, 8) == "Script '"\
\tend\
\tlocal function __mcp_is_actionable_require_log(entry)\
\t\tif not entry or entry.messageType ~= Enum.MessageType.MessageError then return false end\
\t\tlocal msg = tostring(entry.message)\
\t\treturn msg ~= __mcp_REQUIRE_GENERIC and not __mcp_is_stack_noise(msg)\
\tend\
\tlocal function __mcp_entry_mentions_module(entry, module_path)\
\t\tif not entry or not module_path or module_path == "" then return false end\
\t\treturn string.find(tostring(entry.message), module_path, 1, true) ~= nil\
\tend\
\tlocal function __mcp_prior_module_error(hist, module_path)\
\t\tif not module_path or module_path == "" then return nil end\
\t\tfor i = #hist, 1, -1 do\
\t\t\tlocal entry = hist[i]\
\t\t\tif __mcp_entry_mentions_module(entry, module_path) then\
\t\t\t\tif __mcp_is_actionable_require_log(entry) then\
\t\t\t\t\treturn tostring(entry.message)\
\t\t\t\tend\
\t\t\t\tfor j = i - 1, math.max(1, i - 6), -1 do\
\t\t\t\t\tlocal previous = hist[j]\
\t\t\t\t\tif __mcp_is_actionable_require_log(previous) then\
\t\t\t\t\t\treturn tostring(previous.message)\
\t\t\t\t\tend\
\t\t\t\tend\
\t\t\tend\
\t\tend\
\t\treturn nil\
\tend\
\tlocal function __mcp_recover_require_error(err, history_start, module)\
\t\tlocal err_msg = tostring(err)\
\t\tif err_msg ~= __mcp_REQUIRE_GENERIC then return err_msg end\
\t\tlocal module_path\
\t\tif typeof(module) == "Instance" then\
\t\t\tlocal ok_path, path = pcall(function()\
\t\t\t\treturn module:GetFullName()\
\t\t\tend)\
\t\t\tif ok_path then module_path = path end\
\t\tend\
\t\ttask.wait(0.05)\
\t\tlocal hist = __mcp_LogService:GetLogHistory()\
\t\tfor i = #hist, history_start + 1, -1 do\
\t\t\tlocal entry = hist[i]\
\t\t\tif __mcp_is_actionable_require_log(entry) then\
\t\t\t\treturn tostring(entry.message)\
\t\t\tend\
\t\tend\
\t\tlocal prior = __mcp_prior_module_error(hist, module_path)\
\t\tif prior then return prior end\
\t\treturn err_msg\
\tend\
\tlocal function require(module)\
\t\tlocal history_start = #__mcp_LogService:GetLogHistory()\
\t\tlocal ok, value = pcall(__mcp_real_require, module)\
\t\tif ok then return value end\
\t\terror(__mcp_recover_require_error(value, history_start, module), 0)\
\tend\
\tlocal function __mcp_run()\
{code}\
\tend\
\t__mcp_remap = function(s)\
\t\t-- Two chunk-name formats can reference our payload:\
\t\t--   * "Workspace.__MCPExecLuauPayload:N" — ModuleScript:require fallback path\
\t\t--   * "[string \\"return ((function()...\\"]:N" — loadstring() (default in plugin)\
\t\t-- Subtract LINE_OFFSET to get the user-relative number, then clamp.\
\t\t-- Clamping matters for unclosed constructs ("local x = (") where the\
\t\t-- parser keeps reading into wrapper postamble and reports a payload\
\t\t-- line past user EOF. Without clamping, that frames wrapper postamble\
\t\t-- as user code.\
\t\tlocal function __mcp_user_line(payload_n)\
\t\t\tlocal user_n = payload_n - __mcp_LINE_OFFSET\
\t\t\tif user_n < 1 then return "1" end\
\t\t\tif user_n > __mcp_USER_LINES then return tostring(__mcp_USER_LINES) .. " (at end of input)" end\
\t\t\treturn tostring(user_n)\
\t\tend\
\t\ts = string.gsub(s, "Workspace%.{payloadPattern}:(%d+)", function(num)\
\t\t\tlocal n = tonumber(num)\
\t\t\tif n then return "user_code:" .. __mcp_user_line(n) end\
\t\t\treturn "user_code:" .. num\
\t\tend)\
\t\ts = string.gsub(s, "{payloadPattern}:(%d+)", function(num)\
\t\t\tlocal n = tonumber(num)\
\t\t\tif n then return "user_code:" .. __mcp_user_line(n) end\
\t\t\treturn "user_code:" .. num\
\t\tend)\
\t\ts = string.gsub(s, '%[string "[^"]+"%]:(%d+)', function(num)\
\t\t\tlocal n = tonumber(num)\
\t\t\tif n then return "user_code:" .. __mcp_user_line(n) end\
\t\t\treturn "user_code:" .. num\
\t\tend)\
\t\treturn s\
\tend\
\t__mcp_traceback = function(err)\
\t\tlocal raw = debug.traceback(tostring(err), 2)\
\t\tlocal kept = \{\}\
\t\tfor line in string.gmatch(raw, "[^\\n]+") do\
\t\t\t-- Extract referenced line number (either chunk-name format).\
\t\t\tlocal num_str = string.match(line, "__MCPExecLuauPayload:(%d+)")\
\t\t\t\tor string.match(line, '%[string "[^"]+"%]:(%d+)')\
\t\t\tlocal n = num_str and tonumber(num_str)\
\t\t\t-- Strip the "in function '__mcp_run'" annotation before doing\
\t\t\t-- any filtering, because user-code frames carry that suffix —\
\t\t\t-- the entire user payload is hosted inside __mcp_run, so EVERY\
\t\t\t-- user frame would otherwise match a naive "__mcp_" filter and\
\t\t\t-- get dropped. Strip first, then apply filters.\
\t\t\tline = (string.gsub(line, " in function '__mcp_run'", ""))\
\t\t\tlocal skip = string.find(line, "MCPPlugin", 1, true)\
\t\t\t\tor string.find(line, "__mcp_", 1, true)\
\t\t\t\tor string.find(line, "in function 'xpcall'", 1, true)\
\t\t\t-- Frame lines pointing at wrapper preamble/postamble (outside\
\t\t\t-- user range) are wrapper internals — drop them. Lines without\
\t\t\t-- a payload-chunk line number (the traceback header / engine\
\t\t\t-- C frames) are kept; remap is a no-op for them.\
\t\t\tif n and (n <= __mcp_LINE_OFFSET or n > __mcp_LINE_OFFSET + __mcp_USER_LINES) then\
\t\t\t\tskip = true\
\t\t\tend\
\t\t\tif not skip then\
\t\t\t\ttable.insert(kept, __mcp_remap(line))\
\t\t\tend\
\t\tend\
\t\treturn table.concat(kept, "\\n")\
\tend\
\tlocal ok, errOrValue = xpcall(__mcp_run, __mcp_traceback)\
\treturn \{ ok = ok, value = errOrValue, output = __mcp_output \}\
end)())`
end
-- TS-side mirror of the Lua __mcp_remap. Used by runViaModuleScript when
-- pulling the real compile-error diagnostic out of LogService — that error
-- references the payload module's line number directly, and never passes
-- through the IIFE's runtime wrapper.
local function remapPayloadLines(s, userLines, payloadInstanceName)
	if payloadInstanceName == nil then
		payloadInstanceName = PAYLOAD_INSTANCE_NAME
	end
	-- Mirror of the Lua __mcp_remap inside the wrapper, for paths that
	-- don't pass through the IIFE (compile errors recovered from
	-- LogService, the immediate loadstring compileError surface). Same
	-- two-format coverage plus the same clamp: unclosed user constructs
	-- let the parser consume wrapper postamble, so the raw payload line
	-- is sometimes well past user EOF — clamp to [1, userLines] and
	-- annotate so the error doesn't say "user_code:49" for one-line input.
	local userLine = function(payload)
		local u = payload - WRAPPER_LINE_OFFSET
		if u < 1 then
			return "1"
		end
		if u > userLines then
			return `{tostring(userLines)} (at end of input)`
		end
		return tostring(u)
	end
	local payloadPattern = luaPatternEscape(payloadInstanceName)
	local out = s
	local a = string.gsub(out, `Workspace%.{payloadPattern}:(%d+)`, function(num)
		local n = tonumber(num)
		if n ~= nil then
			return `user_code:{userLine(n)}`
		end
		return `user_code:{num}`
	end)
	out = a
	local b = string.gsub(out, `{payloadPattern}:(%d+)`, function(num)
		local n = tonumber(num)
		if n ~= nil then
			return `user_code:{userLine(n)}`
		end
		return `user_code:{num}`
	end)
	out = b
	local c = string.gsub(out, '%[string "[^"]+"%]:(%d+)', function(num)
		local n = tonumber(num)
		if n ~= nil then
			return `user_code:{userLine(n)}`
		end
		return `user_code:{num}`
	end)
	return c
end
local recoverPayloadRequireError
local function runViaModuleScript(wrapped, userLines)
	local m = Instance.new("ModuleScript")
	m.Name = PAYLOAD_INSTANCE_NAME
	local okSet, setErr = pcall(function()
		m.Source = wrapped
	end)
	if not okSet then
		m:Destroy()
		-- error(..., 0) suppresses the "user_MCPPlugin.rbxmx.MCPPlugin.modules.LuauExec:N:"
		-- prefix that error() would otherwise prepend, keeping the visible
		-- message focused on the user-actionable error rather than our path.
		error(`ModuleScript Source set failed: {tostring(setErr)}`, 0)
	end
	m.Parent = game:GetService("Workspace")
	local okReq, reqResult = pcall(function()
		return require(m)
	end)
	m:Destroy()
	if not okReq then
		-- Compile errors reference the payload module's line number directly
		-- — remap + clamp to user-relative line numbers so `local x = 1 +`
		-- reports :1: instead of :23:, and reports the clamp annotation
		-- when the parser ran off the end of user code into wrapper code.
		error(recoverPayloadRequireError(reqResult, userLines, PAYLOAD_INSTANCE_NAME), 0)
	end
	return reqResult
end
local function isLoadstringUnavailable(err)
	local errStr = tostring(err)
	local matchStart = string.find(errStr, "not available", 1, true)
	return matchStart ~= nil
end
-- Returns a string suitable for `returnValue`. Tables get JSON-encoded so
-- the caller sees structured data instead of "table: 0xaddr". Anything that
-- JSONEncode chokes on (cycles, Roblox userdata) falls back to tostring.
local function formatReturnValue(value)
	if value == nil then
		return ""
	end
	if type(value) == "table" then
		local ok, encoded = pcall(function()
			return HttpService:JSONEncode(value)
		end)
		if ok then
			return encoded
		end
	end
	return tostring(value)
end
function recoverPayloadRequireError(err, userLines, payloadInstanceName, historyStart)
	if payloadInstanceName == nil then
		payloadInstanceName = PAYLOAD_INSTANCE_NAME
	end
	if historyStart == nil then
		historyStart = 0
	end
	local errMsg = tostring(err)
	-- pcall(require, m) collapses parse/compile failures into the canned
	-- engine string. The real diagnostic is emitted to LogService on the
	-- next engine frame — give it ~50ms to land then scan backward.
	if errMsg == REQUIRE_GENERIC_ERROR then
		task.wait(0.05)
		local payloadPathPrefix = `Workspace.{payloadInstanceName}:`
		local hist = LogService:GetLogHistory()
		local start = math.max(0, historyStart)
		do
			local i = #hist - 1
			local shouldIncrement = false
			while true do
				if shouldIncrement then
					i -= 1
				else
					shouldIncrement = true
				end
				if not (i >= start) then
					break
				end
				local e = hist[i + 1]
				if e.messageType == Enum.MessageType.MessageError and string.sub(e.message, 1, #payloadPathPrefix) == payloadPathPrefix then
					errMsg = e.message
					break
				end
			end
		end
	end
	return remapPayloadLines(errMsg, userLines, payloadInstanceName)
end
local function execute(code)
	if not (code ~= "" and code) or code == "" then
		return {
			success = false,
			error = "code is required",
		}
	end
	local wrapped = buildWrapper(code)
	local userLines = countLines(code)
	local success, result = pcall(function()
		local fn, compileError = loadstring(wrapped)
		if not fn then
			if isLoadstringUnavailable(compileError) then
				return runViaModuleScript(wrapped, userLines)
			end
			error(`Compile error: {remapPayloadLines(tostring(compileError), userLines)}`, 0)
		end
		return fn()
	end)
	-- loadstring can throw (not return nil) when ServerScriptService.
	-- LoadStringEnabled is false; treat that as a second-chance fallback.
	if not success and isLoadstringUnavailable(result) then
		success, result = pcall(function()
			return runViaModuleScript(wrapped, userLines)
		end)
	end
	if not success then
		return {
			success = false,
			error = tostring(result),
			output = {},
			message = "Code execution failed",
		}
	end
	local r = result
	local capturedOutput = r.output
	local output = if capturedOutput ~= nil then capturedOutput else ({})
	if r.ok == true then
		return {
			success = true,
			returnValue = if r.value ~= nil then formatReturnValue(r.value) else nil,
			output = output,
			message = "Code executed successfully",
		}
	end
	return {
		success = false,
		error = if r.value ~= nil then tostring(r.value) else "(unknown error)",
		output = output,
		message = "Code execution failed",
	}
end
return {
	buildWrapper = buildWrapper,
	countLines = countLines,
	execute = execute,
	formatReturnValue = formatReturnValue,
	recoverPayloadRequireError = recoverPayloadRequireError,
	remapPayloadLines = remapPayloadLines,
}
