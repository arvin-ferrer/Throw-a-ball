--!strict
--[[
	BallThrowController.luau
	Client combat & movement controller (GDD §5):
	  - Stepping onto own TrainingPad anchors smoothly into stationary shooting stance;
	    jumping or moving off cancels immediately.
	  - Outside TrainingPad: 18 walk / 24 sprint + 0.35s Dash (2.5s cooldown) with coyote/buffer.
	  - Client-side predicted arc & visual ball + hit-marker while sending ONLY aim origin/direction.
	  - Mobile touch controls (Throw/Hold-to-Aim + Dash) + soft magnetic aim assist (mild in PvP).
]]

export type Vec3Like = {
	X: number,
	Y: number,
	Z: number,
}

export type ThrowPayload = {
	origin: Vec3Like,
	direction: Vec3Like,
	onTrainingPad: boolean,
}

export type ThrowResult = {
	fired: boolean,
	payload: ThrowPayload?,
	assistedTargetId: string?,
}

export type StateConfig = {
	net: any,
	projectileArc: any?,
	throwCooldown: number?,
}

export type CombatState = {
	isOnTrainingPad: (self: CombatState) -> boolean,
	getActivePadId: (self: CombatState) -> string?,
	enterTrainingPad: (self: CombatState, padId: string) -> boolean,
	cancelTrainingPad: (self: CombatState, reason: string?) -> boolean,
	handleMoveIntent: (self: CombatState, moveMagnitude: number) -> boolean,
	setSprinting: (self: CombatState, sprinting: boolean) -> (),
	getTargetWalkSpeed: (self: CombatState) -> number,
	requestDash: (self: CombatState) -> boolean,
	isDashing: (self: CombatState) -> boolean,
	getDashCooldownRemaining: (self: CombatState) -> number,
	setArenaPhase: (self: CombatState, phase: string) -> (),
	getAimAssistMode: (self: CombatState) -> string,
	performThrow: (
		self: CombatState,
		origin: Vec3Like,
		rawDirection: Vec3Like,
		candidates: { any },
		useAimAssist: boolean
	) -> ThrowResult,
	step: (self: CombatState, dt: number, isGrounded: boolean) -> (),
}

type InternalState = CombatState & {
	_net: any,
	_projectileArc: any?,
	_isOnPad: boolean,
	_activePadId: string?,
	_padEntryGrace: number,
	_padReentryLockout: number,
	_sprinting: boolean,
	_dashActiveRemaining: number,
	_dashCooldownRemaining: number,
	_coyoteRemaining: number,
	_dashBufferRemaining: number,
	_throwCooldownDuration: number,
	_throwCooldownRemaining: number,
	_arenaPhase: string,
}

type ActiveBall = {
	part: BasePart,
	origin: Vec3Like,
	direction: Vec3Like,
	elapsed: number,
	maxDuration: number,
	lastPos: Vector3,
}

local WALK_SPEED = 18
local SPRINT_SPEED = 24
local DASH_DURATION = 0.35
local DASH_COOLDOWN = 2.5
local DASH_SPEED = 56
local COYOTE_WINDOW = 0.14
local DASH_BUFFER_WINDOW = 0.15
local PAD_ENTRY_SETTLE = 0.15
local PAD_REENTRY_LOCKOUT = 0.45
local DEFAULT_THROW_COOLDOWN = 0.35
local PREVIEW_DOT_COUNT = 14

local BallThrowController = {
	Name = "BallThrowController",
	Priority = 50,
	Constants = table.freeze({
		WALK_SPEED = WALK_SPEED,
		SPRINT_SPEED = SPRINT_SPEED,
		DASH_DURATION = DASH_DURATION,
		DASH_COOLDOWN = DASH_COOLDOWN,
		DASH_SPEED = DASH_SPEED,
		COYOTE_WINDOW = COYOTE_WINDOW,
		DASH_BUFFER_WINDOW = DASH_BUFFER_WINDOW,
	}),
}

