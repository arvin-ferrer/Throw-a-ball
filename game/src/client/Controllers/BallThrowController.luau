--!strict
--[[
	BallThrowController.luau
	Client movement, 100% FREE AFK Auto-Training Range, Souls-Like Lock-On Aim Integration,
	and real 60 FPS ballistic ball physics with hand launch & post-impact bounce rebound!
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyConfigs = require(Shared.Configs.EconomyConfigs)
local MonetizationConfigs = require(Shared.Configs.MonetizationConfigs)
local CombatLogic = require(Shared.Utils.CombatLogic)
local EconomyLogic = require(Shared.Utils.EconomyLogic)
local LockOnLogic = require(Shared.Utils.LockOnLogic)
local MathUtil = require(Shared.Utils.MathUtil)
local ProceduralModels = require(Shared.Utils.ProceduralModels)
local AudioCatalog = require(Shared.Utils.AudioCatalog)
local Remotes = require(Shared.Net.Remotes)

local HudGui = require(script.Parent.Parent.UI.HudGui)
local AnimationController = require(script.Parent.AnimationController)
local LockOnController = require(script.Parent.LockOnController)

local BallThrowController = {}

local WALK_SPEED = 18
local SPRINT_SPEED = 24
local DASH_PEAK_SPEED = 88
local DASH_END_SPEED = 30
local DASH_DURATION = 0.26
local DASH_COOLDOWN = 2.5

type VisualBall = {
	id: number,
	ball: Model,
	mode: "Homing" | "Ballistic",
	pos: Vector3,
	vel: Vector3,
	gravity: number,
	startPos: Vector3,
	serverOrigin: Vector3,
	launchTime: number,
	homingPart: BasePart?,
	homingEndPos: Vector3,
	homingDur: number,
	arcBoost: number,
	expiresAt: number,
	bounced: boolean,
	rolling: boolean,
	spinAngle: number,
}

local localPlayer = Players.LocalPlayer
local isSprinting = false
local isOnTrainingPad = false
local padLocked = false
local lastDashAt = 0
local lastThrowAt = 0
local isHoldingFire = false
local afkTargetCycle = 0
local activeVisualBalls: { [number]: VisualBall } = {}
local crosshairRayParams = RaycastParams.new()
crosshairRayParams.FilterType = Enum.RaycastFilterType.Exclude
crosshairRayParams.IgnoreWater = true

local function getRootAndHum(): (BasePart?, Humanoid?)
	local char = localPlayer.Character
	if not char then
		return nil, nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	return if hrp and hrp:IsA("BasePart") then hrp else nil, hum
end

local function getThrowHandOrigin(player: Player?, fallbackPos: Vector3): Vector3
	local char = if player then player.Character else nil
	if not char then
		return fallbackPos
	end
	local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
	if hand and hand:IsA("BasePart") then
		return hand.Position + Vector3.new(0, 0.35, 0)
	end
	return fallbackPos
end

local function findMyFiringPad(): BasePart?
	local myPlotId = tonumber(localPlayer:GetAttribute("PlotId"))
	if not myPlotId then
		return nil
	end
	for _, pad in ipairs(CollectionService:GetTagged("TrainingFiringPad")) do
		if pad:IsA("BasePart") and tonumber(pad:GetAttribute("PlotId")) == myPlotId then
			return pad
		end
	end
	return nil
end

local function pickAfkTrainingTarget(pad: BasePart, hasTurboPass: boolean): BasePart?
	local tr = pad.Parent
	if not tr then
		return nil
	end
	local gold = tr:FindFirstChild("Target_MovingGold")
	if gold and gold:IsA("BasePart") then
		if hasTurboPass then
			return gold
		end
		local localOffset = pad.CFrame:PointToObjectSpace(gold.Position)
		if math.abs(localOffset.X) <= 7.5 then
			return gold
		end
	end

	local statics: { BasePart } = {}
	for _, child in ipairs(tr:GetChildren()) do
		if child:IsA("BasePart") and child:GetAttribute("TargetKind") == "Static" then
			table.insert(statics, child)
		end
	end
	if #statics == 0 then
		return if gold and gold:IsA("BasePart") then gold else nil
	end
	table.sort(statics, function(a, b)
		return a.Name < b.Name
	end)
	afkTargetCycle = (afkTargetCycle % #statics) + 1
	return statics[afkTargetCycle]
end

local function isSightlineTargetPart(part: BasePart): boolean
	local tk = part:GetAttribute("TargetKind")
	if tk == "Static" or tk == "MovingGold" then
		return true
	end
	local mdl = part:FindFirstAncestorOfClass("Model")
	if not mdl then
		return false
	end
	local entityKind = mdl:GetAttribute("EntityKind")
	if entityKind == "PvEMob" or entityKind == "BiomeBoss" then
		local hum = mdl:FindFirstChildOfClass("Humanoid")
		return not hum or hum.Health > 0
	end
	local hitPlr = Players:GetPlayerFromCharacter(mdl)
	if
		hitPlr
		and hitPlr ~= localPlayer
		and localPlayer:GetAttribute("Zone") == "LockedBossPvP"
		and hitPlr:GetAttribute("Zone") == "LockedBossPvP"
	then
		local hum = mdl:FindFirstChildOfClass("Humanoid")
		return hum ~= nil and hum.Health > 0
	end
	return false
end

local function isCrosshairIgnorablePart(part: BasePart): boolean
	if isSightlineTargetPart(part) then
		return false
	end
	return not part.CanCollide and part.Transparency >= 0.85
end

local function castCrosshairSightline(cam: Camera, origin: Vector3): Vector3
	local vp = cam.ViewportSize
	local ray = cam:ViewportPointToRay(vp.X * 0.5, vp.Y * 0.5)
	local excluded: { Instance } = {}
	if localPlayer.Character then
		table.insert(excluded, localPlayer.Character)
	end
	local followers = workspace:FindFirstChild("LocalActiveFollowers")
	if followers then
		table.insert(excluded, followers)
	end
	local hitDist: number? = nil
	for _ = 1, 5 do
		crosshairRayParams.FilterDescendantsInstances = excluded
		local res = workspace:Raycast(ray.Origin, ray.Direction * 240, crosshairRayParams)
		if not res or not res.Instance or not res.Instance:IsA("BasePart") then
			break
		end
		local part = res.Instance
		if isCrosshairIgnorablePart(part) then
			table.insert(excluded, part)
		else
			hitDist = res.Distance
			break
		end
	end
	local dx, dy, dz = CombatLogic.computeCrosshairAimDirection(
		origin.X,
		origin.Y,
		origin.Z,
		ray.Origin.X,
		ray.Origin.Y,
		ray.Origin.Z,
		ray.Direction.X,
		ray.Direction.Y,
		ray.Direction.Z,
		hitDist
	)
	return Vector3.new(dx, dy, dz)
end

local function executeThrow(overrideTarget: BasePart?, isAfkShot: boolean)
	local hrp = getRootAndHum()
	local cam = workspace.CurrentCamera
	if not hrp or not cam then
		return
	end
	local now = os.clock()
	local speedStat = tonumber(localPlayer:GetAttribute("ThrowSpeed")) or 1.0
	local turboBonus = if padLocked
			and localPlayer:GetAttribute("Pass_AutoFireRange") == true
		then 0.25
		else 0
	local cd = MathUtil.computeThrowCooldown(speedStat, turboBonus)
	if now - lastThrowAt < cd * 0.94 then
		return
	end
	lastThrowAt = now

	local origin = hrp.Position + Vector3.new(0, 1.4, 0)
	local useHoming = isAfkShot
	local lockedPart: BasePart? = if isAfkShot then overrideTarget else nil
	local aimDir: Vector3

	if isAfkShot and lockedPart and lockedPart.Parent then
		local delta = lockedPart.Position - origin
		aimDir = if delta.Magnitude > 0.1 then delta.Unit else hrp.CFrame.LookVector
	else
		local _, _, lockWorldPos = LockOnController.getLockedTarget()
		if lockWorldPos then
			local ballTierId = tostring(localPlayer:GetAttribute("BallTier") or "RubberBall")
			local ballTier = EconomyConfigs.getBallTierById(ballTierId)
				or EconomyConfigs.BALL_TIERS[1]
			local projSpeed = MathUtil.computeProjectileSpeed(ballTier.projectileSpeed, speedStat)
			local ax, ay, az = LockOnLogic.solveLockedBallisticAimDirection(
				origin.X,
				origin.Y,
				origin.Z,
				lockWorldPos.X,
				lockWorldPos.Y,
				lockWorldPos.Z,
				projSpeed
			)
			aimDir = Vector3.new(ax, ay, az)
			local lookFlat = Vector3.new(lockWorldPos.X, hrp.Position.Y, lockWorldPos.Z)
			if (lookFlat - hrp.Position).Magnitude > 0.5 then
				hrp.CFrame = hrp.CFrame:Lerp(CFrame.lookAt(hrp.Position, lookFlat), 0.72)
			end
		else
			aimDir = castCrosshairSightline(cam, origin)
		end
	end

	AnimationController.playThrowAnim(localPlayer)
	Remotes.waitClient().ThrowBall:FireServer(aimDir, useHoming, lockedPart)
	AudioCatalog.play("Throw", 1.0 + math.random() * 0.14, if isAfkShot then 0.12 else 0.28)
end

function BallThrowController.fireThrow()
	executeThrow(nil, false)
end

function BallThrowController.setHoldingFire(holding: boolean)
	isHoldingFire = holding
	if holding then
		BallThrowController.fireThrow()
	end
end

function BallThrowController.triggerDash()
	local now = os.clock()
	if now - lastDashAt < DASH_COOLDOWN or padLocked then
		return
	end
	local hrp, hum = getRootAndHum()
	if not hrp or not hum or hum.Health <= 0 then
		return
	end
	lastDashAt = now

	-- 8-way directional Valorant Jett Tailwind burst (follows WASD / thumbstick or facing)
	local rawMove = hum.MoveDirection
	local flatDir = Vector3.new(rawMove.X, 0, rawMove.Z)
	local moveDir = if flatDir.Magnitude > 0.1
		then flatDir.Unit
		else Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z).Unit
	if moveDir.Magnitude < 0.05 then
		moveDir = Vector3.zAxis
	end

	Remotes.waitClient().DashRequest:FireServer(moveDir)
	AnimationController.playJettDash(localPlayer, moveDir, DASH_DURATION)
	AudioCatalog.playJettDash()

	local att = Instance.new("Attachment")
	att.Parent = hrp
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.MaxForce = hrp.AssemblyMass * workspace.Gravity * 32
	lv.VectorVelocity = Vector3.new(moveDir.X * DASH_PEAK_SPEED, 1.2, moveDir.Z * DASH_PEAK_SPEED)
	lv.Parent = hrp

	-- Snappy explosive start + crisp tapered wind-stop (no floaty overshoot)
	local startAt = os.clock()
	local conn: RBXScriptConnection? = nil
	conn = RunService.Heartbeat:Connect(function()
		local alpha = (os.clock() - startAt) / DASH_DURATION
		if alpha >= 1 or not lv.Parent or not hrp.Parent then
			if conn then
				conn:Disconnect()
				conn = nil
			end
			if lv.Parent then
				lv:Destroy()
			end
			if att.Parent then
				att:Destroy()
			end
			return
		end
		local ease = 1 - (alpha * alpha)
		local spd = DASH_END_SPEED + (DASH_PEAK_SPEED - DASH_END_SPEED) * ease
		lv.VectorVelocity = Vector3.new(moveDir.X * spd, 0.8, moveDir.Z * spd)
	end)
end

local function spawnDamagePopup(pos: Vector3, text: string, color: Color3)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(pos + Vector3.new(0, 2, 0))
	anchor.Parent = workspace

	local bb = Instance.new("BillboardGui")
	bb.Adornee = anchor
	bb.Size = UDim2.fromOffset(128, 40)
	bb.AlwaysOnTop = true
	bb.Parent = anchor

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextScaled = true
	lbl.TextColor3 = color
	lbl.TextStrokeTransparency = 0.2
	lbl.Text = text
	lbl.Parent = bb

	TweenService
		:Create(anchor, TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = anchor.CFrame + Vector3.new(0, 4.2, 0),
		})
		:Play()
	task.delay(0.7, function()
		anchor:Destroy()
	end)
end

local function triggerImpactFeedback(
	impactPos: Vector3,
	hitKind: string,
	isCrit: boolean,
	damage: number,
	hitInst: Instance?
)
	if hitKind == "GoldTarget" then
		local col = Color3.fromRGB(250, 204, 21)
		AudioCatalog.play("GoldCombo", 1.25, 0.45)
		spawnDamagePopup(impactPos, "2x GOLD +SPD!", col)
		AnimationController.playImpactEffect(impactPos, hitKind, true, col, hitInst)
	elseif hitKind == "Target" then
		local col = Color3.fromRGB(74, 222, 128)
		AudioCatalog.play("TargetHit", 1.05, 0.28)
		spawnDamagePopup(impactPos, "+DMG!", col)
		AnimationController.playImpactEffect(impactPos, hitKind, false, col, hitInst)
	elseif hitKind == "Mob" or hitKind == "Boss" or hitKind == "PvP" then
		local col = if isCrit then Color3.fromRGB(250, 204, 21) else Color3.fromRGB(255, 110, 90)
		AudioCatalog.play("BossHit", if isCrit then 1.35 else 1.0, 0.45)
		local dmgTxt = MathUtil.formatNumber(damage)
		spawnDamagePopup(impactPos, if isCrit then `CRIT {dmgTxt}!` else `-{dmgTxt}`, col)
		AnimationController.playImpactEffect(impactPos, hitKind, isCrit, col, hitInst)
	elseif hitKind == "Surface" then
		AudioCatalog.play("Throw", 1.42, 0.12)
		AnimationController.playImpactEffect(
			impactPos,
			"Surface",
			false,
			Color3.fromRGB(200, 220, 255),
			nil
		)
	end
end

local function destroyVisualBall(ballId: number)
	local entry = activeVisualBalls[ballId]
	if not entry then
		return
	end
	activeVisualBalls[ballId] = nil
	if entry.ball.Parent then
		entry.ball:Destroy()
	end
end

local function resolveBallSkinColor(ballSkin: any): Color3?
	if type(ballSkin) ~= "string" then
		return nil
	end
	local spec = MonetizationConfigs.COSMETICS[ballSkin]
	return if spec then Color3.fromRGB(spec.color[1], spec.color[2], spec.color[3]) else nil
end

local function registerVisualBall(
	ballId: number,
	ball: Model,
	startPos: Vector3,
	serverOrigin: Vector3,
	staticEnd: Vector3,
	launchVel: Vector3,
	dur: number,
	homingPart: BasePart?,
	gravityOverride: number?
)
	local now = os.clock()
	activeVisualBalls[ballId] = {
		id = ballId,
		ball = ball,
		mode = if homingPart then "Homing" else "Ballistic",
		pos = serverOrigin,
		vel = launchVel,
		gravity = gravityOverride or CombatLogic.BALL_GRAVITY,
		startPos = startPos,
		serverOrigin = serverOrigin,
		launchTime = now,
		homingPart = homingPart,
		homingEndPos = staticEnd,
		homingDur = dur,
		arcBoost = math.clamp((staticEnd - startPos).Magnitude * 0.08, 0.8, 5.5),
		expiresAt = now + dur + CombatLogic.POST_BOUNCE_LIFETIME + 0.5,
		bounced = false,
		rolling = false,
		spinAngle = 0,
	}
end

local function handleLaunchPacket(data: any)
	local ballId = tonumber(data.ballId)
	if not ballId or typeof(data.origin) ~= "Vector3" or typeof(data.endPos) ~= "Vector3" then
		return
	end
	destroyVisualBall(ballId)

	local shooterId = tonumber(data.shooterId)
	local shooterPlr = if shooterId then Players:GetPlayerByUserId(shooterId) else nil
	if shooterPlr and shooterPlr ~= localPlayer then
		AnimationController.playThrowAnim(shooterPlr)
	end

	local ball = ProceduralModels.createBallVisual(
		tostring(data.ballTierId or "RubberBall"),
		resolveBallSkinColor(data.ballSkin)
	)
	local startPos = getThrowHandOrigin(shooterPlr, data.origin)
	local serverOrigin: Vector3 = data.origin
	local staticEnd: Vector3 = data.endPos
	local hitInst = if typeof(data.hitTarget) == "Instance" then data.hitTarget else nil
	local homingPart = if data.isHoming == true
			and hitInst
			and hitInst:IsA("BasePart")
		then hitInst
		else nil
	local dur = math.clamp(tonumber(data.travelSec) or 0.25, 0.08, 2.2)
	local launchVel: Vector3 = if typeof(data.launchVel) == "Vector3"
		then data.launchVel
		else (staticEnd - serverOrigin).Unit * (tonumber(data.speed) or 115)

	ball:PivotTo(CFrame.lookAt(startPos, staticEnd))
	ball.Parent = workspace
	registerVisualBall(ballId, ball, startPos, serverOrigin, staticEnd, launchVel, dur, homingPart)
end

local function handleBouncePacket(data: any)
	local ballId = tonumber(data.ballId)
	if not ballId or typeof(data.pos) ~= "Vector3" or typeof(data.vel) ~= "Vector3" then
		return
	end
	local entry = activeVisualBalls[ballId]
	local hitKind = tostring(data.hitKind or "Surface")
	local hitInst = if typeof(data.hitTarget) == "Instance" then data.hitTarget else nil
	if entry then
		entry.mode = "Ballistic"
		entry.bounced = true
		entry.rolling = hitKind == "Roll"
		entry.pos = data.pos
		entry.vel = data.vel
		local rem = math.clamp(
			tonumber(data.remainingLife) or 0.1,
			0.05,
			CombatLogic.POST_BOUNCE_LIFETIME + 0.2
		)
		entry.expiresAt = os.clock() + rem
	end
	if hitKind ~= "Roll" then
		triggerImpactFeedback(
			data.pos,
			hitKind,
			data.isCrit == true,
			tonumber(data.damage) or 0,
			hitInst
		)
	end
end

local function handleImpactDespawnPacket(data: any)
	local ballId = tonumber(data.ballId)
	if ballId then
		destroyVisualBall(ballId)
	end
	if typeof(data.pos) == "Vector3" then
		local hitInst = if typeof(data.hitTarget) == "Instance" then data.hitTarget else nil
		triggerImpactFeedback(
			data.pos,
			tostring(data.hitKind or "Surface"),
			data.isCrit == true,
			tonumber(data.damage) or 0,
			hitInst
		)
	end
end

local function playEliminationVfx(data: any)
	if typeof(data.pos) ~= "Vector3" then
		return
	end
	local isVoid = data.eliminationVfx == "VoidShatter"
	local col = if isVoid then Color3.fromRGB(168, 85, 247) else Color3.fromRGB(251, 146, 60)
	local burst = Instance.new("Part")
	burst.Name = "EliminationBurst"
	burst.Shape = Enum.PartType.Ball
	burst.Material = Enum.Material.Neon
	burst.Color = col
	burst.Transparency = 0.25
	burst.Size = Vector3.new(2.5, 2.5, 2.5)
	burst.Anchored = true
	burst.CanCollide = false
	burst.CanQuery = false
	burst.CFrame = CFrame.new(data.pos :: Vector3)
	burst.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(14, 30)
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Size = NumberSequence.new(1.1, 0)
	emitter.Color = ColorSequence.new(col, Color3.fromRGB(255, 255, 255))
	emitter.LightEmission = 1
	emitter.Parent = burst
	emitter:Emit(math.min(32, EconomyLogic.COSMETIC_MAX_BURST_PARTICLES))

	TweenService
		:Create(burst, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
			Size = Vector3.new(16, 16, 16),
		})
		:Play()
	task.delay(0.9, function()
		burst:Destroy()
	end)
