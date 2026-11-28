--!strict
--[[
	MobCombatLogic.luau
	Pure, Lune-testable server-authoritative mob AI & strictly NON-HOMING ballistic physics:
	- Exact analytical ballistic launch velocity solver (ground-to-ground & elevated tower-to-ground)
	- Pure gravity flight integrator (zero mid-flight target tracking)
	- Multi-mob pack formation offsets, perched balcony clamping, splash AoE, and archetype intents
]]

local req: any = require
local scriptRef: any = script
local isRoblox = type(scriptRef) == "userdata"
local MathUtil = if isRoblox then req(scriptRef.Parent.MathUtil) else req("./MathUtil")

export type MobIntent =
	"Dormant"
	| "Patrol"
	| "ReturnHome"
	| "Chase"
	| "MeleeAttack"
	| "RangedCast"
	| "ChargeTelegraph"
	| "Strafe"
	| "Retreat"
	| "PerchedIdle"

export type MobIntentInput = {
	archetype: string,
	isPerched: boolean,
	distToTarget: number?,
	distFromHome: number,
	aggroRange: number,
	leashRange: number,
	meleeRange: number,
	rangedMin: number?,
	rangedMax: number?,
	preferredMin: number?,
	preferredMax: number?,
	chargeMin: number?,
	chargeMax: number?,
	canRanged: boolean,
	canCharge: boolean,
	canMelee: boolean,
}

local MobCombatLogic = {}

MobCombatLogic.DORMANCY_RANGE = 160
MobCombatLogic.DEFAULT_GRAVITY = 42

function MobCombatLogic.solveBallisticVelocity(
	ox: number,
	oy: number,
	oz: number,
	tx: number,
	ty: number,
	tz: number,
	speed: number,
	gravity: number,
	highArc: boolean,
	maxPitchDeg: number?
): (number, number, number)
	local safeSpeed = if MathUtil.isPositiveFinite(speed) then speed else 60
	if
		not MathUtil.isFinite(ox)
		or not MathUtil.isFinite(oy)
		or not MathUtil.isFinite(oz)
		or not MathUtil.isFinite(tx)
		or not MathUtil.isFinite(ty)
		or not MathUtil.isFinite(tz)
		or not MathUtil.isPositiveFinite(gravity)
	then
		return 0, 0, -safeSpeed
	end

	local dx = tx - ox
	local dy = ty - oy
	local dz = tz - oz
	local horizDist = math.sqrt(dx * dx + dz * dz)
	if horizDist < 1e-3 then
		return 0, if dy >= 0 then safeSpeed else -safeSpeed, 0
	end
	local ux = dx / horizDist
	local uz = dz / horizDist

	local v2 = safeSpeed * safeSpeed
	local v4 = v2 * v2
	local disc = v4 - gravity * (gravity * horizDist * horizDist + 2 * dy * v2)
	local pitchRad: number
	if disc >= 0 then
		local root = math.sqrt(disc)
		local tanLow = (v2 - root) / (gravity * horizDist)
		local tanHigh = (v2 + root) / (gravity * horizDist)
		local capRad = math.rad(maxPitchDeg or (if highArc then 54 else 42))
		local chosenTan = if highArc and math.atan(tanHigh) <= capRad then tanHigh else tanLow
		pitchRad = math.clamp(math.atan(chosenTan), math.rad(-72), capRad)
	else
		pitchRad = math.rad(45)
	end

	local cosP = math.cos(pitchRad)
	local sinP = math.sin(pitchRad)
	return ux * safeSpeed * cosP, safeSpeed * sinP, uz * safeSpeed * cosP
end

function MobCombatLogic.applyHorizontalSpread(
	vx: number,
	vy: number,
	vz: number,
	yawDeg: number
): (number, number, number)
	if not MathUtil.isFinite(yawDeg) or math.abs(yawDeg) < 1e-4 then
		return vx, vy, vz
	end
	local rad = math.rad(yawDeg)
	local c = math.cos(rad)
	local s = math.sin(rad)
	return vx * c - vz * s, vy, vx * s + vz * c
