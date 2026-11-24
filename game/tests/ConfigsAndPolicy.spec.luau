--!strict
--[[
	ConfigsAndPolicy.spec.luau
	Verifies BiomeConfigs, PetConfigs, TraitConfigs, EggConfigs (100.0% sum & Boss/Overcharged
	Robux exclusion), and PolicyLogic (ArePaidRandomItemsRestricted fallback + receipt idempotency).
]]

local ArenaCycleLogic = require("../src/shared/Utils/ArenaCycleLogic")
local BiomeConfigs = require("../src/shared/Configs/BiomeConfigs")
local PetConfigs = require("../src/shared/Configs/PetConfigs")
local TraitConfigs = require("../src/shared/Configs/TraitConfigs")
local EggConfigs = require("../src/shared/Configs/EggConfigs")
local EconomyLogic = require("../src/shared/Utils/EconomyLogic")
local PolicyLogic = require("../src/shared/Utils/PolicyLogic")

local function assertTrue(cond: boolean, label: string)
	if not cond then
		error(`Assertion failed: {label}`)
	end
end

local function assertNear(actual: number, expected: number, label: string)
	if math.abs(actual - expected) > 1e-6 then
		error(`{label}: expected {expected}, got {actual}`)
	end
end

-- 1. Biome Boss HP scaling (+35% per extra player, +40% Overcharged)
assertNear(BiomeConfigs.computeBossMaxHP("EmeraldMeadow", 1, false), 900, "Solo Meadow Boss HP")
assertNear(
	BiomeConfigs.computeBossMaxHP("EmeraldMeadow", 4, false),
	math.floor(900 * 2.05 + 0.5),
	"4-player Meadow Boss HP"
)
assertNear(
	BiomeConfigs.computeBossMaxHP("EmeraldMeadow", 1, true),
	math.floor(900 * 1.40 + 0.5),
	"Overcharged Solo Meadow Boss HP"
)

-- 1b. Biome-themed Monster variants and biome-scaled HP progression across all 3 biomes
assertTrue(
	BiomeConfigs.MOBS.MossSlime.displayName == "Forest Monster",
	"Tier-1 Meadow display name"
)
assertTrue(
	BiomeConfigs.MOBS.BrambleBoar.displayName == "Elder Forest Monster",
	"Tier-2 Meadow display name"
)
assertTrue(
	BiomeConfigs.MOBS.IceWraith.displayName == "Frost Monster",
	"Tier-1 Frostbite display name"
)
assertTrue(
	BiomeConfigs.MOBS.CrystalWolf.displayName == "Elder Frost Monster",
	"Tier-2 Frostbite display name"
)
assertTrue(
	BiomeConfigs.MOBS.CinderImp.displayName == "Magma Monster",
	"Tier-1 Caldera display name"
)
assertTrue(
	BiomeConfigs.MOBS.MagmaHound.displayName == "Elder Magma Monster",
	"Tier-2 Caldera display name"
)
assertNear(BiomeConfigs.MOBS.MossSlime.maxHP, 75, "Tier-1 Meadow biome-scaled HP")
assertNear(BiomeConfigs.MOBS.BrambleBoar.maxHP, 140, "Tier-2 Meadow biome-scaled HP")
assertNear(BiomeConfigs.MOBS.IceWraith.maxHP, 950, "Tier-1 Frostbite biome-scaled HP")
assertNear(BiomeConfigs.MOBS.CrystalWolf.maxHP, 1650, "Tier-2 Frostbite biome-scaled HP")
assertNear(BiomeConfigs.MOBS.CinderImp.maxHP, 9000, "Tier-1 Caldera biome-scaled HP")
assertNear(BiomeConfigs.MOBS.MagmaHound.maxHP, 15500, "Tier-2 Caldera biome-scaled HP")
assertTrue(
	BiomeConfigs.MOBS.MossSlime.maxHP < BiomeConfigs.MOBS.BrambleBoar.maxHP
		and BiomeConfigs.MOBS.BrambleBoar.maxHP < BiomeConfigs.MOBS.IceWraith.maxHP
		and BiomeConfigs.MOBS.IceWraith.maxHP < BiomeConfigs.MOBS.CrystalWolf.maxHP
		and BiomeConfigs.MOBS.CrystalWolf.maxHP < BiomeConfigs.MOBS.CinderImp.maxHP
		and BiomeConfigs.MOBS.CinderImp.maxHP < BiomeConfigs.MOBS.MagmaHound.maxHP,
	"Strict biome-tiered monster HP progression"
)
assertNear(BiomeConfigs.MOBS.MossSlime.coinReward, 28, "Tier-1 Meadow coins preserved")
assertNear(BiomeConfigs.MOBS.BrambleBoar.coinReward, 50, "Tier-2 Meadow coins preserved")

