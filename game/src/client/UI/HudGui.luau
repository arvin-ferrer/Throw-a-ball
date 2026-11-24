--!strict
--[[
	HudGui.luau
	Responsive mobile-first HUD matching the obsidian-slate glass layout:
	- Top-Left: Stacked Coins & Gems capsules with crisp vector icons
	- Top-Right: Compact Audio pill + contextual Hub Plot return pill
	- Mid-Left: Collapsible 2x2 tile drawer (Shop, Pets, Upgrades, Codex) with < / > tab
	- Bottom-Center: Hero Status Dock (LV, live Humanoid HP bar, PWR / DMG / SPD pills)
	- Bottom-Right: Ergonomic thumb-arc (AUTO AIM toggle, DASH circle, THROW hero circle, JUMP circle)
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MathUtil = require(Shared.Utils.MathUtil)
local AudioCatalog = require(Shared.Utils.AudioCatalog)
local OnboardingLogic = require(Shared.Utils.OnboardingLogic)
local Remotes = require(Shared.Net.Remotes)

local Theme = require(script.Parent.Theme)
local HudIcons = require(script.Parent.HudIcons)

local HudGui = {}

local localPlayer = Players.LocalPlayer
local hudScreen: ScreenGui? = nil

-- Top-left currency labels
local currencyStack: Frame? = nil
local coinsValLabel: TextLabel? = nil
local gemsValLabel: TextLabel? = nil

-- Top-right audio & hub return
local topRightStack: Frame? = nil
local audioBtn: TextButton? = nil
local audioLabel: TextLabel? = nil
local speakerIcon: Frame? = nil
local hubReturnBtn: TextButton? = nil

-- Mid-left collapsible 2x2 drawer
local drawerWrap: Frame? = nil
local drawerPanel: Frame? = nil
local drawerGrid: UIGridLayout? = nil
local drawerTabBtn: TextButton? = nil
local drawerTabLbl: TextLabel? = nil
local drawerOpen = true
local drawerTileButtons: { TextButton } = {}

-- Bottom-center Hero Status Dock
local statusDock: Frame? = nil
local levelLabel: TextLabel? = nil
local hpFillBar: Frame? = nil
local hpFillGrad: UIGradient? = nil
local hpValueLabel: TextLabel? = nil
local pwrLabel: TextLabel? = nil
local dmgLabel: TextLabel? = nil
local spdLabel: TextLabel? = nil
local profileMaxHP = 100
local humHealthConn: RBXScriptConnection? = nil
local humMaxHealthConn: RBXScriptConnection? = nil

-- Guide & AFK banners above Hero Status Dock
local guideFrame: Frame? = nil
local guideBanner: TextLabel? = nil
local afkBadgeFrame: Frame? = nil

-- Bottom-right combat thumb-arc
local actionHolder: Frame? = nil
local autoAimBtn: TextButton? = nil
local autoAimReticle: Frame? = nil
local autoAimStateLbl: TextLabel? = nil
local dashBtn: TextButton? = nil
local dashTextLbl: TextLabel? = nil
local dashSubLbl: TextLabel? = nil
local throwBtn: TextButton? = nil
local throwTextLbl: TextLabel? = nil
local jumpActionBtn: TextButton? = nil
local isAutoAimOn = false
local isJumpHeld = false
local jumpPulseUntil = 0

-- Callbacks
local throwCallback: (() -> ())? = nil
local throwHoldCallback: ((boolean) -> ())? = nil
local dashCallback: (() -> ())? = nil
local toggleAutoAimCallback: (() -> ())? = nil
local openModalCallback: ((string) -> ())? = nil

local function updateHumanoidHpBar()
	if not hpFillBar or not hpValueLabel then
		return
	end
	local char = localPlayer.Character
	local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
	local cur = if hum then math.max(0, math.floor(hum.Health + 0.5)) else profileMaxHP
	local mx = if hum
		then math.max(1, math.floor(hum.MaxHealth + 0.5))
		else math.max(1, profileMaxHP)
	local frac = math.clamp(cur / mx, 0, 1)
	hpFillBar.Size = UDim2.fromScale(frac, 1)
	hpValueLabel.Text = `{cur} / {mx} HP`
	if hpFillGrad then
		if frac <= 0.25 then
			hpFillGrad.Color =
				ColorSequence.new(Color3.fromRGB(255, 118, 108), Color3.fromRGB(214, 44, 44))
		elseif frac <= 0.50 then
			hpFillGrad.Color =
				ColorSequence.new(Color3.fromRGB(255, 212, 84), Color3.fromRGB(224, 134, 24))
		else
			hpFillGrad.Color =
				ColorSequence.new(Color3.fromRGB(112, 244, 134), Color3.fromRGB(46, 196, 82))
		end
	end
end

local function bindCharacterHealth(char: Model?)
	if humHealthConn then
		humHealthConn:Disconnect()
		humHealthConn = nil
	end
	if humMaxHealthConn then
		humMaxHealthConn:Disconnect()
		humMaxHealthConn = nil
	end
	if not char then
		updateHumanoidHpBar()
		return
	end
	local hum = char:WaitForChild("Humanoid", 5)
	if hum and hum:IsA("Humanoid") then
		humHealthConn = hum:GetPropertyChangedSignal("Health"):Connect(updateHumanoidHpBar)
		humMaxHealthConn = hum:GetPropertyChangedSignal("MaxHealth"):Connect(updateHumanoidHpBar)
		updateHumanoidHpBar()
	end
end

local function buildCurrencyStack(gui: ScreenGui)
	local stack = Instance.new("Frame")
	stack.Name = "CurrencyStack"
	stack.BackgroundTransparency = 1
	stack.Position = UDim2.fromOffset(14, 8)
	stack.Size = UDim2.fromOffset(140, 80)
	stack.Parent = gui
	currencyStack = stack

	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = stack

	local function makePill(
		name: string,
		order: number,
		color: Color3,
		iconMaker: (Instance, number) -> Frame
	): TextLabel
		local pill = Theme.makeGlossyPanel(
			stack,
			name,
			UDim2.fromOffset(132, 34),
			UDim2.fromOffset(0, 0),
			999
		)
		pill.LayoutOrder = order
		local icon = iconMaker(pill, 22)
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 7, 0.5, 0)
		local val = Theme.makeLabel(
			pill,
			"Value",
			"0",
			UDim2.new(1, -38, 1, 0),
			UDim2.fromOffset(34, 0),
			17,
			color,
			true
		)
		return val
	end

	coinsValLabel = makePill("CoinsPill", 1, Theme.Colors.Coins, HudIcons.createCoinIcon)
	gemsValLabel = makePill("GemsPill", 2, Theme.Colors.Gems, HudIcons.createGemIcon)
end

local function buildTopRight(gui: ScreenGui)
	local stack = Instance.new("Frame")
	stack.Name = "TopRightStack"
	stack.BackgroundTransparency = 1
	stack.AnchorPoint = Vector2.new(1, 0)
	stack.Position = UDim2.new(1, -14, 0, 8)
	stack.Size = UDim2.fromOffset(140, 86)
	stack.Parent = gui
	topRightStack = stack

	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Right
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = stack

	local btn = Instance.new("TextButton")
	btn.Name = "AudioToggleBtn"
	btn.Size = UDim2.fromOffset(132, 34)
	btn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	btn.BackgroundTransparency = 0.05
	btn.Text = ""
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = true
	btn.LayoutOrder = 1
	btn.Parent = stack
	Theme.addCorner(btn, 999)
	Theme.addGradient(btn, Theme.Colors.PanelTop, Theme.Colors.PanelBottom, 90)
	Theme.addStroke(btn, Theme.Colors.Stroke, 1.5, 0.08)

	local spk = HudIcons.createSpeakerIcon(btn, 18)
	spk.AnchorPoint = Vector2.new(0, 0.5)
	spk.Position = UDim2.new(0, 10, 0.5, 0)
	speakerIcon = spk

	local lbl = Theme.makeLabel(
		btn,
		"Label",
		"AUDIO: LOW",
		UDim2.new(1, -34, 1, 0),
		UDim2.fromOffset(32, 0),
		12,
		Theme.Colors.Text,
		true
	)
	audioLabel = lbl
	audioBtn = btn

	btn.Activated:Connect(function()
		local modeLabel = AudioCatalog.cycleAudioMode()
		lbl.Text = modeLabel
		local muted = AudioCatalog.isMuted()
		HudIcons.setSpeakerMuted(speakerIcon, muted)
		Theme.addStroke(btn, if muted then Theme.Colors.Danger else Theme.Colors.Stroke, 1.5, 0.08)
	end)

	local ret = Theme.makeButton(
		stack,
		"ReturnHubBtn",
		"",
		UDim2.fromOffset(124, 34),
		UDim2.fromOffset(0, 0),
		Color3.fromRGB(255, 255, 255),
		function()
			Remotes.waitClient().TeleportZone:FireServer("Hub")
		end
	)
	ret.LayoutOrder = 2
	ret.Visible = false
	Theme.addCorner(ret, 999)
	Theme.addGradient(ret, Color3.fromRGB(246, 134, 48), Color3.fromRGB(204, 82, 22), 90)
	Theme.addStroke(ret, Color3.fromRGB(255, 198, 128), 1.5, 0.15)
	local retLbl = Theme.makeLabel(
		ret,
		"Label",
		"HUB PLOT",
		UDim2.fromScale(1, 1),
		UDim2.fromOffset(0, 0),
		13,
		Theme.Colors.Text,
		true
	)
	retLbl.TextXAlignment = Enum.TextXAlignment.Center
	hubReturnBtn = ret
end

local function updateDrawerSlide(instant: boolean)
	if not drawerWrap or not drawerPanel or not drawerTabBtn then
		return
	end
	local panelW = drawerPanel.Size.X.Offset
	local targetX = if drawerOpen then 0 else -panelW
	if drawerTabLbl then
		drawerTabLbl.Text = if drawerOpen then "<" else ">"
	end
	local targetPos =
		UDim2.new(0, targetX, drawerWrap.Position.Y.Scale, drawerWrap.Position.Y.Offset)
	if instant or GuiService.ReducedMotionEnabled then
		drawerWrap.Position = targetPos
	else
		TweenService:Create(
			drawerWrap,
			TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Position = targetPos }
		):Play()
	end
