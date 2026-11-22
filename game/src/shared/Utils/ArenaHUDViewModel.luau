--!strict
--[[
	ArenaHUDViewModel (Issue #7): pure HUD state. Server payloads (ArenaStateChanged,
	OptInPrompt, EggClaimUpdated) go in, a display description comes out. No Roblox APIs,
	so every HUD rule is tested in Lune; the UI controller only draws getDisplay().
	Between packets the HUD ticks its own clocks via step(dt).
]]

export type ArenaPhase = "PvE_Open" | "OptIn_Window" | "Boss_Phase" | "PvP_EggScramble"
export type ClaimStatus = "Idle" | "Claiming" | "Interrupted" | "Completed"

type BiomeSnapshot = {
	phase: ArenaPhase,
	secondsRemaining: number,
	isOvercharged: boolean,
	bossHp: number?,
	bossMaxHp: number?,
	suddenDeathActive: boolean,
	pvePlayerCount: number,
	queuedPlayers: number,
	highestPowerRating: number,
	recommendedDamage: number,
	overchargeAlerted: boolean,
}

type Claim = {
	biomeId: string?,
	status: ClaimStatus,
	claimerUserId: number?,
	claimerName: string?,
	progressSeconds: number,
	durationSeconds: number,
	reason: string?,
	timerRemaining: number, -- interrupt flash or completion celebration
}

local ArenaHUDViewModel = {}

local OVERCHARGED_ALERT_SECONDS = 6
local INTERRUPT_FLASH_SECONDS = 0.85
local COMPLETE_HOLD_SECONDS = 1.5
local DEFAULT_CLAIM_SECONDS = 5
local PHASES = { PvE_Open = true, OptIn_Window = true, Boss_Phase = true, PvP_EggScramble = true }
local CLAIM_STATUSES = { Idle = true, Claiming = true, Interrupted = true, Completed = true }
local BIOME_NAMES = {
	EmeraldMeadow = "Emerald Meadow",
	FrostbiteCavern = "Frostbite Cavern",
	MoltenCaldera = "Molten Caldera",
	StormRuins = "Storm Ruins",
	VoidCitadel = "Void Citadel",
}
local INTERRUPT_TEXT = {
	Damage = "INTERRUPTED BY DAMAGE!",
	LeftRadius = "LEFT CLAIM RADIUS!",
	PlayerMoved = "LEFT CLAIM RADIUS!", -- the mock harness's name for LeftRadius
	Eliminated = "ELIMINATED!",
	Disconnected = "CLAIMER DISCONNECTED",
	ManualCancel = "CLAIM CANCELLED",
}
local POWER_TIERS = {
	{ min = 10_000, name = "Mythic" },
	{ min = 1_500, name = "Titan" },
	{ min = 250, name = "Champion" },
	{ min = 50, name = "Brawler" },
	{ min = 0, name = "Rookie" },
}

local function isFinite(n: unknown): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function finiteOr(n: unknown, fallback: number): number
	return if isFinite(n) then n :: number else fallback
end

-- Formatting -----------------------------------------------------------------------------------

