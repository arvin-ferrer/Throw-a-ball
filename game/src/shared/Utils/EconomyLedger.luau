--!strict
--[[
	EconomyLedger (Issue #9): the player's persisted profile and every transaction on it.
	Pure (no Roblox APIs). Every transaction is atomic and idempotent:
	  1. validate the server-assigned transaction id
	  2. an exact replay of a recorded id is a successful no-op; a different use is a conflict
	  3. validate every precondition and the arithmetic
	  4. only then mutate and record the receipt
	so a failure never leaves a partial change and a replay can never double-spend.
]]

-- selene: allow(incorrect_standard_library_use) -- string require: same path in Lune and Roblox
local CombatConfigs = require("../Configs/CombatConfigs")
-- selene: allow(incorrect_standard_library_use)
local EconomyConfigs = require("../Configs/EconomyConfigs")
-- selene: allow(incorrect_standard_library_use)
local ShopConfigs = require("../Configs/ShopConfigs")

export type Operation =
	"purchaseBallTier"
	| "purchaseTargetTier"
	| "expandPedestals"
	| "upgradeOfflineVault"
	| "craftGemEgg"
	| "softAscend"
	| "grantCoins"
	| "spendCoins"
	| "grantBossGems"
	| "spendBossGems"

export type TransactionReceipt = { operation: string, argument: (number | string)? }
export type TransactionResult = { ok: boolean, replayed: boolean?, reason: string? }
export type PetData = {
	petId: string,
	level: number,
	stars: number,
	mutation: string,
	trait: string?,
}
export type EggData = { kind: string, biomeId: string? }
export type PedestalData = { petId: string?, eggId: string?, storedCoins: number }

export type PlayerData = {
	schemaVersion: number,
	coins: number,
	bossGems: number,
	ballTierId: string,
	targetTierId: string,
	pedestalsUnlocked: number,
	offlineVaultTier: number,
	ascensionRank: number,
	level: number,
	exp: number,
	ballDamage: number,
	throwSpeed: number,
	lastLogoutTime: number,
	petsById: { [string]: PetData },
	eggsById: { [string]: EggData },
	pedestalsById: { [string]: PedestalData },
	activePetIds: { string },
	transactionReceipts: { [string]: TransactionReceipt },
	extensions: { [string]: any },
}

export type MigrationResult = { ok: boolean, data: PlayerData?, reason: string? }
export type StandardEggMutation = "Normal" | "Shiny" | "Golden"

local EconomyLedger = {}
EconomyLedger.SCHEMA_VERSION = 2

local MAX_SAFE = ShopConfigs.MAX_SAFE_INTEGER
local LEGACY_VAULT_TIER = { [0.5] = 1, [0.75] = 2, [1] = 3 }
local SCALAR_DEFAULTS: { [string]: any } = {
	coins = 0,
	bossGems = 0,
	ballTierId = "RubberBall",
	targetTierId = "WoodenDummy",
	pedestalsUnlocked = ShopConfigs.STARTING_PEDESTALS,
	offlineVaultTier = 1,
	ascensionRank = 0,
	level = 1,
	exp = 0,
	ballDamage = CombatConfigs.Throw.DEFAULT_BASE_BALL_DAMAGE,
	throwSpeed = 0,
	lastLogoutTime = 0,
}
local TABLE_FIELDS =
	{ "petsById", "eggsById", "pedestalsById", "activePetIds", "transactionReceipts", "extensions" }

-- Helpers ------------------------------------------------------------------------------------

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in value do
		copy[key] = deepCopy(child)
	end
	return copy
end

local function isFinite(n: unknown): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function isSafeCount(n: unknown): boolean
	return isFinite(n)
		and (n :: number) >= 0
		and (n :: number) <= MAX_SAFE
		and (n :: number) % 1 == 0
end

local function ok(): TransactionResult
	return { ok = true, replayed = false }
end

local function fail(reason: string): TransactionResult
	return { ok = false, reason = reason }
end

local function indexOf(list: { string }, value: string): number?
	return table.find(list, value)
end

-- Profiles -----------------------------------------------------------------------------------

function EconomyLedger.new(): PlayerData
	local data = deepCopy(SCALAR_DEFAULTS)
	data.schemaVersion = EconomyLedger.SCHEMA_VERSION
	for _, field in TABLE_FIELDS do
		data[field] = {}
	end
	data.eggsById.StarterEgg = { kind = "StarterEgg" }
	data.pedestalsById["1"] = { eggId = "StarterEgg", storedCoins = 0 }
	return data :: PlayerData
end

local function validProfile(data: { [string]: any }): boolean
	for field, default in SCALAR_DEFAULTS do
		local value = data[field]
		if type(default) == "number" then
			if not (isFinite(value) and value >= 0) then
				return false
			end
		elseif type(value) ~= "string" then
			return false
		end
	end
	for _, field in TABLE_FIELDS do
		if type(data[field]) ~= "table" then
			return false
		end
	end
	return isSafeCount(data.coins)
		and isSafeCount(data.bossGems)
		and isSafeCount(data.ascensionRank)
end

-- Version 1 (or unversioned) saves: same field names, vault stored as an efficiency.
local function upgradeLegacy(data: { [string]: any }): boolean
	local efficiency = data.offlineEfficiency
	if efficiency ~= nil then
		local tier = LEGACY_VAULT_TIER[efficiency]
		if not tier then
			return false
		end
		data.offlineVaultTier = tier
		data.offlineEfficiency = nil
	end
	return true
end

function EconomyLedger.migrate(saved: unknown): MigrationResult
	if type(saved) ~= "table" then
		return { ok = false, reason = "InvalidProfile" }
	end
	local version = (saved :: any).schemaVersion
	if version ~= nil and version ~= 1 and version ~= EconomyLedger.SCHEMA_VERSION then
		return {
			ok = false,
			reason = if type(version) == "number"
				then "UnsupportedSchemaVersion"
				else "InvalidProfile",
		}
	end
	local data = deepCopy(saved) -- never touch the caller's table
	if version ~= EconomyLedger.SCHEMA_VERSION and not upgradeLegacy(data) then
		return { ok = false, reason = "InvalidProfile" }
	end
	for field, default in SCALAR_DEFAULTS do
		if data[field] == nil then
			data[field] = default
		end
	end
	for _, field in TABLE_FIELDS do
		if data[field] == nil then
			data[field] = {} -- migration never reissues a starter egg
		end
	end
	data.schemaVersion = EconomyLedger.SCHEMA_VERSION
	if not validProfile(data) then
		return { ok = false, reason = "InvalidProfile" }
	end
	return { ok = true, data = data }
end

-- Transactions ---------------------------------------------------------------------------------

-- Returns a finished result for invalid ids, replays and conflicts; nil means "go ahead".
local function precheck(
	data: PlayerData,
	id: unknown,
	operation: string,
	argument: (number | string)?
): TransactionResult?
	if type(id) ~= "string" or id == "" then
		return fail("InvalidTransactionId")
	end
	local receipt = data.transactionReceipts[id]
	if receipt == nil then
		return nil
	end
	if receipt.operation == operation and receipt.argument == argument then
		return { ok = true, replayed = true }
	end
	return fail("TransactionIdConflict")
end

local function commit(
	data: PlayerData,
	id: string,
	operation: string,
	argument: (number | string)?
): TransactionResult
	data.transactionReceipts[id] = { operation = operation, argument = argument }
	return ok()
end

local function validAmount(amount: unknown): boolean
	return isSafeCount(amount) and (amount :: number) > 0
end

local function grant(
	data: PlayerData,
	id: string,
	amount: number,
	field: string,
	op: string
): TransactionResult
	local done = precheck(data, id, op, amount)
	if done then
		return done
	end
	if not validAmount(amount) then
		return fail("InvalidAmount")
	end
	local balance = (data :: any)[field]
	if balance > MAX_SAFE - amount then
		return fail("BalanceOverflow")
	end
	local record: any = data
	record[field] = balance + amount
	return commit(data, id, op, amount)
end

local function spend(
	data: PlayerData,
	id: string,
	amount: number,
	field: string,
	op: string,
	short: string
): TransactionResult
	local done = precheck(data, id, op, amount)
	if done then
		return done
	end
	if not validAmount(amount) then
		return fail("InvalidAmount")
	end
	if (data :: any)[field] < amount then
		return fail(short)
	end
	local record: any = data
	record[field] -= amount
	return commit(data, id, op, amount)
end

function EconomyLedger.grantCoins(data: PlayerData, id: string, amount: number): TransactionResult
	return grant(data, id, amount, "coins", "grantCoins")
end

function EconomyLedger.grantBossGems(
	data: PlayerData,
	id: string,
	amount: number
): TransactionResult
	return grant(data, id, amount, "bossGems", "grantBossGems")
end

function EconomyLedger.spendCoins(data: PlayerData, id: string, amount: number): TransactionResult
	return spend(data, id, amount, "coins", "spendCoins", "InsufficientCoins")
end

function EconomyLedger.spendBossGems(
	data: PlayerData,
	id: string,
	amount: number
): TransactionResult
	return spend(data, id, amount, "bossGems", "spendBossGems", "InsufficientBossGems")
end

-- Next-tier purchases share one ladder rule: unknown, max, owned, skipped, then funds.
local function buyTier(
	data: PlayerData,
	id: string,
	tierId: string,
	op: string,
	field: string,
	order: { string },
	prices: { [string]: number }
): TransactionResult
	local done = precheck(data, id, op, tierId)
	if done then
		return done
	end
	local wanted, current = indexOf(order, tierId), indexOf(order, (data :: any)[field]) or 1
	if not wanted then
		return fail("UnknownTier")
	elseif current >= #order then
		return fail("MaxTier")
	elseif wanted <= current then
		return fail("AlreadyOwned")
	elseif wanted > current + 1 then
		return fail("OutOfOrder")
	elseif data.coins < prices[tierId] then
		return fail("InsufficientCoins")
	end
	data.coins -= prices[tierId]
	local record: any = data
	record[field] = tierId
	return commit(data, id, op, tierId)
end

function EconomyLedger.purchaseBallTier(
	data: PlayerData,
	id: string,
	tierId: string
): TransactionResult
	return buyTier(
		data,
		id,
		tierId,
		"purchaseBallTier",
		"ballTierId",
		ShopConfigs.BallTierOrder,
		ShopConfigs.BallTierCoinPrices
	)
end

function EconomyLedger.purchaseTargetTier(
	data: PlayerData,
	id: string,
	tierId: string
): TransactionResult
	return buyTier(
		data,
		id,
		tierId,
		"purchaseTargetTier",
		"targetTierId",
		ShopConfigs.TargetTierOrder,
		ShopConfigs.TargetTierCoinPrices
	)
end

function EconomyLedger.expandPedestals(data: PlayerData, id: string): TransactionResult
	local done = precheck(data, id, "expandPedestals", nil)
	if done then
		return done
	end
	if data.pedestalsUnlocked >= ShopConfigs.MAX_PEDESTALS then
		return fail("MaxPedestals")
	end
	local price = ShopConfigs.PedestalPrices[data.pedestalsUnlocked + 1]
	if data.coins < price.coins then
		return fail("InsufficientCoins")
	elseif data.bossGems < price.bossGems then
		return fail("InsufficientBossGems")
	end
	data.coins -= price.coins
	data.bossGems -= price.bossGems
	data.pedestalsUnlocked += 1
	return commit(data, id, "expandPedestals", nil)
end

function EconomyLedger.upgradeOfflineVault(data: PlayerData, id: string): TransactionResult
	local done = precheck(data, id, "upgradeOfflineVault", nil)
	if done then
		return done
	end
	local nextTier = ShopConfigs.OfflineVaultTiers[data.offlineVaultTier + 1]
	if not nextTier then
		return fail("MaxVaultTier")
	elseif data.bossGems < nextTier.bossGems then
		return fail("InsufficientBossGems")
	end
	data.bossGems -= nextTier.bossGems
	data.offlineVaultTier += 1
	return commit(data, id, "upgradeOfflineVault", nil)
end

function EconomyLedger.craftGemEgg(data: PlayerData, id: string, biomeId: string): TransactionResult
	local done = precheck(data, id, "craftGemEgg", biomeId)
	if done then
		return done
	end
	local price = ShopConfigs.GemEggPrices[biomeId]
	if not price then
		return fail("UnknownBiome")
	elseif data.bossGems < price then
		return fail("InsufficientBossGems")
	end
	data.bossGems -= price
	-- Crafted eggs are StandardBiomeEgg: their hatch pool (resolveGemEggMutation) has no exclusives.
	data.eggsById[`Craft:{id}`] = { kind = "StandardBiomeEgg", biomeId = biomeId }
	return commit(data, id, "craftGemEgg", biomeId)
end

local GRANTABLE_EGGS =
	{ StandardBossEgg = true, OverchargedBossEgg = true, StandardBiomeEgg = true }

-- Arena rewards (Boss Egg wins): one egg per transaction id, never a starter egg.
function EconomyLedger.grantEgg(
	data: PlayerData,
	id: string,
	kind: string,
	biomeId: string
): TransactionResult
	local argument = `{kind}:{biomeId}`
	local done = precheck(data, id, "grantEgg", argument)
	if done then
		return done
	end
	if not GRANTABLE_EGGS[kind] then
		return fail("UnknownEggKind")
	elseif not ShopConfigs.GemEggPrices[biomeId] then
		return fail("UnknownBiome")
	end
	data.eggsById[`Egg:{id}`] = { kind = kind, biomeId = biomeId }
	return commit(data, id, "grantEgg", argument)
end

-- Soft Ascension: Coins reset to zero, everything else is kept (GDD §8.7).
function EconomyLedger.softAscend(data: PlayerData, id: string): TransactionResult
	local done = precheck(data, id, "softAscend", nil)
	if done then
		return done
	end
	if data.ascensionRank >= MAX_SAFE then
		return fail("ProgressionOverflow")
	end
	if data.coins < ShopConfigs.getAscensionCoinThreshold(data.ascensionRank) then
		return fail("AscensionThresholdNotMet")
	end
	data.coins = 0
	data.ascensionRank += 1
	return commit(data, id, "softAscend", nil)
end

-- Queries --------------------------------------------------------------------------------------

function EconomyLedger.getOfflineEfficiency(data: PlayerData): number
	local tier = ShopConfigs.OfflineVaultTiers[data.offlineVaultTier]
	return if tier then tier.efficiency else EconomyConfigs.BASE_OFFLINE_EFFICIENCY
end

-- Additive per rank (not compounding): Coins x(1 + 0.25r), training x(1 + 0.05r).
function EconomyLedger.getAscensionMultipliers(data: PlayerData): (number, number)
	local rank = data.ascensionRank
	return 1 + EconomyConfigs.ASCENSION_COIN_BONUS * rank,
		1 + EconomyConfigs.ASCENSION_TRAINING_BONUS * rank
end

-- Server-supplied roll in [0, 1) -> standard pool mutation; nil for any invalid roll.
function EconomyLedger.resolveGemEggMutation(roll: number): StandardEggMutation?
	if not isFinite(roll) or roll < 0 or roll >= 1 then
		return nil
	end
	local cumulative = 0
	for _, entry in ShopConfigs.StandardEggMutationOdds do
		cumulative += entry.percent
		if roll < cumulative / 100 then
			return entry.mutation :: StandardEggMutation
		end
	end
	return nil
end

return EconomyLedger
