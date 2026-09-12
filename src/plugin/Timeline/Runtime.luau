--!strict

-- The two halves of running a timeline inside one DataModel: the shared context, and the clock.
--
-- The context isn't held here. The edit DataModel, the test server and each test client are
-- separate processes running separate copies of this plugin, so the socket back to VMCP is the
-- only thing all of them can touch -- every read and write is a round trip. That's slower than a
-- table and it's the only version that's actually correct, so treat `ctx.thing` as a network read
-- and pull it into a local if you need it more than once.

local UserInputService = game:GetService("UserInputService")

local Bridge = require(script.Parent.Parent.Bridge)

local Runtime = {}

export type Event = {
	at: number,
	blocking: boolean?,
	label: string?,
	run: (ctx: any, input: any, vmcp: any) -> ...any,
}

local DEFAULT_AWAIT = 5
-- Await polls instead of waiting on a signal, because what it's waiting for may be set in another
-- process entirely. Every tick is a round trip, so this is deliberately slower than a frame.
local AWAIT_POLL = 0.05

local Methods = {}

local function origin(self: any): string
	return rawget(self, "__origin") :: string
end

-- Blocks until another context sets `key`. This is what turns a racy read into something the
-- payload declares rather than a coin flip, and a miss is recorded -- so an assertion that fails
-- because the value never arrived says so, instead of quietly reading nil.
function Methods.Await(self: any, key: string, timeout: number?): any
	local limit = timeout or DEFAULT_AWAIT
	local deadline = os.clock() + limit

	repeat
		local value = Bridge.CtxGet(key)
		if value ~= nil then
			return value
		end
		task.wait(AWAIT_POLL)
	until os.clock() >= deadline

	Bridge.CtxNote(`[{origin(self)}] Await("{key}") gave up after {limit}s`)
	return nil
end

function Methods.Note(self: any, text: string)
	Bridge.CtxNote(`[{origin(self)}] {text}`)
end

function Methods.Snapshot(_: any): { [string]: any }
	local snapshot = Bridge.CtxSnapshot()
	return if snapshot then snapshot.values else {}
end

local Proxy = {
	__index = function(self: any, key: string): any
		local method = Methods[key]
		if method then
			return method
		end
		return Bridge.CtxGet(key)
	end,
	__newindex = function(self: any, key: string, value: any)
		Bridge.CtxSet(key, value, origin(self))
	end,
}

-- `where` names this context in the write log: "plugin", "server", "client 2".
function Runtime.Context(where: string): any
	return setmetatable({ __origin = where }, Proxy)
end

-- How late an event may fire before it's worth mentioning. A frame of slop is normal; a tenth of
-- a second means something before it ran long.
local OVERRUN = 0.1

-- Fires each event when its time comes, then holds until `duration` so trailing effects land. A
-- yielding event never delays the next one unless it asked to with `blocking`, which is what a
-- setup step wants. Running late is recorded rather than silently shifting everything after it.
function Runtime.Run(events: { Event }, ctx: any, input: any, vmcp: any, duration: number, note: (string) -> ())
	table.sort(events, function(a, b)
		return a.at < b.at
	end)

	local started = os.clock()
	local function fire(event: Event)
		local ok, err = pcall(event.run, ctx, input, vmcp)
		if not ok then
			local label = if event.label then ` ({event.label})` else ""
			note(`event at {event.at}s{label} failed: {err}`)
		end
	end

	for _, event in events do
		local elapsed = os.clock() - started
		if event.at > elapsed then
			task.wait(event.at - elapsed)
		elseif elapsed - event.at > OVERRUN then
			note(`event at {event.at}s fired {string.format("%.2f", elapsed - event.at)}s late`)
		end

		if event.blocking then
			fire(event)
		else
			task.spawn(fire, event)
		end
	end

	local remaining = duration - (os.clock() - started)
	if remaining > 0 then
		task.wait(remaining)
	end
end

local BUTTONS: { [string]: Enum.UserInputType } = {
	left = Enum.UserInputType.MouseButton1,
	right = Enum.UserInputType.MouseButton2,
	middle = Enum.UserInputType.MouseButton3,
}

local TAP_SECONDS = 0.05

