--!strict
--[[
	LockOnController.luau
	Souls-like Lock-On Targeting, Locked Camera, Character Strafe Orientation,
	Horizontal Input Target Switching, Dynamic LOS/Frustum Validation, and Reticle UI.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AudioCatalog = require(Shared.Utils.AudioCatalog)
local LockOnLogic = require(Shared.Utils.LockOnLogic)

local HudGui = require(script.Parent.Parent.UI.HudGui)
local Theme = require(script.Parent.Parent.UI.Theme)

local CFG = LockOnLogic.CONFIG

export type LockedEntry = {
	id: string,
	model: Model,
	part: BasePart,
	attachment: Attachment?,
	isBoss: boolean,
	isPvP: boolean,
	player: Player?,
}

local LockOnController = {}

local localPlayer = Players.LocalPlayer
local started = false
local suppressed = false
local currentTarget: LockedEntry? = nil
local graceState = LockOnLogic.createGraceState()

-- Camera smoothing & collision state
local prevCameraType: Enum.CameraType? = nil
local smoothedCamPos: Vector3? = nil
local smoothedLookDir: Vector3? = nil
local smoothedWallDist: number? = nil
local lastStableFwdX = 0
local lastStableFwdZ = -1
local switchBoostUntil = 0

-- Horizontal switching input state
local mouseAccumX = 0
local lastMousePos: Vector2? = nil
local lastSwitchAt = 0
local stickArmed = true
local activeSwipeTouch: InputObject? = nil
local swipeStartPos = Vector2.zero
local swipeConsumed = false

-- Diagnostics for automated QA
local switchCount = 0
local lastBreakReason = ""

-- Reticle UI state
local reticleGui: ScreenGui? = nil
local reticleRoot: Frame? = nil
local reticleRing: Frame? = nil
local reticleDiamond: Frame? = nil
local reticleDot: Frame? = nil
local reticleScale: UIScale? = nil
local reticleLeftArrow: TextLabel? = nil
local reticleRightArrow: TextLabel? = nil
local reticleSnapAt = 0
local lastChevronCheckAt = 0
local hasLeftCandidate = false
local hasRightCandidate = false

local losRayParams = RaycastParams.new()
losRayParams.FilterType = Enum.RaycastFilterType.Exclude
losRayParams.IgnoreWater = true

local wallRayParams = RaycastParams.new()
wallRayParams.FilterType = Enum.RaycastFilterType.Exclude
wallRayParams.IgnoreWater = true

local function getRootAndHum(): (BasePart?, Humanoid?)
	local char = localPlayer.Character
	if not char then
		return nil, nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	return if hrp and hrp:IsA("BasePart") then hrp else nil, hum
end

local function isIgnorableGeometry(inst: Instance): boolean
	if inst:IsA("Terrain") then
		return false
	end
	if not inst:IsA("BasePart") then
		return true
	end
	if not inst.CanCollide and inst.Transparency >= 0.85 then
		return true
	end
	local name = inst.Name
	return name == "BossTelegraphRing"
		or name == "MobProjSplashRing"
		or name == "EliminationBurst"
		or name == "CombatJuicePopup"
end

local function resolveLockOnAnchor(
	model: Model,
	isBoss: boolean,
	isPvP: boolean
): (BasePart?, Attachment?)
	local primary = model.PrimaryPart
	local customAtt = if primary then primary:FindFirstChild("LockOnPoint") else nil
	if not customAtt then
		customAtt = model:FindFirstChild("LockOnPoint", true)
	end
	if
		customAtt
		and customAtt:IsA("Attachment")
		and customAtt.Parent
		and customAtt.Parent:IsA("BasePart")
	then
		return customAtt.Parent, customAtt
	end
	if isBoss then
		local chest = model:FindFirstChild("ChestCore") or model:FindFirstChild("BossCore")
		if chest and chest:IsA("BasePart") then
			return chest, nil
		end
	elseif isPvP then
		local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
		if torso and torso:IsA("BasePart") then
			return torso, nil
		end
	end
	if primary and primary:IsA("BasePart") then
		return primary, nil
	end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	return if hrp and hrp:IsA("BasePart") then hrp else nil, nil
end

local function getAnchorWorldPos(entry: LockedEntry): Vector3?
	if entry.attachment and entry.attachment.Parent then
		return entry.attachment.WorldPosition
	end
	if entry.part and entry.part.Parent then
		return entry.part.Position
	end
	return nil
end

local function hasCameraLineOfSight(
	camPos: Vector3,
	targetPos: Vector3,
	targetModel: Model
): boolean
	local delta = targetPos - camPos
	if delta.Magnitude < 0.25 then
		return true
	end
	local excluded: { Instance } = {}
	if localPlayer.Character then
		table.insert(excluded, localPlayer.Character)
	end
	local followers = workspace:FindFirstChild("LocalActiveFollowers")
	if followers then
		table.insert(excluded, followers)
	end
	for _ = 1, 6 do
		losRayParams.FilterDescendantsInstances = excluded
		local res = workspace:Raycast(camPos, delta, losRayParams)
		if not res or not res.Instance then
			return true
		end
		if res.Instance:IsDescendantOf(targetModel) then
			return true
		end
		if isIgnorableGeometry(res.Instance) then
			table.insert(excluded, res.Instance)
		else
			return false
		end
	end
	return false
end

local function isEntryAliveAndEligible(entry: LockedEntry): boolean
	if suppressed or not entry.model.Parent or not entry.part.Parent then
		return false
	end
	local zone = tostring(localPlayer:GetAttribute("Zone") or "Hub")
	local activeBiome = tostring(localPlayer:GetAttribute("ActiveBiome") or "")
	if zone ~= "BiomePvE" and zone ~= "LockedBossPvP" then
		return false
	end
	if entry.isPvP then
		local plr = entry.player
		if not plr or not plr.Parent or zone ~= "LockedBossPvP" then
			return false
		end
		if plr:GetAttribute("Zone") ~= "LockedBossPvP" then
			return false
		end
		local hum = entry.model:FindFirstChildOfClass("Humanoid")
		return hum ~= nil and hum.Health > 0
	end
	local kind = entry.model:GetAttribute("EntityKind")
	local bId = tostring(entry.model:GetAttribute("BiomeId") or "")
	if activeBiome ~= "" and bId ~= activeBiome then
		return false
	end
	if entry.isBoss then
		return zone == "LockedBossPvP" and kind == "BiomeBoss"
	end
	if zone ~= "BiomePvE" or kind ~= "PvEMob" then
		return false
	end
	local hum = entry.model:FindFirstChildOfClass("Humanoid")
	return not hum or hum.Health > 0
end

local function collectMapEnemyEntries(
	zone: string,
	activeBiome: string,
	out: { LockedEntry }
): boolean
	local map = workspace:FindFirstChild("BallBrawl_Map_v2")
	if not map then
		return false
	end
	local foundBoss = false
	for _, desc in ipairs(map:GetDescendants()) do
		if desc:IsA("Model") and desc.PrimaryPart then
			local kind = desc:GetAttribute("EntityKind")
			local bId = tostring(desc:GetAttribute("BiomeId") or "")
			local biomeMatch = activeBiome == "" or bId == activeBiome
			local validMob = zone == "BiomePvE" and kind == "PvEMob" and biomeMatch
			local validBoss = zone == "LockedBossPvP" and kind == "BiomeBoss" and biomeMatch
			if validMob or validBoss then
				local hum = desc:FindFirstChildOfClass("Humanoid")
				if not hum or hum.Health > 0 then
					local part, att = resolveLockOnAnchor(desc, validBoss, false)
					if part then
						if validBoss then
							foundBoss = true
						end
						table.insert(out, {
							id = tostring(desc),
							model = desc,
							part = part,
							attachment = att,
							isBoss = validBoss,
							isPvP = false,
							player = nil,
						})
					end
				end
			end
		end
	end
	return foundBoss
end

local function collectPvPEnemyEntries(out: { LockedEntry })
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= localPlayer and plr:GetAttribute("Zone") == "LockedBossPvP" and plr.Character then
			local hum = plr.Character:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				local part, att = resolveLockOnAnchor(plr.Character, false, true)
				if part then
					table.insert(out, {
						id = tostring(plr.Character),
						model = plr.Character,
						part = part,
						attachment = att,
						isBoss = false,
						isPvP = true,
						player = plr,
					})
				end
			end
		end
	end
end

local function collectZoneEnemyEntries(): { LockedEntry }
	local out: { LockedEntry } = {}
	if suppressed then
		return out
	end
	local zone = tostring(localPlayer:GetAttribute("Zone") or "Hub")
	local activeBiome = tostring(localPlayer:GetAttribute("ActiveBiome") or "")
	if zone ~= "BiomePvE" and zone ~= "LockedBossPvP" then
		return out
	end
	local foundBoss = collectMapEnemyEntries(zone, activeBiome, out)
	if zone == "LockedBossPvP" and not foundBoss then
		collectPvPEnemyEntries(out)
	end
	return out
end

local function collectVisibleCandidates(
	cam: Camera,
	playerPos: Vector3,
	excludeModel: Model?
): (
	{ LockOnLogic.ScreenCandidate },
	{ [string]: LockedEntry }
)
	local vp = cam.ViewportSize
	local w = math.max(1, vp.X)
	local h = math.max(1, vp.Y)
	local camPos = cam.CFrame.Position

	local candidates: { LockOnLogic.ScreenCandidate } = {}
	local byId: { [string]: LockedEntry } = {}
	for _, entry in ipairs(collectZoneEnemyEntries()) do
		if excludeModel and entry.model == excludeModel then
			continue
		end
		local pos = getAnchorWorldPos(entry)
		if not pos then
			continue
		end
		local dist = (pos - playerPos).Magnitude
		if dist < CFG.MIN_LOCK_RANGE or dist > LockOnLogic.getAcquireRange(entry.isBoss) then
			continue
		end
		local vpPos, onScreen = cam:WorldToViewportPoint(pos)
		local u = vpPos.X / w
		local v = vpPos.Y / h
		if
			not onScreen
			or not LockOnLogic.isWithinViewport(u, v, vpPos.Z, CFG.ACQUIRE_VIEWPORT_MARGIN)
		then
			continue
		end
		if not hasCameraLineOfSight(camPos, pos, entry.model) then
			continue
		end
		byId[entry.id] = entry
		table.insert(candidates, {
			id = entry.id,
			u = u,
			v = v,
			depth = vpPos.Z,
			distance = dist,
			isBoss = entry.isBoss,
		})
	end
	return candidates, byId
end

local function makeReticleChevron(
	parent: Frame,
	name: string,
	glyph: string,
	posX: number
): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.Name = name
	lbl.BackgroundTransparency = 1
	lbl.AnchorPoint = Vector2.new(0.5, 0.5)
	lbl.Position = UDim2.fromScale(posX, 0.5)
	lbl.Size = UDim2.fromOffset(18, 20)
	lbl.Font = Enum.Font.GothamBold
	lbl.Text = glyph
	lbl.TextSize = 14
	lbl.TextColor3 = Color3.fromRGB(255, 232, 118)
	lbl.TextStrokeTransparency = 0.25
	lbl.Visible = false
	lbl.AutoLocalize = false
	lbl.Parent = parent
	return lbl
end

local function buildReticleUi()
	if reticleGui and reticleGui.Parent then
		return
	end
	local gui = Theme.createScreenGui("BallBrawl_LockOnReticle", 14)
	gui.IgnoreGuiInset = true
	reticleGui = gui

	local root = Instance.new("Frame")
	root.Name = "LockReticle"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Size = UDim2.fromOffset(58, 58)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.Active = false
	root.Parent = gui
	reticleRoot = root

	local scaleObj = Instance.new("UIScale")
	scaleObj.Scale = 1
	scaleObj.Parent = root
	reticleScale = scaleObj

	local ring = Instance.new("Frame")
	ring.Name = "OuterRing"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(42, 42)
	ring.BackgroundTransparency = 1
	ring.Parent = root
	Theme.addCorner(ring, 999)
	Theme.addStroke(ring, Color3.fromRGB(255, 232, 118), 2.4, 0.08)
	reticleRing = ring

	local diamond = Instance.new("Frame")
	diamond.Name = "Diamond"
	diamond.AnchorPoint = Vector2.new(0.5, 0.5)
	diamond.Position = UDim2.fromScale(0.5, 0.5)
	diamond.Size = UDim2.fromOffset(24, 24)
	diamond.Rotation = 45
	diamond.BackgroundTransparency = 1
	diamond.Parent = root
	Theme.addCorner(diamond, 4)
	Theme.addStroke(diamond, Color3.fromRGB(255, 255, 255), 2.0, 0.1)
	reticleDiamond = diamond

	local dot = Instance.new("Frame")
	dot.Name = "CenterDot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(8, 8)
	dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	dot.BorderSizePixel = 0
	dot.Parent = root
	Theme.addCorner(dot, 999)
	Theme.addStroke(dot, Color3.fromRGB(24, 24, 34), 1.4, 0.1)
	reticleDot = dot

	reticleLeftArrow = makeReticleChevron(root, "LeftChevron", "◀", -0.18)
	reticleRightArrow = makeReticleChevron(root, "RightChevron", "▶", 1.18)
end

local function setReticleStyle(isWarning: boolean)
	local ringCol = if isWarning
		then Color3.fromRGB(251, 146, 60)
		else Color3.fromRGB(255, 232, 118)
	local coreCol = if isWarning
		then Color3.fromRGB(253, 186, 116)
		else Color3.fromRGB(255, 255, 255)
	local strokeTrans = if isWarning then 0.32 else 0.08
	if reticleRing then
		local st = reticleRing:FindFirstChildOfClass("UIStroke")
		if st then
			st.Color = ringCol
			st.Transparency = strokeTrans
		end
	end
	if reticleDiamond then
		local st = reticleDiamond:FindFirstChildOfClass("UIStroke")
		if st then
			st.Color = coreCol
			st.Transparency = strokeTrans
		end
	end
	if reticleDot then
		reticleDot.BackgroundColor3 = coreCol
		reticleDot.BackgroundTransparency = if isWarning then 0.3 else 0
	end
end

local function hideReticle()
	if reticleRoot then
		reticleRoot.Visible = false
	end
	if reticleLeftArrow then
		reticleLeftArrow.Visible = false
	end
	if reticleRightArrow then
		reticleRightArrow.Visible = false
	end
end

local function updateReticleVisual(cam: Camera, targetPos: Vector3, now: number)
	if not reticleRoot then
		return
	end
	local vpPos, onScreen = cam:WorldToViewportPoint(targetPos)
	if not onScreen or vpPos.Z <= 0 then
		reticleRoot.Visible = false
		return
	end
	reticleRoot.Visible = true
	reticleRoot.Position = UDim2.fromOffset(vpPos.X, vpPos.Y)

	local snapElapsed = now - reticleSnapAt
	local snapBoost = if snapElapsed < 0.14 then (1 - snapElapsed / 0.14) * 0.34 else 0
	local pulse = math.sin(now * 6.0) * 0.045
	if reticleScale then
		reticleScale.Scale = 1.0 + snapBoost + pulse
	end
	if reticleDiamond then
		reticleDiamond.Rotation = 45 + math.sin(now * 2.5) * 6
	end
	setReticleStyle(graceState.obstructedSec > 0.02 or graceState.offScreenSec > 0.02)
	if reticleLeftArrow then
		reticleLeftArrow.Visible = hasLeftCandidate
	end
	if reticleRightArrow then
		reticleRightArrow.Visible = hasRightCandidate
	end
end

local function syncLockIndicators(active: boolean)
	localPlayer:SetAttribute("LockOnActive", active)
	HudGui.setLockOnActive(active)
end

local function restoreFreeCamera()
	local cam = workspace.CurrentCamera
	if cam and cam.CameraType == Enum.CameraType.Scriptable then
		cam.CameraType = prevCameraType or Enum.CameraType.Custom
	end
	prevCameraType = nil
	smoothedCamPos = nil
	smoothedLookDir = nil
	smoothedWallDist = nil
	lastMousePos = nil

	local _, hum = getRootAndHum()
	if hum then
		hum.AutoRotate = true
	end
	hideReticle()
	syncLockIndicators(false)
end

local function engageTarget(entry: LockedEntry, isSwitch: boolean)
	local cam = workspace.CurrentCamera
	local wasLocked = currentTarget ~= nil
	currentTarget = entry
	graceState = LockOnLogic.createGraceState()
	mouseAccumX = 0
	lastMousePos = nil
	reticleSnapAt = os.clock()
	lastChevronCheckAt = 0

	if isSwitch then
		switchBoostUntil = os.clock() + CFG.CAM_SWITCH_BOOST_SEC
		switchCount += 1
	end
	if cam and not wasLocked then
		prevCameraType = if cam.CameraType ~= Enum.CameraType.Scriptable
			then cam.CameraType
			else Enum.CameraType.Custom
		cam.CameraType = Enum.CameraType.Scriptable
		smoothedCamPos = cam.CFrame.Position
		smoothedLookDir = cam.CFrame.LookVector
		local flatLook = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
		if flatLook.Magnitude > 0.05 then
			local unitLook = flatLook.Unit
			lastStableFwdX = unitLook.X
			lastStableFwdZ = unitLook.Z
		end
	end
	local _, hum = getRootAndHum()
	if hum then
		hum.AutoRotate = false
	end
	syncLockIndicators(true)
	AudioCatalog.play("TargetHit", if isSwitch then 1.38 else 1.22, 0.16)
end

function LockOnController.clearLockOn(reason: string?)
	lastBreakReason = reason or "Manual"
	if currentTarget == nil then
		syncLockIndicators(false)
		hideReticle()
		return
	end
	currentTarget = nil
	graceState = LockOnLogic.createGraceState()
	mouseAccumX = 0
	lastMousePos = nil
	activeSwipeTouch = nil
	swipeConsumed = false
	restoreFreeCamera()
end

local function tryAcquireOrAutoSwitch(excludeModel: Model?, reasonIfEmpty: string): boolean
	local cam = workspace.CurrentCamera
	local hrp, hum = getRootAndHum()
	if not cam or not hrp or not hum or hum.Health <= 0 or suppressed then
		LockOnController.clearLockOn(reasonIfEmpty)
		return false
	end
	local candidates, byId = collectVisibleCandidates(cam, hrp.Position, excludeModel)
	local picked = LockOnLogic.selectAcquireCandidate(candidates)
	if picked and byId[picked.id] then
		engageTarget(byId[picked.id], excludeModel ~= nil)
		return true
	end
	if currentTarget ~= nil then
		LockOnController.clearLockOn(reasonIfEmpty)
	end
	return false
end

function LockOnController.switchTarget(dirSign: number): boolean
	if not currentTarget or dirSign == 0 then
		return false
	end
	local now = os.clock()
	if now < lastSwitchAt + CFG.SWITCH_COOLDOWN_SEC then
		return false
	end
	local cam = workspace.CurrentCamera
	local hrp = getRootAndHum()
	if not cam or not hrp then
		return false
	end
	local curPos = getAnchorWorldPos(currentTarget)
	if not curPos then
		return false
	end
	local vp = cam.ViewportSize
	local vpPos = cam:WorldToViewportPoint(curPos)
	local curU = vpPos.X / math.max(1, vp.X)
	local curV = vpPos.Y / math.max(1, vp.Y)

	local candidates, byId = collectVisibleCandidates(cam, hrp.Position, currentTarget.model)
	local nextCand =
		LockOnLogic.selectSwitchCandidate(currentTarget.id, curU, curV, candidates, dirSign)
	if nextCand and byId[nextCand.id] then
		lastSwitchAt = now
		engageTarget(byId[nextCand.id], true)
		return true
	end
	lastSwitchAt = now - CFG.SWITCH_COOLDOWN_SEC + 0.10
	return false
end

function LockOnController.toggleLockOn()
	if suppressed then
		return
	end
	if currentTarget ~= nil then
		LockOnController.clearLockOn("ManualToggle")
		return
	end
	tryAcquireOrAutoSwitch(nil, "NoCandidate")
end

function LockOnController.setLockSuppressed(isSuppressed: boolean)
	suppressed = isSuppressed == true
	if suppressed and currentTarget ~= nil then
		LockOnController.clearLockOn("Suppressed")
	end
end

function LockOnController.isLockedOn(): boolean
	return currentTarget ~= nil and not suppressed
end

function LockOnController.getLockedTarget(): (Model?, BasePart?, Vector3?)
	if not currentTarget or suppressed then
		return nil, nil, nil
	end
	local pos = getAnchorWorldPos(currentTarget)
	if not pos then
		return nil, nil, nil
	end
	return currentTarget.model, currentTarget.part, pos
end

function LockOnController.getDebugState(): { [string]: any }
	local cam = workspace.CurrentCamera
	local _, hum = getRootAndHum()
	return {
		active = currentTarget ~= nil,
		targetName = if currentTarget then currentTarget.model.Name else nil,
		isBoss = if currentTarget then currentTarget.isBoss else false,
		obstructedSec = graceState.obstructedSec,
		offScreenSec = graceState.offScreenSec,
		switchCount = switchCount,
		lastBreakReason = lastBreakReason,
		cameraType = if cam then cam.CameraType.Name else "None",
		autoRotate = if hum then hum.AutoRotate else true,
	}
end

local function applyCameraWallCollision(
	pivotPos: Vector3,
	desiredPos: Vector3,
	targetModel: Model,
	dt: number
): Vector3
	local delta = desiredPos - pivotPos
	local fullDist = delta.Magnitude
	if fullDist < 0.25 then
		return desiredPos
	end
	local dir = delta / fullDist
	local excluded: { Instance } = { targetModel }
	if localPlayer.Character then
		table.insert(excluded, localPlayer.Character)
	end
	local followers = workspace:FindFirstChild("LocalActiveFollowers")
	if followers then
		table.insert(excluded, followers)
	end

	local safeDist = fullDist
	for _ = 1, 5 do
		wallRayParams.FilterDescendantsInstances = excluded
		local res = workspace:Spherecast(pivotPos, CFG.WALL_SPHERE_RADIUS, delta, wallRayParams)
		if not res or not res.Instance then
			break
		end
		if isIgnorableGeometry(res.Instance) then
			table.insert(excluded, res.Instance)
		else
			safeDist = math.clamp(res.Distance - CFG.WALL_PULL_MARGIN, CFG.MIN_WALL_DIST, fullDist)
			break
		end
	end
	local curDist = smoothedWallDist or safeDist
	local speed = if safeDist < curDist then CFG.WALL_IN_SPEED else CFG.WALL_OUT_SPEED
	local nextDist = curDist + (safeDist - curDist) * (1 - math.exp(-speed * dt))
	smoothedWallDist = nextDist
	return pivotPos + dir * nextDist
end

local function stepCharacterStrafeYaw(hrp: BasePart, hum: Humanoid, targetPos: Vector3, dt: number)
	hum.AutoRotate = false
	local flatTarget = Vector3.new(targetPos.X, hrp.Position.Y, targetPos.Z)
	if (flatTarget - hrp.Position).Magnitude < 0.75 then
		return
	end
	local desiredCF = CFrame.lookAt(hrp.Position, flatTarget)
	local turnAlpha = 1 - math.exp(-CFG.CHAR_TURN_RATE * dt)
	hrp.CFrame = CFrame.new(hrp.Position) * hrp.CFrame.Rotation:Lerp(desiredCF.Rotation, turnAlpha)
end

local function refreshDirectionalChevrons(
	cam: Camera,
	playerPos: Vector3,
	curPos: Vector3,
	now: number
)
	if now < lastChevronCheckAt + 0.16 or not currentTarget then
		return
	end
	lastChevronCheckAt = now
	local vp = cam.ViewportSize
	local vpPos = cam:WorldToViewportPoint(curPos)
	local curU = vpPos.X / math.max(1, vp.X)
	local curV = vpPos.Y / math.max(1, vp.Y)
	local cands = collectVisibleCandidates(cam, playerPos, currentTarget.model)
	hasLeftCandidate = LockOnLogic.hasDirectionalCandidate(currentTarget.id, curU, curV, cands, -1)
	hasRightCandidate = LockOnLogic.hasDirectionalCandidate(currentTarget.id, curU, curV, cands, 1)
end

local function validateLockedTarget(
	cam: Camera,
	hrp: BasePart,
	target: LockedEntry,
	stepDt: number
): Vector3?
	if not isEntryAliveAndEligible(target) then
		tryAcquireOrAutoSwitch(target.model, "TargetDeadOrIneligible")
		return nil
	end
	local targetPos = getAnchorWorldPos(target)
	if not targetPos then
		tryAcquireOrAutoSwitch(target.model, "TargetDestroyed")
		return nil
	end
	if (targetPos - hrp.Position).Magnitude > LockOnLogic.getBreakRange(target.isBoss) then
		tryAcquireOrAutoSwitch(target.model, "OutOfRange")
		return nil
	end
	local vp = cam.ViewportSize
	local vpPos, onScreen = cam:WorldToViewportPoint(targetPos)
	local u = vpPos.X / math.max(1, vp.X)
	local v = vpPos.Y / math.max(1, vp.Y)
	local isOffScreen = not onScreen
		or not LockOnLogic.isWithinViewport(u, v, vpPos.Z, CFG.TRACK_VIEWPORT_MARGIN)
	local isObstructed = not hasCameraLineOfSight(cam.CFrame.Position, targetPos, target.model)
	if LockOnLogic.stepGraceTimers(graceState, isObstructed, isOffScreen, stepDt) == "Break" then
		local reason = if graceState.obstructedSec >= CFG.OBSTRUCTION_GRACE_SEC
			then "ObstructionTimeout"
			else "OffScreenTimeout"
		tryAcquireOrAutoSwitch(target.model, reason)
		return nil
	end
	return targetPos
end

local function applyLockedCameraFrame(
	cam: Camera,
	hrp: BasePart,
	target: LockedEntry,
	targetPos: Vector3,
	stepDt: number,
	now: number
)
	if cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Scriptable
	end
	local frame = LockOnLogic.computeLockedCameraFrame({
		playerX = hrp.Position.X,
		playerY = hrp.Position.Y,
		playerZ = hrp.Position.Z,
		targetX = targetPos.X,
		targetY = targetPos.Y,
		targetZ = targetPos.Z,
		prevFwdX = lastStableFwdX,
		prevFwdZ = lastStableFwdZ,
		isBoss = target.isBoss,
	})
	lastStableFwdX = frame.fwdX
	lastStableFwdZ = frame.fwdZ

	local rawCamPos = Vector3.new(frame.camX, frame.camY, frame.camZ)
	local rawLookDir = Vector3.new(frame.lookDirX, frame.lookDirY, frame.lookDirZ)
	local posAlpha = 1 - math.exp(-CFG.CAM_POS_DAMPING * stepDt)
	local lookRate = if now < switchBoostUntil
		then CFG.CAM_SWITCH_LOOK_DAMPING
		else CFG.CAM_LOOK_DAMPING
	local lookAlpha = 1 - math.exp(-lookRate * stepDt)

	local nextCamPos = (smoothedCamPos or rawCamPos):Lerp(rawCamPos, posAlpha)
	smoothedCamPos = nextCamPos
	local blendedDir = (smoothedLookDir or rawLookDir):Lerp(rawLookDir, lookAlpha)
	local nextLookDir = if blendedDir.Magnitude > 1e-4 then blendedDir.Unit else rawLookDir
	smoothedLookDir = nextLookDir

	local pivotPos = hrp.Position + Vector3.new(0, CFG.PLAYER_ANCHOR_HEIGHT, 0)
	local safeCamPos = applyCameraWallCollision(pivotPos, nextCamPos, target.model, stepDt)
	cam.CFrame = CFrame.lookAt(safeCamPos, safeCamPos + nextLookDir * 24)
end

local function stepLockedCamera(dt: number)
	local stepDt = math.min(dt, 0.05)
	if not currentTarget then
		return
	end
	mouseAccumX = select(1, LockOnLogic.stepMouseAccumulator(mouseAccumX, 0, 0, stepDt))

	local cam = workspace.CurrentCamera
	local hrp, hum = getRootAndHum()
	if not cam or not hrp or not hum or hum.Health <= 0 then
		LockOnController.clearLockOn("PlayerInvalid")
		return
	end
	local target = currentTarget
	local targetPos = validateLockedTarget(cam, hrp, target, stepDt)
	if not targetPos then
		return
	end
	local now = os.clock()
	applyLockedCameraFrame(cam, hrp, target, targetPos, stepDt, now)
	stepCharacterStrafeYaw(hrp, hum, targetPos, stepDt)
	refreshDirectionalChevrons(cam, hrp.Position, targetPos, now)
	updateReticleVisual(cam, targetPos, now)
end

local function handleMouseSwitchInput(input: InputObject)
	local dx = input.Delta.X
	local dy = input.Delta.Y
	if dx == 0 and dy == 0 and lastMousePos ~= nil then
		dx = input.Position.X - lastMousePos.X
		dy = input.Position.Y - lastMousePos.Y
	end
	if UserInputService.MouseBehavior == Enum.MouseBehavior.Default then
		lastMousePos = Vector2.new(input.Position.X, input.Position.Y)
	else
		lastMousePos = nil
	end
	local switchDir: number
	mouseAccumX, switchDir = LockOnLogic.stepMouseAccumulator(mouseAccumX, dx, dy, 0)
	if switchDir ~= 0 then
		LockOnController.switchTarget(switchDir)
	end
end

local function bindInputs()
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseButton3
			or input.KeyCode == Enum.KeyCode.F
			or input.KeyCode == Enum.KeyCode.ButtonR3
		then
			LockOnController.toggleLockOn()
		elseif input.UserInputType == Enum.UserInputType.Touch and currentTarget ~= nil then
			local cam = workspace.CurrentCamera
			local vp = if cam then cam.ViewportSize else Vector2.new(1280, 720)
			if
				activeSwipeTouch == nil
				and not LockOnLogic.isTouchInThumbstickZone(
					input.Position.X,
					input.Position.Y,
					vp.X,
					vp.Y
				)
			then
				activeSwipeTouch = input
				swipeStartPos = Vector2.new(input.Position.X, input.Position.Y)
				swipeConsumed = false
			end
		end
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject, gameProcessed: boolean)
		if currentTarget == nil then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement and not gameProcessed then
			handleMouseSwitchInput(input)
		elseif
			input.UserInputType == Enum.UserInputType.Touch
			and activeSwipeTouch == input
			and not swipeConsumed
		then
			local swipeDir = LockOnLogic.evaluateTouchSwipe(
				input.Position.X - swipeStartPos.X,
				input.Position.Y - swipeStartPos.Y
			)
			if swipeDir ~= 0 then
				swipeConsumed = true
				LockOnController.switchTarget(swipeDir)
			end
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			local stickDir: number
			stickDir, stickArmed =
				LockOnLogic.evaluateStickSwitch(input.Position.X, input.Position.Y, stickArmed)
			if stickDir ~= 0 then
				LockOnController.switchTarget(stickDir)
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if activeSwipeTouch == input then
			activeSwipeTouch = nil
			swipeConsumed = false
		end
	end)
end

function LockOnController.start()
	if started then
		return
	end
	started = true
	buildReticleUi()
	syncLockIndicators(false)
	bindInputs()

	localPlayer.CharacterAdded:Connect(function()
		LockOnController.clearLockOn("Respawn")
	end)
	localPlayer:GetAttributeChangedSignal("Zone"):Connect(function()
		local zone = tostring(localPlayer:GetAttribute("Zone") or "Hub")
		if zone == "Hub" or zone == "VaultHeist" then
			LockOnController.clearLockOn("ZoneChanged")
		end
	end)

	RunService:BindToRenderStep(
		"BallBrawl_LockOnCamera",
		Enum.RenderPriority.Camera.Value + 2,
		stepLockedCamera
	)
end

return LockOnController
