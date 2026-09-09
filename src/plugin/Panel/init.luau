--!strict
--!optimize 2

-- The connect panel: its instance tree, and the mapping from connection state to what you see.
-- It knows nothing about sockets, plugins or settings -- drive it entirely through the API below.
--
--   Panel.Mount(parent, savedPort?, hasToken?) -> Frame
--   Panel.Destroy()
--
-- Out (assign these; all optional):
--   Panel.OnConnect(port)     Connect clicked, or Enter pressed in the port field
--   Panel.OnDisconnect()      Disconnect clicked
--   Panel.OnToken(token)      a token was pasted and committed -- persist it yourself
--
-- In (call this to change what is displayed):
--   Panel.SetState("idle")
--   Panel.SetState("connecting", { phase = "socket" })      or phase = "handshake"
--   Panel.SetState("connected", { tools = 6, revision = 3 })
--   Panel.SetState("fault", { code = 1008 })                also opens the token field
--   Panel.SetState("fault", { code = 1009 | 4000 })
--   Panel.SetState("fault", { retryIn = 4 })                anything else: unreachable
--
-- Close codes come from docs/protocol.md. The panel only displays them; it never retries.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Style = require(script.Style)

local ADDRESS_PREFIX = "ws://127.0.0.1:"
local TOKEN_STORED = "•••••••• stored — paste to replace"
local NARROW_WIDTH = 240
local FIELD_H = 32
local PAD = 16

local EASE = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

export type State = "idle" | "connecting" | "connected" | "fault"
export type Detail = {
	phase: string?, -- "socket" | "handshake", while connecting
	tools: number?,
	revision: number?,
	code: number?, -- WebSocket close code, on a fault
	retryIn: number?,
}

local Panel = {}

-- Assigned by the transport.
Panel.OnConnect = nil :: ((port: number) -> ())?
Panel.OnDisconnect = nil :: (() -> ())?
Panel.OnToken = nil :: ((token: string) -> ())?

local ui: { [string]: any } = {}
local port = 8791
local sweep: RBXScriptConnection? = nil
local state: State = "idle"
local detail: Detail = {}
local tokenOpen = false
local transient = 0

---------------------------------------------------------------------- tree helpers

local orders: { [Instance]: number } = {}

