--!strict
--[[
	BossAIService.luau
	Server-authoritative AI for all 3 Biome Bosses (Mossback Golem, Glacier Yeti, Obsidian Wyrm — UNTOUCHED)
	AND Open PvE Layer Mob Spawns with:
	- Multi-mob pack spawning & perched Watchtower balcony support
	- Spatial dormancy culling (>160 studs), bridge/river ground raycasting, & whisker obstacle steering
	- Distinct Emerald Meadow archetypes (Hopper, Skirmisher, Charger, RangedCaster, Guardian)
	- Strictly NON-HOMING server-authoritative ballistic mob projectiles with physical Spherecast collision
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BiomeConfigs = require(Shared.Configs.BiomeConfigs)
local EconomyLogic = require(Shared.Utils.EconomyLogic)
local MobCombatLogic = require(Shared.Utils.MobCombatLogic)
local ProceduralModels = require(Shared.Utils.ProceduralModels)
local Remotes = require(Shared.Net.Remotes)

local DataService = require(script.Parent.DataService)
local ArenaCycleService = require(script.Parent.ArenaCycleService)

export type ActiveMob = {
	id: string,
	mobType: string,
	biomeId: string,
	spawnPart: BasePart,
	homePos: Vector3,
	isPerched: boolean,
	perchAxis: Vector3,
	perchOffset: number,
	strafeSign: number,
	patrolTarget: Vector3?,
	nextPatrolAt: number,
	model: Model?,
	hp: number,
	maxHP: number,
	alive: boolean,
	respawnAt: number,
	lastAttackAt: number,
	lastRangedAt: number,
	lastChargeAt: number,
	telegraphKind: string?,
	telegraphEndsAt: number,
	telegraphTarget: Player?,
	telegraphSnapshot: Vector3?,
	chargeDir: Vector3?,
	chargeEndsAt: number,
	chargeHitUsers: { [number]: boolean },
	recoveryEndsAt: number,
	slowUntil: number,
	stunUntil: number,
}

type ActiveMobProjectile = {
	id: number,
	biomeId: string,
	shooterModel: Model?,
	projectileId: string,
	pos: Vector3,
	vel: Vector3,
	gravity: number,
	hitRadius: number,
	aoeRadius: number,
	damage: number,
	slowDuration: number,
	knockbackStrength: number,
	color: { number },
	expiresAt: number,
}

export type ActiveBoss = {
	biomeId: string,
	bossId: string,
	model: Model,
	spawnCF: CFrame,
	isOvercharged: boolean,
	nextAttackAt: number,
	attackIndex: number,
	slowUntil: number,
	stunUntil: number,
}

local BossAIService = {}

local mobs: { ActiveMob } = {}
local mobByModel: { [Model]: ActiveMob } = {}
local activeMobProjectiles: { ActiveMobProjectile } = {}
local activeBosses: { [string]: ActiveBoss } = {}
local bossByModel: { [Model]: ActiveBoss } = {}
local nextMobProjId = 900000

local function updateHealthBar(model: Model, hp: number, maxHP: number)
	local root = model.PrimaryPart
	local bb = if root then root:FindFirstChild("HealthBillboard") else nil
	local bg = if bb then bb:FindFirstChild("BarBg") else nil
	local fill = if bg then bg:FindFirstChild("Fill") else nil
	if fill and fill:IsA("Frame") then
		local frac = math.clamp(hp / math.max(1, maxHP), 0, 1)
		fill.Size = UDim2.fromScale(frac, 1)
	end
end

local function isWorldGeometryPart(part: BasePart): boolean
	if not part.CanCollide or part.Transparency >= 0.85 then
		return false
	end
	if mobByModel[part.Parent :: any] or part:FindFirstAncestorOfClass("Model") == nil then
		return part.CanCollide
	end
	local mdl = part:FindFirstAncestorOfClass("Model")
	if mdl and (mobByModel[mdl] or bossByModel[mdl] or Players:GetPlayerFromCharacter(mdl)) then
		return false
	end
	return true
end

local function sampleGroundY(x: number, refY: number, z: number, mobModel: Model?): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local excluded: { Instance } = {}
	if mobModel then
		table.insert(excluded, mobModel)
	end
	params.FilterDescendantsInstances = excluded
	local origin = Vector3.new(x, refY + 8, z)
	for _ = 1, 4 do
		local res = workspace:Raycast(origin, Vector3.new(0, -18, 0), params)
		if not res or not res.Instance or not res.Instance:IsA("BasePart") then
			return 0
		end
		if isWorldGeometryPart(res.Instance) then
			return res.Position.Y
		end
		table.insert(excluded, res.Instance)
		params.FilterDescendantsInstances = excluded
	end
	return 0
end

local function steerAroundObstacles(pos: Vector3, desiredDir: Vector3, mobModel: Model): Vector3
	local flat = Vector3.new(desiredDir.X, 0, desiredDir.Z)
	if flat.Magnitude < 1e-4 then
		return Vector3.zero
	end
	local fwd = flat.Unit
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { mobModel }

	local res = workspace:Raycast(pos + Vector3.new(0, 1.0, 0), fwd * 6.5, params)
	if not res or not res.Instance:IsA("BasePart") or not isWorldGeometryPart(res.Instance) then
		return fwd
	end
	for _, angDeg in ipairs({ 36, -36, 72, -72 }) do
		local cand = (CFrame.Angles(0, math.rad(angDeg), 0) * fwd).Unit
		local r2 = workspace:Raycast(pos + Vector3.new(0, 1.0, 0), cand * 6.5, params)
		if not r2 or not r2.Instance:IsA("BasePart") or not isWorldGeometryPart(r2.Instance) then
			return cand
		end
	end
	return fwd
end

local function applyPlayerKnockback(victim: Player, dir: Vector3, strength: number)
	if strength <= 0 then
		return
	end
	local char = victim.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
	if not hrp or not hrp:IsA("BasePart") then
		return
	end
	local flat = Vector3.new(dir.X, 0, dir.Z)
	local pushDir = if flat.Magnitude > 0.05 then flat.Unit else Vector3.zAxis
	local att = Instance.new("Attachment")
	att.Parent = hrp
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.MaxForce = hrp.AssemblyMass * workspace.Gravity * 18
	lv.VectorVelocity =
		Vector3.new(pushDir.X * strength, math.max(10, strength * 0.4), pushDir.Z * strength)
	lv.Parent = hrp
	task.delay(0.18, function()
		lv:Destroy()
		att:Destroy()
	end)
end

local function damagePvePlayer(
	player: Player,
	biomeId: string,
	damage: number,
	slowDur: number,
	kbDir: Vector3?,
	kbStrength: number
)
	if
		player:GetAttribute("Zone") ~= "BiomePvE"
		or player:GetAttribute("ActiveBiome") ~= biomeId
	then
		return
	end
	local char = player.Character
	local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
	if not hum or hum.Health <= 0 then
		return
	end
	hum.Health = math.max(0, hum.Health - damage)
	if slowDur > 0 then
		player:SetAttribute(
			"FrostSlowUntil",
			math.max(tonumber(player:GetAttribute("FrostSlowUntil")) or 0, os.clock() + slowDur)
		)
	end
	if kbDir and kbStrength > 0 then
		applyPlayerKnockback(player, kbDir, kbStrength)
	end
end

local function spawnMobInstance(mob: ActiveMob)
	if mob.model then
		mobByModel[mob.model] = nil
		mob.model:Destroy()
		mob.model = nil
	end
	local cfg = BiomeConfigs.MOBS[mob.mobType]
	if not cfg then
		return
	end
	local model = ProceduralModels.createMobModel(mob.mobType)
	model:SetAttribute("EntityKind", "PvEMob")
	model:SetAttribute("BiomeId", mob.biomeId)
	model:SetAttribute("MobType", mob.mobType)
	model:SetAttribute("IsElite", cfg.isElite == true)
	model:SetAttribute("IsPerched", mob.isPerched)
	model:SetAttribute("IsTelegraphing", false)
	local groundOffset = tonumber(model:GetAttribute("GroundOffsetY")) or 3.2
	local baseY = if mob.isPerched
		then mob.homePos.Y + groundOffset + 0.85
		else sampleGroundY(mob.homePos.X, mob.homePos.Y, mob.homePos.Z, model) + groundOffset
	local spawnPos = Vector3.new(mob.homePos.X, baseY, mob.homePos.Z)
	local spawnCF = CFrame.new(spawnPos) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
	model:PivotTo(spawnCF)
	model.Parent = mob.spawnPart.Parent
	mob.model = model
	mob.hp = cfg.maxHP
	mob.maxHP = cfg.maxHP
	mob.alive = true
	mob.perchOffset = 0
	mob.telegraphKind = nil
	mob.chargeDir = nil
	mob.chargeHitUsers = {}
	mob.recoveryEndsAt = 0
	mobByModel[model] = mob
	updateHealthBar(model, mob.hp, mob.maxHP)
end

local function registerPadMobs(pad: BasePart, biomeId: string, nextIdx: number): number
	local primaryType = tostring(pad:GetAttribute("MobType") or "")
	local primaryCount = math.max(1, math.floor(tonumber(pad:GetAttribute("SpawnCount")) or 1))
	local escortType = tostring(pad:GetAttribute("EscortMobType") or "")
	local escortCount = if escortType ~= ""
		then math.max(1, math.floor(tonumber(pad:GetAttribute("EscortCount")) or 1))
		else 0
	local isPerched = pad:GetAttribute("IsPerched") == true
	local rawAxis = pad:GetAttribute("PerchAxis")
	local perchAxis = if typeof(rawAxis) == "Vector3" and rawAxis.Magnitude > 0.05
		then Vector3.new(rawAxis.X, 0, rawAxis.Z).Unit
		else Vector3.xAxis

	local entries: { string } = {}
	if BiomeConfigs.MOBS[primaryType] then
		for _ = 1, primaryCount do
			table.insert(entries, primaryType)
		end
	end
	if escortCount > 0 and BiomeConfigs.MOBS[escortType] then
		for _ = 1, escortCount do
			table.insert(entries, escortType)
		end
	end
	if #entries == 0 then
		return nextIdx
	end

	local offsets = MobCombatLogic.computePackOffsets(#entries, if isPerched then 0 else 6.5)
	for i, mType in ipairs(entries) do
		local cfg = BiomeConfigs.MOBS[mType]
		if cfg then
			nextIdx += 1
			local off = offsets[i] or { 0, 0 }
			local homePos =
				Vector3.new(pad.Position.X + off[1], pad.Position.Y, pad.Position.Z + off[2])
			local mob: ActiveMob = {
				id = `mob_{nextIdx}`,
				mobType = mType,
				biomeId = biomeId,
				spawnPart = pad,
				homePos = homePos,
				isPerched = isPerched,
				perchAxis = perchAxis,
				perchOffset = 0,
				strafeSign = if (nextIdx % 2) == 0 then 1 else -1,
				patrolTarget = nil,
				nextPatrolAt = 0,
				model = nil,
				hp = cfg.maxHP,
				maxHP = cfg.maxHP,
				alive = false,
				respawnAt = 0,
				lastAttackAt = 0,
				lastRangedAt = 0,
				lastChargeAt = 0,
				telegraphKind = nil,
				telegraphEndsAt = 0,
				telegraphTarget = nil,
				telegraphSnapshot = nil,
				chargeDir = nil,
				chargeEndsAt = 0,
				chargeHitUsers = {},
				recoveryEndsAt = 0,
				slowUntil = 0,
				stunUntil = 0,
			}
			table.insert(mobs, mob)
			spawnMobInstance(mob)
		end
	end
	return nextIdx
end

local function discoverMobSpawns()
	local idx = 0
	for _, pad in ipairs(CollectionService:GetTagged("MobSpawnZone")) do
		if pad:IsA("BasePart") then
			local biomeId = tostring(pad:GetAttribute("BiomeId") or "")
			if BiomeConfigs.getBiome(biomeId) then
				idx = registerPadMobs(pad, biomeId, idx)
			end
		end
	end
end

local function findNearestTarget(
	pos: Vector3,
	maxRange: number,
	requiredZone: string,
	biomeId: string
): (Player?, BasePart?, number?)
	local bestPlr: Player? = nil
	local bestHrp: BasePart? = nil
	local bestDist = maxRange
	for _, plr in ipairs(Players:GetPlayers()) do
		if
			plr:GetAttribute("Zone") == requiredZone
			and plr:GetAttribute("ActiveBiome") == biomeId
		then
			local char = plr.Character
			local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
			local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
			if hrp and hrp:IsA("BasePart") and hum and hum.Health > 0 then
				local d = (hrp.Position - pos).Magnitude
				if d < bestDist then
					bestDist = d
					bestPlr = plr
					bestHrp = hrp
				end
			end
		end
	end
	if not bestPlr then
		return nil, nil, nil
	end
	return bestPlr, bestHrp, bestDist
end

-- =============================================================================
-- SERVER-AUTHORITATIVE NON-HOMING MOB BALLISTIC PROJECTILES
-- =============================================================================
local function spawnSingleMobBallisticOrb(
	mob: ActiveMob,
	spec: BiomeConfigs.MobRangedAttackSpec,
	targetPos: Vector3,
	yawSpreadDeg: number
)
	if not mob.alive or not mob.model or not mob.model.PrimaryPart then
		return
	end
	local root = mob.model.PrimaryPart
	local flat = Vector3.new(targetPos.X - root.Position.X, 0, targetPos.Z - root.Position.Z)
	local fwd = if flat.Magnitude > 0.1 then flat.Unit else root.CFrame.LookVector
	local launchOrigin = if mob.isPerched
		then root.Position + Vector3.new(0, 1.8, 0) + fwd * 2.2
		else root.Position + Vector3.new(0, 1.5, 0) + fwd * 1.6

	local vx, vy, vz = MobCombatLogic.solveBallisticVelocity(
		launchOrigin.X,
		launchOrigin.Y,
		launchOrigin.Z,
		targetPos.X,
		targetPos.Y,
		targetPos.Z,
		spec.speed,
		spec.gravity,
		spec.highArc,
		spec.maxPitchDeg
	)
	vx, vy, vz = MobCombatLogic.applyHorizontalSpread(vx, vy, vz, yawSpreadDeg)
	local vel = Vector3.new(vx, vy, vz)

	nextMobProjId += 1
	local projId = nextMobProjId
	local maxFlight = 4.2
	table.insert(activeMobProjectiles, {
		id = projId,
		biomeId = mob.biomeId,
		shooterModel = mob.model,
		projectileId = spec.projectileId,
		pos = launchOrigin,
		vel = vel,
		gravity = spec.gravity,
		hitRadius = spec.hitRadius,
		aoeRadius = spec.aoeRadius,
		damage = spec.damage,
		slowDuration = spec.slowDuration,
		knockbackStrength = spec.knockbackStrength,
		color = spec.color,
		expiresAt = os.clock() + maxFlight,
	})

	Remotes.ensureServer().ProjectileBroadcast:FireAllClients({
		msgKind = "MobLaunch",
		ballId = projId,
		projectileId = spec.projectileId,
		origin = launchOrigin,
		launchVel = vel,
		gravity = spec.gravity,
		color = spec.color,
		maxFlight = maxFlight,
	})
end

local function launchMobBallisticVolley(mob: ActiveMob, spec: BiomeConfigs.MobRangedAttackSpec)
	if not mob.model then
		return
	end
	local atkSeq = (tonumber(mob.model:GetAttribute("AttackSeq")) or 0) + 1
	mob.model:SetAttribute("AttackSeq", atkSeq)

	local targetPos = mob.telegraphSnapshot
	local plr = mob.telegraphTarget
	if plr and plr.Parent and plr.Character then
		local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			local lead = if spec.leadSeconds > 0
				then Vector3.new(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z)
					* math.min(spec.leadSeconds, 0.20)
				else Vector3.zero
			targetPos = hrp.Position + lead
		end
	end
	if not targetPos then
		return
	end

	local count = math.max(1, spec.volleyCount)
	for i = 1, count do
		local spread = if count > 1
			then (if i % 2 == 1 then -spec.spreadDeg else spec.spreadDeg)
			else 0
		if i == 1 or spec.volleyIntervalSec <= 0 then
			spawnSingleMobBallisticOrb(mob, spec, targetPos, spread)
		else
			local snap = targetPos
			task.delay((i - 1) * spec.volleyIntervalSec, function()
				spawnSingleMobBallisticOrb(mob, spec, snap, spread)
			end)
		end
	end
end

local function detonateMobProjectile(
	proj: ActiveMobProjectile,
	impactPos: Vector3,
	directPlayer: Player?
)
	local hitAny = false
	for _, plr in ipairs(Players:GetPlayers()) do
		if
			plr:GetAttribute("Zone") == "BiomePvE"
			and plr:GetAttribute("ActiveBiome") == proj.biomeId
		then
			local char = plr.Character
			local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
			if hrp and hrp:IsA("BasePart") then
				local isDirect = plr == directPlayer
				local inSplash = MobCombatLogic.isWithinSplash(
					impactPos.X,
					impactPos.Y,
					impactPos.Z,
					hrp.Position.X,
					hrp.Position.Y,
					hrp.Position.Z,
					proj.aoeRadius
				)
				if isDirect or inSplash then
					hitAny = true
					local pushDir = hrp.Position - impactPos
					damagePvePlayer(
						plr,
						proj.biomeId,
						proj.damage,
						proj.slowDuration,
						pushDir,
						proj.knockbackStrength
					)
				end
			end
		end
	end
	Remotes.ensureServer().ProjectileBroadcast:FireAllClients({
		msgKind = "MobImpact",
		ballId = proj.id,
		pos = impactPos,
		aoeRadius = proj.aoeRadius,
		color = proj.color,
		hitPlayer = hitAny,
	})
end

local function castMobProjectileSegment(
	proj: ActiveMobProjectile,
	delta: Vector3
): (Vector3?, Player?)
	local excluded: { Instance } = {}
	if proj.shooterModel then
		table.insert(excluded, proj.shooterModel)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	for _ = 1, 5 do
		params.FilterDescendantsInstances = excluded
		local res = workspace:Spherecast(proj.pos, proj.hitRadius, delta, params)
		if not res or not res.Instance or not res.Instance:IsA("BasePart") then
			return nil, nil
		end
		local part = res.Instance
		local mdl = part:FindFirstAncestorOfClass("Model")
		local hitPlr = if mdl then Players:GetPlayerFromCharacter(mdl) else nil
		if hitPlr then
			if
				hitPlr:GetAttribute("Zone") == "BiomePvE"
				and hitPlr:GetAttribute("ActiveBiome") == proj.biomeId
			then
				return res.Position, hitPlr
			end
			table.insert(excluded, mdl :: Instance)
		elseif mdl and (mobByModel[mdl] or bossByModel[mdl]) then
			table.insert(excluded, mdl)
		elseif not part.CanCollide and part.Transparency >= 0.85 then
			table.insert(excluded, part)
		else
			return res.Position, nil
		end
	end
	return nil, nil
end

local function stepAllMobProjectiles(now: number, dt: number)
	if #activeMobProjectiles == 0 then
		return
	end
	for i = #activeMobProjectiles, 1, -1 do
		local proj = activeMobProjectiles[i]
		if now >= proj.expiresAt or proj.pos.Y < -35 then
			table.remove(activeMobProjectiles, i)
			Remotes.ensureServer().ProjectileBroadcast:FireAllClients({
				msgKind = "Despawn",
				ballId = proj.id,
			})
			continue
		end
		local nx, ny, nz, nvx, nvy, nvz = MobCombatLogic.stepBallisticPoint(
			proj.pos.X,
			proj.pos.Y,
			proj.pos.Z,
			proj.vel.X,
			proj.vel.Y,
			proj.vel.Z,
			dt,
			proj.gravity
		)
		local nextPos = Vector3.new(nx, ny, nz)
		local delta = nextPos - proj.pos
		if delta.Magnitude >= 0.05 then
			local hitPos, hitPlr = castMobProjectileSegment(proj, delta)
			if hitPos then
				table.remove(activeMobProjectiles, i)
				detonateMobProjectile(proj, hitPos, hitPlr)
				continue
			end
		end
		proj.pos = nextPos
		proj.vel = Vector3.new(nvx, nvy, nvz)
	end
end

-- =============================================================================
-- BIOME BOSS AI (100% UNTOUCHED)
-- =============================================================================
local function executeBossAttack(boss: ActiveBoss, targetPos: Vector3)
	local cfg = BiomeConfigs.BOSSES[boss.bossId]
	if not cfg or #cfg.attacks == 0 then
		return
	end
	boss.attackIndex = (boss.attackIndex % #cfg.attacks) + 1
	local atk = cfg.attacks[boss.attackIndex]
	local remotes = Remotes.ensureServer()
	local origin = if boss.model.PrimaryPart
		then boss.model.PrimaryPart.Position
		else boss.spawnCF.Position
	local impactPos = if atk.kind == "Shockwave" or atk.kind == "Cone" then origin else targetPos

	remotes.BossTelegraph:FireAllClients({
		biomeId = boss.biomeId,
		kind = atk.kind,
		origin = origin,
		impactPos = impactPos,
		radius = atk.radius,
		telegraphSec = atk.telegraphSec,
		color = cfg.accentColor,
	})

	task.delay(atk.telegraphSec, function()
		if activeBosses[boss.biomeId] ~= boss then
			return
		end
		local st = ArenaCycleService.getBiomeState(boss.biomeId)
		if not st or st.phase ~= "Boss_Phase" then
			return
		end
		local dmgScale = if boss.isOvercharged then 1.25 else 1.0
		for uid in pairs(st.activePlayers) do
			local plr = Players:GetPlayerByUserId(uid)
			local char = if plr then plr.Character else nil
			local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
			local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
			if plr and hrp and hrp:IsA("BasePart") and hum and hum.Health > 0 then
				if (hrp.Position - impactPos).Magnitude <= atk.radius then
					hum.Health = math.max(0, hum.Health - atk.damage * dmgScale)
					if hum.Health <= 0 then
						ArenaCycleService.onPlayerDamagedInPvP(plr, nil, true)
					end
				end
			end
		end
	end)
end

function BossAIService.spawnBoss(
	biomeId: string,
	spawnPart: BasePart,
	maxHP: number,
	isOvercharged: boolean
)
	BossAIService.clearBoss(biomeId)
	local bossCfg = BiomeConfigs.getBossForBiome(biomeId)
	if not bossCfg then
		return
	end
	local model = ProceduralModels.createBossModel(bossCfg.id, isOvercharged)
	model:SetAttribute("EntityKind", "BiomeBoss")
	model:SetAttribute("BiomeId", biomeId)
	model:SetAttribute("BossId", bossCfg.id)
	local spawnCF = spawnPart.CFrame * CFrame.new(0, 7, 0)
	model:PivotTo(spawnCF)
	model.Parent = spawnPart.Parent

	local boss: ActiveBoss = {
		biomeId = biomeId,
		bossId = bossCfg.id,
		model = model,
		spawnCF = spawnCF,
		isOvercharged = isOvercharged,
		nextAttackAt = os.clock() + 2.2,
		attackIndex = 0,
		slowUntil = 0,
		stunUntil = 0,
	}
	activeBosses[biomeId] = boss
	bossByModel[model] = boss
	updateHealthBar(model, maxHP, maxHP)
end

function BossAIService.clearBoss(biomeId: string)
	local existing = activeBosses[biomeId]
	if existing then
		bossByModel[existing.model] = nil
		existing.model:Destroy()
		activeBosses[biomeId] = nil
	end
end

function BossAIService.getMobFromPart(part: BasePart): ActiveMob?
	local cur: Instance? = part
	while cur and cur ~= workspace do
		if cur:IsA("Model") and mobByModel[cur] then
			return mobByModel[cur]
		end
		cur = cur.Parent
	end
	return nil
end

function BossAIService.getBossFromPart(part: BasePart): ActiveBoss?
	local cur: Instance? = part
	while cur and cur ~= workspace do
		if cur:IsA("Model") and bossByModel[cur] then
			return bossByModel[cur]
		end
		cur = cur.Parent
	end
	return nil
end

function BossAIService.getActiveBoss(biomeId: string): ActiveBoss?
	return activeBosses[biomeId]
end

function BossAIService.getNearbyMobs(
	biomeId: string,
	pos: Vector3,
	radius: number,
	exclude: ActiveMob?
): { ActiveMob }
	local out: { ActiveMob } = {}
	for _, m in ipairs(mobs) do
		if
			m.alive
			and m.biomeId == biomeId
			and m ~= exclude
			and m.model
			and m.model.PrimaryPart
		then
			if (m.model.PrimaryPart.Position - pos).Magnitude <= radius then
				table.insert(out, m)
			end
		end
	end
	return out
end

function BossAIService.damageMob(
	mob: ActiveMob,
	attacker: Player,
	damage: number,
	slowDur: number,
	stunDur: number
): boolean
	if not mob.alive or not mob.model then
		return false
	end
	local now = os.clock()
	if slowDur > 0 then
		mob.slowUntil = math.max(mob.slowUntil, now + slowDur)
	end
	if stunDur > 0 then
		mob.stunUntil = math.max(mob.stunUntil, now + stunDur)
	end
	mob.hp = math.max(0, mob.hp - damage)
	updateHealthBar(mob.model, mob.hp, mob.maxHP)
	if mob.hp > 0 then
		local hitSeq = (tonumber(mob.model:GetAttribute("HitSeq")) or 0) + 1
		mob.model:SetAttribute("HitSeq", hitSeq)
	end
	if mob.hp <= 0 then
		local cfg = BiomeConfigs.MOBS[mob.mobType]
		mob.alive = false
		mob.respawnAt = now + (if cfg then cfg.respawnSec else 7)
		mobByModel[mob.model] = nil
		mob.model:Destroy()
		mob.model = nil

		local profile = DataService.getProfile(attacker)
		if profile and cfg then
			local mult = if DataService.hasPass(attacker, "Pass_DoubleCoinsExp") then 2 else 1
			profile.coins += cfg.coinReward * mult
			profile.ballDamage += cfg.ballDmgGain
			local lvls = EconomyLogic.addExp(profile, cfg.expReward * mult)
			if lvls > 0 then
				Remotes.ensureServer().ToastNotify:FireClient(
					attacker,
					`LEVEL UP! Level {profile.level} (+{lvls * 25} Max HP)`,
					{ 74, 222, 128 }
				)
			end
			DataService.syncToClient(attacker)
		end
		return true
	end
	return false
end

function BossAIService.damageBoss(
	boss: ActiveBoss,
	attacker: Player,
	damage: number,
	slowDur: number,
	stunDur: number
): boolean
	local ok = ArenaCycleService.damageBoss(boss.biomeId, attacker, damage)
	if not ok then
		return false
	end
	local now = os.clock()
	if slowDur > 0 then
		boss.slowUntil = math.max(boss.slowUntil, now + slowDur)
	end
	if stunDur > 0 then
		boss.stunUntil = math.max(boss.stunUntil, now + stunDur)
	end
	local st = ArenaCycleService.getBiomeState(boss.biomeId)
	if st and activeBosses[boss.biomeId] == boss then
		updateHealthBar(boss.model, st.bossHP, st.bossMaxHP)
	end
	return true
end

function BossAIService.init()
	ArenaCycleService.setBossHooks(BossAIService.spawnBoss, BossAIService.clearBoss)
	discoverMobSpawns()
end

local function smoothStepModel(model: Model, nextPos: Vector3, lookAtPos: Vector3, dt: number)
	local curCF = model:GetPivot()
	local flatLook = Vector3.new(lookAtPos.X, nextPos.Y, lookAtPos.Z)
	if (flatLook - nextPos).Magnitude < 0.05 then
		model:PivotTo(CFrame.new(nextPos) * curCF.Rotation)
		return
	end
	local targetCF = CFrame.lookAt(nextPos, flatLook)
	local turnAlpha = 1 - math.exp(-8 * dt)
	local blendedRot = curCF.Rotation:Lerp(targetCF.Rotation, turnAlpha)
	model:PivotTo(CFrame.new(nextPos) * blendedRot)
end

local function moveGroundMob(
	mob: ActiveMob,
	root: BasePart,
	dir: Vector3,
	stepDist: number,
	lookTarget: Vector3,
	dt: number
)
	local model = mob.model :: Model
	local steered = if mob.biomeId == "EmeraldMeadow"
		then steerAroundObstacles(root.Position, dir, model)
		else Vector3.new(dir.X, 0, dir.Z).Unit
	local nx = root.Position.X + steered.X * stepDist
	local nz = root.Position.Z + steered.Z * stepDist
	local groundOffset = tonumber(model:GetAttribute("GroundOffsetY")) or 3.2
	local ny = if mob.biomeId == "EmeraldMeadow"
		then sampleGroundY(nx, root.Position.Y, nz, model) + groundOffset
		else root.Position.Y
	smoothStepModel(model, Vector3.new(nx, ny, nz), lookTarget, dt)
	model:SetAttribute("IsMoving", true)
end

local function stepActiveCharge(
	mob: ActiveMob,
	cfg: BiomeConfigs.MobConfig,
	root: BasePart,
	now: number,
	dt: number
): boolean
	local cSpec = cfg.chargeSpec
	local dir = mob.chargeDir
	if not cSpec or not dir then
		return false
	end
	local model = mob.model :: Model
	if now >= mob.chargeEndsAt then
		mob.chargeDir = nil
		mob.recoveryEndsAt = now + cSpec.recoverySec
		model:SetAttribute("IsMoving", false)
		return true
	end
	moveGroundMob(mob, root, dir, cSpec.chargeSpeed * dt, root.Position + dir * 10, dt)
	for _, plr in ipairs(Players:GetPlayers()) do
		if
			not mob.chargeHitUsers[plr.UserId]
			and plr:GetAttribute("Zone") == "BiomePvE"
			and plr:GetAttribute("ActiveBiome") == mob.biomeId
		then
			local hrp = if plr.Character
				then plr.Character:FindFirstChild("HumanoidRootPart")
				else nil
			if
				hrp
				and hrp:IsA("BasePart")
				and (hrp.Position - root.Position).Magnitude <= cSpec.hitRadius
			then
				mob.chargeHitUsers[plr.UserId] = true
				damagePvePlayer(plr, mob.biomeId, cSpec.damage, 0, dir, cSpec.knockbackStrength)
			end
		end
	end
	return true
end

local function stepActiveTelegraph(
	mob: ActiveMob,
	cfg: BiomeConfigs.MobConfig,
	root: BasePart,
	now: number,
	dt: number
): boolean
	local kind = mob.telegraphKind
	if not kind then
		return false
	end
	local model = mob.model :: Model
	model:SetAttribute("IsMoving", false)
	local lookPos = mob.telegraphSnapshot or (root.Position + root.CFrame.LookVector * 10)
	if mob.telegraphTarget and mob.telegraphTarget.Character then
		local hrp = mob.telegraphTarget.Character:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			lookPos = hrp.Position
		end
	end
	smoothStepModel(model, root.Position, lookPos, dt)
	if now < mob.telegraphEndsAt then
		return true
	end

	mob.telegraphKind = nil
	model:SetAttribute("IsTelegraphing", false)
	if kind == "Ranged" and cfg.rangedAttack then
		mob.lastRangedAt = now
		launchMobBallisticVolley(mob, cfg.rangedAttack)
		mob.recoveryEndsAt = now + 0.35
	elseif kind == "Charge" and cfg.chargeSpec then
		mob.lastChargeAt = now
		local flat = Vector3.new(lookPos.X - root.Position.X, 0, lookPos.Z - root.Position.Z)
		mob.chargeDir = if flat.Magnitude > 0.1 then flat.Unit else root.CFrame.LookVector
		mob.chargeEndsAt = now + cfg.chargeSpec.chargeDuration
		mob.chargeHitUsers = {}
		local atkSeq = (tonumber(model:GetAttribute("AttackSeq")) or 0) + 1
		model:SetAttribute("AttackSeq", atkSeq)
	end
	return true
end

local function stepPerchedStrafe(mob: ActiveMob, lookTarget: Vector3, moveSpeed: number, dt: number)
	local model = mob.model :: Model
	local nextOff = mob.perchOffset + mob.strafeSign * moveSpeed * 0.32 * dt
	if math.abs(nextOff) >= 2.5 then
		mob.strafeSign *= -1
		nextOff = MobCombatLogic.clampPerchedOffset(nextOff, 2.5)
	end
	mob.perchOffset = nextOff
	local groundOffset = tonumber(model:GetAttribute("GroundOffsetY")) or 3.0
	local pos = Vector3.new(
		mob.homePos.X + mob.perchAxis.X * nextOff,
		mob.homePos.Y + groundOffset + 0.85,
		mob.homePos.Z + mob.perchAxis.Z * nextOff
	)
	smoothStepModel(model, pos, lookTarget, dt)
	model:SetAttribute("IsMoving", true)
end

local function stepPatrolOrReturn(
	mob: ActiveMob,
	cfg: BiomeConfigs.MobConfig,
	root: BasePart,
	intent: MobCombatLogic.MobIntent,
	now: number,
	dt: number
)
	local model = mob.model :: Model
	if intent == "Dormant" or intent == "PerchedIdle" then
		model:SetAttribute("IsMoving", false)
		return
	end
	if intent == "ReturnHome" then
		local toHome =
			Vector3.new(mob.homePos.X - root.Position.X, 0, mob.homePos.Z - root.Position.Z)
		if toHome.Magnitude > 2.5 then
			moveGroundMob(
				mob,
				root,
				toHome.Unit,
				math.min(toHome.Magnitude, cfg.moveSpeed * 1.15 * dt),
				mob.homePos,
				dt
			)
		else
			model:SetAttribute("IsMoving", false)
			if mob.hp < mob.maxHP then
				mob.hp = mob.maxHP
				updateHealthBar(model, mob.hp, mob.maxHP)
			end
		end
		return
	end
	-- Gentle local patrol inside patrolRadius
	local pRad = cfg.patrolRadius or 12
	if not mob.patrolTarget or now >= mob.nextPatrolAt then
		local ang = math.random() * math.pi * 2
		local r = math.random() * pRad
		mob.patrolTarget = Vector3.new(
			mob.homePos.X + math.cos(ang) * r,
			mob.homePos.Y,
			mob.homePos.Z + math.sin(ang) * r
		)
		mob.nextPatrolAt = now + 3.0 + math.random() * 2.5
	end
	local pt = mob.patrolTarget :: Vector3
	local toPt = Vector3.new(pt.X - root.Position.X, 0, pt.Z - root.Position.Z)
	if toPt.Magnitude > 2.0 then
		moveGroundMob(
			mob,
			root,
			toPt.Unit,
			math.min(toPt.Magnitude, cfg.moveSpeed * 0.45 * dt),
			pt,
			dt
		)
	else
		model:SetAttribute("IsMoving", false)
	end
end

local function executeCombatIntent(
	mob: ActiveMob,
	cfg: BiomeConfigs.MobConfig,
	root: BasePart,
	intent: MobCombatLogic.MobIntent,
	targetPlr: Player,
	targetHrp: BasePart,
	speed: number,
	now: number,
	dt: number
)
	local model = mob.model :: Model
	local toTarget = Vector3.new(
		targetHrp.Position.X - root.Position.X,
		0,
		targetHrp.Position.Z - root.Position.Z
	)
	local dist = toTarget.Magnitude
	local flatDir = if dist > 0.05 then toTarget.Unit else root.CFrame.LookVector

	if intent == "RangedCast" and cfg.rangedAttack then
		mob.telegraphKind = "Ranged"
		mob.telegraphEndsAt = now + cfg.rangedAttack.telegraphSec
		mob.telegraphTarget = targetPlr
		mob.telegraphSnapshot = targetHrp.Position
		model:SetAttribute("IsTelegraphing", true)
		model:SetAttribute("IsMoving", false)
		smoothStepModel(model, root.Position, targetHrp.Position, dt)
	elseif intent == "ChargeTelegraph" and cfg.chargeSpec then
		mob.telegraphKind = "Charge"
		mob.telegraphEndsAt = now + cfg.chargeSpec.telegraphSec
		mob.telegraphTarget = targetPlr
		mob.telegraphSnapshot = targetHrp.Position
		model:SetAttribute("IsTelegraphing", true)
		model:SetAttribute("IsMoving", false)
		smoothStepModel(model, root.Position, targetHrp.Position, dt)
	elseif intent == "MeleeAttack" then
		model:SetAttribute("IsMoving", false)
		smoothStepModel(model, root.Position, targetHrp.Position, dt)
		mob.lastAttackAt = now
		local atkSeq = (tonumber(model:GetAttribute("AttackSeq")) or 0) + 1
		model:SetAttribute("AttackSeq", atkSeq)
		damagePvePlayer(targetPlr, mob.biomeId, cfg.attackDamage, 0, flatDir, 0)
	elseif intent == "Retreat" then
		moveGroundMob(mob, root, -flatDir, speed * 0.85 * dt, targetHrp.Position, dt)
	elseif intent == "Strafe" then
		if mob.isPerched then
			stepPerchedStrafe(mob, targetHrp.Position, speed, dt)
		else
			local strafeDir =
				Vector3.new(-flatDir.Z * mob.strafeSign, 0, flatDir.X * mob.strafeSign)
			if math.random() < dt * 0.45 then
				mob.strafeSign *= -1
			end
			moveGroundMob(mob, root, strafeDir, speed * 0.65 * dt, targetHrp.Position, dt)
		end
	elseif intent == "Chase" then
		local stopDist = math.max(cfg.attackRange - 0.5, 2.0)
		if dist > stopDist then
			moveGroundMob(
				mob,
				root,
				flatDir,
				math.min(dist - stopDist, speed * dt),
				targetHrp.Position,
				dt
			)
		else
			model:SetAttribute("IsMoving", false)
			smoothStepModel(model, root.Position, targetHrp.Position, dt)
		end
	end
end

local function stepSingleMob(mob: ActiveMob, now: number, dt: number)
	if not mob.alive then
		if now >= mob.respawnAt then
			spawnMobInstance(mob)
		end
		return
	end
	if not mob.model or not mob.model.PrimaryPart then
		return
	end
	local cfg = BiomeConfigs.MOBS[mob.mobType]
	local root = mob.model.PrimaryPart
	if not cfg or now < mob.stunUntil or now < mob.recoveryEndsAt then
		mob.model:SetAttribute("IsMoving", false)
		return
	end
	if
		stepActiveCharge(mob, cfg, root, now, dt) or stepActiveTelegraph(mob, cfg, root, now, dt)
	then
		return
	end

	local speedMult = if now < mob.slowUntil then 0.7 else 1.0
	local aggroRange = if mob.isPerched
		then (if cfg.isElite then 125 else 115)
		else (cfg.aggroRange or 58)
	local leashRange = cfg.leashRange or 95
	local targetPlr, targetHrp, distToTarget =
		findNearestTarget(root.Position, MobCombatLogic.DORMANCY_RANGE, "BiomePvE", mob.biomeId)
	local distFromHome =
		Vector3.new(root.Position.X - mob.homePos.X, 0, root.Position.Z - mob.homePos.Z).Magnitude

	local rSpec = cfg.rangedAttack
	local cSpec = cfg.chargeSpec
	local intent = MobCombatLogic.evaluateMobIntent({
		archetype = cfg.archetype or "Hopper",
		isPerched = mob.isPerched,
		distToTarget = distToTarget,
		distFromHome = distFromHome,
		aggroRange = aggroRange,
		leashRange = leashRange,
		meleeRange = cfg.attackRange,
		rangedMin = if rSpec then rSpec.minRange else nil,
		rangedMax = if rSpec then (if mob.isPerched then aggroRange else rSpec.maxRange) else nil,
		preferredMin = cfg.preferredRangeMin,
		preferredMax = cfg.preferredRangeMax,
		chargeMin = if cSpec then cSpec.minRange else nil,
		chargeMax = if cSpec then cSpec.maxRange else nil,
		canRanged = rSpec ~= nil and now >= mob.lastRangedAt + rSpec.cooldownSec,
		canCharge = cSpec ~= nil
			and not mob.isPerched
			and now >= mob.lastChargeAt + cSpec.cooldownSec,
		canMelee = cfg.attackRange > 0 and now >= mob.lastAttackAt + cfg.attackCooldown,
	})

	if
		intent == "Dormant"
		or intent == "Patrol"
		or intent == "ReturnHome"
		or intent == "PerchedIdle"
	then
		stepPatrolOrReturn(mob, cfg, root, intent, now, dt)
	elseif targetPlr and targetHrp then
		executeCombatIntent(
			mob,
			cfg,
			root,
			intent,
			targetPlr,
			targetHrp,
			cfg.moveSpeed * speedMult,
			now,
			dt
		)
	end
end

local function stepSingleBoss(biomeId: string, boss: ActiveBoss, now: number, dt: number)
	local cfg = BiomeConfigs.BOSSES[boss.bossId]
	local root = boss.model.PrimaryPart
	if not cfg or not root or now < boss.stunUntil then
		boss.model:SetAttribute("IsMoving", false)
		return
	end
	local speedMult = if now < boss.slowUntil then 0.75 else 1.0
	local _, targetHrp = findNearestTarget(root.Position, 160, "LockedBossPvP", biomeId)
	if not targetHrp then
		boss.model:SetAttribute("IsMoving", false)
		return
	end
	local toTarget = Vector3.new(
		targetHrp.Position.X - root.Position.X,
		0,
		targetHrp.Position.Z - root.Position.Z
	)
	if toTarget.Magnitude > 14 then
		local nextPos = root.Position + toTarget.Unit * (cfg.moveSpeed * speedMult * dt)
		smoothStepModel(boss.model, nextPos, targetHrp.Position, dt)
		boss.model:SetAttribute("IsMoving", true)
	else
		boss.model:SetAttribute("IsMoving", false)
	end
	if now >= boss.nextAttackAt then
		local atk = cfg.attacks[(boss.attackIndex % #cfg.attacks) + 1]
		local agg = if boss.isOvercharged then BiomeConfigs.OVERCHARGED_AGGRESSION_MULT else 1.0
		boss.nextAttackAt = now + (atk.cooldownSec * agg)
		executeBossAttack(boss, targetHrp.Position)
	end
end

function BossAIService.start()
	RunService.Heartbeat:Connect(function(rawDt: number)
		local dt = math.min(rawDt, 0.08)
		local now = os.clock()
		for _, mob in ipairs(mobs) do
			stepSingleMob(mob, now, dt)
		end
		stepAllMobProjectiles(now, dt)
		for biomeId, boss in pairs(activeBosses) do
			stepSingleBoss(biomeId, boss, now, dt)
		end
	end)
end

return BossAIService
