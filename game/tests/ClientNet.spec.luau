--!strict
local ClientNet = require("../src/shared/Utils/ClientNet")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(`{label}: expected {tostring(expected)}, got {tostring(actual)}`)
	end
end

local function makeFakeSignal()
	local listeners: { (...any) -> () } = {}
	return {
		Connect = function(_self: any, fn: (...any) -> ())
			table.insert(listeners, fn)
			local connected = true
			return {
				Connected = true,
				Disconnect = function(conn: any)
					if not connected then
						return
					end
					connected = false
					conn.Connected = false
					for index, existing in ipairs(listeners) do
						if existing == fn then
							table.remove(listeners, index)
							break
						end
					end
				end,
			}
		end,
		Fire = function(_self: any, ...: any)
			for _, fn in ipairs(table.clone(listeners)) do
				fn(...)
			end
		end,
	}
end

local function makeFakeRemoteEvent()
	local firedCalls: { { any } } = {}
	local signal = makeFakeSignal()
	return {
		ClassName = "RemoteEvent",
		OnClientEvent = signal,
		FiredCalls = firedCalls,
		FireServer = function(_self: any, ...: any)
			table.insert(firedCalls, { ... })
		end,
	}
end

local function makeFakeRemoteFunction(handler: (...any) -> any)
	return {
		ClassName = "RemoteFunction",
		InvokeServer = function(_self: any, ...: any): any
			return handler(...)
		end,
	}
end

-- 1. Live mode blocks mock client emissions and safely handles missing remotes
do
	local warnings: { string } = {}
	local net = ClientNet.new({
		mode = "Live",
		logger = function(msg: string)
			table.insert(warnings, msg)
		end,
	})

	local notified = net:emitClientEvent("OptInPrompt", { biomeId = "EmeraldMeadow" })
	assertEqual(notified, 0, "Live mode must block emitClientEvent")
	assertEqual(
		net:fireServer("MissingRemote", 123),
		false,
		"Missing remote fireServer returns false"
	)

	local ok, reason = net:invokeServer("MissingFunction")
	assertEqual(ok, false, "Missing remote invokeServer returns false")
	assertEqual(reason, "RemoteUnavailable", "Missing remote invokeServer reason")

	local conn = net:onClientEvent("MissingEvent", function() end)
	assertEqual(conn.Connected, false, "Missing event returns disconnected handle")
	conn:Disconnect()
end

-- 2. Live mode wraps Remotes.luau table (Events/Functions layout) cleanly
do
	local throwEvent = makeFakeRemoteEvent()
	local policyFn = makeFakeRemoteFunction(function(tag: string)
		return `policy:{tag}`
	end)
	local failingFn = makeFakeRemoteFunction(function()
		error("simulated network failure")
	end)

	local net = ClientNet.new({ mode = "Live" })
	net:bindLiveRemotes({
		Events = {
			ThrowBall = throwEvent,
		},
		Functions = {
			GetPolicyState = policyFn,
			BrokenCall = failingFn,
		},
	})

	assertEqual(net:fireServer("ThrowBall", "aim", 42), true, "Live fireServer succeeds")
	assertEqual(#throwEvent.FiredCalls, 1, "Live FireServer recorded 1 call")
	assertEqual(throwEvent.FiredCalls[1][1], "aim", "Live FireServer arg1")
	assertEqual(throwEvent.FiredCalls[1][2], 42, "Live FireServer arg2")

	local ok, result = net:invokeServer("GetPolicyState", "uk")
	assertEqual(ok, true, "Live invokeServer succeeds")
	assertEqual(result, "policy:uk", "Live invokeServer return value")

	local failOk = net:invokeServer("BrokenCall")
	assertEqual(failOk, false, "Live invokeServer catches errors safely")

	local received = 0
	local conn = net:onClientEvent("ThrowBall", function(amount: number)
		received += amount
	end)
	assertEqual(conn.Connected, true, "Live onClientEvent connected")
	throwEvent.OnClientEvent:Fire(7)
	assertEqual(received, 7, "Live OnClientEvent fires callback")
	conn:Disconnect()
	assertEqual(conn.Connected, false, "Live connection marks disconnected")
	throwEvent.OnClientEvent:Fire(5)
	assertEqual(received, 7, "Disconnected callback no longer fires")
end

-- 3. Live mode also supports GetEvent / GetFunction provider contract
do
	local optInEvent = makeFakeRemoteEvent()
	local net = ClientNet.new({ mode = "Live" })
	net:bindLiveRemotes({
		GetEvent = function(name: string)
			return if name == "OptIn" then optInEvent else nil
		end,
	})
	assertEqual(net:fireServer("OptIn", true), true, "GetEvent provider works")
	assertEqual(#optInEvent.FiredCalls, 1, "GetEvent FireServer called")
end

-- 4. Mock mode routes events, FireServer handlers, and InvokeServer handlers locally
do
	local net = ClientNet.new({ mode = "Mock" })
	local seenServerArg: string? = nil
	net:registerMockServerHandler("ClaimEgg", function(action: string)
		seenServerArg = action
	end)
	net:registerMockFunction("GetPolicyState", function()
		return { arePaidRandomItemsRestricted = true }
	end)

	local receivedPayload: any = nil
	local conn = net:onClientEvent("EggClaimUpdated", function(payload: any)
		receivedPayload = payload
	end)
	assertEqual(conn.Connected, true, "Mock event connection is active")

	assertEqual(
		net:emitClientEvent("EggClaimUpdated", { progressSeconds = 2.5 }),
		1,
		"Emit notifies 1 listener"
	)
	assertEqual(receivedPayload.progressSeconds, 2.5, "Mock listener received payload")

	conn:Disconnect()
	assertEqual(
		net:emitClientEvent("EggClaimUpdated", { progressSeconds = 5.0 }),
		0,
		"Disconnected mock listener skipped"
	)

	assertEqual(net:fireServer("ClaimEgg", "Start"), true, "Mock fireServer calls handler")
	assertEqual(seenServerArg, "Start", "Mock server handler received arg")

	local ok, policy = net:invokeServer("GetPolicyState")
	assertEqual(ok, true, "Mock invokeServer succeeds")
	assertEqual(policy.arePaidRandomItemsRestricted, true, "Mock function returned expected value")
end

-- 5. Hybrid mode prefers live remotes and falls back to mocks when missing
do
	local liveEvent = makeFakeRemoteEvent()
	local net = ClientNet.new({ mode = "Hybrid" })
	net:bindLiveRemotes({ ThrowBall = liveEvent })

	local mockCollected = false
	net:registerMockServerHandler("CollectPad", function()
		mockCollected = true
	end)

	assertEqual(net:fireServer("ThrowBall", 1), true, "Hybrid routes existing remote to live")
	assertEqual(#liveEvent.FiredCalls, 1, "Hybrid called live FireServer")
	assertEqual(
		net:fireServer("CollectPad", 1),
		true,
		"Hybrid falls back to mock when missing live"
	)
	assertEqual(mockCollected, true, "Hybrid mock fallback ran")
end

-- 6. lockLiveOnly prevents switching to Mock or Hybrid in production
do
	local net = ClientNet.new({ mode = "Mock" })
	net:lockLiveOnly()
	assertEqual(net:getMode(), "Live", "lockLiveOnly forces Live mode")
	assertEqual(net:setMode("Mock"), false, "setMode(Mock) rejected when locked")
	assertEqual(net:setMode("Hybrid"), false, "setMode(Hybrid) rejected when locked")
	assertEqual(net:isLiveLocked(), true, "isLiveLocked reports true")
end

print("PASS: ClientNet.spec.luau")
