--!strict
local Arena = require("../src/shared/Utils/ArenaCycleLogic")
local Combat = require("../src/shared/Utils/CombatLogic")
local Economy = require("../src/shared/Utils/EconomyLogic")
local Policy = require("../src/shared/Utils/PolicyLogic")

local failures: { string } = {}
local checks = 0

local function snapshot(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in pairs(value) do
		copy[key] = snapshot(child)
	end
	return copy
end

-- NaN in a fuzz fixture compares equal only to another NaN at the same path.
local function same(actual: any, expected: any): boolean
	if type(actual) ~= "table" or type(expected) ~= "table" then
		return actual == expected or (actual ~= actual and expected ~= expected)
	end
	for key, value in pairs(expected) do
		if not same(actual[key], value) then
			return false
		end
	end
	for key in pairs(actual) do
		if expected[key] == nil then
			return false
		end
	end
	return true
end

-- Check the post-state even when the API accepts or throws. Continue running
-- independent fixtures so one defect cannot mask the other invariant families.
local function reject(name: string, state: any, attempt: () -> boolean)
	local before = snapshot(state)
	local ok, accepted = pcall(attempt)
	local unchanged = same(state, before)
	checks += 1
	if not ok or accepted ~= false or not unchanged then
		local outcome = if not ok
			then "threw"
			elseif accepted ~= false then "accepted"
			else "rejected"
		table.insert(
			failures,
			`{name} | {outcome} | {if unchanged then "unchanged" else "mutated"}`
		)
	end
end

local function profileWithPup()
	local p = Economy.createDefaultProfile(100000)
	assert(
		Economy.hatchEggOnPedestal(p, "StarterEgg", 1, false, 0.25, 0.25).ok,
		"Fixture needs a placed pet"
	)
	p.padStoredCoins[1] = 3.5
	return p
end

local function throwInput(
	p: Economy.PlayerProfile,
	now: number,
	last: number
): Combat.ThrowValidationInput
	return {
		lastThrowAt = last,
		now = now,
		throwSpeedStat = p.throwSpeed,
		activePets = Economy.getActivePets(p),
		originX = 0,
		originY = 4,
		originZ = 0,
		dirX = 1,
		dirY = 0,
		dirZ = 0,
	}
end

local function malformedArgs()
	local cases: { { name: string, value: any } } = {
		{ name = "nil", value = nil },
		{ name = "boolean", value = false },
		{ name = "string", value = "1" },
		{ name = "large table", value = table.create(4096, 1) },
		{ name = "NaN", value = 0 / 0 },
		{ name = "+inf", value = math.huge },
		{ name = "-inf", value = -math.huge },
	}
	for _, sample in cases do
		local p = profileWithPup()
		local request: any = throwInput(p, 10, 0)
		request.dirY = sample.value
		reject(`aim component / {sample.name}`, { p, request }, function()
			return Combat.validateThrowRequest(request)
		end)
		reject(`unknown product / {sample.name}`, p, function()
			return Policy.applyProductReceipt(p, "pending", sample.value, false).granted
		end)
	end
	local p = profileWithPup()
	reject("oversized fusion list", p, function()
		return Economy.fusePets(p, table.create(4096, p.pets[1].uid)).ok
	end)
	for _, index in { 0 / 0, 1.5 } do
		local fresh = Economy.createDefaultProfile(100000)
		reject(
			if index ~= index then "NaN hatch slot" else "fractional hatch slot",
			fresh,
			function()
				return Economy.hatchEggOnPedestal(fresh, "StarterEgg", index, false, 0.2, 0.2).ok
			end
		)
	end
end

local function scramble()
	local s = Arena.createBiomeState("EmeraldMeadow", 0)
	Arena.triggerOptIn(s, 10, false)
	assert(
		Arena.setOptIn(s, 1, true, 100) and Arena.setOptIn(s, 2, true, 100),
		"Both fighters must enter the queue"
	)
	Arena.stepBiome(s, 25, nil)
	assert(Arena.applyBossDamage(s, 1, s.bossHP, 30), "Boss defeat must start the scramble")
	assert(
		Arena.canDealPvPDamage(s, 1, 2, 33),
		"Live room members must be able to fight after grace"
	)
	return s
end

local function phaseAndZone()
	-- A stale roster must never override the phase, even when both users are listed.
	for _, phase in { "PvE_Open", "OptIn_Window", "Boss_Phase" } do
		local s: any = scramble()
		s.phase = phase
		reject(`stale roster / {phase}`, s, function()
			return Arena.canDealPvPDamage(s, 1, 2, 40)
		end)
	end
	local s = scramble()
	-- The pure API represents Hub and open-PvE users by absence from activePlayers.
	-- User 2 is a former fighter returned to PvE; the Hub user (3) never joined.
	Arena.removePlayerFromArena(s, 2, 40, "Eliminated")
	assert(
		s.phase == "PvP_EggScramble" and s.participants[2],
		"Former participant must have left an active scramble"
	)
	for _, pair in { { 1, 2 }, { 2, 1 }, { 1, 3 }, { 3, 1 }, { 2, 3 }, { 3, 2 } } do
		reject(`outside locked roster / {pair[1]} to {pair[2]}`, s, function()
			return Arena.canDealPvPDamage(s, pair[1], pair[2], 41)
		end)
	end
end

local function claimChecks()
	for _, metric in { { "distance", 0 / 0 }, { "distance", -1 }, { "time", 0 / 0 } } do
		local s = scramble()
		local value = metric[2] :: number
		local distance = if metric[1] == "distance" then value else 1
		local now = if metric[1] == "time" then value else 40
		reject(`claim {metric[1]} / {if value ~= value then "NaN" else "negative"}`, s, function()
			return Arena.beginEggClaim(s, 1, distance, now)
		end)
	end
	local s = scramble()
	assert(Arena.beginEggClaim(s, 1, 1, 40), "In-range fighter must start the hold")
	reject("another player cannot release the claim", s, function()
		return #Arena.cancelEggClaim(s, 2, "Released") > 0
	end)
	assert(
		#Arena.stepBiome(s, 44.99, 1) == 0 and s.claim.claimerId == 1,
		"Hold must still be pending before five seconds"
	)
	assert(
		#Arena.onPlayerDamagedInPvP(s, 1) == 1 and s.claim.claimerId == nil,
		"Damage must release the token"
	)
	reject("interrupted hold cannot award at its old five-second deadline", s, function()
		return #Arena.stepBiome(s, 45, 1) > 0
	end)
end

type Tx = (Economy.PlayerProfile) -> Economy.TxResult
local function walletCases(currency: string, operations: { [string]: Tx })
	for name, transact in operations do
		for _, bad in { -1, 0 / 0, math.huge } do
			local p: any = profileWithPup()
			p.coins = 100000
			p.bossGems = 1000
			p.level = 20
			p[currency] = bad
			local kind = if bad ~= bad then "NaN" elseif bad < 0 then "negative" else "+inf"
			reject(`{name} / {kind} {currency}`, p, function()
				return transact(p).ok
			end)
		end
	end
end

local function cashTransfers()
	for _, stored in { -1, 0 / 0, math.huge } do
		local p = profileWithPup()
		p.padStoredCoins[1] = stored
		reject(
			`cash transfer / {if stored ~= stored
				then "NaN"
				elseif stored < 0 then "negative"
				else "+inf"}`,
			p,
			function()
				return Economy.collectCashPad(p, 1) ~= 0
			end
		)
	end
	local overflowCash = profileWithPup()
	overflowCash.coins = 1.7e308
	overflowCash.padStoredCoins[1] = 1e308
	reject("cash transfer / wallet overflow", overflowCash, function()
		return Economy.collectCashPad(overflowCash, 1) ~= 0
	end)
	local invalidSell = profileWithPup()
	invalidSell.eggs.EmeraldMeadow_BossEgg = 1
	assert(
		Economy.hatchEggOnPedestal(invalidSell, "EmeraldMeadow_BossEgg", 2, false, 0.2, 0.2).ok,
		"Fixture needs two pets to test sell guard"
	)
	invalidSell.coins = math.huge
	reject("sell pet / +inf wallet", invalidSell, function()
		return Economy.sellPet(invalidSell, invalidSell.pets[2].uid).ok
	end)
end

local function purchases()
	local fusionProfile = profileWithPup()
	reject("fusion with missing ingredients", fusionProfile, function()
		return Economy.fusePets(fusionProfile, { fusionProfile.pets[1].uid, "absent2", "absent3" }).ok
	end)
	walletCases("coins", {
		ball = Economy.buyNextBallTier,
		target = Economy.buyNextTargetTier,
		ascend = Economy.performSoftAscension,
		pedestal = Economy.unlockNextPedestal,
		level = function(p)
			return Economy.levelUpPet(p, p.pets[1].uid)
		end,
	})
	walletCases("bossGems", {
		vault = Economy.upgradeOfflineVault,
		slot = Economy.unlockNextActiveSlot,
		pedestal = Economy.unlockNextPedestal,
		craft = function(p)
			return Economy.craftStandardBiomeEgg(p, "EmeraldMeadow")
		end,
		trait = function(p)
			return Economy.rerollPetTrait(p, p.pets[1].uid, 0.5)
		end,
	})
	cashTransfers()
end

local function offlineClock()
	local now = 100000
	for _, saved in { now, now + 1, now + 10 ^ 9, 0 / 0, math.huge, -math.huge } do
		local p = profileWithPup()
		p.lastLogoutTime = saved
		reject(`offline clock / {saved}`, p, function()
			return Economy.accruePedestalCoins(p, now - p.lastLogoutTime, true, false) ~= 0
		end)
	end
	-- A backdated finite timestamp legitimately earns 12 hours. Only the excess is rejected.
	for _, elapsed in { 43200, 43201, 365 * 86400 } do
		local p = profileWithPup()
		p.lastLogoutTime = now - elapsed
		local expected = snapshot(p)
		expected.padStoredCoins[1] += 108000 -- Training Pup at 5/s, starter vault at 50%
		local earned = Economy.accruePedestalCoins(p, now - p.lastLogoutTime, true, false)
		assert(
			earned == 108000 and same(p, expected),
			`Backdated {elapsed}s exceeds allowed changes`
		)
	end
end

-- Compose the same admission and reward APIs as CombatService; the successful
-- control establishes real gains, then every denied attempt must preserve them.
local function trainingAttempt(s: any, now: number): boolean
	local p = s.profile
	local admitted = Combat.validateThrowRequest(throwInput(p, now, s.lastThrowAt))
	if not admitted then
		return false
	end
	local gain = Combat.evaluateTrainingHit({
		isOnAssignedPad = true,
		targetTierId = p.targetTierId,
		isMovingGold = true,
		goldCombo = s.combo,
		ascensionRank = p.ascensionRank,
		hasDoubleTrainingPass = false,
		activePets = Economy.getActivePets(p),
	})
	assert(gain.accepted, "A valid on-pad moving target must pay out")
	s.lastThrowAt = now
	s.combo = gain.nextGoldCombo
	p.ballDamage += gain.ballDamageGain
	p.throwSpeed += gain.throwSpeedGain
	return true
end

local function rapidTraining()
	local s = { profile = profileWithPup(), lastThrowAt = 0, combo = 0 }
	assert(
		trainingAttempt(s, 10) and s.combo == 1 and s.profile.ballDamage > 5,
		"First legal training shot must award stats"
	)
	for i = 1, 128 do
		reject(`rapid training hit {i}`, s, function()
			return trainingAttempt(s, 10 + (i % 8) / 1000)
		end)
	end
	assert(
		trainingAttempt(s, 12) and s.combo == 2,
		"Denied training must not consume the next shot"
	)
end

local function roomBoundsAndPadFootprint()
	local meadow = Arena.createBiomeState("EmeraldMeadow", 0)
	local frost = Arena.createBiomeState("FrostbiteCavern", 0)
	Arena.triggerOptIn(meadow, 10, false)
	local states = { EmeraldMeadow = meadow, FrostbiteCavern = frost }
	assert(Arena.switchOptIn(states, "EmeraldMeadow", 101, true, 50), "Initial opt-in accepted")
	reject("rejected replacement opt-in preserves prior queue", states, function()
		return Arena.switchOptIn(states, "FrostbiteCavern", 101, true, 50)
	end)

	assert(Arena.markOptInOffered(meadow, 101), "First offer recorded")
	assert(not Arena.markOptInOffered(meadow, 101), "Repeated offer deduplicated")
	assert(Arena.markOptInOffered(meadow, 202), "Second eligible offer recorded")
	assert(Arena.setOptIn(meadow, 101, true, 50), "Toggle opt-in")
	assert(Arena.setOptIn(meadow, 101, true, 60), "Repeated opt-in")
	local bossEv = Arena.startBossPhase(meadow, 25)
	local decisions = bossEv[1].payload.optInDecisions
	assert(
		#decisions == 2
			and decisions[1].userId == 101
			and decisions[1].optedIn == true
			and decisions[2].userId == 202
			and decisions[2].optedIn == false,
		"Opt-in decisions emit once per eligible player including unanswered timeout"
	)

	assert(Arena.isInsideArenaBounds(10, 5, -10, 0, 0, 0, 140, 120), "In-bounds fighter admitted")
	for _, badPos in { { 141, 0, 0 }, { 0, 121, 0 }, { 0 / 0, 0, 0 } } do
		assert(
			not Arena.isInsideArenaBounds(badPos[1], badPos[2], badPos[3], 0, 0, 0, 140, 120),
			"Out-of-bounds fighter rejected"
		)
	end

	local hx, hy, hz = 5, 0.5, 5
	assert(
		Combat.isWithinPadFootprint(0, hy + 3, 0, hx, hy, hz),
		"Standing on pad surface admitted"
	)
	for _, off in { { 0, -hy - 1, 0 }, { 0, 0, 0 }, { hx + 2, hy + 3, 0 }, { 0, hy + 8, 0 } } do
		assert(
			not Combat.isWithinPadFootprint(off[1], off[2], off[3], hx, hy, hz),
			"Off-pad position rejected"
		)
	end
end

malformedArgs()
phaseAndZone()
claimChecks()
purchases()
offlineClock()
rapidTraining()
roomBoundsAndPadFootprint()
table.sort(failures)
for _, failure in failures do
	print(failure)
end
assert(#failures == 0, `{#failures}/{checks} rejection checks failed`)
print("PASS: SecurityInvariants.spec.luau")
