--!strict
local ArenaHUDViewModel = require("../src/shared/Utils/ArenaHUDViewModel")

type State = typeof(ArenaHUDViewModel.new(10))
type ArenaPhase = ArenaHUDViewModel.ArenaPhase
type ClaimStatus = ArenaHUDViewModel.ClaimStatus

type PhaseOptions = {
	isOvercharged: boolean?,
	bossHp: number?,
	bossMaxHp: number?,
	suddenDeathActive: boolean?,
	pvePlayerCount: number?,
}

type PromptOptions = {
	isOvercharged: boolean?,
	queuedPlayers: number?,
	highestPowerRating: number?,
	recommendedDamage: number?,
}

local MEADOW = "EmeraldMeadow"
local FROSTBITE = "FrostbiteCavern"
local CALDERA = "MoltenCaldera"
local LOCAL_USER_ID = 10

local function run(name: string, test: () -> ())
	local ok, failure = pcall(test)
	assert(ok, `{name}: {failure}`)
end

local function expectNear(actual: number, expected: number, label: string)
	assert(math.abs(actual - expected) <= 1e-6, `{label}: expected {expected}, got {actual}`)
end

local function publishPhase(
	state: State,
	biomeId: string,
	phase: ArenaPhase,
	seconds: number,
	options: PhaseOptions?
)
	local fields = options or {}
	ArenaHUDViewModel.onArenaStateChanged(state, {
		biomeId = biomeId,
		phase = phase,
		phaseSecondsRemaining = seconds,
		isOvercharged = fields.isOvercharged == true,
		bossHp = fields.bossHp,
		bossMaxHp = fields.bossMaxHp,
		suddenDeathActive = fields.suddenDeathActive == true,
		pvePlayerCount = fields.pvePlayerCount or 3,
	})
end

local function publishOptIn(state: State, biomeId: string, seconds: number, options: PromptOptions?)
	local fields = options or {}
	ArenaHUDViewModel.onOptInPrompt(state, {
		biomeId = biomeId,
		secondsRemaining = seconds,
		isOvercharged = fields.isOvercharged == true,
		queuedPlayers = fields.queuedPlayers or 3,
		highestPowerRating = fields.highestPowerRating or 420,
		recommendedDamage = fields.recommendedDamage or 15,
	})
end

local function publishClaim(
	state: State,
	status: ClaimStatus,
	progress: number,
	reason: string?,
	otherClaimer: boolean?
)
	ArenaHUDViewModel.onEggClaimUpdated(state, {
		biomeId = MEADOW,
		claimerUserId = if otherClaimer then 20 else LOCAL_USER_ID,
		claimerName = if otherClaimer then "Alex" else "Arvin",
		progressSeconds = progress,
		durationSeconds = 5,
		status = status,
		interruptReason = reason,
	})
end

local function optInState(): State
	local state = ArenaHUDViewModel.new(LOCAL_USER_ID)
	ArenaHUDViewModel.setActiveBiome(state, MEADOW, false)
	publishOptIn(state, MEADOW, 15)
	return state
end

local function scrambleState(inLockedRoom: boolean): State
	local state = ArenaHUDViewModel.new(LOCAL_USER_ID)
	ArenaHUDViewModel.setActiveBiome(state, MEADOW, inLockedRoom)
	publishPhase(state, MEADOW, "PvP_EggScramble", 0)
	return state
end

local function expectIntent(key: string, expected: string | boolean, ...: unknown)
	local result = table.pack(...)
	assert(result.n == 2 and result[1] == true, "expected success and exactly one payload argument")
	local payload = result[2]
	assert(type(payload) == "table", "intent payload must be a table")
	local firstKey, firstValue = next(payload)
	assert(firstKey == key and firstValue == expected, `expected payload field {key} = {expected}`)
	assert(next(payload, key) == nil, "intent payload should contain only the canonical field")
end

local function expectRejectedIntent(ok: boolean, payload: unknown)
	assert(not ok and payload == nil, "disallowed intent should have no payload")
end

