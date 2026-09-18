--!strict

-- Mounts a UI Labs story the way the UI Labs plugin would, into a ScreenGui under StarterGui,
-- and hands back a screenshot_ui picture of it. The story file is the contract: the same module
-- the human opens in UI Labs is what this draws, so there is one source of truth for a component.
--
-- Studio's require cache is per instance, and Rojo syncs an edit into the same instance, so a
-- plain require would keep serving the first version. The story's folder is cloned beside the
-- original for the mount (relative requires still resolve) and destroyed afterwards.

local Path = require(script.Parent.Parent.Path)
local ScreenshotUi = require(script.Parent.ScreenshotUi)

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GUI_NAME = "VMCPStory"
local STYLE_RESOLVE_WAIT = 0.2 -- a StyleLink reads class defaults for a frame after linking

type Result = {
	content: { { type: "text", text: string } },
	isError: boolean?,
	postProcess: { [string]: any }?,
}

local Tool = {}

Tool.Definition = {
	name = "mount_story",
	description = "Mounts a UI Labs story (a *.story ModuleScript) into a ScreenGui under "
		.. "StarterGui with the given control values and returns a screenshot_ui picture of it. "
		.. "Handles Vide stories ({ vide, story, controls }), generic stories ({ render, "
		.. "controls }) and function stories. The story's folder is cloned for the mount so a "
		.. "just-synced edit is what runs. ReplicatedStorage.Design.StyleSheet is linked when it "
		.. "exists. Unless keep is set, the mount is torn down after the screenshot; with keep "
		.. "the ScreenGui stays as StarterGui.VMCPStory for inspect_style and run_luau probes.",
	inputSchema = {
		type = "object",
		properties = {
			story = {
				type = "string",
				description = "Dotted path to the story ModuleScript, e.g. StarterPlayer.StarterPlayerScripts.Client.UI.HexStat.HexStat.story",
			},
			controls = {
				type = "object",
				description = "Control values to override the story's defaults, keyed by control name.",
			},
			size = {
				type = "array",
				items = { type = "number" },
				description = "Target frame size in pixels [w, h]. Defaults to [1280, 720].",
			},
			background = {
				type = "string",
				description = 'Target frame colour as "r,g,b" 0-255. Defaults to the story\'s `background` field, else a dark grey.',
			},
			keep = { type = "boolean", description = "Leave the mount in StarterGui.VMCPStory after the screenshot." },
			scale = {
				type = "number",
				description = "Screenshot scale 0.1-1, passed to screenshot_ui.",
				minimum = 0.1,
				maximum = 1,
			},
		},
		required = { "story" },
	},
	tags = { title = "Mount Story" },
	timeoutMs = 60000,
}

local function fail(text: string): Result
	return { content = { { type = "text", text = text } }, isError = true }
end

-- UI Labs control entries are either a raw default or { EntryType = "Control", ControlValue = default }.
local function controlDefault(entry: any): any
	if type(entry) == "table" and entry.EntryType == "Control" then
		return entry.ControlValue
	end
	return entry
end

local function parseColor(text: string?): Color3?
	if not text then
		return nil
	end
	local r, g, b = string.match(text, "^%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*$")
	if not r then
		return nil
	end
	return Color3.fromRGB(tonumber(r) :: number, tonumber(g) :: number, tonumber(b) :: number)
end

local mounted: { gui: ScreenGui?, clone: Instance?, cleanup: (() -> ())? } = {}

local function teardown()
	if mounted.cleanup then
		pcall(mounted.cleanup)
	end
	if mounted.gui then
		mounted.gui:Destroy()
	end
	if mounted.clone then
		mounted.clone:Destroy()
	end
	mounted.gui, mounted.clone, mounted.cleanup = nil, nil, nil
	local stale = StarterGui:FindFirstChild(GUI_NAME)
	if stale then
		stale:Destroy()
	end
end

