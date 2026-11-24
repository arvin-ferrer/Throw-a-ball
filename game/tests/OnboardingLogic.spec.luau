--!strict
local Economy = require("../src/shared/Utils/EconomyLogic")
local Onboarding = require("../src/shared/Utils/OnboardingLogic")

local function expectStep(profile: any, id: string, tag: string)
	local step = Onboarding.currentStep(profile)
	assert(type(step) == "table" and step.id == id, `Expected onboarding step {id}`)
	assert(
		type(step.text) == "string" and string.find(step.text, "%S"),
		`Missing guidance for {id}`
	)
	assert(step.targetTag == tag, `Expected {id} to target {tag}`)
end

-- PlotService discovers pedestals by PedestalIndex. The CashPad tag on the child
-- locates the owner's pedestal #1; the hatch interaction is on its sibling Base.
local function expectHatch(profile: any)
	expectStep(profile, "HatchStarter", "CashPad")
end

local function firstSession()
	local p = Economy.createDefaultProfile(100)
	expectHatch(p)
	assert(
		Economy.hatchEggOnPedestal(p, "StarterEgg", 1, false, 0.5, 0.5).ok,
		"Starter hatch must succeed"
	)
	expectStep(p, "CollectCash", "CashPad")
	assert(Economy.collectCashPad(p, 1) == 0, "An empty pad cannot mark the first sweep")
	expectStep(p, "CollectCash", "CashPad")
	assert(Economy.accruePedestalCoins(p, 1, false, false) == 5, "Pup produces five pending coins")
	expectStep(p, "CollectCash", "CashPad")
	assert(Economy.collectCashPad(p, 1) == 5, "First sweep transfers the five pending coins")
	assert((p :: any).hasCollectedCash == true, "A positive sweep must record the first collection")
	p.coins = 0 -- Spending the first payout must not restart the guide.
	p.ballDamage = 14.99
	expectStep(p, "Train", "TrainingFiringPad")
	p.ballDamage = 15
	expectStep(p, "EnterPortal", "BiomePortal") -- controller filters BiomeId == EmeraldMeadow
	p.level = 2
	assert(Onboarding.currentStep(p) == nil, "Level 2 completes the Meadow step")
end

local function outOfOrderMilestones()
	local p: any = Economy.createDefaultProfile(100)
	p.coins = 1000 -- Earnings from another source do not count as a sweep.
	p.level = 8
	p.ballDamage = 100
	expectHatch(p)
	p.starterEggHatched = true
	p.hasCollectedCash = nil -- Previously saved profiles have no milestone.
	expectStep(p, "CollectCash", "CashPad")
	p.hasCollectedCash = true
	p.ballDamage = 14
	expectStep(p, "Train", "TrainingFiringPad")
	p.ballDamage = 16
	assert(Onboarding.currentStep(p) == nil, "An experienced player skips the portal instruction")
end

expectHatch(nil)
for _, garbage in { false, "unknown", 12, {}, { starterEggHatched = "yes" } } do
	expectHatch(garbage)
end
firstSession()
outOfOrderMilestones()
print("PASS: OnboardingLogic.spec.luau")
