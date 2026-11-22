--!strict
--[[
	Pure 3-phase Biome Arena state machine (GDD §3). No Roblox APIs: the server passes
	time in as `now` (seconds) and executes the returned ArenaActions as side effects.
	PvE_Open -> OptIn_Window (15s) -> Boss_Phase (locked) -> PvP_EggScramble (locked) -> PvE_Open
]]

local ArenaStateMachine = {}

ArenaStateMachine.CONSTANTS = table.freeze({
	PVE_CYCLE_MIN_SECONDS = 90,
	PVE_CYCLE_MAX_SECONDS = 120,
	DEFAULT_PVE_DURATION_SECONDS = 90,
	OVERCHARGED_INTERVAL_SECONDS = 300,
	OPT_IN_WINDOW_SECONDS = 15,
	DEFAULT_BOSS_TIMEOUT_SECONDS = 180,
	PVP_GRACE_SECONDS = 3,
	EGG_CLAIM_DURATION_SECONDS = 5,
	DEFAULT_EGG_CLAIM_RADIUS_STUDS = 12,
	PVP_SUDDEN_DEATH_DELAY_SECONDS = 75,
	DEFAULT_STORM_INITIAL_RADIUS_STUDS = 80,
	DEFAULT_STORM_MIN_RADIUS_STUDS = 8,
	DEFAULT_STORM_SHRINK_DURATION_SECONDS = 45,
	DEFAULT_STORM_DAMAGE_PCT_PER_SEC = 0.08,
	BOSS_HP_SCALING_PER_EXTRA_PLAYER = 0.35,
	OVERCHARGED_BOSS_HP_MULTIPLIER = 1.40,
})
local C = ArenaStateMachine.CONSTANTS
local EPSILON = 1e-9 -- absorbs float drift in "exactly 5.0s held" comparisons

export type PlayerId = number
export type ArenaPhase = "PvE_Open" | "OptIn_Window" | "Boss_Phase" | "PvP_EggScramble"
export type EggRewardType = "StandardBossEgg" | "OverchargedBossEgg"

export type ArenaConfig = {
	biomeId: string,
	baseBossHp: number,
	pveDurationSeconds: number?,
	optInDurationSeconds: number?,
	bossTimeoutSeconds: number?,
	pvpGraceSeconds: number?,
	eggClaimDurationSeconds: number?,
	eggClaimRadiusStuds: number?,
	suddenDeathDelaySeconds: number?,
	stormInitialRadiusStuds: number?,
	stormMinRadiusStuds: number?,
	stormShrinkDurationSeconds: number?,
	stormDamagePctPerSec: number?,
}

export type ResolvedConfig = {
	biomeId: string,
	baseBossHp: number,
	pveDurationSeconds: number,
	optInDurationSeconds: number,
	bossTimeoutSeconds: number,
	pvpGraceSeconds: number,
	eggClaimDurationSeconds: number,
	eggClaimRadiusStuds: number,
	suddenDeathDelaySeconds: number,
	stormInitialRadiusStuds: number,
	stormMinRadiusStuds: number,
	stormShrinkDurationSeconds: number,
	stormDamagePctPerSec: number,
}

export type ClaimState = { playerId: PlayerId, startTime: number }

export type ArenaAction = {
	kind: string,
	biomeId: string,
	timestamp: number,
	phase: ArenaPhase?,
	previousPhase: ArenaPhase?,
	playerId: PlayerId?,
	playerIds: { PlayerId }?,
	reason: string?,
	bossMaxHp: number?,
	isOvercharged: boolean?,
	eggType: EggRewardType?,
	stormRadius: number?,
	damagePctPerSec: number?,
	dt: number?,
}

export type EventResult = { ok: boolean, reason: string?, actions: { ArenaAction } }

export type ArenaSnapshot = {
	biomeId: string,
	phase: ArenaPhase,
	isRoomLocked: boolean,
	isOvercharged: boolean,
	pvpEnabled: boolean,
	phaseStartTime: number,
	phaseEndTime: number?,
	pvpGraceEndTime: number?,
	suddenDeathStartTime: number?,
	stormActive: boolean,
	stormRadius: number,
	optInCount: number,
	aliveCount: number,
	activeClaimPlayerId: PlayerId?,
	claimProgress: number,
}

