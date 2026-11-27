--!strict
--[[
	VaultHeistLogic.luau
	Pure server-authoritative state machine and math for C2: Egg Heist (1-4p Boss Vault Heist).
	100% Lune-testable with zero Roblox Instance dependencies.
]]

local req: any = require
local scriptRef: any = script
local isRoblox = type(scriptRef) == "userdata"
local VaultHeistConfigs = if isRoblox
	then req(scriptRef.Parent.Parent.Configs.VaultHeistConfigs)
	else req("../Configs/VaultHeistConfigs")
local MathUtil = if isRoblox then req(scriptRef.Parent.MathUtil) else req("./MathUtil")

export type Vec3 = {
	x: number,
	y: number,
	z: number,
}

export type BossState = "PATROL" | "INVESTIGATE" | "TELEGRAPH" | "LUNGE" | "STUNNED"

export type DecoyEntity = {
	id: string,
	ownerUserId: number,
	pos: Vec3,
	expiresAt: number,
	radius: number,
}

export type VaultPlayerState = {
	userId: number,
	hp: number,
	maxHP: number,
	downed: boolean,
	downedAt: number,
	reviveProgress: number,
	invulnUntil: number,
	carrySlowImmuneUntil: number,
	soloReviveUsed: boolean,
	orbCooldowns: { [string]: number },
	orbLevels: { [string]: number },
	voteChoice: ("Extract" | "Dive")?,
}

export type VaultBossState = {
	state: BossState,
	hp: number,
	maxHP: number,
	pos: Vec3,
	facingYaw: number,
	patrolIndex: number,
	targetPos: Vec3?,
	targetUserId: number?,
	decoyId: string?,
	stateStartedAt: number,
	stateEndsAt: number,
	investigateStartedAt: number,
	telegraphOrigin: Vec3?,
	telegraphDir: Vec3?,
	lungeHitUsers: { [number]: boolean },
	stunEndsAt: number,
	lungeCooldownUntil: number,
}

export type VaultRunState = {
	runId: string,
	groupKey: string,
	chamber: number,
	mutatorId: string,
	isHourlyStorm: boolean,
	phase: "Active" | "Vote" | "Finished",
	players: { [number]: VaultPlayerState },
	playerOrder: { number },
	totalRunPlayers: number,
	boss: VaultBossState,
	decoys: { DecoyEntity },
	nextDecoySeq: number,
	eggPedestalAvailable: boolean,
	droppedEggPos: Vec3?,
	carrierUserId: number?,
	carryingEggId: string?,
	runBagEggs: { string },
	laserPausedUntil: number,
	startedAt: number,
	chamberEndsAt: number,
	alarmTriggered: boolean,
	streakMult: number,
	voteEndsAt: number?,
	votePayoutDone: boolean,
}

export type VaultEvent = {
	kind: string,
	payload: { [string]: any },
}

export type TxResult = {
	ok: boolean,
	reason: string?,
	data: { [string]: any }?,
}

export type PlayerSeed = {
	userId: number,
	maxHP: number,
	orbLevels: { [string]: number }?,
}

local VaultHeistLogic = {}

local function v3(x: number, y: number, z: number): Vec3
	return { x = x, y = y, z = z }
end

local function isFiniteVec3(vec: any): boolean
	return type(vec) == "table"
		and MathUtil.isFinite(vec.x)
		and MathUtil.isFinite(vec.y)
		and MathUtil.isFinite(vec.z)
end

local function flatDist(a: Vec3, b: Vec3): number
	return MathUtil.distance2D(a.x, a.z, b.x, b.z)
end

local function dist3D(a: Vec3, b: Vec3): number
	return MathUtil.distance3D(a.x, a.y, a.z, b.x, b.y, b.z)
end

local function flatDir(from: Vec3, to: Vec3): (Vec3, number)
	local dx = to.x - from.x
	local dz = to.z - from.z
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 1e-4 then
		return v3(0, 0, -1), 0
	end
	return v3(dx / len, 0, dz / len), len
end

local function clampToExtent(pos: Vec3, center: Vec3?, halfExtent: number?): Vec3
	if not center or not halfExtent or halfExtent <= 0 then
		return pos
	end
	return v3(
		math.clamp(pos.x, center.x - halfExtent, center.x + halfExtent),
		pos.y,
		math.clamp(pos.z, center.z - halfExtent, center.z + halfExtent)
	)
end

local function yawFromDir(dir: Vec3): number
	return math.atan2(-dir.x, -dir.z)
end

local function countLivingPlayers(run: VaultRunState): number
	local living = 0
	for _, uid in ipairs(run.playerOrder) do
		local ps = run.players[uid]
		if ps and not ps.downed then
			living += 1
		end
	end
	return living
end

function VaultHeistLogic.ensureOrbLevels(profile: any): { [string]: number }
	local levels: { [string]: number } = if type(profile) == "table"
			and type(profile.orbLevels) == "table"
		then profile.orbLevels
		else {}
	for _, orbId in ipairs(VaultHeistConfigs.ORDERED_ORBS) do
		local cfg = VaultHeistConfigs.ORBS[orbId]
		local raw = levels[orbId]
		local fallback = if cfg then cfg.defaultLevel else 0
		local maxLv = if cfg then cfg.maxLevel else 6
		if type(raw) ~= "number" or not MathUtil.isFinite(raw) then
			levels[orbId] = fallback
		else
			levels[orbId] = math.clamp(math.floor(raw), fallback, maxLv)
		end
	end
	if type(profile) == "table" then
		profile.orbLevels = levels
	end
	return levels
end