local function normalizeFallback(v: Vec3Like): Vec3Like
	local mag = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	if mag < 1e-6 then
		return { X = 0, Y = 0, Z = -1 }
	end
	return { X = v.X / mag, Y = v.Y / mag, Z = v.Z / mag }
end

local function canActivateDash(self: InternalState): boolean
	if self._dashActiveRemaining > 0 or self._dashCooldownRemaining > 0 then
		return false
	end
	return self._coyoteRemaining > 0
end

local function startDashNow(self: InternalState)
	if self._isOnPad then
		self:cancelTrainingPad("Dash")
	end
	self._dashActiveRemaining = DASH_DURATION
	self._dashCooldownRemaining = DASH_COOLDOWN
	self._dashBufferRemaining = 0
end

local StateMethods = {} :: InternalState
local StateMeta = { __index = StateMethods }

function StateMethods.isOnTrainingPad(self: InternalState): boolean
	return self._isOnPad
end

function StateMethods.getActivePadId(self: InternalState): string?
	return self._activePadId
end

function StateMethods.enterTrainingPad(self: InternalState, padId: string): boolean
	if self._isOnPad or self._padReentryLockout > 0 or self._dashActiveRemaining > 0 then
		return false
	end
	self._isOnPad = true
	self._activePadId = padId
	self._padEntryGrace = PAD_ENTRY_SETTLE
	self._sprinting = false
	return true
end

function StateMethods.cancelTrainingPad(self: InternalState, _reason: string?): boolean
	if not self._isOnPad then
		return false
	end
	self._isOnPad = false
	self._activePadId = nil
	self._padEntryGrace = 0
	self._padReentryLockout = PAD_REENTRY_LOCKOUT
	return true
end

function StateMethods.handleMoveIntent(self: InternalState, moveMagnitude: number): boolean
	if not self._isOnPad or self._padEntryGrace > 0 then
		return false
	end
	if moveMagnitude > 0.25 then
		return self:cancelTrainingPad("Move")
	end
	return false
end

function StateMethods.setSprinting(self: InternalState, sprinting: boolean)
	self._sprinting = sprinting == true
end

function StateMethods.getTargetWalkSpeed(self: InternalState): number
	if self._isOnPad then
		return 0
	end
	return if self._sprinting then SPRINT_SPEED else WALK_SPEED
end

function StateMethods.requestDash(self: InternalState): boolean
	if canActivateDash(self) then
		startDashNow(self)
		return true
	end
	self._dashBufferRemaining = DASH_BUFFER_WINDOW
	return false
end

function StateMethods.isDashing(self: InternalState): boolean
	return self._dashActiveRemaining > 0
end

function StateMethods.getDashCooldownRemaining(self: InternalState): number
	return self._dashCooldownRemaining
end

function StateMethods.setArenaPhase(self: InternalState, phase: string)
	self._arenaPhase = phase
end

function StateMethods.getAimAssistMode(self: InternalState): string
	if self._isOnPad then
		return "Training"
	end
	if self._arenaPhase == "PvP_EggScramble" then
		return "PvP"
	end
	return "PvE"
end

function StateMethods.performThrow(
	self: InternalState,
	origin: Vec3Like,
	rawDirection: Vec3Like,
	candidates: { any },
	useAimAssist: boolean
): ThrowResult
	if self._throwCooldownRemaining > 0 then
		return { fired = false, payload = nil, assistedTargetId = nil }
	end
	local finalDir = normalizeFallback(rawDirection)
	local assistedId: string? = nil
	if useAimAssist and self._projectileArc and #candidates > 0 then
		local assistedDir, matched = self._projectileArc.applyAimAssist(
			origin,
			finalDir,
			candidates,
			self:getAimAssistMode()
		)
		finalDir = assistedDir
		assistedId = if matched then matched.id else nil
	end
	local payload: ThrowPayload = {
		origin = { X = origin.X, Y = origin.Y, Z = origin.Z },
		direction = { X = finalDir.X, Y = finalDir.Y, Z = finalDir.Z },
		onTrainingPad = self._isOnPad,
	}
	self._throwCooldownRemaining = self._throwCooldownDuration
	if self._net then
		self._net:fireServer("ThrowBall", payload)
	end
	return { fired = true, payload = payload, assistedTargetId = assistedId }
