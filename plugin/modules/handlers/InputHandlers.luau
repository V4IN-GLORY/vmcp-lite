-- Virtual input via UserInputService:CreateVirtualInput().
--
-- We deliberately do NOT use VirtualInputManager:Send*Event — those methods
-- are gated behind RobloxScriptSecurity ("lacking capability RobloxScript")
-- in every context a plugin can reach (edit DM, play server/client DMs), so
-- they silently never worked. CreateVirtualInput() is callable without that
-- capability and drives the REAL input pipeline: SendKey feeds
-- UserInputService.InputBegan/Ended and the control modules (so WASD walks the
-- character at full WalkSpeed with controls intact, no Humanoid hijack),
-- SendMouseButton feeds UIS and activates GUI buttons (and hit-tests against
-- CoreGui), and SendTextInput types into the focused TextBox.
--
-- Method set on the VirtualInput object (verified live):
--   SendKey(isDown: boolean, keyCode: Enum.KeyCode)
--   SendMouseButton(position: Vector2, inputType: Enum.UserInputType, isDown: boolean)
--   SendTextInput(text: string)
-- There is NO SendMouseMove / SendMouseWheel / SendKeyEvent — so "move" and
-- "scroll" mouse actions are not supported.
--
-- Coordinate space: SendMouseButton coordinates are viewport pixels matching
-- what capture_screenshot returns (window space, origin at the top-left of the
-- rendered viewport). Pass screenshot pixel coordinates straight through. Note
-- that UserInputService reports input positions in GUI space, which is offset
-- from this by GuiService:GetGuiInset() (~58px on the Y axis) — irrelevant for
-- callers who pick coordinates off a screenshot, which is why we do not
-- translate here.
local RenderMonitor = require(script.Parent.Parent.RenderMonitor)
local UserInputService = game:GetService("UserInputService")
-- One VirtualInput per plugin VM, reused across calls so that a key held down
-- in one call (action="press") and released in a later call (action="release")
-- share the same input source.
local cachedVI
local function getVI()
	if cachedVI then
		return cachedVI
	end
	local ok, vi = pcall(function()
		return UserInputService:CreateVirtualInput()
	end)
	if ok and vi ~= nil then
		cachedVI = vi
		return cachedVI
	end
	return nil
end
local MOUSE_TYPE_MAP = {
	Left = Enum.UserInputType.MouseButton1,
	Right = Enum.UserInputType.MouseButton2,
	Middle = Enum.UserInputType.MouseButton3,
}
local function simulateMouseInput(requestData)
	local action = requestData.action
	local x = requestData.x
	local y = requestData.y
	local condition = requestData.button
	if condition == nil then
		condition = "Left"
	end
	local button = condition
	if not (action ~= "" and action) then
		return {
			error = "action is required",
		}
	end
	if x == nil or y == nil then
		return {
			error = "x and y are required",
		}
	end
	-- Input is silently dropped by the engine when the window isn't rendering
	-- (e.g. minimized). Surface that instead of returning a false success.
	local notRendering = RenderMonitor.notRenderingReason()
	if notRendering ~= nil then
		return {
			error = notRendering,
		}
	end
	local vi = getVI()
	if not vi then
		return {
			error = "UserInputService:CreateVirtualInput() is not available in this context",
		}
	end
	local inputType = MOUSE_TYPE_MAP[button] or Enum.UserInputType.MouseButton1
	local pos = Vector2.new(x, y)
	local success, err = pcall(function()
		if action == "click" then
			vi:SendMouseButton(pos, inputType, true)
			task.wait(0.05)
			vi:SendMouseButton(pos, inputType, false)
		elseif action == "mouseDown" then
			vi:SendMouseButton(pos, inputType, true)
		elseif action == "mouseUp" then
			vi:SendMouseButton(pos, inputType, false)
		else
			error(
				`Unsupported action "{action}". CreateVirtualInput supports click, mouseDown, mouseUp `
					.. `(no move/scroll — those methods don't exist on VirtualInput).`
			)
		end
	end)
	if success then
		return {
			success = true,
			action = action,
			x = x,
			y = y,
			button = button,
		}
	end
	return {
		error = `Failed to simulate mouse input: {err}`,
	}
end
local function simulateKeyboardInput(requestData)
	local notRendering = RenderMonitor.notRenderingReason()
	if notRendering ~= nil then
		return {
			error = notRendering,
		}
	end
	local vi = getVI()
	if not vi then
		return {
			error = "UserInputService:CreateVirtualInput() is not available in this context",
		}
	end
	-- Text mode: type a string into the focused TextBox.
	local text = requestData.text
	if text ~= nil then
		local ok, err = pcall(function()
			return vi:SendTextInput(text)
		end)
		if ok then
			return {
				success = true,
				text = text,
			}
		end
		return {
			error = `Failed to send text input: {err}`,
		}
	end
	local keyCodeName = requestData.keyCode
	if not (keyCodeName ~= "" and keyCodeName) then
		return {
			error = "keyCode (or text) is required",
		}
	end
	local condition = requestData.action
	if condition == nil then
		condition = "tap"
	end
	local action = condition
	local condition_1 = requestData.duration
	if condition_1 == nil then
		condition_1 = 0.1
	end
	local duration = condition_1
	local enumOk, keyCode = pcall(function()
		return (Enum.KeyCode)[keyCodeName]
	end)
	if not enumOk or not keyCode then
		return {
			error = `Unknown keyCode: {keyCodeName}. Use Enum.KeyCode names like "W", "Space", "E", "LeftShift", etc.`,
		}
	end
	local success, err = pcall(function()
		if action == "press" then
			vi:SendKey(true, keyCode)
		elseif action == "release" then
			vi:SendKey(false, keyCode)
		elseif action == "tap" then
			vi:SendKey(true, keyCode)
			task.wait(duration)
			vi:SendKey(false, keyCode)
		else
			error(`Unknown action: {action}`)
		end
	end)
	if success then
		return {
			success = true,
			keyCode = keyCodeName,
			action = action,
		}
	end
	return {
		error = `Failed to simulate keyboard input: {err}`,
	}
end
return {
	simulateMouseInput = simulateMouseInput,
	simulateKeyboardInput = simulateKeyboardInput,
}
