--!strict
local ProjectileArc = require("../src/shared/Utils/ProjectileArc")
local BallThrowController = require("../src/client/Controllers/BallThrowController")
local ClientNet = require("../src/shared/Utils/ClientNet")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(`{label}: expected {tostring(expected)}, got {tostring(actual)}`)
	end
end

local function assertNear(actual: number, expected: number, label: string, eps: number?)
	local tolerance = eps or 1e-4
	if math.abs(actual - expected) > tolerance then
		error(`{label}: expected {expected}, got {actual}`)
	end
end

-- 1. Ballistic kinematics: P(t) = O + dir * speed * t + 0.5 * (0, -g, 0) * t^2
do
	local origin = ProjectileArc.vec3(0, 10, 0)
	local dir = ProjectileArc.vec3(0, 0, -1)
	local config = { speed = 100, gravity = 40, maxDuration = 1.0, stepSeconds = 0.1 }

	local p0 = ProjectileArc.samplePosition(origin, dir, 0, config)
	assertNear(p0.X, 0, "t=0 X")
	assertNear(p0.Y, 10, "t=0 Y")
	assertNear(p0.Z, 0, "t=0 Z")

	local pHalf = ProjectileArc.samplePosition(origin, dir, 0.5, config)
	-- Y = 10 - 0.5 * 40 * 0.25 = 5.0; Z = -50
	assertNear(pHalf.X, 0, "t=0.5 X")
	assertNear(pHalf.Y, 5.0, "t=0.5 Y gravity drop")
	assertNear(pHalf.Z, -50.0, "t=0.5 Z forward travel")

	local vHalf = ProjectileArc.sampleVelocity(dir, 0.5, config)
	assertNear(vHalf.Y, -20.0, "t=0.5 vertical velocity")
	assertNear(vHalf.Z, -100.0, "t=0.5 forward velocity")
end

