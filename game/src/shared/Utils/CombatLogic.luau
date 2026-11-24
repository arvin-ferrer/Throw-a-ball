--!strict
--[[
	CombatLogic.luau
	Pure server-authoritative combat, training validation, cooldown gating,
	and Active Follower Ball Perk calculation (100% Lune-testable).
]]

local req: any = require
local scriptRef: any = script
local isRoblox = type(scriptRef) == "userdata"
local EconomyConfigs = if isRoblox
	then req(scriptRef.Parent.Parent.Configs.EconomyConfigs)
	else req("../Configs/EconomyConfigs")
local PetConfigs = if isRoblox
	then req(scriptRef.Parent.Parent.Configs.PetConfigs)
	else req("../Configs/PetConfigs")
local TraitConfigs = if isRoblox
	then req(scriptRef.Parent.Parent.Configs.TraitConfigs)
	else req("../Configs/TraitConfigs")
local MathUtil = if isRoblox then req(scriptRef.Parent.MathUtil) else req("./MathUtil")

export type OwnedPetSnapshot = {
	uid: string,
	speciesId: string,
	mutationKey: string,
	starTier: number,
	level: number,
	traitKey: string?,
}

export type ThrowValidationInput = {
	lastThrowAt: number,
	now: number,
	throwSpeedStat: number,
	activePets: { OwnedPetSnapshot },
	hasTurboRangeBonus: boolean?,
	originX: number,
	originY: number,
	originZ: number,
	dirX: number,
	dirY: number,
	dirZ: number,
}

export type TrainingHitInput = {
	isOnAssignedPad: boolean,
	targetTierId: string,
	isMovingGold: boolean,
	goldCombo: number,
	ascensionRank: number,
	hasDoubleTrainingPass: boolean,
	activePets: { OwnedPetSnapshot },
}

export type TrainingHitResult = {
	accepted: boolean,
	reason: string?,
	ballDamageGain: number,
	throwSpeedGain: number,
	nextGoldCombo: number,
}

export type DamageEvalInput = {
	baseBallDamage: number,
	ballTierId: string,
	activePets: { OwnedPetSnapshot },
	critRollUnit: number,
}

export type DamageEvalResult = {
	damage: number,
	isCrit: boolean,
	slowFraction: number,
	slowDuration: number,
	burnTotalDamage: number,
	burnDuration: number,
	ricochetFraction: number,
	knockbackStrength: number,
	leechHeal: number,
	shieldAmount: number,
	splashFraction: number,
	miniStunDuration: number,
	explosiveAoEFraction: number,
}

export type AutoAimCandidate = {
	id: string,
	kind: "Boss" | "PvP" | "Mob" | "GoldTarget" | "Target",
	x: number,
	y: number,
	z: number,
	priorityBonus: number?,
}

local CombatLogic = {}

CombatLogic.COOLDOWN_TOLERANCE = 0.85
CombatLogic.CRIT_MULTIPLIER = 1.75
CombatLogic.LEECH_CAP_PER_HIT_FRAC = 0.15
CombatLogic.AUTO_AIM_MAX_RANGE = 185
CombatLogic.BALL_GRAVITY = 42
CombatLogic.POST_BOUNCE_LIFETIME = 1.0
CombatLogic.MAX_INITIAL_FLIGHT_SEC = 2.0
CombatLogic.BOUNCE_RESTITUTION = 0.78
CombatLogic.BOUNCE_TANGENT_RETENTION = 0.88
CombatLogic.BOUNCE_HIT_COOLDOWN = 0.25
CombatLogic.MAX_ACTIVE_BALLS_PER_PLAYER = 12

function CombatLogic.getActiveTraitBonuses(activePets: { OwnedPetSnapshot }): (number, number)
	local throwSpeedBonus = 0
	local ballDamageBonus = 0
	for _, pet in ipairs(activePets) do
		local trait = TraitConfigs.getTrait(pet.traitKey)
		if trait then
			throwSpeedBonus += trait.throwSpeedBonus
			ballDamageBonus += trait.ballDamageBonus
		end
	end
	return throwSpeedBonus, ballDamageBonus
end

