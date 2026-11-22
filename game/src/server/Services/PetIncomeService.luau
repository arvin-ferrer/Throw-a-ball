--!strict
--[[
	PetIncomeService (Issue #10): Cash Pads and pet actions on the server.
	- On profile load: offline income (PetIncome.accrueOffline, consumes the logout marker).
	- Every second: online accrual into each player's pads; HUD gets CashPadUpdated.
	- CollectPad: sweep one pad and grant the Coins in the same non-yielding step (one profile,
	  one save), only when the player stands at their own pedestal.
	- PetAction (RemoteFunction): place/remove/fuse/level/reroll/hatch through PetFusion with
	  player-scoped request ids; all rolls are generated here, never by the client.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ActivePerks = require(Shared.Utils.ActivePerks)
local EconomyLedger = require(Shared.Utils.EconomyLedger)
local PetFusion = require(Shared.Utils.PetFusion)
local PetIncome = require(Shared.Utils.PetIncome)
local Remotes = require(Shared.Net.Remotes)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)

type Ledger = EconomyLedger.PlayerData

local TICK_SECONDS = 1
local COLLECT_RANGE_STUDS = 14 -- stand at your pedestal to collect (Magnet Pass later: #15)
local HATCH_SECONDS = 3 -- GDD: 3s hatch reveal

local PetIncomeService = {}

local remotes: Folder? = nil
local rng = Random.new()
local hatching: { [Player]: boolean } = {}

local function fire(player: Player, name: string, payload: any)
	local remote = remotes and remotes:FindFirstChild(name)
	if remote and remote:IsA("RemoteEvent") then
		remote:FireClient(player, payload)
	end
end

local function padSnapshot(data: Ledger)
	local pads = {}
	for slot = 1, data.pedestalsUnlocked do
		local pad = data.pedestalsById[tostring(slot)]
		table.insert(pads, {
			pedestalId = slot,
			petId = pad and pad.petId,
			coinsPerSec = PetIncome.getPadRate(data, slot),
			storedCoins = if pad then math.floor(pad.storedCoins) else 0,
		})
	end
	return pads
end

-- Mirror pad state onto the player's plot pedestals (attributes the map already defines).
local function syncPedestals(player: Player, data: Ledger)
	for slot = 1, 12 do
		local model = PlotService.getPedestal(player, slot)
		if model then
			local pad = data.pedestalsById[tostring(slot)]
			model:SetAttribute("Locked", slot > data.pedestalsUnlocked)
			model:SetAttribute(
				"PetId",
				if pad and pad.petId
					then data.petsById[pad.petId] and data.petsById[pad.petId].petId or ""
					else ""
			)
			model:SetAttribute("StoredCoins", if pad then math.floor(pad.storedCoins) else 0)
			model:SetAttribute("EggId", if pad and pad.eggId then pad.eggId else "")
		end
	end
end

-- Followers' species for every client to render (FollowerRigController, #11).
local function followerSpecies(data: Ledger): string
	local names = {}
	for _, petId in data.activePetIds do
		local pet = data.petsById[petId]
		if pet then
			table.insert(names, pet.petId)
		end
	end
	return table.concat(names, ",")
end

local function broadcast(player: Player, data: Ledger)
	syncPedestals(player, data)
	player:SetAttribute("Followers", followerSpecies(data))
	fire(player, Remotes.Names.CashPadUpdated, { pads = padSnapshot(data) })
end

-- Collect ---------------------------------------------------------------------------------------

local function onCollectPad(player: Player, slot: unknown)
	local data = DataService.get(player)
	local pedestal = if type(slot) == "number" then PlotService.getPedestal(player, slot) else nil
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not (data and pedestal and root and root:IsA("BasePart")) then
		return
	end
	if (root.Position - pedestal:GetPivot().Position).Magnitude > COLLECT_RANGE_STUDS then
		return -- server-observed proximity, never the client's word
	end
	local coins = PetIncome.sweepPad(data, slot :: number)
	if coins > 0 then
		-- Same frame, same profile: the pad debit and the wallet credit save together.
		local id = `collect:{player.UserId}:{os.clock()}:{slot}`
		local result = EconomyLedger.grantCoins(data, id, coins)
		if not result.ok then
			data.pedestalsById[tostring(slot)].storedCoins += coins -- give it back (overflow)
		end
		player:SetAttribute("Coins", data.coins)
	end
	broadcast(player, data)
end

-- Pet actions ----------------------------------------------------------------------------------------

local function hatch(player: Player, data: Ledger, id: string, slot: number, eggId: string): any
	if hatching[player] then
		return { ok = false, reason = "HatchInProgress" }
	end
	hatching[player] = true
	task.wait(HATCH_SECONDS) -- reveal time; re-read the profile afterwards (player may have left)
	hatching[player] = nil
	local live = DataService.get(player)
	if live ~= data then
		return { ok = false, reason = "ProfileNotLoaded" }
	end
	local rolls = { pet = rng:NextNumber(), mutation = rng:NextNumber() }
	local result = PetFusion.hatchEgg(data, id, slot, eggId, rolls)
	if result.ok then
		local pad = data.pedestalsById[tostring(slot)]
		local pet = pad and pad.petId and data.petsById[pad.petId]
		fire(player, Remotes.Names.HatchReveal, { slot = slot, pet = pet })
	end
	return result
end

-- Followers (GDD §8.3): 1 slot, 2 at Level 10, 3 at Level 25. No currency moves here.
local function setFollower(data: Ledger, petId: any, equip: boolean): any
	local index = table.find(data.activePetIds, petId)
	if not data.petsById[petId] then
		return { ok = false, reason = "UnknownPet" }
	elseif not equip then
		if index then
			table.remove(data.activePetIds, index)
		end
		return { ok = true }
	elseif index then
		return { ok = true, replayed = true }
	elseif #data.activePetIds >= ActivePerks.slotsForLevel(data.level) then
		return { ok = false, reason = "NoFreeFollowerSlot" }
	end
	table.insert(data.activePetIds, petId)
	return { ok = true }
end

local function runAction(player: Player, data: Ledger, kind: string, id: string, args: { any }): any
	if kind == "Equip" or kind == "Unequip" then
		return setFollower(data, args[1], kind == "Equip")
	end
	if kind == "Place" then
		return PetFusion.placePet(data, id, args[1], args[2])
	elseif kind == "Remove" then
		return PetFusion.removePet(data, id, args[1])
	elseif kind == "Fuse" then
		return PetFusion.fusePets(data, id, args[1], args[2], args[3])
	elseif kind == "LevelUp" then
		return PetFusion.levelUpPet(data, id, args[1])
	elseif kind == "RerollTrait" then
		return PetFusion.rerollTrait(data, id, args[1], rng:NextNumber())
	elseif kind == "Hatch" then
		return hatch(player, data, id, args[1], args[2])
	end
	return { ok = false, reason = "UnknownAction" }
end

local function validArgs(args: unknown): boolean
	if type(args) ~= "table" or #(args :: any) > 3 then
		return false
	end
	for _, value in args :: any do
		local t = type(value)
		if not ((t == "string" and #value <= 64) or (t == "number" and value == value)) then
			return false
		end
	end
	return true
end

local function onPetAction(player: Player, kind: unknown, requestId: unknown, args: unknown): any
	local data = DataService.get(player)
	if
		not data
		or type(kind) ~= "string"
		or type(requestId) ~= "string"
		or #requestId == 0
		or #requestId > 64
		or not validArgs(args)
	then
		return { ok = false, reason = "InvalidRequest" }
	end
	local result = runAction(player, data, kind, `pet:{player.UserId}:{requestId}`, args :: { any })
	player:SetAttribute("Coins", data.coins)
	player:SetAttribute("BossGems", data.bossGems)
	broadcast(player, data)
	return { ok = result.ok, reason = result.reason, replayed = result.replayed }
end

-- Lifecycle ----------------------------------------------------------------------------------------

-- EconomyService.onLoaded hook: credit the offline interval once, then show the pads.
function PetIncomeService.onProfileLoaded(player: Player, data: Ledger)
	local earned = PetIncome.accrueOffline(data, os.time())
	if earned > 0 then
		player:SetAttribute("OfflineCoinsEarned", math.floor(earned))
	end
	broadcast(player, data)
end

local function onTick()
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		if data then
			PetIncome.accrue(data, TICK_SECONDS)
			broadcast(player, data)
		end
	end
end

function PetIncomeService.start(folder: Folder)
	remotes = folder
	Remotes.getEvent(folder, Remotes.Names.CollectPad).OnServerEvent:Connect(onCollectPad)
	local action = folder:FindFirstChild(Remotes.Names.PetAction)
	if action and action:IsA("RemoteFunction") then
		action.OnServerInvoke = onPetAction
	end
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= TICK_SECONDS then
			acc -= TICK_SECONDS
			onTick()
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		hatching[player] = nil
	end)
end

return PetIncomeService
