--!strict
--[[
	ProceduralModels.luau
	Asset-First model & VFX factory:
	1. Clones Studio-authored prefabs from ReplicatedStorage.Assets ({Balls, Targets, Mobs, Bosses, Eggs, Pets, VFX})
	2. Applies Studio Mutation VFX overlays & 3-Star Golden Halo onto HaloAttachment
	3. Falls back cleanly to procedural multi-part geometry when running standalone without Studio Assets
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyConfigs = require(script.Parent.Parent.Configs.EconomyConfigs)
local PetConfigs = require(script.Parent.Parent.Configs.PetConfigs)
local BiomeConfigs = require(script.Parent.Parent.Configs.BiomeConfigs)
local EggConfigs = require(script.Parent.Parent.Configs.EggConfigs)

local ProceduralModels = {}

local function rgb(arr: { number }): Color3
	return Color3.fromRGB(arr[1] or 255, arr[2] or 255, arr[3] or 255)
end

local function findAssetPrefab(category: string, name: string): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = if assets then assets:FindFirstChild(category) else nil
	if not folder then
		return nil
	end
	return folder:FindFirstChild(name)
end

local function makePart(
	parent: Instance,
	name: string,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.Shape = shape or Enum.PartType.Block
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function weldOffset(root: BasePart, part: BasePart, offset: CFrame)
	part.CFrame = root.CFrame * offset
	part.Anchored = false
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
end

local function addOverheadBillboard(
	adornee: BasePart,
	title: string,
	subtitle: string,
	accent: Color3,
	yOffset: number
): BillboardGui
	local existing = adornee:FindFirstChild("InfoBillboard")
	if existing then
		existing:Destroy()
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "InfoBillboard"
	bb.Adornee = adornee
	bb.Size = UDim2.fromOffset(180, 52)
	bb.StudsOffset = Vector3.new(0, yOffset, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 95
	bb.Parent = adornee

	local t1 = Instance.new("TextLabel")
	t1.Name = "Title"
	t1.BackgroundTransparency = 1
	t1.Size = UDim2.fromScale(1, 0.55)
	t1.Font = Enum.Font.FredokaOne
	t1.TextScaled = true
	t1.TextColor3 = Color3.fromRGB(255, 255, 255)
	t1.TextStrokeTransparency = 0.25
	t1.Text = title
	t1.Parent = bb

	local t2 = Instance.new("TextLabel")
	t2.Name = "Subtitle"
	t2.BackgroundTransparency = 1
	t2.Position = UDim2.fromScale(0, 0.55)
	t2.Size = UDim2.fromScale(1, 0.45)
	t2.Font = Enum.Font.GothamBold
	t2.TextScaled = true
	t2.TextColor3 = accent
	t2.TextStrokeTransparency = 0.3
	t2.Text = subtitle
	t2.Parent = bb
	return bb
end

local function addHealthBar(
	adornee: BasePart,
	title: string,
	accent: Color3,
	yOffset: number,
	width: number
)
	local existing = adornee:FindFirstChild("HealthBillboard")
	if existing then
		existing:Destroy()
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "HealthBillboard"
	bb.Adornee = adornee
	bb.Size = UDim2.fromOffset(width, 46)
	bb.StudsOffset = Vector3.new(0, yOffset, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 160
	bb.Parent = adornee

	local label = Instance.new("TextLabel")
	label.Name = "NameLabel"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 0.52)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.2
	label.Text = title
	label.Parent = bb

	local bg = Instance.new("Frame")
	bg.Name = "BarBg"
	bg.Position = UDim2.fromScale(0.05, 0.58)
	bg.Size = UDim2.fromScale(0.9, 0.34)
	bg.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
	bg.BorderSizePixel = 0
	bg.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = bg

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = accent
	fill.BorderSizePixel = 0
	fill.Parent = bg
	local fCorner = Instance.new("UICorner")
	fCorner.CornerRadius = UDim.new(0, 6)
	fCorner.Parent = fill
	return bb
end

local function applyMutationAndHalo(
	model: Model,
	root: BasePart,
	mutationKey: string,
	starTier: number
)
	if mutationKey ~= "Normal" then
		local vfxTemplate = findAssetPrefab("VFX", "Mutation_" .. mutationKey)
		if vfxTemplate then
			local matName = tostring(vfxTemplate:GetAttribute("MaterialName") or "")
			if mutationKey == "Golden" then
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BasePart") and d.Name ~= "EyeL" and d.Name ~= "EyeR" then
						d.Color = Color3.fromRGB(255, 212, 56)
						d.Material = Enum.Material.Metal
					end
				end
			elseif mutationKey == "VoidTouched" then
				root.Color = Color3.fromRGB(36, 18, 68)
				root.Material = Enum.Material.Neon
			elseif matName == "Glass" then
				root.Material = Enum.Material.Glass
			elseif matName == "Neon" then
				root.Material = Enum.Material.Neon
			end
			for _, child in ipairs(vfxTemplate:GetChildren()) do
				child:Clone().Parent = root
			end
		end
	end

	if starTier >= 3 then
		local haloAtt = root:FindFirstChild("HaloAttachment")
		local yOff = if haloAtt and haloAtt:IsA("Attachment") then haloAtt.Position.Y else 2.85
		local haloPrefab = findAssetPrefab("VFX", "ApexHalo_3Star")
		if haloPrefab and haloPrefab:IsA("Model") and haloPrefab.PrimaryPart then
			local halo = haloPrefab:Clone()
			local hRoot = halo.PrimaryPart :: BasePart
			halo:PivotTo(root.CFrame * CFrame.new(0, yOff, 0) * CFrame.Angles(0, 0, math.rad(90)))
			for _, p in ipairs(halo:GetDescendants()) do
				if p:IsA("BasePart") then
					p.Anchored = false
				end
			end
			local m = Instance.new("Motor6D")
			m.Name = "ApexHaloMotor"
			m.Part0 = root
			m.Part1 = hRoot
			m.C0 = CFrame.new(0, yOff, 0) * CFrame.Angles(0, 0, math.rad(90))
			m.C1 = CFrame.new()
			m:SetAttribute("AnimRole", "OrbitShard")
			m:SetAttribute("AnimSpeed", 2.2)
			m.Parent = root
			halo.Parent = model
		else
			local ring = makePart(
				model,
				"ApexHalo",
				Vector3.new(0.25, 2.6, 2.6),
				Color3.fromRGB(255, 215, 64),
				Enum.Material.Neon,
				Enum.PartType.Cylinder
			)
			weldOffset(root, ring, CFrame.new(0, yOff, 0) * CFrame.Angles(0, 0, math.rad(90)))
		end
	end
end

local function ensureBallTrail(core: BasePart, col0: Color3, col1: Color3)
	local trail = core:FindFirstChildOfClass("Trail")
	if not trail then
		local att0 = core:FindFirstChild("Trail0")
		if not att0 then
			local a0 = Instance.new("Attachment")
			a0.Name = "Trail0"
			a0.Position = Vector3.new(0, 0.7, 0)
			a0.Parent = core
			att0 = a0
		end
		local att1 = core:FindFirstChild("Trail1")
		if not att1 then
			local a1 = Instance.new("Attachment")
			a1.Name = "Trail1"
			a1.Position = Vector3.new(0, -0.7, 0)
			a1.Parent = core
			att1 = a1
		end
		local newTrail = Instance.new("Trail")
		newTrail.Lifetime = 0.25
		if att0 and att0:IsA("Attachment") then
			newTrail.Attachment0 = att0
		end
		if att1 and att1:IsA("Attachment") then
			newTrail.Attachment1 = att1
		end
		newTrail.Parent = core
		trail = newTrail
	end
	if trail then
		trail.Lifetime = 0.25
		trail.Color = ColorSequence.new(col0, col1)
	end
end

function ProceduralModels.createBallVisual(ballTierId: string, skinColor: Color3?): Model
	local prefab = findAssetPrefab("Balls", ballTierId)
	if prefab and prefab:IsA("Model") and prefab.PrimaryPart then
		local clone = prefab:Clone()
		if skinColor then
			clone.PrimaryPart.Color = skinColor
			ensureBallTrail(clone.PrimaryPart, skinColor, skinColor)
		end
		return clone
	end

	local tier = EconomyConfigs.getBallTierById(ballTierId) or EconomyConfigs.BALL_TIERS[1]
	local primary = skinColor or rgb(tier.primaryColor)
	local trailCol = skinColor or rgb(tier.trailColor)
	local model = Instance.new("Model")
	model.Name = "ThrownBall_" .. tier.id
	local core = makePart(
		model,
		"Root",
		Vector3.new(1.85, 1.85, 1.85),
		primary,
		Enum.Material.Neon,
		Enum.PartType.Ball
	)
	model.PrimaryPart = core
	ensureBallTrail(core, trailCol, primary)
	return model
end

function ProceduralModels.createEggVisual(eggId: string, isOvercharged: boolean?): Model
	local cfg = EggConfigs.getEgg(eggId)
	local accent = if cfg then rgb(cfg.accentColor) else Color3.fromRGB(250, 204, 21)
	local over = isOvercharged == true or (cfg ~= nil and cfg.category == "OverchargedBoss")
	local label = if cfg then cfg.displayName else eggId

	local prefab = findAssetPrefab("Eggs", eggId)
	if prefab and prefab:IsA("Model") and prefab.PrimaryPart then
		local clone = prefab:Clone()
		addOverheadBillboard(
			clone.PrimaryPart,
			label,
			if over then "OVERCHARGED!" else "BOSS EGG",
			accent,
			3.6
		)
		return clone
	end

	local primary = if cfg then rgb(cfg.primaryColor) else Color3.fromRGB(74, 222, 128)
	local model = Instance.new("Model")
	model.Name = "Egg_" .. eggId
	local root = makePart(
		model,
		"Root",
		Vector3.new(3.2, 4.1, 3.2),
		primary,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Ball
	)
	model.PrimaryPart = root
	addOverheadBillboard(root, label, if over then "OVERCHARGED!" else "BOSS EGG", accent, 3.6)
	return model
end

function ProceduralModels.createPetModel(
	speciesId: string,
	mutationKey: string,
	starTier: number,
	subtitleText: string?
): Model
	local spec = PetConfigs.getSpecies(speciesId) or PetConfigs.SPECIES.TrainingPup
	local accent = rgb(spec.accentColor)
	local stars = string.rep("★", math.clamp(starTier, 1, 3))
	local mutPrefix = if mutationKey ~= "Normal" then `[{mutationKey}] ` else ""

	local prefab = findAssetPrefab("Pets", spec.id)
	if prefab and prefab:IsA("Model") and prefab.PrimaryPart then
		local clone = prefab:Clone()
		local root = clone.PrimaryPart :: BasePart
		applyMutationAndHalo(clone, root, mutationKey, starTier)
		addOverheadBillboard(
			root,
			`{mutPrefix}{spec.displayName} {stars}`,
			subtitleText or spec.perkLabel,
			accent,
			3.2
		)
		return clone
	end

	local model = Instance.new("Model")
	model.Name = "Pet_" .. spec.id
	local root = makePart(
		model,
		"Root",
		Vector3.new(2.2, 2.0, 2.6),
		rgb(spec.primaryColor),
		Enum.Material.SmoothPlastic,
		Enum.PartType.Ball
	)
	model.PrimaryPart = root
	applyMutationAndHalo(model, root, mutationKey, starTier)
	addOverheadBillboard(
		root,
		`{mutPrefix}{spec.displayName} {stars}`,
		subtitleText or spec.perkLabel,
		accent,
		3.2
	)
	return model
end

function ProceduralModels.createMobProjectileVisual(
	projectileId: string,
	colorOverride: Color3?
): Model
	local prefab = findAssetPrefab("VFX", projectileId)
	if prefab and prefab:IsA("Model") and prefab.PrimaryPart then
		local clone = prefab:Clone()
		local col = colorOverride or clone.PrimaryPart.Color
		ensureBallTrail(clone.PrimaryPart, col, Color3.fromRGB(255, 255, 255))
		return clone
	end

	local fallbackCol = colorOverride or Color3.fromRGB(198, 72, 255)
	local diam = if projectileId == "Proj_RuneBoulder" then 2.8 else 1.8
	local model = Instance.new("Model")
	model.Name = "MobProj_" .. projectileId
	local core = makePart(
		model,
		"Root",
		Vector3.new(diam, diam, diam),
		fallbackCol,
		if projectileId == "Proj_RuneBoulder" then Enum.Material.Rock else Enum.Material.Neon,
		Enum.PartType.Ball
	)
	model.PrimaryPart = core
	ensureBallTrail(core, fallbackCol, Color3.fromRGB(255, 255, 255))
	return model
end

function ProceduralModels.createMobModel(mobId: string): Model
	local cfg = BiomeConfigs.MOBS[mobId] or BiomeConfigs.MOBS.MossSlime
	local accent = rgb(cfg.accentColor)
	local barWidth = if cfg.isElite then 186 else 150

	local prefab = findAssetPrefab("Mobs", cfg.id)
	if prefab and prefab:IsA("Model") and prefab.PrimaryPart then
		local clone = prefab:Clone()
		local hbOffset = tonumber(clone:GetAttribute("HealthBarOffsetY")) or 4.0
		addHealthBar(clone.PrimaryPart, cfg.displayName, accent, hbOffset, barWidth)
		return clone
	end

	local model = Instance.new("Model")
	model.Name = "Mob_" .. cfg.id
	local scale = if cfg.isElite then 1.25 else 1.0
	local root = makePart(
		model,
		"HumanoidRootPart",
		Vector3.new(3.6 * scale, 3.8 * scale, 3.6 * scale),
		rgb(cfg.primaryColor),
		Enum.Material.SmoothPlastic,
		Enum.PartType.Ball
	)
	root.CanQuery = true
	model.PrimaryPart = root
	addHealthBar(root, cfg.displayName, accent, 3.6 * scale, barWidth)
	return model
end

function ProceduralModels.createBossModel(bossId: string, isOvercharged: boolean): Model
	local cfg = BiomeConfigs.BOSSES[bossId] or BiomeConfigs.BOSSES.MossbackGolem
	local accent = if isOvercharged then Color3.fromRGB(255, 72, 196) else rgb(cfg.accentColor)
	local title = if isOvercharged
		then `⚡ OVERCHARGED {string.upper(cfg.displayName)}`
		else cfg.displayName

	local prefab = findAssetPrefab("Bosses", cfg.id)
	if prefab and prefab:IsA("Model") and prefab.PrimaryPart then
		local clone = prefab:Clone()
		local root = clone.PrimaryPart :: BasePart
		if isOvercharged then
			local ocVfx = findAssetPrefab("VFX", "Mutation_Overcharged")
			if ocVfx then
				for _, child in ipairs(ocVfx:GetChildren()) do
					child:Clone().Parent = root
				end
			end
		end
		addHealthBar(root, title, accent, 14, 260)
		return clone
	end

	local model = Instance.new("Model")
	model.Name = "Boss_" .. cfg.id
	local root = makePart(
		model,
		"HumanoidRootPart",
		Vector3.new(10, 12, 9),
		rgb(cfg.primaryColor),
		Enum.Material.Rock
	)
	root.CanQuery = true
	model.PrimaryPart = root
	addHealthBar(root, title, accent, 12.5, 260)
	return model
end

function ProceduralModels.styleTrainingTargets(trainingRange: Instance, targetTierId: string)
	local tier = EconomyConfigs.getTargetTierById(targetTierId)
		or EconomyConfigs.TRAINING_TARGETS[1]
	local primary = rgb(tier.primaryColor)
	local targetPrefab = findAssetPrefab("Targets", tier.id)
	local pad = trainingRange:FindFirstChild("FiringPad")

	local function facingCF(targetPart: BasePart): CFrame
		if pad and pad:IsA("BasePart") then
			local lookAt = Vector3.new(pad.Position.X, targetPart.Position.Y, pad.Position.Z)
			return CFrame.lookAt(targetPart.Position, lookAt) * CFrame.Angles(0, math.rad(90), 0)
		end
		return targetPart.CFrame * CFrame.Angles(0, math.rad(90), 0)
	end

	for _, child in ipairs(trainingRange:GetChildren()) do
		if child:IsA("BasePart") then
			if string.find(child.Name, "Target_Static_") then
				child.Color = primary
				child.Transparency = if targetPrefab then 1 else 0
				child.Material = if tier.id == "CrystalDrone" or tier.id == "ObsidianCore"
					then Enum.Material.Neon
					else Enum.Material.SmoothPlastic
				local oldDec = child:FindFirstChild("TargetSkin")
				if oldDec then
					oldDec:Destroy()
				end
				if targetPrefab and targetPrefab:IsA("Model") and targetPrefab.PrimaryPart then
					local skin = targetPrefab:Clone()
					skin.Name = "TargetSkin"
					skin:PivotTo(facingCF(child))
					for _, p in ipairs(skin:GetDescendants()) do
						if p:IsA("BasePart") then
							p.CanQuery = false
							p.CanCollide = false
							p.Anchored = true
						end
					end
					skin.Parent = child
				end
			elseif child.Name == "Target_MovingGold" then
				child.Color = Color3.fromRGB(255, 212, 46)
				child.Material = Enum.Material.Neon
				child.Transparency = 1
				local oldGold = child:FindFirstChild("TargetSkin")
				if oldGold then
					oldGold:Destroy()
				end
				local goldPrefab = findAssetPrefab("Targets", "MovingGold")
				if goldPrefab and goldPrefab:IsA("Model") and goldPrefab.PrimaryPart then
					local skin = goldPrefab:Clone()
					skin.Name = "TargetSkin"
					skin:PivotTo(facingCF(child))
					for _, p in ipairs(skin:GetDescendants()) do
						if p:IsA("BasePart") then
							p.CanQuery = false
							p.CanCollide = false
							p.Anchored = false
						end
					end
					local w = Instance.new("WeldConstraint")
					w.Part0 = child
					w.Part1 = skin.PrimaryPart
					w.Parent = skin.PrimaryPart
					skin.Parent = child
				end
			end
		end
	end
end

return ProceduralModels
