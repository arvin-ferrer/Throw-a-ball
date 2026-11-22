--!strict
local BossAIStateMachine = require("../src/shared/Utils/BossAIStateMachine")
local CombatConfigs = require("../src/shared/Configs/CombatConfigs")
local CombatMath = require("../src/shared/Utils/CombatMath")

type BossAction = BossAIStateMachine.BossAction
type TargetSnapshot = BossAIStateMachine.TargetSnapshot
type AABB = CombatMath.AABB

local MOSSBACK = CombatConfigs.Bosses.MossbackGolem
local ORIGIN: CombatMath.Vec3 = { X = 0, Y = 0, Z = 0 }

local function newBoss(isOvercharged: boolean)
	return BossAIStateMachine.new(
		MOSSBACK,
		ORIGIN,
		if isOvercharged then 2_184 else 1_560,
		isOvercharged,
		0
	)
end

type BossState = typeof(newBoss(false))

local function run(name: string, test: () -> ())
	local ok, failure = pcall(test)
	assert(ok, `{name}: {failure}`)
end

local function assertNear(actual: number, expected: number, label: string)
	assert(math.abs(actual - expected) <= 1e-6, `{label}: expected {expected}, got {actual}`)
end

local function target(playerId: number, x: number, y: number, z: number): TargetSnapshot
	return { playerId = playerId, position = { X = x, Y = y, Z = z } }
end

local function step(
	state: BossState,
	now: number,
	targets: { TargetSnapshot },
	obstacles: { AABB }?
): { BossAction }
	local result = BossAIStateMachine.tick(state, now, targets, obstacles or {})
	assert(result.ok, `tick at {now} failed: {result.reason}`)
	return result.actions
end

local function findAction(actions: { BossAction }, kind: string): BossAction?
	for _, action in actions do
		if action.kind == kind then
			return action
		end
	end
	return nil
end

local function countActions(actions: { BossAction }, kind: string): number
	local count = 0
	for _, action in actions do
		if action.kind == kind then
			count += 1
		end
	end
	return count
end

local function expectAction(actions: { BossAction }, kind: string): BossAction
	return assert(findAction(actions, kind), `expected {kind} action`)
end

local function beginAttack(state: BossState, targets: { TargetSnapshot }, kind: string): BossAction
	local actions = step(state, 0, targets)
	if state.state == "Chase" then
		actions = step(state, 0, targets)
	end
	return expectAction(actions, kind)
end

local function startRolling(state: BossState, targets: { TargetSnapshot }, spawnAt: number): number
	beginAttack(state, targets, "TelegraphBoulder")
	local spawned = expectAction(step(state, spawnAt, targets), "SpawnBoulder")
	return assert(spawned.boulderId, "spawn must identify the rolling boulder")
end

local function expectDespawn(actions: { BossAction }, id: number, reason: string)
	local action = expectAction(actions, "DespawnBoulder")
	assert(
		action.boulderId == id and action.reason == reason,
		`expected boulder {id} to despawn: {reason}`
	)
end

