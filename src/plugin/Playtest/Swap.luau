--!strict

-- Starts a playtest that runs different Source in some scripts than the place has, without the
-- place ever holding it.
--
-- A playtest copies every script at start, so the trick is timing: write the replacement Source
-- in the edit DataModel, start the test, wait until its server is up, put the original back. The
-- playtest keeps the swapped copies until it stops; Studio's copy was different for a few
-- seconds and is untouched again by the time anyone reads it. Nothing is saved, and nothing lands
-- on disk -- Rojo only syncs toward Studio.
--
-- profile_scripts uses this to get its debug.profilebegin sections in; try_scripts uses it to let
-- the user play the candidate fix before it's applied anywhere.

local Bridge = require(script.Parent.Parent.Bridge)
local Session = require(script.Parent.Session)

local PEER_TIMEOUT = 90
local STOP_TIMEOUT = 30

local Swap = {}

export type Replacement = { instance: Instance, source: string }

local function stopRunning(): string?
	Bridge.Invoke("peer", { action = "stop", context = "server" }, 20)
	Session.Forget()
	local deadline = os.clock() + STOP_TIMEOUT
	while Session.IsRunning() and os.clock() < deadline do
		task.wait(0.25)
	end
	return if Session.IsRunning() then "the running playtest wouldn't stop" else nil
end

-- A playtest DataModel takes a few seconds to boot and connect, and there's no event for it.
function Swap.WaitFor(context: string, player: number?): string?
	local deadline = os.clock() + PEER_TIMEOUT
	local last = "never answered"
	repeat
		local reached, result = Bridge.Invoke("peer", { action = "ping", context = context, player = player }, 10)
		if reached and result ~= nil and result.isError ~= true then
			return nil
		end
		last = if reached then "not up yet" else tostring(result)
		task.wait(0.5)
	until os.clock() >= deadline
	return `the {context} never came up ({last})`
end

-- Reads each script once so the caller gets the text to build a replacement from, and the exact
-- text to restore.
function Swap.ReadSource(instance: Instance): (string?, string?)
	if not instance:IsA("LuaSourceContainer") then
		return nil, `{instance:GetFullName()} is a {instance.ClassName}, not a script`
	end
	local readable, source = pcall(function()
		return (instance :: any).Source
	end)
	if not readable or type(source) ~= "string" then
		return nil, `couldn't read {instance:GetFullName()} -- allow script injection for VMCP in Plugin Management`
	end
	return source, nil
end

-- Swaps, starts, waits for `context` to answer, restores. `restarted` says whether a playtest
-- that was already running had to be stopped first. `temporary` instances ride along the same
-- way: parented for the boot, destroyed once the playtest has its copy.
function Swap.Start(
	replacements: { Replacement },
	players: number,
	context: string,
	player: number?,
	temporary: { Instance }?
): (string?, boolean)
	local restarted = false
	if Session.IsRunning() then
		local failure = stopRunning()
		if failure then
			return failure, false
		end
		restarted = true
	end

	local originals: { Replacement } = {}
	local function restore()
		for _, original in originals do
			pcall(function()
				(original.instance :: any).Source = original.source
			end)
		end
		if temporary then
			for _, instance in temporary do
				instance:Destroy()
			end
		end
	end

	for _, replacement in replacements do
		local current, why = Swap.ReadSource(replacement.instance)
		if not current then
			restore()
			return why, restarted
		end
		table.insert(originals, { instance = replacement.instance, source = current })
		local written = pcall(function()
			(replacement.instance :: any).Source = replacement.source
		end)
		if not written then
			restore()
			return `couldn't write {replacement.instance:GetFullName()}`, restarted
		end
	end

	local failure = Session.Start(math.clamp(players, 1, 8))
	if failure then
		restore()
		return failure, restarted
	end

	local notUp = Swap.WaitFor(context, player)
	restore()
	return notUp, restarted
end

return Swap
