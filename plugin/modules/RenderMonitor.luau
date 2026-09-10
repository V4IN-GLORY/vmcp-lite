-- Detects whether the Studio window is actually rendering, so virtual input
-- and screenshot tools can surface a clear reason instead of silently failing.
--
-- When a Studio window is MINIMIZED, the engine suspends the render loop AND
-- input processing, but keeps running scripts (Heartbeat keeps firing). That's
-- why simulate_*_input would return success while having zero effect, and
-- CaptureService:CaptureScreenshot would time out. Validated live: during a 3s
-- minimize, RenderStepped's max inter-frame gap was 5.08s while Heartbeat's was
-- 0.10s. So RenderStepped freshness is the reliable "is this window rendering?"
-- signal; Heartbeat is not.
local RunService = game:GetService("RunService")
local lastFrame = 0
local connected = false
-- Above this many seconds since the last rendered frame, we treat the window
-- as not rendering. RenderStepped normally fires every ~16ms; a multi-second
-- gap only happens when minimized/suspended, so 1s cleanly avoids false
-- positives from ordinary frame hitches while still catching the real case.
local STALE_THRESHOLD = 1.0
local function start()
	if connected then
		return nil
	end
	-- RenderStepped can only be connected from a client/edit render loop; it
	-- throws in the play-server DM. pcall so a server-DM call is a safe no-op
	-- (connected stays false → notRenderingReason() returns undefined there).
	local ok = pcall(function()
		RunService.RenderStepped:Connect(function()
			lastFrame = tick()
		end)
	end)
	if ok then
		connected = true
		lastFrame = tick()
	end
end
local function secondsSinceFrame()
	if not connected then
		return 0
	end
	return tick() - lastFrame
end
-- Returns a human-readable reason if the window appears minimized / not
-- rendering (so input + screenshots won't work), else undefined. Fail-open:
-- when the monitor isn't active in this DM (server peer, or connect failed) it
-- returns undefined so we never block on a false signal.
local function notRenderingReason()
	if not connected then
		return nil
	end
	local gap = secondsSinceFrame()
	if gap > STALE_THRESHOLD then
		return string.format(
			"Studio window appears minimized or not rendering (no frame in %.1fs). "
				.. "Virtual input and screenshots only work while the window is visible — "
				.. "restore/un-minimize the Studio window and retry.",
			gap
		)
	end
	return nil
end
return {
	start = start,
	secondsSinceFrame = secondsSinceFrame,
	notRenderingReason = notRenderingReason,
}
