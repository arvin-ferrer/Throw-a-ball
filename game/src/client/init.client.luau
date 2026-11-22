--!strict
--[[
	init.client.luau
	Ordered client bootstrap for Ball Brawl: Boss Eggs (v1.1).
	Mounts mobile-first HUD/Modals, wires Controllers, and syncs initial server state.
]]

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)
local MathUtil = require(Shared.Utils.MathUtil)

local UI = script:WaitForChild("UI")
local Controllers = script:WaitForChild("Controllers")

local HudGui = require(UI.HudGui)
local HubModalsGui = require(UI.HubModalsGui)
local ShopCodexGui = require(UI.ShopCodexGui)

local BallThrowController = require(Controllers.BallThrowController)
local PlotCashController = require(Controllers.PlotCashController)
local ArenaHUDController = require(Controllers.ArenaHUDController)
local HatchVFXController = require(Controllers.HatchVFXController)

local function openPanel(kind: string)
	if kind == "Pets" or kind == "TraitAltar" then
		ShopCodexGui.close()
		HubModalsGui.open("Pets")
	elseif kind == "Eggs" or kind == "GemEggCrafter" then
		ShopCodexGui.close()
		HubModalsGui.open("Eggs")
	elseif kind == "Upgrades" or kind == "BallShop" or kind == "AscensionShrine" then
		ShopCodexGui.close()
		HubModalsGui.open("Upgrades")
	elseif kind == "Shop" or kind == "EggShop" then
		HubModalsGui.close()
		ShopCodexGui.open("Shop")
	elseif kind == "Codex" or kind == "CodexPavilion" then
		HubModalsGui.close()
		ShopCodexGui.open("Codex")
	end
end

local function applyProfilePayload(payload: any)
	if type(payload) ~= "table" or type(payload.profile) ~= "table" then
		return
	end
	HudGui.updateProfile(
		payload.profile,
		tonumber(payload.powerRating) or 0,
		tonumber(payload.maxHP) or 100
	)
	HubModalsGui.setProfile(payload.profile)
	ShopCodexGui.setProfile(payload.profile)
	HatchVFXController.rebuildFollowers(payload.profile)
end

HudGui.mount({
	onThrow = BallThrowController.fireThrow,
	onDash = BallThrowController.triggerDash,
	onOpenModal = openPanel,
})
HubModalsGui.mount()
ShopCodexGui.mount()
ArenaHUDController.setServiceModalHandler(openPanel)

BallThrowController.start()
PlotCashController.start()
ArenaHUDController.start()
HatchVFXController.start()

local remotes = Remotes.waitClient()
remotes.ProfileSync.OnClientEvent:Connect(applyProfilePayload)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.P then
		openPanel("Pets")
	elseif input.KeyCode == Enum.KeyCode.B then
		openPanel("Shop")
	elseif input.KeyCode == Enum.KeyCode.C then
		openPanel("Codex")
	end
end)

task.spawn(function()
	local ok, initial = pcall(function()
		return remotes.GetInitialState:InvokeServer()
	end)
	if ok and type(initial) == "table" then
		applyProfilePayload(initial)
		local offline = tonumber(initial.offlineCoinsEarned) or 0
		if offline > 0 then
			ArenaHUDController.showToast(
				`Welcome back! Your Pets earned +{MathUtil.formatNumber(offline)} Offline Coins on your Cash Pads!`,
				{ 250, 204, 21 }
			)
		end
	end
end)

script:SetAttribute("BootOk", true)
print("[BallBrawlClient] All UI & Controllers bootstrapped.")
