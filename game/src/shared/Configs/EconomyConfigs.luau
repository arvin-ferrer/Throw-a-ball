--!strict
--[[
	EconomyConfigs.luau
	Canonical Dual-Currency (Coins + Boss Gems), Pet Income, Offline Vault,
	Training Targets, Ball Tiers, Pedestal Expansion, and Soft Ascension formulas
	aligned with GameIdea_Evolved_GDD.md (v1.1).
]]

export type PetIncomeParams = {
	baseRate: number,
	mutationKey: string,
	starTier: number,
	petLevel: number,
	traitKey: string?,
	ascensionRank: number,
}

export type TrainingTargetTier = {
	id: string,
	displayName: string,
	costCoins: number,
	dmgPerHit: number,
	throwSpeedPerGoldHit: number,
	goldMultiplier: number,
	primaryColor: { number },
	accentColor: { number },
}

export type BallTier = {
	id: string,
	displayName: string,
	costCoins: number,
	damageMult: number,
	projectileSpeed: number,
	primaryColor: { number },
	trailColor: { number },
}

export type PedestalUnlockSpec = {
	index: number,
	tier: number,
	tierName: string,
	costCoins: number,
	costGems: number,
	requiresVipPass: boolean,
}

export type OfflineVaultTier = {
	tier: number,
	efficiency: number,
	costGems: number,
}

export type ActiveSlotUnlock = {
	slot: number,
	requiredLevel: number,
	costGems: number,
}

local EconomyConfigs = {}

EconomyConfigs.MAX_OFFLINE_SECONDS = 12 * 3600
EconomyConfigs.BASE_OFFLINE_EFFICIENCY = 0.50
EconomyConfigs.LEVEL_BONUS_PER_STEP = 0.12
EconomyConfigs.MAX_PET_LEVEL = 25
EconomyConfigs.ASCENSION_COIN_BONUS = 0.25
EconomyConfigs.ASCENSION_TRAINING_BONUS = 0.05
EconomyConfigs.TRAIT_REROLL_GEM_COST = 15
EconomyConfigs.BASE_PLAYER_HP = 100
EconomyConfigs.HP_PER_LEVEL = 25
EconomyConfigs.STARTER_BALL_DAMAGE = 5
EconomyConfigs.STARTER_THROW_SPEED = 1.0

EconomyConfigs.MUTATION_MULTIPLIERS = {
	Normal = 1.0,
	Shiny = 1.5,
	Golden = 2.5,
	Overcharged = 4.0,
	VoidTouched = 6.0,
}

EconomyConfigs.STAR_MULTIPLIERS = {
	[1] = 1.0,
	[2] = 1.75,
	[3] = 3.0,
}

EconomyConfigs.TRAIT_COIN_BONUSES = {
	Greedy = 0.25,
	Tycoon = 0.50,
}

EconomyConfigs.TRAINING_TARGETS = {
	{
		id = "WoodenDummy",
		displayName = "Wooden Dummy",
		costCoins = 0,
		dmgPerHit = 1,
		throwSpeedPerGoldHit = 0.05,
		goldMultiplier = 2,
		primaryColor = { 176, 128, 78 },
		accentColor = { 235, 76, 66 },
	},
	{
		id = "IronBullseye",
		displayName = "Iron Bullseye",
		costCoins = 75,
		dmgPerHit = 4,
		throwSpeedPerGoldHit = 0.08,
		goldMultiplier = 2,
		primaryColor = { 148, 163, 184 },
		accentColor = { 56, 189, 248 },
	},
	{
		id = "CrystalDrone",
		displayName = "Crystal Drone",
		costCoins = 1200,
		dmgPerHit = 22,
		throwSpeedPerGoldHit = 0.12,
		goldMultiplier = 2,
		primaryColor = { 56, 217, 245 },
		accentColor = { 167, 139, 250 },
	},
	{
		id = "ObsidianCore",
		displayName = "Obsidian Core",
		costCoins = 18000,
		dmgPerHit = 120,
		throwSpeedPerGoldHit = 0.16,
		goldMultiplier = 2,
		primaryColor = { 42, 34, 52 },
		accentColor = { 255, 108, 42 },
	},
} :: { TrainingTargetTier }

