--!strict
--[[
	AudioCatalog.luau
	Client-side SFX helper with pitch-escalating Cash Pad chimes, combat feedback,
	hatch wobble/reveal fanfare, and automatic instance cleanup.
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
	Dash = "rbxassetid://12222200",
}

function AudioCatalog.play(key: string, pitch: number?, volume: number?, parentOverride: Instance?)
	local assetId = SOUND_IDS[key]
	if not assetId then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = assetId
	s.PlaybackSpeed = math.clamp(pitch or 1.0, 0.5, 2.2)
	s.Volume = math.clamp(volume or 0.45, 0, 1.5)
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
	AudioCatalog.play("CoinSweep", pitch, 0.55)
end

return AudioCatalog
