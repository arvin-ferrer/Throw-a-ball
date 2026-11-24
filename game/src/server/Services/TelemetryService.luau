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
local funnelStepByUser: { [number]: number } = {}
local starterHatchRecorded: { [number]: boolean } = {}
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
	local uid = player.UserId
	local funnel = TelemetryLogic.nextFunnelStep(eventName, funnelStepByUser[uid])
	if funnel then
		funnelStepByUser[uid] = funnel.step
		pcall(function()
			AnalyticsService:LogOnboardingFunnelStepEvent(player, funnel.step, funnel.label)
		end)
	end
end

local function recordStarterHatch(plr: Player?, uid: number?, explicitSeconds: number?)
	if not plr or not uid or starterHatchRecorded[uid] then
		return
	end
	local isFirst = plr:GetAttribute("IsFirstSession") == true
	if not isFirst then
		return
	end
	local elapsed = explicitSeconds
	if elapsed == nil then
		local joined = joinTimestamps[uid]
		elapsed = if joined then os.clock() - joined else nil
	end
	local outcome, safeSec = TelemetryLogic.starterHatchOutcome(elapsed, isFirst)
	if outcome and safeSec then
		starterHatchRecorded[uid] = true
		logCustom(plr, outcome, safeSec)
		logCustom(plr, "FirstEggHatchSeconds", safeSec)
	end
end

function TelemetryService.record(eventName: string, payload: { [string]: any })
	local uid = tonumber(payload.userId)
	local plr = if uid then Players:GetPlayerByUserId(uid) else nil
	if eventName == "StarterHatch" or eventName == "FirstEggHatchSeconds" then
		local explicit = if eventName == "FirstEggHatchSeconds"
			then tonumber(payload.value or payload.seconds)
			else nil
		recordStarterHatch(plr, uid, explicit)
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
	local uid = player.UserId
	if joinTimestamps[uid] then
		return
	end
	joinTimestamps[uid] = os.clock()
	funnelStepByUser[uid] = 0
	starterHatchRecorded[uid] = nil
	logCustom(player, "SessionStart", 1)
end

local function onPlayerRemoving(player: Player)
	local uid = player.UserId
	local joined = joinTimestamps[uid]
	joinTimestamps[uid] = nil
	funnelStepByUser[uid] = nil
	starterHatchRecorded[uid] = nil
	if joined then
		local duration = os.clock() - joined
		local isFirst = DataService.isFirstSession(player)
		logCustom(player, TelemetryLogic.sessionBucket(duration, isFirst), duration)
	end
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
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return TelemetryService
