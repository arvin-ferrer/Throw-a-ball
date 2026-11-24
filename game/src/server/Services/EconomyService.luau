--!strict
--[[
	EconomyService.luau
	Server-authoritative atomic progression transactions:
	Training Target Tiers, Ball Shop Tiers, Pedestal Expansion (4->12), Offline Vault (50%->100%),
	Active Equip Slots (1->3), Gem-Craftable Biome Eggs, Cosmetics, and Soft Ascension.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyLogic = require(Shared.Utils.EconomyLogic)
local MathUtil = require(Shared.Utils.MathUtil)
local MonetizationConfigs = require(Shared.Configs.MonetizationConfigs)
local Remotes = require(Shared.Net.Remotes)

local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local PetIncomeService = require(script.Parent.PetIncomeService)

local EconomyService = {}

local telemetryHook: ((string, { [string]: any }) -> ())? = nil

local function notifyResult(player: Player, ok: boolean, successMsg: string, failReason: string?)
	local remotes = Remotes.ensureServer()
	if ok then
		remotes.ToastNotify:FireClient(player, successMsg, { 74, 222, 128 })
	else
		remotes.ToastNotify:FireClient(
			player,
			`Upgrade blocked: {failReason or "Unavailable"}`,
			{ 239, 68, 68 }
		)
	end
end

local function handleBuyCosmetic(
	player: Player,
	profile: EconomyLogic.PlayerProfile,
	cosmeticId: string
)
	local spec = MonetizationConfigs.COSMETICS[cosmeticId]
	if not spec then
		notifyResult(player, false, "", "UnknownCosmetic")
		return
	end
	if profile.ownedCosmetics[cosmeticId] then
		if spec.category == "BallSkin" then
			profile.equippedBallSkin = cosmeticId
			DataService.syncToClient(player)
			notifyResult(player, true, `Equipped {spec.displayName}!`, nil)
		end
		return
	end
	if not MathUtil.isFinite(profile.bossGems) or profile.bossGems < spec.costGems then
		notifyResult(player, false, "", "InsufficientGems")
		return
	end
	profile.bossGems -= spec.costGems
	profile.ownedCosmetics[cosmeticId] = true
	if spec.category == "BallSkin" then
		profile.equippedBallSkin = cosmeticId
	end
	if telemetryHook then
		telemetryHook("ShopPurchase", { userId = player.UserId, value = 1 })
	end
	DataService.syncToClient(player)
	notifyResult(player, true, `Unlocked {spec.displayName}!`, nil)
end

local function handleUpgradeAction(player: Player, action: any, arg: any)
	if type(action) ~= "string" then
		return
	end
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end

	local res: EconomyLogic.TxResult = { ok = false, reason = "UnknownAction" }
	local successMsg = "Upgraded!"

	if action == "UpgradeTarget" then
		res = EconomyLogic.buyNextTargetTier(profile)
		successMsg =
			`Training Targets upgraded to {if res.data then res.data.targetTierId else ""}!`
	elseif action == "UpgradeBall" then
		res = EconomyLogic.buyNextBallTier(profile)
		successMsg = `Throwable Ball upgraded to {if res.data then res.data.ballTierId else ""}!`
	elseif action == "UnlockPedestal" then
		res = EconomyLogic.unlockNextPedestal(profile)
		successMsg = `Pedestal #{if res.data then res.data.pedestalsUnlocked else 0} unlocked!`
	elseif action == "UpgradeOfflineVault" then
		res = EconomyLogic.upgradeOfflineVault(profile)
		local pct = if res.data then math.floor((res.data.efficiency or 0.5) * 100) else 50
		successMsg = `Offline Vault upgraded to {pct}% efficiency!`
	elseif action == "UnlockActiveSlot" then
		res = EconomyLogic.unlockNextActiveSlot(profile)
		successMsg =
			`Active Combat Slot #{if res.data then res.data.activeSlotsUnlocked else 1} unlocked!`
	elseif action == "CraftBiomeEgg" and type(arg) == "string" then
		res = EconomyLogic.craftStandardBiomeEgg(profile, arg)
		successMsg = `Crafted {if res.data then res.data.eggId else "Biome Egg"}!`
	elseif action == "SoftAscend" then
		res = EconomyLogic.performSoftAscension(profile)
		successMsg =
			`ASCENSION RANK {if res.data then res.data.ascensionRank else 1}! +25% Coins & +5% Training!`
		if res.ok and telemetryHook then
			telemetryHook("SoftAscension", { userId = player.UserId, rank = profile.ascensionRank })
		end
	elseif action == "BuyCosmetic" and type(arg) == "string" then
		handleBuyCosmetic(player, profile, arg)
		return
	end

	if res.ok then
		if action ~= "SoftAscend" and telemetryHook then
			telemetryHook("ShopPurchase", { userId = player.UserId, value = 1 })
		end
		PlotService.refreshPlotVisuals(player, profile)
		DataService.syncToClient(player)
		notifyResult(player, true, successMsg, nil)
	else
		notifyResult(player, false, "", res.reason)
	end
end

local function onPedestalPrompt(player: Player, pedestalIndex: number)
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	local hasVip = DataService.hasPass(player, "Pass_ExtraPedestals")
	local isVipSlot = pedestalIndex == 13 or pedestalIndex == 14
	local unlocked = (not isVipSlot and pedestalIndex <= profile.pedestalsUnlocked)
		or (isVipSlot and hasVip)
	if not unlocked then
		if not isVipSlot and pedestalIndex == profile.pedestalsUnlocked + 1 then
			handleUpgradeAction(player, "UnlockPedestal", nil)
		else
			Remotes.ensureServer().ToastNotify:FireClient(
				player,
				if isVipSlot
					then "Requires +2 Pedestals VIP Game Pass!"
					else "Unlock earlier pedestals first!",
				{ 250, 204, 21 }
			)
		end
		return
	end
	-- Check if pedestal already has a pet
	for _, pet in ipairs(profile.pets) do
		if pet.pedestalIndex == pedestalIndex then
			Remotes.ensureServer().ToastNotify:FireClient(
				player,
				"Open Pets Menu [P] to Level Up, Fuse, or Toggle Active Follower!",
				{ 56, 189, 248 }
			)
			return
		end
	end
	local eggId = PetIncomeService.pickDefaultEggForPlayer(profile)
	if eggId then
		PetIncomeService.hatchEggOnPedestal(player, eggId, pedestalIndex)
	else
		Remotes.ensureServer().ToastNotify:FireClient(
			player,
			"No Eggs in Backpack! Win a Biome Boss Egg or Craft one with Boss Gems!",
			{ 250, 204, 21 }
		)
	end
end

function EconomyService.setTelemetryHook(cb: (string, { [string]: any }) -> ())
	telemetryHook = cb
end

function EconomyService.init()
	PlotService.setCallbacks({
		onHatch = onPedestalPrompt,
		onCollectPad = function(player: Player, idx: number)
			PetIncomeService.collectPad(player, idx)
		end,
		onUpgradeTarget = function(player: Player)
			handleUpgradeAction(player, "UpgradeTarget", nil)
		end,
		onService = function(player: Player, serviceId: string)
			Remotes.ensureServer().ToastNotify
				:FireClient(player, `OPEN_MODAL:{serviceId}`, { 56, 189, 248 })
		end,
	})
end

function EconomyService.start()
	local remotes = Remotes.ensureServer()
	remotes.UpgradeAction.OnServerEvent:Connect(handleUpgradeAction)
end

return EconomyService
