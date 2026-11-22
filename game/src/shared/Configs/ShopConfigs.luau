--!strict
-- Sources refer to docs/GameIdea_Evolved_GDD.md v1.1.
-- Prices and odds marked as tuning are provisional where the GDD specifies only behavior.

-- selene: allow(incorrect_standard_library_use)
local CombatConfigs = require("./CombatConfigs")
-- selene: allow(incorrect_standard_library_use)
local EconomyConfigs = require("./EconomyConfigs")

local ShopConfigs = {}

-- §5.2 names the progression. CombatConfigs owns the existing ball shop prices.
ShopConfigs.BallTierOrder = table.freeze({
	"RubberBall",
	"IronSphere",
	"FrostOrb",
	"MagmaCore",
	"NovaSphere",
})

local ballTierCoinPrices: { [string]: number } = {}
for _, tierId in ShopConfigs.BallTierOrder do
	ballTierCoinPrices[tierId] = CombatConfigs.BallTiers[tierId].costCoins
end
ShopConfigs.BallTierCoinPrices = table.freeze(ballTierCoinPrices)

-- §6.1 names target progression. The first paid tier is tuned for the first sweep in §2.2.
ShopConfigs.TargetTierOrder = table.freeze({
	"WoodenDummy",
	"IronBullseye",
	"CrystalDrone",
	"ObsidianCore",
})
local targetTierCoinPrices: { [string]: number } = {
	WoodenDummy = 0,
	IronBullseye = 100,
	CrystalDrone = 1_500,
	ObsidianCore = 15_000,
}
ShopConfigs.TargetTierCoinPrices = table.freeze(targetTierCoinPrices)

-- §§7.1 and 8.7. Slot numbers are the new total after unlocking one pedestal.
ShopConfigs.STARTING_PEDESTALS = 4
ShopConfigs.MAX_PEDESTALS = 12
ShopConfigs.PedestalPrices = table.freeze({
	[5] = table.freeze({ coins = 500, bossGems = 0 }),
	[6] = table.freeze({ coins = 1_000, bossGems = 0 }),
	[7] = table.freeze({ coins = 2_000, bossGems = 0 }),
	[8] = table.freeze({ coins = 4_000, bossGems = 0 }),
	[9] = table.freeze({ coins = 8_000, bossGems = 5 }),
	[10] = table.freeze({ coins = 16_000, bossGems = 10 }),
	[11] = table.freeze({ coins = 32_000, bossGems = 15 }),
	[12] = table.freeze({ coins = 64_000, bossGems = 20 }),
})

-- §8.2 fixes the efficiencies and cap. Upgrade prices are provisional.
ShopConfigs.MAX_OFFLINE_SECONDS = EconomyConfigs.MAX_OFFLINE_SECONDS
ShopConfigs.OfflineVaultTiers = table.freeze({
	table.freeze({ efficiency = EconomyConfigs.BASE_OFFLINE_EFFICIENCY, bossGems = 0 }),
	table.freeze({ efficiency = 0.75, bossGems = 10 }),
	table.freeze({ efficiency = 1.0, bossGems = 25 }),
})

-- §§8.4 and 9. Tune the prices against the target of about four to five fights.
local gemEggPrices: { [string]: number } = {
	EmeraldMeadow = 5,
	FrostbiteCavern = 10,
	MoltenCaldera = 15,
}
ShopConfigs.GemEggPrices = table.freeze(gemEggPrices)

-- §8.6. Provisional standard-egg weights in hatch roll order.
ShopConfigs.StandardEggMutationOdds = table.freeze({
	table.freeze({ mutation = "Normal", percent = 90 }),
	table.freeze({ mutation = "Shiny", percent = 9 }),
	table.freeze({ mutation = "Golden", percent = 1 }),
})

-- §8.7 fixes the rank bonuses. The Coin threshold uses provisional linear tuning.
ShopConfigs.MAX_SAFE_INTEGER = 9_007_199_254_740_991
ShopConfigs.ASCENSION_BASE_COINS = 100_000
ShopConfigs.ASCENSION_COINS_PER_RANK = 100_000
ShopConfigs.ASCENSION_COIN_BONUS = EconomyConfigs.ASCENSION_COIN_BONUS
ShopConfigs.ASCENSION_TRAINING_BONUS = EconomyConfigs.ASCENSION_TRAINING_BONUS

function ShopConfigs.getAscensionCoinThreshold(currentRank: number): number
	local base = ShopConfigs.ASCENSION_BASE_COINS
	local step = ShopConfigs.ASCENSION_COINS_PER_RANK
	local max = ShopConfigs.MAX_SAFE_INTEGER
	assert(
		currentRank >= 0 and currentRank <= max and currentRank == math.floor(currentRank),
		"ascension rank must be a nonnegative safe integer"
	)
	local maxRankBeforeCap = math.floor((max - base) / step)
	if currentRank > maxRankBeforeCap then
		return max
	end
	return base + currentRank * step
end

return table.freeze(ShopConfigs)