-- 2. Trait weights sum to 100%
assertNear(TraitConfigs.getTotalWeight(), 100, "Trait roll weights sum")
assertTrue(TraitConfigs.rollTrait(0.0).id == "Greedy", "First trait bucket Greedy")
assertTrue(TraitConfigs.rollTrait(0.95).id == "Tycoon", "Last trait bucket Tycoon")

-- 3. EggConfig 100.0% sum & Compliance Invariants
for eggId, egg in pairs(EggConfigs.EGGS) do
	local petSum = EggConfigs.getWeightSum(egg.petTable)
	local mutSum = EggConfigs.getWeightSum(egg.mutationTable)
	assertNear(petSum, 100.0, `{eggId} pet weight sum`)
	assertNear(mutSum, 100.0, `{eggId} mutation weight sum`)

	if egg.category == "BiomeBoss" or egg.category == "OverchargedBoss" then
		assertTrue(not EggConfigs.isRobuxPurchasable(eggId), `{eggId} must NEVER be sold for Robux`)
	end
	if egg.isPaidRandomItem then
		for _, entry in ipairs(egg.petTable) do
			local spec = PetConfigs.getSpecies(entry.id)
			assertTrue(
				spec ~= nil and not spec.isBiomeBossPet,
				`{eggId} must never contain Boss pet {entry.id}`
			)
		end
		for _, mut in ipairs(egg.mutationTable) do
			local mSpec = PetConfigs.MUTATIONS[mut.id]
			assertTrue(
				mSpec ~= nil and not mSpec.overchargedOnly,
				`{eggId} must never roll {mut.id}`
			)
		end
	end
end

