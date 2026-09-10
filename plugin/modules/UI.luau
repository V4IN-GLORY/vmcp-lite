local TweenService = game:GetService("TweenService")
local State = require(script.Parent.State)
local ServerUrlSettings = require(script.Parent.ServerUrlSettings)
local elements = nil
local pulseAnimation
local buttonHover = false
local toolbarButton
local toolbarIcons
local lastToolbarIcon
local activeBannerKind
local updateToolbarIcon
local function setToolbarButton(btn, icons)
	toolbarButton = btn
	toolbarIcons = icons
	lastToolbarIcon = nil
	updateToolbarIcon()
end
function updateToolbarIcon()
	if not toolbarButton or not toolbarIcons then
		return nil
	end
	local conn = State.getActiveConnection()
	local nextIcon
	if not conn or not conn.isActive then
		nextIcon = toolbarIcons.disconnected
	elseif conn.lastHttpOk and conn.lastMcpOk then
		nextIcon = toolbarIcons.connected
	else
		nextIcon = toolbarIcons.connecting
	end
	if nextIcon ~= lastToolbarIcon then
		toolbarButton.Icon = nextIcon
		lastToolbarIcon = nextIcon
	end
end
local TWEEN_QUICK = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local function tweenProp(instance, props)
	TweenService:Create(instance, TWEEN_QUICK, props):Play()
end
local function showBanner(kind, text)
	activeBannerKind = kind
	elements.updateBannerText.Text = text
	elements.updateBanner.Visible = true
	elements.contentFrame.Position = UDim2.new(0, 8, 0, 70)
	elements.contentFrame.Size = UDim2.new(1, -16, 1, -78)
end
local function hideBanner(kind)
	if kind ~= nil and activeBannerKind ~= kind then
		return nil
	end
	activeBannerKind = nil
	elements.updateBanner.Visible = false
	elements.updateBannerText.Text = ""
	elements.contentFrame.Position = UDim2.new(0, 8, 0, 44)
	elements.contentFrame.Size = UDim2.new(1, -16, 1, -52)
end
local C = {
	bg = Color3.fromRGB(14, 14, 14),
	card = Color3.fromRGB(22, 22, 22),
	surface = Color3.fromRGB(30, 30, 30),
	border = Color3.fromRGB(38, 38, 38),
	subtle = Color3.fromRGB(48, 48, 48),
	muted = Color3.fromRGB(100, 100, 100),
	dim = Color3.fromRGB(140, 140, 140),
	label = Color3.fromRGB(180, 180, 180),
	white = Color3.fromRGB(240, 240, 240),
	green = Color3.fromRGB(52, 211, 153),
	yellow = Color3.fromRGB(251, 191, 36),
	red = Color3.fromRGB(248, 113, 113),
	gray = Color3.fromRGB(120, 120, 120),
}
local CORNER = UDim.new(0, 4)
local function setButtonConnect(btn, stroke)
	btn.Text = "Connect"
	btn.TextColor3 = C.white
	btn.BackgroundColor3 = C.surface
	stroke.Color = C.subtle
end
local function setButtonDisconnect(btn, stroke)
	btn.Text = "Disconnect"
	btn.TextColor3 = C.red
	btn.BackgroundColor3 = C.bg
	stroke.Color = Color3.fromRGB(80, 30, 30)
end
local function stopPulseAnimation()
	elements.statusPulse.Size = UDim2.new(0, 10, 0, 10)
	elements.statusPulse.Position = UDim2.new(0, 0, 0, 0)
	elements.statusPulse.BackgroundTransparency = 0.7
end
local function startPulseAnimation()
	elements.statusPulse.Size = UDim2.new(0, 10, 0, 10)
	elements.statusPulse.Position = UDim2.new(0, 0, 0, 0)
	elements.statusPulse.BackgroundTransparency = 0.7
