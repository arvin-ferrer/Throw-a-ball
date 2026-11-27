--!strict
--[[
	ViralSocialController.luau
	Client controller for Ball Brawl: Boss Eggs Retention & Viral Social Engine:
	- Friend & PartyId Co-Op HUD badge (+10%/ally up to +30%)
	- Non-verbal 4-icon Quick-Ping Wheel (Keybind G + mobile button) & 3D world markers
	- Server-wide GlobalAnnouncement celebration toast + 1-tap CaptureService Save Clip
	- Forgiving 7-Day Daily Check-In, 3 Daily Quests & Live Hub Leaderboards modal
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RetentionConfigs = require(Shared.Configs.RetentionConfigs)
local MathUtil = require(Shared.Utils.MathUtil)
local AudioCatalog = require(Shared.Utils.AudioCatalog)
local Remotes = require(Shared.Net.Remotes)

local Theme = require(script.Parent.Parent.UI.Theme)
local HudIcons = require(script.Parent.Parent.UI.HudIcons)

local ViralSocialController = {}

local WHITE = Color3.fromRGB(255, 255, 255)
local MUTED_TOP = Color3.fromRGB(142, 154, 178)
local MUTED_BOT = Color3.fromRGB(104, 116, 140)
local PING_CHIME_SOUND = "rbxassetid://12221976"

local TAB_SPECS = {
	{
		id = "Daily",
		label = "DAILY",
		header = "7-DAY CHECK-IN (NO RESET!)",
		top = Theme.Colors.GoldTop,
		bot = Theme.Colors.GoldBot,
	},
	{
		id = "Quests",
		label = "QUESTS",
		header = "DAILY QUESTS",
		top = Theme.Colors.LimeTop,
		bot = Theme.Colors.LimeBot,
	},
	{
		id = "Leaderboard",
		label = "RANKS",
		header = "LIVE HUB LEADERBOARDS",
		top = Theme.Colors.HubBlueTop,
		bot = Theme.Colors.HubBlueBot,
	},
}

local localPlayer = Players.LocalPlayer
local mainGui: ScreenGui? = nil
local topBarFrame: Frame? = nil
local dailyBtn: TextButton? = nil
local dailyBadgeDot: Frame? = nil
local pingToggleBtn: TextButton? = nil
local coopBadgeFrame: Frame? = nil
local coopBadgeLabel: TextLabel? = nil
local pingWheelFrame: Frame? = nil
local toastFrame: Frame? = nil
local toastHeadline: TextLabel? = nil
local toastDetail: TextLabel? = nil
local saveClipBtn: TextButton? = nil
local modalRoot: Frame? = nil
local modalHeaderBar: Frame? = nil
local modalHeaderTitle: TextLabel? = nil
local modalScroll: ScrollingFrame? = nil
local modalTabButtons: { [string]: TextButton } = {}
local activeTab = "Daily"
local isStarted = false
local announcementSeq = 0
local topBarExternalHidden = false
local syncListener: (({ [string]: any }) -> ())? = nil

local syncState: { [string]: any } = {
	dailyDay = 1,
	dailyClaimable = false,
	cumulativeDays = 0,
	quests = {},
	friendBonusMult = 1.0,
	friendCount = 0,
	partySize = 0,
	winStreak = 0,
	bestWinStreak = 0,
	totalBossWins = 0,
	leaderboards = { power = {}, wins = {}, income = {} },
}

local function waitRemote(folder: Folder, name: string): RemoteEvent
	local inst = folder:WaitForChild(name, 15)
	if not inst or not inst:IsA("RemoteEvent") then
		error(`Timed out waiting for social remote {name}`)
	end
	return inst
end

local function applyTextConstraint(lbl: TextLabel | TextButton, minSize: number, maxSize: number)
	lbl.TextScaled = true
	local tc = Instance.new("UITextSizeConstraint")
	tc.MinTextSize = minSize
	tc.MaxTextSize = maxSize
	tc.Parent = lbl
end

local function sendRetentionAction(action: string, questId: string?)
	local folder = Remotes.waitClient().Folder
	local remote = waitRemote(folder, "RetentionAction")
	remote:FireServer({ action = action, questId = questId })
end

local function countReadyClaims(): number
	local count = if syncState.dailyClaimable then 1 else 0
	for _, q in ipairs(syncState.quests or {}) do
		if type(q) == "table" and not q.claimed and (q.progress or 0) >= (q.target or 1) then
			count += 1
		end
	end
	return count
end

local function updateTopBarWidgets()
	local mult = tonumber(syncState.friendBonusMult) or 1.0
	local pct = math.max(0, math.floor((mult - 1.0) * 100 + 0.5))
	local fCount = tonumber(syncState.friendCount) or 0
	local pSize = tonumber(syncState.partySize) or 0
	if coopBadgeLabel and coopBadgeFrame then
		if pct > 0 then
			local sourceTag = if pSize > 1
				then `PARTY {pSize}`
				else `{fCount} FRIEND{if fCount == 1 then "" else "S"}`
			coopBadgeLabel.Text = `CO-OP +{pct}% ({sourceTag})`
			Theme.addGradient(coopBadgeFrame, Theme.Colors.LimeTop, Theme.Colors.LimeBot, 90)
		else
			coopBadgeLabel.Text = "CO-OP +0% (SOLO)"
			Theme.addGradient(coopBadgeFrame, Theme.Colors.PanelTop, Theme.Colors.PanelBottom, 90)
		end
	end
	if dailyBadgeDot then
		dailyBadgeDot.Visible = countReadyClaims() > 0
	end
end

local function makeCoOpBadge(parent: Frame): Frame
	local badge = Theme.makeFrame(
		parent,
		"CoOpBadge",
		UDim2.fromOffset(154, 44),
		UDim2.fromOffset(0, 0),
		WHITE,
		999
	)
	badge.BackgroundTransparency = 0
	badge.LayoutOrder = 3
	Theme.addGradient(badge, Theme.Colors.PanelTop, Theme.Colors.PanelBottom, 90)
	Theme.addStroke(badge, Theme.Colors.Ink, 2.5, 0)

	local lbl = Theme.makeLabel(
		badge,
		"Text",
		"CO-OP +0% (SOLO)",
		UDim2.new(1, -14, 1, 0),
		UDim2.fromOffset(7, 0),
		12,
		WHITE,
		true
	)
	lbl.TextXAlignment = Enum.TextXAlignment.Center
	Theme.addTextStroke(lbl, 1.5, Theme.Colors.Ink)
	applyTextConstraint(lbl, 8, 12)
	coopBadgeLabel = lbl
	coopBadgeFrame = badge
	return badge
end

local function buildNotificationDot(btn: TextButton): Frame
	local dot = Instance.new("Frame")
	dot.Name = "AlertDot"
	dot.Size = UDim2.fromOffset(14, 14)
	dot.Position = UDim2.new(1, -10, 0, -2)
	dot.BackgroundColor3 = Theme.Colors.Danger
	dot.BorderSizePixel = 0
	dot.Visible = false
	dot.ZIndex = 4
	dot.Parent = btn
	Theme.addCorner(dot, 999)
	Theme.addStroke(dot, Theme.Colors.Ink, 2, 0)
	return dot
end

local function buildTopSocialBar(gui: ScreenGui)
	local bar = Instance.new("Frame")
	bar.Name = "ViralSocialTopBar"
	bar.BackgroundTransparency = 1
	bar.Position = UDim2.fromOffset(10, 8)
	bar.Size = UDim2.fromOffset(360, 48)
	bar.Parent = gui
	topBarFrame = bar

	local daily = Theme.makeGoldPillButton(
		bar,
		"DailyQuestsBtn",
		"DAILY",
		UDim2.fromOffset(96, 44),
		UDim2.fromOffset(0, 0),
		function()
			local defaultTab = if syncState.dailyClaimable then "Daily" else "Quests"
			ViralSocialController.openModal(defaultTab)
		end,
		Theme.Colors.GoldTop,
		Theme.Colors.GoldBot
	)
	daily.LayoutOrder = 1
	applyTextConstraint(daily, 10, 14)
	dailyBtn = daily
	dailyBadgeDot = buildNotificationDot(daily)

	local pingBtn = Theme.makeGoldPillButton(
		bar,
		"QuickPingBtn",
		"PING [G]",
		UDim2.fromOffset(88, 44),
		UDim2.fromOffset(102, 0),
		function()
			ViralSocialController.togglePingWheel()
		end,
		Theme.Colors.TileSkyTop,
		Theme.Colors.TileSkyBot
	)
	pingBtn.LayoutOrder = 2
	applyTextConstraint(pingBtn, 10, 13)
	pingToggleBtn = pingBtn

	makeCoOpBadge(bar)
end

local WHEEL_OFFSETS: { [string]: UDim2 } = {
	BossReady = UDim2.new(0.5, 0, 0, 8),
	Help = UDim2.new(0, 8, 0.5, 0),
	ExtractNow = UDim2.new(1, -8, 0.5, 0),
	NiceShot = UDim2.new(0.5, 0, 1, -8),
}

local WHEEL_ANCHORS: { [string]: Vector2 } = {
	BossReady = Vector2.new(0.5, 0),
	Help = Vector2.new(0, 0.5),
	ExtractNow = Vector2.new(1, 0.5),
	NiceShot = Vector2.new(0.5, 1),
}

local function makePingWheelOption(wheel: Frame, spec: RetentionConfigs.QuickPingSpec)
	local col = Color3.fromRGB(spec.color[1], spec.color[2], spec.color[3])
	local botCol = col:Lerp(Theme.Colors.Ink, 0.25)
	local btn = Theme.makeGoldPillButton(
		wheel,
		"Ping_" .. spec.id,
		`{spec.glyph}\n{spec.shortLabel}`,
		UDim2.fromOffset(92, 68),
		WHEEL_OFFSETS[spec.id] or UDim2.fromScale(0.5, 0.5),
		function()
			ViralSocialController.triggerQuickPing(spec.id)
		end,
		col,
		botCol
	)
	btn.AnchorPoint = WHEEL_ANCHORS[spec.id] or Vector2.new(0.5, 0.5)
	Theme.addCorner(btn, 16)
	applyTextConstraint(btn, 10, 14)
end

local function buildQuickPingWheel(gui: ScreenGui)
	local wheel = Theme.makeFrame(
		gui,
		"QuickPingWheel",
		UDim2.fromOffset(252, 252),
		UDim2.fromScale(0.5, 0.5),
		Theme.Colors.Panel,
		999
	)
	wheel.AnchorPoint = Vector2.new(0.5, 0.5)
	wheel.BackgroundTransparency = 0.14
	wheel.Visible = false
	Theme.addStroke(wheel, Theme.Colors.Ink, 3, 0)
	pingWheelFrame = wheel

	for _, spec in ipairs(RetentionConfigs.QUICK_PINGS) do
		makePingWheelOption(wheel, spec)
	end

	local closeBtn = Theme.makeGoldPillButton(
		wheel,
		"CloseWheel",
		"✕",
		UDim2.fromOffset(48, 48),
		UDim2.fromScale(0.5, 0.5),
		function()
			wheel.Visible = false
		end,
		MUTED_TOP,
		MUTED_BOT
	)
	closeBtn.AnchorPoint = Vector2.new(0.5, 0.5)
	applyTextConstraint(closeBtn, 14, 18)
end

local function triggerMomentCapture(btn: TextButton)
	btn.Text = "SAVING..."
	local okSvc, capSvc = pcall(function()
		return game:GetService("CaptureService")
	end)
	if not okSvc or not capSvc then
		btn.Text = "STUDIO N/A"
		return
	end
	local captured = pcall(function()
		(capSvc :: any):CaptureScreenshot(function(contentId: any)
			pcall(function()
				if contentId ~= nil then
					(capSvc :: any):PromptSaveCapturesToGallery({ contentId }, function() end)
				end
			end)
		end)
	end)
	btn.Text = if captured then "CLIP SAVED!" else "UNAVAILABLE"
end

local function addToastLabels(banner: Frame)
	local head = Theme.makeLabel(
		banner,
		"Headline",
		"CELEBRATION!",
		UDim2.new(1, -184, 0, 26),
		UDim2.fromOffset(58, 8),
		16,
		WHITE,
		true
	)
	head.ZIndex = 13
	Theme.addTextStroke(head, 1.8, Theme.Colors.Ink)
	applyTextConstraint(head, 10, 16)
	toastHeadline = head

	local det = Theme.makeLabel(
		banner,
		"Detail",
		"",
		UDim2.new(1, -184, 0, 22),
		UDim2.fromOffset(58, 36),
		12,
		WHITE,
		false
	)
	det.ZIndex = 13
	Theme.addTextStroke(det, 1.3, Theme.Colors.Ink)
	applyTextConstraint(det, 9, 12)
	toastDetail = det
end

local function buildCelebrationBanner(gui: ScreenGui)
	local banner = Theme.makeFrame(
		gui,
		"GlobalCelebrationBanner",
		UDim2.fromOffset(440, 68),
		UDim2.new(0.5, 0, 0, -90),
		WHITE,
		16
	)
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.BackgroundTransparency = 0
	banner.Visible = false
	banner.ZIndex = 12
	Theme.addGradient(banner, Theme.Colors.GoldTop, Theme.Colors.GoldBot, 90)
	Theme.addStroke(banner, Theme.Colors.Ink, 3, 0)
	toastFrame = banner

	local star = HudIcons.createStarBurstIcon(banner, 42)
	star.Position = UDim2.new(0, 10, 0.5, -21)
	star.ZIndex = 13
	addToastLabels(banner)

	local clipBtn = Theme.makeGoldPillButton(
		banner,
		"SaveClipBtn",
		"Save Clip",
		UDim2.fromOffset(112, 44),
		UDim2.new(1, -122, 0.5, -22),
		function() end,
		Theme.Colors.TileSkyTop,
		Theme.Colors.TileSkyBot
	)
	clipBtn.ZIndex = 14
	applyTextConstraint(clipBtn, 10, 13)
	clipBtn.Activated:Connect(function()
		triggerMomentCapture(clipBtn)
	end)
	saveClipBtn = clipBtn
end

local function clearModalScroll()
	if not modalScroll then
		return
	end
	for _, child in ipairs(modalScroll:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function makeModalCard(name: string, order: number, bg: Color3?): Frame
	local card = Instance.new("Frame")
	card.Name = name
	card.LayoutOrder = order
	card.Size = UDim2.fromScale(1, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = bg or WHITE
	card.BorderSizePixel = 0
	card.Parent = modalScroll
	Theme.addCorner(card, 12)
	Theme.addStroke(card, Theme.Colors.Ink, 2.5, 0)
	Theme.addPadding(card, 10, 10)
	return card
end

local function addAutoText(
	parent: Instance,
	name: string,
	text: string,
	size: number,
	color: Color3,
	bold: boolean,
	order: number
)
	local lbl = Theme.makeLabel(
		parent,
		name,
		text,
		UDim2.fromScale(1, 0),
		UDim2.fromOffset(0, 0),
		size,
		color,
		bold
	)
	lbl.LayoutOrder = order
	lbl.TextWrapped = true
	lbl.AutomaticSize = Enum.AutomaticSize.Y
end

local function buildHeroSummaryCard(name: string, titleTxt: string, subTxt: string, order: number)
	local card = makeModalCard(name, order, Color3.fromRGB(238, 246, 255))
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 4)
	list.Parent = card
	addAutoText(card, "Title", titleTxt, 14, Theme.Colors.TextDark, true, 1)
	addAutoText(card, "Sub", subTxt, 12, Theme.Colors.TextMutedDark, false, 2)
end

local function formatDailyRewardSummary(spec: RetentionConfigs.DailyRewardSpec): string
	local eggPart = if spec.eggId then ` + 1x {spec.eggId}` else ""
	return `+{MathUtil.formatNumber(spec.coins)} Coins, +{spec.gems} Boss Gems{eggPart}`
end

local function resolveDailySlotStatus(dayIdx: number): (boolean, boolean)
	local claimable = syncState.dailyClaimable == true
	local currentSlot = math.clamp(tonumber(syncState.dailyDay) or 1, 1, 7)
	if claimable then
		return dayIdx < currentSlot, dayIdx == currentSlot
	end
	return dayIdx <= currentSlot, false
end

local function buildClaimableRowCard(
	cardName: string,
	order: number,
	bg: Color3,
	titleText: string,
	subText: string,
	btnText: string,
	isReady: boolean,
	onClick: () -> ()
)
	local card = makeModalCard(cardName, order, bg)
	local left = Instance.new("Frame")
	left.BackgroundTransparency = 1
	left.Size = UDim2.new(1, -138, 0, 44)
	left.AutomaticSize = Enum.AutomaticSize.Y
	left.Parent = card
	local ll = Instance.new("UIListLayout")
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Padding = UDim.new(0, 2)
	ll.Parent = left
	addAutoText(left, "Title", titleText, 14, Theme.Colors.TextDark, true, 1)
	addAutoText(left, "Desc", subText, 12, Theme.Colors.TextMutedDark, false, 2)

	local btnTop = if isReady then Theme.Colors.LimeTop else MUTED_TOP
	local btnBot = if isReady then Theme.Colors.LimeBot else MUTED_BOT
	local btn = Theme.makeGoldPillButton(
		card,
		"ClaimBtn",
		btnText,
		UDim2.fromOffset(128, 44),
		UDim2.new(1, -128, 0.5, -22),
		onClick,
		btnTop,
		btnBot
	)
	applyTextConstraint(btn, 10, 14)
end

local function renderDailyRowCard(spec: RetentionConfigs.DailyRewardSpec, order: number)
	local isDone, isReady = resolveDailySlotStatus(spec.day)
	local bg = if isReady
		then Color3.fromRGB(255, 250, 224)
		elseif isDone then Color3.fromRGB(236, 253, 245)
		else WHITE
	local btnText = if isDone then "CLAIMED" elseif isReady then "CLAIM!" else "LOCKED"
	buildClaimableRowCard(
		"Day_" .. tostring(spec.day),
		order,
		bg,
		`Day {spec.day}: {spec.title}`,
		formatDailyRewardSummary(spec),
		btnText,
		isReady,
		function()
			if isReady then
				sendRetentionAction("ClaimDaily", nil)
			end
		end
	)
end

local function renderDailyTab()
	local totalDays = tonumber(syncState.cumulativeDays) or 0
	local pct =
		math.max(0, math.floor(((tonumber(syncState.friendBonusMult) or 1) - 1) * 100 + 0.5))
	buildHeroSummaryCard(
		"DailyHeader",
		`Cumulative Check-Ins: {totalDays} Days • Co-Op Bonus: +{pct}%`,
		"Missed days NEVER reset your progress! Squad up with Friends or Roblox Party mates for up to +30% Coins & EXP.",
		1
	)
	for idx, spec in ipairs(RetentionConfigs.DAILY_REWARDS) do
		renderDailyRowCard(spec, idx + 1)
	end
end

local function renderQuestRowCard(quest: any, order: number)
	local target = math.max(1, tonumber(quest.target) or 1)
	local progress = math.clamp(tonumber(quest.progress) or 0, 0, target)
	local claimed = quest.claimed == true
	local canClaim = not claimed and progress >= target
	local bg = if canClaim
		then Color3.fromRGB(255, 250, 224)
		elseif claimed then Color3.fromRGB(236, 253, 245)
		else WHITE
	local btnText = if claimed
		then "CLAIMED"
		elseif canClaim then "CLAIM!"
		else `{progress}/{target}`
	local rewardTxt =
		`{quest.description} • +{MathUtil.formatNumber(quest.rewardCoins or 0)} Coins, +{quest.rewardGems or 0} Gems`
	buildClaimableRowCard(
		"Quest_" .. tostring(quest.id),
		order,
		bg,
		`{quest.title} ({progress}/{target})`,
		rewardTxt,
		btnText,
		canClaim,
		function()
			if canClaim then
				sendRetentionAction("ClaimQuest", tostring(quest.id))
			end
		end
	)
end

local function renderQuestsTab()
	buildHeroSummaryCard(
		"QuestsHeader",
		"3 Rotating Daily Quests",
		"Complete arena, training, and Vault Heist objectives for bonus Coins & Boss Gems!",
		1
	)
	local quests = syncState.quests or {}
	if #quests == 0 then
		buildHeroSummaryCard(
			"QuestsLoading",
			"Syncing Daily Quests...",
			"Check back in a second.",
			2
		)
		return
	end
	for idx, q in ipairs(quests) do
		renderQuestRowCard(q, idx + 1)
	end
end

local function renderLeaderboardSection(
	name: string,
	heading: string,
	rows: { any }?,
	suffix: string,
	order: number
)
	local card = makeModalCard(name, order, WHITE)
	local ll = Instance.new("UIListLayout")
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Padding = UDim.new(0, 4)
	ll.Parent = card
	addAutoText(card, "Heading", heading, 14, Theme.Colors.TextDark, true, 1)
	if not rows or #rows == 0 then
		addAutoText(
			card,
			"Empty",
			"No players ranked yet.",
			12,
			Theme.Colors.TextMutedDark,
			false,
			2
		)
		return
	end
	for idx, r in ipairs(rows) do
		local isSelf = tonumber(r.userId) == localPlayer.UserId
		local rowColor = if isSelf then Theme.Colors.HubBlueBot else Theme.Colors.TextMutedDark
		local rowText =
			`#{r.rank} {r.displayName} — {MathUtil.formatNumber(r.value or 0)}{suffix}`
		addAutoText(card, `Row_{idx}`, rowText, 13, rowColor, isSelf, idx + 1)
	end
end

local function renderLeaderboardTab()
	local streak = tonumber(syncState.winStreak) or 0
	local best = tonumber(syncState.bestWinStreak) or 0
	local wins = tonumber(syncState.totalBossWins) or 0
	buildHeroSummaryCard(
		"StreakSummary",
		`Win Streak: {streak} (Best: {best}) • Total Boss Wins: {wins}`,
		"Reach a 3+ Win Streak, defeat an Overcharged Boss, hatch a Mythic, or extract Chamber 2+ for a Server Celebration!",
		1
	)
	local boards = syncState.leaderboards or {}
	renderLeaderboardSection("PowerRanks", "⚡ TOP POWER RATING", boards.power, "", 2)
	renderLeaderboardSection("WinsRanks", "⚔ TOP BOSS WINS", boards.wins, " Wins", 3)
	renderLeaderboardSection("IncomeRanks", "💰 TOP COINS/SEC", boards.income, "/s", 4)
end

local function updateModalTabVisuals()
	for _, spec in ipairs(TAB_SPECS) do
		local selected = activeTab == spec.id
		local btn = modalTabButtons[spec.id]
		if btn then
			Theme.addGradient(
				btn,
				if selected then spec.top else MUTED_TOP,
				if selected then spec.bot else MUTED_BOT,
				90
			)
		end
		if selected then
			if modalHeaderTitle then
				modalHeaderTitle.Text = spec.header
			end
			if modalHeaderBar then
				Theme.addGradient(modalHeaderBar, spec.top, spec.bot, 90)
			end
		end
	end
end

local function rerenderModal()
	if not modalRoot or not modalRoot.Visible then
		return
	end
	updateModalTabVisuals()
	clearModalScroll()
	if activeTab == "Daily" then
		renderDailyTab()
	elseif activeTab == "Quests" then
		renderQuestsTab()
	else
		renderLeaderboardTab()
	end
end

local function buildModalTabs(panel: Frame)
	local row = Instance.new("Frame")
	row.Name = "TabRow"
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(14, 60)
	row.Size = UDim2.new(1, -28, 0, 44)
	row.Parent = panel
	local tl = Instance.new("UIListLayout")
	tl.FillDirection = Enum.FillDirection.Horizontal
	tl.SortOrder = Enum.SortOrder.LayoutOrder
	tl.Padding = UDim.new(0, 8)
	tl.Parent = row

	for idx, spec in ipairs(TAB_SPECS) do
		local tb = Theme.makeGoldPillButton(
			row,
			"Tab_" .. spec.id,
			spec.label,
			UDim2.fromScale(0.32, 1),
			UDim2.fromOffset(0, 0),
			function()
				activeTab = spec.id
				rerenderModal()
			end,
			spec.top,
			spec.bot
		)
		tb.LayoutOrder = idx
		applyTextConstraint(tb, 10, 14)
		local fx = Instance.new("UIFlexItem")
		fx.FlexMode = Enum.UIFlexMode.Fill
		fx.Parent = tb
		modalTabButtons[spec.id] = tb
	end
end

local function buildModalScroll(panel: Frame)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Body"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(12, 112)
	scroll.Size = UDim2.new(1, -24, 1, -122)
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = Theme.Colors.Ink
	scroll.Parent = panel
	Theme.addPadding(scroll, 4, 4)
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 10)
	list.Parent = scroll
	modalScroll = scroll
end

local function buildSocialModal(gui: ScreenGui)
	local panel = Theme.makeCartoonWindow(
		gui,
		"ViralSocialModal",
		UDim2.fromScale(0.92, 0.86),
		UDim2.fromScale(0.5, 0.5),
		16
	)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Visible = false
	panel.ZIndex = 20
	local sc = Instance.new("UISizeConstraint")
	sc.MaxSize = Vector2.new(600, 480)
	sc.MinSize = Vector2.new(300, 260)
	sc.Parent = panel
	modalRoot = panel

	local bar, title = Theme.makeHeaderBanner(
		panel,
		"DAILY & LEADERBOARDS",
		Theme.Colors.GoldTop,
		Theme.Colors.GoldBot,
		function()
			panel.Visible = false
		end
	)
	modalHeaderBar = bar
	modalHeaderTitle = title
	applyTextConstraint(title, 14, 22)
	buildModalTabs(panel)
	buildModalScroll(panel)
end

local function applyResponsiveLayout()
	local m = Theme.getLayoutMetrics()
	local compact = m.isCompact
	if topBarFrame and dailyBtn and pingToggleBtn and coopBadgeFrame then
		if compact then
			topBarFrame.Position = UDim2.fromOffset(8, 6)
			topBarFrame.Size = UDim2.fromOffset(170, 82)
			dailyBtn.Size = UDim2.fromOffset(92, 44)
			dailyBtn.Position = UDim2.fromOffset(0, 0)
			pingToggleBtn.Size = UDim2.fromOffset(70, 44)
			pingToggleBtn.Position = UDim2.fromOffset(98, 0)
			pingToggleBtn.Text = if m.isTouch then "PING" else "PING [G]"
			coopBadgeFrame.Size = UDim2.fromOffset(168, 30)
			coopBadgeFrame.Position = UDim2.fromOffset(0, 48)
		else
			topBarFrame.Position = UDim2.fromOffset(12, 8)
			topBarFrame.Size = UDim2.fromOffset(360, 48)
			dailyBtn.Size = UDim2.fromOffset(96, 44)
			dailyBtn.Position = UDim2.fromOffset(0, 0)
			pingToggleBtn.Size = UDim2.fromOffset(88, 44)
			pingToggleBtn.Position = UDim2.fromOffset(102, 0)
			pingToggleBtn.Text = if m.isTouch then "PING" else "PING [G]"
			coopBadgeFrame.Size = UDim2.fromOffset(158, 44)
			coopBadgeFrame.Position = UDim2.fromOffset(196, 0)
		end
	end
	if pingWheelFrame then
		local sz = if compact then 232 else 256
		pingWheelFrame.Size = UDim2.fromOffset(sz, sz)
	end
	if toastFrame then
		local tw = if m.isPortrait
			then math.clamp(m.viewport.X - 24, 240, 360)
			elseif compact then math.clamp(m.viewport.X - 340, 240, 350)
			else 460
		toastFrame.Size = UDim2.fromOffset(tw, if compact then 62 else 68)
	end
end

local function playPingChime(pitch: number)
	if AudioCatalog.isMuted() then
		return
	end
	local snd = Instance.new("Sound")
	snd.SoundId = PING_CHIME_SOUND
	snd.PlaybackSpeed = pitch
	snd.Volume = 0.24
	snd.Parent = SoundService
	snd:Play()
	task.delay(1.8, function()
		if snd.Parent then
			snd:Destroy()
		end
	end)
end

local function createPingBillboard(
	anchor: Part,
	spec: RetentionConfigs.QuickPingSpec,
	sender: string
)
	local bb = Instance.new("BillboardGui")
	bb.Adornee = anchor
	bb.Size = UDim2.fromOffset(154, 54)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 260
	bb.Parent = anchor

	local col = Color3.fromRGB(spec.color[1], spec.color[2], spec.color[3])
	local pill = Theme.makeFrame(bb, "Card", UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), col, 14)
	pill.BackgroundTransparency = 0.08
	Theme.addStroke(pill, Theme.Colors.Ink, 2.5, 0)

	local topLbl = Theme.makeLabel(
		pill,
		"Ping",
		`{spec.glyph} {spec.label}`,
		UDim2.new(1, -10, 0, 26),
		UDim2.fromOffset(5, 4),
		15,
		WHITE,
		true
	)
	topLbl.TextXAlignment = Enum.TextXAlignment.Center
	Theme.addTextStroke(topLbl, 1.8, Theme.Colors.Ink)
	applyTextConstraint(topLbl, 10, 15)

	local whoLbl = Theme.makeLabel(
		pill,
		"Sender",
		sender,
		UDim2.new(1, -10, 0, 18),
		UDim2.fromOffset(5, 30),
		11,
		WHITE,
		false
	)
	whoLbl.TextXAlignment = Enum.TextXAlignment.Center
	Theme.addTextStroke(whoLbl, 1.3, Theme.Colors.Ink)
	applyTextConstraint(whoLbl, 8, 11)
end

local function spawnPingWorldMarker(payload: any)
	if type(payload) ~= "table" or typeof(payload.worldPos) ~= "Vector3" then
		return
	end
	local spec = RetentionConfigs.getQuickPing(tostring(payload.pingId or ""))
	if not spec then
		return
	end
	playPingChime(spec.soundPitch)

	local anchor = Instance.new("Part")
	anchor.Name = "QuickPingMarker"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(payload.worldPos + Vector3.new(0, 4.5, 0))
	anchor.Parent = workspace

	createPingBillboard(anchor, spec, tostring(payload.displayName or "Squad"))
	if not GuiService.ReducedMotionEnabled then
		TweenService:Create(
			anchor,
			TweenInfo.new(spec.durationSec, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = CFrame.new(payload.worldPos + Vector3.new(0, 6.2, 0)) }
		):Play()
	end
	task.delay(spec.durationSec, function()
		if anchor.Parent then
			anchor:Destroy()
		end
	end)
end

local function showCelebrationBanner(payload: any)
	if type(payload) ~= "table" or not toastFrame or not toastHeadline or not toastDetail then
		return
	end
	announcementSeq += 1
	local mySeq = announcementSeq
	local acc = if type(payload.accent) == "table" then payload.accent else { 251, 191, 36 }
	local topCol = Color3.fromRGB(acc[1] or 251, acc[2] or 191, acc[3] or 36)
	local botCol = topCol:Lerp(Theme.Colors.Ink, 0.30)
	Theme.addGradient(toastFrame, topCol, botCol, 90)
	toastHeadline.Text = tostring(payload.headline or "SERVER MILESTONE!")
	toastDetail.Text = tostring(payload.detail or "")

	local hasClip = payload.suggestClip == true
	if saveClipBtn then
		saveClipBtn.Visible = hasClip
		saveClipBtn.Text = tostring(payload.clipLabel or "Save Clip")
	end
	local textOffset = if hasClip then -184 else -68
	toastHeadline.Size = UDim2.new(1, textOffset, 0, 26)
	toastDetail.Size = UDim2.new(1, textOffset, 0, 22)

	toastFrame.Visible = true
	toastFrame.Position = UDim2.new(0.5, 0, 0, -90)
	if GuiService.ReducedMotionEnabled then
		toastFrame.Position = UDim2.new(0.5, 0, 0, 12)
	else
		TweenService:Create(
			toastFrame,
			TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0.5, 0, 0, 12) }
		):Play()
	end
	AudioCatalog.play("Victory", 1.08, 0.28)

	task.delay(6.5, function()
		if announcementSeq == mySeq and toastFrame then
			toastFrame.Visible = false
		end
	end)
