--!strict
--[[
	ActivePerks (Issue #14): Active Ball Perks from equipped follower pets (GDD §8.3). Pure.
	Distinct perk types stack; a duplicate type keeps only its highest star tier
	(1/2/3 stars = x1.00/x1.15/x1.30 strength, PetConfigs.PERK_BONUS_BY_STAR).
	CombatService applies the returned effects authoritatively on the server.
]]

-- selene: allow(incorrect_standard_library_use) -- string require: same path in Lune and Roblox
local PetConfigs = require("../Configs/PetConfigs")

export type Perks = { [string]: number } -- perk type -> strength multiplier
export type HitEffects = {
	damage: number,
	crit: boolean,
	slow: { fraction: number, seconds: number }?,
	burn: { totalDamage: number, seconds: number }?,
	ricochet: { damage: number, range: number }?,
	splash: { damage: number, radius: number }?,
	knockback: number?,
	leech: number?,
	stunSeconds: number?,
	shieldSeconds: number?,
}

local ActivePerks = {}

-- GDD §8.3 magnitudes; mythic perks (no GDD numbers yet) are provisional tuning.
local BASE = table.freeze({
	TrainingBoost = { training = 0.05 },
	FrostSlow = { slow = 0.20, seconds = 2.0 },
	EmberBurn = { burn = 0.15, seconds = 3.0 },
	ChainRicochet = { ricochet = 0.45, range = 14 },
	HeavyKnockback = { knockback = 55 },
	VampiricLeech = { leech = 0.04 },
	CritSurge = { chance = 0.12, multiplier = 1.75 },
	ShieldOnThrow = { shield = 1.5 }, -- provisional: 1.5s damage shield after each throw
	DeepFreeze = { stun = 0.6 }, -- provisional mini-stun
	ShockwaveSplash = { splash = 0.30, radius = 8 }, -- provisional
	AoEFireball = { splash = 0.40, radius = 10, burn = 0.15, seconds = 3.0 }, -- provisional
})
-- Combo perks from the GDD pet table ("Speed + Burn", "Knockback + Burn").
local COMBOS = table.freeze({
	SpeedBurn = { "EmberBurn" }, -- provisional: the speed half is a follower move buff, not a hit effect
	KnockbackBurn = { "HeavyKnockback", "EmberBurn" },
})

local function isFinite(n: unknown): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function tierOf(stars: unknown): number
	local bonus = isFinite(stars) and PetConfigs.PERK_BONUS_BY_STAR[stars :: number] or 0
	return 1 + bonus
end

-- Equipped pets -> { perkType = strength }, highest tier per type.
function ActivePerks.resolve(pets: { any }): Perks
	local perks: Perks = {}
	for _, pet in pets do
		local species = if type(pet) == "table" then PetConfigs.Species[pet.petId] else nil
		if species then
			local tier = tierOf(pet.stars)
			for _, perk in COMBOS[species.activePerk] or { species.activePerk } do
				if BASE[perk] then
					perks[perk] = math.max(perks[perk] or 0, tier)
				end
			end
		end
	end
	return perks
end

function ActivePerks.trainingMultiplier(perks: Perks): number
	local tier = perks.TrainingBoost
	return if tier then 1 + BASE.TrainingBoost.training * tier else 1
end

function ActivePerks.slotsForLevel(level: number): number
	if not isFinite(level) then
		return 1
	end
	return if level >= 25 then 3 elseif level >= 10 then 2 else 1
end

local function applyCrit(perks: Perks, damage: number, roll: number): (number, boolean)
	local tier = perks.CritSurge
	local valid = isFinite(roll) and roll >= 0 and roll < 1
	if tier and valid and roll < BASE.CritSurge.chance then
		return damage * BASE.CritSurge.multiplier, true -- the chance itself is not tier-scaled
	end
	return damage, false
end

-- One validated ball hit -> final damage plus every side effect to apply.
function ActivePerks.onHit(perks: Perks, baseDamage: number, critRoll: number): HitEffects
	if not isFinite(baseDamage) or baseDamage <= 0 then
		return { damage = 0, crit = false }
	end
	local damage, crit = applyCrit(perks, baseDamage, critRoll)
	local fx: HitEffects = { damage = damage, crit = crit }
	local t = perks
	if t.FrostSlow then
		fx.slow = { fraction = BASE.FrostSlow.slow * t.FrostSlow, seconds = BASE.FrostSlow.seconds }
	end
	if t.EmberBurn or t.AoEFireball then
		local tier = math.max(t.EmberBurn or 0, t.AoEFireball or 0)
		fx.burn =
			{ totalDamage = damage * BASE.EmberBurn.burn * tier, seconds = BASE.EmberBurn.seconds }
	end
	if t.ChainRicochet then
		fx.ricochet = {
			damage = damage * BASE.ChainRicochet.ricochet * t.ChainRicochet,
			range = BASE.ChainRicochet.range,
		}
	end
	local splashPerk = if t.AoEFireball
		then "AoEFireball"
		elseif t.ShockwaveSplash then "ShockwaveSplash"
		else nil
	if splashPerk then
		local cfg = (BASE :: any)[splashPerk]
		fx.splash = { damage = damage * cfg.splash * t[splashPerk], radius = cfg.radius }
	end
	fx.knockback = if t.HeavyKnockback
		then BASE.HeavyKnockback.knockback * t.HeavyKnockback
		else nil
	fx.leech = if t.VampiricLeech then damage * BASE.VampiricLeech.leech * t.VampiricLeech else nil
	fx.stunSeconds = if t.DeepFreeze then BASE.DeepFreeze.stun * t.DeepFreeze else nil
	fx.shieldSeconds = if t.ShieldOnThrow then BASE.ShieldOnThrow.shield * t.ShieldOnThrow else nil
	return fx
end

return ActivePerks
