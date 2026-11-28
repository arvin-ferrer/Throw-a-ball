--!strict
--[[
	MobCombatLogic.spec.luau
	Unit tests for pure server-authoritative Emerald Meadow mob ballistics (strictly non-homing),
	ground & perched-watchtower trajectories, pack formation offsets, and archetype AI intents.
]]

local MobCombatLogic = require("../src/shared/Utils/MobCombatLogic")

local function assertTrue(cond: boolean, label: string)
	if not cond then
		error(`Assertion failed: {label}`)
	end
end

local function assertNear(actual: number, expected: number, eps: number, label: string)
	if math.abs(actual - expected) > eps then
		error(`{label}: expected {expected}, got {actual}`)
	end
end

-- Helper to simulate pure gravity flight to horizontal distance d
local function simulateToHorizontalDist(
	ox: number,
	oy: number,
	oz: number,
	vx: number,
	vy: number,
	vz: number,
	gravity: number,
	targetDist: number
): (number, number, number)
	local horizSpeed = math.sqrt(vx * vx + vz * vz)
	assertTrue(horizSpeed > 1e-3, "Horizontal speed must be positive")
	local flightTime = targetDist / horizSpeed
	local dt = 0.005
	local px, py, pz = ox, oy, oz
	local cvx, cvy, cvz = vx, vy, vz
	local t = 0
	while t + dt <= flightTime do
		px, py, pz, cvx, cvy, cvz =
			MobCombatLogic.stepBallisticPoint(px, py, pz, cvx, cvy, cvz, dt, gravity)
		t += dt
	end
	local rem = flightTime - t
	if rem > 1e-6 then
		px, py, pz = MobCombatLogic.stepBallisticPoint(px, py, pz, cvx, cvy, cvz, rem, gravity)
	end
	return px, py, pz
end

-- 1. Ground-to-ground ballistic solver hits stationary snapshot accurately (low & high arcs)
do
	local vx, vy, vz = MobCombatLogic.solveBallisticVelocity(0, 3.5, 0, 48, 3.0, 0, 68, 42, false)
	local hx, hy, hz = simulateToHorizontalDist(0, 3.5, 0, vx, vy, vz, 42, 48)
	assertNear(hx, 48, 0.2, "Low-arc hex orb reaches X=48")
	assertNear(hy, 3.0, 0.25, "Low-arc hex orb lands at torso Y=3.0")
	assertNear(hz, 0, 0.05, "Low-arc hex orb stays in aim plane")

	local lvx, lvy, lvz =
		MobCombatLogic.solveBallisticVelocity(0, 2.5, 0, 0, 3.0, -34, 54, 48, true)
	assertTrue(lvy > vy, "High lob launches steeper upward than low ballistic arc")
	local lx, ly, lz = simulateToHorizontalDist(0, 2.5, 0, lvx, lvy, lvz, 48, 34)
	assertNear(lx, 0, 0.05, "High-lob aqua glob stays in Z plane")
	assertNear(ly, 3.0, 0.35, "High-lob aqua glob lands at target Y=3.0")
	assertNear(lz, -34, 0.2, "High-lob aqua glob reaches Z=-34")
end

-- 2. Elevated perched Watchtower-to-ground ballistic solver (deltaY = -31.8 studs)
for _, dist in ipairs({ 25, 65, 110 }) do
	local vx, vy, vz = MobCombatLogic.solveBallisticVelocity(
		2511,
		34.8,
		-3750,
		2511 + dist,
		3.0,
		-3750,
		74,
		42,
		false
	)
	local hx, hy, hz = simulateToHorizontalDist(2511, 34.8, -3750, vx, vy, vz, 42, dist)
	assertNear(hx, 2511 + dist, 0.3, `Perched tower shot dist={dist} X`)
	assertNear(hy, 3.0, 0.45, `Perched tower shot dist={dist} lands at player torso Y=3.0`)
	assertNear(hz, -3750, 0.05, `Perched tower shot dist={dist} Z`)
end

-- 3. Strict non-homing invariant: horizontal velocity stays constant, gravity acts solely on Y
do
	local vx0, vy0, vz0 =
		MobCombatLogic.solveBallisticVelocity(10, 4, -20, 45, 3, 15, 68, 42, false)
	local px, py, pz = 10, 4, -20
	local vx, vy, vz = vx0, vy0, vz0
	for _ = 1, 30 do
		px, py, pz, vx, vy, vz = MobCombatLogic.stepBallisticPoint(px, py, pz, vx, vy, vz, 0.02, 42)
		assertNear(vx, vx0, 1e-6, "Non-homing vx constant mid-flight")
		assertNear(vz, vz0, 1e-6, "Non-homing vz constant mid-flight")
	end
	assertNear(vy, vy0 - 42 * 0.6, 1e-4, "Gravity accelerates purely on -Y")
end

