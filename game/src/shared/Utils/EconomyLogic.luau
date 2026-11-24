--!strict
--[[
	EconomyLogic.luau
	Pure atomic player-profile economy mutations (Lune & Roblox Server safe):
	- Starter Egg Minute-0 onboarding
	- Cash Pad accrual & <=12h offline cap (50%->100% + Overclocked + Tycoon plot bonus)
	- Pet Leveling (Lv 1-25), 3-to-1 Duplicate Star Fusion, Gem Trait Rerolls
	- Active Combat Followers (1-3 slots without pausing pedestal Coin income)
	- Pedestal Expansion (4->12 + VIP 13-14), Target/Ball Tiers, Gem-Crafted Eggs
	- Soft Ascension (resets Coins ONLY; keeps 100% pets, levels, damage, gems)
]]

local req: any = require
local scriptRef: any = script
local isRoblox = type(scriptRef) == "userdata"
local EconomyConfigs = if isRoblox
	then req(scriptRef.Parent.Parent.Configs.EconomyConfigs)
	else req("../Configs/EconomyConfigs")
local PetConfigs = if isRoblox
	then req(scriptRef.Parent.Parent.Configs.PetConfigs)
	else req("../Configs/PetConfigs")
local TraitConfigs = if isRoblox
	then req(scriptRef.Parent.Parent.Configs.TraitConfigs)
	else req("../Configs/TraitConfigs")
local EggConfigs = if isRoblox
	then req(scriptRef.Parent.Parent.Configs.EggConfigs)
	else req("../Configs/EggConfigs")
local MathUtil = if isRoblox then req(scriptRef.Parent.MathUtil) else req("./MathUtil")

export type OwnedPet = {
	uid: string,
	speciesId: string,
	mutationKey: string,
	starTier: number,
	level: number,
	traitKey: string?,
	pedestalIndex: number?,
}

export type PlayerProfile = {
	schemaVersion: number,
	coins: number,
	bossGems: number,
	ballDamage: number,
	throwSpeed: number,
	level: number,
	exp: number,
	ascensionRank: number,
	targetTierId: string,
	ballTierId: string,
	pedestalsUnlocked: number,
	offlineVaultTier: number,
	activeSlotsUnlocked: number,
	starterEggHatched: boolean,
	eggs: { [string]: number },
	pets: { OwnedPet },
	activeFollowerUids: { string },
	padStoredCoins: { [number]: number },
	codexUnlocked: { [string]: boolean },
	ownedCosmetics: { [string]: boolean },
	equippedBallSkin: string?,
	purchaseIds: { string },
	processedPurchases: { [string]: boolean }?,
	lastLogoutTime: number,
	nextPetSeq: number,
}

export type TxResult = {
	ok: boolean,
	reason: string?,
	data: { [string]: any }?,
}

local EconomyLogic = {}

EconomyLogic.CURRENT_SCHEMA_VERSION = 1

local function isValidBalance(value: any, cost: number): boolean
	return MathUtil.isFinite(value)
		and MathUtil.isFinite(cost)
		and cost >= 0
		and (value :: number) >= 0
		and (value :: number) >= cost
end

local function isValidIntegerSlot(value: any): boolean
	return MathUtil.isFinite(value) and math.floor(value :: number) == (value :: number)
end

function EconomyLogic.createDefaultProfile(now: number): PlayerProfile
	return {
		schemaVersion = EconomyLogic.CURRENT_SCHEMA_VERSION,
		coins = 0,
		bossGems = 0,
		ballDamage = EconomyConfigs.STARTER_BALL_DAMAGE,
		throwSpeed = EconomyConfigs.STARTER_THROW_SPEED,
		level = 1,
		exp = 0,
		ascensionRank = 0,
		targetTierId = "WoodenDummy",
		ballTierId = "RubberBall",
		pedestalsUnlocked = 4,
		offlineVaultTier = 1,
		activeSlotsUnlocked = 1,
		starterEggHatched = false,
		eggs = { StarterEgg = 1 },
		pets = {},
		activeFollowerUids = {},
		padStoredCoins = {},
		codexUnlocked = {},
		ownedCosmetics = {},
		equippedBallSkin = nil,
		purchaseIds = {},
		processedPurchases = {},
		lastLogoutTime = now,
		nextPetSeq = 1,
	}
