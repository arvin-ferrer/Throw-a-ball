--!strict
--[[
	Server bootstrap: create the remote contract, then start services against the
	Studio-built map (Workspace.BallBrawl_Map_v2), which Rojo never touches.
	Services talk only through the hooks wired here.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyConfigs = require(Shared.Configs.EconomyConfigs)
local Remotes = require(Shared.Net.Remotes)
local Services = script.Services
local ArenaCycleService = require(Services.ArenaCycleService)
local BossAIService = require(Services.BossAIService)
local CombatService = require(Services.CombatService)
local MobService = require(Services.MobService)
local PortalService = require(Services.PortalService)

local MAP_NAME = "BallBrawl_Map_v2"

local remotesFolder = Remotes.setupServer(ReplicatedStorage)

local map = Workspace:FindFirstChild(MAP_NAME)
if map then
	BossAIService.init(map, {
		getFighterIds = ArenaCycleService.getFighterIds,
		onDefeated = ArenaCycleService.notifyBossDefeated,
	})
	MobService.init(map)
	PortalService.init(map)
	CombatService.init(remotesFolder, {
		canDealPvPDamage = ArenaCycleService.canDealPvPDamage,
		notifyPvPDamage = ArenaCycleService.notifyPvPDamage,
		getFighterBiome = ArenaCycleService.getFighterBiome,
		getBossTarget = BossAIService.getHitTarget,
		damageBoss = function(biomeId, amount, attackerId)
			BossAIService.applyDamage(biomeId, amount, attackerId)
		end,
		getMobTargets = MobService.getTargets,
		damageMob = function(mobId, amount)
			return MobService.applyDamage(mobId, amount)
		end,
	})
	ArenaCycleService.init(map, remotesFolder, {
		onSpawnBoss = BossAIService.spawn,
		onDespawnBoss = BossAIService.despawn,
		getBossHealth = BossAIService.getHealth,
		onAwardEgg = function(userId, biomeId, eggType)
			print(`[Arena] {userId} won {eggType} in {biomeId}`) -- EconomyService (#9) grants it
		end,
		onAwardConsolation = function(userIds, biomeId)
			print(`[Arena] consolation in {biomeId} for {table.concat(userIds, ",")}`)
		end,
	})
	ArenaCycleService.start()
else
	warn(`[BallBrawlServer] Workspace.{MAP_NAME} not found; arena and combat disabled`)
end

print(`[BallBrawlServer] Bootstrapped (MaxOfflineSeconds={EconomyConfigs.MAX_OFFLINE_SECONDS})`)