EconomyConfigs.BALL_TIERS = {
	{
		id = "RubberBall",
		displayName = "Rubber Ball",
		costCoins = 0,
		damageMult = 1.0,
		projectileSpeed = 115,
		primaryColor = { 239, 68, 68 },
		trailColor = { 255, 160, 122 },
	},
	{
		id = "IronSphere",
		displayName = "Iron Sphere",
		costCoins = 350,
		damageMult = 1.45,
		projectileSpeed = 130,
		primaryColor = { 148, 163, 184 },
		trailColor = { 226, 232, 240 },
	},
	{
		id = "FrostOrb",
		displayName = "Frost Orb",
		costCoins = 3200,
		damageMult = 2.2,
		projectileSpeed = 145,
		primaryColor = { 96, 212, 255 },
		trailColor = { 186, 242, 255 },
	},
	{
		id = "MagmaCore",
		displayName = "Magma Core",
		costCoins = 28000,
		damageMult = 3.5,
		projectileSpeed = 160,
		primaryColor = { 255, 94, 26 },
		trailColor = { 255, 196, 54 },
	},
	{
		id = "NovaSphere",
		displayName = "Nova Sphere",
		costCoins = 220000,
		damageMult = 5.5,
		projectileSpeed = 178,
		primaryColor = { 168, 85, 247 },
		trailColor = { 94, 234, 212 },
	},
} :: { BallTier }

EconomyConfigs.PEDESTAL_UNLOCKS = {
	{
		index = 1,
		tier = 1,
		tierName = "Starter",
		costCoins = 0,
		costGems = 0,
		requiresVipPass = false,
	},
	{
		index = 2,
		tier = 1,
		tierName = "Starter",
		costCoins = 0,
		costGems = 0,
		requiresVipPass = false,
	},
	{
		index = 3,
		tier = 1,
		tierName = "Starter",
		costCoins = 0,
		costGems = 0,
		requiresVipPass = false,
	},
	{
		index = 4,
		tier = 1,
		tierName = "Starter",
		costCoins = 0,
		costGems = 0,
		requiresVipPass = false,
	},
	{
		index = 5,
		tier = 2,
		tierName = "Courtyard",
		costCoins = 600,
		costGems = 0,
		requiresVipPass = false,
	},
	{
		index = 6,
		tier = 2,
		tierName = "Courtyard",
		costCoins = 2200,
		costGems = 0,
		requiresVipPass = false,
	},
	{
		index = 7,
		tier = 2,
		tierName = "Courtyard",
		costCoins = 7500,
		costGems = 0,
		requiresVipPass = false,
	},
	{
		index = 8,
		tier = 2,
		tierName = "Courtyard",
		costCoins = 22000,
		costGems = 0,
		requiresVipPass = false,
	},
	{
		index = 9,
		tier = 3,
		tierName = "Balcony",
		costCoins = 65000,
		costGems = 30,
		requiresVipPass = false,
	},
	{
		index = 10,
		tier = 3,
		tierName = "Balcony",
		costCoins = 160000,
		costGems = 50,
		requiresVipPass = false,
	},
	{
		index = 11,
		tier = 3,
		tierName = "Balcony",
		costCoins = 380000,
		costGems = 75,
		requiresVipPass = false,
	},
	{
		index = 12,
		tier = 3,
		tierName = "Balcony",
		costCoins = 850000,
		costGems = 110,
		requiresVipPass = false,
	},
	{
		index = 13,
		tier = 4,
		tierName = "VIPGamePass",
		costCoins = 0,
		costGems = 0,
		requiresVipPass = true,
	},
	{
		index = 14,
		tier = 4,
		tierName = "VIPGamePass",
		costCoins = 0,
		costGems = 0,
		requiresVipPass = true,
	},
} :: { PedestalUnlockSpec }

EconomyConfigs.OFFLINE_VAULT_TIERS = {
	{ tier = 1, efficiency = 0.50, costGems = 0 },
	{ tier = 2, efficiency = 0.75, costGems = 40 },
	{ tier = 3, efficiency = 1.00, costGems = 120 },
} :: { OfflineVaultTier }

EconomyConfigs.ACTIVE_SLOT_UNLOCKS = {
	{ slot = 1, requiredLevel = 1, costGems = 0 },
	{ slot = 2, requiredLevel = 10, costGems = 35 },
	{ slot = 3, requiredLevel = 25, costGems = 120 },
} :: { ActiveSlotUnlock }

EconomyConfigs.GEM_CRAFT_EGG_COSTS = {
	EmeraldMeadow = 25,
	FrostbiteCavern = 60,
	MoltenCaldera = 140,
}

