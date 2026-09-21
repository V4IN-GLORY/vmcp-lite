--!strict
--!optimize 2

-- The socket. Opens one WebStreamClient, handshakes, keeps it alive, and hands tool/call
-- messages to Dispatch.
--
-- Bridge.Init(toolFolder, settings)   settings: { GetPlaceGuid: () -> string }
-- Bridge.Connect(port, token, as)     as: { role, linkId, alsoClient } -- the edit session omits it
-- Bridge.Disconnect()                 deliberate; stops retrying
-- Bridge.OnStatus(fn)                 fn(signal, word, line) -- drives the Panel
-- Bridge.OnUpdateOffered(fn)          fn(offer) -- the server has a different plugin build bundled
-- Bridge.ApplyUpdate(sha256)          the person clicked Update; writes only the build with that sha
-- Bridge.Invoke(name, arguments)      call another tool, in any context, through the server
-- Bridge.Ctx*                         the timeline's shared context, which the server holds
--
-- One Studio window runs several of these. The plugin loads into the edit DataModel and, while a
-- playtest is on, into the test server and every test client as well -- same code, different role
-- in the handshake. That is how a call for a live context reaches a real running game.
--
-- The reconnect rule is not the one in docs/protocol.md. That table says to skip retrying on
-- close codes 1008 and 4000, but WebStreamClient's Closed event carries no arguments at all, so
-- the plugin never sees a code. What it can see is whether the handshake ever succeeded: 1008
-- (bad token, bad version, non-JSON) always closes before the hello reply, so a close that
-- happened after the socket opened but before the reply is a configuration problem and retrying
-- it forever is pointless noise. A close with no Opened behind it is just a server that isn't
-- listening yet, which is exactly what a restart looks like, so that one keeps retrying.

local HttpService = game:GetService("HttpService")

local Dispatch = require(script.Dispatch)
local Registry = require(script.Registry)

local PROTOCOL_VERSION = 3
local BACKOFF_START = 1
local BACKOFF_MAX = 30
-- A supersede (close 4000) also lands after a good handshake, so two Studio windows sharing a
-- sessionId would retry each other forever. Dropping out after a few near-instant closes ends
-- that without needing the close code we can't read.
local FLAP_WINDOW = 10
local FLAP_LIMIT = 4

local Bridge = {}

local state = {
	socket = nil :: any,
	sessionId = HttpService:GenerateGUID(false),
	port = nil :: string?,
	token = nil :: string?,
	-- The reconnect decision hangs off this pair: opened means the socket reached the server at
	-- all, handshakeOk means the server accepted the session.
	opened = false,
	handshakeOk = false,
	helloId = 0,
	nextId = 1,
	wantConnected = false,
	backoff = BACKOFF_START,
	connectedAt = 0,
	flaps = 0,
	role = "plugin",
	linkId = nil :: string?,
	alsoClient = false,
	-- Assigned by the server: 0 for a test server, 1+ for each test client.
	peerIndex = nil :: number?,
	onUpdateOffered = nil :: ((offer: any) -> ())?,
	toolFolder = nil :: Instance?,
	getPlaceGuid = nil :: (() -> string)?,
	onStatus = nil :: ((signal: string, word: string, line: string) -> ())?,
}

-- Replies we're still waiting on, keyed by the id we sent. Only Bridge.Request puts anything in
-- here; tool/call goes the other direction.
local pending: { [number]: (ok: boolean, payload: any) -> () } = {}

local function report(signal: string, word: string, line: string)
	if state.onStatus then
		state.onStatus(signal, word, line)
	end
end

-- Encoding is the only way this fails, and a silent failure means Claude waits out the whole
-- timeout for a reply that never comes, so the reason goes back to the caller.
local function send(message: { [string]: any }): (boolean, string?)
	local socket = state.socket
	if not socket then
		return false, "socket is closed"
	end

	local ok, encoded = pcall(HttpService.JSONEncode, HttpService, message)
	if not ok then
		return false, tostring(encoded)
	end

	socket:Send(encoded)
	return true, nil
end

-- An unsaved place has a PlaceId of 0, which the server refuses, so those fall back to a GUID
-- stored in plugin settings -- stable across sessions the way a real PlaceId would be.
local function placeIdentity(): (string, string)
	local id = game.PlaceId
	if id ~= 0 then
		return tostring(id), if game.Name ~= "" then game.Name else "Unsaved Place"
	end
	local getGuid = state.getPlaceGuid
	return (if getGuid then getGuid() else "0"), "Unsaved Place"
end

local function closeSocket()
	local socket = state.socket
	if not socket then
		return
	end
	state.socket = nil
	-- Six live stream clients per session, so the old one goes before a new one opens.
	pcall(function()
		socket:Close()
	end)
end

local scheduleRetry: () -> ()

