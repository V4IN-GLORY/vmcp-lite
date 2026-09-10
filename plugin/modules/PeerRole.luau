local RunService = game:GetService("RunService")
local function detect()
	if RunService:IsEdit() then
		return "edit"
	end
	if RunService:IsServer() then
		return "server"
	end
	return "client"
end
return {
	detect = detect,
}
