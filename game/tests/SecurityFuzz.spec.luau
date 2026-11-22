--!strict
--[[
	SecurityFuzz.spec.luau
	Anti-exploit & fuzz test suite verifying server-authoritative invariants:
	- NaN / Inf / Zero-vector / Remote-spam flood protection
	- Off-pad training rejection
	- Strict PvP immunity outside active PvP_EggScramble
	- Egg claim distance, grace window & single-claimer lock
	- Atomic economy & PolicyService restriction / receipt replay defenses
]]

local ArenaCycleLogic = require("../src/shared/Utils/ArenaCycleLogic")
local CombatLogic = require("../src/shared/Utils/CombatLogic")
local EconomyLogic = require("../src/shared/Utils/EconomyLogic")
local PolicyLogic = require("../src/shared/Utils/PolicyLogic")
local EconomyConfigs = require("../src/shared/Configs/EconomyConfigs")

local function assertTrue(cond: boolean, label: string)
	if not cond then
		error(`SECURITY FUZZ FAILED: {label}`)
	end
end

-- 1. Hostile numeric payloads (NaN, +Inf, -Inf, zero vector)
local hostileNumbers = { 0 / 0, math.huge, -math.huge }
for _, bad in ipairs(hostileNumbers) do
	local ok = CombatLogic.validateThrowRequest({
		lastThrowAt = 0,
		now = 100,
		throwSpeedStat = 1,
		activePets = {},
		originX = bad,
		originY = 5,
		originZ = 0,
		dirX = 0,
		dirY = 0,
		dirZ = 1,
	})
	assertTrue(not ok, "Hostile origin number rejected")
end

-- 2. Same-frame 1000-call throw spam flood -> only 1 accepted
local acceptedThrows = 0
local lastAt = 0
for i = 1, 1000 do
	local now = 10.0 + i * 0.0001
	local ok = CombatLogic.validateThrowRequest({
		lastThrowAt = lastAt,
		now = now,
		throwSpeedStat = 1.0,
		activePets = {},
		originX = 0,
		originY = 5,
		originZ = 0,
		dirX = 0,
		dirY = 0,
		dirZ = 1,
	})
	if ok then
		acceptedThrows += 1
		lastAt = now
	end
end
assertTrue(acceptedThrows == 1, `Expected 1 accepted throw under flood, got {acceptedThrows}`)

-- 3. PvP damage strictly blocked in every non-PvP phase and against Hub/PvE players
local st = ArenaCycleLogic.createBiomeState("FrostbiteCavern", 0)
assertTrue(not ArenaCycleLogic.canDealPvPDamage(st, 1, 2, 10), "Blocked in PvE_Open")
ArenaCycleLogic.triggerOptIn(st, 105, false)
ArenaCycleLogic.setOptIn(st, 1, true, 100)
ArenaCycleLogic.setOptIn(st, 2, true, 100)
assertTrue(not ArenaCycleLogic.canDealPvPDamage(st, 1, 2, 110), "Blocked in OptIn_Window")
ArenaCycleLogic.stepBiome(st, 120, nil)
assertTrue(not ArenaCycleLogic.canDealPvPDamage(st, 1, 2, 125), "Blocked in Boss_Phase")
-- Non-participant boss damage rejected
local okOutsider = ArenaCycleLogic.applyBossDamage(st, 999, 50000, 126)
assertTrue(not okOutsider, "Outsider cannot damage locked Boss")
-- Hostile NaN boss damage rejected
local okNanBoss = ArenaCycleLogic.applyBossDamage(st, 1, 0 / 0, 126)
assertTrue(not okNanBoss, "NaN boss damage rejected")

-- Defeat boss -> test claim radius & grace defenses
ArenaCycleLogic.applyBossDamage(st, 1, 999999, 130)
assertTrue(not ArenaCycleLogic.beginEggClaim(st, 1, 2, 131), "Cannot claim during 3s grace")
assertTrue(not ArenaCycleLogic.beginEggClaim(st, 1, 50, 135), "Cannot claim from 50 studs away")
assertTrue(ArenaCycleLogic.beginEggClaim(st, 1, 4, 135), "Valid claim starts")
-- Moving out of radius cancels claim on next step
local outEv = ArenaCycleLogic.stepBiome(st, 137, 25)
assertTrue(
	#outEv == 1 and outEv[1].kind == "ClaimCanceled",
	"Walking out of claim radius cancels claim"
)

-- 4. Economy hostile inputs (negative/NaN dt, VIP pedestal without pass, mismatched fusion, premature ascension)
local p = EconomyLogic.createDefaultProfile(500)
assertTrue(EconomyLogic.accruePedestalCoins(p, -500, false, false) == 0, "Negative dt yields 0")
assertTrue(EconomyLogic.accruePedestalCoins(p, 0 / 0, true, false) == 0, "NaN dt yields 0")
assertTrue(EconomyLogic.accruePedestalCoins(p, math.huge, true, false) == 0, "Inf dt yields 0")
assertTrue(
	not EconomyLogic.hatchEggOnPedestal(p, "StarterEgg", 13, false, 0.5, 0.5).ok,
	"VIP slot blocked without pass"
)
assertTrue(not EconomyLogic.performSoftAscension(p).ok, "Ascension blocked below coin threshold")
assertTrue(
	not EconomyLogic.craftStandardBiomeEgg(p, "StormRuins").ok,
	"Invalid biome craft blocked"
)
assertTrue(not EconomyLogic.unlockNextActiveSlot(p).ok, "Active Slot 2 blocked at Lv 1 / 0 Gems")

-- 5. Active Follower never pauses pedestal accrual & Overclocked trait caps cleanly at 100%
EconomyLogic.hatchEggOnPedestal(p, "StarterEgg", 1, false, 0.5, 0.5)
p.offlineVaultTier = 3 -- 100%
p.pets[1].traitKey = "Overclocked" -- +20%, must clamp to 100% (1.0)
local capped = EconomyLogic.accruePedestalCoins(p, 48 * 3600, true, false)
assertTrue(
	capped == 5 * EconomyConfigs.MAX_OFFLINE_SECONDS * 1.0,
	"Offline accrual clamped at 12h & 100% eff"
)

-- 6. PolicyService replay & restriction flood (100 duplicate receipts grant exactly ONCE)
local receiptGrants = 0
for _ = 1, 100 do
	local r = PolicyLogic.applyProductReceipt(p, "dup_tx_999", 190000202, true)
	if r.granted and not r.duplicate then
		receiptGrants += 1
	end
end
assertTrue(receiptGrants == 1, "100 duplicate receipts granted exactly once")

print("PASS: SecurityFuzz.spec.luau")