end

function EconomyLogic.findPetByUid(profile: PlayerProfile, uid: string): (OwnedPet?, number?)
	for idx, pet in ipairs(profile.pets) do
		if pet.uid == uid then
			return pet, idx
		end
	end
	return nil, nil
end

export type OwnedPetSnapshot = {
	uid: string,
	speciesId: string,
	mutationKey: string,
	starTier: number,
	level: number,
	traitKey: string?,
}

function EconomyLogic.getActivePets(profile: PlayerProfile): { OwnedPetSnapshot }
	local out: { OwnedPetSnapshot } = {}
	for _, uid in ipairs(profile.activeFollowerUids) do
		local pet = EconomyLogic.findPetByUid(profile, uid)
		if pet then
			table.insert(out, {
				uid = pet.uid,
				speciesId = pet.speciesId,
				mutationKey = pet.mutationKey,
				starTier = pet.starTier,
				level = pet.level,
				traitKey = pet.traitKey,
			})
		end
	end
	return out
end

function EconomyLogic.getGlobalPlotBonus(profile: PlayerProfile): number
	local bonus = 0
	for _, pet in ipairs(profile.pets) do
		if pet.pedestalIndex ~= nil and pet.traitKey == "Tycoon" then
			bonus += 0.10
		end
	end
	return bonus
end

function EconomyLogic.computePlacedPetRate(
	profile: PlayerProfile,
	pet: OwnedPet,
	hasDoubleCoinsPass: boolean
): number
	local species = PetConfigs.getSpecies(pet.speciesId)
	if not species then
		return 0
	end
	local base = EconomyConfigs.computePetCoinsPerSec({
		baseRate = species.baseRate,
		mutationKey = pet.mutationKey,
		starTier = pet.starTier,
		petLevel = pet.level,
		traitKey = pet.traitKey,
		ascensionRank = profile.ascensionRank,
	})
	local plotMult = 1 + EconomyLogic.getGlobalPlotBonus(profile)
	local passMult = if hasDoubleCoinsPass then 2.0 else 1.0
	return base * plotMult * passMult
end

function EconomyLogic.accruePedestalCoins(
	profile: PlayerProfile,
	dtSeconds: number,
	isOffline: boolean,
	hasDoubleCoinsPass: boolean
): number
	if not MathUtil.isPositiveFinite(dtSeconds) then
		return 0
	end
	local baseEff = EconomyConfigs.getOfflineVaultEfficiency(profile.offlineVaultTier)
	local totalAdded = 0
	for _, pet in ipairs(profile.pets) do
		local pedIdx = pet.pedestalIndex
		if pedIdx ~= nil then
			local rate = EconomyLogic.computePlacedPetRate(profile, pet, hasDoubleCoinsPass)
			local added = 0
			if isOffline then
				local trait = TraitConfigs.getTrait(pet.traitKey)
				local eff = math.clamp(baseEff + (if trait then trait.offlineBonus else 0), 0, 1)
				added = EconomyConfigs.computeOfflineCoins(rate, dtSeconds, eff)
			else
				added = rate * dtSeconds
			end
			if added > 0 then
				profile.padStoredCoins[pedIdx] = (profile.padStoredCoins[pedIdx] or 0) + added
				totalAdded += added
			end
		end
	end
	return totalAdded
end

function EconomyLogic.collectCashPad(profile: PlayerProfile, pedestalIndex: number): number
	if not isValidIntegerSlot(pedestalIndex) or not isValidBalance(profile.coins, 0) then
		return 0
	end
	local rawStored = profile.padStoredCoins[pedestalIndex]
	if not MathUtil.isPositiveFinite(rawStored) then
		return 0
	end
	local stored = math.floor(rawStored :: number)
	if stored <= 0 then
		return 0
	end
	local nextCoins = (profile.coins :: number) + stored
	if not MathUtil.isFinite(nextCoins) then
		return 0
	end
	profile.padStoredCoins[pedestalIndex] = (rawStored :: number) - stored
	profile.coins = nextCoins
	return stored
