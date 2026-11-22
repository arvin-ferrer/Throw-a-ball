--!strict
--[[
	ArenaCycleService (Issue #4): thin server wrapper around the pure ArenaStateMachine.
	The FSM decides; this file only executes its ArenaActions against the live map
	(Workspace.BallBrawl_Map_v2.Biomes.<BiomeId>) and validates every client intent.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArenaStateMachine = require(Shared.Utils.ArenaStateMachine)
local BiomeConfigs = require(Shared.Configs.BiomeConfigs)
local Remotes = require(Shared.Net.Remotes)

type ArenaState = ArenaStateMachine.ArenaState
type ArenaAction = ArenaStateMachine.ArenaAction

export type Callbacks = {
	onSpawnBoss: ((biomeId: string, maxHp: number, isOvercharged: boolean, spawn: CFrame) -> ())?,
	onDespawnBoss: ((biomeId: string) -> ())?,
	onAwardEgg: ((userId: number, biomeId: string, eggType: string) -> ())?,
	onAwardConsolation: ((userIds: { number }, biomeId: string) -> ())?,
}

type Runtime = {
	biomeId: string,
	fsm: ArenaState,
	folder: Instance,
	roomSpawns: { CFrame },
	bossSpawn: CFrame,
	pveCenter: Vector3, -- PvEGround disc: "standing in this biome"
	pveRadius: number,
	roomCenter: Vector3, -- ArenaFloor disc: "inside the locked room"
	roomRadius: number,
	pveReturn: CFrame,
	eggPosition: Vector3,
	egg: BasePart?,
	deathConns: { [number]: RBXScriptConnection },
	admitted: { [number]: Model }, -- the exact character that entered the room
}

local REMOTE_MIN_INTERVAL = 0.2 -- seconds between accepted intents per player per remote
local BROADCAST_INTERVAL = 1
local ZONE_MARGIN_STUDS = 6 -- standing on the rim still counts
local ROOM_HEIGHT_STUDS = 80 -- above/below the floor by more than this = out of the room

local ArenaCycleService = {}

local runtimes: { [string]: Runtime } = {}
local callbacks: Callbacks = {}
local remotesFolder: Folder? = nil
local lastIntent: { [string]: number } = {}
local heartbeatConn: RBXScriptConnection? = nil
local nextOverchargedAt = 0
local nextBroadcastAt = 0

-- Map lookup ---------------------------------------------------------------------------

local function pivotOf(inst: Instance?): CFrame?
	if inst and inst:IsA("BasePart") then
		return inst.CFrame
	elseif inst and inst:IsA("Model") then
		return inst:GetPivot()
	end
	return nil
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Floors are thin discs/slabs: their footprint radius is half the largest dimension.
local function discOf(
	part: Instance?,
	fallbackCenter: Vector3,
	fallbackRadius: number
): (Vector3, number)
	if part and part:IsA("BasePart") then
		local s = part.Size
		return part.Position, math.max(s.X, s.Y, s.Z) / 2 + ZONE_MARGIN_STUDS
	end
	return fallbackCenter, fallbackRadius
end

local function collectRoomSpawns(arena: Instance): { CFrame }
	local spawns = {}
	for _, child in arena:GetChildren() do
		local cf = if child.Name:match("^OptInSpawn_") then pivotOf(child) else nil
		if cf then
			table.insert(spawns, cf)
		end
	end
	return spawns
end

local function buildRuntime(biomeFolder: Instance, now: number): Runtime?
	local config = BiomeConfigs.get(biomeFolder.Name)
	local arena = biomeFolder:FindFirstChild("BossPvPArena")
	local pve = biomeFolder:FindFirstChild("PvELayer")
	local pedestal = pivotOf(arena and arena:FindFirstChild("EggClaimPedestal"))
	local arrival = pivotOf(pve and pve:FindFirstChild("ArrivalPad"))
	if not (config and arena and pedestal and arrival) then
		warn(`[ArenaCycleService] Skipping {biomeFolder.Name}: missing config or map anchors`)
		return nil
	end
	local spawns = collectRoomSpawns(arena)
	if #spawns == 0 then
		spawns = { pedestal * CFrame.new(0, 0, 10) }
	end
	local stormRadius = ArenaStateMachine.CONSTANTS.DEFAULT_STORM_INITIAL_RADIUS_STUDS
	local roomCenter, roomRadius =
		discOf(arena:FindFirstChild("ArenaFloor"), pedestal.Position, stormRadius)
	local pveCenter, pveRadius =
		discOf(pve and pve:FindFirstChild("PvEGround"), arrival.Position, 260)
	return {
		bossSpawn = pivotOf(arena:FindFirstChild("BossSpawn")) or spawns[1],
		pveCenter = pveCenter,
		pveRadius = pveRadius,
		roomCenter = roomCenter,
		roomRadius = roomRadius,
		admitted = {},
		biomeId = config.biomeId,
		fsm = ArenaStateMachine.new(
			{ biomeId = config.biomeId, baseBossHp = config.baseBossHp },
			now
		),
		folder = arena,
		roomSpawns = spawns,
		pveReturn = arrival,
		eggPosition = pedestal.Position,
		egg = nil,
		deathConns = {},
	}
end

-- Character helpers --------------------------------------------------------------------

local function rootOf(userId: number): (BasePart?, Humanoid?)
	local player = Players:GetPlayerByUserId(userId)
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return if root and root:IsA("BasePart") then root else nil, humanoid
end

local function teleport(userId: number, cf: CFrame)
	local root = rootOf(userId)
	local character = root and root.Parent
	if root and character and character:IsA("Model") then
		root.AssemblyLinearVelocity = Vector3.zero
		character:PivotTo(cf + Vector3.new(0, 4, 0))
	end
end

-- Forward declaration: action handlers re-enter the FSM (storm damage cancels claims).
local dispatch: (rt: Runtime, actions: { ArenaAction }) -> ()

local function watchDeath(rt: Runtime, userId: number)
	local _, humanoid = rootOf(userId)
	if not humanoid then
		return
	end
	rt.deathConns[userId] = humanoid.Died:Connect(function()
		dispatch(rt, ArenaStateMachine.eliminate(rt.fsm, userId, os.clock()).actions)
	end)
end

local function unwatchDeath(rt: Runtime, userId: number)
	local conn = rt.deathConns[userId]
	if conn then
		conn:Disconnect()
		rt.deathConns[userId] = nil
	end
end

-- Broadcasts (FireAllClients + biomeId; clients filter by the biome they stand in) -----

local function fireAll(name: string, payload: { [string]: any })
	if remotesFolder then
		Remotes.getEvent(remotesFolder, name):FireAllClients(payload)
	end
end

local function broadcastState(rt: Runtime, now: number)
	local snap = ArenaStateMachine.getSnapshot(rt.fsm, now)
	local remaining = if snap.phaseEndTime then math.max(0, snap.phaseEndTime - now) else 0
	rt.folder:SetAttribute("Phase", snap.phase)
	rt.folder:SetAttribute("StormActive", snap.stormActive)
	rt.folder:SetAttribute("StormRadius", snap.stormRadius)
	fireAll(Remotes.Names.ArenaStateChanged, {
		biomeId = rt.biomeId,
		phase = snap.phase,
		isOvercharged = snap.isOvercharged,
		phaseSecondsRemaining = remaining,
		suddenDeathActive = snap.stormActive,
		pvePlayerCount = #Players:GetPlayers() - snap.aliveCount,
	})
end

local function broadcastOptIn(rt: Runtime, now: number)
	local snap = ArenaStateMachine.getSnapshot(rt.fsm, now)
	local config = BiomeConfigs.get(rt.biomeId)
	fireAll(Remotes.Names.OptInPrompt, {
		biomeId = rt.biomeId,
		isOvercharged = snap.isOvercharged,
		secondsRemaining = if snap.phaseEndTime then math.max(0, snap.phaseEndTime - now) else 0,
		queuedPlayers = snap.optInCount,
		highestPowerRating = 0, -- filled in once DataService (#9) exposes Power Rating
		recommendedDamage = if config then config.recommendedDamage else 0,
	})
end

local function broadcastClaim(rt: Runtime, action: ArenaAction, status: string)
	local player = action.playerId and Players:GetPlayerByUserId(action.playerId)
	fireAll(Remotes.Names.EggClaimUpdated, {
		biomeId = rt.biomeId,
		claimerUserId = action.playerId,
		claimerName = if player then player.DisplayName else nil,
		progressSeconds = 0,
		durationSeconds = rt.fsm.config.eggClaimDurationSeconds,
		status = status,
		interruptReason = action.reason,
	})
end

-- Egg ------------------------------------------------------------------------------------

local function requestClaim(player: Player, holding: boolean)
	for _, rt in runtimes do
		if rt.fsm.alivePlayers[player.UserId] then
			local now = os.clock()
			local root = rootOf(player.UserId)
			if not holding then
				dispatch(rt, ArenaStateMachine.cancelClaim(rt.fsm, player.UserId, now).actions)
			elseif root then
				local dist = (root.Position - rt.eggPosition).Magnitude
				local result = ArenaStateMachine.startClaim(rt.fsm, player.UserId, dist, now)
				dispatch(rt, result.actions)
			end
			return
		end
	end
end

local function spawnEgg(rt: Runtime)
	local egg = Instance.new("Part")
	egg.Name = "BossEgg"
	egg.Shape = Enum.PartType.Ball
	egg.Size = Vector3.new(4, 5, 4)
	egg.Material = Enum.Material.Neon
	egg.Color = if rt.fsm.isOvercharged
		then Color3.fromRGB(255, 170, 40)
		else Color3.fromRGB(120, 255, 140)
	egg.Anchored = true
	egg.CanCollide = false
	egg.Position = rt.eggPosition + Vector3.new(0, 4, 0)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Claim Boss Egg"
	-- Visual only: the server times the claim. +0.5s so the client's hold-end (latency) can't
	-- arrive before the server completes and cancel a winning claim.
	prompt.HoldDuration = rt.fsm.config.eggClaimDurationSeconds + 0.5
	prompt.MaxActivationDistance = rt.fsm.config.eggClaimRadiusStuds
	prompt.RequiresLineOfSight = false
	prompt.PromptButtonHoldBegan:Connect(function(player)
		requestClaim(player, true)
	end)
	prompt.PromptButtonHoldEnded:Connect(function(player)
		requestClaim(player, false)
	end)
	prompt.Parent = egg
	egg.Parent = rt.folder
	rt.egg = egg
end

local function despawnEgg(rt: Runtime)
	if rt.egg then
		rt.egg:Destroy()
		rt.egg = nil
	end
end

-- Storm ----------------------------------------------------------------------------------

local function applyStorm(rt: Runtime, action: ArenaAction)
	local radius, pct, dt = action.stormRadius, action.damagePctPerSec, action.dt
	if not (radius and pct and dt) or dt <= 0 then
		return
	end
	for userId in table.clone(rt.fsm.alivePlayers) do
		local root, humanoid = rootOf(userId)
		if root and humanoid and flatDistance(root.Position, rt.eggPosition) > radius then
			local amount = humanoid.MaxHealth * pct * dt
			humanoid:TakeDamage(amount)
			dispatch(rt, ArenaStateMachine.damage(rt.fsm, userId, amount, os.clock(), nil).actions)
		end
	end
end

-- Action dispatch ------------------------------------------------------------------------

local function enterRoom(rt: Runtime, ids: { number })
	for i, userId in ids do
		teleport(userId, rt.roomSpawns[(i - 1) % #rt.roomSpawns + 1])
		watchDeath(rt, userId)
		local player = Players:GetPlayerByUserId(userId)
		if player and player.Character then
			rt.admitted[userId] = player.Character
		end
	end
end

local function leaveRoom(rt: Runtime, ids: { number })
	for _, userId in ids do
		unwatchDeath(rt, userId)
		rt.admitted[userId] = nil
		local _, humanoid = rootOf(userId)
		if humanoid and humanoid.Health > 0 then
			teleport(userId, rt.pveReturn)
		end
	end
end

local function healAll(ids: { number })
	for _, userId in ids do
		local _, humanoid = rootOf(userId)
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = humanoid.MaxHealth
		end
	end
end

local function handleRoomAction(rt: Runtime, a: ArenaAction): boolean
	local ids = a.playerIds or {}
	if a.kind == "TeleportToBossRoom" then
		enterRoom(rt, ids)
	elseif a.kind == "TeleportToPvELayer" then
		leaveRoom(rt, ids)
	elseif a.kind == "FullHealPlayers" then
		healAll(ids)
	elseif a.kind == "SpawnEgg" then
		spawnEgg(rt)
	elseif a.kind == "DespawnEgg" then
		despawnEgg(rt)
	elseif a.kind == "StormTick" then
		applyStorm(rt, a)
	else
		return false
	end
	return true
end

-- External hooks are deferred: they run after this whole action list (egg removal,
-- teleports) is applied, and a hook that errors or yields can never stall that cleanup.
local function handleRewardAction(rt: Runtime, a: ArenaAction)
	if a.kind == "SpawnBoss" and callbacks.onSpawnBoss then
		local hp, oc = a.bossMaxHp or 0, a.isOvercharged == true
		task.defer(callbacks.onSpawnBoss, rt.biomeId, hp, oc, rt.bossSpawn)
	elseif a.kind == "DespawnBoss" and callbacks.onDespawnBoss then
		task.defer(callbacks.onDespawnBoss, rt.biomeId)
	elseif a.kind == "EggClaimed" and a.playerId then
		broadcastClaim(rt, a, "Completed")
		if callbacks.onAwardEgg then
			local eggType = a.eggType or "StandardBossEgg"
			task.defer(callbacks.onAwardEgg, a.playerId, rt.biomeId, eggType)
		end
	elseif a.kind == "AwardConsolation" and callbacks.onAwardConsolation then
		task.defer(callbacks.onAwardConsolation, a.playerIds or {}, rt.biomeId)
	elseif a.kind == "ClaimStarted" then
		broadcastClaim(rt, a, "Claiming")
	elseif a.kind == "ClaimCancelled" then
		broadcastClaim(rt, a, "Interrupted")
	end
end

dispatch = function(rt: Runtime, actions: { ArenaAction })
	for _, a in actions do
		if not handleRoomAction(rt, a) then
			handleRewardAction(rt, a)
		end
		if a.kind == "PhaseChanged" then
			broadcastState(rt, a.timestamp)
			if a.phase == "OptIn_Window" then
				broadcastOptIn(rt, a.timestamp)
			end
		elseif a.kind == "OptInUpdated" then
			broadcastOptIn(rt, a.timestamp)
		end
	end
end

-- Heartbeat ------------------------------------------------------------------------------

local function checkClaimRadius(rt: Runtime, now: number)
	local claim = rt.fsm.activeClaim
	if not claim then
		return
	end
	local root = rootOf(claim.playerId)
	local dist = if root then (root.Position - rt.eggPosition).Magnitude else math.huge
	if dist > rt.fsm.config.eggClaimRadiusStuds then
		dispatch(rt, ArenaStateMachine.leaveRadius(rt.fsm, claim.playerId, now).actions)
	end
end

-- The biome whose PvEGround disc this position stands over (Hub and other biomes: nil).
local function biomeAt(position: Vector3): Runtime?
	for _, rt in runtimes do
		if flatDistance(position, rt.pveCenter) <= rt.pveRadius then
			return rt
		end
	end
	return nil
end

local function isAliveAt(userId: number): (BasePart?, Humanoid?)
	local root, humanoid = rootOf(userId)
	if root and humanoid and humanoid.Health > 0 then
		return root, humanoid
	end
	return nil, nil
end

-- Alive, still the character that was admitted, and over the arena floor's height band.
local function isFighterInRoom(rt: Runtime, userId: number): boolean
	local root = isAliveAt(userId)
	return root ~= nil
		and root.Parent == rt.admitted[userId]
		and flatDistance(root.Position, rt.roomCenter) <= rt.roomRadius
		and math.abs(root.Position.Y - rt.roomCenter.Y) <= ROOM_HEIGHT_STUDS
end

local function dropFighter(rt: Runtime, userId: number, now: number)
	unwatchDeath(rt, userId)
	rt.admitted[userId] = nil
	-- A player who already left the server is a disconnect (no consolation), not a death.
	local result = if Players:GetPlayerByUserId(userId)
		then ArenaStateMachine.eliminate(rt.fsm, userId, now)
		else ArenaStateMachine.disconnect(rt.fsm, userId, now)
	dispatch(rt, result.actions)
end

-- Roster must match reality every frame: the FSM only knows what we tell it, so dead,
-- respawned, departed or out-of-biome players are removed before it can lock or award.
local function reconcile(rt: Runtime, now: number)
	for userId in table.clone(rt.fsm.optedIn) do
		local root = isAliveAt(userId)
		if not root or biomeAt(root.Position) ~= rt then
			dispatch(rt, ArenaStateMachine.disconnect(rt.fsm, userId, now).actions)
		end
	end
	for userId in table.clone(rt.fsm.alivePlayers) do
		if not isFighterInRoom(rt, userId) then
			dropFighter(rt, userId, now)
		end
	end
	checkClaimRadius(rt, now)
end

local function onHeartbeat()
	local now = os.clock()
	local overcharge = now >= nextOverchargedAt
	if overcharge then
		nextOverchargedAt = now + ArenaStateMachine.CONSTANTS.OVERCHARGED_INTERVAL_SECONDS
	end
	local broadcast = now >= nextBroadcastAt
	if broadcast then
		nextBroadcastAt = now + BROADCAST_INTERVAL
	end
	for _, rt in runtimes do
		if overcharge then
			dispatch(rt, ArenaStateMachine.triggerOvercharged(rt.fsm, now).actions)
		end
		reconcile(rt, now)
		dispatch(rt, ArenaStateMachine.tick(rt.fsm, now).actions)
		if broadcast then
			broadcastState(rt, now)
		end
	end
end

-- Remote intents -------------------------------------------------------------------------

local function allowIntent(player: Player, remote: string): boolean
	local key = `{player.UserId}:{remote}`
	local now = os.clock()
	if now - (lastIntent[key] or -math.huge) < REMOTE_MIN_INTERVAL then
		return false
	end
	lastIntent[key] = now
	return true
end

local function isBusyElsewhere(userId: number, except: Runtime): boolean
	for _, rt in runtimes do
		if rt ~= except and (rt.fsm.optedIn[userId] or rt.fsm.alivePlayers[userId]) then
			return true
		end
	end
	return false
end

-- Intent schema shared with ClientNet's mock (PR #21): OptIn(true|false|{accepted: boolean}).
-- The biome is never taken from the client; it is wherever the player's character stands.
local function onOptIn(player: Player, payload: unknown)
	if not allowIntent(player, "OptIn") or not callbacks.onSpawnBoss then
		return -- no boss provider wired: never lock players into an empty room
	end
	local accepted = if type(payload) == "table" then (payload :: any).accepted else payload
	if type(accepted) ~= "boolean" then
		return -- malformed intent: ignore rather than guess
	end
	local root = isAliveAt(player.UserId)
	local rt = root and biomeAt(root.Position)
	if not rt or isBusyElsewhere(player.UserId, rt) then
		return
	end
	local now = os.clock()
	local result = if accepted
		then ArenaStateMachine.optIn(rt.fsm, player.UserId, now)
		else ArenaStateMachine.optOut(rt.fsm, player.UserId, now)
	dispatch(rt, result.actions)
end

-- ClaimEgg("Start"|"Cancel"|{action: "Start"|"Cancel"}). Releases skip the rate limit so a
-- quick start->release can never leave a claim armed.
local function onClaimEgg(player: Player, payload: unknown)
	local action = if type(payload) == "table" then (payload :: any).action else payload
	if action == "Cancel" then
		requestClaim(player, false)
	elseif action == "Start" and allowIntent(player, "ClaimEgg") then
		requestClaim(player, true)
	end
end

local function onPlayerRemoving(player: Player)
	local now = os.clock()
	for _, rt in runtimes do
		unwatchDeath(rt, player.UserId)
		dispatch(rt, ArenaStateMachine.disconnect(rt.fsm, player.UserId, now).actions)
	end
	for key in lastIntent do
		if key:sub(1, #tostring(player.UserId) + 1) == `{player.UserId}:` then
			lastIntent[key] = nil
		end
	end
end

-- Public API -----------------------------------------------------------------------------

function ArenaCycleService.init(mapRoot: Instance, folder: Folder, cbs: Callbacks?)
	callbacks = cbs or {}
	remotesFolder = folder
	local biomes = mapRoot:FindFirstChild("Biomes")
	assert(biomes, "[ArenaCycleService] map root has no Biomes folder")
	local now = os.clock()
	for _, biomeFolder in biomes:GetChildren() do
		local rt = buildRuntime(biomeFolder, now)
		if rt then
			runtimes[rt.biomeId] = rt
		end
	end
	nextOverchargedAt = now + ArenaStateMachine.CONSTANTS.OVERCHARGED_INTERVAL_SECONDS
end

function ArenaCycleService.start()
	assert(remotesFolder, "call init first")
	Remotes.getEvent(remotesFolder, Remotes.Names.OptIn).OnServerEvent:Connect(onOptIn)
	Remotes.getEvent(remotesFolder, Remotes.Names.ClaimEgg).OnServerEvent:Connect(onClaimEgg)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	heartbeatConn = RunService.Heartbeat:Connect(onHeartbeat)
end

function ArenaCycleService.stop()
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
end

-- CombatService (#5) must gate every player-vs-player hit through this.
function ArenaCycleService.canDealPvPDamage(attacker: Player, victim: Player): boolean
	local now = os.clock()
	for _, rt in runtimes do
		if
			ArenaStateMachine.canDealPvPDamage(rt.fsm, attacker.UserId, victim.UserId, now)
			and isFighterInRoom(rt, attacker.UserId)
			and isFighterInRoom(rt, victim.UserId)
		then
			return true
		end
	end
	return false
end

-- CombatService reports applied PvP damage so an active claim is cancelled.
function ArenaCycleService.notifyPvPDamage(victim: Player, amount: number, attacker: Player?)
	local now = os.clock()
	for _, rt in runtimes do
		if rt.fsm.alivePlayers[victim.UserId] then
			local attackerId = if attacker then attacker.UserId else nil
			dispatch(
				rt,
				ArenaStateMachine.damage(rt.fsm, victim.UserId, amount, now, attackerId).actions
			)
		end
	end
end

-- BossAIService (#5) calls this when the biome boss dies.
function ArenaCycleService.notifyBossDefeated(biomeId: string)
	local rt = runtimes[biomeId]
	if rt then
		dispatch(rt, ArenaStateMachine.bossDefeated(rt.fsm, os.clock()).actions)
	end
end

function ArenaCycleService.isInLockedRoom(player: Player): boolean
	for _, rt in runtimes do
		if rt.fsm.alivePlayers[player.UserId] then
			return true
		end
	end
	return false
end

function ArenaCycleService.getSnapshot(biomeId: string): ArenaStateMachine.ArenaSnapshot?
	local rt = runtimes[biomeId]
	return if rt then ArenaStateMachine.getSnapshot(rt.fsm, os.clock()) else nil
end

-- Studio/test hook: jump a biome straight to its opt-in window.
function ArenaCycleService.debugOpenOptIn(biomeId: string)
	local rt = runtimes[biomeId]
	if rt and rt.fsm.phase == "PvE_Open" then
		rt.fsm.phaseEndTime = os.clock()
	end
end

return ArenaCycleService
