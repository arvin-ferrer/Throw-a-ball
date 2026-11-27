--!strict
--[[
	VaultHeistController.luau
	Client controller & mobile-first cartoon HUD for C2: Egg Heist:
	- Top-Left 0s-wait Quick Launch ("VAULT HEIST") & Utility Orb Shop modal trigger
	- Heavy-Egg carry speed & downed override on PreSimulation (cleanly layered over BallThrowController)
	- 3 Utility Orb buttons with 3D arc preview + magnetic aim + keyboard [1]/[2]/[3], [E], [R]
	- Procedural mutator feel (local LowGravity VectorForce & Darkness ColorCorrection)
	- 10s Push-Your-Luck Extraction Vote Modal (Extract Now vs Dive Deeper)
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AudioCatalog = require(Shared.Utils.AudioCatalog)
local MathUtil = require(Shared.Utils.MathUtil)
local Remotes = require(Shared.Net.Remotes)
local VaultHeistConfigs = require(Shared.Configs.VaultHeistConfigs)

local Theme = require(script.Parent.Parent.UI.Theme)

local VaultHeistController = {}

local localPlayer = Players.LocalPlayer
local startQuickBtn: TextButton? = nil
local orbsQuickBtn: TextButton? = nil
local leaveBtn: TextButton? = nil
local stormChip: TextLabel? = nil

local runHeader: Frame? = nil
local headerTitleLbl: TextLabel? = nil
local headerSubLbl: TextLabel? = nil
local bossHpFill: Frame? = nil
local bossHpText: TextLabel? = nil
local promptBanner: TextLabel? = nil

local orbDock: Frame? = nil
local orbSlotBtns: { [string]: TextButton } = {}
local orbCdLabels: { [string]: TextLabel } = {}
local orbLvLabels: { [string]: TextLabel } = {}
local eggActionBtn: TextButton? = nil

local orbModal: Frame? = nil
local orbScroll: ScrollingFrame? = nil
local voteModal: Frame? = nil
local voteTitleLbl: TextLabel? = nil
local voteDescLbl: TextLabel? = nil
local voteDiveBtn: TextButton? = nil

local currentSync: { [string]: any } = {
	active = false,
	chamber = 1,
	mutatorId = "LowGravity",
	timeLeft = 0,
	bossHP = 0,
	bossMaxHP = 1,
	bossState = "PATROL",
	voteActive = false,
	streakMult = 1.0,
	orbCooldowns = {},
	orbLevels = { Decoy = 1, Freeze = 0, DashBomb = 0 },
	vaultBankCount = 0,
	isHourlyStorm = false,
}

local syncReceivedAt = 0
local previewOrbId: string? = nil
local previewStartAt = 0
local previewBeads: { Part } = {}
local lowGravForce: VectorForce? = nil
local lowGravAttachment: Attachment? = nil
local darknessFx: ColorCorrectionEffect? = nil
local playerLantern: PointLight? = nil

local actionRemoteCache: RemoteEvent? = nil

local function getActionRemote(): RemoteEvent?
	if actionRemoteCache and actionRemoteCache.Parent then
		return actionRemoteCache
	end
	local folder = Remotes.waitClient().Folder
	local found = folder:WaitForChild("VaultHeistAction", 15)
	if found and found:IsA("RemoteEvent") then
		actionRemoteCache = found
		return found
	end
	return nil
end

local function sendVaultAction(payload: { [string]: any })
	local remote = getActionRemote()
	if remote then
		remote:FireServer(payload)
	end
end

local function rgb(arr: { number }): Color3
	return Color3.fromRGB(arr[1] or 255, arr[2] or 255, arr[3] or 255)
end

local function applyTextConstraint(lbl: TextLabel | TextButton, minSz: number, maxSz: number)
	lbl.TextScaled = true
	local tc = Instance.new("UITextSizeConstraint")
	tc.MinTextSize = minSz
	tc.MaxTextSize = maxSz
	tc.Parent = lbl
end

local function getRootAndHum(): (BasePart?, Humanoid?)
	local char = localPlayer.Character
	if not char then
		return nil, nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	return if hrp and hrp:IsA("BasePart") then hrp else nil, hum
end

local function computeAimDirection(orbId: string): Vector3
	local hrp, hum = getRootAndHum()
	local cam = workspace.CurrentCamera
	if orbId == "DashBomb" and hrp then
		if hum and hum.MoveDirection.Magnitude > 0.1 then
			return Vector3.new(hum.MoveDirection.X, 0, hum.MoveDirection.Z).Unit
		end
		local flat = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
		return if flat.Magnitude > 0.05 then flat.Unit else Vector3.zAxis
	end
	if cam then
		local look = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
		if look.Magnitude > 0.05 then
			return look.Unit
		end
	end
	if hrp then
		local flat = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
		if flat.Magnitude > 0.05 then
			return flat.Unit
		end
	end
	return Vector3.new(0, 0, -1)
end

local function clearArcPreview()
	for _, bead in ipairs(previewBeads) do
		bead:Destroy()
	end
	table.clear(previewBeads)
end

local function updateArcPreview()
	if not previewOrbId or not currentSync.active or previewOrbId == "DashBomb" then
		clearArcPreview()
		return
	end
	local hrp = getRootAndHum()
	if not hrp then
		clearArcPreview()
		return
	end
	local origin = hrp.Position + Vector3.new(0, 1.5, 0)
	local dir = computeAimDirection(previewOrbId)
	local target = origin + dir * 24
	for i = 1, 7 do
		local bead = previewBeads[i]
		if not bead then
			bead = Instance.new("Part")
			bead.Name = "OrbArcBead"
			bead.Shape = Enum.PartType.Ball
			bead.Material = Enum.Material.Neon
			bead.Anchored = true
			bead.CanCollide = false
			bead.CanQuery = false
			bead.Size = Vector3.new(0.7, 0.7, 0.7)
			bead.Parent = workspace
			previewBeads[i] = bead
		end
		local cfg = VaultHeistConfigs.getOrb(previewOrbId)
		bead.Color = if cfg then rgb(cfg.color) else Theme.Colors.Frost
		local t = i / 7
		local pos = origin:Lerp(target, t) + Vector3.new(0, 4 * t * (1 - t) * 4.5, 0)
		bead.CFrame = CFrame.new(pos)
	end
end

local function throwOrbNow(orbId: string)
	local hrp = getRootAndHum()
	if not hrp or not currentSync.active then
		return
	end
	local lv = (currentSync.orbLevels or {})[orbId] or 0
	if lv < 1 then
		VaultHeistController.openVaultOrbModal()
		return
	end
	local dir = computeAimDirection(orbId)
	AudioCatalog.play("Throw", 1.15, 0.3)
	sendVaultAction({
		action = "ThrowOrb",
		orbId = orbId,
		aimDir = dir,
		origin = hrp.Position + Vector3.new(0, 1.5, 0),
	})
end

local function spawnCryoRingVfx(pos: Vector3)
	local ring = Instance.new("Part")
	ring.Name = "CryoBurstRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(125, 249, 255)
	ring.Transparency = 0.25
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Size = Vector3.new(0.5, 4, 4)
	ring.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace
	TweenService
		:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.5, 28, 28),
			Transparency = 1,
		})
		:Play()
	task.delay(0.5, function()
		ring:Destroy()
	end)
