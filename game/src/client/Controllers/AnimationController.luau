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
}

type ThrowState = {
	startTime: number,
	duration: number,
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
	return {
		rightShoulder = rightShoulder,
		leftShoulder = leftShoulder,
		waist = waist,
		rightElbow = rightElbow,
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

local function applyCharacterAnimations(now: number)
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		if not char then
			continue
		end
		local throwSt = activeThrows[plr]
		local isLocalTraining = (plr == localPlayer) and trainingStanceActive
		if not throwSt and not isLocalTraining then
			continue
		end
		local joints = resolveCharacterJoints(char)

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
		elseif isLocalTraining then
			-- Rhythmic athletic ready bounce between AFK auto-throws
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
