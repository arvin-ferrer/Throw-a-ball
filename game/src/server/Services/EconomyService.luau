--!strict
--[[
	EconomyService (Issue #9): the ONLY way Coins, Boss Gems, tiers and eggs change. Every
	change is an EconomyLedger transaction with a server-generated id, so it is atomic, can't
	go negative, and a replayed request can't double-spend. Balances are mirrored to Player
	attributes for the HUD (read-only display; the profile is the truth).
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BiomeConfigs = require(Shared.Configs.BiomeConfigs)
local EconomyLedger = require(Shared.Utils.EconomyLedger)
local Remotes = require(Shared.Net.Remotes)
local DataService = require(script.Parent.DataService)

type Ledger = EconomyLedger.PlayerData
type Result = EconomyLedger.TransactionResult

local MIRRORED: { [string]: string } = {
	Coins = "coins",
	BossGems = "bossGems",
	BallTier = "ballTierId",
	TargetTier = "targetTierId",
	PedestalsUnlocked = "pedestalsUnlocked",
	OfflineVaultTier = "offlineVaultTier",
	AscensionRank = "ascensionRank",
}
-- Training stats are earned by CombatService (attributes) and persisted from there.
local TRAINING: { [string]: string } =
	{ BallDamage = "ballDamage", ThrowSpeed = "throwSpeed", Level = "level", Exp = "exp" }

local EconomyService = {}

local function newId(prefix: string): string
	return `{prefix}:{HttpService:GenerateGUID(false)}`
end

local function mirror(player: Player, data: Ledger)
	for attribute, field in MIRRORED do
		player:SetAttribute(attribute, (data :: any)[field])
	end
end

-- Run one ledger transaction for a loaded player and refresh the HUD mirror.
local function transact(player: Player, run: (data: Ledger) -> Result): Result
	local data = DataService.get(player)
	if not data then
		return { ok = false, reason = "ProfileNotLoaded" }
	end
	local result = run(data)
	if result.ok then
		mirror(player, data)
	end
	return result
end

local function onLoaded(player: Player, data: Ledger)
	for attribute, field in TRAINING do
		player:SetAttribute(attribute, (data :: any)[field])
	end
	mirror(player, data)
	-- Persist training progress as CombatService raises it (finite, never lowered by clients).
	for attribute, field in TRAINING do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			local value = player:GetAttribute(attribute)
			if type(value) == "number" and value == value and value >= 0 and value < math.huge then
				(data :: any)[field] = value
			end
		end)
	end
end

-- Server-side grants -----------------------------------------------------------------------------

function EconomyService.grantCoins(player: Player, amount: number, reason: string): Result
	local coins = math.floor(amount)
	if coins <= 0 then
		return { ok = false, reason = "InvalidAmount" }
	end
	return transact(player, function(data)
		return EconomyLedger.grantCoins(data, newId(reason), coins)
	end)
end

function EconomyService.grantBossGems(player: Player, amount: number, reason: string): Result
	return transact(player, function(data)
		return EconomyLedger.grantBossGems(data, newId(reason), math.floor(amount))
	end)
end

-- ArenaCycleService.onAwardEgg: the egg plus bonus Gems.
function EconomyService.awardArenaWin(userId: number, biomeId: string, eggType: string)
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return
	end
	transact(player, function(data)
		return EconomyLedger.grantEgg(data, newId("BossEgg"), eggType, biomeId)
	end)
	EconomyService.grantBossGems(player, BiomeConfigs.ArenaRewards.winnerBonusBossGems, "WinGems")
end

-- Every participant earns Coins and a Gem (EXP is granted by CombatService's level curve).
function EconomyService.awardConsolation(userIds: { number }, biomeId: string)
	local biome = BiomeConfigs.get(biomeId)
	local rewards = BiomeConfigs.ArenaRewards
	for _, userId in userIds do
		local player = Players:GetPlayerByUserId(userId)
		if player and biome then
			EconomyService.grantCoins(
				player,
				rewards.participantCoinsPerRecDamage * biome.recommendedDamage,
				"ArenaCoins"
			)
			EconomyService.grantBossGems(player, rewards.participantBossGems, "ArenaGems")
		end
	end
end

function EconomyService.getAscensionMultipliers(player: Player): (number, number)
	local data = DataService.get(player)
	if not data then
		return 1, 1
	end
	return EconomyLedger.getAscensionMultipliers(data)
end

-- Shop remote (RemoteFunction ShopPurchase) ---------------------------------------------------------
-- The client sends (kind, argument, requestId). requestId makes a retried click idempotent:
-- the transaction id is scoped to this player, so one player can never replay another's.

local SHOP: { [string]: (data: Ledger, id: string, arg: string) -> Result } = {
	BallTier = EconomyLedger.purchaseBallTier,
	TargetTier = EconomyLedger.purchaseTargetTier,
	Pedestal = function(data, id, _arg)
		return EconomyLedger.expandPedestals(data, id)
	end,
	OfflineVault = function(data, id, _arg)
		return EconomyLedger.upgradeOfflineVault(data, id)
	end,
	GemEgg = EconomyLedger.craftGemEgg,
	Ascend = function(data, id, _arg)
		return EconomyLedger.softAscend(data, id)
	end,
}

local function onShopPurchase(player: Player, kind: unknown, arg: unknown, requestId: unknown): any
	local handler = if type(kind) == "string" then SHOP[kind] else nil
	local validId = type(requestId) == "string" and #requestId > 0 and #requestId <= 64
	if not handler or not validId or (arg ~= nil and (type(arg) ~= "string" or #arg > 64)) then
		return { ok = false, reason = "InvalidRequest" }
	end
	local result = transact(player, function(data)
		return handler(data, `shop:{player.UserId}:{requestId}`, (arg or "") :: string)
	end)
	return { ok = result.ok, reason = result.reason, replayed = result.replayed }
end

function EconomyService.start(remotesFolder: Folder)
	DataService.start(onLoaded)
	local shop = remotesFolder:FindFirstChild(Remotes.Names.ShopPurchase)
	if shop and shop:IsA("RemoteFunction") then
		shop.OnServerInvoke = onShopPurchase
	end
end

return EconomyService
