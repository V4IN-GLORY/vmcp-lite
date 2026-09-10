local BASE_PORT = 58741

local connection = {
	port = BASE_PORT,
	serverUrl = `http://localhost:{BASE_PORT}`,
	isActive = false,
	consecutiveFailures = 0,
	maxFailuresBeforeError = 50,
	currentRetryDelay = 0.5,
	lastHttpOk = false,
	lastMcpOk = false,
	mcpWaitStartTime = nil :: number?,
	heartbeatConnection = nil :: RBXScriptConnection?,
}

local function getActiveConnection()
	return connection
end

return {
	CURRENT_VERSION = "3.1.3",
	PLUGIN_VARIANT = "main",
	getActiveConnection = getActiveConnection,
}