export type ArenaState = {
	config: ResolvedConfig,
	phase: ArenaPhase,
	phaseStartTime: number,
	phaseEndTime: number?,
	lastTickTime: number,
	isOvercharged: boolean,
	pendingOvercharged: boolean,
	optedIn: { [PlayerId]: boolean },
	participants: { [PlayerId]: boolean },
	alivePlayers: { [PlayerId]: boolean },
	pvpEnabled: boolean,
	pvpGraceEndTime: number?,
	suddenDeathStartTime: number?,
	stormActive: boolean,
	stormRadius: number,
	activeClaim: ClaimState?,
	eggSpawned: boolean,
	lastEliminationTime: number?,
	eliminatedAtLastTimeCount: number,
}

-- Helpers ---------------------------------------------------------------------------

local function ok(actions: { ArenaAction }?, reason: string?): EventResult
	return { ok = true, reason = reason, actions = actions or {} }
end

local function fail(reason: string): EventResult
	return { ok = false, reason = reason, actions = {} }
end

local function emit(
	state: ArenaState,
	actions: { ArenaAction },
	kind: string,
	now: number
): ArenaAction
	local action: ArenaAction = { kind = kind, biomeId = state.config.biomeId, timestamp = now }
	table.insert(actions, action)
	return action
end

local function setKeys(set: { [PlayerId]: boolean }): { PlayerId }
	local list = {}
	for playerId in set do
		table.insert(list, playerId)
	end
	table.sort(list)
	return list
end

local function countKeys(set: { [PlayerId]: boolean }): number
	local n = 0
	for _ in set do
		n += 1
	end
	return n
end

local function isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

local function resolveConfig(config: ArenaConfig): ResolvedConfig
	assert(type(config.biomeId) == "string" and config.biomeId ~= "", "biomeId required")
	assert(isFinite(config.baseBossHp) and config.baseBossHp > 0, "baseBossHp must be > 0")
	return {
		biomeId = config.biomeId,
		baseBossHp = config.baseBossHp,
		pveDurationSeconds = config.pveDurationSeconds or C.DEFAULT_PVE_DURATION_SECONDS,
		optInDurationSeconds = config.optInDurationSeconds or C.OPT_IN_WINDOW_SECONDS,
		bossTimeoutSeconds = config.bossTimeoutSeconds or C.DEFAULT_BOSS_TIMEOUT_SECONDS,
		pvpGraceSeconds = config.pvpGraceSeconds or C.PVP_GRACE_SECONDS,
		eggClaimDurationSeconds = config.eggClaimDurationSeconds or C.EGG_CLAIM_DURATION_SECONDS,
		eggClaimRadiusStuds = config.eggClaimRadiusStuds or C.DEFAULT_EGG_CLAIM_RADIUS_STUDS,
		suddenDeathDelaySeconds = config.suddenDeathDelaySeconds
			or C.PVP_SUDDEN_DEATH_DELAY_SECONDS,
		stormInitialRadiusStuds = config.stormInitialRadiusStuds
			or C.DEFAULT_STORM_INITIAL_RADIUS_STUDS,
		stormMinRadiusStuds = config.stormMinRadiusStuds or C.DEFAULT_STORM_MIN_RADIUS_STUDS,
		stormShrinkDurationSeconds = config.stormShrinkDurationSeconds
			or C.DEFAULT_STORM_SHRINK_DURATION_SECONDS,
		stormDamagePctPerSec = config.stormDamagePctPerSec or C.DEFAULT_STORM_DAMAGE_PCT_PER_SEC,
	}
end

-- Math --------------------------------------------------------------------------------

function ArenaStateMachine.computeBossMaxHp(
	baseBossHp: number,
	optInCount: number,
	isOvercharged: boolean
): number
	local scale = 1 + C.BOSS_HP_SCALING_PER_EXTRA_PLAYER * math.max(0, optInCount - 1)
	local overcharge = if isOvercharged then C.OVERCHARGED_BOSS_HP_MULTIPLIER else 1
	return math.floor(baseBossHp * scale * overcharge + 0.5)
end

