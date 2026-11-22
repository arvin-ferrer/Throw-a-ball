--!strict
--[[
	AudioCatalog.luau
	Client-side SFX & volume control helper with comfortable balanced default gain,
	1-tap Mute/Low/On toggle, pitch-escalating Cash Pad chimes, and automatic cleanup.
]]

local SoundService = game:GetService("SoundService")

local AudioCatalog = {}

local SOUND_IDS: { [string]: string } = {
	Throw = "rbxassetid://12222200",
	TargetHit = "rbxassetid://12221967",
	GoldCombo = "rbxassetid://12222140",
	CoinSweep = "rbxassetid://12221976",
	BossHit = "rbxassetid://12222084",
	BossWarning = "rbxassetid://12222030",
	HatchTick = "rbxassetid://12221967",
	HatchReveal = "rbxassetid://12222253",
	ClaimTick = "rbxassetid://12221976",
	Victory = "rbxassetid://12222253",
	Dash = "rbxassetid://9119713951",
	DashBurst = "rbxassetid://9113677992",
}

-- Comfortable default master scale so classic Roblox SFX & fanfares never blast player ears
local masterVolumeScale = 0.22
local isMuted = false
local musicBaseVolumes: { [Sound]: number } = {}

local function applyToSound(desc: Instance)
	local mult = if isMuted then 0 else masterVolumeScale
	if desc:IsA("Sound") and desc.Looped then
		if musicBaseVolumes[desc] == nil then
			musicBaseVolumes[desc] = math.min(desc.Volume, 0.5)
		end
		desc.Volume = (musicBaseVolumes[desc] or 0.35) * mult
	end
end

local function applyToExistingMusic()
	for _, container in ipairs({ SoundService, workspace }) do
		for _, desc in ipairs(container:GetDescendants()) do
			applyToSound(desc)
		end
	end
end

SoundService.DescendantAdded:Connect(applyToSound)
workspace.DescendantAdded:Connect(applyToSound)

function AudioCatalog.setMasterVolume(scale: number)
	masterVolumeScale = math.clamp(scale, 0, 1)
	isMuted = masterVolumeScale <= 0.001
	applyToExistingMusic()
end

function AudioCatalog.setMuted(muted: boolean)
	isMuted = muted
	applyToExistingMusic()
end

function AudioCatalog.isMuted(): boolean
	return isMuted
end

function AudioCatalog.cycleAudioMode(): string
	if isMuted then
		isMuted = false
		masterVolumeScale = 0.22
		applyToExistingMusic()
		return "AUDIO: LOW"
	elseif masterVolumeScale < 0.35 then
		masterVolumeScale = 0.45
		applyToExistingMusic()
		return "AUDIO: MED"
	else
		isMuted = true
		applyToExistingMusic()
		return "AUDIO: OFF"
	end
end

function AudioCatalog.play(key: string, pitch: number?, volume: number?, parentOverride: Instance?)
	if isMuted or masterVolumeScale <= 0.001 then
		return
	end
	local assetId = SOUND_IDS[key]
	if not assetId then
		return
	end
	local baseVol = math.clamp(volume or 0.4, 0, 1.0)
	local finalVol = math.clamp(baseVol * masterVolumeScale, 0, 0.6)
	if finalVol <= 0.005 then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = assetId
	s.PlaybackSpeed = math.clamp(pitch or 1.0, 0.5, 2.2)
	s.Volume = finalVol
	s.RollOffMaxDistance = 85
	s.Parent = parentOverride or SoundService
	s:Play()
	task.delay(2.5, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

function AudioCatalog.playCashSweep(comboStep: number)
	local pitch = 1.0 + math.min(comboStep, 12) * 0.06
	AudioCatalog.play("CoinSweep", pitch, 0.42)
end

function AudioCatalog.playJettDash(parentOverride: Instance?)
	if isMuted or masterVolumeScale <= 0.001 then
		return
	end
	local targetParent = parentOverride or SoundService
	local scale = math.clamp(masterVolumeScale, 0, 1)

	-- Layer 1: Crisp explosive wind snap transient
	local burst = Instance.new("Sound")
	burst.SoundId = SOUND_IDS.DashBurst
	burst.PlaybackSpeed = 1.42 + (math.random() - 0.5) * 0.08
	burst.Volume = math.clamp(0.68 * scale, 0, 0.55)
	burst.RollOffMaxDistance = 95
	burst.Parent = targetParent

	-- Layer 2: Airy Tailwind high-shimmer wind whoosh tail
	local tail = Instance.new("Sound")
	tail.SoundId = SOUND_IDS.Dash
	tail.PlaybackSpeed = 1.22 + (math.random() - 0.5) * 0.06
	tail.Volume = math.clamp(0.75 * scale, 0, 0.6)
	tail.RollOffMaxDistance = 95
	local eq = Instance.new("EqualizerSoundEffect")
	eq.HighGain = 5
	eq.MidGain = 1.5
	eq.LowGain = -4
	eq.Parent = tail
	tail.Parent = targetParent

	burst:Play()
	tail:Play()
	task.delay(1.3, function()
		if burst.Parent then
			burst:Destroy()
		end
		if tail.Parent then
			tail:Destroy()
		end
	end)
end

applyToExistingMusic()

return AudioCatalog
