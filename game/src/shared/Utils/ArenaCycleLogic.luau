--!strict
--[[
	ArenaCycleLogic.luau
	Pure 3-Phase Biome Arena FSM + 5-Minute Overcharged Global Scheduler.
	100% deterministic & Lune-testable (zero Roblox Instance dependencies).
]]

local req: any = require
local scriptRef: any = script
local BiomeConfigs = if type(scriptRef) == "userdata"
	then req(scriptRef.Parent.Parent.Configs.BiomeConfigs)
	else req("../Configs/BiomeConfigs")

export type ArenaPhase = "PvE_Open" | "OptIn_Window" | "Boss_Phase" | "PvP_EggScramble"

export type ClaimState = {
	claimerId: number?,
	startedAt: number,
	progress: number,
}

export type ArenaEvent = {
	kind: string,
	biomeId: string,
	payload: { [string]: any },
}

export type BiomeArenaState = {
	biomeId: string,
	phase: ArenaPhase,
	phaseStartedAt: number,
	phaseEndsAt: number,
	isOvercharged: boolean,
	queuedPlayers: { [number]: number }, -- userId -> powerRating
	activePlayers: { [number]: boolean }, -- alive inside Locked Boss/PvP Room
	participants: { [number]: boolean }, -- everyone who entered Boss Phase (for payouts)
	bossHP: number,
	bossMaxHP: number,
	eggSpawnedAt: number,
	pvpStartedAt: number,
	suddenDeathRadius: number,
	claim: ClaimState,
}

export type OverchargedClock = {
	nextEventAt: number,
	eventCount: number,
}

local ArenaCycleLogic = {}

local function countMap(tbl: { [number]: any }): number
	local n = 0
	for _ in pairs(tbl) do
		n += 1
	end
	return n
end

local function cloneUserList(tbl: { [number]: any }): { number }
	local list: { number } = {}
	for userId in pairs(tbl) do
		table.insert(list, userId)
	end
	table.sort(list)
	return list
end

local function clearClaim(state: BiomeArenaState)
	state.claim.claimerId = nil
	state.claim.startedAt = 0
	state.claim.progress = 0
end

local function resetToPvE(
	state: BiomeArenaState,
	now: number,
	events: { ArenaEvent },
	reason: string
)
	local biome = BiomeConfigs.BIOMES[state.biomeId]
	local oldParticipants = cloneUserList(state.participants)
	local oldActive = cloneUserList(state.activePlayers)
	state.phase = "PvE_Open"
	state.phaseStartedAt = now
	state.phaseEndsAt = now + biome.pveCycleSeconds
	state.isOvercharged = false
	state.queuedPlayers = {}
	state.activePlayers = {}
	state.participants = {}
	state.bossHP = 0
	state.bossMaxHP = 0
	state.eggSpawnedAt = 0
	state.pvpStartedAt = 0
	state.suddenDeathRadius = BiomeConfigs.SUDDEN_DEATH_START_RADIUS
	clearClaim(state)
	table.insert(events, {
		kind = "PhaseChanged",
		biomeId = state.biomeId,
		payload = {
			phase = "PvE_Open",
			reason = reason,
			returnPlayers = oldActive,
			participants = oldParticipants,
			endsAt = state.phaseEndsAt,
		},
	})
end

function ArenaCycleLogic.createOverchargedClock(startTime: number): OverchargedClock
	return {
		nextEventAt = startTime + BiomeConfigs.OVERCHARGED_INTERVAL_SEC,
		eventCount = 0,
	}
end

function ArenaCycleLogic.createBiomeState(biomeId: string, now: number): BiomeArenaState
	local biome = BiomeConfigs.BIOMES[biomeId]
	if not biome then
		error(`Unknown biomeId: {biomeId}`)
	end
	return {
		biomeId = biomeId,
		phase = "PvE_Open",
		phaseStartedAt = now,
		phaseEndsAt = now + biome.pveCycleSeconds,
		isOvercharged = false,
		queuedPlayers = {},
		activePlayers = {},
		participants = {},
		bossHP = 0,
		bossMaxHP = 0,
		eggSpawnedAt = 0,
		pvpStartedAt = 0,
		suddenDeathRadius = BiomeConfigs.SUDDEN_DEATH_START_RADIUS,
		claim = { claimerId = nil, startedAt = 0, progress = 0 },
	}
end

function ArenaCycleLogic.triggerOptIn(
	state: BiomeArenaState,
	now: number,
	isOvercharged: boolean
): { ArenaEvent }
	local events: { ArenaEvent } = {}
	if state.phase ~= "PvE_Open" then
		return events
	end
	state.phase = "OptIn_Window"
	state.phaseStartedAt = now
	state.phaseEndsAt = now + BiomeConfigs.OPT_IN_WINDOW_SEC
	state.isOvercharged = isOvercharged
	state.queuedPlayers = {}
	table.insert(events, {
		kind = "PhaseChanged",
		biomeId = state.biomeId,
		payload = {
			phase = "OptIn_Window",
			isOvercharged = isOvercharged,
			endsAt = state.phaseEndsAt,
		},
	})
	return events