end

local function validateHatchArgs(
	profile: PlayerProfile,
	eggId: string,
	pedestalIndex: number,
	hasVipPass: boolean,
	petRollUnit: number,
	mutRollUnit: number
): string?
	if
		type(eggId) ~= "string"
		or not MathUtil.isFinite(petRollUnit)
		or not MathUtil.isFinite(mutRollUnit)
	then
		return "InvalidArgs"
	end
	if not EggConfigs.getEgg(eggId) then
		return "UnknownEgg"
	end
	if (profile.eggs[eggId] or 0) < 1 then
		return "NoEggInInventory"
	end
	if not isValidIntegerSlot(pedestalIndex) then
		return "InvalidPedestal"
	end
	local maxUnlocked = if hasVipPass then 14 else profile.pedestalsUnlocked
	if pedestalIndex < 1 or pedestalIndex > maxUnlocked then
		return "PedestalLocked"
	end
	if pedestalIndex > profile.pedestalsUnlocked and pedestalIndex <= 12 then
		return "PedestalLocked"
	end
	for _, pet in ipairs(profile.pets) do
		if pet.pedestalIndex == pedestalIndex then
			return "PedestalOccupied"
		end
	end
	return nil
end

function EconomyLogic.hatchEggOnPedestal(
	profile: PlayerProfile,
	eggId: string,
	pedestalIndex: number,
	hasVipPass: boolean,
	petRollUnit: number,
	mutRollUnit: number
): TxResult
	local errReason =
		validateHatchArgs(profile, eggId, pedestalIndex, hasVipPass, petRollUnit, mutRollUnit)
	if errReason then
		return { ok = false, reason = errReason }
	end
	local speciesId, mutationKey = EggConfigs.rollHatch(eggId, petRollUnit, mutRollUnit)
	profile.eggs[eggId] = (profile.eggs[eggId] or 1) - 1
	if profile.eggs[eggId] <= 0 then
		profile.eggs[eggId] = nil
	end
	if eggId == "StarterEgg" then
		profile.starterEggHatched = true
	end
	local uid = `pet_{profile.nextPetSeq}`
	profile.nextPetSeq += 1
	local newPet: OwnedPet = {
		uid = uid,
		speciesId = speciesId,
		mutationKey = mutationKey,
		starTier = 1,
		level = 1,
		traitKey = nil,
		pedestalIndex = pedestalIndex,
	}
	table.insert(profile.pets, newPet)
	profile.codexUnlocked[speciesId] = true
	if #profile.activeFollowerUids < profile.activeSlotsUnlocked then
		table.insert(profile.activeFollowerUids, uid)
	end
	return { ok = true, data = { pet = newPet } }
end

function EconomyLogic.levelUpPet(profile: PlayerProfile, petUid: string): TxResult
	local pet = EconomyLogic.findPetByUid(profile, petUid)
	if not pet then
		return { ok = false, reason = "PetNotFound" }
	end
	if pet.level >= EconomyConfigs.MAX_PET_LEVEL then
		return { ok = false, reason = "MaxLevelReached" }
	end
	local species = PetConfigs.getSpecies(pet.speciesId)
	if not species then
		return { ok = false, reason = "UnknownSpecies" }
	end
	local cost = EconomyConfigs.getPetLevelUpCost(pet.level, species.baseRate)
	if not isValidBalance(profile.coins, cost) then
		return { ok = false, reason = "InsufficientCoins" }
	end
	profile.coins -= cost
	pet.level += 1
	return { ok = true, data = { newLevel = pet.level, cost = cost } }
end

