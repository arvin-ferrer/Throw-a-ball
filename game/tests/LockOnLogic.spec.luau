--!strict
--[[
	LockOnLogic.spec.luau
	Unit tests for pure Souls-like Lock-On targeting, horizontal screen-space switching,
	mouse/touch/stick flick thresholds, obstruction & off-screen grace timers, camera framing,
	pitch clamping, close-range singularity guard, and ballistic aim compensation.
]]

local CombatLogic = require("../src/shared/Utils/CombatLogic")
local LockOnLogic = require("../src/shared/Utils/LockOnLogic")

local function assertTrue(cond: boolean, label: string)
	if not cond then
		error(`Assertion failed: {label}`)
	end
end

-- 1. Strict viewport & behind-camera filtering
assertTrue(
	not LockOnLogic.isWithinViewport(0.5, 0.5, -10, 0.03),
	"Enemy behind camera (depth < 0) rejected"
)
assertTrue(
	not LockOnLogic.isWithinViewport(0.5, 0.5, 0, 0.03),
	"Enemy on camera plane (depth == 0) rejected"
)
assertTrue(
	not LockOnLogic.isWithinViewport(0.01, 0.5, 30, 0.03),
	"Enemy clipped past left acquire margin rejected"
)
assertTrue(not LockOnLogic.isWithinViewport(1.02, 0.5, 30, 0.03), "Enemy off right edge rejected")
assertTrue(LockOnLogic.isWithinViewport(0.5, 0.5, 30, 0.03), "Visible center enemy accepted")

-- 2. Acquisition scoring: center-screen priority over closer edge target + distance tie-break
local acquired = LockOnLogic.selectAcquireCandidate({
	{ id = "behind", u = 0.50, v = 0.50, depth = -15, distance = 15 },
	{ id = "offscreen", u = 1.20, v = 0.50, depth = 25, distance = 25 },
	{ id = "tooFar", u = 0.50, v = 0.50, depth = 110, distance = 110 },
	{ id = "nearEdge", u = 0.90, v = 0.50, depth = 18, distance = 18 },
	{ id = "centerMid", u = 0.52, v = 0.49, depth = 55, distance = 55 },
})
assertTrue(
	acquired ~= nil and acquired.id == "centerMid",
	"Center-screen visible enemy beats closer edge enemy and ignores behind/offscreen/tooFar"
)

-- Boss acquires up to extended boss arena range (130 studs)
local acquiredBoss = LockOnLogic.selectAcquireCandidate({
	{ id = "boss", u = 0.50, v = 0.50, depth = 120, distance = 120, isBoss = true },
})
assertTrue(
	acquiredBoss ~= nil and acquiredBoss.id == "boss",
	"Boss target eligible inside extended 130-stud boss acquire range"
)

-- Tie-breaker: two enemies equally centered -> nearer wins
local acquiredNear = LockOnLogic.selectAcquireCandidate({
	{ id = "far", u = 0.50, v = 0.50, depth = 75, distance = 75 },
	{ id = "near", u = 0.50, v = 0.50, depth = 25, distance = 25 },
})
assertTrue(acquiredNear ~= nil and acquiredNear.id == "near", "Closer target wins center tie-break")

-- 3. Horizontal screen-space switching only (Left / Right)
local pack: { LockOnLogic.ScreenCandidate } = {
	{ id = "leftFar", u = 0.15, v = 0.50, depth = 35, distance = 35 },
	{ id = "leftNear", u = 0.34, v = 0.51, depth = 40, distance = 40 },
	{ id = "center", u = 0.50, v = 0.50, depth = 38, distance = 38 },
	{ id = "rightNear", u = 0.67, v = 0.52, depth = 42, distance = 42 },
	{ id = "rightFar", u = 0.88, v = 0.50, depth = 30, distance = 30 },
	{ id = "behindRight", u = 0.60, v = 0.50, depth = -20, distance = 20 },
}
local swRight = LockOnLogic.selectSwitchCandidate("center", 0.50, 0.50, pack, 1)
assertTrue(swRight ~= nil and swRight.id == "rightNear", "Switch right picks nearest visible right")
local swLeft = LockOnLogic.selectSwitchCandidate("center", 0.50, 0.50, pack, -1)
assertTrue(swLeft ~= nil and swLeft.id == "leftNear", "Switch left picks nearest visible left")
local swPastEdge = LockOnLogic.selectSwitchCandidate("rightFar", 0.88, 0.50, pack, 1)
assertTrue(swPastEdge == nil, "Switch past rightmost target returns nil (keep current lock)")
assertTrue(
	LockOnLogic.hasDirectionalCandidate("center", 0.50, 0.50, pack, -1)
		and LockOnLogic.hasDirectionalCandidate("center", 0.50, 0.50, pack, 1)
		and not LockOnLogic.hasDirectionalCandidate("rightFar", 0.88, 0.50, pack, 1),
	"Directional chevron helper accurately reports left/right switch availability"
)

