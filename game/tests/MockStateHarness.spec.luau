--!strict
local ClientNet = require("../src/shared/Utils/ClientNet")
local EconomyConfigs = require("../src/shared/Configs/EconomyConfigs")
local MockStateHarness = require("../src/client/Controllers/MockStateHarness")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(`{label}: expected {tostring(expected)}, got {tostring(actual)}`)
	end
end

local function assertNear(actual: number, expected: number, label: string)
	if math.abs(actual - expected) > 1e-6 then
		error(`{label}: expected {expected}, got {actual}`)
	end
end

-- 1. Non-Studio (live) sessions MUST automatically disable the mock harness
do
	local net = ClientNet.new({ mode = "Live" })
	local harness = MockStateHarness.new({
		net = net,
		economyConfigs = EconomyConfigs,
		isStudio = false,
	})

	local receivedEvents = 0
	net:onClientEvent("OptInPrompt", function()
		receivedEvents += 1
	end)

	assertEqual(harness:isAllowed(), false, "Non-Studio harness is not allowed")
	assertEqual(harness:isEnabled(), false, "Non-Studio harness starts disabled")
	assertEqual(harness:setEnabled(true), false, "Non-Studio setEnabled(true) rejected")
	assertEqual(harness:triggerOptInModal(), false, "Non-Studio triggerOptInModal rejected")
	assertEqual(harness:startEggClaim(), false, "Non-Studio startEggClaim rejected")
	assertEqual(harness:setPolicyRestricted(true), false, "Non-Studio setPolicyRestricted rejected")
	assertEqual(net:getMode(), "Live", "Non-Studio keeps ClientNet in Live mode")
	assertEqual(receivedEvents, 0, "Non-Studio emitted zero mock events")
end

-- 2. Studio Opt-In modal simulation + OptIn remote acceptance
do
	local net = ClientNet.new({ mode = "Hybrid" })
	local harness = MockStateHarness.new({
		net = net,
		economyConfigs = EconomyConfigs,
		isStudio = true,
	})

	assertEqual(harness:setEnabled(true), true, "Studio enable succeeds")
	assertEqual(net:getMode(), "Mock", "Studio enable switches ClientNet to Mock")

	local lastOptIn: any = nil
	local lastArena: any = nil
	net:onClientEvent("OptInPrompt", function(payload: any)
		lastOptIn = payload
	end)
	net:onClientEvent("ArenaStateChanged", function(payload: any)
		lastArena = payload
	end)

	assertEqual(
		harness:triggerOptInModal({
			biomeId = "EmeraldMeadow",
			isOvercharged = true,
			queuedPlayers = 4,
			highestPowerRating = 1850,
		}),
		true,
		"triggerOptInModal succeeds"
	)

	assertEqual(lastOptIn.biomeId, "EmeraldMeadow", "OptIn biomeId")
	assertEqual(lastOptIn.isOvercharged, true, "OptIn isOvercharged")
	assertEqual(lastOptIn.queuedPlayers, 4, "OptIn queuedPlayers")
	assertEqual(lastOptIn.highestPowerRating, 1850, "OptIn highestPowerRating")
	assertEqual(lastOptIn.secondsRemaining, 15, "OptIn default 15s countdown")
	assertEqual(lastArena.phase, "OptIn_Window", "Arena enters OptIn_Window")

	harness:step(5)
	assertNear(lastOptIn.secondsRemaining, 10, "OptIn countdown ticks down")

	-- Accepting Opt-In via ClientNet transitions mock arena to Boss_Phase
	assertEqual(
		net:fireServer("OptIn", { biomeId = "EmeraldMeadow", accepted = true }),
		true,
		"Mock OptIn remote"
	)
	assertEqual(lastArena.phase, "Boss_Phase", "Accepting Opt-In enters Boss_Phase")
end

-- 3. Studio 5.0s Egg Claim progress, interrupt-on-damage, and completion
do
	local net = ClientNet.new({ mode = "Hybrid" })
	local harness = MockStateHarness.new({
		net = net,
		economyConfigs = EconomyConfigs,
		isStudio = true,
	})
	harness:setEnabled(true)

	local lastClaim: any = nil
	local lastArena: any = nil
	net:onClientEvent("EggClaimUpdated", function(payload: any)
		lastClaim = payload
	end)
	net:onClientEvent("ArenaStateChanged", function(payload: any)
		lastArena = payload
	end)

	assertEqual(harness:startEggClaim("EmeraldMeadow"), true, "startEggClaim succeeds")
	assertEqual(lastArena.phase, "PvP_EggScramble", "Claim starts in PvP_EggScramble")
	assertEqual(lastClaim.status, "Claiming", "Claim status is Claiming")
	assertNear(lastClaim.durationSeconds, 5.0, "Claim duration is 5.0s")

	harness:step(2.5)
	assertNear(lastClaim.progressSeconds, 2.5, "Claim progresses to 2.5s")

	assertEqual(harness:interruptEggClaim("PvPDamage"), true, "interruptEggClaim succeeds")
	assertEqual(lastClaim.status, "Interrupted", "Claim status Interrupted")
	assertNear(lastClaim.progressSeconds, 0, "Interrupted claim resets progress")
	assertEqual(lastClaim.interruptReason, "PvPDamage", "Interrupt reason propagated")

	assertEqual(harness:startEggClaim("EmeraldMeadow"), true, "Restart claim succeeds")
	harness:step(5.0)
	assertEqual(lastClaim.status, "Completed", "Claim completes at 5.0s")
	assertNear(lastClaim.progressSeconds, 5.0, "Completed claim progress is 5.0s")
	assertEqual(lastArena.phase, "PvE_Open", "Arena resets to PvE_Open after claim")