end

local function handleMobLaunchPacket(data: any)
	local ballId = tonumber(data.ballId)
	if not ballId or typeof(data.origin) ~= "Vector3" or typeof(data.launchVel) ~= "Vector3" then
		return
	end
	destroyVisualBall(ballId)
	local colArr = data.color or { 198, 72, 255 }
	local col = Color3.fromRGB(colArr[1] or 198, colArr[2] or 72, colArr[3] or 255)
	local ball = ProceduralModels.createMobProjectileVisual(
		tostring(data.projectileId or "Proj_ArcaneHexOrb"),
		col
	)
	local origin: Vector3 = data.origin
	local vel: Vector3 = data.launchVel
	local g = tonumber(data.gravity) or CombatLogic.BALL_GRAVITY
	local maxFlight = math.clamp(tonumber(data.maxFlight) or 4.0, 0.4, 5.0)
	ball:PivotTo(CFrame.lookAt(origin, origin + vel))
	ball.Parent = workspace
	registerVisualBall(ballId, ball, origin, origin, origin + vel, vel, maxFlight, nil, g)
end

local function handleMobImpactPacket(data: any)
	local ballId = tonumber(data.ballId)
	if ballId then
		destroyVisualBall(ballId)
	end
	if typeof(data.pos) ~= "Vector3" then
		return
	end
	local colArr = data.color or { 198, 72, 255 }
	local col = Color3.fromRGB(colArr[1] or 198, colArr[2] or 72, colArr[3] or 255)
	local aoe = math.clamp(tonumber(data.aoeRadius) or 4.0, 2.0, 10.0)
	AnimationController.playImpactEffect(data.pos, "Mob", data.hitPlayer == true, col, nil)
	if data.hitPlayer == true then
		AudioCatalog.play("BossHit", 0.92, 0.32)
	end
	local ring = Instance.new("Part")
	ring.Name = "MobProjSplashRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = col
	ring.Transparency = 0.35
	ring.Size = Vector3.new(0.22, 1.5, 1.5)
	ring.CFrame = CFrame.new(data.pos.X, math.max(0.25, data.pos.Y), data.pos.Z)
		* CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace
	TweenService
		:Create(ring, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.1, aoe * 2, aoe * 2),
			Transparency = 1,
		})
		:Play()
	task.delay(0.36, function()
		if ring.Parent then
			ring:Destroy()
		end
	end)
