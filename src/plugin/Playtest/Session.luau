--!strict

-- Starting and stopping the one playtest a Studio window is allowed to have.
--
-- There is very little to it now. Nothing is injected into the place and nothing is saved, because
-- the plugin loads into the playtest's DataModels by itself -- so all this does is press the
-- button and remember whether it was the one that pressed it.

local Session = {}

local state = {
	ours = false,
	players = 0,
	startedAt = 0,
}

local function service(): any
	return game:GetService("StudioTestService")
end

function Session.IsRunning(): boolean
	return not service().EditModeActive
end

-- One player gets Play Solo: a single DataModel that is both server and client, and far quicker to
-- start than the real thing. Two or more needs a genuine multiplayer test.
function Session.Start(players: number): string?
	if Session.IsRunning() then
		return "a playtest is already running -- stop that one first"
	end

	state.ours = true
	state.players = players
	state.startedAt = os.clock()

	-- Both calls yield until the test ends, and the plugin has to stay answerable the whole time a
	-- session is open, so the waiting happens on its own thread.
	task.spawn(function()
		local studio = service()
		local ok, failure
		if players <= 1 then
			ok, failure = pcall(studio.ExecutePlayModeAsync, studio, {})
		else
			ok, failure = pcall(studio.ExecuteMultiplayerTestAsync, studio, players, {})
		end
		if not ok then
			warn(`[VMCP] the playtest would not start: {failure}`)
		end
		state.ours = false
	end)
	return nil
end

function Session.Status(): { [string]: any }
	local running = Session.IsRunning()
	return {
		running = running,
		-- Studio's own Play button counts as a playtest; it just is not one we started, so we
		-- should not stop it out from under anyone either.
		ours = running and state.ours,
		players = if running then state.players else nil,
		seconds = if running then math.floor(os.clock() - state.startedAt) else nil,
	}
end

function Session.Forget()
	state.ours = false
end

return Session
