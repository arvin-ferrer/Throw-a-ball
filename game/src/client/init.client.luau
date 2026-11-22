--!strict
--[[
	init.client.luau
	Ball Brawl: Boss Eggs — Client Bootstrapping Composition Root.
	Wires ClientNet (with live-only lock outside Studio), loads Controllers,
	and executes deterministic two-phase lifecycle: Init() then Start().
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyConfigs = require(Shared:WaitForChild("Configs"):WaitForChild("EconomyConfigs"))
local ClientNet = require(Shared:WaitForChild("Utils"):WaitForChild("ClientNet"))
local ClientLifecycle = require(script:WaitForChild("ClientLifecycle"))

local function tryLoadLiveRemotes(): any
	local netFolder = Shared:FindFirstChild("Net")
	if not netFolder then
		return nil
	end
	local remotesModule = netFolder:FindFirstChild("Remotes")
	if not remotesModule or not remotesModule:IsA("ModuleScript") then
		return nil
	end
	local ok, loaded = pcall(require, remotesModule)
	if not ok then
		warn(`[BallBrawlClient] Failed to require Shared.Net.Remotes: {tostring(loaded)}`)
		return nil
	end
	return loaded
end

local function configureClientNet(isStudio: boolean): ClientNet.ClientNetClient
	local net = ClientNet.getDefault()
	local liveRemotes = tryLoadLiveRemotes()
	if liveRemotes ~= nil then
		net:bindLiveRemotes(liveRemotes)
	end
	if isStudio then
		net:setMode("Hybrid")
	else
		net:lockLiveOnly()
	end
	return net
end

local function discoverControllers(): { ClientLifecycle.ClientController }
	local controllers: { ClientLifecycle.ClientController } = {}
	local folder = script:FindFirstChild("Controllers")
	if not folder then
		return controllers
	end
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("ModuleScript") then
			local ok, loaded = pcall(require, child)
			if ok and type(loaded) == "table" then
				local controller = loaded :: ClientLifecycle.ClientController
				if type(controller.Name) ~= "string" or controller.Name == "" then
					controller.Name = child.Name
				end
				table.insert(controllers, controller)
			else
				warn(
					`[BallBrawlClient] Failed to load controller "{child.Name}": {tostring(loaded)}`
				)
			end
		end
	end
	return controllers
end

local function buildStudioPanelMounter(): ((harness: any) -> (() -> ())?)?
	if not RunService:IsStudio() then
		return nil
	end
	local uiFolder = script:FindFirstChild("UI")
	local panelModule = if uiFolder then uiFolder:FindFirstChild("MockHarnessPanel") else nil
	if not panelModule or not panelModule:IsA("ModuleScript") then
		return nil
	end
	local ok, panel = pcall(require, panelModule)
	if not ok or type(panel) ~= "table" then
		return nil
	end
	return function(harness: any): (() -> ())?
		local localPlayer = Players.LocalPlayer
		if not localPlayer then
			return nil
		end
		local playerGui = localPlayer:WaitForChild("PlayerGui", 5)
		if playerGui and playerGui:IsA("PlayerGui") then
			return panel.mount(playerGui, harness)
		end
		return nil
	end
end

local isStudio = RunService:IsStudio()
local net = configureClientNet(isStudio)
local controllers = discoverControllers()

local result = ClientLifecycle.bootstrap(controllers, {
	net = net,
	economyConfigs = EconomyConfigs,
	isStudio = isStudio,
	connectHeartbeat = if isStudio
		then function(callback: (dt: number) -> ())
			return RunService.Heartbeat:Connect(callback)
		end
		else nil,
	mountStudioPanel = buildStudioPanelMounter(),
}, {
	spawnStart = function(fn: () -> ())
		task.spawn(fn)
	end,
	onError = function(controllerName: string, phase: string, err: string)
		warn(`[BallBrawlClient] {phase} error in "{controllerName}": {err}`)
	end,
})

print(
	`[BallBrawlClient] Bootstrapped ({result.initializedCount} init, {result.startedCount} started, mode={net:getMode()})`
)
