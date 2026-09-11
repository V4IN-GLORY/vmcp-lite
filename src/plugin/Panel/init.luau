--!strict
--!optimize 2

-- The panel's instance tree and its styling. There is no protocol, no state machine and no
-- validation in here -- it builds the widgets, styles them, and hands them back for you to wire.
--
--   local root = Panel.Mount(parent)
--
--   Panel.ConnectButton     TextButton
--   Panel.DisconnectButton  TextButton  (starts disabled; set .Interactable)
--   Panel.PortInput         TextBox
--   Panel.TokenInput        TextBox
--   Panel.StatusLine        TextLabel   the sentence under the buttons
--   Panel.StatusWord        TextLabel   the word beside the lamp
--
--   Panel.SetSignal("Idle" | "Work" | "Live" | "Fault")   lamp + hairline colour; Work animates
--   Panel.SetTokenOpen(open)                              the auth-token drawer
--   Panel.SetStatusWord(text)                              the word beside the lamp
--   Panel.SetStatusLine(text)                              the sentence under the buttons
--   Panel.SetConnectEnabled(enabled)                       ConnectButton.Interactable
--   Panel.SetDisconnectEnabled(enabled)                    DisconnectButton.Interactable
--   Panel.Destroy()
--
--   Panel.ConnectRequested      ()             Connect button clicked
--   Panel.DisconnectRequested   ()             Disconnect button clicked
--   Panel.PortChanged           (text: string) PortInput text edited
--   Panel.TokenChanged          (text: string) TokenInput text edited
--
-- Clicking the disclosure row toggles the drawer on its own. Everything else is yours.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Style = require(script.Style)

local ADDRESS_PREFIX = "ws://127.0.0.1:"
local NARROW_WIDTH = 240
local FIELD_H = 32
local PAD = 16

local EASE = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- Filled in by Mount; this is the panel's whole public surface.
local Panel = {
	Root = nil :: any,
	ConnectButton = nil :: any,
	DisconnectButton = nil :: any,
	PortInput = nil :: any,
	TokenInput = nil :: any,
	StatusLine = nil :: any,
	StatusWord = nil :: any,
	ConnectRequested = nil :: any,
	DisconnectRequested = nil :: any,
	PortChanged = nil :: any,
	TokenChanged = nil :: any,
}

Panel._connectRequestedBindable = Instance.new("BindableEvent")
Panel._disconnectRequestedBindable = Instance.new("BindableEvent")
Panel._portChangedBindable = Instance.new("BindableEvent")
Panel._tokenChangedBindable = Instance.new("BindableEvent")
Panel.ConnectRequested = Panel._connectRequestedBindable.Event
Panel.DisconnectRequested = Panel._disconnectRequestedBindable.Event
Panel.PortChanged = Panel._portChangedBindable.Event
Panel.TokenChanged = Panel._tokenChangedBindable.Event

local gradient: UIGradient
local tokenGroup: Frame
local toggleWord: TextLabel
local sweep: RBXScriptConnection? = nil
local tokenOpen = false

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
	local created = new("TextLabel", {
		Name = name,
		Text = text,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 14),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent)
	created:AddTag("FieldLabel")
	return created
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

---------------------------------------------------------------------- presentation

-- The lamp and the hairline share one colour. "Work" is the only one that animates, and the
-- sweep runs for exactly as long as that signal is showing.
function Panel.SetSignal(name: string)
	Style.SetSignal(name)

	local animate = name == "Work"
	gradient.Enabled = animate

	if not animate then
		if sweep then
			sweep:Disconnect()
			sweep = nil
		end
	elseif not sweep then
		sweep = RunService.Heartbeat:Connect(function()
			gradient.Offset = Vector2.new((os.clock() * 0.9) % 2 - 1, 0)
		end)
	end
end

function Panel.SetTokenOpen(open: boolean)
	if tokenOpen == open then
		return
	end
	tokenOpen = open

	TweenService:Create(tokenGroup, EASE, {
		Size = UDim2.new(1, 0, 0, if open then FIELD_H else 0),
	}):Play()
	toggleWord.Text = if open then "Hide" else "Show"

	if not open and Panel.TokenInput:IsFocused() then
		Panel.TokenInput:ReleaseFocus()
	end
