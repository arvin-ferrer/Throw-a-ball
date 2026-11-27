--!strict
--[[
	CombatJuiceController.luau
	Client 3-second mute-clip combat polish:
	- Floating 3D Damage, CRIT! (gold starburst), +Coins, and +Gems BillboardGui popups
	- Subtle toggleable micro camera-shake (trauma decay) + impact hit-flash & dash burst punch
	- Corner Kill / Egg Claim / Win-Streak feed (max 3 entries, 4s auto-fade)
	- Overhead 3D Win-Streak Halo / Flame Crown VFX on players with winStreak >= 2
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatJuiceLogic = require(Shared.Utils.CombatJuiceLogic)
local Remotes = require(Shared.Net.Remotes)

local Theme = require(script.Parent.Parent.UI.Theme)

local CombatJuiceController = {}

local MAX_ACTIVE_POPUPS = 24
local CAMERA_SHAKE_RANGE = 95
local HALO_CULL_RANGE = 160
local FLASH_SEARCH_RADIUS = 10

type ActiveHalo = {
	model: Model,
	motor: Motor6D,
	streak: number,
	tier: number,
}

local localPlayer = Players.LocalPlayer
local traumaState = CombatJuiceLogic.createTraumaState(true)
local activePopupCount = 0
local lastDashPulseAt = 0
local flashBusy: { [Instance]: boolean } = {}
local streakByUser: { [number]: number } = {}
local activeHalos: { [Player]: ActiveHalo } = {}
local feedEntries: { CombatJuiceLogic.FeedEntry } = {}
local nextFeedId = 1
local feedGui: ScreenGui? = nil
local feedContainer: Frame? = nil
local feedRowsById: { [number]: Frame } = {}
local started = false

local function toColor3(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1] or 255, rgb[2] or 255, rgb[3] or 255)
end

local function waitRemote(folder: Folder, remoteName: string): RemoteEvent?
	local found = folder:FindFirstChild(remoteName) or folder:WaitForChild(remoteName, 20)
	return if found and found:IsA("RemoteEvent") then found else nil
end

local function addStarburstRays(host: Frame, color: Color3)
	for idx, deg in ipairs({ 0, 45 }) do
		local star = Instance.new("Frame")
		star.Name = `Starburst_{idx}`
		star.AnchorPoint = Vector2.new(0.5, 0.5)
		star.Position = UDim2.fromScale(0.5, 0.5)
		star.Size = UDim2.fromScale(0.74, 0.74)
		star.Rotation = deg
		star.BackgroundColor3 = color
		star.BackgroundTransparency = 0.22
		star.BorderSizePixel = 0
		star.ZIndex = 1
		star.Parent = host
		Theme.addCorner(star, 6)
		Theme.addStroke(star, Color3.fromRGB(255, 250, 210), 1.8, 0.15)
	end
end

local function tweenPopupLife(
	anchor: Part,
	root: Frame,
	scaleObj: UIScale,
	lbl: TextLabel,
	spec: CombatJuiceLogic.PopupSpec
)
	TweenService:Create(
		scaleObj,
		TweenInfo.new(0.11, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1.18 }
	):Play()
	task.delay(0.12, function()
		if scaleObj.Parent then
			TweenService:Create(
				scaleObj,
				TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Scale = 1.0 }
			):Play()
		end
	end)
	TweenService:Create(
		anchor,
		TweenInfo.new(spec.duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = anchor.CFrame + Vector3.new(0, spec.riseStuds, 0) }
	):Play()
	task.delay(spec.duration * 0.45, function()
		if not lbl.Parent then
			return
		end
		local fadeInfo =
			TweenInfo.new(spec.duration * 0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(lbl, fadeInfo, { TextTransparency = 1, TextStrokeTransparency = 1 })
			:Play()
		for _, desc in ipairs(root:GetDescendants()) do
			if desc:IsA("Frame") then
				TweenService:Create(desc, fadeInfo, { BackgroundTransparency = 1 }):Play()
			elseif desc:IsA("UIStroke") then
				TweenService:Create(desc, fadeInfo, { Transparency = 1 }):Play()
			end
		end
	end)
end

local function createPopupLabel(root: Frame, spec: CombatJuiceLogic.PopupSpec): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.ZIndex = 3
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextScaled = true
	lbl.TextColor3 = toColor3(spec.color)
	lbl.TextStrokeColor3 = toColor3(spec.strokeColor)
	lbl.TextStrokeTransparency = 0.1
	lbl.Text = spec.text
	lbl.AutoLocalize = false
	lbl.Parent = root
	return lbl
end

local function createPopupBillboard(
	worldPos: Vector3,
	spec: CombatJuiceLogic.PopupSpec
): (Part, Frame, UIScale, TextLabel)
	local jitterX = (math.random() - 0.5) * 1.4
	local jitterZ = (math.random() - 0.5) * 1.4
	local anchor = Instance.new("Part")
	anchor.Name = "CombatJuicePopup"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(worldPos + Vector3.new(jitterX, 2.2, jitterZ))
	anchor.Parent = workspace

	local bb = Instance.new("BillboardGui")
	bb.Adornee = anchor
	bb.Size = UDim2.fromOffset(math.floor(156 * spec.scale), math.floor(54 * spec.scale))
	bb.AlwaysOnTop = true
	bb.MaxDistance = 160
	bb.Parent = anchor

	local root = Instance.new("Frame")
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = bb

	local scaleObj = Instance.new("UIScale")
	scaleObj.Scale = 0.35
	scaleObj.Parent = root
	if spec.isStarburst then
		addStarburstRays(root, toColor3(spec.color))
	end
	return anchor, root, scaleObj, createPopupLabel(root, spec)
end

local function spawnFloatingPopup(worldPos: Vector3, spec: CombatJuiceLogic.PopupSpec)
	if activePopupCount >= MAX_ACTIVE_POPUPS then
		return
	end
	activePopupCount += 1
	local anchor, root, scaleObj, lbl = createPopupBillboard(worldPos, spec)
	tweenPopupLife(anchor, root, scaleObj, lbl, spec)
	task.delay(spec.duration + 0.08, function()
		activePopupCount = math.max(0, activePopupCount - 1)
		if anchor.Parent then
			anchor:Destroy()
		end
	end)
end

function CombatJuiceController.flashInstance(target: Instance, color: Color3?)
	if not target.Parent or flashBusy[target] then
		return
	end
	local model = if target:IsA("Model") then target else target:FindFirstAncestorOfClass("Model")
	local adornee: Instance = if model
			and (model:GetAttribute("EntityKind") ~= nil or Players:GetPlayerFromCharacter(model))
		then model
		else target
	if flashBusy[adornee] then
		return
	end
	flashBusy[adornee] = true
	local hl = Instance.new("Highlight")
	hl.Name = "JuiceHitFlash"
	hl.FillColor = color or Color3.fromRGB(255, 244, 180)
	hl.OutlineColor = Color3.fromRGB(255, 255, 255)
	hl.FillTransparency = 0.28
	hl.OutlineTransparency = 0.05
	hl.Adornee = adornee
	hl.Parent = adornee
	task.delay(0.13, function()
		if hl.Parent then
			hl:Destroy()
		end
		flashBusy[adornee] = nil
	end)
end

local function isFlashableEntity(inst: Instance): BasePart?
	if inst:IsA("Model") and inst.PrimaryPart and inst:GetAttribute("EntityKind") ~= nil then
		return inst.PrimaryPart
	end
	if inst:IsA("BasePart") then
		local tk = inst:GetAttribute("TargetKind")
		if tk == "Static" or tk == "MovingGold" then
			return inst
		end
	end
	return nil
end

local function flashNearestImpactTarget(worldPos: Vector3, color: Color3)
	local bestInst: Instance? = nil
	local bestDist = FLASH_SEARCH_RADIUS
	local map = workspace:FindFirstChild("BallBrawl_Map_v2")
	if map then
		for _, desc in ipairs(map:GetDescendants()) do
			local part = isFlashableEntity(desc)
			if part then
				local dist = (part.Position - worldPos).Magnitude
				if dist < bestDist then
					bestDist = dist
					bestInst = desc
				end
			end
		end
	end
	for _, plr in ipairs(Players:GetPlayers()) do
		local hrp = if plr.Character then plr.Character:FindFirstChild("HumanoidRootPart") else nil
		if hrp and hrp:IsA("BasePart") then
			local dist = (hrp.Position - worldPos).Magnitude
			if dist < bestDist and plr.Character then
				bestDist = dist
				bestInst = plr.Character
			end
		end
	end
	if bestInst then
		CombatJuiceController.flashInstance(bestInst, color)
	end
end

local function applyFeedResponsiveLayout()
	if not feedGui or not feedContainer then
		return
	end
	local metrics = Theme.getLayoutMetrics()
	local width = if metrics.isCompact then 176 else 248
	local xOff = if metrics.isCompact then -10 else -14
	local yOff = if metrics.isCompact then 120 else 142
	feedContainer.AnchorPoint = Vector2.new(1, 0)
	feedContainer.Position = UDim2.new(1, xOff, 0, yOff)
	feedContainer.Size = UDim2.fromOffset(width, 76)
	local list = feedContainer:FindFirstChildOfClass("UIListLayout")
	if list then
		list.Padding = UDim.new(0, if metrics.isCompact then 3 else 5)
		list.HorizontalAlignment = Enum.HorizontalAlignment.Right
	end
end

local function buildFeedUi()
	local gui = Theme.createScreenGui("BallBrawl_CombatJuice", 16)
	gui.IgnoreGuiInset = false
	feedGui = gui

	local box = Instance.new("Frame")
	box.Name = "CombatFeed"
	box.AnchorPoint = Vector2.new(1, 0)
	box.BackgroundTransparency = 1
	box.Active = false
	box.ClipsDescendants = false
	box.Parent = gui
	feedContainer = box

	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Right
	list.Parent = box

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyFeedResponsiveLayout)
	applyFeedResponsiveLayout()
