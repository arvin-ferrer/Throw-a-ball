--!strict
--[[
	TelemetryService.luau
	Phase 4 launch telemetry hooks (First-Play Bounce <60s/61-180s, Boss Opt-In Rate,
	Cash Pad Sweep frequency, Egg Hatch onboarding, Soft Ascension funnel).
	Safely wraps AnalyticsService in pcall so unpublished/Studio runs never throw.
]]

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MathUtil = require(Shared.Utils.MathUtil)
local TelemetryLogic = require(Shared.Utils.TelemetryLogic)

local ArenaCycleService = require(script.Parent.ArenaCycleService)
local PetIncomeService = require(script.Parent.PetIncomeService)
local EconomyService = require(script.Parent.EconomyService)
local PolicyGuardService = require(script.Parent.PolicyGuardService)

local TelemetryService = {}

local joinTimestamps: { [number]: number } = {}
local counters: { [string]: number } = {}

local function logCustom(player: Player?, eventName: string, value: number?)
	counters[eventName] = (counters[eventName] or 0) + 1
	if not player then
		return
	end
	local safeVal = if type(value) == "number" and MathUtil.isFinite(value) then value else 1
	pcall(function()
		AnalyticsService:LogCustomEvent(player, eventName, safeVal)
	end)
end

function TelemetryService.record(eventName: string, payload: { [string]: any })
	local uid = tonumber(payload.userId)
	local plr = if uid then Players:GetPlayerByUserId(uid) else nil
	local val: number
	if eventName == "StarterHatch" then
		local joined = if uid then joinTimestamps[uid] else nil
		val = if joined then math.max(0, os.clock() - joined) else 0
	else
		local raw = tonumber(payload.value or payload.coins or payload.rank or 1)
		val = if raw and MathUtil.isFinite(raw) then raw else 1
	end
	logCustom(plr, eventName, val)
end

function TelemetryService.getCounters(): { [string]: number }
	return counters
end

function TelemetryService.init()
	ArenaCycleService.setTelemetryHook(TelemetryService.record)
	PetIncomeService.setTelemetryHook(TelemetryService.record)
	EconomyService.setTelemetryHook(TelemetryService.record)
	PolicyGuardService.setTelemetryHook(TelemetryService.record)
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
			logCustom(player, TelemetryLogic.sessionBucket(duration), duration)
		end
	end)
end

return TelemetryService
