--!strict
--[[
	ClientNet.luau
	Typed client wrapper around Shared/Net/Remotes.luau (Issue #1) with safe fallback
	and Studio-only mock injection for offline UI / HUD development.
]]

export type NetMode = "Live" | "Mock" | "Hybrid"

export type ArenaPhase = "PvE_Open" | "OptIn_Window" | "Boss_Phase" | "PvP_EggScramble"

export type OptInPromptPayload = {
	biomeId: string,
	isOvercharged: boolean,
	secondsRemaining: number,
	queuedPlayers: number,
	highestPowerRating: number,
	recommendedDamage: number,
}

export type EggClaimPayload = {
	biomeId: string,
	claimerUserId: number?,
	claimerName: string?,
	progressSeconds: number,
	durationSeconds: number,
	status: "Idle" | "Claiming" | "Interrupted" | "Completed",
	interruptReason: string?,
}

export type CashPadState = {
	pedestalId: number,
	petId: string?,
	petName: string?,
	mutationKey: string?,
	coinsPerSec: number,
	storedCoins: number,
	offlineEfficiency: number,
	isFull: boolean,
}

export type CashPadBatchPayload = {
	pads: { CashPadState },
	totalCoinsPerSec: number,
	totalStoredCoins: number,
	offlineSecondsAccrued: number,
}

export type CurrencyPayload = {
	coins: number,
	bossGems: number,
}

export type PolicyStatePayload = {
	arePaidRandomItemsRestricted: boolean,
	source: "LivePolicyService" | "MockHarness" | "FallbackSafe",
}

export type ArenaStatePayload = {
	biomeId: string,
	phase: ArenaPhase,
	isOvercharged: boolean,
	phaseSecondsRemaining: number,
	bossHp: number?,
	bossMaxHp: number?,
	suddenDeathActive: boolean,
	pvePlayerCount: number,
}

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type ClientNetOptions = {
	mode: NetMode?,
	liveRemotes: any?,
	logger: ((message: string) -> ())?,
}

export type ClientNetClient = {
	getMode: (self: ClientNetClient) -> NetMode,
	setMode: (self: ClientNetClient, mode: NetMode) -> boolean,
	lockLiveOnly: (self: ClientNetClient) -> (),
	isLiveLocked: (self: ClientNetClient) -> boolean,
	bindLiveRemotes: (self: ClientNetClient, source: any) -> (),
	fireServer: (self: ClientNetClient, remoteName: string, ...any) -> boolean,
	invokeServer: (self: ClientNetClient, remoteName: string, ...any) -> (boolean, any),
	onClientEvent: (
		self: ClientNetClient,
		remoteName: string,
		callback: (...any) -> ()
	) -> Connection,
	emitClientEvent: (self: ClientNetClient, remoteName: string, ...any) -> number,
	registerMockServerHandler: (
		self: ClientNetClient,
		remoteName: string,
		handler: (...any) -> ()
	) -> (),
	registerMockFunction: (
		self: ClientNetClient,
		remoteName: string,
		handler: (...any) -> any
	) -> (),
	clearMocks: (self: ClientNetClient) -> (),
}

type InternalClientNet = ClientNetClient & {
	_mode: NetMode,
	_liveLocked: boolean,
	_liveRemotes: any,
	_logger: (message: string) -> (),
	_mockListeners: { [string]: { (...any) -> () } },
	_mockServerHandlers: { [string]: (...any) -> () },
	_mockFunctions: { [string]: (...any) -> any },
}

local ClientNet = {}

ClientNet.Remotes = table.freeze({
	-- Client -> Server
	ThrowBall = "ThrowBall",
	OptIn = "OptIn",
	ClaimEgg = "ClaimEgg",
	CollectPad = "CollectPad",
	UpgradePet = "UpgradePet",
	Ascend = "Ascend",
	GetPolicyState = "GetPolicyState",
	-- Server -> Client
	ArenaStateChanged = "ArenaStateChanged",
	OptInPrompt = "OptInPrompt",
	EggClaimUpdated = "EggClaimUpdated",
	CashPadUpdated = "CashPadUpdated",
	CurrencyUpdated = "CurrencyUpdated",
	PolicyStateUpdated = "PolicyStateUpdated",
	HatchReveal = "HatchReveal",
})

local function defaultLogger(message: string)
	warn(`[ClientNet] {message}`)
end

local function makeDisconnectedHandle(): Connection
	return {
		Connected = false,
		Disconnect = function(_self: Connection) end,
	}
end

local function matchesRemoteKind(candidate: any, kind: "Event" | "Function"): boolean
	if candidate == nil then
		return false
	end
	local candidateType = typeof(candidate)
	if candidateType == "Instance" then
		local expected = if kind == "Event" then "RemoteEvent" else "RemoteFunction"
		return (candidate :: Instance):IsA(expected)
	end
	if candidateType ~= "table" then
		return false
	end
	if kind == "Event" then
		return type(candidate.FireServer) == "function" or candidate.OnClientEvent ~= nil
	end
	return type(candidate.InvokeServer) == "function"
end

local function resolveFromMethod(source: any, methodNames: { string }, name: string): any
	for _, methodName in ipairs(methodNames) do
		local getter = source[methodName]
		if type(getter) == "function" then
			local ok, resolved = pcall(getter, name)
			if ok and resolved ~= nil then
				return resolved
			end
			local okSelf, resolvedSelf = pcall(getter, source, name)
			if okSelf and resolvedSelf ~= nil then
				return resolvedSelf
			end
		end
	end
	return nil
end

local function resolveLiveRemote(source: any, remoteName: string, kind: "Event" | "Function"): any
	if source == nil then
		return nil
	end
	if typeof(source) == "Instance" then
		local found = (source :: Instance):FindFirstChild(remoteName)
		return if matchesRemoteKind(found, kind) then found else nil
	end
	if type(source) ~= "table" then
		return nil
	end
	local methods = if kind == "Event"
		then { "GetEvent", "getEvent", "GetRemote", "getRemote" }
		else { "GetFunction", "getFunction", "GetRemote", "getRemote" }
	local viaMethod = resolveFromMethod(source, methods, remoteName)
	if matchesRemoteKind(viaMethod, kind) then
		return viaMethod
	end
	local bucket = if kind == "Event"
		then (source.Events or source.events)
		else (source.Functions or source.functions)
	if type(bucket) == "table" and matchesRemoteKind(bucket[remoteName], kind) then
		return bucket[remoteName]
	end
	return if matchesRemoteKind(source[remoteName], kind) then source[remoteName] else nil
end

local function connectMockListener(
	self: InternalClientNet,
	remoteName: string,
	callback: (...any) -> ()
): Connection
	local list = self._mockListeners[remoteName]
	if not list then
		list = {}
		self._mockListeners[remoteName] = list
	end
	table.insert(list, callback)
	local connection: Connection = {
		Connected = true,
		Disconnect = function(conn: Connection)
			if not conn.Connected then
				return
			end
			conn.Connected = false
			local currentList = self._mockListeners[remoteName]
			if not currentList then
				return
			end
			for index, existing in ipairs(currentList) do
				if existing == callback then
					table.remove(currentList, index)
					break
				end
			end
		end,
	}
	return connection
end

local function connectLiveListener(remote: any, callback: (...any) -> ()): Connection
	local ok, rawConn = pcall(function()
		return remote.OnClientEvent:Connect(callback)
	end)
	if not ok or rawConn == nil then
		return makeDisconnectedHandle()
	end
	return {
		Connected = true,
		Disconnect = function(conn: Connection)
			if not conn.Connected then
				return
			end
			conn.Connected = false
			pcall(function()
				rawConn:Disconnect()
			end)
		end,
	}
end

local ClientNetMethods = {} :: InternalClientNet
local ClientNetMeta = { __index = ClientNetMethods }

function ClientNetMethods.getMode(self: InternalClientNet): NetMode
	return self._mode
end

function ClientNetMethods.setMode(self: InternalClientNet, mode: NetMode): boolean
	if self._liveLocked and mode ~= "Live" then
		self._logger(`Blocked setMode("{mode}") because ClientNet is locked to Live mode.`)
		return false
	end
	self._mode = mode
	return true
end

function ClientNetMethods.lockLiveOnly(self: InternalClientNet)
	self._liveLocked = true
	self._mode = "Live"
end

function ClientNetMethods.isLiveLocked(self: InternalClientNet): boolean
	return self._liveLocked
end

function ClientNetMethods.bindLiveRemotes(self: InternalClientNet, source: any)
	self._liveRemotes = source
end

function ClientNetMethods.fireServer(self: InternalClientNet, remoteName: string, ...: any): boolean
	if self._mode ~= "Mock" then
		local liveRemote = resolveLiveRemote(self._liveRemotes, remoteName, "Event")
		if liveRemote ~= nil then
			local args = table.pack(...)
			local ok, err = pcall(function()
				liveRemote:FireServer(table.unpack(args, 1, args.n))
			end)
			if not ok then
				self._logger(`FireServer("{remoteName}") failed: {tostring(err)}`)
				return false
			end
			return true
		end
		if self._mode == "Live" then
			self._logger(`RemoteEvent "{remoteName}" unavailable in Live mode.`)
			return false
		end
	end
	local mockHandler = self._mockServerHandlers[remoteName]
	if not mockHandler then
		self._logger(`No mock handler registered for FireServer("{remoteName}").`)
		return false
	end
	local args = table.pack(...)
	local ok, err = pcall(function()
		mockHandler(table.unpack(args, 1, args.n))
	end)
	if not ok then
		self._logger(`Mock handler for "{remoteName}" threw: {tostring(err)}`)
		return false
	end
	return true
end

function ClientNetMethods.invokeServer(
	self: InternalClientNet,
	remoteName: string,
	...: any
): (boolean, any)
	local args = table.pack(...)
	if self._mode ~= "Mock" then
		local liveRemote = resolveLiveRemote(self._liveRemotes, remoteName, "Function")
		if liveRemote ~= nil then
			local ok, result = pcall(function()
				return liveRemote:InvokeServer(table.unpack(args, 1, args.n))
			end)
			if not ok then
				self._logger(`InvokeServer("{remoteName}") failed: {tostring(result)}`)
			end
			return ok, result
		end
		if self._mode == "Live" then
			self._logger(`RemoteFunction "{remoteName}" unavailable in Live mode.`)
			return false, "RemoteUnavailable"
		end
	end
	local mockFn = self._mockFunctions[remoteName]
	if not mockFn then
		self._logger(`No mock function registered for InvokeServer("{remoteName}").`)
		return false, "MockFunctionUnavailable"
	end
	return pcall(function()
		return mockFn(table.unpack(args, 1, args.n))
	end)
end

function ClientNetMethods.onClientEvent(
	self: InternalClientNet,
	remoteName: string,
	callback: (...any) -> ()
): Connection
	if self._mode == "Mock" then
		return connectMockListener(self, remoteName, callback)
	end
	local liveRemote = resolveLiveRemote(self._liveRemotes, remoteName, "Event")
	if liveRemote ~= nil then
		return connectLiveListener(liveRemote, callback)
	end
	if self._mode == "Hybrid" then
		return connectMockListener(self, remoteName, callback)
	end
	self._logger(`RemoteEvent "{remoteName}" unavailable for OnClientEvent in Live mode.`)
	return makeDisconnectedHandle()
end

function ClientNetMethods.emitClientEvent(
	self: InternalClientNet,
	remoteName: string,
	...: any
): number
	if self._mode == "Live" or self._liveLocked then
		self._logger(`Blocked emitClientEvent("{remoteName}") in Live mode.`)
		return 0
	end
	local list = self._mockListeners[remoteName]
	if not list or #list == 0 then
		return 0
	end
	local snapshot = table.clone(list)
	local args = table.pack(...)
	local notified = 0
	for _, callback in ipairs(snapshot) do
		local ok, err = pcall(function()
			callback(table.unpack(args, 1, args.n))
		end)
		if ok then
			notified += 1
		else
			self._logger(`Mock listener for "{remoteName}" threw: {tostring(err)}`)
		end
	end
	return notified
end

function ClientNetMethods.registerMockServerHandler(
	self: InternalClientNet,
	remoteName: string,
	handler: (...any) -> ()
)
	self._mockServerHandlers[remoteName] = handler
end

function ClientNetMethods.registerMockFunction(
	self: InternalClientNet,
	remoteName: string,
	handler: (...any) -> any
)
	self._mockFunctions[remoteName] = handler
end

function ClientNetMethods.clearMocks(self: InternalClientNet)
	table.clear(self._mockServerHandlers)
	table.clear(self._mockFunctions)
end

function ClientNet.new(options: ClientNetOptions?): ClientNetClient
	local opts = options or {}
	local instance: InternalClientNet = setmetatable({
		_mode = opts.mode or "Live",
		_liveLocked = false,
		_liveRemotes = opts.liveRemotes,
		_logger = opts.logger or defaultLogger,
		_mockListeners = {},
		_mockServerHandlers = {},
		_mockFunctions = {},
	}, ClientNetMeta) :: any
	return instance
end

local defaultInstance: ClientNetClient = ClientNet.new({ mode = "Live" })

function ClientNet.getDefault(): ClientNetClient
	return defaultInstance
end

function ClientNet.getMode(): NetMode
	return defaultInstance:getMode()
end

function ClientNet.setMode(mode: NetMode): boolean
	return defaultInstance:setMode(mode)
end

function ClientNet.lockLiveOnly()
	defaultInstance:lockLiveOnly()
end

function ClientNet.isLiveLocked(): boolean
	return defaultInstance:isLiveLocked()
end

function ClientNet.bindLiveRemotes(source: any)
	defaultInstance:bindLiveRemotes(source)
end

function ClientNet.fireServer(remoteName: string, ...: any): boolean
	return defaultInstance:fireServer(remoteName, ...)
end

function ClientNet.invokeServer(remoteName: string, ...: any): (boolean, any)
	return defaultInstance:invokeServer(remoteName, ...)
end

function ClientNet.onClientEvent(remoteName: string, callback: (...any) -> ()): Connection
	return defaultInstance:onClientEvent(remoteName, callback)
end

function ClientNet.emitClientEvent(remoteName: string, ...: any): number
	return defaultInstance:emitClientEvent(remoteName, ...)
end

function ClientNet.registerMockServerHandler(remoteName: string, handler: (...any) -> ())
	defaultInstance:registerMockServerHandler(remoteName, handler)
end

function ClientNet.registerMockFunction(remoteName: string, handler: (...any) -> any)
	defaultInstance:registerMockFunction(remoteName, handler)
end

return ClientNet
