--!strict
--[[
	CombatAndEconomyLogic.spec.luau
	Verifies CombatLogic (cooldown, NaN guard, off-pad rejection, moving gold 2x + throw speed,
	Active Follower perks) and EconomyLogic (Minute-0 Starter Egg, Cash Pad + <=12h offline cap,
	Lv 1-25, 3-to-1 Star Fusion atomicity, Gem Trait Rerolls, Gem Egg Crafting, Soft Ascension).
]]

local CombatLogic = require("../src/shared/Utils/CombatLogic")
local EconomyLogic = require("../src/shared/Utils/EconomyLogic")
local EconomyConfigs = require("../src/shared/Configs/EconomyConfigs")
local PetConfigs = require("../src/shared/Configs/PetConfigs")

local function assertTrue(cond: boolean, label: string)
	if not cond then
		error(`Assertion failed: {label}`)
	end
end

-- 1. Combat validation (NaN, zero dir, rate-limit)
local okNan = CombatLogic.validateThrowRequest({
	lastThrowAt = 0,
	now = 10,
	throwSpeedStat = 1,
	activePets = {},
	originX = 0 / 0,
	originY = 0,
	originZ = 0,
	dirX = 0,
	dirY = 0,
	dirZ = 1,
})
assertTrue(not okNan, "NaN origin rejected")

local okSpam = CombatLogic.validateThrowRequest({
	lastThrowAt = 10.0,
	now = 10.05,
	throwSpeedStat = 1,
	activePets = {},
	originX = 0,
	originY = 5,
	originZ = 0,
	dirX = 0,
	dirY = 0,
	dirZ = 1,
})
assertTrue(not okSpam, "Cooldown spam rejected")

-- 2. Training off-pad rejection vs on-pad Moving Gold 2x + Throw Speed
local offPad = CombatLogic.evaluateTrainingHit({
	isOnAssignedPad = false,
	targetTierId = "WoodenDummy",
	isMovingGold = true,
	goldCombo = 0,
	ascensionRank = 0,
	hasDoubleTrainingPass = false,
	activePets = {},
})
assertTrue(not offPad.accepted, "Off-pad training hit rejected")

local onPadGold = CombatLogic.evaluateTrainingHit({
	isOnAssignedPad = true,
	targetTierId = "WoodenDummy",
	isMovingGold = true,
	goldCombo = 2,
	ascensionRank = 0,
	hasDoubleTrainingPass = false,
	activePets = {},
})
assertTrue(onPadGold.accepted and onPadGold.ballDamageGain == 2, "Gold target gives 2x dmg")
assertTrue(
	onPadGold.throwSpeedGain > 0 and onPadGold.nextGoldCombo == 3,
	"Gold combo increments speed"
)

-- 3. Active Follower Perk resolution (duplicate perk picks highest tier)
local activeDupes: { PetConfigs.OwnedPetSnapshot } = {
	{
		uid = "a",
		speciesId = "ThornStag",
		mutationKey = "Normal",
		starTier = 1,
		level = 1,
		traitKey = nil,
	},
	{
		uid = "b",
		speciesId = "ThornStag",
		mutationKey = "Golden",
		starTier = 3,
		level = 5,
		traitKey = nil,
	},
	{
		uid = "c",
		speciesId = "SnowFox",
		mutationKey = "Normal",
		starTier = 1,
		level = 1,
		traitKey = "Brawler",
	},
}
local resolved = PetConfigs.resolveActivePerks(activeDupes)
assertTrue(resolved.CritSurge.sourcePetUid == "b", "Duplicate perk selects highest potency tier")
assertTrue(resolved.FrostSlow ~= nil, "Distinct perk stacks alongside CritSurge")

local hitEval = CombatLogic.evaluateBallHit({
	baseBallDamage = 100,
	ballTierId = "IronSphere",
	activePets = activeDupes,
	critRollUnit = 0.01,
})
assertTrue(hitEval.isCrit and hitEval.slowFraction > 0, "Crit + FrostSlow applied together")