-- Cases 1–3
run("A fresh HUD starts in Hub with its modal, claim ring, and alert hidden", function()
	local display = ArenaHUDViewModel.getDisplay(ArenaHUDViewModel.new(LOCAL_USER_ID))
	assert(display.activeBiomeId == nil and display.activeModal == "None", "initial Hub context")
	assert(
		display.banner.phase == "Hub" and display.banner.accentTone == "Safe",
		"initial Hub banner"
	)
	assert(
		not display.optInModal.visible and not display.optInModal.showQueuedPill,
		"initial modal"
	)
	assert(
		not display.claimRing.visible and display.claimRing.status == "Idle",
		"initial claim ring"
	)
	assert(not display.overchargedAlert.visible, "initial Overcharged alert")
end)

run("Countdown formatting rounds upward and sanitizes invalid times", function()
	for _, example in
		{
			{ seconds = 90, text = "01:30" },
			{ seconds = 300, text = "05:00" },
			{ seconds = 59.1, text = "01:00" },
			{ seconds = 59, text = "0:59" },
			{ seconds = 0.2, text = "0:01" },
			{ seconds = 0, text = "0:00" },
			{ seconds = -5, text = "0:00" },
			{ seconds = 0 / 0, text = "0:00" },
			{ seconds = math.huge, text = "0:00" },
		}
	do
		assert(
			ArenaHUDViewModel.formatCountdown(example.seconds) == example.text,
			`countdown for {example.seconds}`
		)
	end
	assert(ArenaHUDViewModel.formatShortSeconds(15) == "15s", "whole seconds on the opt-in badge")
	assert(ArenaHUDViewModel.formatShortSeconds(1) == "1s", "singular second on the badge")
	assert(ArenaHUDViewModel.formatShortSeconds(0) == "0s", "expired badge")
end)

run("Power numbers use compact thousands and millions formatting", function()
	assert(ArenaHUDViewModel.formatNumber(420) == "420", "plain power")
	assert(ArenaHUDViewModel.formatNumber(1_500) == "1.5K", "thousands")
	assert(ArenaHUDViewModel.formatNumber(1_250_000) == "1.25M", "millions")
end)

run("The PvE banner counts down locally from the last server snapshot", function()
	local state = ArenaHUDViewModel.new(LOCAL_USER_ID)
	ArenaHUDViewModel.setActiveBiome(state, MEADOW, false)
	publishPhase(state, MEADOW, "PvE_Open", 90, { pvePlayerCount = 4 })
	local banner = ArenaHUDViewModel.getDisplay(state).banner
	assert(banner.visible and banner.biomeName == "Emerald Meadow", "active biome banner")
	assert(banner.phase == "PvE_Open" and banner.accentTone == "Safe", "PvE banner tone")
	assert(banner.countdownText == "01:30", "phase countdown from server")
	assert(not banner.showBossHpBar and not banner.showSuddenDeathWarning, "PvE-only indicators")
	ArenaHUDViewModel.step(state, 15.5)
	assert(ArenaHUDViewModel.getDisplay(state).banner.countdownText == "01:15", "local countdown")
end)

-- Cases 4–6
run("Another biome updates its portal without taking over the active HUD", function()
	local state = ArenaHUDViewModel.new(LOCAL_USER_ID)
	ArenaHUDViewModel.setActiveBiome(state, MEADOW, false)
	publishPhase(state, MEADOW, "PvE_Open", 90)
	publishPhase(state, FROSTBITE, "PvE_Open", 72, { pvePlayerCount = 6 })
	local portal = ArenaHUDViewModel.getPortalDisplay(state, FROSTBITE, 150)
	assert(
		portal.timerLabel == "Boss Opt-In: 01:12" and portal.playerCountText == "6 in PvE",
		"remote biome snapshot"
	)
	local display = ArenaHUDViewModel.getDisplay(state)
	assert(
		display.banner.biomeId == MEADOW and not display.optInModal.visible,
		"foreign phase is isolated"
	)
	publishOptIn(state, FROSTBITE, 15, { recommendedDamage = 150 })
	portal = ArenaHUDViewModel.getPortalDisplay(state, FROSTBITE, 150)
	assert(portal.timerLabel == "OPT-IN LIVE! 0:15", "remote opt-in updates its portal")
	display = ArenaHUDViewModel.getDisplay(state)
	assert(
		display.banner.biomeId == MEADOW and display.activeModal == "None",
		"foreign opt-in is isolated"
	)
	assert(not display.optInModal.visible, "another biome does not show a modal")
end)

