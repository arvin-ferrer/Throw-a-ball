--!strict
--[[
	PetConfigs.luau
	Unified Pet catalog (Starter + 3 MVP Biomes + Shop/Seasonal exclusives),
	Active Ball Perks, Mutation specs, Star Tiers, and non-duplicate perk resolution.
]]

export type PerkType =
	"TrainingBoost"
	| "HeavyKnockback"
	| "VampiricLeech"
	| "CritSurge"
	| "ShockwaveSplash"
	| "FrostSlow"
	| "ChainRicochet"
	| "ShieldOnThrow"
	| "DeepFreeze"
	| "EmberBurn"
	| "SpeedBurn"
	| "KnockbackBurn"
	| "ExplosiveAoE"

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Mythic" | "Exclusive"

export type PetSpecies = {
	id: string,
	displayName: string,
	source: string,
	rarity: Rarity,
	baseRate: number,
	perkType: PerkType,
	perkLabel: string,
	perkBaseValue: number,
	isBiomeBossPet: boolean,
	primaryColor: { number },
	accentColor: { number },
	silhouette: "Quadruped" | "Sprite" | "Avian" | "Golem" | "Dragon",
}

export type MutationSpec = {
	id: string,
	displayName: string,
	coinMult: number,
	perkPotencyBonus: number,
	overchargedOnly: boolean,
	color: { number },
}

export type StarSpec = {
	star: number,
	label: string,
	coinMult: number,
	perkPotencyBonus: number,
	hasGoldenHalo: boolean,
}

export type OwnedPetSnapshot = {
	uid: string,
	speciesId: string,
	mutationKey: string,
	starTier: number,
	level: number,
	traitKey: string?,
}

export type ResolvedPerk = {
	perkType: PerkType,
	potency: number,
	baseValue: number,
	effectiveValue: number,
	sourcePetUid: string,
}

local PetConfigs = {}

PetConfigs.RARITY_COLORS = {
	Common = { 186, 204, 218 },
	Uncommon = { 74, 222, 128 },
	Rare = { 56, 189, 248 },
	Epic = { 192, 132, 252 },
	Mythic = { 251, 191, 36 },
	Exclusive = { 244, 114, 182 },
}

PetConfigs.MUTATIONS = {
	Normal = {
		id = "Normal",
		displayName = "Normal",
		coinMult = 1.0,
		perkPotencyBonus = 0.0,
		overchargedOnly = false,
		color = { 226, 232, 240 },
	},
	Shiny = {
		id = "Shiny",
		displayName = "Shiny",
		coinMult = 1.5,
		perkPotencyBonus = 0.10,
		overchargedOnly = false,
		color = { 125, 249, 255 },
	},
	Golden = {
		id = "Golden",
		displayName = "Golden",
		coinMult = 2.5,
		perkPotencyBonus = 0.20,
		overchargedOnly = false,
		color = { 255, 215, 64 },
	},
	Overcharged = {
		id = "Overcharged",
		displayName = "Overcharged",
		coinMult = 4.0,
		perkPotencyBonus = 0.30,
		overchargedOnly = true,
		color = { 255, 72, 196 },
	},
	VoidTouched = {
		id = "VoidTouched",
		displayName = "Void-Touched",
		coinMult = 6.0,
		perkPotencyBonus = 0.40,
		overchargedOnly = true,
		color = { 139, 92, 246 },
	},
} :: { [string]: MutationSpec }

PetConfigs.STAR_TIERS = {
	[1] = {
		star = 1,
		label = "1★ Base",
		coinMult = 1.00,
		perkPotencyBonus = 0.0,
		hasGoldenHalo = false,
	},
	[2] = {
		star = 2,
		label = "2★ Fused",
		coinMult = 1.75,
		perkPotencyBonus = 0.15,
		hasGoldenHalo = false,
	},
	[3] = {
		star = 3,
		label = "3★ Apex",
		coinMult = 3.00,
		perkPotencyBonus = 0.30,
		hasGoldenHalo = true,
	},
} :: { [number]: StarSpec }

