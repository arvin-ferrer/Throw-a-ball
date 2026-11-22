--!strict
--[[
	PetFusion (Issue #10): pet inventory transactions — place/remove on pedestals, 3-into-1 star
	fusion, Coin levelling, Gem trait rerolls, and egg hatching. Pure (no Roblox APIs).
	Same contract as EconomyLedger and the SAME receipt namespace: atomic, never a partial
	change, and a replayed id is a no-op even if the server would roll differently now.
	Rolls come from the server; they are never part of the receipt.
]]

-- selene: allow(incorrect_standard_library_use) -- string require: same path in Lune and Roblox
local EconomyLedger = require("./EconomyLedger")
-- selene: allow(incorrect_standard_library_use)
local PetConfigs = require("../Configs/PetConfigs")

type PlayerData = EconomyLedger.PlayerData
type PetData = EconomyLedger.PetData
type TransactionResult = EconomyLedger.TransactionResult

export type HatchRolls = { pet: number, mutation: number }
export type Trait = "Greedy" | "Swift" | "Brawler" | "Overclocked" | "Tycoon"

local PetFusion = {}

local MAX_SLOT = 12
local STANDARD_EGGS = { StandardBiomeEgg = true, StandardBossEgg = true }

local function fail(reason: string): TransactionResult
	return { ok = false, reason = reason }
end

local function isFinite(n: unknown): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function validRoll(roll: unknown): boolean
	return isFinite(roll) and (roll :: number) >= 0 and (roll :: number) < 1
end

-- Length-prefixed so ("a:b","c") and ("a","b:c") can never encode the same receipt.
local function encode(...: any): string
	local parts = {}
	for _, value in { ... } do
		local text = tostring(value)
		table.insert(parts, `{#text}:{text}`)
	end
	return table.concat(parts, "|")
end

-- InvalidSlot / LockedSlot, or nil when the slot is usable.
local function slotError(data: PlayerData, slot: number): string?
	if not isFinite(slot) or slot % 1 ~= 0 or slot < 1 or slot > MAX_SLOT then
		return "InvalidSlot"
	elseif slot > data.pedestalsUnlocked then
		return "LockedSlot"
	end
	return nil
end

local function padOf(data: PlayerData, slot: number): EconomyLedger.PedestalData
	local key = tostring(slot)
	local pad = data.pedestalsById[key]
	if not pad then
		pad = { storedCoins = 0 }
		data.pedestalsById[key] = pad
	end
	return pad
end

local function placedSlotOf(data: PlayerData, field: string, id: string): string?
	for key, pad in data.pedestalsById do
		if (pad :: any)[field] == id then
			return key
		end
	end
	return nil
end

-- Weighted pick with half-open cumulative intervals over integer percentages.
local function pick(entries: { any }, roll: number, field: string): string?
	if not validRoll(roll) then
		return nil
	end
	local cumulative = 0
	for _, entry in entries do
		cumulative += entry.percent
		if roll < cumulative / 100 then
			return entry[field]
		end
	end
	return nil
end

function PetFusion.rollTrait(roll: number): Trait?
	return pick(PetConfigs.TraitOdds, roll, "trait") :: Trait?
end

-- Placement ---------------------------------------------------------------------------------------

function PetFusion.placePet(
	data: PlayerData,
	id: string,
	slot: number,
	petId: string
): TransactionResult
	local done = EconomyLedger.precheck(data, id, "placePet", encode(slot, petId))
	if done then
		return done
	end
	local bad = slotError(data, slot)
	if bad then
		return fail(bad)
	elseif not data.petsById[petId] then
		return fail("UnknownPet")
	end
	local existing = data.pedestalsById[tostring(slot)]
	if existing and (existing.petId or existing.eggId) then
		return fail("OccupiedSlot")
	elseif placedSlotOf(data, "petId", petId) then
		return fail("PetAlreadyPlaced") -- one pet can't earn on two pads
	end
	padOf(data, slot).petId = petId -- keeps any Coins already on this pad
	return EconomyLedger.commit(data, id, "placePet", encode(slot, petId))
end

function PetFusion.removePet(data: PlayerData, id: string, slot: number): TransactionResult
	local done = EconomyLedger.precheck(data, id, "removePet", encode(slot))
	if done then
		return done
	end
	local bad = slotError(data, slot)
	local pad = data.pedestalsById[tostring(slot)]
	if bad then
		return fail(bad)
	elseif not (pad and pad.petId) then
		return fail("EmptySlot")
	end
	pad.petId = nil -- pet stays owned/equipped; earned Coins stay on the pad
	return EconomyLedger.commit(data, id, "removePet", encode(slot))
end

-- Fusion / levelling / traits ---------------------------------------------------------------------

local function fusionError(data: PlayerData, keeperId: string, a: string, b: string): string?
	if keeperId == a or keeperId == b or a == b then
		return "DuplicatePetIds"
	end
	local keeper, donorA, donorB = data.petsById[keeperId], data.petsById[a], data.petsById[b]
	if not (keeper and donorA and donorB) then
		return "UnknownPet"
	end
	for _, donor in { donorA, donorB } do
		if
			donor.petId ~= keeper.petId
			or donor.stars ~= keeper.stars
			or donor.mutation ~= keeper.mutation
		then
			return "IncompatiblePets"
		end
	end
	return if keeper.stars >= PetConfigs.MAX_STARS then "MaxStars" else nil
end

local function consumePet(data: PlayerData, petId: string)
	data.petsById[petId] = nil
	for _, pad in data.pedestalsById do
		if pad.petId == petId then
			pad.petId = nil -- its stored Coins stay collectible
		end
	end
	local index = table.find(data.activePetIds, petId)
	if index then
		table.remove(data.activePetIds, index)
	end
end

function PetFusion.fusePets(
	data: PlayerData,
	id: string,
	keeperId: string,
	donorAId: string,
	donorBId: string
): TransactionResult
	local donors = { donorAId, donorBId }
	table.sort(donors) -- donor order never changes what a receipt means
	local argument = encode(keeperId, donors[1], donors[2])
	local done = EconomyLedger.precheck(data, id, "fusePets", argument)
	if done then
		return done
	end
	local bad = fusionError(data, keeperId, donorAId, donorBId)
	if bad then
		return fail(bad)
	end
	consumePet(data, donorAId)
	consumePet(data, donorBId)
	data.petsById[keeperId].stars += 1
	return EconomyLedger.commit(data, id, "fusePets", argument)
end

function PetFusion.levelUpPet(data: PlayerData, id: string, petId: string): TransactionResult
	local done = EconomyLedger.precheck(data, id, "levelUpPet", encode(petId))
	if done then
		return done
	end
	local pet = data.petsById[petId]
	if not pet then
		return fail("UnknownPet")
	end
	local cost = PetConfigs.getLevelUpCoinCost(pet.level)
	if not cost then
		return fail("MaxPetLevel")
	elseif data.coins < cost then
		return fail("InsufficientCoins")
	end
	data.coins -= cost
	pet.level += 1
	return EconomyLedger.commit(data, id, "levelUpPet", encode(petId))
end

function PetFusion.rerollTrait(
	data: PlayerData,
	id: string,
	petId: string,
	roll: number
): TransactionResult
	local done = EconomyLedger.precheck(data, id, "rerollTrait", encode(petId))
	if done then
		return done -- a replay returns the original outcome; the new roll is ignored
	end
	local pet = data.petsById[petId]
	local trait = PetFusion.rollTrait(roll)
	if not pet then
		return fail("UnknownPet")
	elseif not trait then
		return fail("InvalidRoll")
	elseif data.bossGems < PetConfigs.TRAIT_REROLL_COST_GEMS then
		return fail("InsufficientBossGems")
	end
	data.bossGems -= PetConfigs.TRAIT_REROLL_COST_GEMS
	pet.trait = trait
	return EconomyLedger.commit(data, id, "rerollTrait", encode(petId))
end

-- Hatching -------------------------------------------------------------------------------------------

-- (species, mutation) for an egg, or a rejection reason.
local function hatchResult(
	egg: EconomyLedger.EggData,
	rolls: HatchRolls
): (string?, string?, string?)
	if not (type(rolls) == "table" and validRoll(rolls.pet) and validRoll(rolls.mutation)) then
		return nil, nil, "InvalidRoll"
	end
	if egg.kind == "StarterEgg" then
		return PetConfigs.STARTER_PET_ID, "Normal", nil
	end
	local pools = egg.biomeId and PetConfigs.HatchPoolsByBiome[egg.biomeId]
	if not pools then
		return nil, nil, "UnknownEggPool"
	elseif egg.kind == "OverchargedBossEgg" then
		-- Only a won Overcharged egg can roll the exclusive mutations.
		return pick(pools.overcharged, rolls.pet, "petId"),
			pick(PetConfigs.OverchargedMutationOdds, rolls.mutation, "mutation"),
			nil
	elseif STANDARD_EGGS[egg.kind] then
		return pick(pools.standard, rolls.pet, "petId"),
			EconomyLedger.resolveGemEggMutation(rolls.mutation),
			nil
	end
	return nil, nil, "UnknownEggPool"
end

local function hatchSlotError(data: PlayerData, slot: number, eggId: string): string?
	local bad = slotError(data, slot)
	if bad then
		return bad
	elseif not data.eggsById[eggId] then
		return "UnknownEgg"
	end
	local placedAt = placedSlotOf(data, "eggId", eggId)
	if placedAt and placedAt ~= tostring(slot) then
		return "EggAlreadyPlaced"
	end
	local pad = data.pedestalsById[tostring(slot)]
	if pad and (pad.petId or (pad.eggId and pad.eggId ~= eggId)) then
		return "OccupiedSlot"
	end
	return nil
end

function PetFusion.hatchEgg(
	data: PlayerData,
	id: string,
	slot: number,
	eggId: string,
	rolls: HatchRolls
): TransactionResult
	local argument = encode(slot, eggId)
	local done = EconomyLedger.precheck(data, id, "hatchEgg", argument)
	if done then
		return done
	end
	local bad = hatchSlotError(data, slot, eggId)
	if bad then
		return fail(bad)
	end
	local species, mutation, reason = hatchResult(data.eggsById[eggId], rolls)
	if reason or not species or not mutation then
		return fail(reason or "UnknownEggPool")
	end
	local petId = `Hatch:{id}`
	if data.petsById[petId] then
		return fail("PetIdConflict")
	end
	data.eggsById[eggId] = nil
	local pad = padOf(data, slot)
	pad.eggId, pad.petId = nil, petId
	data.petsById[petId] = { petId = species, level = 1, stars = 1, mutation = mutation }
	return EconomyLedger.commit(data, id, "hatchEgg", argument)
end

return PetFusion