-- Atomic 3-to-1 Duplicate Star Fusion (1★ -> 2★ -> 3★)
function EconomyLogic.fusePets(profile: PlayerProfile, uids: { string }): TxResult
	if type(uids) ~= "table" or #uids ~= 3 then
		return { ok = false, reason = "MustProvideThreePets" }
	end
	for i = 1, 3 do
		if type(uids[i]) ~= "string" then
			return { ok = false, reason = "InvalidPetUid" }
		end
	end
	if uids[1] == uids[2] or uids[1] == uids[3] or uids[2] == uids[3] then
		return { ok = false, reason = "DuplicateUidInRequest" }
	end
	local found: { OwnedPet } = {}
	for _, uid in ipairs(uids) do
		local pet = EconomyLogic.findPetByUid(profile, uid)
		if not pet then
			return { ok = false, reason = "PetNotFound" }
		end
		table.insert(found, pet)
	end
	local primary = found[1]
	if primary.starTier >= 3 then
		return { ok = false, reason = "AlreadyMaxStar" }
	end
	for i = 2, 3 do
		if found[i].speciesId ~= primary.speciesId or found[i].starTier ~= primary.starTier then
			return { ok = false, reason = "MismatchedSpeciesOrStar" }
		end
	end
	-- Atomic commit: upgrade primary, remove sacrifices, clean up activeFollowerUids
	primary.starTier += 1
	local removeSet: { [string]: boolean } = { [uids[2]] = true, [uids[3]] = true }
	local remainingPets: { OwnedPet } = {}
	for _, pet in ipairs(profile.pets) do
		if not removeSet[pet.uid] then
			table.insert(remainingPets, pet)
		end
	end
	profile.pets = remainingPets
	local remainingActive: { string } = {}
	for _, activeUid in ipairs(profile.activeFollowerUids) do
		if not removeSet[activeUid] then
			table.insert(remainingActive, activeUid)
		end
	end
	profile.activeFollowerUids = remainingActive
	return { ok = true, data = { upgradedPet = primary } }
end

function EconomyLogic.rerollPetTrait(
	profile: PlayerProfile,
	petUid: string,
	rollUnit: number
): TxResult
	if type(petUid) ~= "string" or not MathUtil.isFinite(rollUnit) then
		return { ok = false, reason = "InvalidArgs" }
	end
	local pet = EconomyLogic.findPetByUid(profile, petUid)
	if not pet then
		return { ok = false, reason = "PetNotFound" }
	end
	local cost = EconomyConfigs.TRAIT_REROLL_GEM_COST
	if not isValidBalance(profile.bossGems, cost) then
		return { ok = false, reason = "InsufficientGems" }
	end
	profile.bossGems -= cost
	local rolled = TraitConfigs.rollTrait(rollUnit)
	pet.traitKey = rolled.id
	return { ok = true, data = { traitId = rolled.id, costGems = cost } }
end

function EconomyLogic.toggleActiveFollower(profile: PlayerProfile, petUid: string): TxResult
	local pet = EconomyLogic.findPetByUid(profile, petUid)
	if not pet then
		return { ok = false, reason = "PetNotFound" }
	end
	for idx, activeUid in ipairs(profile.activeFollowerUids) do
		if activeUid == petUid then
			table.remove(profile.activeFollowerUids, idx)
			return { ok = true, data = { equipped = false } }
		end
	end
	if #profile.activeFollowerUids >= profile.activeSlotsUnlocked then
		return { ok = false, reason = "ActiveSlotsFull" }
	end
	table.insert(profile.activeFollowerUids, petUid)
	return { ok = true, data = { equipped = true } }
end

