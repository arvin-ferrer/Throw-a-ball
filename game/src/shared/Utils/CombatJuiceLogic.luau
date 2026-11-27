--!strict
--[[
	CombatJuiceLogic.luau
	Pure Luau combat feedback math & formatting:
	- 3D floating popup specs (Damage, CRIT!, BossHit, +Coins, +Gems, Kill, EggClaim)
	- Critical threshold evaluation
	- Subtle quadratic camera trauma decay (never nauseating)
	- Win-Streak Halo / Flame Crown tier rules (winStreak >= 2)
	- Corner Kill / Egg Claim / Win-Streak feed queue (max 3 entries, 4s TTL)
]]

local req: any = require
local scriptRef: any = script
local isRoblox = type(scriptRef) == "userdata"
local MathUtil = if isRoblox then req(scriptRef.Parent.MathUtil) else req("./MathUtil")

export type PopupSpec = {
	text: string,
	color: { number },
	strokeColor: { number },
	scale: number,
	isStarburst: boolean,
	riseStuds: number,
	duration: number,
}

export type TraumaState = {
	trauma: number,
	enabled: boolean,
}

export type ShakeSample = {
	offsetX: number,
	offsetY: number,
	rollRad: number,
	intensity: number,
}

export type HaloTier = {
	tier: number,
	name: string,
	label: string,
	primaryColor: { number },
	secondaryColor: { number },
	flameRate: number,
	ringScale: number,
	showCrownSpikes: boolean,
}

export type FeedEntry = {
	id: number,
	text: string,
	accent: { number },
	createdAt: number,
	expiresAt: number,
}

local CombatJuiceLogic = {}

CombatJuiceLogic.DEFAULT_CRIT_THRESHOLD = 150
CombatJuiceLogic.CRIT_THRESHOLD_RATIO = 1.55
CombatJuiceLogic.MAX_TRAUMA_CAP = 0.72
CombatJuiceLogic.TRAUMA_DECAY_PER_SEC = 2.8
CombatJuiceLogic.MAX_OFFSET_STUDS = 0.65
CombatJuiceLogic.MAX_ROLL_RAD = math.rad(1.8)
CombatJuiceLogic.FEED_MAX_ENTRIES = 3
CombatJuiceLogic.FEED_TTL_SEC = 4.0
CombatJuiceLogic.MIN_STREAK_FOR_HALO = 2

local TRAUMA_BY_KIND: { [string]: number } = {
	Crit = 0.40,
	Kill = 0.34,
	EggClaim = 0.30,
	BossHit = 0.24,
	Dash = 0.22,
	Damage = 0.14,
}

local DEFAULT_ACCENT_BY_KIND: { [string]: { number } } = {
	Crit = { 255, 222, 68 },
	Damage = { 255, 96, 86 },
	BossHit = { 255, 138, 66 },
	Coins = { 252, 208, 56 },
	Coin = { 252, 208, 56 },
	Gems = { 204, 132, 255 },
	Gem = { 204, 132, 255 },
	Kill = { 255, 84, 112 },
	EggClaim = { 84, 242, 152 },
	StreakUpdate = { 255, 198, 56 },
}

function CombatJuiceLogic.sanitizeRgb(raw: any, fallback: { number }): { number }
	if type(raw) ~= "table" or #raw < 3 then
		return fallback
	end
	local r, g, b = raw[1], raw[2], raw[3]
	if
		type(r) ~= "number"
		or type(g) ~= "number"
		or type(b) ~= "number"
		or not MathUtil.isFinite(r)
		or not MathUtil.isFinite(g)
		or not MathUtil.isFinite(b)
	then
		return fallback
	end
	return {
		math.clamp(math.floor(r + 0.5), 0, 255),
		math.clamp(math.floor(g + 0.5), 0, 255),
		math.clamp(math.floor(b + 0.5), 0, 255),
	}
end

function CombatJuiceLogic.computeCritThreshold(baseDamage: number?): number
	if type(baseDamage) == "number" and MathUtil.isPositiveFinite(baseDamage) then
		return math.max(1, math.floor(baseDamage * CombatJuiceLogic.CRIT_THRESHOLD_RATIO + 0.5))
	end
	return CombatJuiceLogic.DEFAULT_CRIT_THRESHOLD
end

