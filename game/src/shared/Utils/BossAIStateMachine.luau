--!strict
--[[
	Pure Mossback Golem AI (Issue #5). No Roblox APIs: the server passes `now`, target
	snapshots and cover boxes in, then renders the returned BossActions.
	Idle -> Chase -> Windup_Slam -> Active_Slam -> Recovery -> Chase ...
	              -> Windup_Boulder -> (SpawnBoulder) -> Recovery -> Chase ...
	Any state -> Defeated (HP 0). Boulders roll independently of the boss state.
]]

-- selene: allow(incorrect_standard_library_use) -- string require: same path in Lune and Roblox
local CombatConfigs = require("../Configs/CombatConfigs")
-- selene: allow(incorrect_standard_library_use)
local CombatMath = require("./CombatMath")

type Vec3 = CombatMath.Vec3
type AABB = CombatMath.AABB

export type BossState =
	"Idle"
	| "Chase"
	| "Windup_Slam"
	| "Active_Slam"
	| "Windup_Boulder"
	| "Recovery"
	| "Defeated"

-- radius: the fighter's hit radius (defaults to the standard character radius).
export type TargetSnapshot = { playerId: number, position: Vec3, radius: number? }

export type Boulder = {
	id: number,
	position: Vec3,
	direction: Vec3,
	speed: number,
	traveled: number,
	spawnTime: number,
}

export type BossAction = {
	kind: string,
	position: Vec3?,
	direction: Vec3?,
	radius: number?,
	playerId: number?,
	damage: number?,
	boulderId: number?,
	knockbackImpulse: number?,
	currentHp: number?,
	maxHp: number?,
	reason: string?,
}

export type Result = { ok: boolean, reason: string?, actions: { BossAction } }

type Tuning = {
	moveSpeed: number,
	slamWindup: number,
	slamRecovery: number,
	slamCooldown: number,
	slamDamage: number,
	boulderWindup: number,
	boulderRecovery: number,
	boulderCooldown: number,
	boulderDamage: number,
	boulderSpeed: number,
}

local BossAIStateMachine = {}

local EPSILON = 1e-9
local PLAYER_RADIUS = CombatConfigs.Throw.PLAYER_HIT_RADIUS_STUDS

-- Overcharged: faster, shorter windups/recoveries/cooldowns, harder hits (GDD §4).
local function buildTuning(config: any, isOvercharged: boolean): Tuning
	local oc = config.overcharged
	local function m(key: string): number
		return if isOvercharged then oc[key] else 1
	end
	local function dmg(base: number): number
		return math.floor(base * m("damageMultiplier") + 0.5)
	end
	return {
		moveSpeed = config.moveSpeed * m("speedMultiplier"),
		slamWindup = config.slam.windupSeconds * m("windupMultiplier"),
		slamRecovery = config.slam.recoverySeconds * m("recoveryMultiplier"),
		slamCooldown = config.slam.cooldownSeconds * m("cooldownMultiplier"),
		slamDamage = dmg(config.slam.damage),
		boulderWindup = config.boulder.windupSeconds * m("windupMultiplier"),
		boulderRecovery = config.boulder.recoverySeconds * m("recoveryMultiplier"),
		boulderCooldown = config.boulder.cooldownSeconds * m("cooldownMultiplier"),
		boulderDamage = dmg(config.boulder.damage),
		boulderSpeed = config.boulder.speed * m("speedMultiplier"),
	}
end

function BossAIStateMachine.new(
	config: any,
	position: Vec3,
	maxHp: number,
	isOvercharged: boolean,
	now: number
)
	assert(maxHp == maxHp and maxHp > 0 and maxHp < math.huge, "maxHp must be positive and finite")
	assert(now == now and math.abs(now) < math.huge, "now must be finite")
	return {
		config = config,
		tuning = buildTuning(config, isOvercharged),
		isOvercharged = isOvercharged,
		state = "Idle" :: BossState,
		position = { X = position.X, Y = position.Y, Z = position.Z },
		currentHp = maxHp,
		maxHp = maxHp,
		lastTickTime = now,
		phaseEndsAt = now,
		slamReadyAt = now,
		boulderReadyAt = now,
		slamStartedAt = now,
		slamHitPlayers = {} :: { [number]: boolean },
		slamLastRadius = 0,
		lockedDirection = { X = 0, Y = 0, Z = 1 } :: Vec3,
		boulders = {} :: { [number]: Boulder },
		nextBoulderId = 1,
	}
end

export type State = typeof(BossAIStateMachine.new(nil :: any, { X = 0, Y = 0, Z = 0 }, 1, false, 0))

local function emit(actions: { BossAction }, kind: string): BossAction
	local action: BossAction = { kind = kind }
	table.insert(actions, action)
	return action
end

local function flatDelta(from: Vec3, to: Vec3): (Vec3, number)
	local d = { X = to.X - from.X, Y = 0, Z = to.Z - from.Z }
	return d, CombatMath.length(d)
end

-- Nearest by horizontal distance; ties go to the lowest player ID (deterministic).
local function pickTarget(state: State, targets: { TargetSnapshot }): (TargetSnapshot?, number)
	local best: TargetSnapshot?, bestDist = nil, math.huge
	for _, target in targets do
		local _, dist = flatDelta(state.position, target.position)
		if dist < bestDist or (dist == bestDist and best and target.playerId < best.playerId) then
			best, bestDist = target, dist
		end
	end
	return best, bestDist
end

-- Boulders -----------------------------------------------------------------------------------

local function despawn(state: State, actions: { BossAction }, id: number, reason: string)
	state.boulders[id] = nil
	local action = emit(actions, "DespawnBoulder")
	action.boulderId, action.reason = id, reason
end

local function firstContact(
	from: Vec3,
	to: Vec3,
	targets: { TargetSnapshot },
	obstacles: { AABB },
	radius: number
): (number?, TargetSnapshot?)
	local bestS: number?, bestTarget: TargetSnapshot? = nil, nil
	for _, box in obstacles do
		local s = CombatMath.intersectSegmentAABB(from, to, box)
		if s and (bestS == nil or s < bestS) then
			bestS, bestTarget = s, nil
		end
	end
	for _, target in targets do
		local r = target.radius
		local targetRadius = if r and r == r and r >= 0 and r < math.huge then r else PLAYER_RADIUS
		local s =
			CombatMath.intersectSegmentSphere(from, to, target.position, radius + targetRadius)
		if s and (bestS == nil or s < bestS) then
			bestS, bestTarget = s, target
		end
	end
	return bestS, bestTarget
end

local function stepBoulder(state: State, b: Boulder, ctx: { [string]: any })
	local cfg = state.config.boulder
	local from = b.position
	-- Clip this frame's travel to what the boulder has left, so a laggy frame can never sweep
	-- (and hit) past its range or lifetime.
	local lifeLeft = cfg.maxLifetimeSeconds - (ctx.now - ctx.dt - b.spawnTime)
	local travel =
		math.max(0, math.min(b.speed * ctx.dt, cfg.maxDistance - b.traveled, b.speed * lifeLeft))
	local to = CombatMath.add(from, CombatMath.scale(b.direction, travel))
	local s, hitTarget = firstContact(from, to, ctx.targets, ctx.obstacles, cfg.radius)
	if s then
		if hitTarget then
			local hit = emit(ctx.actions, "BoulderHit")
			hit.boulderId, hit.playerId, hit.damage =
				b.id, hitTarget.playerId, state.tuning.boulderDamage
			hit.knockbackImpulse, hit.direction = cfg.knockbackImpulse, b.direction
		end
		despawn(state, ctx.actions, b.id, if hitTarget then "PlayerHit" else "ObstacleHit")
		return
	end
	b.position = to
	b.traveled += travel
	local moved = emit(ctx.actions, "BoulderMoved")
	moved.boulderId, moved.position = b.id, to
	local expired = b.traveled + EPSILON >= cfg.maxDistance
		or ctx.now - b.spawnTime + EPSILON >= cfg.maxLifetimeSeconds
	if expired then
		despawn(state, ctx.actions, b.id, "Expired")
	end
end

local function spawnBoulder(state: State, actions: { BossAction }, now: number)
	local id = state.nextBoulderId
	state.nextBoulderId += 1
	local b: Boulder = {
		id = id,
		position = { X = state.position.X, Y = state.position.Y, Z = state.position.Z },
		direction = state.lockedDirection,
		speed = state.tuning.boulderSpeed,
		traveled = 0,
		spawnTime = now,
	}
	state.boulders[id] = b
	local action = emit(actions, "SpawnBoulder")
	action.boulderId, action.position, action.direction = id, b.position, b.direction
end

-- Attacks -------------------------------------------------------------------------------------

local function enterRecovery(state: State, now: number, duration: number)
	state.state = "Recovery"
	state.phaseEndsAt = now + duration
end

local function stepSlam(state: State, ctx: { [string]: any })
	local cfg = state.config.slam
	local elapsed = ctx.now - state.slamStartedAt
	local radius = cfg.maxRadius * math.clamp(elapsed / cfg.activeSeconds, 0, 1)
	local tick = emit(ctx.actions, "SlamShockwaveTick")
	tick.radius, tick.position = radius, state.position
	-- Swept annulus: everything the ring crossed since last frame, so lag can't skip a fighter.
	local inner = math.min(state.slamLastRadius, radius) - cfg.ringHalfWidth
	local outer = math.max(state.slamLastRadius, radius) + cfg.ringHalfWidth
	state.slamLastRadius = radius
	for _, target in ctx.targets do
		local _, dist = flatDelta(state.position, target.position)
		local inBand = dist >= inner and dist <= outer
		local grounded = target.position.Y - state.position.Y <= cfg.hitHeight
		if inBand and grounded and not state.slamHitPlayers[target.playerId] then
			state.slamHitPlayers[target.playerId] = true
			local hit = emit(ctx.actions, "SlamHit")
			hit.playerId, hit.damage = target.playerId, state.tuning.slamDamage
		end
	end
	if elapsed + EPSILON >= cfg.activeSeconds then
		state.slamReadyAt = ctx.now + state.tuning.slamCooldown
		enterRecovery(state, ctx.now, state.tuning.slamRecovery)
	end
end

local function startSlam(state: State, actions: { BossAction }, now: number)
	state.state = "Windup_Slam"
	state.phaseEndsAt = now + state.tuning.slamWindup
	local action = emit(actions, "TelegraphSlam")
	action.position, action.radius = state.position, state.config.slam.maxRadius
end

local function startBoulder(
	state: State,
	actions: { BossAction },
	now: number,
	target: TargetSnapshot
)
	local delta, dist = flatDelta(state.position, target.position)
	state.lockedDirection = CombatMath.scale(delta, 1 / dist) -- locked now: the telegraph never lies
	state.state = "Windup_Boulder"
	state.phaseEndsAt = now + state.tuning.boulderWindup
	local action = emit(actions, "TelegraphBoulder")
	action.position, action.direction = state.position, state.lockedDirection
end

local function chase(state: State, ctx: { [string]: any })
	local target, dist = pickTarget(state, ctx.targets)
	if not target then
		state.state = "Idle"
		return
	end
	state.state = "Chase"
	local cfg, now = state.config, ctx.now
	if now + EPSILON >= state.slamReadyAt and dist <= cfg.slam.triggerRange then
		startSlam(state, ctx.actions, now)
	elseif
		now + EPSILON >= state.boulderReadyAt
		and dist >= cfg.boulder.minRange
		and dist <= cfg.boulder.maxRange
	then
		startBoulder(state, ctx.actions, now, target)
	else
		local step = math.min(state.tuning.moveSpeed * ctx.dt, dist - cfg.meleeStopDistance)
		if step > 0 then
			local delta = flatDelta(state.position, target.position)
			state.position = CombatMath.add(state.position, CombatMath.scale(delta, step / dist))
			emit(ctx.actions, "MoveTo").position = state.position
		end
	end
end

local function stepBoss(state: State, ctx: { [string]: any })
	local now, s = ctx.now, state.state
	local phaseOver = now + EPSILON >= state.phaseEndsAt
	if s == "Windup_Slam" and phaseOver then
		state.state, state.slamStartedAt, state.slamLastRadius = "Active_Slam", now, 0
		table.clear(state.slamHitPlayers)
	elseif s == "Active_Slam" then
		stepSlam(state, ctx)
	elseif s == "Windup_Boulder" and phaseOver then
		spawnBoulder(state, ctx.actions, now)
		state.boulderReadyAt = now + state.tuning.boulderCooldown
		enterRecovery(state, now, state.tuning.boulderRecovery)
	elseif (s == "Recovery" and phaseOver) or s == "Chase" or s == "Idle" then
		chase(state, ctx)
	end
end

-- Public events --------------------------------------------------------------------------------

function BossAIStateMachine.tick(
	state: State,
	now: number,
	targets: { TargetSnapshot },
	obstacles: { AABB }
): Result
	if state.state == "Defeated" then
		return { ok = true, actions = {} }
	end
	if now ~= now or now == math.huge or now < state.lastTickTime then
		return { ok = false, reason = "NonMonotonicTime", actions = {} }
	end
	local ctx = {
		now = now,
		dt = now - state.lastTickTime,
		targets = targets,
		obstacles = obstacles,
		actions = {},
	}
	state.lastTickTime = now
	for _, boulder in table.clone(state.boulders) do
		stepBoulder(state, boulder, ctx)
	end
	stepBoss(state, ctx)
	return { ok = true, actions = ctx.actions }
end

function BossAIStateMachine.applyDamage(
	state: State,
	amount: number,
	_now: number,
	attackerId: number?
): Result
	if state.state == "Defeated" then
		return { ok = false, reason = "AlreadyDefeated", actions = {} }
	end
	if amount ~= amount or amount <= 0 or amount == math.huge then
		return { ok = false, reason = "InvalidDamage", actions = {} }
	end
	local actions = {}
	state.currentHp = math.max(0, state.currentHp - amount)
	local damaged = emit(actions, "BossDamaged")
	damaged.currentHp, damaged.maxHp, damaged.damage, damaged.playerId =
		state.currentHp, state.maxHp, amount, attackerId
	if state.currentHp == 0 then
		state.state = "Defeated"
		for id in table.clone(state.boulders) do
			despawn(state, actions, id, "BossDefeated")
		end
		emit(actions, "BossDefeated").playerId = attackerId
	end
	return { ok = true, actions = actions }
end

return BossAIStateMachine
