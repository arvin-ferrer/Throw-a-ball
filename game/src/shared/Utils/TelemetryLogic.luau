--!strict
--[[
	TelemetryLogic.luau
	Pure launch telemetry helpers (session bounce bucket classification).
]]

local TelemetryLogic = {}

function TelemetryLogic.sessionBucket(durationSeconds: number): string
	if type(durationSeconds) ~= "number" or durationSeconds ~= durationSeconds then
		return "FirstPlayBounce_Under60s"
	end
	if durationSeconds < 0 or durationSeconds == math.huge or durationSeconds == -math.huge then
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

return TelemetryLogic
