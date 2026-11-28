--!strict
--[[
	LockOnLogic.luau
	Pure, Lune-testable Souls-like Lock-On targeting, horizontal target switching,
	camera framing/pitch-clamping, grace-window state machine, and ballistic aim solver.
]]

local req: any = require
local scriptRef: any = script
local isRoblox = type(scriptRef) == "userdata"
local CombatLogic = if isRoblox then req(scriptRef.Parent.CombatLogic) else req("./CombatLogic")
local MathUtil = if isRoblox then req(scriptRef.Parent.MathUtil) else req("./MathUtil")

export type ScreenCandidate = {
	id: string,
	u: number,
	v: number,
	depth: number,
	distance: number,
	isBoss: boolean?,
}

export type GraceState = {
	obstructedSec: number,
	offScreenSec: number,
}

export type CameraFrameInput = {
	playerX: number,
	playerY: number,
	playerZ: number,
	targetX: number,
	targetY: number,
	targetZ: number,
	prevFwdX: number,
	prevFwdZ: number,
	isBoss: boolean?,
}

export type CameraFrameOutput = {
	camX: number,
	camY: number,
	camZ: number,
	lookDirX: number,
	lookDirY: number,
	lookDirZ: number,
	fwdX: number,
	fwdZ: number,
	pitchDeg: number,
}

local LockOnLogic = {}

LockOnLogic.CONFIG = {
	MIN_LOCK_RANGE = 2.0,
	MAX_ACQUIRE_RANGE = 95,
	MAX_ACQUIRE_RANGE_BOSS = 130,
	MAX_BREAK_RANGE = 115,
	MAX_BREAK_RANGE_BOSS = 155,
	ACQUIRE_VIEWPORT_MARGIN = 0.03,
	TRACK_VIEWPORT_MARGIN = -0.05,
	WEIGHT_CENTER = 1.0,
	WEIGHT_DIST = 0.25,
	PLAYER_ANCHOR_HEIGHT = 2.2,
	CAM_BACK_DIST = 12.5,
	CAM_BACK_DIST_BOSS = 16.5,
	CAM_HEIGHT_OFFSET = 4.6,
	CAM_HEIGHT_OFFSET_BOSS = 5.6,
	CAM_SHOULDER_OFFSET = 2.1,
	FOCUS_BLEND_ALPHA = 0.64,
	PITCH_MIN_DEG = -32,
	PITCH_MAX_DEG = 28,
	CAM_POS_DAMPING = 10.5,
	CAM_LOOK_DAMPING = 12.0,
	CAM_SWITCH_LOOK_DAMPING = 14.5,
	CAM_SWITCH_BOOST_SEC = 0.25,
	WALL_SPHERE_RADIUS = 0.6,
	WALL_PULL_MARGIN = 0.55,
	MIN_WALL_DIST = 2.5,
	WALL_IN_SPEED = 28.0,
	WALL_OUT_SPEED = 7.5,
	CHAR_TURN_RATE = 16.0,
	CLOSE_RANGE_FREEZE_DIST = 3.2,
	MOUSE_SWITCH_DELTA_PX = 42,
	MOUSE_DECAY_RATE = 10.0,
	MOUSE_HORIZ_DOMINANCE = 1.25,
	TOUCH_SWITCH_SWIPE_PX = 55,
	TOUCH_HORIZ_DOMINANCE = 1.4,
	STICK_SWITCH_DEADZONE = 0.65,
	STICK_REARM_DEADZONE = 0.30,
	SWITCH_COOLDOWN_SEC = 0.28,
	MIN_SWITCH_SEPARATION_X = 0.015,
	OBSTRUCTION_GRACE_SEC = 0.50,
	OFFSCREEN_GRACE_SEC = 0.25,
}

local CFG = LockOnLogic.CONFIG

function LockOnLogic.getAcquireRange(isBoss: boolean?): number
	return if isBoss then CFG.MAX_ACQUIRE_RANGE_BOSS else CFG.MAX_ACQUIRE_RANGE
end

function LockOnLogic.getBreakRange(isBoss: boolean?): number
	return if isBoss then CFG.MAX_BREAK_RANGE_BOSS else CFG.MAX_BREAK_RANGE
end

