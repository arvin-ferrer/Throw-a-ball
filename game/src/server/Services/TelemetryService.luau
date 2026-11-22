--!strict
--[[
	TelemetryService.luau
	Phase 4 launch telemetry hooks (First-Play Bounce <60s/61-180s, Boss Opt-In Rate,
	Cash Pad Sweep frequency, Egg Hatch onboarding, Soft Ascension funnel).
	Safely wraps AnalyticsService in pcall so unpublished/Studio runs never throw.
]]

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")

local ArenaCycleService = require(script.Parent.ArenaCycleService)
local PetIncomeService = require(script.Parent.PetIncomeService)
local EconomyService = require(script.Parent.EconomyService)

local TelemetryService = {}

local joinTimestamps: { [number]: number } = {}
local counters: { [string]: number } = {}

local function logCustom(player: Player?, eventName: string, value: number?)
	counters[eventName] = (counters[eventName] or 0) + 1
	if not player then
		return
	end
	pcall(function()
		AnalyticsService:LogCustomEvent(player, eventName, value or 1)
	end)
end

function TelemetryService.record(eventName: string, payload: { [string]: any })
	local uid = tonumber(payload.userId)
	local plr = if uid then Players:GetPlayerByUserId(uid) else nil
	logCustom(plr, eventName, tonumber(payload.coins or payload.rank or 1))
end

function TelemetryService.getCounters(): { [string]: number }
	return counters
end

function TelemetryService.init()
	ArenaCycleService.setTelemetryHook(TelemetryService.record)
	PetIncomeService.setTelemetryHook(TelemetryService.record)
	EconomyService.setTelemetryHook(TelemetryService.record)
end

function TelemetryService.start()
	Players.PlayerAdded:Connect(function(player: Player)
		joinTimestamps[player.UserId] = os.clock()
		logCustom(player, "SessionStart", 1)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		local joined = joinTimestamps[player.UserId]
		joinTimestamps[player.UserId] = nil
		if joined then
			local duration = os.clock() - joined
			if duration < 60 then
				logCustom(player, "FirstPlayBounce_Under60s", duration)
			elseif duration <= 180 then
				logCustom(player, "FirstPlayBounce_61To180s", duration)
			else
				logCustom(player, "EngagedSession_Over180s", duration)
			end
		end
	end)
end

return TelemetryService
