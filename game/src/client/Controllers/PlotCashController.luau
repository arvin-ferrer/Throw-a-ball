--!strict
--[[
	PlotCashController (Issue #11): Cash Pads on your own plot. Glowing counters interpolate
	stored Coins + Coins/s between server updates; walking onto a pad sweeps it (the server
	re-checks distance and ownership) with a rising chime and coin burst; eggs get a Hatch
	prompt. Sends intents only (CollectPad, PetAction).
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CashPadView = require(Shared.Utils.CashPadView)
local HatchVFXController = require(script.Parent.HatchVFXController)

type Pad = {
	slot: number,
	model: Model,
	part: BasePart,
	label: TextLabel,
	burst: ParticleEmitter,
	shown: number,
	stored: number,
	rate: number,
	updatedAt: number,
	lastSweep: number,
}

local SWEEP_RANGE = 7 -- studs; the server allows 14, so lag never makes a sweep fail
local SWEEP_COOLDOWN = 1
local STREAK_WINDOW = 2.5
local PAD_CAP = 1_000_000

local PlotCashController = { Name = "PlotCashController", Priority = 40 }

local player = Players.LocalPlayer
local pads: { [number]: Pad } = {}
local remotes: Instance? = nil
local streak, lastChime = 0, 0
local chime: Sound? = nil

local function padPart(model: Model): BasePart?
	return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
end

local function makeBillboard(part: BasePart): TextLabel
	local board = Instance.new("BillboardGui")
	board.Name, board.Size, board.StudsOffset =
		"CashPadBoard", UDim2.fromOffset(140, 56), Vector3.new(0, 4, 0)
	board.MaxDistance, board.AlwaysOnTop = 80, false
	local label = Instance.new("TextLabel")
	label.Size, label.BackgroundTransparency = UDim2.fromScale(1, 1), 1
	label.TextScaled, label.Font, label.TextColor3 =
		true, Enum.Font.GothamBlack, Color3.fromRGB(255, 220, 90)
	label.TextStrokeTransparency = 0.2
	label.Parent = board
	board.Parent = part
	return label
end

local function makeBurst(part: BasePart): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled, emitter.Rate, emitter.Lifetime = false, 0, NumberRange.new(0.5, 0.9)
	emitter.Speed, emitter.SpreadAngle = NumberRange.new(10, 18), Vector2.new(40, 40)
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 210, 60))
	emitter.LightEmission, emitter.Size = 0.8, NumberSequence.new(0.6, 0)
	emitter.Acceleration = Vector3.new(0, -35, 0)
	emitter.Parent = part
	return emitter
end

local function fire(name: string, ...: any)
	local remote = remotes and remotes:FindFirstChild(name)
	if remote and remote:IsA("RemoteEvent") then
		remote:FireServer(...)
	end
end

local function playChime()
	local now = os.clock()
	streak = if now - lastChime <= STREAK_WINDOW then streak + 1 else 1
	lastChime = now
	if chime then
		chime.PlaybackSpeed = CashPadView.chimePitch(streak)
		chime:Play()
	end
end

local function hatchPrompt(pad: Pad)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name, prompt.ActionText, prompt.ObjectText = "HatchPrompt", "Hatch", "Egg"
	prompt.HoldDuration, prompt.MaxActivationDistance, prompt.Enabled = 0, 10, false
	prompt.Triggered:Connect(function()
		local eggId = pad.model:GetAttribute("EggId")
		local action = remotes and remotes:FindFirstChild("PetAction")
		if type(eggId) == "string" and eggId ~= "" and action and action:IsA("RemoteFunction") then
			prompt.Enabled = false
			HatchVFXController.startWobble(pad.slot, pad.part)
			task.spawn(function()
				action:InvokeServer(
					"Hatch",
					HttpService:GenerateGUID(false),
					{ pad.slot, eggId } :: { any }
				)
			end)
		end
	end)
	prompt.Parent = pad.part
	return prompt
end

local function bindPlot(plot: Instance)
	local folder = plot:FindFirstChild("Pedestals")
	local children: { Instance } = if folder then folder:GetChildren() else {}
	for _, child in children do
		local slot = child:GetAttribute("PedestalIndex")
		local part = if child:IsA("Model") then padPart(child) else nil
		if type(slot) == "number" and part then
			local pad: Pad = {
				slot = slot,
				model = child :: Model,
				part = part,
				label = makeBillboard(part),
				burst = makeBurst(part),
				shown = 0,
				stored = 0,
				rate = 0,
				updatedAt = os.clock(),
				lastSweep = 0,
			}
			local prompt = hatchPrompt(pad)
			local function refresh()
				local egg = child:GetAttribute("EggId")
				local pet = child:GetAttribute("PetId")
				prompt.Enabled = type(egg) == "string" and egg ~= "" and (pet == nil or pet == "")
			end
			child:GetAttributeChangedSignal("EggId"):Connect(refresh)
			child:GetAttributeChangedSignal("PetId"):Connect(refresh)
			refresh()
			pads[slot] = pad
		end
	end
end

local function onPadsUpdated(payload: any)
	if type(payload) ~= "table" or type(payload.pads) ~= "table" then
		return
	end
	for _, info in payload.pads do
		local pad = if type(info) == "table" then pads[info.pedestalId] else nil
		if pad then
			pad.stored = tonumber(info.storedCoins) or 0
			pad.rate = tonumber(info.coinsPerSec) or 0
			pad.updatedAt = os.clock()
		end
	end
end

local function tryAutoSweep(pad: Pad, root: BasePart, now: number)
	local close = (root.Position - pad.part.Position).Magnitude <= SWEEP_RANGE
	if close and pad.shown >= 1 and now - pad.lastSweep >= SWEEP_COOLDOWN then
		pad.lastSweep = now
		fire("CollectPad", pad.slot)
		pad.burst:Emit(math.clamp(math.floor(pad.shown / 25), 6, 30))
		playChime()
		pad.stored, pad.updatedAt = 0, now -- optimistic; the next server update corrects it
	end
end

local function onFrame(dt: number)
	local now = os.clock()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	for _, pad in pads do
		if pad.model:GetAttribute("Locked") == true then
			pad.label.Text = "🔒 Locked"
		else
			local target = CashPadView.predict(pad.stored, pad.rate, now - pad.updatedAt, PAD_CAP)
			pad.shown = CashPadView.ease(pad.shown, target, dt)
			pad.label.Text = CashPadView.label(pad.shown, pad.rate)
			if root and root:IsA("BasePart") then
				tryAutoSweep(pad, root, now)
			end
		end
	end
end

function PlotCashController.Init(_self: any, _ctx: any)
	local sound = Instance.new("Sound")
	sound.Name, sound.SoundId, sound.Volume =
		"SweepChime", "rbxasset://sounds/electronicpingshort.wav", 0.5
	sound.Parent = workspace.CurrentCamera or workspace
	chime = sound
end

function PlotCashController.Start(_self: any, _ctx: any)
	remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
	while player:GetAttribute("PlotId") == nil do
		player:GetAttributeChangedSignal("PlotId"):Wait()
	end
	local map = workspace:WaitForChild("BallBrawl_Map_v2", 30)
	local plots = map and map:FindFirstChild("Hub") and map.Hub:FindFirstChild("Plots")
	local allPlots: { Instance } = if plots then plots:GetChildren() else {}
	for _, plot in allPlots do
		if plot:GetAttribute("PlotId") == player:GetAttribute("PlotId") then
			bindPlot(plot)
		end
	end
	local update = remotes and remotes:FindFirstChild("CashPadUpdated")
	if update and update:IsA("RemoteEvent") then
		update.OnClientEvent:Connect(onPadsUpdated)
	end
	RunService.Heartbeat:Connect(onFrame)
end

return PlotCashController
