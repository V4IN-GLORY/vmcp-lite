--!strict
--!optimize 2

-- The panel's whole visual system. Two token sheets (one per Studio theme) hold the values;
-- one rule sheet holds the rules and derives from whichever theme is live. Connection state is
-- a single attribute write -- every rule referencing $Signal re-resolves and eases there itself.

local FONT_UI = "rbxasset://fonts/families/BuilderSans.json"
local FONT_MONO = "rbxasset://fonts/families/RobotoMono.json"

-- Theme-independent tokens, copied onto both theme sheets so no derive chain is needed.
local SHARED = {
	Rad = UDim.new(0, 6),
	RadBtn = UDim.new(0, 5),
	FontUI = Font.new(FONT_UI, Enum.FontWeight.Medium),
	FontStrong = Font.new(FONT_UI, Enum.FontWeight.SemiBold),
	FontMono = Font.new(FONT_MONO, Enum.FontWeight.Medium),
	SizeWordmark = 12,
	SizeBody = 13,
	SizeMono = 14,
	SizeMicro = 11,
}

local DARK = {
	Ground = Color3.fromHex("0F1113"),
	Raised = Color3.fromHex("181B1E"),
	HairlineStrong = Color3.fromHex("343A40"),
	Ink = Color3.fromHex("E6E9EC"),
	InkDim = Color3.fromHex("8B949C"),
	InkFaint = Color3.fromHex("7A848C"),
	SignalIdle = Color3.fromHex("5C666E"),
	SignalWork = Color3.fromHex("E0A44A"),
	SignalLive = Color3.fromHex("3ECF8E"),
	SignalFault = Color3.fromHex("FF6B5E"),
}

local LIGHT = {
	Ground = Color3.fromHex("F4F5F6"),
	Raised = Color3.fromHex("FFFFFF"),
	HairlineStrong = Color3.fromHex("CBD1D5"),
	Ink = Color3.fromHex("14171A"),
	InkDim = Color3.fromHex("5C666E"),
	InkFaint = Color3.fromHex("7A848C"),
	SignalIdle = Color3.fromHex("9AA3AA"),
	SignalWork = Color3.fromHex("B77A16"),
	SignalLive = Color3.fromHex("1F9E68"),
	SignalFault = Color3.fromHex("D4362A"),
}

local EASE = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local EASE_FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- Rules are layered: structure loses to role, role loses to interaction state, and a
-- non-interactable control wins over everything.
local BASE, ROLE, STATE, OFF = 0, 10, 20, 30

local Style = {}

local sheets: { style: StyleSheet, dark: StyleSheet, light: StyleSheet }? = nil
local signalName = "Idle"
local dark = true

local function tokenSheet(name: string, palette: { [string]: any }, container: Instance): StyleSheet
	local sheet = Instance.new("StyleSheet")
	sheet.Name = name
	for key, value in palette do
		sheet:SetAttribute(key, value)
	end
	for key, value in SHARED do
		sheet:SetAttribute(key, value)
	end
	sheet.Parent = container
	return sheet
end