-- Runs the story and returns its cleanup. `values` are the resolved control values.
local function mountStory(story: any, target: Frame, values: { [string]: any }): (() -> ())?
	if type(story) == "function" then
		return story(target)
	end
	if type(story) ~= "table" then
		error(`a story module returns a function or a table, not {typeof(story)}`)
	end

	if story.vide then
		local Vide = story.vide
		local sources = {}
		for name, value in values do
			sources[name] = Vide.source(value)
		end
		local props = { target = target, controls = sources }
		local unroot = Vide.root(function()
			local result = story.story(props)
			if typeof(result) == "Instance" then
				result.Parent = target
			end
		end)
		return unroot
	end

	if story.fusion then
		error("Fusion stories aren't supported here; use a Vide, generic or function story")
	end

	local render = story.render or story.story
	if type(render) ~= "function" then
		error("story table needs `story` (Vide) or `render` (generic)")
	end
	local props = {
		target = target,
		controls = values,
		-- Controls never change during a mount, so a subscription has nothing to deliver.
		subscribe = function(): () -> ()
			return function() end
		end,
	}
	local result = render(props)
	if typeof(result) == "Instance" then
		result.Parent = target
		return function()
			result:Destroy()
		end
	end
	return result
end

function Tool.Run(arguments: {
	story: string,
	controls: { [string]: any }?,
	size: { number }?,
	background: string?,
	keep: boolean?,
	scale: number?,
}): Result
	teardown()

	local found, problem = Path.Resolve(arguments.story)
	if not found then
		return fail(problem :: string)
	end
	if not found:IsA("ModuleScript") then
		return fail(`{found:GetFullName()} is a {found.ClassName}, not a ModuleScript`)
	end

	-- Clone the folder the story lives in so this run sees the current source of everything in it.
	local original = found.Parent :: Instance
	local clone = original:Clone()
	clone.Name = original.Name
	clone.Parent = original.Parent
	local storyModule = clone:FindFirstChild(found.Name) :: ModuleScript
	mounted.clone = clone

	local okRequire, story = pcall(require, storyModule)
	if not okRequire then
		teardown()
		return fail(`story failed to load: {story}`)
	end

	local values: { [string]: any } = {}
	if type(story) == "table" and type(story.controls) == "table" then
		for name, entry in story.controls do
			values[name] = controlDefault(entry)
		end
	end
	local overrides: { [string]: any } = arguments.controls or {}
	for name, value in overrides do
		if typeof(values[name]) == "Color3" and type(value) == "string" then
			values[name] = parseColor(value) or values[name]
		else
			values[name] = value
		end
	end

	local size = arguments.size or { 1280, 720 }
	local gui = Instance.new("ScreenGui")
	gui.Name = GUI_NAME
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = StarterGui
	mounted.gui = gui

	local target = Instance.new("Frame")
	target.Name = "Target"
	target.Size = UDim2.fromOffset(size[1], size[2])
	target.AnchorPoint = Vector2.new(0.5, 0.5)
	target.Position = UDim2.fromScale(0.5, 0.5)
	target.BorderSizePixel = 0
	target.BackgroundColor3 = parseColor(arguments.background)
		or (
			if type(story) == "table" and typeof(story.background) == "Color3"
				then story.background
				else Color3.fromRGB(24, 24, 28)
		)
	target.Parent = gui

	-- Design builds its sheets on first require (Rojo can't author StyleRules).
	local design = ReplicatedStorage:FindFirstChild("Design")
	if design and design:IsA("ModuleScript") then
		pcall(require, design)
	end
	local sheet = if design then design:FindFirstChild("StyleSheet") else nil
	if sheet and sheet:IsA("StyleSheet") then
		local link = Instance.new("StyleLink")
		link.Parent = gui
		link.StyleSheet = sheet
	end

	local okMount, cleanupOrError = pcall(mountStory, story, target, values)
	if not okMount then
		teardown()
		return fail(`story errored while mounting: {cleanupOrError}`)
	end
	mounted.cleanup = if type(cleanupOrError) == "function" then cleanupOrError else nil

	task.wait(STYLE_RESOLVE_WAIT)

	local shot = ScreenshotUi.Run({
		root = `StarterGui.{GUI_NAME}`,
		scale = arguments.scale,
		name = `story-{string.gsub(found.Name, "[^%w_-]", "")}`,
	})

	local summary = { `mounted {found:GetFullName()} at {size[1]}x{size[2]}` }
	local names = {}
	for name, value in values do
		table.insert(names, `{name}={tostring(value)}`)
	end
	table.sort(names)
	if #names > 0 then
		table.insert(summary, `controls: {table.concat(names, ", ")}`)
	end
	if arguments.keep then
		table.insert(summary, `kept as StarterGui.{GUI_NAME} -- call mount_story again or run_luau to remove it`)
	else
		teardown()
	end

	local header: { type: "text", text: string } = { type = "text", text = table.concat(summary, "\n") }
	table.insert(shot.content, 1, header)
	return shot
end

return Tool