end

local function onProjectileBroadcast(data: any)
	if type(data) ~= "table" then
		return
	end
	local kind = data.msgKind
	if kind == "Launch" then
		handleLaunchPacket(data)
	elseif kind == "Bounce" then
		handleBouncePacket(data)
	elseif kind == "ImpactDespawn" then
		handleImpactDespawnPacket(data)
	elseif kind == "MobLaunch" then
		handleMobLaunchPacket(data)
	elseif kind == "MobImpact" then
		handleMobImpactPacket(data)
	elseif kind == "Elimination" then
		playEliminationVfx(data)
	elseif kind == "Despawn" then
		local ballId = tonumber(data.ballId)
		if ballId then
			destroyVisualBall(ballId)
		end
	end
end

local function stepVisualBalls(dt: number)
	local now = os.clock()
	local stepDt = math.min(dt, 0.05)
	for ballId, entry in pairs(activeVisualBalls) do
		if now >= entry.expiresAt or not entry.ball.Parent then
			destroyVisualBall(ballId)
			continue
		end
		local renderPos: Vector3
		local forwardDir = Vector3.zAxis
		if entry.mode == "Homing" then
			local alpha = math.clamp((now - entry.launchTime) / entry.homingDur, 0, 1)
			local dest = if entry.homingPart and entry.homingPart.Parent
				then entry.homingPart.Position
				else entry.homingEndPos
			local linear = entry.startPos:Lerp(dest, alpha)
			renderPos = linear + Vector3.new(0, 4 * alpha * (1 - alpha) * entry.arcBoost, 0)
			local delta = dest - entry.startPos
			if delta.Magnitude > 0.1 then
				forwardDir = delta.Unit
			end
		else
			if entry.rolling then
				entry.pos += Vector3.new(entry.vel.X, 0, entry.vel.Z) * stepDt
			else
				local g = entry.gravity
				entry.pos += entry.vel * stepDt + Vector3.new(0, -0.5 * g * stepDt * stepDt, 0)
				entry.vel += Vector3.new(0, -g * stepDt, 0)
			end
			if entry.vel.Magnitude > 0.5 then
				forwardDir = entry.vel.Unit
			end
			local handBlend = if entry.bounced
				then 0
				else math.clamp(1 - (now - entry.launchTime) * 8, 0, 1)
			renderPos = entry.pos + (entry.startPos - entry.serverOrigin) * handBlend
		end
		entry.spinAngle += stepDt * math.clamp(entry.vel.Magnitude * 0.22, 4, 22)
		entry.ball:PivotTo(
			CFrame.lookAt(renderPos, renderPos + forwardDir) * CFrame.Angles(-entry.spinAngle, 0, 0)
		)
		if entry.bounced and entry.ball.PrimaryPart then
			local rem = entry.expiresAt - now
			entry.ball.PrimaryPart.Transparency = if rem < 0.35
				then math.clamp(1 - (rem / 0.35), 0, 0.92)
				else 0
		end
	end
