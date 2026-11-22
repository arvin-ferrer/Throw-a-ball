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

local CombatLogic = {}

CombatLogic.COOLDOWN_TOLERANCE = 0.85
CombatLogic.CRIT_MULTIPLIER = 1.75
CombatLogic.LEECH_CAP_PER_HIT_FRAC = 0.15

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
	if
		not MathUtil.isFinite(input.originX)
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
	local cd = MathUtil.computeThrowCooldown(input.throwSpeedStat, swiftBonus)
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

return CombatLogic
