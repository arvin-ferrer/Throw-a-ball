--!strict
local PetIncome = require("../src/shared/Utils/PetIncome")
local EconomyLedger = require("../src/shared/Utils/EconomyLedger")
local PetConfigs = require("../src/shared/Configs/PetConfigs")

type PlayerData = EconomyLedger.PlayerData

local function run(name: string, test: () -> ())
	local ok, failure = pcall(test)
	assert(ok, `{name}: {failure}`)
end

local function expectNear(actual: number, expected: number, label: string)
	assert(math.abs(actual - expected) <= 1e-6, `{label}: expected {expected}, got {actual}`)
end

local function placeFixture(data: PlayerData, slot: number, id: string, species: string)
	data.petsById[id] = { petId = species, level = 1, stars = 1, mutation = "Normal" }
	data.pedestalsById[tostring(slot)] = { petId = id, storedCoins = 0 }
end

local function pupProfile(): PlayerData
	local data = EconomyLedger.new()
	placeFixture(data, 2, "pup", "TrainingPup")
	return data
end

run("Starter and Meadow pets use the five GDD base income rates", function()
	local data = EconomyLedger.new()
	for _, example in
		{
			{ species = "TrainingPup", rate = 5 },
			{ species = "PebbleCub", rate = 12 },
			{ species = "DewSprite", rate = 18 },
			{ species = "ThornStag", rate = 30 },
			{ species = "GolemHeart", rate = 65 },
		}
	do
		placeFixture(data, 2, "pet", example.species)
		expectNear(PetIncome.getPadRate(data, 2), example.rate, example.species)
	end
	assert(PetConfigs.STARTER_TRAINING_GAIN_BONUS == 0.05, "starter training bonus")
end)

run("Pad rates stack mutation, star, level, trait and Ascension exactly once", function()
	local data = EconomyLedger.new()
	placeFixture(data, 2, "cub", "PebbleCub")
	data.petsById.cub.level = 11
	data.petsById.cub.stars = 2
	data.petsById.cub.mutation = "Golden"
	data.petsById.cub.trait = "Greedy"
	data.ascensionRank = 2
	expectNear(PetIncome.getPadRate(data, 2), 216.5625, "stacked rate")
	expectNear(PetIncome.accrue(data, 2), 433.125, "two seconds of stacked income")
	expectNear(data.pedestalsById["2"].storedCoins, 433.125, "unrounded pad storage")
	assert(data.coins == 0 and data.bossGems == 0, "accrual credits the pad only")
end)

run("Active followers continue earning on their pads and unplaced pets earn nothing", function()
	local data = pupProfile()
	placeFixture(data, 3, "sprite", "DewSprite")
	data.petsById.loose = { petId = "GolemHeart", level = 1, stars = 1, mutation = "Normal" }
	expectNear(PetIncome.accrue(data, 1), 23, "income with no active followers")
	data.activePetIds = { "pup" }
	expectNear(PetIncome.accrue(data, 1), 23, "income with one follower")
	data.activePetIds = { "pup", "sprite", "loose" }
	expectNear(PetIncome.accrue(data, 1), 23, "income with three followers")
	assert(data.pedestalsById["2"].storedCoins == 15, "active Training Pup earns normally")
	assert(data.pedestalsById["3"].storedCoins == 54, "active Dew Sprite earns normally")
	assert(data.pedestalsById["4"] == nil, "unplaced follower creates no pad")
end)

run("Placed Tycoons add the pet bonus and one plot bonus without stacking plot copies", function()
	local data = pupProfile()
	placeFixture(data, 3, "sprite", "DewSprite")
	data.petsById.sprite.trait = "Tycoon"
	placeFixture(data, 4, "cub", "PebbleCub")
	data.petsById.cub.trait = "Tycoon"
	expectNear(PetIncome.getPadRate(data, 2), 5.5, "plot bonus applies to other pads once")
	expectNear(PetIncome.getPadRate(data, 3), 29.7, "Tycoon's own bonus and the plot bonus")
	data.pedestalsById["3"].petId = nil
	data.pedestalsById["4"].petId = nil
	expectNear(PetIncome.getPadRate(data, 2), 5, "unplaced Tycoons provide no plot bonus")
end)

run("Accrual limits each pad independently and saturates under huge finite ticks", function()
	local data = pupProfile()
	placeFixture(data, 3, "cub", "PebbleCub")
	local cap = PetConfigs.CASH_PAD_CAP
	data.pedestalsById["2"].storedCoins = cap - 2
	expectNear(PetIncome.accrue(data, 1), 14, "credit only the available room on each pad")
	assert(data.pedestalsById["2"].storedCoins == cap, "first pad stops at cap")
	assert(data.pedestalsById["3"].storedCoins == 12, "second pad continues earning")
	expectNear(
		PetIncome.accrue(data, 1e308),
		cap - 12,
		"large finite tick fills the remaining room"
	)
	assert(data.pedestalsById["3"].storedCoins == cap, "large tick stores a finite cap")
	assert(PetIncome.accrue(data, 5) == 0, "full pads add nothing")
end)

run("Fractional accrual survives small ticks and a sweep drains only whole Coins", function()
	local data = pupProfile()
	for _ = 1, 3 do
		expectNear(PetIncome.accrue(data, 0.15), 0.75, "fraction earned each step")
	end
	expectNear(data.pedestalsById["2"].storedCoins, 2.25, "fractional ticks add up")
	assert(PetIncome.sweepPad(data, 2) == 2, "whole Coins returned for the grant")
	expectNear(data.pedestalsById["2"].storedCoins, 0.25, "fraction kept on pad")
	assert(
		PetIncome.sweepPad(data, 2) == 0 and data.coins == 0,
		"no repeated withdrawal or wallet grant"
	)
	PetIncome.accrue(data, 0.15)
	data.pedestalsById["2"].petId = nil
	assert(
		PetIncome.sweepPad(data, 2) == 1,
		"previous balance remains collectible after pet removal"
	)
end)