function ArenaStateMachine.computeStormRadius(state: ArenaState, now: number): number
	local cfg = state.config
	local start = state.suddenDeathStartTime
	if not state.stormActive or start == nil then
		return cfg.stormInitialRadiusStuds
	end
	local alpha = math.clamp((now - start) / cfg.stormShrinkDurationSeconds, 0, 1)
	return cfg.stormInitialRadiusStuds
		+ (cfg.stormMinRadiusStuds - cfg.stormInitialRadiusStuds) * alpha
end

-- Construction & transitions --------------------------------------------------------

function ArenaStateMachine.new(config: ArenaConfig, startTime: number): ArenaState
	local cfg = resolveConfig(config)
	return {
		config = cfg,
		phase = "PvE_Open",
		phaseStartTime = startTime,
		phaseEndTime = startTime + cfg.pveDurationSeconds,
		lastTickTime = startTime,
		isOvercharged = false,
		pendingOvercharged = false,
		optedIn = {},
		participants = {},
		alivePlayers = {},
		pvpEnabled = false,
		pvpGraceEndTime = nil,
		suddenDeathStartTime = nil,
		stormActive = false,
		stormRadius = cfg.stormInitialRadiusStuds,
		activeClaim = nil,
		eggSpawned = false,
		lastEliminationTime = nil,
		eliminatedAtLastTimeCount = 0,
	}
end

local function changePhase(
	state: ArenaState,
	actions: { ArenaAction },
	nextPhase: ArenaPhase,
	now: number,
	reason: string?
)
	local action = emit(state, actions, "PhaseChanged", now)
	action.previousPhase = state.phase
	action.phase = nextPhase
	action.reason = reason
	action.isOvercharged = state.isOvercharged
	state.phase = nextPhase
	state.phaseStartTime = now
end

local function resetToPvE(state: ArenaState, actions: { ArenaAction }, now: number, reason: string)
	table.clear(state.optedIn)
	table.clear(state.participants)
	table.clear(state.alivePlayers)
	state.isOvercharged = false
	state.pvpEnabled = false
	state.pvpGraceEndTime = nil
	state.suddenDeathStartTime = nil
	state.stormActive = false
	state.stormRadius = state.config.stormInitialRadiusStuds
	state.activeClaim = nil
	state.eggSpawned = false
	state.lastEliminationTime = nil
	state.eliminatedAtLastTimeCount = 0
	changePhase(state, actions, "PvE_Open", now, reason)
	-- A queued 5-minute Overcharged event opens its window on the very next tick.
	state.phaseEndTime = if state.pendingOvercharged
		then now
		else now + state.config.pveDurationSeconds
end

local function enterOptIn(
	state: ArenaState,
	actions: { ArenaAction },
	now: number,
	overcharged: boolean
)
	table.clear(state.optedIn)
	state.isOvercharged = overcharged
	state.pendingOvercharged = false
	changePhase(state, actions, "OptIn_Window", now)
	state.phaseEndTime = now + state.config.optInDurationSeconds
end

