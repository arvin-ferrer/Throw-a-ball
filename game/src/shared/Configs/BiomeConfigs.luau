--!strict
--[[
	BiomeConfigs.luau
	Canonical 3 MVP Biomes (Emerald Meadow, Frostbite Cavern, Molten Caldera),
	mob tables, Boss stats, dynamic +35%/player HP scaling, and 5-Min Overcharged cadence.
]]

export type MobConfig = {
	id: string,
	displayName: string,
	biomeId: string,
	maxHP: number,
	moveSpeed: number,
	attackDamage: number,
	attackRange: number,
	attackCooldown: number,
	expReward: number,
	coinReward: number,
	ballDmgGain: number,
	respawnSec: number,
	primaryColor: { number },
	accentColor: { number },
}

export type BossAttackSpec = {
	id: string,
	displayName: string,
	telegraphSec: number,
	cooldownSec: number,
	damage: number,
	radius: number,
	kind: "Shockwave" | "Projectile" | "Cone" | "RingDrop" | "Geysers",
}

export type BossConfig = {
	id: string,
	displayName: string,
	biomeId: string,
	baseHP: number,
	moveSpeed: number,
	participationCoins: number,
	participationExp: number,
	participationGems: number,
	winnerBonusCoins: number,
	winnerBonusGems: number,
	pvpKillGems: number,
	primaryColor: { number },
	accentColor: { number },
	attacks: { BossAttackSpec },
}

export type BiomeConfig = {
	id: string,
	order: number,
	displayName: string,
	enabled: boolean,
	recommendedDamage: number,
	pveCycleSeconds: number,
	pveDmgMultiplier: number,
	bossId: string,
	standardEggId: string,
	overchargedEggId: string,
	themeColor: { number },
	fogColor: { number },
	ambientColor: { number },
	mobs: { string },
}

local BiomeConfigs = {}

BiomeConfigs.BOSS_HP_SCALE_PER_EXTRA_PLAYER = 0.35
BiomeConfigs.OVERCHARGED_INTERVAL_SEC = 300
BiomeConfigs.OVERCHARGED_HP_MULT = 1.40
BiomeConfigs.OVERCHARGED_AGGRESSION_MULT = 0.80
BiomeConfigs.OPT_IN_WINDOW_SEC = 15
BiomeConfigs.BOSS_PHASE_TIMEOUT_SEC = 180
BiomeConfigs.PVP_GRACE_SEC = 3
BiomeConfigs.EGG_CLAIM_DURATION_SEC = 5.0
BiomeConfigs.EGG_CLAIM_RADIUS = 12
BiomeConfigs.SUDDEN_DEATH_START_SEC = 75
BiomeConfigs.SUDDEN_DEATH_SHRINK_SEC = 45
BiomeConfigs.SUDDEN_DEATH_START_RADIUS = 115
BiomeConfigs.SUDDEN_DEATH_MIN_RADIUS = 14
BiomeConfigs.SUDDEN_DEATH_DPS_FRACTION = 0.08

BiomeConfigs.ORDERED_MVP_BIOMES = {
	"EmeraldMeadow",
	"FrostbiteCavern",
	"MoltenCaldera",
}

BiomeConfigs.BIOMES = {
	EmeraldMeadow = {
		id = "EmeraldMeadow",
		order = 1,
		displayName = "Emerald Meadow",
		enabled = true,
		recommendedDamage = 15,
		pveCycleSeconds = 90,
		pveDmgMultiplier = 1.5,
		bossId = "MossbackGolem",
		standardEggId = "EmeraldMeadow_BossEgg",
		overchargedEggId = "EmeraldMeadow_OverchargedEgg",
		themeColor = { 52, 211, 153 },
		fogColor = { 172, 232, 198 },
		ambientColor = { 112, 156, 128 },
		mobs = { "MossSlime", "BrambleBoar" },
	},
	FrostbiteCavern = {
		id = "FrostbiteCavern",
		order = 2,
		displayName = "Frostbite Cavern",
		enabled = true,
		recommendedDamage = 150,
		pveCycleSeconds = 105,
		pveDmgMultiplier = 3.2,
		bossId = "GlacierYeti",
		standardEggId = "FrostbiteCavern_BossEgg",
		overchargedEggId = "FrostbiteCavern_OverchargedEgg",
		themeColor = { 56, 189, 248 },
		fogColor = { 164, 218, 248 },
		ambientColor = { 102, 140, 178 },
		mobs = { "IceWraith", "CrystalWolf" },
	},
	MoltenCaldera = {
		id = "MoltenCaldera",
		order = 3,
		displayName = "Molten Caldera",
		enabled = true,
		recommendedDamage = 1200,
		pveCycleSeconds = 120,
		pveDmgMultiplier = 6.0,
		bossId = "ObsidianWyrm",
		standardEggId = "MoltenCaldera_BossEgg",
		overchargedEggId = "MoltenCaldera_OverchargedEgg",
		themeColor = { 251, 113, 42 },
		fogColor = { 126, 56, 42 },
		ambientColor = { 150, 82, 62 },
		mobs = { "CinderImp", "MagmaHound" },
	},
} :: { [string]: BiomeConfig }

