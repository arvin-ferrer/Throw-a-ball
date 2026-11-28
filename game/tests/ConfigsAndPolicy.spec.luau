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
local MonetizationConfigs = require("../src/shared/Configs/MonetizationConfigs")
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

-- 1b. Emerald Meadow 10-mob roster (5 Base + 5 Natural Area Elites) & biome-scaled HP progression
assertTrue(BiomeConfigs.MOBS.MossSlime.displayName == "Moss Slime", "Base Meadow Slime name")
assertTrue(BiomeConfigs.MOBS.BrambleBoar.displayName == "Bramble Boar", "Base Meadow Boar name")
assertTrue(
	BiomeConfigs.MOBS.MeadowWitch.rangedAttack ~= nil
		and BiomeConfigs.MOBS.MeadowWitch.rangedAttack.gravity == 42,
	"MeadowWitch has non-homing ballistic ranged spec"
)
assertTrue(
	BiomeConfigs.MOBS.CovenArchWitch.isElite == true
		and BiomeConfigs.MOBS.CovenArchWitch.rangedAttack ~= nil
		and BiomeConfigs.MOBS.CovenArchWitch.rangedAttack.volleyCount == 2,
	"CovenArchWitch elite fires 2-orb staggered volley"
)
assertTrue(
	BiomeConfigs.MOBS.IceWraith.displayName == "Frost Monster",
	"Tier-1 Frostbite display name untouched"
)
assertTrue(
	BiomeConfigs.MOBS.CrystalWolf.displayName == "Elder Frost Monster",
	"Tier-2 Frostbite display name untouched"
)
assertTrue(
	BiomeConfigs.MOBS.CinderImp.displayName == "Magma Monster",
	"Tier-1 Caldera display name untouched"
)
assertTrue(
	BiomeConfigs.MOBS.MagmaHound.displayName == "Elder Magma Monster",
	"Tier-2 Caldera display name untouched"
)
assertNear(BiomeConfigs.MOBS.MossSlime.maxHP, 75, "Base MossSlime HP")
assertNear(BiomeConfigs.MOBS.BrambleBoar.maxHP, 145, "Base BrambleBoar HP")
assertNear(BiomeConfigs.MOBS.AncientWarden.maxHP, 350, "Top Emerald Meadow Elite HP")
assertNear(BiomeConfigs.MOBS.IceWraith.maxHP, 950, "Tier-1 Frostbite biome-scaled HP")
assertNear(BiomeConfigs.MOBS.CrystalWolf.maxHP, 1650, "Tier-2 Frostbite biome-scaled HP")
assertNear(BiomeConfigs.MOBS.CinderImp.maxHP, 9000, "Tier-1 Caldera biome-scaled HP")
assertNear(BiomeConfigs.MOBS.MagmaHound.maxHP, 15500, "Tier-2 Caldera biome-scaled HP")
assertTrue(
	#BiomeConfigs.BIOMES.EmeraldMeadow.mobs == 10,
	"Emerald Meadow registers all 10 Base + Elite mobs"
)
for _, mobId in ipairs(BiomeConfigs.BIOMES.EmeraldMeadow.mobs) do
	local m = BiomeConfigs.MOBS[mobId]
	assertTrue(m ~= nil and m.biomeId == "EmeraldMeadow", `Emerald Meadow mob exists: {mobId}`)
	assertTrue(
		m.maxHP < BiomeConfigs.BOSSES.MossbackGolem.baseHP
			and m.maxHP < BiomeConfigs.MOBS.IceWraith.maxHP,
		`{mobId} HP stays strictly below Meadow Boss (900) and Frostbite Tier-1 (950)`
	)