end

local function makeFeedRow(
	parent: Frame,
	entry: CombatJuiceLogic.FeedEntry,
	order: number,
	rowH: number
): Frame
	local pill = Theme.makeFrame(
		parent,
		`Feed_{entry.id}`,
		UDim2.new(1, 0, 0, rowH),
		UDim2.fromOffset(0, 0),
		Theme.Colors.Panel,
		999
	)
	pill.LayoutOrder = order
	pill.Active = false
	pill.BackgroundTransparency = 0.08
	Theme.addStroke(pill, toColor3(entry.accent), 2, 0.05)

	local lbl = Theme.makeLabel(
		pill,
		"Msg",
		entry.text,
		UDim2.new(1, -14, 1, 0),
		UDim2.fromOffset(7, 0),
		12,
		toColor3(entry.accent),
		true
	)
	lbl.TextScaled = true
	lbl.TextTruncate = Enum.TextTruncate.AtEnd
	lbl.Active = false
	Theme.addTextStroke(lbl, 1.5)
	local tc = Instance.new("UITextSizeConstraint")
	tc.MinTextSize = 8
	tc.MaxTextSize = 12
	tc.Parent = lbl
	return pill
end

local function fadeAndDestroyRow(row: Frame)
	local fadeInfo = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(row, fadeInfo, { BackgroundTransparency = 1 }):Play()
	for _, desc in ipairs(row:GetDescendants()) do
		if desc:IsA("TextLabel") then
			TweenService
				:Create(desc, fadeInfo, { TextTransparency = 1, TextStrokeTransparency = 1 })
				:Play()
		elseif desc:IsA("UIStroke") then
			TweenService:Create(desc, fadeInfo, { Transparency = 1 }):Play()
		end
	end
	task.delay(0.3, function()
		if row.Parent then
			row:Destroy()
		end
	end)