function CombatLogic.validateThrowRequest(input: ThrowValidationInput): (boolean, string?, number)
	if type(input) ~= "table" then
		return false, "InvalidPayload", 0
	end
	if
		not MathUtil.isFinite(input.lastThrowAt)
		or not MathUtil.isFinite(input.now)
		or not MathUtil.isFinite(input.throwSpeedStat)
		or not MathUtil.isFinite(input.originX)
		or not MathUtil.isFinite(input.originY)
		or not MathUtil.isFinite(input.originZ)
		or not MathUtil.isFinite(input.dirX)
		or not MathUtil.isFinite(input.dirY)
		or not MathUtil.isFinite(input.dirZ)
	then
		return false, "NonFiniteVector", 0
	end
	local dirMag = math.sqrt(input.dirX ^ 2 + input.dirY ^ 2 + input.dirZ ^ 2)
	if dirMag < 1e-4 then
		return false, "ZeroDirection", 0
	end
	local swiftBonus = CombatLogic.getActiveTraitBonuses(input.activePets)
	local turboBonus = if input.hasTurboRangeBonus then 0.25 else 0
	local cd = MathUtil.computeThrowCooldown(input.throwSpeedStat, swiftBonus + turboBonus)
	local elapsed = input.now - input.lastThrowAt
	if elapsed < cd * CombatLogic.COOLDOWN_TOLERANCE then
		return false, "RateLimited", cd
	end
	return true, nil, cd
end

function CombatLogic.evaluateTrainingHit(input: TrainingHitInput): TrainingHitResult
	if not input.isOnAssignedPad then
		return {
			accepted = false,
			reason = "NotOnAssignedPad",
			ballDamageGain = 0,
			throwSpeedGain = 0,
			nextGoldCombo = 0,
		}
	end
	local tier = EconomyConfigs.getTargetTierById(input.targetTierId)
	if not tier then
		return {
			accepted = false,
			reason = "InvalidTargetTier",
			ballDamageGain = 0,
			throwSpeedGain = 0,
			nextGoldCombo = 0,
		}
	end
	local perks = PetConfigs.resolveActivePerks(input.activePets)
	local trainingPerk = perks.TrainingBoost
	local petTrainingMult = 1 + (if trainingPerk then trainingPerk.effectiveValue else 0)
	local ascensionMult = EconomyConfigs.getAscensionTrainingMult(input.ascensionRank)
	local passMult = if input.hasDoubleTrainingPass then 2.0 else 1.0

	local nextCombo = if input.isMovingGold then math.min(input.goldCombo + 1, 10) else 0
	local goldMult = if input.isMovingGold then tier.goldMultiplier else 1
	local dmgGain = math.max(
		1,
		math.floor(tier.dmgPerHit * goldMult * petTrainingMult * ascensionMult * passMult + 0.5)
	)
	local speedGain = 0
	if input.isMovingGold then
		local comboMult = 1 + (nextCombo - 1) * 0.15
		speedGain = tier.throwSpeedPerGoldHit * comboMult * passMult
	end
	return {
		accepted = true,
		reason = nil,
		ballDamageGain = dmgGain,
		throwSpeedGain = speedGain,
		nextGoldCombo = nextCombo,
	}
end

