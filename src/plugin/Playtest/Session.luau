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

function Session.Start(players: number): string?
	if Session.IsRunning() then
		return "a playtest is already running"
	end

	state.ours = true
	state.players = players
	state.startedAt = os.clock()

	task.spawn(function()
		local studio = service()
		local ok, failure
		if players <= 1 then
			ok, failure = pcall(studio.ExecutePlayModeAsync, studio, {})
		else
			ok, failure = pcall(studio.ExecuteMultiplayerTestAsync, studio, players, {})
		end
		if not ok then
			warn(`the playtest is not starting because {failure}`)
		end
		state.ours = false
	end)
	return nil
end

function Session.Status(): { [string]: any }
	local running = Session.IsRunning()
	return {
		running = running,
		ours = running and state.ours,
		players = if running then state.players else nil,
		seconds = if running then math.floor(os.clock() - state.startedAt) else nil,
	}
end

function Session.Forget()
	state.ours = false
end

return Session
