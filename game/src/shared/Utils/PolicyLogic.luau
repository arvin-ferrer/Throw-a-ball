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
local EconomyLogic = if isRoblox then req(scriptRef.Parent.EconomyLogic) else req("./EconomyLogic")
local MathUtil = if isRoblox then req(scriptRef.Parent.MathUtil) else req("./MathUtil")

export type DisclosedOdd = {
	id: string,
	percent: number,
}

export type JointOdd = {
	speciesId: string,
	mutationKey: string,
	percent: number,
	formattedPercent: string,
}

export type ShopCatalogItem = {
	kind: "PaidEgg" | "DirectBundle",
	id: string,
	displayName: string,
	description: string,
	devProductId: number,
	petOdds: { DisclosedOdd }?,
	mutationOdds: { DisclosedOdd }?,
	jointOdds: { JointOdd }?,
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

local function distributeBpsRemainders(
	entries: {
		{
			speciesId: string,
			mutationKey: string,
			bps: number,
			rem: number,
			idx: number,
		}
	},
	deficit: number
)
	if deficit <= 0 then
		return
	end
	local order: { number } = {}
	for idx = 1, #entries do
		table.insert(order, idx)
	end
	table.sort(order, function(a, b)
		if math.abs(entries[a].rem - entries[b].rem) > 1e-12 then
			return entries[a].rem > entries[b].rem
		end
		return entries[a].idx < entries[b].idx
	end)
	for k = 1, math.min(deficit, #order) do
		entries[order[k]].bps += 1
	end
end

function PolicyLogic.computeJointOdds(eggId: string): { JointOdd }
	local egg = EggConfigs.getEgg(eggId)
	if not egg then
		return {}
	end
	local petSum = EggConfigs.getWeightSum(egg.petTable)
	local mutSum = EggConfigs.getWeightSum(egg.mutationTable)
	if petSum <= 0 or mutSum <= 0 then
		return {}
	end
	local raw: { { speciesId: string, mutationKey: string, bps: number, rem: number, idx: number } } =
		{}
	local bpsSum = 0
	for _, petEntry in ipairs(egg.petTable) do
		for _, mutEntry in ipairs(egg.mutationTable) do
			local exactBps = (petEntry.weight / petSum) * (mutEntry.weight / mutSum) * 10000
			local floorBps = math.floor(exactBps + 1e-9)
			bpsSum += floorBps
			table.insert(raw, {
				speciesId = petEntry.id,
				mutationKey = mutEntry.id,
				bps = floorBps,
				rem = math.max(0, exactBps - floorBps),
				idx = #raw + 1,
			})
		end
	end
	distributeBpsRemainders(raw, 10000 - bpsSum)
	local out: { JointOdd } = {}
	for _, entry in ipairs(raw) do
		local pct = entry.bps / 100
		table.insert(out, {
			speciesId = entry.speciesId,
			mutationKey = entry.mutationKey,
			percent = pct,
			formattedPercent = string.format("%.2f%%", pct),
		})
	end
	return out
end

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
					jointOdds = PolicyLogic.computeJointOdds(eggId),
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

function PolicyLogic.isPaidRandomEgg(eggId: string): boolean
	local egg = if type(eggId) == "string" then EggConfigs.getEgg(eggId) else nil
	return egg ~= nil and egg.isPaidRandomItem == true
end

local function awardDirectBundleContents(
	profile: any,
	bundle: MonetizationConfigs.DirectBundleSpec,
	pedestalIndex: number?,
	equipBallSkin: boolean
): EconomyLogic.OwnedPet
	local seq = if MathUtil.isPositiveFinite(profile.nextPetSeq)
		then math.floor(profile.nextPetSeq)
		else 1
	local uid = `pet_{seq}`
	profile.nextPetSeq = seq + 1
	local newPet: EconomyLogic.OwnedPet = {
		uid = uid,
		speciesId = bundle.guaranteedPetId,
		mutationKey = bundle.guaranteedMutation,
		starTier = 1,
		level = 1,
		traitKey = nil,
		pedestalIndex = pedestalIndex,
	}
	table.insert(profile.pets, newPet)
	if type(profile.codexUnlocked) ~= "table" then
		profile.codexUnlocked = {}
	end
	profile.codexUnlocked[bundle.guaranteedPetId] = true
	if type(profile.ownedCosmetics) ~= "table" then
		profile.ownedCosmetics = {}
	end
	profile.ownedCosmetics[bundle.guaranteedBallSkin] = true
	if equipBallSkin or profile.equippedBallSkin == nil then
		profile.equippedBallSkin = bundle.guaranteedBallSkin
	end
	return newPet
end

local function grantDirectBundle(profile: any, itemId: string): boolean
	local bundle = MonetizationConfigs.DIRECT_BUNDLES[itemId]
	if not bundle then
		return false
	end
	awardDirectBundleContents(profile, bundle, nil, true)
	return true
end

local function validatePaidHatchSlot(
	profile: any,
	eggId: string,
	pedestalIndex: number,
	hasVipPass: boolean
): string?
	if type(profile) ~= "table" or type(eggId) ~= "string" then
		return "InvalidArgs"
	end
	if not EggConfigs.getEgg(eggId) then
		return "UnknownEgg"
	end
	if type(profile.eggs) ~= "table" or (profile.eggs[eggId] or 0) < 1 then
		return "NoEggInInventory"
	end
	if not MathUtil.isFinite(pedestalIndex) or math.floor(pedestalIndex) ~= pedestalIndex then
		return "InvalidPedestal"
	end
	local unlocked = if MathUtil.isPositiveFinite(profile.pedestalsUnlocked)
		then math.floor(profile.pedestalsUnlocked)
		else 0
	local maxUnlocked = if hasVipPass then 14 else unlocked
	if pedestalIndex < 1 or pedestalIndex > maxUnlocked then
		return "PedestalLocked"
	end
	if pedestalIndex > unlocked and pedestalIndex <= 12 then
		return "PedestalLocked"
	end
	for _, pet in ipairs(profile.pets) do
		if pet.pedestalIndex == pedestalIndex then
			return "PedestalOccupied"
		end
	end
	return nil
end

function PolicyLogic.hatchPaidEggDirectBundle(
	profile: any,
	eggId: string,
	pedestalIndex: number,
	hasVipPass: boolean
): EconomyLogic.TxResult
	local errReason = validatePaidHatchSlot(profile, eggId, pedestalIndex, hasVipPass)
	if errReason then
		return { ok = false, reason = errReason }
	end
	local bundle = MonetizationConfigs.getDirectBundleForEgg(eggId)
	if not bundle then
		return { ok = false, reason = "DirectBundleUnavailable" }
	end
	profile.eggs[eggId] = (profile.eggs[eggId] or 1) - 1
	if profile.eggs[eggId] <= 0 then
		profile.eggs[eggId] = nil
	end
	local newPet = awardDirectBundleContents(profile, bundle, pedestalIndex, false)
	if type(profile.activeFollowerUids) ~= "table" then
		profile.activeFollowerUids = {}
	end
	local activeSlots = if MathUtil.isPositiveFinite(profile.activeSlotsUnlocked)
		then math.floor(profile.activeSlotsUnlocked)
		else 1
	if #profile.activeFollowerUids < activeSlots then
		table.insert(profile.activeFollowerUids, newPet.uid)
	end
	return { ok = true, data = { pet = newPet, directBundle = true, bundle = bundle } }
end

function PolicyLogic.hatchEggWithPolicy(
	profile: EconomyLogic.PlayerProfile,
	eggId: string,
	pedestalIndex: number,
	hasVipPass: boolean,
	arePaidRandomItemsRestricted: boolean,
	petRollUnit: number?,
	mutRollUnit: number?
): EconomyLogic.TxResult
	if type(profile) ~= "table" then
		return { ok = false, reason = "InvalidArgs" }
	end
	if PolicyLogic.isPaidRandomEgg(eggId) and arePaidRandomItemsRestricted ~= false then
		return PolicyLogic.hatchPaidEggDirectBundle(profile, eggId, pedestalIndex, hasVipPass)
	end
	local r1 = if petRollUnit ~= nil then petRollUnit else math.random()
	local r2 = if mutRollUnit ~= nil then mutRollUnit else math.random()
	return EconomyLogic.hatchEggOnPedestal(profile, eggId, pedestalIndex, hasVipPass, r1, r2)
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
