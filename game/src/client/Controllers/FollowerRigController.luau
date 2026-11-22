--!strict
--[[
	FollowerRigController (Issue #11): every player's 1-3 equipped followers float beside them
	(server publishes the species list in the player's "Followers" attribute). Followers are
	cosmetic: anchored, no collision, no query, so they never block a ball throw.
	Uses ReplicatedStorage.Assets.Pets.<species> when the team's model exists, else a placeholder.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FollowerRigController = { Name = "FollowerRigController", Priority = 60 }

local OFFSETS =
	{ Vector3.new(-3.5, 1.5, 2.5), Vector3.new(3.5, 1.5, 2.5), Vector3.new(0, 3.2, 3.5) }
local FOLLOW_SHARPNESS = 8

local rigs: { [Player]: { species: string, models: { Model } } } = {}

local function makeModel(species: string): Model
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local pets = assets and assets:FindFirstChild("Pets")
	local template = pets and pets:FindFirstChild(species)
	local model: Model
	if template and template:IsA("Model") then
		model = template:Clone()
	else
		model = Instance.new("Model")
		local orb = Instance.new("Part")
		orb.Shape, orb.Size, orb.Material =
			Enum.PartType.Ball, Vector3.one * 1.6, Enum.Material.Neon
		orb.Color = Color3.fromRGB(120, 230, 160)
		orb.Parent = model
		model.PrimaryPart = orb
	end
	model.Name = `Follower_{species}`
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
		end
	end
	model.Parent = workspace
	return model
end

local function rebuild(player: Player)
	local attr = player:GetAttribute("Followers")
	local species = if type(attr) == "string" then attr else ""
	local rig = rigs[player]
	if rig and rig.species == species then
		return
	end
	if rig then
		for _, model in rig.models do
			model:Destroy()
		end
	end
	local models = {}
	for name in species:gmatch("[^,]+") do
		if #models < #OFFSETS then
			table.insert(models, makeModel(name))
		end
	end
	rigs[player] = { species = species, models = models }
end

local function onFrame(dt: number)
	local t = os.clock()
	local alpha = 1 - math.exp(-FOLLOW_SHARPNESS * dt)
	for player, rig in rigs do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			for i, model in rig.models do
				local bob = Vector3.new(0, math.sin(t * 2 + i) * 0.35, 0)
				local goal = root.CFrame * CFrame.new(OFFSETS[i] + bob)
				model:PivotTo(model:GetPivot():Lerp(goal, alpha))
			end
		end
	end
end

local function track(player: Player)
	player:GetAttributeChangedSignal("Followers"):Connect(function()
		rebuild(player)
	end)
	rebuild(player)
end

function FollowerRigController.Init(_self: any, _ctx: any) end

function FollowerRigController.Start(_self: any, _ctx: any)
	Players.PlayerAdded:Connect(track)
	for _, player in Players:GetPlayers() do
		track(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local rig = rigs[player]
		if rig then
			for _, model in rig.models do
				model:Destroy()
			end
		end
		rigs[player] = nil
	end)
	RunService.RenderStepped:Connect(onFrame)
end

return FollowerRigController
