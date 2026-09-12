--!strict

-- Derives a rig's pose hierarchy from the Motor6D graph it actually has.
--
-- This exists because of one trap that costs an afternoon every time: a Pose is *named* after a
-- BasePart, but the CFrame on it drives the Motor6D joining that part to its **parent pose's**
-- part. A Pose named LowerTorso drives the motor named Root. So a pose tree that looks sensible
-- but doesn't mirror the real joint graph animates the wrong joints, and nothing errors -- the
-- character just moves wrong.
--
-- Nothing here is hardcoded to a skeleton, so R6, R15 and custom rigs all work the same way.

local Rig = {}

export type Node = {
	part: BasePart,
	-- The motor that moves `part` relative to its parent. nil on the root, which nothing moves.
	motor: Motor6D?,
	children: { Node },
}

export type Rig = {
	root: Node,
	byName: { [string]: Node },
	-- Every part name, parents before children, which is the order a pose tree has to be built in.
	order: { string },
}

local function collect(model: Instance): ({ Motor6D }, { [BasePart]: true })
	local motors: { Motor6D } = {}
	local moved: { [BasePart]: true } = {}
	for _, descendant in model:GetDescendants() do
		if not descendant:IsA("Motor6D") then
			continue
		end
		local child = descendant.Part1
		if descendant.Part0 and child then
			table.insert(motors, descendant)
			moved[child] = true
		end
	end
	return motors, moved
end

-- Walks the Motor6D graph out from the one part nothing else moves. Returns the problem instead
-- of the rig when the graph doesn't describe a single tree, because every later step assumes it.
function Rig.Build(model: Instance): (Rig?, string?)
	local motors, moved = collect(model)
	if #motors == 0 then
		return nil, `{model:GetFullName()} has no Motor6Ds, so there's no rig to read`
	end

	local roots: { BasePart } = {}
	for _, motor in motors do
		local part0 = motor.Part0 :: BasePart
		if not moved[part0] and not table.find(roots, part0) then
			table.insert(roots, part0)
		end
	end
	if #roots == 0 then
		return nil, "every part in this rig is driven by a motor, so the joints form a loop"
	end
	if #roots > 1 then
		local names = {}
		for _, part in roots do
			table.insert(names, part.Name)
		end
		return nil, `this rig has {#roots} unmoved parts ({table.concat(names, ", ")}); it needs exactly one root`
	end

	local byName: { [string]: Node } = {}
	local order: { string } = {}

	local function node(part: BasePart, motor: Motor6D?): Node
		local created: Node = { part = part, motor = motor, children = {} }
		byName[part.Name] = created
		table.insert(order, part.Name)
		return created
	end

	local root = node(roots[1], nil)
	local frontier = { root }
	while #frontier > 0 do
		local current = table.remove(frontier) :: Node
		for _, motor in motors do
			if motor.Part0 ~= current.part then
				continue
			end
			local child = node(motor.Part1 :: BasePart, motor)
			table.insert(current.children, child)
			table.insert(frontier, child)
		end
	end

	if #order < #motors + 1 then
		return nil, `only {#order} of {#motors + 1} parts are reachable from {root.part.Name} -- the rig is in pieces`
	end
	return { root = root, byName = byName, order = order }, nil
end

-- Builds one keyframe's worth of Poses: the same shape as the rig, one Pose per part, named after
-- the part but driving the motor above it. `cframeFor` supplies each joint's transform; anything
-- it has no opinion on stays at identity, which is the joint's rest position.
function Rig.PoseTree(rig: Rig, cframeFor: (partName: string) -> CFrame?): Pose
	local function build(node: Node): Pose
		local pose = Instance.new("Pose")
		pose.Name = node.part.Name
		pose.CFrame = cframeFor(node.part.Name) or CFrame.identity
		for _, child in node.children do
			build(child).Parent = pose
		end
		return pose
	end
	return build(rig.root)
end

-- Names the rig knows, so a typo in a track can be reported as "no such joint" instead of
-- animating nothing and looking like a broken export.
function Rig.Describe(rig: Rig): string
	local lines = {}
	local function walk(node: Node, depth: number)
		local motor = if node.motor then ` via {node.motor.Name}` else " (root)"
		table.insert(lines, `{string.rep("  ", depth)}{node.part.Name}{motor}`)
		for _, child in node.children do
			walk(child, depth + 1)
		end
	end
	walk(rig.root, 0)
	return table.concat(lines, "\n")
end

return Rig
