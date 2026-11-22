--!strict
--[[
	MockStateHarness.luau
	Studio-only toggle & state simulator so Dev B can preview Opt-In modals,
	5.0s Egg Claim progress, Cash Pad accrual (including <=12h offline cap),
	and PolicyService restricted shop mode before live server services finish.

	SECURITY INVARIANT: Automatically disabled in all live / non-Studio sessions.
]]

export type MockHarnessConfig = {
	net: any,
	economyConfigs: any,
	isStudio: boolean,
}

export type OptInOptions = {
	biomeId: string?,
	isOvercharged: boolean?,
	secondsRemaining: number?,
	queuedPlayers: number?,
	highestPowerRating: number?,
	recommendedDamage: number?,
}

export type MockPad = {
	pedestalId: number,
	petId: string,
	petName: string,
	mutationKey: string,
	starTier: number,
	petLevel: number,
	traitKey: string?,
	baseRate: number,
	coinsPerSec: number,
	storedCoins: number,
	offlineEfficiency: number,
	isFull: boolean,
}

export type MockHarnessInstance = {
	isAllowed: (self: MockHarnessInstance) -> boolean,
	isEnabled: (self: MockHarnessInstance) -> boolean,
	setEnabled: (self: MockHarnessInstance, enabled: boolean) -> boolean,
	toggle: (self: MockHarnessInstance) -> boolean,
	isPolicyRestricted: (self: MockHarnessInstance) -> boolean,
	setPolicyRestricted: (self: MockHarnessInstance, restricted: boolean) -> boolean,
	setArenaPhase: (self: MockHarnessInstance, phase: string, biomeId: string?) -> boolean,
	triggerOptInModal: (self: MockHarnessInstance, options: OptInOptions?) -> boolean,
	startEggClaim: (self: MockHarnessInstance, biomeId: string?) -> boolean,
	interruptEggClaim: (self: MockHarnessInstance, reason: string?) -> boolean,
	simulateOfflineAccrual: (self: MockHarnessInstance, elapsedSeconds: number) -> boolean,
	sweepCashPad: (self: MockHarnessInstance, pedestalId: number) -> number,
	step: (self: MockHarnessInstance, dt: number) -> (),
	getSnapshot: (self: MockHarnessInstance) -> { [string]: any },
}

type InternalHarness = MockHarnessInstance & {
	_net: any,
	_economyConfigs: any,
	_isStudio: boolean,
	_enabled: boolean,
	_previousNetMode: string?,
	_policyRestricted: boolean,
	_coins: number,
	_bossGems: number,
	_biomeId: string,
	_arenaPhase: string,
	_isOvercharged: boolean,
	_optInActive: boolean,
	_optInPayload: { [string]: any },
	_claimPayload: { [string]: any },
	_pads: { MockPad },
	_offlineSecondsAccrued: number,
}

local EGG_CLAIM_DURATION_SECONDS = 5.0
local OPT_IN_DURATION_SECONDS = 15.0

local MockStateHarness = {
	Name = "MockStateHarness",
	Priority = 10,
}

local function computePadRate(economyConfigs: any, pad: MockPad): number
	if economyConfigs and type(economyConfigs.computePetCoinsPerSec) == "function" then
		return economyConfigs.computePetCoinsPerSec({
			baseRate = pad.baseRate,
			mutationKey = pad.mutationKey,
			starTier = pad.starTier,
			petLevel = pad.petLevel,
			traitKey = pad.traitKey,
			ascensionRank = 0,
		})
	end
	return pad.baseRate
end

local function createDefaultPads(economyConfigs: any): { MockPad }
	local offlineEff = if economyConfigs and economyConfigs.BASE_OFFLINE_EFFICIENCY
		then economyConfigs.BASE_OFFLINE_EFFICIENCY
		else 0.5
	local starterPad: MockPad = {
		pedestalId = 1,
		petId = "TrainingPup",
		petName = "Training Pup",
		mutationKey = "Normal",
		starTier = 1,
		petLevel = 1,
		traitKey = nil,
		baseRate = 5,
		coinsPerSec = 5,
		storedCoins = 0,
		offlineEfficiency = offlineEff,
		isFull = false,
	}
	starterPad.coinsPerSec = computePadRate(economyConfigs, starterPad)

	local meadowPad: MockPad = {
		pedestalId = 2,
		petId = "PebbleCub",
		petName = "Pebble Cub",
		mutationKey = "Shiny",
		starTier = 1,
		petLevel = 1,
		traitKey = nil,
		baseRate = 12,
		coinsPerSec = 18,
		storedCoins = 0,
		offlineEfficiency = offlineEff,
		isFull = false,
	}
	meadowPad.coinsPerSec = computePadRate(economyConfigs, meadowPad)

	return { starterPad, meadowPad }