local function enterBoss(state: ArenaState, actions: { ArenaAction }, now: number)
	local fighters = setKeys(state.optedIn)
	for _, playerId in fighters do
		state.participants[playerId] = true
		state.alivePlayers[playerId] = true
	end
	table.clear(state.optedIn)
	changePhase(state, actions, "Boss_Phase", now)
	state.phaseEndTime = now + state.config.bossTimeoutSeconds
	emit(state, actions, "TeleportToBossRoom", now).playerIds = fighters
	local spawn = emit(state, actions, "SpawnBoss", now)
	spawn.bossMaxHp =
		ArenaStateMachine.computeBossMaxHp(state.config.baseBossHp, #fighters, state.isOvercharged)
	spawn.isOvercharged = state.isOvercharged
end

local function dissolveEgg(state: ArenaState, actions: { ArenaAction }, now: number, reason: string)
	emit(state, actions, "DespawnEgg", now)
	emit(state, actions, "EggDissolved", now).reason = reason
	resetToPvE(state, actions, now, reason)
end

local function bossFailed(state: ArenaState, actions: { ArenaAction }, now: number, reason: string)
	emit(state, actions, "DespawnBoss", now)
	resetToPvE(state, actions, now, reason)
end

local function cancelClaimFor(
	state: ArenaState,
	actions: { ArenaAction },
	playerId: PlayerId,
	now: number,
	reason: string
)
	local claim = state.activeClaim
	if claim and claim.playerId == playerId then
		state.activeClaim = nil
		local action = emit(state, actions, "ClaimCancelled", now)
		action.playerId = playerId
		action.reason = reason
	end
end

local function completeClaim(
	state: ArenaState,
	actions: { ArenaAction },
	winner: PlayerId,
	now: number
)
	local claimed = emit(state, actions, "EggClaimed", now)
	claimed.playerId = winner
	claimed.eggType = if state.isOvercharged then "OverchargedBossEgg" else "StandardBossEgg"
	-- Eliminated fighters were already paid on elimination, so only surviving non-winners here.
	local others = {}
	for _, playerId in setKeys(state.alivePlayers) do
		if playerId ~= winner then
			table.insert(others, playerId)
		end
	end
	if #others > 0 then
		emit(state, actions, "AwardConsolation", now).playerIds = others
	end
	emit(state, actions, "DespawnEgg", now)
	emit(state, actions, "TeleportToPvELayer", now).playerIds = setKeys(state.alivePlayers)
	resetToPvE(state, actions, now, "EggClaimed")
end

-- Tick ----------------------------------------------------------------------------------

local function stepStorm(state: ArenaState, actions: { ArenaAction }, now: number, dt: number)
	local start = state.suddenDeathStartTime
	if start == nil or now < start then
		return
	end
	if not state.stormActive then
		state.stormActive = true
		emit(state, actions, "SuddenDeathStarted", now)
	end
	state.stormRadius = ArenaStateMachine.computeStormRadius(state, now)
	local stormTick = emit(state, actions, "StormTick", now)
	stormTick.stormRadius = state.stormRadius
	stormTick.damagePctPerSec = state.config.stormDamagePctPerSec
	stormTick.dt = dt
end

local function tickScramble(state: ArenaState, actions: { ArenaAction }, now: number, dt: number)
	if countKeys(state.alivePlayers) == 0 then
		dissolveEgg(state, actions, now, "NoSurvivors")
		return
	end
	local graceEnd = state.pvpGraceEndTime
	if not state.pvpEnabled and graceEnd and now >= graceEnd then
		state.pvpEnabled = true
		emit(state, actions, "PvPEnabled", now)
	end
	if not state.pvpEnabled then
		return
	end
	local claim = state.activeClaim
	if claim and now - claim.startTime + EPSILON >= state.config.eggClaimDurationSeconds then
		completeClaim(state, actions, claim.playerId, now)
		return
	end
	stepStorm(state, actions, now, dt)
end

local function tickPhase(state: ArenaState, actions: { ArenaAction }, now: number, dt: number)
	local deadline = state.phaseEndTime
	local expired = deadline ~= nil and now >= deadline
	if state.phase == "PvE_Open" and expired then
		enterOptIn(state, actions, now, state.pendingOvercharged)
	elseif state.phase == "OptIn_Window" and expired then
		if countKeys(state.optedIn) == 0 then
			resetToPvE(state, actions, now, "ZeroOptIns")
		else
			enterBoss(state, actions, now)
		end
	elseif state.phase == "Boss_Phase" and expired then
		emit(state, actions, "TeleportToPvELayer", now).playerIds = setKeys(state.alivePlayers)
		bossFailed(state, actions, now, "BossTimeout")
	elseif state.phase == "PvP_EggScramble" then
		tickScramble(state, actions, now, dt)
	end
end

function ArenaStateMachine.tick(state: ArenaState, now: number): EventResult
	if not isFinite(now) or now < state.lastTickTime then
		return fail("NonMonotonicTime")
	end
	local dt = now - state.lastTickTime
	state.lastTickTime = now
	local actions = {}
	tickPhase(state, actions, now, dt)
	return ok(actions)
end

-- Player & server events --------------------------------------------------------------

function ArenaStateMachine.triggerOvercharged(state: ArenaState, now: number): EventResult
	local actions = {}
	if state.phase == "PvE_Open" then
		enterOptIn(state, actions, now, true)
	elseif state.phase == "OptIn_Window" then
		state.isOvercharged = true
		emit(state, actions, "OptInUpdated", now).isOvercharged = true
	else
		state.pendingOvercharged = true -- never disrupt a locked room
	end
	return ok(actions)
end

function ArenaStateMachine.optIn(state: ArenaState, playerId: PlayerId, now: number): EventResult
	if state.phase ~= "OptIn_Window" then
		return fail("NotInOptInWindow")
	end
	if state.optedIn[playerId] then
		return ok() -- idempotent: remote spam can't inflate boss HP
	end
	state.optedIn[playerId] = true
	local actions = {}
	local action = emit(state, actions, "OptInUpdated", now)
	action.playerIds = setKeys(state.optedIn)
	action.isOvercharged = state.isOvercharged
	return ok(actions)
end

function ArenaStateMachine.optOut(state: ArenaState, playerId: PlayerId, now: number): EventResult
	if state.phase ~= "OptIn_Window" or not state.optedIn[playerId] then
		return fail("NotOptedIn")
	end
	state.optedIn[playerId] = nil
	local actions = {}
	local action = emit(state, actions, "OptInUpdated", now)
	action.playerIds = setKeys(state.optedIn)
	action.isOvercharged = state.isOvercharged
	return ok(actions)
end

function ArenaStateMachine.bossDefeated(state: ArenaState, now: number): EventResult
	if state.phase ~= "Boss_Phase" then
		return fail("NotInBossPhase")
	end
	local actions = {}
	if countKeys(state.alivePlayers) == 0 then
		bossFailed(state, actions, now, "NoSurvivors")
		return ok(actions)
	end
	local cfg = state.config
	state.eggSpawned = true
	state.pvpEnabled = false
	state.pvpGraceEndTime = now + cfg.pvpGraceSeconds
	state.suddenDeathStartTime = now + cfg.pvpGraceSeconds + cfg.suddenDeathDelaySeconds
	state.stormActive = false
	state.stormRadius = cfg.stormInitialRadiusStuds
	emit(state, actions, "DespawnBoss", now)
	emit(state, actions, "SpawnEgg", now)
	emit(state, actions, "FullHealPlayers", now).playerIds = setKeys(state.alivePlayers)
	changePhase(state, actions, "PvP_EggScramble", now)
	state.phaseEndTime = nil
	return ok(actions)
end

function ArenaStateMachine.startClaim(
	state: ArenaState,
	playerId: PlayerId,
	distanceFromEgg: number,
	now: number
): EventResult
	if state.phase ~= "PvP_EggScramble" or not state.eggSpawned then
		return fail("NotInPvPPhase")
	end
	local graceEnd = state.pvpGraceEndTime
	if graceEnd == nil or now < graceEnd then
		return fail("GracePeriodActive")
	end
	if not state.alivePlayers[playerId] then
		return fail("PlayerNotAliveInRoom")
	end
	if not isFinite(distanceFromEgg) or distanceFromEgg > state.config.eggClaimRadiusStuds then
		return fail("OutOfRadius")
	end
	local claim = state.activeClaim
	if claim then
		if claim.playerId == playerId then
			return ok(nil, "AlreadyClaiming")
		end
		return fail("AlreadyClaimedByOther")
	end
	state.activeClaim = { playerId = playerId, startTime = now }
	local actions = {}
	emit(state, actions, "ClaimStarted", now).playerId = playerId
	return ok(actions)
end

function ArenaStateMachine.cancelClaim(
	state: ArenaState,
	playerId: PlayerId,
	now: number
): EventResult
	local actions = {}
	cancelClaimFor(state, actions, playerId, now, "ManualCancel")
	return ok(actions)
end

function ArenaStateMachine.leaveRadius(
	state: ArenaState,
	playerId: PlayerId,
	now: number
): EventResult
	local actions = {}
	cancelClaimFor(state, actions, playerId, now, "LeftRadius")
	return ok(actions)
end

function ArenaStateMachine.canDealPvPDamage(
	state: ArenaState,
	attackerId: PlayerId,
	victimId: PlayerId,
	now: number
): boolean
	local graceEnd = state.pvpGraceEndTime
	return state.phase == "PvP_EggScramble"
		and graceEnd ~= nil
		and now >= graceEnd
		and attackerId ~= victimId
		and state.alivePlayers[attackerId] == true
		and state.alivePlayers[victimId] == true
end

function ArenaStateMachine.damage(
	state: ArenaState,
	victimId: PlayerId,
	amount: number,
	now: number,
	attackerId: PlayerId?
): EventResult
	if not isFinite(amount) or amount <= 0 then
		return fail("InvalidDamage")
	end
	if state.phase ~= "PvP_EggScramble" or not state.pvpEnabled then
		return fail("PvPNotActive")
	end
	if not state.alivePlayers[victimId] then
		return fail("VictimNotInRoom")
	end
	if
		attackerId ~= nil
		and not ArenaStateMachine.canDealPvPDamage(state, attackerId, victimId, now)
	then
		return fail("InvalidPvPAttacker")
	end
	local actions = {}
	cancelClaimFor(state, actions, victimId, now, "Damage")
	return ok(actions)
end

local function recordElimination(state: ArenaState, now: number)
	if state.lastEliminationTime == now then
		state.eliminatedAtLastTimeCount += 1
	else
		state.lastEliminationTime = now
		state.eliminatedAtLastTimeCount = 1
	end
end

function ArenaStateMachine.eliminate(
	state: ArenaState,
	playerId: PlayerId,
	now: number
): EventResult
	local inScramble = state.phase == "PvP_EggScramble"
	if not (inScramble or state.phase == "Boss_Phase") or not state.alivePlayers[playerId] then
		return fail("PlayerNotAliveInRoom")
	end
	local actions = {}
	cancelClaimFor(state, actions, playerId, now, "Eliminated")
	state.alivePlayers[playerId] = nil
	recordElimination(state, now)
	emit(state, actions, "TeleportToPvELayer", now).playerIds = { playerId }
	if inScramble then
		emit(state, actions, "AwardConsolation", now).playerIds = { playerId }
	end
	if countKeys(state.alivePlayers) == 0 then
		if not inScramble then
			bossFailed(state, actions, now, "AllEliminatedInBoss")
		elseif state.eliminatedAtLastTimeCount >= 2 then
			dissolveEgg(state, actions, now, "MutualElimination")
		else
			dissolveEgg(state, actions, now, "NoSurvivors")
		end
	end
	return ok(actions)
end

function ArenaStateMachine.disconnect(
	state: ArenaState,
	playerId: PlayerId,
	now: number
): EventResult
	local actions = {}
	if state.phase == "OptIn_Window" then
		if state.optedIn[playerId] then
			state.optedIn[playerId] = nil
			emit(state, actions, "OptInUpdated", now).playerIds = setKeys(state.optedIn)
		end
		return ok(actions)
	end
	if state.phase == "PvE_Open" or not state.participants[playerId] then
		return ok(actions)
	end
	cancelClaimFor(state, actions, playerId, now, "Disconnected")
	state.alivePlayers[playerId] = nil
	state.participants[playerId] = nil
	if countKeys(state.alivePlayers) == 0 then
		if state.phase == "Boss_Phase" then
			bossFailed(state, actions, now, "AllDisconnected")
		else
			dissolveEgg(state, actions, now, "AllDisconnected")
		end
	end
	return ok(actions)
end

-- Queries -------------------------------------------------------------------------------

function ArenaStateMachine.isRoomLocked(state: ArenaState): boolean
	return state.phase == "Boss_Phase" or state.phase == "PvP_EggScramble"
end

function ArenaStateMachine.getClaimProgress(state: ArenaState, now: number): number
	local claim = state.activeClaim
	if claim == nil then
		return 0
	end
	return math.clamp((now - claim.startTime) / state.config.eggClaimDurationSeconds, 0, 1)
end

function ArenaStateMachine.getSnapshot(state: ArenaState, now: number): ArenaSnapshot
	local claim = state.activeClaim
	return {
		biomeId = state.config.biomeId,
		phase = state.phase,
		isRoomLocked = ArenaStateMachine.isRoomLocked(state),
		isOvercharged = state.isOvercharged,
		pvpEnabled = state.pvpEnabled,
		phaseStartTime = state.phaseStartTime,
		phaseEndTime = state.phaseEndTime,
		pvpGraceEndTime = state.pvpGraceEndTime,
		suddenDeathStartTime = state.suddenDeathStartTime,
		stormActive = state.stormActive,
		stormRadius = state.stormRadius,
		optInCount = countKeys(state.optedIn),
		aliveCount = countKeys(state.alivePlayers),
		activeClaimPlayerId = if claim then claim.playerId else nil,
		claimProgress = ArenaStateMachine.getClaimProgress(state, now),
	}
end

return ArenaStateMachine
