--!strict
-- Issue #14: Active Ball Perks (GDD §8.3). Written red-first, before ActivePerks.luau.
local ActivePerks = require("../src/shared/Utils/ActivePerks")

local function run(name: string, test: () -> ())
	local ok, failure = pcall(test)
	assert(ok, `{name}: {failure}`)
end

local function near(actual: number?, expected: number, label: string)
	assert(
		actual and math.abs(actual - expected) <= 1e-9,
		`{label}: expected {expected}, got {actual}`
	)
end

local function pet(species: string, stars: number?)
	return { petId = species, level = 1, stars = stars or 1, mutation = "Normal" }
end

run("No followers means a plain hit with no effects", function()
	local hit = ActivePerks.onHit(ActivePerks.resolve({}), 100, 0.5)
	assert(hit.damage == 100 and not hit.crit, "plain damage")
	assert(
		hit.burn == nil and hit.slow == nil and hit.ricochet == nil and hit.leech == nil,
		"no effects"
	)
end)

run("Distinct perks stack and duplicate perks keep only the highest star tier", function()
	local perks = ActivePerks.resolve({ pet("SnowFox", 1), pet("SnowFox", 3), pet("ThornStag", 1) })
	near(perks.FrostSlow, 1.30, "3-star Frost Slow wins over the 1-star copy")
	near(perks.CritSurge, 1.00, "distinct Crit Surge also applies")
	local count = 0
	for _ in perks do
		count += 1
	end
	assert(count == 2, "two distinct perks, not three")
end)

run("GDD magnitudes: slow, burn, ricochet, leech, knockback", function()
	local perks = ActivePerks.resolve({
		pet("SnowFox"),
		pet("AshLizard"),
		pet("ShardOwl"),
		pet("DewSprite"),
		pet("PebbleCub"),
	})
	local hit = ActivePerks.onHit(perks, 200, 0.99)
	assert(hit.damage == 200 and not hit.crit, "no crit at a high roll")
	near(hit.slow and hit.slow.fraction, 0.20, "Frost Slow -20%")
	near(hit.slow and hit.slow.seconds, 2.0, "for 2.0s")
	near(hit.burn and hit.burn.totalDamage, 30, "Ember Burn 15% of the hit")
	near(hit.burn and hit.burn.seconds, 3.0, "over 3.0s")
	near(hit.ricochet and hit.ricochet.damage, 90, "Chain Ricochet 45%")
	near(hit.leech, 8, "Vampiric Leech 4% of damage dealt")
	assert(hit.knockback and hit.knockback > 0, "Heavy Knockback impulse")
end)

run("Crit Surge: +12% chance for a 1.75x throw, half-open at the boundary", function()
	local perks = ActivePerks.resolve({ pet("ThornStag") })
	local crit = ActivePerks.onHit(perks, 100, 0.1199)
	assert(crit.crit and crit.damage == 175, "crit under 0.12")
	local plain = ActivePerks.onHit(perks, 100, 0.12)
	assert(not plain.crit and plain.damage == 100, "no crit at exactly 0.12")
	for _, bad in { -1, 1, 0 / 0, math.huge } do
		assert(not ActivePerks.onHit(perks, 100, bad).crit, "invalid rolls never crit")
	end
end)

run("Star tiers scale perk strength by +15% and +30%", function()
	local two = ActivePerks.onHit(ActivePerks.resolve({ pet("SnowFox", 2) }), 100, 0.5)
	near(two.slow and two.slow.fraction, 0.23, "2-star slow")
	local three = ActivePerks.onHit(ActivePerks.resolve({ pet("AshLizard", 3) }), 100, 0.5)
	near(three.burn and three.burn.totalDamage, 19.5, "3-star burn")
end)

run("Training Boost raises Training Range gains by 5% and nothing else", function()
	local perks = ActivePerks.resolve({ pet("TrainingPup") })
	near(ActivePerks.trainingMultiplier(perks), 1.05, "starter boost")
	near(ActivePerks.trainingMultiplier(ActivePerks.resolve({})), 1, "no boost without the pup")
	local hit = ActivePerks.onHit(perks, 100, 0.5)
	assert(hit.damage == 100 and hit.burn == nil, "no combat effect")
end)

run("Follower slots open at levels 1, 10 and 25", function()
	assert(ActivePerks.slotsForLevel(1) == 1 and ActivePerks.slotsForLevel(9) == 1, "one slot")
	assert(ActivePerks.slotsForLevel(10) == 2 and ActivePerks.slotsForLevel(24) == 2, "two slots")
	assert(ActivePerks.slotsForLevel(25) == 3 and ActivePerks.slotsForLevel(80) == 3, "three slots")
	assert(ActivePerks.slotsForLevel(0 / 0) == 1, "invalid level falls back to one slot")
end)

run("Unknown species and invalid damage never produce effects or NaN", function()
	local perks = ActivePerks.resolve({ pet("NotAPet"), { petId = "SnowFox", stars = 9 } :: any })
	near(perks.FrostSlow, 1, "out-of-range stars clamp to the 1-star tier")
	for _, bad in { -5, 0 / 0, math.huge } do
		local hit = ActivePerks.onHit(perks, bad, 0.5)
		assert(hit.damage == 0 and hit.slow == nil, "invalid damage is a no-op hit")
	end
end)

print("PASS: ActivePerks.spec.luau")
