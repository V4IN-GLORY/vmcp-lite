--!strict

-- Builds the Style Editor's layout under this module: Design.StyleSheet (rules, derives the
-- tokens), Design.TokenSheet (shared tokens as attributes) and Design.Themes.Cyberpunk.<Name>
-- (one sheet per theme, same attribute names). Rojo can't author StyleRule properties, so the
-- sheets are built here on first require; the Style Editor can then read and tweak them live.
--
-- Any ScreenGui that wants the theme adds a StyleLink to Design.StyleSheet.

local Design = {}

local JURA = Font.new("rbxasset://fonts/families/Jura.json", Enum.FontWeight.SemiBold)
local MONO = Font.new("rbxasset://fonts/families/BuilderMono.json", Enum.FontWeight.Bold)

local TOKENS = {
	Plate = Color3.fromRGB(45, 12, 16),
	Ink = Color3.fromRGB(8, 8, 14),
}

-- Every theme carries the same names; swapping the derive swaps the whole look.
local THEMES: { [string]: { [string]: Color3 } } = {
	Red = {
		Accent = Color3.fromRGB(255, 60, 60),
		Cyan = Color3.fromRGB(70, 230, 255),
		Yellow = Color3.fromRGB(255, 200, 40),
		Green = Color3.fromRGB(80, 240, 120),
		Dim = Color3.fromRGB(150, 60, 66),
	},
	Ice = {
		Accent = Color3.fromRGB(70, 230, 255),
		Cyan = Color3.fromRGB(255, 255, 255),
		Yellow = Color3.fromRGB(255, 220, 120),
		Green = Color3.fromRGB(120, 255, 200),
		Dim = Color3.fromRGB(60, 110, 130),
	},
}

-- selector, properties, optional priority
local RULES: { { any } } = {
	{ "TextLabel", { BackgroundTransparency = 1, FontFace = JURA, TextColor3 = "$Accent", TextSize = 20 } },
	{ "TextLabel.Mono", { FontFace = MONO } },
	{ "TextLabel.Cyan", { TextColor3 = "$Cyan" } },
	{ "TextLabel.Yellow", { TextColor3 = "$Yellow" } },
	{ "TextLabel.Green", { TextColor3 = "$Green" } },
	{ "TextLabel.Dim", { TextColor3 = "$Dim" } },
	{ "TextLabel.Tab", { TextColor3 = "$Dim" } },
	{ "TextLabel.Tab.Active", { TextColor3 = "$Cyan", TextSize = 22 }, 2 },
	{ "ImageLabel", { BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, ImageColor3 = "$Accent" } },
	{ "ImageLabel.Cyan", { ImageColor3 = "$Cyan" } },
	{ "ImageLabel.Yellow", { ImageColor3 = "$Yellow" } },
	{ "ImageLabel.Dim", { ImageColor3 = "$Dim" } },
	{ "Frame", { BorderSizePixel = 0 } },
	{ "Frame.Accent", { BackgroundColor3 = "$Accent" } },
	{ "Frame.Cyan", { BackgroundColor3 = "$Cyan" } },
	{ "Frame.Green", { BackgroundColor3 = "$Green" } },
	{ "Frame.Yellow", { BackgroundColor3 = "$Yellow" } },
	{ "Frame.Trace", { BackgroundColor3 = "$Accent", BackgroundTransparency = 0.55 } },
	{ "Frame.Plate", { BackgroundColor3 = "$Plate", BackgroundTransparency = 0.35 } },
	{ "Frame.Outline::UIStroke", { Color = "$Cyan", Thickness = 2 } },
	{ "Frame.OutlineAccent::UIStroke", { Color = "$Accent", Thickness = 2 } },
	{ "Frame.OutlineYellow::UIStroke", { Color = "$Yellow", Thickness = 2 } },
	{ "Frame.OutlineNavy::UIStroke", { Color = Color3.fromRGB(60, 60, 120), Thickness = 2 } },
	{ "Frame.Round::UICorner", { CornerRadius = UDim.new(0.5, 0) } },
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

local built: { sheet: StyleSheet?, themes: { [string]: StyleSheet } } = { themes = {} }

function Design.Build(): StyleSheet
	if built.sheet then
		return built.sheet
	end

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
	derive(tokens, main)
	derive(built.themes.Red, main)
	for _, entry in RULES do
		local selector: string, properties: { [string]: any }, priority: number? = entry[1], entry[2], entry[3]
		local rule = Instance.new("StyleRule")
		rule.Name = selector
		rule.Selector = selector
		rule:SetProperties(properties)
		rule.Priority = priority or 0
		assert(rule.SelectorError == "", `{selector}: {rule.SelectorError}`)
		rule.Parent = main
	end
	built.sheet = main
	return main
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
