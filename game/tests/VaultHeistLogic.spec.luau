--!strict
--[[
	VaultHeistLogic.spec.luau
	Unit tests for C2 Boss Vault Heist pure state machine and configs:
	- Config & Roblox 2026 Policy invariants (zero Robux Boss/Overcharged eggs)
	- Orb level sanitization, coin upgrades, throw validation, Decoy/Freeze/DashBomb
	- Egg grab, anti-reroll drop/re-grab, alarm timer & carry slow immunity
	- Boss FSM (PATROL/INVESTIGATE/TELEGRAPH/LUNGE/STUNNED) & damage/revive/wipe
	- Extraction vote, chamber dive progression, disconnects, collapse & NaN safety
]]

local EggConfigs = require("../src/shared/Configs/EggConfigs")
local VaultHeistConfigs = require("../src/shared/Configs/VaultHeistConfigs")
local VaultHeistLogic = require("../src/shared/Utils/VaultHeistLogic")

local function run(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	assert(ok, `{name}: {err}`)
end

local function makeSoloRun(
	now: number?,
	chamber: number?,
	storm: boolean?
): VaultHeistLogic.VaultRunState
	return VaultHeistLogic.createRun({
		runId = "run_solo",
		groupKey = "solo:101",
		chamber = chamber or 1,
		mutatorId = "LowGravity",
		isHourlyStorm = storm == true,
		now = now or 100,
		bossSpawnPos = { x = 0, y = 0, z = -900 },
		players = {
			{ userId = 101, maxHP = 100, orbLevels = { Decoy = 1, Freeze = 1, DashBomb = 1 } },
		},
	})
end

local function makeSquadRun(now: number?, chamber: number?): VaultHeistLogic.VaultRunState
	return VaultHeistLogic.createRun({
		runId = "run_squad",
		groupKey = "party:alpha",
		chamber = chamber or 1,
		mutatorId = "Darkness",
		isHourlyStorm = false,
		now = now or 100,
		bossSpawnPos = { x = 0, y = 0, z = -900 },
		players = {
			{ userId = 1, maxHP = 100, orbLevels = { Decoy = 2, Freeze = 2, DashBomb = 2 } },
			{ userId = 2, maxHP = 120, orbLevels = { Decoy = 1, Freeze = 0, DashBomb = 0 } },
		},
	})
end

run("VaultHeistConfigs invariants and Roblox 2026 zero-Robux Boss Egg policy", function()
	for ch = 1, VaultHeistConfigs.MAX_CHAMBER do
		local cfg = VaultHeistConfigs.getChamber(ch)
		assert(cfg.chamber == ch, "chamber index matches")
		for _, eggId in ipairs({ cfg.standardEggId, cfg.stormEggId }) do
			local egg = EggConfigs.getEgg(eggId)
			assert(egg ~= nil, `missing egg config {eggId}`)
			assert(not EggConfigs.isRobuxPurchasable(eggId), `{eggId} must never be Robux`)
			assert(not (egg :: EggConfigs.EggConfig).isPaidRandomItem, `{eggId} not paid random`)
		end
	end
	for _, orbId in ipairs(VaultHeistConfigs.ORDERED_ORBS) do
		local orb = VaultHeistConfigs.getOrb(orbId)
		assert(orb ~= nil and #orb.upgradeCosts == orb.maxLevel, `{orbId} cost table matches max`)
		local lv0 = VaultHeistConfigs.getOrbStats(orbId, 0)
		local lvMax = VaultHeistConfigs.getOrbStats(orbId, orb.maxLevel)
		assert(lv0 ~= nil and lv0.level == 0 and lv0.bossDamage == 0, "lv0 inert")
		assert(lvMax ~= nil and lvMax.cooldown >= 3.5, "cooldown floor >= 3.5s")
	end
	assert(VaultHeistConfigs.getOrb("Unknown") == nil, "unknown orb nil")
	assert(VaultHeistConfigs.getOrbStats("Unknown", 1) == nil, "unknown orb stats nil")
	assert(VaultHeistConfigs.getOrbUpgradeCost("Unknown", 1) == nil, "unknown orb cost nil")
	assert(VaultHeistConfigs.scaleBossHP(1000, 1) == 1000, "1p HP 1.0x")
	assert(VaultHeistConfigs.scaleBossHP(1000, 99) == 2350, "4p max HP clamped")
	assert(math.abs(VaultHeistConfigs.scaleBossSpeed(20, 1) - 18.4) < 1e-6, "1p 0.92x speed")
	assert(math.abs(VaultHeistConfigs.scaleBossSpeed(20, 4) - 23.2) < 1e-6, "4p speed scale")
end)

run("Orb level sanitization and coin upgrade transactions", function()
	local profile: any = {
		coins = 1000,
		orbLevels = { Decoy = 0 / 0, Freeze = -5, DashBomb = 99 },
	}
	local levels = VaultHeistLogic.ensureOrbLevels(profile)
	assert(levels.Decoy == 1 and levels.Freeze == 0 and levels.DashBomb == 6, "sanitized levels")

	local okDecoy = VaultHeistLogic.upgradeOrb(profile, "Decoy")
	assert(okDecoy.ok and profile.coins == 750 and profile.orbLevels.Decoy == 2, "Decoy 1->2")

	local okFreeze = VaultHeistLogic.upgradeOrb(profile, "Freeze")
	assert(okFreeze.ok and profile.coins == 350 and profile.orbLevels.Freeze == 1, "Freeze 0->1")

	local noCoins = VaultHeistLogic.upgradeOrb(profile, "Freeze")
	assert(not noCoins.ok and noCoins.reason == "InsufficientCoins", "insufficient coins")
	assert(profile.coins == 350 and profile.orbLevels.Freeze == 1, "wallet untouched on fail")

	local maxFail = VaultHeistLogic.upgradeOrb(profile, "DashBomb")
	assert(not maxFail.ok and maxFail.reason == "MaxOrbLevel", "cannot exceed max level")
	assert(VaultHeistLogic.upgradeOrb(profile, "FakeOrb").reason == "UnknownOrb", "unknown orb")
	assert(VaultHeistLogic.upgradeOrb(nil, "Decoy").reason == "InvalidArgs", "nil profile")

	local badBal: any = { coins = -10, orbLevels = {} }
	assert(VaultHeistLogic.upgradeOrb(badBal, "Decoy").reason == "InvalidBalance", "neg coins")
	badBal.coins = 0 / 0
	assert(VaultHeistLogic.upgradeOrb(badBal, "Decoy").reason == "InvalidBalance", "NaN coins")
end)

run("Hourly storm cadence, group keys, mutator selection, eggs and streak multiplier", function()
	assert(VaultHeistLogic.isHourlyVaultStormActive(0), "t=0 storm active")
	assert(VaultHeistLogic.isHourlyVaultStormActive(479.9), "t=479.9 storm active")
	assert(not VaultHeistLogic.isHourlyVaultStormActive(480), "t=480 storm ended")
	assert(VaultHeistLogic.isHourlyVaultStormActive(3600), "t=3600 next hour active")
	assert(not VaultHeistLogic.isHourlyVaultStormActive(-1), "negative time inactive")
	assert(not VaultHeistLogic.isHourlyVaultStormActive(0 / 0), "NaN time inactive")
	assert(VaultHeistLogic.getHourlyVaultStormRemaining(100) == 380, "380s left in storm")
	assert(VaultHeistLogic.getHourlyVaultStormRemaining(500) == 3100, "3100s until next storm")
	assert(VaultHeistLogic.getHourlyVaultStormRemaining(0 / 0) == 3600, "NaN fallback period")

	assert(VaultHeistLogic.resolveJoinGroupKey(42, "squad_7") == "party:squad_7", "party key")
	assert(VaultHeistLogic.resolveJoinGroupKey(42, "") == "solo:42", "empty party -> solo")
	assert(VaultHeistLogic.resolveJoinGroupKey(42, nil) == "solo:42", "nil party -> solo")

	assert(VaultHeistLogic.pickChamberMutator(1, true, 0.1) == "VaultStorm", "storm forces mut")
	assert(VaultHeistLogic.pickChamberMutator(1, false, 0.99) == "LowGravity", "ch1 avoids storm")
	assert(VaultHeistLogic.pickChamberMutator(2, false, 0.99) == "VaultStorm", "ch2 allows storm")
	assert(VaultHeistLogic.pickChamberMutator(2, false, 0 / 0) == "LowGravity", "NaN roll safe")

	assert(
		VaultHeistLogic.getChamberEggId(1, "LowGravity", false, 0.0) == "EmeraldMeadow_BossEgg",
		"ch1 low gravity 0% storm egg"
	)
	assert(
		VaultHeistLogic.getChamberEggId(1, "LowGravity", true, 0.64)
			== "EmeraldMeadow_OverchargedEgg",
		"hourly storm boosts chance to 0.65"
	)
	assert(
		VaultHeistLogic.getChamberEggId(3, "LowGravity", false, 0.24)
			== "MoltenCaldera_OverchargedEgg",
		"ch3 floor 0.25 storm egg chance"
	)
	assert(
		VaultHeistLogic.getChamberEggId(3, "VaultStorm", true, 0 / 0) == "MoltenCaldera_BossEgg",
		"NaN roll defaults to 0.99 standard egg"
	)
	local mult = VaultHeistLogic.computeStreakMult(2, "VaultStorm", true)
	assert(math.abs(mult - (1.8 * 1.5 * 1.5)) < 1e-6, "streakMult = ch * mut * storm")
end)

run("Run creation, squad scaling, late-join rules and carrier move speed", function()
	local runState = VaultHeistLogic.createRun({
		runId = "r1",
		groupKey = "party:p1",
		chamber = 99,
		now = 50,
		bossSpawnPos = { x = 0, y = 0, z = -900 },
		players = {
			{ userId = 10, maxHP = 20 },
			{ userId = 10, maxHP = 200 },
			{ userId = 0 / 0, maxHP = 100 },
		},
	})
	assert(runState.chamber == 3, "chamber clamped to MAX_CHAMBER")
	assert(#runState.playerOrder == 1 and runState.players[10].maxHP == 50, "dedup + min 50 HP")

	runState.boss.hp = math.floor(runState.boss.maxHP * 0.5)
	assert(VaultHeistLogic.addPlayerToRun(runState, { userId = 20, maxHP = 100 }), "2nd joins")
	assert(
		not VaultHeistLogic.addPlayerToRun(runState, { userId = 20, maxHP = 100 }),
		"dup blocked"
	)
	local expectedMax = VaultHeistConfigs.scaleBossHP(VaultHeistConfigs.getChamber(3).bossBaseHP, 2)
	assert(runState.boss.maxHP == expectedMax, "boss maxHP scaled for 2p")
	assert(math.abs(runState.boss.hp / runState.boss.maxHP - 0.5) < 0.01, "HP ratio preserved")
	assert(VaultHeistLogic.addPlayerToRun(runState, { userId = 30, maxHP = 100 }), "3rd joins")
	assert(VaultHeistLogic.addPlayerToRun(runState, { userId = 40, maxHP = 100 }), "4th joins")
	assert(
		not VaultHeistLogic.addPlayerToRun(runState, { userId = 50, maxHP = 100 }),
		"5th blocked"
	)

	local solo = makeSoloRun(100, 1, false)
	assert(VaultHeistLogic.getPlayerMoveSpeed(solo, 101, 100, false) == 18, "base walk speed")
	assert(VaultHeistLogic.getPlayerMoveSpeed(solo, 101, 100, true) == 24, "base sprint speed")
	solo.carrierUserId = 101
	assert(math.abs(VaultHeistLogic.getPlayerMoveSpeed(solo, 101, 100, true) - 24 * 0.78) < 1e-6)
	solo.players[101].carrySlowImmuneUntil = 105
	assert(VaultHeistLogic.getPlayerMoveSpeed(solo, 101, 104, true) == 24, "carry slow immunity")
	solo.players[101].downed = true
	assert(VaultHeistLogic.getPlayerMoveSpeed(solo, 101, 104, true) == 0, "downed speed 0")
	assert(VaultHeistLogic.getPlayerMoveSpeed(solo, 999, 104, true) == 0, "unknown speed 0")
end)

run("Egg grab, alarm collapse timer, drop and anti-reroll re-grab", function()
	local runState = makeSoloRun(100, 1, true)
	local pedestal = { x = 0, y = 2, z = -942 }

	local badRange, rReason =
		VaultHeistLogic.tryGrabEgg(runState, 101, { x = 0, y = 2, z = -900 }, pedestal, 105, 0.99)
	assert(not badRange and rReason == "OutOfRange", "far grab rejected")

	local badNaN, nReason =
		VaultHeistLogic.tryGrabEgg(runState, 101, { x = 0 / 0, y = 2, z = -942 }, pedestal, 105)
	assert(not badNaN and nReason == "InvalidArgs", "NaN pos rejected")

	local okGrab, _, grabEv =
		VaultHeistLogic.tryGrabEgg(runState, 101, { x = 0, y = 2, z = -935 }, pedestal, 110, 0.99)
	assert(okGrab and #grabEv == 1 and grabEv[1].kind == "EggGrabbed", "pedestal grab succeeded")
	assert(runState.carrierUserId == 101 and not runState.eggPedestalAvailable, "carrier set")
	assert(runState.carryingEggId == "EmeraldMeadow_BossEgg", "standard egg rolled")
	assert(runState.alarmTriggered and runState.chamberEndsAt == 185, "collapse timer 110+75=185")
	assert(
		runState.boss.state == "INVESTIGATE" and runState.boss.targetUserId == 101,
		"boss alerted"
	)

	assert(not VaultHeistLogic.dropEgg(runState, 999, { x = 5, y = 1, z = -920 }, 112), "wrong uid")
	local okDrop, dropEv = VaultHeistLogic.dropEgg(runState, 101, { x = 5, y = 1, z = -920 }, 112)
	assert(okDrop and #dropEv == 1 and dropEv[1].kind == "EggDropped", "egg dropped")
	assert(runState.carrierUserId == nil and runState.droppedEggPos ~= nil, "dropped pos stored")

	local okRegrab =
		VaultHeistLogic.tryGrabEgg(runState, 101, { x = 5, y = 1, z = -915 }, pedestal, 115, 0.0)
	assert(
		okRegrab and runState.carryingEggId == "EmeraldMeadow_BossEgg",
		"anti-reroll preserves egg"
	)
	assert(runState.chamberEndsAt == 185, "alarm timer does not reset on re-grab")
end)

run("Orb throw validation rejects locked, zero-dir, non-finite and cooldown inputs", function()
	local runState = makeSquadRun(100, 1)
	local origin = { x = 0, y = 2, z = -880 }
	local dir = { x = 0, y = 0, z = -1 }

	local okLocked, lockedReason =
		VaultHeistLogic.validateOrbThrow(runState, 2, "Freeze", origin, dir, 101)
	assert(not okLocked and lockedReason == "OrbLocked", "lv0 orb locked")

	local okZero, zeroReason =
		VaultHeistLogic.validateOrbThrow(runState, 1, "Decoy", origin, { x = 0, y = 0, z = 0 }, 101)
	assert(not okZero and zeroReason == "ZeroDirection", "zero dir rejected")

	local okNaN, nanReason = VaultHeistLogic.validateOrbThrow(
		runState,
		1,
		"Decoy",
		{ x = 0 / 0, y = 0, z = 0 },
		dir,
		101
	)
	assert(not okNaN and nanReason == "NonFiniteVector", "NaN origin rejected")

	local badImpact, impReason = VaultHeistLogic.executeOrbAction(
		runState,
		1,
		"Decoy",
		origin,
		dir,
		{ x = math.huge, y = 0, z = 0 },
		101
	)
	assert(not badImpact and impReason == "InvalidImpact", "inf impact rejected")
	assert(runState.players[1].orbCooldowns.Decoy == nil, "no cooldown spent on invalid impact")
end)

run("Decoy lure, Freeze stun/laser pause and DashBomb knockback/interrupt", function()
	local runState = makeSquadRun(100, 1)
	local origin, dir = { x = 0, y = 2, z = -880 }, { x = 0, y = 0, z = -1 }
	local exec = VaultHeistLogic.executeOrbAction

	local okDecoy, _, decoyEv =
		exec(runState, 1, "Decoy", origin, dir, { x = 10, y = 0, z = -900 }, 102)
	assert(okDecoy and decoyEv[1].kind == "DecoySpawned", "decoy spawned")
	assert(runState.boss.state == "INVESTIGATE" and runState.boss.decoyId == "decoy_1", "lured")

	local okCd, cdReason = VaultHeistLogic.validateOrbThrow(runState, 1, "Decoy", origin, dir, 103)
	assert(not okCd and cdReason == "OnCooldown", "cooldown enforced")

	local hpBefore = runState.boss.hp
	local okFreeze, _, freezeEv =
		exec(runState, 1, "Freeze", origin, dir, { x = 0, y = 0, z = -900 }, 104)
	assert(okFreeze and freezeEv[1].kind == "FreezeBurst" and freezeEv[1].payload.hitBoss, "freeze")
	assert(runState.boss.state == "STUNNED" and runState.boss.hp < hpBefore, "stunned + damaged")
	assert(runState.laserPausedUntil == 108, "lasers paused 4s")

	runState.boss.state = "TELEGRAPH"
	local okDash, _, dashEv = exec(
		runState,
		1,
		"DashBomb",
		origin,
		dir,
		{ x = 0, y = 0, z = -895 },
		105,
		{ x = 0, y = 0, z = -900 },
		10
	)
	assert(okDash and #dashEv == 2 and dashEv[2].kind == "BossKnockedBack", "dash knocked boss")
	assert(runState.boss.pos.z >= -910 and runState.boss.pos.z <= -890, "clamped to extent")
	assert(runState.boss.state == "PATROL" and runState.boss.lungeCooldownUntil == 106.4, "reset")
end)

run("Damage, SoloDroneRevive, LaserGate pause/drop and Co-Op revive decay", function()
	local solo = makeSoloRun(100, 1, false)
	local noOp =
		VaultHeistLogic.applyDamageToPlayer(solo, 101, 0 / 0, 101, { x = 0, y = 0, z = -890 })
	assert(#noOp == 0 and solo.players[101].hp == 100, "NaN damage ignored")

	local revEv =
		VaultHeistLogic.applyDamageToPlayer(solo, 101, 150, 102, { x = 0, y = 0, z = -890 })
	assert(#revEv == 2 and revEv[2].kind == "SoloDroneRevive", "solo drone revive triggered")
	assert(solo.players[101].soloReviveUsed and solo.players[101].hp == 65, "revived at 65% HP")
	assert(#VaultHeistLogic.applyDamageToPlayer(solo, 101, 99, 103) == 0, "invuln blocks damage")

	local wipeEv =
		VaultHeistLogic.applyDamageToPlayer(solo, 101, 99, 106, { x = 0, y = 0, z = -890 })
	assert(
		wipeEv[#wipeEv].kind == "SquadWiped" and solo.phase == "Finished",
		"2nd lethal wipes solo"
	)

	local squad = makeSquadRun(100, 1)
	squad.carrierUserId = 1
	squad.carryingEggId = "EmeraldMeadow_BossEgg"
	squad.laserPausedUntil = 110
	assert(
		#VaultHeistLogic.onTouchLaserGate(squad, 1, 105, { x = 0, y = 2, z = -922 }) == 0,
		"paused"
	)

	local laserEv = VaultHeistLogic.onTouchLaserGate(squad, 1, 111, { x = 0, y = 2, z = -922 })
	assert(squad.players[1].hp == 78 and squad.carrierUserId == nil, "laser damages + drops egg")
	assert(laserEv[#laserEv].kind == "LaserHit", "emits LaserHit")
	assert(
		#VaultHeistLogic.onTouchLaserGate(squad, 1, 111.5, { x = 0, y = 2, z = -922 }) == 0,
		"invuln"
	)

	VaultHeistLogic.applyDamageToPlayer(squad, 1, 100, 115, { x = 0, y = 0, z = -860 })
	assert(squad.players[1].downed and squad.phase == "Active", "1 downed, 1 living stays active")
	local positions = { [1] = { x = 0, y = 0, z = -860 }, [2] = { x = 5, y = 0, z = -860 } }
	VaultHeistLogic.stepRun(squad, 1.25, 116.25, {}, positions)
	assert(math.abs(squad.players[1].reviveProgress - 0.5) < 1e-6, "half revived after 1.25s")
	positions[2] = { x = 40, y = 0, z = -860 }
	VaultHeistLogic.stepRun(squad, 1.0, 117.25, {}, positions)
	assert(math.abs(squad.players[1].reviveProgress - 0.25) < 1e-6, "decays when teammate leaves")
	positions[2] = { x = 4, y = 0, z = -860 }
	local reviveEv = VaultHeistLogic.stepRun(squad, 2.0, 119.25, {}, positions)
	assert(not squad.players[1].downed and squad.players[1].hp == 50, "revived at 50% HP")
	assert(reviveEv[1].kind == "PlayerRevived", "emits PlayerRevived")
end)

run("Boss FSM patrol, sight cone, telegraph, lunge hit dedup and stun recovery", function()
	local runState = makeSquadRun(100, 1)
	local nodes = { { x = -20, y = 0, z = -900 }, { x = 20, y = 0, z = -900 } }
	VaultHeistLogic.stepRun(runState, 2.0, 102, nodes, {
		[1] = { x = 0, y = 0, z = -820 },
		[2] = { x = 0, y = 0, z = -820 },
	})
	assert(runState.boss.state == "PATROL" and runState.boss.patrolIndex == 2, "patrol wraps node")

	local closePos = { [1] = { x = -10, y = 0, z = -900 }, [2] = { x = 0, y = 0, z = -800 } }
	local telEv = VaultHeistLogic.stepRun(runState, 0.1, 103, nodes, closePos)
	assert(
		runState.boss.state == "TELEGRAPH" and telEv[1].kind == "BossTelegraph",
		"telegraph start"
	)

	local lungeEv = VaultHeistLogic.stepRun(runState, 0.1, 104.3, nodes, closePos)
	assert(runState.boss.state == "LUNGE" and lungeEv[1].kind == "BossLunge", "enters LUNGE")

	local hpBefore = runState.players[1].hp
	VaultHeistLogic.stepRun(runState, 0.1, 104.4, nodes, closePos, { x = 0, y = 0, z = -900 }, 50)
	local hpAfterHit = runState.players[1].hp
	assert(hpAfterHit == hpBefore - VaultHeistConfigs.getChamber(1).lungeDamage, "lunge hits P1")
	VaultHeistLogic.stepRun(runState, 0.1, 104.5, nodes, closePos, { x = 0, y = 0, z = -900 }, 50)
	assert(runState.players[1].hp == hpAfterHit, "lungeHitUsers prevents double hit")

	VaultHeistLogic.stepRun(runState, 0.1, 104.8, nodes, closePos, { x = 0, y = 0, z = -900 }, 50)
	assert(runState.boss.state == "PATROL", "returns to PATROL after lunge")

	runState.boss.state = "STUNNED"
	runState.boss.stunEndsAt = 110
	VaultHeistLogic.stepRun(runState, 0.5, 110, nodes, closePos)
	assert(runState.boss.state == "PATROL", "recovers from STUNNED")
end)

run("Extraction vote, Dive progression, Chamber 3 cap, disconnects and collapse timeout", function()
	local runState = makeSquadRun(100, 1)
	assert(not VaultHeistLogic.triggerExtractionVote(runState, 1, 105), "non-carrier cannot vote")
	runState.carrierUserId = 1
	runState.carryingEggId = "EmeraldMeadow_BossEgg"
	local okVote, vEv = VaultHeistLogic.triggerExtractionVote(runState, 1, 105)
	assert(okVote and runState.phase == "Vote" and vEv[1].payload.canDive == true, "vote started")

	local ok1, ev1 = VaultHeistLogic.castExtractionVote(runState, 1, "Dive", 106)
	assert(ok1 and #ev1 == 0, "waiting for P2 vote")
	local ok2, ev2 = VaultHeistLogic.castExtractionVote(runState, 2, "Dive", 107, nil, 0.99)
	assert(ok2 and ev2[1].kind == "ChamberAdvanced" and runState.chamber == 2, "advanced to ch2")
	assert(#runState.runBagEggs == 1 and runState.eggPedestalAvailable, "ch1 egg banked in bag")

	runState.chamber = VaultHeistConfigs.MAX_CHAMBER
	runState.carrierUserId = 1
	runState.carryingEggId = "MoltenCaldera_BossEgg"
	VaultHeistLogic.triggerExtractionVote(runState, 1, 120)
	VaultHeistLogic.castExtractionVote(runState, 1, "Dive", 121)
	local _, extEv = VaultHeistLogic.castExtractionVote(runState, 2, "Dive", 122)
	assert(extEv[1].kind == "HeistExtracted" and runState.phase == "Finished", "ch3 forces Extract")
	assert(#extEv[1].payload.eggs == 2 and runState.votePayoutDone, "payout includes bagged + held")
	assert(#VaultHeistLogic.stepRun(runState, 1, 150, {}, {}) == 0, "Finished run no-ops")

	local timeoutRun = makeSoloRun(100, 1, false)
	timeoutRun.carrierUserId = 101
	timeoutRun.carryingEggId = "EmeraldMeadow_BossEgg"
	VaultHeistLogic.triggerExtractionVote(timeoutRun, 101, 110)
	local toEv = VaultHeistLogic.stepRun(timeoutRun, 0.5, 120, {}, {})
	assert(toEv[1].kind == "HeistExtracted", "vote timeout defaults to Extract")

	local collapseRun = makeSoloRun(100, 1, false)
	assert(#VaultHeistLogic.stepRun(collapseRun, 0 / 0, 105, {}, {}) == 0, "NaN dt ignored")
	local colEv = VaultHeistLogic.stepRun(collapseRun, 0.1, 220, {}, {})
	assert(
		colEv[1].kind == "SquadWiped" and colEv[1].payload.reason == "VaultCollapsed",
		"collapsed"
	)

	local discRun = makeSquadRun(100, 1)
	discRun.carrierUserId = 1
	discRun.carryingEggId = "EmeraldMeadow_BossEgg"
	discRun.players[2].downed = true
	local remEv = VaultHeistLogic.removePlayerFromRun(discRun, 1, nil, 115)
	assert(discRun.eggPedestalAvailable and discRun.phase == "Finished", "remaining downed wipes")
	assert(remEv[1].kind == "SquadWiped" and remEv[1].payload.reason == "RemainingDowned")
end)

print("PASS: VaultHeistLogic.spec.luau")
