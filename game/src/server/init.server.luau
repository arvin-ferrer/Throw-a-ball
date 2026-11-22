--!strict
--[[
	init.server.luau
	Ordered 2-phase server bootstrap (Init then Start) for Ball Brawl: Boss Eggs (v1.1).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)

Remotes.ensureServer()

local ServicesFolder = script:WaitForChild("Services")
local DataService = require(ServicesFolder.DataService)
local PolicyGuardService = require(ServicesFolder.PolicyGuardService)
local PlotService = require(ServicesFolder.PlotService)
local ArenaCycleService = require(ServicesFolder.ArenaCycleService)
local BossAIService = require(ServicesFolder.BossAIService)
local CombatService = require(ServicesFolder.CombatService)
local PetIncomeService = require(ServicesFolder.PetIncomeService)
local EconomyService = require(ServicesFolder.EconomyService)
local TelemetryService = require(ServicesFolder.TelemetryService)

local orderedServices: { { name: string, mod: any } } = {
	{ name = "DataService", mod = DataService },
	{ name = "PolicyGuardService", mod = PolicyGuardService },
	{ name = "PlotService", mod = PlotService },
	{ name = "ArenaCycleService", mod = ArenaCycleService },
	{ name = "BossAIService", mod = BossAIService },
	{ name = "CombatService", mod = CombatService },
	{ name = "PetIncomeService", mod = PetIncomeService },
	{ name = "EconomyService", mod = EconomyService },
	{ name = "TelemetryService", mod = TelemetryService },
}

for _, entry in ipairs(orderedServices) do
	local ok, err = pcall(entry.mod.init)
	if not ok then
		warn(`[BallBrawlServer] Init error in {entry.name}: {err}`)
	end
end

for _, entry in ipairs(orderedServices) do
	local ok, err = pcall(entry.mod.start)
	if not ok then
		warn(`[BallBrawlServer] Start error in {entry.name}: {err}`)
	end
end

script:SetAttribute("BootOk", true)
print(`[BallBrawlServer] All {#orderedServices} services initialized & started.`)
