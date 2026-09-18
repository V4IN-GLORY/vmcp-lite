--!strict

-- The three instance builders every component is made of. Sizes are pixels on the 1920x1080
-- design stage; a UIScale on the stage fits it to the viewport. Tags select StyleRules.

local CollectionService = game:GetService("CollectionService")

local Make = {}

local function tag(instance: Instance, tags: { string }?): Instance
	if tags then
		for _, name in tags do
			CollectionService:AddTag(instance, name)
		end
	end
	return instance
end

function Make.Label(
	parent: Instance?,
	text: string,
	x: number,
	y: number,
	w: number,
	h: number,
	size: number,
	tags: { string }?,
	align: Enum.TextXAlignment?
): TextLabel
	local label = Instance.new("TextLabel")
	label.Text = text
	label.Position = UDim2.fromOffset(x, y)
	label.Size = UDim2.fromOffset(w, h)
	label.TextSize = size
	label.TextXAlignment = align or Enum.TextXAlignment.Left
	label.Parent = parent
	tag(label, tags)
	return label
end

function Make.Box(
	parent: Instance?,
	x: number,
	y: number,
	w: number,
	h: number,
	tags: { string }?,
	transparency: number?
): Frame
	local frame = Instance.new("Frame")
	frame.Position = UDim2.fromOffset(x, y)
	frame.Size = UDim2.fromOffset(w, h)
	frame.BackgroundTransparency = transparency or 0
	frame.Parent = parent
	tag(frame, tags)
	return frame
end

function Make.Image(
	parent: Instance?,
	image: string,
	x: number,
	y: number,
	w: number,
	h: number,
	tags: { string }?
): ImageLabel
	local label = Instance.new("ImageLabel")
	label.Image = image
	label.Position = UDim2.fromOffset(x, y)
	label.Size = UDim2.fromOffset(w, h)
	label.Parent = parent
	tag(label, tags)
	return label
end

return Make
