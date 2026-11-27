--!strict
--[[
	ViralSocialLogic.luau
	Pure Lune-testable logic for Ball Brawl: Boss Eggs Retention & Viral Social Engine:
	- Server-authoritative friend & PartyId Co-Op bonus (+10%/ally, capped at +30% / 3)
	- Forgiving 7-day cumulative check-in (never resets missed days, zero Robux streak-save)
	- 3 deterministic rotating Daily Quests + progress + claim validation
	- Non-verbal 4-icon Quick-Ping rate limiting & zone/radius routing
	- Win-streak & celebration announcement rules + Live Hub Leaderboards
]]

local req: any = require
local scriptRef: any = script
local isRoblox = type(scriptRef) == "userdata"
local RetentionConfigs = if isRoblox
	then req(scriptRef.Parent.Parent.Configs.RetentionConfigs)
	else req("../Configs/RetentionConfigs")
local MathUtil = if isRoblox then req(scriptRef.Parent.MathUtil) else req("./MathUtil")

export type DailyQuestState = {
	id: string,
	eventType: string,
	title: string,
	description: string,
	progress: number,
	target: number,
	rewardCoins: number,
	rewardGems: number,
	claimed: boolean,
}

export type CoOpPeer = {
	userId: number,
	isFriend: boolean?,
	partyId: string?,
}

export type CoOpBonusSummary = {
	friendCount: number,
	partySize: number,
	allyCount: number,
	friendBonusMult: number,
	bonusPercent: number,
}

export type LeaderboardSnapshot = {
	userId: number,
	displayName: string,
	powerRating: number,
	totalBossWins: number,
	coinsPerSec: number,
}

export type LeaderboardRow = {
	rank: number,
	userId: number,
	displayName: string,
	value: number,
}

export type LeaderboardBundle = {
	power: { LeaderboardRow },
	wins: { LeaderboardRow },
	income: { LeaderboardRow },
}

export type AnnouncementSpec = {
	category: RetentionConfigs.AnnouncementCategory,
	headline: string,
	detail: string,
	accent: { number },
	suggestClip: boolean,
	clipLabel: string?,
}

local ViralSocialLogic = {}

local function toSafeInt(value: any, fallback: number, minVal: number): number
	if type(value) ~= "number" or not MathUtil.isFinite(value) then
		return fallback
	end
	local floored = math.floor(value)
	if floored < minVal then
		return fallback
	end
	return floored
end

local function isValidBalance(value: any): boolean
	return type(value) == "number" and MathUtil.isFinite(value) and value >= 0
end

function ViralSocialLogic.getDayNumber(unixTimestamp: number): number
	if
		type(unixTimestamp) ~= "number"
		or not MathUtil.isFinite(unixTimestamp)
		or unixTimestamp < 0
	then
		return 0
	end
	return math.floor(unixTimestamp / RetentionConfigs.SECONDS_PER_DAY)
end

function ViralSocialLogic.ensureSocialProfile(profile: any, now: number?)
	if type(profile) ~= "table" then
		return
	end
	profile.dailyLoginDay = toSafeInt(profile.dailyLoginDay, 0, 0)
	profile.lastDailyClaimDay = toSafeInt(profile.lastDailyClaimDay, -1, -1)
	profile.lastQuestResetDay = toSafeInt(profile.lastQuestResetDay, -1, -1)
	profile.winStreak = toSafeInt(profile.winStreak, 0, 0)
	profile.bestWinStreak = math.max(toSafeInt(profile.bestWinStreak, 0, 0), profile.winStreak)
	profile.totalBossWins = toSafeInt(profile.totalBossWins, 0, 0)
	profile.totalVaultExtracts = toSafeInt(profile.totalVaultExtracts, 0, 0)
	if type(profile.dailyQuests) ~= "table" then
		profile.dailyQuests = {}
	end
	if type(profile.eggs) ~= "table" then
		profile.eggs = {}
	end
	if now ~= nil and MathUtil.isFinite(now) then
		ViralSocialLogic.ensureDailyQuests(profile, now)
	end
end

