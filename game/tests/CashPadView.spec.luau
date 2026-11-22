--!strict
-- Issue #11: pure display rules for Cash Pads and the hatch reveal (written red-first).
local CashPadView = require("../src/shared/Utils/CashPadView")

local function run(name: string, test: () -> ())
	local ok, failure = pcall(test)
	assert(ok, `{name}: {failure}`)
end

local function near(a: number, b: number, label: string)
	assert(math.abs(a - b) <= 1e-9, `{label}: expected {b}, got {a}`)
end

run("Between server updates the pad predicts stored + rate x elapsed, capped", function()
	near(CashPadView.predict(100, 5, 2, 1_000_000), 110, "two seconds at 5/s")
	near(CashPadView.predict(999_990, 50, 1, 1_000_000), 1_000_000, "never shows past the cap")
	near(CashPadView.predict(100, 5, -3, 1_000_000), 100, "clock going backwards never subtracts")
	near(CashPadView.predict(0 / 0, 5, 1, 1_000_000), 0, "corrupt stored value shows zero")
end)

run("The counter eases toward its target and snaps when close", function()
	local v = CashPadView.ease(0, 100, 0.1)
	assert(v > 0 and v < 100, "moves part of the way in one frame")
	near(CashPadView.ease(99.95, 100, 0.016), 100, "snaps within a tenth of a coin")
	near(CashPadView.ease(500, 100, 0.1), 100, "drops instantly after a sweep (no counting down)")
end)

run("Sweep chimes rise in pitch with a streak and cap out", function()
	near(CashPadView.chimePitch(1), 1, "first sweep at base pitch")
	near(CashPadView.chimePitch(2), 1.08, "each follow-up sweep is higher")
	near(CashPadView.chimePitch(50), 1.8, "capped so it never gets shrill")
	near(CashPadView.chimePitch(0 / 0), 1, "invalid streak plays the base pitch")
end)

run("Hatch reveal beams are coloured by mutation rarity", function()
	local normal = CashPadView.beamColor("Normal")
	local void = CashPadView.beamColor("VoidTouched")
	assert(normal ~= void, "rarer mutations look different")
	assert(CashPadView.beamColor("Unknown") == normal, "unknown falls back to Normal")
	assert(CashPadView.revealSeconds() == 3, "GDD: a crisp 3.0-second reveal")
end)

run("Coin labels are compact and show the earning rate", function()
	assert(CashPadView.label(1_500, 12) == "1.5K\n+12/s", "compact stored + rate")
	assert(CashPadView.label(0, 0) == "0\n+0/s", "empty pad")
end)

print("PASS: CashPadView.spec.luau")