end
assertTrue(
	BiomeConfigs.MOBS.MossSlime.maxHP < BiomeConfigs.MOBS.BrambleBoar.maxHP
		and BiomeConfigs.MOBS.BrambleBoar.maxHP < BiomeConfigs.MOBS.AncientWarden.maxHP
		and BiomeConfigs.MOBS.AncientWarden.maxHP < BiomeConfigs.MOBS.IceWraith.maxHP
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

local function verifyJointOddsForOffer(offer: PolicyLogic.ShopCatalogItem)
	local egg = EggConfigs.getEgg(offer.id)
	assertTrue(egg ~= nil, `Paid egg config exists for {offer.id}`)
	local jointOdds = offer.jointOdds :: { PolicyLogic.JointOdd }
	assertTrue(
		jointOdds ~= nil and #jointOdds == 9,
		`{offer.id} exposes all 9 species x mutation jointOdds`
	)
	local seen: { [string]: boolean } = {}
	local totalPercent = 0
	for _, odd in ipairs(jointOdds) do
		local key = `{odd.speciesId}:{odd.mutationKey}`
		assertTrue(not seen[key], `{offer.id} joint odd {key} is unique`)
		seen[key] = true
		assertTrue(
			odd.formattedPercent == string.format("%.2f%%", odd.percent),
			`{offer.id} {key} formatted to 2 decimal places`
		)
		totalPercent += odd.percent
	end
	assertNear(totalPercent, 100.0, `{offer.id} jointOdds sum to 100.00%`)
	assertTrue(
		string.format("%.2f%%", totalPercent) == "100.00%",
		`{offer.id} formatted jointOdds sum equals 100.00%`
	)
end

local function verifyPaidEggJointOdds(
	unrestricted: { PolicyLogic.ShopCatalogItem },
	restricted: { PolicyLogic.ShopCatalogItem },
	nilPolicy: { PolicyLogic.ShopCatalogItem }
)
	for _, offer in ipairs(unrestricted) do
		verifyJointOddsForOffer(offer)
	end
	local prismJoint = unrestricted[1].jointOdds :: { PolicyLogic.JointOdd }
	local cyberJoint = unrestricted[2].jointOdds :: { PolicyLogic.JointOdd }
	assertNear(prismJoint[1].percent, 41.25, "PrismFox Normal exact joint odd")
	assertNear(prismJoint[2].percent, 9.90, "PrismFox Shiny exact joint odd")
	assertNear(prismJoint[9].percent, 0.84, "AegisGryphon Golden exact joint odd")
	assertNear(cyberJoint[1].percent, 41.25, "CyberHound Normal exact joint odd")
	assertNear(cyberJoint[5].percent, 5.94, "NeonMoth Shiny exact joint odd")
	assertNear(cyberJoint[9].percent, 0.84, "VoltSerpent Golden exact joint odd")
	for _, list in ipairs({ restricted, nilPolicy }) do
		for _, offer in ipairs(list) do
			assertTrue(offer.jointOdds == nil, "DirectBundle must never expose jointOdds")
		end
	end
end

local function verifyRestrictedPaidHatchFallback()
	local p = EconomyLogic.createDefaultProfile(2000)
	local noEgg = PolicyLogic.hatchEggWithPolicy(p, "Shop_PrismEgg", 1, false, true)
	assertTrue(
		not noEgg.ok and noEgg.reason == "NoEggInInventory",
		"Restricted paid hatch fails closed when player owns 0 eggs"
	)

	local grant = PolicyLogic.applyProductReceipt(p, "rcpt_owned_prism", 190000101, false)
	assertTrue(grant.granted and p.eggs.Shop_PrismEgg == 1, "Owned paid egg seeded")

	-- Even with extreme RNG rolls (0.99, 0.99), restricted policy hatches deterministic bundle
	local r1 = PolicyLogic.hatchEggWithPolicy(p, "Shop_PrismEgg", 1, false, true, 0.99, 0.99)
	local bundle1 = MonetizationConfigs.getDirectBundleForEgg("Shop_PrismEgg")
	assertTrue(r1.ok and r1.data ~= nil and bundle1 ~= nil, "Restricted paid hatch succeeds")
	assertTrue((r1.data :: any).directBundle == true, "Restricted paid hatch reports directBundle")
	assertTrue(p.eggs.Shop_PrismEgg == nil, "Consumes 1 Shop_PrismEgg on fallback hatch")
	assertTrue(
		#p.pets == 1
			and p.pets[1].uid == "pet_1"
			and p.pets[1].speciesId == (bundle1 :: any).guaranteedPetId
			and p.pets[1].mutationKey == (bundle1 :: any).guaranteedMutation
			and p.pets[1].pedestalIndex == 1
			and p.nextPetSeq == 2,
		"Fallback hatch awards guaranteed pet, mutation, uid, and pedestal placement"
	)
	assertTrue(
		p.codexUnlocked[(bundle1 :: any).guaranteedPetId] == true
			and p.ownedCosmetics[(bundle1 :: any).guaranteedBallSkin] == true
			and p.equippedBallSkin == (bundle1 :: any).guaranteedBallSkin
			and #p.activeFollowerUids == 1
			and p.activeFollowerUids[1] == "pet_1",
		"Fallback hatch updates codex, ownedCosmetics, ballSkin, and active follower slot"
	)
end

local function verifyNilPolicyHatchAndNonClobber()
	local p = EconomyLogic.createDefaultProfile(3000)
	assertTrue(
		PolicyLogic.applyProductReceipt(p, "rcpt_cyber_1", 190000102, false).granted
			and PolicyLogic.applyProductReceipt(p, "rcpt_cyber_2", 190000102, false).granted,
		"Seeded 2 Seasonal_CyberEggs"
	)
	p.equippedBallSkin = "PrismTrail"

	local okNil = PolicyLogic.hatchEggWithPolicy(p, "Seasonal_CyberEgg", 1, false, nil :: any)
	assertTrue(okNil.ok, "First Seasonal_CyberEgg hatches on pedestal 1 under nil policy")
	assertTrue(p.pets[1].speciesId == "NeonMoth" and p.pets[1].mutationKey == "Normal", "Zero RNG")
	assertTrue(
		p.ownedCosmetics.CyberPulse == true and p.equippedBallSkin == "PrismTrail",
		"Unlocks CyberPulse without clobbering already equipped ball skin"
	)

	local failOcc = PolicyLogic.hatchEggWithPolicy(p, "Seasonal_CyberEgg", 1, false, nil :: any)
	assertTrue(
		not failOcc.ok and failOcc.reason == "PedestalOccupied" and p.eggs.Seasonal_CyberEgg == 1,
		"Occupied pedestal fails closed without consuming paid egg"
	)
	local failLock = PolicyLogic.hatchEggWithPolicy(p, "Seasonal_CyberEgg", 5, false, true)
	assertTrue(
		not failLock.ok and failLock.reason == "PedestalLocked" and p.eggs.Seasonal_CyberEgg == 1,
		"Locked pedestal fails closed without consuming paid egg"
	)
end

local function verifyUnrestrictedAndDeterministicRepeats()
	local p = EconomyLogic.createDefaultProfile(4000)
	assertTrue(
		PolicyLogic.applyProductReceipt(p, "rcpt_prism_unr", 190000101, false).granted,
		"Seeded unrestricted Shop_PrismEgg"
	)
	local rUnr = PolicyLogic.hatchEggWithPolicy(p, "Shop_PrismEgg", 2, false, false, 0.99, 0.99)
	assertTrue(
		rUnr.ok
			and (rUnr.data :: any).pet.speciesId == "AegisGryphon"
			and (rUnr.data :: any).pet.mutationKey == "Golden",
		"Unrestricted hatch uses normal weighted RNG"
	)
	local rStarter = PolicyLogic.hatchEggWithPolicy(p, "StarterEgg", 3, false, true)
	assertTrue(
		rStarter.ok
			and (rStarter.data :: any).pet.speciesId == "TrainingPup"
			and p.starterEggHatched,
		"Non-paid StarterEgg hatches normally even under restricted policy"
	)

	local pRep = EconomyLogic.createDefaultProfile(5000)
	pRep.pedestalsUnlocked = 6
	for idx = 1, 4 do
		assertTrue(
			PolicyLogic.applyProductReceipt(pRep, `rcpt_rep_{idx}`, 190000101, false).granted,
			"Seeded repeat Shop_PrismEgg"
		)
		local res = PolicyLogic.hatchEggWithPolicy(
			pRep,
			"Shop_PrismEgg",
			idx,
			false,
			true,
			idx * 0.24,
			0.99
		)
		assertTrue(
			res.ok
				and pRep.pets[idx].speciesId == "StarlightBeetle"
				and pRep.pets[idx].mutationKey == "Normal"
				and pRep.pets[idx].uid == `pet_{idx}`,
			"Repeated restricted hatch is 100% deterministic"
		)
	end
end

verifyPaidEggJointOdds(unrestrictedShop, restrictedShop, nilShop)
verifyRestrictedPaidHatchFallback()
verifyNilPolicyHatchAndNonClobber()
verifyUnrestrictedAndDeterministicRepeats()

print("PASS: ConfigsAndPolicy.spec.luau")
