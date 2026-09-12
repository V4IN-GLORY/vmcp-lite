--!strict
--!optimize 2

-- A rolling record of everything Studio logs, hooked once at plugin load.
--
-- This is the part run_luau structurally cannot do: a snippet only ever sees its own output, but
-- the errors worth reading are usually thrown by the place's own scripts, minutes before any tool
-- ran. Buffer.Since also backs run_luau's output capture -- note the cursor, run, read the tail.

local LogService = game:GetService("LogService")

local CAPACITY = 500

export type Entry = {
	cursor: number,
	time: number,
	severity: string,
	text: string,
}

local SEVERITY: { [Enum.MessageType]: string } = {
	[Enum.MessageType.MessageOutput] = "print",
	[Enum.MessageType.MessageInfo] = "info",
	[Enum.MessageType.MessageWarning] = "warn",
	[Enum.MessageType.MessageError] = "error",
}

local Buffer = {
	-- Total entries ever written, so it doubles as a cursor that never repeats.
	written = 0,
}

local entries: { Entry } = table.create(CAPACITY)
local started = false

local function push(messageType: Enum.MessageType, text: string, when: number)
	Buffer.written += 1
	entries[(Buffer.written - 1) % CAPACITY + 1] = {
		cursor = Buffer.written,
		time = when,
		severity = SEVERITY[messageType] or "print",
		text = text,
	}
end

function Buffer.Start()
	if started then
		return
	end
	started = true

	-- MessageOut only fires from here on, so whatever Studio already has scrolls in first.
	for _, item in LogService:GetLogHistory() do
		push(item.messageType, item.message, item.timestamp)
	end
	LogService.MessageOut:Connect(function(text: string, messageType: Enum.MessageType)
		push(messageType, text, os.time())
	end)
end

-- Entries newer than `cursor`, oldest first, plus how many fell off the ring before we got to
-- them -- a caller that asked for a gap it can't have should be able to say so.
function Buffer.Since(cursor: number): ({ Entry }, number)
	local oldest = math.max(Buffer.written - CAPACITY, 0)
	local dropped = math.max(oldest - cursor, 0)

	local out = {}
	for index = math.max(cursor, oldest) + 1, Buffer.written do
		table.insert(out, entries[(index - 1) % CAPACITY + 1])
	end
	return out, dropped
end

return Buffer