function EconomyLogic.placeOrMovePet(
	profile: PlayerProfile,
	petUid: string,
	pedestalIndex: number?,
	hasVipPass: boolean
): TxResult
	local pet = EconomyLogic.findPetByUid(profile, petUid)
	if not pet then
		return { ok = false, reason = "PetNotFound" }
	end
	if pedestalIndex == nil then
		pet.pedestalIndex = nil
		return { ok = true, data = { pedestalIndex = nil } }
	end
	if not isValidIntegerSlot(pedestalIndex) then
		return { ok = false, reason = "InvalidPedestal" }
	end
	local isVipSlot = pedestalIndex == 13 or pedestalIndex == 14
	if pedestalIndex < 1 or pedestalIndex > 14 then
		return { ok = false, reason = "InvalidPedestal" }
	end
	if isVipSlot and not hasVipPass then
		return { ok = false, reason = "RequiresVipPass" }
	end
	if not isVipSlot and pedestalIndex > profile.pedestalsUnlocked then
		return { ok = false, reason = "PedestalLocked" }
	end
	for _, other in ipairs(profile.pets) do
		if other.uid ~= petUid and other.pedestalIndex == pedestalIndex then
			other.pedestalIndex = pet.pedestalIndex
			break
		end
	end
	pet.pedestalIndex = pedestalIndex
	return { ok = true, data = { pedestalIndex = pedestalIndex } }
end

function EconomyLogic.sellPet(profile: PlayerProfile, petUid: string): TxResult
	if not isValidBalance(profile.coins, 0) then
		return { ok = false, reason = "InvalidBalance" }
	end
	local pet, idx = EconomyLogic.findPetByUid(profile, petUid)
	if not pet or not idx then
		return { ok = false, reason = "PetNotFound" }
	end
	if #profile.pets <= 1 then
		return { ok = false, reason = "CannotSellLastPet" }
	end
	local species = PetConfigs.getSpecies(pet.speciesId)
	local baseRate = if species then species.baseRate else 5
	local value = EconomyConfigs.getPetSellValue(baseRate, pet.starTier, pet.level)
	local nextCoins = (profile.coins :: number) + value
	if not MathUtil.isFinite(nextCoins) then
		return { ok = false, reason = "BalanceOverflow" }
	end
	table.remove(profile.pets, idx)
	for i, aUid in ipairs(profile.activeFollowerUids) do
		if aUid == petUid then
			table.remove(profile.activeFollowerUids, i)
			break
		end
	end
	profile.coins = nextCoins
	return { ok = true, data = { coinsGained = value } }
end

function EconomyLogic.buyNextTargetTier(profile: PlayerProfile): TxResult
	local curIdx = EconomyConfigs.getTargetTierIndex(profile.targetTierId)
	local nextTier = EconomyConfigs.TRAINING_TARGETS[curIdx + 1]
	if not nextTier then
		return { ok = false, reason = "MaxTargetTier" }
	end
	if not isValidBalance(profile.coins, nextTier.costCoins) then
		return { ok = false, reason = "InsufficientCoins" }
	end
	profile.coins -= nextTier.costCoins
	profile.targetTierId = nextTier.id
	return { ok = true, data = { targetTierId = nextTier.id } }
end

function EconomyLogic.buyNextBallTier(profile: PlayerProfile): TxResult
	local curIdx = EconomyConfigs.getBallTierIndex(profile.ballTierId)
	local nextTier = EconomyConfigs.BALL_TIERS[curIdx + 1]
	if not nextTier then
		return { ok = false, reason = "MaxBallTier" }
	end
	if not isValidBalance(profile.coins, nextTier.costCoins) then
		return { ok = false, reason = "InsufficientCoins" }
	end
	profile.coins -= nextTier.costCoins
	profile.ballTierId = nextTier.id
	return { ok = true, data = { ballTierId = nextTier.id } }
end

function EconomyLogic.unlockNextPedestal(profile: PlayerProfile): TxResult
	if profile.pedestalsUnlocked >= 12 then
		return { ok = false, reason = "MaxCoinGemPedestals" }
	end
	local spec = EconomyConfigs.PEDESTAL_UNLOCKS[profile.pedestalsUnlocked + 1]
	if not spec or spec.requiresVipPass then
		return { ok = false, reason = "RequiresVipPass" }
	end
	if not isValidBalance(profile.coins, spec.costCoins) then
		return { ok = false, reason = "InsufficientCoins" }
	end
	if not isValidBalance(profile.bossGems, spec.costGems) then
		return { ok = false, reason = "InsufficientGems" }
	end
	profile.coins -= spec.costCoins
	profile.bossGems -= spec.costGems
	profile.pedestalsUnlocked = spec.index
	return { ok = true, data = { pedestalsUnlocked = profile.pedestalsUnlocked } }
