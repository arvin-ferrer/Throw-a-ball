--!strict
--[[
	HudGui.luau
	Responsive cartoon HUD:
	- Bottom-Center: Stacked Gems and Coins pills, HP, stats and level progress
	- Top-Right: Compact Audio pill + contextual Hub Plot return pill
	- Mid-Left: Collapsible 2x2 tile drawer (Shop, Pets, Upgrades, Codex) with < / > tab
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
local EconomyConfigs = require(Shared.Configs.EconomyConfigs)
local Remotes = require(Shared.Net.Remotes)

local Theme = require(script.Parent.Theme)
local HudIcons = require(script.Parent.HudIcons)

local HudGui = {}

local localPlayer = Players.LocalPlayer
local hudScreen: ScreenGui? = nil

-- Bottom-center currency labels
local currencyStack: Frame? = nil
local coinsValLabel: TextLabel? = nil
local gemsValLabel: TextLabel? = nil

-- Top-left unified social, ping & vault bar
local topLeftBar: Frame? = nil
local dailyQuickBtn: TextButton? = nil
local dailyAlertDot: Frame? = nil
local pingQuickBtn: TextButton? = nil
local vaultQuickBtn: TextButton? = nil
local orbsQuickBtn: TextButton? = nil
local streakPartyBadge: Frame? = nil
local streakPartyLabel: TextLabel? = nil
local cachedWinStreak = 0
local cachedCoOpPct = 0
local cachedPartyTag = "SOLO"
local cachedVaultActive = false
local cachedVaultStorm = false

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
local expFillBar: Frame? = nil
local expValueLabel: TextLabel? = nil
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
local autoAimTitleLbl: TextLabel? = nil
local autoAimStateLbl: TextLabel? = nil
local dashBtn: TextButton? = nil
local dashIconFrame: Frame? = nil
local dashTextLbl: TextLabel? = nil
local dashSubLbl: TextLabel? = nil
local throwBtn: TextButton? = nil
local shootIconFrame: Frame? = nil
local throwTextLbl: TextLabel? = nil
local throwHintLbl: TextLabel? = nil
local jumpActionBtn: TextButton? = nil
local jumpIconFrame: Frame? = nil
local jumpTextLbl: TextLabel? = nil
local isAutoAimOn = false
local isJumpHeld = false
local jumpPulseUntil = 0
local lastIsTouch = UserInputService.PreferredInput == Enum.PreferredInput.Touch
local lastIsCompact = false
local isDashOnCooldown = false

-- Callbacks
local throwCallback: (() -> ())? = nil
local throwHoldCallback: ((boolean) -> ())? = nil
local dashCallback: (() -> ())? = nil
local toggleAutoAimCallback: (() -> ())? = nil
local openModalCallback: ((string) -> ())? = nil
local openDailyCallback: (() -> ())? = nil
local togglePingCallback: (() -> ())? = nil
local vaultActionCallback: (() -> ())? = nil
local openOrbsCallback: (() -> ())? = nil

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

local function makeCurrencyPill(
	stack: Frame,
	name: string,
	order: number,
	size: Vector2,
	top: Color3,
	bottom: Color3,
	iconMaker: (Instance, number) -> Frame
): TextLabel
	local pill = Theme.makeFrame(
		stack,
		name,
		UDim2.fromOffset(size.X, size.Y),
		UDim2.fromOffset(0, 0),
		Color3.new(1, 1, 1),
		999
	)
	pill.LayoutOrder = order
	pill.BackgroundTransparency = 0
	Theme.addGradient(pill, top, bottom, 90)
	Theme.addStroke(pill, Theme.Colors.Ink, 3)
	local icon = iconMaker(pill, size.Y - 10)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 8, 0.5, 0)
	local val = Theme.makeLabel(
		pill,
		"Value",
		"0",
		UDim2.new(1, -54, 1, 0),
		UDim2.fromOffset(27, 0),
		if order == 1 then 14 else 19,
		Theme.Colors.Text,
		true
	)
	val.TextXAlignment = Enum.TextXAlignment.Center
	val.TextTruncate = Enum.TextTruncate.AtEnd
	Theme.addTextStroke(val, 2.2)
	return val
end

local function buildCurrencyStack(gui: ScreenGui)
	local stack = Instance.new("Frame")
	stack.Name = "CurrencyStack"
	stack.BackgroundTransparency = 1
	stack.AnchorPoint = Vector2.new(0.5, 1)
	stack.Position = UDim2.new(0.5, 0, 1, -100)
	stack.Size = UDim2.fromOffset(152, 60)
	stack.Parent = gui
	currencyStack = stack

	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 5)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = stack

	gemsValLabel = makeCurrencyPill(
		stack,
		"GemsPill",
		1,
		Vector2.new(112, 24),
		Color3.fromRGB(67, 48, 114),
		Color3.fromRGB(41, 30, 77),
		HudIcons.createGemIcon
	)
	coinsValLabel = makeCurrencyPill(
		stack,
		"CoinsPill",
		2,
		Vector2.new(152, 31),
		Theme.Colors.LimeTop,
		Theme.Colors.LimeBot,
		HudIcons.createCoinIcon
	)
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

local function skinCartoonButton(btn: TextButton, top: Color3, bottom: Color3, corner: number)
	btn.BackgroundColor3 = Color3.new(1, 1, 1)
	btn.BackgroundTransparency = 0
	btn.AutoButtonColor = false
	Theme.addCorner(btn, corner)
	Theme.addGradient(btn, top, bottom, 90)
	Theme.addStroke(btn, Theme.Colors.Ink, 3)
	Theme.attachBounce(btn)
end

