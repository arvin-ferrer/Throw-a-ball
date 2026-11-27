--!strict
--[[
	VaultHeistConfigs.luau
	Canonical data tables for C2: Egg Heist (1-4p Co-Op Boss Vault Heist):
	- 3 Coin-upgradable Utility Orbs (100% gameplay-earned, zero Robux RNG)
	- 3 Chambers mapped cleanly to existing EggConfigs species (Emerald/Frostbite/Molten)
	- 4 Procedural Chamber Mutators + Hourly VaultStorm cadence
]]

export type OrbId = "Decoy" | "Freeze" | "DashBomb"

export type OrbConfig = {
	id: OrbId,
	displayName: string,
	shortLabel: string,
	description: string,
	defaultLevel: number,
	maxLevel: number,
	baseCooldown: number,
	cooldownPerLevel: number,
	baseDuration: number,
	durationPerLevel: number,
	baseRadius: number,
	radiusPerLevel: number,
	laserPauseSec: number,
	dashImpulse: number,
	dashImpulsePerLevel: number,
	bossKnockback: number,
	bossKnockbackPerLevel: number,
	carrySlowImmunitySec: number,
	carrySlowImmunityPerLevel: number,
	bossDamage: number,
	upgradeCosts: { number },
	color: { number },
}

export type OrbStats = {
	level: number,
	cooldown: number,
	duration: number,
	radius: number,
	laserPauseSec: number,
	dashImpulse: number,
	bossKnockback: number,
	carrySlowImmunitySec: number,
	bossDamage: number,
}

export type ChamberConfig = {
	chamber: number,
	displayName: string,
	standardEggId: string,
	stormEggId: string,
	bossName: string,
	bossBaseHP: number,
	patrolSpeed: number,
	chaseSpeed: number,
	lungeSpeed: number,
	telegraphSec: number,
	lungeDamage: number,
	lungeRadius: number,
	sightRange: number,
	sightHalfAngleDeg: number,
	chamberDurationSec: number,
	collapseDurationSec: number,
	carrySlowFraction: number,
	streakMult: number,
	coinReward: number,
	expReward: number,
	gemReward: number,
	primaryColor: { number },
	accentColor: { number },
}

export type MutatorConfig = {
	id: string,
	displayName: string,
	description: string,
	gravityScale: number,
	laserSpeedMult: number,
	rewardMult: number,
	stormEggChance: number,
	accentColor: { number },
}

local VaultHeistConfigs = {}

VaultHeistConfigs.MAX_SQUAD_SIZE = 4
VaultHeistConfigs.MAX_ORB_LEVEL = 6
VaultHeistConfigs.MAX_CHAMBER = 3
VaultHeistConfigs.EXTRACTION_VOTE_SEC = 10.0
VaultHeistConfigs.REVIVE_HOLD_SEC = 2.5
VaultHeistConfigs.REVIVE_RADIUS = 10.0
VaultHeistConfigs.DOWNED_BLEEDOUT_SEC = 18.0
VaultHeistConfigs.HOURLY_STORM_PERIOD_SEC = 3600
VaultHeistConfigs.HOURLY_STORM_DURATION_SEC = 480
VaultHeistConfigs.HOURLY_STORM_REWARD_MULT = 1.50
VaultHeistConfigs.BASE_WALK_SPEED = 18
VaultHeistConfigs.BASE_SPRINT_SPEED = 24
VaultHeistConfigs.LASER_DAMAGE = 22
VaultHeistConfigs.BOSS_HP_SCALE_PER_PLAYER = 0.45
VaultHeistConfigs.BOSS_SPEED_SCALE_PER_PLAYER = 0.08
VaultHeistConfigs.SOLO_SIGHT_CONE_SCALE = 0.85

VaultHeistConfigs.ORDERED_ORBS = { "Decoy", "Freeze", "DashBomb" }
VaultHeistConfigs.DEFAULT_ORB_LEVELS = {
	Decoy = 1,
	Freeze = 0,
	DashBomb = 0,
}