run("The Hub keeps biome portal updates while hiding the opt-in modal and claim ring", function()
	local state = scrambleState(true)
	publishClaim(state, "Claiming", 2)
	assert(ArenaHUDViewModel.getDisplay(state).claimRing.visible, "claim visible before leaving")
	ArenaHUDViewModel.setActiveBiome(state, nil)
	publishPhase(state, MEADOW, "PvE_Open", 90, { pvePlayerCount = 4 })
	publishOptIn(state, MEADOW, 15)
	local display = ArenaHUDViewModel.getDisplay(state)
	assert(display.activeBiomeId == nil and display.banner.phase == "Hub", "Hub context")
	assert(display.activeModal == "None" and not display.optInModal.visible, "no Hub modal")
	assert(
		not display.claimRing.visible and not display.claimRing.showHoldPromptButton,
		"no Hub claim controls"
	)
	local portal = ArenaHUDViewModel.getPortalDisplay(state, MEADOW, 15)
	assert(portal.timerLabel == "OPT-IN LIVE! 0:15", "Hub portal still shows opt-in")
	assert(portal.playerCountText == "4 in PvE", "Hub portal keeps the biome population")
end)

run("A local opt-in prompt shows its 15-second timer, queue, and power details", function()
	local state = optInState()
	local display = ArenaHUDViewModel.getDisplay(state)
	local modal = display.optInModal
	assert(
		display.activeModal == "OptIn" and modal.visible and not modal.showQueuedPill,
		"opt-in modal"
	)
	assert(modal.biomeId == MEADOW and not modal.isOvercharged, "standard Meadow opt-in")
	assert(modal.countdownText == "15s" and modal.secondsRemaining == 15, "initial timer")
	assert(modal.queuedPlayers == 3 and modal.queuedText == "3 Fighters Queued", "queue summary")
	assert(string.find(modal.highestPowerText, "420", 1, true), "highest power")
	assert(string.find(modal.recommendedText, "15", 1, true), "recommended damage")

	ArenaHUDViewModel.step(state, 3)
	expectNear(
		ArenaHUDViewModel.getDisplay(state).optInModal.secondsRemaining,
		12,
		"local opt-in clock"
	)
	publishOptIn(state, MEADOW, 11, { queuedPlayers = 1, highestPowerRating = 0 })
	modal = ArenaHUDViewModel.getDisplay(state).optInModal
	assert(modal.secondsRemaining == 11 and modal.countdownText == "11s", "server clock resync")
	assert(modal.queuedText == "1 Fighter Queued", "singular queue summary")
	assert(string.find(modal.highestPowerText, "--", 1, true), "unknown power fallback")
end)

-- Cases 7–9. The contract decision in section 2 supersedes the older positional intents.
run("Joining sends only accepted true and later updates keep the queued pill", function()
	local state = optInState()
	expectIntent("accepted", true, ArenaHUDViewModel.buildOptInIntent(state, true))
	local display = ArenaHUDViewModel.getDisplay(state)
	assert(
		display.activeModal == "QueuedPill" and not display.optInModal.visible,
		"join closes the full modal"
	)
	assert(
		display.optInModal.showQueuedPill and display.optInModal.isLocalQueued,
		"local queue status"
	)
	publishOptIn(state, MEADOW, 14, { queuedPlayers = 4 })
	display = ArenaHUDViewModel.getDisplay(state)
	assert(
		display.activeModal == "QueuedPill" and not display.optInModal.visible,
		"refresh keeps the pill"
	)
	assert(
		display.optInModal.showQueuedPill and display.optInModal.queuedPlayers == 4,
		"queue refresh"
	)
end)