end

local function playSyncedEvents(events: any)
	if type(events) ~= "table" then
		return
	end
	for _, ev in ipairs(events) do
		if type(ev) == "table" then
			if ev.kind == "FreezeBurst" and typeof(ev.pos) == "Vector3" then
				spawnCryoRingVfx(ev.pos)
				AudioCatalog.play("BossHit", 1.45, 0.35)
			elseif ev.kind == "DashImpulse" then
				AudioCatalog.playJettDash()
			elseif ev.kind == "EggGrabbed" then
				AudioCatalog.play("GoldCombo", 1.15, 0.4)
			elseif ev.kind == "SoloDroneRevive" then
				AudioCatalog.play("HatchReveal", 1.2, 0.45)
			end
		end
	end
end

local function makeQuickBarRow(bar: Frame): Frame
	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 44)
	row.Parent = bar
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.Padding = UDim.new(0, 6)
	list.Parent = row
	return row
end

local function buildQuickBarLaunchButtons(row: Frame)
	local startBtn = Theme.makeGoldPillButton(
		row,
		"StartVaultBtn",
		"VAULT HEIST",
		UDim2.fromOffset(122, 44),
		UDim2.fromOffset(0, 0),
		VaultHeistController.startVaultRun,
		Theme.Colors.LimeTop,
		Theme.Colors.LimeBot
	)
	applyTextConstraint(startBtn, 10, 14)
	startQuickBtn = startBtn

	local orbsBtn = Theme.makeGoldPillButton(
		row,
		"OrbsModalBtn",
		"ORBS",
		UDim2.fromOffset(78, 44),
		UDim2.fromOffset(0, 0),
		VaultHeistController.openVaultOrbModal,
		Theme.Colors.HubBlueTop,
		Theme.Colors.HubBlueBot
	)
	applyTextConstraint(orbsBtn, 10, 14)
	orbsQuickBtn = orbsBtn
end