local function openSocket()
	closeSocket()
	state.opened = false
	state.handshakeOk = false

	local port = state.port
	local token = state.token
	if not port or not token then
		report("Fault", "no token", "Set a port and paste the auth token first.")
		return
	end

	report("Work", "connecting", `Connecting to ws://127.0.0.1:{port}`)

	-- No Origin header: the server refuses any connection carrying one, because a webpage can
	-- reach localhost and a plugin never sends it.
	local ok, socket = pcall(function()
		return HttpService:CreateWebStreamClient(Enum.WebStreamClientType.WebSocket, {
			Url = `ws://127.0.0.1:{port}`,
		})
	end)
	if not ok then
		report("Fault", "failed", `Could not open a socket: {socket}`)
		return
	end

	state.socket = socket
	state.connectedAt = os.clock()

	-- Every handler below ignores a socket that is no longer the current one. Replacing a socket
	-- fires Closed on the old one, and without this that stale event would schedule a retry
	-- alongside the connection that just replaced it.
	socket.Opened:Connect(function()
		if socket ~= state.socket then
			return
		end
		state.opened = true

		local folder = state.toolFolder
		if not folder then
			report("Fault", "not set up", "Bridge.Init was never called with a tool folder.")
			return
		end
		Registry.Collect(folder)
		local placeId, placeName = placeIdentity()

		state.helloId = state.nextId
		state.nextId += 1
		send({
			jsonrpc = "2.0",
			id = state.helloId,
			method = "session/hello",
			params = {
				token = token,
				protocolVersion = PROTOCOL_VERSION,
				sessionId = state.sessionId,
				placeId = placeId,
				placeName = placeName,
				tools = Registry.definitions,
				role = state.role,
				linkId = state.linkId,
				alsoClient = state.alsoClient,
			},
		})
	end)

	socket.MessageReceived:Connect(function(raw: string)
		if socket ~= state.socket then
			return
		end

		local decoded, message = pcall(HttpService.JSONDecode, HttpService, raw)
		if not decoded then
			warn(`[VMCP] server sent something that wasn't JSON: {message}`)
			return
		end

		local waiter = if message.method == nil then pending[message.id] else nil
		if waiter then
			if message.error then
				waiter(false, message.error.message)
			else
				waiter(true, message.result)
			end
			return
		end

		if message.id == state.helloId and not state.handshakeOk then
			if message.error then
				-- Wrong token or wrong protocol version. Retrying can't fix either.
				report("Fault", "refused", message.error.message)
				state.wantConnected = false
				closeSocket()
				return
			end
			state.handshakeOk = true
			state.backoff = BACKOFF_START
			state.flaps = 0
			state.peerIndex = if message.result then message.result.peerIndex else nil
			local count = #Registry.definitions
			report("Live", "connected", `{count} tool{if count == 1 then "" else "s"} registered.`)
			return
		end

		-- The server never installs a plugin build on its own; it only says one is bundled.
		if message.method == "plugin/update-available" then
			if state.onUpdateOffered then
				state.onUpdateOffered(message.params)
			end
			return
		end

		Dispatch.Handle(send, message)
	end)

	socket.Error:Connect(function(status: number, reason: string)
		if socket ~= state.socket then
			return
		end
		warn(`[VMCP] socket error {status}: {reason}`)
	end)

	socket.Closed:Connect(function()
		-- No close code here -- see the note at the top of the file.
		if socket ~= state.socket then
			return
		end

		local wasOpen, wasLive = state.opened, state.handshakeOk
		state.socket = nil
		for _, waiting in pending do
			waiting(false, "the connection to the VMCP server dropped")
		end
		state.opened = false
		state.handshakeOk = false

		if not state.wantConnected then
			report("Idle", "not connected", "Disconnected.")
			return
		end
		-- Never opened: nothing was listening. Common and temporary -- Node restarts constantly
		-- during development -- so back off and keep trying.
		if not wasOpen then
			scheduleRetry()
			return
		end
		if not wasLive then
			report("Fault", "refused", "Server closed before the handshake. Check the port and token.")
			state.wantConnected = false
			return
		end

		if os.clock() - state.connectedAt < FLAP_WINDOW then
			state.flaps += 1
		else
			state.flaps = 0
		end
		if state.flaps >= FLAP_LIMIT then
			report("Fault", "superseded", "Kept getting dropped -- another Studio window may hold this session.")
			state.wantConnected = false
			return
		end

		scheduleRetry()
	end)
end

function scheduleRetry()
	local delay = state.backoff
	state.backoff = math.min(delay * 2, BACKOFF_MAX)
	report("Work", "reconnecting", `Lost the server. Retrying in {delay}s.`)

	task.delay(delay, function()
		if state.wantConnected and not state.socket then
			openSocket()
		end
	end)
end