function VaultHeistLogic.upgradeOrb(profile: any, orbId: string): TxResult
	if type(profile) ~= "table" or type(orbId) ~= "string" then
		return { ok = false, reason = "InvalidArgs" }
	end
	local cfg = VaultHeistConfigs.getOrb(orbId)
	if not cfg then
		return { ok = false, reason = "UnknownOrb" }
	end
	if not MathUtil.isFinite(profile.coins) or (profile.coins :: number) < 0 then
		return { ok = false, reason = "InvalidBalance" }
	end
	local levels = VaultHeistLogic.ensureOrbLevels(profile)
	local curLv = levels[orbId] or cfg.defaultLevel
	if curLv >= cfg.maxLevel then
		return { ok = false, reason = "MaxOrbLevel" }
	end
	local cost = VaultHeistConfigs.getOrbUpgradeCost(orbId, curLv)
	if not cost or (profile.coins :: number) < cost then
		return { ok = false, reason = "InsufficientCoins" }
	end
	profile.coins -= cost
	levels[orbId] = curLv + 1
	return {
		ok = true,
		data = {
			orbId = orbId,
			newLevel = curLv + 1,
			cost = cost,
		},
	}
end

function VaultHeistLogic.isHourlyVaultStormActive(unixTime: number): boolean
	if not MathUtil.isFinite(unixTime) or unixTime < 0 then
		return false
	end
	local rem = math.floor(unixTime) % VaultHeistConfigs.HOURLY_STORM_PERIOD_SEC
	return rem < VaultHeistConfigs.HOURLY_STORM_DURATION_SEC
end

function VaultHeistLogic.getHourlyVaultStormRemaining(unixTime: number): number
	if not MathUtil.isFinite(unixTime) or unixTime < 0 then
		return VaultHeistConfigs.HOURLY_STORM_PERIOD_SEC
	end
	local rem = math.floor(unixTime) % VaultHeistConfigs.HOURLY_STORM_PERIOD_SEC
	if rem < VaultHeistConfigs.HOURLY_STORM_DURATION_SEC then
		return VaultHeistConfigs.HOURLY_STORM_DURATION_SEC - rem
	end
	return VaultHeistConfigs.HOURLY_STORM_PERIOD_SEC - rem
end

function VaultHeistLogic.resolveJoinGroupKey(userId: number, partyId: string?): string
	if type(partyId) == "string" and partyId ~= "" then
		return "party:" .. partyId
	end
	return "solo:" .. tostring(userId)
end

