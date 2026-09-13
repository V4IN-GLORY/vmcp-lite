--!strict

-- Reads the game's own handler source and points at the remotes worth attacking first.
--
-- This is the static half of the loop. Exploit fires remotes from a client and watches what falls
-- over; that finds bugs but it's blind -- it can only try things. Audit reads the code the traffic
-- lands in and says *why* a remote is likely exploitable: it grants currency from a number the
-- client sent, it destroys an Instance the client named without checking who owns it, it never
-- rate-limits. The output is a short list of leads, ranked, so the abuse step has somewhere to aim
-- instead of fuzzing four hundred remotes evenly.
--
-- It reads Script.Source, so it only means anything on the plugin/server side of a Studio session,
-- not from a real client. And it's a text scanner, not a compiler: it matches the shapes that
-- almost always mean trouble, over a fixed window after each handler binding. It will miss a bug
-- hidden behind a helper call and it will occasionally flag a handler that's actually fine. Treat a
-- finding as "aim Exploit here", not "proven" -- the dynamic pass is what proves it.

local Audit = {}

export type Finding = {
	remote: string,
	handler: string,
	severity: string, -- "high" | "medium" | "low"
	kind: string,
	message: string,
	evidence: string,
}

local RANK: { [string]: number } = { high = 3, medium = 2, low = 1 }

-- Words that mean "this is the economy". A .Value write next to one of these, fed by a client
-- argument, is the classic grant-yourself-cash bug.
local CURRENCY = {
	"leaderstats",
	"Cash",
	"Coins",
	"Gold",
	"Money",
	"Gems",
	"Credits",
	"Points",
	"Currency",
	"Tokens",
	"Bucks",
	"Balance",
	"Wallet",
}

-- Any of these appearing in the body counts as "the handler looked at its arguments". Absence is
-- the signal, not presence -- a mutating handler with none of these trusts whatever it's handed.
local VALIDATION = {
	"type(",
	"typeof(",
	":IsA(",
	"assert(",
	"tonumber(",
	"~= nil",
	"== nil",
	"math.clamp",
	"math.max",
	"math.min",
	"string.len",
}

-- Proof the handler tied the request back to the caller. Ownership bugs are the absence of all of
-- these while still acting on a client-named Instance.
local OWNERSHIP = {
	"GetPlayerFromCharacter",
	"== player",
	"player ==",
	".Owner",
	"Ownership",
	"player.Character",
	"player.UserId",
	".UserId ==",
}

local RATE = {
	"os.clock",
	"tick(",
	"debounce",
	"Debounce",
	"cooldown",
	"Cooldown",
	"lastFire",
	"lastCall",
	"RateLimit",
	"ratelimit",
	"Throttle",
}

local function hasAny(body: string, words: { string }): boolean
	for _, word in words do
		if string.find(body, word, 1, true) then
			return true
		end
	end
	return false
end

