--!strict
--!optimize 2

-- Collects the tool modules and turns them into the `tools` array for session/hello.
--
-- The server validates definitions too, but it rejects the *whole* list when one entry is
-- malformed, and its error arrives as a closed socket. Checking here instead means a bad tool
-- names itself in the Output window and the other tools still register.

export type Definition = {
	name: string,
	description: string,
	inputSchema: { [string]: any },
	outputSchema: { [string]: any }?,
	tags: { [string]: any }?,
	timeoutMs: number?,
}

export type Tool = {
	Definition: Definition,
	Run: (arguments: any) -> any,
}

local Registry = {
	definitions = {} :: { Definition },
	byName = {} :: { [string]: Tool },
}

-- Mirrors the server's NAME_PATTERN; anything else is refused at registration.
local function validate(definition: any): string?
	if type(definition) ~= "table" then
		return "Definition must be a table"
	end
	local name = definition.name
	if type(name) ~= "string" or #name > 64 or not string.match(name, "^[%w_%-]+$") then
		return "name must be 1-64 chars of letters, digits, underscore or hyphen"
	end
	if type(definition.description) ~= "string" or definition.description == "" then
		return "description must be a non-empty string"
	end

	local input = definition.inputSchema
	if type(input) ~= "table" then
		return "inputSchema must be a table"
	end
	-- An empty table encodes as [] and the server turns that back into { type = "object" }.
	if next(input) ~= nil and input.type ~= "object" then
		return `inputSchema needs type = "object" at its root (MCP requires it)`
	end
	if definition.timeoutMs ~= nil and (type(definition.timeoutMs) ~= "number" or definition.timeoutMs <= 0) then
		return "timeoutMs must be a positive number"
	end
	return nil
end

-- Requires every ModuleScript in `folder` and keeps the ones that look like tools.
function Registry.Collect(folder: Instance)
	table.clear(Registry.definitions)
	table.clear(Registry.byName)

	for _, child in folder:GetChildren() do
		if not child:IsA("ModuleScript") then
			continue
		end

		local ok, tool = pcall(require, child)
		if not ok then
			warn(`[VMCP] tool "{child.Name}" failed to load: {tool}`)
			continue
		end
		if type(tool) ~= "table" or type(tool.Run) ~= "function" then
			warn(`[VMCP] tool "{child.Name}" has no Run function`)
			continue
		end

		local problem = validate(tool.Definition)
		if problem then
			warn(`[VMCP] tool "{child.Name}" rejected: {problem}`)
			continue
		end

		local name = tool.Definition.name
		if Registry.byName[name] then
			warn(`[VMCP] duplicate tool name "{name}" in "{child.Name}"`)
			continue
		end

		Registry.byName[name] = tool
		table.insert(Registry.definitions, tool.Definition)
	end
end

return Registry
