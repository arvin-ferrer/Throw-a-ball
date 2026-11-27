--!strict
--[[
	HubModalsGui.luau
	RBLX Essentials cartoon-pop Hub Progression modal:
	- Pets Tab: Lv 1-25 Coin leveling, 3-to-1 Star Fusion, Gem Trait Rerolls, Active Followers (1-3), Pedestal placement, Sell
	- Eggs & Craft Tab: Egg Backpack hatching + Gem-Craftable Standard Biome Eggs
	- Upgrades & Ascension Tab: Target Tiers, Ball Tiers, Pedestals 4->12, Offline Vault, Active Slots, Config-Driven Soft Ascension
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyConfigs = require(Shared.Configs.EconomyConfigs)
local EggConfigs = require(Shared.Configs.EggConfigs)
local PetConfigs = require(Shared.Configs.PetConfigs)
local MathUtil = require(Shared.Utils.MathUtil)
local Remotes = require(Shared.Net.Remotes)

local HudIcons = require(script.Parent.HudIcons)
local Theme = require(script.Parent.Theme)

local HubModalsGui = {}

local WHITE = Color3.fromRGB(255, 255, 255)
local MUTED_TOP = Color3.fromRGB(142, 154, 178)
local MUTED_BOT = Color3.fromRGB(104, 116, 140)
local TAB_SPECS = {
	{
		id = "Pets",
		label = "PETS",
		header = "PETS & FUSION",
		top = Theme.Colors.LimeTop,
		bot = Theme.Colors.LimeBot,
	},
	{
		id = "Eggs",
		label = "EGGS & CRAFT",
		header = "EGGS & CRAFT",
		top = Theme.Colors.GoldTop,
		bot = Theme.Colors.GoldBot,
	},
	{
		id = "Upgrades",
		label = "UPGRADES",
		header = "UPGRADES & ASCENSION",
		top = Theme.Colors.HubBlueTop,
		bot = Theme.Colors.HubBlueBot,
	},
}
local BIOME_COLORS: { [string]: Color3 } = {
	EmeraldMeadow = Theme.Colors.Emerald,
	FrostbiteCavern = Theme.Colors.Frost,
	MoltenCaldera = Theme.Colors.Molten,
}

local rootFrame: Frame? = nil
local headerTitle: TextLabel? = nil
local scrollBody: ScrollingFrame? = nil
local tabButtons: { [string]: TextButton } = {}
local activeTab = "Pets"
local latestProfile: any = nil

local function applyTextConstraint(lbl: TextLabel | TextButton, minSize: number, maxSize: number)
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

local function addSectionDivider(parent: ScrollingFrame, name: string, order: number)
	local div = Instance.new("Frame")
	div.Name = name
	div.LayoutOrder = order
	div.Size = UDim2.new(1, 0, 0, 3)
	div.BackgroundColor3 = Theme.Colors.Ink
	div.BorderSizePixel = 0
	div.Parent = parent
	Theme.addCorner(div, 999)
end

local function addSectionHeader(parent: ScrollingFrame, name: string, text: string, order: number)
	local lbl = Theme.makeLabel(
		parent,
		name,
		text,
		UDim2.fromScale(1, 0),
		UDim2.fromOffset(0, 0),
		14,
		Theme.Colors.TextDark,
		true
	)
	lbl.LayoutOrder = order
	lbl.TextWrapped = true
	lbl.AutomaticSize = Enum.AutomaticSize.Y
end

local function makeLightCard(
	parent: ScrollingFrame,
	name: string,
	order: number,
	bg: Color3?
): Frame
	local card = Instance.new("Frame")
	card.Name = name
	card.LayoutOrder = order
	card.Size = UDim2.fromScale(1, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = bg or WHITE
	card.BorderSizePixel = 0
	card.Parent = parent
	Theme.addCorner(card, 12)
	Theme.addStroke(card, Theme.Colors.Ink, 2.5, 0)
	Theme.addPadding(card, 10, 10)
	return card
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

local function addPetActionButton(
	btnRow: Frame,
	btnName: string,
	txt: string,
	topCol: Color3,
	botCol: Color3,
	order: number,
	cb: () -> ()
)
	local b = Theme.makeGoldPillButton(
		btnRow,
		btnName,
		txt,
		UDim2.new(0.18, 0, 0, 48),
		UDim2.fromOffset(0, 0),
		cb,
		topCol,
		botCol
	)
	b.LayoutOrder = order
	applyTextConstraint(b, 8, 12)
	local fx = Instance.new("UIFlexItem")
	fx.FlexMode = Enum.UIFlexMode.Fill
	fx.Parent = b
end

local function appendPetCoreActions(
	btnRow: Frame,
	profile: any,
	pet: any,
	baseRate: number,
	remotes: any
)
	local eq = isEquipped(profile, pet.uid)
	addPetActionButton(
		btnRow,
		"EqBtn",
		if eq then "UNEQUIP" else "EQUIP",
		if eq then MUTED_TOP else Theme.Colors.LimeTop,
		if eq then MUTED_BOT else Theme.Colors.LimeBot,
		1,
		function()
			remotes.PetAction:FireServer("ToggleActive", pet.uid)
		end
	)

	local lvlCost = if (pet.level or 1) < EconomyConfigs.MAX_PET_LEVEL
		then EconomyConfigs.getPetLevelUpCost(pet.level or 1, baseRate)
		else 0
	addPetActionButton(
		btnRow,
		"LvlBtn",
		if lvlCost > 0 then `LV+ ({MathUtil.formatNumber(lvlCost)})` else "MAX LV",
		Theme.Colors.GoldTop,
		Theme.Colors.GoldBot,
		2,
		function()
			remotes.PetAction:FireServer("LevelUp", pet.uid)
		end
	)
end

local function appendPetSecondaryActions(btnRow: Frame, profile: any, pet: any, remotes: any)
	addPetActionButton(
		btnRow,
		"TraitBtn",
		`TRAIT ({EconomyConfigs.TRAIT_REROLL_GEM_COST}G)`,
		Theme.Colors.TilePurpleTop,
		Theme.Colors.TilePurpleBot,
		3,
		function()
			remotes.PetAction:FireServer("RerollTrait", pet.uid)
		end
	)

	local fuseGroup = findThreeMatchingUids(profile, pet.speciesId, pet.starTier or 1)
	addPetActionButton(
		btnRow,
		"FuseBtn",
		if fuseGroup then "FUSE 3->1★" else "NEED 3x",
		if fuseGroup then Theme.Colors.TileGoldTop else MUTED_TOP,
		if fuseGroup then Theme.Colors.TileGoldBot else MUTED_BOT,
		4,
		function()
			if fuseGroup then
				remotes.PetAction:FireServer("Fuse", fuseGroup)
			end
		end
	)
end

local function appendPetSlotAction(btnRow: Frame, profile: any, pet: any, remotes: any)
	if pet.pedestalIndex == nil then
		local openPed = findOpenPedestal(profile)
		addPetActionButton(
			btnRow,
			"PlaceBtn",
			"PLACE",
			Theme.Colors.TileSkyTop,
			Theme.Colors.TileSkyBot,
			5,
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
		addPetActionButton(
			btnRow,
			"SellBtn",
			"SELL",
			Theme.Colors.ShopRedTop,
			Theme.Colors.ShopRedBot,
			5,
			function()
				remotes.PetAction:FireServer("SellPet", pet.uid)
			end
		)
	end
end

local function addPetCardHeader(card: Frame, pet: any, spec: PetConfigs.PetSpecies?, rate: number)
	local name = if spec then spec.displayName else pet.speciesId
	local stars = string.rep("★", math.clamp(pet.starTier or 1, 1, 3))
	local title = Theme.makeLabel(
		card,
		"Name",
		`[{pet.mutationKey}] {name} {stars} (Lv {pet.level})`,
		UDim2.fromScale(1, 0),
		UDim2.fromOffset(0, 0),
		15,
		Theme.Colors.TextDark,
		true
	)
	title.LayoutOrder = 1
	title.TextWrapped = true
	title.AutomaticSize = Enum.AutomaticSize.Y

	local traitTxt = if pet.traitKey then ` | Trait: {pet.traitKey}` else ""
	local pedTxt = if pet.pedestalIndex then `Ped #{pet.pedestalIndex}` else "Backpack"
	local perk = if spec then spec.perkLabel else ""
	local info = Theme.makeLabel(
		card,
		"Info",
		`{MathUtil.formatNumber(rate)} Coins/s | {perk}{traitTxt} | {pedTxt}`,
		UDim2.fromScale(1, 0),
		UDim2.fromOffset(0, 0),
		12,
		Theme.Colors.TextMutedDark,
		false
	)
	info.LayoutOrder = 2
	info.TextWrapped = true
	info.AutomaticSize = Enum.AutomaticSize.Y
end

local function renderPetCard(
	parent: ScrollingFrame,
	profile: any,
	pet: any,
	remotes: any,
	order: number
)
	local spec = PetConfigs.getSpecies(pet.speciesId)
	local baseRate = if spec then spec.baseRate else 5
	local rate = EconomyConfigs.computePetCoinsPerSec({
		baseRate = baseRate,
		mutationKey = pet.mutationKey or "Normal",
		starTier = pet.starTier or 1,
		petLevel = pet.level or 1,
		traitKey = pet.traitKey,
		ascensionRank = profile.ascensionRank or 0,
	})

	local card = makeLightCard(parent, "Pet_" .. pet.uid, order, WHITE)
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 6)
	list.Parent = card
	addPetCardHeader(card, pet, spec, rate)

	local btnRow = Instance.new("Frame")
	btnRow.Name = "ActionRow"
	btnRow.LayoutOrder = 3
	btnRow.BackgroundTransparency = 1
	btnRow.Size = UDim2.new(1, 0, 0, 48)
	btnRow.Parent = card
	local rl = Instance.new("UIListLayout")
	rl.FillDirection = Enum.FillDirection.Horizontal
	rl.SortOrder = Enum.SortOrder.LayoutOrder
	rl.Padding = UDim.new(0, 5)
	rl.Parent = btnRow
	appendPetCoreActions(btnRow, profile, pet, baseRate, remotes)
	appendPetSecondaryActions(btnRow, profile, pet, remotes)
	appendPetSlotAction(btnRow, profile, pet, remotes)
end

local function renderPetsTab(profile: any)
	if not scrollBody then
		return
	end
	local remotes = Remotes.waitClient()
	local pets = profile.pets or {}
	if #pets == 0 then
		local card = makeLightCard(scrollBody, "EmptyCard", 1, Color3.fromRGB(255, 250, 232))
		local msg = Theme.makeLabel(
			card,
			"Empty",
			"No Pets yet! Hatch your FREE Starter Egg on Pedestal #1!",
			UDim2.fromScale(1, 0),
			UDim2.fromOffset(0, 0),
			15,
			Theme.Colors.TextDark,
			true
		)
		msg.TextWrapped = true
		msg.AutomaticSize = Enum.AutomaticSize.Y
		return
	end
	for idx, pet in ipairs(pets) do
		renderPetCard(scrollBody, profile, pet, remotes, idx)
	end
end

local function addWrappedAutoLabel(
	parent: Instance,
	name: string,
	text: string,
	textSize: number,
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
		textSize,
		color,
		bold
	)
	lbl.LayoutOrder = order
	lbl.TextWrapped = true
	lbl.AutomaticSize = Enum.AutomaticSize.Y
end

local function addCardTextColumn(
	parent: Frame,
	titleText: string,
	subText: string?,
	widthOffset: number
)
	local textBox = Instance.new("Frame")
	textBox.Name = "TextCol"
	textBox.BackgroundTransparency = 1
	textBox.Position = UDim2.fromOffset(48, 0)
	textBox.Size = UDim2.new(1, widthOffset, 0, 44)
	textBox.AutomaticSize = Enum.AutomaticSize.Y
	textBox.Parent = parent
	local tl = Instance.new("UIListLayout")
	tl.SortOrder = Enum.SortOrder.LayoutOrder
	tl.Padding = UDim.new(0, 3)
	tl.Parent = textBox

	addWrappedAutoLabel(textBox, "Title", titleText, 14, Theme.Colors.TextDark, true, 1)
	if subText and subText ~= "" then
		addWrappedAutoLabel(textBox, "Desc", subText, 12, Theme.Colors.TextMutedDark, false, 2)
	end
end

type ActionCardSpec = {
	name: string,
	title: string,
	sub: string?,
	btnText: string,
	btnTop: Color3,
	btnBot: Color3,
	accentBg: Color3?,
	order: number,
	onClick: () -> (),
}

local function buildActionRowCard(parent: ScrollingFrame, spec: ActionCardSpec): (Frame, Frame)
	local card = makeLightCard(parent, spec.name, spec.order, spec.accentBg or WHITE)
	local isCompact = Theme.getLayoutMetrics().isCompact
	if isCompact then
		local list = Instance.new("UIListLayout")
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Padding = UDim.new(0, 8)
		list.Parent = card
		local topRow = Instance.new("Frame")
		topRow.Name = "TopRow"
		topRow.LayoutOrder = 1
		topRow.BackgroundTransparency = 1
		topRow.Size = UDim2.new(1, 0, 0, 44)
		topRow.AutomaticSize = Enum.AutomaticSize.Y
		topRow.Parent = card
		addCardTextColumn(topRow, spec.title, spec.sub, -48)
		local btn = Theme.makeGoldPillButton(
			card,
			"Btn",
			spec.btnText,
			UDim2.new(1, 0, 0, 48),
			UDim2.fromOffset(0, 0),
			spec.onClick,
			spec.btnTop,
			spec.btnBot
		)
		btn.LayoutOrder = 2
		applyTextConstraint(btn, 10, 14)
		return card, topRow
	end
	addCardTextColumn(card, spec.title, spec.sub, -196)
	local btn = Theme.makeGoldPillButton(
		card,
		"Btn",
		spec.btnText,
		UDim2.fromOffset(140, 48),
		UDim2.new(1, -140, 0.5, -24),
		spec.onClick,
		spec.btnTop,
		spec.btnBot
	)
	applyTextConstraint(btn, 9, 13)
	return card, card
end

local function renderOwnedEggRow(
	parent: ScrollingFrame,
	profile: any,
	remotes: any,
	eggId: string,
	order: number
)
	local count = (profile.eggs or {})[eggId]
	local cfg = EggConfigs.getEgg(eggId)
	local eggAccent = if cfg
		then Color3.fromRGB(cfg.primaryColor[1], cfg.primaryColor[2], cfg.primaryColor[3])
		else nil
	local _, iconHost = buildActionRowCard(parent, {
		name = "Egg_" .. eggId,
		title = `{if cfg then cfg.displayName else eggId} (x{count})`,
		sub = "Tap Hatch Now to place on your next open pedestal.",
		btnText = "HATCH NOW",
		btnTop = Theme.Colors.LimeTop,
		btnBot = Theme.Colors.LimeBot,
		accentBg = WHITE,
		order = order,
		onClick = function()
			local ped = findOpenPedestal(profile)
			if ped then
				remotes.HatchEgg:FireServer(eggId, ped)
			end
		end,
	})
	local icon = HudIcons.createEggIcon(iconHost, 40, eggAccent)
	icon.Position = UDim2.new(0, 0, 0.5, -20)
end

local function renderOwnedEggsSection(
	parent: ScrollingFrame,
	profile: any,
	remotes: any,
	startOrder: number
): number
	local order = startOrder
	addSectionHeader(parent, "H1", "Your Egg Backpack (3s Instant Pedestal Hatch)", order)
	order += 1

	local ownedIds: { string } = {}
	for eggId, count in pairs(profile.eggs or {}) do
		if count > 0 then
			table.insert(ownedIds, eggId)
		end
	end
	table.sort(ownedIds)

	for _, eggId in ipairs(ownedIds) do
		renderOwnedEggRow(parent, profile, remotes, eggId, order)
		order += 1
	end
	if #ownedIds == 0 then
		local emptyCard = makeLightCard(parent, "NoEggsCard", order, Color3.fromRGB(240, 244, 252))
		local lbl = Theme.makeLabel(
			emptyCard,
			"NoEggs",
			"Win Biome Boss Eggs in PvP or craft Standard Eggs with Boss Gems below!",
			UDim2.fromScale(1, 0),
			UDim2.fromOffset(0, 0),
			13,
			Theme.Colors.TextMutedDark,
			false
		)
		lbl.TextWrapped = true
		lbl.AutomaticSize = Enum.AutomaticSize.Y
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
	addSectionDivider(parent, "CraftDivider", order)
	order += 1
	addSectionHeader(
		parent,
		"H2",
		"Gem Egg Crafter (Standard Biome Eggs — Overcharged stays PvP Exclusive!)",
		order
	)
	order += 1
	for _, biomeId in ipairs({ "EmeraldMeadow", "FrostbiteCavern", "MoltenCaldera" }) do
		local cost = EconomyConfigs.GEM_CRAFT_EGG_COSTS[biomeId]
		local _, iconHost = buildActionRowCard(parent, {
			name = "Craft_" .. biomeId,
			title = `{biomeId} Standard Boss Egg`,
			sub = "Craftable with Boss Gems earned in Biome PvE & Boss fights.",
			btnText = `CRAFT ({cost} Gems)`,
			btnTop = Theme.Colors.TilePurpleTop,
			btnBot = Theme.Colors.TilePurpleBot,
			accentBg = WHITE,
			order = order,
			onClick = function()
				remotes.UpgradeAction:FireServer("CraftBiomeEgg", biomeId)
			end,
		})
		local icon = HudIcons.createEggIcon(iconHost, 40, BIOME_COLORS[biomeId])
		icon.Position = UDim2.new(0, 0, 0.5, -20)
		order += 1
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

local function addUpgradeCard(
	title: string,
	desc: string,
	btnText: string,
	topCol: Color3,
	botCol: Color3,
	iconKind: string,
	action: string,
	order: number,
	cardBg: Color3?
)
	if not scrollBody then
		return
	end
	local _, iconHost = buildActionRowCard(scrollBody, {
		name = "Upg_" .. action,
		title = title,
		sub = desc,
		btnText = btnText,
		btnTop = topCol,
		btnBot = botCol,
		accentBg = cardBg or WHITE,
		order = order,
		onClick = function()
			Remotes.waitClient().UpgradeAction:FireServer(action)
		end,
	})
	local icon = if iconKind == "Cash"
		then HudIcons.createCashStackIcon(iconHost, 40)
		elseif iconKind == "Gem" then HudIcons.createGemIcon(iconHost, 38)
		elseif iconKind == "Gift" then HudIcons.createGiftIcon(iconHost, 40)
		elseif iconKind == "Star" then HudIcons.createStarBurstIcon(iconHost, 40)
		else HudIcons.createUpgradesIcon(iconHost, 38)
	icon.Position = UDim2.new(0, 0, 0.5, -20)
end

local function formatVaultProgression(): string
	local steps: { string } = {}
	for _, tierSpec in ipairs(EconomyConfigs.OFFLINE_VAULT_TIERS) do
		table.insert(steps, `{math.floor(tierSpec.efficiency * 100 + 0.5)}%`)
	end
	return table.concat(steps, " -> ")
end

local function renderCombatUpgrades(profile: any)
	local tIdx = EconomyConfigs.getTargetTierIndex(profile.targetTierId or "WoodenDummy")
	local nextTarget = EconomyConfigs.TRAINING_TARGETS[tIdx + 1]
	addUpgradeCard(
		`Training Target Tier ({profile.targetTierId})`,
		if nextTarget
			then `Next: {nextTarget.displayName} ({nextTarget.dmgPerHit} DMG/hit)`
			else "Max Target Tier!",
		if nextTarget then `{MathUtil.formatNumber(nextTarget.costCoins)} Coins` else "MAXED",
		if nextTarget then Theme.Colors.LimeTop else MUTED_TOP,
		if nextTarget then Theme.Colors.LimeBot else MUTED_BOT,
		"Upgrade",
		"UpgradeTarget",
		1,
		WHITE
	)

	local bIdx = EconomyConfigs.getBallTierIndex(profile.ballTierId or "RubberBall")
	local nextBall = EconomyConfigs.BALL_TIERS[bIdx + 1]
	addUpgradeCard(
		`Ball Shop Tier ({profile.ballTierId})`,
		if nextBall
			then `Next: {nextBall.displayName} ({nextBall.damageMult}x DMG)`
			else "Max Ball Tier!",
		if nextBall then `{MathUtil.formatNumber(nextBall.costCoins)} Coins` else "MAXED",
		if nextBall then Theme.Colors.GoldTop else MUTED_TOP,
		if nextBall then Theme.Colors.GoldBot else MUTED_BOT,
		"Star",
		"UpgradeBall",
		2,
		WHITE
	)
end

local function renderPlotUpgrades(profile: any)
	local pedCount = profile.pedestalsUnlocked or 4
	local nextPed = EconomyConfigs.PEDESTAL_UNLOCKS[pedCount + 1]
	local canBuyPed = nextPed ~= nil and not nextPed.requiresVipPass
	local pedCostTxt = if canBuyPed and nextPed
		then `{MathUtil.formatNumber(nextPed.costCoins)}C` .. (if nextPed.costGems > 0
			then ` + {nextPed.costGems}G`
			else "")
		else "MAX (12/12)"
	addUpgradeCard(
		`Base Pedestals ({pedCount}/12 + 2nd-Floor Balcony)`,
		"Unlock Pedestals 5-8 (Courtyard) & 9-12 (2nd-Floor Showcase Balcony).",
		pedCostTxt,
		if canBuyPed then Theme.Colors.TileGoldTop else MUTED_TOP,
		if canBuyPed then Theme.Colors.TileGoldBot else MUTED_BOT,
		"Gift",
		"UnlockPedestal",
		3,
		WHITE
	)

	local vTier = profile.offlineVaultTier or 1
	local nextVault = EconomyConfigs.OFFLINE_VAULT_TIERS[vTier + 1]
	local vaultEffPct = math.floor(EconomyConfigs.getOfflineVaultEfficiency(vTier) * 100 + 0.5)
	addUpgradeCard(
		`Offline Vault ({vaultEffPct}% <=12h)`,
		`Upgrade offline Cash Pad accrual efficiency ({formatVaultProgression()}).`,
		if nextVault then `{nextVault.costGems} Gems` else "100% MAX",
		if nextVault then Theme.Colors.TilePurpleTop else MUTED_TOP,
		if nextVault then Theme.Colors.TilePurpleBot else MUTED_BOT,
		"Cash",
		"UpgradeOfflineVault",
		4,
		WHITE
	)
end

local function renderSlotAndAscensionUpgrades(profile: any)
	local slots = profile.activeSlotsUnlocked or 1
	local nextSlot = EconomyConfigs.ACTIVE_SLOT_UNLOCKS[slots + 1]
	addUpgradeCard(
		`Active Combat Follower Slots ({slots}/3)`,
		if nextSlot
			then `Requires Level {nextSlot.requiredLevel} + {nextSlot.costGems} Gems`
			else "All 3 Slots Unlocked!",
		if nextSlot then `{nextSlot.costGems} Gems` else "MAXED",
		if nextSlot then Theme.Colors.TileSkyTop else MUTED_TOP,
		if nextSlot then Theme.Colors.TileSkyBot else MUTED_BOT,
		"Gem",
		"UnlockActiveSlot",
		5,
		WHITE
	)

	local ascRank = profile.ascensionRank or 0
	local ascCost = EconomyConfigs.getAscensionCoinThreshold(ascRank)
	local coinBonusPct = math.floor(EconomyConfigs.ASCENSION_COIN_BONUS * 100 + 0.5)
	local trainBonusPct = math.floor(EconomyConfigs.ASCENSION_TRAINING_BONUS * 100 + 0.5)
	addUpgradeCard(
		`Soft Ascension (Rank {ascRank} -> {ascRank + 1})`,
		`Resets COINS ONLY (keeps 100% Pets, DMG, Lv & Gems)! +{coinBonusPct}% Coins & +{trainBonusPct}% Training per rank.`,
		`{MathUtil.formatNumber(ascCost)} Coins`,
		Theme.Colors.TilePurpleTop,
		Theme.Colors.TilePurpleBot,
		"Star",
		"SoftAscend",
		6,
		Color3.fromRGB(246, 238, 255)
	)
end

local function renderUpgradesTab(profile: any)
	renderCombatUpgrades(profile)
	renderPlotUpgrades(profile)
	renderSlotAndAscensionUpgrades(profile)
end

local function updateTabStyles()
	for _, spec in ipairs(TAB_SPECS) do
		local isSelected = activeTab == spec.id
		local btn = tabButtons[spec.id]
		if btn then
			Theme.addGradient(
				btn,
				if isSelected then spec.top else MUTED_TOP,
				if isSelected then spec.bot else MUTED_BOT,
				90
			)
		end
		if isSelected and headerTitle then
			headerTitle.Text = spec.header
		end
	end
end

local function rerender()
	if not latestProfile or not rootFrame or not rootFrame.Visible then
		return
	end
	updateTabStyles()
	clearScroll()
	if activeTab == "Pets" then
		renderPetsTab(latestProfile)
	elseif activeTab == "Eggs" then
		renderEggsTab(latestProfile)
	else
		renderUpgradesTab(latestProfile)
	end
end

local function buildHeaderAndTabs(panel: Frame)
	local _, title = Theme.makeHeaderBanner(
		panel,
		"HUB PROGRESSION",
		Theme.Colors.HubBlueTop,
		Theme.Colors.HubBlueBot,
		function()
			panel.Visible = false
		end
	)
	headerTitle = title

	local tabRow = Instance.new("Frame")
	tabRow.Name = "TabRow"
	tabRow.BackgroundTransparency = 1
	tabRow.Position = UDim2.fromOffset(14, 60)
	tabRow.Size = UDim2.new(1, -28, 0, 44)
	tabRow.Parent = panel
	local tl = Instance.new("UIListLayout")
	tl.FillDirection = Enum.FillDirection.Horizontal
	tl.SortOrder = Enum.SortOrder.LayoutOrder
	tl.Padding = UDim.new(0, 8)
	tl.Parent = tabRow

	for idx, spec in ipairs(TAB_SPECS) do
		local tb = Theme.makeGoldPillButton(
			tabRow,
			"Tab_" .. spec.id,
			spec.label,
			UDim2.fromScale(0.32, 1),
			UDim2.fromOffset(0, 0),
			function()
				activeTab = spec.id
				rerender()
			end,
			spec.top,
			spec.bot
		)
		tb.LayoutOrder = idx
		applyTextConstraint(tb, 10, 14)
		local fx = Instance.new("UIFlexItem")
		fx.FlexMode = Enum.UIFlexMode.Fill
		fx.Parent = tb
		tabButtons[spec.id] = tb
	end
end

local function buildScrollContainer(panel: Frame)
	local sc = Instance.new("ScrollingFrame")
	sc.Name = "Body"
	sc.BackgroundTransparency = 1
	sc.BorderSizePixel = 0
	sc.Position = UDim2.fromOffset(12, 112)
	sc.Size = UDim2.new(1, -24, 1, -122)
	sc.CanvasSize = UDim2.fromOffset(0, 0)
	sc.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sc.ScrollBarThickness = 6
	sc.ScrollBarImageColor3 = Theme.Colors.Ink
	sc.Parent = panel
	Theme.addPadding(sc, 4, 4)
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 10)
	list.Parent = sc
	scrollBody = sc
end

function HubModalsGui.mount()
	local gui = Theme.createScreenGui("BallBrawl_HubModals", 20)
	local panel = Theme.makeCartoonWindow(
		gui,
		"MainPanel",
		UDim2.fromScale(0.92, 0.86),
		UDim2.fromScale(0.5, 0.5),
		16
	)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Visible = false
	local scConstraint = Instance.new("UISizeConstraint")
	scConstraint.MaxSize = Vector2.new(600, 480)
	scConstraint.MinSize = Vector2.new(300, 260)
	scConstraint.Parent = panel
	rootFrame = panel

	buildHeaderAndTabs(panel)
	buildScrollContainer(panel)
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