end

local function onRetentionSync(payload: any)
	if type(payload) ~= "table" then
		return
	end
	syncState = payload
	updateTopBarWidgets()
	rerenderModal()
	if syncListener then
		syncListener(syncState)
	end
end

local function bindResponsiveHooks(gui: ScreenGui)
	local function hookCam()
		local cam = workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(applyResponsiveLayout)
		end
	end
	hookCam()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hookCam)
	UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(applyResponsiveLayout)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyResponsiveLayout)
	applyResponsiveLayout()
end

function ViralSocialController.togglePingWheel()
	if pingWheelFrame then
		pingWheelFrame.Visible = not pingWheelFrame.Visible
	end
end

function ViralSocialController.triggerQuickPing(pingId: string)
	if pingWheelFrame then
		pingWheelFrame.Visible = false
	end
	local char = localPlayer.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
	local worldPos = if hrp and hrp:IsA("BasePart") then hrp.Position else nil
	local folder = Remotes.waitClient().Folder
	waitRemote(folder, "QuickPing"):FireServer({
		pingId = pingId,
		worldPos = worldPos,
	})
end

function ViralSocialController.openModal(tabName: string?)
	if tabName == "Daily" or tabName == "Quests" or tabName == "Leaderboard" then
		activeTab = tabName
	end
	if modalRoot then
		modalRoot.Visible = true
		rerenderModal()
	end
	sendRetentionAction("RequestState", nil)