-- The sheets live inside the tree they style, so the panel carries its own styling wherever it
-- is mounted and a single Destroy on the root takes the whole thing with it.
local function build(container: Instance)
	local darkSheet = tokenSheet("VmcpDarkTokens", DARK, container)
	local lightSheet = tokenSheet("VmcpLightTokens", LIGHT, container)

	local style = Instance.new("StyleSheet")
	style.Name = "VmcpStyle"
	style.Parent = container
	style:SetDerives({ darkSheet })

	local function rule(selector: string, priority: number, props: { [string]: any }): StyleRule
		local r = Instance.new("StyleRule")
		r.Selector = selector
		r.Priority = priority
		r:SetProperties(props)
		r.Parent = style
		return r
	end

	rule("#VmcpRoot", BASE, { BackgroundColor3 = "$Ground", BorderSizePixel = 0 })

	-- The signal: a full-bleed hairline and a lamp, both carrying the one colour that means state.
	local signalRule = rule("#SignalRule", BASE, { BackgroundColor3 = "$Signal", BorderSizePixel = 0 })
	local lampRule = rule("#Lamp", BASE, { BackgroundColor3 = "$Signal", BorderSizePixel = 0 })
	rule("#Lamp::UICorner", BASE, { CornerRadius = UDim.new(1, 0) })
	signalRule:SetPropertyTransition("BackgroundColor3", EASE)
	lampRule:SetPropertyTransition("BackgroundColor3", EASE)

	-- Type
	rule("#Wordmark", BASE, {
		FontFace = "$FontStrong",
		TextSize = "$SizeWordmark",
		TextColor3 = "$Ink",
		BackgroundTransparency = 1,
	})
	rule("#StatusWord, #StatusLine, .FieldLabel", BASE, {
		FontFace = "$FontUI",
		TextSize = "$SizeMicro",
		TextColor3 = "$InkDim",
		BackgroundTransparency = 1,
	})

	-- Fields. Active = true so the frame reports :Hover for the stroke rule below.
	rule(".Field", ROLE, { BackgroundColor3 = "$Raised", BorderSizePixel = 0 })
	rule(".Field::UICorner", ROLE, { CornerRadius = "$Rad" })
	-- Border mode, not the Contextual default: on a transparent background Contextual outlines the
	-- glyphs instead of the edge.
	local fieldStroke = rule(".Field::UIStroke", ROLE, {
		Color = "$HairlineStrong",
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
	rule(".Field:Hover::UIStroke", STATE, { Color = "$InkFaint" })
	fieldStroke:SetPropertyTransition("Color", EASE_FAST)

	rule("#PortPrefix", BASE, {
		FontFace = "$FontMono",
		TextSize = "$SizeMono",
		TextColor3 = "$InkFaint",
		BackgroundTransparency = 1,
	})
	rule("TextBox", BASE, {
		FontFace = "$FontMono",
		TextSize = "$SizeMono",
		TextColor3 = "$Ink",
		PlaceholderColor3 = "$InkFaint",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
	})

	-- Buttons. Connect is an inverted neutral fill, not a blue -- the only saturated colour on
	-- the panel is the signal, so nothing else competes with it.
	-- Size lives here rather than on the instances: a property set directly on an instance beats
	-- every rule, which would make the @Narrow override below a no-op.
	rule(".Btn", BASE, {
		FontFace = "$FontUI",
		TextSize = "$SizeBody",
		Size = UDim2.new(0, 104, 0, 34),
		BorderSizePixel = 0,
		AutoButtonColor = false,
	})
	rule(".Btn::UICorner", BASE, { CornerRadius = "$RadBtn" })

	local fill = rule(".Fill", ROLE, {
		BackgroundColor3 = "$Ink",
		TextColor3 = "$Ground",
		BackgroundTransparency = 0,
	})
	rule(".Fill:Hover", STATE, { BackgroundTransparency = 0.08 })
	rule(".Fill:Press", STATE, { BackgroundTransparency = 0.2 })
	-- Only the return eases; press-in stays instant so the control feels connected to the click.
	fill:SetPropertyTransition("BackgroundTransparency", EASE_FAST)

	local ghost = rule(".Ghost", ROLE, {
		BackgroundColor3 = "$Raised",
		BackgroundTransparency = 1,
		TextColor3 = "$Ink",
	})
	local ghostStroke = rule(".Ghost::UIStroke", ROLE, {
		Color = "$HairlineStrong",
		Thickness = 1,
		Transparency = 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
	rule(".Ghost:Hover", STATE, { BackgroundTransparency = 0 })
	rule(".Ghost:Press", STATE, { TextColor3 = "$SignalFault" })
	rule(".Ghost:Press::UIStroke", STATE, { Color = "$SignalFault" })
	ghost:SetPropertyTransition("BackgroundTransparency", EASE_FAST)
	ghost:SetPropertyTransition("TextColor3", EASE_FAST)
	ghostStroke:SetPropertyTransition("Color", EASE_FAST)

	-- GuiState has no Disabled, so an off control is Interactable = false and styled here. It goes
	-- fully transparent rather than to a filled slab, so the one live control keeps the weight.
	rule(".Btn:NonInteractable", OFF, {
		BackgroundTransparency = 1,
		TextColor3 = "$InkFaint",
	})
	rule(".Btn:NonInteractable::UIStroke", OFF, { Transparency = 1 })

	rule("#Disclosure", BASE, {
		FontFace = "$FontUI",
		TextSize = "$SizeMicro",
		TextColor3 = "$InkDim",
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		BorderSizePixel = 0,
	})
	local disclosureHover = rule("#Disclosure:Hover", STATE, { TextColor3 = "$Ink" })
	disclosureHover:SetPropertyTransition("TextColor3", EASE_FAST)

	-- The narrow layout is a media query, not a second code path: the button row's UIListLayout
	-- is phantom, so the @Narrow rule simply overrides it.
	rule("#ButtonRow::UIListLayout", BASE, {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	rule("@Narrow::UIListLayout", ROLE, { FillDirection = Enum.FillDirection.Vertical })
	rule("@Narrow >> .Btn", ROLE, { Size = UDim2.new(1, 0, 0, 34) })

	sheets = { style = style, dark = darkSheet, light = lightSheet }
end

local function applySignal()
	local live = sheets
	if not live then
		return
	end
	live.dark:SetAttribute("Signal", DARK["Signal" .. signalName])
	live.light:SetAttribute("Signal", LIGHT["Signal" .. signalName])
end

-- Creates the sheets on first call, then links them to `root` and everything beneath it.
function Style.Attach(root: Instance)
	if not sheets then
		build(root)
	end
	local live = sheets :: any

	local link = Instance.new("StyleLink")
	link.Name = "VmcpStyleLink"
	link.StyleSheet = live.style
	link.Parent = root

	applySignal()
end

-- `name` is one of Idle, Work, Live, Fault.
function Style.SetSignal(name: string)
	if signalName == name then
		return
	end
	signalName = name
	applySignal()
end

function Style.SetTheme(isDark: boolean)
	local live = sheets
	if not live then
		dark = isDark
		return
	end
	if dark == isDark then
		return
	end
	dark = isDark

	live.style:SetDerives({ if isDark then live.dark else live.light })
end

function Style.Destroy()
	local live = sheets
	if not live then
		return
	end
	live.style:Destroy()
	live.dark:Destroy()
	live.light:Destroy()
	sheets = nil
end

return Style
