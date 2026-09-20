--!strict

-- STYLE LAYER. Builds the Style Editor's layout under this module: Design.StyleSheet (rules,
-- derives the tokens), Design.TokenSheet (shared tokens as attributes) and
-- Design.Themes.Cyberpunk.<Name> (one sheet per theme, same attribute names). Rojo can't author
-- StyleRule properties, so the sheets are built here on first require. A rerun in another VM
-- adopts the live sheets when they came from this same source and replaces them when they didn't
-- (never stacked). The Style Editor can read and tweak them live.
--
-- Any ScreenGui that wants the theme adds a StyleLink to Design.StyleSheet (Design.Link does it).
-- Structure code only tags instances; every shared colour, font, border, slice and hover
-- treatment lives in RULES below and is referenced as "$Token".

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Design = {}

local JURA = Font.new("rbxasset://fonts/families/Jura.json", Enum.FontWeight.SemiBold)
local JURA_BOLD = Font.new("rbxasset://fonts/families/Jura.json", Enum.FontWeight.Bold)
local MONO = Font.new("rbxasset://fonts/families/BuilderMono.json", Enum.FontWeight.Bold)

-- A 256px plate exported at 4096: 16 image px per stage px, 20px cut corners (4 + 16 in the SVG).
local PLATE_SLICE = Rect.new(384, 384, 3712, 3712)
local PLATE_SCALE = 1 / 16

-- Theme-independent tokens.
local TOKENS: { [string]: any } = {
	Ink = Color3.fromRGB(8, 8, 14),
	PanelBg = Color3.fromRGB(22, 10, 18),
	PanelInset = Color3.fromRGB(12, 8, 16),
	PanelBorder = Color3.fromRGB(120, 34, 44),
	Navy = Color3.fromRGB(24, 22, 52),
	Track = Color3.fromRGB(40, 34, 48),
	SpacingS = 6,
	SpacingM = 12,
	SpacingL = 24,
}

-- Every theme carries the same names; swapping the derive swaps the whole look.
local THEMES: { [string]: { [string]: Color3 } } = {
	Red = {
		Accent = Color3.fromRGB(255, 62, 62),
		Cyan = Color3.fromRGB(70, 230, 255),
		Yellow = Color3.fromRGB(255, 200, 40),
		Green = Color3.fromRGB(80, 240, 120),
		Purple = Color3.fromRGB(180, 70, 240),
		Dim = Color3.fromRGB(150, 60, 66),
	},
	Ice = {
		Accent = Color3.fromRGB(70, 230, 255),
		Cyan = Color3.fromRGB(255, 255, 255),
		Yellow = Color3.fromRGB(255, 220, 120),
		Green = Color3.fromRGB(120, 255, 200),
		Purple = Color3.fromRGB(150, 150, 255),
		Dim = Color3.fromRGB(60, 110, 130),
	},
}