function ArenaHUDViewModel.formatCountdown(seconds: number): string
	local total = if isFinite(seconds) and seconds > 0 then math.ceil(seconds) else 0
	if total >= 60 then
		return string.format("%02d:%02d", total // 60, total % 60)
	end
	return string.format("0:%02d", total)
end

function ArenaHUDViewModel.formatShortSeconds(seconds: number): string
	return `{if isFinite(seconds) and seconds > 0 then math.ceil(seconds) else 0}s`
end

local function trimDecimals(value: number): string
	local text = string.format("%.2f", value):gsub("0+$", ""):gsub("%.$", "")
	return text
end

function ArenaHUDViewModel.formatNumber(value: number): string
	local n = if isFinite(value) and value > 0 then value else 0
	if n >= 1_000_000 then
		return trimDecimals(n / 1_000_000) .. "M"
	elseif n >= 1_000 then
		return trimDecimals(n / 1_000) .. "K"
	end
	return tostring(math.floor(n))
end

local function withCommas(value: number): string
	local digits = tostring(math.floor(math.max(0, finiteOr(value, 0))))
	local out = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

function ArenaHUDViewModel.formatInterruptReason(reason: string?): string
	return reason and INTERRUPT_TEXT[reason] or "CLAIM INTERRUPTED!"
end

function ArenaHUDViewModel.formatPowerBadge(power: number, ascensionRank: number?)
	local p = if isFinite(power) and power > 0 then power else 0
	local tierName = "Rookie"
	for _, tier in POWER_TIERS do
		if p >= tier.min then
			tierName = tier.name
			break
		end
	end
	local rank = if ascensionRank and isFinite(ascensionRank) then math.floor(ascensionRank) else 0
	return {
		powerText = ArenaHUDViewModel.formatNumber(p),
		tierName = tierName,
		ascensionText = if rank >= 1 then `★{rank}` else nil,
	}
end

local function biomeName(biomeId: string): string
	return BIOME_NAMES[biomeId] or (biomeId:gsub("(%l)(%u)", "%1 %2"))
end

-- State ------------------------------------------------------------------------------------------

local function idleClaim(): Claim
	return {
		biomeId = nil,
		status = "Idle",
		claimerUserId = nil,
		claimerName = nil,
		progressSeconds = 0,
		durationSeconds = DEFAULT_CLAIM_SECONDS,
		reason = nil,
		timerRemaining = 0,
	}
end

function ArenaHUDViewModel.new(localUserId: number)
	return {
		localUserId = localUserId,
		activeBiomeId = nil :: string?,
		inLockedRoom = false,
		biomes = {} :: { [string]: BiomeSnapshot },
		optInQueued = false,
		optInDismissed = false,
		claim = idleClaim(),
		overchargedAlertRemaining = 0,
	}
end

export type State = typeof(ArenaHUDViewModel.new(0))

local function biomeOf(state: State, biomeId: string): BiomeSnapshot
	local snap = state.biomes[biomeId]
	if not snap then
		snap = {
			phase = "PvE_Open",
			secondsRemaining = 0,
			isOvercharged = false,
			bossHp = nil,
			bossMaxHp = nil,
			suddenDeathActive = false,
			pvePlayerCount = 0,
			queuedPlayers = 0,
			highestPowerRating = 0,
			recommendedDamage = 0,
			overchargeAlerted = false,
		}
		state.biomes[biomeId] = snap
	end
	return snap
end

local function activeSnapshot(state: State): BiomeSnapshot?
	return if state.activeBiomeId then state.biomes[state.activeBiomeId] else nil
end

function ArenaHUDViewModel.setActiveBiome(state: State, biomeId: string?, inLockedRoom: boolean?)
	state.activeBiomeId = biomeId
	state.inLockedRoom = inLockedRoom == true
end

-- Reducers -----------------------------------------------------------------------------------------

-- A biome moving to a new phase resets per-window state (queue, dismissal, live claim).
local function onPhaseChange(
	state: State,
	biomeId: string,
	snap: BiomeSnapshot,
	nextPhase: ArenaPhase
)
	if nextPhase ~= "OptIn_Window" and biomeId == state.activeBiomeId then
		state.optInQueued, state.optInDismissed = false, false
	end
	if nextPhase == "PvE_Open" then
		snap.overchargeAlerted = false
	end
	local claim = state.claim
	if
		nextPhase ~= "PvP_EggScramble"
		and claim.biomeId == biomeId
		and claim.status == "Claiming"
	then
		state.claim = idleClaim()
	end
end

local function maybeAlertOvercharged(state: State, snap: BiomeSnapshot)
	if snap.phase == "OptIn_Window" and snap.isOvercharged and not snap.overchargeAlerted then
		snap.overchargeAlerted = true
		state.overchargedAlertRemaining = OVERCHARGED_ALERT_SECONDS
	end
end

function ArenaHUDViewModel.onArenaStateChanged(state: State, payload: unknown)
	if type(payload) ~= "table" then
		return
	end
	local p = payload :: any
	if
		type(p.biomeId) ~= "string"
		or not PHASES[p.phase]
		or not isFinite(p.phaseSecondsRemaining)
	then
		return -- malformed: keep the current HUD
	end
	local snap = biomeOf(state, p.biomeId)
	if snap.phase ~= p.phase then
		onPhaseChange(state, p.biomeId, snap, p.phase)
	end
	snap.phase = p.phase
	snap.secondsRemaining = math.max(0, p.phaseSecondsRemaining)
	snap.isOvercharged = p.isOvercharged == true
	snap.bossHp = if isFinite(p.bossHp) then p.bossHp else nil
	snap.bossMaxHp = if isFinite(p.bossMaxHp) then p.bossMaxHp else nil
	snap.suddenDeathActive = p.suddenDeathActive == true
	snap.pvePlayerCount = math.max(0, math.floor(finiteOr(p.pvePlayerCount, snap.pvePlayerCount)))
	maybeAlertOvercharged(state, snap)
end

function ArenaHUDViewModel.onOptInPrompt(state: State, payload: unknown)
	if type(payload) ~= "table" then
		return
	end
	local p = payload :: any
	if type(p.biomeId) ~= "string" or not isFinite(p.secondsRemaining) then
		return
	end
	local snap = biomeOf(state, p.biomeId)
	if snap.phase ~= "OptIn_Window" then
		onPhaseChange(state, p.biomeId, snap, "OptIn_Window")
	end
	snap.phase = "OptIn_Window"
	snap.secondsRemaining = math.max(0, p.secondsRemaining)
	snap.isOvercharged = p.isOvercharged == true
	snap.queuedPlayers = math.max(0, math.floor(finiteOr(p.queuedPlayers, 0)))
	snap.highestPowerRating = math.max(0, finiteOr(p.highestPowerRating, 0))
	snap.recommendedDamage = math.max(0, finiteOr(p.recommendedDamage, 0))
end

local function applyClaiming(state: State, p: any, duration: number)
	local claim = state.claim
	local progress = math.clamp(finiteOr(p.progressSeconds, 0), 0, duration)
	local sameClaim = claim.status == "Claiming"
		and claim.claimerUserId == p.claimerUserId
		and claim.biomeId == p.biomeId
	-- The live server sends one event per transition and the mock sends every frame: never
	-- rewind on a late packet, never double-advance on a fresh one.
	claim.progressSeconds = if sameClaim
		then math.max(claim.progressSeconds, progress)
		else progress
end

function ArenaHUDViewModel.onEggClaimUpdated(state: State, payload: unknown)
	if type(payload) ~= "table" then
		return
	end
	local p = payload :: any
	if type(p.biomeId) ~= "string" or not CLAIM_STATUSES[p.status] then
		return
	end
	local duration = if isFinite(p.durationSeconds) and p.durationSeconds > 0
		then p.durationSeconds
		else DEFAULT_CLAIM_SECONDS
	if p.status == "Claiming" then
		applyClaiming(state, p, duration)
	end
	local claim = state.claim
	claim.biomeId, claim.status, claim.durationSeconds = p.biomeId, p.status, duration
	claim.claimerUserId = if isFinite(p.claimerUserId) then p.claimerUserId else nil
	claim.claimerName = if type(p.claimerName) == "string" then p.claimerName else nil
	claim.reason = if type(p.interruptReason) == "string" then p.interruptReason else nil
	if p.status == "Interrupted" then
		claim.progressSeconds, claim.timerRemaining = 0, INTERRUPT_FLASH_SECONDS
	elseif p.status == "Completed" then
		claim.progressSeconds, claim.timerRemaining = duration, COMPLETE_HOLD_SECONDS
	elseif p.status == "Idle" then
		state.claim = idleClaim()
	end
end

function ArenaHUDViewModel.step(state: State, dt: number)
	if not isFinite(dt) or dt <= 0 then
		return
	end
	for _, snap in state.biomes do
		snap.secondsRemaining = math.max(0, snap.secondsRemaining - dt)
	end
	state.overchargedAlertRemaining = math.max(0, state.overchargedAlertRemaining - dt)
	local claim = state.claim
	if claim.status == "Claiming" then
		claim.progressSeconds = math.min(claim.durationSeconds, claim.progressSeconds + dt)
	elseif claim.status == "Interrupted" or claim.status == "Completed" then
		claim.timerRemaining -= dt
		if claim.timerRemaining <= 0 then
			state.claim = idleClaim()
		end
	end
end

-- Intents ------------------------------------------------------------------------------------------

local function optInOpen(state: State): boolean
	local snap = activeSnapshot(state)
	return snap ~= nil
		and not state.inLockedRoom
		and snap.phase == "OptIn_Window"
		and snap.secondsRemaining > 0
end

-- (true, payload) to send; (false, nil) when the button should do nothing.
function ArenaHUDViewModel.buildOptInIntent(
	state: State,
	accept: boolean
): (boolean, { accepted: boolean }?)
	if not optInOpen(state) then
		return false, nil
	end
	state.optInQueued = accept
	state.optInDismissed = not accept
	return true, { accepted = accept }
end

function ArenaHUDViewModel.buildClaimEggIntent(
	state: State,
	holding: boolean
): (boolean, { action: string }?)
	if not holding then
		return true, { action = "Cancel" } -- releasing is always safe to send
	end
	local snap = activeSnapshot(state)
	if snap and state.inLockedRoom and snap.phase == "PvP_EggScramble" then
		return true, { action = "Start" }
	end
	return false, nil
end

-- Display ------------------------------------------------------------------------------------------

local function activeModal(state: State): string
	if not optInOpen(state) then
		return "None"
	elseif state.optInQueued then
		return "QueuedPill"
	elseif state.optInDismissed then
		return "None"
	end
	return "OptIn"
end

local function accentTone(snap: BiomeSnapshot): string
	if snap.phase == "PvP_EggScramble" then
		return if snap.suddenDeathActive then "SuddenDeath" else "PvP"
	elseif snap.isOvercharged then
		return "Overcharged"
	end
	return if snap.phase == "Boss_Phase" then "Boss" else "Safe"
end

local function bannerDisplay(state: State)
	local snap = activeSnapshot(state)
	local biomeId = state.activeBiomeId
	if not snap or not biomeId then
		local hub = {
			visible = true,
			biomeId = biomeId,
			biomeName = if biomeId then biomeName(biomeId) else "Hub",
		}
		hub.phase, hub.accentTone, hub.countdownText =
			if biomeId then "PvE_Open" else "Hub", "Safe", ""
		hub.showBossHpBar, hub.bossHpRatio, hub.bossHpText = false, 0, ""
		hub.showSuddenDeathWarning, hub.suddenDeathText = false, ""
		return hub
	end
	local hp, maxHp = snap.bossHp, snap.bossMaxHp
	local hasHp = snap.phase == "Boss_Phase" and hp ~= nil and maxHp ~= nil and maxHp > 0
	return {
		visible = true,
		biomeId = biomeId,
		biomeName = biomeName(biomeId),
		phase = snap.phase :: string,
		accentTone = accentTone(snap),
		countdownText = ArenaHUDViewModel.formatCountdown(snap.secondsRemaining),
		showBossHpBar = hasHp,
		bossHpRatio = if hasHp and hp and maxHp then math.clamp(hp / maxHp, 0, 1) else 0,
		bossHpText = if hasHp
				and hp
				and maxHp
			then `{withCommas(hp)} / {withCommas(maxHp)}`
			else "",
		showSuddenDeathWarning = snap.phase == "PvP_EggScramble" and snap.suddenDeathActive,
		suddenDeathText = if snap.suddenDeathActive then "SUDDEN DEATH — STORM CLOSING!" else "",
	}
end

local function optInDisplay(state: State, modal: string)
	local snap = activeSnapshot(state)
	local queued = if snap then snap.queuedPlayers else 0
	local power = if snap then snap.highestPowerRating else 0
	local seconds = if snap and snap.phase == "OptIn_Window" then snap.secondsRemaining else 0
	return {
		visible = modal == "OptIn",
		showQueuedPill = modal == "QueuedPill",
		isLocalQueued = state.optInQueued,
		biomeId = state.activeBiomeId,
		isOvercharged = snap ~= nil and snap.isOvercharged,
		secondsRemaining = seconds,
		countdownText = ArenaHUDViewModel.formatShortSeconds(seconds),
		queuedPlayers = queued,
		queuedText = `{queued} Fighter{if queued == 1 then "" else "s"} Queued`,
		highestPowerText = `Top Power: {if power > 0
			then ArenaHUDViewModel.formatNumber(power)
			else "--"}`,
		recommendedText = `Rec. {withCommas(if snap then snap.recommendedDamage else 0)} DMG`,
	}
end

local function claimDisplay(state: State)
	local claim, snap = state.claim, activeSnapshot(state)
	local here = claim.biomeId ~= nil and claim.biomeId == state.activeBiomeId
	local status = claim.status
	local countdown = if status == "Claiming"
		then string.format("%.1fs", math.max(0, claim.durationSeconds - claim.progressSeconds))
		else if status == "Completed" then "CLAIMED!" else ""
	return {
		visible = here and status ~= "Idle",
		status = status,
		isLocalClaimer = claim.claimerUserId == state.localUserId,
		claimerLabel = if claim.claimerName then `{claim.claimerName} is claiming` else "",
		progressSeconds = claim.progressSeconds,
		progressRatio = claim.progressSeconds / claim.durationSeconds,
		durationSeconds = claim.durationSeconds,
		countdownText = countdown,
		flashInterrupt = here and status == "Interrupted" and claim.timerRemaining > 0,
		interruptReasonText = if status == "Interrupted"
			then ArenaHUDViewModel.formatInterruptReason(claim.reason)
			else "",
		showHoldPromptButton = snap ~= nil
			and state.inLockedRoom
			and snap.phase == "PvP_EggScramble",
	}
end

function ArenaHUDViewModel.getDisplay(state: State)
	local modal = activeModal(state)
	return {
		activeBiomeId = state.activeBiomeId,
		activeModal = modal,
		banner = bannerDisplay(state),
		optInModal = optInDisplay(state, modal),
		claimRing = claimDisplay(state),
		overchargedAlert = {
			visible = state.overchargedAlertRemaining > 0,
			remainingSeconds = state.overchargedAlertRemaining,
		},
	}
end

function ArenaHUDViewModel.getPortalDisplay(
	state: State,
	biomeId: string,
	recommendedDamage: number,
	enabled: boolean?
)
	local snap = state.biomes[biomeId]
	local timer = "--"
	if enabled == false then
		timer = "COMING SOON"
	elseif snap and snap.phase == "PvE_Open" then
		timer = "Boss Opt-In: " .. ArenaHUDViewModel.formatCountdown(snap.secondsRemaining)
	elseif snap and snap.phase == "OptIn_Window" then
		timer = "OPT-IN LIVE! " .. ArenaHUDViewModel.formatCountdown(snap.secondsRemaining)
	elseif snap and snap.phase == "Boss_Phase" then
		timer = "BOSS IN PROGRESS"
	elseif snap and snap.phase == "PvP_EggScramble" then
		timer = "PvP SCRAMBLE"
	end
	return {
		biomeId = biomeId,
		biomeName = biomeName(biomeId),
		enabled = enabled ~= false,
		recommendedDamage = recommendedDamage,
		recommendedText = `Rec. {withCommas(recommendedDamage)} DMG`,
		playerCountText = `{if snap then snap.pvePlayerCount else 0} in PvE`,
		isOvercharged = snap ~= nil and snap.isOvercharged,
		timerLabel = timer,
	}
end

return ArenaHUDViewModel