local function makeTopLeftButton(
	parent: Frame,
	name: string,
	text: string,
	top: Color3,
	bottom: Color3,
	onClick: () -> ()
): TextButton
	local btn = Theme.makeButton(
		parent,
		name,
		"",
		UDim2.fromOffset(74, 44),
		UDim2.fromOffset(0, 0),
		Color3.new(1, 1, 1),
		onClick
	)
	skinCartoonButton(btn, top, bottom, 12)
	local lbl = Theme.makeLabel(
		btn,
		"Text",
		text,
		UDim2.new(1, -8, 1, 0),
		UDim2.fromOffset(4, 0),
		12,
		Theme.Colors.Text,
		true
	)
	lbl.TextXAlignment = Enum.TextXAlignment.Center
	lbl.TextScaled = true
	Theme.addTextStroke(lbl, 1.6)
	local tc = Instance.new("UITextSizeConstraint")
	tc.MinTextSize = 9
	tc.MaxTextSize = 13
	tc.Parent = lbl
	return btn
end

local function refreshStreakPartyBadge()
	if not streakPartyBadge or not streakPartyLabel then
		return
	end
	local coOpText = if cachedCoOpPct > 0 then `+{cachedCoOpPct}% {cachedPartyTag}` else "SOLO"
	streakPartyLabel.Text = `🔥 {cachedWinStreak} • 👥 {coOpText}`
	if cachedCoOpPct > 0 then
		Theme.addGradient(streakPartyBadge, Theme.Colors.LimeTop, Theme.Colors.LimeBot, 90)
	elseif cachedWinStreak >= 2 then
		Theme.addGradient(streakPartyBadge, Theme.Colors.GoldTop, Theme.Colors.GoldBot, 90)
	else
		Theme.addGradient(streakPartyBadge, Theme.Colors.PanelTop, Theme.Colors.PanelBottom, 90)
	end
end

local function buildStreakPartyBadge(bar: Frame)
	local badge = Theme.makeFrame(
		bar,
		"StreakPartyBadge",
		UDim2.fromOffset(220, 24),
		UDim2.fromOffset(0, 48),
		Color3.new(1, 1, 1),
		999
	)
	badge.BackgroundTransparency = 0
	Theme.addGradient(badge, Theme.Colors.PanelTop, Theme.Colors.PanelBottom, 90)
	Theme.addStroke(badge, Theme.Colors.Ink, 2.2)
	streakPartyBadge = badge

	local lbl = Theme.makeLabel(
		badge,
		"Label",
		"🔥 0 • 👥 SOLO",
		UDim2.new(1, -12, 1, 0),
		UDim2.fromOffset(6, 0),
		11,
		Theme.Colors.Text,
		true
	)
	lbl.TextXAlignment = Enum.TextXAlignment.Center
	lbl.TextScaled = true
	Theme.addTextStroke(lbl, 1.4)
	local tc = Instance.new("UITextSizeConstraint")
	tc.MinTextSize = 8
	tc.MaxTextSize = 12
	tc.Parent = lbl
	streakPartyLabel = lbl
end

local function attachDailyAlertDot(btn: TextButton): Frame
	local dot = Theme.makeFrame(
		btn,
		"AlertDot",
		UDim2.fromOffset(12, 12),
		UDim2.new(1, -10, 0, -2),
		Theme.Colors.Danger,
		999
	)
	dot.BackgroundTransparency = 0
	dot.Visible = false
	dot.ZIndex = 4
	Theme.addStroke(dot, Theme.Colors.Ink, 2)
	return dot
end

local function invokeOptional(cb: (() -> ())?)
	if cb then
		cb()
	end
end

local function buildQuickButtons(bar: Frame)
	local dBtn = makeTopLeftButton(
		bar,
		"DailyQuickBtn",
		"DAILY",
		Theme.Colors.GoldTop,
		Theme.Colors.GoldBot,
		function()
			invokeOptional(openDailyCallback)
		end
	)
	dailyQuickBtn = dBtn
	dailyAlertDot = attachDailyAlertDot(dBtn)
	pingQuickBtn = makeTopLeftButton(
		bar,
		"PingQuickBtn",
		"PING [G]",
		Theme.Colors.TileSkyTop,
		Theme.Colors.TileSkyBot,
		function()
			invokeOptional(togglePingCallback)
		end
	)
	vaultQuickBtn = makeTopLeftButton(
		bar,
		"VaultQuickBtn",
		"VAULT",
		Theme.Colors.LimeTop,
		Theme.Colors.LimeBot,
		function()
			invokeOptional(vaultActionCallback)
		end
	)
	orbsQuickBtn = makeTopLeftButton(
		bar,
		"OrbsQuickBtn",
		"ORBS",
		Theme.Colors.HubBlueTop,
		Theme.Colors.HubBlueBot,
		function()
			invokeOptional(openOrbsCallback)
		end
	)
end

local function buildTopLeftActionBar(gui: ScreenGui)
	local bar = Instance.new("Frame")
	bar.Name = "TopLeftSocialBar"
	bar.BackgroundTransparency = 1
	bar.Position = UDim2.fromOffset(12, 8)
	bar.Size = UDim2.fromOffset(390, 76)
	bar.Parent = gui
	topLeftBar = bar
	buildQuickButtons(bar)
	buildStreakPartyBadge(bar)
end

type DrawerTile = {
	id: string,
	label: string,
	top: Color3,
	bottom: Color3,
	icon: (Instance, number) -> Frame,
}

local DRAWER_TILES: { DrawerTile } = {
	{
		id = "Shop",
		label = "SHOP",
		top = Theme.Colors.ShopRedTop,
		bottom = Theme.Colors.ShopRedBot,
		icon = HudIcons.createShopIcon,
	},
	{
		id = "Pets",
		label = "PETS",
		top = Color3.fromRGB(255, 163, 54),
		bottom = Color3.fromRGB(238, 91, 19),
		icon = HudIcons.createPetsIcon,
	},
	{
		id = "Upgrades",
		label = "UPGRADES",
		top = Theme.Colors.LimeTop,
		bottom = Theme.Colors.LimeBot,
		icon = HudIcons.createUpgradesIcon,
	},
	{
		id = "Codex",
		label = "CODEX",
		top = Theme.Colors.TilePurpleTop,
		bottom = Theme.Colors.HubBlueBot,
		icon = HudIcons.createCodexIcon,
	},
}

