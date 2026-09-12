--!strict
--!optimize 2

-- Turns a dotted DataModel path like "Workspace.Rig.Torso" into the Instance it names, and says
-- which segment went missing when it can't. Every tool that takes a `root` argument goes through
-- this, so they all fail the same readable way.

local Path = {}

function Path.Resolve(path: string): (Instance?, string?)
	local current: Instance = game
	for segment in string.gmatch(path, "[^%.]+") do
		if current == game then
			if segment == "game" then
				continue
			end
			-- A service that has never been touched isn't a child of game yet, so FindFirstChild
			-- alone would miss half the DataModel.
			local ok, service = pcall(game.GetService, game, segment)
			if ok and service then
				current = service
				continue
			end
		end

		local child = current:FindFirstChild(segment)
		if not child then
			return nil, `no instance at "{path}" -- "{segment}" isn't under {current:GetFullName()}`
		end
		current = child
	end
	return current, nil
end

return Path
