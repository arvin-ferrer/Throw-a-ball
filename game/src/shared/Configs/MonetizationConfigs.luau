--!strict
--[[
	MonetizationConfigs.luau
	Game Passes, Cosmetics, Paid Random Eggs, and Non-Random Direct Bundles
	for PolicyService ArePaidRandomItemsRestricted compliance (GDD §10).
]]

export type GamePassSpec = {
	key: string,
	displayName: string,
	description: string,
	passId: number,
	attributeName: string,
}

export type DirectBundleSpec = {
	id: string,
	replacesEggId: string,
	displayName: string,
	description: string,
	devProductId: number,
	guaranteedPetId: string,
	guaranteedMutation: string,
	guaranteedBallSkin: string,
}

export type CosmeticSpec = {
	id: string,
	category: "BallSkin" | "HatchVFX" | "EliminationVFX" | "PlotTheme",
	displayName: string,
	costGems: number,
	color: { number },
}

local MonetizationConfigs = {}

MonetizationConfigs.GAME_PASSES = {
	DoubleTraining = {
		key = "DoubleTraining",
		displayName = "2x Training Speed",
		description = "Doubles Ball Damage & Throw Speed gains on your Training Range.",
		passId = 190001001,
		attributeName = "Pass_DoubleTraining",
	},
	DoubleCoinsExp = {
		key = "DoubleCoinsExp",
		displayName = "2x Coins & EXP",
		description = "Doubles Cash Pad Coins, PvE Coins, and EXP across all biomes.",
		passId = 190001002,
		attributeName = "Pass_DoubleCoinsExp",
	},
	AutoFireRange = {
		key = "AutoFireRange",
		displayName = "Auto-Fire Training Pad",
		description = "Automatically fires downrange while standing on your Training Pad.",
		passId = 190001003,
		attributeName = "Pass_AutoFireRange",
	},
	MagnetCollect = {
		key = "MagnetCollect",
		displayName = "Magnet Coin Collect",
		description = "Automatically vacuums Cash Pad Coins across your Personal Plot.",
		passId = 190001004,
		attributeName = "Pass_MagnetCollect",
	},
	ExtraPedestals = {
		key = "ExtraPedestals",
		displayName = "+2 Base Pedestal Slots",
		description = "Unlocks VIP Bonus Pedestals #13 and #14 on your Personal Plot.",
		passId = 190001005,
		attributeName = "Pass_ExtraPedestals",
	},
} :: { [string]: GamePassSpec }

-- Shown ONLY when PolicyService reports ArePaidRandomItemsRestricted == true.
-- Zero RNG: clearly pictures the exact Pet + Ball Skin granted.
MonetizationConfigs.DIRECT_BUNDLES = {
	Direct_PrismPack = {
		id = "Direct_PrismPack",
		replacesEggId = "Shop_PrismEgg",
		displayName = "Prism Starlight Pack (Direct)",
		description = "Guaranteed Starlight Beetle (Normal) + Prism Trail Ball Skin. Zero RNG!",
		devProductId = 190000201,
		guaranteedPetId = "StarlightBeetle",
		guaranteedMutation = "Normal",
		guaranteedBallSkin = "PrismTrail",
	},
	Direct_CyberPack = {
		id = "Direct_CyberPack",
		replacesEggId = "Seasonal_CyberEgg",
		displayName = "Cyber Neon Pack (Direct)",
		description = "Guaranteed Neon Moth (Normal) + Cyber Pulse Ball Skin. Zero RNG!",
		devProductId = 190000202,
		guaranteedPetId = "NeonMoth",
		guaranteedMutation = "Normal",
		guaranteedBallSkin = "CyberPulse",
	},
} :: { [string]: DirectBundleSpec }

MonetizationConfigs.COSMETICS = {
	PrismTrail = {
		id = "PrismTrail",
		category = "BallSkin",
		displayName = "Prism Trail",
		costGems = 45,
		color = { 244, 114, 182 },
	},
	CyberPulse = {
		id = "CyberPulse",
		category = "BallSkin",
		displayName = "Cyber Pulse",
		costGems = 60,
		color = { 34, 211, 238 },
	},
	SupernovaHatch = {
		id = "SupernovaHatch",
		category = "HatchVFX",
		displayName = "Supernova Hatch Beam",
		costGems = 70,
		color = { 250, 204, 21 },
	},
	VoidShatter = {
		id = "VoidShatter",
		category = "EliminationVFX",
		displayName = "Void Shatter KO",
		costGems = 85,
		color = { 139, 92, 246 },
	},
	RoyalMarblePlot = {
		id = "RoyalMarblePlot",
		category = "PlotTheme",
		displayName = "Royal Marble Plot Theme",
		costGems = 110,
		color = { 248, 250, 252 },
	},
} :: { [string]: CosmeticSpec }

function MonetizationConfigs.getDirectBundleForEgg(eggId: string): DirectBundleSpec?
	for _, bundle in pairs(MonetizationConfigs.DIRECT_BUNDLES) do
		if bundle.replacesEggId == eggId then
			return bundle
		end
	end
	return nil
end

function MonetizationConfigs.getProductByDevProductId(productId: number): (string?, string?)
	if productId == 190000101 then
		return "PaidEgg", "Shop_PrismEgg"
	elseif productId == 190000102 then
		return "PaidEgg", "Seasonal_CyberEgg"
	end
	for id, bundle in pairs(MonetizationConfigs.DIRECT_BUNDLES) do
		if bundle.devProductId == productId then
			return "DirectBundle", id
		end
	end
	return nil, nil
end

return MonetizationConfigs
