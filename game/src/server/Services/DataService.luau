--!strict
--[[
	DataService.luau
	Server-authoritative player profile persistence with session locking (UpdateAsync + BindToClose),
	automatic Studio/unpublished in-memory fallback, <=12h offline accrual on join,
	and replicated leaderstats/attributes/ProfileSync snapshots.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyConfigs = require(Shared.Configs.EconomyConfigs)
local EconomyLogic = require(Shared.Utils.EconomyLogic)
local MathUtil = require(Shared.Utils.MathUtil)
local Remotes = require(Shared.Net.Remotes)

export type PlayerProfile = EconomyLogic.PlayerProfile

local DataService = {}

local STORE_NAME = "BallBrawl_PlayerData_v1"
local SESSION_LOCK_TTL = 1800

local dataStore: DataStore? = nil
local useMemoryFallback = false
local serverSessionId = HttpService:GenerateGUID(false)
local profiles: { [number]: PlayerProfile } = {}
local memoryStore: { [string]: any } = {}
local keyLocks: { [number]: boolean } = {}
local offlineSummary: { [number]: number } = {}
local onProfileLoadedCallbacks: { (Player, PlayerProfile) -> () } = {}

local function getStore(): DataStore?
	if useMemoryFallback then
		return nil
	end
	if dataStore then
		return dataStore
	end
	local ok, storeOrErr = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok and storeOrErr then
		dataStore = storeOrErr
		return dataStore
	end
	useMemoryFallback = true
	return nil
end

local function sanitizeNumberField(
	raw: { [string]: any },
	key: string,
	fallback: number,
	minVal: number,
	integerOnly: boolean?
)
	local val = raw[key]
	if type(val) ~= "number" or not MathUtil.isFinite(val) or val < minVal then
		raw[key] = fallback
		return
	end
	if integerOnly then
		raw[key] = math.floor(val)
	end
end

local function sanitizeProfileTables(raw: { [string]: any }, template: PlayerProfile)
	for _, field in ipairs({
		"pets",
		"activeFollowerUids",
		"codexUnlocked",
		"ownedCosmetics",
		"purchaseIds",
		"processedPurchases",
	}) do
		if type(raw[field]) ~= "table" then
			raw[field] = {}
		end
	end
	if type(raw.eggs) ~= "table" then
		raw.eggs = template.eggs
	end
	if type(raw.padStoredCoins) ~= "table" then
		raw.padStoredCoins = {}
	else
		for idx, amt in pairs(raw.padStoredCoins) do
			if type(idx) ~= "number" or not MathUtil.isPositiveFinite(amt) then
				raw.padStoredCoins[idx] = nil
			end
		end
	end
	for _, pid in ipairs(raw.purchaseIds) do
		if type(pid) == "string" and pid ~= "" then
			raw.processedPurchases[pid] = true
		end
	end
end

local function reconcileProfile(raw: any, now: number): PlayerProfile
	local template = EconomyLogic.createDefaultProfile(now)
	if type(raw) ~= "table" then
		return template
	end
	for key, defaultVal in pairs(template) do
		if raw[key] == nil then
			raw[key] = defaultVal
		end
	end
	sanitizeNumberField(raw, "coins", template.coins, 0, false)
	sanitizeNumberField(raw, "bossGems", template.bossGems, 0, true)
	sanitizeNumberField(raw, "ballDamage", template.ballDamage, 1, false)
	sanitizeNumberField(raw, "throwSpeed", template.throwSpeed, 1, false)
	sanitizeNumberField(raw, "level", template.level, 1, true)
	sanitizeNumberField(raw, "exp", template.exp, 0, true)
	sanitizeNumberField(raw, "ascensionRank", template.ascensionRank, 0, true)
	sanitizeNumberField(raw, "pedestalsUnlocked", template.pedestalsUnlocked, 4, true)
	sanitizeNumberField(raw, "offlineVaultTier", template.offlineVaultTier, 1, true)
	sanitizeNumberField(raw, "activeSlotsUnlocked", template.activeSlotsUnlocked, 1, true)
	sanitizeNumberField(raw, "lastLogoutTime", now, 0, false)
	sanitizeNumberField(raw, "nextPetSeq", template.nextPetSeq, 1, true)
	sanitizeProfileTables(raw, template)
	return raw :: PlayerProfile
end

local function computePower(profile: PlayerProfile): number
	local ballTier = EconomyConfigs.getBallTierById(profile.ballTierId)
		or EconomyConfigs.BALL_TIERS[1]
	local maxHP = EconomyConfigs.getPlayerMaxHP(profile.level)
	local activeRate = 0
	for _, pet in ipairs(profile.pets) do
		if pet.pedestalIndex ~= nil then
			activeRate += EconomyLogic.computePlacedPetRate(profile, pet, false)
		end
	end
	return MathUtil.computePowerRating(
		profile.ballDamage,
		ballTier.damageMult,
		profile.throwSpeed,
		maxHP,
		activeRate
	)
end

function DataService.hasPass(player: Player, passAttr: string): boolean
	return player:GetAttribute(passAttr) == true
end

function DataService.mirrorAttributes(player: Player, profile: PlayerProfile)
	local maxHP = EconomyConfigs.getPlayerMaxHP(profile.level)
	local power = computePower(profile)
	player:SetAttribute("Coins", math.floor(profile.coins))
	player:SetAttribute("BossGems", math.floor(profile.bossGems))
	player:SetAttribute("BallDamage", math.floor(profile.ballDamage))
	player:SetAttribute("ThrowSpeed", profile.throwSpeed)
	player:SetAttribute("Level", profile.level)
	player:SetAttribute("MaxHP", maxHP)
	player:SetAttribute("AscensionRank", profile.ascensionRank)
	player:SetAttribute("PowerRating", power)
	player:SetAttribute("TargetTier", profile.targetTierId)
	player:SetAttribute("BallTier", profile.ballTierId)

	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		ls.Parent = player
	end
	local function setStat(name: string, val: number)
		local iv = ls:FindFirstChild(name)
		if not iv or not iv:IsA("IntValue") then
			local created = Instance.new("IntValue")
			created.Name = name
			created.Parent = ls
			iv = created
		end
		(iv :: IntValue).Value = math.floor(val)
	end
	setStat("Power", power)
	setStat("Coins", profile.coins)
	setStat("Gems", profile.bossGems)
	setStat("Level", profile.level)
end

function DataService.syncToClient(player: Player)
	local profile = profiles[player.UserId]
	if not profile then
		return
	end
	DataService.mirrorAttributes(player, profile)
	local remotes = Remotes.ensureServer()
	remotes.ProfileSync:FireClient(player, {
		profile = profile,
		powerRating = computePower(profile),
		maxHP = EconomyConfigs.getPlayerMaxHP(profile.level),
		offlineCoinsEarned = offlineSummary[player.UserId] or 0,
	})
end

function DataService.getProfile(player: Player): PlayerProfile?
	return profiles[player.UserId]
end

function DataService.getProfileByUserId(userId: number): PlayerProfile?
	return profiles[userId]
end

function DataService.onProfileLoaded(cb: (Player, PlayerProfile) -> ())
	table.insert(onProfileLoadedCallbacks, cb)
end

function DataService.savePlayer(userId: number, releaseLock: boolean): boolean
	local profile = profiles[userId]
	if not profile or keyLocks[userId] then
		return false
	end
	keyLocks[userId] = true
	local now = os.time()
	profile.lastLogoutTime = now
	local key = `Player_{userId}`
	local store = getStore()
	local saved = false
	if store then
		local ok, result = pcall(function()
			return store:UpdateAsync(key, function(oldData: any): any
				if type(oldData) == "table" then
					if
						oldData.sessionLock ~= nil
						and oldData.sessionLock ~= serverSessionId
						and (now - (oldData.lockTime or 0)) < SESSION_LOCK_TTL
					then
						return nil
					end
					if
						type(oldData.data) == "table"
						and (oldData.data.schemaVersion or 0)
							> EconomyLogic.CURRENT_SCHEMA_VERSION
					then
						return nil
					end
				end
				return {
					sessionLock = if releaseLock then nil else serverSessionId,
					lockTime = now,
					data = profile,
				}
			end)
		end)
		if ok and type(result) == "table" then
			saved = true
		elseif not ok and RunService:IsStudio() then
			useMemoryFallback = true
			memoryStore[key] = profile
			saved = true
		end
	elseif RunService:IsStudio() or useMemoryFallback then
		memoryStore[key] = profile
		saved = true
	end
	keyLocks[userId] = nil
	return saved
end

local function acquireProfileFromStore(
	store: DataStore,
	key: string,
	now: number
): (boolean, any, boolean)
	local ok, result = pcall(function()
		return store:UpdateAsync(key, function(oldVal: any)
			if
				type(oldVal) == "table"
				and oldVal.sessionLock ~= nil
				and oldVal.sessionLock ~= serverSessionId
				and (now - (oldVal.lockTime or 0)) < SESSION_LOCK_TTL
			then
				return nil
			end
			local existing = if type(oldVal) == "table" then oldVal.data else nil
			return {
				sessionLock = serverSessionId,
				lockTime = now,
				data = existing or EconomyLogic.createDefaultProfile(now),
			}
		end)
	end)
	if ok and type(result) == "table" and result.sessionLock == serverSessionId then
		return true, result.data, false
	end
	return false, nil, ok
end

local function loadPlayer(player: Player)
	local userId = player.UserId
	local now = os.time()
	local key = `Player_{userId}`
	local rawData: any = nil
	local store = getStore()
	if store then
		local acquired, data, canceled = acquireProfileFromStore(store, key, now)
		if acquired then
			rawData = data
		elseif not canceled and RunService:IsStudio() then
			useMemoryFallback = true
			rawData = memoryStore[key]
		else
			player:Kick("Session data is locked or unavailable. Please rejoin in a moment.")
			return
		end
	else
		rawData = memoryStore[key]
	end

	local profile = reconcileProfile(rawData, now)
	local lastLogout = if MathUtil.isFinite(profile.lastLogoutTime)
		then profile.lastLogoutTime
		else now
	local elapsedOffline = math.max(0, now - lastLogout)
	local offlineEarned = EconomyLogic.accruePedestalCoins(
		profile,
		elapsedOffline,
		true,
		DataService.hasPass(player, "Pass_DoubleCoinsExp")
	)
	profile.lastLogoutTime = now
	profiles[userId] = profile
	offlineSummary[userId] = offlineEarned
	player:SetAttribute("Zone", "Hub")

	DataService.syncToClient(player)
	for _, cb in ipairs(onProfileLoadedCallbacks) do
		task.spawn(cb, player, profile)
	end
end

function DataService.init()
	local remotes = Remotes.ensureServer()
	remotes.GetInitialState.OnServerInvoke = function(player: Player): any
		local p = profiles[player.UserId]
		if not p then
			return nil
		end
		return {
			profile = p,
			powerRating = computePower(p),
			maxHP = EconomyConfigs.getPlayerMaxHP(p.level),
			offlineCoinsEarned = offlineSummary[player.UserId] or 0,
			restrictedRandom = player:GetAttribute("ArePaidRandomItemsRestricted") == true,
		}
	end
end

function DataService.start()
	Players.PlayerAdded:Connect(loadPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(loadPlayer, player)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		local uid = player.UserId
		DataService.savePlayer(uid, true)
		profiles[uid] = nil
		offlineSummary[uid] = nil
	end)

	game:BindToClose(function()
		if RunService:IsStudio() then
			for uid in pairs(profiles) do
				DataService.savePlayer(uid, true)
			end
			return
		end
		for uid in pairs(profiles) do
			task.spawn(DataService.savePlayer, uid, true)
		end
		task.wait(2)
	end)

	-- Periodic autosave every 90s
	task.spawn(function()
		while true do
			task.wait(90)
			for uid in pairs(profiles) do
				DataService.savePlayer(uid, false)
			end
		end
	end)
end

return DataService
