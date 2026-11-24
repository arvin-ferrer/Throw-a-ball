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

local function applyTextConstraint(lbl: TextLabel, minSize: number, maxSize: number)
	lbl.TextScaled = true
	local tc = Instance.new("UITextSizeConstraint")
	tc.MinTextSize = minSize
	tc.MaxTextSize = maxSize
	tc.Parent = lbl
end

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

	for idx, pet in ipairs(pets) do
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
		card.LayoutOrder = idx
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

		local btnRow = Instance.new("Frame")
		btnRow.Name = "ActionRow"
		btnRow.BackgroundTransparency = 1
		btnRow.Position = UDim2.fromOffset(10, 48)
		btnRow.Size = UDim2.new(1, -20, 0, 32)
		btnRow.Parent = card
		local rl = Instance.new("UIListLayout")
		rl.FillDirection = Enum.FillDirection.Horizontal
		rl.SortOrder = Enum.SortOrder.LayoutOrder
		rl.Padding = UDim.new(0, 5)
		rl.Parent = btnRow

		local btnOrder = 0
		local function addCardBtn(btnName: string, txt: string, col: Color3, cb: () -> ())
			btnOrder += 1
			local b = Theme.makeButton(
				btnRow,
				btnName,
				txt,
				UDim2.fromScale(0.18, 1),
				UDim2.fromOffset(0, 0),
				col,
				cb
			)
			b.LayoutOrder = btnOrder
			b.TextScaled = true
			local tc = Instance.new("UITextSizeConstraint")
			tc.MaxTextSize = 12
			tc.MinTextSize = 8
			tc.Parent = b
			local fx = Instance.new("UIFlexItem")
			fx.FlexMode = Enum.UIFlexMode.Fill
			fx.Parent = b
		end

		local eq = isEquipped(profile, pet.uid)
		addCardBtn(
			"EqBtn",
			if eq then "UNEQUIP" else "EQUIP",
			if eq then Theme.Colors.CardAlt else Theme.Colors.Emerald,
			function()
				remotes.PetAction:FireServer("ToggleActive", pet.uid)
			end
		)

		local lvlCost = if (pet.level or 1) < EconomyConfigs.MAX_PET_LEVEL
			then EconomyConfigs.getPetLevelUpCost(pet.level or 1, baseRate)
			else 0
		addCardBtn(
			"LvlBtn",
			if lvlCost > 0 then `LV+ ({MathUtil.formatNumber(lvlCost)})` else "MAX LV",
			Theme.Colors.Coins,
			function()
				remotes.PetAction:FireServer("LevelUp", pet.uid)
			end
		)

		addCardBtn(
			"TraitBtn",
			`TRAIT ({EconomyConfigs.TRAIT_REROLL_GEM_COST}G)`,
			Theme.Colors.Gems,
			function()
				remotes.PetAction:FireServer("RerollTrait", pet.uid)
			end
		)

		local fuseGroup = findThreeMatchingUids(profile, pet.speciesId, pet.starTier or 1)
		addCardBtn(
			"FuseBtn",
			if fuseGroup then "FUSE 3->1★" else "NEED 3x",
			if fuseGroup then Theme.Colors.Molten else Theme.Colors.CardAlt,
			function()
				if fuseGroup then
					remotes.PetAction:FireServer("Fuse", fuseGroup)
				end
			end
		)

		if pet.pedestalIndex == nil then
			local openPed = findOpenPedestal(profile)
			addCardBtn("PlaceBtn", "PLACE", Theme.Colors.Frost, function()
				if openPed then
					remotes.PetAction:FireServer(
						"PlacePet",
						{ uid = pet.uid, pedestalIndex = openPed }
					)
				end
			end)
		else
			addCardBtn("SellBtn", "SELL", Theme.Colors.Danger, function()
				remotes.PetAction:FireServer("SellPet", pet.uid)
			end)
		end
	end
end