end

local function emitArenaState(self: InternalHarness)
	self._net:emitClientEvent("ArenaStateChanged", {
		biomeId = self._biomeId,
		phase = self._arenaPhase,
		isOvercharged = self._isOvercharged,
		phaseSecondsRemaining = if self._optInActive
			then self._optInPayload.secondsRemaining
			else 90,
		bossHp = if self._arenaPhase == "Boss_Phase" then 1000 else nil,
		bossMaxHp = if self._arenaPhase == "Boss_Phase" then 1000 else nil,
		suddenDeathActive = false,
		pvePlayerCount = 3,
	})
end

local function emitCashPads(self: InternalHarness)
	local totalRate = 0
	local totalStored = 0
	local padSnapshots: { { [string]: any } } = {}
	for _, pad in ipairs(self._pads) do
		totalRate += pad.coinsPerSec
		totalStored += pad.storedCoins
		table.insert(padSnapshots, {
			pedestalId = pad.pedestalId,
			petId = pad.petId,
			petName = pad.petName,
			mutationKey = pad.mutationKey,
			coinsPerSec = pad.coinsPerSec,
			storedCoins = pad.storedCoins,
			offlineEfficiency = pad.offlineEfficiency,
			isFull = pad.isFull,
		})
	end
	self._net:emitClientEvent("CashPadUpdated", {
		pads = padSnapshots,
		totalCoinsPerSec = totalRate,
		totalStoredCoins = totalStored,
		offlineSecondsAccrued = self._offlineSecondsAccrued,
	})
end

local function emitCurrency(self: InternalHarness)
	self._net:emitClientEvent("CurrencyUpdated", {
		coins = self._coins,
		bossGems = self._bossGems,
	})
end

local function emitPolicyState(self: InternalHarness)
	self._net:emitClientEvent("PolicyStateUpdated", {
		arePaidRandomItemsRestricted = self._policyRestricted,
		source = "MockHarness",
	})
end

local function registerMockRemotes(self: InternalHarness)
	self._net:registerMockServerHandler("OptIn", function(payload: any)
		local accepted = if type(payload) == "table"
			then payload.accepted == true
			else payload == true
		self._optInActive = false
		if accepted then
			self._arenaPhase = "Boss_Phase"
		else
			self._arenaPhase = "PvE_Open"
		end
		emitArenaState(self)
	end)

	self._net:registerMockServerHandler("ClaimEgg", function(payload: any)
		local action = if type(payload) == "table" then payload.action else payload
		if action == "Start" then
			self:startEggClaim(self._biomeId)
		elseif action == "Cancel" then
			self:interruptEggClaim("PlayerMoved")
		end
	end)

	self._net:registerMockServerHandler("CollectPad", function(payload: any)
		local pedestalId = if type(payload) == "table" then payload.pedestalId else payload
		if type(pedestalId) == "number" then
			self:sweepCashPad(pedestalId)
		end
	end)

	self._net:registerMockFunction("GetPolicyState", function()
		return {
			arePaidRandomItemsRestricted = self._policyRestricted,
			source = "MockHarness",
		}
	end)
end

local HarnessMethods = {} :: InternalHarness
local HarnessMeta = { __index = HarnessMethods }

function HarnessMethods.isAllowed(self: InternalHarness): boolean
	return self._isStudio == true
end

function HarnessMethods.isEnabled(self: InternalHarness): boolean
	return self._isStudio == true and self._enabled == true
end

function HarnessMethods.setEnabled(self: InternalHarness, enabled: boolean): boolean
	if not self._isStudio then
		self._enabled = false
		return false
	end
	if enabled == self._enabled then
		return true
	end
	if enabled then
		self._previousNetMode = self._net:getMode()
		if not self._net:setMode("Mock") then
			return false
		end
		self._enabled = true
		registerMockRemotes(self)
		emitPolicyState(self)
		emitArenaState(self)
		emitCashPads(self)
		emitCurrency(self)
		return true
	end
	self._enabled = false
	self._optInActive = false
	self._claimPayload.status = "Idle"
	self._claimPayload.progressSeconds = 0
	self._net:clearMocks()
	if self._previousNetMode then
		self._net:setMode(self._previousNetMode)
		self._previousNetMode = nil
	end
	return true
