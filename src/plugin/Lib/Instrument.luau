--!strict
--!optimize 2

-- Puts a debug.profilebegin/profileend scope around every named function in a script, so one
-- capture says which function in a module the time went to -- the engine only ever reports
-- "$Script" on its own.
--
-- The end has to run on every way out, so each `return` that belongs to the function is rewritten
-- as `do debug.profileend() return ... end` (a `return` is always the last statement in its block,
-- so wrapping it in do/end is always legal) and one more profileend goes before the closing `end`
-- for the fall-through case. Errors leave the scope open; the engine closes it when the thread
-- ends, which is fine for a profile and wrong for nothing else.

local LuauScan = require(script.Parent.LuauScan)

local Instrument = {}

local BLOCK_CLOSERS = { ["end"] = true, ["else"] = true, ["elseif"] = true, ["until"] = true, [";"] = true }
local BLOCK_OPENERS = { ["function"] = true, ["if"] = true, ["do"] = true, ["repeat"] = true }

type Edit = { at: number, text: string, sequence: number? }

-- Index of the last token of the return statement starting at `from`. A `function`, `do` or
-- `repeat` inside the expression is balanced so its `end` isn't taken for the block's; an
-- if-expression has no `end` of its own.
local function returnEnd(tokens: { LuauScan.Token }, from: number): number
	local depth = 0
	local index = from + 1
	while index <= #tokens do
		local token = tokens[index]
		local text = token.text
		if token.kind == "keyword" and BLOCK_OPENERS[text] then
			-- `if` as an expression has no `end`; only a `function`, `do` or `repeat` opens here.
			if text ~= "if" then
				depth += 1
			end
		elseif depth > 0 and (text == "end" or text == "until") then
			depth -= 1
		elseif depth == 0 and BLOCK_CLOSERS[text] then
			return index - 1
		end
		index += 1
	end
	return #tokens
end

-- Rewrites `source` and returns it with the list of labels it introduced. Anonymous functions
-- (event handlers, callbacks) are skipped: they have no name to label, and a name is the point.
function Instrument.Functions(source: string, prefix: string): (string, { string })
	local scan = LuauScan.Scan(source)
	local tokens = scan.tokens
	local edits: { Edit } = {}
	local labels: { string } = {}
	local functionOf: { [number]: number } = {}

	for blockIndex, block in scan.blocks do
		if block.kind ~= "function" or not block.close or not block.body or block.name == "" then
			continue
		end
		local name = (block.name :: string):gsub("^local ", "")
		local label = `{prefix}.{name}`
		table.insert(labels, label)
		functionOf[blockIndex] = #labels

		local bodyToken = tokens[block.body :: number]
		local closeToken = tokens[block.close :: number]
		table.insert(edits, { at = bodyToken.start, text = `debug.profilebegin({string.format("%q", label)}) ` })
		table.insert(edits, { at = closeToken.start, text = "debug.profileend() " })
	end

	for index, token in tokens do
		if token.text ~= "return" or token.kind ~= "keyword" then
			continue
		end
		local owner = LuauScan.Enclosing(scan, index, "function")
		if not owner then
			continue
		end
		local ownerIndex = table.find(scan.blocks, owner) :: number
		if not functionOf[ownerIndex] then
			continue
		end
		local last = returnEnd(tokens, index)
		table.insert(edits, { at = token.start, text = "do debug.profileend() " })
		table.insert(edits, { at = tokens[last].stop + 1, text = " end" })
	end

	-- Same offset, same order they were added: a begin before an end on an empty body, " end"
	-- before the fall-through profileend when a return sits right at the close.
	for sequence, edit in edits do
		edit.sequence = sequence
	end
	table.sort(edits, function(a, b)
		if a.at ~= b.at then
			return a.at < b.at
		end
		return a.sequence < b.sequence
	end)
	local pieces = {}
	local cursor = 1
	for _, edit in edits do
		table.insert(pieces, string.sub(source, cursor, edit.at - 1))
		table.insert(pieces, edit.text)
		cursor = edit.at
	end
	table.insert(pieces, string.sub(source, cursor))
	local out = table.concat(pieces)
	return out, labels
end

return Instrument
