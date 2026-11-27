--!strict
--[[
	ViralSocialLogic.spec.luau
	Unit tests for Ball Brawl: Boss Eggs Retention & Viral Social Engine:
	- RetentionConfigs invariants & Day-7 non-Robux Boss Egg compliance
	- Forgiving 7-day cumulative check-in (never resets missed days, wallet/overflow guards)
	- Deterministic 3-quest daily rotation, aliases, bounds & claim idempotency
	- Server-authoritative Friend & PartyId Co-Op bonus (+10%/ally, deduped, +30% cap)
	- Non-verbal Quick-Ping rate limiting & zone/biome/radius routing
	- Win-streak, Overcharged, MythicHatch & VaultExtract announcements + Leaderboards
]]

local EggConfigs = require("../src/shared/Configs/EggConfigs")
local RetentionConfigs = require("../src/shared/Configs/RetentionConfigs")
local ViralSocialLogic = require("../src/shared/Utils/ViralSocialLogic")

local DAY = RetentionConfigs.SECONDS_PER_DAY

local function run(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	assert(ok, `{name}: {err}`)
end

local function makeProfile(): { [string]: any }
	return {
		coins = 100,
		bossGems = 10,
		eggs = {},
	}
end

run("RetentionConfigs invariants and Day-7 earned Boss Egg policy", function()
	assert(#RetentionConfigs.DAILY_REWARDS == 7, "7 daily reward tiers")
	local prevCoins = 0
	for i, r in ipairs(RetentionConfigs.DAILY_REWARDS) do
		assert(r.day == i and r.coins > prevCoins and r.gems > 0, `day {i} monotonic`)
		prevCoins = r.coins
	end
	local day7 = RetentionConfigs.getDailyReward(7)
	assert(day7.eggId ~= nil and day7.eggCount == 1, "day 7 awards Boss Egg")
	assert(EggConfigs.getEgg(day7.eggId :: string) ~= nil, "day 7 egg exists in EggConfigs")
	assert(not EggConfigs.isRobuxPurchasable(day7.eggId :: string), "day 7 egg never Robux")
	assert(RetentionConfigs.getDailyReward(8).day == 1, "day 8 wraps to day 1")
	assert(RetentionConfigs.getDailyReward(0).day == 1, "day 0 clamps to day 1")

	assert(#RetentionConfigs.QUICK_PINGS == 4, "4 non-verbal quick pings")
	assert(RetentionConfigs.getQuickPing("ExtractNow") ~= nil, "valid ping lookup")
	assert(RetentionConfigs.getQuickPing("NonExistent") == nil, "unknown ping nil")
	assert(
		RetentionConfigs.getAnnouncementPreset("UnknownCategory").category == "MythicHatch",
		"unknown announcement preset falls back to MythicHatch"
	)
end)

run("Day number calculation and social profile sanitization", function()
	assert(ViralSocialLogic.getDayNumber(0) == 0, "t=0 -> day 0")
	assert(ViralSocialLogic.getDayNumber(DAY - 1) == 0, "86399 -> day 0")
	assert(ViralSocialLogic.getDayNumber(DAY) == 1, "86400 -> day 1")
	assert(ViralSocialLogic.getDayNumber(-50) == 0, "negative -> 0")
	assert(ViralSocialLogic.getDayNumber(0 / 0) == 0, "NaN -> 0")
	assert(ViralSocialLogic.getDayNumber(math.huge) == 0, "inf -> 0")

	local dirty: any = {
		dailyLoginDay = -3,
		lastDailyClaimDay = 0 / 0,
		winStreak = 5.9,
		bestWinStreak = 2,
		totalBossWins = "bad",
		dailyQuests = "corrupt",
		eggs = nil,
	}
	ViralSocialLogic.ensureSocialProfile(dirty, DAY * 3)
	assert(dirty.dailyLoginDay == 0 and dirty.lastDailyClaimDay == -1, "sanitized daily fields")
	assert(dirty.winStreak == 5 and dirty.bestWinStreak == 5, "bestWinStreak >= winStreak")
	assert(dirty.totalBossWins == 0 and type(dirty.eggs) == "table", "sanitized counters/eggs")
	assert(#dirty.dailyQuests == RetentionConfigs.DAILY_QUEST_COUNT, "initialized 3 daily quests")
	ViralSocialLogic.ensureSocialProfile(nil, DAY)
end)

run("Forgiving 7-day cumulative check-in never resets and guards wallet/overflow", function()
	local p = makeProfile()
	local st0 = ViralSocialLogic.getDailyState(p, 100)
	assert(st0.dailyClaimable and st0.dailyDay == 1 and st0.cumulativeDays == 0, "day 1 ready")

	local c1 = ViralSocialLogic.claimDailyReward(p, 100)
	assert(c1.ok and c1.dayIndex == 1 and p.coins == 250 and p.bossGems == 15, "day 1 claimed")
	local dup = ViralSocialLogic.claimDailyReward(p, 500)
	assert(not dup.ok and dup.reason == "AlreadyClaimedToday", "double claim blocked")

	-- Skip 10 days: streak MUST NOT reset, advances monotonically to Day 2.
	local c2 = ViralSocialLogic.claimDailyReward(p, DAY * 11 + 50)
	assert(c2.ok and c2.dayIndex == 2 and c2.cumulativeDays == 2, "forgiving after 10 missed days")

	for step = 3, 7 do
		local res = ViralSocialLogic.claimDailyReward(p, DAY * (10 + step))
		assert(res.ok and res.dayIndex == step and res.cumulativeDays == step, `day {step} ok`)
	end
	assert(p.eggs.FrostbiteCavern_BossEgg == 1, "day 7 granted FrostbiteCavern_BossEgg")

	local c8 = ViralSocialLogic.claimDailyReward(p, DAY * 20)
	assert(c8.ok and c8.dayIndex == 1 and c8.cumulativeDays == 8, "day 8 wraps to tier 1")

	assert(ViralSocialLogic.claimDailyReward(nil, DAY).reason == "InvalidArgs", "nil profile")
	assert(ViralSocialLogic.claimDailyReward(p, -1).reason == "InvalidArgs", "negative now")
	assert(ViralSocialLogic.claimDailyReward(p, 0 / 0).reason == "InvalidArgs", "NaN now")

	local badWallet: any = { coins = -1, bossGems = 5 }
	assert(ViralSocialLogic.claimDailyReward(badWallet, DAY).reason == "InvalidWallet", "neg coins")
	local badGems: any = { coins = 0, bossGems = -1 }
	assert(ViralSocialLogic.claimDailyReward(badGems, DAY).reason == "InvalidWallet", "neg gems")
	local overflowP: any = { coins = math.huge, bossGems = 0 }
	assert(ViralSocialLogic.claimDailyReward(overflowP, DAY).reason == "InvalidWallet", "inf coins")
	local missingWallet: any = {}
	assert(
		ViralSocialLogic.claimDailyReward(missingWallet, DAY).reason == "InvalidWallet",
		"missing wallet rejected"
	)
end)

run("Deterministic daily quests, event aliases, progress clamping and claim validation", function()
	local qA = ViralSocialLogic.buildQuestsForDay(10)
	local qB = ViralSocialLogic.buildQuestsForDay(10)
	assert(#qA == 3 and qA[1].id == qB[1].id and qA[2].id == qB[2].id, "deterministic for day")
	assert(qA[1].id ~= qA[2].id and qA[2].id ~= qA[3].id, "3 distinct quests")

	local p = makeProfile()
	assert(ViralSocialLogic.ensureDailyQuests(p, 0), "first init resets quests")
	assert(not ViralSocialLogic.ensureDailyQuests(p, 500), "same day keeps quests")
	assert(not ViralSocialLogic.ensureDailyQuests(p, -5), "negative now ignored")
	assert(not ViralSocialLogic.ensureDailyQuests(p, 0 / 0), "NaN now ignored")

	-- Day 0 quests start at index 1: TargetHits (15), MobKills (6), BossOptIns (1).
	local badAmt = ViralSocialLogic.recordQuestProgress(p, "TargetHit", 0 / 0, 100)
	assert(not badAmt.changed and #badAmt.newlyCompletedIds == 0, "NaN amount ignored")
	local zeroAmt = ViralSocialLogic.recordQuestProgress(p, "TargetHit", 0.5, 100)
	assert(not zeroAmt.changed, "sub-1 floored to 0 ignored")

	local partial = ViralSocialLogic.recordQuestProgress(p, "TargetHit", 10.9, 100)
	assert(partial.changed and #partial.newlyCompletedIds == 0, "alias TargetHit +10")
	assert(ViralSocialLogic.claimQuestReward(p, "q_target_hits", 100).reason == "QuestIncomplete")

	local done = ViralSocialLogic.recordQuestProgress(p, "TargetHits", 99, 100)
	assert(done.changed and done.newlyCompletedIds[1] == "q_target_hits", "clamped & completed")
	assert(p.dailyQuests[1].progress == 15, "progress clamped to target")

	local claimed = ViralSocialLogic.claimQuestReward(p, "q_target_hits", 100)
	assert(claimed.ok and p.coins == 350 and p.bossGems == 15, "reward credited")
	assert(ViralSocialLogic.claimQuestReward(p, "q_target_hits", 100).reason == "AlreadyClaimed")
	assert(ViralSocialLogic.claimQuestReward(p, "missing_id", 100).reason == "QuestNotFound")
	assert(ViralSocialLogic.claimQuestReward(p, "", 100).reason == "InvalidArgs")
	assert(ViralSocialLogic.ensureDailyQuests(p, DAY), "next UTC day rotates quests")
end)

run("Co-Op friend and party bonus deduplication and +30% cap", function()
	local solo = ViralSocialLogic.computeCoOpBonus(1, nil, {})
	assert(solo.friendBonusMult == 1.0 and solo.bonusPercent == 0 and solo.partySize == 0)

	local mixed = ViralSocialLogic.computeCoOpBonus(1, "party_A", {
		{ userId = 1, isFriend = true, partyId = "party_A" }, -- self ignored
		{ userId = 2, isFriend = true, partyId = "party_A" }, -- both friend & party -> 1 ally
		{ userId = 3, isFriend = false, partyId = "party_A" }, -- party mate
		{ userId = 4, isFriend = true, partyId = "party_B" }, -- friend in other party
		{ userId = 5, isFriend = false, partyId = "party_B" }, -- stranger ignored
		{ userId = 6, isFriend = true, partyId = "party_A" }, -- 4th ally (over cap)
		{ userId = 7, isFriend = true, partyId = nil }, -- 5th ally (over cap)
	})
	assert(mixed.allyCount == 5, "5 unique allies counted")
	assert(mixed.partySize == 4, "local + 3 party mates = 4")
	assert(
		math.abs(mixed.friendBonusMult - 1.30) < 1e-6 and mixed.bonusPercent == 30,
		"capped +30%"
	)

	local emptyParty = ViralSocialLogic.computeCoOpBonus(1, "", {
		{ userId = 2, isFriend = false, partyId = "" },
	})
	assert(emptyParty.partySize == 0 and emptyParty.allyCount == 0, "empty partyId ignored")
end)

run("Quick-Ping validation and rate limiting", function()
	local ok1 = ViralSocialLogic.validateQuickPing("Help", { x = 10, y = 2, z = -5 }, nil, 100)
	assert(ok1, "first valid ping allowed")
	local ok2, r2 = ViralSocialLogic.validateQuickPing("Help", nil, 100, 101.4)
	assert(not ok2 and r2 == "RateLimited", "blocked before 1.5s cooldown")
	assert(ViralSocialLogic.validateQuickPing("NiceShot", nil, 100, 101.5), "exact 1.5s allowed")

	local okBadId, rBadId = ViralSocialLogic.validateQuickPing("Spam", nil, nil, 100)
	assert(not okBadId and rBadId == "InvalidPingId", "unknown ping rejected")
	local okBadTime, rBadTime = ViralSocialLogic.validateQuickPing("Help", nil, nil, 0 / 0)
	assert(not okBadTime and rBadTime == "InvalidTime", "NaN time rejected")
	local okBadPos, rBadPos =
		ViralSocialLogic.validateQuickPing("Help", { x = 0 / 0, y = 0, z = 0 }, nil, 100)
	assert(not okBadPos and rBadPos == "InvalidWorldPos", "NaN pos rejected")
end)

run("Quick-Ping zone, biome and radius routing", function()
	local origin = { x = 0, y = 0, z = 0 }
	local far = { x = 5000, y = 0, z = 0 }
	local near = { x = 100, y = 0, z = 0 }
	local recv = ViralSocialLogic.shouldReceivePing
	assert(recv("Hub", "", origin, "Hub", "", far), "same Hub always receives")
	assert(
		recv("BiomePvE", "EmeraldMeadow", origin, "BiomePvE", "EmeraldMeadow", far),
		"same biome"
	)
	assert(
		not recv("BiomePvE", "EmeraldMeadow", origin, "BiomePvE", "FrostbiteCavern", far),
		"far different biome excluded"
	)
	assert(recv("Hub", "", origin, "BiomePvE", "EmeraldMeadow", near, 150), "within radius")
	assert(not recv("Hub", "", origin, "BiomePvE", "EmeraldMeadow", near, 50), "outside radius")
end)

run("Milestone announcements, win streaks and clip suggestions", function()
	local payload = ViralSocialLogic.buildAnnouncementPayload(
		"WinStreak",
		"",
		"sub",
		{ -5, 300, 127.9 },
		true,
		""
	)
	assert(payload.headline == "SERVER MILESTONE!", "empty headline fallback")
	assert(payload.accent[1] == 0 and payload.accent[2] == 255 and payload.accent[3] == 127)
	assert(payload.suggestClip and payload.clipLabel == "Save Streak Clip", "preset clipLabel")
	local noClip =
		ViralSocialLogic.buildAnnouncementPayload("WinStreak", "HI", "", nil, false, "Ignored")
	assert(not noClip.suggestClip and noClip.clipLabel == nil, "clipLabel omitted")

	local p = makeProfile()
	local w1 = ViralSocialLogic.recordProgressEvent(p, "Ace", "BossWin", 1, DAY)
	local w2 = ViralSocialLogic.recordProgressEvent(p, "Ace", "PvPWin", 1, DAY)
	local w3 = ViralSocialLogic.recordProgressEvent(p, "Ace", "OverchargedWin", 1, DAY, {
		bossName = "Pyro",
	})
	assert(#w1.announcements == 0 and #w2.announcements == 0, "no streak announcement under 3")
	assert(#w3.announcements == 2 and p.totalBossWins == 3 and p.winStreak == 3)

	ViralSocialLogic.recordProgressEvent(p, "Ace", "BossLoss", 1, DAY)
	assert(p.winStreak == 0 and p.bestWinStreak == 3, "loss resets streak, preserves best")

	local hatch = ViralSocialLogic.recordProgressEvent(p, "Ace", "MythicHatch", 1, DAY, {
		speciesName = "CryoTitan",
	})
	assert(#hatch.announcements == 1 and string.find(hatch.announcements[1].headline, "CRYOTITAN"))

	local v1 =
		ViralSocialLogic.recordProgressEvent(p, "Ace", "VaultExtract", 1, DAY, { chamber = 1 })
	local v2 =
		ViralSocialLogic.recordProgressEvent(p, "Ace", "VaultExtract", 1, DAY, { chamber = 2 })
	assert(#v1.announcements == 0 and #v2.announcements == 1 and p.totalVaultExtracts == 2)
end)

run("Live Hub Leaderboards sorting, tie-breaking and metric sanitization", function()
	local lb = ViralSocialLogic.computeLeaderboards({
		{
			userId = 20,
			displayName = "B",
			powerRating = 500,
			totalBossWins = 3,
			coinsPerSec = 10.4,
		},
		{
			userId = 10,
			displayName = "A",
			powerRating = 500,
			totalBossWins = 3.9,
			coinsPerSec = 10.6,
		},
		{
			userId = 30,
			displayName = "C",
			powerRating = -50,
			totalBossWins = 0 / 0,
			coinsPerSec = math.huge,
		},
	}, 2)
	assert(#lb.power == 2 and lb.power[1].userId == 10 and lb.power[2].userId == 20, "tie userId")
	assert(lb.wins[1].userId == 10 and lb.wins[1].value == 3, "wins floored")
	assert(lb.income[1].userId == 10 and lb.income[1].value == 11, "income rounded")
	local lbAll = ViralSocialLogic.computeLeaderboards({
		{
			userId = 30,
			displayName = "C",
			powerRating = -50,
			totalBossWins = 0 / 0,
			coinsPerSec = 0 / 0,
		},
	}, 5)
	assert(lbAll.power[1].value == 0 and lbAll.wins[1].value == 0 and lbAll.income[1].value == 0)
end)

print("PASS: ViralSocialLogic.spec.luau")