end

local function onBossTelegraph(data: any)
	if type(data) ~= "table" or typeof(data.impactPos) ~= "Vector3" then
		return
	end
	local radius = tonumber(data.radius) or 16
	local dur = tonumber(data.telegraphSec) or 1.0
	local colArr = data.color or { 239, 68, 68 }
	local kind = tostring(data.kind or "Shockwave")
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local vfxFolder = if assets then assets:FindFirstChild("VFX") else nil
	local prefab = if vfxFolder then vfxFolder:FindFirstChild("Telegraph_" .. kind) else nil
	local ring: Part
	if prefab and prefab:IsA("Part") then
		ring = prefab:Clone()
	else
		ring = Instance.new("Part")
		ring.Shape = Enum.PartType.Cylinder
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.Material = Enum.Material.Neon
	end
	ring.Name = "BossTelegraphRing"
	ring.Color = Color3.fromRGB(colArr[1] or 239, colArr[2] or 68, colArr[3] or 68)
	ring.Transparency = 0.55
	ring.Size = Vector3.new(0.4, 2, 2)
	ring.CFrame = CFrame.new(
		data.impactPos.X,
		math.max(0.5, data.impactPos.Y - 2),
		data.impactPos.Z
	) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace

	AudioCatalog.play("BossWarning", 0.9, 0.45)
	TweenService
		:Create(ring, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.4, radius * 2, radius * 2),
			Transparency = 0.18,
		})
		:Play()
	task.delay(dur + 0.15, function()
		ring:Destroy()
	end)
