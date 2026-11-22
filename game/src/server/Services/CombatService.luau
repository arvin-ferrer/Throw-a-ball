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

local CombatService = {}

local lastThrowTime: { [number]: number } = {}
local lastDashTime: { [number]: number } = {}
local goldComboByUser: { [number]: number } = {}
local shieldByUser: { [number]: number } = {}
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

local function stepBallisticArc(
	origin: Vector3,
	launchVel: Vector3,
	maxTime: number,
	char: Model
): (RaycastResult?, Vector3, Vector3, number)
	local steps = 12
	local dt = maxTime / steps
	local prevPos = origin
	for i = 1, steps do
		local t = i * dt
		local nx, ny, nz = CombatLogic.sampleBallisticPosition(
			origin.X,
			origin.Y,
			origin.Z,
			launchVel.X,
			launchVel.Y,
			launchVel.Z,
			t,
			CombatLogic.BALL_GRAVITY
		)
		local nextPos = Vector3.new(nx, ny, nz)
		local seg = nextPos - prevPos
		local res = castSegmentSphere(prevPos, seg, char)
		if res then
			local frac = math.clamp(res.Distance / math.max(0.01, seg.Magnitude), 0, 1)
			local hitTime = (i - 1 + frac) * dt
			return res, res.Position, res.Normal, hitTime
		end
		prevPos = nextPos
	end
	return nil, prevPos, Vector3.yAxis, maxTime
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

	local ballTier = EconomyConfigs.getBallTierById(profile.ballTierId)
		or EconomyConfigs.BALL_TIERS[1]
	local speed = MathUtil.computeProjectileSpeed(ballTier.projectileSpeed, profile.throwSpeed)
	local eval = CombatLogic.evaluateBallHit({
		baseBallDamage = profile.ballDamage,
		ballTierId = profile.ballTierId,
		activePets = activePets,
		critRollUnit = math.random(),
	})
	if eval.shieldAmount > 0 then
		applyShield(player, eval.shieldAmount)
	end

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
		task.delay(travelSec, function()
			applyResolvedImpact(player, profile, homingTarget, dir, eval)
		end)
		Remotes.ensureServer().ProjectileBroadcast:FireAllClients({
			shooterId = player.UserId,
			ballTierId = profile.ballTierId,
			ballSkin = profile.equippedBallSkin,
			origin = origin,
			endPos = homingTarget.hitPart.Position,
			normal = -dir,
			launchVel = Vector3.new(vx, vy, vz),
			travelSec = travelSec,
			speed = speed,
			isHoming = true,
			hitKind = homingTarget.hitKind,
			hitTarget = homingTarget.hitPart,
			damage = eval.damage,
			isCrit = eval.isCrit,
		})
		return
	end

	-- Manual free-aim: real stepped ballistic gravity arc with arrival-timed impact
	local dir = aimDirection.Unit
	local vx, vy, vz = CombatLogic.computeBallisticLaunchVelocity(dir.X, dir.Y, dir.Z, speed, 0.09)
	local launchVel = Vector3.new(vx, vy, vz)
	local maxTime = math.clamp(175 / math.max(55, speed), 0.75, 1.65)
	local res, endPos, hitNormal, hitTime = stepBallisticArc(origin, launchVel, maxTime, char)
	local hitTargetPart = if res
			and res.Instance
			and res.Instance:IsA("BasePart")
		then res.Instance
		else nil
	local resolved = if hitTargetPart then classifyHitPart(player, hitTargetPart) else nil
	local hitKind = if resolved then resolved.hitKind else (if res then "Surface" else "Miss")

	if resolved then
		task.delay(hitTime, function()
			applyResolvedImpact(player, profile, resolved, dir, eval)
		end)
	end

	Remotes.ensureServer().ProjectileBroadcast:FireAllClients({
		shooterId = player.UserId,
		ballTierId = profile.ballTierId,
		ballSkin = profile.equippedBallSkin,
		origin = origin,
		endPos = endPos,
		normal = hitNormal,
		launchVel = launchVel,
		travelSec = hitTime,
		speed = speed,
		isHoming = false,
		hitKind = hitKind,
		hitTarget = hitTargetPart,
		damage = eval.damage,
		isCrit = eval.isCrit,
	})
end

function CombatService.init() end

function CombatService.start()
	local remotes = Remotes.ensureServer()
	remotes.ThrowBall.OnServerEvent:Connect(onThrowBall)

	remotes.DashRequest.OnServerEvent:Connect(function(player: Player)
		local now = os.clock()
		if (lastDashTime[player.UserId] or 0) + DASH_COOLDOWN > now then
			return
		end
		if PlotService.isPlayerOnAssignedPad(player) then
			return
		end
		lastDashTime[player.UserId] = now
		player:SetAttribute("LastDashAt", now)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		local uid = player.UserId
		lastThrowTime[uid] = nil
		lastDashTime[uid] = nil
		goldComboByUser[uid] = nil
		shieldByUser[uid] = nil
	end)
end

return CombatService