VaultHeistConfigs.ORBS = {
	Decoy = {
		id = "Decoy",
		displayName = "Decoy Orb",
		shortLabel = "DECOY",
		description = "Spawns a holographic clone luring boss aggro within radius.",
		defaultLevel = 1,
		maxLevel = 6,
		baseCooldown = 8.0,
		cooldownPerLevel = -0.4,
		baseDuration = 5.0,
		durationPerLevel = 0.5,
		baseRadius = 45,
		radiusPerLevel = 3,
		laserPauseSec = 0,
		dashImpulse = 0,
		dashImpulsePerLevel = 0,
		bossKnockback = 0,
		bossKnockbackPerLevel = 0,
		carrySlowImmunitySec = 0,
		carrySlowImmunityPerLevel = 0,
		bossDamage = 0,
		upgradeCosts = { 0, 250, 650, 1500, 3400, 7500 },
		color = { 56, 217, 245 },
	},
	Freeze = {
		id = "Freeze",
		displayName = "Freeze Orb",
		shortLabel = "FREEZE",
		description = "14-stud cryo burst that stuns Bosses and pauses LaserGate for 4s.",
		defaultLevel = 0,
		maxLevel = 6,
		baseCooldown = 11.0,
		cooldownPerLevel = -0.5,
		baseDuration = 3.5,
		durationPerLevel = 0.3,
		baseRadius = 14,
		radiusPerLevel = 1,
		laserPauseSec = 4.0,
		dashImpulse = 0,
		dashImpulsePerLevel = 0,
		bossKnockback = 0,
		bossKnockbackPerLevel = 0,
		carrySlowImmunitySec = 0,
		carrySlowImmunityPerLevel = 0,
		bossDamage = 90,
		upgradeCosts = { 400, 900, 2000, 4500, 9500, 18000 },
		color = { 96, 165, 250 },
	},
	DashBomb = {
		id = "DashBomb",
		displayName = "Dash-Bomb Orb",
		shortLabel = "DASH",
		description = "+28 stud forward burst, boss knockback, and brief carry-slow immunity.",
		defaultLevel = 0,
		maxLevel = 6,
		baseCooldown = 10.0,
		cooldownPerLevel = -0.4,
		baseDuration = 0,
		durationPerLevel = 0,
		baseRadius = 16,
		radiusPerLevel = 1,
		laserPauseSec = 0,
		dashImpulse = 28,
		dashImpulsePerLevel = 2,
		bossKnockback = 26,
		bossKnockbackPerLevel = 3,
		carrySlowImmunitySec = 2.0,
		carrySlowImmunityPerLevel = 0.25,
		bossDamage = 140,
		upgradeCosts = { 1000, 2200, 4800, 10000, 20000, 36000 },
		color = { 251, 146, 60 },
	},
} :: { [string]: OrbConfig }

VaultHeistConfigs.CHAMBERS = {
	[1] = {
		chamber = 1,
		displayName = "Bronze Vault",
		standardEggId = "EmeraldMeadow_BossEgg",
		stormEggId = "EmeraldMeadow_OverchargedEgg",
		bossName = "Iron Vault Sentinel",
		bossBaseHP = 700,
		patrolSpeed = 13,
		chaseSpeed = 20,
		lungeSpeed = 52,
		telegraphSec = 1.25,
		lungeDamage = 26,
		lungeRadius = 11,
		sightRange = 46,
		sightHalfAngleDeg = 55,
		chamberDurationSec = 120,
		collapseDurationSec = 75,
		carrySlowFraction = 0.22,
		streakMult = 1.0,
		coinReward = 240,
		expReward = 80,
		gemReward = 4,
		primaryColor = { 132, 144, 158 },
		accentColor = { 245, 158, 11 },
	},
	[2] = {
		chamber = 2,
		displayName = "Cobalt Vault",
		standardEggId = "FrostbiteCavern_BossEgg",
		stormEggId = "FrostbiteCavern_OverchargedEgg",
		bossName = "Volt Stalker",
		bossBaseHP = 2400,
		patrolSpeed = 16,
		chaseSpeed = 23,
		lungeSpeed = 58,
		telegraphSec = 1.05,
		lungeDamage = 42,
		lungeRadius = 12,
		sightRange = 54,
		sightHalfAngleDeg = 62,
		chamberDurationSec = 105,
		collapseDurationSec = 60,
		carrySlowFraction = 0.27,
		streakMult = 1.8,
		coinReward = 1400,
		expReward = 260,
		gemReward = 10,
		primaryColor = { 56, 132, 224 },
		accentColor = { 56, 232, 255 },
	},
	[3] = {
		chamber = 3,
		displayName = "Obsidian Vault",
		standardEggId = "MoltenCaldera_BossEgg",
		stormEggId = "MoltenCaldera_OverchargedEgg",
		bossName = "Obsidian Vault Warden",
		bossBaseHP = 8500,
		patrolSpeed = 18,
		chaseSpeed = 26,
		lungeSpeed = 64,
		telegraphSec = 0.90,
		lungeDamage = 65,
		lungeRadius = 13,
		sightRange = 62,
		sightHalfAngleDeg = 68,
		chamberDurationSec = 95,
		collapseDurationSec = 50,
		carrySlowFraction = 0.32,
		streakMult = 3.0,
		coinReward = 8500,
		expReward = 850,
		gemReward = 22,
		primaryColor = { 44, 34, 56 },
		accentColor = { 255, 72, 196 },
	},
} :: { [number]: ChamberConfig }

VaultHeistConfigs.ORDERED_MUTATORS = {
	"LowGravity",
	"Darkness",
	"LaserSweep",
	"VaultStorm",
}

