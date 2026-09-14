--!strict
--!native
--!optimize 2

-- A token stream for Luau source with block structure on top: which function, loop or `if` each
-- token sits inside. Not a parser -- it knows nothing about expressions -- but it's exactly enough
-- to answer "is this call inside a per-frame handler" (Lint) and "where does this function's body
-- start, and which returns are its own" (Instrument) without either of them lexing strings and
-- comments themselves.

local LuauScan = {}

export type Token = {
	kind: "name" | "keyword" | "number" | "string" | "op",
	text: string,
	line: number,
	-- Byte range in the source, inclusive.
	start: number,
	stop: number,
}

export type Block = {
	-- function | loop | if | do | repeat
	kind: string,
	-- Index of the opening token (the `function`, `do`, `if`, `repeat`, or the `while`/`for`).
	open: number,
	-- Index of the closing `end`/`until`, filled in when it's found.
	close: number?,
	-- Functions only: the declared name ("Combat.ResolveHit", "local step", "" for anonymous),
	-- and the signal name when it's the argument of `:Connect(` ("Heartbeat").
	name: string?,
	connect: string?,
	-- Functions only: index of the first token of the body.
	body: number?,
	parent: number?,
}

export type Scan = {
	tokens: { Token },
	blocks: { Block },
	-- blockOf[i] is the index into blocks of the innermost block containing token i, or nil at
	-- top level.
	blockOf: { number? },
}

local KEYWORDS = {}
for _, word in
	{
		"and",
		"break",
		"do",
		"else",
		"elseif",
		"end",
		"false",
		"for",
		"function",
		"if",
		"in",
		"local",
		"nil",
		"not",
		"or",
		"repeat",
		"return",
		"then",
		"true",
		"until",
		"while",
		"continue",
	}
do
	KEYWORDS[word] = true
end

-- Longest first, so `...` beats `..` beats `.`.
local OPS = {
	"...",
	"..=",
	"//=",
	"..",
	"==",
	"~=",
	"<=",
	">=",
	"->",
	"::",
	"+=",
	"-=",
	"*=",
	"/=",
	"%=",
	"^=",
	"//",
	"+",
	"-",
	"*",
	"/",
	"%",
	"^",
	"#",
	"=",
	"<",
	">",
	"(",
	")",
	"{",
	"}",
	"[",
	"]",
	";",
	":",
	",",
	".",
	"?",
	"|",
	"&",
}

local function longBracketLevel(source: string, at: number): number?
	-- `[` then `=`* then `[`
	if string.byte(source, at) ~= 91 then
		return nil
	end
	local index = at + 1
	local level = 0
	while string.byte(source, index) == 61 do
		level += 1
		index += 1
	end
	return if string.byte(source, index) == 91 then level else nil
end

local function closeLongBracket(source: string, from: number, level: number): number
	local pattern = "]" .. string.rep("=", level) .. "]"
	local _, stop = string.find(source, pattern, from, true)
	return stop or #source
end