local function buildQuickBar(gui: ScreenGui)
	local bar = Instance.new("Frame")
	bar.Name = "VaultQuickBar"
	bar.BackgroundTransparency = 1
	bar.Position = UDim2.fromOffset(12, 8)
	bar.Size = UDim2.fromOffset(230, 66)
	bar.Parent = gui

	local row = makeQuickBarRow(bar)
	buildQuickBarLaunchButtons(row)

	local exBtn = Theme.makeGoldPillButton(
		row,
		"LeaveVaultBtn",
		"EXIT VAULT",
		UDim2.fromOffset(116, 44),
		UDim2.fromOffset(0, 0),
		function()
			sendVaultAction({ action = "Leave" })
		end,
		Theme.Colors.ShopRedTop,
		Theme.Colors.ShopRedBot
	)
	exBtn.Visible = false
	applyTextConstraint(exBtn, 10, 13)
	leaveBtn = exBtn

	local chip = Theme.makeLabel(
		bar,
		"StormChip",
		"VAULT STORM 1.5x LIVE!",
		UDim2.new(1, 0, 0, 18),
		UDim2.fromOffset(4, 46),
		11,
		Theme.Colors.Coins,
		true
	)
	chip.Visible = false
	Theme.addTextStroke(chip, 1.5)
	stormChip = chip
end

local function buildHeaderTrack(frame: Frame)
	local track = Theme.makeFrame(
		frame,
		"BossTrack",
		UDim2.new(1, -20, 0, 22),
		UDim2.fromOffset(10, 44),
		Theme.Colors.Ink,
		999
	)
	track.ClipsDescendants = true
	local fill = Theme.makeFrame(
		track,
		"Fill",
		UDim2.fromScale(1, 1),
		UDim2.fromOffset(0, 0),
		Theme.Colors.ShopRedTop,
		999
	)
	Theme.addGradient(fill, Theme.Colors.ShopRedTop, Theme.Colors.ShopRedBot, 90)
	bossHpFill = fill
	local hpTxt = Theme.makeLabel(
		track,
		"HpText",
		"BOSS [PATROL]",
		UDim2.fromScale(1, 1),
		UDim2.fromOffset(0, 0),
		11,
		Theme.Colors.Text,
		true
	)
	hpTxt.TextXAlignment = Enum.TextXAlignment.Center
	hpTxt.ZIndex = 3
	Theme.addTextStroke(hpTxt, 1.4)
	applyTextConstraint(hpTxt, 8, 12)
	bossHpText = hpTxt
end

local function buildPromptBanner(gui: ScreenGui)
	local prompt = Theme.makeLabel(
		gui,
		"VaultPromptBanner",
		"",
		UDim2.fromOffset(340, 24),
		UDim2.new(0.5, 0, 0, 88),
		12,
		Theme.Colors.Emerald,
		true
	)
	prompt.AnchorPoint = Vector2.new(0.5, 0)
	prompt.TextXAlignment = Enum.TextXAlignment.Center
	prompt.Visible = false
	Theme.addTextStroke(prompt, 1.6)
	applyTextConstraint(prompt, 9, 13)
	promptBanner = prompt
end

local function buildRunHeader(gui: ScreenGui)
	local frame = Theme.makeFrame(
		gui,
		"VaultRunHeader",
		UDim2.fromOffset(340, 76),
		UDim2.new(0.5, 0, 0, 8),
		Theme.Colors.Panel,
		12
	)
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.BackgroundTransparency = 0.08
	frame.Visible = false
	Theme.addStroke(frame, Theme.Colors.Ink, 3)
	runHeader = frame

	local title = Theme.makeLabel(
		frame,
		"Title",
		"CH.1 BRONZE VAULT • 1:15",
		UDim2.new(1, -16, 0, 20),
		UDim2.fromOffset(8, 4),
		13,
		Theme.Colors.Coins,
		true
	)
	title.TextXAlignment = Enum.TextXAlignment.Center
	Theme.addTextStroke(title, 1.5)
	applyTextConstraint(title, 9, 14)
	headerTitleLbl = title

	local sub = Theme.makeLabel(
		frame,
		"Sub",
		"Mutator: Low Gravity • Bag: 0 • 1.0x",
		UDim2.new(1, -16, 0, 16),
		UDim2.fromOffset(8, 24),
		11,
		Theme.Colors.Text,
		false
	)
	sub.TextXAlignment = Enum.TextXAlignment.Center
	applyTextConstraint(sub, 8, 12)
	headerSubLbl = sub
	buildHeaderTrack(frame)
	buildPromptBanner(gui)
end

local function bindOrbSlotInput(btn: TextButton, orbId: string)
	btn.InputBegan:Connect(function(inp: InputObject)
		if
			inp.UserInputType == Enum.UserInputType.MouseButton1
			or inp.UserInputType == Enum.UserInputType.Touch
		then
			previewOrbId = orbId
			previewStartAt = os.clock()
		end
	end)
	btn.InputEnded:Connect(function(inp: InputObject)
		if
			(
				inp.UserInputType == Enum.UserInputType.MouseButton1
				or inp.UserInputType == Enum.UserInputType.Touch
			) and previewOrbId == orbId
		then
			previewOrbId = nil
			clearArcPreview()
			throwOrbNow(orbId)
		end
	end)
end

