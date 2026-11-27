--!strict
--[[
	RetentionConfigs.luau
	Configuration tables for Ball Brawl: Boss Eggs late-2026 Viral Social & Retention Engine:
	- Friend & Roblox PartyId Co-Op bonus (+10%/ally, capped at +30% / 3 allies)
	- Forgiving 7-day cumulative check-in rewards (never resets, zero Robux streak-saves)
	- Rotating Daily Quests (3 per UTC day)
	- Non-verbal 4-icon Quick-Ping Wheel (works across Jan 2026 age-gated chat walls)
	- Server-wide celebration announcements & leaderboards
]]

export type DailyRewardSpec = {
	day: number,
	title: string,
	coins: number,
	gems: number,
	eggId: string?,
	eggCount: number?,
}

export type QuestTemplate = {
	id: string,
	eventType: string,
	title: string,
	description: string,
	target: number,
	rewardCoins: number,
	rewardGems: number,
}

export type QuickPingId = "Help" | "BossReady" | "ExtractNow" | "NiceShot"

export type QuickPingSpec = {
	id: QuickPingId,
	label: string,
	shortLabel: string,
	glyph: string,
	color: { number },
	soundPitch: number,
	durationSec: number,
}

export type AnnouncementCategory = "MythicHatch" | "OverchargedWin" | "VaultExtract" | "WinStreak"

export type AnnouncementPreset = {
	category: AnnouncementCategory,
	accent: { number },
	clipLabel: string,
}

local RetentionConfigs = {}

RetentionConfigs.SECONDS_PER_DAY = 86400
RetentionConfigs.FRIEND_BONUS_PER_ALLY = 0.10
RetentionConfigs.MAX_FRIEND_BONUS_COUNT = 3
RetentionConfigs.MAX_FRIEND_BONUS_EXTRA = 0.30
RetentionConfigs.QUICK_PING_COOLDOWN_SEC = 1.5
RetentionConfigs.QUICK_PING_RADIUS = 220
RetentionConfigs.QUICK_PING_MAX_OFFSET = 120
RetentionConfigs.DAILY_QUEST_COUNT = 3
RetentionConfigs.MIN_STREAK_ANNOUNCEMENT = 3
RetentionConfigs.MIN_VAULT_CHAMBER_ANNOUNCEMENT = 2
RetentionConfigs.LEADERBOARD_LIMIT = 5
RetentionConfigs.FRIEND_CACHE_TTL_SEC = 120
RetentionConfigs.HUB_BOARD_ROTATE_SEC = 6.0

RetentionConfigs.DAILY_REWARDS = {
	{
		day = 1,
		title = "Starter Boost",
		coins = 150,
		gems = 5,
		eggId = nil,
		eggCount = nil,
	},
	{
		day = 2,
		title = "Momentum Pack",
		coins = 350,
		gems = 8,
		eggId = nil,
		eggCount = nil,
	},
	{
		day = 3,
		title = "Arena Ready",
		coins = 750,
		gems = 12,
		eggId = nil,
		eggCount = nil,
	},
	{
		day = 4,
		title = "Gem Stash",
		coins = 1500,
		gems = 18,
		eggId = nil,
		eggCount = nil,
	},
	{
		day = 5,
		title = "Power Surge",
		coins = 3000,
		gems = 25,
		eggId = nil,
		eggCount = nil,
	},
	{
		day = 6,
		title = "Vault Prep",
		coins = 6000,
		gems = 35,
		eggId = nil,
		eggCount = nil,
	},
	{
		day = 7,
		title = "Earned Boss Egg!",
		coins = 12000,
		gems = 50,
		eggId = "FrostbiteCavern_BossEgg",
		eggCount = 1,
	},
} :: { DailyRewardSpec }

RetentionConfigs.QUEST_POOL = {
	{
		id = "q_target_hits",
		eventType = "TargetHits",
		title = "Range Warmup",
		description = "Hit Training Targets 15 times",
		target = 15,
		rewardCoins = 250,
		rewardGems = 5,
	},
	{
		id = "q_mob_kills",
		eventType = "MobKills",
		title = "Biome Hunter",
		description = "Defeat 6 Biome PvE Monsters",
		target = 6,
		rewardCoins = 450,
		rewardGems = 8,
	},
	{
		id = "q_boss_optins",
		eventType = "BossOptIns",
		title = "Boss Challenger",
		description = "Opt into 1 Biome Boss Fight",
		target = 1,
		rewardCoins = 600,
		rewardGems = 12,
	},
	{
		id = "q_vault_extracts",
		eventType = "VaultExtracts",
		title = "Vault Raider",
		description = "Extract an Egg from Boss Vault Heist",
		target = 1,
		rewardCoins = 750,
		rewardGems = 15,
	},
	{
		id = "q_cash_sweeps",
		eventType = "CashSweeps",
		title = "Tycoon Collector",
		description = "Sweep Cash Pads 5 times",
		target = 5,
		rewardCoins = 300,
		rewardGems = 6,
	},
} :: { QuestTemplate }

RetentionConfigs.QUICK_PINGS = {
	{
		id = "Help",
		label = "HELP!",
		shortLabel = "Help",
		glyph = "!",
		color = { 244, 86, 78 },
		soundPitch = 1.28,
		durationSec = 4.5,
	},
	{
		id = "BossReady",
		label = "BOSS READY!",
		shortLabel = "Boss Ready",
		glyph = "⚔",
		color = { 255, 198, 56 },
		soundPitch = 1.05,
		durationSec = 4.5,
	},
	{
		id = "ExtractNow",
		label = "EXTRACT NOW!",
		shortLabel = "Extract",
		glyph = "↗",
		color = { 64, 242, 168 },
		soundPitch = 1.18,
		durationSec = 4.5,
	},
	{
		id = "NiceShot",
		label = "NICE SHOT!",
		shortLabel = "Nice Shot",
		glyph = "★",
		color = { 64, 198, 255 },
		soundPitch = 1.40,
		durationSec = 4.0,
	},
} :: { QuickPingSpec }

RetentionConfigs.ANNOUNCEMENT_PRESETS = {
	MythicHatch = {
		category = "MythicHatch",
		accent = { 251, 191, 36 },
		clipLabel = "Save Hatch Clip",
	},
	OverchargedWin = {
		category = "OverchargedWin",
		accent = { 255, 72, 196 },
		clipLabel = "Save Boss Clip",
	},
	VaultExtract = {
		category = "VaultExtract",
		accent = { 64, 242, 214 },
		clipLabel = "Save Heist Clip",
	},
	WinStreak = {
		category = "WinStreak",
		accent = { 242, 122, 42 },
		clipLabel = "Save Streak Clip",
	},
} :: { [string]: AnnouncementPreset }

function RetentionConfigs.getDailyReward(dayIndex: number): DailyRewardSpec
	local clamped = ((math.max(1, math.floor(dayIndex)) - 1) % #RetentionConfigs.DAILY_REWARDS) + 1
	return RetentionConfigs.DAILY_REWARDS[clamped]
end

function RetentionConfigs.getQuickPing(pingId: string): QuickPingSpec?
	for _, spec in ipairs(RetentionConfigs.QUICK_PINGS) do
		if spec.id == pingId then
			return spec
		end
	end
	return nil
end

function RetentionConfigs.getAnnouncementPreset(category: string): AnnouncementPreset
	local found = RetentionConfigs.ANNOUNCEMENT_PRESETS[category]
	if found then
		return found
	end
	return RetentionConfigs.ANNOUNCEMENT_PRESETS.MythicHatch
end

return RetentionConfigs