BiomeConfigs.MOBS = {
	MossSlime = {
		id = "MossSlime",
		displayName = "Moss Slime",
		biomeId = "EmeraldMeadow",
		maxHP = 45,
		moveSpeed = 12,
		attackDamage = 10,
		attackRange = 6,
		attackCooldown = 1.6,
		expReward = 22,
		coinReward = 28,
		ballDmgGain = 2,
		respawnSec = 6,
		primaryColor = { 74, 222, 128 },
		accentColor = { 22, 163, 74 },
	},
	BrambleBoar = {
		id = "BrambleBoar",
		displayName = "Bramble Boar",
		biomeId = "EmeraldMeadow",
		maxHP = 85,
		moveSpeed = 15,
		attackDamage = 16,
		attackRange = 7,
		attackCooldown = 1.4,
		expReward = 38,
		coinReward = 50,
		ballDmgGain = 4,
		respawnSec = 8,
		primaryColor = { 120, 84, 56 },
		accentColor = { 52, 211, 153 },
	},
	IceWraith = {
		id = "IceWraith",
		displayName = "Ice Wraith",
		biomeId = "FrostbiteCavern",
		maxHP = 480,
		moveSpeed = 16,
		attackDamage = 32,
		attackRange = 10,
		attackCooldown = 1.5,
		expReward = 140,
		coinReward = 280,
		ballDmgGain = 18,
		respawnSec = 7,
		primaryColor = { 125, 211, 252 },
		accentColor = { 224, 242, 254 },
	},
	CrystalWolf = {
		id = "CrystalWolf",
		displayName = "Crystal Wolf",
		biomeId = "FrostbiteCavern",
		maxHP = 780,
		moveSpeed = 20,
		attackDamage = 44,
		attackRange = 7,
		attackCooldown = 1.25,
		expReward = 210,
		coinReward = 440,
		ballDmgGain = 28,
		respawnSec = 8,
		primaryColor = { 56, 189, 248 },
		accentColor = { 165, 180, 252 },
	},
	CinderImp = {
		id = "CinderImp",
		displayName = "Cinder Imp",
		biomeId = "MoltenCaldera",
		maxHP = 3600,
		moveSpeed = 19,
		attackDamage = 72,
		attackRange = 11,
		attackCooldown = 1.3,
		expReward = 560,
		coinReward = 2200,
		ballDmgGain = 115,
		respawnSec = 7,
		primaryColor = { 249, 115, 22 },
		accentColor = { 253, 224, 71 },
	},
	MagmaHound = {
		id = "MagmaHound",
		displayName = "Magma Hound",
		biomeId = "MoltenCaldera",
		maxHP = 5800,
		moveSpeed = 22,
		attackDamage = 95,
		attackRange = 8,
		attackCooldown = 1.15,
		expReward = 820,
		coinReward = 3500,
		ballDmgGain = 175,
		respawnSec = 9,
		primaryColor = { 55, 42, 48 },
		accentColor = { 239, 68, 68 },
	},
} :: { [string]: MobConfig }

