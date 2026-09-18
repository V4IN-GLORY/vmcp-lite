--!strict

-- A cyberware slot: bracketed plate, either an installed item (tinted by rarity, with a
-- quality bar) or a dim "+" when empty, and the cyan base line.

local Assets = require(script.Parent.Assets)
local Make = require(script.Parent.Make)

local SIZE = 105

export type Props = {
	x: number,
	y: number,
	-- item tint when installed; nil for an empty slot
	item: Color3?,
	quality: Color3?,
}

local function CyberwareSlot(props: Props): ImageLabel
	local slot = Make.Image(nil, Assets.slot, props.x, props.y, SIZE, SIZE)
	slot.Name = "Slot"
	if props.item then
		local item = Make.Image(slot, Assets.item, 18, 18, SIZE - 36, SIZE - 36)
		item.ImageColor3 = props.item
		if props.quality then
			Make.Box(slot, 4, 10, 6, SIZE - 20).BackgroundColor3 = props.quality
		end
	else
		Make.Label(slot, "+", 0, 0, SIZE, SIZE, 44, { "Dim" }, Enum.TextXAlignment.Center)
	end
	Make.Box(slot, 8, SIZE - 6, SIZE - 16, 2, { "Cyan" }, 0.6)
	return slot
end

return CyberwareSlot
