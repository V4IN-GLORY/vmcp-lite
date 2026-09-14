--!strict

-- Makes a test client behave like a player for a while, so a profile taken meanwhile has real
-- movement, animation, replication and remote traffic in it -- and with several clients doing
-- it at once, the per-player loops that only blow up at eight players show up at eight players.
--
-- Client-side only: it drives `input`, the timeline's real input path, and fires remotes the way
-- the game's own UI would.

local Load = {}

export type RemoteSpec = { remote: Instance, args: { any }?, perSecond: number? }

export type Options = {
	-- Seconds to keep going. Defaults to 5.
	seconds: number?,
	-- Remotes to fire while wandering, each with the arguments to send and how often per second.
	remotes: { RemoteSpec }?,
	-- Chance per step of a jump. Defaults to 0.15.
	jump: number?,
	-- Seed, so eight clients don't all walk the same line. Defaults to the peer index if the
	-- caller passes it, else time.
	seed: number?,
}

local MOVE_KEYS = { "W", "A", "S", "D" }

-- Walks, turns, jumps and fires remotes until `seconds` are up. `input` is the timeline's input
-- object for this client event. Returns how many steps and remote calls were made.
function Load.Wander(input: any, options: Options?): { steps: number, remoteCalls: number }
	local settings: Options = options or {}
	local random = Random.new(settings.seed or math.floor(os.clock() * 1000))
	local deadline = os.clock() + (settings.seconds or 5)
	local jumpChance = settings.jump or 0.15
	local remotes: { RemoteSpec } = settings.remotes or {}
	local nextFire: { number } = {}
	for index in remotes do
		nextFire[index] = 0
	end

	local steps, remoteCalls = 0, 0
	local held: string? = nil
	while os.clock() < deadline do
		local key = MOVE_KEYS[random:NextInteger(1, #MOVE_KEYS)]
		if held then
			input:Release(held)
		end
		input:Hold(key)
		held = key
		if random:NextNumber() < jumpChance then
			input:Tap("Space", 0.05)
		end
		steps += 1

		local now = os.clock()
		for index, spec in remotes do
			if now < nextFire[index] then
				continue
			end
			nextFire[index] = now + 1 / (spec.perSecond or 2)
			local remote: any = spec.remote
			local args = spec.args or {}
			local ok = pcall(function()
				if remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent") then
					remote:FireServer(table.unpack(args))
				elseif remote:IsA("RemoteFunction") then
					remote:InvokeServer(table.unpack(args))
				end
			end)
			if ok then
				remoteCalls += 1
			end
		end

		task.wait(random:NextNumber(0.2, 0.7))
	end
	if held then
		input:Release(held)
	end
	return { steps = steps, remoteCalls = remoteCalls }
end

return Load
