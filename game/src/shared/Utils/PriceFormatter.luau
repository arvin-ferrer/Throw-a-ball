--!strict
--[[
	PriceFormatter.luau
	Pure Luau regional/managed pricing parser, formatter, and TTL cache helpers
	for MarketplaceService:GetProductInfoAsync responses (100% Lune-testable).
]]

local req: any = require
local scriptRef: any = script
local isRoblox = type(scriptRef) == "userdata"
local MathUtil = if isRoblox then req(scriptRef.Parent.MathUtil) else req("./MathUtil")

export type ProductInfoTypeName = "GamePass" | "Product"

export type PriceQuote = {
	robux: number?,
	isRegional: boolean,
	isOffSale: boolean,
	discountPercent: number,
	formatted: string,
	badgeText: string?,
}

export type CacheEntry = {
	quote: PriceQuote,
	fetchedAt: number,
	ok: boolean,
}

local PriceFormatter = {}

PriceFormatter.DEFAULT_CACHE_TTL_SEC = 300
PriceFormatter.FAILURE_RETRY_SEC = 30
PriceFormatter.MAX_REGIONAL_DISCOUNT_PCT = 70

function PriceFormatter.formatIntegerWithCommas(value: number): string
	if not MathUtil.isFinite(value) then
		return "0"
	end
	local rounded = math.floor(math.abs(value) + 0.5)
	local sign = if value < 0 then "-" else ""
	local digits = tostring(rounded)
	local out = digits
	while true do
		local nextStr, subs = string.gsub(out, "^(%d+)(%d%d%d)", "%1,%2")
		out = nextStr
		if subs == 0 then
			break
		end
	end
	return sign .. out
end

function PriceFormatter.formatRobux(amount: any, fallbackText: string?): string
	if type(amount) ~= "number" or not MathUtil.isFinite(amount) or amount < 0 then
		return fallbackText or "ROBUX"
	end
	local rounded = math.floor(amount + 0.5)
	if rounded == 0 then
		return "FREE"
	end
	return `{PriceFormatter.formatIntegerWithCommas(rounded)} R$`
end

function PriceFormatter.computeDiscountPercent(
	localizedRobux: number,
	basePriceRobux: number?
): number
	if
		type(basePriceRobux) ~= "number"
		or not MathUtil.isPositiveFinite(basePriceRobux)
		or not MathUtil.isFinite(localizedRobux)
		or localizedRobux < 0
		or localizedRobux >= basePriceRobux
	then
		return 0
	end
	local rawPct = ((basePriceRobux - localizedRobux) / basePriceRobux) * 100
	return math.clamp(math.floor(rawPct + 0.5), 0, PriceFormatter.MAX_REGIONAL_DISCOUNT_PCT)
end

function PriceFormatter.parseProductInfo(info: any, basePriceRobux: number?): PriceQuote
	if type(info) ~= "table" then
		return {
			robux = nil,
			isRegional = false,
			isOffSale = false,
			discountPercent = 0,
			formatted = "ROBUX",
			badgeText = nil,
		}
	end
	local rawPrice = info.PriceInRobux
	local validPrice = type(rawPrice) == "number" and MathUtil.isFinite(rawPrice) and rawPrice >= 0
	if not validPrice then
		local offSale = info.IsForSale == false
		return {
			robux = nil,
			isRegional = false,
			isOffSale = offSale,
			discountPercent = 0,
			formatted = if offSale then "OFF SALE" else "ROBUX",
			badgeText = nil,
		}
	end
	local rounded = math.floor(rawPrice + 0.5)
	local discountPct = PriceFormatter.computeDiscountPercent(rounded, basePriceRobux)
	local isRegional = discountPct > 0
	return {
		robux = rounded,
		isRegional = isRegional,
		isOffSale = false,
		discountPercent = discountPct,
		formatted = PriceFormatter.formatRobux(rounded),
		badgeText = if isRegional then `-{discountPct}% REGIONAL` else nil,
	}
end

function PriceFormatter.formatActionLabel(
	baseLabel: string,
	quote: PriceQuote?,
	compact: boolean?,
	fallbackLabel: string?
): string
	if not quote then
		return fallbackLabel or baseLabel
	end
	if quote.isOffSale then
		return "OFF SALE"
	end
	if quote.robux == nil then
		return fallbackLabel or baseLabel
	end
	if quote.robux == 0 then
		return "FREE"
	end
	if compact then
		return quote.formatted
	end
	return `{baseLabel} • {quote.formatted}`
end

function PriceFormatter.makeCacheKey(infoTypeName: ProductInfoTypeName, productId: number): string
	return `{infoTypeName}:{math.floor(productId)}`
end

function PriceFormatter.isCacheEntryFresh(
	entry: CacheEntry?,
	now: number,
	successTtlSec: number?,
	failureRetrySec: number?
): boolean
	if not entry or not MathUtil.isFinite(now) or not MathUtil.isFinite(entry.fetchedAt) then
		return false
	end
	local age = now - entry.fetchedAt
	if age < 0 then
		return false
	end
	local limit = if entry.ok
		then (successTtlSec or PriceFormatter.DEFAULT_CACHE_TTL_SEC)
		else (failureRetrySec or PriceFormatter.FAILURE_RETRY_SEC)
	return age < limit
end

return PriceFormatter