end

function EconomyLogic.upgradeOfflineVault(profile: PlayerProfile): TxResult
	local nextTier = EconomyConfigs.OFFLINE_VAULT_TIERS[profile.offlineVaultTier + 1]
	if not nextTier then
		return { ok = false, reason = "MaxVaultTier" }
	end
	if not isValidBalance(profile.bossGems, nextTier.costGems) then
		return { ok = false, reason = "InsufficientGems" }
	end
	profile.bossGems -= nextTier.costGems
	profile.offlineVaultTier = nextTier.tier
	return { ok = true, data = { vaultTier = nextTier.tier, efficiency = nextTier.efficiency } }
end

function EconomyLogic.unlockNextActiveSlot(profile: PlayerProfile): TxResult
	local nextSlot = EconomyConfigs.ACTIVE_SLOT_UNLOCKS[profile.activeSlotsUnlocked + 1]
	if not nextSlot then
		return { ok = false, reason = "MaxActiveSlots" }
	end
	if not MathUtil.isFinite(profile.level) or profile.level < nextSlot.requiredLevel then
		return { ok = false, reason = "LevelTooLow" }
	end
	if not isValidBalance(profile.bossGems, nextSlot.costGems) then
		return { ok = false, reason = "InsufficientGems" }
	end
	profile.bossGems -= nextSlot.costGems
	profile.activeSlotsUnlocked = nextSlot.slot
	return { ok = true, data = { activeSlotsUnlocked = nextSlot.slot } }
end

function EconomyLogic.craftStandardBiomeEgg(profile: PlayerProfile, biomeId: string): TxResult
	if type(biomeId) ~= "string" then
		return { ok = false, reason = "InvalidBiome" }
	end
	local costGems = EconomyConfigs.GEM_CRAFT_EGG_COSTS[biomeId]
	if not costGems then
		return { ok = false, reason = "InvalidBiome" }
	end
	if not isValidBalance(profile.bossGems, costGems) then
		return { ok = false, reason = "InsufficientGems" }
	end
	local eggId = biomeId .. "_BossEgg"
	if not EggConfigs.getEgg(eggId) then
		return { ok = false, reason = "UnknownEgg" }
	end
	profile.bossGems -= costGems
	profile.eggs[eggId] = (profile.eggs[eggId] or 0) + 1
	return { ok = true, data = { eggId = eggId, costGems = costGems } }
end

-- Soft Ascension: Resets Coins ONLY — keeps 100% pets, levels, stars, traits, damage, level, ball tiers & gems!
function EconomyLogic.performSoftAscension(profile: PlayerProfile): TxResult
	local threshold = EconomyConfigs.getAscensionCoinThreshold(profile.ascensionRank)
	if not isValidBalance(profile.coins, threshold) then
		return { ok = false, reason = "BelowAscensionThreshold" }
	end
	profile.coins = 0
	profile.padStoredCoins = {}
	profile.ascensionRank += 1
	return {
		ok = true,
		data = {
			ascensionRank = profile.ascensionRank,
			coinMult = EconomyConfigs.getAscensionCoinMult(profile.ascensionRank),
			trainingMult = EconomyConfigs.getAscensionTrainingMult(profile.ascensionRank),
		},
	}
end

function EconomyLogic.addExp(profile: PlayerProfile, amount: number): number
	if not MathUtil.isPositiveFinite(amount) or not isValidBalance(profile.exp, 0) then
		return 0
	end
	profile.exp += math.floor(amount)
	local levelsGained = 0
	while profile.exp >= EconomyConfigs.getExpForNextLevel(profile.level) do
		profile.exp -= EconomyConfigs.getExpForNextLevel(profile.level)
		profile.level += 1
		levelsGained += 1
	end
	return levelsGained
end

return EconomyLogic
