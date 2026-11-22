--!strict
--[[
	HubModalsGui.luau
	Responsive Hub progression modal:
	- Pets Tab: Lv 1-25 Coin leveling, 3-to-1 Star Fusion, Gem Trait Rerolls, Active Followers (1-3), Pedestal placement, Sell
	- Eggs & Craft Tab: Egg Backpack hatching + Gem-Craftable Standard Biome Eggs
	- Upgrades & Ascension Tab: Target Tiers, Ball Tiers, Pedestals 4->12, Offline Vault 50%->100%, Active Slots 2-3, Soft Ascension
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyConfigs = require(Shared.Configs.EconomyConfigs)
local PetConfigs = require(Shared.Configs.PetConfigs)
local EggConfigs = require(Shared.Configs.EggConfigs)
local MathUtil = require(Shared.Utils.MathUtil)
local Remotes = require(Shared.Net.Remotes)

local Theme = require(script.Parent.Theme)

local HubModalsGui = {}

local rootFrame: Frame? = nil
local scrollBody: ScrollingFrame? = nil
local activeTab = "Pets"
local latestProfile: any = nil

local function clearScroll()
	if not scrollBody then
		return
	end
	for _, child in ipairs(scrollBody:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function isEquipped(profile: any, uid: string): boolean
	for _, id in ipairs(profile.activeFollowerUids or {}) do
		if id == uid then
			return true
		end
	end
	return false
end

local function findThreeMatchingUids(profile: any, speciesId: string, starTier: number): { string }?
	if starTier >= 3 then
		return nil
	end
	local match: { string } = {}
	for _, p in ipairs(profile.pets or {}) do
		if p.speciesId == speciesId and p.starTier == starTier then
			table.insert(match, p.uid)
			if #match == 3 then
				return match
			end
		end
	end
	return nil
end

local function findOpenPedestal(profile: any): number?
	local used: { [number]: boolean } = {}
	for _, p in ipairs(profile.pets or {}) do
		if p.pedestalIndex ~= nil then
			used[p.pedestalIndex] = true
		end
	end
	for idx = 1, (profile.pedestalsUnlocked or 4) do
		if not used[idx] then
			return idx
		end
	end
	return nil
end

local function renderPetsTab(profile: any)
	if not scrollBody then
		return
	end
	local remotes = Remotes.waitClient()
	local pets = profile.pets or {}
	if #pets == 0 then
		Theme.makeLabel(
			scrollBody,
			"Empty",
			"No Pets yet! Hatch your FREE Starter Egg on Pedestal #1!",
			UDim2.new(1, 0, 0, 36),
			UDim2.fromOffset(0, 0),
			15,
			Theme.Colors.Coins,
			true
		)
		return
	end

	for _, pet in ipairs(pets) do
		local spec = PetConfigs.getSpecies(pet.speciesId)
		local name = if spec then spec.displayName else pet.speciesId
		local baseRate = if spec then spec.baseRate else 5
		local stars = string.rep("★", math.clamp(pet.starTier or 1, 1, 3))
		local rate = EconomyConfigs.computePetCoinsPerSec({
			baseRate = baseRate,
			mutationKey = pet.mutationKey or "Normal",
			starTier = pet.starTier or 1,
			petLevel = pet.level or 1,
			traitKey = pet.traitKey,
			ascensionRank = profile.ascensionRank or 0,
		})
		local card = Theme.makeFrame(
			scrollBody,
			"Pet_" .. pet.uid,
			UDim2.new(1, -8, 0, 88),
			UDim2.fromOffset(0, 0),
			Theme.Colors.Card,
			10
		)
		local traitTxt = if pet.traitKey then ` | Trait: {pet.traitKey}` else ""
		local pedTxt = if pet.pedestalIndex then `Ped #{pet.pedestalIndex}` else "Backpack"
		Theme.makeLabel(
			card,
			"Name",
			`[{pet.mutationKey}] {name} {stars} (Lv {pet.level})`,
			UDim2.new(1, -16, 0, 22),
			UDim2.fromOffset(10, 6),
			15,
			Theme.Colors.Text,
			true
		)
		Theme.makeLabel(
			card,
			"Info",
			`{MathUtil.formatNumber(rate)} Coins/s | {if spec then spec.perkLabel else ""}{traitTxt} | {pedTxt}`,
			UDim2.new(1, -16, 0, 18),
			UDim2.fromOffset(10, 28),
			12,
			Theme.Colors.Muted,
			false
		)

		local eq = isEquipped(profile, pet.uid)
		Theme.makeButton(
			card,
			"EqBtn",
			if eq then "UNEQUIP" else "EQUIP",
			UDim2.fromOffset(82, 30),
			UDim2.fromOffset(10, 50),
			if eq then Theme.Colors.CardAlt else Theme.Colors.Emerald,
			function()
				remotes.PetAction:FireServer("ToggleActive", pet.uid)
			end
		)

		local lvlCost = if (pet.level or 1) < EconomyConfigs.MAX_PET_LEVEL
			then EconomyConfigs.getPetLevelUpCost(pet.level or 1, baseRate)
			else 0
		Theme.makeButton(
			card,
			"LvlBtn",
			if lvlCost > 0 then `LV+ ({MathUtil.formatNumber(lvlCost)})` else "MAX LV",
			UDim2.fromOffset(104, 30),
			UDim2.fromOffset(98, 50),
			Theme.Colors.Coins,
			function()
				remotes.PetAction:FireServer("LevelUp", pet.uid)
			end
		)

		Theme.makeButton(
			card,
			"TraitBtn",
			`TRAIT ({EconomyConfigs.TRAIT_REROLL_GEM_COST}G)`,
			UDim2.fromOffset(100, 30),
			UDim2.fromOffset(208, 50),
			Theme.Colors.Gems,
			function()
				remotes.PetAction:FireServer("RerollTrait", pet.uid)
			end
		)

		local fuseGroup = findThreeMatchingUids(profile, pet.speciesId, pet.starTier or 1)
		Theme.makeButton(
			card,
			"FuseBtn",
			if fuseGroup then "FUSE 3->1★" else "NEED 3x",
			UDim2.fromOffset(92, 30),
			UDim2.fromOffset(314, 50),
			if fuseGroup then Theme.Colors.Molten else Theme.Colors.CardAlt,
			function()
				if fuseGroup then
					remotes.PetAction:FireServer("Fuse", fuseGroup)
				end
			end
		)

		if pet.pedestalIndex == nil then
			local openPed = findOpenPedestal(profile)
			Theme.makeButton(
				card,
				"PlaceBtn",
				"PLACE",
				UDim2.fromOffset(70, 30),
				UDim2.fromOffset(412, 50),
				Theme.Colors.Frost,
				function()
					if openPed then
						remotes.PetAction:FireServer(
							"PlacePet",
							{ uid = pet.uid, pedestalIndex = openPed }
						)
					end
				end
			)
		else
			Theme.makeButton(
				card,
				"SellBtn",
				"SELL",
				UDim2.fromOffset(70, 30),
				UDim2.fromOffset(412, 50),
				Theme.Colors.Danger,
				function()
					remotes.PetAction:FireServer("SellPet", pet.uid)
				end
			)
		end
	end
end

local function renderEggsTab(profile: any)
	if not scrollBody then
		return
	end
	local remotes = Remotes.waitClient()
	Theme.makeLabel(
		scrollBody,
		"H1",
		"Your Egg Backpack (3s Instant Pedestal Hatch)",
		UDim2.new(1, 0, 0, 24),
		UDim2.fromOffset(0, 0),
		15,
		Theme.Colors.Coins,
		true
	)
	local anyEgg = false
	for eggId, count in pairs(profile.eggs or {}) do
		if count > 0 then
			anyEgg = true
			local cfg = EggConfigs.getEgg(eggId)
			local card = Theme.makeFrame(
				scrollBody,
				"Egg_" .. eggId,
				UDim2.new(1, -8, 0, 56),
				UDim2.fromOffset(0, 0),
				Theme.Colors.Card,
				10
			)
			Theme.makeLabel(
				card,
				"Name",
				`{if cfg then cfg.displayName else eggId} (x{count})`,
				UDim2.fromScale(0.65, 1),
				UDim2.fromOffset(12, 0),
				15,
				Theme.Colors.Text,
				true
			)
			Theme.makeButton(
				card,
				"HatchBtn",
				"HATCH NOW",
				UDim2.fromOffset(120, 36),
				UDim2.new(1, -132, 0, 10),
				Theme.Colors.Emerald,
				function()
					local ped = findOpenPedestal(profile)
					if ped then
						remotes.HatchEgg:FireServer(eggId, ped)
					end
				end
			)
		end
	end
	if not anyEgg then
		Theme.makeLabel(
			scrollBody,
			"NoEggs",
			"Win Biome Boss Eggs in PvP or craft Standard Eggs with Boss Gems below!",
			UDim2.new(1, 0, 0, 24),
			UDim2.fromOffset(0, 0),
			13,
			Theme.Colors.Muted,
			false
		)
	end

	Theme.makeLabel(
		scrollBody,
		"H2",
		"Gem Egg Crafter (Standard Biome Eggs — Overcharged stays PvP Exclusive!)",
		UDim2.new(1, 0, 0, 24),
		UDim2.fromOffset(0, 0),
		14,
		Theme.Colors.Gems,
		true
	)
	for _, biomeId in ipairs({ "EmeraldMeadow", "FrostbiteCavern", "MoltenCaldera" }) do
		local cost = EconomyConfigs.GEM_CRAFT_EGG_COSTS[biomeId]
		local card = Theme.makeFrame(
			scrollBody,
			"Craft_" .. biomeId,
			UDim2.new(1, -8, 0, 54),
			UDim2.fromOffset(0, 0),
			Theme.Colors.Card,
			10
		)
		Theme.makeLabel(
			card,
			"Name",
			`{biomeId} Standard Boss Egg`,
			UDim2.fromScale(0.62, 1),
			UDim2.fromOffset(12, 0),
			14,
			Theme.Colors.Text,
			true
		)
		Theme.makeButton(
			card,
			"CraftBtn",
			`CRAFT ({cost} Gems)`,
			UDim2.fromOffset(146, 34),
			UDim2.new(1, -158, 0, 10),
			Theme.Colors.Gems,
			function()
				remotes.UpgradeAction:FireServer("CraftBiomeEgg", biomeId)
			end
		)
	end
end

local function addUpgradeRow(
	title: string,
	desc: string,
	btnText: string,
	color: Color3,
	action: string
)
	if not scrollBody then
		return
	end
	local card = Theme.makeFrame(
		scrollBody,
		"Upg_" .. action,
		UDim2.new(1, -8, 0, 64),
		UDim2.fromOffset(0, 0),
		Theme.Colors.Card,
		10
	)
	Theme.makeLabel(
		card,
		"Title",
		title,
		UDim2.new(0.64, 0, 0, 24),
		UDim2.fromOffset(12, 6),
		15,
		Theme.Colors.Text,
		true
	)
	Theme.makeLabel(
		card,
		"Desc",
		desc,
		UDim2.new(0.64, 0, 0, 28),
		UDim2.fromOffset(12, 30),
		12,
		Theme.Colors.Muted,
		false
	)
	Theme.makeButton(
		card,
		"Btn",
		btnText,
		UDim2.fromOffset(146, 40),
		UDim2.new(1, -158, 0, 12),
		color,
		function()
			Remotes.waitClient().UpgradeAction:FireServer(action)
		end
	)
end

local function renderUpgradesTab(profile: any)
	local tIdx = EconomyConfigs.getTargetTierIndex(profile.targetTierId or "WoodenDummy")
	local nextTarget = EconomyConfigs.TRAINING_TARGETS[tIdx + 1]
	addUpgradeRow(
		`Training Target Tier ({profile.targetTierId})`,
		if nextTarget
			then `Next: {nextTarget.displayName} ({nextTarget.dmgPerHit} DMG/hit)`
			else "Max Target Tier!",
		if nextTarget then `{MathUtil.formatNumber(nextTarget.costCoins)} Coins` else "MAXED",
		Theme.Colors.Emerald,
		"UpgradeTarget"
	)

	local bIdx = EconomyConfigs.getBallTierIndex(profile.ballTierId or "RubberBall")
	local nextBall = EconomyConfigs.BALL_TIERS[bIdx + 1]
	addUpgradeRow(
		`Ball Shop Tier ({profile.ballTierId})`,
		if nextBall
			then `Next: {nextBall.displayName} ({nextBall.damageMult}x DMG)`
			else "Max Ball Tier!",
		if nextBall then `{MathUtil.formatNumber(nextBall.costCoins)} Coins` else "MAXED",
		Theme.Colors.Molten,
		"UpgradeBall"
	)

	local pedCount = profile.pedestalsUnlocked or 4
	local nextPed = EconomyConfigs.PEDESTAL_UNLOCKS[pedCount + 1]
	local pedCostTxt = if nextPed and not nextPed.requiresVipPass
		then `{MathUtil.formatNumber(nextPed.costCoins)}C` .. (if nextPed.costGems > 0
			then ` + {nextPed.costGems}G`
			else "")
		else "MAX (12/12)"
	addUpgradeRow(
		`Base Pedestals ({pedCount}/12 + 2nd-Floor Balcony)`,
		"Unlock Pedestals 5-8 (Courtyard) & 9-12 (2nd-Floor Showcase Balcony).",
		pedCostTxt,
		Theme.Colors.Coins,
		"UnlockPedestal"
	)

	local vTier = profile.offlineVaultTier or 1
	local nextVault = EconomyConfigs.OFFLINE_VAULT_TIERS[vTier + 1]
	addUpgradeRow(
		`Offline Vault ({math.floor(EconomyConfigs.getOfflineVaultEfficiency(vTier) * 100)}% <=12h)`,
		"Upgrade offline Cash Pad accrual efficiency (50% -> 75% -> 100%).",
		if nextVault then `{nextVault.costGems} Gems` else "100% MAX",
		Theme.Colors.Gems,
		"UpgradeOfflineVault"
	)

	local slots = profile.activeSlotsUnlocked or 1
	local nextSlot = EconomyConfigs.ACTIVE_SLOT_UNLOCKS[slots + 1]
	addUpgradeRow(
		`Active Combat Follower Slots ({slots}/3)`,
		if nextSlot
			then `Requires Level {nextSlot.requiredLevel} + {nextSlot.costGems} Gems`
			else "All 3 Slots Unlocked!",
		if nextSlot then `{nextSlot.costGems} Gems` else "MAXED",
		Theme.Colors.Frost,
		"UnlockActiveSlot"
	)

	local ascRank = profile.ascensionRank or 0
	local ascCost = EconomyConfigs.getAscensionCoinThreshold(ascRank)
	addUpgradeRow(
		`Soft Ascension (Rank {ascRank} -> {ascRank + 1})`,
		"Resets COINS ONLY (keeps 100% Pets, DMG, Lv & Gems)! +25% Coins & +5% Training.",
		`{MathUtil.formatNumber(ascCost)} Coins`,
		Theme.Colors.Overcharged,
		"SoftAscend"
	)
end

local function rerender()
	if not latestProfile or not rootFrame or not rootFrame.Visible then
		return
	end
	clearScroll()
	if activeTab == "Pets" then
		renderPetsTab(latestProfile)
	elseif activeTab == "Eggs" then
		renderEggsTab(latestProfile)
	else
		renderUpgradesTab(latestProfile)
	end
end

function HubModalsGui.mount()
	local gui = Theme.createScreenGui("BallBrawl_HubModals", 20)
	local panel = Theme.makeFrame(
		gui,
		"MainPanel",
		UDim2.fromOffset(520, 410),
		UDim2.new(0.5, -260, 0.5, -205),
		Theme.Colors.Panel,
		14
	)
	panel.Visible = false
	rootFrame = panel

	Theme.makeLabel(
		panel,
		"Title",
		"HUB PROGRESSION & PETS",
		UDim2.fromOffset(300, 32),
		UDim2.fromOffset(14, 10),
		18,
		Theme.Colors.Coins,
		true
	)
	Theme.makeButton(
		panel,
		"CloseBtn",
		"X",
		UDim2.fromOffset(34, 34),
		UDim2.new(1, -44, 0, 8),
		Theme.Colors.Danger,
		function()
			panel.Visible = false
		end
	)

	local tabs = {
		{ id = "Pets", label = "PETS & FUSION", x = 14 },
		{ id = "Eggs", label = "EGGS & CRAFT", x = 178 },
		{ id = "Upgrades", label = "UPGRADES & ASCEND", x = 342 },
	}
	for _, t in ipairs(tabs) do
		Theme.makeButton(
			panel,
			"Tab_" .. t.id,
			t.label,
			UDim2.fromOffset(156, 32),
			UDim2.fromOffset(t.x, 48),
			Theme.Colors.CardAlt,
			function()
				activeTab = t.id
				rerender()
			end
		)
	end

	local sc = Instance.new("ScrollingFrame")
	sc.Name = "Body"
	sc.BackgroundTransparency = 1
	sc.Position = UDim2.fromOffset(12, 88)
	sc.Size = UDim2.new(1, -24, 1, -100)
	sc.CanvasSize = UDim2.fromOffset(0, 0)
	sc.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sc.ScrollBarThickness = 6
	sc.Parent = panel
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.Parent = sc
	scrollBody = sc
end

function HubModalsGui.open(tabName: string)
	activeTab = tabName
	if rootFrame then
		rootFrame.Visible = true
		rerender()
	end
end

function HubModalsGui.close()
	if rootFrame then
		rootFrame.Visible = false
	end
end

function HubModalsGui.setProfile(profile: any)
	latestProfile = profile
	rerender()
end

return HubModalsGui
