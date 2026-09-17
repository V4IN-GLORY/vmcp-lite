--!strict

local Players = game:GetService("Players")
local AnimationClipProvider = game:GetService("AnimationClipProvider")

local Anim = require(script.Parent.Parent.Lib.Anim)
local Build = require(script.Parent.Parent.Lib.Build)
local Rig = require(script.Parent.Parent.Lib.Rig)
local Path = require(script.Parent.Parent.Path)

local MAX_FRAMES = 16
local DUMMY_PREFIX = "VMCPRig"

type Result = {
	content: { { type: "text", text: string } },
	isError: boolean?,
	postProcess: { [string]: any }?,
}

local Tool = {}

Tool.Definition = {
	name = "render_anim",
	description = "Draws an animation as a contact sheet: the rig posed at each keyframe, laid out in "
		.. "reading order, one panel per view (four views in a 2x2 grid by default, so one 4k image "
		.. "shows the whole thing). Takes the same per-joint tracks vmcp.Anim.Compile takes, compiles "
		.. "them, and returns a temporary animation id you can play straight away. Nothing in the place "
		.. "moves; poses are computed from the rig's Motor6Ds, and anything welded to the rig (a held "
		.. "tool, accessories) comes along. With no rig given it spawns a classic-coloured R15 or R6 "
		.. `dummy at Workspace.{DUMMY_PREFIX}R15 / R6 and reuses it. Works on any Motor6D rig.`,
	inputSchema = {
		type = "object",
		properties = {
			tracks = {
				type = "object",
				description = "Joint name -> keys. A key is { time, angles = [x, y, z] degrees, easing } or "
					.. '{ time, cframe = [12 CFrame components], easing }. easing is "Style/Direction": '
					.. "CubicV2, Bounce, Elastic, Constant, Linear with In, Out, InOut; it sits on the key it "
					.. "leaves from. Rig joint names: R15 UpperTorso, Head, RightUpperArm, RightLowerArm, "
					.. 'RightHand, RightUpperLeg...; R6 Torso, Head, "Right Arm", "Left Leg"...',
			},
			animationId = {
				type = "string",
				description = "Draw an existing animation (rbxassetid://...) instead of tracks. Its tracks come back in the text.",
			},
			rig = {
				type = "string",
				description = "Dotted path to a rigged model. Defaults to the dummy for rigType.",
			},
			rigType = {
				type = "string",
				enum = { "R15", "R6" },
				description = "Which dummy to spawn when rig isn't given. Defaults to R15.",
			},
			holding = {
				type = "string",
				description = "Dotted path to a Tool or a Model with a Handle, drawn in the rig's right hand "
					.. "the way the engine grips it (RightGripAttachment and Tool.Grip). Nothing is welded.",
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
				description = "Angles, one panel each: front, right, left, back, top, iso, or { yaw, pitch, name }. Defaults to front, right, iso, top.",
				maxItems = 4,
			},
			size = {
				type = "integer",
				description = "Pixels per panel. Defaults to 2048.",
				minimum = 128,
				maximum = 2048,
			},
			loop = { type = "boolean", description = "Sequence loops. Defaults to true." },
			priority = { type = "string", description = "Animation priority name. Defaults to Action." },
			save = {
				type = "string",
				description = "Dotted path to a folder. Puts the KeyframeSequence there (named after `name`), "
					.. "replacing one with the same name, so it can be published with right-click > Save to Roblox.",
			},
			name = { type = "string", description = "Sequence and file name. Defaults to a timestamp." },
		},
	},
	tags = { title = "Render Animation" },
	timeoutMs = 60000,
}

-- Classic noob colours, because a grey dummy is one blob in a blockout render and this makes
-- head, torso, arms and legs tell apart at a glance. Keyed by what the name contains so R6's
-- "Right Arm" and R15's RightUpperArm land the same way.
local YELLOW, BLUE, GREEN = Color3.fromRGB(245, 205, 48), Color3.fromRGB(13, 105, 172), Color3.fromRGB(75, 151, 75)
local function classic(name: string): Color3?
	if string.find(name, "Torso") then
		return BLUE
	end
	if string.find(name, "Leg") or string.find(name, "Foot") then
		return GREEN
	end
	if name == "Head" or string.find(name, "Arm") or string.find(name, "Hand") then
		return YELLOW
	end
	return nil
end