local function makeSlotCaption(
	btn: TextButton,
	name: string,
	text: string,
	y: number,
	h: number,
	color: Color3
): TextLabel
	local lbl = Theme.makeLabel(
		btn,
		name,
		text,
		UDim2.new(1, -6, 0, h),
		UDim2.fromOffset(3, y),
		10,
		color,
		true
	)
	lbl.TextXAlignment = Enum.TextXAlignment.Center
	Theme.addTextStroke(lbl, 1.3)
	return lbl
end

local function makeOrbSlotButton(dock: Frame, orbId: string, keyHint: string, order: number)
	local cfg = VaultHeistConfigs.getOrb(orbId) :: VaultHeistConfigs.OrbConfig
	local col = rgb(cfg.color)
	local btn = Theme.makeGoldPillButton(
		dock,
		`Orb_{orbId}`,
		"",
		UDim2.fromOffset(66, 54),
		UDim2.fromOffset(0, 0),
		function() end,
		col,
		col:Lerp(Theme.Colors.Ink, 0.32)
	)
	btn.LayoutOrder = order
	Theme.addCorner(btn, 12)

	local topLbl =
		makeSlotCaption(btn, "Name", `{cfg.shortLabel} [{keyHint}]`, 4, 18, Theme.Colors.Text)
	applyTextConstraint(topLbl, 8, 11)
	orbLvLabels[orbId] = makeSlotCaption(btn, "Lv", "Lv 1", 21, 14, Theme.Colors.Coins)
	orbCdLabels[orbId] = makeSlotCaption(btn, "Cd", "READY", 35, 15, Theme.Colors.Text)
	orbSlotBtns[orbId] = btn
	bindOrbSlotInput(btn, orbId)
end

local function buildOrbDock(gui: ScreenGui)
	local dock = Instance.new("Frame")
	dock.Name = "VaultOrbDock"
	dock.BackgroundTransparency = 1
	dock.AnchorPoint = Vector2.new(0.5, 1)
	dock.Position = UDim2.new(0.5, 0, 1, -172)
	dock.Size = UDim2.fromOffset(300, 56)
	dock.Visible = false
	dock.Parent = gui
	orbDock = dock

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = dock

	makeOrbSlotButton(dock, "Decoy", "1", 1)
	makeOrbSlotButton(dock, "Freeze", "2", 2)
	makeOrbSlotButton(dock, "DashBomb", "3", 3)

	local eggBtn = Theme.makeGoldPillButton(
		dock,
		"EggActionBtn",
		"GRAB [E]",
		UDim2.fromOffset(78, 54),
		UDim2.fromOffset(0, 0),
		function()
			if currentSync.carrierUserId == localPlayer.UserId then
				sendVaultAction({ action = "DropEgg" })
			else
				sendVaultAction({ action = "GrabEgg" })
			end
		end,
		Theme.Colors.GoldTop,
		Theme.Colors.GoldBot
	)
	eggBtn.LayoutOrder = 4
	Theme.addCorner(eggBtn, 12)
	applyTextConstraint(eggBtn, 9, 13)
	eggActionBtn = eggBtn
end

local function formatOrbStatNote(orbId: string, stats: VaultHeistConfigs.OrbStats): string
	if orbId == "Decoy" then
		return string.format(
			"%.1fs Lure | %d-stud Radius | %.1fs CD",
			stats.duration,
			stats.radius,
			stats.cooldown
		)
	elseif orbId == "Freeze" then
		return string.format(
			"%.1fs Stun | 4.0s Laser Pause | %.1fs CD",
			stats.duration,
			stats.cooldown
		)
	end
	return string.format(
		"+%d Dash | %.1fs Slow Immune | %.1fs CD",
		stats.dashImpulse,
		stats.carrySlowImmunitySec,
		stats.cooldown
	)
end

local function addOrbUpgradeButton(card: Frame, orbId: string, lv: number, cost: number?)
	local btnLabel = if cost == nil
		then "MAXED"
		elseif lv == 0 then `UNLOCK ({MathUtil.formatNumber(cost)}C)`
		else `UPGRADE ({MathUtil.formatNumber(cost)}C)`
	local actionBtn = Theme.makeGoldPillButton(
		card,
		"UpgradeBtn",
		btnLabel,
		UDim2.fromOffset(128, 46),
		UDim2.new(1, -128, 0.5, -23),
		function()
			if cost ~= nil then
				sendVaultAction({ action = "UpgradeOrb", orbId = orbId })
			end
		end,
		if cost then Theme.Colors.LimeTop else Color3.fromRGB(142, 154, 178),
		if cost then Theme.Colors.LimeBot else Color3.fromRGB(104, 116, 140)
	)
	applyTextConstraint(actionBtn, 9, 13)
end