local function buildDrawerTile(panel: Frame, order: number, tileSpec: DrawerTile)
	local tile = Theme.makeButton(
		panel,
		tileSpec.id .. "Btn",
		"",
		UDim2.fromOffset(74, 74),
		UDim2.fromOffset(0, 0),
		Color3.new(1, 1, 1),
		function()
			if openModalCallback then
				openModalCallback(tileSpec.id)
			end
		end
	)
	tile.LayoutOrder = order
	skinCartoonButton(tile, tileSpec.top, tileSpec.bottom, 12)
	local icon = tileSpec.icon(tile, 36)
	icon.Name = "TileIcon"
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 8)

	local lbl = Theme.makeLabel(
		tile,
		"TileText",
		tileSpec.label,
		UDim2.new(1, -6, 0, 18),
		UDim2.new(0, 3, 1, -21),
		11,
		Theme.Colors.Text,
		true
	)
	lbl.TextXAlignment = Enum.TextXAlignment.Center
	lbl.TextScaled = true
	Theme.addTextStroke(lbl, 1.5)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 12
	constraint.MinTextSize = 9
	constraint.Parent = lbl
	table.insert(drawerTileButtons, tile)
end

local function buildDrawerTab(wrap: Frame)
	local tab = Theme.makeButton(
		wrap,
		"CollapseTab",
		"",
		UDim2.fromOffset(48, 52),
		UDim2.new(0, 174, 0.5, 0),
		Color3.new(1, 1, 1),
		function()
			drawerOpen = not drawerOpen
			updateDrawerSlide(false)
		end
	)
	tab.AnchorPoint = Vector2.new(0, 0.5)
	skinCartoonButton(tab, Theme.Colors.HubBlueTop, Theme.Colors.CodexPurpleBot, 12)
	local label = Theme.makeLabel(
		tab,
		"Arrow",
		"<",
		UDim2.fromScale(1, 1),
		UDim2.fromOffset(0, 0),
		24,
		Theme.Colors.Text,
		true
	)
	label.TextXAlignment = Enum.TextXAlignment.Center
	Theme.addTextStroke(label, 2.1)
	drawerTabLbl = label
	drawerTabBtn = tab
end

local function buildMenuDrawer(gui: ScreenGui)
	local wrap = Instance.new("Frame")
	wrap.Name = "MenuDrawerWrap"
	wrap.BackgroundTransparency = 1
	wrap.AnchorPoint = Vector2.new(0, 0.5)
	wrap.Position = UDim2.fromScale(0, 0.44)
	wrap.Size = UDim2.fromOffset(224, 178)
	wrap.Parent = gui
	drawerWrap = wrap

	local panel = Theme.makeCartoonWindow(
		wrap,
		"MenuPanel",
		UDim2.fromOffset(176, 178),
		UDim2.fromOffset(0, 0),
		16
	)
	-- Keep the tile outlines visible through hover bounce.
	panel.ClipsDescendants = false
	drawerPanel = panel
	Theme.addPadding(panel, 10)

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(74, 74)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.FillDirectionMaxCells = 2
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = panel
	drawerGrid = grid

	table.clear(drawerTileButtons)
	for order, tileSpec in ipairs(DRAWER_TILES) do
		buildDrawerTile(panel, order, tileSpec)
	end
	buildDrawerTab(wrap)
end

local function buildHeroHpTrack(dock: Frame)
	local track = Theme.makeFrame(
		dock,
		"HpTrack",
		UDim2.new(1, -16, 0, 18),
		UDim2.fromOffset(8, 6),
		Theme.Colors.Ink,
		7
	)
	track.ClipsDescendants = true
	Theme.addStroke(track, Theme.Colors.Ink, 2)
	local fill = Theme.makeFrame(
		track,
		"HpFill",
		UDim2.fromScale(1, 1),
		UDim2.fromOffset(0, 0),
		Color3.new(1, 1, 1),
		6
	)
	fill.BackgroundTransparency = 0
	Theme.addStroke(fill, Theme.Colors.Ink, 0)
	hpFillGrad = Theme.addGradient(fill, Color3.fromRGB(112, 244, 134), Color3.fromRGB(46, 196, 82))
	hpFillBar = fill
	local label = Theme.makeLabel(
		track,
		"HpText",
		"100 / 100 HP",
		UDim2.fromScale(1, 1),
		UDim2.fromOffset(0, 0),
		13,
		Theme.Colors.Text,
		true
	)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.ZIndex = 3
	Theme.addTextStroke(label, 1.7)
	hpValueLabel = label
end

local function buildHeroExpTrack(dock: Frame)
	local level = Theme.makeLabel(
		dock,
		"LevelLabel",
		"Lvl 1",
		UDim2.new(0.48, -8, 0, 15),
		UDim2.new(0, 8, 1, -25),
		12,
		Theme.Colors.Text,
		true
	)
	levelLabel = level
	Theme.addTextStroke(level, 1.5)
	local xp = Theme.makeLabel(
		dock,
		"ExpText",
		"0 / 60 EXP",
		UDim2.new(0.52, -8, 0, 15),
		UDim2.new(0.48, 0, 1, -25),
		11,
		Theme.Colors.Text,
		true
	)
	expValueLabel = xp
	xp.TextXAlignment = Enum.TextXAlignment.Right
	Theme.addTextStroke(xp, 1.5)
	local track = Theme.makeFrame(
		dock,
		"ExpTrack",
		UDim2.new(1, -16, 0, 6),
		UDim2.new(0, 8, 1, -8),
		Theme.Colors.Ink,
		4
	)
	track.ClipsDescendants = true
	Theme.addStroke(track, Theme.Colors.Ink, 2)
	local fill = Theme.makeFrame(
		track,
		"ExpFill",
		UDim2.fromScale(0, 1),
		UDim2.fromOffset(0, 0),
		Color3.new(1, 1, 1),
		4
	)
	fill.BackgroundTransparency = 0
	Theme.addStroke(fill, Theme.Colors.Ink, 0)
	Theme.addGradient(fill, Theme.Colors.MintTop, Theme.Colors.MintBot)
	expFillBar = fill
