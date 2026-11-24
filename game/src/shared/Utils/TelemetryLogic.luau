--!strict
--[[
	TelemetryLogic.luau
	Pure launch telemetry helpers (first-session bounce buckets, 30s starter hatch outcomes,
	and strict monotonic 1->4 onboarding funnel transitions).
]]

export type FunnelStep = {
	step: number,
	label: string,
}

local TelemetryLogic = {}

local FUNNEL_STEPS: { [string]: FunnelStep } = {
	SessionStart = { step = 1, label = "SessionStart" },
	StarterHatch_Within30s = { step = 2, label = "StarterHatch" },
	StarterHatch_Over30s = { step = 2, label = "StarterHatch" },
	CashPadSweep = { step = 3, label = "CashPadSweep" },
	SoftAscension = { step = 4, label = "SoftAscension" },
}

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

function TelemetryLogic.starterHatchOutcome(
	elapsedSeconds: number?,
	isFirstSession: boolean?
): (string?, number?)
	if isFirstSession ~= true or not isFiniteNonNegative(elapsedSeconds) then
		return nil, nil
	end
	local safeSec = elapsedSeconds :: number
	if safeSec <= 30 then
		return "StarterHatch_Within30s", safeSec
	end
	return "StarterHatch_Over30s", safeSec
end

function TelemetryLogic.nextFunnelStep(eventName: string, currentStep: number?): FunnelStep?
	local target = FUNNEL_STEPS[eventName]
	if not target then
		return nil
	end
	local prev = if type(currentStep) == "number" and isFiniteNonNegative(currentStep)
		then math.floor(currentStep)
		else 0
	if target.step ~= prev + 1 then
		return nil
	end
	return target
end

return TelemetryLogic
