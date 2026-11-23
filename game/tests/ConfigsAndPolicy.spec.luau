--!strict
--[[
	ConfigsAndPolicy.spec.luau
	Verifies BiomeConfigs, PetConfigs, TraitConfigs, EggConfigs (100.0% sum & Boss/Overcharged
	Robux exclusion), and PolicyLogic (ArePaidRandomItemsRestricted fallback + receipt idempotency).
]]

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
end

local canPaidEggRestricted = PolicyLogic.canPromptProduct(190000101, true)
assertTrue(not canPaidEggRestricted, "Restricted account cannot prompt paid random egg")
local canDirectRestricted = PolicyLogic.canPromptProduct(190000201, true)
assertTrue(canDirectRestricted, "Restricted account CAN prompt direct bundle")

-- 5. Receipt idempotency
local profile = EconomyLogic.createDefaultProfile(1000)
local r1 = PolicyLogic.applyProductReceipt(profile, "rcpt_001", 190000201, true)
assertTrue(r1.granted and not r1.duplicate, "First receipt grants Direct Bundle")
assertTrue(
	#profile.pets == 1 and profile.pets[1].speciesId == "StarlightBeetle",
	"Direct Bundle pet added"
)
local r2 = PolicyLogic.applyProductReceipt(profile, "rcpt_001", 190000201, true)
assertTrue(r2.granted and r2.duplicate, "Duplicate receipt is idempotent")
assertTrue(#profile.pets == 1, "Duplicate receipt did NOT duplicate pet")

local rForbidden = PolicyLogic.applyProductReceipt(profile, "rcpt_002", 190000101, true)
assertTrue(not rForbidden.granted, "Restricted account receipt for random egg rejected")

print("PASS: ConfigsAndPolicy.spec.luau")