local FAST = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SLOW = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- { selector, properties, priority?, transitions? }. A rule value must never equal the class
-- default (it arrives empty on the client); the client re-sets those few at startup.
local RULES: { { any } } = {
	-- text
	{
		"TextLabel",
		{
			BackgroundTransparency = 1,
			FontFace = JURA,
			TextColor3 = "$Accent",
			TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Left,
		},
	},
	{ "TextLabel.Center", { TextXAlignment = Enum.TextXAlignment.Center }, 1 },
	{ "TextLabel.Right", { TextXAlignment = Enum.TextXAlignment.Right }, 1 },
	{ "TextLabel.Mono", { FontFace = MONO } },
	{ "TextLabel.Bold", { FontFace = JURA_BOLD } },
	{ "TextLabel.Cyan", { TextColor3 = "$Cyan" } },
	{ "TextLabel.Yellow", { TextColor3 = "$Yellow" } },
	{ "TextLabel.Green", { TextColor3 = "$Green" } },
	{ "TextLabel.Purple", { TextColor3 = "$Purple" } },
	{ "TextLabel.Dim", { TextColor3 = "$Dim" } },
	{ "TextLabel.Faint", { TextColor3 = "$Dim", TextTransparency = 0.45, TextSize = 11, FontFace = MONO } },
	{
		"TextLabel.Body",
		{ TextColor3 = "$Cyan", TextSize = 17, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top },
	},
	-- a panel's header: only inside a .Panel, so a stray label can't pick it up
	{ ".Panel > TextLabel.PanelHeader", { TextColor3 = "$Accent", TextSize = 24, FontFace = JURA_BOLD } },
	{ ".Panel.Cyan > TextLabel.PanelHeader", { TextColor3 = "$Cyan" }, 1 },

	-- buttons: tabs and panel buttons, hover/press through state selectors
	{
		"TextButton",
		{
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			FontFace = JURA,
			TextColor3 = "$Dim",
			TextSize = 20,
			BorderSizePixel = 0,
		},
	},
	{ "TextButton.Tab", { TextXAlignment = Enum.TextXAlignment.Left } },
	{ "TextButton.Tab:Hover", { TextColor3 = "$Cyan" }, 1, { TextColor3 = FAST } },
	{ "TextButton.Tab.Active", { TextColor3 = "$Cyan", TextSize = 22 }, 2, { TextColor3 = FAST } },
	{
		".Tab > Frame.Marker",
		{ BackgroundColor3 = "$Cyan", BackgroundTransparency = 1 },
		0,
		{ BackgroundTransparency = SLOW },
	},
	{ ".Tab.Active > Frame.Marker", { BackgroundTransparency = 0.02 }, 2, { BackgroundTransparency = SLOW } },
	{ ".Tab > ImageLabel", { ImageColor3 = "$Dim" } },
	{ ".Tab:Hover > ImageLabel", { ImageColor3 = "$Cyan" }, 1, { ImageColor3 = FAST } },
	{ ".Tab.Active > ImageLabel", { ImageColor3 = "$Cyan" }, 2 },
	{
		".PanelButton > TextLabel.Label",
		{ TextColor3 = "$Cyan", TextSize = 22, FontFace = JURA_BOLD },
		1,
		{ TextColor3 = FAST },
	},
	{ ".PanelButton:Hover > TextLabel.Label", { TextColor3 = Color3.new(1, 1, 1) }, 2, { TextColor3 = FAST } },
	{ ".PanelButton:Press > TextLabel.Label", { TextSize = 21 }, 3 },
	{
		".PanelButton > ImageLabel.PlateFill",
		{ ImageColor3 = "$PanelBg", ImageTransparency = 0.2 },
		0,
		{ ImageColor3 = FAST },
	},
	{ ".PanelButton:Hover > ImageLabel.PlateFill", { ImageColor3 = "$PanelBorder" }, 1, { ImageColor3 = FAST } },
	{
		".PanelButton:Press > ImageLabel.PlateFill",
		{ ImageColor3 = "$Accent", ImageTransparency = 0.5 },
		2,
		{ ImageColor3 = FAST },
	},
	{ ".PanelButton > ImageLabel.PlateEdge", { ImageColor3 = "$PanelBorder" }, 0, { ImageColor3 = FAST } },
	{ ".PanelButton:Hover > ImageLabel.PlateEdge", { ImageColor3 = "$Accent" }, 1, { ImageColor3 = FAST } },
	-- category rows (stats page) and weapon cards: hover lifts the plate
	{ "TextButton.Row", { TextColor3 = "$Cyan", TextSize = 20 } },
	{ "TextButton.Row:Hover", { TextColor3 = Color3.new(1, 1, 1) }, 1, { TextColor3 = FAST } },
	{
		".Row > Frame.RowPlate",
		{ BackgroundColor3 = "$PanelInset", BackgroundTransparency = 0.2 },
		0,
		{ BackgroundColor3 = FAST },
	},
	{ ".Row:Hover > Frame.RowPlate", { BackgroundColor3 = "$Navy" }, 1, { BackgroundColor3 = FAST } },
	{ ".Row.Active > Frame.RowPlate", { BackgroundColor3 = "$Navy" }, 2 },
	{ ".Row.Active > Frame.RowPlate::UIStroke", { Color = "$Accent", Thickness = 2 } },
	{ ".Row > Frame.RowMark", { BackgroundColor3 = "$Dim" }, 0, { BackgroundColor3 = FAST } },
	{ ".Row:Hover > Frame.RowMark", { BackgroundColor3 = "$Cyan" }, 1, { BackgroundColor3 = FAST } },
	{ ".Row.Active > Frame.RowMark", { BackgroundColor3 = "$Accent" }, 2 },

	-- images: icons tinted by tag, plates 9-sliced
	{
		"ImageLabel",
		{ BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, ImageColor3 = "$Accent", BorderSizePixel = 0 },
	},
	{ "ImageLabel.Cyan", { ImageColor3 = "$Cyan" } },
	{ "ImageLabel.Yellow", { ImageColor3 = "$Yellow" } },
	{ "ImageLabel.Green", { ImageColor3 = "$Green" } },
	{ "ImageLabel.Purple", { ImageColor3 = "$Purple" } },
	{ "ImageLabel.Dim", { ImageColor3 = "$Dim" } },
	{ "ImageLabel.White", { ImageColor3 = Color3.new(1, 1, 1) } },
	{
		"ImageLabel.PlateFill",
		{
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = PLATE_SLICE,
			SliceScale = PLATE_SCALE,
			ImageColor3 = "$PanelBg",
			ImageTransparency = 0.18,
		},
	},
	{ "ImageLabel.PlateFill.Inset", { ImageColor3 = "$PanelInset", ImageTransparency = 0.1 }, 1 },
	{
		"ImageLabel.PlateEdge",
		{
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = PLATE_SLICE,
			SliceScale = PLATE_SCALE,
			ImageColor3 = "$PanelBorder",
		},
		0,
		{ ImageColor3 = SLOW },
	},
	{ "ImageLabel.PlateEdge.Cyan", { ImageColor3 = "$Cyan", ImageTransparency = 0.35 }, 1 },
	{ ".Panel:Hover > ImageLabel.PlateEdge", { ImageColor3 = "$Accent" }, 2, { ImageColor3 = SLOW } },
	{ "ImageLabel.Bracket", { ImageColor3 = "$Cyan", ImageTransparency = 0.25 } },
	{ ".Panel.Accent >> ImageLabel.Bracket", { ImageColor3 = "$Accent" }, 1 },
	{
		"ImageLabel.Scanlines",
		{
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromOffset(64, 64),
			ImageColor3 = Color3.new(0, 0, 0),
			ImageTransparency = 0.88,
		},
		1,
	},
	{ "ImageLabel.Glow", { ImageColor3 = "$Cyan", ImageTransparency = 0.82 }, 1 },

	-- cyberware / clothing slots are ImageButtons: plate art dim, cyan on hover, sunk on press
	{
		"ImageButton",
		{
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			ScaleType = Enum.ScaleType.Fit,
			ImageColor3 = "$Dim",
			BorderSizePixel = 0,
		},
		0,
		{ ImageColor3 = FAST },
	},
	{ "ImageButton:Hover", { ImageColor3 = "$Cyan" }, 1, { ImageColor3 = FAST } },
	{ "ImageButton:Press", { ImageTransparency = 0.4 }, 2, { ImageTransparency = FAST } },
	{ "ImageButton.Slot > ImageLabel.Item", { ImageColor3 = "$Yellow" } },
	{ "ImageButton.Slot > TextLabel.Empty", { TextColor3 = "$Dim", TextSize = 40, FontFace = MONO } },
	{ "ImageButton.Slot:Hover > TextLabel.Empty", { TextColor3 = "$Cyan" }, 1, { TextColor3 = FAST } },
	{ "ImageButton.Slot > Frame.Quality", { BackgroundColor3 = "$Purple" } },

	-- frames: solid tints, traces, strokes
	{ "Frame", { BorderSizePixel = 0 } },
	{ "Frame.Panel", { BackgroundTransparency = 1 } },
	{ "Frame.Accent", { BackgroundColor3 = "$Accent" } },
	{ "Frame.Cyan", { BackgroundColor3 = "$Cyan" } },
	{ "Frame.Green", { BackgroundColor3 = "$Green" } },
	{ "Frame.Yellow", { BackgroundColor3 = "$Yellow" } },
	{ "Frame.Purple", { BackgroundColor3 = "$Purple" } },
	{ "Frame.Dim", { BackgroundColor3 = "$Dim" } },
	{ "Frame.Ink", { BackgroundColor3 = "$Ink" } },
	{ "Frame.Navy", { BackgroundColor3 = "$Navy" } },
	{ "Frame.Track", { BackgroundColor3 = "$Track" } },
	{ "Frame.Trace", { BackgroundColor3 = "$Accent", BackgroundTransparency = 0.55 } },
	{ "Frame.Trace.Cyan", { BackgroundColor3 = "$Cyan", BackgroundTransparency = 0.5 }, 1 },
	{ "Frame.StatBar", { BackgroundColor3 = "$Track" } },
	{ ".StatBar > Frame.Fill", { BackgroundColor3 = "$Cyan" } },
	{ ".StatBar.Accent > Frame.Fill", { BackgroundColor3 = "$Accent" }, 1 },
	{ ".StatBar.Green > Frame.Fill", { BackgroundColor3 = "$Green" }, 1 },
	{ "Frame.Outline::UIStroke", { Color = "$Cyan", Thickness = 2 } },
	{ "Frame.OutlineAccent::UIStroke", { Color = "$Accent", Thickness = 2 } },
	{ "Frame.OutlineYellow::UIStroke", { Color = "$Yellow", Thickness = 2 } },
	{ "Frame.OutlineNavy::UIStroke", { Color = Color3.fromRGB(70, 66, 130), Thickness = 2 } },
	{ "Frame.OutlineDim::UIStroke", { Color = "$PanelBorder", Thickness = 1 } },
	{ "Frame.Round::UICorner", { CornerRadius = UDim.new(0.5, 0) } },
	{ "Frame.Chip", { BackgroundColor3 = Color3.fromRGB(30, 110, 130) } },
	{ "Frame.Node::UIStroke", { Color = "$Cyan", Thickness = 2, Transparency = 0.3 } },

	-- the viewport: an inset ink well with a cyan hairline, a panel-thickness shadow behind it
	{ "ViewportFrame", { BackgroundColor3 = "$Ink", BackgroundTransparency = 0.15, BorderSizePixel = 0 } },
	{ "#CenterViewport::UIStroke", { Color = "$Cyan", Thickness = 1, Transparency = 0.45 } },
	{ "#CenterViewport >> ImageLabel.Bracket", { ImageColor3 = "$Cyan", ImageTransparency = 0.02 }, 2 },
	{ "Frame.Shadow", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.55 } },
}

