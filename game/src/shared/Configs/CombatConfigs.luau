--!strict
-- Combat tuning for issue #5. The throw baseline matches the client projectile arc.

export type BallTier = {
	displayName: string,
	damageMultiplier: number,
	projectileSpeed: number,
	ballRadius: number,
	costCoins: number,
}

export type TargetTier = { damageMult: number }

export type MobConfig = {
	maxHp: number,
	hitRadius: number,
	expReward: number,
	baseBallDamageGain: number,
	coinsReward: number,
	walkSpeed: number,
	contactDamage: number,
	respawnSeconds: number,
}

local CombatConfigs = {}

local ballTiers: { [string]: BallTier } = {
	RubberBall = table.freeze({
		displayName = "Rubber Ball",
		damageMultiplier = 1.0,
		projectileSpeed = 135,
		ballRadius = 0.55,
		costCoins = 0,
	}),
	IronSphere = table.freeze({
		displayName = "Iron Sphere",
		damageMultiplier = 1.5,
		projectileSpeed = 145,
		ballRadius = 0.60,
		costCoins = 250,
	}),
	FrostOrb = table.freeze({
		displayName = "Frost Orb",
		damageMultiplier = 2.25,
		projectileSpeed = 155,
		ballRadius = 0.65,
		costCoins = 2_500,
	}),
	MagmaCore = table.freeze({
		displayName = "Magma Core",
		damageMultiplier = 3.5,
		projectileSpeed = 165,
		ballRadius = 0.70,
		costCoins = 25_000,
	}),
	NovaSphere = table.freeze({
		displayName = "Nova Sphere",
		damageMultiplier = 5.0,
		projectileSpeed = 180,
		ballRadius = 0.75,
		costCoins = 250_000,
	}),
}
CombatConfigs.BallTiers = table.freeze(ballTiers)

CombatConfigs.Throw = table.freeze({
	BASE_THROW_COOLDOWN = 0.35,
	MIN_THROW_COOLDOWN = 0.15,
	COOLDOWN_JITTER_TOLERANCE = 0.04,
	THROW_SPEED_HALF_SATURATION = 100,
	MAX_THROW_SPEED_VEL_BONUS = 0.30,
	GRAVITY = 42,
	MAX_FLIGHT_SECONDS = 1.6,
	SWEEP_STEP_SECONDS = 0.05,
	MAX_ORIGIN_DISTANCE_STUDS = 12.0,
	PLAYER_HIT_RADIUS_STUDS = 2.2,
	DEFAULT_BASE_BALL_DAMAGE = 10,
})

local targetTiers: { [string]: TargetTier } = {
	WoodenDummy = table.freeze({ damageMult = 1.0 }),
	IronBullseye = table.freeze({ damageMult = 2.5 }),
	CrystalDrone = table.freeze({ damageMult = 6.0 }),
	ObsidianCore = table.freeze({ damageMult = 15.0 }),
}

CombatConfigs.Training = table.freeze({
	TargetTiers = table.freeze(targetTiers),
	BASE_TRAINING_DAMAGE_GAIN = 0.5,
	MOVING_GOLD_DAMAGE_MULT = 2.0,
	MOVING_GOLD_THROW_SPEED_GAIN = 1.0,
	PAD_HORIZONTAL_MARGIN = 1.5,
	PAD_MIN_Y = -0.5,
	PAD_MAX_Y = 7.5,
})

local mobs: { [string]: MobConfig } = {
	MossSlime = table.freeze({
		maxHp = 45,
		hitRadius = 2.4,
		expReward = 20,
		baseBallDamageGain = 0.5,
		coinsReward = 15,
		walkSpeed = 12,
		contactDamage = 8,
		respawnSeconds = 6,
	}),
	BrambleBoar = table.freeze({
		maxHp = 90,
		hitRadius = 2.8,
		expReward = 40,
		baseBallDamageGain = 1.0,
		coinsReward = 30,
		walkSpeed = 16,
		contactDamage = 14,
		respawnSeconds = 9,
	}),
}
CombatConfigs.Mobs = table.freeze(mobs)

CombatConfigs.PlayerProgression = table.freeze({
	BASE_MAX_HP = 100,
	HP_PER_LEVEL = 15,
	EXP_BASE = 100,
	EXP_GROWTH = 1.25,
})

CombatConfigs.Bosses = table.freeze({
	MossbackGolem = table.freeze({
		biomeId = "EmeraldMeadow",
		baseHp = 1_560,
		hpScalePerExtraPlayer = 0.35,
		hitRadius = 5.0,
		moveSpeed = 12.0,
		meleeStopDistance = 10.0,
		slam = table.freeze({
			triggerRange = 22.0,
			windupSeconds = 1.20,
			activeSeconds = 0.75,
			maxRadius = 26.0,
			ringHalfWidth = 2.5,
			hitHeight = 5.5,
			damage = 28,
			recoverySeconds = 0.80,
			cooldownSeconds = 6.00,
		}),
		boulder = table.freeze({
			minRange = 12.0,
			maxRange = 75.0,
			windupSeconds = 1.00,
			radius = 3.2,
			speed = 46.0,
			maxDistance = 75.0,
			maxLifetimeSeconds = 2.00,
			damage = 22,
			knockbackImpulse = 42.0,
			recoverySeconds = 0.70,
			cooldownSeconds = 4.50,
		}),
		overcharged = table.freeze({
			hpMultiplier = 1.40,
			speedMultiplier = 1.15,
			windupMultiplier = 0.85,
			recoveryMultiplier = 0.85,
			cooldownMultiplier = 0.80,
			damageMultiplier = 1.20,
		}),
	}),
})

return CombatConfigs