-- 4. Mouse flick accumulator (jitter rejection, vertical rejection, decay, brisk flick trigger)
local acc = 0
local dir = 0
acc, dir = LockOnLogic.stepMouseAccumulator(acc, 8, 2, 0.016)
assertTrue(dir == 0, "Small mouse jitter does not switch targets")
acc, dir = LockOnLogic.stepMouseAccumulator(acc, 10, 40, 0.016)
assertTrue(dir == 0, "Vertical-dominant mouse motion ignored")
acc, dir = LockOnLogic.stepMouseAccumulator(30, 0, 0, 0.35)
assertTrue(acc < 2 and dir == 0, "Mouse accumulator decays cleanly during pauses")
acc, dir = LockOnLogic.stepMouseAccumulator(0, 48, 4, 0.016)
assertTrue(dir == 1 and acc == 0, "Brisk rightward mouse flick triggers +1 and resets")
acc, dir = LockOnLogic.stepMouseAccumulator(0, -50, -3, 0.016)
assertTrue(dir == -1 and acc == 0, "Brisk leftward mouse flick triggers -1 and resets")

-- 5. Touch swipe & thumbstick exclusion + gamepad stick re-arm
assertTrue(LockOnLogic.evaluateTouchSwipe(25, 0) == 0, "Short touch drag does not switch")
assertTrue(LockOnLogic.evaluateTouchSwipe(70, 65) == 0, "Diagonal/vertical touch drag ignored")
assertTrue(LockOnLogic.evaluateTouchSwipe(68, 10) == 1, "Brisk horizontal right swipe triggers +1")
assertTrue(LockOnLogic.evaluateTouchSwipe(-68, 5) == -1, "Brisk horizontal left swipe triggers -1")
assertTrue(
	LockOnLogic.isTouchInThumbstickZone(120, 420, 844, 390)
		or LockOnLogic.isTouchInThumbstickZone(120, 300, 844, 390),
	"Bottom-left thumbstick quadrant excluded from swipe switching"
)
assertTrue(
	not LockOnLogic.isTouchInThumbstickZone(500, 200, 844, 390),
	"Center/right viewport touch allowed for swipe switching"
)

local sDir, sArmed = LockOnLogic.evaluateStickSwitch(0.80, 0.0, true)
assertTrue(sDir == 1 and not sArmed, "Right stick flick fires once and disarms")
sDir, sArmed = LockOnLogic.evaluateStickSwitch(0.85, 0.0, sArmed)
assertTrue(sDir == 0 and not sArmed, "Held stick does not double-fire before returning neutral")
sDir, sArmed = LockOnLogic.evaluateStickSwitch(0.10, 0.0, sArmed)
assertTrue(sDir == 0 and sArmed, "Returning stick to neutral re-arms switching")

-- 6. Obstruction (0.50s) & off-screen (0.25s) grace timers
local grace = LockOnLogic.createGraceState()
assertTrue(
	LockOnLogic.stepGraceTimers(grace, true, false, 0.30) == "Keep",
	"Brief 0.30s tree obstruction keeps lock"
)
assertTrue(
	LockOnLogic.stepGraceTimers(grace, false, false, 0.05) == "Keep" and grace.obstructedSec == 0,
	"Clearing obstruction resets grace timer to 0"
)
assertTrue(
	LockOnLogic.stepGraceTimers(grace, true, false, 0.49) == "Keep",
	"0.49s obstruction still inside grace window"
)
assertTrue(
	LockOnLogic.stepGraceTimers(grace, true, false, 0.02) == "Break",
	"Crossing 0.50s solid wall obstruction triggers Break"
)

local offGrace = LockOnLogic.createGraceState()
assertTrue(
	LockOnLogic.stepGraceTimers(offGrace, false, true, 0.20) == "Keep",
	"0.20s off-screen keeps lock"
)
assertTrue(
	LockOnLogic.stepGraceTimers(offGrace, false, true, 0.06) == "Break",
	"Crossing 0.25s off-screen triggers Break"
)

