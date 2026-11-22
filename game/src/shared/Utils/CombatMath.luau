--!strict
--[[
	Pure combat math (Issue #5). No Roblox APIs: vectors are plain {X, Y, Z} tables so the
	same code runs in Lune and on the server. Mirrors PR #22's ProjectileArc equation.
]]

-- selene: allow(incorrect_standard_library_use) -- string require: same path in Lune and Roblox
local ArenaStateMachine = require("./ArenaStateMachine")
-- selene: allow(incorrect_standard_library_use)
local CombatConfigs = require("../Configs/CombatConfigs")

local THROW = CombatConfigs.Throw
local TRAINING = CombatConfigs.Training
local PROGRESSION = CombatConfigs.PlayerProgression
local MIN_DIRECTION_LENGTH = 1e-6

export type Vec3 = { X: number, Y: number, Z: number }
export type AABB = { min: Vec3, max: Vec3 }
export type ArcConfig = { speed: number, gravity: number, maxDuration: number, stepSeconds: number }
export type ArcSegment = { tStart: number, tEnd: number, startPos: Vec3, endPos: Vec3 }
export type ThrowRateState = { lastThrowTime: number, nextAllowedTime: number }
export type ValidatedThrow = {
	ok: boolean,
	reason: string?,
	origin: Vec3?,
	direction: Vec3?,
	cooldownSeconds: number?,
	onTrainingPadHint: boolean?,
}
export type TrainingPadBox = {
	center: Vec3,
	halfSize: Vec3,
	minY: number,
	maxY: number,
	ownerUserId: number,
}
export type SweepTarget = { id: string, kind: string, position: Vec3, radius: number }
export type SweepHit = {
	hit: boolean,
	hitKind: string, -- "Player" | "Boss" | "Mob" | "Target" (from SweepTarget.kind), "World", "None"
	target: SweepTarget?,
	hitPosition: Vec3?,
	t: number?,
}

local CombatMath = {}

-- Vectors ------------------------------------------------------------------------------

local function isFinite(n: unknown): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function add(a: Vec3, b: Vec3): Vec3
	return { X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z }
end

local function sub(a: Vec3, b: Vec3): Vec3
	return { X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }
end

local function scale(a: Vec3, s: number): Vec3
	return { X = a.X * s, Y = a.Y * s, Z = a.Z * s }
end

local function dot(a: Vec3, b: Vec3): number
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end

local function length(a: Vec3): number
	return math.sqrt(dot(a, a))
end

local function lerp(a: Vec3, b: Vec3, t: number): Vec3
	return add(a, scale(sub(b, a), t))
end

CombatMath.add, CombatMath.sub, CombatMath.scale = add, sub, scale
CombatMath.dot, CombatMath.length, CombatMath.lerp = dot, length, lerp

-- Untrusted {X,Y,Z} (or Vector3-like) -> clean Vec3, or nil if any component is not finite.
function CombatMath.toVec3(value: unknown): Vec3?
	if type(value) ~= "table" then
		return nil
	end
	local v = value :: any
	if not (isFinite(v.X) and isFinite(v.Y) and isFinite(v.Z)) then
		return nil
	end
	return { X = v.X, Y = v.Y, Z = v.Z }
end

-- Stats ----------------------------------------------------------------------------------

local function sanitizeStat(value: number): number
	return if isFinite(value) and value > 0 then value else 0
end

function CombatMath.computeThrowCooldown(throwSpeed: number): number
	local s = sanitizeStat(throwSpeed)
	local span = THROW.BASE_THROW_COOLDOWN - THROW.MIN_THROW_COOLDOWN
	return THROW.MIN_THROW_COOLDOWN + span / (1 + s / THROW.THROW_SPEED_HALF_SATURATION)
end

local function tierOf(ballTierId: string): CombatConfigs.BallTier
	return CombatConfigs.BallTiers[ballTierId] or CombatConfigs.BallTiers.RubberBall
end

function CombatMath.computeProjectileSpeed(ballTierId: string, throwSpeed: number): number
	local s = sanitizeStat(throwSpeed)
	local bonus = THROW.MAX_THROW_SPEED_VEL_BONUS * (s / (s + THROW.THROW_SPEED_HALF_SATURATION))
	return tierOf(ballTierId).projectileSpeed * (1 + bonus)
end

function CombatMath.computeBallDamage(
	baseBallDamage: number,
	ballTierId: string,
	bonusMultiplier: number?
): number
	local base = if isFinite(baseBallDamage) and baseBallDamage > 0
		then baseBallDamage
		else THROW.DEFAULT_BASE_BALL_DAMAGE
	local bonus = if bonusMultiplier
			and isFinite(bonusMultiplier)
			and bonusMultiplier > 0
		then bonusMultiplier
		else 1
	local raw = base * tierOf(ballTierId).damageMultiplier * bonus
	return if isFinite(raw) then math.max(1, raw) else THROW.DEFAULT_BASE_BALL_DAMAGE
end

function CombatMath.computeBossMaxHp(
	baseBossHp: number,
	optInCount: number,
	isOvercharged: boolean
): number
	assert(isFinite(baseBossHp) and baseBossHp > 0, "baseBossHp must be positive and finite")
	local count = if isFinite(optInCount) then math.max(1, math.floor(optInCount)) else 1
	return ArenaStateMachine.computeBossMaxHp(baseBossHp, count, isOvercharged)
end

function CombatMath.computeTrainingGain(
	targetTierId: string,
	isMovingGold: boolean
): (number, number)
	local tier = TRAINING.TargetTiers[targetTierId] or TRAINING.TargetTiers.WoodenDummy
	local gold = if isMovingGold then TRAINING.MOVING_GOLD_DAMAGE_MULT else 1
	local speedGain = if isMovingGold then TRAINING.MOVING_GOLD_THROW_SPEED_GAIN else 0
	return TRAINING.BASE_TRAINING_DAMAGE_GAIN * tier.damageMult * gold, speedGain
end

-- Returns EXP, Ball Damage progress, Coins for one kill.
function CombatMath.computeMobRewards(
	mobId: string,
	biomeDamageMultiplier: number
): (number, number, number)
	local mob = CombatConfigs.Mobs[mobId]
	if not mob then
		return 0, 0, 0
	end
	local mult = if isFinite(biomeDamageMultiplier) and biomeDamageMultiplier > 0
		then biomeDamageMultiplier
		else 1
	return mob.expReward, mob.baseBallDamageGain * mult, mob.coinsReward
end

local function expToNext(level: number): number
	return math.floor(PROGRESSION.EXP_BASE * PROGRESSION.EXP_GROWTH ^ (level - 1) + 0.5)
end

-- Returns the new level, leftover EXP and the resulting max HP.
function CombatMath.applyExp(level: number, exp: number, gained: number): (number, number, number)
	local lvl = if isFinite(level) then math.max(1, math.floor(level)) else 1
	local base = if isFinite(exp) then math.max(0, exp) else 0
	local total = base + (if isFinite(gained) and gained > 0 then gained else 0)
	if not isFinite(total) then
		total = base -- an unrepresentable gain is dropped, never propagated as inf
	end
	while total >= expToNext(lvl) do
		total -= expToNext(lvl)
		lvl += 1
	end
	return lvl, total, PROGRESSION.BASE_MAX_HP + PROGRESSION.HP_PER_LEVEL * (lvl - 1)
end

-- Throw validation -------------------------------------------------------------------------

function CombatMath.newRateState(): ThrowRateState
	return { lastThrowTime = -math.huge, nextAllowedTime = -math.huge }
end

local function rejectThrow(reason: string): ValidatedThrow
	return { ok = false, reason = reason }
end

-- Client sends intent only ({origin, direction, onTrainingPad}); damage, tier and target
-- always come from the server. Rejections never consume cooldown.
function CombatMath.validateThrowPayload(
	payload: unknown,
	playerRootPos: Vec3,
	rate: ThrowRateState,
	throwSpeed: number,
	now: number,
	maxOriginDist: number?
): ValidatedThrow
	if type(payload) ~= "table" then
		return rejectThrow("InvalidPayload")
	end
	local p = payload :: any
	local origin = CombatMath.toVec3(p.origin)
	if not origin then
		return rejectThrow("InvalidOrigin")
	end
	local rawDirection = CombatMath.toVec3(p.direction)
	local dirLength = if rawDirection then length(rawDirection) else 0
	if not rawDirection or not isFinite(dirLength) or dirLength < MIN_DIRECTION_LENGTH then
		return rejectThrow("InvalidDirection")
	end
	if not isFinite(now) or now < rate.lastThrowTime then
		return rejectThrow("NonMonotonicTime")
	end
	local limit = maxOriginDist or THROW.MAX_ORIGIN_DISTANCE_STUDS
	local originGap = length(sub(origin, playerRootPos))
	-- Fail closed: a NaN root or limit must never let a throw through.
	if not (isFinite(originGap) and isFinite(limit) and originGap <= limit) then
		return rejectThrow("OriginTooFar")
	end
	if now < rate.nextAllowedTime - THROW.COOLDOWN_JITTER_TOLERANCE then
		return rejectThrow("RateLimited")
	end
	local cooldown = CombatMath.computeThrowCooldown(throwSpeed)
	-- Debt carries over: an early (jittered) packet pushes the next deadline, so the average
	-- rate can never exceed 1 / cooldown.
	rate.nextAllowedTime = math.max(now, rate.nextAllowedTime) + cooldown
	rate.lastThrowTime = now
	return {
		ok = true,
		origin = origin,
		direction = scale(rawDirection, 1 / dirLength),
		cooldownSeconds = cooldown,
		onTrainingPadHint = p.onTrainingPad == true,
	}
end

function CombatMath.isPointOnOwnedPad(
	playerRootPos: Vec3,
	playerUserId: number,
	pad: TrainingPadBox,
	allowUnassigned: boolean?
): boolean
	local owned = if pad.ownerUserId == 0
		then allowUnassigned == true
		else pad.ownerUserId == playerUserId
	local dy = playerRootPos.Y - pad.center.Y
	return owned
		and math.abs(playerRootPos.X - pad.center.X) <= pad.halfSize.X
		and math.abs(playerRootPos.Z - pad.center.Z) <= pad.halfSize.Z
		and dy >= pad.minY
		and dy <= pad.maxY
end

-- Ballistics ---------------------------------------------------------------------------------

function CombatMath.sampleArcPosition(origin: Vec3, unitDir: Vec3, t: number, cfg: ArcConfig): Vec3
	local p = add(origin, scale(unitDir, cfg.speed * t))
	p.Y -= 0.5 * cfg.gravity * t * t
	return p
end

function CombatMath.buildArcSegments(origin: Vec3, unitDir: Vec3, cfg: ArcConfig): { ArcSegment }
	assert(isFinite(cfg.maxDuration) and cfg.maxDuration > 0, "arc maxDuration must be positive")
	assert(isFinite(cfg.stepSeconds) and cfg.stepSeconds > 0, "arc stepSeconds must be positive")
	-- Same rule as PR #22: whole steps plus one partial final step; bounded against tiny steps.
	local count = math.clamp(math.ceil(cfg.maxDuration / cfg.stepSeconds - 1e-9), 1, 256)
	local segments = {}
	local prevT, prevPos = 0, origin
	for i = 1, count do
		local t = math.min(i * cfg.stepSeconds, cfg.maxDuration)
		local pos = CombatMath.sampleArcPosition(origin, unitDir, t, cfg)
		table.insert(segments, { tStart = prevT, tEnd = t, startPos = prevPos, endPos = pos })
		prevT, prevPos = t, pos
	end
	return segments
end

-- Collision ----------------------------------------------------------------------------------

-- Earliest fraction s in [0,1] where segment a->b comes within `radius` of center (inclusive).
local function isFiniteVec(v: Vec3): boolean
	return isFinite(v.X) and isFinite(v.Y) and isFinite(v.Z)
end

function CombatMath.intersectSegmentSphere(a: Vec3, b: Vec3, center: Vec3, radius: number): number?
	if
		not (isFiniteVec(a) and isFiniteVec(b) and isFiniteVec(center) and isFinite(radius))
		or radius < 0
	then
		return nil -- bogus geometry never produces a hit
	end
	local r2 = radius * radius + 1e-9 -- inclusive: a tangent graze counts
	local toCenter = sub(center, a)
	if dot(toCenter, toCenter) <= r2 then
		return 0 -- starts inside
	end
	local d = sub(b, a)
	local segLen2 = dot(d, d)
	if segLen2 == 0 then
		return nil
	end
	-- Solve on the infinite line first, then clip to the segment, so the entry point is exact
	-- even when the sphere's centre projects past an endpoint.
	local s0 = dot(toCenter, d) / segLen2
	local perp = sub(add(a, scale(d, s0)), center)
	local perp2 = dot(perp, perp)
	if perp2 > r2 then
		return nil
	end
	local half = math.sqrt(math.max(0, r2 - perp2) / segLen2)
	local entry, exit = s0 - half, s0 + half
	if exit < 0 or entry > 1 then
		return nil
	end
	return math.max(0, entry)
end

-- Slab test: earliest fraction s in [0,1] where segment a->b enters the box (0 if it starts inside).
function CombatMath.intersectSegmentAABB(a: Vec3, b: Vec3, box: AABB): number?
	local tMin, tMax = 0, 1
	for _, axis in { "X", "Y", "Z" } do
		local origin, delta = (a :: any)[axis], (b :: any)[axis] - (a :: any)[axis]
		local lo, hi = (box.min :: any)[axis], (box.max :: any)[axis]
		if math.abs(delta) < 1e-12 then
			if origin < lo or origin > hi then
				return nil
			end
		else
			local t1, t2 = (lo - origin) / delta, (hi - origin) / delta
			tMin, tMax = math.max(tMin, math.min(t1, t2)), math.min(tMax, math.max(t1, t2))
			if tMin > tMax then
				return nil
			end
		end
	end
	return tMin
end

local function earliestOnSegment(
	seg: ArcSegment,
	ballRadius: number,
	targets: { SweepTarget },
	obstacles: { AABB },
	excludeId: string?
): (number?, SweepTarget?)
	local bestS: number?, bestTarget: SweepTarget? = nil, nil
	for _, box in obstacles do
		local s = CombatMath.intersectSegmentAABB(seg.startPos, seg.endPos, box)
		if s and (bestS == nil or s < bestS) then
			bestS, bestTarget = s, nil
		end
	end
	for _, target in targets do
		if target.id ~= excludeId then
			local r = target.radius + ballRadius
			local s =
				CombatMath.intersectSegmentSphere(seg.startPos, seg.endPos, target.position, r)
			if s and (bestS == nil or s < bestS) then
				bestS, bestTarget = s, target
			end
		end
	end
	return bestS, bestTarget
end

-- Walk the arc segment by segment; the first thing touched (target sphere or world box) wins.
function CombatMath.sweepProjectile(
	origin: Vec3,
	unitDir: Vec3,
	cfg: ArcConfig,
	ballRadius: number,
	targets: { SweepTarget },
	worldObstacles: { AABB },
	excludeId: string?
): SweepHit
	for _, seg in CombatMath.buildArcSegments(origin, unitDir, cfg) do
		local s, target = earliestOnSegment(seg, ballRadius, targets, worldObstacles, excludeId)
		if s then
			return {
				hit = true,
				hitKind = if target then target.kind else "World",
				target = target,
				hitPosition = lerp(seg.startPos, seg.endPos, s),
				t = seg.tStart + (seg.tEnd - seg.tStart) * s,
			}
		end
	end
	return { hit = false, hitKind = "None" }
end

return CombatMath
