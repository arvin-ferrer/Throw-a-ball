--!strict
--[[
	PolicyLogic.luau
	Pure Roblox 2026 Paid Random Items compliance logic & idempotent receipt handler
	(100% Lune-testable with mocked PolicyService responses).
]]

local req: any = require
local scriptRef: any = script
local isRoblox = type(scriptRef) == "userdata"
local EggConfigs = if isRoblox
	then req(scriptRef.Parent.Parent.Configs.EggConfigs)
	else req("../Configs/EggConfigs")
local MonetizationConfigs = if isRoblox
	then req(scriptRef.Parent.Parent.Configs.MonetizationConfigs)
	else req("../Configs/MonetizationConfigs")
local MathUtil = if isRoblox then req(scriptRef.Parent.MathUtil) else req("./MathUtil")

export type DisclosedOdd = {
	id: string,
	percent: number,
}

export type ShopCatalogItem = {
	kind: "PaidEgg" | "DirectBundle",
	id: string,
	displayName: string,
	description: string,
	devProductId: number,
	petOdds: { DisclosedOdd }?,
	mutationOdds: { DisclosedOdd }?,
	guaranteedPetId: string?,
	guaranteedBallSkin: string?,
}

export type ReceiptResult = {
	granted: boolean,
	duplicate: boolean,
	reason: string?,
}

local PolicyLogic = {}

PolicyLogic.MAX_PURCHASE_LOG = 100

function PolicyLogic.buildShopOfferings(arePaidRandomItemsRestricted: boolean): { ShopCatalogItem }
	local items: { ShopCatalogItem } = {}
	local paidEggs = { "Shop_PrismEgg", "Seasonal_CyberEgg" }
	for _, eggId in ipairs(paidEggs) do
		local egg = EggConfigs.getEgg(eggId)
		if egg and EggConfigs.isRobuxPurchasable(eggId) then
			if arePaidRandomItemsRestricted ~= false then
				local bundle = MonetizationConfigs.getDirectBundleForEgg(eggId)
				if bundle then
					table.insert(items, {
						kind = "DirectBundle",
						id = bundle.id,
						displayName = bundle.displayName,
						description = bundle.description,
						devProductId = bundle.devProductId,
						guaranteedPetId = bundle.guaranteedPetId,
						guaranteedBallSkin = bundle.guaranteedBallSkin,
					})
				end
			else
				local petOdds, mutOdds = EggConfigs.getDisclosedOdds(eggId)
				table.insert(items, {
					kind = "PaidEgg",
					id = egg.id,
					displayName = egg.displayName,
					description = "100% Disclosed Odds — Shop Exclusive Creatures",
					devProductId = egg.devProductId or 0,
					petOdds = petOdds,
					mutationOdds = mutOdds,
				})
			end
		end
	end
	return items
end

function PolicyLogic.canPromptProduct(
	productId: number,
	arePaidRandomItemsRestricted: boolean
): (boolean, string?)
	local kind, itemId = MonetizationConfigs.getProductByDevProductId(productId)
	if not kind or not itemId then
		return false, "UnknownProduct"
	end
	if kind == "PaidEgg" then
		if arePaidRandomItemsRestricted ~= false then
			return false, "PaidRandomItemsRestricted"
		end
		if not EggConfigs.isRobuxPurchasable(itemId) then
			return false, "EggNotRobuxPurchasable"
		end
		return true, nil
	end
	return true, nil
end

function PolicyLogic.hasRecordedPurchase(profile: any, purchaseId: string): boolean
	if type(profile) ~= "table" or type(purchaseId) ~= "string" then
		return false
	end
	if
		type(profile.processedPurchases) == "table"
		and profile.processedPurchases[purchaseId] == true
	then
		return true
	end
	if type(profile.purchaseIds) == "table" then
		for _, id in ipairs(profile.purchaseIds) do
			if id == purchaseId then
				return true
			end
		end
	end
	return false
end

local function grantDirectBundle(profile: any, itemId: string): boolean
	local bundle = MonetizationConfigs.DIRECT_BUNDLES[itemId]
	if not bundle then
		return false
	end
	local uid = `pet_{profile.nextPetSeq}`
	profile.nextPetSeq += 1
	table.insert(profile.pets, {
		uid = uid,
		speciesId = bundle.guaranteedPetId,
		mutationKey = bundle.guaranteedMutation,
		starTier = 1,
		level = 1,
		traitKey = nil,
		pedestalIndex = nil,
	})
	profile.codexUnlocked[bundle.guaranteedPetId] = true
	profile.ownedCosmetics[bundle.guaranteedBallSkin] = true
	profile.equippedBallSkin = bundle.guaranteedBallSkin
	return true
end

local function recordPurchase(profile: any, purchaseId: string)
	if type(profile.processedPurchases) ~= "table" then
		profile.processedPurchases = {}
	end
	profile.processedPurchases[purchaseId] = true
	table.insert(profile.purchaseIds, purchaseId)
	while #profile.purchaseIds > PolicyLogic.MAX_PURCHASE_LOG do
		table.remove(profile.purchaseIds, 1)
	end
end

function PolicyLogic.applyProductReceipt(
	profile: any,
	purchaseId: string,
	productId: number,
	arePaidRandomItemsRestricted: boolean
): ReceiptResult
	if
		type(profile) ~= "table"
		or type(purchaseId) ~= "string"
		or purchaseId == ""
		or not MathUtil.isFinite(productId)
	then
		return { granted = false, duplicate = false, reason = "InvalidReceiptArgs" }
	end
	if PolicyLogic.hasRecordedPurchase(profile, purchaseId) then
		return { granted = true, duplicate = true, reason = "AlreadyProcessed" }
	end
	local kind, itemId = MonetizationConfigs.getProductByDevProductId(productId)
	if not kind or not itemId then
		return { granted = false, duplicate = false, reason = "UnknownProduct" }
	end
	if kind == "PaidEgg" then
		if arePaidRandomItemsRestricted ~= false or not EggConfigs.isRobuxPurchasable(itemId) then
			return { granted = false, duplicate = false, reason = "RestrictedOrForbiddenEgg" }
		end
		profile.eggs[itemId] = (profile.eggs[itemId] or 0) + 1
	elseif kind == "DirectBundle" then
		if not grantDirectBundle(profile, itemId) then
			return { granted = false, duplicate = false, reason = "UnknownBundle" }
		end
	end
	recordPurchase(profile, purchaseId)
	return { granted = true, duplicate = false, reason = nil }
end

return PolicyLogic