run("Declining sends only accepted false and suppresses reopening until a new window", function()
	local state = optInState()
	expectIntent("accepted", false, ArenaHUDViewModel.buildOptInIntent(state, false))
	local display = ArenaHUDViewModel.getDisplay(state)
	assert(display.activeModal == "None", "decline closes modal")
	assert(
		not display.optInModal.visible and not display.optInModal.showQueuedPill,
		"no modal or pill after decline"
	)
	publishOptIn(state, MEADOW, 14, { queuedPlayers = 4 })
	assert(ArenaHUDViewModel.getDisplay(state).activeModal == "None", "same window stays dismissed")

	publishPhase(state, MEADOW, "PvE_Open", 90)
	publishOptIn(state, MEADOW, 15)
	display = ArenaHUDViewModel.getDisplay(state)
	assert(display.activeModal == "OptIn" and display.optInModal.visible, "new window opens")
	expectIntent("accepted", true, ArenaHUDViewModel.buildOptInIntent(state, true))
	expectIntent("accepted", false, ArenaHUDViewModel.buildOptInIntent(state, false))
	assert(
		ArenaHUDViewModel.getDisplay(state).activeModal == "None",
		"leaving the queue hides its pill"
	)
end)

run("Opt-in expires locally and rejects joins after expiry or outside the window", function()
	local state = optInState()
	ArenaHUDViewModel.step(state, 15)
	local display = ArenaHUDViewModel.getDisplay(state)
	assert(
		display.activeModal == "None" and not display.optInModal.visible,
		"close at the exact deadline"
	)
	assert(display.optInModal.secondsRemaining == 0, "expired modal clock stays at zero")
	expectRejectedIntent(ArenaHUDViewModel.buildOptInIntent(state, true))
	publishPhase(state, MEADOW, "PvE_Open", 90)
	expectRejectedIntent(ArenaHUDViewModel.buildOptInIntent(state, true))
	ArenaHUDViewModel.setActiveBiome(state, nil)
	expectRejectedIntent(ArenaHUDViewModel.buildOptInIntent(state, true))
end)

run("The locked room suppresses opt-in and entering the boss phase clears the queue", function()
	local state = ArenaHUDViewModel.new(LOCAL_USER_ID)
	ArenaHUDViewModel.setActiveBiome(state, MEADOW, true)
	publishOptIn(state, MEADOW, 15)
	assert(
		ArenaHUDViewModel.getDisplay(state).activeModal == "None",
		"no modal inside a locked room"
	)

	state = optInState()
	expectIntent("accepted", true, ArenaHUDViewModel.buildOptInIntent(state, true))
	publishPhase(state, MEADOW, "Boss_Phase", 180)
	local display = ArenaHUDViewModel.getDisplay(state)
	assert(
		display.activeModal == "None" and not display.optInModal.isLocalQueued,
		"boss phase clears local queue"
	)
	assert(
		not display.optInModal.showQueuedPill and not display.optInModal.visible,
		"no opt-in controls in boss phase"
	)
	publishPhase(state, MEADOW, "PvE_Open", 90)
	publishOptIn(state, MEADOW, 15)
	assert(
		ArenaHUDViewModel.getDisplay(state).activeModal == "OptIn",
		"queue does not persist into the next cycle"
	)
end)

-- Cases 10–11
run("Boss HP is optional, formatted when present, and clamped to the bar bounds", function()
	local state = ArenaHUDViewModel.new(LOCAL_USER_ID)
	ArenaHUDViewModel.setActiveBiome(state, MEADOW, true)
	publishPhase(state, MEADOW, "Boss_Phase", 180)
	local banner = ArenaHUDViewModel.getDisplay(state).banner
	assert(banner.accentTone == "Boss" and not banner.showBossHpBar, "missing boss HP is safe")
	assert(banner.bossHpRatio >= 0 and banner.bossHpRatio <= 1, "missing HP ratio is finite")

	publishPhase(state, MEADOW, "Boss_Phase", 160, { bossHp = 780, bossMaxHp = 1_560 })
	banner = ArenaHUDViewModel.getDisplay(state).banner
	assert(banner.showBossHpBar and banner.bossHpRatio == 0.5, "half-full boss health bar")
	local normalizedText = string.gsub(banner.bossHpText, ",", "")
	assert(string.find(normalizedText, "780 / 1560", 1, true), "current and maximum HP label")
	publishPhase(state, MEADOW, "Boss_Phase", 159, { bossHp = -10, bossMaxHp = 1_560 })
	assert(ArenaHUDViewModel.getDisplay(state).banner.bossHpRatio == 0, "negative HP is clamped")
	publishPhase(state, MEADOW, "Boss_Phase", 158, { bossHp = 9_999, bossMaxHp = 1_560 })
	assert(ArenaHUDViewModel.getDisplay(state).banner.bossHpRatio == 1, "overflow HP is clamped")
	publishPhase(state, MEADOW, "Boss_Phase", 157, { bossHp = 780, bossMaxHp = 0 })
	assert(
		not ArenaHUDViewModel.getDisplay(state).banner.showBossHpBar,
		"zero max HP hides the bar"
	)
end)