local function renderOwnedEggsSection(
	parent: ScrollingFrame,
	profile: any,
	remotes: any,
	startOrder: number
): number
	local order = startOrder
	local h1 = Theme.makeLabel(
		parent,
		"H1",
		"Your Egg Backpack (3s Instant Pedestal Hatch)",
		UDim2.new(1, 0, 0, 24),
		UDim2.fromOffset(0, 0),
		15,
		Theme.Colors.Coins,
		true
	)
	h1.LayoutOrder = order
	order += 1

	local ownedIds: { string } = {}
	for eggId, count in pairs(profile.eggs or {}) do
		if count > 0 then
			table.insert(ownedIds, eggId)
		end
	end
	table.sort(ownedIds)

	for _, eggId in ipairs(ownedIds) do
		local count = (profile.eggs or {})[eggId]
		local cfg = EggConfigs.getEgg(eggId)
		local card = Theme.makeFrame(
			parent,
			"Egg_" .. eggId,
			UDim2.new(1, -8, 0, 56),
			UDim2.fromOffset(0, 0),
			Theme.Colors.Card,
			10
		)
		card.LayoutOrder = order
		order += 1
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
	if #ownedIds == 0 then
		local emptyLbl = Theme.makeLabel(
			parent,
			"NoEggs",
			"Win Biome Boss Eggs in PvP or craft Standard Eggs with Boss Gems below!",
			UDim2.new(1, 0, 0, 24),
			UDim2.fromOffset(0, 0),
			13,
			Theme.Colors.Muted,
			false
		)
		emptyLbl.LayoutOrder = order
		order += 1
	end
	return order
end

local function renderGemCraftSection(
	parent: ScrollingFrame,
	remotes: any,
	startOrder: number
): number
	local order = startOrder
	local h2 = Theme.makeLabel(
		parent,
		"H2",
		"Gem Egg Crafter (Standard Biome Eggs — Overcharged stays PvP Exclusive!)",
		UDim2.new(1, 0, 0, 24),
		UDim2.fromOffset(0, 0),
		14,
		Theme.Colors.Gems,
		true
	)
	h2.LayoutOrder = order
	order += 1
	for _, biomeId in ipairs({ "EmeraldMeadow", "FrostbiteCavern", "MoltenCaldera" }) do
		local cost = EconomyConfigs.GEM_CRAFT_EGG_COSTS[biomeId]
		local card = Theme.makeFrame(
			parent,
			"Craft_" .. biomeId,
			UDim2.new(1, -8, 0, 54),
			UDim2.fromOffset(0, 0),
			Theme.Colors.Card,
			10
		)
		card.LayoutOrder = order
		order += 1
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
	return order
end

local function renderEggsTab(profile: any)
	if not scrollBody then
		return
	end
	local remotes = Remotes.waitClient()
	local nextOrder = renderOwnedEggsSection(scrollBody, profile, remotes, 1)
	renderGemCraftSection(scrollBody, remotes, nextOrder)
end

