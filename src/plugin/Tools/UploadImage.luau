--!strict

-- Publishes a picture as a Roblox Image asset, so a script can use rbxassetid://id at runtime
-- instead of an EditableImage that only exists in this session. The upload itself happens on
-- the VMCP server over Open Cloud, because Studio's own CreateAssetAsync isn't enabled
-- everywhere yet; the plugin's job is to say what to upload and who should own it.

local Path = require(script.Parent.Parent.Path)
local Canvas = require(script.Parent.Parent.Lib.Canvas)

type Result = {
	content: { { type: "text", text: string } },
	isError: boolean?,
	postProcess: { [string]: any }?,
}

local Tool = {}

Tool.Definition = {
	name = "upload_image",
	description = "Uploads an image as a Roblox Image asset and returns its rbxassetid, so the "
		.. "picture can be used at runtime without EditableImage. Give it either `file`, the "
		.. "name of a PNG vmcp.Render already wrote under ~/.vmcp/images, or `root`, a dotted "
		.. "path to an ImageLabel/ImageButton showing an EditableImage (or the EditableImage "
		.. "itself). `owner` is the Studio user by default; pass a group id to upload there. "
		.. "First-time setup: pass `apiKey` once (an Open Cloud key with the assets read/write "
		.. "scope for that user or group) and it's remembered in ~/.vmcp/roblox-api-key. "
		.. "Moderation runs after upload, so the id is usable at once and the picture appears a "
		.. "little later.",
	inputSchema = {
		type = "object",
		properties = {
			file = {
				type = "string",
				description = "Name of a PNG under ~/.vmcp/images, without the extension -- what you gave vmcp.Render.",
			},
			root = {
				type = "string",
				description = "Dotted path to an ImageLabel, ImageButton or EditableImage in the place.",
			},
			name = {
				type = "string",
				description = "Asset display name. Defaults to the file or instance name.",
			},
			description = { type = "string", description = "Asset description." },
			owner = {
				type = "string",
				description = '"user" (default: whoever is logged into Studio) or a group id like "12345678".',
			},
			apiKey = {
				type = "string",
				description = "Open Cloud API key to remember for every later upload. Only needed once.",
			},
		},
	},
	tags = { title = "Upload Image", external = true },
	timeoutMs = 90000,
}

local function studioUserId(): number?
	local ok, id = pcall(function()
		return game:GetService("StudioService"):GetUserId()
	end)
	return if ok then id else nil
end

local function fail(text: string): Result
	return { content = { { type = "text", text = text } }, isError = true }
end

function Tool.Run(arguments: {
	file: string?,
	root: string?,
	name: string?,
	description: string?,
	owner: string?,
	apiKey: string?,
}): Result
	local directive: { [string]: any } = {
		kind = "upload",
		apiKey = arguments.apiKey,
		description = arguments.description,
	}

	local owner = arguments.owner
	if owner == nil or owner == "" or owner == "user" then
		local userId = studioUserId()
		if not userId then
			return fail("couldn't read the Studio user; pass owner as a group id instead")
		end
		directive.userId = userId
	else
		local groupId = tonumber(owner)
		if not groupId then
			return fail(`owner must be "user" or a group id, not "{owner}"`)
		end
		directive.groupId = groupId
	end

	if type(arguments.file) == "string" and arguments.file ~= "" then
		directive.file = arguments.file
		directive.name = arguments.name or arguments.file
	elseif type(arguments.root) == "string" and arguments.root ~= "" then
		local found, problem = Path.Resolve(arguments.root)
		if not found then
			return fail(problem :: string)
		end
		local image: EditableImage? = nil
		if found:IsA("EditableImage") then
			image = found
		elseif found:IsA("ImageLabel") or found:IsA("ImageButton") then
			local content = (found :: any):GetStyled("ImageContent") :: Content
			local object = if content.SourceType == Enum.ContentSourceType.Object then content.Object else nil
			if object and object:IsA("EditableImage") then
				image = object
			end
		end
		if not image then
			return fail(`{found:GetFullName()} isn't an EditableImage or an image label showing one`)
		end
		local pixels = Canvas.Base64Pixels(image)
		if not pixels then
			return fail(`{found:GetFullName()} is too big to send ({image.Size.X}x{image.Size.Y}); render it with vmcp.Render first and upload the file`)
		end
		directive.width = image.Size.X
		directive.height = image.Size.Y
		directive.pixels = pixels
		directive.name = arguments.name or found.Name
	elseif arguments.apiKey then
		-- Just storing the key is a fine call on its own.
		directive.name = nil
	else
		return fail("give `file` (a PNG vmcp.Render wrote) or `root` (an image in the place)")
	end

	local what = if directive.file then `~/.vmcp/images/{directive.file}.png` elseif directive.pixels then arguments.root else "nothing"
	local who = if directive.groupId then `group {directive.groupId}` else `user {directive.userId}`
	return {
		content = { { type = "text", text = `uploading {what} as "{directive.name or "-"}" owned by {who}` } },
		postProcess = directive,
	}
end

return Tool
