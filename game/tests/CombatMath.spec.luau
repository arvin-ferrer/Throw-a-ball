--!strict
local CombatMath = require("../src/shared/Utils/CombatMath")
local ArenaStateMachine = require("../src/shared/Utils/ArenaStateMachine")
local BiomeConfigs = require("../src/shared/Configs/BiomeConfigs")
local CombatConfigs = require("../src/shared/Configs/CombatConfigs")

type Vec3 = CombatMath.Vec3
type ThrowRateState = CombatMath.ThrowRateState
type ValidatedThrow = CombatMath.ValidatedThrow

local ZERO: Vec3 = { X = 0, Y = 0, Z = 0 }
local FORWARD: Vec3 = { X = 0, Y = 0, Z = -1 }
local BASELINE_ARC: CombatMath.ArcConfig = {
	speed = 135,
	gravity = 42,
	maxDuration = 1.6,
	stepSeconds = 0.05,
}
local STRAIGHT_ARC: CombatMath.ArcConfig = {
	speed = 135,
	gravity = 0,
	maxDuration = 1.6,
	stepSeconds = 0.05,
}

local function run(name: string, test: () -> ())
	local ok, failure = pcall(test)
	assert(ok, `{name}: {failure}`)
end

local function assertNear(actual: number, expected: number, label: string)
	assert(math.abs(actual - expected) <= 1e-6, `{label}: expected {expected}, got {actual}`)
end

local function assertVec(actual: Vec3, expected: Vec3, label: string)
	assertNear(actual.X, expected.X, label .. " X")
	assertNear(actual.Y, expected.Y, label .. " Y")
	assertNear(actual.Z, expected.Z, label .. " Z")
end

local function validate(payload: unknown, rate: ThrowRateState, now: number): ValidatedThrow
	return CombatMath.validateThrowPayload(payload, ZERO, rate, 0, now)
end

local function expectRejected(payload: unknown, rate: ThrowRateState, now: number, reason: string)
	local previousThrow, previousDeadline = rate.lastThrowTime, rate.nextAllowedTime
	local result = validate(payload, rate, now)
	assert(not result.ok and result.reason == reason, `expected {reason}, got {result.reason}`)
	assert(rate.lastThrowTime == previousThrow, "a rejected throw changed lastThrowTime")
	assert(rate.nextAllowedTime == previousDeadline, "a rejected throw changed nextAllowedTime")
end

local function sweepTarget(id: string, x: number, z: number): CombatMath.SweepTarget
	return { id = id, kind = "Player", position = { X = x, Y = 0, Z = z }, radius = 2.2 }
end