end

local function buildMenuDrawer(gui: ScreenGui)
	local wrap = Instance.new("Frame")
	wrap.Name = "MenuDrawerWrap"
	wrap.BackgroundTransparency = 1
	wrap.AnchorPoint = Vector2.new(0, 0.5)
	wrap.Position = UDim2.fromScale(0, 0.44)
	wrap.Size = UDim2.fromOffset(204, 178)
	wrap.Parent = gui
	drawerWrap = wrap

	local panel = Theme.makeGlossyPanel(
		wrap,
		"MenuPanel",
		UDim2.fromOffset(176, 178),
		UDim2.fromOffset(0, 0),
		16
	)
	drawerPanel = panel
	Theme.addPadding(panel, 10)

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(74, 74)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = panel
	drawerGrid = grid

	local tiles = {
		{
			id = "Shop",
			label = "SHOP",
			top = Color3.fromRGB(168, 130, 42),
			bot = Color3.fromRGB(98, 72, 20),
			stroke = Color3.fromRGB(238, 196, 86),
			icon = HudIcons.createShopIcon,
		},
		{
			id = "Pets",
			label = "PETS",
			top = Color3.fromRGB(46, 152, 88),
			bot = Color3.fromRGB(24, 92, 54),
			stroke = Color3.fromRGB(94, 232, 146),
			icon = HudIcons.createPetsIcon,
		},
		{
			id = "Upgrades",
			label = "UPGRADES",
			top = Color3.fromRGB(44, 118, 194),
			bot = Color3.fromRGB(24, 68, 128),
			stroke = Color3.fromRGB(98, 192, 255),
			icon = HudIcons.createUpgradesIcon,
		},
		{
			id = "Codex",
			label = "CODEX",
			top = Color3.fromRGB(124, 72, 194),
			bot = Color3.fromRGB(70, 36, 128),
			stroke = Color3.fromRGB(186, 128, 255),
			icon = HudIcons.createCodexIcon,
		},
	}

	table.clear(drawerTileButtons)
	for i, t in ipairs(tiles) do
		local tile = Instance.new("TextButton")
		tile.Name = t.id .. "Btn"
		tile.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		tile.Text = ""
		tile.BorderSizePixel = 0
		tile.AutoButtonColor = true
		tile.LayoutOrder = i
		tile.Parent = panel
		Theme.addCorner(tile, 12)
		Theme.addGradient(tile, t.top, t.bot, 90)
		Theme.addStroke(tile, t.stroke, 2.0, 0.1)

		local ic = t.icon(tile, 36)
		ic.Name = "TileIcon"
		ic.AnchorPoint = Vector2.new(0.5, 0)
		ic.Position = UDim2.new(0.5, 0, 0, 8)

		local lbl = Theme.makeLabel(
			tile,
			"TileText",
			t.label,
			UDim2.new(1, -6, 0, 18),
			UDim2.new(0, 3, 1, -21),
			11,
			Theme.Colors.Text,
			true
		)
		lbl.TextXAlignment = Enum.TextXAlignment.Center
		lbl.TextScaled = true
		local tc = Instance.new("UITextSizeConstraint")
		tc.MaxTextSize = 12
		tc.MinTextSize = 9
		tc.Parent = lbl

		tile.Activated:Connect(function()
			if openModalCallback then
				openModalCallback(t.id)
			end
		end)
		table.insert(drawerTileButtons, tile)
	end

	local tab = Instance.new("TextButton")
	tab.Name = "CollapseTab"
	tab.AnchorPoint = Vector2.new(0, 0.5)
	tab.Position = UDim2.new(0, 174, 0.5, 0)
	tab.Size = UDim2.fromOffset(26, 52)
	tab.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	tab.BackgroundTransparency = 0.05
	tab.Text = ""
	tab.BorderSizePixel = 0
	tab.AutoButtonColor = true
	tab.AutoLocalize = false
	tab.Parent = wrap
	Theme.addCorner(tab, 10)
	Theme.addGradient(tab, Theme.Colors.PanelTop, Theme.Colors.PanelBottom, 90)
	Theme.addStroke(tab, Theme.Colors.Stroke, 1.5, 0.08)

	local tabLbl = Theme.makeLabel(
		tab,
		"Arrow",
		"<",
		UDim2.fromScale(1, 1),
		UDim2.fromOffset(0, 0),
		20,
		Theme.Colors.Text,
		true
	)
	tabLbl.TextXAlignment = Enum.TextXAlignment.Center
	drawerTabLbl = tabLbl

	tab.Activated:Connect(function()
		drawerOpen = not drawerOpen
		updateDrawerSlide(false)
	end)
	drawerTabBtn = tab
