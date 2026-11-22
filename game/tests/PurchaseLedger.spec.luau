--!strict
local PurchaseLedger = require("../src/shared/Utils/PurchaseLedger")
local EconomyLedger = require("../src/shared/Utils/EconomyLedger")
local MonetizationConfigs = require("../src/shared/Configs/MonetizationConfigs")

type PlayerData = EconomyLedger.PlayerData
type Catalog = MonetizationConfigs.Catalog

local OWNER = 42
local ALLOWED = { ArePaidRandomItemsRestricted = false }
local RESTRICTED = { ArePaidRandomItemsRestricted = true }

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

local function liveCatalog(): Catalog
	local catalog = copyTree(MonetizationConfigs.Catalog)
	catalog.products.ArcadeEgg.productId = 101
	catalog.products.FrostfestEgg.productId = 102
	catalog.products.ArcadeBundle.productId = 103
	catalog.products.FrostfestBundle.productId = 104
	catalog.products.AuroraSkin.productId = 105
	catalog.gamePasses.DoubleTraining.passId = 201
	return catalog
end

local function receipt(id: string, productId: number, userId: number?): PurchaseLedger.ReceiptInfo
	return { PurchaseId = id, ProductId = productId, PlayerId = userId or OWNER }
end

local function apply(
	data: PlayerData,
	raw: unknown,
	policy: unknown,
	catalog: Catalog?
): PurchaseLedger.Result
	return PurchaseLedger.processReceipt(data, OWNER, raw, policy, catalog)
end

local function granted(data: PlayerData, raw: unknown, policy: unknown, catalog: Catalog?)
	local result = apply(data, raw, policy, catalog)
	assert(
		result.decision == "Granted" and result.reason == nil,
		`expected grant, got {result.reason}`
	)
end

local function expectUnchanged(
	data: PlayerData,
	raw: unknown,
	policy: unknown,
	catalog: Catalog?,
	decision: PurchaseLedger.Decision,
	reason: string?
)
	local before = copyTree(data)
	local result = apply(data, raw, policy, catalog)
	assert(
		result.decision == decision and result.reason == reason,
		`expected {decision}/{reason}, got {result.decision}/{result.reason}`
	)
	expectSameTree(data, before, "unchanged receipt profile")
end

run("Paid receipts grant one unopened shop egg with its pinned disclosure pool", function()
	local catalog = liveCatalog()
	for _, example in
		{
			{ product = 101, kind = "PaidPermanentEgg", poolKey = "ArcadeV1" },
			{ product = 102, kind = "PaidSeasonalEgg", poolKey = "FrostfestV1" },
		}
	do
		local data = EconomyLedger.new()
		granted(data, receipt("egg", example.product), ALLOWED, catalog)
		local egg = data.eggsById["PurchaseEgg:egg"] :: PurchaseLedger.PaidEggData
		assert(
			egg.kind == example.kind and egg.poolKey == example.poolKey,
			"persist the exact egg reward"
		)
		assert(
			egg.biomeId == nil and next(data.petsById) == nil,
			"shop egg remains unopened and non-biome"
		)
		assert(data.coins == 0 and data.bossGems == 0, "no currency side effects")
		local marker = data.transactionReceipts["Robux:egg"]
		assert(
			marker.operation == "processDeveloperProduct" and marker.argument == example.product,
			"durable marker matches grant"
		)
		local log = data.extensions.recentRobuxPurchases
		assert(
			#log == 1 and log[1].purchaseId == "egg" and log[1].productId == example.product,
			"one recent entry"
		)
	end
end)

run(
	"Direct bundles grant the fixed pet and cosmetic even with missing or restricted policy",
	function()
		local catalog = liveCatalog()
		for _, example in
			{
				{
					product = 103,
					petId = "ArcadeAxolotl",
					cosmetic = "ArcadeTrail",
					policy = RESTRICTED,
				},
				{
					product = 104,
					petId = "FrostfestHare",
					cosmetic = "FrostfestBallSkin",
					policy = nil,
				},
			}
		do
			local data = EconomyLedger.new()
			granted(data, receipt("bundle", example.product), example.policy, catalog)
			expectSameTree(data.petsById["PurchasePet:bundle"], {
				petId = example.petId,
				mutation = "Normal",
				level = 1,
				stars = 1,
			}, "deterministic bundle pet")
			assert(
				data.extensions.ownedCosmeticKeys[example.cosmetic] == true,
				"deterministic cosmetic"
			)
			assert(data.eggsById["PurchaseEgg:bundle"] == nil, "bundle delivers no egg")
			expectUnchanged(
				data,
				receipt("bundle", example.product),
				example.policy,
				catalog,
				"AlreadyGranted"
			)
		end
	end
)