local function sheet(name: string, parent: Instance, attributes: { [string]: any }?): StyleSheet
	local s = Instance.new("StyleSheet")
	s.Name = name
	if attributes then
		for key, value in attributes do
			s:SetAttribute(key, value)
		end
	end
	s.Parent = parent
	return s
end

local function derive(from: StyleSheet, to: StyleSheet)
	local d = Instance.new("StyleDerive")
	d.Name = from.Name
	d.StyleSheet = from
	d.Parent = to
end

-- A fingerprint of TOKENS, THEMES and RULES. A live sheet carrying it was built from this same
-- source, so another VM (the client, a UI Labs story environment, the plugin) adopts it instead
-- of building again. Every UI Labs mount runs this module fresh, so this happens a lot.
local SIGNATURE = (function(): number
	local parts = {}
	for key, value in TOKENS do
		table.insert(parts, `{key}={value}`)
	end
	for name, attributes in THEMES do
		for key, value in attributes do
			table.insert(parts, `{name}.{key}={value}`)
		end
	end
	for _, entry in RULES do
		table.insert(parts, `{entry[1]}@{entry[3] or 0}`)
		for key, value in entry[2] do
			table.insert(parts, `{entry[1]}.{key}={value}`)
		end
		if entry[4] then
			for key, value in entry[4] do
				table.insert(parts, `{entry[1]}.{key}~{value}`)
			end
		end
	end
	table.sort(parts)
	local hash = 5381
	for _, part in parts do
		for i = 1, #part do
			hash = (hash * 33 + string.byte(part, i)) % 4294967296
		end
	end
	return hash
end)()

