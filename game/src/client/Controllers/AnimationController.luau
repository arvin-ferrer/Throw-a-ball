--!strict
--[[
	AnimationController.luau
	60 FPS Client Animation & Impact VFX Controller:
	- R15 (AnimationConstraint) & R6 (Motor6D) procedural throwing + AFK ready-stance animations
	  written cleanly to joint.Transform in RunService.PreSimulation (never modifies read-only C0/C1).
	- Distance-culled 60 FPS Motor6D procedural animation for all Pets, Mobs, Bosses, Eggs & Apex Halos.
	- Smooth 60 FPS SpinRing / FloatBob world prop animations.
	- Layered impact bursts (expanding shockwave ring + one-shot spark emit + Highlight hit-flash + recoil).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local AnimationController = {}

type JointPair = {
	rightShoulder: Instance?,
	leftShoulder: Instance?,
	waist: Instance?,
	rightElbow: Instance?,
	leftElbow: Instance?,
	rightHip: Instance?,
	leftHip: Instance?,
	rightKnee: Instance?,
	leftKnee: Instance?,
}

type ThrowState = {
	startTime: number,
	duration: number,
}

type DashState = {
	startTime: number,
	duration: number,
	dir: Vector3,
}

type RigMotorEntry = {
	motor: Motor6D,
	role: string,
	speed: number,
	amp: number,
	phase: number,
	model: Model?,
}

local localPlayer = Players.LocalPlayer
local activeThrows: { [Player]: ThrowState } = {}
local activeDashes: { [Player]: DashState } = {}
local rigMotors: { [Motor6D]: RigMotorEntry } = {}
local spinBases: { [BasePart]: { cf: CFrame, speed: number, axis: string } } = {}
local floatBases: { [BasePart]: { cf: CFrame, phase: number } } = {}
local recoilBusy: { [Instance]: boolean } = {}
local trainingStanceActive = false

local CULL_DISTANCE = 210

local function findJoint(char: Model, name: string): Instance?
	for _, desc in ipairs(char:GetDescendants()) do
		if desc.Name == name and (desc:IsA("Motor6D") or desc:IsA("AnimationConstraint")) then
			return desc
		end
	end
	return nil
end

local function resolveCharacterJoints(char: Model): JointPair
	local rightShoulder = findJoint(char, "RightShoulder") or findJoint(char, "Right Shoulder")
	local leftShoulder = findJoint(char, "LeftShoulder") or findJoint(char, "Left Shoulder")
	local waist = findJoint(char, "Waist") or findJoint(char, "RootJoint")
	local rightElbow = findJoint(char, "RightElbow")
	local leftElbow = findJoint(char, "LeftElbow")
	local rightHip = findJoint(char, "RightHip") or findJoint(char, "Right Hip")
	local leftHip = findJoint(char, "LeftHip") or findJoint(char, "Left Hip")
	local rightKnee = findJoint(char, "RightKnee")
	local leftKnee = findJoint(char, "LeftKnee")
	return {
		rightShoulder = rightShoulder,
		leftShoulder = leftShoulder,
		waist = waist,
		rightElbow = rightElbow,
		leftElbow = leftElbow,
		rightHip = rightHip,
		leftHip = leftHip,
		rightKnee = rightKnee,
		leftKnee = leftKnee,
	}
end

local function multiplyTransform(joint: Instance?, offset: CFrame)
	if not joint then
		return
	end
	if joint:IsA("Motor6D") or joint:IsA("AnimationConstraint") then
		local j: any = joint
		j.Transform = j.Transform * offset
	end
end

local function computeThrowCurve(alpha: number): (number, number, number, number)
	-- 0.00 -> 0.30: Wind-up back; 0.30 -> 0.58: Explosive overhand snap; 0.58 -> 1.00: Spring recover
	if alpha < 0.30 then
		local t = alpha / 0.30
		local ease = math.sin(t * math.pi * 0.5)
		return math.rad(-72) * ease, math.rad(-22) * ease, math.rad(34) * ease, math.rad(28) * ease
	elseif alpha < 0.58 then
		local t = (alpha - 0.30) / 0.28
		local ease = 1 - (1 - t) * (1 - t)
		local pitch = math.rad(-72) + math.rad(192) * ease
		local twist = math.rad(-22) + math.rad(50) * ease
		local elbow = math.rad(34) * (1 - ease)
		local offArm = math.rad(28) - math.rad(56) * ease
		return pitch, twist, elbow, offArm
	else
		local t = (alpha - 0.58) / 0.42
		local rem = 1 - (t * t * (3 - 2 * t))
		return math.rad(120) * rem, math.rad(28) * rem, 0, math.rad(-28) * rem
	end
end

local function computeDashEnvelope(alpha: number): number
	-- Instant explosive snap into Tailwind lean (0..0.18), sustained wind-glide (0.18..0.68), smooth spring recovery
	if alpha < 0.18 then
		local t = alpha / 0.18
		return 1 - (1 - t) * (1 - t)
	elseif alpha < 0.68 then
		return 1.0
	else
		local t = (alpha - 0.68) / 0.32
		return 1 - (t * t * (3 - 2 * t))
	end
end

local function applyJettDashPose(char: Model, joints: JointPair, dashSt: DashState, alpha: number)
	local env = computeDashEnvelope(alpha)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local localFwd = 1
	local localRight = 0
	if hrp and hrp:IsA("BasePart") then
		local flatDir = Vector3.new(dashSt.dir.X, 0, dashSt.dir.Z)
		if flatDir.Magnitude > 0.05 then
			local unitDir = flatDir.Unit
			localFwd = math.clamp(hrp.CFrame.LookVector:Dot(unitDir), -1, 1)
			localRight = math.clamp(hrp.CFrame.RightVector:Dot(unitDir), -1, 1)
		end
	end

	-- Aerodynamic torso lean INTO the wind-dash direction
	local leanPitch = math.rad(-34 * localFwd) * env
	local leanRoll = math.rad(-30 * localRight) * env
	local leanYaw = math.rad(16 * localRight) * env
	multiplyTransform(joints.waist, CFrame.Angles(leanPitch, leanYaw, leanRoll))

	-- Swept-back Jett wind-slicer arms + tucked trailing legs
	multiplyTransform(
		joints.rightShoulder,
		CFrame.Angles(math.rad(-54) * env, 0, math.rad(28) * env)
	)
	multiplyTransform(
		joints.leftShoulder,
		CFrame.Angles(math.rad(-54) * env, 0, math.rad(-28) * env)
	)
	multiplyTransform(joints.rightElbow, CFrame.Angles(math.rad(26) * env, 0, 0))
	multiplyTransform(joints.leftElbow, CFrame.Angles(math.rad(26) * env, 0, 0))
	multiplyTransform(
		joints.rightHip,
		CFrame.Angles(math.rad(28 * localFwd) * env, 0, math.rad(10 * localRight) * env)
	)
	multiplyTransform(
		joints.leftHip,
		CFrame.Angles(math.rad(-32 * localFwd) * env, 0, math.rad(-10 * localRight) * env)
	)
	multiplyTransform(joints.rightKnee, CFrame.Angles(math.rad(-38) * env, 0, 0))
	multiplyTransform(joints.leftKnee, CFrame.Angles(math.rad(-18) * env, 0, 0))
end

local function applyCharacterAnimations(now: number)
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		if not char then
			continue
		end
		local dashSt = activeDashes[plr]
		local throwSt = activeThrows[plr]
		local isLocalTraining = (plr == localPlayer) and trainingStanceActive
		if not dashSt and not throwSt and not isLocalTraining then
			continue
		end
		local joints = resolveCharacterJoints(char)

		if dashSt then
			local alpha = (now - dashSt.startTime) / dashSt.duration
			if alpha >= 1 then
				activeDashes[plr] = nil
			else
				applyJettDashPose(char, joints, dashSt, alpha)
			end
		end

		if throwSt then
			local alpha = (now - throwSt.startTime) / throwSt.duration
			if alpha >= 1 then
				activeThrows[plr] = nil
			else
				local armPitch, torsoYaw, elbowBend, leftPitch = computeThrowCurve(alpha)
				multiplyTransform(joints.rightShoulder, CFrame.Angles(armPitch, 0, math.rad(14)))
				multiplyTransform(joints.rightElbow, CFrame.Angles(elbowBend, 0, 0))
				multiplyTransform(joints.leftShoulder, CFrame.Angles(leftPitch, 0, math.rad(-10)))
				multiplyTransform(joints.waist, CFrame.Angles(math.rad(-6), torsoYaw, 0))
			end
		elseif isLocalTraining and not dashSt then
			local bob = math.sin(now * 4.2)
			multiplyTransform(
				joints.rightShoulder,
				CFrame.Angles(math.rad(26 + bob * 7), 0, math.rad(12))
			)
			multiplyTransform(
				joints.leftShoulder,
				CFrame.Angles(math.rad(14 - bob * 5), 0, math.rad(-10))
			)
			multiplyTransform(joints.waist, CFrame.Angles(math.rad(-4), math.rad(bob * 4), 0))
		end
	end
end

local function registerMotor(inst: Instance)
	if not inst:IsA("Motor6D") then
		return
	end
	local role = inst:GetAttribute("AnimRole")
	if type(role) ~= "string" then
		return
	end
	local model = inst:FindFirstAncestorOfClass("Model")
	rigMotors[inst] = {
		motor = inst,
		role = role,
		speed = tonumber(inst:GetAttribute("AnimSpeed")) or 4.0,
		amp = tonumber(inst:GetAttribute("AnimAmp")) or 0.25,
		phase = (math.random() * math.pi * 2),
		model = model,
	}
end

local function stepRigMotors(now: number, camPos: Vector3)
	for motor, entry in pairs(rigMotors) do
		if not motor.Parent or not motor.Part0 or not motor.Part1 then
			rigMotors[motor] = nil
			continue
		end
		if (motor.Part0.Position - camPos).Magnitude > CULL_DISTANCE then
			continue
		end
		local model = entry.model
		local isMoving = if model then (model:GetAttribute("IsMoving") == true) else false
		local spd = entry.speed * (if isMoving then 1.45 else 1.0)
		local amp = entry.amp * (if isMoving then 1.35 else 1.0)
		local s = math.sin(now * spd + entry.phase)
		local role = entry.role

		if role == "WingL" then
			motor.Transform = CFrame.Angles(0, 0, s * amp)
		elseif role == "WingR" then
			motor.Transform = CFrame.Angles(0, 0, -s * amp)
		elseif role == "Tail" then
			motor.Transform = CFrame.Angles(math.sin(now * spd * 0.5) * amp * 0.25, s * amp, 0)
		elseif role == "EarL" then
			motor.Transform = CFrame.Angles(0, 0, math.max(0, s) * amp)
		elseif role == "EarR" then
			motor.Transform = CFrame.Angles(0, 0, -math.max(0, s) * amp)
		elseif role == "Head" then
			motor.Transform =
				CFrame.Angles(s * amp * 0.65, math.cos(now * spd * 0.7 + entry.phase) * amp, 0)
		elseif role == "ArmL" then
			motor.Transform = CFrame.Angles(s * amp, 0, 0)
		elseif role == "ArmR" then
			motor.Transform = CFrame.Angles(-s * amp, 0, 0)
		elseif role == "LegFL" or role == "LegBR" then
			local mult = if isMoving then 1.0 else 0.18
			motor.Transform = CFrame.Angles(s * amp * mult, 0, 0)
		elseif role == "LegFR" or role == "LegBL" then
			local mult = if isMoving then 1.0 else 0.18
			motor.Transform = CFrame.Angles(-s * amp * mult, 0, 0)
		elseif role == "OrbitShard" then
			motor.Transform = CFrame.Angles(0, now * entry.speed + entry.phase, 0)
		elseif role == "Core" then
			motor.Transform = CFrame.new(0, s * amp, 0) * CFrame.Angles(0, now * 1.4, 0)
		end
	end
end

local function registerSpinRing(inst: Instance)
	if not inst:IsA("BasePart") or inst.Name == "AfkPadGlowRing" then
		return
	end
	spinBases[inst] = {
		cf = inst.CFrame,
		speed = tonumber(inst:GetAttribute("SpinSpeed")) or 1.4,
		axis = tostring(inst:GetAttribute("SpinAxis") or "Y"),
	}
end

local function registerFloatBob(inst: Instance)
	if not inst:IsA("BasePart") then
		return
	end
	floatBases[inst] = {
		cf = inst.CFrame,
		phase = math.random() * math.pi * 2,
	}
end

local function stepWorldProps(now: number, camPos: Vector3)
	for part, data in pairs(spinBases) do
		if not part.Parent then
			spinBases[part] = nil
			continue
		end
		if (data.cf.Position - camPos).Magnitude > 260 then
			continue
		end
		local angle = now * data.speed
		local bobY = if floatBases[part]
			then math.sin(now * 2.2 + floatBases[part].phase) * 1.1
			else 0
		local rot = if data.axis == "X"
			then CFrame.Angles(angle, 0, 0)
			else CFrame.Angles(0, angle, 0)
		part.CFrame = (data.cf + Vector3.new(0, bobY, 0)) * rot
	end
	for part, data in pairs(floatBases) do
		if not part.Parent then
			floatBases[part] = nil
			continue
		end
		if spinBases[part] or (data.cf.Position - camPos).Magnitude > 260 then
			continue
		end
		local bobY = math.sin(now * 2.4 + data.phase) * 0.9
		part.CFrame = data.cf + Vector3.new(0, bobY, 0)
	end
end

local function spawnDashAfterimage(cf: CFrame, dashDir: Vector3)
	local ghost = Instance.new("Part")
	ghost.Name = "JettDashAfterimage"
	ghost.Anchored = true
	ghost.CanCollide = false
	ghost.CanTouch = false
	ghost.CanQuery = false
	ghost.CastShadow = false
	ghost.Material = Enum.Material.Neon
	ghost.Color = Color3.fromRGB(165, 243, 255)
	ghost.Transparency = 0.42
	ghost.Size = Vector3.new(2.2, 4.4, 1.4)
	ghost.CFrame = cf * CFrame.Angles(math.rad(-18), 0, 0)
	ghost.Parent = workspace

	local streak = Instance.new("Part")
	streak.Name = "WindStreak"
	streak.Anchored = true
	streak.CanCollide = false
	streak.CanTouch = false
	streak.CanQuery = false
	streak.CastShadow = false
	streak.Material = Enum.Material.Neon
	streak.Color = Color3.fromRGB(240, 252, 255)
	streak.Transparency = 0.28
	streak.Size = Vector3.new(0.45, 0.45, 5.2)
	streak.CFrame = CFrame.lookAt(cf.Position, cf.Position + dashDir)
	streak.Parent = workspace

	TweenService
		:Create(ghost, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
			Size = Vector3.new(1.0, 4.8, 2.8),
		})
		:Play()
	TweenService
		:Create(streak, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
			Size = Vector3.new(0.1, 0.1, 8.5),
		})
		:Play()
	task.delay(0.28, function()
		if ghost.Parent then
			ghost:Destroy()
		end
		if streak.Parent then
			streak:Destroy()
		end
	end)