local function createOrbCardBase(scroll: ScrollingFrame, orbId: string, order: number): Frame
	local card = Theme.makeFrame(
		scroll,
		`Card_{orbId}`,
		UDim2.new(1, 0, 0, 94),
		UDim2.fromOffset(0, 0),
		Color3.new(1, 1, 1),
		12
	)
	card.BackgroundTransparency = 0
	card.LayoutOrder = order
	Theme.addStroke(card, Theme.Colors.Ink, 2.5)
	Theme.addPadding(card, 10, 8)
	return card
end

local function renderOrbModalCard(scroll: ScrollingFrame, orbId: string, order: number)
	local cfg = VaultHeistConfigs.getOrb(orbId) :: VaultHeistConfigs.OrbConfig
	local lv = (currentSync.orbLevels or {})[orbId] or cfg.defaultLevel
	local cost = VaultHeistConfigs.getOrbUpgradeCost(orbId, lv)
	local stats =
		VaultHeistConfigs.getOrbStats(orbId, math.max(1, lv)) :: VaultHeistConfigs.OrbStats
	local card = createOrbCardBase(scroll, orbId, order)

	local titleTxt = if lv == 0
		then `{cfg.displayName} (LOCKED)`
		else `{cfg.displayName} • Lv {lv}/{cfg.maxLevel}`
	local titleLbl = Theme.makeLabel(
		card,
		"Title",
		titleTxt,
		UDim2.new(1, -138, 0, 22),
		UDim2.fromOffset(0, 0),
		15,
		Theme.Colors.TextDark,
		true
	)
	applyTextConstraint(titleLbl, 10, 15)

	local statNote = formatOrbStatNote(orbId, stats)
	local descLbl = Theme.makeLabel(
		card,
		"Desc",
		`{cfg.description}\n{statNote}`,
		UDim2.new(1, -138, 0, 52),
		UDim2.fromOffset(0, 22),
		11,
		Theme.Colors.TextMutedDark,
		false
	)
	descLbl.TextWrapped = true
	applyTextConstraint(descLbl, 9, 12)
	addOrbUpgradeButton(card, orbId, lv, cost)
end

local function refreshOrbModal()
	if not orbScroll or not orbModal or not orbModal.Visible then
		return
	end
	for _, ch in ipairs(orbScroll:GetChildren()) do
		if not ch:IsA("UIListLayout") and not ch:IsA("UIPadding") then
			ch:Destroy()
		end
	end
	for i, orbId in ipairs(VaultHeistConfigs.ORDERED_ORBS) do
		renderOrbModalCard(orbScroll, orbId, i)
	end
end

local function createOrbModalScroll(win: Frame): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.Position = UDim2.fromOffset(10, 58)
	scroll.Size = UDim2.new(1, -20, 1, -118)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.ScrollBarThickness = 6
	scroll.Parent = win
	Theme.addPadding(scroll, 4, 4)
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = scroll
	return scroll
end

local function buildOrbModal(gui: ScreenGui)
	local win = Theme.makeCartoonWindow(
		gui,
		"VaultOrbModal",
		UDim2.fromScale(0.9, 0.68),
		UDim2.fromScale(0.5, 0.5),
		16
	)
	win.AnchorPoint = Vector2.new(0.5, 0.5)
	win.Visible = false
	local sc = Instance.new("UISizeConstraint")
	sc.MaxSize = Vector2.new(520, 440)
	sc.MinSize = Vector2.new(290, 320)
	sc.Parent = win
	orbModal = win

	local _, head = Theme.makeHeaderBanner(
		win,
		"UTILITY ORB ARMORY (COINS ONLY)",
		Theme.Colors.HubBlueTop,
		Theme.Colors.HubBlueBot,
		VaultHeistController.closeVaultOrbModal
	)
	applyTextConstraint(head, 13, 21)
	orbScroll = createOrbModalScroll(win)

	local launchBtn = Theme.makeGoldPillButton(
		win,
		"EnterVaultBtn",
		"ENTER VAULT HEIST (0s WAIT)",
		UDim2.new(1, -24, 0, 46),
		UDim2.new(0, 12, 1, -54),
		function()
			VaultHeistController.closeVaultOrbModal()
			VaultHeistController.startVaultRun()
		end,
		Theme.Colors.GoldTop,
		Theme.Colors.GoldBot
	)
	applyTextConstraint(launchBtn, 11, 16)
end

local function addVoteChoiceButton(
	row: Frame,
	name: string,
	text: string,
	actionName: string,
	topCol: Color3,
	botCol: Color3
): TextButton
	local btn = Theme.makeGoldPillButton(
		row,
		name,
		text,
		UDim2.fromScale(0.48, 1),
		UDim2.fromOffset(0, 0),
		function()
			sendVaultAction({ action = actionName })
		end,
		topCol,
		botCol
	)
	applyTextConstraint(btn, 10, 14)
	local flex = Instance.new("UIFlexItem")
	flex.FlexMode = Enum.UIFlexMode.Fill
	flex.Parent = btn
	return btn
