--!strict
--[[
	OnboardingGuideController.luau
	0-5 minute Hub onboarding floor Beam guide driven purely by OnboardingLogic.currentStep(profile).
	Pools a single Beam + 2 Attachments and hides cleanly outside Hub or once completed.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local OnboardingLogic = require(Shared.Utils.OnboardingLogic)

local OnboardingGuideController = {}

local localPlayer = Players.LocalPlayer
local latestProfile: any = nil
local guideBeam: Beam? = nil
local startAttachment: Attachment? = nil
local endAttachment: Attachment? = nil

local function findPlotIdInAncestors(inst: Instance?): number?
	local cur: Instance? = inst
	for _ = 1, 5 do
		if not cur then
			return nil
		end
		local pid = tonumber(cur:GetAttribute("PlotId"))
		if pid then
			return pid
		end
		cur = cur.Parent
	end
	return nil
end

local function destroyStalePooled()
	if guideBeam then
		guideBeam:Destroy()
		guideBeam = nil
	end
	if startAttachment then
		startAttachment:Destroy()
		startAttachment = nil
	end
	if endAttachment then
		endAttachment:Destroy()
		endAttachment = nil
	end
end

local function disableGuide(beam: Beam?, a0: Attachment?, a1: Attachment?)
	if beam then
		beam.Enabled = false
	end
	if a0 then
		a0.Parent = nil
	end
	if a1 then
		a1.Parent = nil
	end
end

local function ensurePooledBeam(): (Beam, Attachment, Attachment)
	if
		guideBeam
		and guideBeam.Parent
		and startAttachment
		and endAttachment
		and guideBeam.Attachment0 == startAttachment
		and guideBeam.Attachment1 == endAttachment
	then
		return guideBeam, startAttachment, endAttachment
	end
	destroyStalePooled()
	local a0 = Instance.new("Attachment")
	a0.Name = "OnboardingGuideStart"
	local a1 = Instance.new("Attachment")
	a1.Name = "OnboardingGuideEnd"
	a1.Position = Vector3.new(0, 1.5, 0)

	local beam = Instance.new("Beam")
	beam.Name = "OnboardingGuideBeam"
	beam.FaceCamera = true
	beam.Width0 = 1.0
	beam.Width1 = 1.8
	beam.Segments = 10
	beam.LightEmission = 0.9
	beam.Color = ColorSequence.new(Color3.fromRGB(250, 204, 21), Color3.fromRGB(74, 222, 128))
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(0.85, 0.1),
		NumberSequenceKeypoint.new(1, 0.35),
	})
	beam.Enabled = false
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Parent = workspace

	guideBeam = beam
	startAttachment = a0
	endAttachment = a1
	return beam, a0, a1
end

local function findPedestalOneTarget(stepId: string, myPlotId: number): BasePart?
	for _, pad in ipairs(CollectionService:GetTagged("CashPad")) do
		if pad:IsA("BasePart") then
			local ped = pad.Parent
			local pedIdx = if ped then tonumber(ped:GetAttribute("PedestalIndex")) else nil
			if pedIdx == 1 and findPlotIdInAncestors(pad) == myPlotId then
				if stepId == "HatchStarter" and ped then
					local base = ped:FindFirstChild("Base")
					if base and base:IsA("BasePart") then
						return base
					end
				end
				return pad
			end
		end
	end
	return nil
end

local function findStepTarget(step: OnboardingLogic.OnboardingStep): BasePart?
	if not step.targetTag then
		return nil
	end
	if step.id == "EnterPortal" then
		for _, portal in ipairs(CollectionService:GetTagged(step.targetTag)) do
			if portal:IsA("BasePart") and portal:GetAttribute("BiomeId") == "EmeraldMeadow" then
				return portal
			end
		end
		return nil
	end
	local myPlotId = tonumber(localPlayer:GetAttribute("PlotId"))
	if not myPlotId then
		return nil
	end
	if step.id == "HatchStarter" or step.id == "CollectCash" then
		return findPedestalOneTarget(step.id, myPlotId)
	elseif step.id == "Train" then
		for _, pad in ipairs(CollectionService:GetTagged(step.targetTag)) do
			if pad:IsA("BasePart") and findPlotIdInAncestors(pad) == myPlotId then
				return pad
			end
		end
	end
	return nil
end

local function refreshGuide()
	local beam, a0, a1 = ensurePooledBeam()
	if type(latestProfile) ~= "table" then
		disableGuide(beam, a0, a1)
		return
	end
	if tostring(localPlayer:GetAttribute("Zone") or "Hub") ~= "Hub" then
		disableGuide(beam, a0, a1)
		return
	end
	local step = OnboardingLogic.currentStep(latestProfile)
	if not step then
		disableGuide(beam, a0, a1)
		return
	end
	local char = localPlayer.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
	local target = findStepTarget(step)
	if
		not hrp
		or not hrp:IsA("BasePart")
		or not hrp:IsDescendantOf(workspace)
		or not target
		or not target:IsDescendantOf(workspace)
	then
		disableGuide(beam, a0, a1)
		return
	end
	a0.Parent = hrp
	a1.Parent = target
	beam.Enabled = true
end

function OnboardingGuideController.updateProfile(profile: any)
	latestProfile = profile
	refreshGuide()
end

function OnboardingGuideController.start()
	ensurePooledBeam()
	localPlayer.CharacterAdded:Connect(function(char: Model)
		char:WaitForChild("HumanoidRootPart", 10)
		refreshGuide()
	end)
	localPlayer.CharacterRemoving:Connect(function()
		disableGuide(guideBeam, startAttachment, endAttachment)
	end)
	localPlayer:GetAttributeChangedSignal("Zone"):Connect(refreshGuide)
	localPlayer:GetAttributeChangedSignal("PlotId"):Connect(refreshGuide)
	for _, tag in ipairs({ "CashPad", "TrainingFiringPad", "BiomePortal" }) do
		CollectionService:GetInstanceAddedSignal(tag):Connect(refreshGuide)
	end
	refreshGuide()
end

return OnboardingGuideController