end

function HarnessMethods.toggle(self: InternalHarness): boolean
	return self:setEnabled(not self._enabled)
end

function HarnessMethods.isPolicyRestricted(self: InternalHarness): boolean
	return self._policyRestricted
end

function HarnessMethods.setPolicyRestricted(self: InternalHarness, restricted: boolean): boolean
	if not self:isEnabled() then
		return false
	end
	self._policyRestricted = restricted == true
	emitPolicyState(self)
	return true
end

function HarnessMethods.setArenaPhase(
	self: InternalHarness,
	phase: string,
	biomeId: string?
): boolean
	if not self:isEnabled() then
		return false
	end
	if biomeId then
		self._biomeId = biomeId
	end
	self._arenaPhase = phase
	self._optInActive = phase == "OptIn_Window"
	emitArenaState(self)
	return true
end

function HarnessMethods.triggerOptInModal(self: InternalHarness, options: OptInOptions?): boolean
	if not self:isEnabled() then
		return false
	end
	local opts = options or {}
	self._biomeId = opts.biomeId or self._biomeId
	self._isOvercharged = opts.isOvercharged == true
	self._arenaPhase = "OptIn_Window"
	self._optInActive = true
	self._optInPayload = {
		biomeId = self._biomeId,
		isOvercharged = self._isOvercharged,
		secondsRemaining = opts.secondsRemaining or OPT_IN_DURATION_SECONDS,
		queuedPlayers = opts.queuedPlayers or 3,
		highestPowerRating = opts.highestPowerRating or 420,
		recommendedDamage = opts.recommendedDamage or 15,
	}
	emitArenaState(self)
	self._net:emitClientEvent("OptInPrompt", table.clone(self._optInPayload))
	return true
end

function HarnessMethods.startEggClaim(self: InternalHarness, biomeId: string?): boolean
	if not self:isEnabled() then
		return false
	end
	if biomeId then
		self._biomeId = biomeId
	end
	self._optInActive = false
	self._arenaPhase = "PvP_EggScramble"
	self._claimPayload = {
		biomeId = self._biomeId,
		claimerUserId = 1,
		claimerName = "StudioTester",
		progressSeconds = 0,
		durationSeconds = EGG_CLAIM_DURATION_SECONDS,
		status = "Claiming",
		interruptReason = nil,
	}
	emitArenaState(self)
	self._net:emitClientEvent("EggClaimUpdated", table.clone(self._claimPayload))
	return true
end

function HarnessMethods.interruptEggClaim(self: InternalHarness, reason: string?): boolean
	if not self:isEnabled() then
		return false
	end
	self._claimPayload.progressSeconds = 0
	self._claimPayload.status = "Interrupted"
	self._claimPayload.interruptReason = reason or "PvPDamage"
	self._net:emitClientEvent("EggClaimUpdated", table.clone(self._claimPayload))
	return true
end

function HarnessMethods.simulateOfflineAccrual(
	self: InternalHarness,
	elapsedSeconds: number
): boolean
	if not self:isEnabled() then
		return false
	end
	local maxOffline = if self._economyConfigs and self._economyConfigs.MAX_OFFLINE_SECONDS
		then self._economyConfigs.MAX_OFFLINE_SECONDS
		else 12 * 3600
	local bounded = math.clamp(elapsedSeconds, 0, maxOffline)
	self._offlineSecondsAccrued = bounded
	for _, pad in ipairs(self._pads) do
		local offlineGain = if self._economyConfigs
				and type(self._economyConfigs.computeOfflineCoins) == "function"
			then self._economyConfigs.computeOfflineCoins(
				pad.coinsPerSec,
				elapsedSeconds,
				pad.offlineEfficiency
			)
			else math.floor(pad.coinsPerSec * bounded * pad.offlineEfficiency)
		pad.storedCoins += offlineGain
		pad.isFull = bounded >= maxOffline
	end
	emitCashPads(self)
	return true
end

function HarnessMethods.sweepCashPad(self: InternalHarness, pedestalId: number): number
	if not self:isEnabled() then
		return 0
	end
	for _, pad in ipairs(self._pads) do
		if pad.pedestalId == pedestalId then
			local collected = math.floor(pad.storedCoins)
			pad.storedCoins = 0
			pad.isFull = false
			self._coins += collected
			emitCashPads(self)
			emitCurrency(self)
			return collected
		end
	end
	return 0