VaultHeistConfigs.MUTATORS = {
	LowGravity = {
		id = "LowGravity",
		displayName = "Low Gravity",
		description = "Reduced gravity for higher leaps and extended orb arcs.",
		gravityScale = 0.55,
		laserSpeedMult = 1.0,
		rewardMult = 1.15,
		stormEggChance = 0.0,
		accentColor = { 96, 212, 255 },
	},
	Darkness = {
		id = "Darkness",
		displayName = "Blackout Spotlight",
		description = "Dimmed chamber; boss red spotlight and egg glow light the dark.",
		gravityScale = 1.0,
		laserSpeedMult = 1.0,
		rewardMult = 1.25,
		stormEggChance = 0.15,
		accentColor = { 168, 85, 247 },
	},
	LaserSweep = {
		id = "LaserSweep",
		displayName = "Laser Sweep",
		description = "Faster sweeping laser barriers (pausable with Freeze Orbs).",
		gravityScale = 1.0,
		laserSpeedMult = 1.65,
		rewardMult = 1.25,
		stormEggChance = 0.15,
		accentColor = { 244, 63, 94 },
	},
	VaultStorm = {
		id = "VaultStorm",
		displayName = "Vault Storm",
		description = "Electrified surge boosting Overcharged egg chances and payouts!",
		gravityScale = 0.85,
		laserSpeedMult = 1.25,
		rewardMult = 1.50,
		stormEggChance = 0.50,
		accentColor = { 250, 204, 21 },
	},
} :: { [string]: MutatorConfig }

function VaultHeistConfigs.getOrb(orbId: string): OrbConfig?
	return VaultHeistConfigs.ORBS[orbId]
end

function VaultHeistConfigs.getOrbStats(orbId: string, level: number): OrbStats?
	local cfg = VaultHeistConfigs.ORBS[orbId]
	if not cfg then
		return nil
	end
	local lv = math.clamp(math.floor(level), 0, cfg.maxLevel)
	if lv <= 0 then
		return {
			level = 0,
			cooldown = cfg.baseCooldown,
			duration = 0,
			radius = cfg.baseRadius,
			laserPauseSec = 0,
			dashImpulse = 0,
			bossKnockback = 0,
			carrySlowImmunitySec = 0,
			bossDamage = 0,
		}
	end
	local step = lv - 1
	return {
		level = lv,
		cooldown = math.max(3.5, cfg.baseCooldown + cfg.cooldownPerLevel * step),
		duration = if cfg.baseDuration > 0
			then cfg.baseDuration + cfg.durationPerLevel * step
			else 0,
		radius = cfg.baseRadius + cfg.radiusPerLevel * step,
		laserPauseSec = cfg.laserPauseSec,
		dashImpulse = if cfg.dashImpulse > 0
			then cfg.dashImpulse + cfg.dashImpulsePerLevel * step
			else 0,
		bossKnockback = if cfg.bossKnockback > 0
			then cfg.bossKnockback + cfg.bossKnockbackPerLevel * step
			else 0,
		carrySlowImmunitySec = if cfg.carrySlowImmunitySec > 0
			then cfg.carrySlowImmunitySec + cfg.carrySlowImmunityPerLevel * step
			else 0,
		bossDamage = if cfg.bossDamage > 0
			then math.floor(cfg.bossDamage * (1 + 0.2 * step))
			else 0,
	}
end

function VaultHeistConfigs.getOrbUpgradeCost(orbId: string, currentLevel: number): number?
	local cfg = VaultHeistConfigs.ORBS[orbId]
	if not cfg then
		return nil
	end
	local lv = math.floor(currentLevel)
	if lv < 0 or lv >= cfg.maxLevel then
		return nil
	end
	return cfg.upgradeCosts[lv + 1]
end

function VaultHeistConfigs.getChamber(chamber: number): ChamberConfig
	local idx = math.clamp(math.floor(chamber), 1, VaultHeistConfigs.MAX_CHAMBER)
	return VaultHeistConfigs.CHAMBERS[idx]
end

function VaultHeistConfigs.getMutator(mutatorId: string): MutatorConfig
	return VaultHeistConfigs.MUTATORS[mutatorId] or VaultHeistConfigs.MUTATORS.LowGravity
end

function VaultHeistConfigs.scaleBossHP(baseHP: number, playerCount: number): number
	local count = math.clamp(math.floor(playerCount), 1, VaultHeistConfigs.MAX_SQUAD_SIZE)
	local mult = 1 + VaultHeistConfigs.BOSS_HP_SCALE_PER_PLAYER * (count - 1)
	return math.floor(baseHP * mult + 0.5)
end

function VaultHeistConfigs.scaleBossSpeed(baseSpeed: number, playerCount: number): number
	local count = math.clamp(math.floor(playerCount), 1, VaultHeistConfigs.MAX_SQUAD_SIZE)
	if count == 1 then
		return baseSpeed * 0.92
	end
	return baseSpeed * (1 + VaultHeistConfigs.BOSS_SPEED_SCALE_PER_PLAYER * (count - 2))
end

return VaultHeistConfigs
