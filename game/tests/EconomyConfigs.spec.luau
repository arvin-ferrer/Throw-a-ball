--!strict
local EconomyConfigs = require("../src/shared/Configs/EconomyConfigs")

local function assertNear(actual: number, expected: number, label: string)
	local delta = math.abs(actual - expected)
	if delta > 1e-6 then
		error(`{label}: expected {expected}, got {actual}`)
	end
end

-- 1. Starter pet (Training Pup: 5/s, Normal, 1-star, Lv1, no trait, Ascension 0)
assertNear(
	EconomyConfigs.computePetCoinsPerSec({
		baseRate = 5,
		mutationKey = "Normal",
		starTier = 1,
		petLevel = 1,
		traitKey = nil,
		ascensionRank = 0,
	}),
	5.0,
	"Starter pet base Coins/s"
)

-- 2. Stacked scaling (Overcharged 4x, 2-star 1.75x, Lv11 => 2.2x, Greedy 1.25x, Ascension 2 => 1.5x)
local expectedStacked = 10 * 4.0 * 1.75 * 2.2 * 1.25 * 1.5
assertNear(
	EconomyConfigs.computePetCoinsPerSec({
		baseRate = 10,
		mutationKey = "Overcharged",
		starTier = 2,
		petLevel = 11,
		traitKey = "Greedy",
		ascensionRank = 2,
	}),
	expectedStacked,
	"Stacked pet Coins/s formula"
)

-- 3. Bounded 12h offline cap at 50% default efficiency
local capped = EconomyConfigs.computeOfflineCoins(10, 24 * 3600, nil)
assertNear(capped, 10 * 12 * 3600 * 0.5, "Offline 12h cap at 50%")

-- 4. Upgraded 100% offline vault efficiency for 1 hour
local oneHourFull = EconomyConfigs.computeOfflineCoins(10, 3600, 1.0)
assertNear(oneHourFull, 36000, "Offline 1h at 100%")

print("PASS: EconomyConfigs.spec.luau")
