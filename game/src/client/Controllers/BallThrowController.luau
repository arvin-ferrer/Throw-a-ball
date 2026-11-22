--!strict
--[[
	BallThrowController.luau
	Client movement & ball-throwing controller:
	- Stationary Training Pad stance lock (jump/move off cancels cleanly)
	- Free movement (18 walk / 24 sprint) + 0.35s Dash/Dodge (2.5s CD) + Frost Slow/Stun respect
	- Soft Magnetic Aim-Assist (generous on PvE targets/mobs/bosses, tuned gently in PvP)
	- Auto-Fire Range pass support, client projectile trails, damage popups & Boss Telegraphs
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MonetizationConfigs = require(Shared.Configs.MonetizationConfigs)
local MathUtil = require(Shared.Utils.MathUtil)
local ProceduralModels = require(Shared.Utils.ProceduralModels)
local AudioCatalog = require(Shared.Utils.AudioCatalog)
local Remotes = require(Shared.Net.Remotes)

local HudGui = require(script.Parent.Parent.UI.HudGui)

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

local function getRootAndHum(): (BasePart?, Humanoid?)
	local char = localPlayer.Character
	if not char then
		return nil, nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	return if hrp and hrp:IsA("BasePart") then hrp else nil, hum
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

local function computeMagneticAim(origin: Vector3, baseDir: Vector3): Vector3
	local zone = tostring(localPlayer:GetAttribute("Zone") or "Hub")
	local maxConeDot = if zone == "LockedBossPvP" then 0.965 else 0.90
	local bestDir = baseDir
	local bestScore = maxConeDot

	local function consider(pos: Vector3)
		local toTarget = pos - origin
		local dist = toTarget.Magnitude
		if dist < 2 or dist > 155 then
			return
		end
		local d = toTarget.Unit:Dot(baseDir)
		if d > bestScore then
			bestScore = d
			bestDir = toTarget.Unit
		end
	end

	if zone == "Hub" then
		for _, tag in ipairs({ "MovingGoldTarget", "TrainingTarget" }) do
			for _, t in ipairs(CollectionService:GetTagged(tag)) do
				if t:IsA("BasePart") then
					consider(t.Position)
				end
			end
		end
	else
		local map = workspace:FindFirstChild("BallBrawl_Map_v2")
		if map then
			for _, desc in ipairs(map:GetDescendants()) do
				if desc:IsA("Model") and desc.PrimaryPart then
					local kind = desc:GetAttribute("EntityKind")
					if kind == "PvEMob" or kind == "BiomeBoss" then
						consider(desc.PrimaryPart.Position)
					end
				end
			end
		end
		if zone == "LockedBossPvP" then
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr ~= localPlayer and plr.Character then
					local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
					if hrp and hrp:IsA("BasePart") then
						consider(hrp.Position)
					end
				end
			end
		end
	end
	return bestDir
end

function BallThrowController.fireThrow()
	local hrp = getRootAndHum()
	local cam = workspace.CurrentCamera
	if not hrp or not cam then
		return
	end
	local now = os.clock()
	local speedStat = tonumber(localPlayer:GetAttribute("ThrowSpeed")) or 1.0
	local cd = MathUtil.computeThrowCooldown(speedStat, 0)
	if now - lastThrowAt < cd * 0.92 then
		return
	end
	lastThrowAt = now

	local origin = hrp.Position + Vector3.new(0, 1.4, 0)
	local baseDir = cam.CFrame.LookVector
	if UserInputService.PreferredInput == Enum.PreferredInput.KeyboardAndMouse then
		local mouseLoc = UserInputService:GetMouseLocation()
		local ray = cam:ViewportPointToRay(mouseLoc.X, mouseLoc.Y)
		local targetPoint = ray.Origin + ray.Direction * 120
		baseDir = (targetPoint - origin).Unit
	end
	local aimDir = computeMagneticAim(origin, baseDir)
	Remotes.waitClient().ThrowBall:FireServer(aimDir)
	AudioCatalog.play("Throw", 1.0 + math.random() * 0.15, 0.35)
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
	bb.Size = UDim2.fromOffset(120, 38)
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
			CFrame = anchor.CFrame + Vector3.new(0, 3.8, 0),
		})
		:Play()
	task.delay(0.7, function()
		anchor:Destroy()
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
	local skinCol: Color3? = nil
	if type(data.ballSkin) == "string" then
		local spec = MonetizationConfigs.COSMETICS[data.ballSkin]
		if spec then
			skinCol = Color3.fromRGB(spec.color[1], spec.color[2], spec.color[3])
		end
	end
	local ball =
		ProceduralModels.createBallVisual(tostring(data.ballTierId or "RubberBall"), skinCol)
	ball:PivotTo(CFrame.new(data.origin))
	ball.Parent = workspace

	local dist = (data.endPos - data.origin).Magnitude
	local dur = math.clamp(dist / math.max(40, tonumber(data.speed) or 115), 0.06, 0.9)
	local root = ball.PrimaryPart
	if root then
		local tween = TweenService:Create(root, TweenInfo.new(dur, Enum.EasingStyle.Linear), {
			CFrame = CFrame.new(data.endPos),
		})
		tween:Play()
		tween.Completed:Connect(function()
			if data.hitKind == "GoldTarget" then
				AudioCatalog.play("GoldCombo", 1.25, 0.55)
				spawnDamagePopup(data.endPos, "2x GOLD +SPD!", Color3.fromRGB(250, 204, 21))
			elseif data.hitKind == "Target" then
				AudioCatalog.play("TargetHit", 1.05, 0.4)
				spawnDamagePopup(data.endPos, "+DMG!", Color3.fromRGB(74, 222, 128))
			elseif data.hitKind == "Mob" or data.hitKind == "Boss" or data.hitKind == "PvP" then
				AudioCatalog.play("BossHit", if data.isCrit then 1.35 else 1.0, 0.45)
				local dmgTxt = MathUtil.formatNumber(tonumber(data.damage) or 1)
				spawnDamagePopup(
					data.endPos,
					if data.isCrit then `CRIT {dmgTxt}!` else `-{dmgTxt}`,
					if data.isCrit
						then Color3.fromRGB(250, 204, 21)
						else Color3.fromRGB(255, 110, 90)
				)
			end
			ball:Destroy()
		end)
	else
		ball:Destroy()
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

	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		HudGui.setDashCooldown(math.max(0, DASH_COOLDOWN - (now - lastDashAt)))

		local hrp, hum = getRootAndHum()
		if not hrp or not hum or hum.Health <= 0 then
			return
		end

		-- Check Stationary Training Firing Pad
		local pad = findMyFiringPad()
		local nearPad = pad ~= nil and (hrp.Position - pad.Position).Magnitude <= 6.2
		if nearPad ~= isOnTrainingPad then
			isOnTrainingPad = nearPad
			padLocked = nearPad
			remotes.SetTrainingStance:FireServer(padLocked)
		end
		if padLocked and hum.Jump then
			padLocked = false
			remotes.SetTrainingStance:FireServer(false)
		end

		-- Compute authoritative WalkSpeed (18 walk / 24 sprint, Frost Slow -20%, Mini-Stun 0)
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

		-- Continuous firing when held OR Auto-Fire Range Game Pass on Training Pad
		local autoFire = padLocked and localPlayer:GetAttribute("Pass_AutoFireRange") == true
		if isHoldingFire or autoFire then
			BallThrowController.fireThrow()
		end
	end)
end

return BallThrowController
