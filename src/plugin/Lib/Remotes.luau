--!strict

-- Watches remote traffic, so "what is this thing actually sending" stops being a guess.
--
-- Two different mechanisms, because remotes aren't symmetrical. A RemoteEvent can be *observed*:
-- connecting a second listener to OnServerEvent doesn't disturb the first, so watching one is
-- free and can't break the game. A RemoteFunction has exactly one callback, so the only way to
-- see a call is to take the callback, put our own in front, and hand the arguments on -- a real
-- hook. Stop() puts the originals back; a watch left running when a playtest ends dies with it.

local RunService = game:GetService("RunService")

local Path = require(script.Parent.Parent.Path)
local Portable = require(script.Parent.Parent.Exec.Portable)
local Serialize = require(script.Parent.Parent.Exec.Serialize)

local Remotes = {}

export type Call = {
	remote: string,
	direction: string,
	from: string?,
	at: number,
	args: string,
	-- The same arguments in a form that survives ctx and can be rebuilt in another DataModel, so
	-- what a client really sent can be replayed and mutated from a client event.
	captured: { any },
}

local MAX_CALLS = 500

local calls: { Call } = {}
local connections: { RBXScriptConnection } = {}
local restores: { () -> () } = {}

local function record(remote: Instance, direction: string, from: string?, args: { any })
	if #calls >= MAX_CALLS then
		return
	end
	table.insert(calls, {
		remote = remote:GetFullName(),
		direction = direction,
		from = from,
		at = os.clock(),
		args = Serialize.Render(args),
		captured = Portable.CaptureArgs(args),
	})
end

local function watchEvent(remote: RemoteEvent | UnreliableRemoteEvent)
	if RunService:IsServer() then
		table.insert(
			connections,
			(remote :: any).OnServerEvent:Connect(function(player: Player, ...)
				record(remote, "client to server", player.Name, table.pack(...))
			end)
		)
		return
	end
	table.insert(
		connections,
		(remote :: any).OnClientEvent:Connect(function(...)
			record(remote, "server to client", nil, table.pack(...))
		end)
	)
end

-- The invasive half. Saved and restored rather than left in place, because leaving a wrapper on a
-- live RemoteFunction after the watch ends would quietly change the game's behaviour.
local function hookFunction(remote: RemoteFunction)
	local property = if RunService:IsServer() then "OnServerInvoke" else "OnClientInvoke"
	local original = (remote :: any)[property]
	if type(original) ~= "function" then
		-- Nothing has claimed it yet. Hooking now would make us the handler, and there'd be no
		-- real one to pass the call to.
		return
	end
	(remote :: any)[property] = function(...)
		if RunService:IsServer() then
			-- OnServerInvoke gets the player as the first argument; the payload is what comes after,
			-- so a captured call can be replayed from a client without the player baked into it.
			local player = select(1, ...) :: any
			record(
				remote,
				"invoke server",
				if typeof(player) == "Instance" then player.Name else nil,
				table.pack(select(2, ...))
			)
		else
			record(remote, "invoke client", nil, table.pack(...))
		end
		return original(...)
	end

	table.insert(restores, function()
		(remote :: any)[property] = original
	end)
end

function Remotes.Watch(remote: Instance): string?
	if remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent") then
		watchEvent(remote :: any)
		return nil
	end
	if remote:IsA("RemoteFunction") then
		hookFunction(remote)
		return nil
	end
	return `{remote:GetFullName()} is a {remote.ClassName}, not a remote`
end

-- Every remote under `root`, plus any added later, so a remote created after the watch started
-- still gets seen.
function Remotes.WatchAll(root: Instance): number
	local found = 0
	for _, descendant in root:GetDescendants() do
		if not Remotes.Watch(descendant) then
			found += 1
		end
	end
	table.insert(
		connections,
		root.DescendantAdded:Connect(function(descendant: Instance)
			Remotes.Watch(descendant)
		end)
	)
	return found
end

function Remotes.Calls(): { Call }
	return calls
end

export type Shape = {
	remote: string,
	class: string,
	direction: string,
	calls: number,
	-- One word per argument position, from the most recent call.
	signature: { string },
	-- Real arguments, as sent. Feed them to Exploit.Tailor and it breaks them in the ways that
	-- matter for the types they actually are.
	sample: { any },
}

-- What the game's own traffic looks like: every remote seen, with a real set of arguments. JSON
-- safe on purpose -- write it to ctx from a server event and read it from a client event, and the
-- fuzzer stops guessing at shapes it could have just been told.
function Remotes.Shapes(): { Shape }
	local byRemote: { [string]: Shape } = {}
	local order: { string } = {}

	for _, call in calls do
		local shape = byRemote[call.remote]
		if not shape then
			local instance = Path.Resolve(call.remote)
			shape = {
				remote = call.remote,
				class = if instance then instance.ClassName else "unknown",
				direction = call.direction,
				calls = 0,
				signature = {},
				sample = {},
			}
			byRemote[call.remote] = shape
			table.insert(order, call.remote)
		end

		shape.calls += 1
		-- Last call wins: a later one is likelier to be the interesting in-game case than the
		-- first, which is often an empty init ping.
		shape.sample = call.captured
		local signature = {}
		for index = 1, (call.captured :: any).n or #call.captured do
			table.insert(signature, Portable.Describe(call.captured[index]))
		end
		shape.signature = signature
	end

	local out: { Shape } = {}
	for _, name in order do
		table.insert(out, byRemote[name])
	end
	return out
end

function Remotes.Report(): string
	if #calls == 0 then
		return "no remote traffic seen"
	end

	local counts: { [string]: number } = {}
	local order: { string } = {}
	for _, call in calls do
		local key = `{call.remote} ({call.direction})`
		if not counts[key] then
			table.insert(order, key)
		end
		counts[key] = (counts[key] or 0) + 1
	end

	local lines = { `{#calls} call(s) across {#order} remote(s):` }
	for _, key in order do
		table.insert(lines, `  {counts[key]}x {key}`)
	end
	table.insert(lines, "")
	table.insert(lines, "most recent:")
	for index = math.max(#calls - 9, 1), #calls do
		local call = calls[index]
		local who = if call.from then ` from {call.from}` else ""
		table.insert(lines, `  {call.remote}{who} {call.args}`)
	end
	return table.concat(lines, "\n")
end

function Remotes.Stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, restore in restores do
		pcall(restore)
	end
	table.clear(restores)
end

function Remotes.Clear()
	table.clear(calls)
end

return Remotes
