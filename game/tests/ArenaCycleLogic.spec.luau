--!strict
--[[
	ArenaCycleLogic.spec.luau
	Tests the 3-Phase Arena FSM across all GDD edge cases:
	- 0 opt-ins cleanly returns to PvE_Open
	- 1-CCU solo opt-in -> Boss (1.0x HP) -> PvP -> uncontested 5.0s claim
	- 2-player Boss (+35% HP) -> Full Heal + 3s grace -> Mid-claim PvP interrupt -> Sudden Death
	- Mutual elimination / disconnect cleanly dissolves Egg and resets room
	- PvP immunity strictly enforced outside active PvP_EggScramble
	- 5-Minute Overcharged Global Scheduler triggers all 3 biomes simultaneously
]]

local ArenaCycleLogic = require("../src/shared/Utils/ArenaCycleLogic")
local BiomeConfigs = require("../src/shared/Configs/BiomeConfigs")

local function assertTrue(cond: boolean, label: string)
	if not cond then
		error(`Assertion failed: {label}`)
	end
end

-- 1. 0-player opt-in resets to PvE_Open
local state0 = ArenaCycleLogic.createBiomeState("EmeraldMeadow", 0)
assertTrue(state0.phase == "PvE_Open", "Starts in PvE_Open")
assertTrue(not ArenaCycleLogic.canDealPvPDamage(state0, 1, 2, 10), "No PvP in PvE_Open")
ArenaCycleLogic.stepBiome(state0, 90, nil)
assertTrue(state0.phase == "OptIn_Window", "Transitions to OptIn_Window at 90s")
ArenaCycleLogic.stepBiome(state0, 105, nil)
assertTrue(state0.phase == "PvE_Open", "0 opt-ins returns cleanly to PvE_Open")

