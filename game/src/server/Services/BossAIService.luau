--!strict
--[[
	BossAIService (Issue #5): thin wrapper that runs one BossAIStateMachine per biome boss
	room and renders its actions (telegraphs, shockwave ring, rolling boulders).
	ArenaCycleService decides WHEN a boss exists; this decides how it fights.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BossAIStateMachine = require(Shared.Utils.BossAIStateMachine)
local CombatConfigs = require(Shared.Configs.CombatConfigs)
local CombatMath = require(Shared.Utils.CombatMath)

type Vec3 = CombatMath.Vec3
type BossAction = BossAIStateMachine.BossAction

type Hooks = {
	getFighterIds: (biomeId: string) -> { number },
	onDefeated: (biomeId: string) -> (),
}

type ActiveBoss = {
	biomeId: string,
	fsm: BossAIStateMachine.State,
	model: Model,
	arena: Instance,
	floorY: number,
	obstacles: { CombatMath.AABB },
	boulders: { [number]: BasePart },
	ring: BasePart?,
	lane: BasePart?,
}

local ROOT_HEIGHT = 3 -- boss logic runs at character-root height above the floor
local BOSS_CONFIG_BY_BIOME: { [string]: any } = {
	EmeraldMeadow = CombatConfigs.Bosses.MossbackGolem,
	FrostbiteCavern = CombatConfigs.Bosses.GlacierYeti,
	MoltenCaldera = CombatConfigs.Bosses.ObsidianWyrm,
}
local BOSS_ID_BY_BIOME = {
	EmeraldMeadow = "MossbackGolem",
	FrostbiteCavern = "GlacierYeti",
	MoltenCaldera = "ObsidianWyrm",
}
-- Placeholder body/accent colours until the #17 meshes are uploaded.
local BOSS_COLORS = {
	MossbackGolem = { Color3.fromRGB(86, 110, 70), Color3.fromRGB(70, 170, 70) },
	GlacierYeti = { Color3.fromRGB(200, 225, 240), Color3.fromRGB(120, 200, 255) },
	ObsidianWyrm = { Color3.fromRGB(40, 32, 38), Color3.fromRGB(255, 110, 30) },
}

local BossAIService = {}

local bosses: { [string]: ActiveBoss } = {}
local hooks: Hooks? = nil
local mapRoot: Instance? = nil

local function toVec3(v: Vector3): Vec3
	return { X = v.X, Y = v.Y, Z = v.Z }
end

local function toVector3(v: Vec3): Vector3
	return Vector3.new(v.X, v.Y, v.Z)
end

-- Rendering helpers ------------------------------------------------------------------------

local function makePart(name: string, size: Vector3, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false -- never block projectile raycasts
	part.CanTouch = false
	part.Parent = parent
	return part
end

-- Real art (from #8) wins when it exists in ServerStorage.BossModels; otherwise a readable
-- placeholder so the fight is playable today.
local function buildModel(bossId: string, parent: Instance): Model
	local folder = ServerStorage:FindFirstChild("BossModels")
	local template = folder and folder:FindFirstChild(bossId)
	if template and template:IsA("Model") then
		local model = template:Clone()
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.CanQuery = false -- hits come from the boss sphere, not its mesh
				part.Anchored = true
			end
		end
		model.Parent = parent
		return model
	end
	local model = Instance.new("Model")
	model.Name = bossId
	local colors = BOSS_COLORS[bossId] or BOSS_COLORS.MossbackGolem
	local body = makePart("Body", Vector3.new(9, 11, 9), colors[1], model)
	body.Material = Enum.Material.Slate
	local moss = makePart("Moss", Vector3.new(9.6, 2.5, 9.6), colors[2], model)
	moss.Material = Enum.Material.Grass
	moss.CFrame = body.CFrame * CFrame.new(0, 5, 0)
	model.PrimaryPart = body
	model.Parent = parent
	return model
end

local function placeModel(boss: ActiveBoss)
	local pos = boss.fsm.position
	local center = Vector3.new(pos.X, boss.floorY + boss.model:GetExtentsSize().Y / 2, pos.Z)
	boss.model:PivotTo(CFrame.new(center))
end

local function aabbOf(part: BasePart): CombatMath.AABB
	local half = part.Size / 2
	return { min = toVec3(part.Position - half), max = toVec3(part.Position + half) }
end

local function collectObstacles(arena: Instance): { CombatMath.AABB }
	local boxes = {}
	for _, child in arena:GetDescendants() do
		local isCover = child.Name:match("^CoverPillar_") or child.Name:match("^ArenaWall_")
		if isCover and child:IsA("BasePart") then
			table.insert(boxes, aabbOf(child))
		end
	end
	return boxes
end

-- Action rendering --------------------------------------------------------------------------

local function damagePlayer(userId: number, amount: number, push: Vector3?)
	local player = Players:GetPlayerByUserId(userId)
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 then
		humanoid:TakeDamage(amount)
		if push and root and root:IsA("BasePart") then
			root.AssemblyLinearVelocity = push + Vector3.new(0, 18, 0)
		end
	end
end

local function clearTelegraphs(boss: ActiveBoss)
	if boss.ring then
		boss.ring:Destroy()
		boss.ring = nil
	end
	if boss.lane then
		boss.lane:Destroy()
		boss.lane = nil
	end
end

local function showSlam(boss: ActiveBoss, a: BossAction)
	clearTelegraphs(boss)
	local radius = a.radius or 0
	local ring = makePart(
		"SlamTelegraph",
		Vector3.new(0.4, radius * 2, radius * 2),
		Color3.fromRGB(255, 70, 40),
		boss.arena
	)
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.6
	ring.CFrame = CFrame.new(boss.fsm.position.X, boss.floorY + 0.3, boss.fsm.position.Z)
		* CFrame.Angles(0, 0, math.rad(90))
	boss.ring = ring
end

local function updateRing(boss: ActiveBoss, radius: number)
	local ring = boss.ring
	if ring then
		ring.Material = Enum.Material.Neon
		ring.Transparency = 0.35
		ring.Size = Vector3.new(0.6, math.max(0.1, radius * 2), math.max(0.1, radius * 2))
	end
end

local function showLane(boss: ActiveBoss, a: BossAction)
	clearTelegraphs(boss)
	local dir = toVector3(a.direction or { X = 0, Y = 0, Z = 1 })
	local length = boss.fsm.config.boulder.maxDistance
	local origin = Vector3.new(boss.fsm.position.X, boss.floorY + 0.25, boss.fsm.position.Z)
	local lane = makePart(
		"BoulderLane",
		Vector3.new(boss.fsm.config.boulder.radius * 2, 0.3, length),
		Color3.fromRGB(255, 140, 40),
		boss.arena
	)
	lane.Material = Enum.Material.Neon
	lane.Transparency = 0.5
	lane.CFrame = CFrame.lookAt(origin + dir * length / 2, origin + dir * length)
	boss.lane = lane
end

local function renderBoulder(boss: ActiveBoss, a: BossAction)
	local id = a.boulderId
	if not id then
		return
	end
	if a.kind == "SpawnBoulder" then
		clearTelegraphs(boss)
		local d = boss.fsm.config.boulder.radius * 2
		local ball =
			makePart("Boulder", Vector3.new(d, d, d), Color3.fromRGB(110, 100, 85), boss.arena)
		ball.Shape = Enum.PartType.Ball
		ball.Material = Enum.Material.Slate
		boss.boulders[id] = ball
	end
	local ball = boss.boulders[id]
	if ball and a.position then
		ball.Position = toVector3(a.position)
			- Vector3.new(0, ROOT_HEIGHT - boss.fsm.config.boulder.radius, 0)
	elseif ball and a.kind == "DespawnBoulder" then
		ball:Destroy()
		boss.boulders[id] = nil
	end
end

local function handleAction(boss: ActiveBoss, a: BossAction)
	local kind = a.kind
	if kind == "MoveTo" then
		placeModel(boss)
	elseif kind == "TelegraphSlam" then
		showSlam(boss, a)
	elseif kind == "SlamShockwaveTick" then
		updateRing(boss, a.radius or 0)
	elseif kind == "SlamHit" and a.playerId then
		damagePlayer(a.playerId, a.damage or 0, nil)
	elseif kind == "TelegraphBoulder" then
		showLane(boss, a)
	elseif kind == "BoulderHit" and a.playerId then
		local push = toVector3(a.direction or { X = 0, Y = 0, Z = 0 }) * (a.knockbackImpulse or 0)
		damagePlayer(a.playerId, a.damage or 0, push)
	elseif kind == "BossDamaged" then
		boss.model:SetAttribute("Health", a.currentHp)
	else
		renderBoulder(boss, a)
	end
end

local function teardown(boss: ActiveBoss)
	clearTelegraphs(boss)
	for _, ball in boss.boulders do
		ball:Destroy()
	end
	boss.model:Destroy()
	bosses[boss.biomeId] = nil
end

local function dispatch(boss: ActiveBoss, actions: { BossAction })
	local defeated = false
	for _, a in actions do
		handleAction(boss, a)
		defeated = defeated or a.kind == "BossDefeated"
	end
	local state = boss.fsm.state
	if boss.ring and state ~= "Windup_Slam" and state ~= "Active_Slam" then
		clearTelegraphs(boss) -- slam finished: remove the ring
	end
	if defeated and hooks then
		teardown(boss)
		hooks.onDefeated(boss.biomeId)
	end
end

-- Heartbeat ---------------------------------------------------------------------------------

local function snapshotTargets(biomeId: string): { BossAIStateMachine.TargetSnapshot }
	local targets = {}
	local ids: { number } = if hooks then hooks.getFighterIds(biomeId) else {}
	for _, userId in ids do
		local player = Players:GetPlayerByUserId(userId)
		local root = player
			and player.Character
			and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			table.insert(targets, { playerId = userId, position = toVec3(root.Position) })
		end
	end
	return targets
end

local function onHeartbeat()
	local now = os.clock()
	for _, boss in table.clone(bosses) do
		local result =
			BossAIStateMachine.tick(boss.fsm, now, snapshotTargets(boss.biomeId), boss.obstacles)
		if result.ok then
			dispatch(boss, result.actions)
		end
	end
end

-- Public API ---------------------------------------------------------------------------------

function BossAIService.init(map: Instance, serviceHooks: Hooks)
	mapRoot = map
	hooks = serviceHooks
	RunService.Heartbeat:Connect(onHeartbeat)
end

-- ArenaCycleService.onSpawnBoss
function BossAIService.spawn(biomeId: string, maxHp: number, isOvercharged: boolean, spawn: CFrame)
	local config = BOSS_CONFIG_BY_BIOME[biomeId] or CombatConfigs.Bosses.MossbackGolem
	local biomes = mapRoot and mapRoot:FindFirstChild("Biomes")
	local biome = biomes and biomes:FindFirstChild(biomeId)
	local arena = biome and biome:FindFirstChild("BossPvPArena")
	if not arena or bosses[biomeId] then
		return
	end
	local position = toVec3(spawn.Position + Vector3.new(0, ROOT_HEIGHT, 0))
	local boss: ActiveBoss = {
		biomeId = biomeId,
		fsm = BossAIStateMachine.new(config, position, maxHp, isOvercharged, os.clock()),
		model = buildModel(BOSS_ID_BY_BIOME[biomeId] or "MossbackGolem", arena),
		arena = arena,
		floorY = spawn.Position.Y,
		obstacles = collectObstacles(arena),
		boulders = {},
	}
	boss.model:SetAttribute("Health", maxHp)
	boss.model:SetAttribute("MaxHealth", maxHp)
	boss.model:SetAttribute("BiomeId", biomeId)
	placeModel(boss)
	bosses[biomeId] = boss
end

-- ArenaCycleService.onDespawnBoss (timeout, everyone eliminated, or after defeat).
function BossAIService.despawn(biomeId: string)
	local boss = bosses[biomeId]
	if boss then
		teardown(boss)
	end
end

-- CombatService reports a validated ball hit on the boss.
function BossAIService.applyDamage(biomeId: string, amount: number, attackerId: number?): boolean
	local boss = bosses[biomeId]
	if not boss then
		return false
	end
	local result = BossAIStateMachine.applyDamage(boss.fsm, amount, os.clock(), attackerId)
	dispatch(boss, result.actions)
	return result.ok
end

-- Swept-sphere target for CombatService, or nil when this biome has no live boss.
function BossAIService.getHitTarget(biomeId: string): CombatMath.SweepTarget?
	local boss = bosses[biomeId]
	if not boss then
		return nil
	end
	return {
		id = biomeId,
		kind = "Boss",
		position = boss.fsm.position,
		radius = boss.fsm.config.hitRadius,
	}
end

function BossAIService.getHealth(biomeId: string): (number?, number?)
	local boss = bosses[biomeId]
	if not boss then
		return nil, nil
	end
	return boss.fsm.currentHp, boss.fsm.maxHp
end

function BossAIService.getModel(biomeId: string): Model?
	local boss = bosses[biomeId]
	return if boss then boss.model else nil
end

return BossAIService