PetConfigs.SPECIES = {
	-- 0. Hub Starter
	TrainingPup = {
		id = "TrainingPup",
		displayName = "Training Pup",
		source = "HubStarter",
		rarity = "Common",
		baseRate = 5,
		perkType = "TrainingBoost",
		perkLabel = "+5% Training Gain",
		perkBaseValue = 0.05,
		isBiomeBossPet = false,
		primaryColor = { 242, 186, 114 },
		accentColor = { 255, 244, 214 },
		silhouette = "Quadruped",
	},
	-- 1. Emerald Meadow
	PebbleCub = {
		id = "PebbleCub",
		displayName = "Pebble Cub",
		source = "EmeraldMeadow",
		rarity = "Uncommon",
		baseRate = 12,
		perkType = "HeavyKnockback",
		perkLabel = "Heavy Knockback",
		perkBaseValue = 48,
		isBiomeBossPet = true,
		primaryColor = { 128, 146, 134 },
		accentColor = { 74, 222, 128 },
		silhouette = "Quadruped",
	},
	DewSprite = {
		id = "DewSprite",
		displayName = "Dew Sprite",
		source = "EmeraldMeadow",
		rarity = "Rare",
		baseRate = 18,
		perkType = "VampiricLeech",
		perkLabel = "4% Vampiric Leech",
		perkBaseValue = 0.04,
		isBiomeBossPet = true,
		primaryColor = { 52, 211, 153 },
		accentColor = { 186, 255, 228 },
		silhouette = "Sprite",
	},
	ThornStag = {
		id = "ThornStag",
		displayName = "Thorn Stag",
		source = "EmeraldMeadow",
		rarity = "Epic",
		baseRate = 30,
		perkType = "CritSurge",
		perkLabel = "12% Crit (1.75x)",
		perkBaseValue = 0.12,
		isBiomeBossPet = true,
		primaryColor = { 62, 148, 86 },
		accentColor = { 250, 204, 21 },
		silhouette = "Quadruped",
	},
	GolemHeart = {
		id = "GolemHeart",
		displayName = "Golem Heart",
		source = "EmeraldMeadow",
		rarity = "Mythic",
		baseRate = 65,
		perkType = "ShockwaveSplash",
		perkLabel = "Shockwave Splash",
		perkBaseValue = 0.35,
		isBiomeBossPet = true,
		primaryColor = { 76, 94, 84 },
		accentColor = { 52, 255, 168 },
		silhouette = "Golem",
	},
	-- 2. Frostbite Cavern
	SnowFox = {
		id = "SnowFox",
		displayName = "Snow Fox",
		source = "FrostbiteCavern",
		rarity = "Uncommon",
		baseRate = 75,
		perkType = "FrostSlow",
		perkLabel = "Frost Slow (-20% 2s)",
		perkBaseValue = 0.20,
		isBiomeBossPet = true,
		primaryColor = { 224, 242, 254 },
		accentColor = { 56, 189, 248 },
		silhouette = "Quadruped",
	},
	ShardOwl = {
		id = "ShardOwl",
		displayName = "Shard Owl",
		source = "FrostbiteCavern",
		rarity = "Rare",
		baseRate = 115,
		perkType = "ChainRicochet",
		perkLabel = "Chain Ricochet (45%)",
		perkBaseValue = 0.45,
		isBiomeBossPet = true,
		primaryColor = { 96, 165, 250 },
		accentColor = { 224, 242, 254 },
		silhouette = "Avian",
	},
	PermafrostBear = {
		id = "PermafrostBear",
		displayName = "Permafrost Bear",
		source = "FrostbiteCavern",
		rarity = "Epic",
		baseRate = 190,
		perkType = "ShieldOnThrow",
		perkLabel = "Shield on Throw",
		perkBaseValue = 18,
		isBiomeBossPet = true,
		primaryColor = { 147, 197, 253 },
		accentColor = { 56, 217, 245 },
		silhouette = "Golem",
	},
	CryoTitan = {
		id = "CryoTitan",
		displayName = "Cryo Titan",
		source = "FrostbiteCavern",
		rarity = "Mythic",
		baseRate = 420,
		perkType = "DeepFreeze",
		perkLabel = "Deep Freeze Mini-Stun",
		perkBaseValue = 0.45,
		isBiomeBossPet = true,
		primaryColor = { 37, 99, 235 },
		accentColor = { 165, 243, 252 },
		silhouette = "Golem",
	},
	-- 3. Molten Caldera
	AshLizard = {
		id = "AshLizard",
		displayName = "Ash Lizard",
		source = "MoltenCaldera",
		rarity = "Uncommon",
		baseRate = 450,
		perkType = "EmberBurn",
		perkLabel = "Ember Burn (15%/3s)",
		perkBaseValue = 0.15,
		isBiomeBossPet = true,
		primaryColor = { 78, 52, 56 },
		accentColor = { 249, 115, 22 },
		silhouette = "Quadruped",
	},
	PyroHawk = {
		id = "PyroHawk",
		displayName = "Pyro Hawk",
		source = "MoltenCaldera",
		rarity = "Rare",
		baseRate = 680,
		perkType = "SpeedBurn",
		perkLabel = "Speed + Ember Burn",
		perkBaseValue = 0.18,
		isBiomeBossPet = true,
		primaryColor = { 234, 88, 12 },
		accentColor = { 253, 224, 71 },
		silhouette = "Avian",
	},
	LavaRhino = {
		id = "LavaRhino",
		displayName = "Lava Rhino",
		source = "MoltenCaldera",
		rarity = "Epic",
		baseRate = 1100,
		perkType = "KnockbackBurn",
		perkLabel = "Knockback + Burn",
		perkBaseValue = 54,
		isBiomeBossPet = true,
		primaryColor = { 62, 42, 46 },
		accentColor = { 239, 68, 68 },
		silhouette = "Golem",
	},
	InfernoDrake = {
		id = "InfernoDrake",
		displayName = "Inferno Drake",
		source = "MoltenCaldera",
		rarity = "Mythic",
		baseRate = 2500,
		perkType = "ExplosiveAoE",
		perkLabel = "Explosive AoE + Burn",
		perkBaseValue = 0.45,
		isBiomeBossPet = true,
		primaryColor = { 185, 28, 28 },
		accentColor = { 255, 196, 54 },
		silhouette = "Dragon",
	},
	-- Permanent Shop Exclusive Pets (Never Boss Creatures!)
	PrismFox = {
		id = "PrismFox",
		displayName = "Prism Fox",
		source = "ShopPermanent",
		rarity = "Exclusive",
		baseRate = 28,
		perkType = "CritSurge",
		perkLabel = "12% Crit (1.75x)",
		perkBaseValue = 0.12,
		isBiomeBossPet = false,
		primaryColor = { 244, 114, 182 },
		accentColor = { 96, 212, 255 },
		silhouette = "Quadruped",
	},
	StarlightBeetle = {
		id = "StarlightBeetle",
		displayName = "Starlight Beetle",
		source = "ShopPermanent",
		rarity = "Exclusive",
		baseRate = 95,
		perkType = "VampiricLeech",
		perkLabel = "4% Vampiric Leech",
		perkBaseValue = 0.04,
		isBiomeBossPet = false,
		primaryColor = { 168, 85, 247 },
		accentColor = { 253, 224, 71 },
		silhouette = "Sprite",
	},
	AegisGryphon = {
		id = "AegisGryphon",
		displayName = "Aegis Gryphon",
		source = "ShopPermanent",
		rarity = "Exclusive",
		baseRate = 340,
		perkType = "ShieldOnThrow",
		perkLabel = "Shield on Throw",
		perkBaseValue = 20,
		isBiomeBossPet = false,
		primaryColor = { 250, 204, 21 },
		accentColor = { 248, 250, 252 },
		silhouette = "Avian",
	},
	-- Rotating Seasonal Exclusive Pets (Cyber Season)
	CyberHound = {
		id = "CyberHound",
		displayName = "Cyber Hound",
		source = "Seasonal_Cyber",
		rarity = "Exclusive",
		baseRate = 55,
		perkType = "ChainRicochet",
		perkLabel = "Chain Ricochet (45%)",
		perkBaseValue = 0.45,
		isBiomeBossPet = false,
		primaryColor = { 34, 211, 238 },
		accentColor = { 244, 63, 94 },
		silhouette = "Quadruped",
	},
	NeonMoth = {
		id = "NeonMoth",
		displayName = "Neon Moth",
		source = "Seasonal_Cyber",
		rarity = "Exclusive",
		baseRate = 140,
		perkType = "FrostSlow",
		perkLabel = "Frost Slow (-20% 2s)",
		perkBaseValue = 0.20,
		isBiomeBossPet = false,
		primaryColor = { 192, 132, 252 },
		accentColor = { 45, 212, 191 },
		silhouette = "Avian",
	},
	VoltSerpent = {
		id = "VoltSerpent",
		displayName = "Volt Serpent",
		source = "Seasonal_Cyber",
		rarity = "Exclusive",
		baseRate = 480,
		perkType = "EmberBurn",
		perkLabel = "Ember Burn (15%/3s)",
		perkBaseValue = 0.15,
		isBiomeBossPet = false,
		primaryColor = { 250, 204, 21 },
		accentColor = { 56, 189, 248 },
		silhouette = "Dragon",
	},
} :: { [string]: PetSpecies }

