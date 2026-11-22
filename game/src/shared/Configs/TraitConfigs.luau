--!strict
--[[
	TraitConfigs.luau
	Canonical Gem Trait Reroll table (GDD §8.5) summing to 100% roll weight.
]]

export type TraitSpec = {
	id: string,
	displayName: string,
	weight: number,
	description: string,
	coinBonus: number,
	throwSpeedBonus: number,
	ballDamageBonus: number,
	offlineBonus: number,
	globalPlotBonus: number,
	color: { number },
}

local TraitConfigs = {}

TraitConfigs.ORDERED = {
	{
		id = "Greedy",
		displayName = "Greedy",
		weight = 30,
		description = "+25% Pet Coins/sec on Base Pedestal",
		coinBonus = 0.25,
		throwSpeedBonus = 0,
		ballDamageBonus = 0,
		offlineBonus = 0,
		globalPlotBonus = 0,
		color = { 250, 204, 21 },
	},
	{
		id = "Swift",
		displayName = "Swift",
		weight = 25,
		description = "+10% Player Throw Speed while Active Follower",
		coinBonus = 0,
		throwSpeedBonus = 0.10,
		ballDamageBonus = 0,
		offlineBonus = 0,
		globalPlotBonus = 0,
		color = { 56, 189, 248 },
	},
	{
		id = "Brawler",
		displayName = "Brawler",
		weight = 20,
		description = "+8% Player Ball Damage while Active Follower",
		coinBonus = 0,
		throwSpeedBonus = 0,
		ballDamageBonus = 0.08,
		offlineBonus = 0,
		globalPlotBonus = 0,
		color = { 239, 68, 68 },
	},
	{
		id = "Overclocked",
		displayName = "Overclocked",
		weight = 15,
		description = "+20% Offline Accrual Efficiency for that Pedestal",
		coinBonus = 0,
		throwSpeedBonus = 0,
		ballDamageBonus = 0,
		offlineBonus = 0.20,
		globalPlotBonus = 0,
		color = { 192, 132, 252 },
	},
	{
		id = "Tycoon",
		displayName = "Tycoon",
		weight = 10,
		description = "+50% Pet Coins/sec + +10% Global Plot Cash Pad Bonus",
		coinBonus = 0.50,
		throwSpeedBonus = 0,
		ballDamageBonus = 0,
		offlineBonus = 0,
		globalPlotBonus = 0.10,
		color = { 244, 114, 182 },
	},
} :: { TraitSpec }

TraitConfigs.BY_ID = {} :: { [string]: TraitSpec }
for _, spec in ipairs(TraitConfigs.ORDERED) do
	TraitConfigs.BY_ID[spec.id] = spec
end

function TraitConfigs.getTotalWeight(): number
	local total = 0
	for _, spec in ipairs(TraitConfigs.ORDERED) do
		total += spec.weight
	end
	return total
end

function TraitConfigs.rollTrait(rollUnit: number): TraitSpec
	local clamped = math.clamp(rollUnit, 0, 0.9999999)
	local target = clamped * TraitConfigs.getTotalWeight()
	local acc = 0
	for _, spec in ipairs(TraitConfigs.ORDERED) do
		acc += spec.weight
		if target < acc then
			return spec
		end
	end
	return TraitConfigs.ORDERED[#TraitConfigs.ORDERED]
end

function TraitConfigs.getTrait(id: string?): TraitSpec?
	if not id then
		return nil
	end
	return TraitConfigs.BY_ID[id]
end

return TraitConfigs
