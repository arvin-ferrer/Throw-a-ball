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

local okFreeAfk, _, baseCd = CombatLogic.validateThrowRequest({
	lastThrowAt = 10.0,
	now = 11.0,
	throwSpeedStat = 1,
	activePets = {},
	hasTurboRangeBonus = false,
	originX = 0,
	originY = 5,
	originZ = 0,
	dirX = 0,
	dirY = 0,
	dirZ = 1,
})
local okTurbo, _, turboCd = CombatLogic.validateThrowRequest({
	lastThrowAt = 10.0,
	now = 11.0,
	throwSpeedStat = 1,
	activePets = {},
	hasTurboRangeBonus = true,
	originX = 0,
	originY = 5,
	originZ = 0,
	dirX = 0,
	dirY = 0,
	dirZ = 1,
})
assertTrue(
	okFreeAfk and okTurbo and turboCd < baseCd,
	"Free AFK throw valid and Turbo Range reduces cooldown"
)

-- 1b. Auto-Aim target selection (range cap, Boss/PvP priority, nearest mob)
local pickedBoss = CombatLogic.selectAutoAimTarget(0, 5, 0, {
	{ id = "farMob", kind = "Mob", x = 0, y = 5, z = 200 },
	{ id = "nearMob", kind = "Mob", x = 0, y = 5, z = 40 },
	{ id = "boss", kind = "Boss", x = 0, y = 5, z = 55 },
})
assertTrue(pickedBoss ~= nil and pickedBoss.id == "boss", "Auto-Aim prioritizes Boss in range")

local pickedNear = CombatLogic.selectAutoAimTarget(0, 5, 0, {
	{ id = "mobA", kind = "Mob", x = 0, y = 5, z = 65 },
	{ id = "mobB", kind = "Mob", x = 18, y = 5, z = 10 },
	{ id = "tooFar", kind = "Boss", x = 0, y = 5, z = 220 },
})
assertTrue(
	pickedNear ~= nil and pickedNear.id == "mobB",
	"Auto-Aim ignores out-of-range and picks nearest Mob"
)

-- 1c. Ballistic throw physics (gravity drop + upward loft arc)
local vx, vy, vz = CombatLogic.computeBallisticLaunchVelocity(0, 0, -1, 120, 0.10)
local px0, py0, pz0 = CombatLogic.sampleBallisticPosition(0, 5, 0, vx, vy, vz, 0)
local pxMid, pyMid, pzMid = CombatLogic.sampleBallisticPosition(0, 5, 0, vx, vy, vz, 0.25)
local pxLate, pyLate, pzLate = CombatLogic.sampleBallisticPosition(0, 5, 0, vx, vy, vz, 1.0)
assertTrue(px0 == 0 and py0 == 5 and pz0 == 0, "Ballistic t=0 starts at origin")
assertTrue(pyMid > py0 and pzMid < pz0, "Ballistic loft rises smoothly at mid-flight")
assertTrue(
	pyLate < py0 and pxLate == 0 and pzLate < pzMid,
	"Ballistic gravity curves ball downward"
)

-- 1d. Camera-look manual aim direction (unified PC & Mobile camera look vector)
local aimX, aimY, aimZ = CombatLogic.computeCameraAimDirection(3, 4, 0)
assertTrue(
	math.abs(aimX - 0.6) < 1e-4 and math.abs(aimY - 0.8) < 1e-4 and math.abs(aimZ) < 1e-4,
	"Camera aim normalizes non-unit look vector"
)
local fbX, fbY, fbZ = CombatLogic.computeCameraAimDirection(0, 0, 0)
assertTrue(fbX == 0 and fbY == 0 and fbZ == -1, "Zero camera look vector falls back safely")
local nanX, nanY, nanZ = CombatLogic.computeCameraAimDirection(0 / 0, 1, 0)
assertTrue(
	nanX == 0 and nanY == 0 and nanZ == -1,
	"Non-finite camera look vector falls back safely"
)

-- 1e. Active post-bounce physics & 1.0s damage lifetime
assertTrue(CombatLogic.POST_BOUNCE_LIFETIME == 1.0, "Post-bounce lifetime is 1.0 second")
local rvx, rvy, rvz = CombatLogic.computeBounceVelocity(20, -30, 0, 0, 1, 0)
assertTrue(rvx > 10 and rvx < 20 and rvy > 15 and rvz == 0, "Floor bounce reflects upward cleanly")
local wvx, wvy, wvz = CombatLogic.computeBounceVelocity(0, 0, -80, 0, 0, 1)
assertTrue(wvz > 40 and wvy >= 8, "Wall/target bounce rebounds backward with lively arc")
local svx, svy, svz = CombatLogic.computeBounceVelocity(12, -2, 0, 0, 1, 0)
assertTrue(svx > 0 and svy == 0 and svz == 0, "Tiny floor impact settles smoothly without buzzing")
local bnx, bny, bnz = CombatLogic.computeBounceVelocity(0 / 0, 5, 0, 0, 1, 0)
assertTrue(bnx == 0 and bny == 0 and bnz == 0, "Non-finite bounce velocity returns zero safely")

assertTrue(not CombatLogic.isBounceActive(nil, 10.0), "No bounce yet means bounce timer inactive")
assertTrue(CombatLogic.isBounceActive(10.0, 10.0), "Active immediately at first bounce")
assertTrue(CombatLogic.isBounceActive(10.0, 10.95), "Still active within 1.0s after first bounce")
assertTrue(not CombatLogic.isBounceActive(10.0, 11.0), "Expires at exact 1.0s after first bounce")
assertTrue(
	math.abs(CombatLogic.getRemainingBounceTime(10.0, 10.25) - 0.75) < 1e-4,
	"Remaining bounce time tracks 1s countdown accurately"
)
assertTrue(
	CombatLogic.getRemainingBounceTime(10.0, 12.0) == 0,
	"Remaining bounce time clamps at 0 after expiry"
)
assertTrue(CombatLogic.canBounceHitTarget(nil, 10.0), "First hit on a target is allowed")
assertTrue(
	not CombatLogic.canBounceHitTarget(10.0, 10.05),
	"Same target debounced inside bounce hit cooldown"
)
assertTrue(
	CombatLogic.canBounceHitTarget(10.0, 10.35),
	"Same target can be hit again after bounce cooldown"
)
assertTrue(
	CombatLogic.shouldDespawnOnHitKind("Mob")
		and CombatLogic.shouldDespawnOnHitKind("Boss")
		and CombatLogic.shouldDespawnOnHitKind("PvP")
		and CombatLogic.shouldDespawnOnHitKind("Target")
		and CombatLogic.shouldDespawnOnHitKind("GoldTarget"),
	"Ball auto-despawns when hitting an enemy or target"
)
assertTrue(
	not CombatLogic.shouldDespawnOnHitKind("Surface")
		and not CombatLogic.shouldDespawnOnHitKind("Roll"),
	"Ball keeps bouncing when hitting surfaces"
)

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