run("The scramble shows hold controls only in the room and flags sudden death", function()
	local state = scrambleState(true)
	local display = ArenaHUDViewModel.getDisplay(state)
	assert(
		display.banner.accentTone == "PvP" and not display.banner.showSuddenDeathWarning,
		"base PvP banner"
	)
	assert(display.claimRing.showHoldPromptButton, "in-room player can hold to claim")
	ArenaHUDViewModel.setActiveBiome(state, MEADOW, false)
	assert(
		not ArenaHUDViewModel.getDisplay(state).claimRing.showHoldPromptButton,
		"PvE bystander has no hold button"
	)

	publishPhase(state, MEADOW, "PvP_EggScramble", 0, { suddenDeathActive = true })
	local banner = ArenaHUDViewModel.getDisplay(state).banner
	assert(banner.accentTone == "SuddenDeath" and banner.showSuddenDeathWarning, "storm warning")
	assert(banner.suddenDeathText ~= "", "storm warning has a label")
end)

-- Cases 12–13
run("One live claim event drives a five-second ring without further packets", function()
	local state = scrambleState(true)
	publishClaim(state, "Claiming", 0)
	local ring = ArenaHUDViewModel.getDisplay(state).claimRing
	assert(
		ring.visible and ring.status == "Claiming" and ring.isLocalClaimer,
		"local claim is visible"
	)
	assert(ring.progressRatio == 0 and ring.durationSeconds == 5, "live start has zero progress")

	ArenaHUDViewModel.step(state, 2.5)
	ring = ArenaHUDViewModel.getDisplay(state).claimRing
	assert(ring.progressSeconds == 2.5 and ring.progressRatio == 0.5, "halfway through the hold")
	assert(ring.countdownText == "2.5s", "fractional countdown")
	ArenaHUDViewModel.step(state, 3)
	ring = ArenaHUDViewModel.getDisplay(state).claimRing
	assert(ring.progressSeconds == 5 and ring.progressRatio == 1, "progress caps at duration")
	assert(ring.countdownText == "0.0s" and ring.status == "Claiming", "wait for server completion")
end)

run("Mock claim updates synchronize without advancing twice or rewinding", function()
	local state = scrambleState(true)
	publishClaim(state, "Claiming", 0)
	for _, progress in { 0.5, 1, 1.5 } do
		ArenaHUDViewModel.step(state, 0.5)
		publishClaim(state, "Claiming", progress)
		expectNear(
			ArenaHUDViewModel.getDisplay(state).claimRing.progressSeconds,
			progress,
			"mock and local clocks agree"
		)
	end
	publishClaim(state, "Claiming", 1)
	expectNear(
		ArenaHUDViewModel.getDisplay(state).claimRing.progressSeconds,
		1.5,
		"ignore a late older update"
	)
	publishClaim(state, "Claiming", 2)
	expectNear(
		ArenaHUDViewModel.getDisplay(state).claimRing.progressSeconds,
		2,
		"accept newer progress"
	)

	publishClaim(state, "Claiming", 0.25, nil, true)
	local ring = ArenaHUDViewModel.getDisplay(state).claimRing
	expectNear(ring.progressSeconds, 0.25, "a new claimer starts their own clock")
	assert(
		not ring.isLocalClaimer and string.find(ring.claimerLabel, "Alex", 1, true),
		"remote claimer label"
	)
end)