function CombatLogic.evaluateBallHit(input: DamageEvalInput): DamageEvalResult
	local tier = EconomyConfigs.getBallTierById(input.ballTierId)
	local tierMult = if tier then tier.damageMult else 1.0
	local _, brawlerBonus = CombatLogic.getActiveTraitBonuses(input.activePets)
	local rawDmg = math.max(1, input.baseBallDamage) * tierMult * (1 + brawlerBonus)
	local perks = PetConfigs.resolveActivePerks(input.activePets)

	local isCrit = false
	if perks.CritSurge and input.critRollUnit < perks.CritSurge.effectiveValue then
		isCrit = true
		rawDmg *= CombatLogic.CRIT_MULTIPLIER
	end
	local finalDmg = math.max(1, math.floor(rawDmg + 0.5))

	local slowFrac = if perks.FrostSlow then math.min(0.45, perks.FrostSlow.effectiveValue) else 0
	local slowDur = if slowFrac > 0 then 2.0 else 0
	local burnFrac = 0
	if perks.EmberBurn then
		burnFrac = math.max(burnFrac, perks.EmberBurn.effectiveValue)
	end
	if perks.SpeedBurn then
		burnFrac = math.max(burnFrac, perks.SpeedBurn.effectiveValue)
	end
	if perks.KnockbackBurn then
		burnFrac = math.max(burnFrac, 0.15 * perks.KnockbackBurn.potency)
	end
	if perks.ExplosiveAoE then
		burnFrac = math.max(burnFrac, 0.15 * perks.ExplosiveAoE.potency)
	end
	local kb = 0
	if perks.HeavyKnockback then
		kb = math.max(kb, perks.HeavyKnockback.effectiveValue)
	end
	if perks.KnockbackBurn then
		kb = math.max(kb, perks.KnockbackBurn.effectiveValue)
	end
	local leech = if perks.VampiricLeech
		then math.floor(
			finalDmg
					* math.min(
						perks.VampiricLeech.effectiveValue,
						CombatLogic.LEECH_CAP_PER_HIT_FRAC
					)
				+ 0.5
		)
		else 0

	return {
		damage = finalDmg,
		isCrit = isCrit,
		slowFraction = slowFrac,
		slowDuration = slowDur,
		burnTotalDamage = math.floor(finalDmg * burnFrac + 0.5),
		burnDuration = if burnFrac > 0 then 3.0 else 0,
		ricochetFraction = if perks.ChainRicochet then perks.ChainRicochet.effectiveValue else 0,
		knockbackStrength = kb,
		leechHeal = leech,
		shieldAmount = if perks.ShieldOnThrow
			then math.floor(perks.ShieldOnThrow.effectiveValue + 0.5)
			else 0,
		splashFraction = if perks.ShockwaveSplash then perks.ShockwaveSplash.effectiveValue else 0,
		miniStunDuration = if perks.DeepFreeze
			then math.min(0.85, perks.DeepFreeze.effectiveValue)
			else 0,
		explosiveAoEFraction = if perks.ExplosiveAoE then perks.ExplosiveAoE.effectiveValue else 0,
	}
end

function CombatLogic.selectAutoAimTarget(
	originX: number,
	originY: number,
	originZ: number,
	candidates: { AutoAimCandidate },
	maxRange: number?
): AutoAimCandidate?
	local limit = maxRange or CombatLogic.AUTO_AIM_MAX_RANGE
	local best: AutoAimCandidate? = nil
	local bestScore = math.huge

	for _, cand in ipairs(candidates) do
		local dx = cand.x - originX
		local dy = cand.y - originY
		local dz = cand.z - originZ
		local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
		if dist >= 1.5 and dist <= limit then
			local weight = if cand.kind == "Boss"
				then 0.55
				elseif cand.kind == "PvP" then 0.72
				elseif cand.kind == "GoldTarget" then 0.65
				else 1.0
			local bonus = cand.priorityBonus or 0
			local score = dist * weight - bonus
			if score < bestScore then
				bestScore = score
				best = cand
			end
		end
	end
	return best
end

function CombatLogic.computeCameraAimDirection(
	lookX: number,
	lookY: number,
	lookZ: number
): (number, number, number)
	if
		not MathUtil.isFinite(lookX)
		or not MathUtil.isFinite(lookY)
		or not MathUtil.isFinite(lookZ)
	then
		return 0, 0, -1
	end
	local mag = math.sqrt(lookX * lookX + lookY * lookY + lookZ * lookZ)
	if mag < 1e-4 then
		return 0, 0, -1
	end
	return lookX / mag, lookY / mag, lookZ / mag
end

function CombatLogic.computeBallisticLaunchVelocity(
	dirX: number,
	dirY: number,
	dirZ: number,
	speed: number,
	upwardLoft: number?
): (number, number, number)
	local mag = math.sqrt(dirX * dirX + dirY * dirY + dirZ * dirZ)
	if mag < 1e-4 then
		return 0, 0, -speed
	end
	local ux, uy, uz = dirX / mag, dirY / mag, dirZ / mag
	local loft = upwardLoft or 0.08
	return ux * speed, (uy + loft) * speed, uz * speed
end

function CombatLogic.sampleBallisticPosition(
	originX: number,
	originY: number,
	originZ: number,
	velX: number,
	velY: number,
	velZ: number,
	t: number,
	gravity: number?
): (number, number, number)
	local g = gravity or CombatLogic.BALL_GRAVITY
	return originX + velX * t, originY + velY * t - 0.5 * g * t * t, originZ + velZ * t