end

local function makeStatPill(
	row: Frame,
	order: number,
	name: string,
	text: string,
	tint: Color3
): TextLabel
	local pill =
		Theme.makeFrame(row, name, UDim2.fromScale(0.30, 1), UDim2.fromOffset(0, 0), tint, 7)
	pill.LayoutOrder = order
	Theme.addStroke(pill, Theme.Colors.Ink, 1.7)
	local flex = Instance.new("UIFlexItem")
	flex.FlexMode = Enum.UIFlexMode.Fill
	flex.Parent = pill

	local label = Theme.makeLabel(
		pill,
		"Value",
		text,
		UDim2.new(1, -6, 1, 0),
		UDim2.fromOffset(3, 0),
		12,
		Theme.Colors.Text,
		true
	)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextScaled = true
	Theme.addTextStroke(label, 1.4)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 12
	constraint.MinTextSize = 8
	constraint.Parent = label
	return label
end

local function buildHeroStats(dock: Frame)
	local row = Instance.new("Frame")
	row.Name = "StatRow"
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(8, 29)
	row.Size = UDim2.new(1, -16, 0, 18)
	row.Parent = dock

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 5)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = row

	pwrLabel = makeStatPill(row, 1, "PwrPill", "⚡ PWR: 10", Color3.fromRGB(46, 123, 194))
	dmgLabel = makeStatPill(row, 2, "DmgPill", "⚔ DMG: 5", Color3.fromRGB(211, 89, 34))
	spdLabel = makeStatPill(row, 3, "SpdPill", "» SPD: 1.00x", Color3.fromRGB(120, 77, 180))
end

local function buildHeroStatusDock(gui: ScreenGui)
	local dock = Theme.makeFrame(
		gui,
		"HeroStatusDock",
		UDim2.fromOffset(360, 76),
		UDim2.new(0.5, 0, 1, -14),
		Color3.fromRGB(38, 33, 64),
		11
	)
	dock.BackgroundTransparency = 0
	dock.AnchorPoint = Vector2.new(0.5, 1)
	Theme.addStroke(dock, Theme.Colors.Ink, 3)
	statusDock = dock
	buildHeroHpTrack(dock)
	buildHeroStats(dock)
	buildHeroExpTrack(dock)
end

local function makeCombatButton(holder: Frame, name: string, size: UDim2, pos: UDim2): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.AnchorPoint = Vector2.new(1, 1)
	btn.Position = pos
	btn.Size = size
	btn.Text = ""
	btn.BorderSizePixel = 0
	btn.AutoLocalize = false
	btn.Parent = holder
	return btn
end

local function makeControlCaption(
	btn: TextButton,
	name: string,
	text: string,
	size: UDim2,
	pos: UDim2,
	textSize: number,
	color: Color3?
): TextLabel
	local caption =
		Theme.makeLabel(btn, name, text, size, pos, textSize, color or Theme.Colors.Text, true)
	caption.TextXAlignment = Enum.TextXAlignment.Center
	Theme.addTextStroke(caption, 1.6)
	return caption
end

local function setAimButtonPalette(btn: TextButton, enabled: boolean)
	local top = if enabled then Color3.fromRGB(57, 146, 142) else Theme.Colors.CodexPurpleTop
	local bottom = if enabled then Color3.fromRGB(34, 90, 108) else Theme.Colors.CodexPurpleBot
	Theme.addGradient(btn, top, bottom, 90)
end

local function buildAutoAimButton(holder: Frame)
	local btn =
		makeCombatButton(holder, "AutoAimBtn", UDim2.fromOffset(88, 48), UDim2.new(1, -66, 1, -12))
	skinCartoonButton(btn, Theme.Colors.CodexPurpleTop, Theme.Colors.CodexPurpleBot, 12)
	local reticle = HudIcons.createReticleIcon(btn, 24, Theme.Colors.Danger)
	reticle.AnchorPoint = Vector2.new(0, 0.5)
	reticle.Position = UDim2.new(0, 8, 0.5, 0)
	autoAimReticle = reticle

	autoAimTitleLbl = makeControlCaption(
		btn,
		"AimTitle",
		"AUTO AIM",
		UDim2.new(1, -38, 0, 17),
		UDim2.fromOffset(36, 6),
		10
	)
	autoAimStateLbl = makeControlCaption(
		btn,
		"AimState",
		"OFF",
		UDim2.new(1, -38, 0, 17),
		UDim2.fromOffset(36, 23),
		12,
		Theme.Colors.Danger
	)
	autoAimBtn = btn
	btn.Activated:Connect(function()
		if toggleAutoAimCallback then
			toggleAutoAimCallback()
		end
	end)
end

local function buildDashButton(holder: Frame)
	local btn =
		makeCombatButton(holder, "DashBtn", UDim2.fromOffset(66, 66), UDim2.new(1, 0, 1, -8))
	skinCartoonButton(btn, Theme.Colors.TileSkyTop, Theme.Colors.TileSkyBot, 999)
	local icon = HudIcons.createDashIcon(btn, 22)
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 6)
	dashIconFrame = icon

	dashTextLbl = makeControlCaption(
		btn,
		"DashText",
		"DASH",
		UDim2.new(1, -6, 0, 15),
		UDim2.new(0, 3, 1, -21),
		11
	)
	dashSubLbl = makeControlCaption(
		btn,
		"KeyHint",
		"[Q]",
		UDim2.new(1, 0, 0, 13),
		UDim2.new(0, 0, 1, -15),
		10
	)
	dashBtn = btn
	btn.Activated:Connect(function()
		if dashCallback then
			dashCallback()
		end
	end)
end