-- Cases 14–15
run("Damage resets claim progress and shows the interruption flash for 0.85 seconds", function()
	local state = scrambleState(true)
	publishClaim(state, "Claiming", 0)
	ArenaHUDViewModel.step(state, 3.5)
	expectNear(
		ArenaHUDViewModel.getDisplay(state).claimRing.progressRatio,
		0.7,
		"progress before damage"
	)
	publishClaim(state, "Interrupted", 0, "Damage")
	local ring = ArenaHUDViewModel.getDisplay(state).claimRing
	assert(
		ring.progressRatio == 0 and ring.progressSeconds == 0,
		"damage resets progress immediately"
	)
	assert(
		ring.visible and ring.flashInterrupt and ring.status == "Interrupted",
		"interruption flash"
	)
	assert(ring.interruptReasonText == "INTERRUPTED BY DAMAGE!", "damage reason text")
	ArenaHUDViewModel.step(state, 0.8)
	assert(
		ArenaHUDViewModel.getDisplay(state).claimRing.flashInterrupt,
		"flash remains before expiry"
	)
	ArenaHUDViewModel.step(state, 0.1)
	ring = ArenaHUDViewModel.getDisplay(state).claimRing
	assert(
		not ring.flashInterrupt and not ring.visible and ring.status == "Idle",
		"flash clears by 0.9s"
	)
end)

run("Live and mock interruption reasons map to the same radius warning", function()
	local state = scrambleState(true)
	for _, reason in { "LeftRadius", "PlayerMoved" } do
		publishClaim(state, "Claiming", 2)
		publishClaim(state, "Interrupted", 0, reason)
		local ring = ArenaHUDViewModel.getDisplay(state).claimRing
		assert(ring.interruptReasonText == "LEFT CLAIM RADIUS!", `display reason for {reason}`)
		assert(ring.progressRatio == 0 and ring.flashInterrupt, `reset progress for {reason}`)
		ArenaHUDViewModel.step(state, 0.9)
	end
	assert(
		ArenaHUDViewModel.formatInterruptReason("Eliminated") == "ELIMINATED!",
		"elimination label"
	)
	assert(
		ArenaHUDViewModel.formatInterruptReason("Disconnected") == "CLAIMER DISCONNECTED",
		"disconnect label"
	)
	assert(
		ArenaHUDViewModel.formatInterruptReason("ManualCancel") == "CLAIM CANCELLED",
		"manual cancel label"
	)
	assert(
		ArenaHUDViewModel.formatInterruptReason(nil) == "CLAIM INTERRUPTED!",
		"missing reason fallback"
	)
	assert(
		ArenaHUDViewModel.formatInterruptReason("Unknown") == "CLAIM INTERRUPTED!",
		"unknown reason fallback"
	)
end)

run(
	"Live zero-progress and mock full-progress completions both hold a full ring for 1.5 seconds",
	function()
		for _, reportedProgress in { 0, 5 } do
			local state = scrambleState(true)
			publishClaim(state, "Claiming", 2.5)
			publishClaim(state, "Completed", reportedProgress)
			local ring = ArenaHUDViewModel.getDisplay(state).claimRing
			assert(ring.status == "Completed" and ring.visible, "show successful claim")
			assert(
				ring.progressRatio == 1 and ring.progressSeconds == 5,
				"completion fills the ring"
			)
			assert(ring.countdownText == "CLAIMED!", "celebration label")
			ArenaHUDViewModel.step(state, 1.4)
			assert(
				ArenaHUDViewModel.getDisplay(state).claimRing.visible,
				"celebration persists before 1.5s"
			)
			ArenaHUDViewModel.step(state, 0.2)
			ring = ArenaHUDViewModel.getDisplay(state).claimRing
			assert(ring.status == "Idle" and not ring.visible, "celebration clears by 1.6s")
		end
	end
)

-- Case 16. Canonical actions are strings inside a single payload table.
run("Starting a claim sends only action Start and requires the active scramble room", function()
	local state = scrambleState(true)
	expectIntent("action", "Start", ArenaHUDViewModel.buildClaimEggIntent(state, true))
	ArenaHUDViewModel.setActiveBiome(state, MEADOW, false)
	expectRejectedIntent(ArenaHUDViewModel.buildClaimEggIntent(state, true))
	ArenaHUDViewModel.setActiveBiome(state, MEADOW, true)
	publishPhase(state, MEADOW, "Boss_Phase", 180)
	expectRejectedIntent(ArenaHUDViewModel.buildClaimEggIntent(state, true))
	ArenaHUDViewModel.setActiveBiome(state, nil)
	expectRejectedIntent(ArenaHUDViewModel.buildClaimEggIntent(state, true))
end)