function CombatJuiceLogic.isCriticalHit(
	kind: string,
	amount: number?,
	critThreshold: number?
): boolean
	if kind == "Crit" then
		return true
	end
	if kind ~= "Damage" and kind ~= "BossHit" then
		return false
	end
	if type(amount) ~= "number" or not MathUtil.isFinite(amount) then
		return false
	end
	local threshold = if type(critThreshold) == "number"
			and MathUtil.isPositiveFinite(critThreshold)
		then critThreshold
		else CombatJuiceLogic.DEFAULT_CRIT_THRESHOLD
	return amount >= threshold
end

local function formatPopupText(
	kind: string,
	amount: number?,
	label: string?,
	isCrit: boolean
): string
	if type(label) == "string" and label ~= "" then
		return label
	end
	local hasAmount = type(amount) == "number" and MathUtil.isFinite(amount)
	local fmtAmt = if hasAmount then MathUtil.formatNumber(amount :: number) else nil
	if isCrit then
		return if fmtAmt then `CRIT! -{fmtAmt}` else "CRIT!"
	elseif kind == "Coins" or kind == "Coin" then
		return if fmtAmt then `+{fmtAmt} Coins` else "+Coins!"
	elseif kind == "Gems" or kind == "Gem" then
		return if fmtAmt then `+{fmtAmt} Gems` else "+Gems!"
	elseif kind == "BossHit" then
		return if fmtAmt then `-{fmtAmt}` else "BOSS HIT!"
	elseif kind == "Kill" then
		return "KO!"
	elseif kind == "EggClaim" then
		return "EGG CLAIMED!"
	end
	return if fmtAmt then `-{fmtAmt}` else "HIT!"
end

function CombatJuiceLogic.formatPopup(payload: any, critThreshold: number?): PopupSpec
	local kind = if type(payload) == "table" and type(payload.kind) == "string"
		then payload.kind
		else "Damage"
	local amount = if type(payload) == "table" and type(payload.amount) == "number"
		then payload.amount
		else nil
	local label = if type(payload) == "table" and type(payload.label) == "string"
		then payload.label
		else nil
	local rawAccent = if type(payload) == "table" then payload.accent else nil
	local isCrit = CombatJuiceLogic.isCriticalHit(kind, amount, critThreshold)
	local effectiveKind = if isCrit then "Crit" else kind
	local defaultColor = DEFAULT_ACCENT_BY_KIND[effectiveKind] or { 255, 255, 255 }
	local color = if isCrit
		then DEFAULT_ACCENT_BY_KIND.Crit
		else CombatJuiceLogic.sanitizeRgb(rawAccent, defaultColor)
	local isStarburst = isCrit or kind == "Kill" or kind == "EggClaim"

	return {
		text = formatPopupText(kind, amount, label, isCrit),
		color = color,
		strokeColor = if isCrit then { 96, 36, 0 } else { 18, 22, 32 },
		scale = if isCrit
			then 1.45
			elseif kind == "Kill" or kind == "EggClaim" then 1.32
			elseif kind == "BossHit" or kind == "Gems" or kind == "Gem" then 1.16
			elseif kind == "Coins" or kind == "Coin" then 1.12
			else 1.0,
		isStarburst = isStarburst,
		riseStuds = if isCrit then 5.4 elseif isStarburst then 5.0 else 4.0,
		duration = if isCrit then 0.85 elseif isStarburst then 0.90 else 0.70,
	}
end

function CombatJuiceLogic.createTraumaState(enabled: boolean?): TraumaState
	return {
		trauma = 0,
		enabled = if enabled == nil then true else enabled == true,
	}
end

function CombatJuiceLogic.getTraumaImpulseForEvent(kind: string): number
	return TRAUMA_BY_KIND[kind] or 0
end

function CombatJuiceLogic.addTrauma(state: TraumaState, amount: number): number
	if not state.enabled then
		state.trauma = 0
		return 0
	end
	if type(amount) ~= "number" or not MathUtil.isFinite(amount) or amount <= 0 then
		return state.trauma
	end
	state.trauma = math.clamp(state.trauma + amount, 0, CombatJuiceLogic.MAX_TRAUMA_CAP)
	return state.trauma
end

