--!strict
local PolicyGuard = require("../src/shared/Utils/PolicyGuard")
local MonetizationConfigs = require("../src/shared/Configs/MonetizationConfigs")
local PetConfigs = require("../src/shared/Configs/PetConfigs")

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

local function liveCatalog(): MonetizationConfigs.Catalog
	local catalog = copyTree(MonetizationConfigs.Catalog)
	catalog.products.ArcadeEgg.productId = 101
	catalog.products.FrostfestEgg.productId = 102
	catalog.products.ArcadeBundle.productId = 103
	catalog.products.FrostfestBundle.productId = 104
	catalog.products.AuroraSkin.productId = 105
	catalog.gamePasses.DoubleTraining.passId = 201
	return catalog
end

local function expectDenied(
	snapshot: unknown,
	key: string,
	catalog: MonetizationConfigs.Catalog?,
	reason: string
)
	local allowed, actualReason = PolicyGuard.canPurchase(snapshot, key, catalog)
	assert(not allowed and actualReason == reason, `expected {reason}, got {actualReason}`)
end

run("Only an explicit false paid-random restriction allows random purchase policy", function()
	assert(not PolicyGuard.isRestricted(ALLOWED), "explicit false is allowed")
	assert(PolicyGuard.isRestricted(RESTRICTED), "explicit true is restricted")
	assert(PolicyGuard.isRestricted(nil), "failed or missing PolicyService result is restricted")
	for _, snapshot in
		{
			false,
			"policy lookup failed",
			{},
			{ ArePaidRandomItemsRestricted = "false" },
			{ ArePaidRandomItemsRestricted = 0 },
			{ IsPaidItemTradingAllowed = true },
		}
	do
		assert(PolicyGuard.isRestricted(snapshot), "malformed or unrelated flags fail closed")
	end
end)

