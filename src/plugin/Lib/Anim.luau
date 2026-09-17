--!strict

-- Compiles per-joint tracks into the Keyframe/Pose trees the engine wants, and reads them back.
--
-- The authoring model is "the right arm does this over time". The engine's format is "at t=0.3,
-- here is every joint in the body". The first is how animation is thought about and the second is
-- what has to be written, so the whole job here is the translation between them: union every
-- track's timestamps, fill each keyframe's pose tree from the rig, and interpolate the joints
-- that have no key at that moment.
--
-- Easing is written on the key it leaves *from*, because Pose.EasingStyle describes how to reach
-- the next keyframe's value, not this one's.

local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

local Rig = require(script.Parent.Rig)

local Anim = {}

export type Key = {
	time: number,
	-- Degrees, XYZ, in character space (see cframeOf). `cframe` wins if given.
	angles: { number }?,
	-- Studs, XYZ, in character space: +X right, +Y up, +Z back.
	offset: { number }?,
	-- Raw Motor6D Transform, in the joint's C0 space. What Decompile hands back.
	cframe: (CFrame | { number })?,
	-- "CubicV2/InOut", "Bounce/Out", "Elastic/In", "Constant", "Linear". Applies from this key toward the next.
	easing: string?,
	weight: number?,
}

export type Tracks = { [string]: { Key } }

export type Compiled = {
	id: string,
	length: number,
	joints: { string },
	keyframes: number,
}

-- Motor6D.Transform is applied inside C0, and C0 carries a rotation on many rigs (every R6
-- joint: the shoulders are turned 90 about Y, the root and neck -90 about X). Raw angles there
-- mean "Z swings the arm forward" and "Y lifts the torso backwards", which nobody guesses right.
-- So angles/offset are taken in character space (+X right, +Y up, +Z back, same on every rig)
-- and conjugated by C0's rotation: C0 * T = C0.pos * R * C0.rot, i.e. R acts on the parent's axes
-- at the joint pivot. `cframe` stays raw so a decompiled track round-trips untouched.
local function cframeOf(key: Key, basis: CFrame): CFrame
	local cframe = key.cframe
	if typeof(cframe) == "CFrame" then
		return cframe
	end
	-- Over JSON a CFrame arrives as its 12 components.
	if type(cframe) == "table" and #cframe == 12 then
		return CFrame.new(table.unpack(cframe))
	end
	local angles = key.angles or { 0, 0, 0 }
	local offset = key.offset or { 0, 0, 0 }
	local local_ = CFrame.new(offset[1] or 0, offset[2] or 0, offset[3] or 0)
		* CFrame.Angles(math.rad(angles[1] or 0), math.rad(angles[2] or 0), math.rad(angles[3] or 0))
	return basis:Inverse() * local_ * basis
end

-- nil for anything that isn't a real PoseEasingStyle, so "Quad" is an error, not a silent Linear.
local function easingOf(key: Key): (Enum.PoseEasingStyle?, Enum.PoseEasingDirection?)
	local style, direction = string.match(key.easing or "Linear", "^(%a+)/?(%a*)$")
	local resolved = (Enum.PoseEasingStyle :: any)[style or "Linear"]
	-- In is the engine's default direction, and in Pose terms means slow start, fast finish.
	local towards = (Enum.PoseEasingDirection :: any)[direction ~= "" and direction or "In"]
	return resolved, towards
end