end

function ViralSocialController.closeModal()
	if modalRoot then
		modalRoot.Visible = false
	end
end

function ViralSocialController.setTopBarVisible(visible: boolean)
	topBarExternalHidden = not visible
	if topBarFrame then
		topBarFrame.Visible = visible
	end
end

function ViralSocialController.onSyncChanged(cb: ({ [string]: any }) -> ())
	syncListener = cb
	cb(syncState)
end

function ViralSocialController.getSyncState(): { [string]: any }
	return syncState
end

function ViralSocialController.getScreenGui(): ScreenGui?
	return mainGui
end

function ViralSocialController.start()
	if isStarted then
		return
	end
	isStarted = true
	local gui = Theme.createScreenGui("BallBrawl_ViralSocial", 18)
	mainGui = gui

	buildTopSocialBar(gui)
	if topBarExternalHidden and topBarFrame then
		topBarFrame.Visible = false
	end
	buildQuickPingWheel(gui)
	buildCelebrationBanner(gui)
	buildSocialModal(gui)
	bindResponsiveHooks(gui)

	local coreRemotes = Remotes.waitClient()
	local folder = coreRemotes.Folder
	waitRemote(folder, "QuickPing").OnClientEvent:Connect(spawnPingWorldMarker)
	waitRemote(folder, "RetentionSync").OnClientEvent:Connect(onRetentionSync)
	waitRemote(folder, "GlobalAnnouncement").OnClientEvent:Connect(showCelebrationBanner)

	coreRemotes.ToastNotify.OnClientEvent:Connect(function(msg: any)
		if type(msg) ~= "string" or string.sub(msg, 1, 11) ~= "OPEN_MODAL:" then
			return
		end
		local target = string.sub(msg, 12)
		if target == "Leaderboard" or target == "Daily" or target == "Quests" then
			ViralSocialController.openModal(target)
		end
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.G then
			ViralSocialController.togglePingWheel()
		end
	end)

	task.spawn(function()
		sendRetentionAction("RequestState", nil)
	end)
end

return ViralSocialController