end

local function buildHeroStatusDock(gui: ScreenGui)
	local dock = Theme.makeGlossyPanel(
		gui,
		"HeroStatusDock",
		UDim2.fromOffset(420, 84),
		UDim2.new(0.5, 0, 1, -14),
		16
	)
	dock.AnchorPoint = Vector2.new(0.5, 1)
	statusDock = dock

	-- Top Row: LV badge + Live HP bar
	local topRow = Instance.new("Frame")
	topRow.Name = "TopRow"
	topRow.BackgroundTransparency = 1
	topRow.Position = UDim2.fromOffset(12, 8)
	topRow.Size = UDim2.new(1, -24, 0, 30)
	topRow.Parent = dock

	local lv = Theme.makeLabel(
		topRow,
		"LevelLabel",
		"LV 1",
		UDim2.fromOffset(66, 30),
		UDim2.fromOffset(0, 0),
		21,
		Theme.Colors.Text,
		true
	)
	levelLabel = lv

	local hpTrack = Theme.makeFrame(
		topRow,
		"HpTrack",
		UDim2.new(1, -72, 0, 26),
		UDim2.new(0, 72, 0.5, -13),
		Theme.Colors.Card,
		9
	)
	hpTrack.ClipsDescendants = true
	Theme.addStroke(hpTrack, Theme.Colors.Stroke, 1.4, 0.15)

	local fill = Instance.new("Frame")
	fill.Name = "HpFill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	fill.BorderSizePixel = 0
	fill.Parent = hpTrack
	Theme.addCorner(fill, 8)
	hpFillGrad =
		Theme.addGradient(fill, Color3.fromRGB(112, 244, 134), Color3.fromRGB(46, 196, 82), 90)
	hpFillBar = fill

	local hpLbl = Theme.makeLabel(
		hpTrack,
		"HpText",
		"100 / 100 HP",
		UDim2.fromScale(1, 1),
		UDim2.fromOffset(0, 0),
		14,
		Theme.Colors.Text,
		true
	)
	hpLbl.TextXAlignment = Enum.TextXAlignment.Center
	hpLbl.ZIndex = 3
	local hpStroke = Instance.new("UIStroke")
	hpStroke.Color = Color3.fromRGB(12, 20, 14)
	hpStroke.Thickness = 1.6
	hpStroke.Transparency = 0.25
	hpStroke.Parent = hpLbl
	hpValueLabel = hpLbl

	-- Bottom Row: PWR / DMG / SPD pills
	local botRow = Instance.new("Frame")
	botRow.Name = "StatRow"
	botRow.BackgroundTransparency = 1
	botRow.Position = UDim2.new(0, 12, 1, -36)
	botRow.Size = UDim2.new(1, -24, 0, 28)
	botRow.Parent = dock

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Padding = UDim.new(0, 6)
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Parent = botRow

	local function makeStatPill(
		order: number,
		name: string,
		text: string,
		strokeCol: Color3,
		textCol: Color3
	): TextLabel
		local pill = Theme.makeFrame(
			botRow,
			name,
			UDim2.fromScale(0.32, 1),
			UDim2.fromOffset(0, 0),
			Theme.Colors.Card,
			8
		)
		pill.LayoutOrder = order
		Theme.addStroke(pill, strokeCol, 1.4, 0.15)
		local flex = Instance.new("UIFlexItem")
		flex.FlexMode = Enum.UIFlexMode.Fill
		flex.Parent = pill

		local lbl = Theme.makeLabel(
			pill,
			"Value",
			text,
			UDim2.new(1, -8, 1, 0),
			UDim2.fromOffset(4, 0),
			13,
			textCol,
			true
		)
		lbl.TextXAlignment = Enum.TextXAlignment.Center
		lbl.TextScaled = true
		local tc = Instance.new("UITextSizeConstraint")
		tc.MaxTextSize = 14
		tc.MinTextSize = 9
		tc.Parent = lbl
		return lbl
	end

	pwrLabel =
		makeStatPill(1, "PwrPill", "⚡ PWR: 10", Color3.fromRGB(58, 154, 192), Theme.Colors.Frost)
	dmgLabel =
		makeStatPill(2, "DmgPill", "⚔ DMG: 5", Color3.fromRGB(194, 108, 48), Theme.Colors.Molten)
	spdLabel = makeStatPill(
		3,
		"SpdPill",
		"» SPD: 1.00x",
		Color3.fromRGB(112, 124, 146),
		Theme.Colors.Text
	)
