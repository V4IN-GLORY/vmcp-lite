--!strict
--!optimize 2

-- Proves two functions behave the same: same inputs in, same returns, same errors, same state
-- left behind. This is what makes "the fix doesn't change behaviour" a measured claim.
--
-- No dependencies on the rest of the plugin, on purpose: GameVm copies this module into the
-- playtest so it can run against functions that live in the game's own VM (where the plugin
-- can't reach them), and it's the same file either side.

local Equiv = {}

export type Mismatch = {
	-- The call index, or a probe label like "arg 2: nil".
	input: string,
	-- returns | error | state | outcome
	kind: string,
	detail: string,
}

export type Options = {
	-- Calls to make. Defaults to 100.
	n: number?,
	-- Snapshot of whatever the functions mutate, taken after each call and compared.
	state: (() -> any)?,
	-- Also feed both functions broken arguments and compare how they fail. Defaults to true.
	probes: boolean?,
	-- Relative tolerance for numbers. Defaults to 1e-9.
	tolerance: number?,
	-- Stop after this many mismatches. Defaults to 10.
	limit: number?,
}

export type Result = {
	passed: boolean,
	checked: number,
	probed: number,
	mismatches: { Mismatch },
	text: string,
}

local DEFAULT_N = 100
local DEFAULT_LIMIT = 10
local DEFAULT_TOLERANCE = 1e-9

