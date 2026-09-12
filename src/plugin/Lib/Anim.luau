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
	-- Degrees, XYZ. Shorthand for the common case; `cframe` wins if both are given.
	angles: { number }?,
	cframe: CFrame?,
	-- "Cubic/Out", "Quad/InOut", "Linear". Applies from this key toward the next.
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

local function cframeOf(key: Key): CFrame
	if key.cframe then
		return key.cframe
	end
	local angles = key.angles or { 0, 0, 0 }
	return CFrame.Angles(math.rad(angles[1] or 0), math.rad(angles[2] or 0), math.rad(angles[3] or 0))
end

local function easingOf(key: Key): (Enum.PoseEasingStyle, Enum.PoseEasingDirection)
	local style, direction = string.match(key.easing or "Linear", "^(%a+)/?(%a*)$")
	local resolved = (Enum.PoseEasingStyle :: any)[style or "Linear"] or Enum.PoseEasingStyle.Linear
	local towards = (Enum.PoseEasingDirection :: any)[direction ~= "" and direction or "Out"]
	return resolved, towards or Enum.PoseEasingDirection.Out
end

-- The value of one joint at an arbitrary time. Before the first key it holds the first value,
-- after the last it holds the last, and between two it lerps -- so a joint keyed only at the ends
-- still has a sensible pose in every keyframe the other joints introduced.
local function sample(keys: { Key }, at: number): CFrame
	if #keys == 0 then
		return CFrame.identity
	end
	if at <= keys[1].time then
		return cframeOf(keys[1])
	end

	for index = 1, #keys - 1 do
		local from, to = keys[index], keys[index + 1]
		if at >= from.time and at <= to.time then
			local span = to.time - from.time
			local alpha = if span > 0 then (at - from.time) / span else 1
			return cframeOf(from):Lerp(cframeOf(to), alpha)
		end
	end
	return cframeOf(keys[#keys])
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

-- Returns a temporary hash id usable straight away as Animation.AnimationId. Studio only, and
-- nothing is uploaded -- which is what makes previewing an animation a one-call loop.
function Anim.Compile(
	model: Instance,
	tracks: Tracks,
	options: { priority: string?, loop: boolean? }?
): (Compiled?, string?)
	local rig, problem = Rig.Build(model)
	if not rig then
		return nil, problem
	end

	local times, joints, bad = validate(rig, tracks)
	if bad then
		return nil, bad
	end

	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = model.Name
	local settings = options or ({} :: { priority: string?, loop: boolean? })
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
			return if keys then sample(keys, at) else nil
		end)

		-- Easing and weight are per-pose and only meaningful where the author actually put a key.
		for _, descendant in pose:GetDescendants() do
			local keys = tracks[descendant.Name]
			local key = if keys then keyAt(keys, at) else nil
			if key and descendant:IsA("Pose") then
				descendant.EasingStyle, descendant.EasingDirection = easingOf(key)
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
	local length = times[#times]
	local ok, id = pcall(function()
		return KeyframeSequenceProvider:RegisterKeyframeSequence(sequence)
	end)
	sequence:Destroy()
	if not ok then
		return nil, `couldn't register the sequence: {id}`
	end

	return { id = id, length = length, joints = joints, keyframes = #times }, nil
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