end

local function buildCombatButtons(gui: ScreenGui)
	local holder = Instance.new("Frame")
	holder.Name = "ActionButtons"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(1, 1)
	holder.Position = UDim2.new(1, -14, 1, -14)
	holder.Size = UDim2.fromOffset(308, 176)
	holder.Parent = gui
	actionHolder = holder

	-- AUTO AIM toggle pill (left of DASH)
	local aimBtn = Instance.new("TextButton")
	aimBtn.Name = "AutoAimBtn"
	aimBtn.AnchorPoint = Vector2.new(1, 1)
	aimBtn.Position = UDim2.new(1, -174, 1, -10)
	aimBtn.Size = UDim2.fromOffset(118, 48)
	aimBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	aimBtn.BackgroundTransparency = 0.05
	aimBtn.Text = ""
	aimBtn.BorderSizePixel = 0
	aimBtn.AutoButtonColor = true
	aimBtn.Parent = holder
	Theme.addCorner(aimBtn, 12)
	Theme.addGradient(aimBtn, Theme.Colors.PanelTop, Theme.Colors.PanelBottom, 90)
	Theme.addStroke(aimBtn, Theme.Colors.Stroke, 1.5, 0.1)

	local reticle = HudIcons.createReticleIcon(aimBtn, 26, Theme.Colors.Danger)
	reticle.AnchorPoint = Vector2.new(0, 0.5)
	reticle.Position = UDim2.new(0, 9, 0.5, 0)
	autoAimReticle = reticle

	local aimTitle = Theme.makeLabel(
		aimBtn,
		"AimTitle",
		"AUTO AIM",
		UDim2.new(1, -42, 0, 18),
		UDim2.fromOffset(40, 6),
		11,
		Theme.Colors.Text,
		true
	)
	aimTitle.TextXAlignment = Enum.TextXAlignment.Center
	local aimState = Theme.makeLabel(
		aimBtn,
		"AimState",
		"OFF",
		UDim2.new(1, -42, 0, 18),
		UDim2.fromOffset(40, 23),
		12,
		Theme.Colors.Danger,
		true
	)
	aimState.TextXAlignment = Enum.TextXAlignment.Center
	autoAimStateLbl = aimState
	autoAimBtn = aimBtn

	aimBtn.Activated:Connect(function()
		if toggleAutoAimCallback then
			toggleAutoAimCallback()
		end
	end)

	-- DASH circle (sky-blue glossy; child TextLabel avoids UIGradient tinting white text)
	local dBtn = Instance.new("TextButton")
	dBtn.Name = "DashBtn"
	dBtn.AnchorPoint = Vector2.new(1, 1)
	dBtn.Position = UDim2.new(1, -94, 1, -4)
	dBtn.Size = UDim2.fromOffset(70, 70)
	dBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	dBtn.Text = ""
	dBtn.BorderSizePixel = 0
	dBtn.AutoButtonColor = true
	dBtn.AutoLocalize = false
	dBtn.Parent = holder
	Theme.addCorner(dBtn, 999)
	Theme.addGradient(dBtn, Color3.fromRGB(122, 206, 255), Color3.fromRGB(58, 146, 228), 90)
	Theme.addStroke(dBtn, Color3.fromRGB(196, 238, 255), 2.2, 0.1)

	local dLbl = Theme.makeLabel(
		dBtn,
		"DashText",
		"DASH",
		UDim2.fromScale(1, 1),
		UDim2.fromOffset(0, -2),
		17,
		Theme.Colors.Text,
		true
	)
	dLbl.TextXAlignment = Enum.TextXAlignment.Center
	local dStroke = Instance.new("UIStroke")
	dStroke.Color = Color3.fromRGB(18, 56, 98)
	dStroke.Thickness = 1.6
	dStroke.Transparency = 0.25
	dStroke.Parent = dLbl
	dashTextLbl = dLbl

	local qHint = Theme.makeLabel(
		dBtn,
		"KeyHint",
		"[Q]",
		UDim2.new(1, 0, 0, 14),
		UDim2.new(0, 0, 1, -15),
		10,
		Color3.fromRGB(232, 248, 255),
		true
	)
	qHint.TextXAlignment = Enum.TextXAlignment.Center
	dashSubLbl = qHint
	dashBtn = dBtn

	dBtn.Activated:Connect(function()
		if dashCallback then
			dashCallback()
		end
	end)

	-- THROW hero circle (largest fiery-orange button; child TextLabel keeps pure white text)
	local tBtn = Instance.new("TextButton")
	tBtn.Name = "ThrowBtn"
	tBtn.AnchorPoint = Vector2.new(1, 1)
	tBtn.Position = UDim2.fromScale(1, 1)
	tBtn.Size = UDim2.fromOffset(86, 86)
	tBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	tBtn.Text = ""
	tBtn.BorderSizePixel = 0
	tBtn.AutoButtonColor = true
	tBtn.AutoLocalize = false
	tBtn.Parent = holder
	Theme.addCorner(tBtn, 999)
	Theme.addGradient(tBtn, Color3.fromRGB(248, 138, 48), Color3.fromRGB(206, 82, 18), 90)
	Theme.addStroke(tBtn, Color3.fromRGB(255, 204, 134), 2.5, 0.08)

	local tLbl = Theme.makeLabel(
		tBtn,
		"ThrowText",
		"THROW",
		UDim2.fromScale(1, 1),
		UDim2.fromOffset(0, 0),
		19,
		Theme.Colors.Text,
		true
	)
	tLbl.TextXAlignment = Enum.TextXAlignment.Center
	local tStroke = Instance.new("UIStroke")
	tStroke.Color = Color3.fromRGB(112, 38, 8)
	tStroke.Thickness = 1.8
	tStroke.Transparency = 0.22
	tStroke.Parent = tLbl
	throwTextLbl = tLbl
	throwBtn = tBtn

	tBtn.Activated:Connect(function()
		if throwCallback then
			throwCallback()
		end
	end)
	tBtn.InputBegan:Connect(function(inp: InputObject)
		if
			inp.UserInputType == Enum.UserInputType.Touch
			or inp.UserInputType == Enum.UserInputType.MouseButton1
		then
			if throwHoldCallback then
				throwHoldCallback(true)
			end
		end
	end)
	tBtn.InputEnded:Connect(function(inp: InputObject)
		if
			inp.UserInputType == Enum.UserInputType.Touch
			or inp.UserInputType == Enum.UserInputType.MouseButton1
		then
			if throwHoldCallback then
				throwHoldCallback(false)
			end
		end
	end)

	-- Upper-right Jump circle directly above THROW
	local jBtn = Instance.new("TextButton")
	jBtn.Name = "JumpActionBtn"
	jBtn.AnchorPoint = Vector2.new(1, 1)
	jBtn.Position = UDim2.new(1, -11, 1, -96)
	jBtn.Size = UDim2.fromOffset(64, 64)
	jBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	jBtn.Text = ""
	jBtn.BorderSizePixel = 0
	jBtn.AutoButtonColor = true
	jBtn.Parent = holder
	Theme.addCorner(jBtn, 999)
	Theme.addGradient(jBtn, Color3.fromRGB(248, 138, 48), Color3.fromRGB(202, 78, 18), 90)
	Theme.addStroke(jBtn, Color3.fromRGB(255, 204, 134), 2.2, 0.1)

	local jIcon = HudIcons.createJumpIcon(jBtn, 36)
	jIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	jIcon.Position = UDim2.fromScale(0.5, 0.5)
	jumpActionBtn = jBtn

	local function triggerJumpNow()
		jumpPulseUntil = os.clock() + 0.16
		local char = localPlayer.Character
		local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
		if hum and hum.Health > 0 then
			hum.Jump = true
			local st = hum:GetState()
			if
				hum.FloorMaterial ~= Enum.Material.Air
				or st == Enum.HumanoidStateType.Running
				or st == Enum.HumanoidStateType.Landed
				or st == Enum.HumanoidStateType.Climbing
				or st == Enum.HumanoidStateType.Swimming
				or st == Enum.HumanoidStateType.Seated
			then
				hum:ChangeState(Enum.HumanoidStateType.Jumping)
			end
		end
	end

	jBtn.Activated:Connect(triggerJumpNow)
	jBtn.InputBegan:Connect(function(inp: InputObject)
		if
			inp.UserInputType == Enum.UserInputType.Touch
			or inp.UserInputType == Enum.UserInputType.MouseButton1
		then
			isJumpHeld = true
			triggerJumpNow()
		end
	end)
	jBtn.InputEnded:Connect(function(inp: InputObject)
		if
			inp.UserInputType == Enum.UserInputType.Touch
			or inp.UserInputType == Enum.UserInputType.MouseButton1
		then
			isJumpHeld = false
		end
	end)