end

local function syncFeedRows()
	if not feedContainer then
		return
	end
	local activeById: { [number]: CombatJuiceLogic.FeedEntry } = {}
	for _, entry in ipairs(feedEntries) do
		activeById[entry.id] = entry
	end
	for id, row in pairs(feedRowsById) do
		if not activeById[id] then
			feedRowsById[id] = nil
			fadeAndDestroyRow(row)
		end
	end
	local rowH = if Theme.getLayoutMetrics().isCompact then 19 else 24
	for idx, entry in ipairs(feedEntries) do
		local existing = feedRowsById[entry.id]
		if existing then
			existing.LayoutOrder = idx
		else
			feedRowsById[entry.id] = makeFeedRow(feedContainer, entry, idx, rowH)
		end
	end
end

local function pushFeed(text: string, accent: { number }?)
	local now = os.clock()
	nextFeedId = CombatJuiceLogic.pushFeedEntry(feedEntries, nextFeedId, text, accent, now)
	syncFeedRows()
end

local function createHaloPart(
	parent: Instance,
	name: string,
	size: Vector3,
	color: Color3,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Shape = shape or Enum.PartType.Block
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Massless = true
	p.Parent = parent
	return p
end

local function weldToPivot(pivot: BasePart, part: BasePart, offset: CFrame)
	part.CFrame = pivot.CFrame * offset
	local wc = Instance.new("WeldConstraint")
	wc.Part0 = pivot
	wc.Part1 = part
	wc.Parent = part
end

local function attachHaloCrownDecor(model: Model, pivot: BasePart, tier: CombatJuiceLogic.HaloTier)
	local pCol = toColor3(tier.primaryColor)
	local sCol = toColor3(tier.secondaryColor)
	local ring = createHaloPart(
		model,
		"HaloRing",
		Vector3.new(0.18, 2.4 * tier.ringScale, 2.4 * tier.ringScale),
		pCol,
		Enum.PartType.Cylinder
	)
	ring.Transparency = 0.18
	weldToPivot(pivot, ring, CFrame.Angles(0, 0, math.rad(90)))

	if tier.showCrownSpikes then
		local count = if tier.tier >= 3 then 6 else 4
		local rad = 1.12 * tier.ringScale
		for i = 1, count do
			local theta = (i / count) * math.pi * 2
			local spike = createHaloPart(
				model,
				`CrownSpike_{i}`,
				Vector3.new(0.22, 0.56, 0.22),
				if i % 2 == 0 then sCol else pCol,
				Enum.PartType.Block
			)
			local pos = Vector3.new(math.cos(theta) * rad, 0.22, math.sin(theta) * rad)
			weldToPivot(pivot, spike, CFrame.new(pos) * CFrame.Angles(0, -theta, math.rad(-14)))
		end
	end

	local pe = Instance.new("ParticleEmitter")
	pe.Rate = tier.flameRate
	pe.Speed = NumberRange.new(1.8, 3.8)
	pe.Lifetime = NumberRange.new(0.45, 0.85)
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.42 * tier.ringScale),
		NumberSequenceKeypoint.new(1, 0),
	})
	pe.Color = ColorSequence.new(pCol, sCol)
	pe.LightEmission = 1
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Parent = pivot
end