local function bindShootButton(btn: TextButton)
	local activeInput: InputObject? = nil
	btn.Activated:Connect(function()
		if throwCallback then
			throwCallback()
		end
	end)
	btn.InputBegan:Connect(function(inp: InputObject)
		if
			inp.UserInputType == Enum.UserInputType.Touch
			or inp.UserInputType == Enum.UserInputType.MouseButton1
		then
			activeInput = inp
			if throwHoldCallback then
				throwHoldCallback(true)
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(inp: InputObject)
		if activeInput ~= nil and inp == activeInput then
			activeInput = nil
			if throwHoldCallback then
				throwHoldCallback(false)
			end
		end
	end)
end

local function buildShootButton(holder: Frame)
	local btn =
		makeCombatButton(holder, "ThrowBtn", UDim2.fromOffset(78, 78), UDim2.new(1, -68, 1, -68))
	skinCartoonButton(btn, Color3.fromRGB(255, 183, 60), Color3.fromRGB(236, 89, 19), 999)
	local icon = HudIcons.createShootIcon(btn, 28)
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 9)
	shootIconFrame = icon

	throwTextLbl = makeControlCaption(
		btn,
		"ThrowText",
		"SHOOT",
		UDim2.new(1, -8, 0, 18),
		UDim2.new(0, 4, 1, -26),
		13
	)
	throwHintLbl = makeControlCaption(
		btn,
		"KeyHint",
		"[LMB]",
		UDim2.new(1, 0, 0, 13),
		UDim2.new(0, 0, 1, -15),
		10
	)
	throwBtn = btn
	bindShootButton(btn)
end

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

local function bindJumpButton(btn: TextButton)
	local activeJumpInput: InputObject? = nil
	btn.Activated:Connect(triggerJumpNow)
	btn.InputBegan:Connect(function(inp: InputObject)
		if
			inp.UserInputType == Enum.UserInputType.Touch
			or inp.UserInputType == Enum.UserInputType.MouseButton1
		then
			activeJumpInput = inp
			isJumpHeld = true
			triggerJumpNow()
		end
	end)
	UserInputService.InputEnded:Connect(function(inp: InputObject)
		if activeJumpInput ~= nil and inp == activeJumpInput then
			activeJumpInput = nil
			isJumpHeld = false
		end
	end)
end

local function buildJumpButton(holder: Frame)
	local btn =
		makeCombatButton(holder, "JumpActionBtn", UDim2.fromOffset(54, 54), UDim2.new(1, 0, 1, -76))
	skinCartoonButton(btn, Theme.Colors.GoldTop, Theme.Colors.GoldBot, 999)
	local icon = HudIcons.createJumpIcon(btn, 24)
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 6)
	jumpIconFrame = icon
	jumpTextLbl = makeControlCaption(
		btn,
		"JumpText",
		"JUMP",
		UDim2.new(1, -6, 0, 13),
		UDim2.new(0, 3, 1, -17),
		10
	)
	jumpActionBtn = btn
	bindJumpButton(btn)
end

local function buildCombatButtons(gui: ScreenGui)
	local holder = Instance.new("Frame")
	holder.Name = "ActionButtons"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(1, 1)
	holder.Position = UDim2.new(1, -16, 1, -14)
	holder.Size = UDim2.fromOffset(260, 210)
	holder.Parent = gui
	actionHolder = holder

	buildAutoAimButton(holder)
	buildDashButton(holder)
	buildShootButton(holder)
	buildJumpButton(holder)
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

local function applyDrawerResponsive(compact: boolean, isPortrait: boolean)
	if not (drawerWrap and drawerPanel and drawerGrid and drawerTabBtn) then
		return
	end
	local tileS = if compact then 54 else 74
	local pad = if compact then 8 else 10
	local gap = if compact then 6 else 8
	local panelS = tileS * 2 + gap + pad * 2 + 2
	local tabW = 48
	local tabH = if compact then 48 else 52
	local padding = drawerPanel:FindFirstChildOfClass("UIPadding")
	if padding then
		padding.PaddingTop = UDim.new(0, pad)
		padding.PaddingBottom = UDim.new(0, pad)
		padding.PaddingLeft = UDim.new(0, pad)
		padding.PaddingRight = UDim.new(0, pad)
	end
	drawerGrid.CellSize = UDim2.fromOffset(tileS, tileS)
	drawerGrid.CellPadding = UDim2.fromOffset(gap, gap)
	drawerPanel.Size = UDim2.fromOffset(panelS, panelS)
	drawerTabBtn.Size = UDim2.fromOffset(tabW, tabH)
	drawerTabBtn.Position = UDim2.new(0, panelS - 1, 0.5, 0)
	drawerWrap.Size = UDim2.fromOffset(panelS + tabW, panelS)
	if compact then
		drawerWrap.AnchorPoint = Vector2.new(0, 0)
		local height = if hudScreen then hudScreen.AbsoluteSize.Y else 0
		local minY = if isPortrait then 128 else 76
		local maxY = if isPortrait then 148 else 108
		local y = if height > 0 then math.clamp(height - panelS - 158, minY, maxY) else minY
		drawerWrap.Position = UDim2.fromOffset(if drawerOpen then 0 else -panelS, y)
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

local function setQuickButtonBox(btn: TextButton?, w: number, h: number, x: number, y: number)
	if btn then
		btn.Size = UDim2.fromOffset(w, h)
		btn.Position = UDim2.fromOffset(x, y)
	end
end

local TOP_LEFT_LAYOUTS = {
	portrait = {
		pos = { 6, 6 },
		bar = { 170, 120 },
		daily = { 82, 44, 0, 0 },
		ping = { 82, 44, 88, 0 },
		vault = { 82, 44, 0, 48 },
		orbs = { 82, 44, 88, 48 },
		badge = { 170, 22, 0, 96 },
	},
	compact = {
		pos = { 6, 6 },
		bar = { 286, 68 },
		daily = { 72, 44, 0, 0 },
		ping = { 62, 44, 76, 0 },
		vault = { 76, 44, 142, 0 },
		orbs = { 58, 44, 222, 0 },
		badge = { 172, 20, 0, 46 },
	},
	desktop = {
		pos = { 12, 8 },
		bar = { 390, 76 },
		daily = { 94, 44, 0, 0 },
		ping = { 88, 44, 100, 0 },
		vault = { 114, 44, 194, 0 },
		orbs = { 72, 44, 314, 0 },
		badge = { 220, 24, 0, 48 },
	},
}

