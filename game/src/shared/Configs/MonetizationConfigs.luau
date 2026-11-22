--!strict
-- GDD v1.1 §§4, 8.4, 8.6, and 10. Shop names, species, and odds are provisional.
-- TODO: Replace each 0 with its Creator Dashboard ID before enabling the offer.
-- A zero ID is disabled. Give changed paid rewards a new product ID and retain old pools for hatches.

export type OddsRow = { petId: string, mutation: string, basisPoints: number }

export type PaidEggPool = {
	kind: string, -- "PermanentEgg" | "SeasonalEgg"
	odds: { OddsRow },
}

export type Bundle = { petId: string, mutation: string, cosmeticKey: string }

export type DeveloperProduct = {
	productId: number,
	kind: string, -- "PermanentEgg" | "SeasonalEgg" | "DirectBundle" | "Cosmetic"
	poolKey: string?,
	directBundleKey: string?,
	bundle: Bundle?,
	cosmeticKey: string?,
}

export type GamePass = { passId: number, displayName: string }

export type Catalog = {
	gamePasses: { [string]: GamePass },
	products: { [string]: DeveloperProduct },
	paidEggPools: { [string]: PaidEggPool },
}

local MonetizationConfigs = {}

MonetizationConfigs.ODDS_TOTAL_BASIS_POINTS = 10_000
MonetizationConfigs.RECENT_PURCHASE_LIMIT = 100

-- §10.1. These shop-exclusive IDs are independent of the gameplay-earned PetConfigs species.
MonetizationConfigs.ShopPets = table.freeze({
	ArcadeAxolotl = table.freeze({
		displayName = "Arcade Axolotl",
		baseCoinsPerSec = 42,
		activePerk = "TrainingBoost",
	}),
	NeonKitsune = table.freeze({
		displayName = "Neon Kitsune",
		baseCoinsPerSec = 86,
		activePerk = "ChainRicochet",
	}),
	FrostfestHare = table.freeze({
		displayName = "Frostfest Hare",
		baseCoinsPerSec = 48,
		activePerk = "FrostSlow",
	}),
	SnowglobeDrake = table.freeze({
		displayName = "Snowglobe Drake",
		baseCoinsPerSec = 92,
		activePerk = "ShieldOnThrow",
	}),
})
MonetizationConfigs.Cosmetics = table.freeze({
	ArcadeTrail = "Arcade Trail",
	FrostfestBallSkin = "Frostfest Ball Skin",
	AuroraBallSkin = "Aurora Ball Skin",
})

-- §§10.1–10.2. Each paid egg offer has a fixed bundle for restricted players.
local products: { [string]: DeveloperProduct } = {
	ArcadeEgg = table.freeze({
		productId = 0, -- TODO: permanent random egg product ID
		kind = "PermanentEgg",
		poolKey = "ArcadeV1",
		directBundleKey = "ArcadeBundle",
	}),
	FrostfestEgg = table.freeze({
		productId = 0, -- TODO: seasonal random egg product ID
		kind = "SeasonalEgg",
		poolKey = "FrostfestV1",
		directBundleKey = "FrostfestBundle",
	}),
	ArcadeBundle = table.freeze({
		productId = 0, -- TODO: permanent direct bundle product ID
		kind = "DirectBundle",
		bundle = table.freeze({
			petId = "ArcadeAxolotl",
			mutation = "Normal",
			cosmeticKey = "ArcadeTrail",
		}),
	}),
	FrostfestBundle = table.freeze({
		productId = 0, -- TODO: seasonal direct bundle product ID
		kind = "DirectBundle",
		bundle = table.freeze({
			petId = "FrostfestHare",
			mutation = "Normal",
			cosmeticKey = "FrostfestBallSkin",
		}),
	}),
	AuroraSkin = table.freeze({
		productId = 0, -- TODO: direct cosmetic product ID
		kind = "Cosmetic",
		cosmeticKey = "AuroraBallSkin",
	}),
}

-- §10.2. Each outcome is a species and mutation pair with exact integer basis points.
local paidEggPools: { [string]: PaidEggPool } = {
	ArcadeV1 = table.freeze({
		kind = "PermanentEgg",
		odds = table.freeze({
			table.freeze({ petId = "ArcadeAxolotl", mutation = "Normal", basisPoints = 7_750 }),
			table.freeze({ petId = "NeonKitsune", mutation = "Shiny", basisPoints = 2_000 }),
			table.freeze({ petId = "NeonKitsune", mutation = "Golden", basisPoints = 250 }),
		}),
	}),
	FrostfestV1 = table.freeze({
		kind = "SeasonalEgg",
		odds = table.freeze({
			table.freeze({ petId = "FrostfestHare", mutation = "Normal", basisPoints = 8_325 }),
			table.freeze({ petId = "SnowglobeDrake", mutation = "Shiny", basisPoints = 1_650 }),
			table.freeze({ petId = "SnowglobeDrake", mutation = "Golden", basisPoints = 25 }),
		}),
	}),
}

-- §10.1. Ownership comes from Roblox, independently of Developer Product receipts.
local gamePasses: { [string]: GamePass } = {
	DoubleTraining = table.freeze({ passId = 0, displayName = "2× Training Speed" }), -- TODO: pass ID
	DoubleCoinsExp = table.freeze({ passId = 0, displayName = "2× Coins & EXP" }), -- TODO: pass ID
	AutoFire = table.freeze({ passId = 0, displayName = "Auto-Fire Range" }), -- TODO: pass ID
	MagnetCollect = table.freeze({ passId = 0, displayName = "Magnet Coin Collect" }), -- TODO: pass ID
	ExtraPedestals = table.freeze({ passId = 0, displayName = "+2 Pedestals" }), -- TODO: pass ID
}

MonetizationConfigs.Catalog = table.freeze({
	gamePasses = table.freeze(gamePasses),
	products = table.freeze(products),
	paidEggPools = table.freeze(paidEggPools),
})

return table.freeze(MonetizationConfigs)