local function trim(line: string): string
	return (line:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The remote a handler serves, read back from the code. Handlers bind through a variable
-- (`combat.OnServerEvent:Connect`), so find the variable, then find where it was pulled from a
-- remote by name. Falls back to the variable name itself when the source doesn't say.
local function remoteName(source: string, var: string): string
	for _, pattern in
		{
			`local%s+${var}%s*=%s*[^\n]-[:.]WaitForChild%s*%(%s*["'](.-)["']`,
			`${var}%s*=%s*[^\n]-[:.]WaitForChild%s*%(%s*["'](.-)["']`,
			`local%s+${var}%s*=%s*[%w%.]-%.([%w_]+)%s*[\n;]`,
			`${var}%s*=%s*[%w%.]-%.([%w_]+)%s*[\n;]`,
		}
	do
		local name = string.match(source, pattern)
		if name then
			return name
		end
	end
	return var
end

-- The handler body, roughly. A fixed window after the binding rather than a balanced parse -- Luau
-- text doesn't balance cleanly (strings, `end` inside names) and the signals we're after all sit in
-- the first few dozen lines of a handler anyway.
local WINDOW = 60

local function analyse(path: string, source: string, out: { Finding })
	-- Every server-side binding in this script: the variable it hangs off, and where it starts.
	for var, rest in source:gmatch("([%w_]+)%.OnServer[EI][%w]-([^\n]*)") do
		local isFunction = string.find(rest or "", "Invoke", 1, true) ~= nil
		local bindAt = string.find(source, `${var}.OnServer`, 1, true)
		if not bindAt then
			continue
		end

		-- Grab the signature (may run onto the next couple of lines) and the window after it.
		local head = source:sub(bindAt, bindAt + 4000)
		local params = string.match(head, "function%s*%(%s*(.-)%s*%)") or ""
		local body = ""
		do
			local lines = {}
			local count = 0
			for line in head:gmatch("[^\n]*\n?") do
				table.insert(lines, line)
				count += 1
				if count > WINDOW then
					break
				end
			end
			body = table.concat(lines)
		end

		local name = remoteName(source, var)
		local usesArgs = false
		-- First param is the calling player; the rest are the payload. A handler that references
		-- any payload param is one that acts on client data.
		local payload: { string } = {}
		local first = true
		for token in params:gmatch("[%w_]+") do
			if first then
				first = false
			else
				table.insert(payload, token)
				if string.find(body, token, 1, true) then
					usesArgs = true
				end
			end
		end

		local function add(severity: string, kind: string, message: string, evidence: string?)
			table.insert(out, {
				remote = name,
				handler = path,
				severity = severity,
				kind = kind,
				message = message,
				evidence = trim(evidence or ""),
			})
		end

		local function lineWith(needle: string): string?
			for line in body:gmatch("[^\n]+") do
				if string.find(line, needle, 1, true) then
					return line
				end
			end
			return nil
		end

		local mutates = false

		-- Currency written from a client argument: the grant bug.
		local valueWrite = string.find(body, "%.Value%s*[%+%-]?=")
		if valueWrite and hasAny(body, CURRENCY) then
			mutates = true
			if usesArgs then
				add(
					"high",
					"currency-from-client",
					"writes a currency/Value using an argument the client sent -- send a huge or negative amount",
					lineWith(".Value") or lineWith("leaderstats")
				)
			end
		end

		-- Reflection / arbitrary code from client input.
		if string.find(body, "loadstring", 1, true) or string.find(body, "getfenv", 1, true) then
			add(
				"high",
				"arbitrary-code",
				"loadstring/getfenv in a remote handler -- client can run code",
				lineWith("loadstring") or lineWith("getfenv")
			)
		end

		-- DataStore write driven by the handler: client can steer persistence.
		if
			string.find(body, "SetAsync", 1, true)
			or string.find(body, "UpdateAsync", 1, true)
			or string.find(body, "IncrementAsync", 1, true)
		then
			mutates = true
			if usesArgs then
				add(
					"high",
					"datastore-from-client",
					"writes a DataStore from a remote handler using client input",
					lineWith("Async")
				)
			end
		end

		-- Damage / health from a client number: client-authoritative combat.
		if
			string.find(body, ":TakeDamage(", 1, true)
			or string.find(body, "Humanoid.Health", 1, true)
			or string.find(body, ".Health%s*[%+%-]?=")
		then
			mutates = true
			if usesArgs then
				add(
					"high",
					"client-damage",
					"applies damage/health from the handler -- client decides the number",
					lineWith("Damage") or lineWith("Health")
				)
			end
		end

		-- Acts on a client-named Instance with no tie back to the caller: missing ownership check.
		local touchesInstance = string.find(body, ":Destroy(", 1, true)
			or string.find(body, "%.Parent%s*=")
			or string.find(body, ":FindFirstChild", 1, true)
			or string.find(body, ".Character", 1, true)
		local instancePayload = false
		for _, token in payload do
			if string.find(body, `${token}%.`) or string.find(body, `${token}:`) then
				instancePayload = true
			end
		end
		if touchesInstance and instancePayload and not hasAny(body, OWNERSHIP) then
			mutates = true
			add(
				"high",
				"missing-ownership",
				"acts on a client-supplied Instance without checking who owns it -- swap in another player's",
				lineWith(":Destroy(") or lineWith(".Parent")
			)
		end

		-- Whatever else, if it fires clients or sets Values it's a state change.
		if string.find(body, "FireAllClients", 1, true) or valueWrite then
			mutates = true
		end

		-- No validation at all on a handler that takes and uses a payload.
		if usesArgs and not hasAny(body, VALIDATION) then
			add(
				if mutates then "high" else "medium",
				"no-validation",
				"uses its arguments without a single type/nil/range check",
				`function(${params})`
			)
		end

		-- Mutating handler with nothing that looks like a cooldown.
		if mutates and not hasAny(body, RATE) then
			add(
				"medium",
				"no-rate-limit",
				"changes state with no visible rate limit -- spam it",
				`${var}.OnServer${if isFunction then "Invoke" else "Event"}`
			)
		end
	end
end

-- Scan everything readable under `root` (default: the whole DataModel). Returns findings ranked
-- worst-first.
function Audit.Scan(root: Instance?): { Finding }
	local out: { Finding } = {}
	for _, instance in (root or game):GetDescendants() do
		if not instance:IsA("LuaSourceContainer") then
			continue
		end
		local ok, source = pcall(function()
			return (instance :: any).Source
		end)
		if ok and type(source) == "string" and string.find(source, "OnServer", 1, true) then
			analyse(instance:GetFullName(), source, out)
		end
	end

	table.sort(out, function(a, b)
		return RANK[a.severity] > RANK[b.severity]
	end)
	return out
end

-- The remotes worth handing to Exploit, high severity first, each once. This is the bridge between
-- the two halves: Scan on the server/plugin side, cross the names through ctx, resolve and abuse
-- them on the client.
function Audit.Harsh(findings: { Finding }): { string }
	local seen: { [string]: boolean } = {}
	local out: { string } = {}
	for _, finding in findings do
		if finding.severity == "high" and not seen[finding.remote] then
			seen[finding.remote] = true
			table.insert(out, finding.remote)
		end
	end
	return out
end

function Audit.Report(findings: { Finding }): string
	if #findings == 0 then
		return "scanned every readable script; no server remote handlers looked exploitable (or none were readable)"
	end

	local lines = { `{#findings} finding(s), worst first:` }
	for _, finding in findings do
		table.insert(lines, `  [{finding.severity:upper()}] {finding.remote} ({finding.kind}) -- {finding.message}`)
		if finding.evidence ~= "" then
			table.insert(lines, `      {finding.evidence}   @ {finding.handler}`)
		end
	end
	return table.concat(lines, "\n")
end

return Audit
