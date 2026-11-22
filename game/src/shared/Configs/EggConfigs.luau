--!strict
--[[
	EggConfigs.luau
	Single source of truth for BOTH server egg rolls and UI 100.0% Odds Disclosure.
	Enforces GDD §8.4 & §10.2 invariants:
	- Biome Boss Eggs & Overcharged Eggs are NEVER Robux-purchasable.
	- Paid Shop/Seasonal Eggs NEVER contain Biome Boss Pets or Overcharged/VoidTouched mutations.
]]

export type WeightedEntry = {
	id: string,
	weight: number,
}

export type EggCategory =
	"Starter"
	| "BiomeBoss"
	| "OverchargedBoss"
	| "ShopPermanent"
	| "ShopSeasonal"

export type EggConfig = {
	id: string,
	displayName: string,
	category: EggCategory,
	biomeId: string?,
	isPaidRandomItem: boolean,
	devProductId: number?,
	gemCraftCost: number?,
	primaryColor: { number },
	accentColor: { number },
	petTable: { WeightedEntry },
	mutationTable: { WeightedEntry },
}

export type DisclosedOdd = {
	id: string,
	percent: number,
}

local EggConfigs = {}

local STANDARD_MUTATIONS: { WeightedEntry } = {
	{ id = "Normal", weight = 80.0 },
	{ id = "Shiny", weight = 15.0 },
	{ id = "Golden", weight = 5.0 },
}

local OVERCHARGED_MUTATIONS: { WeightedEntry } = {
	{ id = "Shiny", weight = 25.0 },
	{ id = "Golden", weight = 30.0 },
	{ id = "Overcharged", weight = 38.0 },
	{ id = "VoidTouched", weight = 7.0 },
}

local SHOP_MUTATIONS: { WeightedEntry } = {
	{ id = "Normal", weight = 75.0 },
	{ id = "Shiny", weight = 18.0 },
	{ id = "Golden", weight = 7.0 },
}

EggConfigs.EGGS = {
	StarterEgg = {
		id = "StarterEgg",
		displayName = "Starter Egg",
		category = "Starter",
		biomeId = nil,
		isPaidRandomItem = false,
		devProductId = nil,
		gemCraftCost = nil,
		primaryColor = { 250, 224, 150 },
		accentColor = { 249, 115, 22 },
		petTable = {
			{ id = "TrainingPup", weight = 100.0 },
		},
		mutationTable = {
			{ id = "Normal", weight = 100.0 },
		},
	},
	EmeraldMeadow_BossEgg = {
		id = "EmeraldMeadow_BossEgg",
		displayName = "Meadow Boss Egg",
		category = "BiomeBoss",
		biomeId = "EmeraldMeadow",
		isPaidRandomItem = false,
		devProductId = nil,
		gemCraftCost = 25,
		primaryColor = { 52, 211, 153 },
		accentColor = { 22, 163, 74 },
		petTable = {
			{ id = "PebbleCub", weight = 45.0 },
			{ id = "DewSprite", weight = 30.0 },
			{ id = "ThornStag", weight = 19.0 },
			{ id = "GolemHeart", weight = 6.0 },
		},
		mutationTable = STANDARD_MUTATIONS,
	},
	EmeraldMeadow_OverchargedEgg = {
		id = "EmeraldMeadow_OverchargedEgg",
		displayName = "Overcharged Meadow Egg",
		category = "OverchargedBoss",
		biomeId = "EmeraldMeadow",
		isPaidRandomItem = false,
		devProductId = nil,
		gemCraftCost = nil,
		primaryColor = { 192, 132, 252 },
		accentColor = { 52, 255, 168 },
		petTable = {
			{ id = "DewSprite", weight = 40.0 },
			{ id = "ThornStag", weight = 42.0 },
			{ id = "GolemHeart", weight = 18.0 },
		},
		mutationTable = OVERCHARGED_MUTATIONS,
	},
	FrostbiteCavern_BossEgg = {
		id = "FrostbiteCavern_BossEgg",
		displayName = "Frostbite Boss Egg",
		category = "BiomeBoss",
		biomeId = "FrostbiteCavern",
		isPaidRandomItem = false,
		devProductId = nil,
		gemCraftCost = 60,
		primaryColor = { 56, 189, 248 },
		accentColor = { 224, 242, 254 },
		petTable = {
			{ id = "SnowFox", weight = 45.0 },
			{ id = "ShardOwl", weight = 30.0 },
			{ id = "PermafrostBear", weight = 19.0 },
			{ id = "CryoTitan", weight = 6.0 },
		},
		mutationTable = STANDARD_MUTATIONS,
	},
	FrostbiteCavern_OverchargedEgg = {
		id = "FrostbiteCavern_OverchargedEgg",
		displayName = "Overcharged Frost Egg",
		category = "OverchargedBoss",
		biomeId = "FrostbiteCavern",
		isPaidRandomItem = false,
		devProductId = nil,
		gemCraftCost = nil,
		primaryColor = { 139, 92, 246 },
		accentColor = { 125, 249, 255 },
		petTable = {
			{ id = "ShardOwl", weight = 40.0 },
			{ id = "PermafrostBear", weight = 42.0 },
			{ id = "CryoTitan", weight = 18.0 },
		},
		mutationTable = OVERCHARGED_MUTATIONS,
	},
	MoltenCaldera_BossEgg = {
		id = "MoltenCaldera_BossEgg",
		displayName = "Caldera Boss Egg",
		category = "BiomeBoss",
		biomeId = "MoltenCaldera",
		isPaidRandomItem = false,
		devProductId = nil,
		gemCraftCost = 140,
		primaryColor = { 251, 113, 42 },
		accentColor = { 253, 224, 71 },
		petTable = {
			{ id = "AshLizard", weight = 45.0 },
			{ id = "PyroHawk", weight = 30.0 },
			{ id = "LavaRhino", weight = 19.0 },
			{ id = "InfernoDrake", weight = 6.0 },
		},
		mutationTable = STANDARD_MUTATIONS,
	},
	MoltenCaldera_OverchargedEgg = {
		id = "MoltenCaldera_OverchargedEgg",
		displayName = "Overcharged Caldera Egg",
		category = "OverchargedBoss",
		biomeId = "MoltenCaldera",
		isPaidRandomItem = false,
		devProductId = nil,
		gemCraftCost = nil,
		primaryColor = { 255, 72, 196 },
		accentColor = { 255, 168, 38 },
		petTable = {
			{ id = "PyroHawk", weight = 40.0 },
			{ id = "LavaRhino", weight = 42.0 },
			{ id = "InfernoDrake", weight = 18.0 },
		},
		mutationTable = OVERCHARGED_MUTATIONS,
	},
	Shop_PrismEgg = {
		id = "Shop_PrismEgg",
		displayName = "Prism Premium Egg",
		category = "ShopPermanent",
		biomeId = nil,
		isPaidRandomItem = true,
		devProductId = 190000101,
		gemCraftCost = nil,
		primaryColor = { 244, 114, 182 },
		accentColor = { 96, 212, 255 },
		petTable = {
			{ id = "PrismFox", weight = 55.0 },
			{ id = "StarlightBeetle", weight = 33.0 },
			{ id = "AegisGryphon", weight = 12.0 },
		},
		mutationTable = SHOP_MUTATIONS,
	},
	Seasonal_CyberEgg = {
		id = "Seasonal_CyberEgg",
		displayName = "Cyber Seasonal Egg",
		category = "ShopSeasonal",
		biomeId = nil,
		isPaidRandomItem = true,
		devProductId = 190000102,
		gemCraftCost = nil,
		primaryColor = { 34, 211, 238 },
		accentColor = { 244, 63, 94 },
		petTable = {
			{ id = "CyberHound", weight = 55.0 },
			{ id = "NeonMoth", weight = 33.0 },
			{ id = "VoltSerpent", weight = 12.0 },
		},
		mutationTable = SHOP_MUTATIONS,
	},
} :: { [string]: EggConfig }

