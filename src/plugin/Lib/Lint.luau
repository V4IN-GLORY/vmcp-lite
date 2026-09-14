--!strict
--!optimize 2

-- Finds the shapes that cost frame time, with the context that makes them cost it: a
-- GetDescendants is a fact, a GetDescendants inside a Heartbeat handler is a finding. Everything
-- here is a token pattern plus "which block is it in", so it's fast and it's shallow -- it hands
-- the profiler a shortlist, it doesn't replace it.

local LuauScan = require(script.Parent.LuauScan)

local Lint = {}

export type Finding = {
	line: number,
	-- high | medium | low
	severity: string,
	pattern: string,
	-- per-frame | hot-event | loop | function | top
	context: string,
	detail: string,
}

local PER_FRAME = {
	Heartbeat = true,
	RenderStepped = true,
	Stepped = true,
	PreRender = true,
	PreSimulation = true,
	PostSimulation = true,
	PreAnimation = true,
	BindToRenderStep = true,
}
local HOT_EVENT = { Touched = true, TouchEnded = true, Changed = true, GetPropertyChangedSignal = true }

local TREE_WALKS =
	{ GetDescendants = true, GetChildren = true, FindFirstChildWhichIsA = true, FindFirstChildOfClass = true }
local ALLOCATORS = { Clone = true }
local PHYSICS_QUERIES = {
	Raycast = true,
	Blockcast = true,
	Spherecast = true,
	Shapecast = true,
	GetPartBoundsInBox = true,
	GetPartBoundsInRadius = true,
	GetPartsInPart = true,
}
local LEGACY = { wait = "wait", spawn = "spawn", delay = "delay" }

-- What the innermost meaningful block around a token is. Loops beat functions because a loop
-- inside a per-frame handler is worse than the handler, and the label says so either way.
local function contextOf(scan: LuauScan.Scan, index: number): (string, string?)
	local at = scan.blockOf[index]
	local sawLoop = false
	local sawFunction = false
	while at do
		local block = scan.blocks[at]
		if block.kind == "loop" or block.kind == "repeat" then
			sawLoop = true
		elseif block.kind == "function" then
			local connect = block.connect
			if connect and PER_FRAME[connect] then
				return "per-frame", connect
			end
			if connect and HOT_EVENT[connect] then
				return "hot-event", connect
			end
			-- A handler wrapped in a named function connected elsewhere isn't traced; the loop
			-- inside a function is still the more useful label.
			if sawLoop then
				return "loop", nil
			end
			-- Keep walking: an anonymous function inside a Heartbeat handler still counts.
			sawFunction = true
			at = block.parent
			continue
		end
		at = block.parent
	end
	return if sawLoop then "loop" elseif sawFunction then "function" else "top", nil
end

local function inFunction(scan: LuauScan.Scan, index: number): boolean
	return LuauScan.Enclosing(scan, index, "function") ~= nil
end

-- Depth of a `game.A.B.C` / `workspace.A.B.C` chain starting at token `index`.
local function pathDepth(tokens: { LuauScan.Token }, index: number): number
	local depth = 0
	local at = index + 1
	while tokens[at] and tokens[at].text == "." and tokens[at + 1] and tokens[at + 1].kind == "name" do
		depth += 1
		at += 2
	end
	return depth
end

local function literalArgs(tokens: { LuauScan.Token }, paren: number): boolean
	local at = paren + 1
	while tokens[at] and tokens[at].text ~= ")" do
		local token = tokens[at]
		if not (token.kind == "number" or token.text == "," or token.text == "-") then
			return false
		end
		at += 1
	end
	return tokens[at] ~= nil
end