run("A direct cosmetic receipt grants only the named cosmetic and records the receipt", function()
	local data = EconomyLedger.new()
	local catalog = liveCatalog()
	granted(data, receipt("skin", 105), nil, catalog)
	assert(data.extensions.ownedCosmeticKeys.AuroraBallSkin == true, "exact skin granted")
	assert(
		next(data.petsById) == nil and data.eggsById["PurchaseEgg:skin"] == nil,
		"skin grants no pet or egg"
	)
	assert(data.transactionReceipts["Robux:skin"].argument == 105, "receipt marker recorded")
	expectUnchanged(data, receipt("skin", 105), nil, catalog, "AlreadyGranted")
end)

run("Restricted and unknown policies reject paid receipts without substituting a bundle", function()
	local data = EconomyLedger.new()
	local catalog = liveCatalog()
	for _, productId in { 101, 102 } do
		expectUnchanged(
			data,
			receipt("denied", productId),
			RESTRICTED,
			catalog,
			"Rejected",
			"PolicyRestricted"
		)
		expectUnchanged(
			data,
			receipt("denied", productId),
			nil,
			catalog,
			"Rejected",
			"PolicyRestricted"
		)
		expectUnchanged(
			data,
			receipt("denied", productId),
			{},
			catalog,
			"Rejected",
			"PolicyRestricted"
		)
	end
	granted(data, receipt("denied", 101), ALLOWED, catalog)
	assert(
		data.eggsById["PurchaseEgg:denied"] ~= nil,
		"a failed receipt can be retried once authorized"
	)
end)

run("Exact receipt replays survive profile reload and policy or catalog changes", function()
	local data = EconomyLedger.new()
	local catalog = liveCatalog()
	granted(data, receipt("replay", 101), ALLOWED, catalog)
	local migrated = EconomyLedger.migrate(data)
	assert(migrated.ok, "profile migrates")
	local loaded = assert(migrated.data, "reloaded profile")
	loaded.eggsById["PurchaseEgg:replay"] = nil
	catalog.products.ArcadeEgg = nil
	expectUnchanged(loaded, receipt("replay", 101), RESTRICTED, catalog, "AlreadyGranted")
	assert(loaded.eggsById["PurchaseEgg:replay"] == nil, "a consumed egg is never reissued")
end)

run("A receipt belongs to the exact player and product", function()
	local data = EconomyLedger.new()
	local catalog = liveCatalog()
	expectUnchanged(data, receipt("bound", 103, 99), ALLOWED, catalog, "Rejected", "WrongPlayer")
	granted(data, receipt("bound", 103), ALLOWED, catalog)
	expectUnchanged(
		data,
		receipt("bound", 104),
		RESTRICTED,
		catalog,
		"Rejected",
		"PurchaseIdConflict"
	)
	expectUnchanged(data, receipt("bound", 103, 99), ALLOWED, catalog, "Rejected", "WrongPlayer")
end)

run("Malformed receipt IDs and numbers are rejected with zero mutation", function()
	local data = EconomyLedger.new()
	local catalog = liveCatalog()
	expectUnchanged(data, nil, ALLOWED, catalog, "Rejected", "InvalidReceipt")
	expectUnchanged(data, "bad", ALLOWED, catalog, "Rejected", "InvalidReceipt")
	expectUnchanged(data, {}, ALLOWED, catalog, "Rejected", "InvalidReceipt")
	expectUnchanged(data, receipt("", 103), ALLOWED, catalog, "Rejected", "InvalidReceipt")
	for _, invalid in { 0, -1, 0.5, 0 / 0, math.huge, 9_007_199_254_740_992 } do
		expectUnchanged(
			data,
			receipt("invalid", invalid),
			ALLOWED,
			catalog,
			"Rejected",
			"InvalidReceipt"
		)
	end
	expectUnchanged(
		data,
		receipt("invalid", 103, math.huge),
		ALLOWED,
		catalog,
		"Rejected",
		"InvalidReceipt"
	)
end)

run("Unknown product IDs and Game Pass IDs cannot be granted by ProcessReceipt", function()
	local data = EconomyLedger.new()
	local catalog = liveCatalog()
	expectUnchanged(data, receipt("unknown", 999), ALLOWED, catalog, "Rejected", "UnknownProduct")
	expectUnchanged(data, receipt("pass", 201), ALLOWED, catalog, "Rejected", "UnknownProduct")
	expectUnchanged(data, receipt("not-published", 103), ALLOWED, nil, "Rejected", "UnknownProduct")
end)

run("Duplicate active product IDs fail closed rather than choosing a reward", function()
	local data = EconomyLedger.new()
	local catalog = liveCatalog()
	catalog.products.FrostfestBundle.productId = 103
	expectUnchanged(
		data,
		receipt("ambiguous", 103),
		ALLOWED,
		catalog,
		"Rejected",
		"AmbiguousProductId"
	)
end)