local LINK_TAG = "DesignLink"

local built: { sheet: StyleSheet?, themes: { [string]: StyleSheet } } = { themes = {} }

local function make(): StyleSheet
	local tokens = sheet("TokenSheet", script, TOKENS)
	local themes = Instance.new("Folder")
	themes.Name = "Themes"
	themes.Parent = script
	local group = Instance.new("Folder")
	group.Name = "Cyberpunk"
	group.Parent = themes
	for name, attributes in THEMES do
		built.themes[name] = sheet(name, group, attributes)
	end

	local main = sheet("StyleSheet", script)
	main:SetAttribute("Signature", SIGNATURE)
	derive(tokens, main)
	derive(built.themes.Red, main)
	for _, entry in RULES do
		local selector: string, properties: { [string]: any } = entry[1], entry[2]
		local priority: number?, transitions: { [string]: TweenInfo }? = entry[3], entry[4]
		local rule = Instance.new("StyleRule")
		rule.Name = selector
		rule.Selector = selector
		rule:SetProperties(properties)
		rule.Priority = priority or 0
		if transitions then
			rule:SetPropertyTransitions(transitions)
		end
		assert(rule.SelectorError == "", `{selector}: {rule.SelectorError}`)
		rule.Parent = main
	end
	built.sheet = main
	return main
