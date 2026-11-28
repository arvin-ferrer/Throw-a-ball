--!strict
--[[
	WorldMapBootstrapService.luau
	Builds Workspace.BallBrawl_Map_v2 cleanly when Team Create map geometry is absent,
	so local playtests & solo Rojo workflows run 100% standalone.
	NEVER modifies an existing Workspace.BallBrawl_Map_v2 (preserves Team Create art).
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BiomeConfigs = require(Shared.Configs.BiomeConfigs)
local WorldMapLayout = require(Shared.Utils.WorldMapLayout)

type PartOpts = {
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?,
	canCollide: boolean?,
	canTouch: boolean?,
	canQuery: boolean?,
	transparency: number?,
	castShadow: boolean?,
	anchored: boolean?,
	tags: { string }?,
}

type BiomeVisual = {
	ground: { number },
	groundMat: Enum.Material,
	wall: { number },
	wallMat: Enum.Material,
	accent: { number },
}

local WorldMapBootstrapService = {}

local BIOME_VISUALS: { [string]: BiomeVisual } = {
	EmeraldMeadow = {
		ground = { 78, 168, 92 },
		groundMat = Enum.Material.Grass,
		wall = { 98, 118, 92 },
		wallMat = Enum.Material.Rock,
		accent = { 52, 211, 153 },
	},
	FrostbiteCavern = {
		ground = { 176, 224, 248 },
		groundMat = Enum.Material.Ice,
		wall = { 104, 154, 206 },
		wallMat = Enum.Material.Glacier,
		accent = { 56, 189, 248 },
	},
	MoltenCaldera = {
		ground = { 58, 42, 46 },
		groundMat = Enum.Material.Basalt,
		wall = { 42, 32, 38 },
		wallMat = Enum.Material.Rock,
		accent = { 251, 113, 42 },
	},
}

local function rgb(arr: { number }): Color3
	return Color3.fromRGB(arr[1] or 255, arr[2] or 255, arr[3] or 255)
end

local function vec3(arr: WorldMapLayout.Vec3): Vector3
	return Vector3.new(arr[1], arr[2], arr[3])
end

local function addTags(inst: Instance, tags: { string }?)
	if not tags then
		return
	end
	for _, tag in ipairs(tags) do
		CollectionService:AddTag(inst, tag)
	end
end

local function makePart(parent: Instance, opts: PartOpts): Part
	local p = Instance.new("Part")
	p.Name = opts.name
	p.Size = opts.size
	p.CFrame = opts.cf
	p.Color = opts.color
	p.Material = opts.material or Enum.Material.SmoothPlastic
	p.Shape = opts.shape or Enum.PartType.Block
	p.Anchored = if opts.anchored ~= nil then opts.anchored else true
	p.CanCollide = if opts.canCollide ~= nil then opts.canCollide else true
	p.CanTouch = if opts.canTouch ~= nil then opts.canTouch else true
	p.CanQuery = if opts.canQuery ~= nil then opts.canQuery else true
	p.Transparency = opts.transparency or 0
	p.CastShadow = if opts.castShadow ~= nil then opts.castShadow else true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	addTags(p, opts.tags)
	return p
end

local function addSurfaceSign(
	part: BasePart,
	text: string,
	bgColor: Color3,
	textColor: Color3
): TextLabel
	local sg = Instance.new("SurfaceGui")
	sg.Name = "SurfaceGui"
	sg.Face = Enum.NormalId.Front
	sg.CanvasSize = Vector2.new(640, 240)
	sg.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	sg.Parent = part

	local bg = Instance.new("Frame")
	bg.Name = "Backdrop"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = bgColor
	bg.BorderSizePixel = 0
	bg.Parent = sg

	local lbl = Instance.new("TextLabel")
	lbl.Name = "Text"
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(0.92, 0.86)
	lbl.Position = UDim2.fromScale(0.04, 0.07)
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextScaled = true
	lbl.TextWrapped = true
	lbl.TextColor3 = textColor
	lbl.TextStrokeTransparency = 0.25
	lbl.Text = text
	lbl.Parent = bg
	return lbl
end

local function addBillboard(
	adornee: BasePart,
	title: string,
	subtitle: string,
	accent: Color3,
	yOffset: number,
	maxDist: number?
)
	local bb = Instance.new("BillboardGui")
	bb.Name = "InfoBillboard"
	bb.Adornee = adornee
	bb.Size = UDim2.fromOffset(220, 64)
	bb.StudsOffset = Vector3.new(0, yOffset, 0)
	bb.MaxDistance = maxDist or 120
	bb.Parent = adornee

	local t1 = Instance.new("TextLabel")
	t1.Name = "Title"
	t1.BackgroundTransparency = 1
	t1.Size = UDim2.fromScale(1, 0.56)
	t1.Font = Enum.Font.FredokaOne
	t1.TextScaled = true
	t1.TextColor3 = Color3.new(1, 1, 1)
	t1.TextStrokeTransparency = 0.2
	t1.Text = title
	t1.Parent = bb

	local t2 = Instance.new("TextLabel")
	t2.Name = "Subtitle"
	t2.BackgroundTransparency = 1
	t2.Position = UDim2.fromScale(0, 0.56)
	t2.Size = UDim2.fromScale(1, 0.44)
	t2.Font = Enum.Font.GothamBold
	t2.TextScaled = true
	t2.TextColor3 = accent
	t2.TextStrokeTransparency = 0.25
	t2.Text = subtitle
	t2.Parent = bb
end

local function buildRingWalls(
	parent: Instance,
	prefix: string,
	center: WorldMapLayout.Vec3,
	radius: number,
	count: number,
	height: number,
	width: number,
	thickness: number,
	color: Color3,
	material: Enum.Material
)
	local segs =
		WorldMapLayout.getRingWallTransforms(center, radius, count, height, width, thickness)
	for _, seg in ipairs(segs) do
		makePart(parent, {
			name = string.format("%s_%02d", prefix, seg.index),
			size = vec3(seg.size),
			cf = CFrame.lookAt(vec3(seg.center), vec3(seg.lookAt)),
			color = color,
			material = material,
		})
	end
end

local function configureLighting()
	Lighting.ClockTime = 13.5
	Lighting.Brightness = 2.2
	Lighting.Ambient = Color3.fromRGB(115, 130, 152)
	Lighting.OutdoorAmbient = Color3.fromRGB(142, 156, 178)
	Lighting.GlobalShadows = true
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmo = Instance.new("Atmosphere")
		atmo.Density = 0.24
		atmo.Offset = 0.1
		atmo.Color = Color3.fromRGB(205, 224, 255)
		atmo.Decay = Color3.fromRGB(130, 165, 210)
		atmo.Glare = 0.15
		atmo.Haze = 0.6
		atmo.Parent = Lighting
	end
end

local function buildBeaconClocks(beacon: Model)
	for i = 1, 4 do
		local pos = WorldMapLayout.polarPosition(4.6, (i - 1) * 90, 9.5)
		local outPos = WorldMapLayout.polarPosition(10, (i - 1) * 90, 9.5)
		local board = makePart(beacon, {
			name = `ClockBoard_{i}`,
			size = Vector3.new(7.4, 4.4, 0.5),
			cf = CFrame.lookAt(vec3(pos), vec3(outPos)),
			color = Color3.fromRGB(24, 28, 44),
			tags = { "OverchargedClockBoard" },
		})
		addSurfaceSign(
			board,
			"OVERCHARGED EVENT\n5:00",
			Color3.fromRGB(48, 16, 56),
			Color3.fromRGB(255, 114, 188)
		)
	end
end

local function buildBeaconCore(beacon: Model)
	local base = makePart(beacon, {
		name = "BasePedestal",
		size = Vector3.new(16, 2.5, 16),
		cf = CFrame.new(0, 1.25, 0),
		color = Color3.fromRGB(48, 56, 78),
	})
	beacon.PrimaryPart = base
	makePart(beacon, {
		name = "Pillar",
		size = Vector3.new(8.5, 14, 8.5),
		cf = CFrame.new(0, 9.5, 0),
		color = Color3.fromRGB(36, 42, 62),
	})
end

local function buildHubBeacon(hub: Folder)
	local beacon = Instance.new("Model")
	beacon.Name = "CentralOverchargedBeacon"
	beacon.Parent = hub
	CollectionService:AddTag(beacon, "OverchargedBeacon")

	buildBeaconCore(beacon)
	local orb = makePart(beacon, {
		name = "OverchargedOrb",
		size = Vector3.new(7, 7, 7),
		cf = CFrame.new(0, 21.5, 0),
		color = Color3.fromRGB(255, 72, 196),
		material = Enum.Material.Neon,
		shape = Enum.PartType.Ball,
		canCollide = false,
		tags = { "OverchargedOrb", "FloatBob" },
	})
	addBillboard(
		orb,
		"OVERCHARGED BEACON",
		"Global Boss Event Every 5:00",
		Color3.fromRGB(255, 150, 220),
		5.5,
		180
	)
	local ring = makePart(beacon, {
		name = "OrbRing",
		size = Vector3.new(0.8, 12, 12),
		cf = CFrame.new(0, 21.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
		color = Color3.fromRGB(250, 204, 21),
		material = Enum.Material.Neon,
		shape = Enum.PartType.Cylinder,
		canCollide = false,
		tags = { "SpinRing" },
	})
	ring:SetAttribute("SpinSpeed", 1.5)
	buildBeaconClocks(beacon)
end

local function buildPortalArch(model: Model, rootCF: CFrame, accent: Color3, enabled: boolean)
	local frameCol = if enabled then Color3.fromRGB(45, 54, 76) else Color3.fromRGB(58, 62, 74)
	makePart(model, {
		name = "StepBase",
		size = Vector3.new(16, 0.8, 8),
		cf = rootCF * CFrame.new(0, 0.4, 0),
		color = frameCol,
	})
	for _, xOff in ipairs({ -6.5, 6.5 }) do
		makePart(model, {
			name = "Pillar",
			size = Vector3.new(2.4, 15, 3),
			cf = rootCF * CFrame.new(xOff, 8, 0),
			color = frameCol,
		})
	end
	makePart(model, {
		name = "ArchTop",
		size = Vector3.new(16.5, 2.4, 3.6),
		cf = rootCF * CFrame.new(0, 16, 0),
		color = accent,
		material = Enum.Material.Neon,
	})
end

local function buildPortalFieldAndHolo(
	model: Model,
	rootCF: CFrame,
	spec: WorldMapLayout.PortalSpec,
	accent: Color3
)
	local field = makePart(model, {
		name = "PortalField",
		size = Vector3.new(10.6, 13.5, 1.4),
		cf = rootCF * CFrame.new(0, 7.6, 0),
		color = accent,
		material = Enum.Material.Neon,
		canCollide = false,
		transparency = if spec.enabled then 0.35 else 0.72,
		tags = { spec.tag },
	})
	field:SetAttribute("BiomeId", spec.biomeId)
	field:SetAttribute("Enabled", spec.enabled)
	field:SetAttribute("RecommendedDamage", spec.recommendedDamage)
	if spec.biomeId == "VaultHeist" then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Enter Vault Heist"
		prompt.ObjectText = "Co-Op Boss Heist (0s Wait)"
		prompt.MaxActivationDistance = 14
		prompt.RequiresLineOfSight = false
		prompt.Parent = field
	end
end

local function buildSinglePortal(portalsFolder: Folder, spec: WorldMapLayout.PortalSpec)
	local model = Instance.new("Model")
	model.Name = spec.name
	model:SetAttribute("BiomeId", spec.biomeId)
	model:SetAttribute("Enabled", spec.enabled)
	model:SetAttribute("RecommendedDamage", spec.recommendedDamage)
	model.Parent = portalsFolder

	local posArr = WorldMapLayout.polarPosition(WorldMapLayout.PORTAL_RING_RADIUS, spec.angleDeg, 0)
	local rootCF = CFrame.lookAt(vec3(posArr), Vector3.zero)
	local accent = rgb(spec.color)
	buildPortalArch(model, rootCF, accent, spec.enabled)
	buildPortalFieldAndHolo(model, rootCF, spec, accent)

	local holo = makePart(model, {
		name = "Hologram",
		size = Vector3.new(2.4, 2.4, 2.4),
		cf = rootCF * CFrame.new(0, 19.6, 0),
		color = accent,
		material = Enum.Material.Neon,
		shape = Enum.PartType.Ball,
		canCollide = false,
		tags = { "PortalHologram", "FloatBob" },
	})
	addBillboard(holo, spec.title, spec.subtitle, accent, 3.2, 160)
	local board = makePart(model, {
		name = "InfoBoard",
		size = Vector3.new(12, 3.0, 0.6),
		cf = rootCF * CFrame.new(0, 16, -2.1),
		color = Color3.fromRGB(22, 26, 40),
		tags = { "PortalInfoBoard" },
	})
	addSurfaceSign(board, `{spec.title}\n{spec.subtitle}`, Color3.fromRGB(22, 26, 40), accent)
end

local function populateLeaderboardGui(board: Part)
	local sg = Instance.new("SurfaceGui")
	sg.Name = "SurfaceGui"
	sg.Face = Enum.NormalId.Front
	sg.CanvasSize = Vector2.new(900, 540)
	sg.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	sg.Parent = board

	local bg = Instance.new("Frame")
	bg.Name = "Backdrop"
	bg.ZIndex = 1
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(16, 22, 36)
	bg.BorderSizePixel = 0
	bg.Parent = sg

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.ZIndex = 2
	title.BackgroundColor3 = Color3.fromRGB(30, 58, 110)
	title.BorderSizePixel = 0
	title.Size = UDim2.fromScale(1, 0.18)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(250, 204, 21)
	title.Text = "SERVER LEADERBOARDS • POWER • WINS • COINS/S"
	title.Parent = sg

	local rows = Instance.new("TextLabel")
	rows.Name = "Rows"
	rows.ZIndex = 2
	rows.BackgroundTransparency = 1
	rows.Position = UDim2.fromScale(0.04, 0.21)
	rows.Size = UDim2.fromScale(0.92, 0.75)
	rows.Font = Enum.Font.GothamBold
	rows.TextSize = 26
	rows.TextWrapped = true
	rows.TextYAlignment = Enum.TextYAlignment.Top
	rows.TextXAlignment = Enum.TextXAlignment.Left
	rows.TextColor3 = Color3.fromRGB(238, 245, 255)
	rows.Text = "Top Power: Syncing...\nBoss Wins: Syncing...\nCoins/s: Syncing..."
	rows.Parent = sg
end

local function buildLeaderboardBoard(servicesFolder: Folder, spec: WorldMapLayout.ServiceSpec)
	local posArr =
		WorldMapLayout.polarPosition(WorldMapLayout.SERVICE_RING_RADIUS, spec.angleDeg, 0)
	local rootCF = CFrame.lookAt(vec3(posArr), Vector3.zero)
	local board = makePart(servicesFolder, {
		name = spec.name,
		size = Vector3.new(22, 13, 1.6),
		cf = rootCF * CFrame.new(0, 8.2, 0),
		color = Color3.fromRGB(24, 30, 48),
		tags = { spec.tag },
	})
	board:SetAttribute("ServiceId", spec.serviceId)
	makePart(board, {
		name = "BasePlinth",
		size = Vector3.new(24, 2, 4.2),
		cf = rootCF * CFrame.new(0, 1, 0),
		color = Color3.fromRGB(48, 58, 82),
	})
	makePart(board, {
		name = "TrimFrame",
		size = Vector3.new(23.2, 1.0, 2.0),
		cf = rootCF * CFrame.new(0, 15.1, 0),
		color = rgb(spec.color),
		material = Enum.Material.Neon,
	})
	populateLeaderboardGui(board)
end

local function buildServiceKiosk(servicesFolder: Folder, spec: WorldMapLayout.ServiceSpec)
	local model = Instance.new("Model")
	model.Name = spec.name
	model:SetAttribute("ServiceId", spec.serviceId)
	model.Parent = servicesFolder

	local posArr =
		WorldMapLayout.polarPosition(WorldMapLayout.SERVICE_RING_RADIUS, spec.angleDeg, 0)
	local rootCF = CFrame.lookAt(vec3(posArr), Vector3.zero)
	local accent = rgb(spec.color)

	makePart(model, {
		name = "KioskBase",
		size = Vector3.new(12, 1.2, 10),
		cf = rootCF * CFrame.new(0, 0.6, 0),
		color = Color3.fromRGB(48, 56, 76),
	})
	makePart(model, {
		name = "BackWall",
		size = Vector3.new(10, 7.5, 1.8),
		cf = rootCF * CFrame.new(0, 4.9, 3.6),
		color = Color3.fromRGB(36, 42, 60),
	})
	local canopy = makePart(model, {
		name = "Canopy",
		size = Vector3.new(12.6, 1.2, 8.6),
		cf = rootCF * CFrame.new(0, 9.2, 0.5),
		color = accent,
		material = Enum.Material.Neon,
	})
	local pad = makePart(model, {
		name = "InteractPad",
		size = Vector3.new(8, 0.8, 6),
		cf = rootCF * CFrame.new(0, 1.4, -1.5),
		color = accent,
		material = Enum.Material.Neon,
		tags = { spec.tag },
	})
	pad:SetAttribute("ServiceId", spec.serviceId)
	addBillboard(canopy, spec.title, spec.subtitle, accent, 3.0, 130)
end

local function buildPedestalAccessories(
	ped: Model,
	plotCF: CFrame,
	spec: WorldMapLayout.PedestalSpec
)
	local pad = makePart(ped, {
		name = "CashPad",
		size = Vector3.new(4.4, 0.4, 4.4),
		cf = plotCF * CFrame.new(vec3(spec.cashPadPos)),
		color = Color3.fromRGB(56, 72, 92),
		canCollide = false,
		tags = { "CashPad" },
	})
	pad:SetAttribute("StoredCoins", 0)
	makePart(ped, {
		name = "PetAnchor",
		size = Vector3.new(1, 1, 1),
		cf = plotCF * CFrame.new(vec3(spec.petAnchorPos)),
		color = Color3.new(1, 1, 1),
		canCollide = false,
		canTouch = false,
		canQuery = false,
		transparency = 1,
		tags = { "PetAnchor" },
	})
	if spec.index == 1 then
		makePart(ped, {
			name = "StarterEgg",
			size = Vector3.new(2.4, 3.0, 2.4),
			cf = plotCF * CFrame.new(vec3(spec.petAnchorPos)),
			color = Color3.fromRGB(110, 231, 183),
			shape = Enum.PartType.Ball,
			canCollide = false,
			canQuery = false,
			tags = { "StarterEgg" },
		})
	end
end

local function buildPlotPedestal(
	pedFolder: Folder,
	plotCF: CFrame,
	plotId: number,
	spec: WorldMapLayout.PedestalSpec
)
	local ped = Instance.new("Model")
	ped.Name = spec.name
	ped:SetAttribute("PedestalIndex", spec.index)
	ped.Parent = pedFolder

	local baseColor = if spec.isVip
		then Color3.fromRGB(250, 204, 21)
		elseif spec.isBalcony then Color3.fromRGB(129, 140, 248)
		else Color3.fromRGB(72, 84, 112)
	local basePart = makePart(ped, {
		name = "Base",
		size = Vector3.new(5.5, 2.2, 5.5),
		cf = plotCF * CFrame.new(vec3(spec.basePos)),
		color = baseColor,
		tags = { "BasePedestal" },
	})
	basePart:SetAttribute("PedestalIndex", spec.index)
	basePart:SetAttribute("PlotId", plotId)

	makePart(ped, {
		name = "TrimRing",
		size = Vector3.new(5.9, 0.4, 5.9),
		cf = plotCF * CFrame.new(spec.basePos[1], spec.basePos[2] + 0.9, spec.basePos[3]),
		color = if spec.isVip then Color3.fromRGB(255, 240, 150) else Color3.fromRGB(148, 163, 184),
	})
	buildPedestalAccessories(ped, plotCF, spec)
end

local function attachMovingGoldVisual(gold: Part)
	local vis = makePart(gold, {
		name = "GoldVisual",
		size = Vector3.new(3.4, 4.6, 1.4),
		cf = gold.CFrame,
		color = Color3.fromRGB(255, 212, 46),
		material = Enum.Material.Neon,
		anchored = false,
		canCollide = false,
		canTouch = false,
		canQuery = false,
	})
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = gold
	weld.Part1 = vis
	weld.Parent = vis
	addBillboard(gold, "GOLD 2x", "+THROW SPEED", Color3.fromRGB(250, 204, 21), 4.2, 95)
end

local function buildTrainingTargets(tr: Model, plotCF: CFrame, padZ: number)
	local cfg = WorldMapLayout.TRAINING_RANGE_OFFSETS
	for _, t in ipairs(cfg.staticTargets) do
		local tp = vec3(t.pos)
		local target = makePart(tr, {
			name = t.name,
			size = Vector3.new(4.2, 5.6, 2.4),
			cf = plotCF * CFrame.lookAt(tp, Vector3.new(tp.X, tp.Y, padZ)),
			color = Color3.fromRGB(176, 128, 78),
			tags = { "TrainingTarget" },
		})
		target:SetAttribute("TargetKind", "Static")
	end

	local gp = vec3(cfg.movingGold.pos)
	local gold = makePart(tr, {
		name = cfg.movingGold.name,
		size = Vector3.new(4.4, 5.6, 2.4),
		cf = plotCF * CFrame.lookAt(gp, Vector3.new(gp.X, gp.Y, padZ)),
		color = Color3.fromRGB(255, 212, 46),
		material = Enum.Material.Neon,
		tags = { "MovingGoldTarget" },
	})
	gold:SetAttribute("TargetKind", "MovingGold")
	gold:SetAttribute("RailHalfLength", cfg.movingGold.railHalfLength)
	attachMovingGoldVisual(gold)

	makePart(tr, {
		name = "GoldRail",
		size = Vector3.new(24, 0.5, 1.2),
		cf = plotCF * CFrame.new(gp.X, 0.25, gp.Z),
		color = Color3.fromRGB(250, 204, 21),
		canQuery = false,
	})
end

local function buildRangePadAndTerminal(tr: Model, plotCF: CFrame, plotId: number)
	local cfg = WorldMapLayout.TRAINING_RANGE_OFFSETS
	local padPos = vec3(cfg.firingPad)
	local pad = makePart(tr, {
		name = "FiringPad",
		size = Vector3.new(8, 0.6, 8),
		cf = plotCF * CFrame.lookAt(padPos, padPos + Vector3.new(0, 0, 10)),
		color = Color3.fromRGB(52, 211, 153),
		material = Enum.Material.Neon,
		tags = { "TrainingFiringPad" },
	})
	pad:SetAttribute("PlotId", plotId)
	makePart(tr, {
		name = "FiringStance",
		size = Vector3.new(6, 0.25, 1.5),
		cf = plotCF * CFrame.new(vec3(cfg.firingStance)),
		color = Color3.fromRGB(250, 204, 21),
		material = Enum.Material.Neon,
		canCollide = false,
		canQuery = false,
		tags = { "FiringStance" },
	})
	local term = makePart(tr, {
		name = "UpgradeTerminal",
		size = Vector3.new(3.6, 5.0, 3.0),
		cf = plotCF * CFrame.new(vec3(cfg.upgradeTerminal)),
		color = Color3.fromRGB(56, 189, 248),
		tags = { "RangeUpgradeTerminal" },
	})
	addBillboard(
		term,
		"TARGET UPGRADE",
		"Interact to Tier Up",
		Color3.fromRGB(56, 189, 248),
		3.8,
		70
	)
	return padPos.Z
end

local function buildPlotTrainingRange(plotModel: Model, plotCF: CFrame, plotId: number)
	local tr = Instance.new("Model")
	tr.Name = "TrainingRange"
	tr:SetAttribute("TargetTier", "WoodenDummy")
	tr.Parent = plotModel

	local padZ = buildRangePadAndTerminal(tr, plotCF, plotId)
	buildTrainingTargets(tr, plotCF, padZ)
	makePart(tr, {
		name = "RangeBackstop",
		size = Vector3.new(26, 13, 2),
		cf = plotCF * CFrame.new(25, 6.5, 38),
		color = Color3.fromRGB(48, 56, 78),
	})
	local rSign = makePart(tr, {
		name = "OwnerSign",
		size = Vector3.new(18, 4.2, 0.8),
		cf = plotCF * CFrame.new(vec3(WorldMapLayout.TRAINING_RANGE_OFFSETS.ownerSign)),
		color = Color3.fromRGB(24, 28, 44),
		tags = { "PlotOwnerSign" },
	})
	addSurfaceSign(
		rSign,
		"TRAINING RANGE",
		Color3.fromRGB(24, 28, 44),
		Color3.fromRGB(74, 222, 128)
	)
end

local function buildPlotBalcony(plotModel: Model, plotCF: CFrame)
	local balcony = Instance.new("Folder")
	balcony.Name = "Balcony"
	balcony.Parent = plotModel

	makePart(balcony, {
		name = "BalconyDeck",
		size = Vector3.new(45, 1.5, 25),
		cf = plotCF * CFrame.new(-13.5, 10.5, 30.5),
		color = Color3.fromRGB(165, 180, 206),
	})
	local wedge = Instance.new("WedgePart")
	wedge.Name = "BalconyRamp"
	wedge.Size = Vector3.new(5, 11.25, 22)
	wedge.CFrame = plotCF * CFrame.new(-33, 5.625, 7)
	wedge.Color = Color3.fromRGB(148, 163, 184)
	wedge.Material = Enum.Material.SmoothPlastic
	wedge.Anchored = true
	wedge.Parent = balcony

	for idx, pPos in ipairs({
		Vector3.new(-35, 5.25, 19),
		Vector3.new(8, 5.25, 19),
		Vector3.new(-35, 5.25, 42),
		Vector3.new(8, 5.25, 42),
	}) do
		makePart(balcony, {
			name = `Pillar_{idx}`,
			size = Vector3.new(2, 10.5, 2),
			cf = plotCF * CFrame.new(pPos),
			color = Color3.fromRGB(100, 116, 139),
		})
	end
	makePart(balcony, {
		name = "TrimRailing",
		size = Vector3.new(38, 2.2, 0.8),
		cf = plotCF * CFrame.new(-10, 12.35, 18.4),
		color = Color3.fromRGB(129, 140, 248),
	})
end

local function buildPlotShell(plotModel: Model, plotCF: CFrame, plotId: number)
	local shell = Instance.new("Model")
	shell.Name = "Shell"
	shell.Parent = plotModel

	local floor = makePart(shell, {
		name = "PlotFloor",
		size = vec3(WorldMapLayout.PLOT_SIZE),
		cf = plotCF * CFrame.new(0, -1, 0),
		color = Color3.fromRGB(205, 214, 228),
	})
	shell.PrimaryPart = floor
	makePart(shell, {
		name = "BackWall",
		size = Vector3.new(80, 10, 2),
		cf = plotCF * CFrame.new(0, 5, 44),
		color = Color3.fromRGB(72, 84, 112),
	})
	makePart(shell, {
		name = "TrimLeft",
		size = Vector3.new(1.8, 1.4, 90),
		cf = plotCF * CFrame.new(-39.1, 0.7, 0),
		color = Color3.fromRGB(96, 165, 250),
	})
	makePart(shell, {
		name = "TrimRight",
		size = Vector3.new(1.8, 1.4, 90),
		cf = plotCF * CFrame.new(39.1, 0.7, 0),
		color = Color3.fromRGB(96, 165, 250),
	})
	local sign = makePart(shell, {
		name = "OwnerSign",
		size = Vector3.new(20, 4.5, 1.2),
		cf = plotCF * CFrame.new(0, 6.5, -43),
		color = Color3.fromRGB(28, 36, 56),
		tags = { "PlotOwnerSign" },
	})
	addSurfaceSign(sign, `Plot #{plotId} — Open`, Color3.fromRGB(28, 36, 56), Color3.new(1, 1, 1))
end

local function buildSinglePlot(plotsFolder: Folder, plotSpec: WorldMapLayout.PlotTransformSpec)
	local plotModel = Instance.new("Model")
	plotModel.Name = plotSpec.plotName
	plotModel:SetAttribute("PlotId", plotSpec.plotId)
	plotModel:SetAttribute("OwnerUserId", 0)
	plotModel:SetAttribute("PedestalsUnlocked", WorldMapLayout.DEFAULT_UNLOCKED_PEDESTALS)
	plotModel.Parent = plotsFolder

	local plotCF = CFrame.lookAt(vec3(plotSpec.center), vec3(plotSpec.lookAt))
	buildPlotShell(plotModel, plotCF, plotSpec.plotId)

	makePart(plotModel, {
		name = "PlotSpawn",
		size = Vector3.new(6, 0.5, 6),
		cf = plotCF * CFrame.new(0, 0.25, -39) * CFrame.Angles(0, math.rad(180), 0),
		color = Color3.fromRGB(52, 211, 153),
		material = Enum.Material.Neon,
		canCollide = false,
		tags = { "PlotSpawn" },
	})
	local zone = makePart(plotModel, {
		name = "PlotZone",
		size = Vector3.new(80, 48, 90),
		cf = plotCF * CFrame.new(0, 24, 0),
		color = Color3.new(1, 1, 1),
		canCollide = false,
		canTouch = false,
		canQuery = false,
		transparency = 1,
		castShadow = false,
		tags = { "PlotZone" },
	})
	zone:SetAttribute("PlotId", plotSpec.plotId)

	buildPlotBalcony(plotModel, plotCF)
	local peds = Instance.new("Folder")
	peds.Name = "Pedestals"
	peds.Parent = plotModel
	for _, pedSpec in ipairs(WorldMapLayout.PLOT_PEDESTALS) do
		buildPlotPedestal(peds, plotCF, plotSpec.plotId, pedSpec)
	end
	buildPlotTrainingRange(plotModel, plotCF, plotSpec.plotId)
end

local function buildHubGroundAndSpawn(hub: Folder)
	makePart(hub, {
		name = "Ground",
		size = vec3(WorldMapLayout.HUB_FLOOR_SIZE),
		cf = CFrame.new(0, -2, 0),
		color = Color3.fromRGB(132, 168, 206),
	})
	makePart(hub, {
		name = "PlazaCenterRing",
		size = Vector3.new(0.2, 174, 174),
		cf = CFrame.new(0, 0.05, 0) * CFrame.Angles(0, 0, math.rad(90)),
		color = Color3.fromRGB(224, 234, 248),
		shape = Enum.PartType.Cylinder,
		canCollide = false,
		canQuery = false,
	})
	local boundary = Instance.new("Folder")
	boundary.Name = "Boundary"
	boundary.Parent = hub
	buildRingWalls(
		boundary,
		"HubWall",
		{ 0, 0, 0 },
		WorldMapLayout.HUB_BOUNDARY_RADIUS,
		WorldMapLayout.HUB_BOUNDARY_COUNT,
		26,
		50,
		4,
		Color3.fromRGB(64, 82, 118),
		Enum.Material.SmoothPlastic
	)
	local spawns = Instance.new("Folder")
	spawns.Name = "Spawns"
	spawns.Parent = hub
	local fallback = Instance.new("SpawnLocation")
	fallback.Name = "FallbackSpawn"
	fallback.Size = Vector3.new(8, 0.8, 8)
	fallback.CFrame = CFrame.lookAt(vec3(WorldMapLayout.FALLBACK_SPAWN_POS), Vector3.new(0, 0.5, 0))
	fallback.Color = Color3.fromRGB(74, 222, 128)
	fallback.Material = Enum.Material.Neon
	fallback.Anchored = true
	fallback.Duration = 0
	fallback.Neutral = true
	fallback.Parent = spawns
end

local function buildHub(root: Folder)
	local hub = Instance.new("Folder")
	hub.Name = "Hub"
	hub:SetAttribute("ZoneType", "Hub")
	hub:SetAttribute("PvPEnabled", false)
	hub.Parent = root

	buildHubGroundAndSpawn(hub)
	buildHubBeacon(hub)

	local portals = Instance.new("Folder")
	portals.Name = "Portals"
	portals.Parent = hub
	for _, spec in ipairs(WorldMapLayout.PORTALS) do
		buildSinglePortal(portals, spec)
	end

	local services = Instance.new("Folder")
	services.Name = "Services"
	services.Parent = hub
	for _, spec in ipairs(WorldMapLayout.SERVICES) do
		if spec.isLeaderboard then
			buildLeaderboardBoard(services, spec)
		else
			buildServiceKiosk(services, spec)
		end
	end

	local plots = Instance.new("Folder")
	plots.Name = "Plots"
	plots.Parent = hub
	for _, plotSpec in ipairs(WorldMapLayout.getAllPlots()) do
		buildSinglePlot(plots, plotSpec)
	end
end

local function buildPveSpawnsAndLandmarks(
	pve: Folder,
	biomeCfg: BiomeConfigs.BiomeConfig,
	vis: BiomeVisual,
	cx: number,
	cz: number
)
	local landmarks = Instance.new("Folder")
	landmarks.Name = "Landmarks"
	landmarks.Parent = pve
	for idx, off in ipairs(WorldMapLayout.LANDMARK_OFFSETS) do
		makePart(landmarks, {
			name = `Landmark_{idx}`,
			size = Vector3.new(9, 14 + (idx % 3) * 4, 9),
			cf = CFrame.new(cx + off[1], 7, cz + off[3]),
			color = rgb(vis.wall),
			material = vis.wallMat,
		})
	end

	local mobSpawns = Instance.new("Folder")
	mobSpawns.Name = "MobSpawns"
	mobSpawns.Parent = pve
	for idx, spec in ipairs(WorldMapLayout.getBiomeMobSpawns(biomeCfg.id)) do
		local off = spec.offset
		local mType = spec.mobType or biomeCfg.mobs[((idx - 1) % #biomeCfg.mobs) + 1]
		local pad = makePart(mobSpawns, {
			name = string.format("MobSpawn_%02d", idx),
			size = Vector3.new(8, 0.3, 8),
			cf = CFrame.new(cx + off[1], 0.15, cz + off[3]),
			color = rgb(vis.accent),
			canCollide = false,
			canTouch = false,
			canQuery = false,
			transparency = 0.65,
			tags = { "MobSpawnZone" },
		})
		pad:SetAttribute("BiomeId", biomeCfg.id)
		pad:SetAttribute("MobType", mType)
	end
end

local function buildPveFloorAndPortals(
	pve: Folder,
	biomeId: string,
	vis: BiomeVisual,
	cx: number,
	cz: number
)
	local arrOff, retOff = WorldMapLayout.getBiomeArrivalAndReturnOffsets(biomeId)
	makePart(pve, {
		name = "PvEGround",
		size = vec3(WorldMapLayout.getBiomePveSize(biomeId)),
		cf = CFrame.new(cx, -2, cz),
		color = rgb(vis.ground),
		material = vis.groundMat,
	})
	makePart(pve, {
		name = "ArrivalPad",
		size = Vector3.new(12, 0.5, 12),
		cf = CFrame.lookAt(
			Vector3.new(cx + arrOff[1], arrOff[2], cz + arrOff[3]),
			Vector3.new(cx, arrOff[2], cz)
		),
		color = rgb(vis.accent),
		material = Enum.Material.Neon,
		tags = { "BiomeArrivalPad" },
	})
	local ret = makePart(pve, {
		name = "ReturnPortal",
		size = Vector3.new(10, 10, 2.5),
		cf = CFrame.lookAt(
			Vector3.new(cx + retOff[1], retOff[2], cz + retOff[3]),
			Vector3.new(cx, retOff[2], cz)
		),
		color = Color3.fromRGB(96, 165, 250),
		material = Enum.Material.Neon,
		canCollide = false,
		transparency = 0.35,
		tags = { "ReturnPortal" },
	})
	addBillboard(
		ret,
		"RETURN TO HUB",
		"Step in to Teleport",
		Color3.fromRGB(147, 197, 253),
		6.2,
		130
	)
end

local function buildBiomePvE(
	biomeFolder: Folder,
	biomeCfg: BiomeConfigs.BiomeConfig,
	spatial: WorldMapLayout.BiomeSpatialSpec
)
	local vis = BIOME_VISUALS[biomeCfg.id] or BIOME_VISUALS.EmeraldMeadow
	local pve = Instance.new("Folder")
	pve.Name = "PvELayer"
	pve:SetAttribute("ZoneType", "BiomePvE")
	pve:SetAttribute("PvPEnabled", false)
	pve:SetAttribute("BiomeId", biomeCfg.id)
	pve.Parent = biomeFolder

	local cx, _, cz = spatial.pveCenter[1], spatial.pveCenter[2], spatial.pveCenter[3]
	buildPveFloorAndPortals(pve, biomeCfg.id, vis, cx, cz)
	buildPveSpawnsAndLandmarks(pve, biomeCfg, vis, cx, cz)
	local pveSz = WorldMapLayout.getBiomePveSize(biomeCfg.id)
	local rimRadius = math.max(WorldMapLayout.BIOME_RIM_RADIUS, math.max(pveSz[1], pveSz[3]) * 0.5)
	buildRingWalls(
		pve,
		"RimWall",
		spatial.pveCenter,
		rimRadius,
		WorldMapLayout.BIOME_WALL_COUNT,
		24,
		math.max(38, math.ceil((2 * math.pi * rimRadius) / WorldMapLayout.BIOME_WALL_COUNT) + 6),
		4,
		rgb(vis.wall),
		vis.wallMat
	)
end

local function buildArenaSpawnsAndPillars(arena: Folder, vis: BiomeVisual, cx: number, cz: number)
	for i = 1, WorldMapLayout.ARENA_OPTIN_COUNT do
		local off =
			WorldMapLayout.polarPosition(WorldMapLayout.ARENA_OPTIN_RADIUS, (i - 1) * 45, 0.25)
		makePart(arena, {
			name = string.format("OptInSpawn_%02d", i),
			size = Vector3.new(6, 0.5, 6),
			cf = CFrame.lookAt(
				Vector3.new(cx + off[1], 0.25, cz + off[3]),
				Vector3.new(cx, 0.25, cz)
			),
			color = rgb(vis.accent),
			material = Enum.Material.Neon,
			canCollide = false,
			tags = { "ArenaPlayerSpawn" },
		})
	end
	for i = 1, WorldMapLayout.ARENA_PILLAR_COUNT do
		local off =
			WorldMapLayout.polarPosition(WorldMapLayout.ARENA_PILLAR_RADIUS, 30 + (i - 1) * 60, 8)
		makePart(arena, {
			name = string.format("CoverPillar_%02d", i),
			size = Vector3.new(8, 16, 8),
			cf = CFrame.new(cx + off[1], 8, cz + off[3]),
			color = rgb(vis.wall),
			material = vis.wallMat,
		})
	end
end

local function buildArenaCoreMarkers(arena: Folder, cx: number, cz: number)
	makePart(arena, {
		name = "BossSpawn",
		size = Vector3.new(12, 0.4, 12),
		cf = CFrame.lookAt(Vector3.new(cx, 0.2, cz - 32), Vector3.new(cx, 0.2, cz)),
		color = Color3.fromRGB(239, 68, 68),
		material = Enum.Material.Neon,
		canCollide = false,
		canQuery = false,
		transparency = 0.4,
		tags = { "BossSpawn" },
	})
	makePart(arena, {
		name = "EggClaimPedestal",
		size = Vector3.new(8, 4, 8),
		cf = CFrame.new(cx, 2, cz),
		color = Color3.fromRGB(250, 204, 21),
		tags = { "BossEggPedestal" },
	})
	local claimD = BiomeConfigs.EGG_CLAIM_RADIUS * 2
	makePart(arena, {
		name = "EggClaimRing",
		size = Vector3.new(0.25, claimD, claimD),
		cf = CFrame.new(cx, 0.15, cz) * CFrame.Angles(0, 0, math.rad(90)),
		color = Color3.fromRGB(250, 204, 21),
		material = Enum.Material.Neon,
		shape = Enum.PartType.Cylinder,
		canCollide = false,
		canQuery = false,
		transparency = 0.55,
	})
	local sdDiam = BiomeConfigs.SUDDEN_DEATH_START_RADIUS * 2
	makePart(arena, {
		name = "SuddenDeathRingMarker",
		size = Vector3.new(0.4, sdDiam, sdDiam),
		cf = CFrame.new(cx, 0.35, cz) * CFrame.Angles(0, 0, math.rad(90)),
		color = Color3.fromRGB(239, 68, 68),
		material = Enum.Material.Neon,
		shape = Enum.PartType.Cylinder,
		canCollide = false,
		canQuery = false,
		transparency = 0.5,
		tags = { "SuddenDeathRing" },
	})
end

local function buildArenaFloorAndVolume(arena: Folder, vis: BiomeVisual, cx: number, cz: number)
	local diam = WorldMapLayout.ARENA_FLOOR_DIAMETER
	makePart(arena, {
		name = "ArenaFloor",
		size = Vector3.new(4, diam, diam),
		cf = CFrame.new(cx, -2, cz) * CFrame.Angles(0, 0, math.rad(90)),
		color = rgb(vis.ground),
		material = vis.groundMat,
		shape = Enum.PartType.Cylinder,
	})
	local vol = makePart(arena, {
		name = "RoomVolume",
		size = vec3(WorldMapLayout.ARENA_ROOM_VOLUME_SIZE),
		cf = CFrame.new(cx, WorldMapLayout.ARENA_ROOM_VOLUME_Y, cz),
		color = Color3.new(1, 1, 1),
		canCollide = false,
		canTouch = false,
		canQuery = false,
		transparency = 1,
		castShadow = false,
	})
	vol:SetAttribute("IsRoomVolume", true)
end

local function buildBiomeArena(
	biomeFolder: Folder,
	biomeCfg: BiomeConfigs.BiomeConfig,
	spatial: WorldMapLayout.BiomeSpatialSpec
)
	local vis = BIOME_VISUALS[biomeCfg.id] or BIOME_VISUALS.EmeraldMeadow
	local arena = Instance.new("Folder")
	arena.Name = "BossPvPArena"
	arena:SetAttribute("ZoneType", "LockedBossPvP")
	arena:SetAttribute("BossId", biomeCfg.bossId)
	arena:SetAttribute("BiomeId", biomeCfg.id)
	arena.Parent = biomeFolder

	local cx, _, cz = spatial.arenaCenter[1], spatial.arenaCenter[2], spatial.arenaCenter[3]
	buildArenaFloorAndVolume(arena, vis, cx, cz)
	buildArenaCoreMarkers(arena, cx, cz)
	buildArenaSpawnsAndPillars(arena, vis, cx, cz)
	buildRingWalls(
		arena,
		"ArenaWall",
		spatial.arenaCenter,
		WorldMapLayout.ARENA_WALL_RADIUS,
		WorldMapLayout.BIOME_WALL_COUNT,
		36,
		36,
		4,
		rgb(vis.wall),
		vis.wallMat
	)
end

local function buildBiomes(root: Folder)
	local biomes = Instance.new("Folder")
	biomes.Name = "Biomes"
	biomes.Parent = root
	for _, biomeId in ipairs(BiomeConfigs.ORDERED_MVP_BIOMES) do
		local cfg = BiomeConfigs.BIOMES[biomeId]
		if cfg then
			local bFolder = Instance.new("Folder")
			bFolder.Name = biomeId
			bFolder.Parent = biomes
			local spatial = WorldMapLayout.getBiomeSpatial(biomeId)
			buildBiomePvE(bFolder, cfg, spatial)
			buildBiomeArena(bFolder, cfg, spatial)
		end
	end
end

local function buildVaultStructure(vault: Folder)
	local vc = WorldMapLayout.VAULT_CENTER
	makePart(vault, {
		name = "VaultFloor",
		size = vec3(WorldMapLayout.VAULT_FLOOR_SIZE),
		cf = CFrame.new(vc[1], -2, vc[3]),
		color = Color3.fromRGB(34, 40, 58),
		material = Enum.Material.Metal,
	})
	local bounds = Instance.new("Folder")
	bounds.Name = "VaultBoundary"
	bounds.Parent = vault
	local b = WorldMapLayout.getVaultBounds()
	for _, ws in ipairs({
		{
			name = "Wall_North",
			pos = Vector3.new(vc[1], 12, b.minZ),
			size = Vector3.new(124, 24, 4),
		},
		{
			name = "Wall_South",
			pos = Vector3.new(vc[1], 12, b.maxZ),
			size = Vector3.new(124, 24, 4),
		},
		{
			name = "Wall_East",
			pos = Vector3.new(b.maxX, 12, vc[3]),
			size = Vector3.new(4, 24, 124),
		},
		{
			name = "Wall_West",
			pos = Vector3.new(b.minX, 12, vc[3]),
			size = Vector3.new(4, 24, 124),
		},
	}) do
		makePart(bounds, {
			name = ws.name,
			size = ws.size,
			cf = CFrame.new(ws.pos),
			color = Color3.fromRGB(24, 28, 42),
			material = Enum.Material.Metal,
		})
	end
end

local function buildVaultBossAndEgg(vault: Folder)
	makePart(vault, {
		name = "VaultBossSpawn",
		size = Vector3.new(8, 0.4, 8),
		cf = CFrame.lookAt(
			vec3(WorldMapLayout.VAULT_BOSS_SPAWN_POS),
			vec3(WorldMapLayout.VAULT_SPAWN_POS)
		),
		color = Color3.fromRGB(239, 68, 68),
		material = Enum.Material.Neon,
		canCollide = false,
		tags = { "VaultBossSpawn" },
	})
	local ped = makePart(vault, {
		name = "VaultEggPedestal",
		size = Vector3.new(8, 4, 8),
		cf = CFrame.new(vec3(WorldMapLayout.VAULT_EGG_PEDESTAL_POS)),
		color = Color3.fromRGB(250, 204, 21),
		tags = { "VaultEggPedestal" },
	})
	addBillboard(
		ped,
		"VAULT EGG PEDESTAL",
		"Snatch & Extract!",
		Color3.fromRGB(250, 204, 21),
		5.0,
		120
	)
end

local function buildVaultGameplayNodes(vault: Folder)
	local vc = WorldMapLayout.VAULT_CENTER
	makePart(vault, {
		name = "VaultSpawn",
		size = Vector3.new(8, 0.5, 8),
		cf = CFrame.lookAt(vec3(WorldMapLayout.VAULT_SPAWN_POS), vec3(vc)),
		color = Color3.fromRGB(56, 189, 248),
		material = Enum.Material.Neon,
		canCollide = false,
		tags = { "VaultPlayerSpawn" },
	})
	local ext = makePart(vault, {
		name = "ExtractionPad",
		size = Vector3.new(12, 0.5, 12),
		cf = CFrame.new(vec3(WorldMapLayout.VAULT_EXTRACTION_POS)),
		color = Color3.fromRGB(52, 211, 153),
		material = Enum.Material.Neon,
		canCollide = false,
		tags = { "VaultExtractionPad" },
	})
	addBillboard(
		ext,
		"EXTRACTION PAD",
		"Bring Vault Egg Here!",
		Color3.fromRGB(74, 222, 128),
		4.5,
		120
	)
	buildVaultBossAndEgg(vault)
end

local function buildVaultObstacles(vault: Folder)
	makePart(vault, {
		name = "LaserGate",
		size = vec3(WorldMapLayout.VAULT_LASER_GATE_SIZE),
		cf = CFrame.new(vec3(WorldMapLayout.VAULT_LASER_GATE_POS)),
		color = Color3.fromRGB(239, 68, 68),
		material = Enum.Material.Neon,
		canCollide = false,
		transparency = 0.25,
		tags = { "VaultLaserGate" },
	})
	local nodes = Instance.new("Folder")
	nodes.Name = "PatrolNodes"
	nodes.Parent = vault
	for i, nPos in ipairs(WorldMapLayout.VAULT_PATROL_NODES) do
		makePart(nodes, {
			name = string.format("Node_%02d", i),
			size = Vector3.new(3, 1, 3),
			cf = CFrame.new(vec3(nPos)),
			color = Color3.fromRGB(248, 113, 113),
			canCollide = false,
			canTouch = false,
			canQuery = false,
			transparency = 0.75,
		})
	end
	for i, pPos in ipairs(WorldMapLayout.VAULT_COVER_PILLARS) do
		makePart(vault, {
			name = string.format("CoverPillar_%02d", i),
			size = Vector3.new(7, 12, 7),
			cf = CFrame.new(vec3(pPos)),
			color = Color3.fromRGB(58, 68, 96),
			material = Enum.Material.Metal,
		})
	end
end

local function buildVaultHeist(root: Folder)
	local vault = Instance.new("Folder")
	vault.Name = "VaultHeist"
	vault:SetAttribute("ZoneType", "VaultHeist")
	vault:SetAttribute("PvPEnabled", false)
	vault.Parent = root

	buildVaultStructure(vault)
	buildVaultGameplayNodes(vault)
	buildVaultObstacles(vault)
end

function WorldMapBootstrapService.ensureBuilt(): Instance
	local existing = workspace:FindFirstChild(WorldMapLayout.MAP_NAME)
	if existing then
		return existing
	end
	configureLighting()
	local root = Instance.new("Folder")
	root.Name = WorldMapLayout.MAP_NAME
	root:SetAttribute("MapVersion", WorldMapLayout.MAP_VERSION)
	root:SetAttribute("BiomeSpacingX", WorldMapLayout.BIOME_SPACING_X)
	root:SetAttribute("ArenaOffsetZ", WorldMapLayout.ARENA_OFFSET_Z)
	buildHub(root)
	buildBiomes(root)
	buildVaultHeist(root)
	root.Parent = workspace
	return root
end

function WorldMapBootstrapService.init()
	WorldMapBootstrapService.ensureBuilt()
end

function WorldMapBootstrapService.start() end

return WorldMapBootstrapService