-- Asks the server a question and waits for the answer. The server can reach the filesystem and
-- the plugin can't, which is the only reason this direction exists.
--
-- Yields, so it can only be called from a tool's own thread -- Dispatch spawns one per call, so
-- blocking here holds up that call and nothing else on the socket.
function Bridge.Request(method: string, params: { [string]: any }, timeout: number?): (boolean, any)
	if not state.handshakeOk then
		return false, "not connected to the VMCP server"
	end

	local id = state.nextId
	state.nextId += 1
	local thread = coroutine.running()

	pending[id] = function(ok: boolean, payload: any)
		pending[id] = nil
		task.spawn(thread, ok, payload)
	end

	local sent, failure = send({ jsonrpc = "2.0", id = id, method = method, params = params })
	if not sent then
		pending[id] = nil
		return false, failure :: any
	end

	task.delay(timeout or 15, function()
		local waiting = pending[id]
		if waiting then
			waiting(false, `the server didn't answer {method} in time`)
		end
	end)

	return coroutine.yield()
end

function Bridge.Init(toolFolder: Instance, settings: { GetPlaceGuid: () -> string })
	state.toolFolder = toolFolder
	state.getPlaceGuid = settings.GetPlaceGuid
end

function Bridge.OnStatus(fn: (signal: string, word: string, line: string) -> ())
	state.onStatus = fn
end

export type UpdateOffer = { sha256: string, destination: string, fresh: boolean, bytes: number }

function Bridge.OnUpdateOffered(fn: (offer: UpdateOffer) -> ())
	state.onUpdateOffered = fn
end

function Bridge.ApplyUpdate(sha256: string): (boolean, string)
	local ok, payload = Bridge.Request("plugin/update-apply", { sha256 = sha256 }, 15)
	if not ok then
		return false, tostring(payload)
	end
	return true, tostring(payload.destination)
end

-- `as` is how a playtest DataModel says which one it is. The edit session leaves it out.
function Bridge.Connect(port: string, token: string, as: { role: string, linkId: string, alsoClient: boolean? }?)
	state.port = port
	state.token = token
	if as then
		state.role = as.role
		state.linkId = as.linkId
		state.alsoClient = as.alsoClient == true
	end
	state.wantConnected = true
	state.backoff = BACKOFF_START
	state.flaps = 0
	openSocket()
end

function Bridge.Disconnect()
	state.wantConnected = false
	closeSocket()
	report("Idle", "not connected", "Disconnected.")
end

function Bridge.Connection(): { port: string?, token: string?, sessionId: string, role: string, peerIndex: number? }
	return {
		port = state.port,
		token = state.token,
		sessionId = state.sessionId,
		role = state.role,
		peerIndex = state.peerIndex,
	}
end

-- Calls another tool, in whatever context `arguments.context` names, through the server. This is
-- what lets a timeline event in a test client ask the edit session for a tree dump, or push work
-- onto the server and read the answer in the same snippet.
function Bridge.Invoke(name: string, arguments: { [string]: any }?, timeout: number?): (boolean, any)
	local ok, payload = Bridge.Request("tool/invoke", {
		name = name,
		arguments = arguments or {},
		depth = Dispatch.CurrentDepth(),
	}, timeout)
	if not ok then
		return false, payload
	end
	return true, payload.result
end

-- The timeline's shared context. It lives on the server because the edit DataModel, the test
-- server and each test client are separate processes -- this socket is the only thing they share.
-- Asks the VMCP server to finish something this side can't: writing a Canvas recording out as a
-- PNG. A tool result can carry the same directive back, but a timeline event isn't a tool result.
function Bridge.Post(directive: { [string]: any }): (boolean, string)
	local ok, payload = Bridge.Request("post/process", directive, 30)
	if not ok then
		return false, tostring(payload)
	end
	return true, tostring(if type(payload) == "table" then payload.outcome else payload)
end

function Bridge.CtxSet(key: string, value: any, from: string): boolean
	-- No timestamp: every write blocks until the server has it, so arrival order is write order
	-- and the server is the only clock all three DataModels agree on.
	return (Bridge.Request("ctx/set", { key = key, value = value, from = from }, 5))
end

function Bridge.CtxGet(key: string): any
	local ok, payload = Bridge.Request("ctx/get", { key = key }, 5)
	return if ok then payload.value else nil
end

function Bridge.CtxNote(text: string): boolean
	return (Bridge.Request("ctx/note", { text = text }, 5))
end

function Bridge.CtxClear(): boolean
	return (Bridge.Request("ctx/clear", {}, 5))
end

function Bridge.CtxSnapshot(): any
	local ok, payload = Bridge.Request("ctx/snapshot", {}, 10)
	return if ok then payload else nil
end

function Bridge.IsConnected(): boolean
	return state.handshakeOk
end

return Bridge
