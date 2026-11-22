--!strict
--[[
	MockHarnessPanel.luau
	Lightweight, Studio-only collapsible preview toolbar so Dev B can interactively
	toggle MockStateHarness simulations (Opt-In modal, 5s Claim, Cash Pads, PolicyService).
]]

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local MockHarnessPanel = {}

local function createButton(
	parent: Instance,
	text: string,
	order: number,
	onClick: () -> ()
): TextButton
	local button = Instance.new("TextButton")
	button.Name = `MockBtn_{order}`
	button.LayoutOrder = order
	button.Size = UDim2.new(1, 0, 0, 30)
	button.BackgroundColor3 = Color3.fromRGB(36, 42, 56)
	button.TextColor3 = Color3.fromRGB(240, 244, 255)
	button.Font = Enum.Font.GothamMedium
	button.TextSize = 13
	button.Text = text
	button.AutoButtonColor = true
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button

	button.MouseButton1Click:Connect(onClick)
	return button
end

local function addCorner(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function createTogglePill(screenGui: ScreenGui): TextButton
	local togglePill = Instance.new("TextButton")
	togglePill.Name = "TogglePill"
	togglePill.AnchorPoint = Vector2.new(1, 0)
	togglePill.Position = UDim2.new(1, -12, 0, 12)
	togglePill.Size = UDim2.fromOffset(172, 32)
	togglePill.BackgroundColor3 = Color3.fromRGB(24, 30, 42)
	togglePill.TextColor3 = Color3.fromRGB(255, 214, 102)
	togglePill.Font = Enum.Font.GothamBold
	togglePill.TextSize = 13
	togglePill.Text = "Mock Harness [OFF]"
	togglePill.Parent = screenGui
	addCorner(togglePill, 8)
	return togglePill
end

local function createDrawer(screenGui: ScreenGui): (Frame, TextLabel)
	local drawer = Instance.new("Frame")
	drawer.Name = "Drawer"
	drawer.AnchorPoint = Vector2.new(1, 0)
	drawer.Position = UDim2.new(1, -12, 0, 50)
	drawer.Size = UDim2.fromOffset(220, 316)
	drawer.BackgroundColor3 = Color3.fromRGB(18, 22, 32)
	drawer.BackgroundTransparency = 0.08
	drawer.Visible = false
	drawer.Parent = screenGui
	addCorner(drawer, 10)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = drawer

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = drawer

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.LayoutOrder = 0
	statusLabel.Size = UDim2.new(1, 0, 0, 24)
	statusLabel.BackgroundTransparency = 1
	statusLabel.TextColor3 = Color3.fromRGB(168, 212, 255)
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextSize = 12
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.Text = "Phase: PvE_Open | Policy: Open"
	statusLabel.Parent = drawer

	return drawer, statusLabel
end

local function createContainer(screenGui: ScreenGui): (TextButton, Frame, TextLabel)
	local togglePill = createTogglePill(screenGui)
	local drawer, statusLabel = createDrawer(screenGui)
	return togglePill, drawer, statusLabel
end

local function wireActions(drawer: Frame, harness: any, refreshLabels: () -> ())
	createButton(drawer, "Toggle Mock Mode", 1, function()
		harness:toggle()
		refreshLabels()
	end)
	createButton(drawer, "Opt-In Modal (Meadow)", 2, function()
		harness:setEnabled(true)
		harness:triggerOptInModal({ biomeId = "EmeraldMeadow", isOvercharged = false })
		refreshLabels()
	end)
	createButton(drawer, "Opt-In (5m Overcharged)", 3, function()
		harness:setEnabled(true)
		harness:triggerOptInModal({
			biomeId = "EmeraldMeadow",
			isOvercharged = true,
			queuedPlayers = 5,
			highestPowerRating = 2400,
		})
		refreshLabels()
	end)
	createButton(drawer, "Start 5.0s Egg Claim", 4, function()
		harness:setEnabled(true)
		harness:startEggClaim("EmeraldMeadow")
		refreshLabels()
	end)
	createButton(drawer, "Interrupt Claim (PvP Dmg)", 5, function()
		harness:interruptEggClaim("PvPDamage")
		refreshLabels()
	end)
	createButton(drawer, "Simulate +6h Offline Pads", 6, function()
		harness:setEnabled(true)
		harness:simulateOfflineAccrual(6 * 3600)
		refreshLabels()
	end)
	createButton(drawer, "Sweep Cash Pad #1", 7, function()
		harness:sweepCashPad(1)
		refreshLabels()
	end)
	createButton(drawer, "Toggle Policy Restricted", 8, function()
		harness:setEnabled(true)
		harness:setPolicyRestricted(not harness:isPolicyRestricted())
		refreshLabels()
	end)
end

function MockHarnessPanel.mount(playerGui: PlayerGui, harness: any): (() -> ())?
	if not RunService:IsStudio() or not harness or not harness:isAllowed() then
		return nil
	end
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BallBrawl_StudioMockHarness"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 999
	screenGui.Parent = playerGui

	local togglePill, drawer, statusLabel = createContainer(screenGui)
	local function refreshLabels()
		local snap = harness:getSnapshot()
		local modeTag = if snap.isEnabled then "ON" else "OFF"
		local policyTag = if snap.policyRestricted then "Restricted" else "Open"
		togglePill.Text = `Mock Harness [{modeTag}]`
		statusLabel.Text = `Phase: {snap.arenaPhase} | Policy: {policyTag}`
	end

	togglePill.MouseButton1Click:Connect(function()
		drawer.Visible = not drawer.Visible
		refreshLabels()
	end)
	wireActions(drawer, harness, refreshLabels)
	refreshLabels()

	local keyConn = UserInputService.InputBegan:Connect(function(input: InputObject, gp: boolean)
		if not gp and input.KeyCode == Enum.KeyCode.F8 then
			drawer.Visible = not drawer.Visible
			refreshLabels()
		end
	end)

	return function()
		keyConn:Disconnect()
		screenGui:Destroy()
	end
end

return MockHarnessPanel
