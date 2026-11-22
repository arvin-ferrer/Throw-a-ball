--!strict
--[[
	PortalService: Hub portal travel. Touching an enabled Hub portal's PortalField (tag
	BiomePortal, BiomeId attribute, Enabled on the portal model) sends you to that biome's
	ArrivalPad; touching a biome's ReturnPortal.ReturnField sends you back to the Hub spawn.
	The server decides; Touched only tells us who to check.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local COOLDOWN_SECONDS = 2 -- stops ping-ponging when you land next to a portal

local PortalService = {}

local lastTravel: { [Player]: number } = {}

local function pivotOf(inst: Instance?): CFrame?
	if inst and inst:IsA("BasePart") then
		return inst.CFrame
	elseif inst and inst:IsA("Model") then
		return inst:GetPivot()
	end
	return nil
end

local function travel(hit: BasePart, destination: CFrame?)
	local character = hit:FindFirstAncestorOfClass("Model")
	local player = character and Players:GetPlayerFromCharacter(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (player and character and destination and humanoid and humanoid.Health > 0) then
		return
	end
	local now = os.clock()
	if now - (lastTravel[player] or -math.huge) < COOLDOWN_SECONDS then
		return
	end
	lastTravel[player] = now
	character:PivotTo(destination + Vector3.new(0, 5, 0))
end

local function bindHubPortals(biomes: Instance)
	for _, field in CollectionService:GetTagged("BiomePortal") do
		local portal = field.Parent
		local biomeId = field:GetAttribute("BiomeId")
		if field:IsA("BasePart") and portal and type(biomeId) == "string" then
			field.Touched:Connect(function(hit)
				local biome = biomes:FindFirstChild(biomeId)
				local layer = biome and biome:FindFirstChild("PvELayer")
				if portal:GetAttribute("Enabled") == true then
					travel(hit, pivotOf(layer and layer:FindFirstChild("ArrivalPad")))
				end
			end)
		end
	end
end

local function bindReturnPortals(biomes: Instance, hubSpawn: CFrame?)
	for _, biome in biomes:GetChildren() do
		local layer = biome:FindFirstChild("PvELayer")
		local portal = layer and layer:FindFirstChild("ReturnPortal")
		local field = portal and portal:FindFirstChild("ReturnField")
		if field and field:IsA("BasePart") then
			field.Touched:Connect(function(hit)
				travel(hit, hubSpawn)
			end)
		end
	end
end

function PortalService.init(mapRoot: Instance)
	local biomes = mapRoot:FindFirstChild("Biomes")
	local hub = mapRoot:FindFirstChild("Hub")
	local spawns = hub and hub:FindFirstChild("Spawns")
	if not biomes then
		return
	end
	bindHubPortals(biomes)
	bindReturnPortals(biomes, pivotOf(spawns and spawns:FindFirstChild("FallbackSpawn")))
	Players.PlayerRemoving:Connect(function(player)
		lastTravel[player] = nil
	end)
end

return PortalService
