--!strict
--[[
	PriceFormatter.spec.luau
	Unit tests for regional/managed Robux price parsing, formatting and TTL cache:
	- Comma integer formatting with rounding, negatives & non-finite guards
	- Robux price formatting (FREE, commas, fallbacks for nil/negative/NaN)
	- Regional discount percentage calculation and 70% cap
	- MarketplaceService ProductInfo parsing (regional, standard, FREE, off-sale, malformed)
	- Action button labels (compact, standard, FREE, OFF SALE, fallback)
	- Cache keys & success/failure TTL freshness + clock skew protection
]]

local PriceFormatter = require("../src/shared/Utils/PriceFormatter")

local function run(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	assert(ok, `{name}: {err}`)
end

run("formatIntegerWithCommas handles thresholds, negatives, rounding and non-finite", function()
	assert(PriceFormatter.formatIntegerWithCommas(0) == "0", "0")
	assert(PriceFormatter.formatIntegerWithCommas(99) == "99", "99")
	assert(PriceFormatter.formatIntegerWithCommas(999) == "999", "999")
	assert(PriceFormatter.formatIntegerWithCommas(1000) == "1,000", "1,000")
	assert(PriceFormatter.formatIntegerWithCommas(12345) == "12,345", "12,345")
	assert(PriceFormatter.formatIntegerWithCommas(1234567) == "1,234,567", "1,234,567")
	assert(PriceFormatter.formatIntegerWithCommas(-4500) == "-4,500", "negative formatted")
	assert(PriceFormatter.formatIntegerWithCommas(1499.6) == "1,500", "rounds half-up")
	assert(PriceFormatter.formatIntegerWithCommas(0 / 0) == "0", "NaN -> 0")
	assert(PriceFormatter.formatIntegerWithCommas(math.huge) == "0", "+inf -> 0")
	assert(PriceFormatter.formatIntegerWithCommas(-math.huge) == "0", "-inf -> 0")
end)

run("formatRobux handles FREE, valid amounts and invalid/negative fallbacks", function()
	assert(PriceFormatter.formatRobux(0) == "FREE", "0 -> FREE")
	assert(PriceFormatter.formatRobux(0.4) == "FREE", "rounds to 0 -> FREE")
	assert(PriceFormatter.formatRobux(49) == "49 R$", "49 R$")
	assert(PriceFormatter.formatRobux(1999) == "1,999 R$", "comma Robux")
	assert(PriceFormatter.formatRobux(99.6) == "100 R$", "rounded Robux")

	for _, bad in ipairs({ nil, "100", -1, -0.01, 0 / 0, math.huge, -math.huge } :: { any }) do
		assert(PriceFormatter.formatRobux(bad) == "ROBUX", "invalid -> default ROBUX")
		assert(PriceFormatter.formatRobux(bad, "N/A") == "N/A", "invalid -> custom fallback")
	end
end)

run("computeDiscountPercent calculates regional discounts and caps at 70%", function()
	assert(PriceFormatter.computeDiscountPercent(70, 100) == 30, "30% off")
	assert(PriceFormatter.computeDiscountPercent(67, 100) == 33, "33% off")
	assert(PriceFormatter.computeDiscountPercent(10, 100) == 70, "capped at 70%")
	assert(PriceFormatter.computeDiscountPercent(0, 100) == 70, "0 price capped at 70%")
	assert(PriceFormatter.computeDiscountPercent(100, 100) == 0, "same price -> 0%")
	assert(PriceFormatter.computeDiscountPercent(120, 100) == 0, "higher price -> 0%")
	assert(PriceFormatter.computeDiscountPercent(50, nil) == 0, "nil base -> 0%")
	assert(PriceFormatter.computeDiscountPercent(50, 0) == 0, "0 base -> 0%")
	assert(PriceFormatter.computeDiscountPercent(50, -100) == 0, "neg base -> 0%")
	assert(PriceFormatter.computeDiscountPercent(-10, 100) == 0, "neg localized -> 0%")
	assert(PriceFormatter.computeDiscountPercent(0 / 0, 100) == 0, "NaN localized -> 0%")
	assert(PriceFormatter.computeDiscountPercent(50, 0 / 0) == 0, "NaN base -> 0%")
end)

run("parseProductInfo handles standard, regional, FREE, off-sale and malformed inputs", function()
	local std = PriceFormatter.parseProductInfo({ PriceInRobux = 249, IsForSale = true }, 249)
	assert(std.robux == 249 and not std.isRegional and not std.isOffSale)
	assert(std.discountPercent == 0 and std.formatted == "249 R$" and std.badgeText == nil)

	local reg = PriceFormatter.parseProductInfo({ PriceInRobux = 149, IsForSale = true }, 249)
	assert(reg.robux == 149 and reg.isRegional and reg.discountPercent == 40)
	assert(reg.formatted == "149 R$" and reg.badgeText == "-40% REGIONAL")

	local free = PriceFormatter.parseProductInfo({ PriceInRobux = 0, IsForSale = true })
	assert(free.robux == 0 and free.formatted == "FREE" and not free.isOffSale)

	local offSale = PriceFormatter.parseProductInfo({ PriceInRobux = nil, IsForSale = false }, 199)
	assert(offSale.robux == nil and offSale.isOffSale and offSale.formatted == "OFF SALE")

	local missingPrice = PriceFormatter.parseProductInfo({ IsForSale = true })
	assert(
		missingPrice.robux == nil
			and not missingPrice.isOffSale
			and missingPrice.formatted == "ROBUX"
	)

	local badPrice = PriceFormatter.parseProductInfo({ PriceInRobux = -5, IsForSale = true })
	assert(badPrice.robux == nil and badPrice.formatted == "ROBUX")

	local nanPrice = PriceFormatter.parseProductInfo({ PriceInRobux = 0 / 0 })
	assert(nanPrice.robux == nil and nanPrice.formatted == "ROBUX")

	for _, garbage in ipairs({ nil, 42, "bad", false } :: { any }) do
		local q = PriceFormatter.parseProductInfo(garbage, 100)
		assert(q.robux == nil and not q.isRegional and not q.isOffSale and q.formatted == "ROBUX")
	end
end)

run("formatActionLabel formats full, compact, FREE, OFF SALE and fallback labels", function()
	local std = PriceFormatter.parseProductInfo({ PriceInRobux = 399 }, 399)
	local free = PriceFormatter.parseProductInfo({ PriceInRobux = 0 })
	local offSale = PriceFormatter.parseProductInfo({ IsForSale = false })
	local unpriced = PriceFormatter.parseProductInfo({})

	assert(PriceFormatter.formatActionLabel("BUY", std, false) == "BUY • 399 R$", "full label")
	assert(PriceFormatter.formatActionLabel("BUY", std, true) == "399 R$", "compact label")
	assert(PriceFormatter.formatActionLabel("BUY", free, false) == "FREE", "FREE overrides")
	assert(PriceFormatter.formatActionLabel("BUY", offSale, false) == "OFF SALE", "OFF SALE")
	assert(PriceFormatter.formatActionLabel("BUY", nil, false) == "BUY", "nil -> baseLabel")
	assert(PriceFormatter.formatActionLabel("BUY", nil, false, "LOADING") == "LOADING", "fallback")
	assert(
		PriceFormatter.formatActionLabel("BUY", unpriced, false, "CHECK PRICE") == "CHECK PRICE",
		"unpriced -> fallbackLabel"
	)
end)

run("makeCacheKey and isCacheEntryFresh enforce success/failure TTLs and clock skew", function()
	assert(PriceFormatter.makeCacheKey("GamePass", 12345.9) == "GamePass:12345", "GamePass key")
	assert(PriceFormatter.makeCacheKey("Product", 99001) == "Product:99001", "Product key")

	local okQuote = PriceFormatter.parseProductInfo({ PriceInRobux = 100 })
	local okEntry: PriceFormatter.CacheEntry = { quote = okQuote, fetchedAt = 1000, ok = true }
	local errEntry: PriceFormatter.CacheEntry = { quote = okQuote, fetchedAt = 1000, ok = false }

	assert(PriceFormatter.isCacheEntryFresh(okEntry, 1000), "age 0 fresh")
	assert(PriceFormatter.isCacheEntryFresh(okEntry, 1299.9), "age < 300s fresh")
	assert(not PriceFormatter.isCacheEntryFresh(okEntry, 1300), "age == 300s stale")
	assert(not PriceFormatter.isCacheEntryFresh(okEntry, 999), "negative age (skew) stale")

	assert(PriceFormatter.isCacheEntryFresh(errEntry, 1029.9), "failure < 30s cached")
	assert(not PriceFormatter.isCacheEntryFresh(errEntry, 1030), "failure >= 30s retries")
	assert(PriceFormatter.isCacheEntryFresh(okEntry, 1050, 60, 10), "custom success TTL")
	assert(not PriceFormatter.isCacheEntryFresh(errEntry, 1010, 60, 10), "custom failure TTL")
	assert(not PriceFormatter.isCacheEntryFresh(nil, 1000), "nil entry stale")
	assert(not PriceFormatter.isCacheEntryFresh(okEntry, 0 / 0), "NaN now stale")
	assert(
		not PriceFormatter.isCacheEntryFresh(
			{ quote = okQuote, fetchedAt = 0 / 0, ok = true },
			1000
		),
		"NaN fetchedAt stale"
	)
end)

print("PASS: PriceFormatter.spec.luau")
