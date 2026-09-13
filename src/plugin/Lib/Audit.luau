--!strict

-- Collects the code a model needs to review the game's remotes for real.
--
-- The hard part of a security pass isn't the reasoning -- a model can spot a missing ownership
-- check or a client-authoritative grant on sight. The hard part is putting the *right* code in
-- front of it: out of a whole game, which scripts actually handle remotes, and which remote does
-- each one serve. That's what this does. It finds every server-side remote binding, traces the
-- variable back to the remote it belongs to, and returns the full source of each handling script
-- so the model reads the real thing -- requires, validation helpers, the lot -- not a sliced window.
--
-- It reads Script.Source, so it only works on the plugin/server side of a Studio session. It does
-- no grading of its own on purpose: the point is that the model reviews the code, decides which
-- remotes are exploitable, and hands those to Exploit to abuse. This just gathers.

local Audit = {}

export type Handler = {
	script: string,
	remotes: { string }, -- remote names this script binds a server handler for
	source: string,
}

export type Surface = {
	handlers: { Handler },
	remotes: { { name: string, path: string, class: string } },
	-- Remotes with no server-side binding found in any readable script: client-only, or dispatched
	-- through a table the tracer can't follow. Worth a manual look.
	orphans: { string },
}

local MAX_SOURCE = 24000

-- The remote a handler serves, read back from the code. Handlers bind through a variable
-- (`combat.OnServerEvent:Connect`), so find the variable, then find where it was assigned from a
-- remote by name. Returns nil when the source doesn't say plainly enough to trust.
local function remoteName(source: string, var: string): string?
	for _, pattern in
		{
			`local%s+${var}%s*=%s*[^\n]-[:.]WaitForChild%s*%(%s*["'](.-)["']`,
			`${var}%s*=%s*[^\n]-[:.]WaitForChild%s*%(%s*["'](.-)["']`,
			`local%s+${var}%s*=%s*[%w%.%[%]"']-%.([%w_]+)%s*[\n;]`,
			`${var}%s*=%s*[%w%.%[%]"']-%.([%w_]+)%s*[\n;]`,
		}
	do
		local name = string.match(source, pattern)
		if name then
			return name
		end
	end
	return nil
end

-- Gather every RemoteEvent/RemoteFunction and every script that binds a server handler, with the
-- handler's full source, so a model can review the real code.
function Audit.Surface(root: Instance?): Surface
	local scope = root or game

	local remotes: { { name: string, path: string, class: string } } = {}
	local bound: { [string]: boolean } = {}
	for _, instance in scope:GetDescendants() do
		if instance:IsA("RemoteEvent") or instance:IsA("UnreliableRemoteEvent") or instance:IsA("RemoteFunction") then
			table.insert(remotes, { name = instance.Name, path = instance:GetFullName(), class = instance.ClassName })
		end
	end

	local handlers: { Handler } = {}
	for _, instance in scope:GetDescendants() do
		if not instance:IsA("LuaSourceContainer") then
			continue
		end
		local ok, source = pcall(function()
			return (instance :: any).Source
		end)
		if not ok or type(source) ~= "string" or not string.find(source, "OnServer", 1, true) then
			continue
		end

		local names: { string } = {}
		local seen: { [string]: boolean } = {}
		for var in source:gmatch("([%w_]+)%.OnServer[EI]") do
			local name = remoteName(source, var) or var
			if not seen[name] then
				seen[name] = true
				bound[name] = true
				table.insert(names, name)
			end
		end

		if #names > 0 then
			table.insert(handlers, {
				script = instance:GetFullName(),
				remotes = names,
				source = if #source > MAX_SOURCE
					then source:sub(1, MAX_SOURCE) .. "\n-- ...(truncated, read the script directly for the rest)"
					else source,
			})
		end
	end

	local orphans: { string } = {}
	for _, remote in remotes do
		if not bound[remote.name] then
			table.insert(orphans, remote.path)
		end
	end

	return { handlers = handlers, remotes = remotes, orphans = orphans }
end

-- The surface as text, for a model to read and review. No verdicts -- that's the reader's job.
function Audit.Render(surface: Surface): string
	local lines = {
		`{#surface.remotes} remote(s), {#surface.handlers} handling script(s). Review each handler `
			.. "below for exploitable remotes -- missing type/ownership/rate checks, client-authoritative "
			.. "state, anything a client could abuse -- then hand the ones you flag to Exploit.AbuseAll.",
		"",
	}
	for _, handler in surface.handlers do
		table.insert(lines, `=== {handler.script}  (binds: {table.concat(handler.remotes, ", ")}) ===`)
		table.insert(lines, handler.source)
		table.insert(lines, "")
	end
	if #surface.orphans > 0 then
		table.insert(lines, `no server handler found for (client-only or dynamically dispatched -- look manually):`)
		for _, path in surface.orphans do
			table.insert(lines, `  {path}`)
		end
	end
	return table.concat(lines, "\n")
end

return Audit