end

local function syncNativeTouchJump()
	local pg = localPlayer:FindFirstChildOfClass("PlayerGui")
	local touchGui = if pg then pg:FindFirstChild("TouchGui") else nil
	local ctrlFrame = if touchGui then touchGui:FindFirstChild("TouchControlFrame") else nil
	local nativeJump = if ctrlFrame then ctrlFrame:FindFirstChild("JumpButton") else nil
	if nativeJump and nativeJump:IsA("ImageButton") then
		-- Hide duplicate default gray JumpButton while keeping TouchGui + DynamicThumbstick enabled
		nativeJump.Visible = false
	end
end

local function applyResponsiveLayout()
	local m = Theme.getLayoutMetrics()
	local compact = m.isCompact

	-- Currencies
	if currencyStack then
		currencyStack.Position =
			UDim2.fromOffset(if compact then 10 else 14, if compact then 6 else 8)
		local pillW = if compact then 104 else 132
		local pillH = if compact then 28 else 34
		for _, ch in ipairs(currencyStack:GetChildren()) do
			if ch:IsA("Frame") then
				ch.Size = UDim2.fromOffset(pillW, pillH)
			end
		end
	end
	if coinsValLabel then
		coinsValLabel.TextSize = if compact then 14 else 17
	end
	if gemsValLabel then
		gemsValLabel.TextSize = if compact then 14 else 17
	end

	-- Top-Right Audio
	if topRightStack then
		topRightStack.Position =
			UDim2.new(1, if compact then -10 else -14, 0, if compact then 6 else 8)
	end
	if audioBtn then
		audioBtn.Size = UDim2.fromOffset(if compact then 108 else 132, if compact then 28 else 34)
	end
	if audioLabel then
		audioLabel.TextSize = if compact then 10 else 12
	end
	if hubReturnBtn then
		hubReturnBtn.Size =
			UDim2.fromOffset(if compact then 102 else 124, if compact then 28 else 34)
	end

	-- Collapsible 2x2 Drawer
	if drawerWrap and drawerPanel and drawerGrid and drawerTabBtn then
		local tileS = if compact then 54 else 74
		local pad = if compact then 8 else 10
		local gap = if compact then 6 else 8
		local panelS = tileS * 2 + gap + pad * 2
		local tabW = if compact then 22 else 26
		local tabH = if compact then 42 else 52
		drawerGrid.CellSize = UDim2.fromOffset(tileS, tileS)
		drawerGrid.CellPadding = UDim2.fromOffset(gap, gap)
		drawerPanel.Size = UDim2.fromOffset(panelS, panelS)
		drawerTabBtn.Size = UDim2.fromOffset(tabW, tabH)
		drawerTabBtn.Position = UDim2.new(0, panelS - 2, 0.5, 0)
		drawerWrap.Size = UDim2.fromOffset(panelS + tabW, panelS)
		if compact then
			drawerWrap.AnchorPoint = Vector2.new(0, 0)
			drawerWrap.Position = UDim2.fromOffset(if drawerOpen then 0 else -panelS, 72)
		else
			drawerWrap.AnchorPoint = Vector2.new(0, 0.5)
			drawerWrap.Position = UDim2.new(0, if drawerOpen then 0 else -panelS, 0.44, 0)
		end
		for _, tile in ipairs(drawerTileButtons) do
			local ic = tile:FindFirstChild("TileIcon")
			if ic and ic:IsA("Frame") then
				local icS = if compact then 26 else 36
				ic.Size = UDim2.fromOffset(icS, icS)
				ic.Position = UDim2.new(0.5, 0, 0, if compact then 5 else 8)
			end
		end
	end

	-- Bottom-Center Hero Status Dock
	if statusDock and levelLabel then
		if m.isPortrait then
			local dockW = math.clamp(math.floor(m.viewport.X - 24), 256, 360)
			statusDock.Size = UDim2.fromOffset(dockW, 70)
			statusDock.Position = UDim2.new(0.5, 0, 1, -138)
			levelLabel.TextSize = 16
		elseif compact then
			local dockW = math.clamp(math.floor(m.viewport.X * 0.41), 248, 300)
			statusDock.Size = UDim2.fromOffset(dockW, 68)
			statusDock.Position = UDim2.new(0.43, 0, 1, -8)
			levelLabel.TextSize = 16
		else
			statusDock.Size = UDim2.fromOffset(420, 84)
			statusDock.Position = UDim2.new(0.5, 0, 1, -14)
			levelLabel.TextSize = 21
		end
	end

	-- Guide & AFK banners right above Hero Status Dock
	local dockTopOffset = if m.isPortrait then -214 elseif compact then -82 else -106
	if guideFrame then
		local gw = if compact then math.min(340, m.viewport.X - 28) else 440
		guideFrame.Size = UDim2.fromOffset(gw, if compact then 28 else 32)
		guideFrame.Position = UDim2.new(0.5, 0, 1, dockTopOffset)
	end
	if afkBadgeFrame then
		local aw = if compact then 260 else 320
		afkBadgeFrame.Size = UDim2.fromOffset(aw, if compact then 28 else 32)
		afkBadgeFrame.Position = UDim2.new(0.5, 0, 1, dockTopOffset - 36)
	end

	-- Bottom-Right Combat Thumb-Arc
	if actionHolder and throwBtn and dashBtn and autoAimBtn and jumpActionBtn then
		actionHolder.Position =
			UDim2.new(1, if compact then -10 else -16, 1, if compact then -8 else -14)
		local tS = if compact then 66 else 86
		local dS = if compact then 54 else 70
		local jS = if compact then 50 else 64
		local aW = if compact then 92 else 118
		local aH = if compact then 42 else 48
		throwBtn.Size = UDim2.fromOffset(tS, tS)
		if throwTextLbl then
			throwTextLbl.TextSize = if compact then 15 else 19
		end
		dashBtn.Size = UDim2.fromOffset(dS, dS)
		dashBtn.Position = UDim2.new(1, -(tS + 8), 1, -4)
		if dashTextLbl then
			dashTextLbl.TextSize = if compact then 13 else 17
		end
		jumpActionBtn.Size = UDim2.fromOffset(jS, jS)
		jumpActionBtn.Position = UDim2.new(1, -math.floor((tS - jS) * 0.5), 1, -(tS + 10))
		autoAimBtn.Size = UDim2.fromOffset(aW, aH)
		autoAimBtn.Position = UDim2.new(1, -(tS + dS + 16), 1, -8)
		if dashSubLbl then
			dashSubLbl.Visible = not m.isTouch
		end
	end

	task.defer(syncNativeTouchJump)
