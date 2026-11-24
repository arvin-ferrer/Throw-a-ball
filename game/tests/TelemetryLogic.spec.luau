--!strict
-- Issue #18: TelemetryLogic & TelemetryService first-session and monotonic funnel specs.
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local MathUtil = require("../src/shared/Utils/MathUtil")
local TelemetryLogic = require("../src/shared/Utils/TelemetryLogic")

local function run(name: string, test: () -> ())
	local ok, failure = pcall(test)
	assert(ok, `{name}: {failure}`)
end

local function readRepoFile(relPath: string): string
	if fs.isFile(relPath) then
		return fs.readFile(relPath)
	end
	return fs.readFile(`game/{relPath}`)
end

local function makePlayer(uid: number, isFirstSession: boolean?): any
	local attrs: { [string]: any } = {}
	if isFirstSession ~= nil then
		attrs.IsFirstSession = isFirstSession
	end
	return {
		UserId = uid,
		Parent = {},
		GetAttribute = function(_self: any, name: string): any
			return attrs[name]
		end,
		SetAttribute = function(_self: any, name: string, value: any)
			attrs[name] = value
		end,
	}
end

local function createTelemetryServices(state: any): { [string]: any }
	return {
		AnalyticsService = {
			LogCustomEvent = function(_s: any, p: any, name: string, val: number)
				table.insert(state.custom, { uid = p.UserId, name = name, value = val })
			end,
			LogOnboardingFunnelStepEvent = function(_s: any, p: any, step: number, lbl: string)
				table.insert(state.funnel, { uid = p.UserId, step = step, label = lbl })
			end,
		},
		Players = state.playersApi,
		ReplicatedStorage = {
			WaitForChild = function(_s: any, key: string)
				if key == "Shared" then
					return { Utils = { MathUtil = "MathUtil", TelemetryLogic = "TelemetryLogic" } }
				end
				return {}
			end,
		},
	}
end

local function buildTelemetryMods(): ({ [string]: any }, { [string]: string })
	local function makeHookService()
		return { setTelemetryHook = function() end }
	end
	local mods: { [string]: any } = {
		MathUtil = MathUtil,
		TelemetryLogic = TelemetryLogic,
		ArenaCycleService = makeHookService(),
		PetIncomeService = makeHookService(),
		EconomyService = makeHookService(),
		PolicyGuardService = makeHookService(),
		DataService = {
			isFirstSession = function(plr: any): boolean
				return plr:GetAttribute("IsFirstSession") == true
			end,
		},
	}
	local scriptRefs = {
		ArenaCycleService = "ArenaCycleService",
		PetIncomeService = "PetIncomeService",
		EconomyService = "EconomyService",
		PolicyGuardService = "PolicyGuardService",
		DataService = "DataService",
	}
	return mods, scriptRefs
end

local function createServiceEnv(state: any): { [string]: any }
	local mods, scriptRefs = buildTelemetryMods()
	local services = createTelemetryServices(state)
	return {
		game = {
			GetService = function(_s: any, name: string)
				return services[name]
			end,
		},
		script = { Parent = scriptRefs },
		require = function(id: any)
			return mods[id]
		end,
		os = {
			clock = function()
				return state.clock
			end,
		},
		tonumber = tonumber,
		pcall = pcall,
		type = type,
		ipairs = ipairs,
		table = table,
	}
end

local function makePlayersApi(addedCbs: { any }, removingCbs: { any }, byId: { [number]: any })
	return {
		PlayerAdded = {
			Connect = function(_s: any, cb: any)
				table.insert(addedCbs, cb)
			end,
		},
		PlayerRemoving = {
			Connect = function(_s: any, cb: any)
				table.insert(removingCbs, cb)
			end,
		},
		GetPlayers = function()
			return {}
		end,
		GetPlayerByUserId = function(_s: any, uid: number)
			return byId[uid]
		end,
	}
end

local function createTelemetryHarness()
	local addedCbs: { (any) -> () } = {}
	local removingCbs: { (any) -> () } = {}
	local playersById: { [number]: any } = {}
	local state: any = { clock = 100, custom = {}, funnel = {} }
	state.playersApi = makePlayersApi(addedCbs, removingCbs, playersById)
	local svc = luau.load(readRepoFile("src/server/Services/TelemetryService.luau"), {
		environment = createServiceEnv(state),
		debugName = "TelemetryService",
	})()
	svc.init()
	svc.start()
	return {
		svc = svc,
		state = state,
		join = function(uid: number, isFirst: boolean?)
			local p = makePlayer(uid, isFirst)
			playersById[uid] = p
			for _, cb in ipairs(addedCbs) do
				cb(p)
			end
			return p
		end,
		leave = function(uid: number)
			local p = playersById[uid]
			for _, cb in ipairs(removingCbs) do
				cb(p)
			end
			playersById[uid] = nil
		end,
	}
end

run("Session bounce buckets classify <60s, 61-180s, and >180s", function()
	assert(TelemetryLogic.sessionBucket(0) == "FirstPlayBounce_Under60s", "0s under 60")
	assert(TelemetryLogic.sessionBucket(59.9) == "FirstPlayBounce_Under60s", "59.9s under 60")
	assert(TelemetryLogic.sessionBucket(60) == "FirstPlayBounce_61To180s", "60s boundary")
	assert(TelemetryLogic.sessionBucket(180) == "FirstPlayBounce_61To180s", "180s upper boundary")
	assert(TelemetryLogic.sessionBucket(180.1) == "EngagedSession_Over180s", "180.1s engaged")
end)

