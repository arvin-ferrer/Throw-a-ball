--!strict
--[[
	Server bootstrap: create the remote contract, then start services against the
	Studio-built map (Workspace.BallBrawl_Map_v2), which Rojo never touches.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyConfigs = require(Shared.Configs.EconomyConfigs)
local Remotes = require(Shared.Net.Remotes)
local ArenaCycleService = require(script.Services.ArenaCycleService)

local MAP_NAME = "BallBrawl_Map_v2"

local remotesFolder = Remotes.setupServer(ReplicatedStorage)

local map = Workspace:FindFirstChild(MAP_NAME)
if map then
	ArenaCycleService.init(map, remotesFolder, {
		onAwardEgg = function(userId, biomeId, eggType)
			print(`[Arena] {userId} won {eggType} in {biomeId}`) -- EconomyService (#9) grants it
		end,
		onAwardConsolation = function(userIds, biomeId)
			print(`[Arena] consolation in {biomeId} for {table.concat(userIds, ",")}`)
		end,
	})
	ArenaCycleService.start()
else
	warn(`[BallBrawlServer] Workspace.{MAP_NAME} not found; arena cycle disabled`)
end

print(`[BallBrawlServer] Bootstrapped (MaxOfflineSeconds={EconomyConfigs.MAX_OFFLINE_SECONDS})`)