end

-- 4. Studio Cash Pad accrual, <=12h offline cap, and walk-over sweep
do
	local net = ClientNet.new({ mode = "Hybrid" })
	local harness = MockStateHarness.new({
		net = net,
		economyConfigs = EconomyConfigs,
		isStudio = true,
	})
	harness:setEnabled(true)

	local lastCashPads: any = nil
	local lastCurrency: any = nil
	net:onClientEvent("CashPadUpdated", function(payload: any)
		lastCashPads = payload
	end)
	net:onClientEvent("CurrencyUpdated", function(payload: any)
		lastCurrency = payload
	end)

	-- Default Starter Pedestal #1 is Training Pup (5 Coins/s)
	harness:step(10)
	assertEqual(lastCashPads ~= nil, true, "CashPadUpdated emitted on step")
	local pad1 = lastCashPads.pads[1]
	assertNear(pad1.coinsPerSec, 5.0, "Starter pad1 Coins/s")
	assertNear(pad1.storedCoins, 50.0, "Starter pad1 accrued 50 Coins in 10s")

	-- Sweep pad #1 via ClientNet CollectPad remote
	assertEqual(
		net:fireServer("CollectPad", { pedestalId = 1 }),
		true,
		"CollectPad handled by mock"
	)
	assertNear(lastCashPads.pads[1].storedCoins, 0, "Swept pad1 resets storedCoins to 0")
	assertNear(lastCurrency.coins, 50, "Swept coins credited to mock player wallet")

	-- Offline accrual caps at 12h (50% base efficiency) even if 24h passed
	assertEqual(harness:simulateOfflineAccrual(24 * 3600), true, "simulateOfflineAccrual succeeds")
	local expectedOffline = EconomyConfigs.computeOfflineCoins(5.0, 24 * 3600, 0.5)
	assertNear(
		lastCashPads.pads[1].storedCoins,
		expectedOffline,
		"Offline accrual respects 12h cap"
	)
end

-- 5. Studio PolicyService restricted mode toggle (Roblox 2026 compliance preview)
do
	local net = ClientNet.new({ mode = "Hybrid" })
	local harness = MockStateHarness.new({
		net = net,
		economyConfigs = EconomyConfigs,
		isStudio = true,
	})
	harness:setEnabled(true)

	local lastPolicy: any = nil
	net:onClientEvent("PolicyStateUpdated", function(payload: any)
		lastPolicy = payload
	end)

	assertEqual(harness:isPolicyRestricted(), false, "Policy restricted defaults false")
	assertEqual(harness:setPolicyRestricted(true), true, "Toggle PolicyService restricted ON")
	assertEqual(lastPolicy.arePaidRandomItemsRestricted, true, "PolicyStateUpdated emits true")
	assertEqual(lastPolicy.source, "MockHarness", "PolicyStateUpdated source is MockHarness")

	local ok, response = net:invokeServer("GetPolicyState")
	assertEqual(ok, true, "GetPolicyState mock invoke succeeds")
	assertEqual(response.arePaidRandomItemsRestricted, true, "GetPolicyState reflects toggle")

	assertEqual(harness:setPolicyRestricted(false), true, "Toggle PolicyService restricted OFF")
	assertEqual(lastPolicy.arePaidRandomItemsRestricted, false, "PolicyStateUpdated emits false")
end

-- 6. Disabling Studio harness restores previous ClientNet mode cleanly
do
	local net = ClientNet.new({ mode = "Hybrid" })
	local harness = MockStateHarness.new({
		net = net,
		economyConfigs = EconomyConfigs,
		isStudio = true,
	})
	harness:setEnabled(true)
	assertEqual(net:getMode(), "Mock", "Enabled mode is Mock")
	harness:setEnabled(false)
	assertEqual(harness:isEnabled(), false, "Harness disabled")
	assertEqual(net:getMode(), "Hybrid", "Prior ClientNet mode restored")
end

print("PASS: MockStateHarness.spec.luau")