function EconomyConfigs.computePetCoinsPerSec(params: PetIncomeParams): number
	local mutationMult = EconomyConfigs.MUTATION_MULTIPLIERS[params.mutationKey] or 1.0
	local starMult = EconomyConfigs.STAR_MULTIPLIERS[params.starTier] or 1.0
	local clampedLevel = math.clamp(math.floor(params.petLevel), 1, EconomyConfigs.MAX_PET_LEVEL)
	local levelMult = 1 + EconomyConfigs.LEVEL_BONUS_PER_STEP * (clampedLevel - 1)
	local traitBonus = if params.traitKey
		then (EconomyConfigs.TRAIT_COIN_BONUSES[params.traitKey] or 0)
		else 0
	local traitMult = 1 + traitBonus
	local ascensionMult = 1
		+ math.max(0, math.floor(params.ascensionRank)) * EconomyConfigs.ASCENSION_COIN_BONUS
	return math.max(0, params.baseRate)
		* mutationMult
		* starMult
		* levelMult
		* traitMult
		* ascensionMult
end

function EconomyConfigs.computeOfflineCoins(
	coinsPerSec: number,
	elapsedSeconds: number,
	offlineEfficiency: number?
): number
	local boundedSeconds = math.clamp(elapsedSeconds, 0, EconomyConfigs.MAX_OFFLINE_SECONDS)
	local efficiency = math.clamp(offlineEfficiency or EconomyConfigs.BASE_OFFLINE_EFFICIENCY, 0, 1)
	return math.floor(math.max(0, coinsPerSec) * boundedSeconds * efficiency)
end

function EconomyConfigs.getPetLevelUpCost(currentLevel: number, baseRate: number): number
	local lvl = math.clamp(math.floor(currentLevel), 1, EconomyConfigs.MAX_PET_LEVEL - 1)
	local base = math.max(5, baseRate)
	return math.floor(base * 18 * (1.28 ^ (lvl - 1)))
end

function EconomyConfigs.getAscensionCoinThreshold(currentRank: number): number
	local rank = math.max(0, math.floor(currentRank))
	return math.floor(100000 * (3.2 ^ rank))
end

function EconomyConfigs.getAscensionCoinMult(rank: number): number
	return 1 + math.max(0, math.floor(rank)) * EconomyConfigs.ASCENSION_COIN_BONUS
end

function EconomyConfigs.getAscensionTrainingMult(rank: number): number
	return 1 + math.max(0, math.floor(rank)) * EconomyConfigs.ASCENSION_TRAINING_BONUS
end

function EconomyConfigs.getPlayerMaxHP(level: number): number
	local lvl = math.max(1, math.floor(level))
	return EconomyConfigs.BASE_PLAYER_HP + (lvl - 1) * EconomyConfigs.HP_PER_LEVEL
end

function EconomyConfigs.getExpForNextLevel(level: number): number
	local lvl = math.max(1, math.floor(level))
	return math.floor(60 * (1.22 ^ (lvl - 1)))
end

function EconomyConfigs.getTargetTierById(id: string): TrainingTargetTier?
	for _, tier in ipairs(EconomyConfigs.TRAINING_TARGETS) do
		if tier.id == id then
			return tier
		end
	end
	return nil
end

function EconomyConfigs.getTargetTierIndex(id: string): number
	for idx, tier in ipairs(EconomyConfigs.TRAINING_TARGETS) do
		if tier.id == id then
			return idx
		end
	end
	return 1
end

function EconomyConfigs.getBallTierById(id: string): BallTier?
	for _, tier in ipairs(EconomyConfigs.BALL_TIERS) do
		if tier.id == id then
			return tier
		end
	end
	return nil
end

function EconomyConfigs.getBallTierIndex(id: string): number
	for idx, tier in ipairs(EconomyConfigs.BALL_TIERS) do
		if tier.id == id then
			return idx
		end
	end
	return 1
end

function EconomyConfigs.getOfflineVaultEfficiency(vaultTier: number): number
	local clamped = math.clamp(math.floor(vaultTier), 1, #EconomyConfigs.OFFLINE_VAULT_TIERS)
	return EconomyConfigs.OFFLINE_VAULT_TIERS[clamped].efficiency
end

function EconomyConfigs.getPetSellValue(
	baseRate: number,
	starTier: number,
	petLevel: number
): number
	local starMult = EconomyConfigs.STAR_MULTIPLIERS[starTier] or 1.0
	return math.floor(math.max(5, baseRate) * 20 * starMult * (1 + 0.1 * (petLevel - 1)))
end

return EconomyConfigs
