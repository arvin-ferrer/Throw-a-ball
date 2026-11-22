--!strict
--[[
	PolicyGuard (Issue #15): Roblox 2026 paid-random-item compliance (AGENTS.md invariant 4).
	Pure: the server passes in its PolicyService snapshot.
	- Paid random eggs are allowed ONLY on an explicit ArePaidRandomItemsRestricted == false;
	  a failed lookup, missing field or wrong type is restricted (fail closed).
	- Every random offer discloses exact odds (basis points summing to exactly 10,000).
	- Restricted players see the egg's deterministic direct bundle instead, never odds.
	- Paid grants are shop species with Normal/Shiny/Golden only: never boss eggs, earned
	  species, Overcharged or Void-Touched.
]]

-- selene: allow(incorrect_standard_library_use) -- string require: same path in Lune and Roblox
local MonetizationConfigs = require("../Configs/MonetizationConfigs")

type Catalog = MonetizationConfigs.Catalog
type OddsRow = MonetizationConfigs.OddsRow
type Bundle = MonetizationConfigs.Bundle

export type DisplayOddsRow = {
	petId: string,
	mutation: string,
	basisPoints: number,
	percentText: string,
}
export type OddsResult = {
	ok: boolean,
	rows: { DisplayOddsRow }?,
	totalBasisPoints: number?,
	totalText: string?,
	reason: string?,
}
export type OfferDisplay = {
	kind: string,
	offerKey: string?,
	productId: number?,
	passId: number?,
	odds: { DisplayOddsRow }?,
	totalText: string?,
	bundle: Bundle?,
	cosmeticKey: string?,
	reason: string?,
}
export type PaidOutcome = { petId: string, mutation: string }

local PolicyGuard = {}

local TOTAL = MonetizationConfigs.ODDS_TOTAL_BASIS_POINTS
local MAX_SAFE = 9_007_199_254_740_991
local PAID_MUTATIONS = { Normal = true, Shiny = true, Golden = true }
local EGG_KINDS = { PermanentEgg = true, SeasonalEgg = true }

local function isSafeId(n: unknown): boolean
	return type(n) == "number" and n == n and n >= 1 and n <= MAX_SAFE and n % 1 == 0
end

function PolicyGuard.isRestricted(snapshot: unknown): boolean
	return not (
		type(snapshot) == "table" and (snapshot :: any).ArePaidRandomItemsRestricted == false
	)
end

-- Odds -----------------------------------------------------------------------------------------

local function validRow(row: unknown): boolean
	if type(row) ~= "table" then
		return false
	end
	local r = row :: any
	return type(r.petId) == "string"
		and r.petId ~= ""
		and type(r.mutation) == "string"
		and r.mutation ~= ""
		and isSafeId(r.basisPoints)
end

function PolicyGuard.formatOdds(rows: unknown): OddsResult
	local invalid = { ok = false, reason = "InvalidOdds" }
	if type(rows) ~= "table" or #(rows :: any) == 0 then
		return invalid
	end
	local list = rows :: { any }
	local count, seen, total, out = 0, {}, 0, {}
	for key in list do
		count += 1
		if type(key) ~= "number" or key < 1 or key > #list or key % 1 ~= 0 then
			return invalid -- sparse or keyed tables can't be disclosed in a stable order
		end
	end
	for _, row in list do
		local pair = validRow(row) and `{row.petId}\0{row.mutation}`
		if count ~= #list or not pair or seen[pair] then
			return invalid
		end
		seen[pair], total = true, total + row.basisPoints
		table.insert(out, {
			petId = row.petId,
			mutation = row.mutation,
			basisPoints = row.basisPoints,
			percentText = string.format("%d.%02d%%", row.basisPoints // 100, row.basisPoints % 100),
		})
	end
	if total ~= TOTAL then
		return invalid
	end
	return { ok = true, rows = out, totalBasisPoints = total, totalText = "100.0%" }
end

-- Grant safety --------------------------------------------------------------------------------------

local function safePet(petId: unknown, mutation: unknown): boolean
	return type(petId) == "string"
		and MonetizationConfigs.ShopPets[petId] ~= nil
		and PAID_MUTATIONS[mutation :: any] == true
end

local function safeBundle(bundle: Bundle?): boolean
	return bundle ~= nil
		and safePet(bundle.petId, bundle.mutation)
		and MonetizationConfigs.Cosmetics[bundle.cosmeticKey] ~= nil
end

-- A pool is usable only if every outcome is grant-safe and the odds are exact.
local function poolError(pool: MonetizationConfigs.PaidEggPool?, kind: string): string?
	if not pool or pool.kind ~= kind then
		return "InvalidOffer"
	end
	for _, row in pool.odds do
		if not safePet(row.petId, row.mutation) then
			return "ForbiddenGrant"
		end
	end
	return if PolicyGuard.formatOdds(pool.odds).ok then nil else "InvalidOdds"
end

-- Offers ----------------------------------------------------------------------------------------------

local function idError(id: unknown): string?
	if id == 0 then
		return "DisabledOffer" -- TODO placeholders stay off until a real Creator Dashboard id
	end
	return if isSafeId(id) then nil else "InvalidOffer"
end

local function isAmbiguous(catalog: Catalog, productId: number): boolean
	local uses = 0
	for _, product in catalog.products do
		if product.productId == productId then
			uses += 1
		end
	end
	return uses > 1
end

local function productError(
	snapshot: unknown,
	product: MonetizationConfigs.DeveloperProduct,
	catalog: Catalog
): string?
	local bad = idError(product.productId)
	if bad then
		return bad
	elseif isAmbiguous(catalog, product.productId) then
		return "AmbiguousProductId"
	elseif EGG_KINDS[product.kind] then
		local poolBad =
			poolError(product.poolKey and catalog.paidEggPools[product.poolKey], product.kind)
		if poolBad then
			return poolBad
		end
		return if PolicyGuard.isRestricted(snapshot) then "PolicyRestricted" else nil
	elseif product.kind == "DirectBundle" then
		return if safeBundle(product.bundle) then nil else "ForbiddenGrant"
	elseif product.kind == "Cosmetic" then
		return if MonetizationConfigs.Cosmetics[product.cosmeticKey] then nil else "ForbiddenGrant"
	end
	return "ForbiddenGrant" -- Boss Eggs and anything unknown are never sold for Robux
end

-- Exactly the requested offer (never a substitute): (true, nil) or (false, reason).
function PolicyGuard.canPurchase(
	snapshot: unknown,
	offerKey: string,
	catalog: Catalog?
): (boolean, string?)
	local cat = catalog or MonetizationConfigs.Catalog
	local product = cat.products[offerKey]
	local pass = cat.gamePasses[offerKey]
	local reason = if product
		then productError(snapshot, product, cat)
		elseif pass then idError(pass.passId)
		else "UnknownOffer"
	return reason == nil, reason
end

local function unavailable(reason: string?): OfferDisplay
	return { kind = "Unavailable", reason = reason }
end

local function bundleDisplay(snapshot: unknown, key: string?, cat: Catalog): OfferDisplay
	local product = key and cat.products[key]
	if
		not (
			key
			and product
			and product.kind == "DirectBundle"
			and PolicyGuard.canPurchase(snapshot, key, cat)
		)
	then
		return unavailable("NoEligibleFallback")
	end
	return {
		kind = "DirectBundle",
		offerKey = key,
		productId = product.productId,
		bundle = product.bundle,
	}
end

function PolicyGuard.getOfferDisplay(
	snapshot: unknown,
	offerKey: string,
	catalog: Catalog?
): OfferDisplay
	local cat = catalog or MonetizationConfigs.Catalog
	local product, pass = cat.products[offerKey], cat.gamePasses[offerKey]
	local allowed, reason = PolicyGuard.canPurchase(snapshot, offerKey, cat)
	if pass and not product then
		return if allowed
			then { kind = "GamePass", offerKey = offerKey, passId = pass.passId }
			else unavailable(reason)
	elseif not product then
		return unavailable(reason)
	elseif EGG_KINDS[product.kind] and PolicyGuard.isRestricted(snapshot) then
		return bundleDisplay(snapshot, product.directBundleKey, cat) -- never odds or a random prompt
	elseif not allowed then
		return unavailable(reason)
	elseif EGG_KINDS[product.kind] then
		local odds = PolicyGuard.formatOdds(cat.paidEggPools[product.poolKey :: string].odds)
		return {
			kind = "PaidEgg",
			offerKey = offerKey,
			productId = product.productId,
			odds = odds.rows,
			totalText = odds.totalText,
		}
	elseif product.kind == "DirectBundle" then
		return bundleDisplay(snapshot, offerKey, cat)
	end
	return {
		kind = "Cosmetic",
		offerKey = offerKey,
		productId = product.productId,
		cosmeticKey = product.cosmeticKey,
	}
end

-- The paid hatch uses the very table shown on the billboard and purchase modal.
function PolicyGuard.resolvePaidEggRoll(
	poolKey: string,
	roll: number,
	catalog: Catalog?
): PaidOutcome?
	local cat = catalog or MonetizationConfigs.Catalog
	local pool = cat.paidEggPools[poolKey]
	if
		not pool
		or poolError(pool, pool.kind)
		or type(roll) ~= "number"
		or not (roll >= 0 and roll < 1)
	then
		return nil
	end
	local cumulative = 0
	for _, row in pool.odds do
		cumulative += row.basisPoints
		if roll < cumulative / TOTAL then
			return { petId = row.petId, mutation = row.mutation }
		end
	end
	return nil
end

return PolicyGuard