end

function HudGui.mount(callbacks: {
	onThrow: () -> (),
	onThrowHold: ((boolean) -> ())?,
	onDash: () -> (),
	onToggleAutoAim: (() -> ())?,
	onOpenModal: (string) -> (),
})
	throwCallback = callbacks.onThrow
	throwHoldCallback = callbacks.onThrowHold
	dashCallback = callbacks.onDash
	toggleAutoAimCallback = callbacks.onToggleAutoAim
	openModalCallback = callbacks.onOpenModal

	local gui = Theme.createScreenGui("BallBrawl_HUD", 10)
	hudScreen = gui

	buildCurrencyStack(gui)
	buildTopRight(gui)
	buildMenuDrawer(gui)
	buildHeroStatusDock(gui)
	buildCombatButtons(gui)

	local bannerFrame = Theme.makeGlossyPanel(
		gui,
		"OnboardingGuide",
		UDim2.fromOffset(440, 32),
		UDim2.new(0.5, 0, 1, -106),
		10
	)
	bannerFrame.AnchorPoint = Vector2.new(0.5, 1)
	bannerFrame.Visible = false
	guideFrame = bannerFrame
	guideBanner = Theme.makeLabel(
		bannerFrame,
		"GuideText",
		"Step 1: Walk to Pedestal #1 & press Hatch for your FREE Starter Egg!",
		UDim2.new(1, -16, 1, 0),
		UDim2.fromOffset(8, 0),
		13,
		Theme.Colors.Coins,
		true
	)
	if guideBanner then
		guideBanner.TextXAlignment = Enum.TextXAlignment.Center
		guideBanner.TextScaled = true
		guideBanner.TextWrapped = true
		local tc = Instance.new("UITextSizeConstraint")
		tc.MaxTextSize = 13
		tc.MinTextSize = 9
		tc.Parent = guideBanner
	end

	local afkFrame = Theme.makeGlossyPanel(
		gui,
		"AfkTrainingBadge",
		UDim2.fromOffset(320, 32),
		UDim2.new(0.5, 0, 1, -142),
		10
	)
	afkFrame.AnchorPoint = Vector2.new(0.5, 1)
	Theme.addStroke(afkFrame, Theme.Colors.Emerald, 2)
	afkFrame.Visible = false
	afkBadgeFrame = afkFrame
	local afkLbl = Theme.makeLabel(
		afkFrame,
		"Label",
		"⚡ AFK AUTO-TRAINING ACTIVE • GRINDING DMG",
		UDim2.new(1, -14, 1, 0),
		UDim2.fromOffset(7, 0),
		12,
		Theme.Colors.Emerald,
		true
	)
	afkLbl.TextXAlignment = Enum.TextXAlignment.Center

	-- Live Humanoid HP binding across respawns
	task.spawn(bindCharacterHealth, localPlayer.Character)
	localPlayer.CharacterAdded:Connect(function(char: Model)
		task.spawn(bindCharacterHealth, char)
	end)

	-- Responsive viewport & PreferredInput updates
	local function hookCamera()
		local cam = workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(applyResponsiveLayout)
		end
	end
	hookCamera()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hookCamera)
	UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(applyResponsiveLayout)

	-- Harmonize native TouchGui JumpButton when it appears
	local pg = localPlayer:WaitForChild("PlayerGui")
	pg.DescendantAdded:Connect(function(inst: Instance)
		if inst.Name == "JumpButton" and inst:IsA("ImageButton") then
			task.defer(syncNativeTouchJump)
			inst:GetPropertyChangedSignal("Visible"):Connect(function()
				if inst.Visible then
					task.defer(syncNativeTouchJump)
				end
			end)
		end
	end)

	-- Apply held/pulsed jump AFTER PlayerModule ControlModule.OnRenderStepped, right before physics
	RunService.PreSimulation:Connect(function()
		if isJumpHeld or os.clock() < jumpPulseUntil then
			local char = localPlayer.Character
			local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
			if hum and hum.Health > 0 then
				hum.Jump = true
			end
		end
	end)

	applyResponsiveLayout()
