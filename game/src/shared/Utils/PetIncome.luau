--!strict
--[[
	PetIncome (Issue #10): Cash Pad accrual from pets placed on pedestals. Pure (no Roblox APIs).
	Coins accrue on the pad (capped per pad, fractions kept); a sweep moves whole Coins out for
	the caller to grant through EconomyService. Offline income: min(elapsed, 12h) x rate x vault
	efficiency (Overclocked pads x1.2, capped at 100%), consuming the logout marker once.
]]

-- selene: allow(incorrect_standard_library_use) -- string require: same path in Lune and Roblox
local EconomyConfigs = require("../Configs/EconomyConfigs")
-- selene: allow(incorrect_standard_library_use)
local EconomyLedger = require("./EconomyLedger")
-- selene: allow(incorrect_standard_library_use)
local PetConfigs = require("../Configs/PetConfigs")

type PlayerData = EconomyLedger.PlayerData
type PetData = EconomyLedger.PetData

local PetIncome = {}

local MAX_SLOT = 12
local CAP = PetConfigs.CASH_PAD_CAP

local function isFinite(n: unknown): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function isUnlockedSlot(data: PlayerData, slot: number): boolean
	return isFinite(slot)
		and slot % 1 == 0
		and slot >= 1
		and slot <= math.min(MAX_SLOT, data.pedestalsUnlocked)
end

local function validPet(pet: PetData?): boolean
	return pet ~= nil
		and PetConfigs.Species[pet.petId] ~= nil
		and isFinite(pet.level)
		and EconomyConfigs.STAR_MULTIPLIERS[pet.stars] ~= nil
		and EconomyConfigs.MUTATION_MULTIPLIERS[pet.mutation] ~= nil
end

-- slot -> pet for every pad that may earn: unlocked, a known pet, and (if a corrupt save put
-- one pet on two pads) only its lowest slot.
local function earningPads(data: PlayerData): { [number]: PetData }
	local pads, seen = {}, {}
	for slot = 1, math.min(MAX_SLOT, data.pedestalsUnlocked) do
		local pad = data.pedestalsById[tostring(slot)]
		local petId = pad and pad.petId
		local pet = petId and data.petsById[petId]
		if petId and pet and validPet(pet) and not seen[petId] then
			seen[petId] = true
			pads[slot] = pet
		end
	end
	return pads
end

local function plotMultiplier(pads: { [number]: PetData }): number
	for _, pet in pads do
		if pet.trait == "Tycoon" then
			return 1 + PetConfigs.TYCOON_PLOT_COIN_BONUS -- once per plot, never stacked
		end
	end
	return 1
end

local function rateFor(data: PlayerData, pet: PetData, plotMult: number): number
	local rate = EconomyConfigs.computePetCoinsPerSec({
		baseRate = PetConfigs.Species[pet.petId].baseCoinsPerSec,
		mutationKey = pet.mutation,
		starTier = pet.stars,
		petLevel = pet.level,
		traitKey = pet.trait,
		ascensionRank = data.ascensionRank,
	}) * plotMult
	return if isFinite(rate) and rate > 0 then rate else 0
end

function PetIncome.getPadRate(data: PlayerData, slot: number): number
	if not isUnlockedSlot(data, slot) then
		return 0
	end
	local pads = earningPads(data)
	local pet = pads[slot]
	return if pet then rateFor(data, pet, plotMultiplier(pads)) else 0
end

-- Normalise a pad's stored Coins: corrupt values become 0, over-cap values clamp to the cap.
local function storedOf(pad: EconomyLedger.PedestalData): number
	local stored = pad.storedCoins
	stored = if isFinite(stored) and stored > 0 then math.min(stored, CAP) else 0
	pad.storedCoins = stored
	return stored
end

-- Add `rate x seconds` to one pad, bounded by its room (no overflow on huge ticks).
local function credit(pad: EconomyLedger.PedestalData, rate: number, seconds: number): number
	local room = CAP - storedOf(pad)
	if room <= 0 or rate <= 0 then
		return 0
	end
	local add = if seconds >= room / rate then room else rate * seconds
	pad.storedCoins += add
	return add
end

function PetIncome.accrue(data: PlayerData, elapsedSeconds: number): number
	if not isFinite(elapsedSeconds) or elapsedSeconds <= 0 then
		return 0
	end
	local pads = earningPads(data)
	local plotMult, total = plotMultiplier(pads), 0
	for slot, pet in pads do
		total += credit(
			data.pedestalsById[tostring(slot)],
			rateFor(data, pet, plotMult),
			elapsedSeconds
		)
	end
	return total
end

function PetIncome.accrueOffline(data: PlayerData, now: number): number
	local logout = data.lastLogoutTime
	if not (isFinite(now) and isFinite(logout) and logout > 0 and now >= logout) then
		return 0 -- unset, corrupt or future marker: keep it and grant nothing
	end
	local seconds = math.min(now - logout, EconomyConfigs.MAX_OFFLINE_SECONDS)
	local vault = EconomyLedger.getOfflineEfficiency(data)
	local pads = earningPads(data)
	local plotMult, total = plotMultiplier(pads), 0
	for slot, pet in pads do
		local boost = if pet.trait == "Overclocked"
			then 1 + PetConfigs.OVERCLOCKED_OFFLINE_BONUS
			else 1
		local efficiency = math.min(1, vault * boost)
		total += credit(
			data.pedestalsById[tostring(slot)],
			rateFor(data, pet, plotMult) * efficiency,
			seconds
		)
	end
	data.lastLogoutTime = 0 -- this interval can never be claimed twice
	return total
end

-- Remove the whole Coins from one unlocked pad (fraction stays). The caller grants them.
function PetIncome.sweepPad(data: PlayerData, slot: number): number
	if not isUnlockedSlot(data, slot) then
		return 0
	end
	local pad = data.pedestalsById[tostring(slot)]
	if not pad then
		return 0
	end
	local whole = math.floor(storedOf(pad))
	pad.storedCoins -= whole
	return whole
end

return PetIncome
