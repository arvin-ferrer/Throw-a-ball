--!strict
--[[
	EconomyConfigs.luau
	Canonical Dual-Currency (Coins + Boss Gems), Pet Income, Offline Vault,
	and Soft Ascension formulas aligned with GameIdea_Evolved_GDD.md (v1.1).
]]

export type PetIncomeParams = {
	baseRate: number,
	mutationKey: string,
	starTier: number,
	petLevel: number,
	traitKey: string?,
	ascensionRank: number,
}

local EconomyConfigs = {}

EconomyConfigs.MAX_OFFLINE_SECONDS = 12 * 3600
EconomyConfigs.BASE_OFFLINE_EFFICIENCY = 0.50
EconomyConfigs.LEVEL_BONUS_PER_STEP = 0.12
EconomyConfigs.MAX_PET_LEVEL = 25
EconomyConfigs.ASCENSION_COIN_BONUS = 0.25
EconomyConfigs.ASCENSION_TRAINING_BONUS = 0.05

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

return EconomyConfigs