function LuauScan.Tokenize(source: string): { Token }
	local tokens: { Token } = {}
	local index = 1
	local length = #source
	local line = 1

	local function push(kind: string, start: number, stop: number)
		table.insert(tokens, {
			kind = kind :: any,
			text = string.sub(source, start, stop),
			line = line,
			start = start,
			stop = stop,
		})
	end

	while index <= length do
		local byte = string.byte(source, index)

		if byte == 10 then
			line += 1
			index += 1
			continue
		end
		if byte == 32 or byte == 9 or byte == 13 then
			index += 1
			continue
		end

		-- Comments, line and block. Newlines inside still count.
		if byte == 45 and string.byte(source, index + 1) == 45 then
			local level = longBracketLevel(source, index + 2)
			local stop
			if level then
				stop = closeLongBracket(source, index + 2, level)
			else
				stop = (string.find(source, "\n", index, true) or length + 1) - 1
			end
			for _ in string.gmatch(string.sub(source, index, stop), "\n") do
				line += 1
			end
			index = stop + 1
			continue
		end

		-- Strings: quoted, backtick (interpolated -- treated as opaque), long bracket.
		if byte == 34 or byte == 39 or byte == 96 then
			local quote = byte
			local at = index + 1
			while at <= length do
				local current = string.byte(source, at)
				if current == 92 then
					at += 2
					continue
				end
				if current == quote then
					break
				end
				if current == 10 then
					line += 1
				end
				at += 1
			end
			push("string", index, math.min(at, length))
			index = at + 1
			continue
		end
		local level = longBracketLevel(source, index)
		if level then
			local stop = closeLongBracket(source, index, level)
			for _ in string.gmatch(string.sub(source, index, stop), "\n") do
				line += 1
			end
			push("string", index, stop)
			index = stop + 1
			continue
		end

		-- Names and keywords.
		if (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122) or byte == 95 then
			local _, stop = string.find(source, "^[%w_]+", index)
			local text = string.sub(source, index, stop :: number)
			push(if KEYWORDS[text] then "keyword" else "name", index, stop :: number)
			index = (stop :: number) + 1
			continue
		end

		-- Numbers, loosely: 0x..., 1e-5, 1_000, 3.5
		if
			byte >= 48 and byte <= 57
			or (
				byte == 46
				and (string.byte(source, index + 1) or 0) >= 48
				and (string.byte(source, index + 1) or 0) <= 57
			)
		then
			local _, stop = string.find(source, "^[%w_%.]+", index)
			-- `1e-5`: the sign belongs to the number.
			local tail = string.byte(source, (stop :: number) + 1)
			if (string.match(string.sub(source, index, stop :: number), "[eE]$")) and (tail == 45 or tail == 43) then
				local _, more = string.find(source, "^[%d_]+", (stop :: number) + 2)
				stop = more or (stop :: number) + 1
			end
			push("number", index, stop :: number)
			index = (stop :: number) + 1
			continue
		end

		local matched = false
		for _, op in OPS do
			if string.sub(source, index, index + #op - 1) == op then
				push("op", index, index + #op - 1)
				index += #op
				matched = true
				break
			end
		end
		if not matched then
			-- Something we don't know (unicode in an identifier, say). Skip the byte.
			index += 1
		end
	end

	return tokens
end

-- Tokens after which an `if` is an expression, not a statement.
local EXPRESSION_LEAD = { ["return"] = true, ["and"] = true, ["or"] = true, ["not"] = true, ["in"] = true }
local CLOSERS = { [")"] = true, ["}"] = true, ["]"] = true }

local STATEMENT_START = {
	["local"] = true,
	["if"] = true,
	["for"] = true,
	["while"] = true,
	["return"] = true,
	["do"] = true,
	["repeat"] = true,
	["function"] = true,
	["end"] = true,
	["break"] = true,
	["continue"] = true,
}

-- Where a function body starts, given the index of its `(`. Skips the parameter list and, if
-- there is one, the return type -- which has no terminator of its own, so this reads on until a
-- token that can only be the start of a statement.
local function bodyStart(tokens: { Token }, paren: number): number
	local depth = 0
	local index = paren
	while index <= #tokens do
		local text = tokens[index].text
		if text == "(" then
			depth += 1
		elseif text == ")" then
			depth -= 1
			if depth == 0 then
				break
			end
		end
		index += 1
	end
	index += 1
	local after = tokens[index]
	if not after or after.text ~= ":" then
		return index
	end
	-- A return type. Balance brackets; at depth 0 the body begins at a statement keyword, or at a
	-- name that directly follows something a type can end with.
	index += 1
	depth = 0
	while index <= #tokens do
		local token = tokens[index]
		local text = token.text
		if depth == 0 then
			if token.kind == "keyword" and STATEMENT_START[text] then
				return index
			end
			if token.kind == "name" or text == "(" then
				local previous = tokens[index - 1]
				if
					previous.kind == "name"
					or previous.kind == "number"
					or previous.text == ")"
					or previous.text == "}"
					or previous.text == "]"
					or previous.text == "?"
					or previous.text == ">"
				then
					return index
				end
			end
		end
		if text == "(" or text == "{" or text == "[" or text == "<" then
			depth += 1
		elseif text == ")" or text == "}" or text == "]" or text == ">" then
			depth -= 1
		end
		index += 1
	end
	return index
end

-- The declared name of a function statement, read backwards from its `function` keyword and
-- forwards to its `(`.
local function functionName(tokens: { Token }, at: number): string
	local parts = {}
	local index = at + 1
	while tokens[index] and tokens[index].text ~= "(" do
		table.insert(parts, tokens[index].text)
		index += 1
	end
	local name = table.concat(parts)
	local before = tokens[at - 1]
	if before and before.text == "local" then
		return `local {name}`
	end
	return name
end

-- The signal an anonymous function is connected to, when it's the first argument of `:Connect(`
-- / `:Once(` / `:ConnectParallel(`: the name just before the `:`.
local function connectedTo(tokens: { Token }, at: number): string?
	local paren = tokens[at - 1]
	local method = tokens[at - 2]
	local colon = tokens[at - 3]
	local signal = tokens[at - 4]
	if not (paren and paren.text == "(" and colon and colon.text == ":" and signal) then
		return nil
	end
	if
		method.text == "Connect"
		or method.text == "Once"
		or method.text == "ConnectParallel"
		or method.text == "BindToRenderStep"
	then
		return signal.text
	end
	return nil
end

function LuauScan.Scan(source: string): Scan
	local tokens = LuauScan.Tokenize(source)
	local blocks: { Block } = {}
	local blockOf: { number? } = table.create(#tokens)
	local stack: { number } = {}
	local pendingLoop = false

	local function open(kind: string, index: number): Block
		local block: Block = { kind = kind, open = index, parent = stack[#stack] }
		table.insert(blocks, block)
		table.insert(stack, #blocks)
		return block
	end

	for index, token in tokens do
		blockOf[index] = stack[#stack]
		if token.kind ~= "keyword" then
			continue
		end
		local text = token.text

		if text == "function" then
			local block = open("function", index)
			local next = tokens[index + 1]
			if next and next.text == "(" then
				block.name = ""
				block.connect = connectedTo(tokens, index)
				block.body = bodyStart(tokens, index + 1)
			else
				block.name = functionName(tokens, index)
				local paren = index + 1
				while tokens[paren] and tokens[paren].text ~= "(" do
					paren += 1
				end
				block.body = bodyStart(tokens, paren)
			end
		elseif text == "while" or text == "for" then
			pendingLoop = true
		elseif text == "do" then
			if pendingLoop then
				pendingLoop = false
				open("loop", index)
			else
				open("do", index)
			end
		elseif text == "if" then
			-- `x = if a then b else c` is an expression and has no `end`.
			local previous = tokens[index - 1]
			local expression = previous ~= nil
				and ((previous.kind == "op" and not CLOSERS[previous.text]) or EXPRESSION_LEAD[previous.text])
			if not expression then
				open("if", index)
			end
		elseif text == "repeat" then
			open("repeat", index)
		elseif text == "end" or text == "until" then
			local top = stack[#stack]
			if top then
				blocks[top].close = index
				table.remove(stack)
			end
		end
	end

	return { tokens = tokens, blocks = blocks, blockOf = blockOf }
end

-- The innermost enclosing block of `kind` for token `index`, walking parents.
function LuauScan.Enclosing(scan: Scan, index: number, kind: string): Block?
	local at = scan.blockOf[index]
	while at do
		local block = scan.blocks[at]
		if block.kind == kind then
			return block
		end
		at = block.parent
	end
	return nil
end

return LuauScan
