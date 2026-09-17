--!strict

local Players = game:GetService("Players")
local AnimationClipProvider = game:GetService("AnimationClipProvider")

local Anim = require(script.Parent.Parent.Lib.Anim)
local Build = require(script.Parent.Parent.Lib.Build)
local Rig = require(script.Parent.Parent.Lib.Rig)
local Path = require(script.Parent.Parent.Path)

local MAX_FRAMES = 12
local DUMMY_NAME = "VMCPRig"

type Result = {
	content: { { type: "text", text: string } },
	isError: boolean?,
	postProcess: { [string]: any }?,
}

local Tool = {}

Tool.Definition = {
	name = "render_anim",
	description = "Draws an animation as a filmstrip: the rig posed at each keyframe, left to right, "
		.. "one panel per view, rendered by the VMCP server with no playtest. Takes the same per-joint "
		.. "tracks vmcp.Anim.Compile takes, compiles them too, and returns a temporary animation id "
		.. "you can play straight away. Nothing in the place moves; the poses are computed from the "
		.. "rig's Motor6Ds. With no rig given it spawns a classic-coloured R15 dummy at "
		.. `Workspace.{DUMMY_NAME} and reuses it after that.`,
	inputSchema = {
		type = "object",
		properties = {
			tracks = {
				type = "object",
				description = 'Joint name -> keys. A key is { time, angles = [x, y, z] degrees, easing = "Cubic/Out" } '
					.. "or { time, cframe = [12 CFrame components] }. Easing sits on the key it leaves from.",
			},
			animationId = {
				type = "string",
				description = "Draw an existing animation (rbxassetid://...) instead of tracks. Its tracks come back in the text.",
			},
			rig = {
				type = "string",
				description = `Dotted path to a rigged model. Defaults to Workspace.{DUMMY_NAME}, created if missing.`,
			},
			times = {
				type = "array",
				items = { type = "number" },
				description = `Seconds to sample at. Defaults to every keyframe time, up to {MAX_FRAMES}.`,
				maxItems = MAX_FRAMES,
			},
			views = {
				type = "array",
				items = { type = { "string", "object" } },
				description = "Angles, one panel each: front, right, left, back, top, iso, or { yaw, pitch, name }. Defaults to front and right.",
				maxItems = 4,
			},
			size = {
				type = "integer",
				description = "Pixels per panel. Defaults to 768.",
				minimum = 128,
				maximum = 1024,
			},
			loop = { type = "boolean", description = "Sequence loops. Defaults to true." },
			priority = { type = "string", description = "Animation priority name. Defaults to Action." },
			name = { type = "string", description = "File name. Defaults to a timestamp." },
		},
	},
	tags = { title = "Render Animation", readOnly = true },
	timeoutMs = 60000,
}

-- Classic noob colours, because a grey dummy is one blob in a blockout render and this makes
-- head, torso, arms and legs tell apart at a glance.
local YELLOW, BLUE, GREEN = Color3.fromRGB(245, 205, 48), Color3.fromRGB(13, 105, 172), Color3.fromRGB(75, 151, 75)
local CLASSIC: { [string]: Color3 } = {
	Head = YELLOW,
	UpperTorso = BLUE,
	LowerTorso = BLUE,
	LeftUpperArm = YELLOW,
	LeftLowerArm = YELLOW,
	LeftHand = YELLOW,
	RightUpperArm = YELLOW,
	RightLowerArm = YELLOW,
	RightHand = YELLOW,
	LeftUpperLeg = GREEN,
	LeftLowerLeg = GREEN,
	LeftFoot = GREEN,
	RightUpperLeg = GREEN,
	RightLowerLeg = GREEN,
	RightFoot = GREEN,
}

local function dummy(): (Model?, string?)
	local existing = workspace:FindFirstChild(DUMMY_NAME)
	if existing and existing:IsA("Model") then
		return existing, nil
	end
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	end)
	if not ok then
		return nil, `couldn't create a dummy ({model}); pass rig = a path to a rigged model instead`
	end
	model.Name = DUMMY_NAME
	for _, child in model:GetChildren() do
		local color = CLASSIC[child.Name]
		if color and child:IsA("BasePart") then
			child.Color = color
		end
	end
	model:PivotTo(CFrame.new(0, 3, 0))
	model.Parent = workspace
	return model, nil
end

-- World CFrame of every rig part with the joint transforms applied, the root placed at `base`.
-- Motor6D: Part1 = Part0 * C0 * Transform * C1^-1, so an identity Transform is the rest pose.
local function pose(rig: Rig.Rig, at: number, tracks: Anim.Tracks, base: CFrame): { [string]: CFrame }
	local world: { [string]: CFrame } = { [rig.root.part.Name] = base }
	local function walk(node: Rig.Node)
		for _, child in node.children do
			local motor = child.motor :: Motor6D
			local keys = tracks[child.part.Name]
			local transform = if keys then Anim.Sample(keys, at) else CFrame.identity
			world[child.part.Name] = world[node.part.Name] * motor.C0 * transform * motor.C1:Inverse()
			walk(child)
		end
	end
	walk(rig.root)
	return world
