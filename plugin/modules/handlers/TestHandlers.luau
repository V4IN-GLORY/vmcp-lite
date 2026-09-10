local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StopPlayMonitor = require(script.Parent.Parent.StopPlayMonitor)
local PluginSession = require(script.Parent.Parent.PluginSession)
local PeerRole = require(script.Parent.Parent.PeerRole)
local StudioTestService = game:GetService("StudioTestService")
local testRunning = false
local multiplayerState = {
	phase = "idle",
}
local function detectPeerRole()
	return PeerRole.detect()
end
local function getPlayersSnapshot()
	local exp = Players:GetPlayers()
	local players = table.create(#exp)
	for i, player in exp do
		players[i] = {
			name = player.Name,
			userId = player.UserId,
			displayName = player.DisplayName,
		}
	end
	table.sort(players, function(a, b)
		return a.name < b.name
	end)
	return players
end
local function cloneMultiplayerState()
	return {
		phase = multiplayerState.phase,
		testId = multiplayerState.testId,
		numPlayers = multiplayerState.numPlayers,
		testArgs = multiplayerState.testArgs,
		startedAt = multiplayerState.startedAt,
		completedAt = multiplayerState.completedAt,
		ok = multiplayerState.ok,
		result = multiplayerState.result,
		error = multiplayerState.error,
	}
end
local function normalizeNumPlayers(value)
	if not (type(value) == "number") then
		return nil
	end
	local n = math.floor(value)
	if n ~= value or n < 1 or n > 8 then
		return nil
	end
	return n
end
local function startPlaytest(requestData)
	local mode = requestData.mode
	local numPlayers = requestData.numPlayers
	if mode ~= "play" and mode ~= "run" then
		return {
			error = 'mode must be "play" or "run"',
		}
	end
	if numPlayers ~= nil then
		return {
			error = "start_playtest is single-player only. Use multiplayer_test_start for multi-client StudioTestService sessions.",
		}
	end
	-- Peer teardown and ExecutePlayModeAsync completion can precede native edit
	-- readiness. Do not acknowledge a new start that the engine cannot execute.
	if not StudioTestService.EditModeActive then
		return {
			success = false,
			error = "Studio is not ready to start a playtest.",
			message = "Wait for Studio to finish its current playtest transition before starting another.",
			editModeReady = false,
		}
	end
	-- Self-heal: if testRunning is stuck true but Studio reports no active
	-- playtest, the previous start_playtest's task.spawn was orphaned
	-- (plugin reload mid-test, Studio entered some inconsistent state, etc).
	-- Reset it so subsequent starts don't hit a false "already running".
	if testRunning and not RunService:IsRunning() then
		testRunning = false
		-- Runtime eval bridges are created by the play server/client plugin
		-- peers and disappear with the play DataModels.
	end
	if testRunning then
		return {
			error = "A test is already running",
		}
	end
	testRunning = true
	local topologyMarkerToken = PluginSession.prepareSharedTopology()
	task.spawn(function()
		local ok, result = pcall(function()
			if mode == "play" then
				return StudioTestService:ExecutePlayModeAsync({})
			end
			return StudioTestService:ExecuteRunModeAsync({})
		end)
		PluginSession.clearTopologyMarker(topologyMarkerToken)
		if not ok then
			warn(`[robloxstudio-mcp] Playtest ended with error: {result}`)
		end
		testRunning = false
	end)
	local response = {
		success = true,
		message = `Playtest started in {mode} mode.`,
	}
	return response
end
local function stopPlaytest(_requestData)
	-- Signal the play-server DM's StopPlayMonitor via plugin:SetSetting.
	-- The monitor acknowledges with the matching request id only after its
	-- StudioTestService:EndTest call returns from pcall.
	local stopRequest = StopPlayMonitor.requestStop()
	if not stopRequest.ok or stopRequest.requestId == nil then
		return {
			error = "Plugin not ready. Try again in a moment.",
		}
	end
	local consumption = StopPlayMonitor.waitForConsumption(stopRequest.requestId)
	if not consumption.ok then
		-- Two distinct failure modes collapse here, distinguished by whether
		-- THIS edit DM has a playtest tracked:
		--
		-- - testRunning=false: no playtest was running from this edit DM
		--   (true negative). Return "no active playtest" — fine to retry only
		--   after actually starting a playtest.
		-- - testRunning=true: a playtest IS running but the cross-DM signal
		--   didn't propagate within the consumption timeout (false negative
		--   from the caller's perspective — playtest may actually have ended).
		--   Tell the caller it's a timing issue and they can retry.
		--
		-- Either way clean up the pending request so a future playtest's monitor
		-- doesn't fire EndTest on startup against a stale signal.
		StopPlayMonitor.clearPending(stopRequest.requestId)
		if testRunning then
			return {
				error = "Playtest stop signal failed or was not acknowledged. "
					.. "The playtest may have ended anyway; check get_connected_instances.",
				detail = consumption.error,
			}
		end
		if consumption.consumed then
			return {
				error = "Playtest stop request reached the play server, but EndTest failed.",
				detail = consumption.error,
			}
		end
		return {
			error = "No active playtest to stop.",
			detail = consumption.error,
		}
	end
	StopPlayMonitor.clearPending(stopRequest.requestId)
	-- EndTest consumption, task completion, and native edit readiness are distinct
	-- milestones. In particular, testRunning can clear before Studio accepts another
	-- ExecutePlayModeAsync call (and is never set for manually started playtests).
	-- Only report completion after both tracked execution and native teardown settle.
	local deadline = tick() + 10
	while (testRunning or not StudioTestService.EditModeActive) and tick() < deadline do
		task.wait(0.1)
	end
	local editModeReady = StudioTestService.EditModeActive
	if testRunning or not editModeReady then
		return {
			success = false,
			error = "Playtest teardown did not complete.",
			message = "Stop signal was accepted, but Studio teardown did not settle before timeout.",
			stopSignalAccepted = true,
			editModeReady = editModeReady,
			playtestTaskPending = testRunning,
			timedOut = true,
		}
	end
	return {
		success = true,
		message = "Playtest stopped.",
	}
end
local function multiplayerTestStart(requestData)
	if RunService:IsRunning() then
		return {
			error = "multiplayer_test_start must be called on the edit DataModel. Route with target=edit.",
		}
	end
	local numPlayers = normalizeNumPlayers(requestData.numPlayers)
	if numPlayers == nil then
		return {
			error = "numPlayers must be an integer from 1 to 8",
		}
	end
	if multiplayerState.phase == "starting" or multiplayerState.phase == "running" then
		return {
			error = "A multiplayer Studio test is already running",
			state = cloneMultiplayerState(),
		}
	end
	local testArgs = if requestData.testArgs ~= nil then requestData.testArgs else {}
	local testId = HttpService:GenerateGUID(false)
	multiplayerState = {
		phase = "starting",
		testId = testId,
		numPlayers = numPlayers,
		testArgs = testArgs,
		startedAt = tick(),
	}
	local topologyMarkerToken = PluginSession.prepareMultiplayerTopology(testId)
	task.spawn(function()
		multiplayerState.phase = "running"
		local ok, result = pcall(function()
			return StudioTestService:ExecuteMultiplayerTestAsync(numPlayers, testArgs)
		end)
		PluginSession.clearTopologyMarker(topologyMarkerToken)
		multiplayerState.completedAt = tick()
		multiplayerState.ok = ok
		if ok then
			multiplayerState.phase = "completed"
			multiplayerState.result = result
			multiplayerState.error = nil
		else
			multiplayerState.phase = "failed"
			multiplayerState.result = nil
			multiplayerState.error = tostring(result)
		end
	end)
	local response = {
		success = true,
		message = `Multiplayer Studio test starting with {numPlayers} player(s).`,
		testId = testId,
		phase = multiplayerState.phase,
		numPlayers = numPlayers,
		testArgs = testArgs,
	}
	return response
end
local function multiplayerTestState(_requestData)
	local peer = detectPeerRole()
	local response = {
		success = true,
		peer = peer,
		isRunning = RunService:IsRunning(),
		isRunMode = RunService:IsRunMode(),
		editModeActive = StudioTestService.EditModeActive,
	}
	if peer == "edit" then
		response.session = cloneMultiplayerState()
		return response
	end
	local argsOk, args = pcall(function()
		return StudioTestService:GetTestArgs()
	end)
	response.testArgsOk = argsOk
	response.testArgs = if argsOk then args else nil
	if not argsOk then
		response.testArgsError = tostring(args)
	end
	local players = getPlayersSnapshot()
	response.players = players
	response.playerCount = #players
	if peer == "client" then
		response.localPlayer = if Players.LocalPlayer then Players.LocalPlayer.Name else nil
		local canLeaveOk, canLeave = pcall(function()
			return StudioTestService:CanLeaveTest()
		end)
		response.canLeaveOk = canLeaveOk
		response.canLeave = if canLeaveOk then canLeave else false
		if not canLeaveOk then
			response.canLeaveError = tostring(canLeave)
		end
	end
	return response
end
local function multiplayerTestAddPlayers(requestData)
	if not RunService:IsRunning() or not RunService:IsServer() then
		return {
			error = "multiplayer_test_add_players must be called on the running server peer. Route with target=server.",
		}
	end
	local numPlayers = normalizeNumPlayers(requestData.numPlayers)
	if numPlayers == nil then
		return {
			error = "numPlayers must be an integer from 1 to 8",
		}
	end
	local before = #Players:GetPlayers()
	local ok, result = pcall(function()
		return StudioTestService:AddPlayers(numPlayers)
	end)
	if not ok then
		return {
			error = tostring(result),
		}
	end
	local exp = tick()
	local condition = requestData.timeout
	if condition == nil then
		condition = 10
	end
	local deadline = exp + condition
	while #Players:GetPlayers() < before + numPlayers and tick() < deadline do
		task.wait(0.1)
	end
	local players = getPlayersSnapshot()
	return {
		success = true,
		message = `Requested {numPlayers} additional player(s).`,
		playerCount = #players,
		players = players,
	}
end
local function multiplayerTestLeaveClient(_requestData)
	if not RunService:IsRunning() or RunService:IsServer() then
		return {
			error = "multiplayer_test_leave_client must be called on a running client peer. Route with target=client-N.",
		}
	end
	local canLeaveOk, canLeave = pcall(function()
		return StudioTestService:CanLeaveTest()
	end)
	if not canLeaveOk then
		return {
			error = tostring(canLeave),
			canLeaveOk = false,
		}
	end
	if not canLeave then
		return {
			error = "This client cannot leave the current test session.",
			canLeaveOk = true,
			canLeave = false,
		}
	end
	local localPlayer = if Players.LocalPlayer then Players.LocalPlayer.Name else nil
	task.defer(function()
		pcall(function()
			return StudioTestService:LeaveTest()
		end)
	end)
	return {
		success = true,
		message = "Client leave requested.",
		localPlayer = localPlayer,
	}
end
local function multiplayerTestEnd(requestData)
	if not RunService:IsRunning() or not RunService:IsServer() then
		return {
			error = "multiplayer_test_end must be called on the running server peer. Route with target=server.",
		}
	end
	local value = if requestData.value ~= nil then requestData.value else "ended_by_mcp"
	local ok, result = pcall(function()
		return StudioTestService:EndTest(value)
	end)
	if not ok then
		return {
			error = tostring(result),
		}
	end
	return {
		success = true,
		message = "Multiplayer Studio test end requested.",
		value = value,
	}
end
return {
	startPlaytest = startPlaytest,
	stopPlaytest = stopPlaytest,
	multiplayerTestStart = multiplayerTestStart,
	multiplayerTestState = multiplayerTestState,
	multiplayerTestAddPlayers = multiplayerTestAddPlayers,
	multiplayerTestLeaveClient = multiplayerTestLeaveClient,
	multiplayerTestEnd = multiplayerTestEnd,
}