end

function ArenaCycleLogic.stepOverchargedClock(
	clock: OverchargedClock,
	states: { [string]: BiomeArenaState },
	now: number
): { ArenaEvent }
	local events: { ArenaEvent } = {}
	if now < clock.nextEventAt then
		return events
	end
	clock.eventCount += 1
	clock.nextEventAt = now + BiomeConfigs.OVERCHARGED_INTERVAL_SEC
	table.insert(events, {
		kind = "OverchargedGlobalAlert",
		biomeId = "Global",
		payload = { eventCount = clock.eventCount, triggeredAt = now },
	})
	for _, biomeId in ipairs(BiomeConfigs.ORDERED_MVP_BIOMES) do
		local st = states[biomeId]
		if st and st.phase == "PvE_Open" then
			local sub = ArenaCycleLogic.triggerOptIn(st, now, true)
			for _, ev in ipairs(sub) do
				table.insert(events, ev)
			end
		elseif st and st.phase == "OptIn_Window" then
			st.isOvercharged = true
		end
	end
	return events
end

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function ArenaCycleLogic.setOptIn(
	state: BiomeArenaState,
	userId: number,
	optedIn: boolean,
	powerRating: number
): boolean
	if
		state.phase ~= "OptIn_Window"
		or not isFiniteNumber(userId)
		or type(optedIn) ~= "boolean"
	then
		return false
	end
	if optedIn then
		local safePower = if isFiniteNumber(powerRating)
			then math.max(0, math.floor(powerRating))
			else 0
		state.queuedPlayers[userId] = safePower
	else
		state.queuedPlayers[userId] = nil
	end
	return true
end

function ArenaCycleLogic.getQueueSummary(state: BiomeArenaState): (number, number)
	local count = 0
	local maxPower = 0
	for _, power in pairs(state.queuedPlayers) do
		count += 1
		if power > maxPower then
			maxPower = power
		end
	end
	return count, maxPower
end

function ArenaCycleLogic.startBossPhase(state: BiomeArenaState, now: number): { ArenaEvent }
	local events: { ArenaEvent } = {}
	local count = countMap(state.queuedPlayers)
	if count == 0 then
		resetToPvE(state, now, events, "NoOptIn")
		return events
	end
	state.phase = "Boss_Phase"
	state.phaseStartedAt = now
	state.phaseEndsAt = now + BiomeConfigs.BOSS_PHASE_TIMEOUT_SEC
	state.activePlayers = {}
	state.participants = {}
	for userId in pairs(state.queuedPlayers) do
		state.activePlayers[userId] = true
		state.participants[userId] = true
	end
	state.queuedPlayers = {}
	state.bossMaxHP = BiomeConfigs.computeBossMaxHP(state.biomeId, count, state.isOvercharged)
	state.bossHP = state.bossMaxHP
	table.insert(events, {
		kind = "PhaseChanged",
		biomeId = state.biomeId,
		payload = {
			phase = "Boss_Phase",
			players = cloneUserList(state.activePlayers),
			bossMaxHP = state.bossMaxHP,
			isOvercharged = state.isOvercharged,
			endsAt = state.phaseEndsAt,
		},
	})
	return events
end

function ArenaCycleLogic.applyBossDamage(
	state: BiomeArenaState,
	attackerId: number,
	damage: number,
	now: number
): (boolean, { ArenaEvent })
	local events: { ArenaEvent } = {}
	if state.phase ~= "Boss_Phase" or not state.activePlayers[attackerId] then
		return false, events
	end
	if not isFiniteNumber(damage) or damage <= 0 or not isFiniteNumber(now) then
		return false, events
	end
	state.bossHP = math.max(0, state.bossHP - damage)
	if state.bossHP <= 0 then
		state.phase = "PvP_EggScramble"
		state.phaseStartedAt = now
		state.eggSpawnedAt = now
		state.pvpStartedAt = now + BiomeConfigs.PVP_GRACE_SEC
		state.phaseEndsAt = state.pvpStartedAt
			+ BiomeConfigs.SUDDEN_DEATH_START_SEC
			+ BiomeConfigs.SUDDEN_DEATH_SHRINK_SEC
			+ 30
		state.suddenDeathRadius = BiomeConfigs.SUDDEN_DEATH_START_RADIUS
		clearClaim(state)
		table.insert(events, {
			kind = "BossDefeated",
			biomeId = state.biomeId,
			payload = {
				survivors = cloneUserList(state.activePlayers),
				isOvercharged = state.isOvercharged,
				pvpStartsAt = state.pvpStartedAt,
			},
		})
	end
	return true, events
end

-- Anti-Desync Guard: PvP damage is ONLY valid during active PvP_EggScramble (after 3s grace)
function ArenaCycleLogic.canDealPvPDamage(
	state: BiomeArenaState,
	attackerId: number,
	victimId: number,
	now: number
): boolean
	if state.phase ~= "PvP_EggScramble" or not isFiniteNumber(now) then
		return false
	end
	if attackerId == victimId then
		return false
	end
	if now < state.pvpStartedAt then
		return false
	end
	return state.activePlayers[attackerId] == true and state.activePlayers[victimId] == true