end

function StateMethods.step(self: InternalState, dt: number, isGrounded: boolean)
	if dt <= 0 then
		return
	end
	self._padEntryGrace = math.max(0, self._padEntryGrace - dt)
	self._padReentryLockout = math.max(0, self._padReentryLockout - dt)
	self._dashActiveRemaining = math.max(0, self._dashActiveRemaining - dt)
	self._dashCooldownRemaining = math.max(0, self._dashCooldownRemaining - dt)
	self._throwCooldownRemaining = math.max(0, self._throwCooldownRemaining - dt)
	self._coyoteRemaining = if isGrounded
		then COYOTE_WINDOW
		else math.max(0, self._coyoteRemaining - dt)

	if self._dashBufferRemaining > 0 then
		self._dashBufferRemaining = math.max(0, self._dashBufferRemaining - dt)
		if canActivateDash(self) then
			startDashNow(self)
		end
	end
end

function BallThrowController.createState(config: StateConfig): CombatState
	local instance: InternalState = setmetatable({
		_net = config.net,
		_projectileArc = config.projectileArc,
		_isOnPad = false,
		_activePadId = nil,
		_padEntryGrace = 0,
		_padReentryLockout = 0,
		_sprinting = false,
		_dashActiveRemaining = 0,
		_dashCooldownRemaining = 0,
		_coyoteRemaining = COYOTE_WINDOW,
		_dashBufferRemaining = 0,
		_throwCooldownDuration = config.throwCooldown or DEFAULT_THROW_COOLDOWN,
		_throwCooldownRemaining = 0,
		_arenaPhase = "PvE_Open",
	}, StateMeta) :: any
	return instance
end

-- === Roblox Client Runtime Integration (lazy-bound in Start) ===

local activeState: CombatState? = nil
local activeProjectileArc: any = nil
local runtimeConns: { any } = {}
local activeBalls: { ActiveBall } = {}
local previewDots: { BasePart } = {}
local previewFolder: Folder? = nil
local touchUIHandle: any = nil
local anchoredPadPart: BasePart? = nil
local isAiming = false
local dashDirection: Vector3? = nil

local function toVec3(v: Vector3): Vec3Like
	return { X = v.X, Y = v.Y, Z = v.Z }
end

local function isOwnedTrainingPad(pad: BasePart, localUserId: number): boolean
	local ownerAttr = pad:GetAttribute("OwnerUserId")
	if ownerAttr == nil and pad.Parent then
		ownerAttr = pad.Parent:GetAttribute("OwnerUserId")
	end
	if type(ownerAttr) == "number" and ownerAttr ~= 0 then
		return ownerAttr == localUserId
	end
	return true
end

local function findStandingTrainingPad(root: BasePart, localUserId: number): BasePart?
	local CollectionService = game:GetService("CollectionService")
	for _, tagged in ipairs(CollectionService:GetTagged("TrainingPad")) do
		if tagged:IsA("BasePart") and isOwnedTrainingPad(tagged, localUserId) then
			local rel = tagged.CFrame:PointToObjectSpace(root.Position)
			local halfX = tagged.Size.X * 0.5 + 1.2
			local halfZ = tagged.Size.Z * 0.5 + 1.2
			if
				math.abs(rel.X) <= halfX
				and math.abs(rel.Z) <= halfZ
				and rel.Y >= 0
				and rel.Y <= 7
			then
				return tagged
			end
		end
	end
	return nil
end