local function destroyPlayerHalo(player: Player)
	local entry = activeHalos[player]
	if entry then
		activeHalos[player] = nil
		if entry.motor and entry.motor.Parent then
			entry.motor:Destroy()
		end
		if entry.model.Parent then
			entry.model:Destroy()
		end
	end
end

local function getEffectiveStreak(player: Player): number
	local cached = streakByUser[player.UserId]
	if cached ~= nil then
		return cached
	end
	return tonumber(player:GetAttribute("WinStreak"))
		or tonumber(player:GetAttribute("winStreak"))
		or 0
end

local function refreshPlayerHalo(player: Player)
	local initialStreak = getEffectiveStreak(player)
	if not CombatJuiceLogic.getStreakHaloTier(initialStreak) then
		destroyPlayerHalo(player)
		return
	end
	local char = player.Character
	local head = if char then char:WaitForChild("Head", 5) else nil
	if not char or not char.Parent or not head or not head:IsA("BasePart") then
		return
	end
	local streak = getEffectiveStreak(player)
	local tier = CombatJuiceLogic.getStreakHaloTier(streak)
	if not tier then
		destroyPlayerHalo(player)
		return
	end
	local existing = activeHalos[player]
	if existing and existing.model.Parent == char and existing.tier == tier.tier then
		existing.streak = streak
		return
	end
	destroyPlayerHalo(player)

	local model = Instance.new("Model")
	model.Name = "WinStreakHalo"
	local pivot =
		createHaloPart(model, "Pivot", Vector3.new(0.2, 0.2, 0.2), toColor3(tier.primaryColor))
	pivot.Transparency = 1
	pivot.CFrame = head.CFrame * CFrame.new(0, 1.55, 0)
	model.PrimaryPart = pivot

	local motor = Instance.new("Motor6D")
	motor.Name = "StreakHaloMotor"
	motor.Part0 = head
	motor.Part1 = pivot
	motor.C0 = CFrame.new(0, 1.55, 0)
	motor.C1 = CFrame.new()
	motor.Parent = head

	attachHaloCrownDecor(model, pivot, tier)
	model.Parent = char
	activeHalos[player] = { model = model, motor = motor, streak = streak, tier = tier.tier }