-- The value of one joint at an arbitrary time. Before the first key it holds the first value,
-- after the last it holds the last, and between two it lerps -- so a joint keyed only at the ends
-- still has a sensible pose in every keyframe the other joints introduced.
-- `motor` is the joint the track drives; its C0 rotation is the basis angles/offset are read in.
function Anim.Sample(keys: { Key }, at: number, motor: Motor6D?): CFrame
	if #keys == 0 then
		return CFrame.identity
	end
	local basis = if motor then motor.C0.Rotation else CFrame.identity
	if at <= keys[1].time then
		return cframeOf(keys[1], basis)
	end

	for index = 1, #keys - 1 do
		local from, to = keys[index], keys[index + 1]
		if at >= from.time and at <= to.time then
			local span = to.time - from.time
			local alpha = if span > 0 then (at - from.time) / span else 1
			return cframeOf(from, basis):Lerp(cframeOf(to, basis), alpha)
		end
	end
	return cframeOf(keys[#keys], basis)
end

local function keyAt(keys: { Key }, at: number): Key?
	for _, key in keys do
		if math.abs(key.time - at) < 1e-4 then
			return key
		end
	end
	return nil
end

-- Also returns the union of every track's timestamps, which is the keyframe list: a keyframe
-- holds the whole body, so any joint moving at time t forces a pose for every joint at time t.
local function validate(rig: Rig.Rig, tracks: Tracks): ({ number }, { string }, string?)
	local times: { number } = {}
	local touched: { string } = {}

	for joint, keys in tracks do
		if not rig.byName[joint] then
			return {}, {}, `this rig has no joint named "{joint}". It has:\n{Rig.Describe(rig)}`
		end
		if type(keys) ~= "table" or #keys == 0 then
			return {}, {}, `track "{joint}" has no keys`
		end
		table.insert(touched, joint)

		table.sort(keys, function(a, b)
			return a.time < b.time
		end)
		for _, key in keys do
			if type(key.time) ~= "number" or key.time < 0 then
				return {}, {}, `a key on "{joint}" has no usable time`
			end
			if key.easing and not easingOf(key) then
				return {},
					{},
					`"{key.easing}" isn't an easing; use Linear, Constant, CubicV2, Cubic, Elastic or Bounce, optionally /In /Out /InOut`
			end
			if not table.find(times, key.time) then
				table.insert(times, key.time)
			end
		end
	end

	if #times == 0 then
		return {}, {}, "no tracks, so there's nothing to compile"
	end
	table.sort(times)
	return times, touched, nil
end

export type Options = { priority: string?, loop: boolean? }

-- The KeyframeSequence itself, parented nowhere. Put it in the place to publish it from Studio
-- (right-click > Save to Roblox); Compile registers it for preview instead.
function Anim.Sequence(model: Instance, tracks: Tracks, options: Options?): (KeyframeSequence?, Compiled?, string?)
	local rig, problem = Rig.Build(model)
	if not rig then
		return nil, nil, problem
	end

	local times, joints, bad = validate(rig, tracks)
	if bad then
		return nil, nil, bad
	end

	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = model.Name
	local settings = options or ({} :: Options)
	sequence.Loop = settings.loop ~= false
	local priority = (Enum.AnimationPriority :: any)[settings.priority or "Action"]
	if priority then
		sequence.Priority = priority
	end

	for _, at in times do
		local keyframe = Instance.new("Keyframe")
		keyframe.Time = at

		local pose = Rig.PoseTree(rig, function(joint: string): CFrame?
			local keys = tracks[joint]
			return if keys then Anim.Sample(keys, at, rig.byName[joint].motor) else nil
		end)

		-- Easing and weight are per-pose and only meaningful where the author actually put a key.
		for _, descendant in pose:GetDescendants() do
			local keys = tracks[descendant.Name]
			local key = if keys then keyAt(keys, at) else nil
			if key and descendant:IsA("Pose") then
				local style, direction = easingOf(key)
				if style and direction then
					descendant.EasingStyle, descendant.EasingDirection = style, direction
				end
				if key.weight then
					descendant.Weight = key.weight
				end
			end
		end

		pose.Parent = keyframe
		keyframe.Parent = sequence
	end

	-- KeyframeSequence.Length reads 0 until the sequence is loaded, so the length is the last
	-- keyframe time and nothing else.
	return sequence, { id = "", length = times[#times], joints = joints, keyframes = #times }, nil
end

-- Returns a temporary hash id usable straight away as Animation.AnimationId. Studio only, and
-- nothing is uploaded -- which is what makes previewing an animation a one-call loop.
function Anim.Register(sequence: KeyframeSequence): (string?, string?)
	local ok, id = pcall(function()
		return KeyframeSequenceProvider:RegisterKeyframeSequence(sequence)
	end)
	if not ok then
		return nil, `couldn't register the sequence: {id}`
	end
	return id, nil
end

function Anim.Compile(model: Instance, tracks: Tracks, options: Options?): (Compiled?, string?)
	local sequence, built, problem = Anim.Sequence(model, tracks, options)
	if not sequence or not built then
		return nil, problem
	end
	local id, bad = Anim.Register(sequence)
	sequence:Destroy()
	if not id then
		return nil, bad
	end
	built.id = id
	return built, nil
end

-- The other direction, so an uploaded animation can be pulled down with
-- AnimationClipProvider:GetAnimationClipAsync, edited as tracks, and recompiled for preview
-- without ever going back through the website.
function Anim.Decompile(sequence: KeyframeSequence): Tracks
	local tracks: Tracks = {}
	local keyframes = sequence:GetKeyframes()
	table.sort(keyframes, function(a, b)
		return (a :: Keyframe).Time < (b :: Keyframe).Time
	end)

	for _, item in keyframes do
		local keyframe = item :: Keyframe
		for _, descendant in keyframe:GetDescendants() do
			if not descendant:IsA("Pose") then
				continue
			end
			-- An identity pose is the rest position, which is the same thing as having no key.
			if descendant.CFrame == CFrame.identity then
				continue
			end
			local keys = tracks[descendant.Name] or {}
			tracks[descendant.Name] = keys
			table.insert(keys, {
				time = keyframe.Time,
				cframe = descendant.CFrame,
				easing = `{descendant.EasingStyle.Name}/{descendant.EasingDirection.Name}`,
				weight = if descendant.Weight ~= 1 then descendant.Weight else nil,
			})
		end
	end
	return tracks
end

return Anim
