--!strict
--[[
	CombatJuiceLogic.spec.luau
	Unit tests for pure Luau combat feedback math & formatting:
	- RGB sanitization and clamping
	- Critical threshold calculation & crit promotion rules
	- 3D floating popup formatting across all event kinds & custom labels/accents
	- Quadratic camera trauma accumulation, capping, dt clamping & smooth decay
	- Win-streak Halo / Flame Crown tier thresholds
	- Corner Kill / EggClaim / StreakUpdate feed formatting, TTL pruning & FIFO cap
]]

local CombatJuiceLogic = require("../src/shared/Utils/CombatJuiceLogic")

local function run(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	assert(ok, `{name}: {err}`)
end

run("sanitizeRgb clamps, rounds and falls back on malformed inputs", function()
	local fb = { 10, 20, 30 }
	local ok = CombatJuiceLogic.sanitizeRgb({ -5, 127.6, 999 }, fb)
	assert(ok[1] == 0 and ok[2] == 128 and ok[3] == 255, "clamped and rounded")
	assert(CombatJuiceLogic.sanitizeRgb(nil, fb) == fb, "nil -> fallback")
	assert(CombatJuiceLogic.sanitizeRgb({ 10, 20 }, fb) == fb, "short table -> fallback")
	assert(CombatJuiceLogic.sanitizeRgb({ 0 / 0, 20, 30 }, fb) == fb, "NaN -> fallback")
	assert(CombatJuiceLogic.sanitizeRgb({ math.huge, 20, 30 }, fb) == fb, "inf -> fallback")
	assert(CombatJuiceLogic.sanitizeRgb({ "10", 20, 30 }, fb) == fb, "non-number -> fallback")
end)

run("Crit threshold and critical hit evaluation rules", function()
	assert(CombatJuiceLogic.computeCritThreshold(100) == 155, "100 * 1.55 = 155")
	assert(CombatJuiceLogic.computeCritThreshold(0.1) == 1, "tiny positive floors at 1")
	assert(CombatJuiceLogic.computeCritThreshold(nil) == 150, "nil -> default 150")
	assert(CombatJuiceLogic.computeCritThreshold(0) == 150, "0 -> default 150")
	assert(CombatJuiceLogic.computeCritThreshold(-25) == 150, "negative -> default 150")
	assert(CombatJuiceLogic.computeCritThreshold(0 / 0) == 150, "NaN -> default 150")

	assert(CombatJuiceLogic.isCriticalHit("Crit", nil, 999), "explicit Crit always true")
	assert(CombatJuiceLogic.isCriticalHit("Damage", 150, nil), "Damage == default 150 is crit")
	assert(not CombatJuiceLogic.isCriticalHit("Damage", 149.9, nil), "Damage < 150 not crit")
	assert(CombatJuiceLogic.isCriticalHit("BossHit", 200, 180), "BossHit >= custom threshold")
	assert(not CombatJuiceLogic.isCriticalHit("Coins", 9999, 10), "Coins never crits")
	assert(not CombatJuiceLogic.isCriticalHit("Kill", 9999, 10), "Kill never crits")
	assert(not CombatJuiceLogic.isCriticalHit("Damage", 0 / 0, 10), "NaN amount never crits")
	assert(CombatJuiceLogic.isCriticalHit("Damage", 150, -5), "invalid threshold falls back to 150")
end)

run("Floating popup formatting for all event kinds, starbursts and crit overrides", function()
	local dmg = CombatJuiceLogic.formatPopup({ kind = "Damage", amount = 42 }, 150)
	assert(dmg.text == "-42" and not dmg.isStarburst and dmg.scale == 1.0, "standard damage popup")

	local critAuto =
		CombatJuiceLogic.formatPopup({ kind = "Damage", amount = 1500, accent = { 1, 2, 3 } }, 150)
	assert(critAuto.text == "CRIT! -1.5K" and critAuto.isStarburst, "auto-promoted crit popup")
	assert(critAuto.scale == 1.45 and critAuto.riseStuds == 5.4 and critAuto.duration == 0.85)
	assert(critAuto.color[1] == 255 and critAuto.color[2] == 222 and critAuto.color[3] == 68)
	assert(critAuto.strokeColor[1] == 96, "crit stroke color")

	local coins = CombatJuiceLogic.formatPopup({ kind = "Coins", amount = 2500000 })
	assert(coins.text == "+2.50M Coins" and coins.scale == 1.12 and not coins.isStarburst)

	local gems = CombatJuiceLogic.formatPopup({ kind = "Gem", amount = 12 })
	assert(gems.text == "+12 Gems" and gems.scale == 1.16)

	local bossHit = CombatJuiceLogic.formatPopup({ kind = "BossHit", amount = 80 }, 200)
	assert(bossHit.text == "-80" and bossHit.scale == 1.16 and not bossHit.isStarburst)

	local bossNoAmt = CombatJuiceLogic.formatPopup({ kind = "BossHit" })
	assert(bossNoAmt.text == "BOSS HIT!", "BossHit without amount")

	local kill = CombatJuiceLogic.formatPopup({ kind = "Kill" })
	assert(kill.text == "KO!" and kill.isStarburst and kill.scale == 1.32 and kill.duration == 0.90)

	local claim = CombatJuiceLogic.formatPopup({ kind = "EggClaim", label = "MYTHIC CLAIM!" })
	assert(claim.text == "MYTHIC CLAIM!" and claim.isStarburst and claim.scale == 1.32)

	local malformed = CombatJuiceLogic.formatPopup(nil)
	assert(malformed.text == "HIT!" and malformed.scale == 1.0, "nil payload defaults safely")
end)

run("Camera trauma impulses, capping, disabled toggle, dt clamping and quadratic decay", function()
	assert(CombatJuiceLogic.getTraumaImpulseForEvent("Crit") == 0.40, "Crit impulse")
	assert(CombatJuiceLogic.getTraumaImpulseForEvent("Damage") == 0.14, "Damage impulse")
	assert(CombatJuiceLogic.getTraumaImpulseForEvent("Unknown") == 0, "Unknown impulse 0")

	local disabled = CombatJuiceLogic.createTraumaState(false)
	assert(CombatJuiceLogic.addTrauma(disabled, 0.5) == 0, "disabled ignores addTrauma")
	local zeroSample = CombatJuiceLogic.stepTrauma(disabled, 0.016, 1.0)
	assert(zeroSample.intensity == 0 and zeroSample.offsetX == 0 and zeroSample.rollRad == 0)

	local st = CombatJuiceLogic.createTraumaState()
	assert(st.enabled and st.trauma == 0, "defaults enabled at 0")
	assert(CombatJuiceLogic.addTrauma(st, -1) == 0, "negative ignored")
	assert(CombatJuiceLogic.addTrauma(st, 0 / 0) == 0, "NaN ignored")
	assert(CombatJuiceLogic.addTrauma(st, 5.0) == CombatJuiceLogic.MAX_TRAUMA_CAP, "capped 0.72")

	-- Huge lag dt=5.0 must clamp to 0.1s decay (0.72 - 0.28 = 0.44).
	local sample = CombatJuiceLogic.stepTrauma(st, 5.0, 1.25)
	assert(math.abs(st.trauma - 0.44) < 1e-6, "dt clamped to 0.1s")
	assert(math.abs(sample.intensity - 0.44 * 0.44) < 1e-6, "quadratic intensity")
	assert(math.abs(sample.offsetX) <= CombatJuiceLogic.MAX_OFFSET_STUDS * sample.intensity + 1e-6)
	assert(math.abs(sample.offsetY) <= CombatJuiceLogic.MAX_OFFSET_STUDS * sample.intensity + 1e-6)
	assert(math.abs(sample.rollRad) <= CombatJuiceLogic.MAX_ROLL_RAD * sample.intensity + 1e-6)

	local negDtSample = CombatJuiceLogic.stepTrauma(st, -1.0, 2.0)
	assert(math.abs(st.trauma - 0.44) < 1e-6 and negDtSample.intensity > 0, "neg dt clamped to 0")

	-- Step until fully decayed to 0.
	for _ = 1, 5 do
		CombatJuiceLogic.stepTrauma(st, 0.1, 3.0)
	end
	local settled = CombatJuiceLogic.stepTrauma(st, 0.1, 3.1)
	assert(st.trauma == 0 and settled.intensity == 0, "decays cleanly to 0")

	st.trauma = 0 / 0
	local healed = CombatJuiceLogic.stepTrauma(st, 0.016, 4.0)
	assert(st.trauma == 0 and healed.intensity == 0, "NaN trauma self-heals")
end)

run("Win-streak Halo and Flame Crown tier boundaries", function()
	for _, bad in ipairs({ nil, "3", -1, 0, 1, 1.9, 0 / 0, math.huge } :: { any }) do
		assert(CombatJuiceLogic.getStreakHaloTier(bad) == nil, "below threshold or invalid -> nil")
	end

	local t1 = CombatJuiceLogic.getStreakHaloTier(2)
	local t1b = CombatJuiceLogic.getStreakHaloTier(3.9)
	assert(t1 ~= nil and t1.tier == 1 and t1.name == "Blaze" and not t1.showCrownSpikes)
	assert(t1b ~= nil and t1b.tier == 1 and t1b.label == "3 WIN STREAK", "floors 3.9 -> 3")

	local t2 = CombatJuiceLogic.getStreakHaloTier(4)
	assert(t2 ~= nil and t2.tier == 2 and t2.name == "Inferno" and t2.showCrownSpikes)
	assert(t2.label == "4x INFERNO" and t2.flameRate == 18 and t2.ringScale == 1.18)

	local t3 = CombatJuiceLogic.getStreakHaloTier(7)
	assert(t3 ~= nil and t3.tier == 3 and t3.name == "MythicCrown" and t3.showCrownSpikes)
	assert(t3.label == "7x APEX STREAK" and t3.flameRate == 26 and t3.ringScale == 1.35)
end)

run("Corner feed formatting, TTL pruning and 3-entry FIFO eviction", function()
	assert(CombatJuiceLogic.formatFeedEntryText(nil) == nil, "nil payload")
	assert(CombatJuiceLogic.formatFeedEntryText({ kind = "Damage" }) == nil, "non-feed kind")
	assert(
		CombatJuiceLogic.formatFeedEntryText({ kind = "Kill", killerName = "A", victimName = "B" })
			== "A KO'd B!"
	)
	assert(
		CombatJuiceLogic.formatFeedEntryText({ kind = "Kill", killerName = "A" })
			== "A scored a KO!"
	)
	assert(CombatJuiceLogic.formatFeedEntryText({ kind = "Kill" }) == "Fighter Knocked Out!")
	assert(
		CombatJuiceLogic.formatFeedEntryText({ kind = "EggClaim", killerName = "A" })
			== "A claimed the Boss Egg!"
	)
	assert(CombatJuiceLogic.formatFeedEntryText({ kind = "EggClaim" }) == "Boss Egg Claimed!")
	assert(CombatJuiceLogic.formatFeedEntryText({ kind = "StreakUpdate", streak = 1 }) == nil)
	assert(CombatJuiceLogic.formatFeedEntryText({ kind = "StreakUpdate", streak = 0 / 0 }) == nil)
	assert(CombatJuiceLogic.formatFeedEntryText({
		kind = "StreakUpdate",
		killerName = "Kai",
		streak = 5,
	}) == "Kai hit a 5x Win Streak!")

	local feed: { CombatJuiceLogic.FeedEntry } = {}
	local nextId = 1
	nextId = CombatJuiceLogic.pushFeedEntry(feed, nextId, "", nil, 10)
	assert(#feed == 0 and nextId == 1, "empty text ignored")
	nextId = CombatJuiceLogic.pushFeedEntry(feed, nextId, "Ignored", nil, 0 / 0)
	assert(#feed == 0 and nextId == 1, "NaN now ignored")

	nextId = CombatJuiceLogic.pushFeedEntry(feed, nextId, "One", { 10, 20, 30 }, 10.0)
	nextId = CombatJuiceLogic.pushFeedEntry(feed, nextId, "Two", nil, 11.0)
	nextId = CombatJuiceLogic.pushFeedEntry(feed, nextId, "Three", nil, 12.0)
	nextId = CombatJuiceLogic.pushFeedEntry(feed, nextId, "Four", nil, 13.0)
	assert(#feed == 3 and feed[1].text == "Two" and feed[3].text == "Four", "FIFO max 3 cap")
	assert(nextId == 5 and feed[3].expiresAt == 17.0, "TTL = now + 4.0")

	assert(not CombatJuiceLogic.pruneFeedEntries(feed, 0 / 0), "NaN prune no-op")
	assert(CombatJuiceLogic.pruneFeedEntries(feed, 15.0), "Two expires at 15.0")
	assert(#feed == 2 and feed[1].text == "Three", "oldest expired entry removed")
	assert(CombatJuiceLogic.pruneFeedEntries(feed, 20.0) and #feed == 0, "all expired pruned")
end)

print("PASS: CombatJuiceLogic.spec.luau")