local function applyTopLeftResponsive(m: Theme.LayoutMetrics)
	if not topLeftBar then
		return
	end
	if pingQuickBtn then
		local lbl = pingQuickBtn:FindFirstChild("Text")
		if lbl and lbl:IsA("TextLabel") then
			lbl.Text = if m.isTouch then "PING" else "PING [G]"
		end
	end
	local mode = if m.isPortrait then "portrait" elseif m.isCompact then "compact" else "desktop"
	local spec = TOP_LEFT_LAYOUTS[mode]
	topLeftBar.Position = UDim2.fromOffset(spec.pos[1], spec.pos[2])
	topLeftBar.Size = UDim2.fromOffset(spec.bar[1], spec.bar[2])
	setQuickButtonBox(dailyQuickBtn, spec.daily[1], spec.daily[2], spec.daily[3], spec.daily[4])
	setQuickButtonBox(pingQuickBtn, spec.ping[1], spec.ping[2], spec.ping[3], spec.ping[4])
	setQuickButtonBox(vaultQuickBtn, spec.vault[1], spec.vault[2], spec.vault[3], spec.vault[4])
	setQuickButtonBox(orbsQuickBtn, spec.orbs[1], spec.orbs[2], spec.orbs[3], spec.orbs[4])
	if streakPartyBadge then
		streakPartyBadge.Size = UDim2.fromOffset(spec.badge[1], spec.badge[2])
		streakPartyBadge.Position = UDim2.fromOffset(spec.badge[3], spec.badge[4])
	end
end

local function applyDashReadyLayout()
	if dashIconFrame then
		local icS = if lastIsTouch
			then (if lastIsCompact then 20 else 24)
			else (if lastIsCompact then 18 else 22)
		dashIconFrame.Size = UDim2.fromOffset(icS, icS)
		dashIconFrame.Position = UDim2.new(0.5, 0, 0, if lastIsCompact then 5 else 6)
		dashIconFrame.Visible = true
	end
	if dashTextLbl then
		dashTextLbl.Text = "DASH"
		dashTextLbl.TextSize = if lastIsCompact then 11 else 13
		if lastIsTouch then
			dashTextLbl.Size = UDim2.new(1, -6, 0, 15)
			dashTextLbl.Position = UDim2.new(0, 3, 1, if lastIsCompact then -21 else -24)
		else
			dashTextLbl.Size = UDim2.new(1, -6, 0, 15)
			dashTextLbl.Position = UDim2.fromOffset(3, if lastIsCompact then 23 else 27)
		end
	end
	if dashSubLbl then
		dashSubLbl.Visible = not lastIsTouch
		dashSubLbl.Position = UDim2.new(0, 0, 1, if lastIsCompact then -16 else -19)
	end
end

local function applyCombatButtonTypography(compact: boolean, isTouch: boolean)
	if autoAimTitleLbl then
		autoAimTitleLbl.Text = if isTouch then "AUTO AIM" else "AUTO [F]"
	end
	if shootIconFrame then
		local sIc = if compact then 24 else 28
		shootIconFrame.Size = UDim2.fromOffset(sIc, sIc)
		shootIconFrame.Position =
			UDim2.new(0.5, 0, 0, if isTouch then (if compact then 10 else 13) else 6)
	end
	if throwTextLbl then
		throwTextLbl.TextSize = if compact then 12 else 14
		throwTextLbl.Position = if isTouch
			then UDim2.new(0, 4, 1, if compact then -26 else -30)
			else UDim2.fromOffset(4, if compact then 30 else 34)
	end
	if throwHintLbl then
		throwHintLbl.Visible = not isTouch
		throwHintLbl.Position = UDim2.new(0, 0, 1, if compact then -17 else -20)
	end
	if jumpIconFrame then
		local jIc = if compact then 22 else 28
		jumpIconFrame.Size = UDim2.fromOffset(jIc, jIc)
		jumpIconFrame.Position = UDim2.new(0.5, 0, 0, if compact then 6 else 8)
	end
	if jumpTextLbl then
		jumpTextLbl.TextSize = if compact then 10 else 11
	end
	if not isDashOnCooldown then
		applyDashReadyLayout()
	end
end

local function applyCombatButtonsResponsive(m: Theme.LayoutMetrics)
	if not (actionHolder and throwBtn and dashBtn and autoAimBtn and jumpActionBtn) then
		return
	end
	local compact = m.isCompact
	actionHolder.Position =
		UDim2.new(1, if compact then -12 else -18, 1, if compact then -10 else -16)
	jumpActionBtn.Visible = m.isTouch
	if m.isTouch then
		local dS = if compact then 54 else 66
		local tS = if compact then 72 else 88
		dashBtn.Size = UDim2.fromOffset(dS, dS)
		dashBtn.Position = UDim2.new(1, 0, 1, if compact then -8 else -12)
		jumpActionBtn.Size = UDim2.fromOffset(dS, dS)
		jumpActionBtn.Position = UDim2.new(1, 0, 1, if compact then -76 else -96)
		throwBtn.Size = UDim2.fromOffset(tS, tS)
		throwBtn.Position =
			UDim2.new(1, if compact then -68 else -84, 1, if compact then -68 else -85)
		autoAimBtn.Size = UDim2.fromOffset(if compact then 88 else 112, 48)
		autoAimBtn.Position =
			UDim2.new(1, if compact then -66 else -82, 1, if compact then -12 else -21)
	else
		local dS = if compact then 56 else 68
		local tS = if compact then 66 else 78
		dashBtn.Size = UDim2.fromOffset(dS, dS)
		dashBtn.Position = UDim2.new(1, 0, 1, if compact then -8 else -12)
		throwBtn.Size = UDim2.fromOffset(tS, tS)
		throwBtn.Position =
			UDim2.new(1, if compact then -24 else -28, 1, if compact then -74 else -92)
		autoAimBtn.Size = UDim2.fromOffset(if compact then 104 else 122, 48)
		autoAimBtn.Position =
			UDim2.new(1, if compact then -68 else -82, 1, if compact then -14 else -22)
	end
	applyCombatButtonTypography(compact, m.isTouch)