-- Every one of these throws on contact with the topbar, a core-bound key like Escape, a button
-- that's already down, or a mouse delta without a locked cursor. A failed keypress should cost
-- one line in the log, not the whole run, so each call is wrapped and the reason kept.
function Runtime.Input(): any
	local virtual = (UserInputService :: any):CreateVirtualInput()
	local held: { [string]: Enum.KeyCode? } = {}
	local down: { [string]: Enum.UserInputType? } = {}
	local input = { problems = {} :: { string } }

	local function attempt(what: string, action: () -> ...any): boolean
		local ok, err = pcall(action)
		if not ok then
			table.insert(input.problems, `{what}: {err}`)
		end
		return ok
	end

	local function keyCode(name: string): Enum.KeyCode?
		local code = (Enum.KeyCode :: any)[name]
		if not code then
			table.insert(input.problems, `no KeyCode named "{name}"`)
		end
		return code
	end

	function input.Hold(_: any, name: string)
		local code = keyCode(name)
		if not code or held[name] then
			return
		end
		local pressed = attempt(`Hold "{name}"`, function()
			virtual:SendKey(true, code)
		end)
		if pressed then
			held[name] = code
		end
	end

	function input.Release(_: any, name: string)
		local code = held[name]
		if not code then
			return
		end
		held[name] = nil
		attempt(`Release "{name}"`, function()
			virtual:SendKey(false, code)
		end)
	end

	function input.Tap(self: any, name: string, hold: number?)
		input.Hold(self, name)
		task.wait(hold or TAP_SECONDS)
		input.Release(self, name)
	end

	function input.Move(_: any, x: number, y: number)
		attempt(`Move to {x},{y}`, function()
			virtual:SendMousePosition(Vector2.new(x, y))
		end)
	end

	function input.Click(self: any, x: number, y: number, button: string?)
		local name = button or "left"
		local which = BUTTONS[name]
		if not which then
			table.insert(input.problems, `no mouse button named "{name}"`)
			return
		end

		local at = Vector2.new(x, y)
		input.Move(self, x, y)
		local pressed = attempt(`Click {name} at {x},{y}`, function()
			virtual:SendMouseButton(at, which, true)
		end)
		if not pressed then
			return
		end

		down[name] = which
		task.wait(TAP_SECONDS)
		down[name] = nil
		attempt(`Release {name} button`, function()
			virtual:SendMouseButton(at, which, false)
		end)
	end

	function input.Drag(self: any, x1: number, y1: number, x2: number, y2: number, steps: number?)
		local count = math.max(steps or 10, 1)
		local from, to = Vector2.new(x1, y1), Vector2.new(x2, y2)

		input.Move(self, x1, y1)
		local pressed = attempt("Drag press", function()
			virtual:SendMouseButton(from, Enum.UserInputType.MouseButton1, true)
		end)
		if not pressed then
			return
		end
		down.left = Enum.UserInputType.MouseButton1

		for step = 1, count do
			local point = from:Lerp(to, step / count)
			attempt("Drag move", function()
				virtual:SendMousePosition(point)
			end)
			task.wait()
		end

		down.left = nil
		attempt("Drag release", function()
			virtual:SendMouseButton(to, Enum.UserInputType.MouseButton1, false)
		end)
	end

	function input.Type(_: any, text: string)
		attempt(`Type {#text} chars`, function()
			virtual:SendTextInput(text)
		end)
	end

	function input.Scroll(_: any, x: number, y: number, amount: number)
		attempt(`Scroll {amount}`, function()
			virtual:SendPointerAction(Vector2.new(x, y), { Wheel = amount })
		end)
	end

	-- Runs at teardown however the run ended, because a Hold whose Release never came -- an event
	-- that errored between the two, say -- leaves that key down for everything after it.
	function input.ReleaseEverything(_: any)
		for name, code in held do
			held[name] = nil
			attempt(`Release "{name}"`, function()
				virtual:SendKey(false, code)
			end)
		end
		for name, which in down do
			down[name] = nil
			attempt(`Release {name} button`, function()
				virtual:SendMouseButton(Vector2.zero, which, false)
			end)
		end
	end

	return input
end

return Runtime