function CombatJuiceLogic.stepTrauma(state: TraumaState, dt: number, timeSec: number?): ShakeSample
	if not state.enabled or not MathUtil.isFinite(state.trauma) or state.trauma <= 0 then
		state.trauma = 0
		return { offsetX = 0, offsetY = 0, rollRad = 0, intensity = 0 }
	end
	local safeDt = if MathUtil.isFinite(dt) then math.clamp(dt, 0, 0.1) else 0
	state.trauma = math.max(0, state.trauma - CombatJuiceLogic.TRAUMA_DECAY_PER_SEC * safeDt)
	local intensity = state.trauma * state.trauma
	if intensity <= 1e-5 then
		return { offsetX = 0, offsetY = 0, rollRad = 0, intensity = 0 }
	end
	local t = if type(timeSec) == "number" and MathUtil.isFinite(timeSec) then timeSec else 0
	return {
		offsetX = math.sin(t * 47.0) * CombatJuiceLogic.MAX_OFFSET_STUDS * intensity,
		offsetY = math.cos(t * 53.0) * CombatJuiceLogic.MAX_OFFSET_STUDS * intensity,
		rollRad = math.sin(t * 39.0) * CombatJuiceLogic.MAX_ROLL_RAD * intensity,
		intensity = intensity,
	}
end

function CombatJuiceLogic.getStreakHaloTier(winStreak: any): HaloTier?
	if type(winStreak) ~= "number" or not MathUtil.isFinite(winStreak) then
		return nil
	end
	local streak = math.floor(winStreak)
	if streak < CombatJuiceLogic.MIN_STREAK_FOR_HALO then
		return nil
	end
	if streak >= 7 then
		return {
			tier = 3,
			name = "MythicCrown",
			label = `{streak}x APEX STREAK`,
			primaryColor = { 255, 72, 196 },
			secondaryColor = { 96, 240, 255 },
			flameRate = 26,
			ringScale = 1.35,
			showCrownSpikes = true,
		}
	elseif streak >= 4 then
		return {
			tier = 2,
			name = "Inferno",
			label = `{streak}x INFERNO`,
			primaryColor = { 255, 86, 54 },
			secondaryColor = { 255, 224, 72 },
			flameRate = 18,
			ringScale = 1.18,
			showCrownSpikes = true,
		}
	end
	return {
		tier = 1,
		name = "Blaze",
		label = `{streak} WIN STREAK`,
		primaryColor = { 255, 198, 56 },
		secondaryColor = { 255, 112, 34 },
		flameRate = 10,
		ringScale = 1.0,
		showCrownSpikes = false,
	}
end

function CombatJuiceLogic.formatFeedEntryText(payload: any): string?
	if type(payload) ~= "table" or type(payload.kind) ~= "string" then
		return nil
	end
	local kind = payload.kind
	local customLabel = if type(payload.label) == "string" and payload.label ~= ""
		then payload.label
		else nil
	local killer = if type(payload.killerName) == "string" and payload.killerName ~= ""
		then payload.killerName
		else nil
	local victim = if type(payload.victimName) == "string" and payload.victimName ~= ""
		then payload.victimName
		else nil
	if kind == "Kill" then
		if customLabel then
			return customLabel
		elseif killer and victim then
			return `{killer} KO'd {victim}!`
		elseif killer then
			return `{killer} scored a KO!`
		end
		return "Fighter Knocked Out!"
	elseif kind == "EggClaim" then
		if customLabel then
			return customLabel
		elseif killer then
			return `{killer} claimed the Boss Egg!`
		end
		return "Boss Egg Claimed!"
	elseif kind == "StreakUpdate" then
		local streak = if type(payload.streak) == "number"
				and MathUtil.isFinite(payload.streak)
			then math.floor(payload.streak)
			else 0
		if streak < CombatJuiceLogic.MIN_STREAK_FOR_HALO then
			return nil
		end
		return customLabel or `{killer or "Fighter"} hit a {streak}x Win Streak!`
	end
	return nil
end

function CombatJuiceLogic.pruneFeedEntries(entries: { FeedEntry }, now: number): boolean
	if not MathUtil.isFinite(now) then
		return false
	end
	local removed = false
	for i = #entries, 1, -1 do
		if now >= entries[i].expiresAt then
			table.remove(entries, i)
			removed = true
		end
	end
	return removed
end

function CombatJuiceLogic.pushFeedEntry(
	entries: { FeedEntry },
	nextId: number,
	text: string,
	accent: { number }?,
	now: number
): number
	if text == "" or not MathUtil.isFinite(now) then
		return nextId
	end
	CombatJuiceLogic.pruneFeedEntries(entries, now)
	table.insert(entries, {
		id = nextId,
		text = text,
		accent = CombatJuiceLogic.sanitizeRgb(accent, { 250, 204, 21 }),
		createdAt = now,
		expiresAt = now + CombatJuiceLogic.FEED_TTL_SEC,
	})
	while #entries > CombatJuiceLogic.FEED_MAX_ENTRIES do
		table.remove(entries, 1)
	end
	return nextId + 1
end

return CombatJuiceLogic
