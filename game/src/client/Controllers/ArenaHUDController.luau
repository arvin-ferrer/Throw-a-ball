--!strict
--[[
	ArenaHUDController.luau
	Top Phase Banner, Boss HP bar, 5-Min Overcharged countdown & dynamic skybox mood,
	15s Boss Opt-In Modal (with Queue Count & Max Power Rating), 5.0s Egg Claim ring/hold button,
	and Toast notification stack.
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

local ArenaHUDController = {}

local localPlayer = Players.LocalPlayer
local phaseTitle: TextLabel? = nil
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
	local banner = Theme.makeFrame(
		gui,
		"PhaseBanner",
		UDim2.fromOffset(456, 56),
		UDim2.new(0.5, -228, 0, 8),
		Theme.Colors.Panel,
		12
	)
	phaseTitle = Theme.makeLabel(
		banner,
		"PhaseTitle",
		"HUB PLAZA • PvE SAFE",
		UDim2.new(1, -16, 0, 24),
		UDim2.fromOffset(8, 4),
		15,
		Theme.Colors.Text,
		true
	)
	if phaseTitle then
		phaseTitle.TextXAlignment = Enum.TextXAlignment.Center
	end
	overchargedChip = Theme.makeLabel(
		banner,
		"Overcharged",
		"⚡ Overcharged Event: 5:00",
		UDim2.new(1, -16, 0, 20),
		UDim2.fromOffset(8, 30),
		13,
		Theme.Colors.Overcharged,
		true
	)
	if overchargedChip then
		overchargedChip.TextXAlignment = Enum.TextXAlignment.Center
	end

	bossBarFrame = Theme.makeFrame(
		gui,
		"BossHPBar",
		UDim2.fromOffset(380, 32),
		UDim2.new(0.5, -190, 0, 70),
		Theme.Colors.Panel,
		10
	)
	if bossBarFrame then
		bossBarFrame.Visible = false
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.fromScale(1, 1)
		fill.BackgroundColor3 = Theme.Colors.Danger
		fill.BorderSizePixel = 0
		fill.Parent = bossBarFrame
		Theme.addCorner(fill, 10)
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
		end
	end
end

local function buildOptInModal(gui: ScreenGui)
	local modal = Theme.makeFrame(
		gui,
		"OptInModal",
		UDim2.fromOffset(380, 186),
		UDim2.new(0.5, -190, 0.25, 0),
		Theme.Colors.Panel,
		14
	)
	modal.Visible = false
	Theme.addStroke(modal, Theme.Colors.Coins, 2)
	optInModal = modal

	local heading = Theme.makeLabel(
		modal,
		"Heading",
		"BOSS PHASE OPT-IN!",
		UDim2.new(1, -20, 0, 30),
		UDim2.fromOffset(10, 10),
		20,
		Theme.Colors.Coins,
		true
	)
	heading.TextXAlignment = Enum.TextXAlignment.Center

	optInInfo = Theme.makeLabel(
		modal,
		"Info",
		"",
		UDim2.new(1, -24, 0, 74),
		UDim2.fromOffset(12, 42),
		14,
		Theme.Colors.Text,
		false
	)
	if optInInfo then
		optInInfo.TextWrapped = true
		optInInfo.TextXAlignment = Enum.TextXAlignment.Center
	end

	Theme.makeButton(
		modal,
		"JoinBtn",
		"JOIN BOSS",
		UDim2.fromOffset(164, 44),
		UDim2.fromOffset(16, 128),
		Theme.Colors.Emerald,
		function()
			optedInState = true
			Remotes.waitClient().OptInBoss:FireServer(optInBiomeId, true)
		end
	)
	Theme.makeButton(
		modal,
		"StayBtn",
		"STAY IN PvE",
		UDim2.fromOffset(164, 44),
		UDim2.fromOffset(200, 128),
		Theme.Colors.CardAlt,
		function()
			optedInState = false
			Remotes.waitClient().OptInBoss:FireServer(optInBiomeId, false)
		end
	)
end

local function buildClaimBar(gui: ScreenGui)
	local frame = Theme.makeFrame(
		gui,
		"EggClaimPanel",
		UDim2.fromOffset(320, 82),
		UDim2.new(0.5, -160, 0.72, 0),
		Theme.Colors.Panel,
		12
	)
	frame.Visible = false
	Theme.addStroke(frame, Theme.Colors.Coins, 2)
	claimFrame = frame

	claimLabel = Theme.makeLabel(
		frame,
		"Title",
		"HOLD [E] OR BUTTON TO CLAIM BOSS EGG (5.0s)",
		UDim2.new(1, -16, 0, 24),
		UDim2.fromOffset(8, 6),
		13,
		Theme.Colors.Coins,
		true
	)
	if claimLabel then
		claimLabel.TextXAlignment = Enum.TextXAlignment.Center
	end

	local barBg = Theme.makeFrame(
		frame,
		"BarBg",
		UDim2.new(1, -24, 0, 16),
		UDim2.fromOffset(12, 32),
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
		UDim2.new(1, -24, 0, 26),
		UDim2.fromOffset(12, 52),
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
	local f = Theme.makeFrame(
		gui,
		"ToastBanner",
		UDim2.fromOffset(480, 40),
		UDim2.new(0.5, -240, 0, 110),
		Theme.Colors.Panel,
		10
	)
	f.Visible = false
	local lbl = Theme.makeLabel(
		f,
		"ToastText",
		"",
		UDim2.new(1, -16, 1, 0),
		UDim2.fromOffset(8, 0),
		14,
		Theme.Colors.Text,
		true
	)
	lbl.TextXAlignment = Enum.TextXAlignment.Center
	toastLabel = lbl
end

function ArenaHUDController.showToast(message: string, colorArr: { number }?)
	if not toastLabel or not toastLabel.Parent or not toastLabel.Parent:IsA("Frame") then
		return
	end
	toastLabel.Text = message
	if colorArr then
		toastLabel.TextColor3 =
			Color3.fromRGB(colorArr[1] or 255, colorArr[2] or 255, colorArr[3] or 255)
	else
		toastLabel.TextColor3 = Theme.Colors.Text
	end
	toastLabel.Parent.Visible = true
	toastExpireAt = os.clock() + 4.0
	task.delay(4.1, function()
		if
			os.clock() >= toastExpireAt
			and toastLabel
			and toastLabel.Parent
			and toastLabel.Parent:IsA("Frame")
		then
			toastLabel.Parent.Visible = false
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
		overchargedChip.Text = `⚡ 5-Min Overcharged Boss Event: {MathUtil.formatClock(overLeft)}`
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

	if phaseTitle then
		if not st then
			phaseTitle.Text = "HUB PLAZA • PvE SAFE (Walk through Portals to Fight!)"
			phaseTitle.TextColor3 = Theme.Colors.Emerald
		else
			local bCfg = BiomeConfigs.getBiome(activeBiome)
			local bName = if bCfg then bCfg.displayName else activeBiome
			local overTag = if st.isOvercharged then "⚡ OVERCHARGED " else ""
			phaseTitle.Text =
				`{overTag}{bName} • {st.phase} ({MathUtil.formatClock(st.timeRemaining or 0)})`
			phaseTitle.TextColor3 = if st.phase == "PvP_EggScramble"
				then Theme.Colors.Danger
				elseif st.isOvercharged then Theme.Colors.Overcharged
				else Theme.Colors.Coins
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