function Lint.Script(source: string): { Finding }
	local scan = LuauScan.Scan(source)
	local tokens = scan.tokens
	local findings: { Finding } = {}

	local function add(index: number, severity: string, pattern: string, detail: string)
		local context, signal = contextOf(scan, index)
		table.insert(findings, {
			line = tokens[index].line,
			severity = severity,
			pattern = pattern,
			context = if signal then `{context} ({signal})` else context,
			detail = detail,
		})
	end

	-- Severity for a thing that's bad in proportion to how often it runs.
	local function rate(index: number, whenHot: string, whenLoop: string, otherwise: string?): string?
		local context = contextOf(scan, index)
		if context == "per-frame" or context == "hot-event" then
			return whenHot
		end
		if context == "loop" then
			return whenLoop
		end
		return otherwise
	end

	for index, token in tokens do
		local text = token.text
		local previous = tokens[index - 1]
		local following = tokens[index + 1]
		local method = previous and previous.text == ":"
		local call = following and following.text == "("

		if token.kind == "name" and method and call then
			if TREE_WALKS[text] then
				local severity = rate(index, "high", "high", if inFunction(scan, index) then "low" else nil)
				if severity then
					add(index, severity, "tree walk", `{text}() walks the tree every time this runs`)
				end
			elseif text == "FindFirstChild" then
				-- Recursive form: FindFirstChild(name, true)
				local comma = tokens[index + 3]
				local flag = tokens[index + 4]
				if comma and comma.text == "," and flag and flag.text == "true" then
					local severity = rate(index, "high", "high", "medium")
					add(index, severity :: string, "tree walk", "FindFirstChild(name, true) is a recursive search")
				end
			elseif ALLOCATORS[text] then
				local severity = rate(index, "high", "medium", nil)
				if severity then
					add(index, severity, "allocation", `:{text}() creates instances each time this runs`)
				end
			elseif PHYSICS_QUERIES[text] then
				local severity = rate(index, "medium", "medium", nil)
				if severity then
					add(index, severity, "physics query", `:{text}() per run; check the params filter and MaxParts`)
				end
			elseif text == "FireAllClients" or text == "FireClient" or text == "FireServer" then
				local severity = rate(index, "high", "medium", nil)
				if severity then
					add(index, severity, "network", `:{text}() at this rate is a replication cost every frame`)
				end
			elseif text == "Create" and previous and tokens[index - 2] and tokens[index - 2].text == "TweenService" then
				local severity = rate(index, "medium", "low", nil)
				if severity then
					add(index, severity, "allocation", "TweenService:Create per run; reuse tweens or tween once")
				end
			elseif text == "GetService" then
				local severity = rate(index, "low", "low", nil)
				if severity then
					add(index, severity, "hoist", "GetService inside a hot path; hoist to the top of the script")
				end
			elseif text == "Connect" or text == "ConnectParallel" then
				local severity = rate(index, "high", "medium", nil)
				if severity then
					add(index, severity, "leak", "a new connection made each run; these accumulate")
				end
			end
		elseif token.kind == "name" and text == "new" and previous and previous.text == "." and call then
			local owner = tokens[index - 2]
			if owner and owner.text == "Instance" then
				local severity = rate(index, "high", "medium", nil)
				if severity then
					add(index, severity, "allocation", "Instance.new each time this runs")
				end
			elseif
				owner
				and (
					owner.text == "Vector3"
					or owner.text == "CFrame"
					or owner.text == "Color3"
					or owner.text == "UDim2"
				)
			then
				if literalArgs(tokens, index + 1) then
					local severity = rate(index, "low", "low", nil)
					if severity then
						add(index, severity, "hoist", `{owner.text}.new with constant arguments; build it once outside`)
					end
				end
			end
		elseif
			token.kind == "name"
			and LEGACY[text]
			and call
			and not (previous and (previous.text == "." or previous.text == ":"))
		then
			add(index, "medium", "legacy scheduler", `{text}() -- use task.{LEGACY[text]}`)
		elseif token.kind == "name" and text == "require" and call and inFunction(scan, index) then
			add(index, "low", "hoist", "require inside a function; move it to the top of the script")
		elseif token.kind == "name" and (text == "game" or text == "workspace") and inFunction(scan, index) then
			local depth = pathDepth(tokens, index)
			if depth >= 3 then
				local severity = rate(index, "medium", "medium", "low")
				add(index, severity :: string, "deep path", `{depth}-segment path lookup each run; cache the instance`)
			end
		elseif token.kind == "name" and text == "format" and previous and previous.text == "." then
			local owner = tokens[index - 2]
			if owner and owner.text == "string" and contextOf(scan, index) == "per-frame" then
				add(index, "low", "allocation", "string.format every frame allocates a new string")
			end
		elseif token.kind == "op" and text == ".." then
			local severity = rate(index, "medium", "low", nil)
			if severity then
				add(index, severity, "allocation", "string concat in a hot path; each .. makes a new string")
			end
		elseif token.kind == "name" and text == "pcall" and call then
			local severity = rate(index, "low", "low", nil)
			if severity then
				add(index, severity, "call overhead", "pcall per run; wrap the batch instead of the element")
			end
		elseif token.kind == "keyword" and text == "while" and following and following.text == "true" then
			add(
				index,
				"medium",
				"polling loop",
				"while true do ... wait -- an event would run only when something changes"
			)
		elseif token.kind == "name" and text == "GetPropertyChangedSignal" and call then
			local argument = tokens[index + 2]
			if
				argument
				and (argument.text == '"CFrame"' or argument.text == '"Position"' or argument.text == '"Velocity"')
			then
				add(index, "medium", "hot event", `{argument.text} changes every physics step for a moving part`)
			end
		elseif token.kind == "keyword" and text == "function" and following and following.text == "(" then
			local block = scan.blocks[scan.blockOf[index + 1] :: number]
			if block and block.connect and HOT_EVENT[block.connect] and block.connect ~= "GetPropertyChangedSignal" then
				add(index, "low", "hot event", `{block.connect} handler; fires far more often than it looks`)
			end
		end
	end

	return findings
end

local RANK = { high = 3, medium = 2, low = 1 }

-- Worst first, then by line.
function Lint.Sort(findings: { Finding })
	table.sort(findings, function(a, b)
		local ra, rb = RANK[a.severity], RANK[b.severity]
		if ra ~= rb then
			return ra > rb
		end
		return a.line < b.line
	end)
end

Lint.Rank = RANK

return Lint
