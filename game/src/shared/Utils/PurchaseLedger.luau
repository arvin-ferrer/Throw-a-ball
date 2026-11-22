--!strict
--[[
	PurchaseLedger (Issue #15): Developer Product receipts over the player profile. Pure.
	Each PurchaseId is granted exactly once: a "Robux:<PurchaseId>" marker in the same
	transactionReceipts map is committed together with the reward (no yield in between).
	An exact replay is AlreadyGranted even if the policy or catalog changed since.
	The Roblox wrapper returns PurchaseGranted only after that marker is in the saved data.
]]

-- selene: allow(incorrect_standard_library_use) -- string require: same path in Lune and Roblox
local EconomyLedger = require("./EconomyLedger")
-- selene: allow(incorrect_standard_library_use)
local MonetizationConfigs = require("../Configs/MonetizationConfigs")
-- selene: allow(incorrect_standard_library_use)
local PolicyGuard = require("./PolicyGuard")

type PlayerData = EconomyLedger.PlayerData
type Catalog = MonetizationConfigs.Catalog

export type ReceiptInfo = { PurchaseId: string, ProductId: number, PlayerId: number }
export type Decision = "Granted" | "AlreadyGranted" | "Rejected"
export type Result = { decision: Decision, reason: string? }
export type PaidEggData = { kind: string, poolKey: string, biomeId: nil }
export type RecentPurchase = { purchaseId: string, productId: number }

local PurchaseLedger = {}

local OPERATION = "processDeveloperProduct"
local MAX_SAFE = 9_007_199_254_740_991
local EGG_KIND = { PermanentEgg = "PaidPermanentEgg", SeasonalEgg = "PaidSeasonalEgg" }

local function isSafeId(n: unknown): boolean
	return type(n) == "number" and n == n and n >= 1 and n <= MAX_SAFE and n % 1 == 0
end

local function rejected(reason: string): Result
	return { decision = "Rejected", reason = reason }
end

local function validReceipt(raw: unknown): ReceiptInfo?
	if type(raw) ~= "table" then
		return nil
	end
	local r = raw :: any
	if
		type(r.PurchaseId) ~= "string"
		or r.PurchaseId == ""
		or not isSafeId(r.ProductId)
		or not isSafeId(r.PlayerId)
	then
		return nil
	end
	return r :: ReceiptInfo
end

-- The one catalog key whose active product id matches, or a rejection reason.
local function resolveProduct(cat: Catalog, productId: number): (string?, string?)
	local found: string? = nil
	for key, product in cat.products do
		if product.productId == productId then
			if found then
				return nil, "AmbiguousProductId"
			end
			found = key
		end
	end
	return found, if found then nil else "UnknownProduct"
end

local function isArray(value: unknown): boolean
	if type(value) ~= "table" then
		return false
	end
	local count = 0
	for _ in value :: any do
		count += 1
	end
	return count == #(value :: any) -- dense 1..n only
end

-- Destinations must be free and storage well-formed before anything is written.
local function preflight(
	data: PlayerData,
	product: MonetizationConfigs.DeveloperProduct,
	purchaseId: string
): string?
	local log = data.extensions.recentRobuxPurchases
	if log ~= nil and not isArray(log) then
		return "InvalidPurchaseLog"
	end
	local cosmetics = data.extensions.ownedCosmeticKeys
	local needsCosmetic = product.kind == "DirectBundle" or product.kind == "Cosmetic"
	if needsCosmetic and cosmetics ~= nil and type(cosmetics) ~= "table" then
		return "InvalidProfile"
	end
	if EGG_KIND[product.kind] and data.eggsById[`PurchaseEgg:{purchaseId}`] then
		return "GrantConflict"
	elseif product.kind == "DirectBundle" and data.petsById[`PurchasePet:{purchaseId}`] then
		return "GrantConflict"
	end
	return nil
end

local function grant(
	data: PlayerData,
	product: MonetizationConfigs.DeveloperProduct,
	purchaseId: string
)
	local ext = data.extensions
	if EGG_KIND[product.kind] then
		-- The pool key is pinned to the egg so later catalog edits can't change what was bought.
		data.eggsById[`PurchaseEgg:{purchaseId}`] =
			{ kind = EGG_KIND[product.kind], poolKey = product.poolKey } :: any
		return
	end
	ext.ownedCosmeticKeys = ext.ownedCosmeticKeys or {}
	local bundle = product.bundle
	if product.kind == "DirectBundle" and bundle then
		data.petsById[`PurchasePet:{purchaseId}`] =
			{ petId = bundle.petId, mutation = bundle.mutation, level = 1, stars = 1 }
		ext.ownedCosmeticKeys[bundle.cosmeticKey] = true
	elseif product.cosmeticKey then
		ext.ownedCosmeticKeys[product.cosmeticKey] = true
	end
end

local function appendLog(data: PlayerData, purchaseId: string, productId: number)
	local log = data.extensions.recentRobuxPurchases or {}
	data.extensions.recentRobuxPurchases = log
	table.insert(log, { purchaseId = purchaseId, productId = productId })
	while #log > MonetizationConfigs.RECENT_PURCHASE_LIMIT do
		table.remove(log, 1) -- the permanent receipt marker still blocks any replay
	end
end

function PurchaseLedger.processReceipt(
	data: PlayerData,
	ownerUserId: number,
	receiptInfo: unknown,
	policySnapshot: unknown,
	catalog: Catalog?
): Result
	local receipt = validReceipt(receiptInfo)
	if not receipt then
		return rejected("InvalidReceipt")
	elseif receipt.PlayerId ~= ownerUserId then
		return rejected("WrongPlayer") -- checked before any replay lookup
	end
	local id = `Robux:{receipt.PurchaseId}`
	local done = EconomyLedger.precheck(data, id, OPERATION, receipt.ProductId)
	if done then
		return if done.ok then { decision = "AlreadyGranted" } else rejected("PurchaseIdConflict")
	end
	local cat = catalog or MonetizationConfigs.Catalog
	local key, missing = resolveProduct(cat, receipt.ProductId)
	if not key then
		return rejected(missing or "UnknownProduct")
	end
	local allowed, reason = PolicyGuard.canPurchase(policySnapshot, key, cat)
	if not allowed then
		return rejected(reason or "Rejected") -- a denied egg is never swapped for its bundle
	end
	local product = cat.products[key]
	local bad = preflight(data, product, receipt.PurchaseId)
	if bad then
		return rejected(bad)
	end
	grant(data, product, receipt.PurchaseId)
	appendLog(data, receipt.PurchaseId, receipt.ProductId)
	EconomyLedger.commit(data, id, OPERATION, receipt.ProductId)
	return { decision = "Granted" }
end

return PurchaseLedger