-- 2. 1-CCU Solo Run (1.0x Base HP, completes 5.0s claim uncontested)
local solo = ArenaCycleLogic.createBiomeState("EmeraldMeadow", 0)
ArenaCycleLogic.triggerOptIn(solo, 100, false)
assertTrue(ArenaCycleLogic.setOptIn(solo, 101, true, 50), "Solo opt-in accepted")
ArenaCycleLogic.stepBiome(solo, 115, nil)
assertTrue(solo.phase == "Boss_Phase", "Entered Boss_Phase")
assertTrue(solo.bossMaxHP == 900, "Solo Boss HP is 1.0x base (900)")
assertTrue(not ArenaCycleLogic.canDealPvPDamage(solo, 101, 102, 120), "No PvP in Boss_Phase")
local okDmg, defeatEv = ArenaCycleLogic.applyBossDamage(solo, 101, 900, 130)
assertTrue(okDmg and #defeatEv == 1 and defeatEv[1].kind == "BossDefeated", "Boss defeated")
assertTrue(solo.phase == "PvP_EggScramble", "Entered PvP_EggScramble")
assertTrue(not ArenaCycleLogic.beginEggClaim(solo, 101, 5, 131), "Cannot claim during 3s grace")
assertTrue(ArenaCycleLogic.beginEggClaim(solo, 101, 5, 133), "Claim begins after 3s grace")
local evMid = ArenaCycleLogic.stepBiome(solo, 136, 5)
assertTrue(#evMid == 0 and solo.claim.progress > 0.5, "Mid-claim progress advancing")
local evWin = ArenaCycleLogic.stepBiome(solo, 138, 5)
assertTrue(#evWin >= 2 and evWin[1].kind == "EggClaimed", "5.0s claim wins egg")
assertTrue(evWin[1].payload.winnerId == 101, "Winner is solo player 101")
assertTrue(solo.phase == "PvE_Open", "Room resets to PvE_Open after claim")

-- 3. Multi-player mid-claim PvP damage interrupt + Sudden Death shrink
local brawl = ArenaCycleLogic.createBiomeState("EmeraldMeadow", 0)
ArenaCycleLogic.triggerOptIn(brawl, 10, false)
ArenaCycleLogic.setOptIn(brawl, 1, true, 120)
ArenaCycleLogic.setOptIn(brawl, 2, true, 240)
local qCount, qMaxPower = ArenaCycleLogic.getQueueSummary(brawl)
assertTrue(qCount == 2 and qMaxPower == 240, "Opt-In queue summary shows count & max power")
ArenaCycleLogic.stepBiome(brawl, 25, nil)
assertTrue(brawl.bossMaxHP == math.floor(900 * 1.35 + 0.5), "2-player Boss HP scales +35%")
ArenaCycleLogic.applyBossDamage(brawl, 1, 2000, 30)
assertTrue(not ArenaCycleLogic.canDealPvPDamage(brawl, 1, 2, 31), "No PvP during 3s grace")
assertTrue(ArenaCycleLogic.canDealPvPDamage(brawl, 1, 2, 33), "PvP enabled after 3s grace")
assertTrue(not ArenaCycleLogic.canDealPvPDamage(brawl, 1, 999, 33), "Outsiders PvP-immune")
assertTrue(ArenaCycleLogic.beginEggClaim(brawl, 1, 4, 34), "Player 1 begins claim")
assertTrue(not ArenaCycleLogic.beginEggClaim(brawl, 2, 4, 35), "Player 2 blocked while P1 holds")
local intEv = ArenaCycleLogic.onPlayerDamagedInPvP(brawl, 1)
assertTrue(#intEv == 1 and intEv[1].kind == "ClaimCanceled", "PvP damage interrupts claim")
assertTrue(brawl.claim.claimerId == nil, "Claim token cleared on interrupt")
ArenaCycleLogic.stepBiome(brawl, 33 + BiomeConfigs.SUDDEN_DEATH_START_SEC + 22.5, nil)
assertTrue(
	brawl.suddenDeathRadius < BiomeConfigs.SUDDEN_DEATH_START_RADIUS,
	"Sudden Death ring shrinks after 75s"
)

-- 4. Mutual elimination / disconnect cleanly resets arena
ArenaCycleLogic.removePlayerFromArena(brawl, 1, 140, "Eliminated")
assertTrue(brawl.phase == "PvP_EggScramble", "Still active with 1 player left")
ArenaCycleLogic.removePlayerFromArena(brawl, 2, 140, "Disconnected")
assertTrue(brawl.phase == "PvE_Open", "All players gone dissolves egg & resets to PvE_Open")

-- 5. 5-Minute Overcharged Global Scheduler
local clock = ArenaCycleLogic.createOverchargedClock(0)
local allStates = {
	EmeraldMeadow = ArenaCycleLogic.createBiomeState("EmeraldMeadow", 0),
	FrostbiteCavern = ArenaCycleLogic.createBiomeState("FrostbiteCavern", 0),
	MoltenCaldera = ArenaCycleLogic.createBiomeState("MoltenCaldera", 0),
}
local ocEvents = ArenaCycleLogic.stepOverchargedClock(clock, allStates, 300)
assertTrue(#ocEvents == 4 and ocEvents[1].kind == "OverchargedGlobalAlert", "5m alert + 3 biomes")
for _, id in ipairs(BiomeConfigs.ORDERED_MVP_BIOMES) do
	assertTrue(
		allStates[id].phase == "OptIn_Window" and allStates[id].isOvercharged,
		`{id} Overcharged`
	)
end

-- 6. PvP_EggScramble phaseEndsAt deadline enforces ScrambleTimeout even with living survivors
local function testScrambleDeadline()
	local timeoutState = ArenaCycleLogic.createBiomeState("EmeraldMeadow", 0)
	ArenaCycleLogic.triggerOptIn(timeoutState, 10, false)
	ArenaCycleLogic.setOptIn(timeoutState, 11, true, 150)
	ArenaCycleLogic.setOptIn(timeoutState, 12, true, 160)
	ArenaCycleLogic.stepBiome(timeoutState, 25, nil)
	ArenaCycleLogic.applyBossDamage(timeoutState, 11, 5000, 30)
	local endAt = timeoutState.phaseEndsAt
	ArenaCycleLogic.stepBiome(timeoutState, endAt - 5, nil)
	assertTrue(
		timeoutState.phase == "PvP_EggScramble"
			and timeoutState.suddenDeathRadius == BiomeConfigs.SUDDEN_DEATH_MIN_RADIUS,
		"Survivors remain in minimum storm radius before scramble deadline"
	)
	assertTrue(
		ArenaCycleLogic.beginEggClaim(timeoutState, 11, 3, endAt - 2),
		"Partial claim starts 2s before scramble deadline"
	)
	local timeoutEvents = ArenaCycleLogic.stepBiome(timeoutState, endAt, 3)
	local lastEv = timeoutEvents[#timeoutEvents]
	assertTrue(
		lastEv ~= nil
			and lastEv.kind == "PhaseChanged"
			and lastEv.payload.phase == "PvE_Open"
			and lastEv.payload.reason == "ScrambleTimeout",
		"Scramble deadline emits ScrambleTimeout PhaseChanged to PvE_Open"
	)
	assertTrue(
		timeoutState.phase == "PvE_Open"
			and timeoutState.claim.claimerId == nil
			and #lastEv.payload.returnPlayers == 2
			and not ArenaCycleLogic.canDealPvPDamage(timeoutState, 11, 12, endAt),
		"ScrambleTimeout clears claim, ejects survivors, and disables PvP"
	)
	assertTrue(
		not ArenaCycleLogic.beginEggClaim(timeoutState, 11, 2, endAt),
		"Cannot begin claim once PvE_Open resumed"
	)
end

-- 6b. Exact deadline claim completion (finishAt == phaseEndsAt) still awards EggClaimed
local function testExactDeadlineWin()
	local exactState = ArenaCycleLogic.createBiomeState("EmeraldMeadow", 0)
	ArenaCycleLogic.triggerOptIn(exactState, 10, false)
	ArenaCycleLogic.setOptIn(exactState, 11, true, 150)
	ArenaCycleLogic.stepBiome(exactState, 25, nil)
	ArenaCycleLogic.applyBossDamage(exactState, 11, 5000, 30)
	local exactEnd = exactState.phaseEndsAt
	assertTrue(
		not ArenaCycleLogic.canDealPvPDamage(exactState, 11, 12, exactEnd)
			and not ArenaCycleLogic.beginEggClaim(exactState, 11, 2, exactEnd),
		"PvP damage and new claims blocked at exact phaseEndsAt deadline"
	)
	assertTrue(
		ArenaCycleLogic.beginEggClaim(exactState, 11, 2, exactEnd - 5),
		"Claim started 5s before deadline"
	)
	local exactWin = ArenaCycleLogic.stepBiome(exactState, exactEnd, 2)
	assertTrue(
		#exactWin >= 2 and exactWin[1].kind == "EggClaimed" and exactState.phase == "PvE_Open",
		"5s hold finishing at exact phaseEndsAt still wins egg"
	)
end

-- 7. Authored volume/floor room bounds and BiomePvE-only opt-in modal eligibility
local function testVolumeBoundsAndOptInEligibility()
	assertTrue(
		ArenaCycleLogic.isInsideVolumeBounds(10, -5, 10, 100, 60, 100, false),
		"Inside authored box room volume"
	)
	assertTrue(
		not ArenaCycleLogic.isInsideVolumeBounds(55, 0, 0, 100, 60, 100, false),
		"Outside authored box room volume"
	)
	assertTrue(
		not ArenaCycleLogic.isInsideVolumeBounds(0 / 0, 0, 0, 100, 60, 100, false)
			and not ArenaCycleLogic.isInsideVolumeBounds(0, 0, 0, 0, 60, 100, false),
		"Non-finite or zero-size volume bounds rejected"
	)
	assertTrue(
		ArenaCycleLogic.isInsideVolumeBounds(0, 30, 40, 60, 120, 120, true),
		"Inside upright cylinder volume (X thickness, YZ radius 60)"
	)
	assertTrue(
		not ArenaCycleLogic.isInsideVolumeBounds(0, 50, 50, 60, 120, 120, true),
		"Outside cylinder corner radius"
	)
	assertTrue(
		ArenaCycleLogic.isInsideFloorFootprint(10, 10, 200, 200, 15, 10, false, 120),
		"Standing above ArenaFloor within vertical clearance"
	)
	assertTrue(
		not ArenaCycleLogic.isInsideFloorFootprint(10, 10, 200, 200, -5, 10, false, 120)
			and not ArenaCycleLogic.isInsideFloorFootprint(10, 10, 200, 200, 131, 10, false, 120),
		"Fallen below ArenaFloor or above ceiling rejected"
	)
	assertTrue(
		ArenaCycleLogic.isZoneEligibleForOptIn("BiomePvE", "EmeraldMeadow", "EmeraldMeadow"),
		"Matching BiomePvE player eligible for BossFightOffered"
	)
	assertTrue(
		not ArenaCycleLogic.isZoneEligibleForOptIn("Hub", "", "EmeraldMeadow"),
		"Hub player ineligible for opt-in modal offer"
	)
	assertTrue(
		not ArenaCycleLogic.isZoneEligibleForOptIn("BiomePvE", "FrostbiteCavern", "EmeraldMeadow"),
		"Other biome player ineligible for opt-in modal offer"
	)
end

testScrambleDeadline()
testExactDeadlineWin()
testVolumeBoundsAndOptInEligibility()

print("PASS: ArenaCycleLogic.spec.luau")
