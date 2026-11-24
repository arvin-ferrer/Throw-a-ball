--!strict
--[[
	PolicyGuardService.luau
	Roblox 2026 Paid Random Items compliance (PolicyService), Game Pass entitlement sync,
	and single atomic MarketplaceService.ProcessReceipt handler.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local PolicyService = game:GetService("PolicyService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MonetizationConfigs = require(Shared.Configs.MonetizationConfigs)
local PolicyLogic = require(Shared.Utils.PolicyLogic)
local Remotes = require(Shared.Net.Remotes)

local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)

local PolicyGuardService = {}

local restrictedByUser: { [number]: boolean } = {}
local policyTokens: { [number]: number } = {}
local nextPolicyToken = 0
local recordedShopReceipts: { [string]: boolean } = {}
local telemetryHook: ((string, { [string]: any }) -> ())? = nil

local function checkPlayerPolicy(player: Player, token: number)
	local restricted = true
	if player:GetAttribute("Test_RestrictRandom") ~= true then
		local ok, info = pcall(function()
			return PolicyService:GetPolicyInfoForPlayerAsync(player)
		end)
		if ok and type(info) == "table" and info.ArePaidRandomItemsRestricted == false then
			restricted = false
		end
	end
	if not player.Parent or policyTokens[player.UserId] ~= token then
		return
	end
	restrictedByUser[player.UserId] = restricted
	player:SetAttribute("ArePaidRandomItemsRestricted", restricted)
end

local function syncGamePasses(player: Player)
	for _, spec in pairs(MonetizationConfigs.GAME_PASSES) do
		local owned = player:GetAttribute(spec.attributeName) == true
		if not owned then
			local ok, result = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, spec.passId)
			end)
			if ok and result == true then
				owned = true
			end
		end
		player:SetAttribute(spec.attributeName, owned)
	end
end

local function handleProcessReceipt(receiptInfo: any): Enum.ProductPurchaseDecision
	local userId = receiptInfo.PlayerId
	local purchaseId = tostring(receiptInfo.PurchaseId or "")
	local productId = tonumber(receiptInfo.ProductId) or 0
	local player = Players:GetPlayerByUserId(userId)
	local profile = DataService.getProfileByUserId(userId)
	if not player or not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local restricted = PolicyGuardService.isRestricted(player)
	local res = PolicyLogic.applyProductReceipt(profile, purchaseId, productId, restricted)
	if not res.granted then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local saved = DataService.savePlayer(userId, false, purchaseId)
	if not saved then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	PlotService.refreshPlotVisuals(player, profile)
	DataService.syncToClient(player)
	if not recordedShopReceipts[purchaseId] then
		recordedShopReceipts[purchaseId] = true
		if telemetryHook then
			telemetryHook("ShopPurchase", { userId = player.UserId, value = 1 })
		end
		if not res.duplicate then
			Remotes.ensureServer().ToastNotify:FireClient(
				player,
				"Purchase confirmed! Check your Egg Backpack / Pet Inventory!",
				{ 74, 222, 128 }
			)
		end
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function PolicyGuardService.isRestricted(player: Player): boolean
	return restrictedByUser[player.UserId] ~= false
end

function PolicyGuardService.setTelemetryHook(cb: (string, { [string]: any }) -> ())
	telemetryHook = cb
end

function PolicyGuardService.init() end

local function onGamePassFinished(player: Player, passId: number, purchased: boolean)
	if not purchased then
		return
	end
	for _, spec in pairs(MonetizationConfigs.GAME_PASSES) do
		if spec.passId == passId then
			player:SetAttribute(spec.attributeName, true)
			local profile = DataService.getProfile(player)
			if profile then
				PlotService.refreshPlotVisuals(player, profile)
				DataService.syncToClient(player)
			end
			if telemetryHook then
				telemetryHook("ShopPurchase", { userId = player.UserId, value = 1 })
			end
			Remotes.ensureServer().ToastNotify
				:FireClient(player, `Game Pass Activated: {spec.displayName}!`, { 250, 204, 21 })
			break
		end
	end
end

local function handleShopRequest(player: Player, kind: any, idOrProduct: any)
	if type(kind) ~= "string" then
		return
	end
	if kind == "GamePass" and type(idOrProduct) == "string" then
		local spec = MonetizationConfigs.GAME_PASSES[idOrProduct]
		if spec then
			pcall(function()
				MarketplaceService:PromptGamePassPurchase(player, spec.passId)
			end)
		end
	elseif kind == "Product" and type(idOrProduct) == "number" then
		local allowed, reason =
			PolicyLogic.canPromptProduct(idOrProduct, PolicyGuardService.isRestricted(player))
		if not allowed then
			Remotes.ensureServer().ToastNotify:FireClient(
				player,
				`Purchase blocked by regional policy ({reason or "Restricted"}).`,
				{ 239, 68, 68 }
			)
			return
		end
		pcall(function()
			MarketplaceService:PromptProductPurchase(player, idOrProduct)
		end)
	end
end

local function initPolicyAndPasses(player: Player)
	nextPolicyToken += 1
	local token = nextPolicyToken
	policyTokens[player.UserId] = token
	restrictedByUser[player.UserId] = true
	player:SetAttribute("ArePaidRandomItemsRestricted", true)
	task.spawn(function()
		checkPlayerPolicy(player, token)
		syncGamePasses(player)
	end)
end

function PolicyGuardService.start()
	MarketplaceService.ProcessReceipt = handleProcessReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(onGamePassFinished)

	Players.PlayerAdded:Connect(initPolicyAndPasses)
	for _, player in ipairs(Players:GetPlayers()) do
		initPolicyAndPasses(player)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		restrictedByUser[player.UserId] = nil
		policyTokens[player.UserId] = nil
	end)

	Remotes.ensureServer().ShopRequest.OnServerEvent:Connect(handleShopRequest)
end

return PolicyGuardService
