--!strict
-- Sources refer to docs/GameIdea_Evolved_GDD.md v1.1. Prices, storage cap,
-- and hatch weights are provisional tuning.

-- selene: allow(incorrect_standard_library_use)
local EconomyConfigs = require("./EconomyConfigs")

export type PetSpecies = {
	displayName: string,
	baseCoinsPerSec: number,
	activePerk: string,
}

export type SpeciesWeight = { petId: string, percent: number }
export type HatchPools = { standard: { SpeciesWeight }, overcharged: { SpeciesWeight } }

local PetConfigs = {}

local function species(name: string, rate: number, perk: string): PetSpecies
	return table.freeze({ displayName = name, baseCoinsPerSec = rate, activePerk = perk })
end

-- §2.2, §8.3, §8.4, and §9. Rates are before level, star, trait and mutation bonuses.
local speciesById: { [string]: PetSpecies } = {
	TrainingPup = species("Training Pup", 5, "TrainingBoost"),
	PebbleCub = species("Pebble Cub", 12, "HeavyKnockback"),
	DewSprite = species("Dew Sprite", 18, "VampiricLeech"),
	ThornStag = species("Thorn Stag", 30, "CritSurge"),
	GolemHeart = species("Golem Heart", 65, "ShockwaveSplash"),
	SnowFox = species("Snow Fox", 75, "FrostSlow"),
	ShardOwl = species("Shard Owl", 115, "ChainRicochet"),
	PermafrostBear = species("Permafrost Bear", 190, "ShieldOnThrow"),
	CryoTitan = species("Cryo Titan", 420, "DeepFreeze"),
	AshLizard = species("Ash Lizard", 450, "EmberBurn"),
	-- GDD §9: Cinder Imps and Magma Hounds are Caldera MOBS; these are the Caldera pets.
	PyroHawk = species("Pyro Hawk", 680, "SpeedBurn"),
	LavaRhino = species("Lava Rhino", 1_100, "KnockbackBurn"),
	InfernoDrake = species("Inferno Drake", 2_500, "AoEFireball"),
}
PetConfigs.Species = table.freeze(speciesById)
PetConfigs.STARTER_PET_ID = "TrainingPup"
PetConfigs.STARTER_TRAINING_GAIN_BONUS = 0.05

-- §4, §7.2, and §9. Standard boss and crafted eggs share the biome's standard species pool.
local function pools(common: string, uncommon: string, rare: string, mythic: string): HatchPools
	return table.freeze({
		standard = table.freeze({
			table.freeze({ petId = common, percent = 55 }),
			table.freeze({ petId = uncommon, percent = 30 }),
			table.freeze({ petId = rare, percent = 14 }),
			table.freeze({ petId = mythic, percent = 1 }),
		}),
		overcharged = table.freeze({
			table.freeze({ petId = rare, percent = 90 }),
			table.freeze({ petId = mythic, percent = 10 }),
		}),
	})
end

local hatchPoolsByBiome: { [string]: HatchPools } = {
	EmeraldMeadow = pools("PebbleCub", "DewSprite", "ThornStag", "GolemHeart"),
	FrostbiteCavern = pools("SnowFox", "ShardOwl", "PermafrostBear", "CryoTitan"),
	MoltenCaldera = pools("AshLizard", "PyroHawk", "LavaRhino", "InfernoDrake"),
}
PetConfigs.HatchPoolsByBiome = table.freeze(hatchPoolsByBiome)

-- §8.4 and §8.6. Standard mutation odds come from ShopConfigs via EconomyLedger.
PetConfigs.OverchargedMutationOdds = table.freeze({
	table.freeze({ mutation = "Normal", percent = 15 }),
	table.freeze({ mutation = "Shiny", percent = 35 }),
	table.freeze({ mutation = "Golden", percent = 25 }),
	table.freeze({ mutation = "Overcharged", percent = 22 }),
	table.freeze({ mutation = "VoidTouched", percent = 3 }),
})

-- §8.2 and §8.5. Tycoon adds one plot-wide bonus when at least one Tycoon is placed.
PetConfigs.CASH_PAD_CAP = 1_000_000
PetConfigs.TYCOON_PLOT_COIN_BONUS = 0.10
PetConfigs.OVERCLOCKED_OFFLINE_BONUS = 0.20
PetConfigs.TRAIT_REROLL_COST_GEMS = 5
PetConfigs.TraitOdds = table.freeze({
	table.freeze({ trait = "Greedy", percent = 30 }),
	table.freeze({ trait = "Swift", percent = 25 }),
	table.freeze({ trait = "Brawler", percent = 20 }),
	table.freeze({ trait = "Overclocked", percent = 15 }),
	table.freeze({ trait = "Tycoon", percent = 10 }),
})

-- §8.5. The price uses the current level. No upgrade is offered at level 25.
PetConfigs.MAX_PET_LEVEL = EconomyConfigs.MAX_PET_LEVEL
PetConfigs.MAX_STARS = 3
PetConfigs.PERK_BONUS_BY_STAR = table.freeze({ 0, 0.15, 0.30 })

function PetConfigs.getLevelUpCoinCost(currentLevel: number): number?
	if currentLevel < 1 or currentLevel >= PetConfigs.MAX_PET_LEVEL or currentLevel % 1 ~= 0 then
		return nil
	end
	return 100 + 50 * (currentLevel - 1)
end

return table.freeze(PetConfigs)