run("Releasing sends only action Cancel even after leaving the room or changing phase", function()
	local state = scrambleState(true)
	expectIntent("action", "Cancel", ArenaHUDViewModel.buildClaimEggIntent(state, false))
	ArenaHUDViewModel.setActiveBiome(state, MEADOW, false)
	expectIntent("action", "Cancel", ArenaHUDViewModel.buildClaimEggIntent(state, false))
	publishPhase(state, MEADOW, "PvE_Open", 90)
	expectIntent("action", "Cancel", ArenaHUDViewModel.buildClaimEggIntent(state, false))
	ArenaHUDViewModel.setActiveBiome(state, nil)
	expectIntent("action", "Cancel", ArenaHUDViewModel.buildClaimEggIntent(state, false))
end)

run("Leaving the scramble phase clears a live claim and its hold prompt", function()
	local state = scrambleState(true)
	publishClaim(state, "Claiming", 2)
	assert(ArenaHUDViewModel.getDisplay(state).claimRing.visible, "claim visible during scramble")
	publishPhase(state, MEADOW, "PvE_Open", 90)
	local ring = ArenaHUDViewModel.getDisplay(state).claimRing
	assert(
		ring.status == "Idle" and not ring.visible and not ring.showHoldPromptButton,
		"claim cleared after phase change"
	)
end)

-- Cases 17–18
run(
	"An Overcharged biome shows a six-second global alert and a local Overcharged accent",
	function()
		local state = ArenaHUDViewModel.new(LOCAL_USER_ID)
		publishPhase(state, FROSTBITE, "OptIn_Window", 15, { isOvercharged = true })
		local display = ArenaHUDViewModel.getDisplay(state)
		assert(
			display.banner.phase == "Hub" and display.overchargedAlert.visible,
			"alert reaches Hub"
		)
		assert(display.overchargedAlert.remainingSeconds == 6, "six-second global alert")

		ArenaHUDViewModel.setActiveBiome(state, FROSTBITE, false)
		publishOptIn(state, FROSTBITE, 15, { isOvercharged = true, recommendedDamage = 150 })
		display = ArenaHUDViewModel.getDisplay(state)
		assert(
			display.optInModal.visible and display.optInModal.isOvercharged,
			"local Overcharged modal"
		)
		assert(display.banner.accentTone == "Overcharged", "local Overcharged banner accent")
		ArenaHUDViewModel.step(state, 6.1)
		assert(
			not ArenaHUDViewModel.getDisplay(state).overchargedAlert.visible,
			"expired Overcharged alert"
		)

		publishPhase(state, FROSTBITE, "OptIn_Window", 8, { isOvercharged = true })
		assert(
			not ArenaHUDViewModel.getDisplay(state).overchargedAlert.visible,
			"same cycle does not re-alert"
		)
		publishPhase(state, FROSTBITE, "PvE_Open", 90)
		publishPhase(state, FROSTBITE, "OptIn_Window", 15, { isOvercharged = true })
		assert(
			ArenaHUDViewModel.getDisplay(state).overchargedAlert.visible,
			"next Overcharged cycle alerts again"
		)
	end
)

run(
	"Hub portals format each biome phase and keep disabled update portals marked coming soon",
	function()
		local state = ArenaHUDViewModel.new(LOCAL_USER_ID)
		publishPhase(state, MEADOW, "PvE_Open", 90)
		publishOptIn(state, FROSTBITE, 15, { isOvercharged = true, recommendedDamage = 150 })
		publishPhase(state, CALDERA, "Boss_Phase", 180, { pvePlayerCount = 5 })

		local meadow = ArenaHUDViewModel.getPortalDisplay(state, MEADOW, 15)
		assert(meadow.biomeName == "Emerald Meadow" and meadow.enabled, "available Meadow portal")
		assert(
			meadow.recommendedText == "Rec. 15 DMG" and meadow.playerCountText == "3 in PvE",
			"Meadow portal details"
		)
		assert(
			meadow.timerLabel == "Boss Opt-In: 01:30" and not meadow.isOvercharged,
			"Meadow PvE timer"
		)
		local frostbite = ArenaHUDViewModel.getPortalDisplay(state, FROSTBITE, 150)
		assert(
			frostbite.timerLabel == "OPT-IN LIVE! 0:15" and frostbite.isOvercharged,
			"Frostbite Overcharged opt-in"
		)
		assert(
			frostbite.biomeName == "Frostbite Cavern" and frostbite.recommendedDamage == 150,
			"Frostbite portal details"
		)
		local caldera = ArenaHUDViewModel.getPortalDisplay(state, CALDERA, 1_200)
		assert(
			caldera.timerLabel == "BOSS IN PROGRESS" and caldera.playerCountText == "5 in PvE",
			"Caldera boss portal"
		)
		publishPhase(state, CALDERA, "PvP_EggScramble", 0)
		assert(
			ArenaHUDViewModel.getPortalDisplay(state, CALDERA, 1_200).timerLabel == "PvP SCRAMBLE",
			"Caldera scramble portal"
		)

		for _, biomeId in { "StormRuins", "VoidCitadel" } do
			local portal = ArenaHUDViewModel.getPortalDisplay(state, biomeId, 0, false)
			assert(
				not portal.enabled and portal.timerLabel == "COMING SOON",
				`disabled portal for {biomeId}`
			)
		end
	end
)