end

function HudGui.updateProfile(profile: any, powerRating: number, maxHP: number)
	profileMaxHP = math.max(1, tonumber(maxHP) or 100)
	if coinsValLabel then
		coinsValLabel.Text = MathUtil.formatNumber(profile.coins or 0)
	end
	if gemsValLabel then
		gemsValLabel.Text = MathUtil.formatNumber(profile.bossGems or 0)
	end
	if levelLabel then
		levelLabel.Text = `LV {profile.level or 1}`
	end
	if pwrLabel then
		pwrLabel.Text = `⚡ PWR: {MathUtil.formatNumber(powerRating or 0)}`
	end
	if dmgLabel then
		dmgLabel.Text = `⚔ DMG: {MathUtil.formatNumber(profile.ballDamage or 5)}`
	end
	if spdLabel then
		spdLabel.Text = string.format("» SPD: %.2fx", profile.throwSpeed or 1.0)
	end
	updateHumanoidHpBar()

	if guideBanner and guideFrame then
		local step = OnboardingLogic.currentStep(profile)
		if step then
			guideFrame.Visible = true
			guideBanner.Text = step.text
		else
			guideFrame.Visible = false
		end
	end
end

function HudGui.updateZone(zone: string)
	if hubReturnBtn then
		hubReturnBtn.Visible = zone == "BiomePvE"
	end