-- 4. Minute-0 Starter Egg Hatch + Cash Pad sweep + Active Follower keeps pedestal income!
local p = EconomyLogic.createDefaultProfile(1000)
local hatchRes = EconomyLogic.hatchEggOnPedestal(p, "StarterEgg", 1, false, 0.5, 0.5)
assertTrue(hatchRes.ok and p.starterEggHatched, "Starter Egg hatched on Pedestal #1")
assertTrue(#p.pets == 1 and p.pets[1].speciesId == "TrainingPup", "Hatched TrainingPup")
assertTrue(#p.activeFollowerUids == 1 and p.pets[1].pedestalIndex == 1, "Equipped AND on pedestal")
EconomyLogic.accruePedestalCoins(p, 10, false, false)
local swept = EconomyLogic.collectCashPad(p, 1)
assertTrue(
	swept == 50 and p.coins == 50,
	"TrainingPup earned 5 Coins/s * 10s = 50 while Active Follower"
)

-- 5. <=12h Offline accrual cap
EconomyLogic.accruePedestalCoins(p, 24 * 3600, true, false)
local offlineSwept = EconomyLogic.collectCashPad(p, 1)
assertTrue(offlineSwept == 5 * 12 * 3600 * 0.5, "Offline accrual capped at 12h @ 50%")

-- 6. Atomic 3-to-1 Star Fusion + Leveling + Gem Trait Reroll + Gem Egg Craft
p.eggs.EmeraldMeadow_BossEgg = 3
EconomyLogic.hatchEggOnPedestal(p, "EmeraldMeadow_BossEgg", 2, false, 0.1, 0.1)
EconomyLogic.hatchEggOnPedestal(p, "EmeraldMeadow_BossEgg", 3, false, 0.1, 0.1)
EconomyLogic.hatchEggOnPedestal(p, "EmeraldMeadow_BossEgg", 4, false, 0.1, 0.1)
local u1, u2, u3 = p.pets[2].uid, p.pets[3].uid, p.pets[4].uid
local badFuse = EconomyLogic.fusePets(p, { u1, u1, u2 })
assertTrue(not badFuse.ok, "Duplicate UID fusion rejected")
local goodFuse = EconomyLogic.fusePets(p, { u1, u2, u3 })
assertTrue(
	goodFuse.ok and #p.pets == 2 and p.pets[2].starTier == 2,
	"3-to-1 Fusion promoted to 2★"
)

local lvlRes = EconomyLogic.levelUpPet(p, p.pets[1].uid)
assertTrue(lvlRes.ok and p.pets[1].level == 2, "Pet leveled up with Coins")

p.bossGems = 50
local traitRes = EconomyLogic.rerollPetTrait(p, p.pets[1].uid, 0.95)
assertTrue(traitRes.ok and p.pets[1].traitKey == "Tycoon", "Gem Trait Reroll applied Tycoon")
local craftRes = EconomyLogic.craftStandardBiomeEgg(p, "EmeraldMeadow")
assertTrue(
	craftRes.ok and p.eggs.EmeraldMeadow_BossEgg == 1,
	"Crafted standard Meadow egg with Gems"
)

-- 7. Soft Ascension resets Coins ONLY — preserves 100% pets, levels, ball damage & Gems
p.ballDamage = 750
p.level = 14
p.coins = EconomyConfigs.getAscensionCoinThreshold(0)
local ascRes = EconomyLogic.performSoftAscension(p)
assertTrue(ascRes.ok and p.ascensionRank == 1, "Soft Ascension succeeded")
assertTrue(p.coins == 0, "Ascension resets Coins to 0")
assertTrue(
	p.ballDamage == 750 and p.level == 14 and #p.pets == 2 and p.bossGems == 10,
	"Keeps all progress"
)

print("PASS: CombatAndEconomyLogic.spec.luau")