-- Cases 19–20
run("Power badges change at tier boundaries and format optional Ascension crests", function()
	for _, example in
		{
			{ power = 0, tier = "Rookie" },
			{ power = 49, tier = "Rookie" },
			{ power = 50, tier = "Brawler" },
			{ power = 249, tier = "Brawler" },
			{ power = 250, tier = "Champion" },
			{ power = 1_499, tier = "Champion" },
			{ power = 1_500, tier = "Titan" },
			{ power = 9_999, tier = "Titan" },
			{ power = 10_000, tier = "Mythic" },
		}
	do
		assert(
			ArenaHUDViewModel.formatPowerBadge(example.power).tierName == example.tier,
			`tier for {example.power}`
		)
	end
	for _, invalid in { -1, 0 / 0 } do
		local badge = ArenaHUDViewModel.formatPowerBadge(invalid)
		assert(
			badge.powerText == "0" and badge.tierName == "Rookie",
			"invalid power clamps to Rookie"
		)
	end
	assert(
		ArenaHUDViewModel.formatPowerBadge(420, 0).ascensionText == nil,
		"rank zero has no crest"
	)
	local badge = ArenaHUDViewModel.formatPowerBadge(1_500, 3)
	assert(
		badge.powerText == "1.5K" and badge.ascensionText == "★3",
		"compact power and Ascension crest"
	)
	assert(
		ArenaHUDViewModel.formatPowerBadge(420, 3.9).ascensionText == "★3",
		"fractional rank is floored"
	)
end)

run("Malformed network payloads and invalid deltas preserve current HUD state", function()
	local state = scrambleState(true)
	publishClaim(state, "Claiming", 2)
	publishPhase(state, FROSTBITE, "OptIn_Window", 15, { isOvercharged = true })
	publishOptIn(state, FROSTBITE, 15, { isOvercharged = true, recommendedDamage = 150 })

	for _, reducer in
		{
			ArenaHUDViewModel.onArenaStateChanged,
			ArenaHUDViewModel.onOptInPrompt,
			ArenaHUDViewModel.onEggClaimUpdated,
		}
	do
		reducer(state, nil)
		reducer(state, "bad payload")
		reducer(state, {})
	end
	for _, dt in { 0, -1, 0 / 0, math.huge } do
		ArenaHUDViewModel.step(state, dt)
	end

	local display = ArenaHUDViewModel.getDisplay(state)
	assert(
		display.activeBiomeId == MEADOW and display.activeModal == "None",
		"active biome and modal stay intact"
	)
	assert(
		display.banner.phase == "PvP_EggScramble" and display.banner.accentTone == "PvP",
		"banner survives malformed updates"
	)
	assert(
		display.claimRing.status == "Claiming" and display.claimRing.progressSeconds == 2,
		"claim clock is unchanged"
	)
	assert(
		display.overchargedAlert.visible and display.overchargedAlert.remainingSeconds == 6,
		"alert timer is unchanged"
	)
	local portal = ArenaHUDViewModel.getPortalDisplay(state, FROSTBITE, 150)
	assert(portal.timerLabel == "OPT-IN LIVE! 0:15", "foreign biome countdown is unchanged")
end)

print("PASS: ArenaHUDViewModel.spec.luau")