end

function MobCombatLogic.stepBallisticPoint(
	px: number,
	py: number,
	pz: number,
	vx: number,
	vy: number,
	vz: number,
	dt: number,
	gravity: number
): (number, number, number, number, number, number)
	local g = if MathUtil.isPositiveFinite(gravity) then gravity else MobCombatLogic.DEFAULT_GRAVITY
	local step = math.max(0, dt)
	local nx = px + vx * step
	local ny = py + vy * step - 0.5 * g * step * step
	local nz = pz + vz * step
	return nx, ny, nz, vx, vy - g * step, vz
end

function MobCombatLogic.computePackOffsets(count: number, ringRadius: number): { { number } }
	local n = math.max(1, math.floor(count))
	if n == 1 then
		return { { 0, 0 } }
	end
	local r = if MathUtil.isPositiveFinite(ringRadius) then ringRadius else 6.5
	local out: { { number } } = {}
	for i = 1, n do
		local ang = (i - 1) * (math.pi * 2 / n)
		table.insert(out, { math.cos(ang) * r, math.sin(ang) * r })
	end
	return out
end

function MobCombatLogic.clampPerchedOffset(curOffset: number, maxOffset: number): number
	local limit = math.max(0, maxOffset)
	return math.clamp(curOffset, -limit, limit)
end

function MobCombatLogic.isWithinSplash(
	ix: number,
	iy: number,
	iz: number,
	tx: number,
	ty: number,
	tz: number,
	radius: number
): boolean
	if not MathUtil.isPositiveFinite(radius) then
		return false
	end
	local dx = tx - ix
	local dy = ty - iy
	local dz = tz - iz
	return (dx * dx + dy * dy + dz * dz) <= (radius * radius)
end

local function evaluateRangedCasterIntent(input: MobIntentInput, dist: number): MobIntent
	local rMin = input.rangedMin or 14
	local rMax = input.rangedMax or input.aggroRange
	if input.isPerched then
		if input.canRanged and dist >= rMin and dist <= rMax then
			return "RangedCast"
		end
		return "Strafe"
	end
	if input.canRanged and dist >= rMin and dist <= rMax then
		return "RangedCast"
	end
	local pMin = input.preferredMin or 26
	local pMax = input.preferredMax or 54
	if dist < pMin then
		return "Retreat"
	elseif dist > pMax then
		return "Chase"
	end
	return "Strafe"
end

function MobCombatLogic.evaluateMobIntent(input: MobIntentInput): MobIntent
	local dist = input.distToTarget
	if not input.isPerched and input.distFromHome > input.leashRange then
		return "ReturnHome"
	end
	if dist == nil or dist > MobCombatLogic.DORMANCY_RANGE then
		if not input.isPerched and input.distFromHome > 3.5 then
			return "ReturnHome"
		end
		return if input.isPerched then "PerchedIdle" else "Dormant"
	end
	if dist > input.aggroRange then
		if not input.isPerched and input.distFromHome > 4.0 then
			return "ReturnHome"
		end
		return if input.isPerched then "PerchedIdle" else "Patrol"
	end

	if input.archetype == "RangedCaster" then
		return evaluateRangedCasterIntent(input, dist)
	end
	if
		input.archetype == "Charger"
		and input.canCharge
		and input.chargeMin
		and input.chargeMax
		and dist >= input.chargeMin
		and dist <= input.chargeMax
	then
		return "ChargeTelegraph"
	end
	if
		input.canRanged
		and input.rangedMin
		and input.rangedMax
		and dist >= input.rangedMin
		and dist <= input.rangedMax
	then
		return "RangedCast"
	end
	if input.meleeRange > 0 and dist <= input.meleeRange then
		return if input.canMelee then "MeleeAttack" else "Chase"
	end
	return "Chase"
end

return MobCombatLogic