end

local function fetch(animationId: string): (KeyframeSequence?, string?)
	local ok, clip = pcall(function()
		return AnimationClipProvider:GetAnimationClipAsync(animationId)
	end)
	if not ok then
		return nil, `couldn't load {animationId}: {clip}`
	end
	if not clip:IsA("KeyframeSequence") then
		return nil, `{animationId} is a {clip.ClassName}, not a KeyframeSequence`
	end
	return clip, nil
end

local function fmt(value: number): string
	return string.format("%.3g", value)
end

-- Decompiled keys carry CFrames; written back as angles so they can be edited and sent straight in.
local function keyText(key: Anim.Key): string
	local cframe = key.cframe :: CFrame
	local rx, ry, rz = cframe:ToEulerAnglesXYZ()
	local value = `angles = \{ {fmt(math.deg(rx))}, {fmt(math.deg(ry))}, {fmt(math.deg(rz))} }`
	if cframe.Position ~= Vector3.zero then
		value ..= ` (+ position {fmt(cframe.X)}, {fmt(cframe.Y)}, {fmt(cframe.Z)})`
	end
	local easing = if key.easing and key.easing ~= "Linear/Out" then `, easing = "{key.easing}"` else ""
	return `\{ time = {fmt(key.time)}, {value}{easing} }`
end

function Tool.Run(arguments: {
	tracks: Anim.Tracks?,
	animationId: string?,
	rig: string?,
	times: { number }?,
	views: { any }?,
	size: number?,
	loop: boolean?,
	priority: string?,
	name: string?,
}): Result
	local function fail(text: string): Result
		return { content = { { type = "text", text = text } }, isError = true }
	end

	local model: Instance?, problem: string?
	if arguments.rig then
		model, problem = Path.Resolve(arguments.rig)
	else
		model, problem = dummy()
	end
	if not model then
		return fail(problem :: string)
	end
	if not model:IsA("Model") then
		return fail(`{model:GetFullName()} is a {model.ClassName}, not a Model`)
	end

	local rig
	rig, problem = Rig.Build(model)
	if not rig then
		return fail(problem :: string)
	end

	local tracks = arguments.tracks
	local decompiled = false
	if arguments.animationId then
		local clip
		clip, problem = fetch(arguments.animationId)
		if not clip then
			return fail(problem :: string)
		end
		tracks = Anim.Decompile(clip)
		decompiled = true
	end
	if type(tracks) ~= "table" or next(tracks) == nil then
		return fail("give tracks or an animationId")
	end
	local resolved = tracks :: Anim.Tracks

	local built
	built, problem = Anim.Compile(model, resolved, { loop = arguments.loop, priority = arguments.priority })
	if not built then
		return fail(problem :: string)
	end

	local times: { number } = arguments.times or {}
	if #times == 0 then
		local seen: { [number]: true } = {}
		for _, keys in resolved do
			for _, key in keys do
				if not seen[key.time] then
					seen[key.time] = true
					table.insert(times, key.time)
				end
			end
		end
		table.sort(times)
	end
	if #times > MAX_FRAMES then
		return fail(`{#times} frames is too many to read; pass times to pick up to {MAX_FRAMES}`)
	end

	-- The renderer's "front" camera sits on +Z and a character faces -Z, so the rig is turned to
	-- look at it; that also puts its right side towards the "right" camera. Frames step along the
	-- diagonal every preset sees side-on, so they never stack behind each other.
	local _, extents = model:GetBoundingBox()
	local step = Vector3.new(1, 0, -1).Unit * extents.X * 2
	local facing = CFrame.Angles(0, math.pi, 0)
	local parts = {}
	for frame, at in times do
		local world = pose(rig, at, resolved, CFrame.new(step * (frame - 1)) * facing)
		for _, name in rig.order do
			local part = rig.byName[name].part
			if part.Transparency < 1 then
				table.insert(parts, Build.Describe(part, #parts + 1, world[name]))
			end
		end
	end

	local labels = {}
	for _, at in times do
		table.insert(labels, `t={fmt(at)}`)
	end
	local text = `{model:GetFullName()}: {#times} frame(s) left to right: {table.concat(labels, "  ")}\n`
		.. `id = {built.id}  length = {fmt(built.length)}  joints = {table.concat(built.joints, ", ")}`
	if decompiled then
		local lines = {}
		for joint, keys in resolved do
			local items = {}
			for _, key in keys do
				table.insert(items, keyText(key))
			end
			table.insert(lines, `{joint} = \{ {table.concat(items, ", ")} }`)
		end
		table.sort(lines)
		text ..= "\ntracks:\n" .. table.concat(lines, "\n")
	end

	return {
		content = { { type = "text", text = text } },
		postProcess = {
			kind = "scene",
			name = arguments.name,
			size = arguments.size or 768,
			views = (Build.ResolveViews(arguments.views or { "front", "right" })),
			badges = false,
			parts = parts,
		},
	}
end

return Tool