-- 7. Locked camera framing, close-range singularity guard & pitch clamping
local normalFrame = LockOnLogic.computeLockedCameraFrame({
	playerX = 0,
	playerY = 5,
	playerZ = 0,
	targetX = 0,
	targetY = 5,
	targetZ = -30,
	prevFwdX = 0,
	prevFwdZ = -1,
	isBoss = false,
})
assertTrue(
	normalFrame.camZ > 10 and normalFrame.camY > 9 and normalFrame.lookDirZ < -0.8,
	"Locked camera positions behind & above player looking toward target"
)

local closeFrame = LockOnLogic.computeLockedCameraFrame({
	playerX = 0,
	playerY = 5,
	playerZ = 0,
	targetX = 0.1,
	targetY = 5,
	targetZ = 0.2,
	prevFwdX = 0,
	prevFwdZ = -1,
	isBoss = false,
})
assertTrue(
	math.abs(closeFrame.fwdX) < 1e-4 and math.abs(closeFrame.fwdZ + 1) < 1e-4,
	"Close-range (< 3.2 studs) preserves previous stable forward direction (no 180 whip)"
)

local perchedFrame = LockOnLogic.computeLockedCameraFrame({
	playerX = 0,
	playerY = 5,
	playerZ = 0,
	targetX = 0,
	targetY = 60,
	targetZ = -8,
	prevFwdX = 0,
	prevFwdZ = -1,
	isBoss = false,
})
assertTrue(
	perchedFrame.pitchDeg <= LockOnLogic.CONFIG.PITCH_MAX_DEG + 1e-3,
	"High perched target clamps camera pitch cleanly at +28 deg"
)

local lowFrame = LockOnLogic.computeLockedCameraFrame({
	playerX = 0,
	playerY = 40,
	playerZ = 0,
	targetX = 0,
	targetY = 0,
	targetZ = -6,
	prevFwdX = 0,
	prevFwdZ = -1,
	isBoss = false,
})
assertTrue(
	lowFrame.pitchDeg >= LockOnLogic.CONFIG.PITCH_MIN_DEG - 1e-3,
	"Steep downward target clamps camera pitch cleanly at -32 deg"
)

-- 8. Exact ballistic inverse-loft aim solver round-trip against CombatLogic
local ballisticCases = {
	{
		label = "Close Moss Slime (10 studs)",
		ox = 0,
		oy = 4.4,
		oz = 0,
		tx = 0,
		ty = 2.0,
		tz = -10,
		spd = 115,
	},
	{
		label = "Mid Mob (45 studs)",
		ox = 5,
		oy = 4.4,
		oz = -2,
		tx = 35,
		ty = 4.5,
		tz = -35,
		spd = 115,
	},
	{
		label = "Far Mob (90 studs)",
		ox = 0,
		oy = 4.4,
		oz = 0,
		tx = 0,
		ty = 5.0,
		tz = -90,
		spd = 125,
	},
	{
		label = "Perched Witch (+22 Y, 48 studs)",
		ox = 0,
		oy = 4.4,
		oz = 0,
		tx = 20,
		ty = 26.4,
		tz = -44,
		spd = 115,
	},
}
for _, c in ipairs(ballisticCases) do
	local ax, ay, az =
		LockOnLogic.solveLockedBallisticAimDirection(c.ox, c.oy, c.oz, c.tx, c.ty, c.tz, c.spd)
	local vx, vy, vz = CombatLogic.computeBallisticLaunchVelocity(
		ax,
		ay,
		az,
		c.spd,
		CombatLogic.MANUAL_UPWARD_LOFT
	)
	local horizDist = math.sqrt((c.tx - c.ox) ^ 2 + (c.tz - c.oz) ^ 2)
	local horizSpeed = math.sqrt(vx * vx + vz * vz)
	local tHit = horizDist / horizSpeed
	local hx, hy, hz = CombatLogic.sampleBallisticPosition(c.ox, c.oy, c.oz, vx, vy, vz, tHit)
	local err = math.sqrt((hx - c.tx) ^ 2 + (hy - c.ty) ^ 2 + (hz - c.tz) ^ 2)
	assertTrue(err < 0.05, `{c.label} ballistic arrival error ({err}) < 0.05 studs`)
end

print("PASS: LockOnLogic.spec.luau")
