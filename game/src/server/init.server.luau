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
local EconomyService = require(Services.EconomyService)
local MobService = require(Services.MobService)
local PortalService = require(Services.PortalService)

local BiomeConfigs = require(Shared.Configs.BiomeConfigs)

local MAP_NAME = "BallBrawl_Map_v2"

local remotesFolder = Remotes.setupServer(ReplicatedStorage)
EconomyService.start(remotesFolder) -- profiles load even without a map

-- Every arena participant: Coins + a Gem (EconomyService) and EXP (CombatService level curve).
local function payParticipants(userIds: { number }, biomeId: string)
	EconomyService.awardConsolation(userIds, biomeId)
	for _, userId in userIds do
		local player = game:GetService("Players"):GetPlayerByUserId(userId)
		if player then
			CombatService.grantExp(player, BiomeConfigs.ArenaRewards.participantExp)
		end
	end
end

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
		grantCoins = function(player, amount, reason)
			EconomyService.grantCoins(player, amount, reason)
		end,
		getTrainingMultiplier = function(player)
			local _, training = EconomyService.getAscensionMultipliers(player)
			return training
		end,
	})
	ArenaCycleService.init(map, remotesFolder, {
		onSpawnBoss = BossAIService.spawn,
		onDespawnBoss = BossAIService.despawn,
		getBossHealth = BossAIService.getHealth,
		onAwardEgg = function(userId, biomeId, eggType)
			EconomyService.awardArenaWin(userId, biomeId, eggType)
			payParticipants({ userId }, biomeId) -- the winner is a participant too
		end,
		onAwardConsolation = payParticipants,
	})
	ArenaCycleService.start()
else
	warn(`[BallBrawlServer] Workspace.{MAP_NAME} not found; arena and combat disabled`)
end

print(`[BallBrawlServer] Bootstrapped (MaxOfflineSeconds={EconomyConfigs.MAX_OFFLINE_SECONDS})`)