end

local function applyStreakFromEvent(payload: any)
	local streak = tonumber(payload.streak) or 0
	local targetPlr: Player? = nil
	if type(payload.userId) == "number" then
		targetPlr = Players:GetPlayerByUserId(payload.userId)
	end
	if not targetPlr and type(payload.killerName) == "string" then
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr.Name == payload.killerName or plr.DisplayName == payload.killerName then
				targetPlr = plr
				break
			end
		end
	end
	if targetPlr then
		streakByUser[targetPlr.UserId] = streak
		task.spawn(refreshPlayerHalo, targetPlr)
	end
end

local function isNearLocalCamera(worldPos: Vector3?): boolean
	if not worldPos then
		return true
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return true
	end
	return (cam.CFrame.Position - worldPos).Magnitude <= CAMERA_SHAKE_RANGE
end

local function resolvePopupPosition(kind: string, worldPos: Vector3?): Vector3?
	if worldPos then
		return worldPos
	end
	if kind == "Coins" or kind == "Coin" or kind == "Gems" or kind == "Gem" then
		local char = localPlayer.Character
		local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
		if hrp and hrp:IsA("BasePart") then
			return hrp.Position + Vector3.new(0, 1.5, 0)
		end
	end
	return nil
end

function CombatJuiceController.handleJuiceEvent(payload: any)
	if type(payload) ~= "table" or type(payload.kind) ~= "string" then
		return
	end
	local kind = payload.kind
	local worldPos = if typeof(payload.worldPos) == "Vector3" then payload.worldPos else nil
	local baseDmg = tonumber(localPlayer:GetAttribute("BallDamage"))
	local critThreshold = CombatJuiceLogic.computeCritThreshold(baseDmg)
	local isCrit = CombatJuiceLogic.isCriticalHit(kind, payload.amount, critThreshold)

	if kind == "StreakUpdate" then
		applyStreakFromEvent(payload)
	end

	local feedText = CombatJuiceLogic.formatFeedEntryText(payload)
	if feedText then
		pushFeed(feedText, payload.accent)
	end

	local popupPos = resolvePopupPosition(kind, worldPos)
	if popupPos and kind ~= "StreakUpdate" then
		local spec = CombatJuiceLogic.formatPopup(payload, critThreshold)
		spawnFloatingPopup(popupPos, spec)
		if kind == "Damage" or kind == "Crit" or kind == "BossHit" then
			local targetInst = if typeof(payload.hitTarget) == "Instance"
				then payload.hitTarget
				else nil
			if targetInst then
				CombatJuiceController.flashInstance(targetInst, toColor3(spec.color))
			elseif payload.killed ~= true and isNearLocalCamera(popupPos) then
				flashNearestImpactTarget(popupPos, toColor3(spec.color))
			end
		end
	end

	if isNearLocalCamera(worldPos) then
		local impulseKind = if isCrit then "Crit" else kind
		local impulse = CombatJuiceLogic.getTraumaImpulseForEvent(impulseKind)
		if impulse > 0 then
			CombatJuiceController.addTrauma(impulse)
		end
	end
end