end

local function buildVoteButtonsRow(win: Frame)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Position = UDim2.new(0, 12, 1, -58)
	row.Size = UDim2.new(1, -24, 0, 48)
	row.Parent = win
	local rl = Instance.new("UIListLayout")
	rl.FillDirection = Enum.FillDirection.Horizontal
	rl.Padding = UDim.new(0, 10)
	rl.Parent = row

	addVoteChoiceButton(
		row,
		"ExtractNowBtn",
		"EXTRACT NOW (100%)",
		"VoteExtract",
		Theme.Colors.LimeTop,
		Theme.Colors.LimeBot
	)
	voteDiveBtn = addVoteChoiceButton(
		row,
		"DiveDeeperBtn",
		"DIVE DEEPER!",
		"VoteDive",
		Theme.Colors.GoldTop,
		Theme.Colors.GoldBot
	)
end

local function buildVoteModal(gui: ScreenGui)
	local win = Theme.makeCartoonWindow(
		gui,
		"VaultVoteModal",
		UDim2.fromScale(0.88, 0.44),
		UDim2.fromScale(0.5, 0.46),
		16
	)
	win.AnchorPoint = Vector2.new(0.5, 0.5)
	win.Visible = false
	local sc = Instance.new("UISizeConstraint")
	sc.MaxSize = Vector2.new(430, 230)
	sc.MinSize = Vector2.new(280, 190)
	sc.Parent = win
	voteModal = win

	local _, head = Theme.makeHeaderBanner(
		win,
		"EXTRACTION PAD REACHED!",
		Theme.Colors.LimeTop,
		Theme.Colors.LimeBot,
		function() end
	)
	applyTextConstraint(head, 14, 21)
	voteTitleLbl = head

	local desc = Theme.makeLabel(
		win,
		"Desc",
		"",
		UDim2.new(1, -24, 1, -124),
		UDim2.fromOffset(12, 58),
		13,
		Theme.Colors.TextDark,
		true
	)
	desc.TextWrapped = true
	desc.TextXAlignment = Enum.TextXAlignment.Center
	applyTextConstraint(desc, 10, 14)
	voteDescLbl = desc
	buildVoteButtonsRow(win)
end

local function syncLowGravityForce(active: boolean, gravityScale: number, hrp: BasePart?)
	local wantLowGrav = active and gravityScale < 0.99 and hrp ~= nil
	if wantLowGrav and hrp then
		if not lowGravAttachment or lowGravAttachment.Parent ~= hrp then
			if lowGravAttachment then
				lowGravAttachment:Destroy()
			end
			local att = Instance.new("Attachment")
			att.Name = "VaultLowGravAtt"
			att.Parent = hrp
			lowGravAttachment = att
			if lowGravForce then
				lowGravForce:Destroy()
			end
			local vf = Instance.new("VectorForce")
			vf.Name = "VaultLowGravForce"
			vf.Attachment0 = att
			vf.RelativeTo = Enum.ActuatorRelativeTo.World
			vf.Parent = hrp
			lowGravForce = vf
		end
		if lowGravForce then
			lowGravForce.Force =
				Vector3.new(0, hrp.AssemblyMass * workspace.Gravity * (1 - gravityScale), 0)
		end
	elseif lowGravForce then
		lowGravForce:Destroy()
		lowGravForce = nil
		if lowGravAttachment then
			lowGravAttachment:Destroy()
			lowGravAttachment = nil
		end
	end
end

local function syncDarknessEffect(active: boolean, mutatorId: string, hrp: BasePart?)
	if active and mutatorId == "Darkness" then
		if not darknessFx then
			local fx = Instance.new("ColorCorrectionEffect")
			fx.Name = "VaultDarknessFX"
			fx.Brightness = -0.22
			fx.Contrast = 0.16
			fx.Saturation = -0.15
			fx.TintColor = Color3.fromRGB(190, 200, 235)
			fx.Parent = Lighting
			darknessFx = fx
		end
		if hrp and (not playerLantern or playerLantern.Parent ~= hrp) then
			if playerLantern then
				playerLantern:Destroy()
			end
			local pt = Instance.new("PointLight")
			pt.Name = "VaultLantern"
			pt.Range = 22
			pt.Brightness = 1.4
			pt.Color = Color3.fromRGB(220, 235, 255)
			pt.Parent = hrp
			playerLantern = pt
		end
	else
		if darknessFx then
			darknessFx:Destroy()
			darknessFx = nil
		end
		if playerLantern then
			playerLantern:Destroy()
			playerLantern = nil
		end
	end
end

local function syncMutatorEnvironment(active: boolean, mutatorId: string)
	local hrp = getRootAndHum()
	local mut = VaultHeistConfigs.getMutator(mutatorId)
	syncLowGravityForce(active, mut.gravityScale, hrp)
	syncDarknessEffect(active, mutatorId, hrp)
