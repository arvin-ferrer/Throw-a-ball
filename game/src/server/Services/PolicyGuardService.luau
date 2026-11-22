--!strict
--[[
	PolicyGuardService (Issue #15): the Roblox side of PolicyGuard + PurchaseLedger.
	- PolicyService snapshot per player, fetched once on join; any failure = restricted.
	- ProcessReceipt: grant through PurchaseLedger (exactly once per PurchaseId), then return
	  PurchaseGranted ONLY when the receipt marker is in the profile's last SAVED data.
	  Everything else returns NotProcessedYet so Roblox retries later (scenario-roblox-data).
	- GetPolicyState RemoteFunction for the shop UI (#16).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PolicyGuard = require(Shared.Utils.PolicyGuard)
local PurchaseLedger = require(Shared.Utils.PurchaseLedger)
local Remotes = require(Shared.Net.Remotes)
local DataService = require(script.Parent.DataService)

local SAVE_CONFIRM_TIMEOUT = 15

local PolicyGuardService = {}

local snapshots: { [Player]: any } = {}

local function fetchPolicy(player: Player)
	local ok, info = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
	snapshots[player] = if ok and type(info) == "table" then info else nil -- nil = restricted
end

function PolicyGuardService.getSnapshot(player: Player): any
	return snapshots[player]
end

local function markerSaved(profile: any, marker: string): boolean
	local saved = profile.LastSavedData
	return type(saved) == "table"
		and type(saved.transactionReceipts) == "table"
		and saved.transactionReceipts[marker] ~= nil
end

-- Save and wait until the receipt marker is durable (or give up for this attempt).
local function confirmSaved(profile: any, marker: string): boolean
	if markerSaved(profile, marker) then
		return true
	end
	profile:Save()
	local deadline = os.clock() + SAVE_CONFIRM_TIMEOUT
	while os.clock() < deadline and profile:IsActive() do
		if markerSaved(profile, marker) then
			return true
		end
		task.wait(0.5)
	end
	return markerSaved(profile, marker)
end

local function processReceipt(info: any): Enum.ProductPurchaseDecision
	local player = type(info) == "table" and Players:GetPlayerByUserId(info.PlayerId)
	local profile = player and DataService.getProfile(player)
	if not (player and profile) then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- granted on their next session
	end
	-- Policy is read BEFORE the non-yielding ledger call; unknown policy = restricted.
	local result =
		PurchaseLedger.processReceipt(profile.Data, player.UserId, info, snapshots[player])
	if result.decision == "Rejected" then
		warn(`[PolicyGuardService] receipt {info.PurchaseId} rejected: {result.reason}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if confirmSaved(profile, `Robux:{info.PurchaseId}`) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

local function onGetPolicyState(player: Player): any
	local snapshot = snapshots[player]
	return {
		arePaidRandomItemsRestricted = PolicyGuard.isRestricted(snapshot),
		source = if snapshot then "LivePolicyService" else "FallbackSafe",
	}
end

function PolicyGuardService.start(remotesFolder: Folder)
	Players.PlayerAdded:Connect(fetchPolicy)
	for _, player in Players:GetPlayers() do
		task.spawn(fetchPolicy, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		snapshots[player] = nil
	end)
	-- The ONE ProcessReceipt for the whole experience.
	MarketplaceService.ProcessReceipt = processReceipt
	local remote = remotesFolder:FindFirstChild(Remotes.Names.GetPolicyState)
	if remote and remote:IsA("RemoteFunction") then
		remote.OnServerInvoke = onGetPolicyState
	end
end

return PolicyGuardService
