--!strict

-- Copied into the place as ReplicatedStorage.VMCPHarness.Runtime before a test starts, so both
-- harnesses can require it. The plugin never requires this file itself -- it reads the Source and
-- injects it -- but it lives here as a real module so luau-lsp still checks it.
--
-- Three things: the context every event shares, the clock that fires events, and the input
-- helpers. Input is here rather than in the payload because every raw VirtualInput call can
-- throw, and a key pressed with no matching release stays down for the rest of the run.

local UserInputService = game:GetService("UserInputService")

local Runtime = {}

export type Event = {
	at: number,
	blocking: boolean?,
	label: string?,
	run: (ctx: any, input: any) -> ...any,
}

export type Write = { at: number, from: string, key: string }

type Store = {
	values: { [string]: any },
	writes: { Write },
	notes: { string },
	origin: string,
	publish: (key: string, value: any) -> (),
	awaitTimeout: number,
}

-- Reading a key another context set is the normal case, so `ctx.thing` has to mean "the shared
-- value" and not "a field on the proxy". Everything real hides behind rawget.
local Methods = {}

local function store(self: any): Store
	return rawget(self, "__store") :: Store
end

-- Blocks until another context sets `key`. This is what turns a racy read into something the
-- payload declares rather than a coin flip. A miss is recorded, so an assertion that fails
-- because the value never arrived says so instead of quietly reading nil.
function Methods.Await(self: any, key: string, timeout: number?): any
	local state = store(self)
	local limit = timeout or state.awaitTimeout
	local deadline = os.clock() + limit

	repeat
		local value = state.values[key]
		if value ~= nil then
			return value
		end
		task.wait()
	until os.clock() >= deadline

	table.insert(state.notes, string.format('[%s] Await("%s") gave up after %ss', state.origin, key, tostring(limit)))
	return nil
end

function Methods.Note(self: any, text: string)
	local state = store(self)
	table.insert(state.notes, `[{state.origin}] {text}`)
end

function Methods.Snapshot(self: any): { [string]: any }
	return table.clone(store(self).values)
end

local Proxy = {
	__index = function(self: any, key: string): any
		local method = Methods[key]
		if method then
			return method
		end
		return store(self).values[key]
	end,
	__newindex = function(self: any, key: string, value: any)
		local state = store(self)
		state.values[key] = value
		-- Stamped at the origin, not on arrival, so the merged log still orders correctly when a
		-- client's write reaches the server after a later server write.
		table.insert(state.writes, { at = workspace:GetServerTimeNow(), from = state.origin, key = key })
		state.publish(key, value)
	end,
}

-- `origin` names this context in the log; `publish` sends a write out to everyone else.
function Runtime.Context(origin: string, publish: (key: string, value: any) -> (), awaitTimeout: number?): any
	local state: Store = {
		values = {},
		writes = {},
		notes = {},
		origin = origin,
		publish = publish,
		awaitTimeout = awaitTimeout or 5,
	}
	return setmetatable({ __store = state }, Proxy)
end

-- Applies a write that arrived from another context, without echoing it straight back out.
function Runtime.Receive(ctx: any, key: string, value: any)
	store(ctx).values[key] = value
end

function Runtime.Notes(ctx: any): { string }
	return store(ctx).notes
end

function Runtime.Writes(ctx: any): { Write }
	return store(ctx).writes
end

-- How late an event may fire before it's worth mentioning. A frame of slop is normal; a tenth of
-- a second means something before it ran long.
local OVERRUN = 0.1

-- Fires each event when its time comes, then holds until `duration` so trailing effects land. A
-- yielding event never delays the next one unless it asked to with `blocking`, which is what a
-- setup step wants. Running late is recorded rather than silently shifting everything after it.
function Runtime.Run(events: { Event }, ctx: any, input: any, duration: number, note: (string) -> ())
	table.sort(events, function(a, b)
		return a.at < b.at
	end)

	local started = os.clock()
	local function fire(event: Event)
		local ok, err = pcall(event.run, ctx, input)
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
