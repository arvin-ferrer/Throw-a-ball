--!strict
--[[
	PlotService.luau
	Manages Workspace.BallBrawl_Map_v2 Hub Personal Plots (Plot_01..08),
	Pedestal visuals (4->12 + 2nd-floor Balcony + VIP 13-14), Starter Egg on Pedestal #1,
	Stationary Training Range FiringPad + Moving Gold Target animation, and Unrestricted Biome Portals.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BiomeConfigs = require(Shared.Configs.BiomeConfigs)
local EconomyConfigs = require(Shared.Configs.EconomyConfigs)
local EconomyLogic = require(Shared.Utils.EconomyLogic)
local CombatLogic = require(Shared.Utils.CombatLogic)
local MathUtil = require(Shared.Utils.MathUtil)
local ProceduralModels = require(Shared.Utils.ProceduralModels)
local Remotes = require(Shared.Net.Remotes)
local DataService = require(script.Parent.DataService)

export type PlotRecord = {
	plotId: number,
	model: Model,
	ownerUserId: number,
	plotSpawn: BasePart,
	firingPad: BasePart,
	firingStance: BasePart,
	trainingRange: Instance,
	movingGoldTarget: BasePart?,
	goldOriginCF: CFrame?,
	goldHalfLength: number,
	balconyFolder: Instance?,
	pedestals: { [number]: Model },
	pedestalVisuals: { [number]: Model },
}

local PlotService = {}

local mapRoot: Folder? = nil
local plotsById: { [number]: PlotRecord } = {}
local plotByUserId: { [number]: PlotRecord } = {}
local playerOnPad: { [number]: boolean } = {}
local onHatchRequested: ((Player, number) -> ())? = nil
local onCollectPadRequested: ((Player, number) -> ())? = nil
local onUpgradeTargetRequested: ((Player) -> ())? = nil
local onServiceInteract: ((Player, string) -> ())? = nil

local function findMapRoot(): Folder?
	if mapRoot and mapRoot.Parent then
		return mapRoot
	end
	local found = workspace:FindFirstChild("BallBrawl_Map_v2")
	if found and found:IsA("Folder") then
		mapRoot = found
		return mapRoot
	end
	return nil
end

local function ensurePrompt(
	parent: BasePart,
	actionText: string,
	objectText: string,
	maxDist: number
): ProximityPrompt
	local existing = parent:FindFirstChildOfClass("ProximityPrompt")
	if existing then
		existing.ActionText = actionText
		existing.ObjectText = objectText
		existing.MaxActivationDistance = maxDist
		existing.RequiresLineOfSight = false
		return existing
	end
	local p = Instance.new("ProximityPrompt")
	p.Name = "Prompt"
	p.ActionText = actionText
	p.ObjectText = objectText
	p.MaxActivationDistance = maxDist
	p.RequiresLineOfSight = false
	p.HoldDuration = 0
	p.Parent = parent
	return p
end

local function setOwnerSignText(plot: PlotRecord, text: string)
	local shell = plot.model:FindFirstChild("Shell")
	local sign = if shell then shell:FindFirstChild("OwnerSign") else nil
	if not sign or not sign:IsA("BasePart") then
		return
	end
	local sg = sign:FindFirstChildOfClass("SurfaceGui")
	if not sg then
		sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Front
		sg.Parent = sign
		local lbl = Instance.new("TextLabel")
		lbl.Name = "Text"
		lbl.BackgroundTransparency = 1
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.Font = Enum.Font.FredokaOne
		lbl.TextScaled = true
		lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
		lbl.Parent = sg
	end
	local lbl = sg:FindFirstChildWhichIsA("TextLabel", true)
	if lbl then
		lbl.Text = text
	end
end

local function discoverPlots()
	local root = findMapRoot()
	if not root then
		warn("[PlotService] Workspace.BallBrawl_Map_v2 not found")
		return
	end
	local hub = root:FindFirstChild("Hub")
	local plotsFolder = if hub then hub:FindFirstChild("Plots") else nil
	if not plotsFolder then
		return
	end
	for _, plotModel in ipairs(plotsFolder:GetChildren()) do
		if plotModel:IsA("Model") then
			local plotId = tonumber(plotModel:GetAttribute("PlotId"))
			local plotSpawn = plotModel:FindFirstChild("PlotSpawn")
			local tr = plotModel:FindFirstChild("TrainingRange")
			local firingPad = if tr then tr:FindFirstChild("FiringPad") else nil
			local firingStance = if tr then tr:FindFirstChild("FiringStance") else nil
			if
				plotId
				and plotSpawn
				and plotSpawn:IsA("BasePart")
				and tr
				and firingPad
				and firingPad:IsA("BasePart")
				and firingStance
				and firingStance:IsA("BasePart")
			then
				local peds: { [number]: Model } = {}
				local pedFolder = plotModel:FindFirstChild("Pedestals")
				if pedFolder then
					for _, ped in ipairs(pedFolder:GetChildren()) do
						if ped:IsA("Model") then
							local idx = tonumber(ped:GetAttribute("PedestalIndex"))
							if idx then
								peds[idx] = ped
							end
						end
					end
				end
				local goldPart = tr:FindFirstChild("Target_MovingGold")
				local rec: PlotRecord = {
					plotId = plotId,
					model = plotModel,
					ownerUserId = 0,
					plotSpawn = plotSpawn,
					firingPad = firingPad,
					firingStance = firingStance,
					trainingRange = tr,
					movingGoldTarget = if goldPart and goldPart:IsA("BasePart")
						then goldPart
						else nil,
					goldOriginCF = if goldPart and goldPart:IsA("BasePart")
						then goldPart.CFrame
						else nil,
					goldHalfLength = if goldPart
						then tonumber(goldPart:GetAttribute("RailHalfLength")) or 12
						else 12,
					balconyFolder = plotModel:FindFirstChild("Balcony"),
					pedestals = peds,
					pedestalVisuals = {},
				}
				plotsById[plotId] = rec
				setOwnerSignText(rec, `Plot #{plotId} — Open`)
			end
		end
	end
end

local function wirePlotInteractions(plot: PlotRecord)
	-- Training Range Upgrade Terminal
	local terminal = plot.trainingRange:FindFirstChild("UpgradeTerminal")
	if terminal and terminal:IsA("BasePart") then
		local prompt = ensurePrompt(terminal, "Upgrade Targets", "Training Range", 12)
		prompt.Triggered:Connect(function(player: Player)
			if plot.ownerUserId == player.UserId and onUpgradeTargetRequested then
				onUpgradeTargetRequested(player)
			end
		end)
	end

	-- Pedestal Prompts & CashPad touch sweeps
	for idx, pedModel in pairs(plot.pedestals) do
		local base = pedModel:FindFirstChild("Base")
		if base and base:IsA("BasePart") then
			local prompt = ensurePrompt(base, "Hatch / Manage", `Pedestal #{idx}`, 12)
			prompt.Triggered:Connect(function(player: Player)
				if plot.ownerUserId == player.UserId and onHatchRequested then
					onHatchRequested(player, idx)
				end
			end)
		end
		local pad = pedModel:FindFirstChild("CashPad")
		if pad and pad:IsA("BasePart") then
			pad.Touched:Connect(function(hit: BasePart)
				local char = hit.Parent
				local plr = if char then Players:GetPlayerFromCharacter(char) else nil
				if plr and plr.UserId == plot.ownerUserId and onCollectPadRequested then
					onCollectPadRequested(plr, idx)
				end
			end)
		end
	end
end

local function wireHubPortalsAndServices()
	-- Unrestricted Biome Portals (GDD §7.1: 100% unrestricted entry from Minute 1)
	local portalDebounce: { [number]: number } = {}
	for _, field in ipairs(CollectionService:GetTagged("BiomePortal")) do
		if field:IsA("BasePart") then
			local biomeId = tostring(field:GetAttribute("BiomeId") or "")
			local biome = BiomeConfigs.getBiome(biomeId)
			if biome and biome.enabled then
				field.Touched:Connect(function(hit: BasePart)
					local plr = Players:GetPlayerFromCharacter(hit.Parent)
					if not plr then
						return
					end
					local now = os.clock()
					if (portalDebounce[plr.UserId] or 0) + 1.2 > now then
						return
					end
					portalDebounce[plr.UserId] = now
					PlotService.teleportToBiomePvE(plr, biomeId)
				end)
			end
		end
	end

	-- Return Portals inside Biomes -> back to Personal Plot
	for _, field in ipairs(CollectionService:GetTagged("ReturnPortal")) do
		if field:IsA("BasePart") then
			field.Touched:Connect(function(hit: BasePart)
				local plr = Players:GetPlayerFromCharacter(hit.Parent)
				if not plr then
					return
				end
				local now = os.clock()
				if (portalDebounce[plr.UserId] or 0) + 1.2 > now then
					return
				end
				portalDebounce[plr.UserId] = now
				PlotService.teleportToHubPlot(plr)
			end)
		end
	end

	-- Hub Service stations (BallShop, EggShop, TraitAltar, GemEggCrafter, AscensionShrine, CodexPavilion)
	for _, part in ipairs(CollectionService:GetTagged("ServiceInteract")) do
		if part:IsA("BasePart") then
			local serviceId = tostring(part:GetAttribute("ServiceId") or "")
			local prompt = ensurePrompt(part, "Open", serviceId, 14)
			prompt.Triggered:Connect(function(plr: Player)
				if onServiceInteract then
					onServiceInteract(plr, serviceId)
				end
			end)
		end
	end
end

function PlotService.setCallbacks(callbacks: {
	onHatch: ((Player, number) -> ())?,
	onCollectPad: ((Player, number) -> ())?,
	onUpgradeTarget: ((Player) -> ())?,
	onService: ((Player, string) -> ())?,
})
	onHatchRequested = callbacks.onHatch
	onCollectPadRequested = callbacks.onCollectPad
	onUpgradeTargetRequested = callbacks.onUpgradeTarget
	onServiceInteract = callbacks.onService
end

function PlotService.getMapRoot(): Folder?
	return findMapRoot()
end

function PlotService.getPlotForPlayer(player: Player): PlotRecord?
	return plotByUserId[player.UserId]
end

local function computeWorldHalfExtents(part: BasePart): (number, number, number)
	local cf = part.CFrame
	local sz = part.Size
	local hx = 0.5
		* (
			math.abs(cf.XVector.X) * sz.X
			+ math.abs(cf.YVector.X) * sz.Y
			+ math.abs(cf.ZVector.X) * sz.Z
		)
	local hy = 0.5
		* (
			math.abs(cf.XVector.Y) * sz.X
			+ math.abs(cf.YVector.Y) * sz.Y
			+ math.abs(cf.ZVector.Y) * sz.Z
		)
	local hz = 0.5
		* (
			math.abs(cf.XVector.Z) * sz.X
			+ math.abs(cf.YVector.Z) * sz.Y
			+ math.abs(cf.ZVector.Z) * sz.Z
		)
	return hx, hy, hz
end

function PlotService.isPlayerOnAssignedPad(player: Player): boolean
	local plot = plotByUserId[player.UserId]
	local char = player.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
	local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
	if not plot or not hrp or not hrp:IsA("BasePart") or not hum or hum.Health <= 0 then
		return false
	end
	local pad = plot.firingPad
	local hx, hy, hz = computeWorldHalfExtents(pad)
	local delta = hrp.Position - pad.Position
	return CombatLogic.isWithinPadFootprint(delta.X, delta.Y, delta.Z, hx, hy, hz)
end

function PlotService.teleportCharacter(player: Player, targetCF: CFrame)
	local char = player.Character
	if not char then
		return
	end
	-- Always land strictly upright (zero pitch/roll even if the pad is a rotated Cylinder!)
	local pos = targetCF.Position + Vector3.new(0, 4.2, 0)
	local flatLook = Vector3.new(targetCF.LookVector.X, 0, targetCF.LookVector.Z)
	local uprightCF = if flatLook.Magnitude > 0.1
		then CFrame.lookAt(pos, pos + flatLook.Unit)
		else CFrame.new(pos)
	char:PivotTo(uprightCF)

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.PlatformStand = false
		hum.Sit = false
		hum:ChangeState(Enum.HumanoidStateType.Running)
	end
end

function PlotService.teleportToHubPlot(player: Player)
	local plot = plotByUserId[player.UserId]
	player:SetAttribute("Zone", "Hub")
	player:SetAttribute("ActiveBiome", "")
	playerOnPad[player.UserId] = false
	if plot then
		PlotService.teleportCharacter(player, plot.plotSpawn.CFrame)
		return
	end
	local root = findMapRoot()
	local fallback = if root
		then root:FindFirstChild("Hub")
			and root.Hub:FindFirstChild("Spawns")
			and root.Hub.Spawns:FindFirstChild("FallbackSpawn")
		else nil
	if fallback and fallback:IsA("BasePart") then
		PlotService.teleportCharacter(player, fallback.CFrame)
	end
end

function PlotService.teleportToBiomePvE(player: Player, biomeId: string): boolean
	local root = findMapRoot()
	if not root then
		return false
	end
	local biomesFolder = root:FindFirstChild("Biomes")
	local biomeFolder = if biomesFolder then biomesFolder:FindFirstChild(biomeId) else nil
	local pveLayer = if biomeFolder then biomeFolder:FindFirstChild("PvELayer") else nil
	local arrival = if pveLayer then pveLayer:FindFirstChild("ArrivalPad") else nil
	if not arrival or not arrival:IsA("BasePart") then
		return false
	end
	player:SetAttribute("Zone", "BiomePvE")
	player:SetAttribute("ActiveBiome", biomeId)
	playerOnPad[player.UserId] = false
	PlotService.teleportCharacter(player, arrival.CFrame)
	return true
end

function PlotService.refreshPlotVisuals(player: Player, profile: EconomyLogic.PlayerProfile)
	local plot = plotByUserId[player.UserId]
	if not plot then
		return
	end
	local hasVip = DataService.hasPass(player, "Pass_ExtraPedestals")
	local hasDouble = DataService.hasPass(player, "Pass_DoubleCoinsExp")
	plot.model:SetAttribute("PedestalsUnlocked", profile.pedestalsUnlocked)
	plot.trainingRange:SetAttribute("TargetTier", profile.targetTierId)
	ProceduralModels.styleTrainingTargets(plot.trainingRange, profile.targetTierId)

	local ascTag = if profile.ascensionRank > 0 then ` ★Asc {profile.ascensionRank}` else ""
	setOwnerSignText(plot, `{player.DisplayName}'s Plot{ascTag}`)

	-- Show/hide Balcony highlight for Tier 3 (Pedestals 9-12)
	if plot.balconyFolder then
		local unlockedBalcony = profile.pedestalsUnlocked >= 9 or hasVip
		for _, part in ipairs(plot.balconyFolder:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Transparency = if unlockedBalcony then 0 else 0.72
			end
		end
	end

	-- Map placed pets by pedestal index
	local petByPed: { [number]: EconomyLogic.OwnedPet } = {}
	for _, pet in ipairs(profile.pets) do
		if pet.pedestalIndex ~= nil then
			petByPed[pet.pedestalIndex] = pet
		end
	end

	for idx, pedModel in pairs(plot.pedestals) do
		local isVipSlot = idx == 13 or idx == 14
		local unlocked = (not isVipSlot and idx <= profile.pedestalsUnlocked)
			or (isVipSlot and hasVip)
		pedModel:SetAttribute("Locked", not unlocked)

		local base = pedModel:FindFirstChild("Base")
		local prompt = if base then base:FindFirstChildOfClass("ProximityPrompt") else nil
		local anchor = pedModel:FindFirstChild("PetAnchor")
		local pad = pedModel:FindFirstChild("CashPad")
		local starterEggPart = pedModel:FindFirstChild("StarterEgg")

		-- Starter Egg visibility on Pedestal #1
		if starterEggPart and starterEggPart:IsA("BasePart") then
			local showStarter = (idx == 1)
				and not profile.starterEggHatched
				and (profile.eggs.StarterEgg or 0) > 0
			starterEggPart.Transparency = if showStarter then 0 else 1
			starterEggPart.CanCollide = false
		end

		-- Clear previous procedural pet rig
		if plot.pedestalVisuals[idx] then
			plot.pedestalVisuals[idx]:Destroy()
			plot.pedestalVisuals[idx] = nil
		end

		local placed = petByPed[idx]
		if placed and anchor and anchor:IsA("BasePart") then
			local rate = EconomyLogic.computePlacedPetRate(profile, placed, hasDouble)
			pedModel:SetAttribute("PetId", placed.speciesId)
			local rig = ProceduralModels.createPetModel(
				placed.speciesId,
				placed.mutationKey,
				placed.starTier,
				`{MathUtil.formatNumber(rate)}/s • Lv {placed.level}`
			)
			rig:PivotTo(anchor.CFrame)
			rig.Parent = pedModel
			plot.pedestalVisuals[idx] = rig
			if prompt then
				prompt.ActionText = "Manage Pet"
				prompt.ObjectText = `Pedestal #{idx}`
			end
		else
			pedModel:SetAttribute("PetId", "")
			if prompt then
				if idx == 1 and not profile.starterEggHatched then
					prompt.ActionText = "Hatch Starter Egg!"
					prompt.ObjectText = "Free Minute-0 Egg"
				elseif unlocked then
					prompt.ActionText = "Hatch Egg"
					prompt.ObjectText = `Pedestal #{idx} (Open)`
				else
					local spec = EconomyConfigs.PEDESTAL_UNLOCKS[idx]
					prompt.ActionText = if isVipSlot then "VIP +2 Slots" else "Unlock Pedestal"
					prompt.ObjectText = if spec and not isVipSlot
						then `{MathUtil.formatNumber(spec.costCoins)} Coins`
						else "Game Pass"
				end
			end
		end

		if pad and pad:IsA("BasePart") then
			local stored = math.floor(profile.padStoredCoins[idx] or 0)
			pad:SetAttribute("StoredCoins", stored)
			pad.Color = if stored > 0
				then Color3.fromRGB(74, 222, 128)
				elseif unlocked then Color3.fromRGB(56, 72, 92)
				else Color3.fromRGB(45, 38, 52)
			pad.Material = if stored > 0 then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
	end
end

local function assignPlot(player: Player, profile: EconomyLogic.PlayerProfile)
	if plotByUserId[player.UserId] then
		PlotService.refreshPlotVisuals(player, profile)
		return
	end
	for id = 1, 8 do
		local rec = plotsById[id]
		if rec and rec.ownerUserId == 0 then
			rec.ownerUserId = player.UserId
			rec.model:SetAttribute("OwnerUserId", player.UserId)
			plotByUserId[player.UserId] = rec
			player:SetAttribute("PlotId", id)
			PlotService.refreshPlotVisuals(player, profile)
			if player.Character then
				PlotService.teleportToHubPlot(player)
			end
			return
		end
	end
end

local function releasePlot(player: Player)
	local rec = plotByUserId[player.UserId]
	if not rec then
		return
	end
	for idx, rig in pairs(rec.pedestalVisuals) do
		rig:Destroy()
		rec.pedestalVisuals[idx] = nil
	end
	rec.ownerUserId = 0
	rec.model:SetAttribute("OwnerUserId", 0)
	setOwnerSignText(rec, `Plot #{rec.plotId} — Open`)
	plotByUserId[player.UserId] = nil
	playerOnPad[player.UserId] = nil
end

function PlotService.init()
	discoverPlots()
	for _, plot in pairs(plotsById) do
		wirePlotInteractions(plot)
	end
	wireHubPortalsAndServices()
end

local function bindPlayerSpawns()
	Players.PlayerAdded:Connect(function(player: Player)
		player.CharacterAdded:Connect(function(char: Model)
			local hum = char:WaitForChild("Humanoid", 10)
			local profile = DataService.getProfile(player)
			if hum and hum:IsA("Humanoid") and profile then
				local maxHP = EconomyConfigs.getPlayerMaxHP(profile.level)
				hum.MaxHealth = maxHP
				hum.Health = maxHP
			end
			task.defer(function()
				PlotService.teleportToHubPlot(player)
			end)
		end)
	end)
end

local function bindPlotRemotes()
	local remotes = Remotes.ensureServer()
	remotes.TeleportZone.OnServerEvent:Connect(function(player: Player, targetZone: any)
		if type(targetZone) ~= "string" or player:GetAttribute("Zone") == "LockedBossPvP" then
			return
		end
		if targetZone == "Hub" then
			PlotService.teleportToHubPlot(player)
		elseif BiomeConfigs.getBiome(targetZone) then
			PlotService.teleportToBiomePvE(player, targetZone)
		end
	end)

	remotes.SetTrainingStance.OnServerEvent:Connect(function(player: Player, wantsLock: any)
		if type(wantsLock) ~= "boolean" then
			return
		end
		playerOnPad[player.UserId] = wantsLock and PlotService.isPlayerOnAssignedPad(player)
	end)
end

function PlotService.start()
	DataService.onProfileLoaded(assignPlot)
	bindPlayerSpawns()
	Players.PlayerRemoving:Connect(releasePlot)
	bindPlotRemotes()

	RunService.Heartbeat:Connect(function()
		local t = os.clock()
		for _, plot in pairs(plotsById) do
			if plot.movingGoldTarget and plot.goldOriginCF then
				local offset = math.sin(t * 2.1 + plot.plotId) * plot.goldHalfLength
				plot.movingGoldTarget.CFrame = plot.goldOriginCF * CFrame.new(offset, 0, 0)
			end
		end
	end)
end

return PlotService