run("Invalid or negative durations clamp safely to Under60s", function()
	for _, bad in { -5, 0 / 0, math.huge, -math.huge } do
		assert(
			TelemetryLogic.sessionBucket(bad) == "FirstPlayBounce_Under60s",
			"non-finite or negative duration falls back cleanly"
		)
	end
end)

run("Returning sessions classify separately from first-play bounce", function()
	assert(TelemetryLogic.sessionBucket(12, false) == "ReturningSession", "returning under 60s")
	assert(TelemetryLogic.sessionBucket(400, false) == "ReturningSession", "returning over 180s")
	assert(
		TelemetryLogic.sessionBucket(45, true) == "FirstPlayBounce_Under60s",
		"explicit first session still uses bounce bucket"
	)
end)

run("Starter hatch outcome requires isFirstSession == true and valid bounds", function()
	for _, bad in { -1, 0 / 0, math.huge, -math.huge } do
		local outcome, sec = TelemetryLogic.starterHatchOutcome(bad, true)
		assert(outcome == nil and sec == nil, "invalid duration omitted")
	end
	local nilOutcome, nilSec = TelemetryLogic.starterHatchOutcome(nil, true)
	assert(nilOutcome == nil and nilSec == nil, "missing join timestamp omitted")
	local retOutcome, retSec = TelemetryLogic.starterHatchOutcome(12, false)
	assert(retOutcome == nil and retSec == nil, "returning player starter hatch omitted")
	local unkOutcome, unkSec = TelemetryLogic.starterHatchOutcome(12, nil)
	assert(unkOutcome == nil and unkSec == nil, "unknown session flag omitted")
	for _, fast in { 0, 18.5, 30 } do
		local outcome, sec = TelemetryLogic.starterHatchOutcome(fast, true)
		assert(outcome == "StarterHatch_Within30s" and sec == fast, "fast hatch within 30s")
	end
	for _, slow in { 30.1, 95 } do
		local outcome, sec = TelemetryLogic.starterHatchOutcome(slow, true)
		assert(outcome == "StarterHatch_Over30s" and sec == slow, "slow hatch over 30s")
	end
end)

run("Monotonic 1->4 onboarding funnel isolates boss offers and prevents skips", function()
	local nextStep = (TelemetryLogic :: any).nextFunnelStep
	assert(type(nextStep) == "function", "TelemetryLogic.nextFunnelStep must exist")
	assert(nextStep("SessionStart", 0).step == 1, "step 1 from 0")
	assert(nextStep("StarterHatch_Within30s", 1).step == 2, "step 2 from 1")
	assert(nextStep("StarterHatch_Over30s", 1).step == 2, "step 2 slow from 1")
	assert(nextStep("CashPadSweep", 2).step == 3, "step 3 from 2")
	assert(nextStep("SoftAscension", 3).step == 4, "step 4 from 3")
	assert(nextStep("CashPadSweep", 1) == nil, "cannot skip step 2")
	assert(nextStep("SoftAscension", 2) == nil, "cannot skip step 3")
	assert(nextStep("CashPadSweep", 3) == nil, "cannot repeat step 3")
	for _, ev in { "BossFightOffered", "BossOptInOffered", "BossOptInAccepted" } do
		assert(nextStep(ev, 1) == nil and nextStep(ev, 3) == nil, `{ev} isolated from funnel`)
	end
end)

run("TelemetryService gates starter hatch timing strictly on IsFirstSession == true", function()
	local h = createTelemetryHarness()
	h.join(10, false)
	h.join(11, nil)
	h.join(12, true)
	h.state.clock = 114
	h.svc.record("StarterHatch", { userId = 10 })
	h.svc.record("FirstEggHatchSeconds", { userId = 10, value = 14 })
	h.svc.record("StarterHatch", { userId = 11 })
	h.svc.record("StarterHatch", { userId = 12 })
	h.svc.record("StarterHatch", { userId = 12 })
	local counters = h.svc.getCounters()
	assert(counters.StarterHatch_Within30s == 1, "only first-session player increments Within30s")
	assert(counters.FirstEggHatchSeconds == 1, "FirstEggHatchSeconds recorded once")
	local step2Count = 0
	for _, ev in ipairs(h.state.funnel) do
		if ev.step == 2 then
			step2Count += 1
			assert(ev.uid == 12, "only IsFirstSession == true logs funnel step 2")
		end
	end
	assert(step2Count == 1, "funnel step 2 emitted once for first-session player")
end)

run("TelemetryService isolates boss custom events and enforces 1->4 funnel", function()
	local h = createTelemetryHarness()
	h.join(21, true)
	h.svc.record("BossFightOffered", { userId = 21, value = 1 })
	h.svc.record("BossOptInOffered", { userId = 21, value = 1 })
	h.svc.record("BossOptInAccepted", { userId = 21, value = 1 })
	h.svc.record("CashPadSweep", { userId = 21, coins = 15 })
	assert(
		#h.state.funnel == 1 and h.state.funnel[1].step == 1,
		"early boss/cash cannot skip step 2"
	)
	h.state.clock = 120
	h.svc.record("StarterHatch", { userId = 21 })
	h.svc.record("CashPadSweep", { userId = 21, coins = 25 })
	h.svc.record("CashPadSweep", { userId = 21, coins = 25 })
	h.svc.record("SoftAscension", { userId = 21, rank = 1 })
	assert(#h.state.funnel == 4, "funnel advances monotonically 1->4")
	for i = 1, 4 do
		assert(h.state.funnel[i].step == i, `expected funnel step {i}`)
	end
	local counters = h.svc.getCounters()
	assert(
		counters.BossFightOffered == 1 and counters.BossOptInAccepted == 1,
		"custom events logged"
	)
	h.leave(21)
end)

print("PASS: TelemetryLogic.spec.luau")
