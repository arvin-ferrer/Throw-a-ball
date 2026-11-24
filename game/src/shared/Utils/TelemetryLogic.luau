--!strict
--[[
	TelemetryLogic.luau
	Pure launch telemetry helpers (first-session bounce buckets and 30s starter hatch outcomes).
]]

local TelemetryLogic = {}

local function isFiniteNonNegative(value: any): boolean
	return type(value) == "number"
		and value == value
		and value >= 0
		and value ~= math.huge
		and value ~= -math.huge
end

function TelemetryLogic.sessionBucket(durationSeconds: number, isFirstSession: boolean?): string
	if isFirstSession == false then
		return "ReturningSession"
	end
	if not isFiniteNonNegative(durationSeconds) then
		return "FirstPlayBounce_Under60s"
	end
	if durationSeconds < 60 then
		return "FirstPlayBounce_Under60s"
	elseif durationSeconds <= 180 then
		return "FirstPlayBounce_61To180s"
	else
		return "EngagedSession_Over180s"
	end
end

function TelemetryLogic.starterHatchOutcome(elapsedSeconds: number?): (string?, number?)
	if not isFiniteNonNegative(elapsedSeconds) then
		return nil, nil
	end
	local safeSec = elapsedSeconds :: number
	if safeSec <= 30 then
		return "StarterHatch_Within30s", safeSec
	end
	return "StarterHatch_Over30s", safeSec
end

return TelemetryLogic