end

local function spawnJettWindVFX(char: Model, hrp: BasePart, dashDir: Vector3, duration: number)
	local startPos = hrp.Position
	local flatDir = Vector3.new(dashDir.X, 0, dashDir.Z)
	local dir = if flatDir.Magnitude > 0.05 then flatDir.Unit else hrp.CFrame.LookVector

	-- 1. Sonic Tailwind launch shockwave ring perpendicular to dash vector
	local ring = Instance.new("Part")
	ring.Name = "JettTailwindRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(190, 248, 255)
	ring.Transparency = 0.15
	ring.Size = Vector3.new(0.26, 2.2, 2.2)
	ring.CFrame = CFrame.lookAt(startPos, startPos + dir) * CFrame.Angles(0, math.rad(90), 0)
	ring.Parent = workspace

	TweenService
		:Create(ring, TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.08, 11.5, 11.5),
			Transparency = 1,
		})
		:Play()

	-- 2. Explosive backward wind-mist & slipstream sparks
	local burst = Instance.new("ParticleEmitter")
	burst.Rate = 0
	burst.Speed = NumberRange.new(16, 36)
	burst.Lifetime = NumberRange.new(0.16, 0.34)
	burst.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.85),
		NumberSequenceKeypoint.new(1, 0),
	})
	burst.Color = ColorSequence.new(Color3.fromRGB(240, 252, 255), Color3.fromRGB(56, 217, 255))
	burst.LightEmission = 1
	burst.LightInfluence = 0
	burst.SpreadAngle = Vector2.new(38, 38)
	burst.EmissionDirection = Enum.NormalId.Left
	burst.Parent = ring
	burst:Emit(24)
	task.delay(0.42, function()
		if ring.Parent then
			ring:Destroy()
		end
	end)

	-- 3. Sleek multi-ribbon Tailwind trails attached across torso/shoulders
	local cleanupInsts: { Instance } = {}
	local offsets = {
		{ Vector3.new(0, 1.3, 0), Vector3.new(0, 0.4, 0), Color3.fromRGB(240, 252, 255) },
		{ Vector3.new(-1.1, 0.6, 0), Vector3.new(-1.1, -0.4, 0), Color3.fromRGB(125, 240, 255) },
		{ Vector3.new(1.1, 0.6, 0), Vector3.new(1.1, -0.4, 0), Color3.fromRGB(56, 189, 248) },
	}
	for _, o in ipairs(offsets) do
		local a0 = Instance.new("Attachment")
		a0.Position = o[1]
		a0.Parent = hrp
		local a1 = Instance.new("Attachment")
		a1.Position = o[2]
		a1.Parent = hrp
		local tr = Instance.new("Trail")
		tr.Attachment0 = a0
		tr.Attachment1 = a1
		tr.Lifetime = 0.26
		tr.MinLength = 0.05
		tr.LightEmission = 0.9
		tr.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), o[3])
		tr.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.08),
			NumberSequenceKeypoint.new(1, 1),
		})
		tr.WidthScale = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0),
		})
		tr.Parent = hrp
		table.insert(cleanupInsts, a0)
		table.insert(cleanupInsts, a1)
		table.insert(cleanupInsts, tr)
	end
	task.delay(duration + 0.3, function()
		for _, inst in ipairs(cleanupInsts) do
			if inst.Parent then
				inst:Destroy()
			end
		end
	end)

	-- 4. Three staggered cyan wind-ghost afterimages along the dash path
	for _, delaySec in ipairs({ 0.02, 0.08, 0.15 }) do
		task.delay(delaySec, function()
			if char.Parent and hrp.Parent then
				spawnDashAfterimage(hrp.CFrame, dir)
			end
		end)
	end