local function collectAimCandidates(localPlayer: Player, mode: string): { any }
	local CollectionService = game:GetService("CollectionService")
	local Players = game:GetService("Players")
	local candidates: { any } = {}
	if mode == "PvP" then
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= localPlayer and other.Character then
				local hrp = other.Character:FindFirstChild("HumanoidRootPart")
				if hrp and hrp:IsA("BasePart") then
					table.insert(candidates, {
						id = tostring(other.UserId),
						position = toVec3(hrp.Position),
						isPvP = true,
					})
				end
			end
		end
		return candidates
	end
	for _, tagName in ipairs({ "TrainingTarget", "BiomeBoss", "BiomeMob" }) do
		for _, inst in ipairs(CollectionService:GetTagged(tagName)) do
			local part: BasePart? = if inst:IsA("BasePart")
				then inst
				elseif inst:IsA("Model") then inst.PrimaryPart
				else nil
			if part then
				table.insert(candidates, {
					id = inst.Name,
					position = toVec3(part.Position),
					isPvP = false,
					priority = if tagName == "BiomeBoss" then 2 else 1,
				})
			end
		end
	end
	return candidates
end

local function ensurePreviewPool(): Folder
	if previewFolder and previewFolder.Parent then
		return previewFolder
	end
	local Workspace = game:GetService("Workspace")
	local folder = Instance.new("Folder")
	folder.Name = "BallBrawl_ClientPreview"
	folder.Parent = Workspace
	previewFolder = folder
	table.clear(previewDots)
	for i = 1, PREVIEW_DOT_COUNT do
		local dot = Instance.new("Part")
		dot.Name = `ArcDot_{i}`
		dot.Shape = Enum.PartType.Ball
		dot.Size = Vector3.new(0.45, 0.45, 0.45)
		dot.Material = Enum.Material.Neon
		dot.Color = Color3.fromRGB(255, 224, 110)
		dot.Anchored = true
		dot.CanCollide = false
		dot.CanQuery = false
		dot.CanTouch = false
		dot.Transparency = 1
		dot.Parent = folder
		table.insert(previewDots, dot)
	end
	return folder
end

local function updatePreviewDots(visible: boolean, origin: Vec3Like?, dir: Vec3Like?)
	if not visible or not origin or not dir or not activeProjectileArc then
		for _, dot in ipairs(previewDots) do
			dot.Transparency = 1
		end
		return
	end
	ensurePreviewPool()
	local points = activeProjectileArc.buildTrajectoryPoints(origin, dir, {
		maxDuration = 0.7,
		stepSeconds = 0.05,
	})
	for i, dot in ipairs(previewDots) do
		local pt = points[i + 1]
		if pt then
			dot.Position = Vector3.new(pt.X, pt.Y, pt.Z)
			dot.Transparency = 0.25 + (i / PREVIEW_DOT_COUNT) * 0.55
		else
			dot.Transparency = 1
		end
	end
end

local function spawnVisualBall(origin: Vec3Like, direction: Vec3Like)
	local folder = ensurePreviewPool()
	local ball = Instance.new("Part")
	ball.Name = "PredictedBall"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(1.1, 1.1, 1.1)
	ball.Material = Enum.Material.Neon
	ball.Color = Color3.fromRGB(255, 138, 42)
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	local startVec = Vector3.new(origin.X, origin.Y, origin.Z)
	ball.Position = startVec
	ball.Parent = folder
	table.insert(activeBalls, {
		part = ball,
		origin = origin,
		direction = direction,
		elapsed = 0,
		maxDuration = 1.6,
		lastPos = startVec,
	})
end

local function stepVisualBalls(dt: number, ignoreCharacter: Model?)
	if not activeProjectileArc or #activeBalls == 0 then
		return
	end
	local Workspace = game:GetService("Workspace")
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local excludes: { Instance } = {}
	if ignoreCharacter then
		table.insert(excludes, ignoreCharacter)
	end
	if previewFolder then
		table.insert(excludes, previewFolder)
	end
	rayParams.FilterDescendantsInstances = excludes

	for i = #activeBalls, 1, -1 do
		local ball = activeBalls[i]
		ball.elapsed += dt
		local nextPt = activeProjectileArc.samplePosition(ball.origin, ball.direction, ball.elapsed)
		local nextVec = Vector3.new(nextPt.X, nextPt.Y, nextPt.Z)
		local hit = Workspace:Raycast(ball.lastPos, nextVec - ball.lastPos, rayParams)
		if hit or ball.elapsed >= ball.maxDuration then
			if hit and touchUIHandle then
				local model = hit.Instance:FindFirstAncestorOfClass("Model")
				local isCombatHit = model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
				touchUIHandle.flashHitMarker(isCombatHit)
			end
			ball.part:Destroy()
			table.remove(activeBalls, i)
		else
			ball.part.Position = nextVec
			ball.lastPos = nextVec
		end
	end
