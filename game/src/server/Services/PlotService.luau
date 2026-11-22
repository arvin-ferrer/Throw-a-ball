--!strict
--[[
	PlotService (Issue #10): one Hub plot per player (Workspace.BallBrawl_Map_v2.Hub.Plots.
	Plot_01..08, attribute OwnerUserId). Assigns on join, spawns the player there, frees it on
	leave. Other services ask "whose plot is this?" instead of trusting the client.
]]

local Players = game:GetService("Players")

local PlotService = {}

local plotsFolder: Instance? = nil
local plotByUser: { [number]: Instance } = {}

local function spawnCFrame(plot: Instance): CFrame?
	local spawn = plot:FindFirstChild("PlotSpawn", true)
	if spawn and spawn:IsA("BasePart") then
		return spawn.CFrame
	end
	return nil
end

local function sendHome(player: Player, character: Model)
	local plot = plotByUser[player.UserId]
	local cf = plot and spawnCFrame(plot)
	if cf then
		task.defer(function()
			character:PivotTo(cf + Vector3.new(0, 4, 0))
		end)
	end
end

local function assign(player: Player)
	if not plotsFolder then
		return
	end
	local free: Instance? = nil
	for _, plot in plotsFolder:GetChildren() do
		if
			(plot:GetAttribute("OwnerUserId") or 0) == 0 and (free == nil or plot.Name < free.Name)
		then
			free = plot -- lowest-numbered free plot, so assignment is deterministic
		end
	end
	if not free then
		warn(`[PlotService] no free plot for {player.Name}`)
		return
	end
	free:SetAttribute("OwnerUserId", player.UserId)
	plotByUser[player.UserId] = free
	player:SetAttribute("PlotId", free:GetAttribute("PlotId"))
	player.CharacterAdded:Connect(function(character)
		sendHome(player, character)
	end)
	if player.Character then
		sendHome(player, player.Character)
	end
end

local function release(player: Player)
	local plot = plotByUser[player.UserId]
	if plot then
		plot:SetAttribute("OwnerUserId", 0)
		plotByUser[player.UserId] = nil
	end
end

function PlotService.init(mapRoot: Instance)
	local hub = mapRoot:FindFirstChild("Hub")
	plotsFolder = hub and hub:FindFirstChild("Plots")
	if plotsFolder then
		for _, plot in plotsFolder:GetChildren() do
			plot:SetAttribute("OwnerUserId", 0) -- a fresh server owns nothing yet
		end
	end
	Players.PlayerAdded:Connect(assign)
	Players.PlayerRemoving:Connect(release)
	for _, player in Players:GetPlayers() do
		assign(player)
	end
end

function PlotService.getPlot(player: Player): Instance?
	return plotByUser[player.UserId]
end

-- The pedestal for a slot on this player's plot (map contract: Pedestal_NN, attribute PedestalIndex).
function PlotService.getPedestal(player: Player, slot: number): Model?
	local plot = plotByUser[player.UserId]
	local folder = plot and plot:FindFirstChild("Pedestals")
	local children: { Instance } = if folder then folder:GetChildren() else {}
	for _, child in children do
		local n = child:GetAttribute("PedestalIndex") or tonumber(child.Name:match("(%d+)$"))
		if n == slot and child:IsA("Model") then
			return child
		end
	end
	return nil
end

return PlotService