end

-- The sheets a main sheet was built with: its TokenSheet and its Themes folder, found through
-- its derives so several builds can sit side by side.
local function family(main: StyleSheet): { Instance }
	local members: { Instance } = { main }
	for _, child in main:GetChildren() do
		local target: Instance? = if child:IsA("StyleDerive") then child.StyleSheet else nil
		if target then
			-- the token sheet sits beside main; a theme sits in Themes/Cyberpunk
			table.insert(
				members,
				if target.Parent == script then target else (target.Parent :: Instance).Parent :: Instance
			)
		end
	end
	return members
end

-- Both derives still reach a sheet that carries its tokens; a hand-deleted TokenSheet or theme
-- leaves the rules with "$Cyan" strings nothing resolves ("Unable to cast string to Color3").
local function intact(main: StyleSheet): boolean
	local derives = 0
	for _, child in main:GetChildren() do
		if child:IsA("StyleDerive") then
			local target = child.StyleSheet
			if not target or not (target:GetAttribute("Ink") or target:GetAttribute("Cyan")) then
				return false
			end
			derives += 1
		end
	end
	return derives == 2
end

local function adopt(main: StyleSheet)
	built.sheet = main
	for _, member in family(main) do
		local group = member:FindFirstChild("Cyberpunk")
		if group then
			for name in THEMES do
				built.themes[name] = group:FindFirstChild(name) :: StyleSheet
			end
		end
	end
end

function Design.Build(): StyleSheet
	if built.sheet and built.sheet.Parent == script then
		return built.sheet
	end
	-- A running game builds its own: rule values copied from the edit session into a playtest
	-- arrive lossy (SliceCenter/ScaleType came through broken), and nothing else links here.
	if RunService:IsRunning() then
		for _, child in script:GetChildren() do
			child:Destroy()
		end
		return make()
	end
	-- Edit mode: adopt the live build from this same source. Older builds (a Design edit since)
	-- stay beside the new one -- destroying or renaming a StyleSheet under Team Create reverts it
	-- and every StyleSheet created near it -- and every link moves over.
	for _, child in script:GetChildren() do
		if child:IsA("StyleSheet") and child:GetAttribute("Signature") == SIGNATURE and intact(child) then
			adopt(child)
			return child
		end
	end
	local main = make()
	adopt(main)
	for _, link in CollectionService:GetTagged(LINK_TAG) do
		(link :: StyleLink).StyleSheet = main
	end
	return main
end

-- Links the sheet to `target`'s LayerCollector (UI Labs mounts stories into its own widget with
-- no StyleLink). An existing link is repointed: it may still hold a sheet another VM replaced.
function Design.Link(target: Instance)
	local gui = if target:IsA("LayerCollector") then target else target:FindFirstAncestorWhichIsA("LayerCollector")
	if not gui then
		return
	end
	local link = gui:FindFirstChildOfClass("StyleLink") or Instance.new("StyleLink")
	CollectionService:AddTag(link, LINK_TAG)
	link.Parent = gui -- parent first, then the sheet, or the link never resolves
	link.StyleSheet = Design.Build()
end

-- Swaps which theme sheet the main sheet derives from; every linked GUI restyles at once.
function Design.SetTheme(name: string)
	local main = Design.Build()
	local theme = built.themes[name]
	assert(theme, `no theme "{name}"`)
	for _, child in main:GetChildren() do
		if child:IsA("StyleDerive") then
			local current = child.StyleSheet
			if current and current.Parent == theme.Parent then
				child.StyleSheet = theme
				child.Name = name
			end
		end
	end
end

Design.Themes = THEMES

return Design