local function dummy(rigType: string): (Model?, string?)
	local name = DUMMY_PREFIX .. rigType
	local existing = workspace:FindFirstChild(name)
	if existing and existing:IsA("Model") then
		return existing, nil
	end
	local kind = if rigType == "R6" then Enum.HumanoidRigType.R6 else Enum.HumanoidRigType.R15
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), kind)
	end)
	if not ok then
		return nil, `couldn't create a dummy ({model}); pass rig = a path to a rigged model instead`
	end
	model.Name = name
	for _, child in model:GetChildren() do
		local color = classic(child.Name)
		if color and child:IsA("BasePart") then
			child.Color = color
		end
	end
	model:PivotTo(CFrame.new(0, 3, 0))
	model.Parent = workspace
	return model, nil
end

local function jointEnds(joint: Instance): (BasePart?, BasePart?)
	if joint:IsA("JointInstance") then
		return joint.Part0, joint.Part1
	end
	if joint:IsA("WeldConstraint") then
		return joint.Part0, joint.Part1
	end
	return nil, nil
end

-- Parts welded onto the rig (accessories, a tool handle, a backpack) and which rig part carries
-- them, followed through chains of welds. Their offset from that part is read off the model as it
-- sits now, so any joint type works and the pose it's in doesn't matter.
type Rider = { part: BasePart, carrier: string, offset: CFrame }

local function riders(rig: Rig.Rig, root: Instance): { Rider }
	local carrierOf: { [BasePart]: string } = {}
	local skeleton: { [Instance]: true } = {}
	for name, node in rig.byName do
		carrierOf[node.part] = name
		if node.motor then
			skeleton[node.motor] = true
		end
	end

	local joints = {}
	for _, descendant in root:GetDescendants() do
		if not skeleton[descendant] and (descendant:IsA("JointInstance") or descendant:IsA("WeldConstraint")) then
			table.insert(joints, descendant)
		end
	end

	local found: { Rider } = {}
	local grew = true
	while grew do
		grew = false
		for _, joint in joints do
			local a, b = jointEnds(joint)
			if not a or not b then
				continue
			end
			for _, pair in { { a, b }, { b, a } } do
				local carrier, rider = pair[1], pair[2]
				local carrierName = carrierOf[carrier]
				if carrierName and not carrierOf[rider] then
					carrierOf[rider] = carrierName
					table.insert(found, {
						part = rider,
						carrier = carrierName,
						offset = carrier.CFrame:Inverse() * rider.CFrame,
					})
					grew = true
				end
			end
		end
	end
	return found
end

-- A tool in the right hand, placed the way Humanoid equips it: the handle sits on the grip
-- attachment, offset by Tool.Grip. Other parts of the tool ride on the handle.
local function held(rig: Rig.Rig, thing: Instance): ({ Rider }?, string?)
	local handle = thing:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		return nil, `{thing:GetFullName()} has no Handle part`
	end
	local gripName, attachment
	for name, node in rig.byName do
		local found = node.part:FindFirstChild("RightGripAttachment")
		if found and found:IsA("Attachment") then
			gripName, attachment = name, found
			break
		end
	end
	if not gripName or not attachment then
		return nil, "the rig has no RightGripAttachment to hold anything with"
	end
	local grip = if thing:IsA("Tool") then thing.Grip else CFrame.identity
	local handleOffset = attachment.CFrame * grip:Inverse()

	local found: { Rider } = { { part = handle, carrier = gripName, offset = handleOffset } }
	for _, descendant in thing:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= handle then
			table.insert(found, {
				part = descendant,
				carrier = gripName,
				offset = handleOffset * handle.CFrame:Inverse() * descendant.CFrame,
			})
		end
	end
	return found, nil
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
	local value = `angles = [{fmt(math.deg(rx))}, {fmt(math.deg(ry))}, {fmt(math.deg(rz))}]`
	if cframe.Position ~= Vector3.zero then
		value ..= ` (+ position {fmt(cframe.X)}, {fmt(cframe.Y)}, {fmt(cframe.Z)})`
	end
	local easing = if key.easing then `, easing = "{key.easing}"` else ""
	return `\{ time = {fmt(key.time)}, {value}{easing} }`
end

-- Every transition Linear reads as robotic; say so once rather than let it ship unnoticed.
local function easingNote(tracks: Anim.Tracks): string?
	local transitions, eased = 0, 0
	for _, keys in tracks do
		for index = 1, #keys - 1 do
			transitions += 1
			local easing = keys[index].easing
			if easing and not string.find(easing, "^Linear") then
				eased += 1
			end
		end
	end
	if transitions >= 2 and eased == 0 then
		return "every transition is Linear. Body motion usually wants CubicV2/InOut (or /Out to snap then settle); Bounce and Elastic for impacts; Constant for a hard cut."
	end
	return nil
end