run("Live receipts reject boss eggs and every forbidden paid reward before mutation", function()
	local data = EconomyLedger.new()
	local catalog = liveCatalog()
	local invalid = catalog :: any
	for _, kind in { "StandardBiomeEgg", "StandardBossEgg", "OverchargedBossEgg" } do
		invalid.products.Invalid = { productId = 501, kind = kind }
		expectUnchanged(data, receipt("boss", 501), ALLOWED, catalog, "Rejected", "ForbiddenGrant")
	end
	for _, mutation in { "Overcharged", "VoidTouched" } do
		local bundle = assert(catalog.products.ArcadeBundle.bundle, "direct bundle")
		bundle.mutation = mutation
		expectUnchanged(
			data,
			receipt("exclusive-bundle", 103),
			RESTRICTED,
			catalog,
			"Rejected",
			"ForbiddenGrant"
		)
		catalog.paidEggPools.ArcadeV1.odds[1].mutation = mutation
		expectUnchanged(
			data,
			receipt("exclusive-egg", 101),
			ALLOWED,
			catalog,
			"Rejected",
			"ForbiddenGrant"
		)
	end
	catalog.paidEggPools.FrostfestV1.odds[1].petId = "GolemHeart"
	expectUnchanged(
		data,
		receipt("earned-pet", 102),
		ALLOWED,
		catalog,
		"Rejected",
		"ForbiddenGrant"
	)
end)

run("A receipt with a malformed disclosure pool is rejected without granting or saving", function()
	local data = EconomyLedger.new()
	local catalog = liveCatalog()
	catalog.paidEggPools.ArcadeV1.odds[1].basisPoints = 7_749
	expectUnchanged(data, receipt("bad-odds", 101), ALLOWED, catalog, "Rejected", "InvalidOdds")
end)

run("The recent log stays bounded without reopening older receipt IDs", function()
	local data = EconomyLedger.new()
	local catalog = liveCatalog()
	local limit = MonetizationConfigs.RECENT_PURCHASE_LIMIT
	assert(limit == 100, "recent receipt limit")
	granted(data, receipt("older", 103), nil, catalog)
	for index = 1, limit + 3 do
		granted(data, receipt(`filler-{index}`, 105), nil, catalog)
	end
	local log = data.extensions.recentRobuxPurchases
	assert(#log == limit and log[1].purchaseId == "filler-4", "oldest entries leave the recent log")
	assert(log[limit].purchaseId == `filler-{limit + 3}`, "latest entry is retained")
	local migrated = EconomyLedger.migrate(data)
	assert(migrated.ok, "reload after recent log trim")
	local loaded = assert(migrated.data, "reloaded profile")
	loaded.petsById["PurchasePet:older"] = nil
	expectUnchanged(loaded, receipt("older", 103), nil, catalog, "AlreadyGranted")
	assert(
		loaded.transactionReceipts["Robux:older"].argument == 103,
		"marker outlives the recent log"
	)
	assert(
		loaded.petsById["PurchasePet:older"] == nil,
		"trimmed receipt does not recreate a removed pet"
	)
end)

run("A grant collision or invalid purchase log cannot leave a partial reward", function()
	local data = EconomyLedger.new()
	local catalog = liveCatalog()
	data.petsById["PurchasePet:collision"] =
		{ petId = "TrainingPup", level = 1, stars = 1, mutation = "Normal" }
	expectUnchanged(data, receipt("collision", 103), nil, catalog, "Rejected", "GrantConflict")
	data.eggsById["PurchaseEgg:collision"] = { kind = "StandardBossEgg", biomeId = "EmeraldMeadow" }
	expectUnchanged(data, receipt("collision", 101), ALLOWED, catalog, "Rejected", "GrantConflict")
	data.extensions.recentRobuxPurchases = "corrupt"
	expectUnchanged(data, receipt("corrupt", 104), nil, catalog, "Rejected", "InvalidPurchaseLog")
end)

run("Corrupt cosmetic ownership cannot partially grant a direct bundle", function()
	local data = EconomyLedger.new()
	data.extensions.ownedCosmeticKeys = "corrupt"
	expectUnchanged(
		data,
		receipt("corrupt-cosmetics", 103),
		nil,
		liveCatalog(),
		"Rejected",
		"InvalidProfile"
	)
end)

run("Ordinary ledger transaction IDs and namespaced Robux receipts stay distinct", function()
	local data = EconomyLedger.new()
	local catalog = liveCatalog()
	assert(EconomyLedger.grantCoins(data, "same", 5).ok, "ordinary ledger transaction")
	granted(data, receipt("same", 105), nil, catalog)
	assert(
		data.coins == 5 and data.transactionReceipts.same.operation == "grantCoins",
		"wallet unchanged"
	)
	assert(
		data.transactionReceipts["Robux:same"].operation == "processDeveloperProduct",
		"separate receipt marker"
	)
	assert(
		EconomyLedger.grantCoins(data, "Robux:blocked", 2).ok,
		"preexisting migrated namespace collision"
	)
	expectUnchanged(data, receipt("blocked", 105), nil, catalog, "Rejected", "PurchaseIdConflict")
end)

print("PASS: PurchaseLedger.spec.luau")
