--!strict

-- Watches remote traffic, so "what is this thing actually sending" stops being a guess.
--
-- Two different mechanisms, because remotes aren't symmetrical. A RemoteEvent can be *observed*:
-- connecting a second listener to OnServerEvent doesn't disturb the first, so watching one is
-- free and can't break the game. A RemoteFunction has exactly one callback, so the only way to
-- see a call is to take the callback, put our own in front, and hand the arguments on -- a real
-- hook. Stop() puts the originals back; a watch left running when a playtest ends dies with it.

local RunService = game:GetService("RunService")

local Serialize = require(script.Parent.Parent.Exec.Serialize)

local Remotes = {}

export type Call = {
	remote: string,
	direction: string,
	from: string?,
	at: number,
	args: string,
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
			local player = select(1, ...) :: any
			record(remote, "invoke server", if typeof(player) == "Instance" then player.Name else nil, table.pack(...))
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
