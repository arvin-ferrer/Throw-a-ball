--!strict
local PetFusion = require("../src/shared/Utils/PetFusion")
local EconomyLedger = require("../src/shared/Utils/EconomyLedger")
local PetConfigs = require("../src/shared/Configs/PetConfigs")

type PlayerData = EconomyLedger.PlayerData
type TransactionResult = EconomyLedger.TransactionResult

local function run(name: string, test: () -> ())
	local ok, failure = pcall(test)
	assert(ok, `{name}: {failure}`)
end

local function copyTree(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in value do
		copy[key] = copyTree(child)
	end
	return copy
end

local function expectSameTree(actual: any, expected: any, path: string)
	if type(expected) ~= "table" then
		assert(actual == expected, `{path}: expected {expected}, got {actual}`)
		return
	end
	assert(type(actual) == "table", `{path}: expected a table`)
	for key, value in expected do
		expectSameTree(actual[key], value, `{path}.{key}`)
	end
	for key in actual do
		assert(expected[key] ~= nil, `{path}: unexpected key {key}`)
	end
end

local function applied(result: TransactionResult)
	assert(
		result.ok and result.replayed == false,
		`expected an applied transaction, got {result.reason}`
	)
end

local function reject(data: PlayerData, action: () -> TransactionResult, reason: string)
	local before = copyTree(data)
	local result = action()
	assert(not result.ok and result.reason == reason, `expected {reason}, got {result.reason}`)
	expectSameTree(data, before, "rejected profile")
end

local function replay(data: PlayerData, action: () -> TransactionResult)
	local before = copyTree(data)
	local result = action()
	assert(result.ok and result.replayed, "expected a successful no-op replay")
	expectSameTree(data, before, "replayed profile")
end

local function ownPet(data: PlayerData, id: string, species: string, stars: number?)
	data.petsById[id] = { petId = species, level = 1, stars = stars or 1, mutation = "Normal" }
end

local function trio(stars: number?): PlayerData
	local data = EconomyLedger.new()
	for _, id in { "keep", "donor-a", "donor-b" } do
		ownPet(data, id, "PebbleCub", stars)
	end
	return data
end

run("Placing and removing an owned pet preserves pad Coins and follower equipment", function()
	local data = EconomyLedger.new()
	ownPet(data, "cub", "PebbleCub")
	data.activePetIds = { "cub" }
	applied(PetFusion.placePet(data, "place-cub", 2, "cub"))
	assert(
		data.pedestalsById["2"].petId == "cub" and data.pedestalsById["2"].storedCoins == 0,
		"placed in empty slot"
	)
	data.pedestalsById["2"].storedCoins = 13.5
	replay(data, function()
		return PetFusion.placePet(data, "place-cub", 2, "cub")
	end)
	applied(PetFusion.removePet(data, "remove-cub", 2))
	assert(
		data.pedestalsById["2"].petId == nil and data.pedestalsById["2"].storedCoins == 13.5,
		"removal leaves earned balance"
	)
	assert(
		data.petsById.cub.petId == "PebbleCub" and data.activePetIds[1] == "cub",
		"pet stays owned and equipped"
	)
	replay(data, function()
		return PetFusion.removePet(data, "remove-cub", 2)
	end)
	applied(PetFusion.placePet(data, "place-again", 2, "cub"))
	assert(data.pedestalsById["2"].storedCoins == 13.5, "placement preserves previous balance")
end)

run("Placement rejects invalid slots, locked slots, missing pets, and occupied pads", function()
	local data = EconomyLedger.new()
	ownPet(data, "cub", "PebbleCub")
	for _, slot in { 0, -1, 1.5, math.huge, 0 / 0, 13 } do
		reject(data, function()
			return PetFusion.placePet(data, "invalid-slot", slot, "cub")
		end, "InvalidSlot")
	end
	reject(data, function()
		return PetFusion.placePet(data, "locked-slot", 5, "cub")
	end, "LockedSlot")
	reject(data, function()
		return PetFusion.placePet(data, "missing-pet", 2, "someone-else")
	end, "UnknownPet")
	reject(data, function()
		return PetFusion.placePet(data, "starter-occupied", 1, "cub")
	end, "OccupiedSlot")
	applied(PetFusion.placePet(data, "slot-two", 2, "cub"))
	ownPet(data, "sprite", "DewSprite")
	reject(data, function()
		return PetFusion.placePet(data, "pet-occupied", 2, "sprite")
	end, "OccupiedSlot")
end)

run("One pet cannot earn on two pads and empty or locked pads cannot remove a pet", function()
	local data = EconomyLedger.new()
	ownPet(data, "cub", "PebbleCub")
	applied(PetFusion.placePet(data, "place-cub", 2, "cub"))
	reject(data, function()
		return PetFusion.placePet(data, "duplicate", 3, "cub")
	end, "PetAlreadyPlaced")
	reject(data, function()
		return PetFusion.removePet(data, "empty", 3)
	end, "EmptySlot")
	reject(data, function()
		return PetFusion.removePet(data, "locked", 12)
	end, "LockedSlot")
	data.pedestalsUnlocked = 12
	applied(PetFusion.removePet(data, "move-off", 2))
	applied(PetFusion.placePet(data, "move-to", 12, "cub"))
	assert(data.pedestalsById["12"].petId == "cub", "purchased slots can hold pets")
end)

run("Fusion consumes two donors and retains the keeper with one higher star", function()
	local data = trio()
	data.petsById.keep.level = 9
	data.petsById.keep.trait = "Greedy"
	applied(PetFusion.placePet(data, "keeper-pad", 2, "keep"))
	applied(PetFusion.placePet(data, "donor-pad", 3, "donor-a"))
	data.pedestalsById["3"].storedCoins = 123
	data.activePetIds = { "donor-b", "keep", "donor-a" }
	applied(PetFusion.fusePets(data, "fuse", "keep", "donor-a", "donor-b"))
	local keeper = data.petsById.keep
	assert(
		keeper.stars == 2 and keeper.level == 9 and keeper.trait == "Greedy",
		"keeper gains one star only"
	)
	assert(
		keeper.mutation == "Normal" and data.pedestalsById["2"].petId == "keep",
		"keeper stays placed"
	)
	assert(
		data.petsById["donor-a"] == nil and data.petsById["donor-b"] == nil,
		"two donors consumed"
	)
	assert(
		data.pedestalsById["3"].petId == nil and data.pedestalsById["3"].storedCoins == 123,
		"donor pad cleared safely"
	)
	expectSameTree(data.activePetIds, { "keep" }, "active followers after fusion")
	assert(data.coins == 0 and data.bossGems == 0, "three pets are the fusion cost")
	replay(data, function()
		return PetFusion.fusePets(data, "fuse", "keep", "donor-b", "donor-a")
	end)
end)

run(
	"Fusion requires three distinct owned pets with matching species, stars, and mutation",
	function()
		local data = trio()
		reject(data, function()
			return PetFusion.fusePets(data, "duplicate-id", "keep", "keep", "donor-b")
		end, "DuplicatePetIds")
		reject(data, function()
			return PetFusion.fusePets(data, "missing-donor", "keep", "donor-a", "not-owned")
		end, "UnknownPet")
		data.petsById["donor-b"].petId = "DewSprite"
		reject(data, function()
			return PetFusion.fusePets(data, "mixed-species", "keep", "donor-a", "donor-b")
		end, "IncompatiblePets")
		data.petsById["donor-b"].petId = "PebbleCub"
		data.petsById["donor-b"].stars = 2
		reject(data, function()
			return PetFusion.fusePets(data, "mixed-stars", "keep", "donor-a", "donor-b")
		end, "IncompatiblePets")
		data.petsById["donor-b"].stars = 1
		data.petsById["donor-b"].mutation = "Shiny"
		reject(data, function()
			return PetFusion.fusePets(data, "mixed-mutation", "keep", "donor-a", "donor-b")
		end, "IncompatiblePets")
	end
)

run("Two-star duplicates fuse to three stars and apex pets cannot fuse again", function()
	local data = trio(2)
	applied(PetFusion.fusePets(data, "apex", "keep", "donor-a", "donor-b"))
	assert(data.petsById.keep.stars == 3, "two-star to apex promotion")
	ownPet(data, "donor-a", "PebbleCub", 3)
	ownPet(data, "donor-b", "PebbleCub", 3)
	reject(data, function()
		return PetFusion.fusePets(data, "over-max", "keep", "donor-a", "donor-b")
	end, "MaxStars")
	assert(
		PetConfigs.PERK_BONUS_BY_STAR[2] == 0.15 and PetConfigs.PERK_BONUS_BY_STAR[3] == 0.30,
		"GDD perk bonuses"
	)
end)

run("Coin leveling is atomic, retryable, and preserves other pet stats", function()
	local data = EconomyLedger.new()
	ownPet(data, "cub", "PebbleCub", 2)
	data.petsById.cub.mutation = "Golden"
	data.petsById.cub.trait = "Greedy"
	applied(EconomyLedger.grantBossGems(data, "gems", 5))
	reject(data, function()
		return PetFusion.levelUpPet(data, "level", "cub")
	end, "InsufficientCoins")
	applied(EconomyLedger.grantCoins(data, "coins", 100))
	applied(PetFusion.levelUpPet(data, "level", "cub"))
	assert(
		data.coins == 0 and data.bossGems == 5 and data.petsById.cub.level == 2,
		"one level for the exact Coin cost"
	)
	assert(
		data.petsById.cub.stars == 2 and data.petsById.cub.mutation == "Golden",
		"star and mutation preserved"
	)
	assert(data.petsById.cub.trait == "Greedy", "trait preserved")
	replay(data, function()
		return PetFusion.levelUpPet(data, "level", "cub")
	end)
end)

run("Pet leveling reaches but cannot exceed level twenty-five", function()
	local data = EconomyLedger.new()
	ownPet(data, "cub", "PebbleCub")
	data.petsById.cub.level = 24
	local price = assert(PetConfigs.getLevelUpCoinCost(24), "configured last level price")
	assert(
		price == 1_250 and PetConfigs.getLevelUpCoinCost(25) == nil,
		"level-24 and level-25 costs"
	)
	applied(EconomyLedger.grantCoins(data, "fund", price))
	applied(PetFusion.levelUpPet(data, "last-level", "cub"))
	assert(data.coins == 0 and data.petsById.cub.level == 25, "25 is reachable at exact price")
	reject(data, function()
		return PetFusion.levelUpPet(data, "over-level", "cub")
	end, "MaxPetLevel")
	reject(data, function()
		return PetFusion.levelUpPet(data, "missing", "not-owned")
	end, "UnknownPet")
end)

run("Trait rolls honor the GDD weights and deterministic half-open boundaries", function()
	local total = 0
	for _, entry in PetConfigs.TraitOdds do
		total += entry.percent
	end
	assert(total == 100, "trait weights sum to 100 percent")
	for _, example in
		{
			{ roll = 0, trait = "Greedy" },
			{ roll = 0.2999, trait = "Greedy" },
			{ roll = 0.30, trait = "Swift" },
			{ roll = 0.5499, trait = "Swift" },
			{ roll = 0.55, trait = "Brawler" },
			{ roll = 0.7499, trait = "Brawler" },
			{ roll = 0.75, trait = "Overclocked" },
			{ roll = 0.8999, trait = "Overclocked" },
			{ roll = 0.90, trait = "Tycoon" },
			{ roll = 0.9999, trait = "Tycoon" },
		}
	do
		assert(PetFusion.rollTrait(example.roll) == example.trait, `trait at {example.roll}`)
	end
	for _, invalid in { -1, 1, 0 / 0, math.huge } do
		assert(PetFusion.rollTrait(invalid) == nil, "out-of-range or non-finite roll")
	end
end)

run("A trait reroll spends Gems exactly once and changes the trait only", function()
	local data = EconomyLedger.new()
	ownPet(data, "cub", "PebbleCub", 2)
	data.petsById.cub.trait = "Greedy"
	data.petsById.cub.level = 4
	applied(EconomyLedger.grantCoins(data, "coins", 8))
	applied(EconomyLedger.grantBossGems(data, "gems", PetConfigs.TRAIT_REROLL_COST_GEMS))
	applied(PetFusion.rerollTrait(data, "reroll", "cub", 0.92))
	assert(data.bossGems == 0 and data.coins == 8, "reroll debits only the exact Gem price")
	expectSameTree(data.petsById.cub, {
		petId = "PebbleCub",
		level = 4,
		stars = 2,
		mutation = "Normal",
		trait = "Tycoon",
	}, "rerolled pet")
	replay(data, function()
		return PetFusion.rerollTrait(data, "reroll", "cub", 0)
	end)
end)

run("Invalid trait rerolls preserve both funds and the old trait", function()
	local data = EconomyLedger.new()
	ownPet(data, "cub", "PebbleCub")
	data.petsById.cub.trait = "Swift"
	reject(data, function()
		return PetFusion.rerollTrait(data, "no-gems", "cub", 0.9)
	end, "InsufficientBossGems")
	applied(EconomyLedger.grantBossGems(data, "gems", 5))
	reject(data, function()
		return PetFusion.rerollTrait(data, "invalid-roll", "cub", 0 / 0)
	end, "InvalidRoll")
	reject(data, function()
		return PetFusion.rerollTrait(data, "not-owned", "unknown", 0.9)
	end, "UnknownPet")
end)

run("The preplaced starter egg hatches a Normal Training Pup once on pedestal one", function()
	local data = EconomyLedger.new()
	applied(
		PetFusion.hatchEgg(data, "starter", 1, "StarterEgg", { pet = 0.9999, mutation = 0.9999 })
	)
	assert(data.eggsById.StarterEgg == nil, "starter egg consumed")
	local pad = data.pedestalsById["1"]
	assert(
		pad.eggId == nil and pad.petId == "Hatch:starter" and pad.storedCoins == 0,
		"starter pet placed"
	)
	expectSameTree(data.petsById["Hatch:starter"], {
		petId = "TrainingPup",
		level = 1,
		stars = 1,
		mutation = "Normal",
	}, "starter pet")
	replay(data, function()
		return PetFusion.hatchEgg(data, "starter", 1, "StarterEgg", { pet = 0, mutation = 0 })
	end)
	reject(data, function()
		return PetFusion.hatchEgg(
			data,
			"second-starter",
			2,
			"StarterEgg",
			{ pet = 0, mutation = 0 }
		)
	end, "UnknownEgg")
end)

run("Standard Meadow eggs use their weighted species and standard mutation pools", function()
	for _, example in
		{
			{ roll = 0, species = "PebbleCub", mutation = "Normal" },
			{ roll = 0.55, species = "DewSprite", mutation = "Normal" },
			{ roll = 0.85, species = "ThornStag", mutation = "Normal" },
			{ roll = 0.90, species = "ThornStag", mutation = "Shiny" },
			{ roll = 0.99, species = "GolemHeart", mutation = "Golden" },
			{ roll = 0.999999, species = "GolemHeart", mutation = "Golden" },
		}
	do
		for _, kind in { "StandardBiomeEgg", "StandardBossEgg" } do
			local data = EconomyLedger.new()
			applied(EconomyLedger.grantEgg(data, "reward", kind, "EmeraldMeadow"))
			data.pedestalsById["2"] = { storedCoins = 13.5 }
			local rolls = { pet = example.roll, mutation = example.roll }
			applied(PetFusion.hatchEgg(data, "meadow", 2, "Egg:reward", rolls))
			local pet = data.petsById["Hatch:meadow"]
			assert(
				pet.petId == example.species and pet.mutation == example.mutation,
				`{kind} at {example.roll}`
			)
			assert(pet.level == 1 and pet.stars == 1 and pet.trait == nil, "hatched pet defaults")
			assert(data.eggsById["Egg:reward"] == nil, "one egg consumed")
			assert(data.pedestalsById["2"].petId == "Hatch:meadow", "hatch places the pet")
			assert(data.pedestalsById["2"].storedCoins == 13.5, "hatching preserves pad Coins")
		end
	end
end)

run("Crafted eggs hatch into their own biome's species rather than Meadow pets", function()
	for _, example in
		{
			{ biomeId = "FrostbiteCavern", species = "SnowFox" },
			{ biomeId = "MoltenCaldera", species = "AshLizard" },
		}
	do
		local data = EconomyLedger.new()
		applied(EconomyLedger.grantBossGems(data, "fund", 30))
		applied(EconomyLedger.craftGemEgg(data, "craft", example.biomeId))
		applied(PetFusion.hatchEgg(data, "hatch", 2, "Craft:craft", { pet = 0, mutation = 0.9999 }))
		local pet = data.petsById["Hatch:hatch"]
		assert(
			pet.petId == example.species and pet.mutation == "Golden",
			"crafted egg remains biome-specific and standard"
		)
	end
end)

run("Won Overcharged eggs alone can hatch the two exclusive mutations", function()
	for _, example in
		{
			{ petRoll = 0, mutationRoll = 0.75, species = "ThornStag", mutation = "Overcharged" },
			{
				petRoll = 0.90,
				mutationRoll = 0.97,
				species = "GolemHeart",
				mutation = "VoidTouched",
			},
		}
	do
		local data = EconomyLedger.new()
		applied(EconomyLedger.grantEgg(data, "won", "OverchargedBossEgg", "EmeraldMeadow"))
		applied(PetFusion.hatchEgg(data, "win-hatch", 2, "Egg:won", {
			pet = example.petRoll,
			mutation = example.mutationRoll,
		}))
		local pet = data.petsById["Hatch:win-hatch"]
		assert(
			pet.petId == example.species and pet.mutation == example.mutation,
			"Overcharged pool"
		)
	end
end)

run("Hatching respects unlocked slots and existing pet or preplaced egg occupancy", function()
	local data = EconomyLedger.new()
	applied(EconomyLedger.grantEgg(data, "reward", "StandardBossEgg", "EmeraldMeadow"))
	local rolls = { pet = 0.5, mutation = 0.5 }
	reject(data, function()
		return PetFusion.hatchEgg(data, "other-slot", 2, "StarterEgg", rolls)
	end, "EggAlreadyPlaced")
	reject(data, function()
		return PetFusion.hatchEgg(data, "locked", 5, "Egg:reward", rolls)
	end, "LockedSlot")
	reject(data, function()
		return PetFusion.hatchEgg(data, "occupied-egg", 1, "Egg:reward", rolls)
	end, "OccupiedSlot")
	ownPet(data, "pup", "TrainingPup")
	applied(PetFusion.placePet(data, "place", 2, "pup"))
	reject(data, function()
		return PetFusion.hatchEgg(data, "occupied-pet", 2, "Egg:reward", rolls)
	end, "OccupiedSlot")
	data.pedestalsUnlocked = 12
	applied(PetFusion.hatchEgg(data, "balcony-hatch", 12, "Egg:reward", rolls))
	assert(data.pedestalsById["12"].petId == "Hatch:balcony-hatch", "unlocked balcony hatch")
end)

run("Invalid hatch rolls and unsupported egg pools leave inventory untouched", function()
	local data = EconomyLedger.new()
	applied(EconomyLedger.grantEgg(data, "reward", "StandardBossEgg", "EmeraldMeadow"))
	for _, invalid in { -1, 1, 0 / 0, math.huge } do
		reject(data, function()
			return PetFusion.hatchEgg(
				data,
				"bad-pet-roll",
				2,
				"Egg:reward",
				{ pet = invalid, mutation = 0 }
			)
		end, "InvalidRoll")
		reject(data, function()
			return PetFusion.hatchEgg(
				data,
				"bad-mutation-roll",
				2,
				"Egg:reward",
				{ pet = 0, mutation = invalid }
			)
		end, "InvalidRoll")
	end
	data.eggsById.unknown = { kind = "StandardBossEgg", biomeId = "UnknownBiome" }
	reject(data, function()
		return PetFusion.hatchEgg(data, "bad-pool", 2, "unknown", { pet = 0, mutation = 0 })
	end, "UnknownEggPool")
end)

run("Hatching refuses to overwrite an existing pet with the generated ID", function()
	local data = EconomyLedger.new()
	ownPet(data, "Hatch:collision", "GolemHeart")
	reject(data, function()
		return PetFusion.hatchEgg(data, "collision", 1, "StarterEgg", { pet = 0, mutation = 0 })
	end, "PetIdConflict")
end)

run("Pet transactions share the ledger receipt namespace and reject changed arguments", function()
	local data = EconomyLedger.new()
	ownPet(data, "cub", "PebbleCub")
	reject(data, function()
		return PetFusion.placePet(data, "", 2, "cub")
	end, "InvalidTransactionId")
	applied(EconomyLedger.grantCoins(data, "shared-id", 1))
	reject(data, function()
		return PetFusion.placePet(data, "shared-id", 2, "cub")
	end, "TransactionIdConflict")
	applied(PetFusion.placePet(data, "valid-id", 2, "cub"))
	reject(data, function()
		return PetFusion.placePet(data, "valid-id", 3, "cub")
	end, "TransactionIdConflict")
	reject(data, function()
		return EconomyLedger.grantCoins(data, "valid-id", 1)
	end, "TransactionIdConflict")
end)

print("PASS: PetFusion.spec.luau")
