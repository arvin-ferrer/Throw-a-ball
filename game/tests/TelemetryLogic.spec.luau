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

print("PASS: TelemetryLogic.spec.luau")