-- Case 15
run(
	"The boss idles without targets and chases the nearest target at 12 studs per second",
	function()
		local state = newBoss(false)
		assert(
			state.state == "Idle" and state.currentHp == 1_560 and state.maxHp == 1_560,
			"fresh boss state"
		)
		assert(#step(state, 0, {}) == 0 and state.state == "Idle", "idle bot without targets")
		local targets = { target(1, -100, 0, 0), target(2, 80, 0, 0) }
		step(state, 0, targets)
		assert(state.state == "Chase", "available targets should start chase")
		expectAction(step(state, 1, targets), "MoveTo")
		assertNear(state.position.X, 12, "chase toward nearer player")
		assertNear(state.position.Z, 0, "horizontal chase")
		assert(
			#step(state, 2, {}) == 0 and state.state == "Idle",
			"no living target returns to Idle"
		)
	end
)

run("Chase ties favor the lowest player ID and movement stops ten studs away", function()
	local state = newBoss(false)
	-- Keep both attacks on cooldown so this fixture can exercise melee stopping distance.
	state.slamReadyAt = 100
	state.boulderReadyAt = 100
	local tied = { target(9, -80, 0, 0), target(2, 80, 0, 0) }
	step(state, 0, tied)
	expectAction(step(state, 1, tied), "MoveTo")
	assertNear(state.position.X, 12, "equal-distance target with the lower player ID")
	step(state, 7, { tied[2] })
	assertNear(state.position.X, 70, "stop ten studs from target")
	step(state, 8, { tied[2] })
	assertNear(state.position.X, 70, "chase does not overshoot stop distance")
end)

-- Cases 16–17
run("Slam telegraphs before the expanding wave hits each fighter at most once", function()
	local state = newBoss(false)
	local targets = { target(7, 14, 0, 0) }
	beginAttack(state, targets, "TelegraphSlam")
	assert(state.state == "Windup_Slam", "slam takes priority in overlapping range")
	local early = step(state, 1.19, targets)
	assert(
		state.state == "Windup_Slam" and findAction(early, "SlamHit") == nil,
		"windup deals no damage"
	)
	assert(
		findAction(early, "MoveTo") == nil and state.position.X == 0,
		"boss stays put during windup"
	)

	local active = step(state, 1.20, targets)
	assert(
		state.state == "Active_Slam" and findAction(active, "SlamHit") == nil,
		"activate the shockwave"
	)
	local approach = step(state, 1.45, targets)
	local ring = expectAction(approach, "SlamShockwaveTick")
	assertNear(assert(ring.radius, "shockwave radius"), 26 / 3, "one-third shockwave radius")
	assert(findAction(approach, "SlamHit") == nil, "wave has not reached the player")

	local contact = step(state, 1.55, targets)
	local hit = expectAction(contact, "SlamHit")
	assert(
		hit.playerId == 7 and hit.damage == 28 and countActions(contact, "SlamHit") == 1,
		"first ring hit"
	)
	assert(
		findAction(step(state, 1.60, targets), "SlamHit") == nil,
		"same target still overlaps, with no repeat hit"
	)

	assert(findAction(step(state, 1.9501, targets), "SlamHit") == nil, "ring exit does not re-hit")
	assert(state.state == "Recovery", "slam enters recovery")
end)

run("Slam recovers for 0.8 seconds and stays on cooldown for six seconds", function()
	local state = newBoss(false)
	-- Keep the competing attack out of this cooldown test.
	state.boulderReadyAt = 100
	local targets = { target(7, 14, 0, 0) }
	beginAttack(state, targets, "TelegraphSlam")
	step(state, 1.2, targets)
	local finishAt = 1.9501
	step(state, finishAt, targets)
	assert(state.state == "Recovery", "slam enters recovery")
	assertNear(state.slamReadyAt, finishAt + 6.0, "slam cooldown begins at active end")
	local recovering = step(state, finishAt + 0.79, targets)
	assert(
		state.state == "Recovery" and findAction(recovering, "TelegraphSlam") == nil,
		"full recovery delay"
	)
	step(state, finishAt + 0.801, targets)
	assert(state.state == "Chase", "recovery has ended")
	assert(
		findAction(step(state, finishAt + 5.99, targets), "TelegraphSlam") == nil,
		"slam still on cooldown"
	)
	expectAction(step(state, finishAt + 6.001, targets), "TelegraphSlam")
end)

run("One lagged slam tick hits a grounded fighter crossed between radius samples once", function()
	local state = newBoss(false)
	local targets = { target(7, 14, 0, 0) }
	beginAttack(state, targets, "TelegraphSlam")
	step(state, 1.2, targets)
	local lagged = step(state, 1.8, targets)
	local ring = expectAction(lagged, "SlamShockwaveTick")
	assertNear(assert(ring.radius, "ring radius"), 20.8, "ring advanced beyond the fighter")
	local hit = expectAction(lagged, "SlamHit")
	assert(hit.playerId == 7 and hit.damage == 28, "grounded fighter crossed by the wave")
	assert(countActions(lagged, "SlamHit") == 1, "lagged tick delivers one hit")
	assert(
		countActions(step(state, 1.85, targets), "SlamHit") == 0,
		"no second hit from the same slam"
	)
end)

run("Dashing outside the slam ring and jumping above its hit height both avoid damage", function()
	local state = newBoss(false)
	local startingTargets = { target(7, 12, 0, 0), target(8, 12, 0, 0) }
	beginAttack(state, startingTargets, "TelegraphSlam")
	step(state, 1.2, startingTargets)
	local dodging = { target(7, 30, 0, 0), target(8, 12, 5.51, 0) }
	for _, now in { 1.4, 1.6, 1.8, 1.9501 } do
		assert(
			findAction(step(state, now, dodging), "SlamHit") == nil,
			"neither dodge should take damage"
		)
	end
	assert(state.state == "Recovery", "dodge fixture runs through the complete shockwave")
end)

-- Cases 18–20
run("Boulder windup locks its telegraphed direction while the target moves sideways", function()
	local state = newBoss(false)
	local telegraph = beginAttack(state, { target(7, 0, 0, 40) }, "TelegraphBoulder")
	local direction = assert(telegraph.direction, "telegraphed direction")
	assertNear(direction.X, 0, "telegraph lane X")
	assertNear(direction.Z, 1, "telegraph lane Z")
	local sidestep = { target(7, 10, 0, 40) }
	assert(findAction(step(state, 0.99, sidestep), "SpawnBoulder") == nil, "one-second windup")
	assert(
		state.state == "Windup_Boulder" and state.position.Z == 0,
		"boss stays in place during windup"
	)

	local spawned = expectAction(step(state, 1, sidestep), "SpawnBoulder")
	local id = assert(spawned.boulderId, "spawned boulder ID")
	local boulder = assert(state.boulders[id], "spawned boulder")
	assertNear(boulder.direction.X, 0, "locked boulder direction X")
	assertNear(boulder.direction.Z, 1, "locked boulder direction Z")
	local spawnZ = boulder.position.Z
	local moved = expectAction(step(state, 1.25, sidestep), "BoulderMoved")
	local position = assert(moved.position, "boulder travel position")
	assertNear(position.X, 0, "travel stays in the telegraphed lane")
	assertNear(position.Z - spawnZ, 11.5, "46 studs per second travel")
end)

run("A rolling boulder hits at the combined radii, knocks back, and despawns", function()
	local state = newBoss(false)
	local targets = { target(7, 0, 0, 40) }
	local id = startRolling(state, targets, 1)
	local justOutOfReach = step(state, 1.75, targets)
	assert(
		findAction(justOutOfReach, "BoulderHit") == nil,
		"5.5 studs away exceeds combined radius"
	)
	assert(state.boulders[id] ~= nil, "boulder is still rolling")

	local contact = step(state, 1.76, targets)
	local hit = expectAction(contact, "BoulderHit")
	assert(hit.boulderId == id and hit.playerId == 7 and hit.damage == 22, "boulder hit payload")
	assert(hit.knockbackImpulse == 42, "boulder knockback strength")
	assertNear(assert(hit.direction, "knockback direction").Z, 1, "forward knockback")
	expectDespawn(contact, id, "PlayerHit")
	assert(state.boulders[id] == nil, "impact removes boulder from state")
end)

run("Arena cover occludes a player even when one boulder step crosses both", function()
	local state = newBoss(false)
	local targets = { target(7, 0, 0, 40) }
	local id = startRolling(state, targets, 1)
	local pillar: AABB = {
		min = { X = -2, Y = -5, Z = 19 },
		max = { X = 2, Y = 5, Z = 21 },
	}
	local contact = step(state, 1.95, targets, { pillar })
	expectDespawn(contact, id, "ObstacleHit")
	assert(findAction(contact, "BoulderHit") == nil, "cover saves the fighter behind it")
	assert(state.boulders[id] == nil, "obstacle impact removes boulder")
end)

-- Case 21
run(
	"A single lagged boulder tick expires at the range or lifetime cap without hitting beyond it",
	function()
		for _, limit in
			{
				{ range = 75, cutoff = 75 / 46, finalZ = 75, targetZ = 82 },
				{ range = 200, cutoff = 2, finalZ = 92, targetZ = 100 },
			}
		do
			for _, delay in { limit.cutoff, 2.8 } do
				local config = table.clone(MOSSBACK)
				config.boulder = table.clone(MOSSBACK.boulder)
				config.boulder.maxDistance = limit.range
				local state = BossAIStateMachine.new(config, ORIGIN, 1_560, false, 0)
				local id = startRolling(state, { target(7, 0, 0, 40) }, 1)
				local actions = step(state, 1 + delay, { target(7, 0, 0, limit.targetZ) })
				assert(findAction(actions, "BoulderHit") == nil, "cannot hit beyond the cutoff")
				expectDespawn(actions, id, "Expired")
				local moved = expectAction(actions, "BoulderMoved")
				assertNear(
					assert(moved.position, "final boulder position").Z,
					limit.finalZ,
					"clipped travel"
				)
				assert(state.boulders[id] == nil, "boulder is removed in the cutoff tick")
			end
		end
	end
)

run("Boulder collision uses a supplied target radius instead of the default", function()
	local state = newBoss(false)
	local id = startRolling(state, { target(7, 0, 0, 40) }, 1)
	local fighter = target(7, 6, 0, 40)
	fighter.radius = 3
	local contact = step(state, 1.9, { fighter })
	assert(
		expectAction(contact, "BoulderHit").playerId == 7,
		"custom radius reaches the boulder lane"
	)
	expectDespawn(contact, id, "PlayerHit")
end)

run("A missed boulder expires at its 75-stud travel limit", function()
	local state = newBoss(false)
	local id = startRolling(state, { target(7, 0, 0, 40) }, 1)
	local approach = step(state, 2.63, {})
	assert(findAction(approach, "DespawnBoulder") == nil, "74.98 studs is within range")
	local expired = step(state, 2.64, {})
	expectDespawn(expired, id, "Expired")
	assert(
		findAction(expired, "BoulderHit") == nil and state.boulders[id] == nil,
		"unobstructed range cleanup"
	)
end)

run("A missed boulder with range remaining expires after two seconds", function()
	-- Default range expires before lifetime. Extend only the test range to isolate the lifetime limit.
	local boulder = table.clone(MOSSBACK.boulder)
	boulder.maxDistance = 200
	local config = table.clone(MOSSBACK)
	config.boulder = boulder
	local state = BossAIStateMachine.new(config, ORIGIN, 1_560, false, 0)
	local id = startRolling(state, { target(7, 0, 0, 40) }, 1)
	local approach = step(state, 2.99, {})
	assert(findAction(approach, "DespawnBoulder") == nil, "under two seconds old")
	local expired = step(state, 3, {})
	expectDespawn(expired, id, "Expired")
	assert(
		findAction(expired, "BoulderHit") == nil and state.boulders[id] == nil,
		"lifetime cleanup"
	)
end)

-- Case 22
run("Overcharged slam has a 1.02-second windup, 34 damage, and a 4.8-second cooldown", function()
	local state = newBoss(true)
	assert(state.currentHp == 2_184 and state.maxHp == 2_184, "Overcharged solo HP passed by arena")
	local targets = { target(7, 14, 0, 0) }
	beginAttack(state, targets, "TelegraphSlam")
	assert(
		findAction(step(state, 1.01, targets), "SlamHit") == nil and state.state == "Windup_Slam",
		"windup not yet complete"
	)
	step(state, 1.02, targets)
	assert(state.state == "Active_Slam", "Overcharged slam activates at 1.02 seconds")
	local hit = expectAction(step(state, 1.42, targets), "SlamHit")
	assert(hit.damage == 34 and hit.playerId == 7, "Overcharged slam damage is rounded")
	local finishAt = 1.7701
	step(state, finishAt, targets)
	assert(state.state == "Recovery", "Overcharged slam recovers")
	assertNear(state.slamReadyAt, finishAt + 4.8, "Overcharged slam cooldown")
end)

run("Overcharged boulders launch after 0.85 seconds, roll at 52.9, and hit for 26", function()
	local state = newBoss(true)
	local targets = { target(7, 0, 0, 40) }
	beginAttack(state, targets, "TelegraphBoulder")
	assert(
		findAction(step(state, 0.84, targets), "SpawnBoulder") == nil,
		"Overcharged windup not yet complete"
	)
	local spawn = expectAction(step(state, 0.85, targets), "SpawnBoulder")
	local id = assert(spawn.boulderId, "Overcharged boulder ID")
	assertNear(
		assert(state.boulders[id], "rolling Overcharged boulder").speed,
		52.9,
		"Overcharged speed"
	)
	assertNear(state.boulderReadyAt, 4.45, "Overcharged boulder cooldown is 3.6 seconds")
	local contact = step(state, 1.55, targets)
	assert(
		expectAction(contact, "BoulderHit").damage == 26,
		"Overcharged boulder damage is rounded"
	)
	expectDespawn(contact, id, "PlayerHit")
end)

-- Cases 23–24
run("Lethal damage during slam windup removes active boulders and defeats the boss once", function()
	local state = newBoss(false)
	local id = startRolling(state, { target(7, 0, 0, 40) }, 1)
	local targets = { target(7, 14, 0, 0) }
	local recoveryEnd = step(state, 1.71, targets)
	local attack = if state.state == "Chase" then step(state, 1.72, targets) else recoveryEnd
	expectAction(attack, "TelegraphSlam")
	assert(
		state.state == "Windup_Slam" and state.boulders[id] ~= nil,
		"lethal hit during windup with live boulder"
	)

	local lethal = BossAIStateMachine.applyDamage(state, 2_000, 1.73, 7)
	assert(
		lethal.ok and state.state == "Defeated" and state.currentHp == 0,
		"lethal hit clamps HP to zero"
	)
	assert(
		expectAction(lethal.actions, "BossDamaged").currentHp == 0,
		"damage action shows zero HP"
	)
	expectDespawn(lethal.actions, id, "BossDefeated")
	assert(countActions(lethal.actions, "BossDefeated") == 1, "one defeat event")
	assert(next(state.boulders) == nil, "no boulders remain after defeat")

	local duplicate = BossAIStateMachine.applyDamage(state, 1, 1.73, 7)
	assert(
		not duplicate.ok and duplicate.reason == "AlreadyDefeated",
		"same-frame second hit is rejected"
	)
	assert(#duplicate.actions == 0, "same-frame second hit does not announce another defeat")
	assert(#step(state, 4, targets) == 0, "defeated boss has no later movement or attacks")
end)

run(
	"Invalid boss damage and backwards ticks preserve HP, cooldown, and boulder position",
	function()
		local state = newBoss(false)
		local id = startRolling(state, { target(7, 0, 0, 40) }, 1)
		step(state, 1.25, {})
		local previousHp = state.currentHp
		local slamDeadline, boulderDeadline = state.slamReadyAt, state.boulderReadyAt
		local before = assert(state.boulders[id], "active boulder before rejected events")
		local oldPosition = { X = before.position.X, Y = before.position.Y, Z = before.position.Z }
		local oldTravel = before.traveled

		for _, amount in { 0, -10, 0 / 0 } do
			local rejected = BossAIStateMachine.applyDamage(state, amount, 1.25, 7)
			assert(
				not rejected.ok and rejected.reason == "InvalidDamage",
				"nonpositive or NaN damage"
			)
			assert(
				#rejected.actions == 0 and state.currentHp == previousHp,
				"invalid damage leaves HP intact"
			)
		end
		local backwards = BossAIStateMachine.tick(state, 1.24, {}, {})
		assert(
			not backwards.ok and backwards.reason == "NonMonotonicTime",
			"backwards tick rejection"
		)
		assert(
			#backwards.actions == 0 and state.lastTickTime == 1.25,
			"backwards tick keeps last accepted time"
		)
		assert(
			state.slamReadyAt == slamDeadline and state.boulderReadyAt == boulderDeadline,
			"cooldowns preserved"
		)
		local after = assert(state.boulders[id], "boulder after rejected tick")
		assert(
			after.position.X == oldPosition.X
				and after.position.Y == oldPosition.Y
				and after.position.Z == oldPosition.Z,
			"position preserved"
		)
		assert(after.traveled == oldTravel, "traveled distance preserved")
	end
)

print("PASS: BossAIStateMachine.spec.luau")