end

function ArenaCycleLogic.beginEggClaim(
	state: BiomeArenaState,
	userId: number,
	distanceToEgg: number,
	now: number
): boolean
	if state.phase ~= "PvP_EggScramble" or not state.activePlayers[userId] then
		return false
	end
	if not isFiniteNumber(now) or not isFiniteNumber(distanceToEgg) or distanceToEgg < 0 then
		return false
	end
	if now < state.pvpStartedAt then
		return false
	end
	if distanceToEgg > BiomeConfigs.EGG_CLAIM_RADIUS then
		return false
	end
	if state.claim.claimerId ~= nil and state.claim.claimerId ~= userId then
		return false
	end
	if state.claim.claimerId == nil then
		state.claim.claimerId = userId
		state.claim.startedAt = now
		state.claim.progress = 0
	end
	return true
end

function ArenaCycleLogic.cancelEggClaim(
	state: BiomeArenaState,
	userId: number,
	reason: string
): { ArenaEvent }
	local events: { ArenaEvent } = {}
	if state.claim.claimerId ~= userId then
		return events
	end
	clearClaim(state)
	table.insert(events, {
		kind = "ClaimCanceled",
		biomeId = state.biomeId,
		payload = { userId = userId, reason = reason },
	})
	return events
end

function ArenaCycleLogic.onPlayerDamagedInPvP(
	state: BiomeArenaState,
	victimId: number
): { ArenaEvent }
	if state.phase ~= "PvP_EggScramble" then
		return {}
	end
	return ArenaCycleLogic.cancelEggClaim(state, victimId, "Damaged")
end

function ArenaCycleLogic.removePlayerFromArena(
	state: BiomeArenaState,
	userId: number,
	now: number,
	reason: string
): { ArenaEvent }
	local events: { ArenaEvent } = {}
	state.queuedPlayers[userId] = nil
	if not state.activePlayers[userId] then
		return events
	end
	state.activePlayers[userId] = nil
	if state.claim.claimerId == userId then
		clearClaim(state)
		table.insert(events, {
			kind = "ClaimCanceled",
			biomeId = state.biomeId,
			payload = { userId = userId, reason = reason },
		})
	end
	table.insert(events, {
		kind = "PlayerEliminated",
		biomeId = state.biomeId,
		payload = { userId = userId, reason = reason },
	})
	if countMap(state.activePlayers) == 0 then
		resetToPvE(state, now, events, "AllPlayersOut_" .. reason)
	end
	return events
end

function ArenaCycleLogic.stepBiome(
	state: BiomeArenaState,
	now: number,
	claimerDistance: number?
): { ArenaEvent }
	local events: { ArenaEvent } = {}
	if state.phase == "PvE_Open" then
		if now >= state.phaseEndsAt then
			return ArenaCycleLogic.triggerOptIn(state, now, false)
		end
	elseif state.phase == "OptIn_Window" then
		if now >= state.phaseEndsAt then
			return ArenaCycleLogic.startBossPhase(state, now)
		end
	elseif state.phase == "Boss_Phase" then
		if countMap(state.activePlayers) == 0 or now >= state.phaseEndsAt then
			resetToPvE(state, now, events, "BossExpiredOrWiped")
		end
	elseif state.phase == "PvP_EggScramble" then
		if countMap(state.activePlayers) == 0 then
			resetToPvE(state, now, events, "EmptyPvP")
			return events
		end
		local pvpElapsed = math.max(0, now - state.pvpStartedAt)
		state.suddenDeathRadius = BiomeConfigs.computeSuddenDeathRadius(pvpElapsed)
		local claimer = state.claim.claimerId
		if claimer ~= nil then
			local badDist = claimerDistance ~= nil
				and (not isFiniteNumber(claimerDistance) or (claimerDistance :: number) < 0)
			local outOfRange = badDist
				or (
					claimerDistance ~= nil
					and (claimerDistance :: number) > BiomeConfigs.EGG_CLAIM_RADIUS
				)
			if not state.activePlayers[claimer] or outOfRange then
				local cancelEv = ArenaCycleLogic.cancelEggClaim(state, claimer, "OutOfRadius")
				for _, ev in ipairs(cancelEv) do
					table.insert(events, ev)
				end
			else
				local held = math.max(0, now - state.claim.startedAt)
				state.claim.progress = math.clamp(held / BiomeConfigs.EGG_CLAIM_DURATION_SEC, 0, 1)
				if held >= BiomeConfigs.EGG_CLAIM_DURATION_SEC then
					local biome = BiomeConfigs.BIOMES[state.biomeId]
					local eggId = if state.isOvercharged
						then biome.overchargedEggId
						else biome.standardEggId
					table.insert(events, {
						kind = "EggClaimed",
						biomeId = state.biomeId,
						payload = {
							winnerId = claimer,
							eggId = eggId,
							isOvercharged = state.isOvercharged,
							participants = cloneUserList(state.participants),
						},
					})
					resetToPvE(state, now, events, "EggClaimed")
				end
			end
		end
	end
	return events
end

return ArenaCycleLogic