-- 4. Out-of-range fallback & NaN safety
do
	local vx, vy, vz = MobCombatLogic.solveBallisticVelocity(0, 3, 0, 400, 3, 0, 50, 48, false)
	local mag = math.sqrt(vx * vx + vy * vy + vz * vz)
	assertNear(mag, 50, 0.5, "Out-of-range fallback preserves launch speed without boost")
	assertTrue(vy > 20, "Out-of-range fallback pitches upward (~45 deg)")

	local nx, ny, nz = MobCombatLogic.solveBallisticVelocity(0 / 0, 0, 0, 10, 0, 0, 50, 42, false)
	assertTrue(nx == 0 and ny == 0 and nz == -50, "NaN origin returns safe forward vector")

	local sx, sy, sz = MobCombatLogic.applyHorizontalSpread(0, 10, -50, 5)
	assertTrue(sx ~= 0 and sy == 10 and sz < 0, "Horizontal yaw spread rotates XZ and preserves Y")
end

-- 5. Pack formation offsets & splash AoE check
do
	local single = MobCombatLogic.computePackOffsets(1, 6)
	assertTrue(#single == 1 and single[1][1] == 0 and single[1][2] == 0, "Single spawn centered")
	local trio = MobCombatLogic.computePackOffsets(3, 7)
	assertTrue(#trio == 3, "Trio pack produces 3 offsets")
	for i = 1, 3 do
		for j = i + 1, 3 do
			local d = math.sqrt((trio[i][1] - trio[j][1]) ^ 2 + (trio[i][2] - trio[j][2]) ^ 2)
			assertTrue(d >= 8.0, "Pack offsets well separated")
		end
	end
	assertTrue(MobCombatLogic.isWithinSplash(10, 3, 10, 13, 3, 10, 4.5), "Inside splash AoE")
	assertTrue(not MobCombatLogic.isWithinSplash(10, 3, 10, 16, 3, 10, 4.5), "Outside splash AoE")
	assertNear(MobCombatLogic.clampPerchedOffset(5.2, 2.5), 2.5, 1e-6, "Perched clamp +max")
	assertNear(MobCombatLogic.clampPerchedOffset(-4.8, 2.5), -2.5, 1e-6, "Perched clamp -max")
end

-- 6. Archetype AI intent & leash/dormancy transitions
do
	local dormant = MobCombatLogic.evaluateMobIntent({
		archetype = "Hopper",
		isPerched = false,
		distToTarget = 220,
		distFromHome = 2,
		aggroRange = 48,
		leashRange = 85,
		meleeRange = 6.5,
		rangedMin = nil,
		rangedMax = nil,
		preferredMin = nil,
		preferredMax = nil,
		chargeMin = nil,
		chargeMax = nil,
		canRanged = false,
		canCharge = false,
		canMelee = false,
	})
	assertTrue(dormant == "Dormant", "Far player keeps home mob Dormant")

	local leashed = MobCombatLogic.evaluateMobIntent({
		archetype = "Charger",
		isPerched = false,
		distToTarget = 20,
		distFromHome = 120,
		aggroRange = 64,
		leashRange = 115,
		meleeRange = 7.5,
		chargeMin = 14,
		chargeMax = 36,
		canRanged = false,
		canCharge = true,
		canMelee = false,
	})
	assertTrue(leashed == "ReturnHome", "Exceeding leash forces ReturnHome")

	local witchRetreat = MobCombatLogic.evaluateMobIntent({
		archetype = "RangedCaster",
		isPerched = false,
		distToTarget = 12,
		distFromHome = 10,
		aggroRange = 76,
		leashRange = 110,
		meleeRange = 0,
		rangedMin = 14,
		rangedMax = 64,
		preferredMin = 28,
		preferredMax = 56,
		canRanged = false,
		canCharge = false,
		canMelee = false,
	})
	assertTrue(witchRetreat == "Retreat", "Ground Witch retreats when player closes under 18-28")

	local witchCast = MobCombatLogic.evaluateMobIntent({
		archetype = "RangedCaster",
		isPerched = true,
		distToTarget = 75,
		distFromHome = 1,
		aggroRange = 125,
		leashRange = 125,
		meleeRange = 0,
		rangedMin = 12,
		rangedMax = 125,
		preferredMin = 20,
		preferredMax = 125,
		canRanged = true,
		canCharge = false,
		canMelee = false,
	})
	assertTrue(witchCast == "RangedCast", "Perched Witch casts down at 75-stud target")

	local boarCharge = MobCombatLogic.evaluateMobIntent({
		archetype = "Charger",
		isPerched = false,
		distToTarget = 24,
		distFromHome = 15,
		aggroRange = 64,
		leashRange = 115,
		meleeRange = 7.5,
		chargeMin = 14,
		chargeMax = 36,
		canRanged = false,
		canCharge = true,
		canMelee = false,
	})
	assertTrue(boarCharge == "ChargeTelegraph", "BrambleBoar enters ChargeTelegraph in 14..36 band")
end

print("PASS: MobCombatLogic.spec.luau")
