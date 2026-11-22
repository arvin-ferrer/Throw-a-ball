--!strict
--[[
	HatchVFXController.luau
	3.0-second Pedestal Hatch wobble with Hub-wide skyward rarity light beam & mutation burst,
	floating Active Combat Follower rigs (1-3), and overhead Power Rating / Ascension Crest badges.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetConfigs = require(Shared.Configs.PetConfigs)
local MathUtil = require(Shared.Utils.MathUtil)
local ProceduralModels = require(Shared.Utils.ProceduralModels)
local AudioCatalog = require(Shared.Utils.AudioCatalog)
local Remotes = require(Shared.Net.Remotes)

local HatchVFXController = {}

local localPlayer = Players.LocalPlayer
local followerFolder: Folder? = nil
local activeFollowerModels: { Model } = {}
local lastFollowerKey = ""

local function rgb(arr: { number }): Color3
	return Color3.fromRGB(arr[1] or 255, arr[2] or 255, arr[3] or 255)
end

local function onHatchReveal(data: any)
	if type(data) ~= "table" or typeof(data.position) ~= "Vector3" then
		return
	end
	local pos = data.position :: Vector3
	local rarity = tostring(data.rarity or "Common")
	local rarityCol = rgb(PetConfigs.RARITY_COLORS[rarity] or { 74, 222, 128 })
	local eggId = tostring(data.eggId or "StarterEgg")
	local eggVis = ProceduralModels.createEggVisual(
		eggId,
		data.mutationKey == "Overcharged" or data.mutationKey == "VoidTouched"
	)
	local baseCF = CFrame.new(pos + Vector3.new(0, 1.5, 0))
	eggVis:PivotTo(baseCF)
	eggVis.Parent = workspace

	-- Hub-wide skyward rarity light beam visible across the Plaza
	local beamPart = Instance.new("Part")
	beamPart.Name = "HatchRarityBeam"
	beamPart.Anchored = true
	beamPart.CanCollide = false
	beamPart.CanQuery = false
	beamPart.Material = Enum.Material.Neon
	beamPart.Color = rarityCol
	beamPart.Transparency = 0.35
	beamPart.Shape = Enum.PartType.Cylinder
	beamPart.Size = Vector3.new(180, 4.5, 4.5)
	beamPart.CFrame = CFrame.new(pos + Vector3.new(0, 90, 0)) * CFrame.Angles(0, 0, math.rad(90))
	beamPart.Parent = workspace

	-- 3.0-second escalating wobble sequence
	task.spawn(function()
		local startTime = os.clock()
		local nextTick = 0
		while os.clock() - startTime < 2.85 do
			local elapsed = os.clock() - startTime
			local progress = elapsed / 2.85
			local freq = 8 + progress * 24
			local angle = math.sin(elapsed * freq) * math.rad(12 + progress * 22)
			local hop = math.abs(math.sin(elapsed * freq)) * (0.4 + progress * 1.4)
			if eggVis.Parent then
				eggVis:PivotTo(
					baseCF * CFrame.new(0, hop, 0) * CFrame.Angles(0, elapsed * 2.5, angle)
				)
			end
			if elapsed >= nextTick then
				nextTick = elapsed + math.max(0.14, 0.45 - progress * 0.32)
				AudioCatalog.play("HatchTick", 0.9 + progress * 0.6, 0.45)
			end
			RunService.Heartbeat:Wait()
		end

		-- Reveal burst!
		AudioCatalog.play("HatchReveal", 1.0, 0.7)
		local burst = Instance.new("Part")
		burst.Anchored = true
		burst.CanCollide = false
		burst.CanQuery = false
		burst.Transparency = 1
		burst.Size = Vector3.new(1, 1, 1)
		burst.CFrame = baseCF
		burst.Parent = workspace

		local emitter = Instance.new("ParticleEmitter")
		emitter.Rate = 0
		emitter.Speed = NumberRange.new(12, 26)
		emitter.Lifetime = NumberRange.new(0.5, 1.0)
		emitter.Size = NumberSequence.new(1.1, 0)
		emitter.Color = ColorSequence.new(rarityCol, Color3.fromRGB(255, 255, 255))
		emitter.LightEmission = 1
		emitter.Parent = burst
		emitter:Emit(28)

		TweenService
			:Create(beamPart, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 1,
				Size = Vector3.new(180, 12, 12),
			})
			:Play()
		eggVis:Destroy()
		task.delay(1.1, function()
			beamPart:Destroy()
			burst:Destroy()
		end)
	end)
end

function HatchVFXController.rebuildFollowers(profile: any)
	local uids: { string } = profile.activeFollowerUids or {}
	local petsByUid: { [string]: any } = {}
	for _, pet in ipairs(profile.pets or {}) do
		petsByUid[pet.uid] = pet
	end

	local keyParts: { string } = {}
	for _, uid in ipairs(uids) do
		local p = petsByUid[uid]
		if p then
			table.insert(keyParts, `{uid}:{p.speciesId}:{p.mutationKey}:{p.starTier}`)
		end
	end
	local nextKey = table.concat(keyParts, "|")
	if nextKey == lastFollowerKey then
		return
	end
	lastFollowerKey = nextKey

	for _, m in ipairs(activeFollowerModels) do
		m:Destroy()
	end
	table.clear(activeFollowerModels)

	if not followerFolder then
		local f = Instance.new("Folder")
		f.Name = "LocalActiveFollowers"
		f.Parent = workspace
		followerFolder = f
	end
	for _, uid in ipairs(uids) do
		local pet = petsByUid[uid]
		if pet then
			local rig = ProceduralModels.createPetModel(
				pet.speciesId,
				pet.mutationKey,
				pet.starTier,
				"ACTIVE PERK"
			)
			rig:ScaleTo(0.68)
			rig.Parent = followerFolder
			table.insert(activeFollowerModels, rig)
		end
	end
end

local function attachPlayerBadge(player: Player, char: Model)
	local head = char:WaitForChild("Head", 10)
	if not head or not head:IsA("BasePart") then
		return
	end
	local existing = head:FindFirstChild("PowerAscensionBadge")
	if existing then
		existing:Destroy()
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "PowerAscensionBadge"
	bb.Adornee = head
	bb.Size = UDim2.fromOffset(180, 44)
	bb.StudsOffset = Vector3.new(0, 2.8, 0)
	bb.MaxDistance = 120
	bb.Parent = head

	local lbl = Instance.new("TextLabel")
	lbl.Name = "Text"
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextScaled = true
	lbl.TextStrokeTransparency = 0.2
	lbl.AutoLocalize = false
	lbl.Parent = bb

	local function refresh()
		local pwr = tonumber(player:GetAttribute("PowerRating")) or 10
		local asc = tonumber(player:GetAttribute("AscensionRank")) or 0
		local crest = if asc > 0 then `★ASC {asc} • ` else ""
		lbl.Text = `{crest}PWR {MathUtil.formatNumber(pwr)}`
		lbl.TextColor3 = if asc >= 3
			then Color3.fromRGB(255, 72, 196)
			elseif asc >= 1 then Color3.fromRGB(250, 204, 21)
			else Color3.fromRGB(125, 249, 255)
	end
	player:GetAttributeChangedSignal("PowerRating"):Connect(refresh)
	player:GetAttributeChangedSignal("AscensionRank"):Connect(refresh)
	refresh()
end

local function watchPlayerBadges(player: Player)
	if player.Character then
		task.spawn(attachPlayerBadge, player, player.Character)
	end
	player.CharacterAdded:Connect(function(char: Model)
		attachPlayerBadge(player, char)
	end)
end

function HatchVFXController.start()
	Remotes.waitClient().HatchReveal.OnClientEvent:Connect(onHatchReveal)

	for _, plr in ipairs(Players:GetPlayers()) do
		watchPlayerBadges(plr)
	end
	Players.PlayerAdded:Connect(watchPlayerBadges)

	-- Spring-damped smooth hovering & banking float animation for 1-3 Active Combat Followers
	RunService.RenderStepped:Connect(function(dt: number)
		if #activeFollowerModels == 0 then
			return
		end
		local char = localPlayer.Character
		local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
		if not hrp or not hrp:IsA("BasePart") then
			return
		end
		local t = os.clock()
		local speed = hrp.AssemblyLinearVelocity.Magnitude
		local moving = speed > 1.5
		local followAlpha = 1 - math.exp(-7.5 * math.min(dt, 0.1))
		for i, rig in ipairs(activeFollowerModels) do
			rig:SetAttribute("IsMoving", moving)
			local angle = math.rad(135 + (i - 1) * 45)
			local bob = math.sin(t * 3.4 + i * 1.4) * 0.55
			local offset = Vector3.new(math.cos(angle) * 4.8, 2.2 + bob, math.sin(angle) * 4.8)
			local desiredPos = hrp.CFrame:PointToWorldSpace(offset)
			local curCF = rig:GetPivot()
			local smoothedPos = curCF.Position:Lerp(desiredPos, followAlpha)
			local moveVec = desiredPos - curCF.Position
			local bank = math.clamp(moveVec.X * 0.04, -0.25, 0.25)
			local lookPos = hrp.Position + hrp.CFrame.LookVector * 14
			local desiredRot = CFrame.lookAt(
				smoothedPos,
				Vector3.new(lookPos.X, smoothedPos.Y + bob * 0.15, lookPos.Z)
			) * CFrame.Angles(0, 0, bank)
			rig:PivotTo(curCF:Lerp(desiredRot, followAlpha))
		end
	end)
end

return HatchVFXController
