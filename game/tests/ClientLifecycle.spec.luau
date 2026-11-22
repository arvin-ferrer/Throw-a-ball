--!strict
local ClientLifecycle = require("../src/client/ClientLifecycle")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(`{label}: expected {tostring(expected)}, got {tostring(actual)}`)
	end
end

-- 1. All Init() calls run before any Start() call, ordered by Priority then Name
do
	local order: { string } = {}
	local lookupSeenInStart: string? = nil

	local controllers: { ClientLifecycle.ClientController } = {
		{
			Name = "ZetaController",
			Priority = 100,
			Init = function(_self, _ctx)
				table.insert(order, "Init:Zeta")
			end,
			Start = function(_self, ctx)
				table.insert(order, "Start:Zeta")
				local mock = ctx.getController("MockStateHarness")
				lookupSeenInStart = if mock then mock.Name else nil
			end,
		},
		{
			Name = "AlphaController",
			Priority = 100,
			Init = function(_self, _ctx)
				table.insert(order, "Init:Alpha")
			end,
			Start = function(_self, _ctx)
				table.insert(order, "Start:Alpha")
			end,
		},
		{
			Name = "MockStateHarness",
			Priority = 10,
			Init = function(_self, _ctx)
				table.insert(order, "Init:Mock")
			end,
			Start = function(_self, _ctx)
				table.insert(order, "Start:Mock")
			end,
		},
	}

	local result = ClientLifecycle.bootstrap(controllers, {
		net = {},
		economyConfigs = {},
		isStudio = true,
	})

	assertEqual(result.initializedCount, 3, "Initialized count")
	assertEqual(result.startedCount, 3, "Started count")
	assertEqual(#result.errors, 0, "Zero errors")
	assertEqual(lookupSeenInStart, "MockStateHarness", "getController lookup in Start")

	local expected = {
		"Init:Mock",
		"Init:Alpha",
		"Init:Zeta",
		"Start:Mock",
		"Start:Alpha",
		"Start:Zeta",
	}
	assertEqual(#order, #expected, "Order length")
	for i, label in ipairs(expected) do
		assertEqual(order[i], label, `Order step {i}`)
	end
end

-- 2. Partial controllers (only Init, only Start, or neither) succeed cleanly
do
	local hits = 0
	local controllers: { ClientLifecycle.ClientController } = {
		{
			Name = "InitOnly",
			Init = function()
				hits += 1
			end,
		},
		{
			Name = "StartOnly",
			Start = function()
				hits += 10
			end,
		},
		{
			Name = "PassiveOnly",
		},
	}

	local result = ClientLifecycle.bootstrap(controllers, {
		net = {},
		economyConfigs = {},
		isStudio = false,
	})
	assertEqual(hits, 11, "InitOnly + StartOnly ran")
	assertEqual(result.initializedCount, 3, "All 3 registered in Init phase")
	assertEqual(result.startedCount, 3, "All 3 registered in Start phase")
end

-- 3. Error isolation: a failing controller does not block sibling controllers
do
	local reported: { string } = {}
	local survivorStarted = false

	local controllers: { ClientLifecycle.ClientController } = {
		{
			Name = "BrokenController",
			Priority = 1,
			Init = function()
				error("boom in init")
			end,
			Start = function()
				error("should not start if Init failed")
			end,
		},
		{
			Name = "HealthyController",
			Priority = 2,
			Start = function()
				survivorStarted = true
			end,
		},
	}

	local result = ClientLifecycle.bootstrap(controllers, {
		net = {},
		economyConfigs = {},
		isStudio = false,
	}, {
		onError = function(name: string, phase: string, _err: string)
			table.insert(reported, `{phase}:{name}`)
		end,
	})

	assertEqual(survivorStarted, true, "Healthy controller still started")
	assertEqual(#reported, 1, "Only broken Init error reported")
	assertEqual(reported[1], "Init:BrokenController", "Error phase and name")
	assertEqual(result.initializedCount, 1, "Only healthy controller initialized")
	assertEqual(result.startedCount, 1, "Only healthy controller started")
end

print("PASS: ClientLifecycle.spec.luau")