function VaultHeistLogic.pickChamberMutator(
	chamber: number,
	isHourlyStorm: boolean,
	rollUnit: number
): string
	if isHourlyStorm then
		return "VaultStorm"
	end
	local list = VaultHeistConfigs.ORDERED_MUTATORS
	local u = if MathUtil.isFinite(rollUnit) then math.clamp(rollUnit, 0, 0.999999) else 0
	local idx = math.floor(u * #list) + 1
	if chamber == 1 and list[idx] == "VaultStorm" then
		return "LowGravity"
	end
	return list[idx]
end

local function createBossState(
	chamber: number,
	playerCount: number,
	spawnPos: Vec3,
	now: number
): VaultBossState
	local cfg = VaultHeistConfigs.getChamber(chamber)
	local maxHP = VaultHeistConfigs.scaleBossHP(cfg.bossBaseHP, playerCount)
	return {
		state = "PATROL",
		hp = maxHP,
		maxHP = maxHP,
		pos = v3(spawnPos.x, spawnPos.y, spawnPos.z),
		facingYaw = 0,
		patrolIndex = 1,
		targetPos = nil,
		targetUserId = nil,
		decoyId = nil,
		stateStartedAt = now,
		stateEndsAt = now,
		investigateStartedAt = 0,
		telegraphOrigin = nil,
		telegraphDir = nil,
		lungeHitUsers = {},
		stunEndsAt = 0,
		lungeCooldownUntil = 0,
	}
end

local function createPlayerState(seed: PlayerSeed): VaultPlayerState
	local maxHP = math.max(50, math.floor(seed.maxHP))
	return {
		userId = seed.userId,
		hp = maxHP,
		maxHP = maxHP,
		downed = false,
		downedAt = 0,
		reviveProgress = 0,
		invulnUntil = 0,
		carrySlowImmuneUntil = 0,
		soloReviveUsed = false,
		orbCooldowns = {},
		orbLevels = VaultHeistLogic.ensureOrbLevels({ orbLevels = seed.orbLevels }),
		voteChoice = nil,
	}
end

function VaultHeistLogic.computeStreakMult(
	chamber: number,
	mutatorId: string,
	isHourlyStorm: boolean
): number
	local ch = VaultHeistConfigs.getChamber(chamber)
	local mut = VaultHeistConfigs.getMutator(mutatorId)
	local stormMult = if isHourlyStorm then VaultHeistConfigs.HOURLY_STORM_REWARD_MULT else 1.0
	return ch.streakMult * mut.rewardMult * stormMult
end

local function buildSeededPlayers(
	seeds: { PlayerSeed }
): ({ [number]: VaultPlayerState }, { number })
	local playerMap: { [number]: VaultPlayerState } = {}
	local order: { number } = {}
	for _, seed in ipairs(seeds) do
		if MathUtil.isFinite(seed.userId) and not playerMap[seed.userId] then
			playerMap[seed.userId] = createPlayerState(seed)
			table.insert(order, seed.userId)
		end
	end
	return playerMap, order
end

function VaultHeistLogic.createRun(params: {
	runId: string,
	groupKey: string,
	chamber: number?,
	mutatorId: string?,
	isHourlyStorm: boolean?,
	now: number,
	bossSpawnPos: Vec3,
	players: { PlayerSeed },
}): VaultRunState
	local chamber = math.clamp(math.floor(params.chamber or 1), 1, VaultHeistConfigs.MAX_CHAMBER)
	local isStorm = params.isHourlyStorm == true
	local mutatorId = params.mutatorId or VaultHeistLogic.pickChamberMutator(chamber, isStorm, 0.0)
	local chCfg = VaultHeistConfigs.getChamber(chamber)
	local playerMap, order = buildSeededPlayers(params.players)
	local count = math.max(1, #order)
	return {
		runId = params.runId,
		groupKey = params.groupKey,
		chamber = chamber,
		mutatorId = mutatorId,
		isHourlyStorm = isStorm,
		phase = "Active",
		players = playerMap,
		playerOrder = order,
		totalRunPlayers = count,
		boss = createBossState(chamber, count, params.bossSpawnPos, params.now),
		decoys = {},
		nextDecoySeq = 0,
		eggPedestalAvailable = true,
		droppedEggPos = nil,
		carrierUserId = nil,
		carryingEggId = nil,
		runBagEggs = {},
		laserPausedUntil = 0,
		startedAt = params.now,
		chamberEndsAt = params.now + chCfg.chamberDurationSec,
		alarmTriggered = false,
		streakMult = VaultHeistLogic.computeStreakMult(chamber, mutatorId, isStorm),
		voteEndsAt = nil,
		votePayoutDone = false,
	}
end

function VaultHeistLogic.addPlayerToRun(run: VaultRunState, seed: PlayerSeed): boolean
	if
		run.phase ~= "Active"
		or run.players[seed.userId] ~= nil
		or #run.playerOrder >= VaultHeistConfigs.MAX_SQUAD_SIZE
	then
		return false
	end
	run.players[seed.userId] = createPlayerState(seed)
	table.insert(run.playerOrder, seed.userId)
	run.totalRunPlayers = math.max(run.totalRunPlayers, #run.playerOrder)
	local chCfg = VaultHeistConfigs.getChamber(run.chamber)
	local oldMax = math.max(1, run.boss.maxHP)
	local ratio = math.clamp(run.boss.hp / oldMax, 0, 1)
	local newMax = VaultHeistConfigs.scaleBossHP(chCfg.bossBaseHP, run.totalRunPlayers)
	run.boss.maxHP = newMax
	run.boss.hp = math.max(1, math.floor(newMax * ratio + 0.5))
	return true
end

function VaultHeistLogic.getPlayerMoveSpeed(
	run: VaultRunState,
	userId: number,
	now: number,
	isSprinting: boolean
): number
	local ps = run.players[userId]
	if not ps or ps.downed then
		return 0
	end
	local base = if isSprinting
		then VaultHeistConfigs.BASE_SPRINT_SPEED
		else VaultHeistConfigs.BASE_WALK_SPEED
	if run.carrierUserId == userId and now >= ps.carrySlowImmuneUntil then
		local chCfg = VaultHeistConfigs.getChamber(run.chamber)
		base *= (1 - chCfg.carrySlowFraction)
	end
	return base
end

function VaultHeistLogic.getChamberEggId(
	chamber: number,
	mutatorId: string,
	isHourlyStorm: boolean,
	rollUnit: number?
): string
	local chCfg = VaultHeistConfigs.getChamber(chamber)
	local mut = VaultHeistConfigs.getMutator(mutatorId)
	local chance = mut.stormEggChance
	if isHourlyStorm then
		chance = math.max(chance, 0.65)
	end
	if chamber >= 3 then
		chance = math.max(chance, 0.25)
	end
	local roll = if rollUnit ~= nil and MathUtil.isFinite(rollUnit) then rollUnit else 0.99
	if roll < chance then
		return chCfg.stormEggId
	end
	return chCfg.standardEggId
end

function VaultHeistLogic.tryGrabEgg(
	run: VaultRunState,
	userId: number,
	playerPos: Vec3,
	pedestalPos: Vec3,
	now: number,
	rollUnit: number?
): (boolean, string?, { VaultEvent })
	local events: { VaultEvent } = {}
	local ps = run.players[userId]
	if run.phase ~= "Active" or not ps or ps.downed or run.carrierUserId ~= nil then
		return false, "CannotGrab", events
	end
	if not isFiniteVec3(playerPos) or not MathUtil.isFinite(now) then
		return false, "InvalidArgs", events
	end
	local canPedestal = run.eggPedestalAvailable and dist3D(playerPos, pedestalPos) <= 14
	local canDrop = run.droppedEggPos ~= nil and dist3D(playerPos, run.droppedEggPos :: Vec3) <= 12
	if not canPedestal and not canDrop then
		return false, "OutOfRange", events
	end
	local chCfg = VaultHeistConfigs.getChamber(run.chamber)
	local eggId = run.carryingEggId
		or VaultHeistLogic.getChamberEggId(run.chamber, run.mutatorId, run.isHourlyStorm, rollUnit)
	run.carrierUserId = userId
	run.carryingEggId = eggId
	run.eggPedestalAvailable = false
	run.droppedEggPos = nil
	if not run.alarmTriggered then
		run.alarmTriggered = true
		run.chamberEndsAt = math.min(run.chamberEndsAt, now + chCfg.collapseDurationSec)
	end
	if run.boss.state == "PATROL" then
		run.boss.state = "INVESTIGATE"
		run.boss.targetUserId = userId
		run.boss.targetPos = v3(playerPos.x, playerPos.y, playerPos.z)
		run.boss.investigateStartedAt = now
	end
	table.insert(events, {
		kind = "EggGrabbed",
		payload = { userId = userId, eggId = eggId, chamber = run.chamber },
	})
	return true, nil, events
end

function VaultHeistLogic.dropEgg(
	run: VaultRunState,
	userId: number,
	dropPos: Vec3,
	now: number
): (boolean, { VaultEvent })
	local events: { VaultEvent } = {}
	if run.phase ~= "Active" or run.carrierUserId ~= userId or not isFiniteVec3(dropPos) then
		return false, events
	end
	local eggId = run.carryingEggId
	run.carrierUserId = nil
	run.droppedEggPos = v3(dropPos.x, dropPos.y, dropPos.z)
	if run.boss.state == "PATROL" then
		run.boss.state = "INVESTIGATE"
		run.boss.targetPos = v3(dropPos.x, dropPos.y, dropPos.z)
		run.boss.targetUserId = nil
		run.boss.investigateStartedAt = now
	end
	table.insert(events, {
		kind = "EggDropped",
		payload = { userId = userId, eggId = eggId, pos = dropPos },
	})
	return true, events
end

function VaultHeistLogic.validateOrbThrow(
	run: VaultRunState,
	userId: number,
	orbId: string,
	origin: Vec3,
	dir: Vec3,
	now: number
): (boolean, string?, VaultHeistConfigs.OrbStats?)
	if run.phase ~= "Active" then
		return false, "RunNotActive", nil
	end
	local ps = run.players[userId]
	if not ps or ps.downed then
		return false, "PlayerUnavailable", nil
	end
	if type(orbId) ~= "string" or not MathUtil.isFinite(now) then
		return false, "InvalidArgs", nil
	end
	if not isFiniteVec3(origin) or not isFiniteVec3(dir) then
		return false, "NonFiniteVector", nil
	end
	local mag = math.sqrt(dir.x * dir.x + dir.y * dir.y + dir.z * dir.z)
	if mag < 1e-4 then
		return false, "ZeroDirection", nil
	end
	local lv = ps.orbLevels[orbId] or 0
	local stats = VaultHeistConfigs.getOrbStats(orbId, lv)
	if not stats or lv < 1 then
		return false, "OrbLocked", nil
	end
	local readyAt = ps.orbCooldowns[orbId] or 0
	if now < readyAt then
		return false, "OnCooldown", stats
	end
	return true, nil, stats
end

local function applyDecoyOrb(
	run: VaultRunState,
	userId: number,
	impactPos: Vec3,
	stats: VaultHeistConfigs.OrbStats,
	now: number,
	events: { VaultEvent }
)
	run.nextDecoySeq += 1
	local decoy: DecoyEntity = {
		id = `decoy_{run.nextDecoySeq}`,
		ownerUserId = userId,
		pos = v3(impactPos.x, impactPos.y, impactPos.z),
		expiresAt = now + stats.duration,
		radius = stats.radius,
	}
	table.insert(run.decoys, decoy)
	if run.boss.state ~= "STUNNED" and dist3D(run.boss.pos, impactPos) <= stats.radius then
		run.boss.state = "INVESTIGATE"
		run.boss.decoyId = decoy.id
		run.boss.targetUserId = nil
		run.boss.targetPos = v3(impactPos.x, impactPos.y, impactPos.z)
		run.boss.investigateStartedAt = now
	end
	table.insert(events, {
		kind = "DecoySpawned",
		payload = { decoy = decoy, userId = userId },
	})
end

local function applyFreezeOrb(
	run: VaultRunState,
	userId: number,
	impactPos: Vec3,
	stats: VaultHeistConfigs.OrbStats,
	now: number,
	events: { VaultEvent }
)
	run.laserPausedUntil = math.max(run.laserPausedUntil, now + stats.laserPauseSec)
	local bossDist = dist3D(run.boss.pos, impactPos)
	local hitBoss = bossDist <= stats.radius
	if hitBoss then
		run.boss.state = "STUNNED"
		run.boss.stunEndsAt = math.max(run.boss.stunEndsAt, now + stats.duration)
		run.boss.stateEndsAt = run.boss.stunEndsAt
		run.boss.telegraphOrigin = nil
		run.boss.telegraphDir = nil
		run.boss.hp = math.max(0, run.boss.hp - stats.bossDamage)
	end
	table.insert(events, {
		kind = "FreezeBurst",
		payload = {
			userId = userId,
			pos = impactPos,
			radius = stats.radius,
			hitBoss = hitBoss,
			stunDuration = stats.duration,
			laserPausedUntil = run.laserPausedUntil,
			damage = if hitBoss then stats.bossDamage else 0,
		},
	})
end

local function applyDashBombOrb(
	run: VaultRunState,
	userId: number,
	ps: VaultPlayerState,
	impactPos: Vec3,
	dir: Vec3,
	stats: VaultHeistConfigs.OrbStats,
	now: number,
	chamberCenter: Vec3?,
	halfExtent: number?,
	events: { VaultEvent }
)
	ps.carrySlowImmuneUntil = math.max(ps.carrySlowImmuneUntil, now + stats.carrySlowImmunitySec)
	local fDir, _ = flatDir(v3(0, 0, 0), v3(dir.x, 0, dir.z))
	table.insert(events, {
		kind = "DashImpulse",
		payload = {
			userId = userId,
			dir = fDir,
			distance = stats.dashImpulse,
			immunitySec = stats.carrySlowImmunitySec,
		},
	})
	local dBoss = dist3D(run.boss.pos, impactPos)
	if dBoss <= stats.radius then
		local kbDir = flatDir(impactPos, run.boss.pos)
		local pushed = v3(
			run.boss.pos.x + kbDir.x * stats.bossKnockback,
			run.boss.pos.y,
			run.boss.pos.z + kbDir.z * stats.bossKnockback
		)
		run.boss.pos = clampToExtent(pushed, chamberCenter, halfExtent)
		run.boss.hp = math.max(0, run.boss.hp - stats.bossDamage)
		if run.boss.state == "TELEGRAPH" or run.boss.state == "LUNGE" then
			run.boss.state = "PATROL"
			run.boss.lungeCooldownUntil = now + 1.4
		end
		table.insert(events, {
			kind = "BossKnockedBack",
			payload = {
				userId = userId,
				pos = run.boss.pos,
				damage = stats.bossDamage,
			},
		})
	end
end

function VaultHeistLogic.executeOrbAction(
	run: VaultRunState,
	userId: number,
	orbId: string,
	origin: Vec3,
	dir: Vec3,
	impactPos: Vec3,
	now: number,
	chamberCenter: Vec3?,
	halfExtent: number?
): (boolean, string?, { VaultEvent })
	local events: { VaultEvent } = {}
	local ok, reason, stats = VaultHeistLogic.validateOrbThrow(run, userId, orbId, origin, dir, now)
	if not ok or not stats then
		return false, reason, events
	end
	local ps = run.players[userId]
	if not ps or not isFiniteVec3(impactPos) then
		return false, "InvalidImpact", events
	end
	ps.orbCooldowns[orbId] = now + stats.cooldown
	if orbId == "Decoy" then
		applyDecoyOrb(run, userId, impactPos, stats, now, events)
	elseif orbId == "Freeze" then
		applyFreezeOrb(run, userId, impactPos, stats, now, events)
	elseif orbId == "DashBomb" then
		applyDashBombOrb(
			run,
			userId,
			ps,
			impactPos,
			dir,
			stats,
			now,
			chamberCenter,
			halfExtent,
			events
		)
	end
	return true, nil, events
end

local function downPlayerAndCheckWipe(
	run: VaultRunState,
	ps: VaultPlayerState,
	userId: number,
	now: number,
	sourcePos: Vec3?,
	events: { VaultEvent }
)
	ps.downed = true
	ps.downedAt = now
	ps.reviveProgress = 0
	if run.carrierUserId == userId and sourcePos then
		local _, dropEv = VaultHeistLogic.dropEgg(run, userId, sourcePos, now)
		for _, ev in ipairs(dropEv) do
			table.insert(events, ev)
		end
	end
	table.insert(events, { kind = "PlayerDowned", payload = { userId = userId } })
	if countLivingPlayers(run) == 0 then
		run.phase = "Finished"
		table.insert(events, {
			kind = "SquadWiped",
			payload = { chamber = run.chamber, lostEggs = #run.runBagEggs },
		})
	end
end

function VaultHeistLogic.applyDamageToPlayer(
	run: VaultRunState,
	userId: number,
	damage: number,
	now: number,
	sourcePos: Vec3?
): { VaultEvent }
	local events: { VaultEvent } = {}
	local ps = run.players[userId]
	if run.phase ~= "Active" or not ps or ps.downed then
		return events
	end
	if
		not MathUtil.isPositiveFinite(damage)
		or not MathUtil.isFinite(now)
		or now < ps.invulnUntil
	then
		return events
	end
	ps.hp = math.max(0, ps.hp - math.floor(damage + 0.5))
	table.insert(events, {
		kind = "PlayerDamaged",
		payload = { userId = userId, damage = damage, hp = ps.hp, pos = sourcePos },
	})
	if ps.hp > 0 then
		return events
	end
	if run.totalRunPlayers == 1 and not ps.soloReviveUsed then
		ps.soloReviveUsed = true
		ps.hp = math.max(1, math.floor(ps.maxHP * 0.65))
		ps.invulnUntil = now + 2.5
		table.insert(events, {
			kind = "SoloDroneRevive",
			payload = { userId = userId, hp = ps.hp },
		})
		return events
	end
	downPlayerAndCheckWipe(run, ps, userId, now, sourcePos, events)
	return events
end

function VaultHeistLogic.onTouchLaserGate(
	run: VaultRunState,
	userId: number,
	now: number,
	playerPos: Vec3
): { VaultEvent }
	if run.phase ~= "Active" or not MathUtil.isFinite(now) or now < run.laserPausedUntil then
		return {}
	end
	local ps = run.players[userId]
	if not ps or ps.downed or now < ps.invulnUntil then
		return {}
	end
	local events = VaultHeistLogic.applyDamageToPlayer(
		run,
		userId,
		VaultHeistConfigs.LASER_DAMAGE,
		now,
		playerPos
	)
	if run.carrierUserId == userId then
		local _, dropEv = VaultHeistLogic.dropEgg(run, userId, playerPos, now)
		for _, ev in ipairs(dropEv) do
			table.insert(events, ev)
		end
	end
	ps.invulnUntil = math.max(ps.invulnUntil, now + 0.85)
	table.insert(events, { kind = "LaserHit", payload = { userId = userId, pos = playerPos } })
	return events
end

local function resolveActiveDecoy(run: VaultRunState, decoyId: string?): DecoyEntity?
	if not decoyId then
		return nil
	end
	for _, d in ipairs(run.decoys) do
		if d.id == decoyId then
			return d
		end
	end
	return nil
end

local function findNearestDecoyInRange(run: VaultRunState): DecoyEntity?
	local best: DecoyEntity? = nil
	local bestDist = math.huge
	for _, d in ipairs(run.decoys) do
		local dist = dist3D(run.boss.pos, d.pos)
		if dist <= d.radius and dist < bestDist then
			bestDist = dist
			best = d
		end
	end
	return best
end

local function isPlayerVisibleToBoss(
	boss: VaultBossState,
	pPos: Vec3,
	range: number,
	halfAngleDeg: number,
	isCarrier: boolean
): (boolean, number)
	local dir, dist = flatDir(boss.pos, pPos)
	local effectiveRange = if isCarrier then range * 1.35 else range
	if dist > effectiveRange then
		return false, dist
	end
	if dist <= 14 or isCarrier then
		return true, dist
	end
	local fwdX = -math.sin(boss.facingYaw)
	local fwdZ = -math.cos(boss.facingYaw)
	local dot = math.clamp(fwdX * dir.x + fwdZ * dir.z, -1, 1)
	local angleDeg = math.deg(math.acos(dot))
	return angleDeg <= halfAngleDeg, dist
end

local function findVisiblePlayer(
	run: VaultRunState,
	playerPositions: { [number]: Vec3 }
): (number?, Vec3?, number)
	local ch = VaultHeistConfigs.getChamber(run.chamber)
	local coneScale = if run.totalRunPlayers == 1
		then VaultHeistConfigs.SOLO_SIGHT_CONE_SCALE
		else 1.0
	local halfAngle = ch.sightHalfAngleDeg * coneScale
	local bestUid: number? = nil
	local bestPos: Vec3? = nil
	local bestDist = math.huge
	for _, uid in ipairs(run.playerOrder) do
		local ps = run.players[uid]
		local pPos = playerPositions[uid]
		if ps and not ps.downed and pPos and isFiniteVec3(pPos) then
			local visible, d = isPlayerVisibleToBoss(
				run.boss,
				pPos,
				ch.sightRange,
				halfAngle,
				run.carrierUserId == uid
			)
			if visible and d < bestDist then
				bestDist = d
				bestUid = uid
				bestPos = pPos
			end
		end
	end
	return bestUid, bestPos, bestDist
end

local function moveBossToward(boss: VaultBossState, target: Vec3, speed: number, dt: number): number
	local dir, dist = flatDir(boss.pos, target)
	if dist <= 0.1 then
		return dist
	end
	boss.facingYaw = yawFromDir(dir)
	local step = math.min(dist, speed * dt)
	boss.pos = v3(boss.pos.x + dir.x * step, boss.pos.y, boss.pos.z + dir.z * step)
	return dist - step
end

local function startTelegraph(
	run: VaultRunState,
	targetPos: Vec3,
	now: number,
	events: { VaultEvent }
)
	local ch = VaultHeistConfigs.getChamber(run.chamber)
	local dir, _ = flatDir(run.boss.pos, targetPos)
	run.boss.state = "TELEGRAPH"
	run.boss.facingYaw = yawFromDir(dir)
	run.boss.telegraphOrigin = v3(run.boss.pos.x, run.boss.pos.y, run.boss.pos.z)
	run.boss.telegraphDir = dir
	run.boss.stateStartedAt = now
	run.boss.stateEndsAt = now + ch.telegraphSec
	run.boss.lungeHitUsers = {}
	table.insert(events, {
		kind = "BossTelegraph",
		payload = {
			origin = run.boss.telegraphOrigin,
			dir = dir,
			duration = ch.telegraphSec,
			range = ch.lungeSpeed * 0.42,
			radius = ch.lungeRadius,
		},
	})
end

local function stepBossPatrol(
	run: VaultRunState,
	dt: number,
	now: number,
	patrolNodes: { Vec3 },
	playerPositions: { [number]: Vec3 },
	events: { VaultEvent }
)
	local decoy = findNearestDecoyInRange(run)
	if decoy then
		run.boss.state = "INVESTIGATE"
		run.boss.decoyId = decoy.id
		run.boss.targetUserId = nil
		run.boss.targetPos = decoy.pos
		run.boss.investigateStartedAt = now
		return
	end
	local uid, pPos, dist = findVisiblePlayer(run, playerPositions)
	if uid and pPos then
		if dist <= 20 and now >= run.boss.lungeCooldownUntil then
			startTelegraph(run, pPos, now, events)
		else
			run.boss.state = "INVESTIGATE"
			run.boss.targetUserId = uid
			run.boss.decoyId = nil
			run.boss.targetPos = pPos
			run.boss.investigateStartedAt = now
		end
		return
	end
	if #patrolNodes == 0 then
		return
	end
	local ch = VaultHeistConfigs.getChamber(run.chamber)
	local spd = VaultHeistConfigs.scaleBossSpeed(ch.patrolSpeed, run.totalRunPlayers)
	local node = patrolNodes[((run.boss.patrolIndex - 1) % #patrolNodes) + 1]
	if moveBossToward(run.boss, node, spd, dt) <= 3.5 then
		run.boss.patrolIndex = (run.boss.patrolIndex % #patrolNodes) + 1
	end
end

local function stepBossInvestigate(
	run: VaultRunState,
	dt: number,
	now: number,
	playerPositions: { [number]: Vec3 },
	events: { VaultEvent }
)
	local ch = VaultHeistConfigs.getChamber(run.chamber)
	local spd = VaultHeistConfigs.scaleBossSpeed(ch.chaseSpeed, run.totalRunPlayers)
	local decoy = resolveActiveDecoy(run, run.boss.decoyId) or findNearestDecoyInRange(run)
	if decoy then
		run.boss.decoyId = decoy.id
		run.boss.targetPos = decoy.pos
		moveBossToward(run.boss, decoy.pos, spd, dt)
		return
	end
	run.boss.decoyId = nil
	local targetUid = run.boss.targetUserId
	local targetPos = if targetUid then playerPositions[targetUid] else nil
	local ps = if targetUid then run.players[targetUid] else nil
	if not targetPos or not ps or ps.downed then
		local visUid, visPos = findVisiblePlayer(run, playerPositions)
		targetUid, targetPos = visUid, visPos
		run.boss.targetUserId = visUid
	end
	if targetPos and isFiniteVec3(targetPos) then
		run.boss.targetPos = targetPos
		local rem = moveBossToward(run.boss, targetPos, spd, dt)
		if rem <= 22 and now >= run.boss.lungeCooldownUntil then
			startTelegraph(run, targetPos, now, events)
		end
		return
	end
	if (now - run.boss.investigateStartedAt) >= 3.5 then
		run.boss.state = "PATROL"
	end
end

local function stepBossTelegraph(run: VaultRunState, now: number, events: { VaultEvent })
	local decoy = findNearestDecoyInRange(run)
	if decoy then
		run.boss.state = "INVESTIGATE"
		run.boss.decoyId = decoy.id
		run.boss.targetUserId = nil
		run.boss.targetPos = decoy.pos
		run.boss.telegraphOrigin = nil
		run.boss.telegraphDir = nil
		return
	end
	if now >= run.boss.stateEndsAt then
		run.boss.state = "LUNGE"
		run.boss.stateStartedAt = now
		run.boss.stateEndsAt = now + 0.42
		table.insert(events, { kind = "BossLunge", payload = { origin = run.boss.pos } })
	end
end

local function stepBossLunge(
	run: VaultRunState,
	dt: number,
	now: number,
	playerPositions: { [number]: Vec3 },
	chamberCenter: Vec3?,
	halfExtent: number?,
	events: { VaultEvent }
)
	local ch = VaultHeistConfigs.getChamber(run.chamber)
	local dir = run.boss.telegraphDir or v3(0, 0, -1)
	local nextPos = v3(
		run.boss.pos.x + dir.x * ch.lungeSpeed * dt,
		run.boss.pos.y,
		run.boss.pos.z + dir.z * ch.lungeSpeed * dt
	)
	run.boss.pos = clampToExtent(nextPos, chamberCenter, halfExtent)
	for _, uid in ipairs(run.playerOrder) do
		local pPos = playerPositions[uid]
		if pPos and isFiniteVec3(pPos) and not run.boss.lungeHitUsers[uid] then
			if flatDist(run.boss.pos, pPos) <= ch.lungeRadius then
				run.boss.lungeHitUsers[uid] = true
				for _, ev in
					ipairs(VaultHeistLogic.applyDamageToPlayer(run, uid, ch.lungeDamage, now, pPos))
				do
					table.insert(events, ev)
				end
			end
		end
	end
	if now >= run.boss.stateEndsAt then
		run.boss.state = "PATROL"
		run.boss.lungeCooldownUntil = now + 1.8
		run.boss.telegraphOrigin = nil
		run.boss.telegraphDir = nil
	end
end

local function stepDownedAndRevives(
	run: VaultRunState,
	dt: number,
	now: number,
	playerPositions: { [number]: Vec3 },
	events: { VaultEvent }
)
	for _, uid in ipairs(run.playerOrder) do
		local ps = run.players[uid]
		local dPos = playerPositions[uid]
		if ps and ps.downed and dPos then
			local reviverNear = false
			for _, otherUid in ipairs(run.playerOrder) do
				local otherPs = run.players[otherUid]
				local oPos = playerPositions[otherUid]
				if otherUid ~= uid and otherPs and not otherPs.downed and oPos then
					if dist3D(dPos, oPos) <= VaultHeistConfigs.REVIVE_RADIUS then
						reviverNear = true
						break
					end
				end
			end
			if reviverNear then
				ps.reviveProgress += dt / VaultHeistConfigs.REVIVE_HOLD_SEC
				if ps.reviveProgress >= 1 then
					ps.downed = false
					ps.reviveProgress = 0
					ps.hp = math.max(1, math.floor(ps.maxHP * 0.5))
					ps.invulnUntil = now + 1.5
					table.insert(events, { kind = "PlayerRevived", payload = { userId = uid } })
				end
			else
				ps.reviveProgress = math.max(0, ps.reviveProgress - dt * 0.25)
			end
		end
	end
end

local function pruneExpiredDecoys(run: VaultRunState, now: number)
	local kept: { DecoyEntity } = {}
	for _, d in ipairs(run.decoys) do
		if now < d.expiresAt then
			table.insert(kept, d)
		elseif run.boss.decoyId == d.id then
			run.boss.decoyId = nil
		end
	end
	run.decoys = kept
end

local function computeChamberPayout(run: VaultRunState): {
	eggs: { string },
	coins: number,
	gems: number,
	exp: number,
}
	local ch = VaultHeistConfigs.getChamber(run.chamber)
	local eggs: { string } = {}
	for _, eggId in ipairs(run.runBagEggs) do
		table.insert(eggs, eggId)
	end
	if run.carryingEggId then
		table.insert(eggs, run.carryingEggId)
	end
	local mult = run.streakMult
	return {
		eggs = eggs,
		coins = math.floor(ch.coinReward * mult + 0.5),
		gems = math.max(1, math.floor(ch.gemReward * mult + 0.5)),
		exp = math.floor(ch.expReward * mult + 0.5),
	}
end

local function advanceToNextChamber(
	run: VaultRunState,
	now: number,
	bossSpawnPos: Vec3?,
	nextMutatorRoll: number?,
	events: { VaultEvent }
)
	if run.carryingEggId then
		table.insert(run.runBagEggs, run.carryingEggId)
	end
	run.chamber += 1
	run.mutatorId =
		VaultHeistLogic.pickChamberMutator(run.chamber, run.isHourlyStorm, nextMutatorRoll or 0.35)
	local ch = VaultHeistConfigs.getChamber(run.chamber)
	run.phase = "Active"
	run.voteEndsAt = nil
	run.carrierUserId = nil
	run.carryingEggId = nil
	run.droppedEggPos = nil
	run.eggPedestalAvailable = true
	run.alarmTriggered = false
	run.chamberEndsAt = now + ch.chamberDurationSec
	run.streakMult =
		VaultHeistLogic.computeStreakMult(run.chamber, run.mutatorId, run.isHourlyStorm)
	run.boss = createBossState(run.chamber, run.totalRunPlayers, bossSpawnPos or run.boss.pos, now)
	for _, uid in ipairs(run.playerOrder) do
		run.players[uid].voteChoice = nil
	end
	table.insert(events, {
		kind = "ChamberAdvanced",
		payload = {
			chamber = run.chamber,
			mutatorId = run.mutatorId,
			streakMult = run.streakMult,
			bagCount = #run.runBagEggs,
		},
	})
end

local function resolveVoteResult(
	run: VaultRunState,
	now: number,
	bossSpawnPos: Vec3?,
	nextMutatorRoll: number?
): { VaultEvent }
	if run.votePayoutDone then
		return {}
	end
	local events: { VaultEvent } = {}
	local extractVotes = 0
	local diveVotes = 0
	for _, uid in ipairs(run.playerOrder) do
		local ps = run.players[uid]
		if ps and not ps.downed then
			if ps.voteChoice == "Dive" then
				diveVotes += 1
			else
				extractVotes += 1
			end
		end
	end
	if diveVotes > extractVotes and run.chamber < VaultHeistConfigs.MAX_CHAMBER then
		advanceToNextChamber(run, now, bossSpawnPos, nextMutatorRoll, events)
		return events
	end
	run.votePayoutDone = true
	run.phase = "Finished"
	local payout = computeChamberPayout(run)
	table.insert(events, {
		kind = "HeistExtracted",
		payload = {
			chamberCleared = run.chamber,
			eggs = payout.eggs,
			coins = payout.coins,
			gems = payout.gems,
			exp = payout.exp,
			streakMult = run.streakMult,
		},
	})
	return events
end

function VaultHeistLogic.removePlayerFromRun(
	run: VaultRunState,
	userId: number,
	dropPos: Vec3?,
	now: number
): { VaultEvent }
	local events: { VaultEvent } = {}
	if not run.players[userId] then
		return events
	end
	if run.carrierUserId == userId and dropPos then
		local _, dropEv = VaultHeistLogic.dropEgg(run, userId, dropPos, now)
		for _, ev in ipairs(dropEv) do
			table.insert(events, ev)
		end
	elseif run.carrierUserId == userId then
		run.carrierUserId = nil
		run.eggPedestalAvailable = true
	end
	run.players[userId] = nil
	for idx, uid in ipairs(run.playerOrder) do
		if uid == userId then
			table.remove(run.playerOrder, idx)
			break
		end
	end
	if #run.playerOrder == 0 then
		run.phase = "Finished"
		table.insert(events, {
			kind = "SquadWiped",
			payload = { chamber = run.chamber, reason = "Abandoned", lostEggs = #run.runBagEggs },
		})
	elseif run.phase == "Active" and countLivingPlayers(run) == 0 then
		run.phase = "Finished"
		table.insert(events, {
			kind = "SquadWiped",
			payload = {
				chamber = run.chamber,
				reason = "RemainingDowned",
				lostEggs = #run.runBagEggs,
			},
		})
	end
	return events
end

function VaultHeistLogic.triggerExtractionVote(
	run: VaultRunState,
	userId: number,
	now: number
): (boolean, { VaultEvent })
	local events: { VaultEvent } = {}
	if run.phase ~= "Active" or run.carrierUserId ~= userId or not MathUtil.isFinite(now) then
		return false, events
	end
	run.phase = "Vote"
	run.voteEndsAt = now + VaultHeistConfigs.EXTRACTION_VOTE_SEC
	for _, uid in ipairs(run.playerOrder) do
		run.players[uid].voteChoice = nil
	end
	table.insert(events, {
		kind = "VoteStarted",
		payload = {
			chamber = run.chamber,
			voteEndsAt = run.voteEndsAt,
			canDive = run.chamber < VaultHeistConfigs.MAX_CHAMBER,
		},
	})
	return true, events
end

function VaultHeistLogic.castExtractionVote(
	run: VaultRunState,
	userId: number,
	choice: "Extract" | "Dive",
	now: number,
	bossSpawnPos: Vec3?,
	nextMutatorRoll: number?
): (boolean, { VaultEvent })
	local ps = run.players[userId]
	if run.phase ~= "Vote" or not ps or ps.downed or not MathUtil.isFinite(now) then
		return false, {}
	end
	local finalChoice: "Extract" | "Dive" = if choice == "Dive"
			and run.chamber < VaultHeistConfigs.MAX_CHAMBER
		then "Dive"
		else "Extract"
	ps.voteChoice = finalChoice
	local allVoted = true
	for _, uid in ipairs(run.playerOrder) do
		local member = run.players[uid]
		if member and not member.downed and member.voteChoice == nil then
			allVoted = false
			break
		end
	end
	if allVoted then
		return true, resolveVoteResult(run, now, bossSpawnPos, nextMutatorRoll)
	end
	return true, {}
end

local function stepBossState(
	run: VaultRunState,
	dt: number,
	now: number,
	patrolNodes: { Vec3 },
	playerPositions: { [number]: Vec3 },
	chamberCenter: Vec3?,
	halfExtent: number?,
	events: { VaultEvent }
)
	local state = run.boss.state
	if state == "STUNNED" then
		if now >= run.boss.stunEndsAt then
			run.boss.state = "PATROL"
		end
	elseif state == "PATROL" then
		stepBossPatrol(run, dt, now, patrolNodes, playerPositions, events)
	elseif state == "INVESTIGATE" then
		stepBossInvestigate(run, dt, now, playerPositions, events)
	elseif state == "TELEGRAPH" then
		stepBossTelegraph(run, now, events)
	elseif state == "LUNGE" then
		stepBossLunge(run, dt, now, playerPositions, chamberCenter, halfExtent, events)
	end
end

function VaultHeistLogic.stepRun(
	run: VaultRunState,
	dt: number,
	now: number,
	patrolNodes: { Vec3 },
	playerPositions: { [number]: Vec3 },
	chamberCenter: Vec3?,
	halfExtent: number?,
	bossSpawnPos: Vec3?,
	nextMutatorRoll: number?
): { VaultEvent }
	local events: { VaultEvent } = {}
	if run.phase == "Finished" or not MathUtil.isFinite(dt) or not MathUtil.isFinite(now) then
		return events
	end
	pruneExpiredDecoys(run, now)
	if run.phase == "Vote" then
		if run.voteEndsAt and now >= run.voteEndsAt then
			return resolveVoteResult(run, now, bossSpawnPos, nextMutatorRoll)
		end
		return events
	end
	if now >= run.chamberEndsAt then
		run.phase = "Finished"
		table.insert(events, {
			kind = "SquadWiped",
			payload = {
				chamber = run.chamber,
				reason = "VaultCollapsed",
				lostEggs = #run.runBagEggs,
			},
		})
		return events
	end
	stepDownedAndRevives(run, dt, now, playerPositions, events)
	if run.phase == "Active" then
		stepBossState(run, dt, now, patrolNodes, playerPositions, chamberCenter, halfExtent, events)
	end
	return events
end

return VaultHeistLogic
