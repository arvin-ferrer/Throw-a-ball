--!strict
--[[
	HatchVFXController (Issue #11): the 3.0s hatch reveal. Wobbles a glowing egg on the pedestal
	while the server rolls, then a rarity-coloured light beam (visible across the Hub), a
	mutation burst and a name toast when HatchReveal arrives. Purely cosmetic: the server
	decides the pet.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CashPadView = require(Shared.Utils.CashPadView)

local HatchVFXController = { Name = "HatchVFXController", Priority = 45 }

local pending: { [number]: { egg: BasePart, pedestal: BasePart } } = {}

local function toColor(rgb: CashPadView.RGB): Color3
	return Color3.new(rgb.r, rgb.g, rgb.b)
end

local function effectPart(name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame, p.Color = name, size, cf, color
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.Material = Enum.Material.Neon
	p.Parent = workspace
	return p
end

-- Called by PlotCashController the moment the player presses Hatch.
function HatchVFXController.startWobble(slot: number, pedestal: BasePart)
	local top = pedestal.CFrame + Vector3.new(0, pedestal.Size.Y / 2 + 2.2, 0)
	local egg =
		effectPart("HatchEgg", Vector3.new(2.6, 3.2, 2.6), top, Color3.fromRGB(245, 240, 220))
	egg.Shape = Enum.PartType.Ball
	pending[slot] = { egg = egg, pedestal = pedestal }
	local seconds = CashPadView.revealSeconds()
	for i = 1, 6 do -- faster, wider shakes as the reveal nears
		local angle = math.rad(6 + i * 3) * (if i % 2 == 0 then 1 else -1)
		task.delay(seconds * (i - 1) / 6, function()
			if egg.Parent then
				TweenService:Create(
					egg,
					TweenInfo.new(
						seconds / 12,
						Enum.EasingStyle.Sine,
						Enum.EasingDirection.InOut,
						1,
						true
					),
					{ CFrame = top * CFrame.Angles(0, 0, angle) }
				):Play()
			end
		end)
	end
	task.delay(seconds + 4, function()
		egg:Destroy() -- safety net if the reveal never arrives
		pending[slot] = nil
	end)
end

local function toast(text: string, color: Color3)
	local gui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not gui then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name, screen.ResetOnSpawn = "HatchToast", false
	local label = Instance.new("TextLabel")
	label.Size, label.Position, label.AnchorPoint =
		UDim2.fromScale(0.5, 0.08), UDim2.fromScale(0.5, 0.3), Vector2.new(0.5, 0.5)
	label.BackgroundTransparency, label.TextScaled, label.Font = 1, true, Enum.Font.GothamBlack
	label.Text, label.TextColor3, label.TextStrokeTransparency = text, color, 0
	label.Parent = screen
	screen.Parent = gui
	task.delay(2.5, function()
		screen:Destroy()
	end)
end

local function reveal(payload: any)
	if type(payload) ~= "table" or type(payload.slot) ~= "number" then
		return
	end
	local entry = pending[payload.slot]
	pending[payload.slot] = nil
	local pet = payload.pet
	local color = toColor(CashPadView.beamColor(if pet then pet.mutation else "Normal"))
	local origin = if entry then entry.egg.CFrame else nil
	if entry then
		entry.egg:Destroy()
	end
	if origin then
		local beam = effectPart(
			"RarityBeam",
			Vector3.new(160, 3, 3),
			CFrame.new(origin.Position + Vector3.new(0, 80, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			color
		)
		beam.Shape, beam.Transparency = Enum.PartType.Cylinder, 0.35
		local burst = effectPart("MutationBurst", Vector3.one, origin, color)
		burst.Shape = Enum.PartType.Ball
		TweenService
			:Create(burst, TweenInfo.new(0.6), { Size = Vector3.one * 14, Transparency = 1 })
			:Play()
		TweenService:Create(beam, TweenInfo.new(1.8), { Transparency = 1 }):Play()
		task.delay(1.9, function()
			beam:Destroy()
			burst:Destroy()
		end)
	end
	if pet then
		toast(
			`{pet.petId:gsub("(%l)(%u)", "%1 %2")}{if pet.mutation ~= "Normal"
				then " — " .. pet.mutation
				else ""}!`,
			color
		)
	end
end

function HatchVFXController.Init(_self: any, _ctx: any) end

function HatchVFXController.Start(_self: any, _ctx: any)
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
	local event = remotes and remotes:WaitForChild("HatchReveal", 30)
	if event and event:IsA("RemoteEvent") then
		event.OnClientEvent:Connect(reveal)
	end
end

return HatchVFXController
