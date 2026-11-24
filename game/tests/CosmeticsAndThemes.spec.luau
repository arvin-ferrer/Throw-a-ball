--!strict
--[[
	CosmeticsAndThemes.spec.luau
	Verifies mobile particle budget constants and atomic cosmetic unlock / zero-cost equip transitions
	across BallSkin, HatchVFX, EliminationVFX, and PlotTheme categories (#20).
]]

local EconomyLogic = require("../src/shared/Utils/EconomyLogic")

local PolicyLogic = require("../src/shared/Utils/PolicyLogic")
local Monetization = require("../src/shared/Configs/MonetizationConfigs")

local function assertTrue(cond: boolean, label: string)
	if not cond then
		error(`Assertion failed: {label}`)
	end
end

-- 1. Mobile particle budget invariant
assertTrue(
	type(EconomyLogic.COSMETIC_MAX_BURST_PARTICLES) == "number"
		and EconomyLogic.COSMETIC_MAX_BURST_PARTICLES > 0
		and EconomyLogic.COSMETIC_MAX_BURST_PARTICLES <= 36,
	"COSMETIC_MAX_BURST_PARTICLES must stay within mobile ceiling (<= 36)"
)

-- 2. Rejection checks (unknown ID, insufficient, negative, NaN) without mutating profile
local rejectProfile = EconomyLogic.createDefaultProfile(100)
rejectProfile.bossGems = 40
local badUnknown = EconomyLogic.buyOrEquipCosmetic(rejectProfile, "NonExistentCosmetic")
assertTrue(
	not badUnknown.ok
		and rejectProfile.bossGems == 40
		and rejectProfile.ownedCosmetics.PrismTrail == nil,
	"Unknown cosmetic ID rejected cleanly"
)

local badInsufficient = EconomyLogic.buyOrEquipCosmetic(rejectProfile, "PrismTrail")
assertTrue(
	not badInsufficient.ok
		and rejectProfile.bossGems == 40
		and not rejectProfile.ownedCosmetics.PrismTrail
		and rejectProfile.equippedBallSkin == nil,
	"Insufficient Boss Gems leaves profile unmutated"
)

rejectProfile.bossGems = -25
local badNegative = EconomyLogic.buyOrEquipCosmetic(rejectProfile, "PrismTrail")
assertTrue(
	not badNegative.ok
		and rejectProfile.bossGems == -25
		and not rejectProfile.ownedCosmetics.PrismTrail,
	"Negative Boss Gems rejected without mutation"
)

rejectProfile.bossGems = 0 / 0
local badNaN = EconomyLogic.buyOrEquipCosmetic(rejectProfile, "PrismTrail")
assertTrue(
	not badNaN.ok
		and rejectProfile.bossGems ~= rejectProfile.bossGems
		and not rejectProfile.ownedCosmetics.PrismTrail,
	"NaN Boss Gems rejected without mutation"
)

-- 3. Purchase & equip across all 4 categories
local profile = EconomyLogic.createDefaultProfile(100)
profile.bossGems = 500 -- 45 + 60 + 70 + 85 + 110 = 370 total

local rPrism = EconomyLogic.buyOrEquipCosmetic(profile, "PrismTrail")
assertTrue(
	rPrism.ok
		and rPrism.data ~= nil
		and rPrism.data.purchased == true
		and profile.bossGems == 455
		and profile.ownedCosmetics.PrismTrail == true
		and profile.equippedBallSkin == "PrismTrail"
		and EconomyLogic.isCosmeticEquipped(profile, "PrismTrail"),
	"PrismTrail purchased and equipped to equippedBallSkin"
)

local rCyber = EconomyLogic.buyOrEquipCosmetic(profile, "CyberPulse")
assertTrue(
	rCyber.ok
		and rCyber.data ~= nil
		and rCyber.data.purchased == true
		and profile.bossGems == 395
		and profile.ownedCosmetics.CyberPulse == true
		and profile.equippedBallSkin == "CyberPulse"
		and EconomyLogic.isCosmeticEquipped(profile, "CyberPulse")
		and not EconomyLogic.isCosmeticEquipped(profile, "PrismTrail"),
	"CyberPulse purchased and replaces active BallSkin"
)

local rHatch = EconomyLogic.buyOrEquipCosmetic(profile, "SupernovaHatch")
assertTrue(
	rHatch.ok
		and rHatch.data ~= nil
		and rHatch.data.purchased == true
		and profile.bossGems == 325
		and profile.ownedCosmetics.SupernovaHatch == true
		and profile.equippedHatchVfx == "SupernovaHatch"
		and EconomyLogic.isCosmeticEquipped(profile, "SupernovaHatch"),
	"SupernovaHatch purchased and equipped to equippedHatchVfx"
)

local rElim = EconomyLogic.buyOrEquipCosmetic(profile, "VoidShatter")
assertTrue(
	rElim.ok
		and rElim.data ~= nil
		and rElim.data.purchased == true
		and profile.bossGems == 240
		and profile.ownedCosmetics.VoidShatter == true
		and profile.equippedEliminationVfx == "VoidShatter"
		and EconomyLogic.isCosmeticEquipped(profile, "VoidShatter"),
	"VoidShatter purchased and equipped to equippedEliminationVfx"
)

local rPlot = EconomyLogic.buyOrEquipCosmetic(profile, "RoyalMarblePlot")
assertTrue(
	rPlot.ok
		and rPlot.data ~= nil
		and rPlot.data.purchased == true
		and profile.bossGems == 130
		and profile.ownedCosmetics.RoyalMarblePlot == true
		and profile.equippedPlotTheme == "RoyalMarblePlot"
		and EconomyLogic.isCosmeticEquipped(profile, "RoyalMarblePlot"),
	"RoyalMarblePlot purchased and equipped to equippedPlotTheme"
)

-- 4. Zero-cost switching & re-equipping of owned cosmetics
local rSwitchBall = EconomyLogic.buyOrEquipCosmetic(profile, "PrismTrail")
assertTrue(
	rSwitchBall.ok
		and rSwitchBall.data ~= nil
		and rSwitchBall.data.purchased == false
		and profile.bossGems == 130
		and profile.equippedBallSkin == "PrismTrail"
		and EconomyLogic.isCosmeticEquipped(profile, "PrismTrail")
		and not EconomyLogic.isCosmeticEquipped(profile, "CyberPulse"),
	"Switching back to owned PrismTrail deducts 0 gems"
)

local rReequipHatch = EconomyLogic.buyOrEquipCosmetic(profile, "SupernovaHatch")
assertTrue(
	rReequipHatch.ok
		and rReequipHatch.data ~= nil
		and rReequipHatch.data.purchased == false
		and profile.bossGems == 130
		and profile.equippedHatchVfx == "SupernovaHatch",
	"Re-selecting owned SupernovaHatch deducts 0 gems"
)

assertTrue(
	not EconomyLogic.isCosmeticEquipped(nil :: any, "PrismTrail"),
	"isCosmeticEquipped returns false safely for nil profile"
)

local function exactPriceAndFailedSwitch()
	local p = EconomyLogic.createDefaultProfile(100)
	p.bossGems = 45
	p.coins = 275
	assertTrue(EconomyLogic.buyOrEquipCosmetic(p, "PrismTrail").ok, "Exact Gem price must succeed")
	assertTrue(p.bossGems == 0 and p.coins == 275, "Exact purchase debits only Boss Gems")
	assertTrue(
		not EconomyLogic.buyOrEquipCosmetic(p, "CyberPulse").ok,
		"Coins cannot cover a Gem shortfall"
	)
	assertTrue(
		p.equippedBallSkin == "PrismTrail" and p.ownedCosmetics.CyberPulse == nil,
		"Failed replacement must preserve the equipped skin and inventory"
	)
	assertTrue(p.coins == 275 and p.bossGems == 0, "Failed replacement leaves both wallets intact")
end

local function directBundleAndLegacyEquip()
	local p = EconomyLogic.createDefaultProfile(100)
	local bundle = Monetization.DIRECT_BUNDLES.Direct_PrismPack
	local receipt = PolicyLogic.applyProductReceipt(p, "cosmetic-bundle", bundle.devProductId, true)
	assertTrue(
		receipt.granted and not receipt.duplicate,
		"Direct bundle grants its guaranteed skin"
	)
	p.bossGems = 60
	assertTrue(
		EconomyLogic.buyOrEquipCosmetic(p, "CyberPulse").ok,
		"Switch away from the bundle skin"
	)
	local equip = EconomyLogic.buyOrEquipCosmetic(p, bundle.guaranteedBallSkin)
	assertTrue(
		equip.ok and equip.data ~= nil and equip.data.purchased == false,
		"Bundle skin re-equips for free at zero Gems"
	)
	assertTrue(
		p.bossGems == 0 and p.equippedBallSkin == bundle.guaranteedBallSkin,
		"Bundle entitlement persists"
	)
	-- Older saves may own the hatch cosmetic without an equipped hatch slot.
	p.ownedCosmetics.SupernovaHatch = true
	local hatch = EconomyLogic.buyOrEquipCosmetic(p, "SupernovaHatch")
	assertTrue(
		hatch.ok and hatch.data ~= nil and hatch.data.purchased == false,
		"Legacy entitlement re-equips for free"
	)
	assertTrue(
		p.equippedHatchVfx == "SupernovaHatch" and p.equippedBallSkin == bundle.guaranteedBallSkin,
		"Equipping a legacy hatch cosmetic preserves the selected skin"
	)
end

local function rejectInvalidWalletAndPayload()
	local p = EconomyLogic.createDefaultProfile(100)
	p.bossGems = math.huge
	assertTrue(
		not EconomyLogic.buyOrEquipCosmetic(p, "RoyalMarblePlot").ok,
		"Infinite wallet cannot buy a theme"
	)
	assertTrue(
		p.bossGems == math.huge and p.equippedPlotTheme == nil and next(p.ownedCosmetics) == nil,
		"Infinite wallet rejection is atomic"
	)
	p.bossGems = 110
	for _, malformed in { false, 110, { id = "RoyalMarblePlot", costGems = 0 } } do
		assertTrue(
			not EconomyLogic.buyOrEquipCosmetic(p, malformed :: any).ok,
			"Only catalog ID strings are accepted"
		)
		assertTrue(
			p.bossGems == 110 and p.equippedPlotTheme == nil and next(p.ownedCosmetics) == nil,
			"Malformed request cannot spend or equip"
		)
	end
end

local function noopReequipAndChangedFlag()
	local p = EconomyLogic.createDefaultProfile(100)
	p.bossGems = 370
	local firstBuy = EconomyLogic.buyOrEquipCosmetic(p, "RoyalMarblePlot")
	assertTrue(
		firstBuy.ok
			and firstBuy.data ~= nil
			and firstBuy.data.purchased == true
			and firstBuy.data.changed == true,
		"First purchase must mark changed = true"
	)
	local noopTheme = EconomyLogic.buyOrEquipCosmetic(p, "RoyalMarblePlot")
	assertTrue(
		noopTheme.ok
			and noopTheme.data ~= nil
			and noopTheme.data.purchased == false
			and noopTheme.data.changed == false
			and noopTheme.data.alreadyEquipped == true
			and p.bossGems == 260,
		"Re-selecting equipped PlotTheme must report changed = false (no-op)"
	)
	assertTrue(EconomyLogic.buyOrEquipCosmetic(p, "PrismTrail").ok, "Buy PrismTrail")
	local noopSkin = EconomyLogic.buyOrEquipCosmetic(p, "PrismTrail")
	assertTrue(
		noopSkin.ok
			and noopSkin.data ~= nil
			and noopSkin.data.changed == false
			and noopSkin.data.alreadyEquipped == true,
		"Re-selecting equipped BallSkin reports changed = false"
	)
	assertTrue(EconomyLogic.buyOrEquipCosmetic(p, "CyberPulse").ok, "Switch to CyberPulse")
	local switchBack = EconomyLogic.buyOrEquipCosmetic(p, "PrismTrail")
	assertTrue(
		switchBack.ok
			and switchBack.data ~= nil
			and switchBack.data.purchased == false
			and switchBack.data.changed == true
			and switchBack.data.alreadyEquipped == false
			and p.equippedBallSkin == "PrismTrail",
		"Switching to another owned BallSkin reports changed = true"
	)
end

exactPriceAndFailedSwitch()
directBundleAndLegacyEquip()
rejectInvalidWalletAndPayload()
noopReequipAndChangedFlag()
print("PASS: CosmeticsAndThemes.spec.luau")