local function bindCharacterDashWatch(char: Model)
	local hrp = char:WaitForChild("HumanoidRootPart", 10)
	if not hrp or not hrp:IsA("BasePart") then
		return
	end
	hrp.ChildAdded:Connect(function(child: Instance)
		if child:IsA("LinearVelocity") then
			local now = os.clock()
			if now - lastDashPulseAt >= 0.35 then
				lastDashPulseAt = now
				CombatJuiceController.addTrauma(CombatJuiceLogic.getTraumaImpulseForEvent("Dash"))
			end
		end
	end)
end

local function watchPlayerStreak(player: Player)
	local function onAttrChanged(attrName: string)
		streakByUser[player.UserId] = tonumber(player:GetAttribute(attrName)) or 0
		task.spawn(refreshPlayerHalo, player)
	end
	player:GetAttributeChangedSignal("WinStreak"):Connect(function()
		onAttrChanged("WinStreak")
	end)
	player:GetAttributeChangedSignal("winStreak"):Connect(function()
		onAttrChanged("winStreak")
	end)
	if player.Character then
		task.spawn(refreshPlayerHalo, player)
		if player == localPlayer then
			task.spawn(bindCharacterDashWatch, player.Character)
		end
	end
	player.CharacterAdded:Connect(function(char: Model)
		task.spawn(refreshPlayerHalo, player)
		if player == localPlayer then
			task.spawn(bindCharacterDashWatch, char)
		end
	end)
end

local function stepCameraAndHalos(dt: number)
	local now = os.clock()
	if CombatJuiceLogic.pruneFeedEntries(feedEntries, now) then
		syncFeedRows()
	end
	local cam = workspace.CurrentCamera
	if cam then
		local sample = CombatJuiceLogic.stepTrauma(traumaState, dt, now)
		if
			sample.intensity > 0
			and traumaState.enabled
			and not GuiService.ReducedMotionEnabled
			and cam.CameraType ~= Enum.CameraType.Scriptable
		then
			cam.CFrame = cam.CFrame
				* CFrame.new(sample.offsetX, sample.offsetY, 0)
				* CFrame.Angles(0, 0, sample.rollRad)
		end
		local camPos = cam.CFrame.Position
		for plr, halo in pairs(activeHalos) do
			local root = halo.model.PrimaryPart
			if not halo.model.Parent or not root then
				activeHalos[plr] = nil
			elseif (root.Position - camPos).Magnitude <= HALO_CULL_RANGE then
				halo.motor.Transform = CFrame.Angles(0, now * (1.8 + halo.tier * 0.6), 0)
			end
		end
	end
end

function CombatJuiceController.setShakeEnabled(enabled: boolean)
	traumaState.enabled = enabled == true
	if not traumaState.enabled then
		traumaState.trauma = 0
	end
	localPlayer:SetAttribute("CameraShakeEnabled", traumaState.enabled)
end

function CombatJuiceController.isShakeEnabled(): boolean
	return traumaState.enabled
end

function CombatJuiceController.addTrauma(amount: number)
	if GuiService.ReducedMotionEnabled then
		return
	end
	CombatJuiceLogic.addTrauma(traumaState, amount)
end

function CombatJuiceController.getActiveFeedCount(): number
	return #feedEntries
end

function CombatJuiceController.start()
	if started then
		return
	end
	started = true
	local initShake = localPlayer:GetAttribute("CameraShakeEnabled")
	if type(initShake) == "boolean" then
		traumaState.enabled = initShake
	else
		localPlayer:SetAttribute("CameraShakeEnabled", traumaState.enabled)
	end

	buildFeedUi()
	for _, plr in ipairs(Players:GetPlayers()) do
		watchPlayerStreak(plr)
	end
	Players.PlayerAdded:Connect(watchPlayerStreak)
	Players.PlayerRemoving:Connect(function(plr: Player)
		destroyPlayerHalo(plr)
		streakByUser[plr.UserId] = nil
	end)

	RunService:BindToRenderStep(
		"BallBrawl_CombatJuice",
		Enum.RenderPriority.Camera.Value + 5,
		stepCameraAndHalos
	)

	task.spawn(function()
		local bundle = Remotes.waitClient()
		local event = waitRemote(bundle.Folder, "CombatJuiceEvent")
		if event then
			event.OnClientEvent:Connect(CombatJuiceController.handleJuiceEvent)
		end
	end)
end

return CombatJuiceController