end

local function refreshRunHeaderAndPrompt(elapsed: number)
	local ch = VaultHeistConfigs.getChamber(currentSync.chamber or 1)
	local mut = VaultHeistConfigs.getMutator(tostring(currentSync.mutatorId or "LowGravity"))
	local timeLeft = math.max(0, (tonumber(currentSync.timeLeft) or 0) - elapsed)
	if headerTitleLbl then
		headerTitleLbl.Text =
			`CH.{ch.chamber} {string.upper(ch.displayName)} • {MathUtil.formatClock(timeLeft)}`
	end
	if headerSubLbl then
		local drone = if (currentSync.soloReviveLeft or 0) > 0 then " • Drone:1" else ""
		headerSubLbl.Text =
			`{mut.displayName} • Bag:{currentSync.vaultBankCount or 0} • {string.format(
				"%.1fx",
				currentSync.streakMult or 1
			)}{drone}`
	end
	if bossHpFill and bossHpText then
		local frac =
			math.clamp((currentSync.bossHP or 0) / math.max(1, currentSync.bossMaxHP or 1), 0, 1)
		bossHpFill.Size = UDim2.fromScale(frac, 1)
		bossHpText.Text = `{ch.bossName} [{currentSync.bossState or "PATROL"}]`
	end
	if promptBanner then
		if currentSync.downed then
			promptBanner.Text = "DOWNED! Wait for teammate revive!"
			promptBanner.TextColor3 = Theme.Colors.Danger
		elseif currentSync.carrierUserId == localPlayer.UserId then
			promptBanner.Text = "CARRYING HEAVY EGG! Sprint to GREEN Extraction Pad!"
			promptBanner.TextColor3 = Theme.Colors.Coins
		elseif currentSync.laserPaused then
			promptBanner.Text = "LASER GATE FROZEN! Push through now!"
			promptBanner.TextColor3 = Theme.Colors.Frost
		else
			promptBanner.Text = "Lure Boss with Decoy [1] & Snatch Egg [E]!"
			promptBanner.TextColor3 = Theme.Colors.Emerald
		end
	end
end

local function refreshOrbDockAndVote(active: boolean, elapsed: number)
	if active then
		for _, orbId in ipairs(VaultHeistConfigs.ORDERED_ORBS) do
			local lv = (currentSync.orbLevels or {})[orbId] or 0
			local remCd = math.max(0, ((currentSync.orbCooldowns or {})[orbId] or 0) - elapsed)
			if orbLvLabels[orbId] then
				orbLvLabels[orbId].Text = if lv == 0 then "LOCKED" else `Lv {lv}`
			end
			if orbCdLabels[orbId] then
				orbCdLabels[orbId].Text = if lv == 0
					then "COINS"
					elseif remCd > 0.1 then string.format("%.1fs", remCd)
					else "READY"
			end
		end
		if eggActionBtn then
			eggActionBtn.Text = if currentSync.carrierUserId == localPlayer.UserId
				then "DROP [R]"
				else "GRAB [E]"
		end
	end
	if voteModal and voteDescLbl and voteDiveBtn and voteTitleLbl then
		local voteOn = active and currentSync.voteActive == true
		voteModal.Visible = voteOn
		if voteOn then
			local vLeft = math.max(0, (tonumber(currentSync.voteEndsAt) or 0) - elapsed)
			voteTitleLbl.Text = string.format("EXTRACTION VOTE (%.0fs)", vLeft)
			voteDiveBtn.Visible = (currentSync.chamber or 1) < VaultHeistConfigs.MAX_CHAMBER
			voteDescLbl.Text = string.format(
				"Stash: %d Egg(s) at %.1fx Multiplier!\nExtract keeps 100%%. Dive risks run eggs on wipe!",
				currentSync.vaultBankCount or 1,
				currentSync.streakMult or 1
			)
		end
	end
end

local function refreshHudVisuals()
	local active = currentSync.active == true
	local elapsed = math.max(0, os.clock() - syncReceivedAt)
	if startQuickBtn and orbsQuickBtn and leaveBtn and stormChip then
		startQuickBtn.Visible = not active
		orbsQuickBtn.Visible = not active
		leaveBtn.Visible = active
		stormChip.Visible = not active and currentSync.isHourlyStorm == true
	end
	if runHeader then
		runHeader.Visible = active
	end
	if orbDock then
		orbDock.Visible = active
	end
	if promptBanner then
		promptBanner.Visible = active
	end
	if active then
		refreshRunHeaderAndPrompt(elapsed)
	end
	refreshOrbDockAndVote(active, elapsed)
	refreshOrbModal()
end

local quickBarExternalHidden = false
local syncListener: (({ [string]: any }) -> ())? = nil

