--!strict
--[[
	PlotCashController.luau
	Renders glowing Cash Pad Coin counters on the local player's plot, plays pitch-escalating
	chime & Coin burst VFX when sweeping Cash Pads, and runs Magnet Coin Collect vacuuming.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MathUtil = require(Shared.Utils.MathUtil)
local AudioCatalog = require(Shared.Utils.AudioCatalog)
local Remotes = require(Shared.Net.Remotes)

local PlotCashController = {}

local localPlayer = Players.LocalPlayer
local sweepCombo = 0
local lastSweepAt = 0
local lastStoredByPad: { [BasePart]: number } = {}

local function ensurePadBillboard(pad: BasePart): TextLabel
	local bb = pad:FindFirstChild("CashCounter")
	if bb and bb:IsA("BillboardGui") then
		local lbl = bb:FindFirstChild("Amount")
		if lbl and lbl:IsA("TextLabel") then
			return lbl
		end
	end
	local created = Instance.new("BillboardGui")
	created.Name = "CashCounter"
	created.Adornee = pad
	created.Size = UDim2.fromOffset(130, 36)
	created.StudsOffset = Vector3.new(0, 2.2, 0)
	created.MaxDistance = 75
	created.Parent = pad

	local lbl = Instance.new("TextLabel")
	lbl.Name = "Amount"
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextScaled = true
	lbl.TextColor3 = Color3.fromRGB(250, 204, 21)
	lbl.TextStrokeTransparency = 0.25
	lbl.Text = ""
	lbl.Parent = created
	return lbl
end

local function emitSweepBurst(pad: BasePart)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(8, 16)
	emitter.Lifetime = NumberRange.new(0.35, 0.65)
	emitter.Size = NumberSequence.new(0.65, 0)
	emitter.Color = ColorSequence.new(Color3.fromRGB(250, 204, 21), Color3.fromRGB(74, 222, 128))
	emitter.LightEmission = 1
	emitter.Parent = pad
	emitter:Emit(14)
	task.delay(0.8, function()
		emitter:Destroy()
	end)
end

local function bindCashPad(pad: BasePart)
	local lbl = ensurePadBillboard(pad)
	local function update()
		local stored = tonumber(pad:GetAttribute("StoredCoins")) or 0
		local prev = lastStoredByPad[pad] or 0
		lastStoredByPad[pad] = stored
		if stored > 0 then
			lbl.Text = `+{MathUtil.formatNumber(stored)} Coins`
		else
			lbl.Text = ""
		end
		-- Detect sweep drop -> play pitch-escalating chime + Coin burst VFX!
		if prev > 0 and stored == 0 then
			local now = os.clock()
			if now - lastSweepAt < 3.0 then
				sweepCombo += 1
			else
				sweepCombo = 0
			end
			lastSweepAt = now
			AudioCatalog.playCashSweep(sweepCombo)
			emitSweepBurst(pad)
		end
	end
	pad:GetAttributeChangedSignal("StoredCoins"):Connect(update)
	update()
end

function PlotCashController.start()
	for _, pad in ipairs(CollectionService:GetTagged("CashPad")) do
		if pad:IsA("BasePart") then
			bindCashPad(pad)
		end
	end
	CollectionService:GetInstanceAddedSignal("CashPad"):Connect(function(inst: Instance)
		if inst:IsA("BasePart") then
			bindCashPad(inst)
		end
	end)

	-- Magnet Coin Collect Pass auto-sweep while on Hub
	task.spawn(function()
		local remotes = Remotes.waitClient()
		while true do
			task.wait(1.5)
			if
				localPlayer:GetAttribute("Pass_MagnetCollect") == true
				and localPlayer:GetAttribute("Zone") == "Hub"
			then
				remotes.CollectCashPad:FireServer("AllMagnet")
			end
		end
	end)
end

return PlotCashController
