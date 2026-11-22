--!strict
--[[
	BallThrowController.luau
	Client movement, 100% FREE AFK Auto-Training Range, Toggleable Guaranteed-Hit Auto-Aim,
	and real 60 FPS ballistic/homing ball physics with hand launch & post-impact bounce rebound!
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MonetizationConfigs = require(Shared.Configs.MonetizationConfigs)
local CombatLogic = require(Shared.Utils.CombatLogic)
local MathUtil = require(Shared.Utils.MathUtil)
local ProceduralModels = require(Shared.Utils.ProceduralModels)
local AudioCatalog = require(Shared.Utils.AudioCatalog)
local Remotes = require(Shared.Net.Remotes)

local HudGui = require(script.Parent.Parent.UI.HudGui)
local AnimationController = require(script.Parent.AnimationController)

local BallThrowController = {}

local WALK_SPEED = 18
local SPRINT_SPEED = 24
local DASH_SPEED = 56
local DASH_DURATION = 0.35
local DASH_COOLDOWN = 2.5

local localPlayer = Players.LocalPlayer
local isSprinting = false
local isOnTrainingPad = false
local padLocked = false
local lastDashAt = 0
local lastThrowAt = 0
local isHoldingFire = false
local afkTargetCycle = 0
local autoAimEnabled = UserInputService.PreferredInput == Enum.PreferredInput.Touch
local currentLockedPart: BasePart? = nil
local lockReticleGui: BillboardGui? = nil

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

local function ensureReticleGui(): BillboardGui
	if lockReticleGui and lockReticleGui.Parent then
		return lockReticleGui
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "AutoAimReticle"
	bb.Size = UDim2.fromOffset(92, 92)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 200

	local lbl = Instance.new("TextLabel")
	lbl.Name = "Mark"
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextScaled = true
	lbl.TextColor3 = Color3.fromRGB(52, 255, 168)
	lbl.TextStrokeTransparency = 0.15
	lbl.Text = "◎"
	lbl.AutoLocalize = false
	lbl.Parent = bb

	local tag = Instance.new("TextLabel")
	tag.Name = "Sub"
	tag.BackgroundTransparency = 1
	tag.Position = UDim2.fromScale(0, 0.72)
	tag.Size = UDim2.fromScale(1, 0.28)
	tag.Font = Enum.Font.GothamBold
	tag.TextScaled = true
	tag.TextColor3 = Color3.fromRGB(250, 204, 21)
	tag.TextStrokeTransparency = 0.2
	tag.Text = "LOCKED"
	tag.AutoLocalize = false
	tag.Parent = bb

	lockReticleGui = bb
	return bb
end

local function updateLockReticle(targetPart: BasePart?)
	currentLockedPart = targetPart
	if not autoAimEnabled or not targetPart or not targetPart.Parent then
		if lockReticleGui then
			lockReticleGui.Adornee = nil
			lockReticleGui.Parent = nil
		end
		return
	end
	local bb = ensureReticleGui()
	bb.Adornee = targetPart
	bb.Parent = targetPart
end

local function collectBiomeCandidates(
	zone: string,
	activeBiome: string,
	candidates: { CombatLogic.AutoAimCandidate },
	partById: { [string]: BasePart }
)
	local map = workspace:FindFirstChild("BallBrawl_Map_v2")
	if map then
		local idx = 0
		for _, desc in ipairs(map:GetDescendants()) do
			if desc:IsA("Model") and desc.PrimaryPart then
				local kind = desc:GetAttribute("EntityKind")
				local biome = tostring(desc:GetAttribute("BiomeId") or "")
				if
					(kind == "PvEMob" or kind == "BiomeBoss")
					and (activeBiome == "" or biome == activeBiome)
				then
					idx += 1
					local id = `ent_{idx}`
					local pp = desc.PrimaryPart
					partById[id] = pp
					table.insert(candidates, {
						id = id,
						kind = if kind == "BiomeBoss" then "Boss" else "Mob",
						x = pp.Position.X,
						y = pp.Position.Y,
						z = pp.Position.Z,
					})
				end
			end
		end
	end
	if zone == "LockedBossPvP" then
		for _, plr in ipairs(Players:GetPlayers()) do
			if
				plr ~= localPlayer
				and plr:GetAttribute("Zone") == "LockedBossPvP"
				and plr.Character
			then
				local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
				local hum = plr.Character:FindFirstChildOfClass("Humanoid")
				if hrp and hrp:IsA("BasePart") and hum and hum.Health > 0 then
					local id = `plr_{plr.UserId}`
					partById[id] = hrp
					table.insert(candidates, {
						id = id,
						kind = "PvP",
						x = hrp.Position.X,
						y = hrp.Position.Y,
						z = hrp.Position.Z,
					})
				end
			end
		end
	end
end

local function findAutoAimTarget(origin: Vector3): BasePart?
	local zone = tostring(localPlayer:GetAttribute("Zone") or "Hub")
	local activeBiome = tostring(localPlayer:GetAttribute("ActiveBiome") or "")
	local candidates: { CombatLogic.AutoAimCandidate } = {}
	local partById: { [string]: BasePart } = {}

	if zone == "Hub" then
		local pad = findMyFiringPad()
		local tr = if pad then pad.Parent else nil
		if tr then
			for _, child in ipairs(tr:GetChildren()) do
				if child:IsA("BasePart") then
					local tk = child:GetAttribute("TargetKind")
					if tk == "Static" or tk == "MovingGold" then
						partById[child.Name] = child
						table.insert(candidates, {
							id = child.Name,
							kind = if tk == "MovingGold" then "GoldTarget" else "Target",
							x = child.Position.X,
							y = child.Position.Y,
							z = child.Position.Z,
						})
					end
				end
			end
		end
	else
		collectBiomeCandidates(zone, activeBiome, candidates, partById)
	end

	local chosen = CombatLogic.selectAutoAimTarget(origin.X, origin.Y, origin.Z, candidates)
	return if chosen then partById[chosen.id] else nil
end

local function computeManualAim(origin: Vector3, cam: Camera): Vector3
	local baseDir = cam.CFrame.LookVector
	if UserInputService.PreferredInput == Enum.PreferredInput.KeyboardAndMouse then
		local mouseLoc = UserInputService:GetMouseLocation()
		local ray = cam:ViewportPointToRay(mouseLoc.X, mouseLoc.Y)
		local targetPoint = ray.Origin + ray.Direction * 120
		baseDir = (targetPoint - origin).Unit
	end
	return baseDir
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
	local useHoming = isAfkShot or autoAimEnabled
	local lockedPart: BasePart? = overrideTarget
	if not lockedPart and useHoming then
		lockedPart = findAutoAimTarget(origin)
		updateLockReticle(lockedPart)
	end

	local aimDir: Vector3
	if lockedPart and lockedPart.Parent then
		local delta = lockedPart.Position - origin
		aimDir = if delta.Magnitude > 0.1 then delta.Unit else hrp.CFrame.LookVector
		if not isAfkShot then
			local lookFlat =
				Vector3.new(lockedPart.Position.X, hrp.Position.Y, lockedPart.Position.Z)
			if (lookFlat - hrp.Position).Magnitude > 0.5 then
				hrp.CFrame = hrp.CFrame:Lerp(CFrame.lookAt(hrp.Position, lookFlat), 0.72)
			end
		end
	else
		aimDir = computeManualAim(origin, cam)
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

function BallThrowController.setAutoAimEnabled(enabled: boolean)
	autoAimEnabled = enabled
	localPlayer:SetAttribute("AutoAimEnabled", enabled)
	HudGui.setAutoAimEnabled(enabled)
	if not enabled then
		updateLockReticle(nil)
	end
end

function BallThrowController.toggleAutoAim()
	BallThrowController.setAutoAimEnabled(not autoAimEnabled)
end

function BallThrowController.isAutoAimEnabled(): boolean
	return autoAimEnabled
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
	Remotes.waitClient().DashRequest:FireServer()
	AudioCatalog.play("Dash", 1.25, 0.45)

	local moveDir = if hum.MoveDirection.Magnitude > 0.1
		then hum.MoveDirection.Unit
		else hrp.CFrame.LookVector
	local att = Instance.new("Attachment")
	att.Parent = hrp
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.MaxForce = hrp.AssemblyMass * workspace.Gravity * 25
	lv.VectorVelocity = Vector3.new(moveDir.X * DASH_SPEED, 2, moveDir.Z * DASH_SPEED)
	lv.Parent = hrp
	task.delay(DASH_DURATION, function()
		lv:Destroy()
		att:Destroy()
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
		AnimationController.playImpactEffect(
			impactPos,
			"Surface",
			false,
			Color3.fromRGB(200, 220, 255),
			nil
		)
	end
end

local function runPostImpactBounce(
	ball: Model,
	impactPos: Vector3,
	incomingVel: Vector3,
	normal: Vector3
)
	local n = if normal.Magnitude > 0.1 then normal.Unit else Vector3.yAxis
	local reflected = incomingVel - 2 * incomingVel:Dot(n) * n
	local bounceVel = reflected * 0.32
		+ Vector3.new(
			(math.random() - 0.5) * 14,
			math.max(12, math.abs(reflected.Y) * 0.4),
			(math.random() - 0.5) * 14
		)
	local pos = impactPos
	local startAt = os.clock()
	local bounceDur = 0.42
	local floorY = math.max(1.2, impactPos.Y - 4.5)
	local spinAngle = 0
	local conn: RBXScriptConnection? = nil

	conn = RunService.RenderStepped:Connect(function(dt: number)
		local elapsed = os.clock() - startAt
		if elapsed >= bounceDur or not ball.Parent then
			if conn then
				conn:Disconnect()
				conn = nil
			end
			if ball.Parent then
				ball:Destroy()
			end
			return
		end
		local stepDt = math.min(dt, 0.05)
		bounceVel += Vector3.new(0, -68 * stepDt, 0)
		pos += bounceVel * stepDt
		if pos.Y < floorY then
			pos = Vector3.new(pos.X, floorY, pos.Z)
			bounceVel =
				Vector3.new(bounceVel.X * 0.72, math.abs(bounceVel.Y) * 0.48, bounceVel.Z * 0.72)
		end
		spinAngle += stepDt * 14
		local fade = math.clamp(1 - (elapsed / bounceDur), 0.18, 1)
		ball:PivotTo(CFrame.new(pos) * CFrame.Angles(spinAngle, spinAngle * 0.5, 0))
		if ball.PrimaryPart then
			ball.PrimaryPart.Transparency = math.clamp(1 - fade, 0, 0.92)
		end
	end)
end

local function onProjectileBroadcast(data: any)
	if
		type(data) ~= "table"
		or typeof(data.origin) ~= "Vector3"
		or typeof(data.endPos) ~= "Vector3"
	then
		return
	end
	local shooterId = tonumber(data.shooterId)
	local shooterPlr = if shooterId then Players:GetPlayerByUserId(shooterId) else nil
	if shooterPlr and shooterPlr ~= localPlayer then
		AnimationController.playThrowAnim(shooterPlr)
	end

	local skinCol: Color3? = nil
	if type(data.ballSkin) == "string" then
		local spec = MonetizationConfigs.COSMETICS[data.ballSkin]
		if spec then
			skinCol = Color3.fromRGB(spec.color[1], spec.color[2], spec.color[3])
		end
	end
	local ball =
		ProceduralModels.createBallVisual(tostring(data.ballTierId or "RubberBall"), skinCol)
	local startPos = getThrowHandOrigin(shooterPlr, data.origin)
	local serverOrigin: Vector3 = data.origin
	local staticEnd: Vector3 = data.endPos
	local hitInst = if typeof(data.hitTarget) == "Instance" then data.hitTarget else nil
	local homingPart = if data.isHoming == true
			and hitInst
			and hitInst:IsA("BasePart")
		then hitInst
		else nil
	local dur = math.clamp(tonumber(data.travelSec) or 0.25, 0.08, 1.65)
	local launchVel: Vector3 = if typeof(data.launchVel) == "Vector3"
		then data.launchVel
		else (staticEnd - serverOrigin).Unit * (tonumber(data.speed) or 115)
	local normal: Vector3 = if typeof(data.normal) == "Vector3" then data.normal else Vector3.yAxis
	local hitKind = tostring(data.hitKind or "Miss")
	local isCrit = data.isCrit == true
	local damage = tonumber(data.damage) or 1

	ball:PivotTo(CFrame.new(startPos, staticEnd))
	ball.Parent = workspace

	local startTime = os.clock()
	local prevPos = startPos
	local lastVel = launchVel
	local arcBoost = math.clamp((staticEnd - startPos).Magnitude * 0.08, 0.8, 5.5)
	local conn: RBXScriptConnection? = nil

	conn = RunService.RenderStepped:Connect(function(dt: number)
		local elapsed = os.clock() - startTime
		local alpha = math.clamp(elapsed / dur, 0, 1)
		local nextPos: Vector3
		if homingPart and homingPart.Parent then
			-- Real-time homing curve right into the moving target's live center!
			local liveDest = homingPart.Position
			local linear = startPos:Lerp(liveDest, alpha)
			nextPos = linear + Vector3.new(0, 4 * alpha * (1 - alpha) * arcBoost, 0)
		else
			-- True ballistic gravity arc blended smoothly from hand launch to server curve
			local sx, sy, sz = CombatLogic.sampleBallisticPosition(
				serverOrigin.X,
				serverOrigin.Y,
				serverOrigin.Z,
				launchVel.X,
				launchVel.Y,
				launchVel.Z,
				elapsed,
				CombatLogic.BALL_GRAVITY
			)
			local handBlend = math.clamp(1 - alpha * 4, 0, 1)
			nextPos = Vector3.new(sx, sy, sz) + (startPos - serverOrigin) * handBlend
		end

		local stepVel = (nextPos - prevPos) / math.max(0.008, dt)
		if stepVel.Magnitude > 1 then
			lastVel = stepVel
		end
		prevPos = nextPos

		if ball.Parent then
			local rollSpin = elapsed * 20
			local lookPos = nextPos
				+ (if lastVel.Magnitude > 0.5 then lastVel.Unit else Vector3.zAxis)
			ball:PivotTo(CFrame.lookAt(nextPos, lookPos) * CFrame.Angles(-rollSpin, 0, 0))
		end

		if alpha >= 1 then
			if conn then
				conn:Disconnect()
				conn = nil
			end
			local impactPos = if homingPart and homingPart.Parent
				then homingPart.Position
				else staticEnd
			triggerImpactFeedback(impactPos, hitKind, isCrit, damage, hitInst)
			if hitKind ~= "Miss" and ball.Parent then
				runPostImpactBounce(ball, impactPos, lastVel, normal)
			elseif ball.Parent then
				ball:Destroy()
			end
		end
	end)
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
	BallThrowController.setAutoAimEnabled(autoAimEnabled)
	local remotes = Remotes.waitClient()
	remotes.ProjectileBroadcast.OnClientEvent:Connect(onProjectileBroadcast)
	remotes.BossTelegraph.OnClientEvent:Connect(onBossTelegraph)

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.ButtonL3 then
			isSprinting = true
		elseif input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.ButtonB then
			BallThrowController.triggerDash()
		elseif input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.ButtonY then
			BallThrowController.toggleAutoAim()
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
			remotes.SetTrainingStance:FireServer(padLocked)
			HudGui.setAfkTrainingActive(padLocked)
			AnimationController.setTrainingStance(padLocked)
		end
		if padLocked and hum.Jump then
			padLocked = false
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

		if autoAimEnabled and not padLocked then
			local lockedPart = findAutoAimTarget(hrp.Position + Vector3.new(0, 1.4, 0))
			if lockedPart ~= currentLockedPart then
				updateLockReticle(lockedPart)
			end
		elseif currentLockedPart ~= nil then
			updateLockReticle(nil)
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