run("Permanent and seasonal paid eggs disclose exact species and mutation odds", function()
	local catalog = liveCatalog()
	for _, example in
		{
			{ key = "ArcadeEgg", productId = 101, percentages = { "77.50%", "20.00%", "2.50%" } },
			{
				key = "FrostfestEgg",
				productId = 102,
				percentages = { "83.25%", "16.50%", "0.25%" },
			},
		}
	do
		local view = PolicyGuard.getOfferDisplay(ALLOWED, example.key, catalog)
		assert(
			view.kind == "PaidEgg" and view.productId == example.productId,
			"approved paid egg offer"
		)
		assert(
			view.offerKey == example.key and view.totalText == "100.0%",
			"exact disclosure total"
		)
		assert(PolicyGuard.canPurchase(ALLOWED, example.key, catalog), "exact product allowed")
		local displayedRows = assert(view.odds, "paid offer must disclose odds")
		assert(#displayedRows == 3 and view.bundle == nil, "all outcomes disclosed")
		local poolKey = assert(catalog.products[example.key].poolKey, "egg pool")
		for index, expected in example.percentages do
			local display = displayedRows[index]
			local source = catalog.paidEggPools[poolKey].odds[index]
			assert(display.percentText == expected, "basis points are displayed without rounding")
			assert(
				display.petId == source.petId and display.mutation == source.mutation,
				"exact outcome identity"
			)
			assert(display.basisPoints == source.basisPoints, "exact displayed odds data")
		end
	end
end)

run("Restricted and unknown policy swap both egg offers to deterministic bundles", function()
	local catalog = liveCatalog()
	for _, example in
		{
			{
				egg = "ArcadeEgg",
				bundle = "ArcadeBundle",
				id = 103,
				pet = "ArcadeAxolotl",
				cosmetic = "ArcadeTrail",
			},
			{
				egg = "FrostfestEgg",
				bundle = "FrostfestBundle",
				id = 104,
				pet = "FrostfestHare",
				cosmetic = "FrostfestBallSkin",
			},
		}
	do
		expectDenied(RESTRICTED, example.egg, catalog, "PolicyRestricted")
		expectDenied(nil, example.egg, catalog, "PolicyRestricted")
		for _, snapshot in { RESTRICTED, {} } do
			local view = PolicyGuard.getOfferDisplay(snapshot, example.egg, catalog)
			assert(
				view.kind == "DirectBundle" and view.offerKey == example.bundle,
				"resolves to the direct bundle"
			)
			assert(
				view.productId == example.id and view.odds == nil and view.totalText == nil,
				"no random prompt or odds"
			)
			local bundle = assert(view.bundle, "fixed reward details")
			assert(
				bundle.petId == example.pet and bundle.mutation == "Normal",
				"exact pet and mutation"
			)
			assert(bundle.cosmeticKey == example.cosmetic, "exact cosmetic")
			assert(
				PolicyGuard.canPurchase(snapshot, example.bundle, catalog),
				"fixed bundle is allowed"
			)
		end
	end
end)

run("An unavailable or non-direct fallback never exposes a random purchase action", function()
	local catalog = liveCatalog()
	catalog.products.ArcadeBundle.productId = 0
	local view = PolicyGuard.getOfferDisplay(RESTRICTED, "ArcadeEgg", catalog)
	assert(
		view.kind == "Unavailable" and view.productId == nil and view.odds == nil,
		"blocked fallback"
	)
	catalog.products.ArcadeEgg.directBundleKey = "FrostfestEgg"
	view = PolicyGuard.getOfferDisplay(RESTRICTED, "ArcadeEgg", catalog)
	assert(view.kind == "Unavailable" and view.productId == nil, "fallback must be a direct bundle")
	catalog.products.ArcadeEgg.directBundleKey = "Missing"
	view = PolicyGuard.getOfferDisplay(RESTRICTED, "ArcadeEgg", catalog)
	assert(view.kind == "Unavailable" and view.odds == nil, "missing fallback")
end)

run("Fixed cosmetics and active game passes remain available without random policy", function()
	local catalog = liveCatalog()
	assert(PolicyGuard.canPurchase(nil, "AuroraSkin", catalog), "deterministic cosmetic")
	local skin = PolicyGuard.getOfferDisplay(RESTRICTED, "AuroraSkin", catalog)
	assert(skin.kind == "Cosmetic" and skin.productId == 105 and skin.odds == nil, "cosmetic view")
	assert(skin.cosmeticKey == "AuroraBallSkin", "specific promised skin")
	assert(
		PolicyGuard.canPurchase(RESTRICTED, "DoubleTraining", catalog),
		"a pass does not roll an egg"
	)
	local pass = PolicyGuard.getOfferDisplay(nil, "DoubleTraining", catalog)
	assert(
		pass.kind == "GamePass" and pass.passId == 201 and pass.productId == nil,
		"pass keeps its own ID namespace"
	)
end)

run("TODO placeholders are disabled and unknown keys have no actionable display", function()
	for key, pass in MonetizationConfigs.Catalog.gamePasses do
		assert(pass.passId == 0, "placeholder pass IDs start disabled")
		expectDenied(ALLOWED, key, nil, "DisabledOffer")
		assert(
			PolicyGuard.getOfferDisplay(ALLOWED, key).kind == "Unavailable",
			"no placeholder prompt"
		)
	end
	for key, product in MonetizationConfigs.Catalog.products do
		assert(product.productId == 0, "placeholder product IDs start disabled")
		expectDenied(ALLOWED, key, nil, "DisabledOffer")
		assert(
			PolicyGuard.getOfferDisplay(ALLOWED, key).productId == nil,
			"cannot prompt a zero ID"
		)
	end
	for _, key in
		{ "DoubleTraining", "DoubleCoinsExp", "AutoFire", "MagnetCollect", "ExtraPedestals" }
	do
		assert(MonetizationConfigs.Catalog.gamePasses[key], `specified pass {key}`)
	end
	expectDenied(ALLOWED, "Missing", nil, "UnknownOffer")
	assert(PolicyGuard.getOfferDisplay(ALLOWED, "Missing").kind == "Unavailable", "unknown offer")
end)

run("Ambiguous product IDs and invalid active IDs do not produce purchase actions", function()
	local catalog = liveCatalog()
	catalog.products.FrostfestBundle.productId = catalog.products.ArcadeBundle.productId
	expectDenied(ALLOWED, "ArcadeBundle", catalog, "AmbiguousProductId")
	assert(
		PolicyGuard.getOfferDisplay(ALLOWED, "ArcadeBundle", catalog).productId == nil,
		"ambiguous product cannot prompt"
	)
	for _, id in { -1, 1.5, 0 / 0, math.huge } do
		catalog.gamePasses.DoubleTraining.passId = id
		expectDenied(ALLOWED, "DoubleTraining", catalog, "InvalidOffer")
	end
end)

run(
	"Odds formatting preserves one basis point and rejects totals on either side of one hundred",
	function()
		local valid = PolicyGuard.formatOdds({
			{ petId = "A", mutation = "Normal", basisPoints = 9_999 },
			{ petId = "B", mutation = "Golden", basisPoints = 1 },
		})
		assert(
			valid.ok and valid.totalBasisPoints == 10_000 and valid.totalText == "100.0%",
			"exact combined total"
		)
		local rows = assert(valid.rows, "validated odds")
		assert(
			rows[1].percentText == "99.99%" and rows[2].percentText == "0.01%",
			"no rounding to tenths"
		)
		for _, amount in { 9_999, 10_001 } do
			local invalid = PolicyGuard.formatOdds({
				{ petId = "A", mutation = "Normal", basisPoints = amount },
			})
			assert(
				not invalid.ok and invalid.reason == "InvalidOdds" and invalid.rows == nil,
				"total must match exactly"
			)
		end
	end
)

run("Odds reject malformed rows, noninteger weights, duplicates, and sparse arrays", function()
	for _, weight in { 0, -1, 0.5, 0 / 0, math.huge, -math.huge } do
		local result =
			PolicyGuard.formatOdds({ { petId = "A", mutation = "Normal", basisPoints = weight } })
		assert(not result.ok and result.rows == nil, "invalid row weight")
	end
	local half = { petId = "A", mutation = "Normal", basisPoints = 5_000 }
	for _, invalid in
		{
			{},
			"not an odds table",
			{ [2] = { petId = "A", mutation = "Normal", basisPoints = 10_000 } },
			{ half, half },
			{ { petId = "", mutation = "Normal", basisPoints = 10_000 } },
			{ { petId = "A", mutation = "", basisPoints = 10_000 } },
		}
	do
		assert(not PolicyGuard.formatOdds(invalid).ok, "invalid odds structure")
	end
end)

run("Earned boss preview odds can be disclosed without creating a Robux offer", function()
	local odds = {}
	for _, species in PetConfigs.HatchPoolsByBiome.EmeraldMeadow.overcharged do
		for _, mutation in PetConfigs.OverchargedMutationOdds do
			table.insert(odds, {
				petId = species.petId,
				mutation = mutation.mutation,
				basisPoints = species.percent * mutation.percent,
			})
		end
	end
	local display = PolicyGuard.formatOdds(odds)
	assert(display.ok and display.totalBasisPoints == 10_000, "earned joint odds disclose exactly")
	expectDenied(ALLOWED, "OverchargedBossEgg", nil, "UnknownOffer")
end)

run(
	"A misconfigured paid pool with invalid odds is disabled instead of showing a purchase",
	function()
		local catalog = liveCatalog()
		catalog.paidEggPools.ArcadeV1.odds[1].basisPoints = 7_749
		expectDenied(ALLOWED, "ArcadeEgg", catalog, "InvalidOdds")
		local display = PolicyGuard.getOfferDisplay(ALLOWED, "ArcadeEgg", catalog)
		assert(
			display.kind == "Unavailable" and display.productId == nil and display.odds == nil,
			"no invalid paid action"
		)
		assert(
			PolicyGuard.resolvePaidEggRoll("ArcadeV1", 0, catalog) == nil,
			"invalid odds cannot resolve a paid hatch"
		)
	end
)

run("Paid offers cannot contain gameplay-earned species or exclusive mutations", function()
	for _, mutation in { "Overcharged", "VoidTouched" } do
		local catalog = liveCatalog()
		catalog.paidEggPools.ArcadeV1.odds[1].mutation = mutation
		expectDenied(ALLOWED, "ArcadeEgg", catalog, "ForbiddenGrant")
		assert(
			PolicyGuard.resolvePaidEggRoll("ArcadeV1", 0, catalog) == nil,
			"exclusive pool cannot hatch"
		)
		local bundle = assert(catalog.products.ArcadeBundle.bundle, "fixed bundle")
		bundle.mutation = mutation
		expectDenied(RESTRICTED, "ArcadeBundle", catalog, "ForbiddenGrant")
		assert(
			PolicyGuard.getOfferDisplay(RESTRICTED, "ArcadeEgg", catalog).kind == "Unavailable",
			"invalid bundle stays hidden"
		)
	end
	local catalog = liveCatalog()
	catalog.paidEggPools.FrostfestV1.odds[1].petId = "PebbleCub"
	expectDenied(ALLOWED, "FrostfestEgg", catalog, "ForbiddenGrant")
end)

run("Paid hatch rolls use the exact disclosed joint outcome boundaries", function()
	for _, example in
		{
			{ roll = 0, pet = "ArcadeAxolotl", mutation = "Normal" },
			{ roll = 0.774999, pet = "ArcadeAxolotl", mutation = "Normal" },
			{ roll = 0.775, pet = "NeonKitsune", mutation = "Shiny" },
			{ roll = 0.975, pet = "NeonKitsune", mutation = "Golden" },
			{ roll = 0.99999, pet = "NeonKitsune", mutation = "Golden" },
		}
	do
		local outcome =
			assert(PolicyGuard.resolvePaidEggRoll("ArcadeV1", example.roll), "paid hatch outcome")
		assert(
			outcome.petId == example.pet and outcome.mutation == example.mutation,
			`outcome at {example.roll}`
		)
	end
	for _, roll in { -1, 1, 0 / 0, math.huge } do
		assert(PolicyGuard.resolvePaidEggRoll("ArcadeV1", roll) == nil, "invalid roll")
	end
	assert(PolicyGuard.resolvePaidEggRoll("MissingPool", 0) == nil, "missing pool")
end)

print("PASS: PolicyGuard.spec.luau")
