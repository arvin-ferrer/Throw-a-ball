--!strict
--[[
	ArenaHUDController.luau
	Top Zone Shield Banner + attached 5-Min Overcharged crimson pill, Boss HP bar,
	dynamic biome lighting, responsive 15s Boss Opt-In Modal, 5.0s Egg Claim hold bar,
	and Toast notification banner.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BiomeConfigs = require(Shared.Configs.BiomeConfigs)
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

local function applyBiomeLighting(zone: string, biomeId: string, overchargedActive: boolean)
	if overchargedActive then
		Lighting.Ambient = Color3.fromRGB(110, 62, 145)
		Lighting.OutdoorAmbient = Color3.fromRGB(145, 72, 180)
		Lighting.ClockTime = 20.5
		return
	end
	local biome = BiomeConfigs.getBiome(biomeId)
	if zone ~= "Hub" and biome then
		local a = biome.ambientColor
		Lighting.Ambient = Color3.fromRGB(a[1], a[2], a[3])
		Lighting.OutdoorAmbient = Color3.fromRGB(
			math.min(255, a[1] + 24),
			math.min(255, a[2] + 24),
			math.min(255, a[3] + 24)
		)
		Lighting.ClockTime = if biomeId == "MoltenCaldera"
			then 18.2
			elseif biomeId == "FrostbiteCavern" then 11.5
			else 14.0
	else
		Lighting.Ambient = Color3.fromRGB(115, 130, 152)
		Lighting.OutdoorAmbient = Color3.fromRGB(142, 156, 178)
		Lighting.ClockTime = 13.5
	end
end

local function buildTopBanner(gui: ScreenGui)
	local stack = Instance.new("Frame")
	stack.Name = "TopCenterStack"
	stack.BackgroundTransparency = 1
	stack.AnchorPoint = Vector2.new(0.5, 0)
	stack.Position = UDim2.new(0.5, 0, 0, 6)
	stack.Size = UDim2.fromOffset(396, 86)
	stack.Parent = gui
	topStack = stack

	-- Attached crimson-magenta Overcharged Boss sub-pill tucked underneath the main banner
	local ovPill = Theme.makeFrame(
		stack,
		"OverchargedPill",
		UDim2.fromOffset(348, 26),
		UDim2.new(0.5, 0, 0, 50),
		Color3.fromRGB(255, 255, 255),
		10
	)
	ovPill.AnchorPoint = Vector2.new(0.5, 0)
	ovPill.ZIndex = 1
	Theme.addGradient(ovPill, Theme.Colors.OverchargedBgTop, Theme.Colors.OverchargedBgBot, 90)
	Theme.addStroke(ovPill, Theme.Colors.OverchargedStroke, 1.5, 0.1)
	overchargedPill = ovPill

	local ovLbl = Theme.makeLabel(
		ovPill,
		"Overcharged",
		'⚡ 5-MIN OVERCHARGED BOSS EVENT <font color="#FFFFFF">5:00</font>',
		UDim2.new(1, -14, 1, 0),
		UDim2.fromOffset(7, 1),
		11,
		Color3.fromRGB(255, 150, 198),
		true
	)
	ovLbl.RichText = true
	ovLbl.TextXAlignment = Enum.TextXAlignment.Center
	ovLbl.TextScaled = true
	local ovTc = Instance.new("UITextSizeConstraint")
	ovTc.MaxTextSize = 12
	ovTc.MinTextSize = 8
	ovTc.Parent = ovLbl
	overchargedChip = ovLbl

	-- Main Zone Status Banner card (layered above Overcharged pill)
	local banner = Theme.makeGlossyPanel(
		stack,
		"PhaseBanner",
		UDim2.fromOffset(396, 54),
		UDim2.fromScale(0.5, 0),
		16
	)
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.ZIndex = 2
	bannerFrame = banner

	local sh = HudIcons.createShieldIcon(banner, 30, Theme.Colors.Emerald)
	sh.AnchorPoint = Vector2.new(0, 0.5)
	sh.Position = UDim2.new(0, 14, 0.5, 0)
	sh.ZIndex = 3
	shieldIcon = sh

	local title = Theme.makeLabel(
		banner,
		"PhaseTitle",
		"HUB PLAZA • PvE SAFE",
		UDim2.new(1, -60, 0, 24),
		UDim2.fromOffset(50, 6),
		17,
		Theme.Colors.Emerald,
		true
	)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextScaled = true
	title.ZIndex = 3
	local tTc = Instance.new("UITextSizeConstraint")
	tTc.MaxTextSize = 17
	tTc.MinTextSize = 11
	tTc.Parent = title
	phaseTitle = title

	local sub = Theme.makeLabel(
		banner,
		"PhaseSubtitle",
		"(Walk through Portals to Fight!)",
		UDim2.new(1, -60, 0, 18),
		UDim2.fromOffset(50, 30),
		12,
		Color3.fromRGB(218, 226, 240),
		false
	)
	sub.TextXAlignment = Enum.TextXAlignment.Center
	sub.TextScaled = true
	sub.ZIndex = 3
	local sTc = Instance.new("UITextSizeConstraint")
	sTc.MaxTextSize = 12
	sTc.MinTextSize = 9
	sTc.Parent = sub
	phaseSubtitle = sub

	-- Boss HP Bar
	bossBarFrame = Theme.makeGlossyPanel(
		gui,
		"BossHPBar",
		UDim2.fromOffset(370, 30),
		UDim2.new(0.5, 0, 0, 90),
		10
	)
	if bossBarFrame then
		bossBarFrame.AnchorPoint = Vector2.new(0.5, 0)
		bossBarFrame.ClipsDescendants = true
		bossBarFrame.Visible = false
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.fromScale(1, 1)
		fill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		fill.BorderSizePixel = 0
		fill.Parent = bossBarFrame
		Theme.addCorner(fill, 9)
		Theme.addGradient(fill, Color3.fromRGB(255, 92, 82), Color3.fromRGB(196, 32, 42), 90)
		bossBarFill = fill
		bossBarText = Theme.makeLabel(
			bossBarFrame,
			"Label",
			"BOSS HP",
			UDim2.fromScale(1, 1),
			UDim2.fromOffset(0, 0),
			14,
			Theme.Colors.Text,
			true
		)
		if bossBarText then
			bossBarText.TextXAlignment = Enum.TextXAlignment.Center
			bossBarText.ZIndex = 3
		end
	end
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

local function buildClaimBar(gui: ScreenGui)
	local frame = Theme.makeGlossyPanel(
		gui,
		"EggClaimPanel",
		UDim2.fromOffset(320, 88),
		UDim2.fromScale(0.5, 0.70),
		14
	)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Visible = false
	Theme.addStroke(frame, Theme.Colors.Coins, 2)
	claimFrame = frame

	claimLabel = Theme.makeLabel(
		frame,
		"Title",
		"HOLD [E] OR BUTTON TO CLAIM BOSS EGG (5.0s)",
		UDim2.new(1, -16, 0, 22),
		UDim2.fromOffset(8, 6),
		12,
		Theme.Colors.Coins,
		true
	)
	if claimLabel then
		claimLabel.TextXAlignment = Enum.TextXAlignment.Center
	end

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

	local holdBtn = Theme.makeButton(
		frame,
		"HoldClaimBtn",
		"HOLD TO CLAIM EGG",
		UDim2.new(1, -24, 0, 32),
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
	holdBtn.InputEnded:Connect(function()
		if isHoldingClaim then
			isHoldingClaim = false
			Remotes.waitClient().ClaimEggAction:FireServer("Cancel")
		end
	end)
end

local function buildToast(gui: ScreenGui)
	local f = Theme.makeGlossyPanel(
		gui,
		"ToastBanner",
		UDim2.fromOffset(440, 36),
		UDim2.new(0.5, 0, 0, 92),
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
	lbl.TextScaled = true
	local tc = Instance.new("UITextSizeConstraint")
	tc.MaxTextSize = 14
	tc.MinTextSize = 9
	tc.Parent = lbl
	toastLabel = lbl
end

local function applyArenaResponsive()
	local m = Theme.getLayoutMetrics()
	local compact = m.isCompact
	if topStack and bannerFrame and overchargedPill and shieldIcon then
		local bw = if m.isPortrait
			then math.clamp(m.viewport.X - 24, 240, 344)
			elseif compact then math.max(224, math.min(316, m.viewport.X - 230))
			else 376
		local bh = if compact then 44 else 54
		local oh = if compact then 22 else 26
		local topY = if m.isPortrait then 70 elseif compact then 4 else 6
		topStack.Position = UDim2.new(0.5, 0, 0, topY)
		topStack.Size = UDim2.fromOffset(bw, bh + oh + 4)
		bannerFrame.Size = UDim2.fromOffset(bw, bh)
		overchargedPill.Size = UDim2.fromOffset(bw - 34, oh)
		overchargedPill.Position = UDim2.new(0.5, 0, 0, bh - 3)
		local shS = if compact then 24 else 30
		shieldIcon.Size = UDim2.fromOffset(shS, shS)
		shieldIcon.Position = UDim2.new(0, if compact then 12 else 18, 0.5, 0)
		if phaseTitle then
			phaseTitle.Position =
				UDim2.fromOffset(if compact then 42 else 54, if compact then 4 else 6)
			phaseTitle.Size =
				UDim2.new(1, if compact then -52 else -68, 0, if compact then 20 else 24)
		end
		if phaseSubtitle then
			phaseSubtitle.Position =
				UDim2.fromOffset(if compact then 42 else 54, if compact then 24 else 30)
			phaseSubtitle.Size =
				UDim2.new(1, if compact then -52 else -68, 0, if compact then 15 else 18)
		end
	end
	if bossBarFrame then
		local barY = if m.isPortrait then 142 elseif compact then 72 else 90
		bossBarFrame.Size =
			UDim2.fromOffset(if compact then 290 else 370, if compact then 26 else 30)
		bossBarFrame.Position = UDim2.new(0.5, 0, 0, barY)
	end
	if toastFrame then
		local toastY = if m.isPortrait then 144 elseif compact then 74 else 92
		toastFrame.Size =
			UDim2.fromOffset(if compact then math.min(340, m.viewport.X - 24) else 440, 34)
		toastFrame.Position = UDim2.new(0.5, 0, 0, toastY)
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

local function onArenaStateSync(snapshot: any)
	if type(snapshot) ~= "table" then
		return
	end
	local zone = tostring(localPlayer:GetAttribute("Zone") or "Hub")
	local activeBiome = tostring(localPlayer:GetAttribute("ActiveBiome") or "")
	local overLeft = tonumber(snapshot.overchargedRemaining) or 300
	if overchargedChip then
		overchargedChip.Text =
			`⚡ 5-MIN OVERCHARGED BOSS EVENT <font color="#FFFFFF">{MathUtil.formatClock(overLeft)}</font>`
	end

	local biomes = snapshot.biomes or {}
	local st = if activeBiome ~= "" then biomes[activeBiome] else nil
	local anyOvercharged = false
	for _, b in pairs(biomes) do
		if b.isOvercharged and (b.phase == "OptIn_Window" or b.phase == "Boss_Phase") then
			anyOvercharged = true
		end
	end
	applyBiomeLighting(zone, activeBiome, anyOvercharged)

	if phaseTitle and phaseSubtitle then
		if not st then
			phaseTitle.Text = "HUB PLAZA • PvE SAFE"
			phaseTitle.TextColor3 = Theme.Colors.Emerald
			phaseSubtitle.Text = "(Walk through Portals to Fight!)"
			HudIcons.setShieldColor(shieldIcon, Theme.Colors.Emerald)
		else
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
	end

	-- Boss HP Bar
	if bossBarFrame and bossBarFill and bossBarText then
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

	-- 15-Second Opt-In Modal
	if optInModal and optInInfo then
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

	-- 5.0-Second Egg Claim Bar during PvP_EggScramble
	if claimFrame and claimFill and claimLabel then
		if zone == "LockedBossPvP" and st and st.phase == "PvP_EggScramble" then
			claimFrame.Visible = true
			local prog = math.clamp(tonumber(st.claimProgress) or 0, 0, 1)
			claimFill.Size = UDim2.fromScale(prog, 1)
			if (st.pvpGraceRemaining or 0) > 0.05 then
				claimLabel.Text = string.format(
					"FULL HEALED! PvP & Claim unlock in %.1fs...",
					st.pvpGraceRemaining
				)
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
			local svc = string.sub(msg, 12)
			if serviceModalHandler then
				serviceModalHandler(svc)
			end
			return
		end
		ArenaHUDController.showToast(msg, if type(colorArr) == "table" then colorArr else nil)
	end)

	-- Keyboard E hold-to-claim in PvP_EggScramble
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or input.KeyCode ~= Enum.KeyCode.E then
			return
		end
		if claimFrame and claimFrame.Visible then
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
