--!strict

-- Mounts a UI Labs story the way the UI Labs plugin would, into a ScreenGui under StarterGui,
-- and hands back a screenshot_ui picture of it. The story file is the contract: the same module
-- the human opens in UI Labs is what this draws, so there is one source of truth for a component.
--
-- Studio's require cache is per instance, and Rojo syncs an edit into the same instance, so a
-- plain require would keep serving the first version. Modules are loaded from source instead,
-- the way UI Labs' hot reloader does it: every require reached from the story runs fresh, with
-- `script` set and string paths ("./root", "../Make") resolved, so the mount matches the plugin.

local Path = require(script.Parent.Parent.Path)
local ScreenshotUi = require(script.Parent.ScreenshotUi)

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptEditorService = game:GetService("ScriptEditorService")

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
		.. "controls }) and function stories. Every module the story requires is loaded from source "
		.. "(like UI Labs' hot reloader), so a just-synced edit is what runs. ReplicatedStorage.Design "
		.. "is linked when it exists. Unless keep is set, the mount is torn down after the screenshot; with keep "
		.. "the ScreenGui stays as StarterGui.VMCPStory for inspect_style and run_luau probes.",
	inputSchema = {
		type = "object",
		properties = {
			story = {
				type = "string",
				description = "Dotted path to the component module or folder, e.g. StarterPlayer.StarterPlayerScripts.Client.UI.HexStat; its *.story child is mounted. A dotted path can't name the story itself (its name has a dot).",
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

-- "./x", "../x", "@self/x", "@game/x" relative to `module`, the way Luau string requires read.
local function resolvePath(module: ModuleScript, path: string): ModuleScript
	local current: Instance = module.Parent :: Instance
	for _, part in string.split(path, "/") do
		if part == ".." then
			current = current.Parent :: Instance
		elseif part == "@self" then
			current = module
		elseif part == "@game" then
			current = game
		elseif part ~= "." then
			current = current:FindFirstChild(part) or error(`{path}: no "{part}" under {current:GetFullName()}`, 0)
		end
	end
	if not current:IsA("ModuleScript") then
		current = current:FindFirstChild("init")
			or current:FindFirstChild("Init")
			or error(`{path}: {current:GetFullName()} has no init module`, 0)
	end
	return current :: ModuleScript
end

-- One mount's module loader: fresh results, cached for the mount so a module shared by two
-- components (Vide, Make) is one table.
local function newLoader(): (ModuleScript) -> any
	local cache: { [ModuleScript]: any } = {}
	local function load(module: ModuleScript): any
		if cache[module] ~= nil then
			return cache[module]
		end
		local chunk, problem = loadstring(ScriptEditorService:GetEditorSource(module), module:GetFullName())
		if not chunk then
			error(problem, 0)
		end
		local globals: { [string]: any } = {
			script = module,
			require = function(dependency: any)
				local target = if type(dependency) == "string" then resolvePath(module, dependency) else dependency
				if typeof(target) ~= "Instance" or not target:IsA("ModuleScript") then
					error(`{module:GetFullName()}: require of {tostring(dependency)} is not a ModuleScript`, 0)
				end
				return load(target)
			end,
		}
		setfenv(chunk, setmetatable(globals, { __index = getfenv() }) :: any)
		local result = chunk()
		cache[module] = result
		return result
	end
	return load
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

local mounted: { gui: ScreenGui?, cleanup: (() -> ())? } = {}

local function teardown()
	if mounted.cleanup then
		pcall(mounted.cleanup)
	end
	if mounted.gui then
		mounted.gui:Destroy()
	end
	mounted.gui, mounted.cleanup = nil, nil
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

	local container, problem = Path.Resolve(arguments.story)
	if not container then
		return fail(problem :: string)
	end
	local found: ModuleScript? = nil
	for _, child in container:GetChildren() do
		if child:IsA("ModuleScript") and string.match(child.Name, "%.story$") then
			found = child
			break
		end
	end
	if not found then
		return fail(`{container:GetFullName()} has no *.story ModuleScript child`)
	end

	local load = newLoader()
	local okRequire, story = pcall(load, found)
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

	-- The same fresh Design the story got: its Link puts a StyleLink on the gui.
	local design = ReplicatedStorage:FindFirstChild("Design")
	if design and design:IsA("ModuleScript") then
		local okDesign, Design = pcall(load, design)
		if okDesign and type(Design) == "table" and type(Design.Link) == "function" then
			Design.Link(gui)
		end
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