local function timesOf(tracks: Anim.Tracks): { number }
	local seen: { [number]: true } = {}
	local times = {}
	for _, keys in tracks do
		for _, key in keys do
			if not seen[key.time] then
				seen[key.time] = true
				table.insert(times, key.time)
			end
		end
	end
	table.sort(times)
	return times
end

function Tool.Run(arguments: {
	tracks: Anim.Tracks?,
	animationId: string?,
	rig: string?,
	rigType: string?,
	holding: string?,
	times: { number }?,
	views: { any }?,
	size: number?,
	loop: boolean?,
	priority: string?,
	save: string?,
	name: string?,
}): Result
	local function fail(text: string): Result
		return { content = { { type = "text", text = text } }, isError = true }
	end

	local model: Instance?, problem: string?
	if arguments.rig then
		model, problem = Path.Resolve(arguments.rig)
	else
		model, problem = dummy(arguments.rigType or "R15")
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

	local sequence, built
	sequence, built, problem = Anim.Sequence(model, resolved, { loop = arguments.loop, priority = arguments.priority })
	if not sequence or not built then
		return fail(problem :: string)
	end
	local id
	id, problem = Anim.Register(sequence)
	if not id then
		sequence:Destroy()
		return fail(problem :: string)
	end
	local saved = ""
	if arguments.save then
		local folder
		folder, problem = Path.Resolve(arguments.save)
		if not folder then
			sequence:Destroy()
			return fail(problem :: string)
		end
		sequence.Name = arguments.name or model.Name
		local old = folder:FindFirstChild(sequence.Name)
		if old and old:IsA("KeyframeSequence") then
			old:Destroy()
		end
		sequence.Parent = folder
		saved =
			`\nsaved as {sequence:GetFullName()} -- right-click it in Explorer > Save to Roblox to get a real asset id`
	else
		sequence:Destroy()
	end

	local extras = riders(rig, model)
	if arguments.holding then
		local thing
		thing, problem = Path.Resolve(arguments.holding)
		if not thing then
			return fail(problem :: string)
		end
		local grip
		grip, problem = held(rig, thing)
		if not grip then
			return fail(problem :: string)
		end
		for _, rider in grip do
			table.insert(extras, rider)
		end
	end

	local times: { number } = arguments.times or {}
	if #times == 0 then
		times = timesOf(resolved)
	end
	if #times > MAX_FRAMES then
		return fail(`{#times} frames is too many to read; pass times to pick up to {MAX_FRAMES}`)
	end

	-- The renderer's "front" camera sits on +Z and a character faces -Z, so the rig is turned to
	-- look at it; that also puts its right side towards the "right" camera. Frames step along the
	-- diagonal every preset sees side-on so they never stack, and wrap into rows going down.
	local _, extents = model:GetBoundingBox()
	local columns = math.ceil(math.sqrt(#times))
	local step = Vector3.new(1, 0, -1).Unit * extents.X * 2
	local drop = Vector3.new(0, -extents.Y * 1.3, 0)
	local facing = CFrame.Angles(0, math.pi, 0)
	local parts = {}
	for frame, at in times do
		local column, row = (frame - 1) % columns, (frame - 1) // columns
		local world = pose(rig, at, resolved, CFrame.new(step * column + drop * row) * facing)
		for _, name in rig.order do
			local part = rig.byName[name].part
			if part.Transparency < 1 then
				table.insert(parts, Build.Describe(part, #parts + 1, world[name]))
			end
		end
		for _, rider in extras do
			if rider.part.Transparency < 1 then
				table.insert(parts, Build.Describe(rider.part, #parts + 1, world[rider.carrier] * rider.offset))
			end
		end
	end

	local labels = {}
	for _, at in times do
		table.insert(labels, `t={fmt(at)}`)
	end
	local text = `{model:GetFullName()}: {#times} frame(s) in reading order, {columns} per row: {table.concat(
		labels,
		"  "
	)}\n` .. `id = {id}  length = {fmt(built.length)}  joints = {table.concat(built.joints, ", ")}{saved}`
	local note = easingNote(resolved)
	if note then
		text ..= `\nnote: {note}`
	end
	if decompiled then
		local lines = {}
		for joint, keys in resolved do
			local items = {}
			for _, key in keys do
				table.insert(items, keyText(key))
			end
			table.insert(lines, `{joint} = [{table.concat(items, ", ")}]`)
		end
		table.sort(lines)
		text ..= "\ntracks:\n" .. table.concat(lines, "\n")
	end

	return {
		content = { { type = "text", text = text } },
		postProcess = {
			kind = "scene",
			name = arguments.name,
			size = arguments.size or 2048,
			views = (Build.ResolveViews(arguments.views or { "front", "right", "iso", "top" })),
			badges = false,
			parts = parts,
		},
	}
end

return Tool
