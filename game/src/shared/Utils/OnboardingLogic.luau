--!strict
--[[
	OnboardingLogic.luau
	Pure 0-5 minute onboarding state resolver shared by HudGui and OnboardingGuideController.
]]

export type OnboardingStep = {
	id: string,
	text: string,
	targetTag: string?,
}

local OnboardingLogic = {}

function OnboardingLogic.currentStep(profile: any): OnboardingStep?
	if type(profile) ~= "table" or profile.starterEggHatched ~= true then
		return {
			id = "HatchStarter",
			text = "Step 1: Press [E] at Pedestal #1 to hatch your FREE Starter Egg!",
			targetTag = "CashPad",
		}
	end
	if profile.hasCollectedCash ~= true then
		return {
			id = "CollectCash",
			text = "Step 2: Walk onto your glowing Cash Pad to collect your Pet Coins!",
			targetTag = "CashPad",
		}
	end
	local dmg = if type(profile.ballDamage) == "number" then profile.ballDamage else 0
	if dmg < 15 then
		return {
			id = "Train",
			text = "Step 3: Stand on your Training Pad to AUTO-SHOOT & reach 15 DMG!",
			targetTag = "TrainingFiringPad",
		}
	end
	local lvl = if type(profile.level) == "number" then profile.level else 0
	if lvl < 2 then
		return {
			id = "EnterPortal",
			text = "Step 4: Walk into Portal 1 (Emerald Meadow) for PvE & Boss Brawl!",
			targetTag = "BiomePortal",
		}
	end
	return nil
end

return OnboardingLogic