local function describe(value: any, depth: number?): string
	local kind = typeof(value)
	if kind == "string" then
		return string.format("%q", if #value > 60 then string.sub(value, 1, 60) .. "…" else value)
	end
	if kind == "table" then
		if (depth or 0) >= 2 then
			return "{…}"
		end
		local parts = {}
		local count = 0
		for key, entry in value do
			count += 1
			if count > 6 then
				table.insert(parts, "…")
				break
			end
			table.insert(parts, `{tostring(key)} = {describe(entry, (depth or 0) + 1)}`)
		end
		return "{ " .. table.concat(parts, ", ") .. " }"
	end
	if kind == "Instance" then
		return `<{value.ClassName} {value:GetFullName()}>`
	end
	return tostring(value)
end

local function deepCopy(value: any, seen: { [any]: any }?): any
	if type(value) ~= "table" then
		return value
	end
	local memo = seen or {}
	if memo[value] then
		return memo[value]
	end
	local out = {}
	memo[value] = out
	for key, entry in value do
		out[deepCopy(key, memo)] = deepCopy(entry, memo)
	end
	return setmetatable(out, getmetatable(value)) :: any
end

-- Returns nil when equal, otherwise a path plus what differed.
local function diff(a: any, b: any, tolerance: number, path: string, seen: { [any]: boolean }): string?
	local ka, kb = typeof(a), typeof(b)
	if ka ~= kb then
		return `{path}: {ka} vs {kb} ({describe(a)} vs {describe(b)})`
	end
	if ka == "number" then
		if a ~= a and b ~= b then
			return nil
		end
		local scale = math.max(math.abs(a), math.abs(b), 1)
		if math.abs(a - b) > tolerance * scale then
			return `{path}: {a} vs {b}`
		end
		return nil
	end
	if ka == "table" then
		if a == b or seen[a] then
			return nil
		end
		seen[a] = true
		for key, entry in a do
			local problem = diff(entry, b[key], tolerance, `{path}.{tostring(key)}`, seen)
			if problem then
				return problem
			end
		end
		for key in b do
			if a[key] == nil then
				return `{path}.{tostring(key)}: nil vs {describe(b[key])}`
			end
		end
		return nil
	end
	if ka == "function" or ka == "thread" then
		return nil
	end
	if a ~= b then
		return `{path}: {describe(a)} vs {describe(b)}`
	end
	return nil
end

-- Script paths and line numbers differ between the original and a candidate module by
-- construction, so they can't be part of "the same error".
local function stripLocation(message: any): string
	local text = tostring(message)
	return (string.gsub(text, "^[%w%._:%- ]-:%d+: ", ""))
end

local function call(fn: (...any) -> ...any, args: { any }, count: number): (boolean, { any })
	local packed = table.pack(pcall(fn, table.unpack(args, 1, count)))
	local ok = packed[1]
	local rest: { any } = table.create(packed.n - 1)
	for index = 2, packed.n do
		rest[index - 1] = packed[index]
	end
	(rest :: any).n = packed.n - 1
	return ok, rest
end

-- What to swap an argument for to see whether both versions refuse it the same way.
type Probe = { label: string, value: any }

local function probesFor(value: any): { Probe }
	local kind = typeof(value)
	local out: { Probe } = { { label = "nil", value = nil } }
	if kind == "number" then
		table.insert(out, { label = "string instead of number", value = tostring(value) })
		table.insert(out, { label = "negative", value = -math.abs(value) - 1 })
		table.insert(out, { label = "nan", value = 0 / 0 })
	elseif kind == "string" then
		table.insert(out, { label = "number instead of string", value = 7 })
		table.insert(out, { label = "empty string", value = "" })
	elseif kind == "table" then
		table.insert(out, { label = "number instead of table", value = 7 })
		table.insert(out, { label = "empty table", value = {} })
	elseif kind == "Instance" then
		table.insert(out, { label = "string instead of instance", value = value:GetFullName() })
	elseif kind == "boolean" then
		table.insert(out, { label = "number instead of boolean", value = 1 })
	else
		table.insert(out, { label = "number instead of " .. kind, value = 7 })
	end
	return out
end

-- Runs one input through both and records how they disagree, if they do.
local function compareOne(
	old: (...any) -> ...any,
	new: (...any) -> ...any,
	args: { any },
	count: number,
	label: string,
	options: Options,
	tolerance: number,
	mismatches: { Mismatch }
)
	local oldOk, oldOut = call(old, deepCopy(args), count)
	local oldState = if options.state then deepCopy((options.state :: () -> any)()) else nil
	local newOk, newOut = call(new, deepCopy(args), count)
	local newState = if options.state then deepCopy((options.state :: () -> any)()) else nil

	if oldOk ~= newOk then
		table.insert(mismatches, {
			input = label,
			kind = "outcome",
			detail = if oldOk
				then `old returned {describe(oldOut[1])}, new errored: {stripLocation(newOut[1])}`
				else `old errored: {stripLocation(oldOut[1])}, new returned {describe(newOut[1])}`,
		})
		return
	end
	if not oldOk then
		local oldMessage, newMessage = stripLocation(oldOut[1]), stripLocation(newOut[1])
		if oldMessage ~= newMessage then
			table.insert(mismatches, { input = label, kind = "error", detail = `"{oldMessage}" vs "{newMessage}"` })
		end
		return
	end

	local problem = diff(oldOut, newOut, tolerance, "return", {})
	if problem then
		table.insert(mismatches, { input = label, kind = "returns", detail = problem })
		return
	end
	if options.state then
		local stateProblem = diff(oldState, newState, tolerance, "state", {})
		if stateProblem then
			table.insert(mismatches, { input = label, kind = "state", detail = stateProblem })
		end
	end
end

-- `generate(i)` returns the argument list for call i; it's called once per call and the
-- arguments are copied before each version sees them, so a function that mutates its input
-- can't leak that into the other version's run.
function Equiv.Check(
	old: (...any) -> ...any,
	new: (...any) -> ...any,
	generate: (index: number) -> { any },
	options: Options?
): Result
	local settings: Options = options or {}
	local n = settings.n or DEFAULT_N
	local limit = settings.limit or DEFAULT_LIMIT
	local tolerance = settings.tolerance or DEFAULT_TOLERANCE
	local mismatches: { Mismatch } = {}
	local checked = 0
	local probed = 0

	for index = 1, n do
		if #mismatches >= limit then
			break
		end
		local args = generate(index)
		local count = if type(args) == "table" then (args :: any).n or #args else 0
		compareOne(old, new, args, count, `call {index}`, settings, tolerance, mismatches)
		checked += 1
	end

	if settings.probes ~= false and #mismatches < limit then
		local base = generate(1)
		local count = (base :: any).n or #base
		for position = 1, count do
			for _, probe in probesFor(base[position]) do
				if #mismatches >= limit then
					break
				end
				local args = deepCopy(base)
				args[position] = probe.value
				compareOne(old, new, args, count, `arg {position}: {probe.label}`, settings, tolerance, mismatches)
				probed += 1
			end
		end
		if #mismatches < limit then
			compareOne(old, new, {}, 0, "no arguments", settings, tolerance, mismatches)
			probed += 1
		end
	end

	local lines = {}
	if #mismatches == 0 then
		table.insert(lines, `identical over {checked} inputs and {probed} broken-argument probes`)
	else
		table.insert(lines, `{#mismatches} mismatch(es) over {checked} inputs and {probed} probes:`)
		for _, mismatch in mismatches do
			table.insert(lines, `  [{mismatch.kind}] {mismatch.input}: {mismatch.detail}`)
		end
	end

	return {
		passed = #mismatches == 0,
		checked = checked,
		probed = probed,
		mismatches = mismatches,
		text = table.concat(lines, "\n"),
	}
end

return Equiv