end

function CombatLogic.computeBounceVelocity(
	velX: number,
	velY: number,
	velZ: number,
	normX: number,
	normY: number,
	normZ: number,
	restitution: number?,
	tangentRetention: number?
): (number, number, number)
	if
		not MathUtil.isFinite(velX)
		or not MathUtil.isFinite(velY)
		or not MathUtil.isFinite(velZ)
		or not MathUtil.isFinite(normX)
		or not MathUtil.isFinite(normY)
		or not MathUtil.isFinite(normZ)
	then
		return 0, 0, 0
	end
	local nMag = math.sqrt(normX * normX + normY * normY + normZ * normZ)
	local nx, ny, nz = 0, 1, 0
	if nMag >= 1e-4 then
		nx, ny, nz = normX / nMag, normY / nMag, normZ / nMag
	end
	local e = restitution or CombatLogic.BOUNCE_RESTITUTION
	local tRet = tangentRetention or CombatLogic.BOUNCE_TANGENT_RETENTION
	local vn = velX * nx + velY * ny + velZ * nz
	local vtX, vtY, vtZ = velX - vn * nx, velY - vn * ny, velZ - vn * nz
	local outNormal = if vn < 0 then -vn * e else math.max(vn, 4)
	local ox = vtX * tRet + nx * outNormal
	local oy = vtY * tRet + ny * outNormal
	local oz = vtZ * tRet + nz * outNormal
	if math.abs(ny) < 0.35 and oy < 10 then
		oy = 10
	elseif ny > 0.65 and oy < 3.5 then
		oy = 0
	end
	return ox, oy, oz
end

function CombatLogic.isBounceActive(firstBounceAt: number?, now: number, lifetime: number?): boolean
	if
		firstBounceAt == nil
		or not MathUtil.isFinite(firstBounceAt)
		or not MathUtil.isFinite(now)
	then
		return false
	end
	local limit = lifetime or CombatLogic.POST_BOUNCE_LIFETIME
	return now >= firstBounceAt and (now - firstBounceAt) < limit
end

function CombatLogic.getRemainingBounceTime(
	firstBounceAt: number?,
	now: number,
	lifetime: number?
): number
	if
		firstBounceAt == nil
		or not MathUtil.isFinite(firstBounceAt)
		or not MathUtil.isFinite(now)
	then
		return 0
	end
	local limit = lifetime or CombatLogic.POST_BOUNCE_LIFETIME
	return math.max(0, limit - math.max(0, now - firstBounceAt))
end

function CombatLogic.canBounceHitTarget(lastHitAt: number?, now: number, cooldown: number?): boolean
	if not MathUtil.isFinite(now) then
		return false
	end
	if lastHitAt == nil then
		return true
	end
	if not MathUtil.isFinite(lastHitAt) then
		return false
	end
	local cd = cooldown or CombatLogic.BOUNCE_HIT_COOLDOWN
	return (now - lastHitAt) >= cd
end

function CombatLogic.shouldDespawnOnHitKind(hitKind: string): boolean
	return hitKind == "Mob"
		or hitKind == "Boss"
		or hitKind == "PvP"
		or hitKind == "Target"
		or hitKind == "GoldTarget"
end

function CombatLogic.isWithinPadFootprint(
	dx: number,
	dy: number,
	dz: number,
	halfX: number,
	halfY: number,
	halfZ: number,
	isGrounded: boolean?
): boolean
	if
		not MathUtil.isFinite(dx)
		or not MathUtil.isFinite(dy)
		or not MathUtil.isFinite(dz)
		or not MathUtil.isPositiveFinite(halfX)
		or not MathUtil.isPositiveFinite(halfY)
		or not MathUtil.isPositiveFinite(halfZ)
	then
		return false
	end
	if isGrounded ~= nil and isGrounded ~= true then
		return false
	end
	if math.abs(dx) > halfX + 1.25 or math.abs(dz) > halfZ + 1.25 then
		return false
	end
	local abovePadTop = dy - halfY
	return abovePadTop >= 0.5 and abovePadTop <= 5.0
end

return CombatLogic