end

function AnimationController.playJettDash(player: Player?, dashDir: Vector3, duration: number?)
	if not player then
		return
	end
	local dur = duration or 0.28
	activeDashes[player] = {
		startTime = os.clock(),
		duration = dur + 0.08,
		dir = dashDir,
	}
	local char = player.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
	if char and hrp and hrp:IsA("BasePart") then
		spawnJettWindVFX(char, hrp, dashDir, dur)
	end
	-- Snappy Valorant Tailwind camera FOV punch for the local player
	if player == localPlayer then
		local cam = workspace.CurrentCamera
		if cam then
			local baseFov = 70
			TweenService:Create(
				cam,
				TweenInfo.new(0.07, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
				{ FieldOfView = 84 }
			):Play()
			task.delay(0.11, function()
				if cam.Parent then
					TweenService:Create(
						cam,
						TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{ FieldOfView = baseFov }
					):Play()
				end
			end)
		end
	end
end

function AnimationController.playThrowAnim(player: Player?)
	if not player then
		return
	end
	activeThrows[player] = {
		startTime = os.clock(),
		duration = 0.34,
	}
end

function AnimationController.setTrainingStance(active: boolean)
	trainingStanceActive = active
end

function AnimationController.playImpactEffect(
	pos: Vector3,
	hitKind: string,
	isCrit: boolean,
	color: Color3,
	hitInstance: Instance?
)
	-- 1. Crisp 0.22s expanding shockwave ring + one-shot sparks (client-only, zero server cost)
	local ring = Instance.new("Part")
	ring.Name = "BallImpactRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.2
	ring.Size = Vector3.new(0.25, 1.4, 1.4)
	ring.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace

	local endDiam = if isCrit or hitKind == "GoldTarget" then 7.2 else 4.6
	TweenService
		:Create(ring, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.12, endDiam, endDiam),
			Transparency = 1,
		})
		:Play()

	local pe = Instance.new("ParticleEmitter")
	pe.Rate = 0
	pe.Speed = NumberRange.new(10, if isCrit then 24 else 17)
	pe.Lifetime = NumberRange.new(0.18, 0.36)
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, if isCrit then 0.85 else 0.58),
		NumberSequenceKeypoint.new(1, 0),
	})
	pe.Color = ColorSequence.new(color, Color3.fromRGB(255, 255, 255))
	pe.LightEmission = 1
	pe.LightInfluence = 0
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Parent = ring
	pe:Emit(if isCrit or hitKind == "GoldTarget" then 20 else 12)
	task.delay(0.45, function()
		if ring.Parent then
			ring:Destroy()
		end
	end)

	-- 2. Brief Highlight hit-flash & spring recoil on struck Target / Mob / Boss
	if not hitInstance or not hitInstance.Parent or recoilBusy[hitInstance] then
		return
	end
	local targetModel = if hitInstance:IsA("Model")
		then hitInstance
		else hitInstance:FindFirstAncestorOfClass("Model")
	local flashTarget: Instance = if targetModel
			and targetModel:GetAttribute("EntityKind") ~= nil
		then targetModel
		else hitInstance

	recoilBusy[hitInstance] = true
	local hl = Instance.new("Highlight")
	hl.FillColor = color
	hl.OutlineColor = Color3.fromRGB(255, 255, 255)
	hl.FillTransparency = 0.35
	hl.OutlineTransparency = 0.1
	hl.Adornee = flashTarget
	hl.Parent = flashTarget

	-- Springy target knockback recoil on static training target skins
	if hitInstance:IsA("BasePart") and hitInstance:GetAttribute("TargetKind") == "Static" then
		local skin = hitInstance:FindFirstChild("TargetSkin")
		if skin and skin:IsA("Model") and skin.PrimaryPart then
			local baseCF = skin:GetPivot()
			skin:PivotTo(baseCF * CFrame.Angles(math.rad(-14), 0, 0))
			task.delay(0.08, function()
				if skin.Parent then
					skin:PivotTo(baseCF * CFrame.Angles(math.rad(6), 0, 0))
				end
			end)
			task.delay(0.16, function()
				if skin.Parent then
					skin:PivotTo(baseCF)
				end
			end)
		end
	end

	task.delay(0.16, function()
		if hl.Parent then
			hl:Destroy()
		end
		recoilBusy[hitInstance] = nil
	end)
end

function AnimationController.start()
	for _, desc in ipairs(workspace:GetDescendants()) do
		registerMotor(desc)
	end
	workspace.DescendantAdded:Connect(registerMotor)
	workspace.DescendantRemoving:Connect(function(inst: Instance)
		if inst:IsA("Motor6D") then
			rigMotors[inst] = nil
		end
	end)

	for _, inst in ipairs(CollectionService:GetTagged("SpinRing")) do
		registerSpinRing(inst)
	end
	CollectionService:GetInstanceAddedSignal("SpinRing"):Connect(registerSpinRing)

	for _, inst in ipairs(CollectionService:GetTagged("FloatBob")) do
		registerFloatBob(inst)
	end
	CollectionService:GetInstanceAddedSignal("FloatBob"):Connect(registerFloatBob)

	RunService.PreSimulation:Connect(function()
		applyCharacterAnimations(os.clock())
	end)

	RunService.RenderStepped:Connect(function()
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local now = os.clock()
		local camPos = cam.CFrame.Position
		stepRigMotors(now, camPos)
		stepWorldProps(now, camPos)
	end)
end

return AnimationController