-- 4. PolicyService Compliance (Unrestricted vs Restricted Region)
local unrestrictedShop = PolicyLogic.buildShopOfferings(false)
assertTrue(#unrestrictedShop == 2, "Unrestricted region sees 2 paid eggs")
assertTrue(unrestrictedShop[1].kind == "PaidEgg", "Unrestricted item 1 is PaidEgg")
assertTrue(
	unrestrictedShop[1].petOdds ~= nil and #unrestrictedShop[1].petOdds == 3,
	"Disclosed odds present"
)

local restrictedShop = PolicyLogic.buildShopOfferings(true)
assertTrue(#restrictedShop == 2, "Restricted region sees 2 direct non-random bundles")
for _, offer in ipairs(restrictedShop) do
	assertTrue(offer.kind == "DirectBundle", "Restricted offer must be DirectBundle (zero RNG)")
	assertTrue(offer.guaranteedPetId ~= nil, "DirectBundle names exact guaranteed pet")
	assertTrue(
		offer.petOdds == nil and offer.mutationOdds == nil,
		"DirectBundle must never expose random odds"
	)
end

-- Nil/unknown policy status must fail closed (never expose paid random eggs)
local nilShop = PolicyLogic.buildShopOfferings(nil :: any)
assertTrue(
	#nilShop == 2 and nilShop[1].kind == "DirectBundle",
	"Nil policy fails closed to DirectBundle"
)
assertTrue(
	not PolicyLogic.canPromptProduct(190000101, nil :: any),
	"Nil policy blocks prompting paid random egg"
)

for _, paidEggProduct in ipairs({ 190000101, 190000102 }) do
	local canPrompt = PolicyLogic.canPromptProduct(paidEggProduct, true)
	assertTrue(not canPrompt, `Restricted account cannot prompt paid random egg {paidEggProduct}`)
end
for _, bundleProduct in ipairs({ 190000201, 190000202 }) do
	local canPrompt = PolicyLogic.canPromptProduct(bundleProduct, true)
	assertTrue(canPrompt, `Restricted account CAN prompt direct bundle {bundleProduct}`)
end

-- 5. Receipt idempotency & restricted paid-random rejection
local profile = EconomyLogic.createDefaultProfile(1000)
local r1 = PolicyLogic.applyProductReceipt(profile, "rcpt_001", 190000201, true)
assertTrue(r1.granted and not r1.duplicate, "First receipt grants Direct Bundle 1")
assertTrue(
	#profile.pets == 1 and profile.pets[1].speciesId == "StarlightBeetle",
	"Direct Bundle 1 pet added"
)
local r1b = PolicyLogic.applyProductReceipt(profile, "rcpt_001b", 190000202, true)
assertTrue(r1b.granted and not r1b.duplicate, "First receipt grants Direct Bundle 2")
assertTrue(
	#profile.pets == 2 and profile.pets[2].speciesId == "NeonMoth",
	"Direct Bundle 2 pet added"
)
local r2 = PolicyLogic.applyProductReceipt(profile, "rcpt_001", 190000201, true)
assertTrue(r2.granted and r2.duplicate, "Duplicate receipt is idempotent")
assertTrue(#profile.pets == 2, "Duplicate receipt did NOT duplicate pet")

for idx, paidEggProduct in ipairs({ 190000101, 190000102 }) do
	local petCountBefore = #profile.pets
	local txCountBefore = #profile.purchaseIds
	local rForbidden =
		PolicyLogic.applyProductReceipt(profile, `rcpt_forb_{idx}`, paidEggProduct, true)
	assertTrue(not rForbidden.granted, `Restricted account receipt {paidEggProduct} rejected`)
	assertTrue(
		#profile.pets == petCountBefore
			and #profile.purchaseIds == txCountBefore
			and profile.eggs.Shop_PrismEgg == nil
			and profile.eggs.Seasonal_CyberEgg == nil,
		"Rejected restricted random egg receipt leaves profile unmutated"
	)
end

local rNil = PolicyLogic.applyProductReceipt(profile, "rcpt_nil_policy", 190000101, nil :: any)
assertTrue(not rNil.granted, "Nil policy receipt for paid random egg fails closed")

local rUnrestricted = PolicyLogic.applyProductReceipt(profile, "rcpt_unrest_1", 190000101, false)
assertTrue(
	rUnrestricted.granted and profile.eggs.Shop_PrismEgg == 1,
	"Unrestricted account receives paid random egg"
)

-- 6. Overcharged & Biome lighting targets (#16)
assertTrue(
	ArenaCycleLogic.isOverchargedVisualActive({
		EmeraldMeadow = { isOvercharged = true, phase = "PvP_EggScramble" },
	}),
	"Overcharged lighting remains active through PvP_EggScramble"
)
assertTrue(not ArenaCycleLogic.isOverchargedVisualActive({
	EmeraldMeadow = { isOvercharged = true, phase = "PvE_Open" },
}), "Overcharged lighting clears once reset to PvE_Open")
local ovLight = ArenaCycleLogic.getBiomeLighting("Hub", "", true)
local hubLight = ArenaCycleLogic.getBiomeLighting("Hub", "", false)
local moltenLight = ArenaCycleLogic.getBiomeLighting("BiomePvE", "MoltenCaldera", false)
assertTrue(
	ovLight.key == "Overcharged"
		and ovLight.clockTime == 20.5
		and hubLight.key == "Hub"
		and moltenLight.key == "Biome:MoltenCaldera",
	"Lighting targets resolve distinctly for Overcharged, Hub, and Biomes"
)

print("PASS: ConfigsAndPolicy.spec.luau")
