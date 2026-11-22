--!strict
local EconomyLedger = require("../src/shared/Utils/EconomyLedger")
local CombatConfigs = require("../src/shared/Configs/CombatConfigs")
local EconomyConfigs = require("../src/shared/Configs/EconomyConfigs")
local ShopConfigs = require("../src/shared/Configs/ShopConfigs")

type PlayerData = EconomyLedger.PlayerData
type TransactionResult = EconomyLedger.TransactionResult

local function run(name: string, test: () -> ())
	local ok, failure = pcall(test)
	assert(ok, `{name}: {failure}`)
end

local function copyTree(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in value do
		copy[key] = copyTree(child)
	end
	return copy
end

local function expectSameTree(actual: any, expected: any, path: string)
	if type(expected) ~= "table" then
		assert(actual == expected, `{path}: expected {expected}, got {actual}`)
		return
	end
	assert(type(actual) == "table", `{path}: expected a table`)
	for key, value in expected do
		expectSameTree(actual[key], value, `{path}.{key}`)
	end
	for key in actual do
		assert(expected[key] ~= nil, `{path}: unexpected key {key}`)
	end
end

local function expectApplied(result: TransactionResult)
	assert(result.ok, `expected success, got {result.reason}`)
	assert(result.replayed == false, "expected a new transaction")
end

local function expectUnchanged(
	profile: PlayerData,
	transaction: () -> TransactionResult,
	reason: string
)
	local before = copyTree(profile)
	local result = transaction()
	assert(not result.ok and result.reason == reason, `expected {reason}, got {result.reason}`)
	expectSameTree(profile, before, "rejected profile")
end

local function expectReplay(profile: PlayerData, transaction: () -> TransactionResult)
	local before = copyTree(profile)
	local result = transaction()
	assert(result.ok and result.replayed, "expected a successful no-op replay")
	expectSameTree(profile, before, "replayed profile")
end

local function funded(coins: number, bossGems: number): PlayerData
	local profile = EconomyLedger.new()
	if coins > 0 then
		expectApplied(EconomyLedger.grantCoins(profile, "seed-coins", coins))
	end
	if bossGems > 0 then
		expectApplied(EconomyLedger.grantBossGems(profile, "seed-gems", bossGems))
	end
	return profile
end

run("New profiles have independent defaults and a preplaced starter egg", function()
	local profile = EconomyLedger.new()
	local other = EconomyLedger.new()
	assert(EconomyLedger.SCHEMA_VERSION == 2 and profile.schemaVersion == 2, "current schema")
	assert(profile.coins == 0 and profile.bossGems == 0, "two independent starter balances")
	assert(
		profile.ballTierId == "RubberBall" and profile.targetTierId == "WoodenDummy",
		"free tiers"
	)
	assert(profile.pedestalsUnlocked == 4 and profile.offlineVaultTier == 1, "starter progression")
	assert(profile.ascensionRank == 0 and profile.lastLogoutTime == 0, "new account metadata")
	assert(profile.level == 1 and profile.exp == 0, "starter level and EXP")
	assert(profile.ballDamage == 10 and profile.throwSpeed == 0, "starter training stats")
	assert(next(profile.petsById) == nil and #profile.activePetIds == 0, "no hatched pets")
	assert(next(profile.transactionReceipts) == nil, "no transaction receipts")
	assert(profile.eggsById.StarterEgg.kind == "StarterEgg", "starter egg record")
	local first = profile.pedestalsById["1"]
	assert(first.eggId == "StarterEgg" and first.storedCoins == 0, "starter egg is on pedestal one")
	first.storedCoins = 17
	profile.extensions.tutorial = true
	assert(other.pedestalsById["1"].storedCoins == 0, "pedestal state is independent")
	assert(other.extensions.tutorial == nil, "extension state is independent")
end)

run("Version one migration maps vault efficiency and preserves earned nested progress", function()
	local old = {
		schemaVersion = 1,
		coins = 350,
		bossGems = 8,
		ballTierId = "IronSphere",
		offlineEfficiency = 0.75,
		ballDamage = 41,
		lastLogoutTime = 2_000,
		petsById = {
			pup = {
				petId = "TrainingPup",
				level = 4,
				stars = 2,
				mutation = "Shiny",
				trait = "Greedy",
			},
		},
		eggsById = {},
		pedestalsById = { ["1"] = { petId = "pup", storedCoins = 22 } },
		extensions = { tutorial = { hatched = true } },
		transactionReceipts = { welcome = { operation = "grantCoins", argument = 350 } },
	}
	local before = copyTree(old)
	local migrated = EconomyLedger.migrate(old)
	assert(migrated.ok, "version one should migrate")
	local profile = migrated.data
	assert(
		profile.schemaVersion == 2 and profile.offlineVaultTier == 2,
		"migrated schema and vault"
	)
	assert(profile.coins == 350 and profile.bossGems == 8, "earned currencies")
	assert(profile.ballTierId == "IronSphere" and profile.ballDamage == 41, "earned ball progress")
	assert(profile.targetTierId == "WoodenDummy" and profile.level == 1, "missing fields default")
	assert(profile.lastLogoutTime == 2_000, "saved logout time")
	assert(
		profile.pedestalsById["1"].storedCoins == 22 and profile.petsById.pup.stars == 2,
		"pet and pad"
	)
	assert(profile.eggsById.StarterEgg == nil, "migration does not reissue a used starter egg")
	expectSameTree(profile.extensions, old.extensions, "migrated extensions")
	expectReplay(profile, function()
		return EconomyLedger.grantCoins(profile, "welcome", 350)
	end)
	profile.petsById.pup.level = 5
	expectSameTree(old, before, "legacy input")
end)

run("Unversioned and current saves migrate without aliasing or losing progress", function()
	local unversioned = EconomyLedger.migrate({ coins = 23, offlineEfficiency = 1 })
	assert(unversioned.ok, "missing version is treated as version one")
	assert(
		unversioned.data.coins == 23 and unversioned.data.offlineVaultTier == 3,
		"legacy progress"
	)
	local profile = funded(100, 5)
	local first = EconomyLedger.migrate(profile)
	assert(first.ok, "current schema is accepted")
	expectSameTree(first.data, profile, "current migration")
	assert(
		first.data ~= profile and first.data.eggsById ~= profile.eggsById,
		"migration owns its tables"
	)
	local second = EconomyLedger.migrate(first.data)
	assert(second.ok, "migration can be repeated")
	expectSameTree(second.data, first.data, "repeat migration")
end)

run(
	"Migration rejects malformed balances and unsupported versions without changing input",
	function()
		local future = { schemaVersion = 3, coins = 99 }
		local unsupported = EconomyLedger.migrate(future)
		assert(
			not unsupported.ok and unsupported.reason == "UnsupportedSchemaVersion",
			"future schema rejected"
		)
		expectSameTree(future, { schemaVersion = 3, coins = 99 }, "future input")
		local broken = { schemaVersion = 1, coins = -5, bossGems = 13 }
		local invalid = EconomyLedger.migrate(broken)
		assert(not invalid.ok and invalid.reason == "InvalidProfile", "negative persisted balance")
		expectSameTree(broken, { schemaVersion = 1, coins = -5, bossGems = 13 }, "invalid input")
		for _, input in { { bossGems = math.huge }, { offlineEfficiency = 0.9 }, "not a profile" } do
			local rejected = EconomyLedger.migrate(input)
			assert(
				not rejected.ok and rejected.reason == "InvalidProfile",
				"invalid profile shape or field"
			)
		end
	end
)

run("Coin and Boss Gem grants and spends change only the named balance", function()
	local profile = funded(175, 12)
	expectApplied(EconomyLedger.spendCoins(profile, "spend-coins", 175))
	assert(profile.coins == 0 and profile.bossGems == 12, "exact Coin spend to zero")
	expectApplied(EconomyLedger.spendBossGems(profile, "spend-gems", 12))
	assert(profile.coins == 0 and profile.bossGems == 0, "exact Gem spend to zero")
	expectApplied(EconomyLedger.grantCoins(profile, "new-coins", 19))
	assert(profile.coins == 19 and profile.bossGems == 0, "Coin grants never mint Gems")
	expectApplied(EconomyLedger.grantBossGems(profile, "new-gems", 6))
	assert(profile.coins == 19 and profile.bossGems == 6, "Gem grants never mint Coins")
end)

run(
	"Currency transactions reject nonpositive fractional and non-finite amounts atomically",
	function()
		local profile = funded(100, 100)
		for _, transaction in
			{
				EconomyLedger.grantCoins,
				EconomyLedger.spendCoins,
				EconomyLedger.grantBossGems,
				EconomyLedger.spendBossGems,
			}
		do
			for _, amount in { -1, 0, 0.5, 0 / 0, math.huge, -math.huge } do
				expectUnchanged(profile, function()
					return transaction(profile, "invalid-amount", amount)
				end, "InvalidAmount")
			end
		end
	end
)

run(
	"Overspending and unsafe integer overflow leave both balances and receipts unchanged",
	function()
		local profile = funded(100, 10)
		expectUnchanged(profile, function()
			return EconomyLedger.spendCoins(profile, "too-much", 101)
		end, "InsufficientCoins")
		expectUnchanged(profile, function()
			return EconomyLedger.spendBossGems(profile, "too-much", 11)
		end, "InsufficientBossGems")

		local capped = funded(ShopConfigs.MAX_SAFE_INTEGER, ShopConfigs.MAX_SAFE_INTEGER)
		expectUnchanged(capped, function()
			return EconomyLedger.grantCoins(capped, "overflow", 1)
		end, "BalanceOverflow")
		expectUnchanged(capped, function()
			return EconomyLedger.grantBossGems(capped, "overflow", 1)
		end, "BalanceOverflow")
	end
)

run("Successful IDs replay across migration and reject changed amounts or operations", function()
	local profile = funded(25, 50)
	expectApplied(EconomyLedger.spendBossGems(profile, "payment", 50))
	local reloaded = EconomyLedger.migrate(profile)
	assert(reloaded.ok, "saved profile can reload")
	profile = reloaded.data
	expectReplay(profile, function()
		return EconomyLedger.spendBossGems(profile, "payment", 50)
	end)
	expectUnchanged(profile, function()
		return EconomyLedger.spendBossGems(profile, "payment", 1)
	end, "TransactionIdConflict")
	expectUnchanged(profile, function()
		return EconomyLedger.spendCoins(profile, "payment", 50)
	end, "TransactionIdConflict")
	local another = funded(50, 0)
	expectApplied(EconomyLedger.spendCoins(another, "payment", 50))
	assert(another.coins == 0 and profile.coins == 25, "transaction IDs are per account")
end)

run("Failed IDs can be retried after funding and empty IDs cannot mutate a profile", function()
	local profile = EconomyLedger.new()
	expectUnchanged(profile, function()
		return EconomyLedger.spendCoins(profile, "retry", 10)
	end, "InsufficientCoins")
	expectApplied(EconomyLedger.grantCoins(profile, "fund-retry", 10))
	expectApplied(EconomyLedger.spendCoins(profile, "retry", 10))
	expectReplay(profile, function()
		return EconomyLedger.spendCoins(profile, "retry", 10)
	end)
	expectUnchanged(profile, function()
		return EconomyLedger.grantBossGems(profile, "", 1)
	end, "InvalidTransactionId")
end)

run("Ball tiers use CombatConfigs prices and require the next tier in order", function()
	local profile = funded(2_500, 7)
	for _, tierId in ShopConfigs.BallTierOrder do
		assert(
			ShopConfigs.BallTierCoinPrices[tierId] == CombatConfigs.BallTiers[tierId].costCoins,
			"canonical ball price"
		)
	end
	expectUnchanged(profile, function()
		return EconomyLedger.purchaseBallTier(profile, "skip", "FrostOrb")
	end, "OutOfOrder")
	expectUnchanged(profile, function()
		return EconomyLedger.purchaseBallTier(profile, "unknown", "MissingBall")
	end, "UnknownTier")
	expectApplied(EconomyLedger.purchaseBallTier(profile, "buy-iron", "IronSphere"))
	assert(
		profile.ballTierId == "IronSphere" and profile.coins == 2_250 and profile.bossGems == 7,
		"exact Coin purchase"
	)
	expectReplay(profile, function()
		return EconomyLedger.purchaseBallTier(profile, "buy-iron", "IronSphere")
	end)
	expectUnchanged(profile, function()
		return EconomyLedger.purchaseBallTier(profile, "buy-iron-again", "IronSphere")
	end, "AlreadyOwned")
	expectUnchanged(profile, function()
		return EconomyLedger.purchaseBallTier(profile, "buy-frost", "FrostOrb")
	end, "InsufficientCoins")
end)

run("Target tiers charge Coins and reject unknown skipped and already-owned tiers", function()
	local profile = funded(100, 20)
	expectUnchanged(profile, function()
		return EconomyLedger.purchaseTargetTier(profile, "unknown-target", "MissingTarget")
	end, "UnknownTier")
	expectUnchanged(profile, function()
		return EconomyLedger.purchaseTargetTier(profile, "skip-target", "CrystalDrone")
	end, "OutOfOrder")
	expectApplied(EconomyLedger.purchaseTargetTier(profile, "iron-target", "IronBullseye"))
	assert(
		profile.targetTierId == "IronBullseye" and profile.coins == 0 and profile.bossGems == 20,
		"target costs Coins"
	)
	expectReplay(profile, function()
		return EconomyLedger.purchaseTargetTier(profile, "iron-target", "IronBullseye")
	end)
	expectUnchanged(profile, function()
		return EconomyLedger.purchaseTargetTier(profile, "old-target", "WoodenDummy")
	end, "AlreadyOwned")
	expectUnchanged(profile, function()
		return EconomyLedger.purchaseTargetTier(profile, "crystal-target", "CrystalDrone")
	end, "InsufficientCoins")
end)

run("Both shop ladders reach their final tier and reject further purchases", function()
	local profile = funded(500_000, 0)
	for index = 2, #ShopConfigs.BallTierOrder do
		expectApplied(
			EconomyLedger.purchaseBallTier(
				profile,
				`ball-{index}`,
				ShopConfigs.BallTierOrder[index]
			)
		)
	end
	for index = 2, #ShopConfigs.TargetTierOrder do
		expectApplied(
			EconomyLedger.purchaseTargetTier(
				profile,
				`target-{index}`,
				ShopConfigs.TargetTierOrder[index]
			)
		)
	end
	assert(
		profile.ballTierId == "NovaSphere" and profile.targetTierId == "ObsidianCore",
		"final tiers"
	)
	expectUnchanged(profile, function()
		return EconomyLedger.purchaseBallTier(profile, "max-ball", "NovaSphere")
	end, "MaxTier")
	expectUnchanged(profile, function()
		return EconomyLedger.purchaseTargetTier(profile, "max-target", "ObsidianCore")
	end, "MaxTier")
end)

local function expandCourtyard(profile: PlayerData)
	for slot = 5, 8 do
		expectApplied(EconomyLedger.expandPedestals(profile, `slot-{slot}`))
	end
end

run("Pedestals five through eight unlock one at a time for scaling Coins only", function()
	local profile = funded(7_500, 9)
	for slot, expectedRemaining in { 7_000, 6_000, 4_000, 0 } do
		expectApplied(EconomyLedger.expandPedestals(profile, `slot-{slot + 4}`))
		assert(profile.pedestalsUnlocked == slot + 4, "one slot per purchase")
		assert(
			profile.coins == expectedRemaining and profile.bossGems == 9,
			"courtyard charges Coins only"
		)
	end
	expectReplay(profile, function()
		return EconomyLedger.expandPedestals(profile, "slot-8")
	end)
end)

run("A two-currency pedestal expansion rolls back if either balance is short", function()
	local lowCoins = funded(15_499, 5)
	expandCourtyard(lowCoins)
	expectUnchanged(lowCoins, function()
		return EconomyLedger.expandPedestals(lowCoins, "slot-9")
	end, "InsufficientCoins")

	local lowGems = funded(15_500, 4)
	expandCourtyard(lowGems)
	expectUnchanged(lowGems, function()
		return EconomyLedger.expandPedestals(lowGems, "slot-9")
	end, "InsufficientBossGems")
	expectApplied(EconomyLedger.grantBossGems(lowGems, "one-more", 1))
	expectApplied(EconomyLedger.expandPedestals(lowGems, "slot-9"))
	assert(
		lowGems.pedestalsUnlocked == 9 and lowGems.coins == 0 and lowGems.bossGems == 0,
		"atomic exact payment"
	)
end)

run("Balcony slots charge both currencies and stop at twelve pedestals", function()
	local profile = funded(127_500, 50)
	expandCourtyard(profile)
	for slot = 9, 12 do
		local beforeCoins, beforeGems = profile.coins, profile.bossGems
		local price = ShopConfigs.PedestalPrices[slot]
		assert(price.coins > 0 and price.bossGems > 0, "balcony price uses both currencies")
		expectApplied(EconomyLedger.expandPedestals(profile, `slot-{slot}`))
		assert(profile.pedestalsUnlocked == slot, "advance to the next balcony slot")
		assert(
			profile.coins == beforeCoins - price.coins
				and profile.bossGems == beforeGems - price.bossGems,
			"both debits post together"
		)
	end
	assert(profile.coins == 0 and profile.bossGems == 0, "exact total balcony cost")
	expectUnchanged(profile, function()
		return EconomyLedger.expandPedestals(profile, "slot-13")
	end, "MaxPedestals")
end)

run(
	"Boss Gems upgrade the offline vault from fifty to seventy-five to one hundred percent",
	function()
		local profile = funded(18, 35)
		assert(EconomyLedger.getOfflineEfficiency(profile) == 0.5, "starter efficiency")
		expectApplied(EconomyLedger.upgradeOfflineVault(profile, "vault-75"))
		assert(profile.offlineVaultTier == 2 and profile.bossGems == 25, "first Gem price")
		assert(EconomyLedger.getOfflineEfficiency(profile) == 0.75, "mid-tier efficiency")
		expectReplay(profile, function()
			return EconomyLedger.upgradeOfflineVault(profile, "vault-75")
		end)
		expectApplied(EconomyLedger.upgradeOfflineVault(profile, "vault-100"))
		assert(
			profile.offlineVaultTier == 3 and profile.bossGems == 0 and profile.coins == 18,
			"second Gem price"
		)
		assert(EconomyLedger.getOfflineEfficiency(profile) == 1, "maximum efficiency")
		expectUnchanged(profile, function()
			return EconomyLedger.upgradeOfflineVault(profile, "vault-max")
		end, "MaxVaultTier")
	end
)

run("Vault upgrades require Gems and every vault tier keeps the twelve-hour ceiling", function()
	local profile = funded(100_000, 9)
	expectUnchanged(profile, function()
		return EconomyLedger.upgradeOfflineVault(profile, "vault-poor")
	end, "InsufficientBossGems")
	assert(ShopConfigs.MAX_OFFLINE_SECONDS == 43_200, "twelve hours")
	for _, config in ShopConfigs.OfflineVaultTiers do
		local accrual = EconomyConfigs.computeOfflineCoins(10, 86_400, config.efficiency)
		assert(accrual == 432_000 * config.efficiency, "all tiers cap at twelve hours")
	end
end)

run("Gem crafting grants one standard egg for the selected biome and replays safely", function()
	local profile = funded(70, 30)
	for _, biomeId in { "EmeraldMeadow", "FrostbiteCavern", "MoltenCaldera" } do
		local id = `egg-{biomeId}`
		local before = profile.bossGems
		expectApplied(EconomyLedger.craftGemEgg(profile, id, biomeId))
		local egg = profile.eggsById[`Craft:{id}`]
		assert(
			egg and egg.kind == "StandardBiomeEgg" and egg.biomeId == biomeId,
			"standard biome egg in inventory"
		)
		assert(
			profile.bossGems == before - ShopConfigs.GemEggPrices[biomeId],
			"only the Gem price is debited"
		)
		assert(profile.coins == 70, "crafting does not charge Coins")
		expectReplay(profile, function()
			return EconomyLedger.craftGemEgg(profile, id, biomeId)
		end)
	end
	assert(profile.bossGems == 0, "exact total craft price")
end)

run("An unavailable biome or insufficient gems cannot grant a crafted egg", function()
	local profile = funded(100_000, 4)
	expectUnchanged(profile, function()
		return EconomyLedger.craftGemEgg(profile, "unsupported", "VoidCitadel")
	end, "UnknownBiome")
	expectUnchanged(profile, function()
		return EconomyLedger.craftGemEgg(profile, "poor", "EmeraldMeadow")
	end, "InsufficientBossGems")
	expectApplied(EconomyLedger.grantBossGems(profile, "craft-funds", 11))
	expectApplied(EconomyLedger.craftGemEgg(profile, "first", "EmeraldMeadow"))
	expectApplied(EconomyLedger.craftGemEgg(profile, "second", "EmeraldMeadow"))
	assert(
		profile.eggsById["Craft:first"] ~= profile.eggsById["Craft:second"],
		"distinct IDs yield distinct eggs"
	)
	expectUnchanged(profile, function()
		return EconomyLedger.craftGemEgg(profile, "first", "FrostbiteCavern")
	end, "TransactionIdConflict")
end)

run("The gem egg mutation pool sums to one hundred and contains no exclusive mutations", function()
	local allowed = { Normal = true, Shiny = true, Golden = true }
	local total = 0
	for _, entry in ShopConfigs.StandardEggMutationOdds do
		assert(allowed[entry.mutation], `exclusive or unknown mutation {entry.mutation}`)
		assert(entry.percent > 0, "positive weight")
		total += entry.percent
	end
	assert(
		total == 100 and #ShopConfigs.StandardEggMutationOdds == 3,
		"exact complete standard pool"
	)
	for _, example in
		{
			{ roll = 0, mutation = "Normal" },
			{ roll = 0.8999, mutation = "Normal" },
			{ roll = 0.90, mutation = "Shiny" },
			{ roll = 0.9899, mutation = "Shiny" },
			{ roll = 0.99, mutation = "Golden" },
			{ roll = 0.999999, mutation = "Golden" },
		}
	do
		assert(
			EconomyLedger.resolveGemEggMutation(example.roll) == example.mutation,
			`mutation at {example.roll}`
		)
	end
	for _, invalid in { -1, 1, 0 / 0, math.huge } do
		assert(EconomyLedger.resolveGemEggMutation(invalid) == nil, "invalid roll rejected")
	end
end)

run(
	"Soft ascension resets Coins and preserves pets, progression, and every other holding",
	function()
		local profile = funded(101_000, 25)
		expectApplied(EconomyLedger.purchaseBallTier(profile, "better-ball", "IronSphere"))
		expectApplied(EconomyLedger.purchaseTargetTier(profile, "better-target", "IronBullseye"))
		expectApplied(EconomyLedger.upgradeOfflineVault(profile, "better-vault"))
		expectApplied(EconomyLedger.craftGemEgg(profile, "saved-egg", "EmeraldMeadow"))
		profile.ballDamage, profile.throwSpeed, profile.level, profile.exp = 71, 4, 6, 38
		profile.lastLogoutTime, profile.pedestalsUnlocked = 2_000, 8
		profile.petsById.pup =
			{ petId = "TrainingPup", level = 7, stars = 2, mutation = "Golden", trait = "Greedy" }
		profile.activePetIds = { "pup" }
		profile.pedestalsById["1"] = { petId = "pup", storedCoins = 222 }
		profile.extensions.newRankBadge = true

		local expected = copyTree(profile)
		expected.coins = 0
		expected.ascensionRank += 1
		expected.transactionReceipts.ascend = { operation = "softAscend" }
		expectApplied(EconomyLedger.softAscend(profile, "ascend"))
		expectSameTree(profile, expected, "entire ascended profile")
		expectReplay(profile, function()
			return EconomyLedger.softAscend(profile, "ascend")
		end)
	end
)

run("Ascension uses the rank threshold and grants additive coin and training bonuses", function()
	local threshold = ShopConfigs.getAscensionCoinThreshold(0)
	local profile = funded(threshold - 1, 11)
	local coins, training = EconomyLedger.getAscensionMultipliers(profile)
	assert(coins == 1 and training == 1, "no initial bonus")
	expectUnchanged(profile, function()
		return EconomyLedger.softAscend(profile, "first-rank")
	end, "AscensionThresholdNotMet")
	expectApplied(EconomyLedger.grantCoins(profile, "missing-coin", 1))
	expectApplied(EconomyLedger.softAscend(profile, "first-rank"))
	assert(profile.coins == 0 and profile.bossGems == 11, "threshold consumes only Coins")
	coins, training = EconomyLedger.getAscensionMultipliers(profile)
	assert(coins == 1.25 and training == 1.05, "rank one bonuses")

	local nextThreshold = ShopConfigs.getAscensionCoinThreshold(1)
	assert(threshold == 100_000 and nextThreshold == 200_000, "configured Coin curve")
	expectApplied(EconomyLedger.grantCoins(profile, "second-rank-funds", nextThreshold))
	expectApplied(EconomyLedger.softAscend(profile, "second-rank"))
	coins, training = EconomyLedger.getAscensionMultipliers(profile)
	assert(
		profile.ascensionRank == 2 and coins == 1.5 and training == 1.10,
		"rank bonuses add instead of compounding"
	)
end)

run("An unrepresentable ascension rank increment leaves Coins untouched", function()
	local max = ShopConfigs.MAX_SAFE_INTEGER
	local profile = funded(max, 3)
	profile.ascensionRank = max
	assert(ShopConfigs.getAscensionCoinThreshold(max) == max, "threshold remains a safe integer")
	expectUnchanged(profile, function()
		return EconomyLedger.softAscend(profile, "rank-overflow")
	end, "ProgressionOverflow")
end)

run("A won Boss Egg is granted once per transaction and only for known kinds", function()
	local profile = EconomyLedger.new()
	expectApplied(EconomyLedger.grantEgg(profile, "win-1", "OverchargedBossEgg", "EmeraldMeadow"))
	local egg = profile.eggsById["Egg:win-1"]
	assert(egg.kind == "OverchargedBossEgg" and egg.biomeId == "EmeraldMeadow", "won egg stored")
	expectReplay(profile, function()
		return EconomyLedger.grantEgg(profile, "win-1", "OverchargedBossEgg", "EmeraldMeadow")
	end)
	expectUnchanged(profile, function()
		return EconomyLedger.grantEgg(profile, "win-1", "StandardBossEgg", "EmeraldMeadow")
	end, "TransactionIdConflict")
	expectUnchanged(profile, function()
		return EconomyLedger.grantEgg(profile, "starter-again", "StarterEgg", "EmeraldMeadow")
	end, "UnknownEggKind")
	expectUnchanged(profile, function()
		return EconomyLedger.grantEgg(profile, "void", "StandardBossEgg", "VoidCitadel")
	end, "UnknownBiome")
end)

print("PASS: EconomyLedger.spec.luau")