local function applyResponsiveLayout()
	local m = Theme.getLayoutMetrics()
	local compact = m.isCompact
	local narrowLandscape = compact and not m.isPortrait and m.viewport.X < 840
	if runHeader then
		local w = if compact then math.min(280, m.viewport.X - 180) else 340
		runHeader.Size = UDim2.fromOffset(math.max(200, w), 76)
		runHeader.Position = UDim2.new(0.5, 0, 0, if narrowLandscape then 56 else 8)
	end
	if promptBanner then
		promptBanner.Position = UDim2.new(0.5, 0, 0, if narrowLandscape then 134 else 88)
	end
	if orbDock then
		local yOff = if m.isPortrait then -246 elseif compact then -198 else -176
		orbDock.Position = UDim2.new(0.5, 0, 1, yOff)
	end
end

function VaultHeistController.setQuickBarVisible(visible: boolean)
	quickBarExternalHidden = not visible
	if startQuickBtn and startQuickBtn.Parent and startQuickBtn.Parent.Parent then
		local bar = startQuickBtn.Parent.Parent
		if bar:IsA("GuiObject") then
			bar.Visible = visible
		end
	end
end

function VaultHeistController.onSyncChanged(cb: ({ [string]: any }) -> ())
	syncListener = cb
	cb(currentSync)
end

function VaultHeistController.isRunActive(): boolean
	return currentSync.active == true
end

function VaultHeistController.leaveVaultRun()
	sendVaultAction({ action = "Leave" })
end

function VaultHeistController.openVaultOrbModal()
	if orbModal then
		orbModal.Visible = true
		refreshOrbModal()
	end
end

function VaultHeistController.closeVaultOrbModal()
	if orbModal then
		orbModal.Visible = false
	end
end

function VaultHeistController.startVaultRun()
	sendVaultAction({ action = "Start" })
end

local function bindSyncAndInputs()
	task.spawn(function()
		local folder = Remotes.waitClient().Folder
		local syncRemote = folder:WaitForChild("VaultHeistSync", 15)
		if syncRemote and syncRemote:IsA("RemoteEvent") then
			syncRemote.OnClientEvent:Connect(function(payload: any)
				if type(payload) ~= "table" then
					return
				end
				currentSync = payload
				syncReceivedAt = os.clock()
				playSyncedEvents(payload.events)
				refreshHudVisuals()
				if syncListener then
					syncListener(currentSync)
				end
			end)
		end
	end)
	UserInputService.InputBegan:Connect(function(inp: InputObject, gp: boolean)
		if gp or not currentSync.active then
			return
		end
		if inp.KeyCode == Enum.KeyCode.One then
			throwOrbNow("Decoy")
		elseif inp.KeyCode == Enum.KeyCode.Two then
			throwOrbNow("Freeze")
		elseif inp.KeyCode == Enum.KeyCode.Three then
			throwOrbNow("DashBomb")
		elseif inp.KeyCode == Enum.KeyCode.E then
			sendVaultAction({ action = "GrabEgg" })
		elseif inp.KeyCode == Enum.KeyCode.R then
			sendVaultAction({ action = "DropEgg" })
		end
	end)
end

local function bindPhysicsLoop()
	RunService.PreSimulation:Connect(function()
		if localPlayer:GetAttribute("Zone") ~= "VaultHeist" then
			return
		end
		local _, hum = getRootAndHum()
		if not hum then
			return
		end
		if localPlayer:GetAttribute("VaultDowned") == true then
			hum.WalkSpeed = 0
			return
		end
		local slow = tonumber(localPlayer:GetAttribute("VaultCarrySlow")) or 0
		local isImmune = localPlayer:GetAttribute("VaultCarrySlowImmune") == true
			or currentSync.carrySlowImmune == true
		if slow > 0 and not isImmune then
			hum.WalkSpeed = hum.WalkSpeed * (1 - slow)
		end
	end)
	RunService.Heartbeat:Connect(function()
		if currentSync.active then
			refreshHudVisuals()
			if previewOrbId and (os.clock() - previewStartAt) >= 0.16 then
				updateArcPreview()
			end
		else
			clearArcPreview()
		end
		syncMutatorEnvironment(
			currentSync.active == true and localPlayer:GetAttribute("Zone") == "VaultHeist",
			tostring(currentSync.mutatorId or "LowGravity")
		)
	end)
end

function VaultHeistController.start()
	local gui = Theme.createScreenGui("BallBrawl_VaultHeist", 16)
	buildQuickBar(gui)
	if quickBarExternalHidden then
		VaultHeistController.setQuickBarVisible(false)
	end
	buildRunHeader(gui)
	buildOrbDock(gui)
	buildOrbModal(gui)
	buildVoteModal(gui)
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(applyResponsiveLayout)
	end
	applyResponsiveLayout()
	localPlayer:GetAttributeChangedSignal("Coins"):Connect(refreshOrbModal)
	bindSyncAndInputs()
	bindPhysicsLoop()
end

return VaultHeistController