end

local function getUsableViewport(m: Theme.LayoutMetrics): Vector2
	local viewport = if hudScreen then hudScreen.AbsoluteSize else m.viewport
	return if viewport.X > 0 and viewport.Y > 0 then viewport else m.viewport
end

local function measureDock(m: Theme.LayoutMetrics, width: number): (number, number, number)
	if m.isPortrait then
		return math.clamp(width - 24, 1, 340), 160, 0
	end
	if width < 560 then
		-- A shallow landscape phone needs more space for the combat arc than the thumbstick.
		return math.max(1, width - 317), 8, -23
	end
	local preferredWidth = if m.isCompact then math.floor(width * 0.38) else 360
	local reserved = if m.isCompact then 182 else 234
	return math.min(preferredWidth, width - 2 * reserved), if m.isCompact then 8 else 14, 0
end

local function placeStatusBanner(
	frame: Frame,
	m: Theme.LayoutMetrics,
	viewport: Vector2,
	width: number,
	bottom: number,
	centerOffset: number
): number
	local height = 32
	local drawer = drawerWrap
	local drawerBottom = if drawer then drawer.Position.Y.Offset + drawer.Size.Y.Offset else 0
	if m.isPortrait and drawer and viewport.Y - bottom - height < drawerBottom + 4 then
		local left = drawer.Size.X.Offset + 6
		width = math.max(1, math.min(width, viewport.X - left - 8))
		height = 44
		frame.Position = UDim2.new(0, left + width / 2, 1, -bottom)
	else
		frame.Position = UDim2.new(0.5, centerOffset, 1, -bottom)
	end
	frame.Size = UDim2.fromOffset(width, height)
	return height
end

local function applyDockAndBannersResponsive(m: Theme.LayoutMetrics)
	local viewport = getUsableViewport(m)
	local dockWidth, dockBottom, centerOffset = measureDock(m, viewport.X)
	local dockHeight = 76
	if statusDock then
		statusDock.Size = UDim2.fromOffset(dockWidth, dockHeight)
		statusDock.Position = UDim2.new(0.5, centerOffset, 1, -dockBottom)
	end
	local stackBottom = dockBottom + dockHeight + 6
	if currencyStack then
		currencyStack.Position = UDim2.new(0.5, centerOffset, 1, -stackBottom)
	end
	local guideBottom = stackBottom + 68
	local guideHeight = 32
	if guideFrame then
		local width = if m.isCompact then dockWidth else 420
		guideHeight = placeStatusBanner(guideFrame, m, viewport, width, guideBottom, centerOffset)
	end
	if afkBadgeFrame then
		local width = if m.isCompact then math.min(260, dockWidth) else 320
		placeStatusBanner(
			afkBadgeFrame,
			m,
			viewport,
			width,
			guideBottom + guideHeight + 4,
			centerOffset
		)
	end
end

local function applyTopRightResponsive(compact: boolean)
	if topRightStack then
		topRightStack.Position =
			UDim2.new(1, if compact then -10 else -14, 0, if compact then 58 else 70)
		local list = topRightStack:FindFirstChildOfClass("UIListLayout")
		if list then
			list.Padding = UDim.new(0, if compact then 4 else 6)
		end
	end
	if audioBtn then
		audioBtn.Size = UDim2.fromOffset(if compact then 104 else 124, if compact then 26 else 30)
	end
	if speakerIcon then
		local icS = if compact then 15 else 18
		speakerIcon.Size = UDim2.fromOffset(icS, icS)
		speakerIcon.Position = UDim2.new(0, if compact then 8 else 10, 0.5, 0)
	end
	if audioLabel then
		audioLabel.Position = UDim2.fromOffset(if compact then 26 else 32, 0)
		audioLabel.Size = UDim2.new(1, if compact then -30 else -34, 1, 0)
		audioLabel.TextSize = if compact then 10 else 11
	end
	if hubReturnBtn then
		hubReturnBtn.Size =
			UDim2.fromOffset(if compact then 100 else 120, if compact then 26 else 30)
	end
end

local function applyResponsiveLayout()
	local m = Theme.getLayoutMetrics()
	local compact = m.isCompact
	lastIsTouch = m.isTouch
	lastIsCompact = compact

	applyTopLeftResponsive(m)
	applyTopRightResponsive(compact)

	applyDrawerResponsive(compact, m.isPortrait)
	applyDockAndBannersResponsive(m)
	applyCombatButtonsResponsive(m)
	task.defer(syncNativeTouchJump)
end

local function buildGuideBanner(gui: ScreenGui)
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
end

local function buildAfkBadge(gui: ScreenGui)
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
	afkLbl.TextScaled = true
	afkLbl.TextWrapped = true
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 12
	constraint.MinTextSize = 9
	constraint.Parent = afkLbl
end

local function bindHudEvents()
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
end

function HudGui.mount(callbacks: {
	onThrow: () -> (),
	onThrowHold: ((boolean) -> ())?,
	onDash: () -> (),
	onToggleAutoAim: (() -> ())?,
	onOpenModal: (string) -> (),
	onOpenDaily: (() -> ())?,
	onTogglePing: (() -> ())?,
	onVaultAction: (() -> ())?,
	onOpenOrbs: (() -> ())?,
})
	throwCallback = callbacks.onThrow
	throwHoldCallback = callbacks.onThrowHold
	dashCallback = callbacks.onDash
	toggleAutoAimCallback = callbacks.onToggleAutoAim
	openModalCallback = callbacks.onOpenModal
	openDailyCallback = callbacks.onOpenDaily
	togglePingCallback = callbacks.onTogglePing
	vaultActionCallback = callbacks.onVaultAction
	openOrbsCallback = callbacks.onOpenOrbs

	local gui = Theme.createScreenGui("BallBrawl_HUD", 10)
	hudScreen = gui

	buildCurrencyStack(gui)
	buildTopLeftActionBar(gui)
	buildTopRight(gui)
	buildMenuDrawer(gui)
	buildHeroStatusDock(gui)
	buildCombatButtons(gui)
	buildGuideBanner(gui)
	buildAfkBadge(gui)
	bindHudEvents()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyResponsiveLayout)
	applyResponsiveLayout()
