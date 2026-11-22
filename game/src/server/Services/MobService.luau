--!strict
--[[
	MobService (Issue #5): Meadow PvE mobs at the map's MobSpawns. One Heartbeat moves
	every mob; hits are resolved by CombatService against the spheres this exposes.
	PvE layers stay PvP-immune; mobs only damage players by contact.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BiomeConfigs = require(Shared.Configs.BiomeConfigs)
local CombatConfigs = require(Shared.Configs.CombatConfigs)
local CombatMath = require(Shared.Utils.CombatMath)

type Mob = {
	id: string,
	kind: string,
	biomeId: string,
	config: CombatConfigs.MobConfig,
	home: Vector3,
	position: Vector3,
	hp: number,
	alive: boolean,
	respawnAt: number,
	nextContactAt: number,
	model: Model,
}

local AGGRO_RADIUS = 45 -- studs from the mob
local LEASH_RADIUS = 70 -- studs from home before it walks back
local CONTACT_COOLDOWN = 1.0
local GROUND_OFFSET = 2.5

local MobService = {}

local mobs: { [string]: Mob } = {}

local function placeholder(kind: string, parent: Instance): Model
	local folder = ServerStorage:FindFirstChild("MobModels")
	local template = folder and folder:FindFirstChild(kind)
	local model: Model
	if template and template:IsA("Model") then
		model = template:Clone()
	else
		model = Instance.new("Model")
		local body = Instance.new("Part")
		body.Name = "Body"
		local slime = kind == "MossSlime"
		body.Shape = if slime then Enum.PartType.Ball else Enum.PartType.Block
		body.Size = if slime then Vector3.new(4, 4, 4) else Vector3.new(4, 4, 6.5)
		body.Color = if slime then Color3.fromRGB(110, 200, 90) else Color3.fromRGB(120, 80, 50)
		body.Material = if slime then Enum.Material.SmoothPlastic else Enum.Material.Wood
		body.Parent = model
		model.PrimaryPart = body
	end
	model.Name = kind
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
		end
	end
	model.Parent = parent
	return model
end

local function spawnPoints(biomeFolder: Instance): { BasePart }
	local layer = biomeFolder:FindFirstChild("PvELayer")
	local folder = layer and layer:FindFirstChild("MobSpawns")
	local points = {}
	local children: { Instance } = if folder then folder:GetChildren() else {}
	for _, child in children do
		if child:IsA("BasePart") then
			table.insert(points, child)
		end
	end
	return points
end

local function nearestPlayer(position: Vector3, home: Vector3): (Player?, BasePart?, Humanoid?)
	local best: Player?, bestRoot: BasePart?, bestHum: Humanoid?, bestDist =
		nil, nil, nil, AGGRO_RADIUS
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
			local dist = (root.Position - position).Magnitude
			if dist < bestDist and (root.Position - home).Magnitude <= LEASH_RADIUS then
				best, bestRoot, bestHum, bestDist = player, root, humanoid, dist
			end
		end
	end
	return best, bestRoot, bestHum
end

local function stepMob(mob: Mob, now: number, dt: number)
	if not mob.alive then
		if now >= mob.respawnAt then
			mob.alive, mob.hp, mob.position = true, mob.config.maxHp, mob.home
			for _, part in mob.model:GetDescendants() do
				if part:IsA("BasePart") then
					part.Transparency = 0
				end
			end
		end
		return
	end
	local _, root, humanoid = nearestPlayer(mob.position, mob.home)
	local goal = if root then root.Position else mob.home
	local flat = Vector3.new(goal.X - mob.position.X, 0, goal.Z - mob.position.Z)
	local reach = mob.config.hitRadius + 1.5
	if flat.Magnitude > reach then
		local step = math.min(mob.config.walkSpeed * dt, flat.Magnitude - reach)
		mob.position += flat.Unit * step
	elseif humanoid and now >= mob.nextContactAt then
		mob.nextContactAt = now + CONTACT_COOLDOWN
		humanoid:TakeDamage(mob.config.contactDamage)
	end
	local facing = if flat.Magnitude > 0.01
		then mob.position + flat.Unit
		else mob.position + Vector3.zAxis
	mob.model:PivotTo(CFrame.lookAt(mob.position, Vector3.new(facing.X, mob.position.Y, facing.Z)))
end

local function onHeartbeat(dt: number)
	local now = os.clock()
	for _, mob in mobs do
		stepMob(mob, now, dt)
	end
end

function MobService.init(mapRoot: Instance)
	local biomes = mapRoot:FindFirstChild("Biomes")
	local count = 0
	local biomeFolders: { Instance } = if biomes then biomes:GetChildren() else {}
	for _, biomeFolder in biomeFolders do
		local config = BiomeConfigs.get(biomeFolder.Name)
		local kinds = if config then config.mobKinds else {}
		local points: { BasePart } = if #kinds > 0 then spawnPoints(biomeFolder) else {}
		for i, point in points do
			count += 1
			local kind = kinds[(i - 1) % #kinds + 1]
			local home = point.Position + Vector3.new(0, GROUND_OFFSET, 0)
			local mob: Mob = {
				id = `Mob:{count}`,
				kind = kind,
				biomeId = biomeFolder.Name,
				config = CombatConfigs.Mobs[kind],
				home = home,
				position = home,
				hp = CombatConfigs.Mobs[kind].maxHp,
				alive = true,
				respawnAt = 0,
				nextContactAt = 0,
				model = placeholder(kind, point.Parent or biomeFolder),
			}
			mob.model:PivotTo(CFrame.new(home))
			mobs[mob.id] = mob
		end
	end
	RunService.Heartbeat:Connect(onHeartbeat)
end

function MobService.getTargets(): { CombatMath.SweepTarget }
	local targets = {}
	for id, mob in mobs do
		if mob.alive then
			local p = mob.position
			table.insert(targets, {
				id = id,
				kind = "Mob",
				position = { X = p.X, Y = p.Y, Z = p.Z },
				radius = mob.config.hitRadius,
			})
		end
	end
	return targets
end

-- Returns the mob kind and its biome's PvE multiplier when this hit kills it.
function MobService.applyDamage(mobId: string, amount: number): (string?, number?)
	local mob = mobs[mobId]
	if not mob or not mob.alive or not (amount > 0) then
		return nil, nil
	end
	mob.hp -= amount
	if mob.hp > 0 then
		return nil, nil
	end
	mob.alive = false
	mob.respawnAt = os.clock() + mob.config.respawnSeconds
	for _, part in mob.model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Transparency = 1
		end
	end
	local biome = BiomeConfigs.get(mob.biomeId)
	return mob.kind, if biome then biome.pveDamageMultiplier else 1
end

return MobService