local function addUpgradeRow(
	title: string,
	desc: string,
	btnText: string,
	color: Color3,
	action: string,
	order: number
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
	card.LayoutOrder = order
	local titleLbl = Theme.makeLabel(
		card,
		"Title",
		title,
		UDim2.new(1, -174, 0, 22),
		UDim2.fromOffset(12, 6),
		15,
		Theme.Colors.Text,
		true
	)
	applyTextConstraint(titleLbl, 10, 15)
	local descLbl = Theme.makeLabel(
		card,
		"Desc",
		desc,
		UDim2.new(1, -174, 0, 32),
		UDim2.fromOffset(12, 28),
		12,
		Theme.Colors.Muted,
		false
	)
	descLbl.TextWrapped = true
	applyTextConstraint(descLbl, 9, 12)
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
		"UpgradeTarget",
		1
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
		"UpgradeBall",
		2
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
		"UnlockPedestal",
		3
	)

	local vTier = profile.offlineVaultTier or 1
	local nextVault = EconomyConfigs.OFFLINE_VAULT_TIERS[vTier + 1]
	addUpgradeRow(
		`Offline Vault ({math.floor(EconomyConfigs.getOfflineVaultEfficiency(vTier) * 100)}% <=12h)`,
		"Upgrade offline Cash Pad accrual efficiency (50% -> 75% -> 100%).",
		if nextVault then `{nextVault.costGems} Gems` else "100% MAX",
		Theme.Colors.Gems,
		"UpgradeOfflineVault",
		4
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
		"UnlockActiveSlot",
		5
	)

	local ascRank = profile.ascensionRank or 0
	local ascCost = EconomyConfigs.getAscensionCoinThreshold(ascRank)
	addUpgradeRow(
		`Soft Ascension (Rank {ascRank} -> {ascRank + 1})`,
		"Resets COINS ONLY (keeps 100% Pets, DMG, Lv & Gems)! +25% Coins & +5% Training.",
		`{MathUtil.formatNumber(ascCost)} Coins`,
		Theme.Colors.Overcharged,
		"SoftAscend",
		6
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
	local panel = Theme.makeGlossyPanel(
		gui,
		"MainPanel",
		UDim2.fromScale(0.92, 0.86),
		UDim2.fromScale(0.5, 0.5),
		16
	)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Visible = false
	local scConstraint = Instance.new("UISizeConstraint")
	scConstraint.MaxSize = Vector2.new(580, 440)
	scConstraint.MinSize = Vector2.new(300, 250)
	scConstraint.Parent = panel
	rootFrame = panel

	Theme.makeLabel(
		panel,
		"Title",
		"HUB PROGRESSION & PETS",
		UDim2.new(1, -68, 0, 34),
		UDim2.fromOffset(16, 10),
		18,
		Theme.Colors.Coins,
		true
	)
	Theme.makeButton(
		panel,
		"CloseBtn",
		"X",
		UDim2.fromOffset(44, 44),
		UDim2.new(1, -50, 0, 6),
		Theme.Colors.Danger,
		function()
			panel.Visible = false
		end
	)

	local tabRow = Instance.new("Frame")
	tabRow.Name = "TabRow"
	tabRow.BackgroundTransparency = 1
	tabRow.Position = UDim2.fromOffset(14, 52)
	tabRow.Size = UDim2.new(1, -28, 0, 34)
	tabRow.Parent = panel
	local tl = Instance.new("UIListLayout")
	tl.FillDirection = Enum.FillDirection.Horizontal
	tl.SortOrder = Enum.SortOrder.LayoutOrder
	tl.Padding = UDim.new(0, 8)
	tl.Parent = tabRow

	local tabs = {
		{ id = "Pets", label = "PETS & FUSION", color = Theme.Colors.Emerald },
		{ id = "Eggs", label = "EGGS & CRAFT", color = Theme.Colors.Coins },
		{ id = "Upgrades", label = "UPGRADES & ASCEND", color = Theme.Colors.Frost },
	}
	for idx, t in ipairs(tabs) do
		local tb = Theme.makeButton(
			tabRow,
			"Tab_" .. t.id,
			t.label,
			UDim2.fromScale(0.32, 1),
			UDim2.fromOffset(0, 0),
			t.color,
			function()
				activeTab = t.id
				rerender()
			end
		)
		tb.LayoutOrder = idx
		tb.TextScaled = true
		local tc = Instance.new("UITextSizeConstraint")
		tc.MaxTextSize = 13
		tc.MinTextSize = 9
		tc.Parent = tb
		local fx = Instance.new("UIFlexItem")
		fx.FlexMode = Enum.UIFlexMode.Fill
		fx.Parent = tb
	end

	local sc = Instance.new("ScrollingFrame")
	sc.Name = "Body"
	sc.BackgroundTransparency = 1
	sc.Position = UDim2.fromOffset(12, 94)
	sc.Size = UDim2.new(1, -24, 1, -106)
	sc.CanvasSize = UDim2.fromOffset(0, 0)
	sc.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sc.ScrollBarThickness = 6
	sc.Parent = panel
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
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

function HubModalsGui.isOpen(): boolean
	return rootFrame ~= nil and rootFrame.Visible
end

function HubModalsGui.setProfile(profile: any)
	latestProfile = profile
	rerender()
end

return HubModalsGui
