--!strict
--[[
	BossAIService.luau
	Server-authoritative AI for all 3 Biome Bosses (Mossback Golem, Glacier Yeti, Obsidian Wyrm)
	with telegraphed AoE/Cone/Projectile/Ring/Geyser attacks AND all Open PvE Layer Mob Spawns.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BiomeConfigs = require(Shared.Configs.BiomeConfigs)
local EconomyLogic = require(Shared.Utils.EconomyLogic)
local ProceduralModels = require(Shared.Utils.ProceduralModels)
local Remotes = require(Shared.Net.Remotes)

local DataService = require(script.Parent.DataService)
local ArenaCycleService = require(script.Parent.ArenaCycleService)

export type ActiveMob = {
	id: string,
	mobType: string,
	biomeId: string,
	spawnPart: BasePart,
	model: Model?,
	hp: number,
	maxHP: number,
	alive: boolean,
	respawnAt: number,
	lastAttackAt: number,
	slowUntil: number,
	stunUntil: number,
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
local activeBosses: { [string]: ActiveBoss } = {}
local bossByModel: { [Model]: ActiveBoss } = {}

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
	local groundOffset = tonumber(model:GetAttribute("GroundOffsetY")) or 3.2
	local sp = mob.spawnPart.Position
	local spawnCF = CFrame.new(sp.X, sp.Y + groundOffset, sp.Z)
		* CFrame.Angles(0, math.random() * math.pi * 2, 0)
	model:PivotTo(spawnCF)
	model.Parent = mob.spawnPart.Parent
	mob.model = model
	mob.hp = cfg.maxHP
	mob.maxHP = cfg.maxHP
	mob.alive = true
	mobByModel[model] = mob
	updateHealthBar(model, mob.hp, mob.maxHP)
end

local function discoverMobSpawns()
	local idx = 0
	for _, pad in ipairs(CollectionService:GetTagged("MobSpawnZone")) do
		if pad:IsA("BasePart") then
			local biomeId = tostring(pad:GetAttribute("BiomeId") or "")
			local mobType = tostring(pad:GetAttribute("MobType") or "")
			local cfg = BiomeConfigs.MOBS[mobType]
			if cfg and BiomeConfigs.getBiome(biomeId) then
				idx += 1
				local mob: ActiveMob = {
					id = `mob_{idx}`,
					mobType = mobType,
					biomeId = biomeId,
					spawnPart = pad,
					model = nil,
					hp = cfg.maxHP,
					maxHP = cfg.maxHP,
					alive = false,
					respawnAt = 0,
					lastAttackAt = 0,
					slowUntil = 0,
					stunUntil = 0,
				}
				table.insert(mobs, mob)
				spawnMobInstance(mob)
			end
		end
	end
end

local function findNearestTarget(
	pos: Vector3,
	maxRange: number,
	requiredZone: string,
	biomeId: string
): (Player?, BasePart?)
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
	return bestPlr, bestHrp
end

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

	-- Broadcast telegraph indicator to clients
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
	local now = os.clock()
	if slowDur > 0 then
		boss.slowUntil = math.max(boss.slowUntil, now + slowDur)
	end
	if stunDur > 0 then
		boss.stunUntil = math.max(boss.stunUntil, now + stunDur)
	end
	local ok = ArenaCycleService.damageBoss(boss.biomeId, attacker, damage)
	local st = ArenaCycleService.getBiomeState(boss.biomeId)
	if ok and st and activeBosses[boss.biomeId] == boss then
		updateHealthBar(boss.model, st.bossHP, st.bossMaxHP)
	end
	return ok
end

function BossAIService.init()
	ArenaCycleService.setBossHooks(BossAIService.spawnBoss, BossAIService.clearBoss)
	discoverMobSpawns()
end

local function smoothStepModel(model: Model, nextPos: Vector3, lookAtPos: Vector3, dt: number)
	local curCF = model:GetPivot()
	local targetCF = CFrame.lookAt(nextPos, Vector3.new(lookAtPos.X, nextPos.Y, lookAtPos.Z))
	local turnAlpha = 1 - math.exp(-8 * dt)
	local blendedRot = curCF.Rotation:Lerp(targetCF.Rotation, turnAlpha)
	model:PivotTo(CFrame.new(nextPos) * blendedRot)
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
	if not cfg or now < mob.stunUntil then
		mob.model:SetAttribute("IsMoving", false)
		return
	end
	local speedMult = if now < mob.slowUntil then 0.7 else 1.0
	local targetPlr, targetHrp = findNearestTarget(root.Position, 58, "BiomePvE", mob.biomeId)
	if targetPlr and targetHrp then
		local toTarget = Vector3.new(
			targetHrp.Position.X - root.Position.X,
			0,
			targetHrp.Position.Z - root.Position.Z
		)
		local dist = toTarget.Magnitude
		if dist > cfg.attackRange then
			local step = math.min(dist - cfg.attackRange + 0.5, cfg.moveSpeed * speedMult * dt)
			local nextPos = root.Position + toTarget.Unit * step
			smoothStepModel(mob.model, nextPos, targetHrp.Position, dt)
			mob.model:SetAttribute("IsMoving", true)
		else
			mob.model:SetAttribute("IsMoving", false)
			smoothStepModel(mob.model, root.Position, targetHrp.Position, dt)
			if now >= mob.lastAttackAt + cfg.attackCooldown then
				mob.lastAttackAt = now
				local atkSeq = (tonumber(mob.model:GetAttribute("AttackSeq")) or 0) + 1
				mob.model:SetAttribute("AttackSeq", atkSeq)
				local hum = if targetPlr.Character
					then targetPlr.Character:FindFirstChildOfClass("Humanoid")
					else nil
				if hum and hum.Health > 0 then
					hum.Health = math.max(0, hum.Health - cfg.attackDamage)
				end
			end
		end
	else
		local groundOffset = tonumber(mob.model:GetAttribute("GroundOffsetY")) or 3.2
		local sp = mob.spawnPart.Position
		local home = Vector3.new(sp.X, sp.Y + groundOffset, sp.Z)
		local toHome = Vector3.new(home.X - root.Position.X, 0, home.Z - root.Position.Z)
		if toHome.Magnitude > 2.5 then
			local nextPos = root.Position
				+ toHome.Unit * math.min(toHome.Magnitude, cfg.moveSpeed * 0.65 * dt)
			smoothStepModel(mob.model, nextPos, home, dt)
			mob.model:SetAttribute("IsMoving", true)
		else
			mob.model:SetAttribute("IsMoving", false)
		end
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
		for biomeId, boss in pairs(activeBosses) do
			stepSingleBoss(biomeId, boss, now, dt)
		end
	end)
end

return BossAIService
