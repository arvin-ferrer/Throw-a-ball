--!strict
--[[
	CombatService.luau
	Server-authoritative ball throwing with:
	- Real stepped ballistic gravity physics for manual throws (arrival-timed impact & surface normal)
	- Guaranteed-hit server-validated Homing Auto-Aim when Auto-Aim is enabled (tracks Boss/PvP/Mob/Target)
	- Active Follower Ball Perks (all 13 perk types), Dash cooldown, and strict PvP_EggScramble safety guard.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyConfigs = require(Shared.Configs.EconomyConfigs)
local EconomyLogic = require(Shared.Utils.EconomyLogic)
local CombatLogic = require(Shared.Utils.CombatLogic)
local MathUtil = require(Shared.Utils.MathUtil)
local Remotes = require(Shared.Net.Remotes)

local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local ArenaCycleService = require(script.Parent.ArenaCycleService)
local BossAIService = require(script.Parent.BossAIService)

type ResolvedTarget = {
	hitPart: BasePart,
	hitKind: string,
	mob: BossAIService.ActiveMob?,
	boss: BossAIService.ActiveBoss?,
	victim: Player?,
}

type ActiveProjectile = {
	id: number,
	player: Player,
	profile: EconomyLogic.PlayerProfile,
	speed: number,
	pos: Vector3,
	vel: Vector3,
	launchedAt: number,
	firstBounceAt: number?,
	bounceCount: number,
	maxInitialFlight: number,
	homingTarget: ResolvedTarget?,
	homingArrivesAt: number?,
	lastSurfaceBroadcastAt: number,
}

local CombatService = {}

local lastThrowTime: { [number]: number } = {}
local lastDashTime: { [number]: number } = {}
local goldComboByUser: { [number]: number } = {}
local shieldByUser: { [number]: number } = {}
local activeProjectiles: { ActiveProjectile } = {}
local nextBallId = 0
local DASH_COOLDOWN = 2.5

local function applyShield(player: Player, amount: number)
	if amount <= 0 then
		return
	end
	shieldByUser[player.UserId] = math.min(amount * 3, (shieldByUser[player.UserId] or 0) + amount)
	player:SetAttribute("ShieldHP", math.floor(shieldByUser[player.UserId]))
end

local function applyHeal(player: Player, amount: number)
	if amount <= 0 then
		return
	end
	local char = player.Character
	local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
	if hum and hum.Health > 0 then
		hum.Health = math.min(hum.MaxHealth, hum.Health + amount)
	end
end

local function applyPvPKnockback(victim: Player, dir: Vector3, strength: number)
	if strength <= 0 then
		return
	end
	local char = victim.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
	if not hrp or not hrp:IsA("BasePart") then
		return
	end
	local att = Instance.new("Attachment")
	att.Parent = hrp
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.MaxForce = hrp.AssemblyMass * workspace.Gravity * 20
	lv.VectorVelocity = Vector3.new(dir.X, 0.25, dir.Z).Unit * strength
	lv.Parent = hrp
	task.delay(0.2, function()
		lv:Destroy()
		att:Destroy()
	end)
end

local function applyPvPDamage(
	attacker: Player,
	victim: Player,
	damage: number,
	hitDir: Vector3,
	eval: CombatLogic.DamageEvalResult
)
	if not ArenaCycleService.canDealPvPDamage(attacker, victim) then
		return
	end
	local char = victim.Character
	local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
	if not hum or hum.Health <= 0 then
		return
	end
	local shield = shieldByUser[victim.UserId] or 0
	local remaining = damage
	if shield > 0 then
		local absorbed = math.min(shield, remaining)
		shield -= absorbed
		remaining -= absorbed
		shieldByUser[victim.UserId] = shield
		victim:SetAttribute("ShieldHP", math.floor(shield))
	end
	if remaining > 0 then
		hum.Health = math.max(0, hum.Health - remaining)
	end
	if eval.slowFraction > 0 then
		victim:SetAttribute("FrostSlowUntil", os.clock() + eval.slowDuration)
	end
	if eval.miniStunDuration > 0 then
		victim:SetAttribute("MiniStunUntil", os.clock() + eval.miniStunDuration)
	end
	applyPvPKnockback(victim, hitDir, eval.knockbackStrength)
	ArenaCycleService.onPlayerDamagedInPvP(victim, attacker, hum.Health <= 0)

	if eval.burnTotalDamage > 0 and hum.Health > 0 then
		local perTick = math.max(1, math.floor(eval.burnTotalDamage / 3 + 0.5))
		for i = 1, 3 do
			task.delay(i * 1.0, function()
				if not ArenaCycleService.canDealPvPDamage(attacker, victim) then
					return
				end
				if hum.Parent and hum.Health > 0 then
					hum.Health = math.max(0, hum.Health - perTick)
					ArenaCycleService.onPlayerDamagedInPvP(victim, attacker, hum.Health <= 0)
				end
			end)
		end
	end
end

local function resolveTrainingHit(
	player: Player,
	profile: EconomyLogic.PlayerProfile,
	hitPart: BasePart
)
	local plot = PlotService.getPlotForPlayer(player)
	if not plot or not hitPart:IsDescendantOf(plot.trainingRange) then
		return
	end
	local kind = tostring(hitPart:GetAttribute("TargetKind") or "")
	if kind ~= "Static" and kind ~= "MovingGold" then
		return
	end
	local res = CombatLogic.evaluateTrainingHit({
		isOnAssignedPad = PlotService.isPlayerOnAssignedPad(player),
		targetTierId = profile.targetTierId,
		isMovingGold = kind == "MovingGold",
		goldCombo = goldComboByUser[player.UserId] or 0,
		ascensionRank = profile.ascensionRank,
		hasDoubleTrainingPass = DataService.hasPass(player, "Pass_DoubleTraining"),
		activePets = EconomyLogic.getActivePets(profile),
	})
	if not res.accepted then
		return
	end
	goldComboByUser[player.UserId] = res.nextGoldCombo
	profile.ballDamage += res.ballDamageGain
	profile.throwSpeed += res.throwSpeedGain
	DataService.syncToClient(player)
end

local function applySecondaryAreaPerks(
	attacker: Player,
	biomeId: string,
	hitPos: Vector3,
	eval: CombatLogic.DamageEvalResult,
	primaryMob: BossAIService.ActiveMob?
)
	local splashFrac = math.max(eval.splashFraction, eval.explosiveAoEFraction)
	if splashFrac > 0 then
		local splashDmg = math.max(1, math.floor(eval.damage * splashFrac + 0.5))
		for _, m in ipairs(BossAIService.getNearbyMobs(biomeId, hitPos, 16, primaryMob)) do
			BossAIService.damageMob(m, attacker, splashDmg, eval.slowDuration, 0)
		end
	end
	if eval.ricochetFraction > 0 then
		local near = BossAIService.getNearbyMobs(biomeId, hitPos, 28, primaryMob)
		if #near > 0 then
			local bounceDmg = math.max(1, math.floor(eval.damage * eval.ricochetFraction + 0.5))
			BossAIService.damageMob(near[1], attacker, bounceDmg, eval.slowDuration, 0)
		end
	end
end

local function isInvisibleTriggerVolume(part: BasePart): boolean
	if part.CanCollide or part.Transparency < 0.85 then
		return false
	end
	if part:GetAttribute("TargetKind") ~= nil then
		return false
	end
	if BossAIService.getMobFromPart(part) or BossAIService.getBossFromPart(part) then
		return false
	end
	if Players:GetPlayerFromCharacter(part.Parent) then
		return false
	end
	return true
end

local function castSegmentSphere(fromPos: Vector3, delta: Vector3, char: Model): RaycastResult?
	local excluded: { Instance } = { char }
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	for _ = 1, 6 do
		params.FilterDescendantsInstances = excluded
		local res = workspace:Spherecast(fromPos, 1.65, delta, params)
		if not res or not res.Instance or not res.Instance:IsA("BasePart") then
			return res
		end
		if isInvisibleTriggerVolume(res.Instance) then
			table.insert(excluded, res.Instance)
		else
			return res
		end
	end
	return nil
end

local function classifyHitPart(player: Player, hitPart: BasePart): ResolvedTarget?
	local targetKind = tostring(hitPart:GetAttribute("TargetKind") or "")
	if targetKind == "Static" or targetKind == "MovingGold" then
		local plot = PlotService.getPlotForPlayer(player)
		if plot and hitPart:IsDescendantOf(plot.trainingRange) then
			return {
				hitPart = hitPart,
				hitKind = if targetKind == "MovingGold" then "GoldTarget" else "Target",
			}
		end
		return nil
	end
	local mob = BossAIService.getMobFromPart(hitPart)
	if mob and mob.alive and mob.model and mob.model.PrimaryPart then
		return { hitPart = mob.model.PrimaryPart, hitKind = "Mob", mob = mob }
	end
	local boss = BossAIService.getBossFromPart(hitPart)
	if boss and boss.model.PrimaryPart then
		return { hitPart = boss.model.PrimaryPart, hitKind = "Boss", boss = boss }
	end
	local hitPlr = Players:GetPlayerFromCharacter(hitPart.Parent)
	if hitPlr and hitPlr ~= player and ArenaCycleService.canDealPvPDamage(player, hitPlr) then
		local vHrp = if hitPlr.Character
			then hitPlr.Character:FindFirstChild("HumanoidRootPart")
			else nil
		if vHrp and vHrp:IsA("BasePart") then
			return { hitPart = vHrp, hitKind = "PvP", victim = hitPlr }
		end
	end
	return nil
end

local function resolveAutoAimTarget(
	player: Player,
	origin: Vector3,
	targetHint: any
): ResolvedTarget?
	local maxRange = CombatLogic.AUTO_AIM_MAX_RANGE
	if typeof(targetHint) == "Instance" and targetHint:IsA("BasePart") and targetHint.Parent then
		if (targetHint.Position - origin).Magnitude <= maxRange then
			local hinted = classifyHitPart(player, targetHint)
			if hinted then
				return hinted
			end
		end
	end

	local zone = tostring(player:GetAttribute("Zone") or "Hub")
	local activeBiome = tostring(player:GetAttribute("ActiveBiome") or "")
	local candidates: { CombatLogic.AutoAimCandidate } = {}
	local resolvedById: { [string]: ResolvedTarget } = {}

	if zone == "Hub" and PlotService.isPlayerOnAssignedPad(player) then
		local plot = PlotService.getPlotForPlayer(player)
		if plot then
			for _, child in ipairs(plot.trainingRange:GetChildren()) do
				if child:IsA("BasePart") then
					local tk = child:GetAttribute("TargetKind")
					if tk == "Static" or tk == "MovingGold" then
						local id = child.Name
						resolvedById[id] = {
							hitPart = child,
							hitKind = if tk == "MovingGold" then "GoldTarget" else "Target",
						}
						table.insert(candidates, {
							id = id,
							kind = if tk == "MovingGold" then "GoldTarget" else "Target",
							x = child.Position.X,
							y = child.Position.Y,
							z = child.Position.Z,
						})
					end
				end
			end
		end
	elseif zone == "LockedBossPvP" and activeBiome ~= "" then
		local boss = BossAIService.getActiveBoss(activeBiome)
		if boss and boss.model.PrimaryPart then
			local bp = boss.model.PrimaryPart
			resolvedById.boss = { hitPart = bp, hitKind = "Boss", boss = boss }
			table.insert(candidates, {
				id = "boss",
				kind = "Boss",
				x = bp.Position.X,
				y = bp.Position.Y,
				z = bp.Position.Z,
			})
		end
		for _, enemy in ipairs(Players:GetPlayers()) do
			if enemy ~= player and ArenaCycleService.canDealPvPDamage(player, enemy) then
				local eChar = enemy.Character
				local eHrp = if eChar then eChar:FindFirstChild("HumanoidRootPart") else nil
				local eHum = if eChar then eChar:FindFirstChildOfClass("Humanoid") else nil
				if eHrp and eHrp:IsA("BasePart") and eHum and eHum.Health > 0 then
					local id = `pvp_{enemy.UserId}`
					resolvedById[id] = { hitPart = eHrp, hitKind = "PvP", victim = enemy }
					table.insert(candidates, {
						id = id,
						kind = "PvP",
						x = eHrp.Position.X,
						y = eHrp.Position.Y,
						z = eHrp.Position.Z,
					})
				end
			end
		end
	elseif zone == "BiomePvE" and activeBiome ~= "" then
		local nearby = BossAIService.getNearbyMobs(activeBiome, origin, maxRange, nil)
		for i, mob in ipairs(nearby) do
			if mob.model and mob.model.PrimaryPart then
				local mp = mob.model.PrimaryPart
				local id = `mob_{i}`
				resolvedById[id] = { hitPart = mp, hitKind = "Mob", mob = mob }
				table.insert(candidates, {
					id = id,
					kind = "Mob",
					x = mp.Position.X,
					y = mp.Position.Y,
					z = mp.Position.Z,
				})
			end
		end
	end

	local chosen =
		CombatLogic.selectAutoAimTarget(origin.X, origin.Y, origin.Z, candidates, maxRange)
	return if chosen then resolvedById[chosen.id] else nil
end

local function applyResolvedImpact(
	player: Player,
	profile: EconomyLogic.PlayerProfile,
	target: ResolvedTarget,
	impactDir: Vector3,
	eval: CombatLogic.DamageEvalResult
)
	if not player.Parent or not target.hitPart.Parent then
		return
	end
	if target.hitKind == "Target" or target.hitKind == "GoldTarget" then
		resolveTrainingHit(player, profile, target.hitPart)
	elseif target.mob and target.mob.alive then
		BossAIService.damageMob(
			target.mob,
			player,
			eval.damage,
			eval.slowDuration,
			eval.miniStunDuration
		)
		applyHeal(player, eval.leechHeal)
		applySecondaryAreaPerks(
			player,
			target.mob.biomeId,
			target.hitPart.Position,
			eval,
			target.mob
		)
	elseif target.boss then
		BossAIService.damageBoss(
			target.boss,
			player,
			eval.damage,
			eval.slowDuration,
			eval.miniStunDuration
		)
		applyHeal(player, eval.leechHeal)
	elseif target.victim and ArenaCycleService.canDealPvPDamage(player, target.victim) then
		applyPvPDamage(player, target.victim, eval.damage, impactDir, eval)
		applyHeal(player, eval.leechHeal)
	end
end

local function evaluateCurrentHit(profile: EconomyLogic.PlayerProfile): CombatLogic.DamageEvalResult
	return CombatLogic.evaluateBallHit({
		baseBallDamage = profile.ballDamage,
		ballTierId = profile.ballTierId,
		activePets = EconomyLogic.getActivePets(profile),
		critRollUnit = math.random(),
	})
end

local function broadcastProjectile(payload: { [string]: any })
	Remotes.ensureServer().ProjectileBroadcast:FireAllClients(payload)
end

local function despawnProjectileAt(index: number)
	local proj = activeProjectiles[index]
	if not proj then
		return
	end
	table.remove(activeProjectiles, index)
	broadcastProjectile({ msgKind = "Despawn", ballId = proj.id })
end

local function enforcePlayerBallCap(player: Player)
	local count = 0
	local oldestIdx: number? = nil
	for i, proj in ipairs(activeProjectiles) do
		if proj.player == player then
			count += 1
			if oldestIdx == nil then
				oldestIdx = i
			end
		end
	end
	if count >= CombatLogic.MAX_ACTIVE_BALLS_PER_PLAYER and oldestIdx ~= nil then
		despawnProjectileAt(oldestIdx)
	end
end

local function handleProjectileCollision(
	proj: ActiveProjectile,
	now: number,
	hitPos: Vector3,
	hitCenter: Vector3,
	hitNormal: Vector3,
	hitPart: BasePart?,
	forcedResolved: ResolvedTarget?
): boolean
	local n = if hitNormal.Magnitude > 1e-4 then hitNormal.Unit else Vector3.yAxis
	local resolved = forcedResolved
		or (if hitPart then classifyHitPart(proj.player, hitPart) else nil)

	if resolved then
		local eval = evaluateCurrentHit(proj.profile)
		local impactDir = if proj.vel.Magnitude > 0.1 then proj.vel.Unit else -n
		applyResolvedImpact(proj.player, proj.profile, resolved, impactDir, eval)
		broadcastProjectile({
			msgKind = "ImpactDespawn",
			ballId = proj.id,
			pos = hitPos,
			normal = n,
			hitKind = resolved.hitKind,
			hitTarget = resolved.hitPart,
			damage = eval.damage,
			isCrit = eval.isCrit,
		})
		return false
	end

	local isFirstBounce = proj.firstBounceAt == nil
	if isFirstBounce then
		proj.firstBounceAt = now
	end
	proj.bounceCount += 1

	local incomingIntoNormal = -(proj.vel:Dot(n))
	local bx, by, bz =
		CombatLogic.computeBounceVelocity(proj.vel.X, proj.vel.Y, proj.vel.Z, n.X, n.Y, n.Z)
	proj.vel = Vector3.new(bx, by, bz)
	proj.pos = hitCenter + n * 0.18

	local remaining = CombatLogic.getRemainingBounceTime(proj.firstBounceAt, now)
	local shouldBroadcastSurface = isFirstBounce
		or (incomingIntoNormal >= 4.0 and (now - proj.lastSurfaceBroadcastAt) >= 0.08)
	local shouldBroadcastRoll = not shouldBroadcastSurface
		and n.Y > 0.65
		and (now - proj.lastSurfaceBroadcastAt) >= 0.12

	if shouldBroadcastSurface or shouldBroadcastRoll then
		proj.lastSurfaceBroadcastAt = now
		broadcastProjectile({
			msgKind = "Bounce",
			ballId = proj.id,
			pos = proj.pos,
			vel = proj.vel,
			normal = n,
			hitKind = if shouldBroadcastRoll then "Roll" else "Surface",
			hitTarget = hitPart,
			damage = 0,
			isCrit = false,
			remainingLife = remaining,
			bounceCount = proj.bounceCount,
		})
	end
	return true
end

local function stepHomingProjectile(proj: ActiveProjectile, now: number): boolean
	local target = proj.homingTarget
	local arrivesAt = proj.homingArrivesAt
	if not target or not arrivesAt then
		return false
	end
	if now < arrivesAt then
		return true
	end
	local livePos = if target.hitPart.Parent then target.hitPart.Position else proj.pos
	local delta = livePos - proj.pos
	local dir = if delta.Magnitude > 0.1 then delta.Unit else proj.vel.Unit
	proj.homingTarget = nil
	proj.homingArrivesAt = nil
	proj.vel = dir * proj.speed
	local forced = if target.hitPart.Parent then target else nil
	return handleProjectileCollision(proj, now, livePos, livePos, -dir, target.hitPart, forced)
end

local function stepBallisticProjectile(proj: ActiveProjectile, dt: number, now: number): boolean
	if proj.firstBounceAt ~= nil then
		if not CombatLogic.isBounceActive(proj.firstBounceAt, now) then
			return false
		end
	elseif (now - proj.launchedAt) >= proj.maxInitialFlight then
		return false
	end

	local char = proj.player.Character
	if not char then
		return false
	end
	local g = CombatLogic.BALL_GRAVITY
	local nextPos = proj.pos + proj.vel * dt + Vector3.new(0, -0.5 * g * dt * dt, 0)
	local nextVel = proj.vel + Vector3.new(0, -g * dt, 0)
	local seg = nextPos - proj.pos
	local segLen = seg.Magnitude
	local castDelta = if segLen >= 0.05 then seg else Vector3.new(0, 0.08, 0)
	local res = castSegmentSphere(proj.pos, castDelta, char)

	if res then
		local frac = if segLen >= 0.05 then math.clamp(res.Distance / segLen, 0, 1) else 0
		proj.vel = proj.vel + Vector3.new(0, -g * dt * frac, 0)
		local hitCenter = if segLen >= 0.05
			then proj.pos + (seg / segLen) * math.max(0, res.Distance - 0.05)
			else proj.pos
		local hitPart = if res.Instance and res.Instance:IsA("BasePart") then res.Instance else nil
		return handleProjectileCollision(
			proj,
			now,
			res.Position,
			hitCenter,
			res.Normal,
			hitPart,
			nil
		)
	end
	proj.pos = nextPos
	proj.vel = nextVel
	return true
end

local function stepAllProjectiles(dt: number)
	if #activeProjectiles == 0 then
		return
	end
	local stepDt = math.min(dt, 0.05)
	local now = os.clock()
	for i = #activeProjectiles, 1, -1 do
		local proj = activeProjectiles[i]
		local keepAlive = false
		if proj.player.Parent then
			if proj.homingTarget ~= nil then
				keepAlive = stepHomingProjectile(proj, now)
			else
				keepAlive = stepBallisticProjectile(proj, stepDt, now)
			end
		end
		if not keepAlive then
			despawnProjectileAt(i)
		end
	end
end

local function onThrowBall(player: Player, aimDirection: any, autoAimFlag: any, targetHint: any)
	if typeof(aimDirection) ~= "Vector3" then
		return
	end
	local profile = DataService.getProfile(player)
	local char = player.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
	if not profile or not char or not hrp or not hrp:IsA("BasePart") then
		return
	end
	local now = os.clock()
	local origin = hrp.Position + Vector3.new(0, 1.4, 0)
	local activePets = EconomyLogic.getActivePets(profile)
	local ok = CombatLogic.validateThrowRequest({
		lastThrowAt = lastThrowTime[player.UserId] or 0,
		now = now,
		throwSpeedStat = profile.throwSpeed,
		activePets = activePets,
		hasTurboRangeBonus = PlotService.isPlayerOnAssignedPad(player)
			and DataService.hasPass(player, "Pass_AutoFireRange"),
		originX = origin.X,
		originY = origin.Y,
		originZ = origin.Z,
		dirX = aimDirection.X,
		dirY = aimDirection.Y,
		dirZ = aimDirection.Z,
	})
	if not ok then
		return
	end
	lastThrowTime[player.UserId] = now
	enforcePlayerBallCap(player)

	local ballTier = EconomyConfigs.getBallTierById(profile.ballTierId)
		or EconomyConfigs.BALL_TIERS[1]
	local speed = MathUtil.computeProjectileSpeed(ballTier.projectileSpeed, profile.throwSpeed)
	local throwEval = evaluateCurrentHit(profile)
	if throwEval.shieldAmount > 0 then
		applyShield(player, throwEval.shieldAmount)
	end

	nextBallId += 1
	local ballId = nextBallId
	local wantsAutoAim = autoAimFlag == true
	local homingTarget = if wantsAutoAim
		then resolveAutoAimTarget(player, origin, targetHint)
		else nil

	if homingTarget then
		local toTarget = homingTarget.hitPart.Position - origin
		local dist = toTarget.Magnitude
		local dir = if dist > 0.1 then toTarget.Unit else aimDirection.Unit
		local travelSec = math.clamp(dist / math.max(55, speed), 0.08, 0.52)
		local vx, vy, vz =
			CombatLogic.computeBallisticLaunchVelocity(dir.X, dir.Y, dir.Z, speed, 0.12)
		local launchVel = Vector3.new(vx, vy, vz)
		table.insert(activeProjectiles, {
			id = ballId,
			player = player,
			profile = profile,
			speed = speed,
			pos = origin,
			vel = launchVel,
			launchedAt = now,
			firstBounceAt = nil,
			bounceCount = 0,
			maxInitialFlight = travelSec + 0.5,
			homingTarget = homingTarget,
			homingArrivesAt = now + travelSec,
			lastSurfaceBroadcastAt = 0,
		})
		broadcastProjectile({
			msgKind = "Launch",
			ballId = ballId,
			shooterId = player.UserId,
			ballTierId = profile.ballTierId,
			ballSkin = profile.equippedBallSkin,
			origin = origin,
			endPos = homingTarget.hitPart.Position,
			launchVel = launchVel,
			travelSec = travelSec,
			speed = speed,
			isHoming = true,
			hitTarget = homingTarget.hitPart,
		})
		return
	end

	local dir = aimDirection.Unit
	local vx, vy, vz = CombatLogic.computeBallisticLaunchVelocity(dir.X, dir.Y, dir.Z, speed, 0.09)
	local launchVel = Vector3.new(vx, vy, vz)
	table.insert(activeProjectiles, {
		id = ballId,
		player = player,
		profile = profile,
		speed = speed,
		pos = origin,
		vel = launchVel,
		launchedAt = now,
		firstBounceAt = nil,
		bounceCount = 0,
		maxInitialFlight = CombatLogic.MAX_INITIAL_FLIGHT_SEC,
		homingTarget = nil,
		homingArrivesAt = nil,
		lastSurfaceBroadcastAt = 0,
	})
	broadcastProjectile({
		msgKind = "Launch",
		ballId = ballId,
		shooterId = player.UserId,
		ballTierId = profile.ballTierId,
		ballSkin = profile.equippedBallSkin,
		origin = origin,
		endPos = origin + dir * 120,
		launchVel = launchVel,
		travelSec = CombatLogic.MAX_INITIAL_FLIGHT_SEC,
		speed = speed,
		isHoming = false,
		hitTarget = nil,
	})
end

function CombatService.init() end

function CombatService.start()
	local remotes = Remotes.ensureServer()
	remotes.ThrowBall.OnServerEvent:Connect(onThrowBall)
	RunService.Heartbeat:Connect(stepAllProjectiles)

	remotes.DashRequest.OnServerEvent:Connect(function(player: Player, moveDir: any)
		local now = os.clock()
		if (lastDashTime[player.UserId] or 0) + DASH_COOLDOWN > now then
			return
		end
		if PlotService.isPlayerOnAssignedPad(player) then
			return
		end
		lastDashTime[player.UserId] = now
		player:SetAttribute("LastDashAt", now)
		local safeDir = Vector3.zAxis
		if
			typeof(moveDir) == "Vector3"
			and MathUtil.isFinite(moveDir.X)
			and MathUtil.isFinite(moveDir.Z)
		then
			local flat = Vector3.new(moveDir.X, 0, moveDir.Z)
			if flat.Magnitude > 0.05 then
				safeDir = flat.Unit
			end
		end
		remotes.DashRequest:FireAllClients(player.UserId, safeDir)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		local uid = player.UserId
		lastThrowTime[uid] = nil
		lastDashTime[uid] = nil
		goldComboByUser[uid] = nil
		shieldByUser[uid] = nil
		for i = #activeProjectiles, 1, -1 do
			if activeProjectiles[i].player == player then
				despawnProjectileAt(i)
			end
		end
	end)
end

return CombatService
