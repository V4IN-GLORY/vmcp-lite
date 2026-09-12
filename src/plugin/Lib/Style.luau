--!strict

-- Two small checks around StyleRule, both of which exist because the engine fails quietly here.
--
-- StyleRule:SetProperties ignores a property name the target class doesn't have. No error, no
-- warning -- the rule just does less than it says, and the usual next move is to go and rewrite
-- the selector, which was never the problem. StyleRule.SelectorError is the same shape of trap in
-- the other direction: the message is there to read, but nothing makes you read it.

local Style = {}

-- Instance.new is the only honest way to ask "does this class have this property". A probe costs
-- one instance that's thrown away immediately, and the answer is exact.
local function probe(className: string): (Instance?, string?)
	local ok, instance = pcall(Instance.new, className)
	if not ok then
		return nil,
			`can't check against "{className}" -- either it isn't a class or it isn't creatable, `
				.. "which is the case for abstract ones like GuiObject"
	end
	return instance, nil
end

-- Returns the property names the class doesn't have. Empty means everything would land.
function Style.Check(className: string, properties: { [string]: any }): ({ string }, string?)
	local instance, problem = probe(className)
	if not instance then
		return {}, problem
	end

	local missing = {}
	for name in properties do
		if not pcall(function()
			return (instance :: any)[name]
		end) then
			table.insert(missing, name)
		end
	end
	instance:Destroy()

	table.sort(missing)
	return missing, nil
end

-- Checks first, then applies. Returns the names it refused to set, so a typo shows up as a list
-- rather than as a rule that mysteriously does nothing.
function Style.Apply(rule: StyleRule, className: string, properties: { [string]: any }): ({ string }, string?)
	local missing, problem = Style.Check(className, properties)
	if problem then
		return {}, problem
	end

	local wanted = {}
	for name, value in properties do
		if not table.find(missing, name) then
			wanted[name] = value
		end
	end
	rule:SetProperties(wanted)
	return missing, nil
end

-- Sets a selector and hands back whatever the engine made of it. An empty return means it parsed.
function Style.Selector(rule: StyleRule, selector: string): string?
	rule.Selector = selector
	local complaint = rule.SelectorError
	return if complaint ~= "" then complaint else nil
end

return Style