end

function BallThrowController.start()
	RunService.RenderStepped:Connect(stepVisualBalls)
	local remotes = Remotes.waitClient()
	remotes.ProjectileBroadcast.OnClientEvent:Connect(onProjectileBroadcast)
	remotes.BossTelegraph.OnClientEvent:Connect(onBossTelegraph)
	remotes.DashRequest.OnClientEvent:Connect(function(userId: any, dir: any)
		if tonumber(userId) == localPlayer.UserId or typeof(dir) ~= "Vector3" then
			return
		end
		local other = Players:GetPlayerByUserId(tonumber(userId) or 0)
		if other then
			AnimationController.playJettDash(other, dir, DASH_DURATION)
			local hrp = if other.Character
				then other.Character:FindFirstChild("HumanoidRootPart")
				else nil
			if hrp and hrp:IsA("BasePart") then
				AudioCatalog.playJettDash(hrp)
			end
		end
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.ButtonL3 then
			isSprinting = true
		elseif
			input.KeyCode == Enum.KeyCode.Q
			or input.KeyCode == Enum.KeyCode.LeftControl
			or input.KeyCode == Enum.KeyCode.ButtonB
			or input.KeyCode == Enum.KeyCode.ButtonR1
		then
			BallThrowController.triggerDash()
		elseif
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.KeyCode == Enum.KeyCode.ButtonR2
		then
			isHoldingFire = true
			BallThrowController.fireThrow()
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.ButtonL3 then
			isSprinting = false
		elseif
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.KeyCode == Enum.KeyCode.ButtonR2
		then
			isHoldingFire = false
		end
	end)

	RunService.Heartbeat:Connect(function(dt: number)
		local now = os.clock()
		HudGui.setDashCooldown(math.max(0, DASH_COOLDOWN - (now - lastDashAt)))

		local hrp, hum = getRootAndHum()
		if not hrp or not hum or hum.Health <= 0 then
			return
		end

		local pad = findMyFiringPad()
		local nearPad = pad ~= nil and (hrp.Position - pad.Position).Magnitude <= 6.8
		if nearPad ~= isOnTrainingPad then
			isOnTrainingPad = nearPad
			padLocked = nearPad
			LockOnController.setLockSuppressed(padLocked)
			remotes.SetTrainingStance:FireServer(padLocked)
			HudGui.setAfkTrainingActive(padLocked)
			AnimationController.setTrainingStance(padLocked)
		end
		if padLocked and hum.Jump then
			padLocked = false
			LockOnController.setLockSuppressed(false)
			remotes.SetTrainingStance:FireServer(false)
			HudGui.setAfkTrainingActive(false)
			AnimationController.setTrainingStance(false)
		end

		local stunUntil = tonumber(localPlayer:GetAttribute("MiniStunUntil")) or 0
		local slowUntil = tonumber(localPlayer:GetAttribute("FrostSlowUntil")) or 0
		if now < stunUntil then
			hum.WalkSpeed = 0
		else
			local base = if isSprinting then SPRINT_SPEED else WALK_SPEED
			if now < slowUntil then
				base *= 0.80
			end
			hum.WalkSpeed = base
		end

		if padLocked and pad then
			local hasTurbo = localPlayer:GetAttribute("Pass_AutoFireRange") == true
			local target = pickAfkTrainingTarget(pad, hasTurbo)
			if target then
				if hum.MoveDirection.Magnitude < 0.05 then
					local lookAt = Vector3.new(target.Position.X, hrp.Position.Y, target.Position.Z)
					local desiredCF = CFrame.lookAt(hrp.Position, lookAt)
					local turnAlpha = 1 - math.exp(-10 * math.min(dt, 0.1))
					hrp.CFrame = hrp.CFrame:Lerp(desiredCF, turnAlpha)
				end
				executeThrow(target, true)
			end
		elseif isHoldingFire then
			BallThrowController.fireThrow()
		end
	end)
end

return BallThrowController