function ViralSocialLogic.getDailyState(
	profile: any,
	now: number
): {
	currentDayNumber: number,
	dailyDay: number,
	cumulativeDays: number,
	dailyClaimable: boolean,
	nextReward: RetentionConfigs.DailyRewardSpec,
}
	ViralSocialLogic.ensureSocialProfile(profile)
	local dayNumber = ViralSocialLogic.getDayNumber(now)
	local cumulative = if type(profile) == "table" then profile.dailyLoginDay else 0
	local lastClaim = if type(profile) == "table" then profile.lastDailyClaimDay else -1
	local claimable = if type(profile) ~= "table"
			or not MathUtil.isFinite(now)
			or now < 0
		then false
		else (cumulative == 0 and lastClaim <= 0) or (dayNumber > lastClaim)
	local activeSlot = if claimable
		then (cumulative % #RetentionConfigs.DAILY_REWARDS) + 1
		else ((math.max(1, cumulative) - 1) % #RetentionConfigs.DAILY_REWARDS) + 1
	return {
		currentDayNumber = dayNumber,
		dailyDay = activeSlot,
		cumulativeDays = cumulative,
		dailyClaimable = claimable,
		nextReward = RetentionConfigs.getDailyReward(activeSlot),
	}
end

function ViralSocialLogic.claimDailyReward(
	profile: any,
	now: number
): {
	ok: boolean,
	reason: string?,
	dayIndex: number?,
	cumulativeDays: number?,
	reward: RetentionConfigs.DailyRewardSpec?,
}
	if
		type(profile) ~= "table"
		or type(now) ~= "number"
		or not MathUtil.isFinite(now)
		or now < 0
	then
		return { ok = false, reason = "InvalidArgs" }
	end
	ViralSocialLogic.ensureSocialProfile(profile)
	if not isValidBalance(profile.coins) or not isValidBalance(profile.bossGems) then
		return { ok = false, reason = "InvalidWallet" }
	end
	local state = ViralSocialLogic.getDailyState(profile, now)
	if not state.dailyClaimable then
		return { ok = false, reason = "AlreadyClaimedToday" }
	end
	local reward = state.nextReward
	local nextCoins = (profile.coins :: number) + reward.coins
	local nextGems = (profile.bossGems :: number) + reward.gems
	if not MathUtil.isFinite(nextCoins) or not MathUtil.isFinite(nextGems) then
		return { ok = false, reason = "BalanceOverflow" }
	end
	-- Forgiving cumulative counter: never resets on missed days.
	profile.dailyLoginDay += 1
	profile.lastDailyClaimDay = state.currentDayNumber
	profile.coins = nextCoins
	profile.bossGems = nextGems
	if reward.eggId then
		local count = reward.eggCount or 1
		profile.eggs[reward.eggId] = (profile.eggs[reward.eggId] or 0) + count
	end
	return {
		ok = true,
		dayIndex = reward.day,
		cumulativeDays = profile.dailyLoginDay,
		reward = reward,
	}
end

local function makeQuestState(tpl: RetentionConfigs.QuestTemplate): DailyQuestState
	return {
		id = tpl.id,
		eventType = tpl.eventType,
		title = tpl.title,
		description = tpl.description,
		progress = 0,
		target = tpl.target,
		rewardCoins = tpl.rewardCoins,
		rewardGems = tpl.rewardGems,
		claimed = false,
	}
end

function ViralSocialLogic.buildQuestsForDay(dayNumber: number): { DailyQuestState }
	local pool = RetentionConfigs.QUEST_POOL
	local total = #pool
	local count = math.min(RetentionConfigs.DAILY_QUEST_COUNT, total)
	local startIdx = (math.max(0, math.floor(dayNumber)) % total) + 1
	local out: { DailyQuestState } = {}
	for i = 0, count - 1 do
		local idx = ((startIdx - 1 + i) % total) + 1
		table.insert(out, makeQuestState(pool[idx]))
	end
	return out
end

local function sanitizeExistingQuests(quests: { any }): boolean
	if #quests ~= RetentionConfigs.DAILY_QUEST_COUNT then
		return false
	end
	for _, q in ipairs(quests) do
		if type(q) ~= "table" or type(q.id) ~= "string" or type(q.eventType) ~= "string" then
			return false
		end
		q.target = toSafeInt(q.target, 1, 1)
		q.progress = math.clamp(toSafeInt(q.progress, 0, 0), 0, q.target)
		q.rewardCoins = toSafeInt(q.rewardCoins, 100, 0)
		q.rewardGems = toSafeInt(q.rewardGems, 1, 0)
		q.claimed = q.claimed == true
	end
	return true
end

function ViralSocialLogic.ensureDailyQuests(profile: any, now: number): boolean
	if
		type(profile) ~= "table"
		or type(now) ~= "number"
		or not MathUtil.isFinite(now)
		or now < 0
	then
		return false
	end
	ViralSocialLogic.ensureSocialProfile(profile)
	local dayNumber = ViralSocialLogic.getDayNumber(now)
	local needsReset = (profile.lastQuestResetDay ~= dayNumber)
		or not sanitizeExistingQuests(profile.dailyQuests)
	if needsReset then
		profile.dailyQuests = ViralSocialLogic.buildQuestsForDay(dayNumber)
		profile.lastQuestResetDay = dayNumber
		return true
	end
	return false
end

local QUEST_EVENT_ALIASES: { [string]: string } = {
	TargetHit = "TargetHits",
	TargetHits = "TargetHits",
	MobKill = "MobKills",
	MobKills = "MobKills",
	BossOptIn = "BossOptIns",
	BossOptIns = "BossOptIns",
	VaultExtract = "VaultExtracts",
	VaultExtracts = "VaultExtracts",
	CashSweep = "CashSweeps",
	CashSweeps = "CashSweeps",
}

local function normalizeQuestEventType(eventType: string): string
	return QUEST_EVENT_ALIASES[eventType] or eventType
end

function ViralSocialLogic.recordQuestProgress(
	profile: any,
	eventType: string,
	amount: number,
	now: number
): { changed: boolean, newlyCompletedIds: { string } }
	local empty = { changed = false, newlyCompletedIds = {} }
	if
		type(profile) ~= "table"
		or type(eventType) ~= "string"
		or type(amount) ~= "number"
		or not MathUtil.isPositiveFinite(amount)
		or type(now) ~= "number"
		or not MathUtil.isFinite(now)
		or now < 0
	then
		return empty
	end
	local delta = math.floor(amount)
	if delta <= 0 then
		return empty
	end
	ViralSocialLogic.ensureDailyQuests(profile, now)
	local questEvent = normalizeQuestEventType(eventType)
	local changed = false
	local completedIds: { string } = {}
	for _, q in ipairs(profile.dailyQuests) do
		if q.eventType == questEvent and not q.claimed and q.progress < q.target then
			local nextProg = math.min(q.target, q.progress + delta)
			if nextProg ~= q.progress then
				q.progress = nextProg
				changed = true
				if nextProg >= q.target then
					table.insert(completedIds, q.id)
				end
			end
		end
	end
	return { changed = changed, newlyCompletedIds = completedIds }
end

function ViralSocialLogic.claimQuestReward(
	profile: any,
	questId: string,
	now: number
): {
	ok: boolean,
	reason: string?,
	quest: DailyQuestState?,
}
	if
		type(profile) ~= "table"
		or type(questId) ~= "string"
		or questId == ""
		or type(now) ~= "number"
		or not MathUtil.isFinite(now)
		or now < 0
	then
		return { ok = false, reason = "InvalidArgs" }
	end
	if not isValidBalance(profile.coins) or not isValidBalance(profile.bossGems) then
		return { ok = false, reason = "InvalidWallet" }
	end
	ViralSocialLogic.ensureDailyQuests(profile, now)
	for _, q in ipairs(profile.dailyQuests) do
		if q.id == questId then
			if q.claimed then
				return { ok = false, reason = "AlreadyClaimed" }
			end
			if q.progress < q.target then
				return { ok = false, reason = "QuestIncomplete" }
			end
			local nextCoins = (profile.coins :: number) + q.rewardCoins
			local nextGems = (profile.bossGems :: number) + q.rewardGems
			if not MathUtil.isFinite(nextCoins) or not MathUtil.isFinite(nextGems) then
				return { ok = false, reason = "BalanceOverflow" }
			end
			q.claimed = true
			profile.coins = nextCoins
			profile.bossGems = nextGems
			return { ok = true, quest = q }
		end
	end
	return { ok = false, reason = "QuestNotFound" }
end

function ViralSocialLogic.computeCoOpBonus(
	localUserId: number,
	localPartyId: string?,
	peers: { CoOpPeer }
): CoOpBonusSummary
	local hasParty = type(localPartyId) == "string" and localPartyId ~= ""
	local seenAllies: { [number]: boolean } = {}
	local friendCount = 0
	local partyMates = 0
	if type(peers) == "table" then
		for _, peer in ipairs(peers) do
			if
				type(peer) == "table"
				and type(peer.userId) == "number"
				and peer.userId ~= localUserId
			then
				local isFr = peer.isFriend == true
				local sameParty = hasParty
					and type(peer.partyId) == "string"
					and peer.partyId == localPartyId
				if isFr then
					friendCount += 1
				end
				if sameParty then
					partyMates += 1
				end
				if isFr or sameParty then
					seenAllies[peer.userId] = true
				end
			end
		end
	end
	local allyCount = 0
	for _ in pairs(seenAllies) do
		allyCount += 1
	end
	local capped = math.min(allyCount, RetentionConfigs.MAX_FRIEND_BONUS_COUNT)
	local extra = capped * RetentionConfigs.FRIEND_BONUS_PER_ALLY
	return {
		friendCount = friendCount,
		partySize = if hasParty then 1 + partyMates else 0,
		allyCount = allyCount,
		friendBonusMult = 1.0 + extra,
		bonusPercent = math.floor(extra * 100 + 0.5),
	}
end

function ViralSocialLogic.validateQuickPing(
	pingId: any,
	worldPos: { x: number, y: number, z: number }?,
	lastPingAt: number?,
	now: number
): (boolean, string?)
	if type(pingId) ~= "string" or not RetentionConfigs.getQuickPing(pingId) then
		return false, "InvalidPingId"
	end
	if type(now) ~= "number" or not MathUtil.isFinite(now) then
		return false, "InvalidTime"
	end
	if lastPingAt ~= nil and MathUtil.isFinite(lastPingAt) then
		if (now - lastPingAt) < RetentionConfigs.QUICK_PING_COOLDOWN_SEC then
			return false, "RateLimited"
		end
	end
	if worldPos ~= nil then
		if
			type(worldPos) ~= "table"
			or not MathUtil.isFinite(worldPos.x)
			or not MathUtil.isFinite(worldPos.y)
			or not MathUtil.isFinite(worldPos.z)
		then
			return false, "InvalidWorldPos"
		end
	end
	return true, nil
end

function ViralSocialLogic.shouldReceivePing(
	senderZone: string,
	senderBiome: string,
	senderPos: { x: number, y: number, z: number },
	receiverZone: string,
	receiverBiome: string,
	receiverPos: { x: number, y: number, z: number },
	maxDist: number?
): boolean
	if senderZone == receiverZone then
		if senderZone == "BiomePvE" or senderZone == "LockedBossPvP" then
			if senderBiome == receiverBiome then
				return true
			end
		else
			return true
		end
	end
	local radius = maxDist or RetentionConfigs.QUICK_PING_RADIUS
	local dist = MathUtil.distance3D(
		senderPos.x,
		senderPos.y,
		senderPos.z,
		receiverPos.x,
		receiverPos.y,
		receiverPos.z
	)
	return dist <= radius
end

local function clampAccentColor(accent: { number }?, fallback: { number }): { number }
	local src = if type(accent) == "table" and #accent >= 3 then accent else fallback
	return {
		math.clamp(math.floor(tonumber(src[1]) or fallback[1]), 0, 255),
		math.clamp(math.floor(tonumber(src[2]) or fallback[2]), 0, 255),
		math.clamp(math.floor(tonumber(src[3]) or fallback[3]), 0, 255),
	}
end

function ViralSocialLogic.buildAnnouncementPayload(
	category: string,
	headline: string,
	detail: string,
	accent: { number }?,
	suggestClip: boolean?,
	clipLabel: string?
): AnnouncementSpec
	local preset = RetentionConfigs.getAnnouncementPreset(category)
	local safeSuggest = suggestClip == true
	local safeClipLabel = if safeSuggest
		then (if type(clipLabel) == "string" and clipLabel ~= ""
			then clipLabel
			else preset.clipLabel)
		else nil
	return {
		category = preset.category,
		headline = if type(headline) == "string" and headline ~= ""
			then headline
			else "SERVER MILESTONE!",
		detail = if type(detail) == "string" then detail else "",
		accent = clampAccentColor(accent, preset.accent),
		suggestClip = safeSuggest,
		clipLabel = safeClipLabel,
	}
end

local function handleWinMilestone(
	profile: any,
	displayName: string,
	eventType: string,
	ctx: { [string]: any },
	out: { AnnouncementSpec }
)
	profile.totalBossWins += 1
	profile.winStreak += 1
	profile.bestWinStreak = math.max(profile.bestWinStreak or 0, profile.winStreak)
	if eventType == "OverchargedWin" or ctx.isOvercharged == true then
		local bossLabel = string.upper(tostring(ctx.bossName or "Overcharged Boss"))
		table.insert(
			out,
			ViralSocialLogic.buildAnnouncementPayload(
				"OverchargedWin",
				`{displayName} CONQUERED OVERCHARGED {bossLabel}!`,
				"Server-wide Overcharged Boss Victory!",
				nil,
				true
			)
		)
	end
	if profile.winStreak >= RetentionConfigs.MIN_STREAK_ANNOUNCEMENT then
		table.insert(
			out,
			ViralSocialLogic.buildAnnouncementPayload(
				"WinStreak",
				`{displayName} IS ON A {profile.winStreak}x WIN STREAK!`,
				"Unstoppable Boss Brawl dominance!",
				nil,
				true
			)
		)
	end
end

local function checkMilestoneAnnouncements(
	profile: any,
	displayName: string,
	eventType: string,
	amount: number,
	context: { [string]: any }?
): { AnnouncementSpec }
	local out: { AnnouncementSpec } = {}
	local ctx = context or {}
	if eventType == "BossWin" or eventType == "OverchargedWin" or eventType == "PvPWin" then
		handleWinMilestone(profile, displayName, eventType, ctx, out)
	elseif eventType == "BossLoss" or eventType == "PvPLoss" or eventType == "VaultWipe" then
		profile.winStreak = 0
	elseif eventType == "MythicHatch" then
		local speciesLabel = string.upper(tostring(ctx.speciesName or "Mythic Pet"))
		table.insert(
			out,
			ViralSocialLogic.buildAnnouncementPayload(
				"MythicHatch",
				`{displayName} HATCHED A MYTHIC {speciesLabel}!`,
				"Ultra-rare hatch on the Plaza Pedestals!",
				nil,
				true
			)
		)
	elseif eventType == "VaultExtract" or eventType == "VaultExtracts" then
		profile.totalVaultExtracts += 1
		local chamber = tonumber(ctx.chamber) or amount
		if chamber >= RetentionConfigs.MIN_VAULT_CHAMBER_ANNOUNCEMENT then
			table.insert(
				out,
				ViralSocialLogic.buildAnnouncementPayload(
					"VaultExtract",
					`{displayName} EXTRACTED CHAMBER {math.floor(chamber)} VAULT LOOT!`,
					"High-stakes Boss Vault Heist escape!",
					nil,
					true
				)
			)
		end
	end
	return out
end

function ViralSocialLogic.recordProgressEvent(
	profile: any,
	displayName: string,
	eventType: string,
	amount: number,
	now: number,
	context: { [string]: any }?
): {
	questChanged: boolean,
	announcements: { AnnouncementSpec },
}
	if type(profile) ~= "table" or type(eventType) ~= "string" then
		return { questChanged = false, announcements = {} }
	end
	ViralSocialLogic.ensureSocialProfile(profile, now)
	local questRes = ViralSocialLogic.recordQuestProgress(profile, eventType, amount, now)
	local safeName = if type(displayName) == "string" and displayName ~= ""
		then displayName
		else "Player"
	local announcements = checkMilestoneAnnouncements(profile, safeName, eventType, amount, context)
	return {
		questChanged = questRes.changed,
		announcements = announcements,
	}
end

local function buildTopRows(
	entries: { LeaderboardSnapshot },
	limit: number,
	extractor: (LeaderboardSnapshot) -> number
): { LeaderboardRow }
	local sorted: { LeaderboardSnapshot } = {}
	for _, entry in ipairs(entries) do
		if type(entry) == "table" and type(entry.userId) == "number" then
			table.insert(sorted, entry)
		end
	end
	table.sort(sorted, function(a, b)
		local va = extractor(a)
		local vb = extractor(b)
		if va ~= vb then
			return va > vb
		end
		return a.userId < b.userId
	end)
	local rows: { LeaderboardRow } = {}
	for idx = 1, math.min(limit, #sorted) do
		local item = sorted[idx]
		table.insert(rows, {
			rank = idx,
			userId = item.userId,
			displayName = item.displayName,
			value = extractor(item),
		})
	end
	return rows
end

function ViralSocialLogic.computeLeaderboards(
	entries: { LeaderboardSnapshot },
	limit: number?
): LeaderboardBundle
	local cap = math.max(1, math.floor(limit or RetentionConfigs.LEADERBOARD_LIMIT))
	return {
		power = buildTopRows(entries, cap, function(e)
			return if MathUtil.isFinite(e.powerRating)
				then math.max(0, math.floor(e.powerRating + 0.5))
				else 0
		end),
		wins = buildTopRows(entries, cap, function(e)
			return if MathUtil.isFinite(e.totalBossWins)
				then math.max(0, math.floor(e.totalBossWins))
				else 0
		end),
		income = buildTopRows(entries, cap, function(e)
			return if MathUtil.isFinite(e.coinsPerSec)
				then math.max(0, math.floor(e.coinsPerSec + 0.5))
				else 0
		end),
	}
end

return ViralSocialLogic