end

local function computeAimRay(root: BasePart): (Vec3Like, Vec3Like)
	local Workspace = game:GetService("Workspace")
	local UserInputService = game:GetService("UserInputService")
	local camera = Workspace.CurrentCamera
	local origin = root.Position + Vector3.new(0, 1.5, 0)
	if not camera then
		return toVec3(origin), toVec3(root.CFrame.LookVector)
	end
	local aimDir = camera.CFrame.LookVector
	if not UserInputService.TouchEnabled then
		local mouseLoc = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mouseLoc.X, mouseLoc.Y)
		local targetPoint = ray.Origin + ray.Direction * 120
		aimDir = (targetPoint - origin).Unit
	end
	return toVec3(origin), toVec3(aimDir)
end

local function executeThrow(localPlayer: Player)
	local state = activeState
	local character = localPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not state or not root or not root:IsA("BasePart") then
		return
	end
	local UserInputService = game:GetService("UserInputService")
	local origin, rawDir = computeAimRay(root)
	local useAssist = UserInputService.TouchEnabled or state:isOnTrainingPad()
	local candidates = if useAssist
		then collectAimCandidates(localPlayer, state:getAimAssistMode())
		else {}
	local result = state:performThrow(origin, rawDir, candidates, useAssist)
	if result.fired and result.payload then
		spawnVisualBall(result.payload.origin, result.payload.direction)
	end
end

local function triggerDash(localPlayer: Player)
	local state = activeState
	local character = localPlayer.Character
	local hum = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not state or not hum or not root or not root:IsA("BasePart") then
		return
	end
	local moveDir = hum.MoveDirection
	if moveDir.Magnitude > 0.1 then
		dashDirection = Vector3.new(moveDir.X, 0, moveDir.Z).Unit
	else
		local look = root.CFrame.LookVector
		dashDirection = Vector3.new(look.X, 0, look.Z).Unit
	end
	if state:requestDash() then
		anchoredPadPart = nil
	end
end

local function applyMovementPhysics(state: CombatState, hum: Humanoid, root: BasePart, dt: number)
	hum.WalkSpeed = state:getTargetWalkSpeed()
	if state:isOnTrainingPad() and anchoredPadPart then
		local targetCF = anchoredPadPart.CFrame * CFrame.new(0, 3, 0)
		root.CFrame = root.CFrame:Lerp(targetCF, math.clamp(dt * 14, 0, 1))
		root.AssemblyLinearVelocity = Vector3.zero
	elseif state:isDashing() and dashDirection then
		local vel = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity =
			Vector3.new(dashDirection.X * DASH_SPEED, vel.Y, dashDirection.Z * DASH_SPEED)
	end
end

local function updateCharacterStep(localPlayer: Player, dt: number)
	local state = activeState
	local character = localPlayer.Character
	if not state or not character then
		return
	end
	local hum = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not hum or not root or not root:IsA("BasePart") then
		return
	end
	state:step(dt, hum.FloorMaterial ~= Enum.Material.Air)
	if hum.Jump and state:isOnTrainingPad() then
		state:cancelTrainingPad("Jump")
		anchoredPadPart = nil
	end
	if state:handleMoveIntent(hum.MoveDirection.Magnitude) then
		anchoredPadPart = nil
	end
	if not state:isOnTrainingPad() then
		local pad = findStandingTrainingPad(root, localPlayer.UserId)
		if pad and state:enterTrainingPad(pad:GetFullName()) then
			anchoredPadPart = pad
		end
	end
	applyMovementPhysics(state, hum, root, dt)
	if touchUIHandle then
		touchUIHandle.setDashCooldown(state:getDashCooldownRemaining(), DASH_COOLDOWN)
		touchUIHandle.setTrainingMode(state:isOnTrainingPad())
	end
	if isAiming or state:isOnTrainingPad() then
		local origin, rawDir = computeAimRay(root)
		updatePreviewDots(true, origin, rawDir)
	else
		updatePreviewDots(false, nil, nil)
	end
	stepVisualBalls(dt, character)
