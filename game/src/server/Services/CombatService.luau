--!strict
--[[
	CombatService.luau
	Server-authoritative swept-ray ball throw validation, Stationary Training Range hits,
	Active Follower Ball Perks (all 13 perk types), Dash cooldown, and Uncapped PvP with
	strict Phase == "PvP_EggScramble" anti-desync safety guard.
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
	-- Absorb with ShieldOnThrow first
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

	-- Ember Burn DoT (3 ticks over 3.0s — pressures rivals holding the 5s Egg Claim!)
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

local function onThrowBall(player: Player, aimDirection: any)
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

	local dir = aimDirection.Unit
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

	-- Swept-spherecast along trajectory (180 studs max) preventing wall clipping
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	local maxRange = 180
	local result = workspace:Spherecast(origin, 1.35, dir * maxRange, params)
	local endPos = if result then result.Position else (origin + dir * maxRange)
	local hitKind = "Miss"

	if result and result.Instance and result.Instance:IsA("BasePart") then
		local hitPart = result.Instance
		local targetKind = tostring(hitPart:GetAttribute("TargetKind") or "")
		if targetKind == "Static" or targetKind == "MovingGold" then
			hitKind = if targetKind == "MovingGold" then "GoldTarget" else "Target"
			resolveTrainingHit(player, profile, hitPart)
		else
			local mob = BossAIService.getMobFromPart(hitPart)
			local boss = if not mob then BossAIService.getBossFromPart(hitPart) else nil
			local hitPlr = if not mob and not boss
				then Players:GetPlayerFromCharacter(hitPart.Parent)
				else nil
			if mob then
				hitKind = "Mob"
				BossAIService.damageMob(
					mob,
					player,
					eval.damage,
					eval.slowDuration,
					eval.miniStunDuration
				)
				applyHeal(player, eval.leechHeal)
				applySecondaryAreaPerks(player, mob.biomeId, endPos, eval, mob)
			elseif boss then
				hitKind = "Boss"
				BossAIService.damageBoss(
					boss,
					player,
					eval.damage,
					eval.slowDuration,
					eval.miniStunDuration
				)
				applyHeal(player, eval.leechHeal)
			elseif
				hitPlr
				and hitPlr ~= player
				and ArenaCycleService.canDealPvPDamage(player, hitPlr)
			then
				hitKind = "PvP"
				applyPvPDamage(player, hitPlr, eval.damage, dir, eval)
				applyHeal(player, eval.leechHeal)
			end
		end
	end

	Remotes.ensureServer().ProjectileBroadcast:FireAllClients({
		shooterId = player.UserId,
		ballTierId = profile.ballTierId,
		ballSkin = profile.equippedBallSkin,
		origin = origin,
		endPos = endPos,
		speed = speed,
		hitKind = hitKind,
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