function LockOnLogic.isWithinViewport(u: number, v: number, depth: number, margin: number): boolean
	if
		not MathUtil.isFinite(u)
		or not MathUtil.isFinite(v)
		or not MathUtil.isFinite(depth)
		or not MathUtil.isFinite(margin)
	then
		return false
	end
	if depth <= 0 then
		return false
	end
	return u >= margin and u <= (1 - margin) and v >= margin and v <= (1 - margin)
end

local function isCandidateEligible(cand: ScreenCandidate, margin: number): boolean
	if
		not MathUtil.isFinite(cand.distance)
		or cand.distance < CFG.MIN_LOCK_RANGE
		or cand.distance > LockOnLogic.getAcquireRange(cand.isBoss)
	then
		return false
	end
	return LockOnLogic.isWithinViewport(cand.u, cand.v, cand.depth, margin)
end

function LockOnLogic.selectAcquireCandidate(
	candidates: { ScreenCandidate },
	marginOverride: number?,
	anchorU: number?,
	anchorV: number?
): ScreenCandidate?
	local margin = if marginOverride ~= nil then marginOverride else CFG.ACQUIRE_VIEWPORT_MARGIN
	local refU = if anchorU ~= nil and MathUtil.isFinite(anchorU) then anchorU else 0.5
	local refV = if anchorV ~= nil and MathUtil.isFinite(anchorV) then anchorV else 0.5
	local best: ScreenCandidate? = nil
	local bestScore = math.huge

	for _, cand in ipairs(candidates) do
		if isCandidateEligible(cand, margin) then
			local du = cand.u - refU
			local dv = cand.v - refV
			local centerDist = math.sqrt(du * du + dv * dv)
			local maxR = LockOnLogic.getAcquireRange(cand.isBoss)
			local distNorm = math.clamp(cand.distance / maxR, 0, 1)
			local score = CFG.WEIGHT_CENTER * centerDist + CFG.WEIGHT_DIST * distNorm
			if score < bestScore then
				bestScore = score
				best = cand
			end
		end
	end
	return best
end

function LockOnLogic.selectSwitchCandidate(
	currentId: string?,
	currentU: number,
	currentV: number,
	candidates: { ScreenCandidate },
	dirSign: number,
	marginOverride: number?
): ScreenCandidate?
	if
		not MathUtil.isFinite(currentU)
		or not MathUtil.isFinite(currentV)
		or not MathUtil.isFinite(dirSign)
		or dirSign == 0
	then
		return nil
	end
	local sign = if dirSign > 0 then 1 else -1
	local margin = if marginOverride ~= nil then marginOverride else CFG.ACQUIRE_VIEWPORT_MARGIN
	local best: ScreenCandidate? = nil
	local bestScore = math.huge

	for _, cand in ipairs(candidates) do
		if cand.id ~= currentId and isCandidateEligible(cand, margin) then
			local dx = cand.u - currentU
			if dx * sign > CFG.MIN_SWITCH_SEPARATION_X then
				local dy = math.abs(cand.v - currentV)
				local maxR = LockOnLogic.getAcquireRange(cand.isBoss)
				local distNorm = math.clamp(cand.distance / maxR, 0, 1)
				local score = math.abs(dx) + 0.45 * dy + 0.12 * distNorm
				if score < bestScore then
					bestScore = score
					best = cand
				end
			end
		end
	end
	return best
end

function LockOnLogic.hasDirectionalCandidate(
	currentId: string?,
	currentU: number,
	currentV: number,
	candidates: { ScreenCandidate },
	dirSign: number,
	marginOverride: number?
): boolean
	return LockOnLogic.selectSwitchCandidate(
		currentId,
		currentU,
		currentV,
		candidates,
		dirSign,
		marginOverride
	) ~= nil
end

function LockOnLogic.createGraceState(): GraceState
	return {
		obstructedSec = 0,
		offScreenSec = 0,
	}
end

function LockOnLogic.stepGraceTimers(
	state: GraceState,
	isObstructed: boolean,
	isOffScreen: boolean,
	dt: number
): "Keep" | "Break"
	local stepDt = if MathUtil.isFinite(dt) and dt > 0 then dt else 0
	if isObstructed then
		state.obstructedSec += stepDt
	else
		state.obstructedSec = 0
	end
	if isOffScreen then
		state.offScreenSec += stepDt
	else
		state.offScreenSec = 0
	end
	if
		state.obstructedSec >= CFG.OBSTRUCTION_GRACE_SEC
		or state.offScreenSec >= CFG.OFFSCREEN_GRACE_SEC
	then
		return "Break"
	end
	return "Keep"