end

local function updateLevelProgress(rawLevel: any, rawExp: any)
	local level = if MathUtil.isFinite(rawLevel) then math.max(1, math.floor(rawLevel)) else 1
	local exp = if MathUtil.isFinite(rawExp) then math.max(0, math.floor(rawExp)) else 0
	local cap = EconomyConfigs.getExpForNextLevel(level)
	local shownExp = math.min(exp, cap)
	if levelLabel then
		levelLabel.Text = `Lvl {level}`
	end
	if expValueLabel then
		expValueLabel.Text = `{MathUtil.formatNumber(shownExp)} / {MathUtil.formatNumber(cap)} EXP`
	end
	if expFillBar then
		expFillBar.Size = UDim2.fromScale(shownExp / cap, 1)
	end
end

function HudGui.updateProfile(profile: any, powerRating: number, maxHP: number)
	profileMaxHP = math.max(1, tonumber(maxHP) or 100)
	if coinsValLabel then
		coinsValLabel.Text = MathUtil.formatNumber(profile.coins or 0)
	end
	if gemsValLabel then
		gemsValLabel.Text = MathUtil.formatNumber(profile.bossGems or 0)
	end
	updateLevelProgress(profile.level, profile.exp)
	if pwrLabel then
		pwrLabel.Text = `⚡ PWR: {MathUtil.formatNumber(powerRating or 0)}`
	end
	if dmgLabel then
		dmgLabel.Text = `⚔ DMG: {MathUtil.formatNumber(profile.ballDamage or 5)}`
	end
	if spdLabel then
		spdLabel.Text = string.format("» SPD: %.2fx", profile.throwSpeed or 1.0)
	end
	if type(profile.winStreak) == "number" then
		cachedWinStreak = math.max(0, math.floor(profile.winStreak))
		refreshStreakPartyBadge()
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

function HudGui.updateSocialState(syncState: { [string]: any })
	if type(syncState) ~= "table" then
		return
	end
	local ready = if syncState.dailyClaimable == true then 1 else 0
	for _, q in ipairs(syncState.quests or {}) do
		if type(q) == "table" and not q.claimed and (q.progress or 0) >= (q.target or 1) then
			ready += 1
		end
	end
	if dailyAlertDot then
		dailyAlertDot.Visible = ready > 0
	end
	local mult = tonumber(syncState.friendBonusMult) or 1.0
	cachedCoOpPct = math.max(0, math.floor((mult - 1.0) * 100 + 0.5))
	local pSize = tonumber(syncState.partySize) or 0
	local fCount = tonumber(syncState.friendCount) or 0
	cachedPartyTag = if pSize > 1 then `P{pSize}` else `{fCount}F`
	if type(syncState.winStreak) == "number" then
		cachedWinStreak = math.max(0, math.floor(syncState.winStreak))
	end
	refreshStreakPartyBadge()
end

function HudGui.updateVaultState(vaultSync: { [string]: any })
	if type(vaultSync) ~= "table" then
		return
	end
	cachedVaultActive = vaultSync.active == true
	cachedVaultStorm = vaultSync.isHourlyStorm == true
	if vaultQuickBtn then
		local lbl = vaultQuickBtn:FindFirstChild("Text")
		if lbl and lbl:IsA("TextLabel") then
			lbl.Text = if cachedVaultActive
				then "EXIT"
				elseif cachedVaultStorm then "VAULT ⚡"
				else "VAULT"
		end
		if cachedVaultActive then
			Theme.addGradient(vaultQuickBtn, Theme.Colors.ShopRedTop, Theme.Colors.ShopRedBot, 90)
		elseif cachedVaultStorm then
			Theme.addGradient(vaultQuickBtn, Theme.Colors.GoldTop, Theme.Colors.GoldBot, 90)
		else
			Theme.addGradient(vaultQuickBtn, Theme.Colors.LimeTop, Theme.Colors.LimeBot, 90)
		end
	end
	if orbsQuickBtn then
		orbsQuickBtn.Visible = not cachedVaultActive
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
	local stateColor = if enabled then Theme.Colors.Emerald else Theme.Colors.Danger
	autoAimStateLbl.Text = if enabled then "ON" else "OFF"
	autoAimStateLbl.TextColor3 = stateColor
	HudIcons.setReticleColor(autoAimReticle, stateColor)
	setAimButtonPalette(autoAimBtn, enabled)
end

function HudGui.setDashCooldown(remaining: number)
	if not dashBtn or not dashTextLbl then
		return
	end
	if remaining > 0.05 then
		if not isDashOnCooldown then
			isDashOnCooldown = true
			Theme.addGradient(dashBtn, Theme.Colors.CardAlt, Theme.Colors.PanelBottom, 90)
			if dashIconFrame then
				dashIconFrame.Visible = false
			end
			if dashSubLbl then
				dashSubLbl.Visible = false
			end
			dashTextLbl.Size = UDim2.fromScale(1, 1)
			dashTextLbl.Position = UDim2.fromOffset(0, 0)
			dashTextLbl.TextSize = if lastIsCompact then 14 else 17
		end
		dashTextLbl.Text = string.format("%.1fs", remaining)
	elseif isDashOnCooldown then
		isDashOnCooldown = false
		Theme.addGradient(dashBtn, Theme.Colors.TileSkyTop, Theme.Colors.TileSkyBot, 90)
		applyDashReadyLayout()
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
