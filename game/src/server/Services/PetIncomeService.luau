--!strict
--[[
	PetIncomeService.luau
	Server-authoritative Cash Pad accrual (1 Hz), walk-over & Magnet sweep validation,
	3.0-second Pedestal Hatch reveals, Pet Lv 1-25, 3-to-1 Star Fusion, Gem Trait Rerolls,
	and Unified Active Combat Followers (1-3 slots without pausing pedestal Coin income).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyLogic = require(Shared.Utils.EconomyLogic)
local PetConfigs = require(Shared.Configs.PetConfigs)
local EggConfigs = require(Shared.Configs.EggConfigs)
local MathUtil = require(Shared.Utils.MathUtil)
local Remotes = require(Shared.Net.Remotes)

local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)

local PetIncomeService = {}

local activeHatchLock: { [number]: boolean } = {}
local telemetryHook: ((string, { [string]: any }) -> ())? = nil

local function canReachPad(player: Player, pedestalIndex: number): boolean
	if DataService.hasPass(player, "Pass_MagnetCollect") then
		return true
	end
	local plot = PlotService.getPlotForPlayer(player)
	local char = player.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
	if not plot or not hrp or not hrp:IsA("BasePart") then
		return false
	end
	local ped = plot.pedestals[pedestalIndex]
	local pad = if ped then ped:FindFirstChild("CashPad") else nil
	if not pad or not pad:IsA("BasePart") then
		return false
	end
	return (hrp.Position - pad.Position).Magnitude <= 14
end

function PetIncomeService.collectPad(player: Player, pedestalIndex: number)
	local profile = DataService.getProfile(player)
	if
		not profile
		or not MathUtil.isPositiveFinite(pedestalIndex)
		or math.floor(pedestalIndex) ~= pedestalIndex
	then
		return
	end
	if pedestalIndex < 1 or pedestalIndex > 14 or not canReachPad(player, pedestalIndex) then
		return
	end
	local gained = EconomyLogic.collectCashPad(profile, pedestalIndex)
	if gained <= 0 then
		return
	end
	local plot = PlotService.getPlotForPlayer(player)
	if plot and plot.pedestals[pedestalIndex] then
		local pad = plot.pedestals[pedestalIndex]:FindFirstChild("CashPad")
		if pad and pad:IsA("BasePart") then
			pad:SetAttribute("StoredCoins", 0)
			pad.Color = Color3.fromRGB(56, 72, 92)
			pad.Material = Enum.Material.SmoothPlastic
		end
	end
	DataService.syncToClient(player)
	if telemetryHook then
		telemetryHook(
			"CashPadSweep",
			{ userId = player.UserId, pedestalIndex = pedestalIndex, coins = gained }
		)
	end
end

function PetIncomeService.collectAllPadsMagnet(player: Player)
	if not DataService.hasPass(player, "Pass_MagnetCollect") then
		return
	end
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	local total = 0
	for idx = 1, 14 do
		total += EconomyLogic.collectCashPad(profile, idx)
	end
	if total > 0 then
		PlotService.refreshPlotVisuals(player, profile)
		DataService.syncToClient(player)
		if telemetryHook then
			telemetryHook("CashPadSweep", { userId = player.UserId, coins = total })
		end
	end
end

local function broadcastHatchReveal(
	player: Player,
	profile: EconomyLogic.PlayerProfile,
	plot: PlotService.PlotRecord,
	eggId: string,
	pedestalIndex: number,
	newPet: EconomyLogic.OwnedPet
)
	local remotes = Remotes.ensureServer()
	local spec = PetConfigs.getSpecies(newPet.speciesId)
	local ped = plot.pedestals[pedestalIndex]
	local anchor = if ped then ped:FindFirstChild("PetAnchor") else nil
	local pos = if anchor and anchor:IsA("BasePart")
		then anchor.Position
		else plot.plotSpawn.Position
	remotes.HatchReveal:FireAllClients({
		ownerUserId = player.UserId,
		ownerName = player.DisplayName,
		eggId = eggId,
		speciesId = newPet.speciesId,
		displayName = if spec then spec.displayName else newPet.speciesId,
		rarity = if spec then spec.rarity else "Common",
		mutationKey = newPet.mutationKey,
		position = pos,
		duration = 3.0,
	})
	task.delay(3.0, function()
		activeHatchLock[player.UserId] = nil
		if player.Parent then
			PlotService.refreshPlotVisuals(player, profile)
			DataService.syncToClient(player)
			local label = if spec then spec.displayName else newPet.speciesId
			remotes.ToastNotify:FireClient(
				player,
				`HATCHED [{newPet.mutationKey}] {label}!`,
				{ 74, 222, 128 }
			)
		end
	end)
end

function PetIncomeService.hatchEggOnPedestal(player: Player, eggId: string, pedestalIndex: number)
	if activeHatchLock[player.UserId] then
		return
	end
	local profile = DataService.getProfile(player)
	local plot = PlotService.getPlotForPlayer(player)
	if not profile or not plot then
		return
	end
	local hasVip = DataService.hasPass(player, "Pass_ExtraPedestals")
	local res = EconomyLogic.hatchEggOnPedestal(
		profile,
		eggId,
		pedestalIndex,
		hasVip,
		math.random(),
		math.random()
	)
	if not res.ok or not res.data then
		Remotes.ensureServer().ToastNotify
			:FireClient(player, `Cannot hatch: {res.reason or "Error"}`, { 239, 68, 68 })
		return
	end
	activeHatchLock[player.UserId] = true
	local newPet = res.data.pet :: EconomyLogic.OwnedPet
	broadcastHatchReveal(player, profile, plot, eggId, pedestalIndex, newPet)
	if telemetryHook then
		telemetryHook("EggHatched", {
			userId = player.UserId,
			eggId = eggId,
			speciesId = newPet.speciesId,
			mutationKey = newPet.mutationKey,
		})
		if eggId == "StarterEgg" then
			telemetryHook("StarterHatch", { userId = player.UserId })
		end
	end
end

function PetIncomeService.pickDefaultEggForPlayer(profile: EconomyLogic.PlayerProfile): string?
	if not profile.starterEggHatched and (profile.eggs.StarterEgg or 0) > 0 then
		return "StarterEgg"
	end
	local priority = {
		"MoltenCaldera_OverchargedEgg",
		"FrostbiteCavern_OverchargedEgg",
		"EmeraldMeadow_OverchargedEgg",
		"MoltenCaldera_BossEgg",
		"FrostbiteCavern_BossEgg",
		"EmeraldMeadow_BossEgg",
		"Seasonal_CyberEgg",
		"Shop_PrismEgg",
	}
	for _, eggId in ipairs(priority) do
		if (profile.eggs[eggId] or 0) > 0 and EggConfigs.getEgg(eggId) then
			return eggId
		end
	end
	return nil
end

local function executePetAction(
	player: Player,
	profile: EconomyLogic.PlayerProfile,
	action: string,
	payload: any
): (boolean, EconomyLogic.TxResult)
	if action == "LevelUp" and type(payload) == "string" then
		return true, EconomyLogic.levelUpPet(profile, payload)
	elseif action == "Fuse" and type(payload) == "table" then
		return true, EconomyLogic.fusePets(profile, payload)
	elseif action == "RerollTrait" and type(payload) == "string" then
		return true, EconomyLogic.rerollPetTrait(profile, payload, math.random())
	elseif action == "ToggleActive" and type(payload) == "string" then
		return true, EconomyLogic.toggleActiveFollower(profile, payload)
	elseif action == "PlacePet" and type(payload) == "table" and type(payload.uid) == "string" then
		local rawIdx = payload.pedestalIndex
		if rawIdx ~= nil then
			if
				type(rawIdx) ~= "number"
				or not MathUtil.isFinite(rawIdx)
				or math.floor(rawIdx) ~= rawIdx
			then
				return false, { ok = false, reason = "InvalidPedestal" }
			end
		end
		return true,
			EconomyLogic.placeOrMovePet(
				profile,
				payload.uid,
				rawIdx,
				DataService.hasPass(player, "Pass_ExtraPedestals")
			)
	elseif action == "SellPet" and type(payload) == "string" then
		return true, EconomyLogic.sellPet(profile, payload)
	end
	return true, { ok = false, reason = "UnknownAction" }
end

local function handlePetAction(player: Player, action: any, payload: any)
	if type(action) ~= "string" then
		return
	end
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	local accepted, res = executePetAction(player, profile, action, payload)
	if not accepted then
		return
	end
	local remotes = Remotes.ensureServer()
	if res.ok then
		PlotService.refreshPlotVisuals(player, profile)
		DataService.syncToClient(player)
		if action == "Fuse" then
			remotes.ToastNotify:FireClient(
				player,
				"STAR FUSION SUCCESS! Pet promoted!",
				{ 250, 204, 21 }
			)
		elseif action == "RerollTrait" and res.data then
			remotes.ToastNotify:FireClient(
				player,
				`Rolled Trait: {res.data.traitId}!`,
				{ 192, 132, 252 }
			)
		end
	else
		remotes.ToastNotify:FireClient(
			player,
			`Action failed: {res.reason or "Invalid"}`,
			{ 239, 68, 68 }
		)
	end
end

function PetIncomeService.setTelemetryHook(cb: (string, { [string]: any }) -> ())
	telemetryHook = cb
end

function PetIncomeService.init() end

local function runCashPadAccrualTick()
	for _, player in ipairs(Players:GetPlayers()) do
		local profile = DataService.getProfile(player)
		local plot = PlotService.getPlotForPlayer(player)
		if profile and plot then
			local added = EconomyLogic.accruePedestalCoins(
				profile,
				1.0,
				false,
				DataService.hasPass(player, "Pass_DoubleCoinsExp")
			)
			if added > 0 then
				for idx, pedModel in pairs(plot.pedestals) do
					local pad = pedModel:FindFirstChild("CashPad")
					if pad and pad:IsA("BasePart") then
						local stored = math.floor(profile.padStoredCoins[idx] or 0)
						if stored > 0 then
							pad:SetAttribute("StoredCoins", stored)
							pad.Color = Color3.fromRGB(74, 222, 128)
							pad.Material = Enum.Material.Neon
						end
					end
				end
			end
		end
	end
end

function PetIncomeService.start()
	local remotes = Remotes.ensureServer()
	remotes.CollectCashPad.OnServerEvent:Connect(function(player: Player, pedestalIndex: any)
		if pedestalIndex == "AllMagnet" then
			PetIncomeService.collectAllPadsMagnet(player)
		elseif type(pedestalIndex) == "number" then
			PetIncomeService.collectPad(player, pedestalIndex)
		end
	end)
	remotes.HatchEgg.OnServerEvent:Connect(function(player: Player, eggId: any, pedestalIndex: any)
		if
			type(eggId) ~= "string"
			or not MathUtil.isPositiveFinite(pedestalIndex)
			or math.floor(pedestalIndex) ~= pedestalIndex
		then
			return
		end
		PetIncomeService.hatchEggOnPedestal(player, eggId, pedestalIndex)
	end)
	remotes.PetAction.OnServerEvent:Connect(handlePetAction)
	Players.PlayerRemoving:Connect(function(player: Player)
		activeHatchLock[player.UserId] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(1.0)
			runCashPadAccrualTick()
		end
	end)
end

return PetIncomeService
