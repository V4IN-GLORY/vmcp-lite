--!strict
--!optimize 2

-- The socket. Opens one WebStreamClient, handshakes, keeps it alive, and hands tool/call
-- messages to Dispatch.
--
-- Bridge.Init(toolFolder, settings)   settings: { GetPlaceGuid: () -> string }
-- Bridge.Connect(port, token)
-- Bridge.Disconnect()                 deliberate; stops retrying
-- Bridge.OnStatus(fn)                 fn(signal, word, line) -- drives the Panel
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
	toolFolder = nil :: Instance?,
	getPlaceGuid = nil :: (() -> string)?,
	onStatus = nil :: ((signal: string, word: string, line: string) -> ())?,
}

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
			local count = #Registry.definitions
			report("Live", "connected", `{count} tool{if count == 1 then "" else "s"} registered.`)
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

function Bridge.Init(toolFolder: Instance, settings: { GetPlaceGuid: () -> string })
	state.toolFolder = toolFolder
	state.getPlaceGuid = settings.GetPlaceGuid
end

function Bridge.OnStatus(fn: (signal: string, word: string, line: string) -> ())
	state.onStatus = fn
end

function Bridge.Connect(port: string, token: string)
	state.port = port
	state.token = token
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

function Bridge.IsConnected(): boolean
	return state.handshakeOk
end

return Bridge
