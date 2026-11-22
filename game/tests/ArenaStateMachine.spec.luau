--!strict
local ArenaStateMachine = require("../src/shared/Utils/ArenaStateMachine")

type ArenaState = ArenaStateMachine.ArenaState
type ArenaAction = ArenaStateMachine.ArenaAction
type ArenaPhase = ArenaStateMachine.ArenaPhase
type EventResult = ArenaStateMachine.EventResult

local BIOME = "TrainingBiome"
local BASE_HP = 1000
local OPT_IN_START = 90
local BOSS_START = 105
local BOSS_DEFEAT = 110
local GRACE_END = 113
local STORM_START = 188

local function run(name: string, test: () -> ())
	local ok, failure = pcall(test)
	assert(ok, `{name}: {failure}`)
end

local function assertNear(actual: number, expected: number, label: string)
	assert(math.abs(actual - expected) <= 1e-6, `{label}: expected {expected}, got {actual}`)
end

local function accept(result: EventResult): EventResult
	assert(result.ok, `expected success, got {result.reason}`)
	return result
end

local function reject(result: EventResult, reason: string)
	assert(not result.ok, `expected rejection with {reason}`)
	assert(result.reason == reason, `expected {reason}, got {result.reason}`)
	assert(#result.actions == 0, "rejected events should emit no actions")
end

local function findAction(result: EventResult, kind: string): ArenaAction?
	for _, action in result.actions do
		if action.kind == kind then
			return action
		end
	end
	return nil
end

local function expectAction(result: EventResult, kind: string): ArenaAction
	local action = findAction(accept(result), kind)
	assert(action, `expected action {kind}`)
	assert(action.biomeId == BIOME, "action should identify the originating biome")
	return action
end

local function expectPlayers(action: ArenaAction, expected: { number })
	local actual = action.playerIds
	assert(actual and #actual == #expected, `unexpected player count for {action.kind}`)
	for _, playerId in expected do
		assert(table.find(actual, playerId), `{action.kind} should include player {playerId}`)
	end
end

local function expectPhaseChange(
	result: EventResult,
	previous: ArenaPhase,
	current: ArenaPhase,
	reason: string?
)
	local action = expectAction(result, "PhaseChanged")
	assert(action.previousPhase == previous, `expected previous phase {previous}`)
	assert(action.phase == current, `expected next phase {current}`)
	if reason then
		assert(
			action.reason == reason,
			`expected phase change reason {reason}, got {action.reason}`
		)
	end
end

local function expectClaimCleared(state: ArenaState, now: number)
	assert(state.activeClaim == nil)
	assert(ArenaStateMachine.getClaimProgress(state, now) == 0)
	local snapshot = ArenaStateMachine.getSnapshot(state, now)
	assert(snapshot.activeClaimPlayerId == nil and snapshot.claimProgress == 0)
end

local function expectClearRoom(state: ArenaState, now: number)
	local snapshot = ArenaStateMachine.getSnapshot(state, now)
	assert(not snapshot.isRoomLocked and not ArenaStateMachine.isRoomLocked(state))
	assert(snapshot.optInCount == 0 and snapshot.aliveCount == 0)
	assert(next(state.optedIn) == nil)
	assert(next(state.participants) == nil)
	assert(next(state.alivePlayers) == nil)
	assert(not snapshot.pvpEnabled and not snapshot.stormActive and not state.eggSpawned)
	assert(snapshot.pvpGraceEndTime == nil and snapshot.suddenDeathStartTime == nil)
	expectClaimCleared(state, now)
end

local function expectReset(state: ArenaState, now: number)
	expectClearRoom(state, now)
	local snapshot = ArenaStateMachine.getSnapshot(state, now)
	assert(snapshot.phase == "PvE_Open" and not snapshot.isOvercharged)
	assert(snapshot.phaseStartTime == now and snapshot.phaseEndTime == now + 90)
end

local function newArena(): ArenaState
	return ArenaStateMachine.new({ biomeId = BIOME, baseBossHp = BASE_HP }, 0)
end

local function optInWindow(): ArenaState
	local state = newArena()
	accept(ArenaStateMachine.tick(state, OPT_IN_START))
	assert(state.phase == "OptIn_Window")
	return state
end

local function queue(state: ArenaState, playerIds: { number }, now: number)
	for _, playerId in playerIds do
		accept(ArenaStateMachine.optIn(state, playerId, now))
	end
end

local function bossRoom(playerIds: { number }): ArenaState
	local state = optInWindow()
	queue(state, playerIds, OPT_IN_START)
	accept(ArenaStateMachine.tick(state, BOSS_START))
	assert(state.phase == "Boss_Phase")
	return state
end

local function scramble(playerIds: { number }): ArenaState
	local state = bossRoom(playerIds)
	accept(ArenaStateMachine.bossDefeated(state, BOSS_DEFEAT))
	assert(state.phase == "PvP_EggScramble")
	return state
end

local function liveScramble(playerIds: { number }): ArenaState
	local state = scramble(playerIds)
	expectAction(ArenaStateMachine.tick(state, GRACE_END), "PvPEnabled")
	return state
end

local function expectEgg(
	result: EventResult,
	playerId: number,
	eggType: ArenaStateMachine.EggRewardType
)
	local action = expectAction(result, "EggClaimed")
	assert(action.playerId == playerId and action.eggType == eggType)
end

local function expectDissolved(result: EventResult, reason: string)
	expectAction(result, "DespawnEgg")
	assert(expectAction(result, "EggDissolved").reason == reason)
	assert(findAction(result, "EggClaimed") == nil)
	expectPhaseChange(result, "PvP_EggScramble", "PvE_Open")
end

-- Plan cases 1, 2, and 3
run("Initial state, configured PvE duration, and exported constants", function()
	local state = ArenaStateMachine.new(
		{ biomeId = BIOME, baseBossHp = BASE_HP, pveDurationSeconds = 120 },
		10
	)
	local snapshot = ArenaStateMachine.getSnapshot(state, 10)
	assert(snapshot.biomeId == BIOME and snapshot.phase == "PvE_Open")
	assert(snapshot.phaseStartTime == 10 and snapshot.phaseEndTime == 130)
	assert(state.lastTickTime == 10)
	expectClearRoom(state, 10)
	assert(not snapshot.isOvercharged and not ArenaStateMachine.canDealPvPDamage(state, 1, 2, 10))
	assert(ArenaStateMachine.getSnapshot(newArena(), 0).phaseEndTime == 90)

	local constants = ArenaStateMachine.CONSTANTS
	assert(table.isfrozen(constants))
	assert(constants.PVE_CYCLE_MIN_SECONDS == 90)
	assert(constants.PVE_CYCLE_MAX_SECONDS == 120)
	assert(constants.DEFAULT_PVE_DURATION_SECONDS == 90)
	assert(constants.OVERCHARGED_INTERVAL_SECONDS == 300)
	assert(constants.OPT_IN_WINDOW_SECONDS == 15)
	assert(constants.DEFAULT_BOSS_TIMEOUT_SECONDS == 180)
	assert(constants.PVP_GRACE_SECONDS == 3)
	assert(constants.EGG_CLAIM_DURATION_SECONDS == 5)
	assert(constants.DEFAULT_EGG_CLAIM_RADIUS_STUDS == 12)
	assert(constants.PVP_SUDDEN_DEATH_DELAY_SECONDS == 75)
	assert(constants.DEFAULT_STORM_INITIAL_RADIUS_STUDS == 80)
	assert(constants.DEFAULT_STORM_MIN_RADIUS_STUDS == 8)
	assert(constants.DEFAULT_STORM_SHRINK_DURATION_SECONDS == 45)
	assertNear(constants.DEFAULT_STORM_DAMAGE_PCT_PER_SEC, 0.08, "storm damage constant")
	assertNear(constants.BOSS_HP_SCALING_PER_EXTRA_PLAYER, 0.35, "extra-player HP constant")
	assertNear(constants.OVERCHARGED_BOSS_HP_MULTIPLIER, 1.40, "Overcharged HP constant")
end)

run("Two players complete the full arena cycle and only the winner receives the egg", function()
	local state = newArena()
	assert(#accept(ArenaStateMachine.tick(state, 89.9)).actions == 0 and state.phase == "PvE_Open")
	expectPhaseChange(ArenaStateMachine.tick(state, OPT_IN_START), "PvE_Open", "OptIn_Window")
	assert(state.phaseEndTime == BOSS_START and not ArenaStateMachine.isRoomLocked(state))
	queue(state, { 1, 2 }, OPT_IN_START)
	assert(ArenaStateMachine.getSnapshot(state, OPT_IN_START).optInCount == 2)
	assert(
		#accept(ArenaStateMachine.tick(state, 104.9)).actions == 0 and state.phase == "OptIn_Window"
	)

	local boss = ArenaStateMachine.tick(state, BOSS_START)
	expectPhaseChange(boss, "OptIn_Window", "Boss_Phase")
	expectPlayers(expectAction(boss, "TeleportToBossRoom"), { 1, 2 })
	assertNear(assert(expectAction(boss, "SpawnBoss").bossMaxHp), 1350, "two-player boss HP")
	local snapshot = ArenaStateMachine.getSnapshot(state, BOSS_START)
	assert(snapshot.isRoomLocked and snapshot.aliveCount == 2 and snapshot.optInCount == 0)
	assert(state.participants[1] and state.participants[2])
	assert(snapshot.phaseEndTime == 285)

	local pvp = ArenaStateMachine.bossDefeated(state, BOSS_DEFEAT)
	expectPhaseChange(pvp, "Boss_Phase", "PvP_EggScramble")
	expectAction(pvp, "DespawnBoss")
	expectAction(pvp, "SpawnEgg")
	expectPlayers(expectAction(pvp, "FullHealPlayers"), { 1, 2 })
	snapshot = ArenaStateMachine.getSnapshot(state, BOSS_DEFEAT)
	assert(snapshot.isRoomLocked and state.eggSpawned and not snapshot.pvpEnabled)
	assert(snapshot.phaseEndTime == nil and snapshot.pvpGraceEndTime == GRACE_END)
	assert(snapshot.suddenDeathStartTime == STORM_START and not snapshot.stormActive)
	assert(snapshot.stormRadius == 80)

	expectAction(ArenaStateMachine.tick(state, GRACE_END), "PvPEnabled")
	assert(
		expectAction(ArenaStateMachine.startClaim(state, 1, 4, GRACE_END), "ClaimStarted").playerId
			== 1
	)
	local won = ArenaStateMachine.tick(state, 118)
	expectEgg(won, 1, "StandardBossEgg")
	expectPlayers(expectAction(won, "AwardConsolation"), { 2 })
	expectPlayers(expectAction(won, "TeleportToPvELayer"), { 1, 2 })
	expectAction(won, "DespawnEgg")
	expectPhaseChange(won, "PvP_EggScramble", "PvE_Open", "EggClaimed")
	expectReset(state, 118)
end)

run("A solo fighter faces base boss HP and claims an uncontested egg", function()
	local state = optInWindow()
	queue(state, { 1 }, OPT_IN_START)
	local boss = ArenaStateMachine.tick(state, BOSS_START)
	assert(expectAction(boss, "SpawnBoss").bossMaxHp == BASE_HP)
	local pvp = ArenaStateMachine.bossDefeated(state, BOSS_DEFEAT)
	expectPlayers(expectAction(pvp, "FullHealPlayers"), { 1 })
	assert(not state.pvpEnabled and state.pvpGraceEndTime == GRACE_END)
	expectAction(ArenaStateMachine.tick(state, GRACE_END), "PvPEnabled")
	accept(ArenaStateMachine.startClaim(state, 1, 4, GRACE_END))
	expectEgg(ArenaStateMachine.tick(state, 118), 1, "StandardBossEgg")
	expectReset(state, 118)
end)

-- Plan cases 4, 5, 6, and 7
run("An empty opt-in window closes without locking the room or spawning a boss", function()
	local state = optInWindow()
	assert(not ArenaStateMachine.isRoomLocked(state))
	local result = ArenaStateMachine.tick(state, BOSS_START)
	expectPhaseChange(result, "OptIn_Window", "PvE_Open", "ZeroOptIns")
	assert(
		findAction(result, "SpawnBoss") == nil and findAction(result, "TeleportToBossRoom") == nil
	)
	expectReset(state, BOSS_START)
end)

run("The only queued player's disconnect leaves zero opt-ins at the deadline", function()
	local state = optInWindow()
	queue(state, { 1 }, OPT_IN_START)
	expectAction(ArenaStateMachine.disconnect(state, 1, 100), "OptInUpdated")
	assert(ArenaStateMachine.getSnapshot(state, 100).optInCount == 0)
	local result = ArenaStateMachine.tick(state, BOSS_START)
	expectPhaseChange(result, "OptIn_Window", "PvE_Open", "ZeroOptIns")
	assert(findAction(result, "SpawnBoss") == nil)
	expectReset(state, BOSS_START)
end)

run("Duplicate opt-ins count once and never inflate boss HP", function()
	local state = optInWindow()
	expectAction(ArenaStateMachine.optIn(state, 1, 91), "OptInUpdated")
	assert(#accept(ArenaStateMachine.optIn(state, 1, 92)).actions == 0)
	assert(ArenaStateMachine.getSnapshot(state, 92).optInCount == 1)
	assert(
		expectAction(ArenaStateMachine.tick(state, BOSS_START), "SpawnBoss").bossMaxHp == BASE_HP
	)
end)

run("Opting out removes the queued player before the room locks", function()
	local state = optInWindow()
	queue(state, { 1, 2 }, OPT_IN_START)
	expectAction(ArenaStateMachine.optOut(state, 1, 100), "OptInUpdated")
	assert(ArenaStateMachine.getSnapshot(state, 100).optInCount == 1)
	local result = ArenaStateMachine.tick(state, BOSS_START)
	expectPlayers(expectAction(result, "TeleportToBossRoom"), { 2 })
	assert(expectAction(result, "SpawnBoss").bossMaxHp == BASE_HP)
end)

run("Opt-in outside the window never admits a bystander", function()
	local state = newArena()
	reject(ArenaStateMachine.optIn(state, 3, 0), "NotInOptInWindow")
	assert(ArenaStateMachine.getSnapshot(state, 0).optInCount == 0)

	state = bossRoom({ 1, 2 })
	reject(ArenaStateMachine.optIn(state, 3, BOSS_START), "NotInOptInWindow")
	assert(ArenaStateMachine.getSnapshot(state, BOSS_START).aliveCount == 2)
	accept(ArenaStateMachine.bossDefeated(state, BOSS_DEFEAT))
	reject(ArenaStateMachine.optIn(state, 3, BOSS_DEFEAT), "NotInOptInWindow")
	local snapshot = ArenaStateMachine.getSnapshot(state, BOSS_DEFEAT)
	assert(snapshot.aliveCount == 2 and snapshot.optInCount == 0)
	assert(not state.participants[3] and not state.alivePlayers[3])
end)

-- Plan cases 8 through 12
run("Grace blocks both damage and claims until exactly three seconds", function()
	local state = scramble({ 1, 2 })
	for _, now in { BOSS_DEFEAT, 111.5, 112.99 } do
		local result = accept(ArenaStateMachine.tick(state, now))
		assert(findAction(result, "PvPEnabled") == nil and not state.pvpEnabled)
		assert(not ArenaStateMachine.canDealPvPDamage(state, 2, 1, now))
		reject(ArenaStateMachine.damage(state, 1, 10, now, 2), "PvPNotActive")
		reject(ArenaStateMachine.startClaim(state, 1, 4, now), "GracePeriodActive")
		expectClaimCleared(state, now)
	end

	expectAction(ArenaStateMachine.tick(state, GRACE_END), "PvPEnabled")
	assert(state.phase == "PvP_EggScramble" and state.pvpEnabled)
	assert(ArenaStateMachine.canDealPvPDamage(state, 2, 1, GRACE_END))
	expectAction(ArenaStateMachine.startClaim(state, 1, 4, GRACE_END), "ClaimStarted")
	assert(findAction(accept(ArenaStateMachine.tick(state, 114)), "PvPEnabled") == nil)
end)

run("Valid opponent damage cancels a claim at 70 percent progress", function()
	local state = liveScramble({ 1, 2 })
	accept(ArenaStateMachine.startClaim(state, 1, 4, GRACE_END))
	assertNear(ArenaStateMachine.getClaimProgress(state, 116.5), 0.7, "claim progress")
	local result = ArenaStateMachine.damage(state, 1, 10, 116.5, 2)
	local cancelled = expectAction(result, "ClaimCancelled")
	assert(cancelled.reason == "Damage" and cancelled.playerId == 1)
	expectClaimCleared(state, 116.5)
end)

run("An interrupted claim requires a fresh five continuous seconds", function()
	local state = liveScramble({ 1, 2 })
	accept(ArenaStateMachine.startClaim(state, 1, 4, GRACE_END))
	accept(ArenaStateMachine.damage(state, 1, 10, 116.5, 2))
	accept(ArenaStateMachine.startClaim(state, 1, 4, 117))
	assert(ArenaStateMachine.getClaimProgress(state, 117) == 0)
	local early = accept(ArenaStateMachine.tick(state, 121.9))
	assert(findAction(early, "EggClaimed") == nil and state.phase == "PvP_EggScramble")
	assertNear(ArenaStateMachine.getClaimProgress(state, 121.9), 0.98, "restarted claim progress")
	expectEgg(ArenaStateMachine.tick(state, 122), 1, "StandardBossEgg")
	expectReset(state, 122)
end)

run("Leaving the egg radius cancels the claim and out-of-range starts are rejected", function()
	local state = liveScramble({ 1 })
	reject(ArenaStateMachine.startClaim(state, 1, 12.1, GRACE_END), "OutOfRadius")
	expectClaimCleared(state, GRACE_END)
	accept(ArenaStateMachine.startClaim(state, 1, 4, GRACE_END))
	local result = ArenaStateMachine.leaveRadius(state, 1, 115)
	assert(expectAction(result, "ClaimCancelled").reason == "LeftRadius")
	expectClaimCleared(state, 115)
	expectAction(ArenaStateMachine.startClaim(state, 1, 12, 115), "ClaimStarted")
end)

run("A contested claim keeps its owner and start time until interrupted", function()
	local state = liveScramble({ 1, 2 })
	accept(ArenaStateMachine.startClaim(state, 1, 4, GRACE_END))
	reject(ArenaStateMachine.startClaim(state, 2, 4, 114), "AlreadyClaimedByOther")
	local claim = assert(state.activeClaim)
	assert(claim.playerId == 1 and claim.startTime == GRACE_END)
	accept(ArenaStateMachine.leaveRadius(state, 1, 115))
	assert(
		expectAction(ArenaStateMachine.startClaim(state, 2, 4, 115), "ClaimStarted").playerId == 2
	)
end)

-- Plan cases 13 through 16
run("A disconnect cancels the claim and leaves the other fighter able to win", function()
	local state = liveScramble({ 1, 2 })
	accept(ArenaStateMachine.startClaim(state, 1, 4, GRACE_END))
	local result = ArenaStateMachine.disconnect(state, 1, 116)
	assert(expectAction(result, "ClaimCancelled").reason == "Disconnected")
	assert(findAction(result, "DespawnEgg") == nil)
	local snapshot = ArenaStateMachine.getSnapshot(state, 116)
	assert(snapshot.phase == "PvP_EggScramble" and snapshot.aliveCount == 1)
	assert(not state.alivePlayers[1] and not state.participants[1] and state.alivePlayers[2])
	expectClaimCleared(state, 116)
	accept(ArenaStateMachine.startClaim(state, 2, 4, 116))
	expectEgg(ArenaStateMachine.tick(state, 121), 2, "StandardBossEgg")
	expectReset(state, 121)
end)

run("The last survivor disconnecting mid-claim dissolves the egg", function()
	local state = liveScramble({ 1 })
	accept(ArenaStateMachine.startClaim(state, 1, 4, GRACE_END))
	local result = ArenaStateMachine.disconnect(state, 1, 116)
	assert(expectAction(result, "ClaimCancelled").reason == "Disconnected")
	expectDissolved(result, "AllDisconnected")
	expectReset(state, 116)
end)

run("Same-timestamp final eliminations dissolve the egg without a winner", function()
	local state = liveScramble({ 1, 2 })
	accept(ArenaStateMachine.startClaim(state, 1, 4, GRACE_END))
	local first = ArenaStateMachine.eliminate(state, 1, 116)
	assert(expectAction(first, "ClaimCancelled").reason == "Eliminated")
	expectPlayers(expectAction(first, "TeleportToPvELayer"), { 1 })
	expectPlayers(expectAction(first, "AwardConsolation"), { 1 })
	assert(findAction(first, "EggDissolved") == nil)
	assert(state.phase == "PvP_EggScramble" and state.alivePlayers[2])
	expectClaimCleared(state, 116)
	local last = ArenaStateMachine.eliminate(state, 2, 116)
	expectPlayers(expectAction(last, "TeleportToPvELayer"), { 2 })
	expectPlayers(expectAction(last, "AwardConsolation"), { 2 })
	expectDissolved(last, "MutualElimination")
	expectReset(state, 116)
end)

run("Sudden death begins after 75 active PvP seconds and shrinks to the minimum radius", function()
	local state = liveScramble({ 1, 2 })
	local early = accept(ArenaStateMachine.tick(state, 187.9))
	assert(findAction(early, "StormTick") == nil and findAction(early, "SuddenDeathStarted") == nil)
	assert(not state.stormActive and ArenaStateMachine.computeStormRadius(state, 187.9) == 80)

	local started = ArenaStateMachine.tick(state, STORM_START)
	expectAction(started, "SuddenDeathStarted")
	assert(state.stormActive and state.stormRadius == 80)
	local firstTick = expectAction(started, "StormTick")
	assert(firstTick.stormRadius == 80)
	assertNear(assert(firstTick.dt), 0.1, "first storm tick elapsed time")

	local midpoint = ArenaStateMachine.tick(state, 210.5)
	assert(findAction(midpoint, "SuddenDeathStarted") == nil)
	local storm = expectAction(midpoint, "StormTick")
	assert(state.phase == "PvP_EggScramble" and state.stormActive)
	assertNear(state.stormRadius, 44, "midpoint state radius")
	assertNear(ArenaStateMachine.computeStormRadius(state, 210.5), 44, "midpoint computed radius")
	assertNear(assert(storm.stormRadius), 44, "midpoint action radius")
	assertNear(assert(storm.damagePctPerSec), 0.08, "storm damage per second")
	assertNear(assert(storm.dt), 22.5, "midpoint tick elapsed time")

	local clamped = expectAction(ArenaStateMachine.tick(state, 263), "StormTick")
	assert(state.stormRadius == 8 and clamped.stormRadius == 8)
end)

run("Environmental storm damage cancels an active claim without an attacker", function()
	local state = liveScramble({ 1, 2 })
	expectAction(ArenaStateMachine.tick(state, STORM_START), "StormTick")
	accept(ArenaStateMachine.startClaim(state, 1, 4, STORM_START))
	local result = ArenaStateMachine.damage(state, 1, 8, 189, nil)
	assert(expectAction(result, "ClaimCancelled").reason == "Damage")
	expectClaimCleared(state, 189)
end)

-- Plan cases 17 and 18
run("Eliminating every boss fighter despawns the boss and skips the scramble", function()
	local state = bossRoom({ 1, 2 })
	local first = ArenaStateMachine.eliminate(state, 1, 108)
	expectPlayers(expectAction(first, "TeleportToPvELayer"), { 1 })
	assert(
		state.phase == "Boss_Phase" and ArenaStateMachine.getSnapshot(state, 108).aliveCount == 1
	)
	local last = ArenaStateMachine.eliminate(state, 2, 109)
	expectPlayers(expectAction(last, "TeleportToPvELayer"), { 2 })
	expectAction(last, "DespawnBoss")
	expectPhaseChange(last, "Boss_Phase", "PvE_Open", "AllEliminatedInBoss")
	assert(findAction(last, "SpawnEgg") == nil)
	expectReset(state, 109)
end)

run("Boss timeout despawns the boss and returns only surviving fighters", function()
	local state = bossRoom({ 1, 2 })
	accept(ArenaStateMachine.eliminate(state, 1, 109))
	local early = accept(ArenaStateMachine.tick(state, 284.9))
	assert(state.phase == "Boss_Phase" and findAction(early, "DespawnBoss") == nil)
	local result = ArenaStateMachine.tick(state, 285)
	expectAction(result, "DespawnBoss")
	expectPlayers(expectAction(result, "TeleportToPvELayer"), { 2 })
	expectPhaseChange(result, "Boss_Phase", "PvE_Open", "BossTimeout")
	assert(findAction(result, "SpawnEgg") == nil)
	expectReset(state, 285)
end)

-- Plan case 19 and the Overcharged trigger branches in section 3.2
run("An Overcharged trigger opens opt-in immediately and awards the Overcharged egg", function()
	local state = newArena()
	local opened = ArenaStateMachine.triggerOvercharged(state, 10)
	expectPhaseChange(opened, "PvE_Open", "OptIn_Window")
	assert(state.isOvercharged and state.phaseEndTime == 25)
	queue(state, { 1, 2, 3, 4 }, 11)
	local boss = expectAction(ArenaStateMachine.tick(state, 25), "SpawnBoss")
	assert(boss.isOvercharged)
	assertNear(assert(boss.bossMaxHp), 2870, "four-player Overcharged boss HP")
	accept(ArenaStateMachine.bossDefeated(state, 30))
	expectAction(ArenaStateMachine.tick(state, 33), "PvPEnabled")
	accept(ArenaStateMachine.startClaim(state, 1, 4, 33))
	expectEgg(ArenaStateMachine.tick(state, 38), 1, "OverchargedBossEgg")
	expectReset(state, 38)
end)

run("An Overcharged trigger upgrades the current opt-in window in place", function()
	local state = optInWindow()
	queue(state, { 1 }, OPT_IN_START)
	local result = ArenaStateMachine.triggerOvercharged(state, 100)
	assert(expectAction(result, "OptInUpdated").isOvercharged)
	assert(findAction(result, "PhaseChanged") == nil)
	local snapshot = ArenaStateMachine.getSnapshot(state, 100)
	assert(snapshot.phase == "OptIn_Window" and snapshot.isOvercharged)
	assert(snapshot.optInCount == 1 and snapshot.phaseEndTime == BOSS_START)
	local boss = expectAction(ArenaStateMachine.tick(state, BOSS_START), "SpawnBoss")
	assert(boss.isOvercharged and boss.bossMaxHp == 1400)
end)

local function expectOverchargedHandoff(state: ArenaState, now: number)
	expectClearRoom(state, now)
	if state.phase == "PvE_Open" then
		assert(state.phaseEndTime == now)
		expectPhaseChange(ArenaStateMachine.tick(state, now), "PvE_Open", "OptIn_Window")
	end
	local snapshot = ArenaStateMachine.getSnapshot(state, now)
	assert(snapshot.phase == "OptIn_Window" and snapshot.isOvercharged)
	assert(snapshot.phaseEndTime == now + 15 and not state.pendingOvercharged)
end

run("An Overcharged trigger during the boss fight queues the next cycle", function()
	local state = bossRoom({ 1 })
	local result = accept(ArenaStateMachine.triggerOvercharged(state, 109))
	assert(findAction(result, "PhaseChanged") == nil and findAction(result, "DespawnBoss") == nil)
	assert(state.pendingOvercharged and not state.isOvercharged and state.phase == "Boss_Phase")
	assert(state.phaseEndTime == 285 and state.alivePlayers[1])
	accept(ArenaStateMachine.bossDefeated(state, BOSS_DEFEAT))
	expectAction(ArenaStateMachine.tick(state, GRACE_END), "PvPEnabled")
	accept(ArenaStateMachine.startClaim(state, 1, 4, GRACE_END))
	expectEgg(ArenaStateMachine.tick(state, 118), 1, "StandardBossEgg")
	expectOverchargedHandoff(state, 118)
end)

run("An Overcharged trigger during the scramble preserves the active claim", function()
	local state = liveScramble({ 1 })
	accept(ArenaStateMachine.startClaim(state, 1, 4, GRACE_END))
	local result = accept(ArenaStateMachine.triggerOvercharged(state, 115))
	assert(
		findAction(result, "PhaseChanged") == nil and findAction(result, "ClaimCancelled") == nil
	)
	assert(
		state.pendingOvercharged and not state.isOvercharged and state.phase == "PvP_EggScramble"
	)
	assert(assert(state.activeClaim).startTime == GRACE_END)
	expectEgg(ArenaStateMachine.tick(state, 118), 1, "StandardBossEgg")
	expectOverchargedHandoff(state, 118)
end)

-- Plan case 20
run("PvP is blocked outside the scramble, against oneself, and for bystanders", function()
	local state = newArena()
	assert(not ArenaStateMachine.canDealPvPDamage(state, 1, 2, 0))
	state = optInWindow()
	queue(state, { 1, 2 }, OPT_IN_START)
	assert(not ArenaStateMachine.canDealPvPDamage(state, 1, 2, OPT_IN_START))
	accept(ArenaStateMachine.tick(state, BOSS_START))
	assert(ArenaStateMachine.isRoomLocked(state))
	assert(not ArenaStateMachine.canDealPvPDamage(state, 1, 2, BOSS_START))
	accept(ArenaStateMachine.bossDefeated(state, BOSS_DEFEAT))
	expectAction(ArenaStateMachine.tick(state, GRACE_END), "PvPEnabled")
	assert(ArenaStateMachine.canDealPvPDamage(state, 1, 2, GRACE_END))
	assert(not ArenaStateMachine.canDealPvPDamage(state, 1, 1, GRACE_END))
	assert(not ArenaStateMachine.canDealPvPDamage(state, 3, 1, GRACE_END))
	assert(not ArenaStateMachine.canDealPvPDamage(state, 1, 3, GRACE_END))
	accept(ArenaStateMachine.eliminate(state, 2, 114))
	assert(not ArenaStateMachine.canDealPvPDamage(state, 2, 1, 114))
	assert(not ArenaStateMachine.canDealPvPDamage(state, 1, 2, 114))
end)

run("A backwards tick leaves the clock and timers intact", function()
	local state = liveScramble({ 1, 2 })
	accept(ArenaStateMachine.tick(state, 114))
	reject(ArenaStateMachine.tick(state, 113), "NonMonotonicTime")
	assert(state.lastTickTime == 114)
	local snapshot = ArenaStateMachine.getSnapshot(state, 114)
	assert(snapshot.phase == "PvP_EggScramble" and snapshot.phaseStartTime == BOSS_DEFEAT)
	assert(snapshot.pvpGraceEndTime == GRACE_END and snapshot.suddenDeathStartTime == STORM_START)
	local storm = expectAction(ArenaStateMachine.tick(state, STORM_START), "StormTick")
	assertNear(assert(storm.dt), 74, "elapsed time from last accepted tick")
end)

run("Boss defeat reports are rejected outside the boss phase", function()
	local state = newArena()
	reject(ArenaStateMachine.bossDefeated(state, 0), "NotInBossPhase")
	assert(state.phase == "PvE_Open")
	state = optInWindow()
	reject(ArenaStateMachine.bossDefeated(state, OPT_IN_START), "NotInBossPhase")
	assert(state.phase == "OptIn_Window")
	state = scramble({ 1 })
	reject(ArenaStateMachine.bossDefeated(state, 111), "NotInBossPhase")
	assert(state.phase == "PvP_EggScramble" and state.pvpGraceEndTime == GRACE_END)
end)

run("Two full cycles clear the queue, fighters, claim, storm, and Overcharged state", function()
	local state = newArena()
	accept(ArenaStateMachine.triggerOvercharged(state, 0))
	queue(state, { 1 }, 1)
	accept(ArenaStateMachine.tick(state, 15))
	accept(ArenaStateMachine.bossDefeated(state, 20))
	expectAction(ArenaStateMachine.tick(state, 23), "PvPEnabled")
	expectAction(ArenaStateMachine.tick(state, 98), "SuddenDeathStarted")
	assert(state.stormActive and state.isOvercharged)
	accept(ArenaStateMachine.startClaim(state, 1, 4, 98))
	expectEgg(ArenaStateMachine.tick(state, 103), 1, "OverchargedBossEgg")
	expectReset(state, 103)

	expectPhaseChange(ArenaStateMachine.tick(state, 193), "PvE_Open", "OptIn_Window")
	expectClearRoom(state, 193)
	queue(state, { 2 }, 194)
	local boss = ArenaStateMachine.tick(state, 208)
	expectPlayers(expectAction(boss, "TeleportToBossRoom"), { 2 })
	assert(expectAction(boss, "SpawnBoss").bossMaxHp == BASE_HP)
	assert(not state.isOvercharged and not state.participants[1])
	accept(ArenaStateMachine.bossDefeated(state, 213))
	expectAction(ArenaStateMachine.tick(state, 216), "PvPEnabled")
	accept(ArenaStateMachine.startClaim(state, 2, 4, 216))
	expectEgg(ArenaStateMachine.tick(state, 221), 2, "StandardBossEgg")
	expectReset(state, 221)
end)

-- Defensive transitions and event ordering in sections 3.2–3.4
run("Boss defeat with zero survivors despawns the boss and skips egg spawn", function()
	local state = bossRoom({ 1 })
	-- Public removal handlers reset immediately, so seed the defensive guard's empty room.
	table.clear(state.alivePlayers)
	local result = ArenaStateMachine.bossDefeated(state, BOSS_DEFEAT)
	expectAction(result, "DespawnBoss")
	expectPhaseChange(result, "Boss_Phase", "PvE_Open", "NoSurvivors")
	assert(findAction(result, "SpawnEgg") == nil and findAction(result, "FullHealPlayers") == nil)
	expectReset(state, BOSS_DEFEAT)
end)

run("The last boss fighter disconnecting despawns the boss", function()
	local state = bossRoom({ 1, 2 })
	local first = accept(ArenaStateMachine.disconnect(state, 1, 108))
	assert(state.phase == "Boss_Phase" and findAction(first, "DespawnBoss") == nil)
	assert(not state.participants[1] and not state.alivePlayers[1] and state.alivePlayers[2])

	local last = ArenaStateMachine.disconnect(state, 2, 109)
	expectAction(last, "DespawnBoss")
	expectPhaseChange(last, "Boss_Phase", "PvE_Open", "AllDisconnected")
	assert(findAction(last, "SpawnEgg") == nil)
	expectReset(state, 109)
end)

run("Final eliminations at different times dissolve the egg with no survivors", function()
	local state = liveScramble({ 1, 2 })
	accept(ArenaStateMachine.eliminate(state, 1, 115))
	local result = ArenaStateMachine.eliminate(state, 2, 116)
	expectDissolved(result, "NoSurvivors")
	expectReset(state, 116)
end)

run("An empty scramble resets before enabling PvP or starting the storm", function()
	local state = scramble({ 1 })
	-- Public removal handlers reset immediately, so seed the defensive guard's empty room.
	table.clear(state.alivePlayers)
	local result = ArenaStateMachine.tick(state, STORM_START)
	expectPhaseChange(result, "PvP_EggScramble", "PvE_Open", "NoSurvivors")
	assert(findAction(result, "PvPEnabled") == nil)
	assert(findAction(result, "EggClaimed") == nil)
	assert(
		findAction(result, "SuddenDeathStarted") == nil and findAction(result, "StormTick") == nil
	)
	expectReset(state, STORM_START)
end)

run("A claim completing at the storm deadline wins before sudden death runs", function()
	local state = liveScramble({ 1, 2 })
	accept(ArenaStateMachine.startClaim(state, 1, 4, 183))
	local early = accept(ArenaStateMachine.tick(state, 187.9))
	assert(findAction(early, "EggClaimed") == nil and findAction(early, "StormTick") == nil)
	local result = ArenaStateMachine.tick(state, STORM_START)
	expectEgg(result, 1, "StandardBossEgg")
	assert(
		findAction(result, "SuddenDeathStarted") == nil and findAction(result, "StormTick") == nil
	)
	expectReset(state, STORM_START)
end)

run("The same claimant can retry without restarting and can cancel their own claim", function()
	local state = liveScramble({ 1, 2 })
	accept(ArenaStateMachine.startClaim(state, 1, 4, GRACE_END))
	local retry = accept(ArenaStateMachine.startClaim(state, 1, 4, 114))
	assert(retry.reason == "AlreadyClaiming" and #retry.actions == 0)
	assert(#accept(ArenaStateMachine.leaveRadius(state, 2, 114)).actions == 0)
	assert(findAction(ArenaStateMachine.cancelClaim(state, 2, 114), "ClaimCancelled") == nil)
	assert(assert(state.activeClaim).startTime == GRACE_END)

	local result = ArenaStateMachine.cancelClaim(state, 1, 115)
	assert(expectAction(result, "ClaimCancelled").reason == "ManualCancel")
	expectClaimCleared(state, 115)
end)

run("Invalid damage leaves the active claim intact", function()
	local state = liveScramble({ 1, 2 })
	accept(ArenaStateMachine.startClaim(state, 1, 4, GRACE_END))
	reject(ArenaStateMachine.damage(state, 1, 0, 114, 2), "InvalidDamage")
	reject(ArenaStateMachine.damage(state, 3, 10, 114, 2), "VictimNotInRoom")
	reject(ArenaStateMachine.damage(state, 1, 10, 114, 3), "InvalidPvPAttacker")
	reject(ArenaStateMachine.damage(state, 1, 10, 114, 1), "InvalidPvPAttacker")
	assertNear(ArenaStateMachine.getClaimProgress(state, 114), 0.2, "uninterrupted claim progress")
end)

run("Claims require a spawned egg and a living room participant", function()
	local state = bossRoom({ 1, 2 })
	reject(ArenaStateMachine.startClaim(state, 1, 4, 109), "NotInPvPPhase")
	accept(ArenaStateMachine.bossDefeated(state, BOSS_DEFEAT))
	accept(ArenaStateMachine.tick(state, GRACE_END))
	reject(ArenaStateMachine.startClaim(state, 3, 4, GRACE_END), "PlayerNotAliveInRoom")
	accept(ArenaStateMachine.eliminate(state, 2, 114))
	reject(ArenaStateMachine.startClaim(state, 2, 4, 114), "PlayerNotAliveInRoom")
	expectClaimCleared(state, 114)
end)

print("PASS: ArenaStateMachine.spec.luau")