end

function LockOnLogic.stepMouseAccumulator(
	accumX: number,
	dx: number,
	dy: number,
	dt: number
): (number, number)
	local base = if MathUtil.isFinite(accumX) then accumX else 0
	local stepDt = if MathUtil.isFinite(dt) and dt > 0 then dt else 0
	local decayed = base * math.exp(-CFG.MOUSE_DECAY_RATE * stepDt)
	local safeDx = if MathUtil.isFinite(dx) then dx else 0
	local safeDy = if MathUtil.isFinite(dy) then dy else 0

	if
		math.abs(safeDx) > 0
		and math.abs(safeDx) >= math.abs(safeDy) * CFG.MOUSE_HORIZ_DOMINANCE
	then
		if decayed * safeDx < 0 then
			decayed = 0
		end
		decayed += safeDx
	end

	if math.abs(decayed) >= CFG.MOUSE_SWITCH_DELTA_PX then
		return 0, if decayed > 0 then 1 else -1
	end
	return decayed, 0
end

function LockOnLogic.evaluateTouchSwipe(dx: number, dy: number): number
	if not MathUtil.isFinite(dx) or not MathUtil.isFinite(dy) then
		return 0
	end
	if math.abs(dx) < CFG.TOUCH_SWITCH_SWIPE_PX then
		return 0
	end
	if math.abs(dx) < math.abs(dy) * CFG.TOUCH_HORIZ_DOMINANCE then
		return 0
	end
	return if dx > 0 then 1 else -1
end

function LockOnLogic.isTouchInThumbstickZone(
	x: number,
	y: number,
	viewportW: number,
	viewportH: number
): boolean
	if
		not MathUtil.isFinite(x)
		or not MathUtil.isFinite(y)
		or not MathUtil.isPositiveFinite(viewportW)
		or not MathUtil.isPositiveFinite(viewportH)
	then
		return false
	end
	return x < viewportW * 0.35 and y > viewportH * 0.45
end

function LockOnLogic.evaluateStickSwitch(
	stickX: number,
	stickY: number,
	armed: boolean
): (number, boolean)
	if not MathUtil.isFinite(stickX) or not MathUtil.isFinite(stickY) then
		return 0, armed
	end
	local absX = math.abs(stickX)
	if not armed then
		return 0, absX < CFG.STICK_REARM_DEADZONE
	end
	if absX >= CFG.STICK_SWITCH_DEADZONE and absX >= math.abs(stickY) * 1.15 then
		return if stickX > 0 then 1 else -1, false
	end
	return 0, true
end

local function normalize2D(x: number, z: number): (number, number)
	local mag = math.sqrt(x * x + z * z)
	if mag < 1e-4 then
		return 0, -1
	end
	return x / mag, z / mag
end

local function clampLookPitch(vx: number, vy: number, vz: number): (number, number, number, number)
	local mag = math.sqrt(vx * vx + vy * vy + vz * vz)
	if mag < 1e-4 then
		return 0, 0, -1, 0
	end
	local ux, uy, uz = vx / mag, vy / mag, vz / mag
	local rawPitch = math.asin(math.clamp(uy, -1, 1))
	local minRad = math.rad(CFG.PITCH_MIN_DEG)
	local maxRad = math.rad(CFG.PITCH_MAX_DEG)
	local clampedPitch = math.clamp(rawPitch, minRad, maxRad)
	local horizX, horizZ = normalize2D(ux, uz)
	local cosP = math.cos(clampedPitch)
	local sinP = math.sin(clampedPitch)
	return horizX * cosP, sinP, horizZ * cosP, math.deg(clampedPitch)
end