end

function BallThrowController.GetState(): CombatState?
	return activeState
end

function BallThrowController:Init(ctx: any)
	activeProjectileArc = ctx.projectileArc
	if not activeProjectileArc then
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local shared = ReplicatedStorage:FindFirstChild("Shared")
		local utils = if shared then shared:FindFirstChild("Utils") else nil
		local arcMod = if utils then utils:FindFirstChild("ProjectileArc") else nil
		if arcMod and arcMod:IsA("ModuleScript") then
			activeProjectileArc = require(arcMod)
		end
	end
	activeState = BallThrowController.createState({
		net = ctx.net,
		projectileArc = activeProjectileArc,
	})
end

local function mountTouchHUD(localPlayer: Player)
	local uiFolder = if script.Parent and script.Parent.Parent
		then script.Parent.Parent:FindFirstChild("UI")
		else nil
	local touchMod = if uiFolder then uiFolder:FindFirstChild("BallThrowTouchUI") else nil
	local playerGui = localPlayer:WaitForChild("PlayerGui", 5)
	if touchMod and touchMod:IsA("ModuleScript") and playerGui and playerGui:IsA("PlayerGui") then
		local touchUI = require(touchMod)
		touchUIHandle = touchUI.mount(playerGui, {
			onAimBegan = function()
				isAiming = true
			end,
			onThrowReleased = function()
				isAiming = false
				executeThrow(localPlayer)
			end,
			onDashPressed = function()
				triggerDash(localPlayer)
			end,
		})
	end
end

local function bindInputListeners(localPlayer: Player, state: CombatState)
	local UserInputService = game:GetService("UserInputService")
	table.insert(
		runtimeConns,
		UserInputService.JumpRequest:Connect(function()
			if state:cancelTrainingPad("JumpRequest") then
				anchoredPadPart = nil
			end
		end)
	)
	table.insert(
		runtimeConns,
		UserInputService.InputBegan:Connect(function(input: InputObject, gp: boolean)
			if gp then
				return
			end
			if input.KeyCode == Enum.KeyCode.LeftShift then
				state:setSprinting(true)
			elseif input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.LeftControl then
				triggerDash(localPlayer)
			elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
				isAiming = true
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
				executeThrow(localPlayer)
			end
		end)
	)
	table.insert(
		runtimeConns,
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if input.KeyCode == Enum.KeyCode.LeftShift then
				state:setSprinting(false)
			elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
				isAiming = false
			end
		end)
	)
end

function BallThrowController:Start(ctx: any)
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local localPlayer = Players.LocalPlayer
	if not localPlayer or not activeState then
		return
	end
	local state = activeState
	mountTouchHUD(localPlayer)
	table.insert(
		runtimeConns,
		ctx.net:onClientEvent("ArenaStateChanged", function(payload: any)
			if type(payload) == "table" and type(payload.phase) == "string" then
				state:setArenaPhase(payload.phase)
			end
		end)
	)
	bindInputListeners(localPlayer, state)
	table.insert(
		runtimeConns,
		RunService.Heartbeat:Connect(function(dt: number)
			updateCharacterStep(localPlayer, dt)
		end)
	)
end

function BallThrowController:Destroy()
	for _, conn in ipairs(runtimeConns) do
		pcall(function()
			conn:Disconnect()
		end)
	end
	table.clear(runtimeConns)
	if touchUIHandle then
		touchUIHandle.destroy()
		touchUIHandle = nil
	end
	if previewFolder then
		previewFolder:Destroy()
		previewFolder = nil
	end
	table.clear(previewDots)
	table.clear(activeBalls)
end

return BallThrowController