local function rollWeighted(entries: { WeightedEntry }, rollUnit: number): string
	local total = 0
	for _, entry in ipairs(entries) do
		total += entry.weight
	end
	local target = math.clamp(rollUnit, 0, 0.9999999) * total
	local acc = 0
	for _, entry in ipairs(entries) do
		acc += entry.weight
		if target < acc then
			return entry.id
		end
	end
	return entries[#entries].id
end

function EggConfigs.getWeightSum(entries: { WeightedEntry }): number
	local sum = 0
	for _, entry in ipairs(entries) do
		sum += entry.weight
	end
	return sum
end

function EggConfigs.getDisclosedOdds(eggId: string): ({ DisclosedOdd }, { DisclosedOdd })
	local egg = EggConfigs.EGGS[eggId]
	if not egg then
		return {}, {}
	end
	local petSum = EggConfigs.getWeightSum(egg.petTable)
	local mutSum = EggConfigs.getWeightSum(egg.mutationTable)
	local petOdds: { DisclosedOdd } = {}
	local mutOdds: { DisclosedOdd } = {}
	for _, e in ipairs(egg.petTable) do
		table.insert(petOdds, { id = e.id, percent = (e.weight / petSum) * 100 })
	end
	for _, e in ipairs(egg.mutationTable) do
		table.insert(mutOdds, { id = e.id, percent = (e.weight / mutSum) * 100 })
	end
	return petOdds, mutOdds
end

function EggConfigs.rollHatch(
	eggId: string,
	petRollUnit: number,
	mutRollUnit: number
): (string, string)
	local egg = EggConfigs.EGGS[eggId]
	if not egg then
		error(`Unknown eggId: {eggId}`)
	end
	return rollWeighted(egg.petTable, petRollUnit), rollWeighted(egg.mutationTable, mutRollUnit)
end

function EggConfigs.isRobuxPurchasable(eggId: string): boolean
	local egg = EggConfigs.EGGS[eggId]
	if not egg then
		return false
	end
	return egg.isPaidRandomItem
		and egg.category ~= "BiomeBoss"
		and egg.category ~= "OverchargedBoss"
end

function EggConfigs.getEgg(eggId: string): EggConfig?
	return EggConfigs.EGGS[eggId]
end

return EggConfigs