end

function Panel.SetStatusWord(text: string)
	Panel.StatusWord.Text = text
end

function Panel.SetStatusLine(text: string)
	Panel.StatusLine.Text = text
end

function Panel.SetConnectEnabled(enabled: boolean)
	Panel.ConnectButton.Interactable = enabled
end

function Panel.SetDisconnectEnabled(enabled: boolean)
	Panel.DisconnectButton.Interactable = enabled
end

---------------------------------------------------------------------- tree

function Panel.Mount(parent: Instance): Frame
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
	Panel.StatusWord = label("StatusWord", "not connected", statusGroup)

	-- the hero: a full-bleed hairline carrying the signal colour
	local signalRule = new("Frame", { Name = "SignalRule", Size = UDim2.new(1, 0, 0, 1) }, root)
	gradient = new("UIGradient", {
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

	Panel.PortInput = new("TextBox", {
		Name = "PortInput",
		Text = "",
		PlaceholderText = "8791",
		Size = UDim2.new(0, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, portField)
	new("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }, Panel.PortInput)

	-- buttons. The StyleQuery stacks them below NARROW_WIDTH; there is no second code path.
	local buttonRow = box("ButtonRow", body, Enum.FillDirection.Horizontal, 8)
	new("StyleQuery", { Name = "Narrow" }, buttonRow):SetConditions({
		MinSize = Vector2.zero,
		MaxSize = Vector2.new(NARROW_WIDTH, math.huge),
	})

	Panel.ConnectButton = button("Connect", "Connect", "Fill", buttonRow)
	new("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }, Panel.ConnectButton)
	Panel.DisconnectButton = button("Disconnect", "Disconnect", "Ghost", buttonRow)
	Panel.DisconnectButton.Interactable = false

	-- footer
	local footer = box("Footer", body, Enum.FillDirection.Vertical, 8)

	Panel.StatusLine = label("StatusLine", "Not connected", footer)
	Panel.StatusLine.Size = UDim2.new(1, 0, 0, 12)
	Panel.StatusLine.AutomaticSize = Enum.AutomaticSize.None
	Panel.StatusLine.TextTruncate = Enum.TextTruncate.AtEnd

	local disclosure = new("TextButton", { Name = "Disclosure", Text = "", Size = UDim2.new(1, 0, 0, 14) }, footer)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, disclosure)
	label("DisclosureLabel", "Auth token", disclosure)
	-- A word, not a caret glyph: it says what clicking does and needs no icon system.
	toggleWord = label("ToggleWord", "Show", disclosure)

	tokenGroup = new("Frame", {
		Name = "TokenGroup",
		Size = UDim2.new(1, 0, 0, 0),
		ClipsDescendants = true,
		BackgroundTransparency = 1,
	}, footer)

	Panel.TokenInput = new("TextBox", {
		Name = "TokenInput",
		Text = "",
		PlaceholderText = "paste the auth token",
		Size = UDim2.new(1, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, field("TokenField", tokenGroup))

	Style.Attach(root)
	disclosure.Activated:Connect(function()
		Panel.SetTokenOpen(not tokenOpen)
	end)

	Panel.ConnectButton.Activated:Connect(function()
		Panel._connectRequestedBindable:Fire()
	end)
	Panel.DisconnectButton.Activated:Connect(function()
		Panel._disconnectRequestedBindable:Fire()
	end)
	Panel.PortInput.FocusLost:Connect(function()
		Panel._portChangedBindable:Fire(Panel.PortInput.Text)
	end)
	Panel.TokenInput.FocusLost:Connect(function()
		Panel._tokenChangedBindable:Fire(Panel.TokenInput.Text)
	end)

	table.clear(orders)
	Panel.SetSignal("Idle")
	Panel.Root = root
	return root
end

function Panel.Destroy()
	Panel.SetSignal("Idle")
	Style.Destroy()
	if Panel.Root then
		Panel.Root:Destroy()
	end
	Panel._connectRequestedBindable:Destroy()
	Panel._disconnectRequestedBindable:Destroy()
	Panel._portChangedBindable:Destroy()
	Panel._tokenChangedBindable:Destroy()
end

return Panel