function LockOnLogic.computeLockedCameraFrame(input: CameraFrameInput): CameraFrameOutput
	local pX = input.playerX
	local pY = input.playerY + CFG.PLAYER_ANCHOR_HEIGHT
	local pZ = input.playerZ
	local dx = input.targetX - pX
	local dz = input.targetZ - pZ
	local horizDist = math.sqrt(dx * dx + dz * dz)

	local fwdX, fwdZ: number
	if horizDist >= CFG.CLOSE_RANGE_FREEZE_DIST then
		fwdX, fwdZ = dx / horizDist, dz / horizDist
	else
		fwdX, fwdZ = normalize2D(input.prevFwdX, input.prevFwdZ)
	end
	-- Right-handed cross product: forward x (0, 1, 0) = (-fwdZ, 0, fwdX)
	local rightX = -fwdZ
	local rightZ = fwdX

	local isBoss = input.isBoss == true
	local backDist = if isBoss then CFG.CAM_BACK_DIST_BOSS else CFG.CAM_BACK_DIST
	local heightOff = if isBoss then CFG.CAM_HEIGHT_OFFSET_BOSS else CFG.CAM_HEIGHT_OFFSET
	local shoulder = CFG.CAM_SHOULDER_OFFSET

	local camX = pX - fwdX * backDist + rightX * shoulder
	local camY = pY + heightOff
	local camZ = pZ - fwdZ * backDist + rightZ * shoulder

	local closeScale = math.clamp(horizDist / 10, 0.35, 1.0)
	local alpha = CFG.FOCUS_BLEND_ALPHA * closeScale
	local anchorFocusY = pY + 0.8
	local lookX = pX + (input.targetX - pX) * alpha
	local lookY = anchorFocusY + (input.targetY - anchorFocusY) * alpha
	local lookZ = pZ + (input.targetZ - pZ) * alpha

	local ldx, ldy, ldz, pitchDeg = clampLookPitch(lookX - camX, lookY - camY, lookZ - camZ)
	return {
		camX = camX,
		camY = camY,
		camZ = camZ,
		lookDirX = ldx,
		lookDirY = ldy,
		lookDirZ = ldz,
		fwdX = fwdX,
		fwdZ = fwdZ,
		pitchDeg = pitchDeg,
	}
end

local function evalArrivalHeight(
	uy: number,
	horiz: number,
	speed: number,
	gravity: number,
	loft: number
): number
	local cosSq = math.max(1e-4, 1 - uy * uy)
	local cosA = math.sqrt(cosSq)
	return (uy + loft) * (horiz / cosA) - (gravity * horiz * horiz) / (2 * speed * speed * cosSq)
end

function LockOnLogic.solveLockedBallisticAimDirection(
	ox: number,
	oy: number,
	oz: number,
	tx: number,
	ty: number,
	tz: number,
	speed: number,
	gravityOverride: number?,
	upwardLoftOverride: number?
): (number, number, number)
	if
		not MathUtil.isFinite(ox)
		or not MathUtil.isFinite(oy)
		or not MathUtil.isFinite(oz)
		or not MathUtil.isFinite(tx)
		or not MathUtil.isFinite(ty)
		or not MathUtil.isFinite(tz)
	then
		return 0, 0, -1
	end
	local dx = tx - ox
	local dy = ty - oy
	local dz = tz - oz
	local horiz = math.sqrt(dx * dx + dz * dz)
	if horiz < 1e-3 then
		return 0, if dy >= 0 then 1 else -1, 0
	end
	local s = if MathUtil.isPositiveFinite(speed) then speed else 115
	local g = if gravityOverride ~= nil and MathUtil.isPositiveFinite(gravityOverride)
		then gravityOverride
		else CombatLogic.BALL_GRAVITY
	local loft = if upwardLoftOverride ~= nil and MathUtil.isFinite(upwardLoftOverride)
		then upwardLoftOverride
		else CombatLogic.MANUAL_UPWARD_LOFT

	local lo = -0.82
	local hi = 0.64
	local yLo = evalArrivalHeight(lo, horiz, s, g, loft)
	local yHi = evalArrivalHeight(hi, horiz, s, g, loft)
	local uy: number
	if dy <= yLo then
		uy = lo
	elseif dy >= yHi then
		uy = hi
	else
		for _ = 1, 16 do
			local mid = 0.5 * (lo + hi)
			if evalArrivalHeight(mid, horiz, s, g, loft) < dy then
				lo = mid
			else
				hi = mid
			end
		end
		uy = 0.5 * (lo + hi)
	end

	local cosA = math.sqrt(math.max(1e-4, 1 - uy * uy))
	local hUnitX = dx / horiz
	local hUnitZ = dz / horiz
	return hUnitX * cosA, uy, hUnitZ * cosA
end

return LockOnLogic