-- 2. Trajectory points and swept segments continuity
do
	local origin = ProjectileArc.vec3(2, 5, 0)
	local dir = ProjectileArc.vec3(1, 0.2, 0)
	local config = { speed = 120, gravity = 42, maxDuration = 0.5, stepSeconds = 0.1 }

	local points = ProjectileArc.buildTrajectoryPoints(origin, dir, config)
	assertEqual(#points, 6, "0.5s / 0.1s produces 6 points (t=0..0.5)")

	local segments = ProjectileArc.buildSegments(origin, dir, config)
	assertEqual(#segments, 5, "6 points produce 5 continuous swept segments")
	assertNear(segments[1].startPos.X, origin.X, "Segment 1 starts at origin")
	assertNear(
		segments[1].endPos.X,
		segments[2].startPos.X,
		"Segment 1 end matches Segment 2 start"
	)
	assertNear(segments[5].endPos.Y, points[6].Y, "Last segment end matches final point")
end

-- 3. Soft magnetic aim assist: generous in PvE, mildly tuned in PvP
do
	local origin = ProjectileArc.vec3(0, 5, 0)
	local rawDir = ProjectileArc.vec3(0, 0, -1)
	-- Candidate placed ~10 degrees to the right of forward at 50 studs distance
	local rad10 = math.rad(10)
	local candidate10Deg = {
		id = "Target10Deg",
		position = ProjectileArc.vec3(math.sin(rad10) * 50, 5, -math.cos(rad10) * 50),
		isPvP = false,
	}

	-- In PvE (14 deg cone, 0.55 pull), 10 deg target IS assisted
	local pveDir, pveMatch = ProjectileArc.applyAimAssist(origin, rawDir, { candidate10Deg }, "PvE")
	assertEqual(pveMatch ~= nil, true, "PvE assists 10-degree target")
	assertEqual(pveDir.X > 0.05, true, "PvE direction bends toward right target")
	assertNear(ProjectileArc.magnitude(pveDir), 1.0, "Assisted direction stays unit-length")

	-- In PvP (6.5 deg cone, 0.22 pull), 10 deg target is NOT assisted (dodging works cleanly!)
	local pvpDirFar, pvpMatchFar =
		ProjectileArc.applyAimAssist(origin, rawDir, { candidate10Deg }, "PvP")
	assertEqual(pvpMatchFar, nil, "PvP ignores 10-degree target outside mild cone")
	assertNear(pvpDirFar.X, 0, "Unassisted PvP direction stays unchanged")

	-- Candidate at 4 degrees IS mildly assisted in PvP, but less strongly than PvE
	local rad4 = math.rad(4)
	local candidate4Deg = {
		id = "Rival4Deg",
		position = ProjectileArc.vec3(math.sin(rad4) * 50, 5, -math.cos(rad4) * 50),
		isPvP = true,
	}
	local pvpDirNear, pvpMatchNear =
		ProjectileArc.applyAimAssist(origin, rawDir, { candidate4Deg }, "PvP")
	local pveDirNear = ProjectileArc.applyAimAssist(origin, rawDir, { candidate4Deg }, "PvE")
	assertEqual(pvpMatchNear ~= nil, true, "PvP mildly assists 4-degree rival")
	assertEqual(pvpDirNear.X > 0, true, "PvP pulls slightly toward 4-degree rival")
	assertEqual(pvpDirNear.X < pveDirNear.X, true, "PvP pull strength is milder than PvE")

	-- Candidate behind player is never assisted
	local behindCandidate = {
		id = "Behind",
		position = ProjectileArc.vec3(0, 5, 20),
		isPvP = false,
	}
	local behindDir, behindMatch =
		ProjectileArc.applyAimAssist(origin, rawDir, { behindCandidate }, "PvE")
	assertEqual(behindMatch, nil, "Target behind player is ignored")
	assertNear(behindDir.Z, -1, "Direction unchanged for target behind player")
end

-- 4. BallThrowController state: TrainingPad anchor + instant cancel on jump/move
do
	local net = ClientNet.new({ mode = "Mock" })
	local state = BallThrowController.createState({ net = net })

	assertEqual(state:isOnTrainingPad(), false, "Starts off TrainingPad")
	assertEqual(state:getTargetWalkSpeed(), 18, "Default free walk speed is 18")

	assertEqual(
		state:enterTrainingPad("Pad_1"),
		true,
		"Stepping onto own TrainingPad anchors player"
	)
	assertEqual(state:isOnTrainingPad(), true, "Player is anchored on TrainingPad")
	assertEqual(state:getTargetWalkSpeed(), 0, "Anchored TrainingPad WalkSpeed is 0")

	-- Jumping cancels TrainingPad lock immediately
	assertEqual(state:cancelTrainingPad("Jump"), true, "Jumping cancels TrainingPad immediately")
	assertEqual(state:isOnTrainingPad(), false, "No longer on TrainingPad after jump")
	assertEqual(state:getTargetWalkSpeed(), 18, "Restores walk speed 18 after cancel")

	-- Re-entry lockout prevents snapping straight back onto the pad while stepping off
	assertEqual(
		state:enterTrainingPad("Pad_1"),
		false,
		"Immediate re-entry blocked during exit lockout"
	)
	state:step(0.5, true)
	assertEqual(state:enterTrainingPad("Pad_1"), true, "Re-entry allowed after lockout expires")

	-- Moving off after entry settle grace cancels immediately
	state:step(0.2, true)
	assertEqual(state:handleMoveIntent(0.8), true, "Directional move cancels TrainingPad")
	assertEqual(state:isOnTrainingPad(), false, "Unlocked after moving off")
end

-- 5. BallThrowController state: Free movement (18/24) + Dash (0.35s impulse, 2.5s cooldown, coyote + buffer)
do
	local net = ClientNet.new({ mode = "Mock" })
	local state = BallThrowController.createState({ net = net })

	assertEqual(state:getTargetWalkSpeed(), 18, "Base walk speed 18")
	state:setSprinting(true)
	assertEqual(state:getTargetWalkSpeed(), 24, "Sprint speed 24")
	state:setSprinting(false)
	assertEqual(state:getTargetWalkSpeed(), 18, "Back to walk speed 18")

	-- Coyote dash works briefly after leaving ground (e.g. 0.08s airborne)
	state:step(0.08, false)
	assertEqual(state:requestDash(), true, "Dash succeeds within coyote window")
	assertEqual(state:isDashing(), true, "Dash active")
	assertNear(state:getDashCooldownRemaining(), 2.5, "Dash cooldown starts at 2.5s")

	-- Active during 0.35s impulse, ends right at 0.35s
	state:step(0.20, true)
	assertEqual(state:isDashing(), true, "Still dashing at 0.20s")
	state:step(0.16, true)
	assertEqual(state:isDashing(), false, "Dash ends after 0.35s")

	-- Input buffer: pressing dash 0.10s before cooldown ends buffers and fires automatically
	state:step(2.04, true) -- total elapsed 2.40s, 0.10s remaining
	assertEqual(state:requestDash(), false, "Dash rejected while 0.10s cooldown remains (buffered)")
	state:step(0.11, true)
	assertEqual(state:isDashing(), true, "Buffered dash fires as soon as 2.5s cooldown expires")
end

-- 6. Server-authoritative ThrowBall payload: sends ONLY aim origin & direction (never damage)
do
	local net = ClientNet.new({ mode = "Mock" })
	local capturedPayload: any = nil
	net:registerMockServerHandler("ThrowBall", function(payload: any)
		capturedPayload = payload
	end)

	local state = BallThrowController.createState({ net = net, projectileArc = ProjectileArc })
	local origin = ProjectileArc.vec3(0, 6, 0)
	local rawDir = ProjectileArc.vec3(0, 0, -1)

	local result = state:performThrow(origin, rawDir, {}, false)
	assertEqual(result.fired, true, "First throw fires")
	assertEqual(capturedPayload ~= nil, true, "ThrowBall remote received payload")
	assertEqual(capturedPayload.damage, nil, "Client never sends damage to server")
	assertEqual(capturedPayload.targetId, nil, "Client never sends trusted targetId to server")
	assertNear(capturedPayload.origin.Y, 6, "Payload origin Y")
	assertNear(capturedPayload.direction.Z, -1, "Payload normalized direction Z")

	-- Throw cooldown blocks instant spam
	local spamResult = state:performThrow(origin, rawDir, {}, false)
	assertEqual(spamResult.fired, false, "Immediate throw blocked by throw cooldown")
	state:step(0.5, true)

	-- Aim-assist mode switches dynamically from PvE -> PvP when arena phase changes
	local rad10 = math.rad(10)
	local target10Deg = {
		id = "Mob10Deg",
		position = ProjectileArc.vec3(math.sin(rad10) * 50, 6, -math.cos(rad10) * 50),
	}
	assertEqual(state:getAimAssistMode(), "PvE", "Default aim-assist mode is PvE")
	local pveThrow = state:performThrow(origin, rawDir, { target10Deg }, true)
	assertEqual(pveThrow.fired, true, "PvE assisted throw fires")
	assertEqual(pveThrow.assistedTargetId, "Mob10Deg", "PvE throw assists 10-deg target")

	state:step(0.5, true)
	state:setArenaPhase("PvP_EggScramble")
	assertEqual(state:getAimAssistMode(), "PvP", "PvP_EggScramble switches aim-assist to PvP")
	local pvpThrow = state:performThrow(origin, rawDir, { target10Deg }, true)
	assertEqual(pvpThrow.fired, true, "PvP throw fires")
	assertEqual(pvpThrow.assistedTargetId, nil, "Mild PvP assist does not lock 10-deg target")
end

print("PASS: ProjectileArc.spec.luau")