end
local function init(pluginRef)
	local CURRENT_VERSION = State.CURRENT_VERSION
	local screenGui = pluginRef:CreateDockWidgetPluginGuiAsync(
		"MCPServerInterface",
		DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, true, 300, 260, 260, 200)
	)
	screenGui.Title = `MCP Server v{CURRENT_VERSION}`
	local mainFrame = Instance.new("Frame")
	mainFrame.Size = UDim2.new(1, 0, 1, 0)
	mainFrame.BackgroundColor3 = C.bg
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = screenGui
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 40)
	header.BackgroundColor3 = C.bg
	header.BorderSizePixel = 0
	header.Parent = mainFrame
	local headerLine = Instance.new("Frame")
	headerLine.Size = UDim2.new(1, -16, 0, 1)
	headerLine.Position = UDim2.new(0, 8, 1, -1)
	headerLine.BackgroundColor3 = C.border
	headerLine.BorderSizePixel = 0
	headerLine.Parent = header
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, -50, 0, 22)
	titleLabel.Position = UDim2.new(0, 10, 0, 2)
	titleLabel.BackgroundTransparency = 1
	titleLabel.RichText = true
	titleLabel.Text = `<font color="#F0F0F0">MCP</font> <font color="#646464">v{CURRENT_VERSION}</font>`
	titleLabel.TextColor3 = C.white
	titleLabel.TextSize = 12
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = header
	local creditsLabel = Instance.new("TextLabel")
	creditsLabel.Size = UDim2.new(1, -20, 0, 12)
	creditsLabel.Position = UDim2.new(0, 10, 0, 23)
	creditsLabel.BackgroundTransparency = 1
	creditsLabel.RichText = true
	creditsLabel.Text = '<font color="#999999">github</font> <font color="#CCCCCC">Chrrxs/robloxstudio-mcp</font>'
	creditsLabel.TextColor3 = C.muted
	creditsLabel.TextSize = 8
	creditsLabel.Font = Enum.Font.GothamMedium
	creditsLabel.TextXAlignment = Enum.TextXAlignment.Left
	creditsLabel.Parent = header
	local statusContainer = Instance.new("Frame")
	statusContainer.Size = UDim2.new(0, 20, 0, 22)
	statusContainer.Position = UDim2.new(1, -26, 0, 2)
	statusContainer.BackgroundTransparency = 1
	statusContainer.Parent = header
	local statusIndicator = Instance.new("Frame")
	statusIndicator.Size = UDim2.new(0, 8, 0, 8)
	statusIndicator.Position = UDim2.new(0.5, -4, 0.5, -4)
	statusIndicator.BackgroundColor3 = C.red
	statusIndicator.BorderSizePixel = 0
	statusIndicator.Parent = statusContainer
	local statusCorner = Instance.new("UICorner")
	statusCorner.CornerRadius = UDim.new(1, 0)
	statusCorner.Parent = statusIndicator
	local statusPulse = Instance.new("Frame")
	statusPulse.Size = UDim2.new(0, 10, 0, 10)
	statusPulse.Position = UDim2.new(0, 0, 0, 0)
	statusPulse.BackgroundColor3 = C.red
	statusPulse.BackgroundTransparency = 0.7
	statusPulse.BorderSizePixel = 0
	statusPulse.Parent = statusIndicator
	local pulseCorner = Instance.new("UICorner")
	pulseCorner.CornerRadius = UDim.new(1, 0)
	pulseCorner.Parent = statusPulse
	local statusText = Instance.new("TextLabel")
	statusText.Size = UDim2.new(0, 0, 0, 0)
	statusText.BackgroundTransparency = 1
	statusText.Text = "OFFLINE"
	statusText.TextTransparency = 1
	statusText.TextSize = 1
	statusText.Font = Enum.Font.GothamMedium
	statusText.TextColor3 = C.white
	statusText.Parent = statusContainer
	local updateBanner = Instance.new("Frame")
	updateBanner.Size = UDim2.new(1, -16, 0, 24)
	updateBanner.Position = UDim2.new(0, 8, 0, 42)
	updateBanner.BackgroundColor3 = Color3.fromRGB(40, 32, 10)
	updateBanner.BorderSizePixel = 0
	updateBanner.Visible = false
	updateBanner.Parent = mainFrame
	local updateBannerCorner = Instance.new("UICorner")
	updateBannerCorner.CornerRadius = UDim.new(0, 3)
	updateBannerCorner.Parent = updateBanner
	local updateBannerText = Instance.new("TextLabel")
	updateBannerText.Size = UDim2.new(1, -16, 1, 0)
	updateBannerText.Position = UDim2.new(0, 8, 0, 0)
	updateBannerText.BackgroundTransparency = 1
	updateBannerText.Text = ""
	updateBannerText.TextColor3 = C.yellow
	updateBannerText.TextSize = 9
	updateBannerText.Font = Enum.Font.GothamMedium
	updateBannerText.TextXAlignment = Enum.TextXAlignment.Left
	updateBannerText.Parent = updateBanner
	local contentY = 44
	local contentFrame = Instance.new("ScrollingFrame")
	contentFrame.Size = UDim2.new(1, -16, 1, -(contentY + 8))
	contentFrame.Position = UDim2.new(0, 8, 0, contentY)
	contentFrame.BackgroundTransparency = 1
	contentFrame.BorderSizePixel = 0
	contentFrame.ScrollBarThickness = 2
	contentFrame.ScrollBarImageColor3 = C.subtle
	contentFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	contentFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	contentFrame.Parent = mainFrame
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, 0, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = C.card
	card.BorderSizePixel = 0
	card.LayoutOrder = 1
	card.Parent = contentFrame
	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = CORNER
	cardCorner.Parent = card
	local cardPadding = Instance.new("UIPadding")
	cardPadding.PaddingLeft = UDim.new(0, 10)
	cardPadding.PaddingRight = UDim.new(0, 10)
	cardPadding.PaddingTop = UDim.new(0, 8)
	cardPadding.PaddingBottom = UDim.new(0, 10)
	cardPadding.Parent = card
	local cardLayout = Instance.new("UIListLayout")
	cardLayout.Padding = UDim.new(0, 6)
	cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
	cardLayout.Parent = card
	local urlInput = Instance.new("TextBox")
	urlInput.Size = UDim2.new(1, 0, 0, 26)
	urlInput.BackgroundColor3 = C.bg
	urlInput.BorderSizePixel = 0
	urlInput.Text = State.getActiveConnection().serverUrl
	urlInput.TextColor3 = C.label
	urlInput.TextSize = 11
	urlInput.Font = Enum.Font.GothamMedium
	urlInput.ClearTextOnFocus = false
	urlInput.PlaceholderText = "Server URL..."
	urlInput.PlaceholderColor3 = C.muted
	urlInput.LayoutOrder = 1
	urlInput.Parent = card
	local urlCorner = Instance.new("UICorner")
	urlCorner.CornerRadius = CORNER
	urlCorner.Parent = urlInput
	local urlPadding = Instance.new("UIPadding")
	urlPadding.PaddingLeft = UDim.new(0, 8)
	urlPadding.PaddingRight = UDim.new(0, 8)
	urlPadding.Parent = urlInput
	urlInput.FocusLost:Connect(function()
		local conn = State.getActiveConnection()
		if not conn or conn.isActive then
			return nil
		end
		local normalizedUrl = ServerUrlSettings.normalizeServerUrl(urlInput.Text)
		if normalizedUrl == "" then
			urlInput.Text = conn.serverUrl
			return nil
		end
		conn.serverUrl = normalizedUrl
		urlInput.Text = normalizedUrl
		local port = ServerUrlSettings.extractPort(conn.serverUrl)
		if port ~= nil then
			conn.port = port
		end
	end)
	local statusRow = Instance.new("Frame")
	statusRow.Size = UDim2.new(1, 0, 0, 14)
	statusRow.BackgroundTransparency = 1
	statusRow.LayoutOrder = 2
	statusRow.Parent = card
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Size = UDim2.new(1, 0, 1, 0)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "Disconnected"
	statusLabel.TextColor3 = C.red
	statusLabel.TextSize = 10
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextWrapped = true
	statusLabel.Parent = statusRow
	local detailStatusLabel = Instance.new("TextLabel")
	detailStatusLabel.Size = UDim2.new(0.5, 0, 1, 0)
	detailStatusLabel.Position = UDim2.new(0.5, 0, 0, 0)
	detailStatusLabel.BackgroundTransparency = 1
	detailStatusLabel.Text = "HTTP: X  MCP: X"
	detailStatusLabel.TextColor3 = C.muted
	detailStatusLabel.TextSize = 9
	detailStatusLabel.Font = Enum.Font.GothamMedium
	detailStatusLabel.TextXAlignment = Enum.TextXAlignment.Right
	detailStatusLabel.TextWrapped = true
	detailStatusLabel.Parent = statusRow
	local stepsFrame = Instance.new("Frame")
	stepsFrame.Size = UDim2.new(1, 0, 0, 0)
	stepsFrame.AutomaticSize = Enum.AutomaticSize.Y
	stepsFrame.BackgroundTransparency = 1
	stepsFrame.LayoutOrder = 3
	stepsFrame.Parent = card
	local stepsLayout = Instance.new("UIListLayout")
	stepsLayout.Padding = UDim.new(0, 1)
	stepsLayout.FillDirection = Enum.FillDirection.Vertical
	stepsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	stepsLayout.Parent = stepsFrame
	local function createStepRow(text, order)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 13)
		row.BackgroundTransparency = 1
		row.LayoutOrder = order
		local d = Instance.new("Frame")
		d.Size = UDim2.new(0, 4, 0, 4)
		d.Position = UDim2.new(0, 1, 0, 5)
		d.BackgroundColor3 = C.gray
		d.BorderSizePixel = 0
		d.Parent = row
		local dCorner = Instance.new("UICorner")
		dCorner.CornerRadius = UDim.new(1, 0)
		dCorner.Parent = d
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, -12, 1, 0)
		lbl.Position = UDim2.new(0, 12, 0, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text = text
		lbl.TextColor3 = C.dim
		lbl.TextSize = 9
		lbl.Font = Enum.Font.GothamMedium
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Parent = row
		row.Parent = stepsFrame
		return { row, d, lbl }
	end
	local binding = createStepRow("HTTP server", 1)
	local step1Dot = binding[2]
	local step1Label = binding[3]
	local binding_1 = createStepRow("MCP bridge", 2)
	local step2Dot = binding_1[2]
	local step2Label = binding_1[3]
	local binding_2 = createStepRow("Commands", 3)
	local step3Dot = binding_2[2]
	local step3Label = binding_2[3]
	local troubleshootLabel = Instance.new("TextLabel")
	troubleshootLabel.Size = UDim2.new(1, 0, 0, 24)
	troubleshootLabel.BackgroundTransparency = 1
	troubleshootLabel.TextWrapped = true
	troubleshootLabel.Visible = false
	troubleshootLabel.Text = "MCP not responding. Close node.exe and restart server."
	troubleshootLabel.TextColor3 = C.yellow
	troubleshootLabel.TextSize = 9
	troubleshootLabel.Font = Enum.Font.GothamMedium
	troubleshootLabel.TextXAlignment = Enum.TextXAlignment.Left
	troubleshootLabel.LayoutOrder = 4
	troubleshootLabel.Parent = card
	local connectButton = Instance.new("TextButton")
	connectButton.Size = UDim2.new(1, 0, 0, 28)
	connectButton.BackgroundColor3 = C.surface
	connectButton.BackgroundTransparency = 0
	connectButton.BorderSizePixel = 0
	connectButton.Text = "Connect"
	connectButton.TextColor3 = C.white
	connectButton.TextSize = 11
	connectButton.Font = Enum.Font.GothamBold
	connectButton.LayoutOrder = 5
	connectButton.Parent = card
	local connectCorner = Instance.new("UICorner")
	connectCorner.CornerRadius = CORNER
	connectCorner.Parent = connectButton
	local connectStroke = Instance.new("UIStroke")
	connectStroke.Color = C.subtle
	connectStroke.Thickness = 1
	connectStroke.Parent = connectButton
	connectButton.MouseEnter:Connect(function()
		buttonHover = true
		local conn = State.getActiveConnection()
		if conn and conn.isActive then
			tweenProp(connectButton, {
				BackgroundColor3 = C.surface,
			})
			tweenProp(connectStroke, {
				Color = Color3.fromRGB(100, 35, 35),
			})
		else
			tweenProp(connectButton, {
				BackgroundColor3 = C.subtle,
			})
			tweenProp(connectStroke, {
				Color = C.muted,
			})
		end
	end)
	connectButton.MouseLeave:Connect(function()
		buttonHover = false
		local conn = State.getActiveConnection()
		if conn and conn.isActive then
			setButtonDisconnect(connectButton, connectStroke)
		else
			setButtonConnect(connectButton, connectStroke)
		end
	end)
	elements = {
		screenGui = screenGui,
		mainFrame = mainFrame,
		contentFrame = contentFrame,
		statusLabel = statusLabel,
		detailStatusLabel = detailStatusLabel,
		statusIndicator = statusIndicator,
		statusPulse = statusPulse,
		statusText = statusText,
		connectButton = connectButton,
		connectStroke = connectStroke,
		urlInput = urlInput,
		step1Dot = step1Dot,
		step1Label = step1Label,
		step2Dot = step2Dot,
		step2Label = step2Label,
		step3Dot = step3Dot,
		step3Label = step3Label,
		troubleshootLabel = troubleshootLabel,
		updateBanner = updateBanner,
		updateBannerText = updateBannerText,
	}
end
local function updateUIState()
	updateToolbarIcon()
	local conn = State.getActiveConnection()
	if not conn then
		return nil
	end
	local el = elements
	if not conn.isActive then
		el.statusLabel.Text = "Disconnected"
		el.statusLabel.TextColor3 = C.muted
		el.statusIndicator.BackgroundColor3 = C.red
		el.statusPulse.BackgroundColor3 = C.red
		el.statusText.Text = "OFFLINE"
		el.detailStatusLabel.Text = ""
		el.detailStatusLabel.TextColor3 = C.muted
		stopPulseAnimation()
		el.step1Dot.BackgroundColor3 = C.gray
		el.step1Label.Text = "HTTP server"
		el.step2Dot.BackgroundColor3 = C.gray
		el.step2Label.Text = "MCP bridge"
		el.step3Dot.BackgroundColor3 = C.gray
		el.step3Label.Text = "Commands"
		el.troubleshootLabel.Visible = false
		if not buttonHover then
			setButtonConnect(el.connectButton, el.connectStroke)
		end
		el.urlInput.TextEditable = true
		el.urlInput.BackgroundColor3 = C.bg
		return nil
	end
	if not buttonHover then
		setButtonDisconnect(el.connectButton, el.connectStroke)
	end
	el.urlInput.TextEditable = false
	el.urlInput.BackgroundColor3 = C.card
	if conn.lastHttpOk and conn.lastMcpOk then
		el.statusLabel.Text = "Connected"
		el.statusLabel.TextColor3 = Color3.fromRGB(34, 197, 94)
		el.statusIndicator.BackgroundColor3 = Color3.fromRGB(34, 197, 94)
		el.statusPulse.BackgroundColor3 = Color3.fromRGB(34, 197, 94)
		el.statusText.Text = "ONLINE"
		el.detailStatusLabel.Text = "HTTP: OK  MCP: OK"
		el.detailStatusLabel.TextColor3 = Color3.fromRGB(34, 197, 94)
		el.step1Dot.BackgroundColor3 = Color3.fromRGB(34, 197, 94)
		el.step1Label.Text = "HTTP server (OK)"
		el.step2Dot.BackgroundColor3 = Color3.fromRGB(34, 197, 94)
		el.step2Label.Text = "MCP bridge (OK)"
		el.step3Dot.BackgroundColor3 = Color3.fromRGB(34, 197, 94)
		el.step3Label.Text = "Commands (OK)"
		el.troubleshootLabel.Visible = false
		stopPulseAnimation()
	elseif conn.lastHttpOk and not conn.lastMcpOk then
		el.statusLabel.Text = "Waiting for MCP server"
		el.statusLabel.TextColor3 = Color3.fromRGB(245, 158, 11)
		el.statusIndicator.BackgroundColor3 = Color3.fromRGB(245, 158, 11)
		el.statusPulse.BackgroundColor3 = Color3.fromRGB(245, 158, 11)
		el.statusText.Text = "WAITING"
		el.detailStatusLabel.Text = "HTTP: OK  MCP: ..."
		el.detailStatusLabel.TextColor3 = Color3.fromRGB(245, 158, 11)
		el.step1Dot.BackgroundColor3 = Color3.fromRGB(34, 197, 94)
		el.step1Label.Text = "HTTP server (OK)"
		el.step2Dot.BackgroundColor3 = Color3.fromRGB(245, 158, 11)
		el.step2Label.Text = "MCP bridge (waiting...)"
		el.step3Dot.BackgroundColor3 = Color3.fromRGB(245, 158, 11)
		el.step3Label.Text = "Commands (waiting...)"
		local elapsed = if conn.mcpWaitStartTime ~= nil then tick() - conn.mcpWaitStartTime else 0
		el.troubleshootLabel.Visible = elapsed > 8
		startPulseAnimation()
	elseif conn.consecutiveFailures >= conn.maxFailuresBeforeError then
		el.statusLabel.Text = "Server unavailable"
		el.statusLabel.TextColor3 = Color3.fromRGB(239, 68, 68)
		el.statusIndicator.BackgroundColor3 = Color3.fromRGB(239, 68, 68)
		el.statusPulse.BackgroundColor3 = Color3.fromRGB(239, 68, 68)
		el.statusText.Text = "ERROR"
		el.detailStatusLabel.Text = "HTTP: X  MCP: X"
		el.detailStatusLabel.TextColor3 = Color3.fromRGB(239, 68, 68)
		el.step1Dot.BackgroundColor3 = Color3.fromRGB(239, 68, 68)
		el.step1Label.Text = "HTTP server (error)"
		el.step2Dot.BackgroundColor3 = Color3.fromRGB(239, 68, 68)
		el.step2Label.Text = "MCP bridge (error)"
		el.step3Dot.BackgroundColor3 = Color3.fromRGB(239, 68, 68)
		el.step3Label.Text = "Commands (error)"
		el.troubleshootLabel.Visible = false
		stopPulseAnimation()
	elseif conn.consecutiveFailures > 5 then
		local waitTime = math.ceil(conn.currentRetryDelay)
		el.statusLabel.Text = `Retrying ({waitTime}s)`
		el.statusLabel.TextColor3 = Color3.fromRGB(245, 158, 11)
		el.statusIndicator.BackgroundColor3 = Color3.fromRGB(245, 158, 11)
		el.statusPulse.BackgroundColor3 = Color3.fromRGB(245, 158, 11)
		el.statusText.Text = "RETRY"
		el.detailStatusLabel.Text = "HTTP: ...  MCP: ..."
		el.detailStatusLabel.TextColor3 = Color3.fromRGB(245, 158, 11)
		el.step1Dot.BackgroundColor3 = Color3.fromRGB(245, 158, 11)
		el.step1Label.Text = "HTTP server (retrying...)"
		el.step2Dot.BackgroundColor3 = Color3.fromRGB(245, 158, 11)
		el.step2Label.Text = "MCP bridge (retrying...)"
		el.step3Dot.BackgroundColor3 = Color3.fromRGB(245, 158, 11)
		el.step3Label.Text = "Commands (retrying...)"
		el.troubleshootLabel.Visible = false
		startPulseAnimation()
	else
		el.statusLabel.Text = if conn.consecutiveFailures > 1
			then `Connecting (attempt {conn.consecutiveFailures})`
			else "Connecting..."
		el.statusLabel.TextColor3 = C.yellow
		el.statusIndicator.BackgroundColor3 = C.yellow
		el.statusPulse.BackgroundColor3 = C.yellow
		el.statusText.Text = "CONNECTING"
		el.detailStatusLabel.Text = if conn.consecutiveFailures == 0 then "..." else "HTTP: ...  MCP: ..."
		el.detailStatusLabel.TextColor3 = C.muted
		el.step1Dot.BackgroundColor3 = C.yellow
		el.step1Label.Text = "HTTP server (connecting...)"
		el.step2Dot.BackgroundColor3 = C.yellow
		el.step2Label.Text = "MCP bridge (connecting...)"
		el.step3Dot.BackgroundColor3 = C.yellow
		el.step3Label.Text = "Commands (connecting...)"
		el.troubleshootLabel.Visible = false
		startPulseAnimation()
	end
end
return {
	elements = nil,
	init = init,
	updateUIState = updateUIState,
	stopPulseAnimation = stopPulseAnimation,
	startPulseAnimation = startPulseAnimation,
	setToolbarButton = setToolbarButton,
	updateToolbarIcon = updateToolbarIcon,
	showBanner = showBanner,
	hideBanner = hideBanner,
	getElements = function()
		return elements
	end,
}