local function new(class: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(class)
	for key, value in props do
		(inst :: any)[key] = value
	end
	-- Siblings lay out in the order they are written below, so nothing hand-numbers LayoutOrder.
	if parent and inst:IsA("GuiObject") then
		local n = (orders[parent] or 0) + 1
		orders[parent] = n
		inst.LayoutOrder = n
	end
	inst.Parent = parent
	return inst
end

-- A transparent auto-height container and its layout. Every group in the panel is one of these.
local function box(name: string, parent: Instance, dir: Enum.FillDirection, gap: number): Frame
	local frame = new("Frame", {
		Name = name,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, parent)
	new("UIListLayout", {
		FillDirection = dir,
		Padding = UDim.new(0, gap),
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, frame)
	return frame
end

local function pad(parent: Instance, x: number, y: number)
	new("UIPadding", {
		PaddingLeft = UDim.new(0, x),
		PaddingRight = UDim.new(0, x),
		PaddingTop = UDim.new(0, y),
		PaddingBottom = UDim.new(0, y),
	}, parent)
end

local function label(name: string, text: string, parent: Instance): TextLabel
	local text_ = new("TextLabel", {
		Name = name,
		Text = text,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 14),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent)
	text_:AddTag("FieldLabel")
	return text_
end

-- A bordered input row. Active so the frame reports :Hover to the stroke rule.
local function field(name: string, parent: Instance): Frame
	local frame = new("Frame", { Name = name, Size = UDim2.new(1, 0, 0, FIELD_H), Active = true }, parent)
	frame:AddTag("Field")
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, frame)
	return frame
end

local function button(name: string, text: string, role: string, parent: Instance): TextButton
	local btn = new("TextButton", { Name = name, Text = text }, parent)
	btn:AddTag("Btn")
	btn:AddTag(role)
	return btn
end

---------------------------------------------------------------------- state to display

-- The status line and the one-word header label, in the protocol's own vocabulary.
local function copyFor(kind: State, info: Detail): (string, string)
	if kind == "idle" then
		return "Not connected", "not connected"
	end

	if kind == "connecting" then
		if info.phase == "handshake" then
			return "Waiting for handshake…", "connecting"
		end
		return "Opening socket…", "connecting"
	end

	if kind == "connected" then
		local tools = info.tools or 0
		local noun = if tools == 1 then "tool" else "tools"
		return string.format("Connected · %d %s · rev %d", tools, noun, info.revision or 0), "connected"
	end

	local code = info.code
	if code == 1008 then
		return "Bad token — paste a new one below.", "error"
	elseif code == 1009 then
		return "Message too large — the last reply passed 8 MB.", "error"
	elseif code == 4000 then
		return "Replaced by another Studio window.", "replaced"
	elseif info.retryIn then
		return string.format("Server not reachable on %d. Retrying in %ds…", port, info.retryIn), "error"
	end
	return string.format("Server not reachable on %d.", port), "error"
end

local SIGNAL: { [string]: string } = {
	idle = "Idle",
	connecting = "Work",
	connected = "Live",
	fault = "Fault",
}

-- The one motion loop, and it runs only while the connection genuinely is in flight.
local function setSweep(on: boolean)
	ui.gradient.Enabled = on

	if not on then
		if sweep then
			sweep:Disconnect()
			sweep = nil
		end
	elseif not sweep then
		sweep = RunService.Heartbeat:Connect(function()
			ui.gradient.Offset = Vector2.new((os.clock() * 0.9) % 2 - 1, 0)
		end)
	end
end

local function setTokenOpen(open: boolean)
	if tokenOpen == open then
		return
	end
	tokenOpen = open

	TweenService:Create(ui.tokenGroup, EASE, {
		Size = UDim2.new(1, 0, 0, if open then FIELD_H else 0),
	}):Play()
	ui.toggleWord.Text = if open then "Hide" else "Show"

	if not open and ui.tokenInput:IsFocused() then
		ui.tokenInput:ReleaseFocus()
	end
end

-- How the transport reports back. Everything visible follows from these two arguments.
function Panel.SetState(kind: State, info: Detail?)
	state, detail = kind, info or {}
	transient = 0

	ui.statusLine.Text, ui.statusWord.Text = copyFor(state, detail)
	Style.SetSignal(SIGNAL[kind])
	setSweep(kind == "connecting")

	-- Connect is off once a connection exists or is being made; Disconnect doubles as cancel.
	local busy = kind == "connecting" or kind == "connected"
	ui.connect.Interactable = not busy
	ui.disconnect.Interactable = busy
	ui.portInput.TextEditable = not busy

	if kind == "fault" and detail.code == 1008 then
		setTokenOpen(true)
	elseif kind == "connected" then
		setTokenOpen(false) -- the reason to show it is gone
	end
end

-- Says something for a few seconds, then falls back to whatever state the panel is actually in.
local function flash(message: string)
	ui.statusLine.Text = message

	local mine = os.clock()
	transient = mine
	task.delay(3, function()
		if transient == mine then
			transient = 0
			ui.statusLine.Text = copyFor(state, detail)
		end
	end)
end

local function commitPort()
	local value = tonumber((ui.portInput.Text:gsub("%D", "")))

	if not value or value == 0 then
		ui.portInput.Text = tostring(port)
		return
	end
	if value > 65535 then
		ui.portInput.Text = tostring(port)
		flash("Ports run 1–65535.")
		return
	end

	port = value
	ui.portInput.Text = tostring(value)
end

---------------------------------------------------------------------- tree

function Panel.Mount(parent: Instance, savedPort: number?, hasToken: boolean?): Frame
	port = savedPort or port

	local root = new("Frame", {
		Name = "VmcpRoot",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, parent)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, root)

	-- header: wordmark left, lamp and one-word status right
	local header = new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 48),
		BackgroundTransparency = 1,
	}, root)
	pad(header, PAD, 0)

	new("TextLabel", {
		Name = "Wordmark",
		Text = "VMCP",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
	}, header)

	local statusGroup = box("StatusGroup", header, Enum.FillDirection.Horizontal, 6)
	statusGroup.AnchorPoint = Vector2.new(1, 0.5)
	statusGroup.Position = UDim2.new(1, 0, 0.5, 0)
	statusGroup.Size = UDim2.fromOffset(0, 16)
	statusGroup.AutomaticSize = Enum.AutomaticSize.X

	new("Frame", { Name = "Lamp", Size = UDim2.fromOffset(8, 8) }, statusGroup)
	ui.statusWord = label("StatusWord", "not connected", statusGroup)

	-- the hero: a full-bleed hairline whose colour is the connection state
	local signalRule = new("Frame", { Name = "SignalRule", Size = UDim2.new(1, 0, 0, 1) }, root)
	ui.gradient = new("UIGradient", {
		Enabled = false,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.7),
			NumberSequenceKeypoint.new(0.42, 0.7),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(0.58, 0.7),
			NumberSequenceKeypoint.new(1, 0.7),
		}),
	}, signalRule)

	local body = box("Body", root, Enum.FillDirection.Vertical, PAD)
	pad(body, PAD, PAD)

	-- port field: spells out the whole address, so the number is never a bare mystery integer
	local portGroup = box("PortGroup", body, Enum.FillDirection.Vertical, 6)
	label("PortLabel", "Bridge port", portGroup).Size = UDim2.new(1, 0, 0, 12)

	local portField = field("PortField", portGroup)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, portField)

	new("TextLabel", {
		Name = "PortPrefix",
		Text = ADDRESS_PREFIX,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
	}, portField)

	ui.portInput = new("TextBox", {
		Name = "PortInput",
		Text = tostring(port),
		PlaceholderText = "8791",
		Size = UDim2.new(0, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, portField)
	new("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }, ui.portInput)

	-- buttons. The StyleQuery stacks them below NARROW_WIDTH; there is no second code path.
	local buttonRow = box("ButtonRow", body, Enum.FillDirection.Horizontal, 8)
	new("StyleQuery", { Name = "Narrow" }, buttonRow):SetConditions({
		MinSize = Vector2.zero,
		MaxSize = Vector2.new(NARROW_WIDTH, math.huge),
	})

	ui.connect = button("Connect", "Connect", "Fill", buttonRow)
	new("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }, ui.connect)
	ui.disconnect = button("Disconnect", "Disconnect", "Ghost", buttonRow)
	ui.disconnect.Interactable = false

	-- footer
	local footer = box("Footer", body, Enum.FillDirection.Vertical, 8)

	ui.statusLine = label("StatusLine", "Not connected", footer)
	ui.statusLine.Size = UDim2.new(1, 0, 0, 12)
	ui.statusLine.AutomaticSize = Enum.AutomaticSize.None
	ui.statusLine.TextTruncate = Enum.TextTruncate.AtEnd

	local disclosure = new("TextButton", { Name = "Disclosure", Text = "", Size = UDim2.new(1, 0, 0, 14) }, footer)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, disclosure)
	label("DisclosureLabel", "Auth token", disclosure)
	-- A word, not a caret glyph: it says what clicking does and needs no icon system.
	ui.toggleWord = label("ToggleWord", "Show", disclosure)

	ui.tokenGroup = new("Frame", {
		Name = "TokenGroup",
		Size = UDim2.new(1, 0, 0, 0),
		ClipsDescendants = true,
		BackgroundTransparency = 1,
	}, footer)

	ui.tokenInput = new("TextBox", {
		Name = "TokenInput",
		Text = "",
		PlaceholderText = if hasToken then TOKEN_STORED else "paste the token from npm run token",
		Size = UDim2.new(1, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, field("TokenField", ui.tokenGroup))

	---------------------------------------------------------------- wiring

	Style.Attach(root)

	ui.portInput:GetPropertyChangedSignal("Text"):Connect(function()
		local digits = ui.portInput.Text:gsub("%D", "")
		if digits ~= ui.portInput.Text then
			ui.portInput.Text = digits
		end
	end)

	ui.portInput.FocusLost:Connect(function(enterPressed: boolean)
		commitPort()
		if enterPressed and ui.connect.Interactable and Panel.OnConnect then
			Panel.OnConnect(port)
		end
	end)

	-- Saves on any focus loss, not just Enter: clicking straight to Connect is the obvious thing
	-- to do after pasting, and silently dropping the token there is how you get a false 1008.
	ui.tokenInput.FocusLost:Connect(function()
		local token = ui.tokenInput.Text:match("^%s*(.-)%s*$") or ""
		if token == "" then
			return
		end
		ui.tokenInput.Text = ""
		ui.tokenInput.PlaceholderText = TOKEN_STORED
		if Panel.OnToken then
			Panel.OnToken(token)
		end
		flash("Token saved.")
	end)

	disclosure.Activated:Connect(function()
		setTokenOpen(not tokenOpen)
	end)

	ui.connect.Activated:Connect(function()
		commitPort()
		if Panel.OnConnect then
			Panel.OnConnect(port)
		end
	end)

	ui.disconnect.Activated:Connect(function()
		if Panel.OnDisconnect then
			Panel.OnDisconnect()
		end
	end)

	table.clear(orders)
	Panel.SetState("idle")
	return root
end

function Panel.Destroy()
	setSweep(false)
	Style.Destroy()
	table.clear(ui)
end

return Panel