function PetConfigs.computePerkPotency(starTier: number, mutationKey: string): number
	local starSpec = PetConfigs.STAR_TIERS[starTier]
	local mutSpec = PetConfigs.MUTATIONS[mutationKey]
	local starBonus = if starSpec then starSpec.perkPotencyBonus else 0
	local mutBonus = if mutSpec then mutSpec.perkPotencyBonus else 0
	return 1.0 + starBonus + mutBonus
end

function PetConfigs.resolveActivePerks(
	activePets: { OwnedPetSnapshot }
): { [PerkType]: ResolvedPerk }
	local resolved: { [PerkType]: ResolvedPerk } = {}
	for _, pet in ipairs(activePets) do
		local species = PetConfigs.SPECIES[pet.speciesId]
		if species then
			local potency = PetConfigs.computePerkPotency(pet.starTier, pet.mutationKey)
			local eff = species.perkBaseValue * potency
			local existing = resolved[species.perkType]
			if not existing or eff > existing.effectiveValue then
				resolved[species.perkType] = {
					perkType = species.perkType,
					potency = potency,
					baseValue = species.perkBaseValue,
					effectiveValue = eff,
					sourcePetUid = pet.uid,
				}
			end
		end
	end
	return resolved
end

function PetConfigs.getSpecies(speciesId: string): PetSpecies?
	return PetConfigs.SPECIES[speciesId]
end

function PetConfigs.getAllSpeciesOrdered(): { PetSpecies }
	local list: { PetSpecies } = {}
	for _, spec in pairs(PetConfigs.SPECIES) do
		table.insert(list, spec)
	end
	table.sort(list, function(a, b)
		if a.baseRate ~= b.baseRate then
			return a.baseRate < b.baseRate
		end
		return a.id < b.id
	end)
	return list
end

return PetConfigs