run("Locked, empty, and corrupt pedestal references never generate Coins", function()
	local data = pupProfile()
	placeFixture(data, 5, "locked", "GolemHeart")
	data.pedestalsById["5"].storedCoins = 80
	data.pedestalsById["3"] = { petId = "missing", storedCoins = 0 }
	data.pedestalsById["4"] = { petId = "pup", storedCoins = 0 }
	for _, slot in { 0, -1, 1.5, 0 / 0, math.huge, 1, 3, 4, 5 } do
		assert(PetIncome.getPadRate(data, slot) == 0, "no valid unique pet in this slot")
		assert(PetIncome.sweepPad(data, slot) == 0, "no eligible balance")
	end
	expectNear(
		PetIncome.accrue(data, 1),
		5,
		"duplicate assignment only earns at its lowest unlocked slot"
	)
	assert(data.pedestalsById["5"].storedCoins == 80, "locked pad is untouched")
	data.pedestalsUnlocked = 12
	assert(PetIncome.getPadRate(data, 5) == 65, "newly unlocked pedestal earns normally")
	assert(PetIncome.sweepPad(data, 5) == 80, "newly unlocked balance can be swept")
end)

run("Nonpositive or non-finite online time and corrupt balances cannot mint Coins", function()
	local data = pupProfile()
	data.pedestalsById["2"].storedCoins = 11
	for _, elapsed in { -1, 0, 0 / 0, math.huge, -math.huge } do
		assert(PetIncome.accrue(data, elapsed) == 0, "invalid elapsed is a no-op")
		assert(data.pedestalsById["2"].storedCoins == 11, "no change on invalid elapsed")
	end
	for _, balance in { -10, 0 / 0, math.huge } do
		data.pedestalsById["2"].storedCoins = balance
		assert(PetIncome.sweepPad(data, 2) == 0, "corrupt balance pays nothing")
		assert(data.pedestalsById["2"].storedCoins == 0, "sweep normalizes the invalid balance")
	end
	data.petsById.pup.level = math.huge
	assert(
		PetIncome.getPadRate(data, 2) == 0 and PetIncome.accrue(data, 1) == 0,
		"invalid pet yields no rate"
	)
end)

run(
	"Offline accrual caps at twelve hours for all vault tiers and applies Ascension once",
	function()
		for tier, expected in { 162_000, 243_000, 324_000 } do
			local data = pupProfile()
			data.ascensionRank = 2
			data.offlineVaultTier = tier
			data.lastLogoutTime = 1_000
			data.pedestalsById["2"].storedCoins = 10
			expectNear(
				PetIncome.accrueOffline(data, 1_000 + 86_400),
				expected,
				"capped vault accrual"
			)
			expectNear(
				data.pedestalsById["2"].storedCoins,
				expected + 10,
				"offline adds to existing balance"
			)
			assert(data.coins == 0 and data.bossGems == 0, "offline fills pads only")
			assert(data.lastLogoutTime == 0, "logout marker consumed")
		end
	end
)

run(
	"Overclocked increases offline efficiency only and never exceeds one hundred percent",
	function()
		for tier, expected in { 225, 337.5, 375 } do
			local data = pupProfile()
			data.petsById.pup.trait = "Overclocked"
			data.ascensionRank = 1
			data.offlineVaultTier = tier
			data.lastLogoutTime = 1_000
			expectNear(PetIncome.getPadRate(data, 2), 6.25, "online rate has no Overclocked bonus")
			expectNear(
				PetIncome.accrueOffline(data, 1_060),
				expected,
				"effective capped offline efficiency"
			)
		end
	end
)

run("Offline login respects pad headroom and consumes its logout interval once", function()
	local data = pupProfile()
	local cap = PetConfigs.CASH_PAD_CAP
	data.lastLogoutTime = 1_000
	data.pedestalsById["2"].storedCoins = cap - 4
	assert(PetIncome.accrueOffline(data, 1_060) == 4, "credit only pad room")
	assert(
		data.pedestalsById["2"].storedCoins == cap and data.lastLogoutTime == 0,
		"cap and consumed marker"
	)
	assert(PetIncome.sweepPad(data, 2) == cap, "empty the pad after login")
	assert(PetIncome.accrueOffline(data, 1_120) == 0, "cannot repeat the consumed logout interval")
	assert(data.pedestalsById["2"].storedCoins == 0, "repeated login check adds nothing")
end)

run("New profiles and backwards or invalid login clocks grant no offline income", function()
	local data = pupProfile()
	assert(PetIncome.accrueOffline(data, 1_000) == 0, "new profile has no logout")
	data.lastLogoutTime = 1_000
	for _, now in { -1, 999, 0 / 0, math.huge } do
		assert(PetIncome.accrueOffline(data, now) == 0, "invalid login clock is a no-op")
		assert(
			data.lastLogoutTime == 1_000 and data.pedestalsById["2"].storedCoins == 0,
			"keep saved interval"
		)
	end
	assert(
		PetIncome.accrueOffline(data, 1_001) == 2.5,
		"later valid login still gets the elapsed half-rate"
	)
end)

print("PASS: PetIncome.spec.luau")
