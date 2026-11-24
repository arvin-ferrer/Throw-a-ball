--!strict
--[[
	TelemetryService.luau
	Phase 4 launch telemetry hooks (First-Play Bounce <60s/61-180s, <=30s Starter Hatch,
	Boss Opt-In Rate, Cash Pad Sweep frequency, Soft Ascension funnel).
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
local DataService = require(script.Parent.DataService)

local TelemetryService = {}

local joinTimestamps: { [number]: number } = {}
local counters: { [string]: number } = {}

local FUNNEL_STEPS: { [string]: { step: number, label: string } } = {
	SessionStart = { step = 1, label = "SessionStart" },
	StarterHatch_Within30s = { step = 2, label = "StarterHatch" },
	StarterHatch_Over30s = { step = 2, label = "StarterHatch" },
	CashPadSweep = { step = 3, label = "CashPadSweep" },
	BossOptInOffered = { step = 4, label = "BossOptInOffered" },
	BossOptInAccepted = { step = 5, label = "BossOptInAccepted" },
	SoftAscension = { step = 6, label = "SoftAscension" },
}

local function logCustom(player: Player?, eventName: string, value: number?)
	counters[eventName] = (counters[eventName] or 0) + 1
	if not player then
		return
	end
	local safeVal = if type(value) == "number" and MathUtil.isFinite(value) then value else 1
	pcall(function()
		AnalyticsService:LogCustomEvent(player, eventName, safeVal)
	end)
	local funnel = FUNNEL_STEPS[eventName]
	if funnel then
		pcall(function()
			AnalyticsService:LogOnboardingFunnelStepEvent(player, funnel.step, funnel.label)
		end)
	end
end

function TelemetryService.record(eventName: string, payload: { [string]: any })
	local uid = tonumber(payload.userId)
	local plr = if uid then Players:GetPlayerByUserId(uid) else nil
	if eventName == "StarterHatch" then
		local joined = if uid then joinTimestamps[uid] else nil
		if not joined then
			return
		end
		local outcome, elapsed = TelemetryLogic.starterHatchOutcome(os.clock() - joined)
		if outcome and elapsed then
			logCustom(plr, outcome, elapsed)
		end
		return
	end
	local raw = tonumber(payload.value or payload.coins or payload.rank or 1)
	local val = if raw and MathUtil.isFinite(raw) then raw else 1
	logCustom(plr, eventName, val)
end

function TelemetryService.getCounters(): { [string]: number }
	return counters
end

local function onPlayerAdded(player: Player)
	if joinTimestamps[player.UserId] then
		return
	end
	joinTimestamps[player.UserId] = os.clock()
	logCustom(player, "SessionStart", 1)
end

function TelemetryService.init()
	ArenaCycleService.setTelemetryHook(TelemetryService.record)
	PetIncomeService.setTelemetryHook(TelemetryService.record)
	EconomyService.setTelemetryHook(TelemetryService.record)
	PolicyGuardService.setTelemetryHook(TelemetryService.record)
end

function TelemetryService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		local joined = joinTimestamps[player.UserId]
		joinTimestamps[player.UserId] = nil
		if joined then
			local duration = os.clock() - joined
			local isFirst = DataService.isFirstSession(player)
			logCustom(player, TelemetryLogic.sessionBucket(duration, isFirst), duration)
		end
	end)
end

return TelemetryService
