--!strict
local HttpService = game:GetService("HttpService")

-- ============================================================================
--  THIS IS THE ONLY FILE YOU NEED TO TOUCH TO MAKE THE PANEL REALLY CONNECT.
-- ============================================================================
--
-- Right now Connect walks a timer so every visual state is reachable. Replace the bodies of
-- Transport.Connect and Transport.Disconnect with the real socket; the panel never changes.
--
-- What you get:
--   Transport.Connect(port, token)  -- called when the user hits Connect (token may be nil)
--   Transport.Disconnect()          -- called when the user hits Disconnect, or cancels
--
-- What you owe the panel, by calling Transport.Report(kind, detail):
--   ("connecting", { phase = "socket" })          socket opening
--   ("connecting", { phase = "handshake" })       socket open, session/hello sent
--   ("connected",  { tools = 6, revision = 3 })   hello acknowledged
--   ("fault",      { code = 1008 })               closed -- see the table in docs/protocol.md
--   ("fault",      { retryIn = 4 })               unreachable, backing off
--   ("idle")                                      closed on purpose
--
-- Close codes the panel already has copy for: 1008 bad token (this one also pops the token
-- field open), 1009 message too large, 4000 superseded by another Studio window. Anything else
-- reads as unreachable. Per docs/protocol.md, do not retry 1008 or 4000 -- they will not start
-- working.
--
-- The real thing is roughly:
--   local client = HttpService:CreateWebStreamClient(Enum.WebStreamClientType.WebSocket, {
--       Url = `ws://127.0.0.1:{port}`,
--   })
--   client.Opened:Connect(...)  -- send session/hello within 5s, protocolVersion = 3
--   client.MessageReceived:Connect(...)  -- answer tool/call with the matching id
--   client.Error:Connect(...)
--   client.Closed:Connect(...)  -- reconnect with backoff, skipping 1008 and 4000
-- Close the old client before opening a new one; Studio caps you at six live stream clients.

local Transport = {}

-- Assigned by init.server.luau; forwards straight to Panel.SetState.
Transport.Report = nil :: ((kind: string, detail: { [string]: any }?) -> ())?

local attempt = 0

local function report(kind: string, detail: { [string]: any }?)
	if Transport.Report then
		Transport.Report(kind, detail)
	end
end

function Transport.Connect(port: number, token: string?)
	attempt += 1
	local mine = attempt

	report("connecting", { phase = "socket" })
	local socket
	for i = 1, 5 do
		if socket and socket.ConnectionState == Enum.WebStreamClientState.Open then return end
		socket = HttpService:CreateWebStreamClient(Enum.WebStreamClientType.WebSocket, {Url = `ws://127.0.0.1:{port}`})
		task.wait(1)
	end


end

function Transport.Disconnect()
	attempt += 1 -- abandons any in-flight stub attempt
	report("idle")
end

return Transport
