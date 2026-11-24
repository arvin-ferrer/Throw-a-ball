--!strict
-- Issue #18 (part 1): TelemetryLogic session bounce buckets (red-first spec).
local TelemetryLogic = require("../src/shared/Utils/TelemetryLogic")

local function run(name: string, test: () -> ())
	local ok, failure = pcall(test)
	assert(ok, `{name}: {failure}`)
end

run("Session bounce buckets classify <60s, 61-180s, and >180s", function()
	assert(TelemetryLogic.sessionBucket(0) == "FirstPlayBounce_Under60s", "0s under 60")
	assert(TelemetryLogic.sessionBucket(59.9) == "FirstPlayBounce_Under60s", "59.9s under 60")
	assert(TelemetryLogic.sessionBucket(60) == "FirstPlayBounce_61To180s", "60s boundary")
	assert(TelemetryLogic.sessionBucket(180) == "FirstPlayBounce_61To180s", "180s upper boundary")
	assert(TelemetryLogic.sessionBucket(180.1) == "EngagedSession_Over180s", "180.1s engaged")
end)

run("Invalid or negative durations clamp safely to Under60s", function()
	for _, bad in { -5, 0 / 0, math.huge, -math.huge } do
		assert(
			TelemetryLogic.sessionBucket(bad) == "FirstPlayBounce_Under60s",
			"non-finite or negative duration falls back cleanly"
		)
	end
end)

run("Returning sessions classify separately from first-play bounce", function()
	assert(TelemetryLogic.sessionBucket(12, false) == "ReturningSession", "returning under 60s")
	assert(TelemetryLogic.sessionBucket(400, false) == "ReturningSession", "returning over 180s")
	assert(
		TelemetryLogic.sessionBucket(45, true) == "FirstPlayBounce_Under60s",
		"explicit first session still uses bounce bucket"
	)
end)

run("Starter hatch outcome bounds <=30s vs >30s and omits unknown durations", function()
	for _, bad in { -1, 0 / 0, math.huge, -math.huge } do
		local outcome, sec = TelemetryLogic.starterHatchOutcome(bad)
		assert(outcome == nil and sec == nil, "invalid duration omitted")
	end
	local nilOutcome, nilSec = TelemetryLogic.starterHatchOutcome(nil)
	assert(nilOutcome == nil and nilSec == nil, "missing join timestamp omitted")

	for _, fast in { 0, 18.5, 30 } do
		local outcome, sec = TelemetryLogic.starterHatchOutcome(fast)
		assert(outcome == "StarterHatch_Within30s" and sec == fast, "fast hatch within 30s")
	end
	for _, slow in { 30.1, 95 } do
		local outcome, sec = TelemetryLogic.starterHatchOutcome(slow)
		assert(outcome == "StarterHatch_Over30s" and sec == slow, "slow hatch over 30s")
	end
end)

print("PASS: TelemetryLogic.spec.luau")
