--!strict
--[[
	ArenaHUDController.luau
	Top Zone Shield Banner + attached 5-Min Overcharged crimson pill, Boss HP bar,
	dynamic tweened biome lighting, responsive 15s Boss Opt-In Modal, 5.0s Egg Claim hold bar,
	and Toast notification banner.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BiomeConfigs = require(Shared.Configs.BiomeConfigs)
local ArenaCycleLogic = require(Shared.Utils.ArenaCycleLogic)
local MathUtil = require(Shared.Utils.MathUtil)
local AudioCatalog = require(Shared.Utils.AudioCatalog)
local Remotes = require(Shared.Net.Remotes)

local Theme = require(script.Parent.Parent.UI.Theme)
local HudIcons = require(script.Parent.Parent.UI.HudIcons)

local ArenaHUDController = {}

local localPlayer = Players.LocalPlayer
local topStack: Frame? = nil
local bannerFrame: Frame? = nil
local shieldIcon: Frame? = nil
local phaseTitle: TextLabel? = nil
local phaseSubtitle: TextLabel? = nil
local overchargedPill: Frame? = nil
local overchargedChip: TextLabel? = nil
local bossBarFrame: Frame? = nil
local bossBarFill: Frame? = nil
local bossBarText: TextLabel? = nil
local optInModal: Frame? = nil
local optInInfo: TextLabel? = nil
local optInBiomeId = ""
local optedInState = false
local claimFrame: Frame? = nil
local claimFill: Frame? = nil
local claimLabel: TextLabel? = nil
local toastFrame: Frame? = nil
local toastLabel: TextLabel? = nil
local toastExpireAt = 0
local serviceModalHandler: ((string) -> ())? = nil
local isHoldingClaim = false
local activeLightingTween: Tween? = nil
local lastLightingKey = ""

local function applyTextConstraint(lbl: TextLabel, minSize: number, maxSize: number)
	lbl.TextScaled = true
	local tc = Instance.new("UITextSizeConstraint")
	tc.MinTextSize = minSize
	tc.MaxTextSize = maxSize
	tc.Parent = lbl
end

local function applyBiomeLighting(zone: string, biomeId: string, overchargedActive: boolean)
	local target = ArenaCycleLogic.getBiomeLighting(zone, biomeId, overchargedActive)
	if target.key == lastLightingKey then
		return
	end
	lastLightingKey = target.key
	if activeLightingTween then
		activeLightingTween:Cancel()
		activeLightingTween = nil
	end
	local tween = TweenService:Create(
		Lighting,
		TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Ambient = Color3.fromRGB(target.ambient[1], target.ambient[2], target.ambient[3]),
			OutdoorAmbient = Color3.fromRGB(
				target.outdoorAmbient[1],
				target.outdoorAmbient[2],
				target.outdoorAmbient[3]
			),
			ClockTime = target.clockTime,
		}
	)
	activeLightingTween = tween
	tween:Play()
end

local function buildOverchargedPill(stack: Frame)
	local ovPill = Theme.makeFrame(
		stack,
		"OverchargedPill",
		UDim2.fromOffset(216, 20),
		UDim2.new(0.5, 0, 0, 38),
		Color3.fromRGB(255, 255, 255),
		8
	)
	ovPill.AnchorPoint = Vector2.new(0.5, 0)
	ovPill.ZIndex = 1
	Theme.addGradient(ovPill, Theme.Colors.OverchargedBgTop, Theme.Colors.OverchargedBgBot, 90)
	Theme.addStroke(ovPill, Theme.Colors.OverchargedStroke, 1.5, 0.1)
	overchargedPill = ovPill

	local ovLbl = Theme.makeLabel(
		ovPill,
		"Overcharged",
		'⚡ OVERCHARGED EVENT <font color="#FFFFFF">5:00</font>',
		UDim2.new(1, -10, 1, 0),
		UDim2.fromOffset(5, 0),
		10,
		Color3.fromRGB(255, 150, 198),
		true
	)
	ovLbl.RichText = true
	ovLbl.TextXAlignment = Enum.TextXAlignment.Center
	applyTextConstraint(ovLbl, 7, 10)
	overchargedChip = ovLbl
end

local function buildPhaseBanner(stack: Frame)
	local banner = Theme.makeGlossyPanel(
		stack,
		"PhaseBanner",
		UDim2.fromOffset(236, 40),
		UDim2.fromScale(0.5, 0),
		12
	)
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.ZIndex = 2
	bannerFrame = banner

	local sh = HudIcons.createShieldIcon(banner, 22, Theme.Colors.Emerald)
	sh.AnchorPoint = Vector2.new(0, 0.5)
	sh.Position = UDim2.new(0, 10, 0.5, 0)
	sh.ZIndex = 3
	shieldIcon = sh

	local title = Theme.makeLabel(
		banner,
		"PhaseTitle",
		"HUB PLAZA • PvE SAFE",
		UDim2.new(1, -44, 0, 18),
		UDim2.fromOffset(36, 4),
		14,
		Theme.Colors.Emerald,
		true
	)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.ZIndex = 3
	applyTextConstraint(title, 7, 13)
	phaseTitle = title

	local sub = Theme.makeLabel(
		banner,
		"PhaseSubtitle",
		"(Walk through Portals to Fight!)",
		UDim2.new(1, -44, 0, 14),
		UDim2.fromOffset(36, 22),
		10,
		Color3.fromRGB(218, 226, 240),
		false
	)
	sub.TextXAlignment = Enum.TextXAlignment.Center
	sub.ZIndex = 3
	applyTextConstraint(sub, 7, 10)
	phaseSubtitle = sub
end

local function buildBossHpBar(gui: ScreenGui)
	local bar = Theme.makeGlossyPanel(
		gui,
		"BossHPBar",
		UDim2.fromOffset(370, 30),
		UDim2.new(0.5, 0, 0, 90),
		10
	)
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.ClipsDescendants = true
	bar.Visible = false
	bossBarFrame = bar

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	fill.BorderSizePixel = 0
	fill.Parent = bar
	Theme.addCorner(fill, 9)
	Theme.addGradient(fill, Color3.fromRGB(255, 92, 82), Color3.fromRGB(196, 32, 42), 90)
	bossBarFill = fill

	local lbl = Theme.makeLabel(
		bar,
		"Label",
		"BOSS HP",
		UDim2.fromScale(1, 1),
		UDim2.fromOffset(0, 0),
		14,
		Theme.Colors.Text,
		true
	)
	lbl.TextXAlignment = Enum.TextXAlignment.Center
	lbl.ZIndex = 3
	bossBarText = lbl
end

local function buildTopBanner(gui: ScreenGui)
	local stack = Instance.new("Frame")
	stack.Name = "TopCenterStack"
	stack.BackgroundTransparency = 1
	stack.AnchorPoint = Vector2.new(1, 0)
	stack.Position = UDim2.new(1, -14, 0, 6)
	stack.Size = UDim2.fromOffset(236, 58)
	stack.Parent = gui
	topStack = stack
	buildOverchargedPill(stack)
	buildPhaseBanner(stack)
	buildBossHpBar(gui)
end

local function buildOptInButtons(modal: Frame)
	local btnRow = Instance.new("Frame")
	btnRow.Name = "ButtonRow"
	btnRow.BackgroundTransparency = 1
	btnRow.Position = UDim2.new(0, 14, 1, -54)
	btnRow.Size = UDim2.new(1, -28, 0, 44)
	btnRow.Parent = modal
	local rl = Instance.new("UIListLayout")
	rl.FillDirection = Enum.FillDirection.Horizontal
	rl.Padding = UDim.new(0, 10)
	rl.Parent = btnRow

	local joinBtn = Theme.makeButton(
		btnRow,
		"JoinBtn",
		"JOIN BOSS",
		UDim2.fromScale(0.48, 1),
		UDim2.fromOffset(0, 0),
		Theme.Colors.Emerald,
		function()
			optedInState = true
			Remotes.waitClient().OptInBoss:FireServer(optInBiomeId, true)
		end
	)
	local jf = Instance.new("UIFlexItem")
	jf.FlexMode = Enum.UIFlexMode.Fill
	jf.Parent = joinBtn

	local stayBtn = Theme.makeButton(
		btnRow,
		"StayBtn",
		"STAY IN PvE",
		UDim2.fromScale(0.48, 1),
		UDim2.fromOffset(0, 0),
		Theme.Colors.CardAlt,
		function()
			optedInState = false
			Remotes.waitClient().OptInBoss:FireServer(optInBiomeId, false)
		end
	)
	local sf = Instance.new("UIFlexItem")
	sf.FlexMode = Enum.UIFlexMode.Fill
	sf.Parent = stayBtn
end

local function buildOptInModal(gui: ScreenGui)
	local modal = Theme.makeGlossyPanel(
		gui,
		"OptInModal",
		UDim2.fromScale(0.86, 0.46),
		UDim2.fromScale(0.5, 0.42),
		16
	)
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.Visible = false
	Theme.addStroke(modal, Theme.Colors.Coins, 2)
	local sc = Instance.new("UISizeConstraint")
	sc.MaxSize = Vector2.new(390, 192)
	sc.MinSize = Vector2.new(280, 158)
	sc.Parent = modal
	optInModal = modal

	local heading = Theme.makeLabel(
		modal,
		"Heading",
		"BOSS PHASE OPT-IN!",
		UDim2.new(1, -20, 0, 28),
		UDim2.fromOffset(10, 10),
		19,
		Theme.Colors.Coins,
		true
	)
	heading.TextXAlignment = Enum.TextXAlignment.Center

	optInInfo = Theme.makeLabel(
		modal,
		"Info",
		"",
		UDim2.new(1, -24, 1, -104),
		UDim2.fromOffset(12, 40),
		13,
		Theme.Colors.Text,
		false
	)
	if optInInfo then
		optInInfo.TextWrapped = true
		optInInfo.TextXAlignment = Enum.TextXAlignment.Center
	end
	buildOptInButtons(modal)
end

local function buildClaimHoldButton(frame: Frame)
	local holdBtn = Theme.makeButton(
		frame,
		"HoldClaimBtn",
		"HOLD TO CLAIM EGG",
		UDim2.new(1, -24, 0, 44),
		UDim2.fromOffset(12, 50),
		Theme.Colors.Molten,
		function() end
	)
	holdBtn.InputBegan:Connect(function(inp: InputObject)
		if
			inp.UserInputType == Enum.UserInputType.MouseButton1
			or inp.UserInputType == Enum.UserInputType.Touch
		then
			isHoldingClaim = true
			Remotes.waitClient().ClaimEggAction:FireServer("Begin")
		end
	end)
	holdBtn.InputEnded:Connect(function(inp: InputObject)
		if
			isHoldingClaim
			and (
				inp.UserInputType == Enum.UserInputType.MouseButton1
				or inp.UserInputType == Enum.UserInputType.Touch
			)
		then
			isHoldingClaim = false
			Remotes.waitClient().ClaimEggAction:FireServer("Cancel")
		end
	end)
end

local function buildClaimBar(gui: ScreenGui)
	local frame = Theme.makeGlossyPanel(
		gui,
		"EggClaimPanel",
		UDim2.fromOffset(320, 102),
		UDim2.fromScale(0.5, 0.48),
		14
	)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Visible = false
	Theme.addStroke(frame, Theme.Colors.Coins, 2)
	claimFrame = frame

	local lbl = Theme.makeLabel(
		frame,
		"Title",
		"HOLD [E] OR BUTTON TO CLAIM BOSS EGG (5.0s)",
		UDim2.new(1, -16, 0, 22),
		UDim2.fromOffset(8, 6),
		12,
		Theme.Colors.Coins,
		true
	)
	lbl.TextXAlignment = Enum.TextXAlignment.Center
	applyTextConstraint(lbl, 9, 12)
	claimLabel = lbl

	local barBg = Theme.makeFrame(
		frame,
		"BarBg",
		UDim2.new(1, -24, 0, 14),
		UDim2.fromOffset(12, 30),
		Theme.Colors.Card,
		8
	)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Theme.Colors.Emerald
	fill.BorderSizePixel = 0
	fill.Parent = barBg
	Theme.addCorner(fill, 8)
	claimFill = fill

	buildClaimHoldButton(frame)
end

local function buildToast(gui: ScreenGui)
	local f = Theme.makeGlossyPanel(
		gui,
		"ToastBanner",
		UDim2.fromOffset(440, 36),
		UDim2.new(0.5, 0, 0, 124),
		12
	)
	f.AnchorPoint = Vector2.new(0.5, 0)
	f.Visible = false
	toastFrame = f
	local lbl = Theme.makeLabel(
		f,
		"ToastText",
		"",
		UDim2.new(1, -16, 1, 0),
		UDim2.fromOffset(8, 0),
		13,
		Theme.Colors.Text,
		true
	)
	lbl.TextXAlignment = Enum.TextXAlignment.Center
	applyTextConstraint(lbl, 9, 14)
	toastLabel = lbl
end

local function applyTopBannerResponsive(m: Theme.LayoutMetrics)
	if not (topStack and bannerFrame and overchargedPill and shieldIcon) then
		return
	end
	local compact = m.isCompact
	local bw = if compact then 184 else 236
	local bh = if compact then 34 else 40
	local oh = if compact then 17 else 20
	local ow = if compact then 168 else 216
	local topX = if compact then -10 else -14
	local topY = if compact then 4 else 6
	topStack.Position = UDim2.new(1, topX, 0, topY)
	topStack.Size = UDim2.fromOffset(bw, bh + oh - 2)
	bannerFrame.Size = UDim2.fromOffset(bw, bh)
	overchargedPill.Size = UDim2.fromOffset(ow, oh)
	overchargedPill.Position = UDim2.new(0.5, 0, 0, bh - 2)
	local shS = if compact then 18 else 22
	shieldIcon.Size = UDim2.fromOffset(shS, shS)
	shieldIcon.Position = UDim2.new(0, if compact then 8 else 10, 0.5, 0)
	local leftOff = if compact then 30 else 36
	local padW = if compact then -36 else -44
	if phaseTitle then
		phaseTitle.Position = UDim2.fromOffset(leftOff, if compact then 3 else 4)
		phaseTitle.Size = UDim2.new(1, padW, 0, if compact then 15 else 18)
	end
	if phaseSubtitle then
		phaseSubtitle.Position = UDim2.fromOffset(leftOff, if compact then 18 else 22)
		phaseSubtitle.Size = UDim2.new(1, padW, 0, if compact then 12 else 14)
	end
end

local function applyArenaResponsive()
	local m = Theme.getLayoutMetrics()
	local compact = m.isCompact
	applyTopBannerResponsive(m)
	if bossBarFrame then
		local barY = if m.isPortrait then 92 elseif compact then 8 else 10
		local bossW = if m.isPortrait
			then math.clamp(m.viewport.X - 28, 220, 320)
			elseif compact then math.clamp(m.viewport.X - 410, 210, 260)
			else 340
		bossBarFrame.Size = UDim2.fromOffset(bossW, if compact then 24 else 28)
		bossBarFrame.Position = UDim2.new(0.5, 0, 0, barY)
	end
	if toastFrame then
		local toastY = if m.isPortrait then 122 elseif compact then 38 else 46
		local toastW = if m.isPortrait
			then math.min(320, m.viewport.X - 24)
			elseif compact then math.clamp(m.viewport.X - 410, 220, 280)
			else 380
		toastFrame.Size = UDim2.fromOffset(toastW, if compact then 28 else 32)
		toastFrame.Position = UDim2.new(0.5, 0, 0, toastY)
	end
	if claimFrame then
		local cw = math.min(340, math.max(240, m.viewport.X - 24))
		local cy = if m.isPortrait then 0.48 elseif compact then 0.50 else 0.66
		claimFrame.Size = UDim2.fromOffset(cw, 102)
		claimFrame.Position = UDim2.fromScale(0.5, cy)
	end
end

function ArenaHUDController.showToast(message: string, colorArr: { number }?)
	if not toastLabel or not toastFrame then
		return
	end
	toastLabel.Text = message
	if colorArr then
		toastLabel.TextColor3 =
			Color3.fromRGB(colorArr[1] or 255, colorArr[2] or 255, colorArr[3] or 255)
	else
		toastLabel.TextColor3 = Theme.Colors.Text
	end
	toastFrame.Visible = true
	toastExpireAt = os.clock() + 4.0
	task.delay(4.1, function()
		if os.clock() >= toastExpireAt and toastFrame then
			toastFrame.Visible = false
		end
	end)
end

function ArenaHUDController.setServiceModalHandler(handler: (string) -> ())
	serviceModalHandler = handler
end

local function updatePhaseBanner(st: any, activeBiome: string)
	if not phaseTitle or not phaseSubtitle then
		return
	end
	if not st then
		phaseTitle.Text = "HUB PLAZA • PvE SAFE"
		phaseTitle.TextColor3 = Theme.Colors.Emerald
		phaseSubtitle.Text = "(Walk through Portals to Fight!)"
		HudIcons.setShieldColor(shieldIcon, Theme.Colors.Emerald)
		return
	end
	local bCfg = BiomeConfigs.getBiome(activeBiome)
	local bName = string.upper(if bCfg then bCfg.displayName else activeBiome)
	local overTag = if st.isOvercharged then "⚡ OVERCHARGED " else ""
	local clockTxt = MathUtil.formatClock(st.timeRemaining or 0)
	local accent = if st.phase == "PvP_EggScramble"
		then Theme.Colors.Danger
		elseif st.isOvercharged then Theme.Colors.Overcharged
		else Theme.Colors.Coins
	phaseTitle.Text = `{overTag}{bName}`
	phaseTitle.TextColor3 = accent
	HudIcons.setShieldColor(shieldIcon, accent)
	if st.phase == "PvE_Open" then
		phaseSubtitle.Text = `Open PvE Hunting • Next Boss in {clockTxt}`
	elseif st.phase == "OptIn_Window" then
		phaseSubtitle.Text = `Boss Opt-In Open! ({clockTxt})`
	elseif st.phase == "Boss_Phase" then
		phaseSubtitle.Text = `Boss Battle Active! ({clockTxt})`
	else
		phaseSubtitle.Text = `PvP Egg Scramble • Claim the Egg! ({clockTxt})`
	end
end

local function updateBossHpBar(zone: string, st: any)
	if not bossBarFrame or not bossBarFill or not bossBarText then
		return
	end
	if zone == "LockedBossPvP" and st and st.phase == "Boss_Phase" then
		bossBarFrame.Visible = true
		local frac = math.clamp((st.bossHP or 0) / math.max(1, st.bossMaxHP or 1), 0, 1)
		bossBarFill.Size = UDim2.fromScale(frac, 1)
		bossBarText.Text =
			`BOSS HP: {MathUtil.formatNumber(st.bossHP or 0)} / {MathUtil.formatNumber(
				st.bossMaxHP or 1
			)}`
	else
		bossBarFrame.Visible = false
	end
end

local function updateOptInModal(zone: string, activeBiome: string, st: any)
	if not optInModal or not optInInfo then
		return
	end
	if zone == "BiomePvE" and st and st.phase == "OptIn_Window" then
		optInBiomeId = activeBiome
		optInModal.Visible = true
		local statusTxt = if optedInState then "[QUEUED!]" else "[NOT QUEUED]"
		optInInfo.Text = string.format(
			"%s\nTime Left: %ds | Queued Fighters: %d | Top Power: %s\nStatus: %s",
			if st.isOvercharged
				then "⚡ OVERCHARGED BOSS (+40% HP & Exclusive Mutations!)"
				else "Regular Biome Boss (+35% HP/player)",
			math.ceil(st.timeRemaining or 0),
			st.queueCount or 0,
			MathUtil.formatNumber(st.queueMaxPower or 0),
			statusTxt
		)
	else
		optInModal.Visible = false
		optedInState = false
	end
end

local function updateClaimBar(zone: string, st: any)
	if not claimFrame or not claimFill or not claimLabel then
		return
	end
	if zone == "LockedBossPvP" and st and st.phase == "PvP_EggScramble" then
		claimFrame.Visible = true
		local prog = math.clamp(tonumber(st.claimProgress) or 0, 0, 1)
		claimFill.Size = UDim2.fromScale(prog, 1)
		if (st.pvpGraceRemaining or 0) > 0.05 then
			claimLabel.Text =
				string.format("FULL HEALED! PvP & Claim unlock in %.1fs...", st.pvpGraceRemaining)
		elseif st.claimerId == localPlayer.UserId then
			claimLabel.Text =
				string.format("CLAIMING BOSS EGG: %.1fs / 5.0s (Don't get hit!)", prog * 5.0)
			AudioCatalog.play("ClaimTick", 1.0 + prog * 0.5, 0.25)
		elseif st.claimerId ~= nil then
			claimLabel.Text = "A RIVAL IS CLAIMING THE EGG! HIT THEM TO INTERRUPT!"
		else
			claimLabel.Text = "HOLD [E] OR BUTTON NEAR EGG FOR 5.0s TO WIN!"
		end
	else
		claimFrame.Visible = false
		isHoldingClaim = false
	end
end

local function onArenaStateSync(snapshot: any)
	if type(snapshot) ~= "table" then
		return
	end
	local zone = tostring(localPlayer:GetAttribute("Zone") or "Hub")
	local activeBiome = tostring(localPlayer:GetAttribute("ActiveBiome") or "")
	local overLeft = tonumber(snapshot.overchargedRemaining) or 300
	if overchargedChip then
		overchargedChip.Text =
			`⚡ OVERCHARGED EVENT <font color="#FFFFFF">{MathUtil.formatClock(overLeft)}</font>`
	end
	local biomes = snapshot.biomes or {}
	local st = if activeBiome ~= "" then biomes[activeBiome] else nil
	applyBiomeLighting(zone, activeBiome, ArenaCycleLogic.isOverchargedVisualActive(biomes))
	updatePhaseBanner(st, activeBiome)
	updateBossHpBar(zone, st)
	updateOptInModal(zone, activeBiome, st)
	updateClaimBar(zone, st)
end

function ArenaHUDController.start()
	local gui = Theme.createScreenGui("BallBrawl_ArenaHUD", 15)
	buildTopBanner(gui)
	buildOptInModal(gui)
	buildClaimBar(gui)
	buildToast(gui)

	local function hookCamera()
		local cam = workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(applyArenaResponsive)
		end
	end
	hookCamera()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hookCamera)
	applyArenaResponsive()

	local remotes = Remotes.waitClient()
	remotes.ArenaStateSync.OnClientEvent:Connect(onArenaStateSync)
	remotes.ToastNotify.OnClientEvent:Connect(function(msg: any, colorArr: any)
		if type(msg) ~= "string" then
			return
		end
		if string.sub(msg, 1, 11) == "OPEN_MODAL:" then
			if serviceModalHandler then
				serviceModalHandler(string.sub(msg, 12))
			end
			return
		end
		ArenaHUDController.showToast(msg, if type(colorArr) == "table" then colorArr else nil)
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if
			not gameProcessed
			and input.KeyCode == Enum.KeyCode.E
			and claimFrame
			and claimFrame.Visible
		then
			isHoldingClaim = true
			remotes.ClaimEggAction:FireServer("Begin")
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.E and isHoldingClaim then
			isHoldingClaim = false
			remotes.ClaimEggAction:FireServer("Cancel")
		end
	end)
end

return ArenaHUDController