BiomeConfigs.BOSSES = {
	MossbackGolem = {
		id = "MossbackGolem",
		displayName = "Mossback Golem",
		biomeId = "EmeraldMeadow",
		baseHP = 900,
		moveSpeed = 13,
		participationCoins = 320,
		participationExp = 120,
		participationGems = 6,
		winnerBonusCoins = 500,
		winnerBonusGems = 8,
		pvpKillGems = 3,
		primaryColor = { 104, 118, 108 },
		accentColor = { 74, 222, 128 },
		attacks = {
			{
				id = "GroundSlam",
				displayName = "Ground-Slam Shockwave",
				telegraphSec = 1.15,
				cooldownSec = 4.2,
				damage = 28,
				radius = 26,
				kind = "Shockwave",
			},
			{
				id = "RollingBoulder",
				displayName = "Rolling Boulder Throw",
				telegraphSec = 0.85,
				cooldownSec = 3.6,
				damage = 24,
				radius = 9,
				kind = "Projectile",
			},
		},
	},
	GlacierYeti = {
		id = "GlacierYeti",
		displayName = "Glacier Yeti",
		biomeId = "FrostbiteCavern",
		baseHP = 9000,
		moveSpeed = 16,
		participationCoins = 3200,
		participationExp = 520,
		participationGems = 14,
		winnerBonusCoins = 5200,
		winnerBonusGems = 16,
		pvpKillGems = 6,
		primaryColor = { 208, 236, 255 },
		accentColor = { 56, 189, 248 },
		attacks = {
			{
				id = "FrostBreath",
				displayName = "Frost Breath Cone",
				telegraphSec = 1.0,
				cooldownSec = 4.0,
				damage = 64,
				radius = 30,
				kind = "Cone",
			},
			{
				id = "IcicleRings",
				displayName = "Falling Icicle Rings",
				telegraphSec = 1.2,
				cooldownSec = 4.5,
				damage = 58,
				radius = 16,
				kind = "RingDrop",
			},
		},
	},
	ObsidianWyrm = {
		id = "ObsidianWyrm",
		displayName = "Obsidian Wyrm",
		biomeId = "MoltenCaldera",
		baseHP = 75000,
		moveSpeed = 19,
		participationCoins = 26000,
		participationExp = 1900,
		participationGems = 32,
		winnerBonusCoins = 42000,
		winnerBonusGems = 36,
		pvpKillGems = 12,
		primaryColor = { 38, 30, 44 },
		accentColor = { 255, 96, 32 },
		attacks = {
			{
				id = "LavaBreath",
				displayName = "Sweeping Lava Breath",
				telegraphSec = 1.0,
				cooldownSec = 3.8,
				damage = 135,
				radius = 36,
				kind = "Cone",
			},
			{
				id = "FloorGeysers",
				displayName = "Erupting Floor Geysers",
				telegraphSec = 1.15,
				cooldownSec = 4.1,
				damage = 120,
				radius = 18,
				kind = "Geysers",
			},
		},
	},
} :: { [string]: BossConfig }

function BiomeConfigs.computeBossMaxHP(
	biomeId: string,
	optInPlayerCount: number,
	isOvercharged: boolean
): number
	local biome = BiomeConfigs.BIOMES[biomeId]
	if not biome then
		error(`Unknown biomeId: {biomeId}`)
	end
	local boss = BiomeConfigs.BOSSES[biome.bossId]
	local count = math.max(1, math.floor(optInPlayerCount))
	local scaled = boss.baseHP * (1 + BiomeConfigs.BOSS_HP_SCALE_PER_EXTRA_PLAYER * (count - 1))
	if isOvercharged then
		scaled *= BiomeConfigs.OVERCHARGED_HP_MULT
	end
	return math.floor(scaled + 0.5)
end

function BiomeConfigs.computeSuddenDeathRadius(pvpElapsedSec: number): number
	if pvpElapsedSec <= BiomeConfigs.SUDDEN_DEATH_START_SEC then
		return BiomeConfigs.SUDDEN_DEATH_START_RADIUS
	end
	local over = pvpElapsedSec - BiomeConfigs.SUDDEN_DEATH_START_SEC
	local alpha = math.clamp(over / BiomeConfigs.SUDDEN_DEATH_SHRINK_SEC, 0, 1)
	local startR = BiomeConfigs.SUDDEN_DEATH_START_RADIUS
	local endR = BiomeConfigs.SUDDEN_DEATH_MIN_RADIUS
	return startR + (endR - startR) * alpha
end

function BiomeConfigs.getBiome(biomeId: string): BiomeConfig?
	return BiomeConfigs.BIOMES[biomeId]
end

function BiomeConfigs.getBossForBiome(biomeId: string): BossConfig?
	local biome = BiomeConfigs.BIOMES[biomeId]
	if not biome then
		return nil
	end
	return BiomeConfigs.BOSSES[biome.bossId]
end

return BiomeConfigs