-- Case 1
run("Combat config contains the five exact ball tiers and the PR #22 baseline", function()
	local expectedTiers = {
		{ "RubberBall", "Rubber Ball", 1.0, 135, 0.55, 0 },
		{ "IronSphere", "Iron Sphere", 1.5, 145, 0.60, 250 },
		{ "FrostOrb", "Frost Orb", 2.25, 155, 0.65, 2_500 },
		{ "MagmaCore", "Magma Core", 3.5, 165, 0.70, 25_000 },
		{ "NovaSphere", "Nova Sphere", 5.0, 180, 0.75, 250_000 },
	}
	local tierCount = 0
	for _ in CombatConfigs.BallTiers do
		tierCount += 1
	end
	assert(tierCount == #expectedTiers, "expected exactly five ball tiers")
	local previousDamage, previousSpeed, previousCost = 0, 0, -1
	for _, expected in expectedTiers do
		local id = tostring(expected[1])
		local tier = assert(CombatConfigs.BallTiers[id], `missing tier {id}`)
		assert(tier.displayName == expected[2], `{id} display name`)
		assert(tier.damageMultiplier == expected[3], `{id} damage multiplier`)
		assert(tier.projectileSpeed == expected[4], `{id} projectile speed`)
		assert(tier.ballRadius == expected[5], `{id} ball radius`)
		assert(tier.costCoins == expected[6], `{id} coin cost`)
		assert(tier.damageMultiplier > previousDamage, `{id} should increase damage`)
		assert(tier.projectileSpeed > previousSpeed, `{id} should increase speed`)
		assert(tier.costCoins > previousCost, `{id} should increase cost`)
		previousDamage, previousSpeed, previousCost =
			tier.damageMultiplier, tier.projectileSpeed, tier.costCoins
	end
	assert(CombatConfigs.Throw.BASE_THROW_COOLDOWN == 0.35, "PR #22 cooldown")
	assert(CombatConfigs.Throw.GRAVITY == 42, "PR #22 gravity")
	assert(CombatConfigs.Throw.MAX_FLIGHT_SECONDS == 1.6, "PR #22 flight duration")
	assert(CombatConfigs.Throw.SWEEP_STEP_SECONDS == 0.05, "PR #22 flight step")
	assert(BiomeConfigs.Biomes.EmeraldMeadow.baseBossHp == 1_560, "Meadow boss HP")
	assert(CombatConfigs.Bosses.MossbackGolem.baseHp == 1_560, "Mossback tuning HP")
end)

-- Cases 2–5
run("Malformed and non-finite throw fields are rejected without consuming cooldown", function()
	local rate = CombatMath.newRateState()
	assert(rate.lastThrowTime == -math.huge and rate.nextAllowedTime == -math.huge, "fresh limiter")
	expectRejected(nil, rate, 10, "InvalidPayload")
	for _, primitive in { true, 123, "throw" } do
		expectRejected(primitive, rate, 10, "InvalidPayload")
	end
	expectRejected({ direction = FORWARD }, rate, 10, "InvalidOrigin")
	expectRejected({ origin = ZERO }, rate, 10, "InvalidDirection")
	expectRejected(
		{ origin = { X = "0", Y = 0, Z = 0 }, direction = FORWARD },
		rate,
		10,
		"InvalidOrigin"
	)
	expectRejected({ origin = ZERO, direction = ZERO }, rate, 10, "InvalidDirection")
	expectRejected(
		{ origin = ZERO, direction = { X = 0, Y = 0, Z = 1e-7 } },
		rate,
		10,
		"InvalidDirection"
	)
	for _, invalid in { 0 / 0, math.huge, -math.huge } do
		local vector = { X = 0, Y = invalid, Z = -1 }
		expectRejected({ origin = vector, direction = FORWARD }, rate, 10, "InvalidOrigin")
		expectRejected({ origin = ZERO, direction = vector }, rate, 10, "InvalidDirection")
	end
end)

run("Throws normalize direction and ignore client damage, tier, and target fields", function()
	local direction = { X = 3, Y = 0, Z = 4 }
	local clean = validate(
		{ origin = ZERO, direction = direction, onTrainingPad = true },
		CombatMath.newRateState(),
		10
	)
	local injected = validate({
		origin = ZERO,
		direction = direction,
		onTrainingPad = true,
		damage = 999_999,
		ballTier = "NovaSphere",
		targetId = "Boss",
	}, CombatMath.newRateState(), 10)
	assert(clean.ok and injected.ok, "finite unnormalized direction should be accepted")
	assertVec(
		assert(injected.direction, "validated direction"),
		{ X = 0.6, Y = 0, Z = 0.8 },
		"unit direction"
	)
	assertVec(
		assert(injected.direction, "injected direction"),
		assert(clean.direction, "clean direction"),
		"direction parity"
	)
	assertVec(assert(injected.origin, "validated origin"), ZERO, "validated origin")
	assert(
		clean.cooldownSeconds == 0.35 and injected.cooldownSeconds == clean.cooldownSeconds,
		"cooldown parity"
	)
	assert(
		clean.onTrainingPadHint and injected.onTrainingPadHint,
		"client pad hint should be preserved"
	)
	for _, field in { "damage", "ballTier", "targetId" } do
		assert(rawget(injected, field) == nil, `unexpected returned field {field}`)
	end
	assert(CombatMath.computeBallDamage(15, "RubberBall") == 15, "damage comes from server stats")
end)

run("Throw origin accepts 12 studs and rejects 12.01 studs without mutating cooldown", function()
	local rate = CombatMath.newRateState()
	local boundary = { origin = { X = 0, Y = 12, Z = 0 }, direction = FORWARD }
	local outside = { origin = { X = 0, Y = 12.01, Z = 0 }, direction = FORWARD }
	assert(validate(boundary, rate, 10).ok, "exact origin distance boundary")
	expectRejected(outside, rate, 11, "OriginTooFar")
end)

run("Throw rate allows one early packet while preserving cooldown debt", function()
	local rate = CombatMath.newRateState()
	local payload = { origin = ZERO, direction = FORWARD }
	assert(validate(payload, rate, 10).ok, "first throw")
	assertNear(rate.lastThrowTime, 10, "first accepted time")
	assertNear(rate.nextAllowedTime, 10.35, "first allowed deadline")
	expectRejected(payload, rate, 10.10, "RateLimited")

	assert(validate(payload, rate, 10.32).ok, "throw within 40 ms jitter tolerance")
	assertNear(rate.lastThrowTime, 10.32, "second accepted time")
	assertNear(rate.nextAllowedTime, 10.70, "deadline after early throw")
	expectRejected(payload, rate, 10.64, "RateLimited")
	expectRejected(payload, rate, 10.31, "NonMonotonicTime")
	expectRejected(payload, rate, math.huge, "NonMonotonicTime")
	expectRejected(payload, rate, 0 / 0, "NonMonotonicTime")
	assert(validate(payload, rate, 10.70).ok, "deadline should allow next throw")
end)

-- Cases 6–8
run("Throw speed scales with diminishing returns and sanitizes invalid stats", function()
	assertNear(CombatMath.computeThrowCooldown(0), 0.35, "starter cooldown")
	assertNear(CombatMath.computeProjectileSpeed("RubberBall", 0), 135, "starter speed")
	assertNear(CombatMath.computeThrowCooldown(100), 0.25, "half-saturation cooldown")
	assertNear(
		CombatMath.computeProjectileSpeed("RubberBall", 100),
		155.25,
		"half-saturation speed"
	)
	local cooldown = CombatMath.computeThrowCooldown(100_000)
	local projectileSpeed = CombatMath.computeProjectileSpeed("RubberBall", 100_000)
	assert(cooldown >= 0.15 and cooldown < 0.25, "diminishing cooldown must respect the floor")
	assert(
		projectileSpeed > 155.25 and projectileSpeed <= 175.5,
		"diminishing speed must respect the cap"
	)
	for _, invalid in { -1, 0 / 0 } do
		assertNear(CombatMath.computeThrowCooldown(invalid), 0.35, "invalid stat cooldown")
		assertNear(
			CombatMath.computeProjectileSpeed("RubberBall", invalid),
			135,
			"invalid stat speed"
		)
	end
	assertNear(
		CombatMath.computeProjectileSpeed("UnknownTier", 0),
		135,
		"unknown tier speed fallback"
	)
end)

run("Ball damage uses authoritative base stats, tier multipliers, and a safe floor", function()
	assert(CombatMath.computeBallDamage(15, "RubberBall") == 15, "starter tier damage")
	assert(CombatMath.computeBallDamage(15, "NovaSphere") == 75, "Nova Sphere damage")
	assert(CombatMath.computeBallDamage(15, "UnknownTier") == 15, "unknown tier damage fallback")
	assert(CombatMath.computeBallDamage(15, "NovaSphere", 1.2) == 90, "server bonus multiplier")
	for _, invalid in { 0, -10, 0 / 0, math.huge } do
		local damage = CombatMath.computeBallDamage(invalid, "RubberBall")
		assert(
			damage >= 1 and damage < math.huge,
			"invalid base damage should return finite damage"
		)
	end
end)

run("Training pads require ownership and respect horizontal and vertical bounds", function()
	local pad: CombatMath.TrainingPadBox = {
		center = { X = 10, Y = 5, Z = -20 },
		halfSize = { X = 3.5, Y = 0, Z = 4.5 },
		minY = -0.5,
		maxY = 7.5,
		ownerUserId = 42,
	}
	assert(CombatMath.isPointOnOwnedPad(pad.center, 42, pad), "owner inside pad")
	assert(not CombatMath.isPointOnOwnedPad(pad.center, 99, pad, true), "another owner's pad")
	assert(
		CombatMath.isPointOnOwnedPad({ X = 13.5, Y = 12.5, Z = -24.5 }, 42, pad),
		"inclusive bounds"
	)
	assert(
		not CombatMath.isPointOnOwnedPad({ X = 13.51, Y = 5, Z = -20 }, 42, pad),
		"beyond X margin"
	)
	assert(
		not CombatMath.isPointOnOwnedPad({ X = 10, Y = 5, Z = -24.51 }, 42, pad),
		"beyond Z margin"
	)
	assert(
		not CombatMath.isPointOnOwnedPad({ X = 10, Y = 12.51, Z = -20 }, 42, pad),
		"above the pad"
	)
	assert(
		not CombatMath.isPointOnOwnedPad({ X = 10, Y = 4.49, Z = -20 }, 42, pad),
		"below the pad"
	)

	pad.ownerUserId = 0
	assert(
		not CombatMath.isPointOnOwnedPad(pad.center, 42, pad),
		"unassigned pads default to denied"
	)
	assert(
		not CombatMath.isPointOnOwnedPad(pad.center, 42, pad, false),
		"explicitly deny unassigned pad"
	)
	assert(
		CombatMath.isPointOnOwnedPad(pad.center, 42, pad, true),
		"explicitly allow unassigned pad"
	)
end)

-- Cases 9–11
run("The PR #22 ballistic arc samples match and cover 1.6 seconds in 32 segments", function()
	local origin = { X = 0, Y = 5, Z = 0 }
	local sample = CombatMath.sampleArcPosition(origin, FORWARD, 0.5, BASELINE_ARC)
	assertVec(sample, { X = 0, Y = -0.25, Z = -67.5 }, "half-second position")
	local segments = CombatMath.buildArcSegments(origin, FORWARD, BASELINE_ARC)
	assert(#segments == 32, "expected 32 trajectory segments")
	local previousTime, previousPos = 0, origin
	for _, segment in segments do
		assertNear(segment.tStart, previousTime, "contiguous segment times")
		assertNear(segment.tEnd - segment.tStart, 0.05, "segment duration")
		assertVec(segment.startPos, previousPos, "contiguous segment positions")
		previousTime, previousPos = segment.tEnd, segment.endPos
	end
	assertNear(previousTime, 1.6, "end of flight")
	assertVec(previousPos, { X = 0, Y = -48.76, Z = -216 }, "final arc position")
end)

run("Projectile sweeps hit the closest target, include tangent grazes, and exclude self", function()
	local farther = sweepTarget("B", 0, -40)
	local closer = sweepTarget("A", 0, -20)
	local targets = { farther, closer }
	local nearest = CombatMath.sweepProjectile(ZERO, FORWARD, STRAIGHT_ARC, 0.55, targets, {})
	assert(nearest.hit and nearest.hitKind == "Player", "closest player should be hit")
	assert(assert(nearest.target, "closest target payload").id == "A", "hit order follows flight")
	local excluded = CombatMath.sweepProjectile(ZERO, FORWARD, STRAIGHT_ARC, 0.55, targets, {}, "A")
	assert(
		excluded.hit and assert(excluded.target, "remaining target payload").id == "B",
		"excludeId skips A"
	)

	local tangent = { sweepTarget("Graze", 2.75, -20) }
	local graze = CombatMath.sweepProjectile(ZERO, FORWARD, STRAIGHT_ARC, 0.55, tangent, {})
	assert(graze.hit, "target radius plus ball radius should be inclusive")
	local offset = { sweepTarget("Miss", 2.80, -20) }
	local miss = CombatMath.sweepProjectile(ZERO, FORWARD, STRAIGHT_ARC, 0.55, offset, {})
	assert(not miss.hit and miss.hitKind == "None", "0.05 studs outside swept sphere")
end)

run("An intervening wall stops the throw and a target in front of it can be hit", function()
	local wall: CombatMath.AABB = {
		min = { X = -5, Y = -5, Z = -15 },
		max = { X = 5, Y = 5, Z = -13 },
	}
	local behind = sweepTarget("Behind", 0, -25)
	local blocked = CombatMath.sweepProjectile(
		ZERO,
		FORWARD,
		STRAIGHT_ARC,
		0.55,
		{ behind },
		{ wall }
	)
	assert(blocked.hit and blocked.hitKind == "World" and blocked.target == nil, "wall must win")
	assertNear(assert(blocked.hitPosition, "wall position").Z, -13, "wall face impact")
	local ahead = sweepTarget("Ahead", 0, -10)
	local clear = CombatMath.sweepProjectile(
		ZERO,
		FORWARD,
		STRAIGHT_ARC,
		0.55,
		{ behind, ahead },
		{ wall }
	)
	assert(clear.hit and clear.hitKind == "Player", "target is in front of wall")
	assert(
		assert(clear.target, "target in front of wall").id == "Ahead",
		"only the near target can be hit"
	)
end)

-- Cases 12–14
run("The arena allows PvP only between live room fighters after grace", function()
	local state = ArenaStateMachine.new({ biomeId = "EmeraldMeadow", baseBossHp = 1_560 }, 0)
	assert(not ArenaStateMachine.canDealPvPDamage(state, 1, 2, 0), "open PvE immunity")
	assert(ArenaStateMachine.tick(state, 90).ok, "open opt-in")
	assert(
		state.phase == "OptIn_Window" and not ArenaStateMachine.canDealPvPDamage(state, 1, 2, 90),
		"opt-in immunity"
	)
	assert(
		ArenaStateMachine.optIn(state, 1, 90).ok and ArenaStateMachine.optIn(state, 2, 90).ok,
		"queue two fighters"
	)
	assert(ArenaStateMachine.tick(state, 105).ok, "lock the boss room")
	assert(
		state.phase == "Boss_Phase" and not ArenaStateMachine.canDealPvPDamage(state, 1, 2, 105),
		"boss phase immunity"
	)
	assert(ArenaStateMachine.bossDefeated(state, 110).ok, "defeat the boss")
	assert(
		state.phase == "PvP_EggScramble"
			and not ArenaStateMachine.canDealPvPDamage(state, 1, 2, 112.99),
		"grace immunity"
	)
	assert(ArenaStateMachine.tick(state, 113).ok, "advance to grace deadline")
	assert(
		ArenaStateMachine.canDealPvPDamage(state, 1, 2, 113),
		"room fighters can attack after grace"
	)
	assert(not ArenaStateMachine.canDealPvPDamage(state, 1, 1, 113), "self damage")
	assert(not ArenaStateMachine.canDealPvPDamage(state, 1, 3, 113), "bystander victim")
	assert(not ArenaStateMachine.canDealPvPDamage(state, 3, 1, 113), "bystander attacker")
	assert(ArenaStateMachine.eliminate(state, 1, 114).ok, "eliminate attacker")
	assert(
		not ArenaStateMachine.canDealPvPDamage(state, 1, 2, 114),
		"eliminated players cannot deal PvP damage"
	)
end)

run("Reporting valid arena PvP damage cancels an active egg claim", function()
	local state = ArenaStateMachine.new({ biomeId = "EmeraldMeadow", baseBossHp = 1_560 }, 0)
	assert(ArenaStateMachine.tick(state, 90).ok, "open opt-in")
	assert(ArenaStateMachine.optIn(state, 1, 90).ok, "queue attacker")
	assert(ArenaStateMachine.optIn(state, 2, 90).ok, "queue claimant")
	assert(ArenaStateMachine.tick(state, 105).ok, "lock the boss room")
	assert(ArenaStateMachine.bossDefeated(state, 110).ok, "defeat the boss")
	assert(ArenaStateMachine.tick(state, 113).ok, "advance to grace deadline")
	assert(ArenaStateMachine.startClaim(state, 2, 4, 113).ok, "start an egg claim")
	local hit = ArenaStateMachine.damage(state, 2, 15, 114, 1)
	assert(hit.ok, "report valid combat damage")
	local cancelled = false
	for _, action in hit.actions do
		if
			action.kind == "ClaimCancelled"
			and action.reason == "Damage"
			and action.playerId == 2
		then
			cancelled = true
		end
	end
	assert(
		cancelled and ArenaStateMachine.getClaimProgress(state, 114) == 0,
		"damage interrupts the hold"
	)
end)

run("Training and Meadow mob rewards apply the planned stat and currency gains", function()
	local damage, speed = CombatMath.computeTrainingGain("WoodenDummy", false)
	assert(damage == 0.5 and speed == 0, "stationary Wooden Dummy rewards")
	damage, speed = CombatMath.computeTrainingGain("WoodenDummy", true)
	assert(damage == 1 and speed == 1, "moving gold rewards")
	damage, speed = CombatMath.computeTrainingGain("IronBullseye", false)
	assert(damage == 1.25 and speed == 0, "Iron Bullseye applies the 2.5x damage increase")
	local exp, progress, coins = CombatMath.computeMobRewards("MossSlime", 1.5)
	assert(exp == 20 and progress == 0.75 and coins == 15, "Moss Slime Meadow rewards")
	exp, progress, coins = CombatMath.computeMobRewards("BrambleBoar", 1.5)
	assert(exp == 40 and progress == 1.5 and coins == 30, "Bramble Boar Meadow rewards")
end)

run("EXP overflow levels up twice, carries the remainder, and scales max HP", function()
	local level, exp, hp = CombatMath.applyExp(1, 20, 230)
	assert(level == 3 and exp == 25 and hp == 130, "cross the 100 and 125 EXP thresholds")
end)

run("Boss HP scales by 35 percent per extra player and 40 percent when Overcharged", function()
	local solo = CombatMath.computeBossMaxHp(1_560, 1, false)
	local four = CombatMath.computeBossMaxHp(1_560, 4, false)
	local overcharged = CombatMath.computeBossMaxHp(1_560, 4, true)
	assert(solo == 1_560 and four == 3_198 and overcharged == 4_477, "expected rounded boss HP")
	assert(
		solo == ArenaStateMachine.computeBossMaxHp(1_560, 1, false),
		"solo ArenaStateMachine parity"
	)
	assert(
		four == ArenaStateMachine.computeBossMaxHp(1_560, 4, false),
		"four-player ArenaStateMachine parity"
	)
	assert(
		overcharged == ArenaStateMachine.computeBossMaxHp(1_560, 4, true),
		"Overcharged ArenaStateMachine parity"
	)
end)

print("PASS: CombatMath.spec.luau")
