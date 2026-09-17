--!strict

-- Answers "why does this rule do nothing" in one call. The engine has no API that says which
-- rules matched an instance, so this lays out everything that decides it: the instance's class,
-- name and tags (the selector's inputs), the direct value next to the styled value next to the
-- class default (the precedence fight), and every rule in the linked sheets that sets the
-- property, with its selector, priority, stored value and SelectorError.

local CollectionService = game:GetService("CollectionService")

local Path = require(script.Parent.Parent.Path)

type Result = {
	content: { { type: "text", text: string } },
	isError: boolean?,
}

local Tool = {}

Tool.Definition = {
	name = "inspect_style",
	description = "Explains what StyleSheet rules did to one instance. For each property: the value set "
		.. "directly on the instance, the value the rules resolved (GetStyled), the class default, and "
		.. "every rule in the linked sheets that sets that property (selector, priority, stored value, "
		.. "SelectorError). Also lists the instance's tags, since `.Name` is a tag and `#Name` is the "
		.. "instance name. A direct value that isn't the class default beats every rule; a rule whose "
		.. "stored value is the class default may not reach a playtest client. Run it with context "
		.. "client to see what the player actually gets.",
	inputSchema = {
		type = "object",
		properties = {
			root = { type = "string", description = "Dotted path to the GuiObject to inspect." },
			properties = {
				type = "array",
				items = { type = "string" },
				description = "Property names to explain. Defaults to the common visual ones.",
			},
			context = {
				type = "string",
				description = "Which DataModel. Defaults to plugin.",
				enum = { "plugin", "server", "client" },
			},
			player = {
				type = "integer",
				description = "Which test client, 1-based. Only meaningful with context client.",
				minimum = 1,
				maximum = 8,
			},
		},
		required = { "root" },
	},
	tags = { title = "Inspect Style", readOnly = true },
	timeoutMs = 15000,
}

local DEFAULT_PROPERTIES: { string } = {
	"BackgroundColor3", "BackgroundTransparency", "TextColor3", "TextSize", "TextXAlignment",
	"FontFace", "ImageColor3", "ImageTransparency", "Size", "Position", "Visible",
}

local function show(value: any): string
	local kind = typeof(value)
	if kind == "Color3" then
		local c = value :: Color3
		return `rgb({math.round(c.R * 255)}, {math.round(c.G * 255)}, {math.round(c.B * 255)})`
	elseif kind == "Font" then
		return (value :: Font).Family:match("([^/]+)%.json$") or tostring(value)
	end
	return tostring(value)
end

-- Every sheet the instance can see: the StyleLinks on it and its ancestors, plus what those
-- sheets derive from.
local function sheets(instance: Instance): { StyleSheet }
	local out, seen = {}, {}
	local function add(sheet: StyleSheet?)
		if not sheet or seen[sheet] then
			return
		end
		seen[sheet] = true
		table.insert(out, sheet)
		for _, derive in sheet:GetChildren() do
			if derive:IsA("StyleDerive") then
				add(derive.StyleSheet)
			end
		end
	end
	local node: Instance? = instance
	while node do
		for _, child in node:GetChildren() do
			if child:IsA("StyleLink") then
				add(child.StyleSheet)
			end
		end
		node = node.Parent
	end
	return out
end

local function fail(text: string): Result
	return { content = { { type = "text", text = text } }, isError = true }
end

function Tool.Run(arguments: { root: string, properties: { string }? }): Result
	local found, problem = Path.Resolve(arguments.root)
	if not found then
		return fail(problem :: string)
	end
	local instance = found :: Instance
	local names: { string } = if arguments.properties and #arguments.properties > 0 then arguments.properties else DEFAULT_PROPERTIES

	local defaults: any = nil
	pcall(function()
		defaults = Instance.new(instance.ClassName)
	end)

	local rules = {}
	local linked = sheets(instance)
	for _, sheet in linked do
		for _, rule in sheet:GetDescendants() do
			if rule:IsA("StyleRule") then
				table.insert(rules, rule)
			end
		end
	end

	local lines = {
		`{instance:GetFullName()} ({instance.ClassName}) tags: {table.concat(CollectionService:GetTags(instance), ", ")}`,
		`sheets: {#linked}, rules: {#rules}`,
	}
	for _, name in names do
		local okDirect, direct = pcall(function()
			return (instance :: any)[name]
		end)
		if not okDirect then
			table.insert(lines, `\n{name}: no such property on {instance.ClassName}`)
			continue
		end
		local okStyled, styled = pcall(function()
			return (instance :: any):GetStyled(name)
		end)
		local default = if defaults then (defaults :: any)[name] else nil
		local verdict = if direct ~= default
			then "direct value wins (not the class default)"
			elseif okStyled and styled ~= direct then "a rule decides it"
			else "class default; no rule changed it"
		table.insert(lines, `\n{name}: direct={show(direct)} styled={if okStyled then show(styled) else "?"} default={show(default)} -- {verdict}`)
		for _, rule in rules do
			local value = rule:GetProperty(name)
			if value ~= nil then
				local err = rule.SelectorError
				table.insert(lines, `  [{rule.Priority}] {rule.Selector} = {show(value)}{if err ~= "" then " SELECTOR ERROR: " .. err else ""}{if value == default then " (class default: may not reach a client)" else ""}`)
			end
		end
	end
	if defaults then
		defaults:Destroy()
	end
	return { content = { { type = "text", text = table.concat(lines, "\n") } } }
end

return Tool
