--!strict
--[[
	BallThrowTouchUI.luau
	Ergonomic mobile touch controls (Throw / Hold-to-Aim + Dash button with cooldown)
	and crisp center hit-marker feedback for both Mobile & PC viewports.
]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

export type TouchCallbacks = {
	onAimBegan: () -> (),
	onThrowReleased: () -> (),
	onDashPressed: () -> (),
}

export type TouchUIHandle = {
	setDashCooldown: (remaining: number, total: number) -> (),
	setTrainingMode: (isOnPad: boolean) -> (),
	flashHitMarker: (isImportant: boolean?) -> (),
	destroy: () -> (),
}

local BallThrowTouchUI = {}

local function makeCorner(parent: Instance, radius: UDim)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = parent
end

local function makeStroke(parent: Instance, color: Color3, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Parent = parent
end

local function buildHitMarker(parent: ScreenGui): Frame
	local container = Instance.new("Frame")
	container.Name = "HitMarker"
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.Position = UDim2.fromScale(0.5, 0.5)
	container.Size = UDim2.fromOffset(26, 26)
	container.BackgroundTransparency = 1
	container.Visible = false
	container.Parent = parent

	local angles = { 45, 135, 225, 315 }
	for idx, deg in ipairs(angles) do
		local tick = Instance.new("Frame")
		tick.Name = `Tick_{idx}`
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		local rad = math.rad(deg)
		tick.Position = UDim2.new(0.5, math.cos(rad) * 7, 0.5, math.sin(rad) * 7)
		tick.Size = UDim2.fromOffset(10, 3)
		tick.Rotation = deg
		tick.BorderSizePixel = 0
		tick.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		tick.Parent = container
	end
	return container
end

local function buildTouchButton(
	parent: Instance,
	name: string,
	label: string,
	sizePx: number,
	pos: UDim2,
	fillColor: Color3
): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = pos
	button.Size = UDim2.fromOffset(sizePx, sizePx)
	button.BackgroundColor3 = fillColor
	button.BackgroundTransparency = 0.14
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 14
	button.Text = label
	button.AutoButtonColor = true
	button.Parent = parent
	makeCorner(button, UDim.new(1, 0))
	makeStroke(button, Color3.fromRGB(255, 255, 255), 2)
	return button
end

local function isPointerInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.Touch
		or input.UserInputType == Enum.UserInputType.MouseButton1
end

local function buildTouchControls(
	parent: ScreenGui,
	callbacks: TouchCallbacks
): (Frame, TextButton, TextButton)
	local holder = Instance.new("Frame")
	holder.Name = "MobileTouchControls"
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.Visible = UserInputService.TouchEnabled
	holder.Parent = parent

	-- Placed comfortably above/left of Roblox's default bottom-right Jump button
	local throwBtn = buildTouchButton(
		holder,
		"ThrowButton",
		"THROW",
		74,
		UDim2.new(1, -24, 1, -118),
		Color3.fromRGB(245, 118, 36)
	)
	local dashBtn = buildTouchButton(
		holder,
		"DashButton",
		"DASH",
		58,
		UDim2.new(1, -112, 1, -76),
		Color3.fromRGB(48, 138, 240)
	)

	throwBtn.InputBegan:Connect(function(input: InputObject)
		if isPointerInput(input) then
			callbacks.onAimBegan()
		end
	end)
	throwBtn.InputEnded:Connect(function(input: InputObject)
		if isPointerInput(input) then
			callbacks.onThrowReleased()
		end
	end)
	dashBtn.MouseButton1Down:Connect(callbacks.onDashPressed)

	return holder, throwBtn, dashBtn
end

local function createHitMarkerFlasher(hitMarker: Frame): (isImportant: boolean?) -> ()
	local flashSerial = 0
	return function(isImportant: boolean?)
		flashSerial += 1
		local currentSerial = flashSerial
		local tint = if isImportant
			then Color3.fromRGB(255, 214, 72)
			else Color3.fromRGB(255, 255, 255)
		hitMarker.Visible = true
		hitMarker.Size = UDim2.fromOffset(34, 34)
		for _, child in ipairs(hitMarker:GetChildren()) do
			if child:IsA("Frame") then
				child.BackgroundColor3 = tint
				child.BackgroundTransparency = 0
			end
		end
		TweenService:Create(
			hitMarker,
			TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.fromOffset(22, 22) }
		):Play()
		task.delay(0.18, function()
			if flashSerial == currentSerial then
				hitMarker.Visible = false
			end
		end)
	end
end

function BallThrowTouchUI.mount(playerGui: PlayerGui, callbacks: TouchCallbacks): TouchUIHandle
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BallBrawl_CombatHUD"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.DisplayOrder = 15
	screenGui.Parent = playerGui

	local hitMarker = buildHitMarker(screenGui)
	local touchHolder, _throwBtn, dashBtn = buildTouchControls(screenGui, callbacks)
	local touchConn = UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(function()
		touchHolder.Visible = UserInputService.TouchEnabled
	end)

	return {
		setDashCooldown = function(remaining: number, _total: number)
			if remaining > 0.05 then
				dashBtn.Text = string.format("%.1fs", remaining)
				dashBtn.BackgroundTransparency = 0.52
			else
				dashBtn.Text = "DASH"
				dashBtn.BackgroundTransparency = 0.14
			end
		end,
		setTrainingMode = function(isOnPad: boolean)
			dashBtn.Visible = not isOnPad
		end,
		flashHitMarker = createHitMarkerFlasher(hitMarker),
		destroy = function()
			touchConn:Disconnect()
			screenGui:Destroy()
		end,
	}
end

return BallThrowTouchUI
