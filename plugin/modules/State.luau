local CURRENT_VERSION = "3.1.3"
local PLUGIN_VARIANT = "main"
local BASE_PORT = 58741
local function createConnection(port)
	return {
		port = port,
		serverUrl = `http://localhost:{port}`,
		isActive = false,
		consecutiveFailures = 0,
		maxFailuresBeforeError = 50,
		currentRetryDelay = 0.5,
		lastHttpOk = false,
		lastMcpOk = false,
		mcpWaitStartTime = nil,
		heartbeatConnection = nil,
	}
end
local connection = createConnection(BASE_PORT)
local function getActiveConnection()
	return connection
end
return {
	CURRENT_VERSION = CURRENT_VERSION,
	PLUGIN_VARIANT = PLUGIN_VARIANT,
	BASE_PORT = BASE_PORT,
	getActiveConnection = getActiveConnection,
}