end

function HudGui.setAfkTrainingActive(active: boolean)
	if afkBadgeFrame then
		afkBadgeFrame.Visible = active
	end
end

function HudGui.setAutoAimEnabled(enabled: boolean)
	isAutoAimOn = enabled
	if not autoAimBtn or not autoAimStateLbl then
		return
	end
	if enabled then
		autoAimStateLbl.Text = "ON"
		autoAimStateLbl.TextColor3 = Theme.Colors.Emerald
		HudIcons.setReticleColor(autoAimReticle, Theme.Colors.Emerald)
		Theme.addStroke(autoAimBtn, Theme.Colors.Emerald, 2.0, 0.05)
	else
		autoAimStateLbl.Text = "OFF"
		autoAimStateLbl.TextColor3 = Theme.Colors.Danger
		HudIcons.setReticleColor(autoAimReticle, Theme.Colors.Danger)
		Theme.addStroke(autoAimBtn, Theme.Colors.Stroke, 1.5, 0.1)
	end
end

function HudGui.setDashCooldown(remaining: number)
	if not dashBtn or not dashTextLbl then
		return
	end
	if remaining > 0.05 then
		dashTextLbl.Text = string.format("%.1fs", remaining)
		Theme.addGradient(dashBtn, Theme.Colors.CardAlt, Theme.Colors.PanelBottom, 90)
		Theme.addStroke(dashBtn, Theme.Colors.Stroke, 1.8, 0.2)
		if dashSubLbl then
			dashSubLbl.Visible = false
		end
	else
		dashTextLbl.Text = "DASH"
		Theme.addGradient(dashBtn, Color3.fromRGB(122, 206, 255), Color3.fromRGB(58, 146, 228), 90)
		Theme.addStroke(dashBtn, Color3.fromRGB(196, 238, 255), 2.2, 0.1)
		if dashSubLbl then
			dashSubLbl.Visible = UserInputService.PreferredInput ~= Enum.PreferredInput.Touch
		end
	end
end

Players.LocalPlayer:GetAttributeChangedSignal("Zone"):Connect(function()
	HudGui.updateZone(tostring(Players.LocalPlayer:GetAttribute("Zone") or "Hub"))
end)

-- Expose state read for tests/diagnostics without breaking API
function HudGui.isDrawerOpen(): boolean
	return drawerOpen
end

function HudGui.setDrawerOpen(open: boolean)
	drawerOpen = open
	updateDrawerSlide(false)
end

function HudGui.getScreenGui(): ScreenGui?
	return hudScreen
end

function HudGui.isAutoAimOn(): boolean
	return isAutoAimOn
end

return HudGui