end

function HarnessMethods.step(self: InternalHarness, dt: number)
	if not self:isEnabled() or dt <= 0 then
		return
	end
	if self._optInActive then
		local remaining = math.max(0, self._optInPayload.secondsRemaining - dt)
		self._optInPayload.secondsRemaining = remaining
		self._net:emitClientEvent("OptInPrompt", table.clone(self._optInPayload))
		if remaining == 0 then
			self._optInActive = false
			self._arenaPhase = "PvE_Open"
			emitArenaState(self)
		end
	end
	if self._claimPayload.status == "Claiming" then
		local nextProgress =
			math.min(EGG_CLAIM_DURATION_SECONDS, self._claimPayload.progressSeconds + dt)
		self._claimPayload.progressSeconds = nextProgress
		if nextProgress >= EGG_CLAIM_DURATION_SECONDS then
			self._claimPayload.status = "Completed"
			self._net:emitClientEvent("EggClaimUpdated", table.clone(self._claimPayload))
			self._arenaPhase = "PvE_Open"
			emitArenaState(self)
		else
			self._net:emitClientEvent("EggClaimUpdated", table.clone(self._claimPayload))
		end
	end
	for _, pad in ipairs(self._pads) do
		pad.storedCoins += pad.coinsPerSec * dt
	end
	emitCashPads(self)
end

function HarnessMethods.getSnapshot(self: InternalHarness): { [string]: any }
	return {
		isAllowed = self._isStudio,
		isEnabled = self:isEnabled(),
		arenaPhase = self._arenaPhase,
		biomeId = self._biomeId,
		isOvercharged = self._isOvercharged,
		policyRestricted = self._policyRestricted,
		coins = self._coins,
		bossGems = self._bossGems,
		claimStatus = self._claimPayload.status,
		claimProgress = self._claimPayload.progressSeconds,
	}
end

function MockStateHarness.new(config: MockHarnessConfig): MockHarnessInstance
	local isStudio = config.isStudio == true
	local instance: InternalHarness = setmetatable({
		_net = config.net,
		_economyConfigs = config.economyConfigs,
		_isStudio = isStudio,
		_enabled = false,
		_previousNetMode = nil,
		_policyRestricted = false,
		_coins = 0,
		_bossGems = 0,
		_biomeId = "EmeraldMeadow",
		_arenaPhase = "PvE_Open",
		_isOvercharged = false,
		_optInActive = false,
		_optInPayload = {
			biomeId = "EmeraldMeadow",
			isOvercharged = false,
			secondsRemaining = 0,
			queuedPlayers = 0,
			highestPowerRating = 0,
			recommendedDamage = 15,
		},
		_claimPayload = {
			biomeId = "EmeraldMeadow",
			claimerUserId = nil,
			claimerName = nil,
			progressSeconds = 0,
			durationSeconds = EGG_CLAIM_DURATION_SECONDS,
			status = "Idle",
			interruptReason = nil,
		},
		_pads = createDefaultPads(config.economyConfigs),
		_offlineSecondsAccrued = 0,
	}, HarnessMeta) :: any
	return instance
end

local activeHarness: MockHarnessInstance? = nil
local heartbeatConnection: any = nil
local unmountPanel: (() -> ())? = nil

function MockStateHarness.GetInstance(): MockHarnessInstance?
	return activeHarness
end

function MockStateHarness:Init(ctx: any)
	activeHarness = MockStateHarness.new({
		net = ctx.net,
		economyConfigs = ctx.economyConfigs,
		isStudio = ctx.isStudio == true,
	})
end

function MockStateHarness:Start(ctx: any)
	local harness = activeHarness
	if not harness or not harness:isAllowed() then
		return
	end
	if type(ctx.connectHeartbeat) == "function" then
		heartbeatConnection = ctx.connectHeartbeat(function(dt: number)
			if harness:isEnabled() then
				harness:step(dt)
			end
		end)
	end
	if type(ctx.mountStudioPanel) == "function" then
		unmountPanel = ctx.mountStudioPanel(harness)
	end
end

function MockStateHarness:Destroy()
	if heartbeatConnection then
		pcall(function()
			heartbeatConnection:Disconnect()
		end)
		heartbeatConnection = nil
	end
	if unmountPanel then
		unmountPanel()
		unmountPanel = nil
	end
	if activeHarness and activeHarness:isEnabled() then
		activeHarness:setEnabled(false)
	end
end

return MockStateHarness
