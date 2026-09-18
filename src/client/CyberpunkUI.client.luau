--!strict

-- Mounts the character screen on a 1920x1080 stage scaled to the viewport, themed by
-- ReplicatedStorage.Design. Attribute values live in Vide sources so gameplay can set them and
-- the hexes animate.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Vide = require(ReplicatedStorage.Packages.Vide)
local Design = require(ReplicatedStorage.Design)
local CharacterPanel = require(script.Parent.UI.CharacterPanel)

local STAGE = Vector2.new(1920, 1080)

local gui = Instance.new("ScreenGui")
gui.Name = "CyberpunkUI"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

-- Fills the viewport under the stage. White, so the gradient comes through unmultiplied.
local backdrop = Instance.new("Frame")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = Color3.new(1, 1, 1)
backdrop.BorderSizePixel = 0
backdrop.Parent = gui
local haze = Instance.new("UIGradient")
haze.Rotation = 90
haze.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(70, 18, 26)),
	ColorSequenceKeypoint.new(0.35, Color3.fromRGB(28, 10, 16)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 8, 14)),
})
haze.Parent = backdrop

local stage = Instance.new("Frame")
stage.Name = "Stage"
stage.Size = UDim2.fromOffset(STAGE.X, STAGE.Y)
stage.BackgroundTransparency = 1
stage.Parent = gui
local scale = Instance.new("UIScale")
scale.Parent = stage

-- Scale in 1/20 steps and place on whole pixels, or every 1px line lands on a different half-pixel.
local function fit()
	local viewport = workspace.CurrentCamera.ViewportSize
	local k = math.floor(math.min(viewport.X / STAGE.X, viewport.Y / STAGE.Y) * 20) / 20
	scale.Scale = k
	stage.Position =
		UDim2.fromOffset(math.floor((viewport.X - STAGE.X * k) / 2), math.floor((viewport.Y - STAGE.Y * k) / 2))
end
fit()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

local link = Instance.new("StyleLink")
link.Parent = gui
link.StyleSheet = Design.Build()

local state = {
	levelProgress = Vide.source(0.33),
	credProgress = Vide.source(0.77),
	attributes = {
		reflex = Vide.source(7),
		body = Vide.source(4),
		tech = Vide.source(8),
		int = Vide.source(8),
		cool = Vide.source(6),
	},
}

Vide.root(function()
	local page = CharacterPanel({
		level = 12,
		levelProgress = state.levelProgress,
		credProgress = state.credProgress,
		attributePoints = 0,
		perkPoints = 6,
		attributes = state.attributes,
	})
	page.Parent = stage
end)

-- Exposed so a run_luau probe (vm = game) can set a source and watch the hex count up.
_G.CyberpunkUI = state
