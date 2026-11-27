--!strict
--[[
	VaultHeistService.luau
	Server-authoritative 1-4p Co-Op Boss Vault Heist ("C2: Egg Heist"):
	- 0s instant entry via Hub Portal_VaultHeist (VaultHeistPortal) or UI Start action
	- PartyId squad grouping + 1-CCU solo scaling with 1 free Solo Rescue Drone
	- 3 Coin-upgradable Utility Orbs (Decoy, Freeze, DashBomb)
	- Heavy-Egg overhead carry visual + light beam, Drop/Pass, LaserGate freeze pause
	- 5-state Boss AI FSM, 4 procedural mutators, Hourly VaultStorm, and 10s Extraction Vote
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyLogic = require(Shared.Utils.EconomyLogic)
local MathUtil = require(Shared.Utils.MathUtil)
local ProceduralModels = require(Shared.Utils.ProceduralModels)
local Remotes = require(Shared.Net.Remotes)
local VaultHeistConfigs = require(Shared.Configs.VaultHeistConfigs)
local VaultHeistLogic = require(Shared.Utils.VaultHeistLogic)

local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)

type VaultArenaRefs = {
	slotIndex: number,
	isClone: boolean,
	folder: Instance,
	visualsFolder: Folder,
	centerPos: Vector3,
	halfExtent: number,
	vaultSpawn: BasePart,
	bossSpawn: BasePart,
	pedestal: BasePart,
	extractionPad: BasePart,
	laserParts: { BasePart },
	laserOrigCFs: { CFrame },
	patrolNodes: { VaultHeistLogic.Vec3 },
	pedestalPrompt: ProximityPrompt?,
}

type ActiveRunRuntime = {
	run: VaultHeistLogic.VaultRunState,
	refs: VaultArenaRefs,
	bossModel: Model?,
	bossHead: BasePart?,
	bossHpFill: Frame?,
	bossStateLabel: TextLabel?,
	telegraphPart: Part?,
	stunIcePart: Part?,
	pedestalEggVisual: Model?,
	pedestalBeam: Part?,
	droppedEggVisual: Model?,
	droppedPrompt: ProximityPrompt?,
	carrierVisuals: { [number]: Model },
	decoyVisuals: { [string]: Model },
	downedBillboards: { [number]: BillboardGui },
	lastSyncAt: number,
	dirtySync: boolean,
	pendingEvents: { { kind: string, pos: Vector3?, label: string?, color: { number }? } },
}

local VaultHeistService = {}

local activeRunsById: { [string]: ActiveRunRuntime } = {}
local runByUserId: { [number]: ActiveRunRuntime } = {}
local runByGroupKey: { [string]: ActiveRunRuntime } = {}
local occupiedSlots: { [number]: boolean } = {}
local portalDebounce: { [number]: number } = {}
local actionDebounce: { [number]: number } = {}
local ACTION_DEBOUNCE_SEC = 0.25
local nextRunSeq = 0

local announcementHook: ((Player, string, string, { number }, boolean) -> ())? = nil
local juiceHook: ((string, Vector3?, number?, string?, { number }?) -> ())? = nil
local completionHook: ((Player, number, boolean) -> ())? = nil

local function ensureRemote(name: string): RemoteEvent
	local folder = Remotes.ensureServer().Folder
	local existing = folder:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local re = Instance.new("RemoteEvent")
	re.Name = name
	re.Parent = folder
	return re
end

local function toVec3(v: Vector3): VaultHeistLogic.Vec3
	return { x = v.X, y = v.Y, z = v.Z }
end

local function fromVec3(v: VaultHeistLogic.Vec3): Vector3
	return Vector3.new(v.x, v.y, v.z)
end

local function rgb(arr: { number }): Color3
	return Color3.fromRGB(arr[1] or 255, arr[2] or 255, arr[3] or 255)
end

local function getPlayerPartyId(player: Player): string
	local ok, raw = pcall(function()
		return (player :: any).PartyId
	end)
	if ok and type(raw) == "string" and raw ~= "" then
		return raw
	end
	local attr = player:GetAttribute("PartyId")
	return if type(attr) == "string" then attr else ""
end

local function getPlayerHRP(player: Player): (BasePart?, Humanoid?)
	local char = player.Character
	if not char then
		return nil, nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	return if hrp and hrp:IsA("BasePart") then hrp else nil, hum
end

local function resolveBasePart(inst: Instance?): BasePart?
	if not inst then
		return nil
	end
	if inst:IsA("BasePart") then
		return inst
	end
	if inst:IsA("Model") then
		return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
	end
	return inst:FindFirstChildWhichIsA("BasePart", true)
end

local function makeBoxPart(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	mat: Enum.Material,
	collide: boolean
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.Anchored = true
	p.CanCollide = collide
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function buildFallbackWallsAndNodes(folder: Instance, center: Vector3)
	local walls = {
		{ "WallN", Vector3.new(120, 22, 4), Vector3.new(0, 12, -60) },
		{ "WallS", Vector3.new(120, 22, 4), Vector3.new(0, 12, 60) },
		{ "WallE", Vector3.new(4, 22, 120), Vector3.new(60, 12, 0) },
		{ "WallW", Vector3.new(4, 22, 120), Vector3.new(-60, 12, 0) },
	}
	for _, w in ipairs(walls) do
		makeBoxPart(
			folder,
			w[1] :: string,
			w[2] :: Vector3,
			CFrame.new(center + (w[3] :: Vector3)),
			Color3.fromRGB(28, 32, 44),
			Enum.Material.Slate,
			true
		)
	end
	local nodesFolder = Instance.new("Folder")
	nodesFolder.Name = "PatrolNodes"
	nodesFolder.Parent = folder
	local nodeOffsets = {
		Vector3.new(-28, 4, -28),
		Vector3.new(28, 4, -28),
		Vector3.new(28, 4, 12),
		Vector3.new(-28, 4, 12),
	}
	for i, off in ipairs(nodeOffsets) do
		makeBoxPart(
			nodesFolder,
			`Node_0{i}`,
			Vector3.new(3, 1, 3),
			CFrame.new(center + off),
			Color3.fromRGB(148, 163, 184),
			Enum.Material.SmoothPlastic,
			false
		)
	end
end

local FALLBACK_PROP_SPECS = {
	{ "VaultSpawn", { 10, 1, 10 }, { 0, 2.5, 42 }, { 56, 189, 248 }, "VaultPlayerSpawn", false },
	{ "VaultBossSpawn", { 8, 1, 8 }, { 0, 2.5, -10 }, { 244, 63, 94 }, "VaultBossSpawn", false },
	{
		"VaultEggPedestal",
		{ 8, 3, 8 },
		{ 0, 3.5, -42 },
		{ 250, 204, 21 },
		"VaultEggPedestal",
		true,
	},
	{ "LaserGate", { 28, 10, 1.5 }, { 0, 7, 15 }, { 255, 45, 95 }, "VaultLaserGate", false },
	{
		"ExtractionPad",
		{ 14, 1, 14 },
		{ 0, 2.5, 42 },
		{ 74, 222, 128 },
		"VaultExtractionPad",
		false,
	},
}

local function buildFallbackProps(folder: Instance, center: Vector3)
	for _, s in ipairs(FALLBACK_PROP_SPECS) do
		local sz = s[2] :: { number }
		local off = s[3] :: { number }
		local mat = if s[1] == "VaultEggPedestal"
			then Enum.Material.SmoothPlastic
			else Enum.Material.Neon
		local part = makeBoxPart(
			folder,
			s[1] :: string,
			Vector3.new(sz[1], sz[2], sz[3]),
			CFrame.new(center + Vector3.new(off[1], off[2], off[3])),
			rgb(s[4] :: { number }),
			mat,
			s[6] :: boolean
		)
		CollectionService:AddTag(part, s[5] :: string)
	end
end

local function ensureFallbackVaultFolder(): Folder
	local mapRoot = PlotService.getMapRoot()
	local host: Instance = mapRoot or workspace
	local prev = host:FindFirstChild("VaultHeist")
	if prev and prev:IsA("Folder") then
		return prev
	end
	local folder = Instance.new("Folder")
	folder.Name = "VaultHeist"
	folder:SetAttribute("ZoneType", "VaultHeist")
	folder:SetAttribute("PvPEnabled", false)
	folder.Parent = host
	local center = Vector3.new(0, 0, -900)
	makeBoxPart(
		folder,
		"VaultFloor",
		Vector3.new(120, 4, 120),
		CFrame.new(center),
		Color3.fromRGB(38, 44, 58),
		Enum.Material.SmoothPlastic,
		true
	)
	buildFallbackWallsAndNodes(folder, center)
	buildFallbackProps(folder, center)
	return folder
end

local function findVaultTemplateFolder(): Folder
	local root = PlotService.getMapRoot()
	local vh = if root then root:FindFirstChild("VaultHeist") else nil
	if vh and vh:IsA("Folder") then
		return vh
	end
	return ensureFallbackVaultFolder()
end

local function collectLaserParts(folder: Instance): ({ BasePart }, { CFrame })
	local parts: { BasePart } = {}
	local cfs: { CFrame } = {}
	local gate = folder:FindFirstChild("LaserGate")
	if not gate then
		return parts, cfs
	end
	if gate:IsA("BasePart") then
		table.insert(parts, gate)
		table.insert(cfs, gate.CFrame)
		return parts, cfs
	end
	for _, desc in ipairs(gate:GetDescendants()) do
		if desc:IsA("BasePart") then
			table.insert(parts, desc)
			table.insert(cfs, desc.CFrame)
		end
	end
	return parts, cfs
end

local function collectPatrolNodes(folder: Instance, center: Vector3): { VaultHeistLogic.Vec3 }
	local nodes: { VaultHeistLogic.Vec3 } = {}
	local pFolder = folder:FindFirstChild("PatrolNodes")
	if pFolder then
		local children = pFolder:GetChildren()
		table.sort(children, function(a, b)
			return a.Name < b.Name
		end)
		for _, child in ipairs(children) do
			local bp = resolveBasePart(child)
			if bp then
				table.insert(nodes, toVec3(bp.Position + Vector3.new(0, 4.5, 0)))
			end
		end
	end
	if #nodes == 0 then
		for _, off in ipairs({
			Vector3.new(-28, 6.5, -28),
			Vector3.new(28, 6.5, -28),
			Vector3.new(28, 6.5, 12),
			Vector3.new(-28, 6.5, 12),
		}) do
			table.insert(nodes, toVec3(center + off))
		end
	end
	return nodes
end

local function cloneArenaFolder(template: Folder, slotIndex: number): Instance
	local clone = template:Clone()
	clone.Name = `VaultHeist_Slot_{slotIndex}`
	for _, desc in ipairs(clone:GetDescendants()) do
		for _, tag in ipairs(CollectionService:GetTags(desc)) do
			CollectionService:RemoveTag(desc, tag)
		end
		if desc:IsA("BasePart") then
			desc.CFrame = desc.CFrame + Vector3.new((slotIndex + 1) * 240, 0, 0)
		end
	end
	clone.Parent = template.Parent or workspace
	return clone
end

local function allocateArenaRefs(slotIndex: number): VaultArenaRefs
	local template = findVaultTemplateFolder()
	local isClone = true
	local folder: Instance = cloneArenaFolder(template, slotIndex)
	local floor = resolveBasePart(folder:FindFirstChild("VaultFloor"))
	local vSpawn = resolveBasePart(folder:FindFirstChild("VaultSpawn")) or floor
	local bSpawn = resolveBasePart(folder:FindFirstChild("VaultBossSpawn")) or floor
	local ped = resolveBasePart(folder:FindFirstChild("VaultEggPedestal")) or floor
	local ext = resolveBasePart(folder:FindFirstChild("ExtractionPad")) or vSpawn
	assert(floor and vSpawn and bSpawn and ped and ext, "VaultHeist geometry incomplete")
	local laserParts, laserOrigCFs = collectLaserParts(folder)
	local halfExtent = math.max(25, math.min(floor.Size.X, floor.Size.Z) * 0.5 - 5)
	local visualsFolder = Instance.new("Folder")
	visualsFolder.Name = `VaultHeist_Visuals_{slotIndex}`
	visualsFolder.Parent = workspace
	return {
		slotIndex = slotIndex,
		isClone = isClone,
		folder = folder,
		visualsFolder = visualsFolder,
		centerPos = floor.Position,
		halfExtent = halfExtent,
		vaultSpawn = vSpawn,
		bossSpawn = bSpawn,
		pedestal = ped,
		extractionPad = ext,
		laserParts = laserParts,
		laserOrigCFs = laserOrigCFs,
		patrolNodes = collectPatrolNodes(folder, floor.Position),
		pedestalPrompt = nil,
	}
end

local function reserveNextSlot(): number
	local slot = 0
	while occupiedSlots[slot] do
		slot += 1
	end
	occupiedSlots[slot] = true
	return slot
end

local function ensurePedestalPrompt(ped: BasePart): ProximityPrompt
	local existing = ped:FindFirstChild("VaultGrabPrompt")
	if existing and existing:IsA("ProximityPrompt") then
		return existing
	end
	local p = Instance.new("ProximityPrompt")
	p.Name = "VaultGrabPrompt"
	p.ActionText = "Snatch Vault Egg!"
	p.ObjectText = "Heavy Boss Egg"
	p.HoldDuration = 0
	p.MaxActivationDistance = 13
	p.RequiresLineOfSight = false
	p.Parent = ped
	return p
end

local function attachBossBillboard(
	root: BasePart,
	title: string,
	accent: Color3
): (TextLabel, Frame)
	local bb = Instance.new("BillboardGui")
	bb.Name = "BossBillboard"
	bb.Adornee = root
	bb.Size = UDim2.fromOffset(220, 56)
	bb.StudsOffset = Vector3.new(0, 7.2, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 160
	bb.Parent = root

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(1, 0.52)
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextScaled = true
	lbl.TextColor3 = Color3.new(1, 1, 1)
	lbl.TextStrokeTransparency = 0.2
	lbl.Text = title
	lbl.Parent = bb

	local bg = Instance.new("Frame")
	bg.Position = UDim2.fromScale(0.05, 0.58)
	bg.Size = UDim2.fromScale(0.9, 0.32)
	bg.BackgroundColor3 = Color3.fromRGB(18, 22, 32)
	bg.BorderSizePixel = 0
	bg.Parent = bb
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = accent
	fill.BorderSizePixel = 0
	fill.Parent = bg
	return lbl, fill
end

local function buildBossVisualModel(rt: ActiveRunRuntime)
	if rt.bossModel then
		rt.bossModel:Destroy()
		rt.bossModel = nil
	end
	local ch = VaultHeistConfigs.getChamber(rt.run.chamber)
	local model = Instance.new("Model")
	model.Name = `VaultBoss_Ch{rt.run.chamber}`
	local aCol = rgb(ch.accentColor)
	local root = makeBoxPart(
		model,
		"HumanoidRootPart",
		Vector3.new(6, 8.5, 5.5),
		CFrame.new(fromVec3(rt.run.boss.pos)),
		rgb(ch.primaryColor),
		Enum.Material.Metal,
		false
	)
	model.PrimaryPart = root
	local visor = makeBoxPart(
		model,
		"Visor",
		Vector3.new(4.4, 1.4, 1.2),
		root.CFrame * CFrame.new(0, 2.2, -2.5),
		aCol,
		Enum.Material.Neon,
		false
	)
	visor.Anchored = false
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = visor
	weld.Parent = visor
	local spot = Instance.new("SpotLight")
	spot.Color = Color3.fromRGB(255, 56, 72)
	spot.Brightness = 4.5
	spot.Range = 58
	spot.Angle = 72
	spot.Face = Enum.NormalId.Front
	spot.Parent = root
	local lbl, fill = attachBossBillboard(root, `{ch.bossName} [PATROL]`, aCol)
	model.Parent = rt.refs.visualsFolder
	rt.bossModel = model
	rt.bossHead = root
	rt.bossHpFill = fill
	rt.bossStateLabel = lbl
end

local function updatePedestalVisuals(rt: ActiveRunRuntime)
	if rt.pedestalEggVisual then
		rt.pedestalEggVisual:Destroy()
		rt.pedestalEggVisual = nil
	end
	if rt.pedestalBeam then
		rt.pedestalBeam:Destroy()
		rt.pedestalBeam = nil
	end
	if rt.run.eggPedestalAvailable then
		local eggId = VaultHeistLogic.getChamberEggId(
			rt.run.chamber,
			rt.run.mutatorId,
			rt.run.isHourlyStorm,
			0.5
		)
		local vis = ProceduralModels.createEggVisual(eggId, rt.run.isHourlyStorm)
		vis:PivotTo(rt.refs.pedestal.CFrame * CFrame.new(0, 3.6, 0))
		vis.Parent = rt.refs.visualsFolder
		rt.pedestalEggVisual = vis
		local beam = makeBoxPart(
			rt.refs.visualsFolder,
			"PedestalBeam",
			Vector3.new(42, 2.2, 2.2),
			CFrame.new(rt.refs.pedestal.Position + Vector3.new(0, 22, 0))
				* CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(250, 204, 21),
			Enum.Material.Neon,
			false
		)
		beam.Shape = Enum.PartType.Cylinder
		beam.Transparency = 0.65
		rt.pedestalBeam = beam
	end
	if rt.refs.pedestalPrompt then
		rt.refs.pedestalPrompt.Enabled = rt.run.eggPedestalAvailable
			and rt.run.carrierUserId == nil
			and rt.run.phase == "Active"
	end
end

local function clearCarrierVisual(rt: ActiveRunRuntime, userId: number)
	local vis = rt.carrierVisuals[userId]
	if vis then
		vis:Destroy()
		rt.carrierVisuals[userId] = nil
	end
end

local function attachCarrierVisual(rt: ActiveRunRuntime, userId: number, eggId: string)
	clearCarrierVisual(rt, userId)
	local plr = Players:GetPlayerByUserId(userId)
	local hrp = if plr then getPlayerHRP(plr) else nil
	if not hrp then
		return
	end
	local vis = ProceduralModels.createEggVisual(eggId, rt.run.isHourlyStorm)
	vis.Name = "CarriedVaultEgg"
	local root = vis.PrimaryPart
	if root then
		for _, p in ipairs(vis:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Anchored = false
				p.CanCollide = false
				p.CanQuery = false
			end
		end
		vis:PivotTo(hrp.CFrame * CFrame.new(0, 4.8, 0))
		local beam = makeBoxPart(
			vis,
			"CarrierBeam",
			Vector3.new(28, 1.8, 1.8),
			root.CFrame * CFrame.new(0, 14, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(250, 204, 21),
			Enum.Material.Neon,
			false
		)
		beam.Shape = Enum.PartType.Cylinder
		beam.Transparency = 0.62
		beam.Anchored = false
		local bw = Instance.new("WeldConstraint")
		bw.Part0 = root
		bw.Part1 = beam
		bw.Parent = beam
		local w = Instance.new("WeldConstraint")
		w.Part0 = hrp
		w.Part1 = root
		w.Parent = root
	end
	vis.Parent = rt.refs.visualsFolder
	rt.carrierVisuals[userId] = vis
end

local function clearDroppedVisual(rt: ActiveRunRuntime)
	if rt.droppedEggVisual then
		rt.droppedEggVisual:Destroy()
		rt.droppedEggVisual = nil
	end
	rt.droppedPrompt = nil
end

local function setPlayerCarryAttributes(player: Player, rt: ActiveRunRuntime?)
	if not rt then
		player:SetAttribute("VaultCarrySlow", 0)
		player:SetAttribute("VaultDowned", false)
		player:SetAttribute("VaultCarrySlowImmune", false)
		return
	end
	local ps = rt.run.players[player.UserId]
	local ch = VaultHeistConfigs.getChamber(rt.run.chamber)
	local slow = if rt.run.carrierUserId == player.UserId then ch.carrySlowFraction else 0
	player:SetAttribute("VaultCarrySlow", slow)
	player:SetAttribute("VaultDowned", if ps then ps.downed else false)
	player:SetAttribute(
		"VaultCarrySlowImmune",
		if ps then os.clock() < ps.carrySlowImmuneUntil else false
	)
end

local function buildInactiveSyncPayload(
	orbLevels: { [string]: number },
	isStorm: boolean,
	stormLeft: number
): { [string]: any }
	return {
		active = false,
		chamber = 1,
		mutatorId = if isStorm then "VaultStorm" else "LowGravity",
		timeLeft = 0,
		bossHP = 0,
		bossMaxHP = 1,
		bossState = "PATROL",
		carryingEggId = nil,
		carrierUserId = nil,
		voteActive = false,
		voteEndsAt = nil,
		streakMult = if isStorm then VaultHeistConfigs.HOURLY_STORM_REWARD_MULT else 1.0,
		orbCooldowns = {},
		orbLevels = orbLevels,
		vaultBankCount = 0,
		isHourlyStorm = isStorm,
		stormTimeLeft = stormLeft,
	}
end

local function computeCooldownMap(
	ps: VaultHeistLogic.VaultPlayerState?,
	now: number
): { [string]: number }
	local cooldowns: { [string]: number } = {}
	if ps then
		for _, oid in ipairs(VaultHeistConfigs.ORDERED_ORBS) do
			cooldowns[oid] = math.max(0, (ps.orbCooldowns[oid] or 0) - now)
		end
	end
	return cooldowns
end

local function buildSyncPayload(
	player: Player,
	rt: ActiveRunRuntime?,
	profile: EconomyLogic.PlayerProfile?
): { [string]: any }
	local nowUnix = os.time()
	local isStorm = VaultHeistLogic.isHourlyVaultStormActive(nowUnix)
	local stormLeft = VaultHeistLogic.getHourlyVaultStormRemaining(nowUnix)
	local orbLevels = VaultHeistLogic.ensureOrbLevels(profile)
	if not rt then
		return buildInactiveSyncPayload(orbLevels, isStorm, stormLeft)
	end
	local now = os.clock()
	local ps = rt.run.players[player.UserId]
	local soloLeft = if ps and rt.run.totalRunPlayers == 1 and not ps.soloReviveUsed then 1 else 0
	return {
		active = rt.run.phase ~= "Finished",
		chamber = rt.run.chamber,
		mutatorId = rt.run.mutatorId,
		timeLeft = math.max(0, rt.run.chamberEndsAt - now),
		bossHP = rt.run.boss.hp,
		bossMaxHP = rt.run.boss.maxHP,
		bossState = rt.run.boss.state,
		carryingEggId = rt.run.carryingEggId,
		carrierUserId = rt.run.carrierUserId,
		voteActive = rt.run.phase == "Vote",
		voteEndsAt = if rt.run.voteEndsAt then math.max(0, rt.run.voteEndsAt - now) else nil,
		streakMult = rt.run.streakMult,
		orbCooldowns = computeCooldownMap(ps, now),
		orbLevels = if ps then ps.orbLevels else orbLevels,
		vaultBankCount = #rt.run.runBagEggs + (if rt.run.carryingEggId then 1 else 0),
		isHourlyStorm = rt.run.isHourlyStorm or isStorm,
		stormTimeLeft = stormLeft,
		downed = if ps then ps.downed else false,
		soloReviveLeft = soloLeft,
		laserPaused = now < rt.run.laserPausedUntil,
		eggOnPedestal = rt.run.eggPedestalAvailable,
		squadSize = #rt.run.playerOrder,
		carrySlowImmune = if ps then now < ps.carrySlowImmuneUntil else false,
		events = rt.pendingEvents,
	}
end

local function syncPlayerState(player: Player)
	local remote = ensureRemote("VaultHeistSync")
	local rt = runByUserId[player.UserId]
	local profile = DataService.getProfile(player)
	remote:FireClient(player, buildSyncPayload(player, rt, profile))
end

local function syncRunPlayers(rt: ActiveRunRuntime)
	local remote = ensureRemote("VaultHeistSync")
	for _, uid in ipairs(rt.run.playerOrder) do
		local plr = Players:GetPlayerByUserId(uid)
		if plr then
			remote:FireClient(plr, buildSyncPayload(plr, rt, DataService.getProfile(plr)))
		end
	end
	table.clear(rt.pendingEvents)
	rt.dirtySync = false
	rt.lastSyncAt = os.clock()
end

local function destroyRunVisuals(rt: ActiveRunRuntime)
	for _, bb in pairs(rt.downedBillboards) do
		bb:Destroy()
	end
	if rt.refs.pedestalPrompt and rt.refs.pedestalPrompt.Parent then
		rt.refs.pedestalPrompt:Destroy()
		rt.refs.pedestalPrompt = nil
	end
	if rt.refs.visualsFolder.Parent then
		rt.refs.visualsFolder:Destroy()
	end
	if rt.refs.isClone and rt.refs.folder.Parent then
		rt.refs.folder:Destroy()
	end
end

local function cleanupRun(rt: ActiveRunRuntime)
	activeRunsById[rt.run.runId] = nil
	if runByGroupKey[rt.run.groupKey] == rt then
		runByGroupKey[rt.run.groupKey] = nil
	end
	for _, uid in ipairs(rt.run.playerOrder) do
		if runByUserId[uid] == rt then
			runByUserId[uid] = nil
		end
		local plr = Players:GetPlayerByUserId(uid)
		if plr then
			setPlayerCarryAttributes(plr, nil)
			local _, hum = getPlayerHRP(plr)
			if hum then
				hum.PlatformStand = false
			end
			if plr:GetAttribute("Zone") == "VaultHeist" then
				PlotService.teleportToHubPlot(plr)
			end
			syncPlayerState(plr)
		end
	end
	destroyRunVisuals(rt)
	occupiedSlots[rt.refs.slotIndex] = nil
end

local function fireExtractionHooks(
	plr: Player,
	eggCount: number,
	finalCoins: number,
	chamberCleared: number,
	timeLeft: number,
	isStorm: boolean
)
	if completionHook then
		pcall(completionHook, plr, chamberCleared, true)
	end
	if announcementHook and (chamberCleared >= 2 or isStorm or timeLeft < 10) then
		local detail =
			`{plr.DisplayName} escaped Chamber {chamberCleared} with {eggCount} Vault Egg(s)!`
		pcall(announcementHook, plr, "VAULT HEIST EXTRACTED!", detail, { 250, 204, 21 }, true)
	end
	if juiceHook then
		local hrp = getPlayerHRP(plr)
		local pos = if hrp then hrp.Position else nil
		pcall(juiceHook, "Crit", pos, finalCoins, `EXTRACTED x{eggCount}!`, { 74, 222, 128 })
	end
end

local function payoutExtractedPlayer(
	plr: Player,
	eggs: { string },
	coins: number,
	gems: number,
	exp: number,
	chamberCleared: number,
	timeLeft: number,
	isStorm: boolean
)
	local profile = DataService.getProfile(plr)
	if not profile then
		return
	end
	local mult = if DataService.hasPass(plr, "Pass_DoubleCoinsExp") then 2 else 1
	local finalCoins = coins * mult
	for _, eggId in ipairs(eggs) do
		profile.eggs[eggId] = (profile.eggs[eggId] or 0) + 1
	end
	profile.coins += finalCoins
	profile.bossGems += gems
	EconomyLogic.addExp(profile, exp * mult)
	DataService.syncToClient(plr)
	local msg =
		`VAULT EXTRACTED! {#eggs} Egg(s), +{MathUtil.formatNumber(finalCoins)} Coins, +{gems} Gems!`
	Remotes.ensureServer().ToastNotify:FireClient(plr, msg, { 74, 222, 128 })
	fireExtractionHooks(plr, #eggs, finalCoins, chamberCleared, timeLeft, isStorm)
end

local function handleExtractionCompleted(rt: ActiveRunRuntime, payload: { [string]: any })
	local eggs = payload.eggs :: { string }
	local coins = tonumber(payload.coins) or 0
	local gems = tonumber(payload.gems) or 0
	local exp = tonumber(payload.exp) or 0
	local chamberCleared = tonumber(payload.chamberCleared) or rt.run.chamber
	local timeLeft = math.max(0, rt.run.chamberEndsAt - os.clock())
	for _, uid in ipairs(rt.run.playerOrder) do
		local plr = Players:GetPlayerByUserId(uid)
		if plr then
			payoutExtractedPlayer(
				plr,
				eggs,
				coins,
				gems,
				exp,
				chamberCleared,
				timeLeft,
				rt.run.isHourlyStorm
			)
		end
	end
	cleanupRun(rt)
end

local function handleSquadWiped(rt: ActiveRunRuntime, payload: { [string]: any })
	local chamberCleared = math.max(0, (tonumber(payload.chamber) or rt.run.chamber) - 1)
	local remotes = Remotes.ensureServer()
	for _, uid in ipairs(rt.run.playerOrder) do
		local plr = Players:GetPlayerByUserId(uid)
		if plr then
			remotes.ToastNotify:FireClient(
				plr,
				"VAULT WIPE! Unextracted run eggs lost! Returning to Hub...",
				{ 244, 63, 94 }
			)
			if completionHook then
				pcall(completionHook, plr, chamberCleared, false)
			end
		end
	end
	cleanupRun(rt)
end

local function spawnDecoyVisual(rt: ActiveRunRuntime, decoy: VaultHeistLogic.DecoyEntity)
	local model = Instance.new("Model")
	model.Name = decoy.id
	local body = makeBoxPart(
		model,
		"Root",
		Vector3.new(3, 5.2, 2),
		CFrame.new(fromVec3(decoy.pos) + Vector3.new(0, 2.6, 0)),
		Color3.fromRGB(56, 217, 245),
		Enum.Material.Neon,
		false
	)
	body.Transparency = 0.35
	model.PrimaryPart = body
	local ring = makeBoxPart(
		model,
		"Ring",
		Vector3.new(0.3, decoy.radius * 0.25, decoy.radius * 0.25),
		CFrame.new(fromVec3(decoy.pos)) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(56, 217, 245),
		Enum.Material.Neon,
		false
	)
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.72
	local bb = Instance.new("BillboardGui")
	bb.Adornee = body
	bb.Size = UDim2.fromOffset(120, 32)
	bb.StudsOffset = Vector3.new(0, 4, 0)
	bb.AlwaysOnTop = true
	bb.Parent = body
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextScaled = true
	lbl.TextColor3 = Color3.fromRGB(165, 243, 252)
	lbl.Text = "DECOY!"
	lbl.Parent = bb
	model.Parent = rt.refs.visualsFolder
	rt.decoyVisuals[decoy.id] = model
end

local function applyTelegraphVisual(rt: ActiveRunRuntime, payload: { [string]: any })
	if rt.telegraphPart then
		rt.telegraphPart:Destroy()
	end
	local origin = fromVec3(payload.origin)
	local dir = fromVec3(payload.dir)
	local range = tonumber(payload.range) or 22
	local radius = tonumber(payload.radius) or 11
	local mid = origin + dir * (range * 0.5)
	local yPos = rt.refs.centerPos.Y + 2.2
	local p = makeBoxPart(
		rt.refs.visualsFolder,
		"BossTelegraphZone",
		Vector3.new(radius * 1.4, 0.35, range),
		CFrame.lookAt(
			Vector3.new(mid.X, yPos, mid.Z),
			Vector3.new(mid.X + dir.X, yPos, mid.Z + dir.Z)
		),
		Color3.fromRGB(244, 63, 94),
		Enum.Material.Neon,
		false
	)
	p.Transparency = 0.42
	rt.telegraphPart = p
end

local function applyDashImpulseToPlayer(player: Player, dirVec: Vector3, distance: number)
	local hrp = getPlayerHRP(player)
	if not hrp then
		return
	end
	local att = Instance.new("Attachment")
	att.Parent = hrp
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.MaxForce = hrp.AssemblyMass * workspace.Gravity * 35
	lv.VectorVelocity = Vector3.new(dirVec.X * (distance / 0.25), 8, dirVec.Z * (distance / 0.25))
	lv.Parent = hrp
	task.delay(0.25, function()
		lv:Destroy()
		att:Destroy()
	end)
end

local function clearTelegraphVisual(rt: ActiveRunRuntime)
	if rt.telegraphPart then
		rt.telegraphPart:Destroy()
		rt.telegraphPart = nil
	end
end

local handleSingleRunEvent: (ActiveRunRuntime, VaultHeistLogic.VaultEvent) -> boolean
local processRunEvents: (ActiveRunRuntime, { VaultHeistLogic.VaultEvent }) -> boolean

local function tryPerformGrabEgg(player: Player, rt: ActiveRunRuntime)
	local hrp = getPlayerHRP(player)
	if not hrp then
		return
	end
	local ok, _, ev = VaultHeistLogic.tryGrabEgg(
		rt.run,
		player.UserId,
		toVec3(hrp.Position),
		toVec3(rt.refs.pedestal.Position),
		os.clock(),
		math.random()
	)
	if ok then
		clearDroppedVisual(rt)
		updatePedestalVisuals(rt)
		attachCarrierVisual(rt, player.UserId, rt.run.carryingEggId or "")
		setPlayerCarryAttributes(player, rt)
		processRunEvents(rt, ev)
		syncRunPlayers(rt)
	end
end

local function spawnDroppedVisual(rt: ActiveRunRuntime, eggId: string, pos: Vector3)
	clearDroppedVisual(rt)
	local vis = ProceduralModels.createEggVisual(eggId, rt.run.isHourlyStorm)
	vis.Name = "DroppedVaultEgg"
	vis:PivotTo(CFrame.new(pos + Vector3.new(0, 1.8, 0)))
	vis.Parent = rt.refs.visualsFolder
	if vis.PrimaryPart then
		local p = Instance.new("ProximityPrompt")
		p.ActionText = "Pick Up Vault Egg!"
		p.ObjectText = "Heavy Egg"
		p.HoldDuration = 0
		p.MaxActivationDistance = 12
		p.RequiresLineOfSight = false
		p.Parent = vis.PrimaryPart
		p.Triggered:Connect(function(plr: Player)
			if runByUserId[plr.UserId] == rt then
				tryPerformGrabEgg(plr, rt)
			end
		end)
		rt.droppedPrompt = p
	end
	rt.droppedEggVisual = vis
end

local function handleOrbOrCombatEvent(
	rt: ActiveRunRuntime,
	kind: string,
	payload: { [string]: any }
)
	if kind == "DecoySpawned" then
		spawnDecoyVisual(rt, payload.decoy)
		table.insert(
			rt.pendingEvents,
			{ kind = kind, pos = fromVec3(payload.decoy.pos), label = "DECOY!" }
		)
	elseif kind == "FreezeBurst" then
		clearTelegraphVisual(rt)
		table.insert(
			rt.pendingEvents,
			{ kind = kind, pos = fromVec3(payload.pos), label = "FROZEN!" }
		)
		if juiceHook and payload.hitBoss then
			pcall(
				juiceHook,
				"BossHit",
				fromVec3(payload.pos),
				payload.damage,
				"FROZEN!",
				{ 96, 165, 250 }
			)
		end
	elseif kind == "DashImpulse" then
		local plr = Players:GetPlayerByUserId(tonumber(payload.userId) or 0)
		if plr then
			applyDashImpulseToPlayer(plr, fromVec3(payload.dir), tonumber(payload.distance) or 28)
			setPlayerCarryAttributes(plr, rt)
		end
		table.insert(rt.pendingEvents, { kind = kind, label = "DASH BOOST!" })
	elseif kind == "SoloDroneRevive" then
		local plr = Players:GetPlayerByUserId(tonumber(payload.userId) or 0)
		if plr then
			Remotes.ensureServer().ToastNotify
				:FireClient(plr, "RESCUE DRONE ACTIVATED! (1/1 Solo Revive Used)", { 56, 217, 245 })
		end
	end
end

handleSingleRunEvent = function(rt: ActiveRunRuntime, ev: VaultHeistLogic.VaultEvent): boolean
	local kind = ev.kind
	local payload = ev.payload
	if kind == "HeistExtracted" then
		handleExtractionCompleted(rt, payload)
		return true
	elseif kind == "SquadWiped" then
		handleSquadWiped(rt, payload)
		return true
	elseif kind == "ChamberAdvanced" then
		clearDroppedVisual(rt)
		for uid in pairs(rt.carrierVisuals) do
			clearCarrierVisual(rt, uid)
		end
		buildBossVisualModel(rt)
		updatePedestalVisuals(rt)
	elseif kind == "BossTelegraph" then
		applyTelegraphVisual(rt, payload)
	elseif kind == "BossLunge" or kind == "VoteStarted" then
		clearTelegraphVisual(rt)
	elseif kind == "EggDropped" then
		clearCarrierVisual(rt, tonumber(payload.userId) or 0)
		spawnDroppedVisual(rt, tostring(payload.eggId or ""), fromVec3(payload.pos))
	else
		handleOrbOrCombatEvent(rt, kind, payload)
	end
	return false
end

processRunEvents = function(rt: ActiveRunRuntime, events: { VaultHeistLogic.VaultEvent }): boolean
	for _, ev in ipairs(events) do
		if handleSingleRunEvent(rt, ev) then
			return true
		end
	end
	if #events > 0 then
		rt.dirtySync = true
	end
	return false
end

local function enterPlayerIntoVault(player: Player, rt: ActiveRunRuntime)
	runByUserId[player.UserId] = rt
	player:SetAttribute("Zone", "VaultHeist")
	player:SetAttribute("ActiveBiome", "")
	setPlayerCarryAttributes(player, rt)
	local offsetAngle = (#rt.run.playerOrder - 1) * 1.3
	local padOff = Vector3.new(math.cos(offsetAngle) * 4, 0, math.sin(offsetAngle) * 4)
	PlotService.teleportCharacter(player, rt.refs.vaultSpawn.CFrame + padOff)
	local mut = VaultHeistConfigs.getMutator(rt.run.mutatorId)
	Remotes.ensureServer().ToastNotify:FireClient(
		player,
		`CHAMBER {rt.run.chamber} • Mutator: {mut.displayName}! Grab the Egg & Escape!`,
		mut.accentColor
	)
	syncPlayerState(player)
end

local function bindPedestalPromptForRun(rt: ActiveRunRuntime)
	local prompt = ensurePedestalPrompt(rt.refs.pedestal)
	rt.refs.pedestalPrompt = prompt
	prompt.Triggered:Connect(function(plr: Player)
		if runByUserId[plr.UserId] == rt then
			tryPerformGrabEgg(plr, rt)
		end
	end)
end

local function createRunRuntime(
	run: VaultHeistLogic.VaultRunState,
	refs: VaultArenaRefs
): ActiveRunRuntime
	return {
		run = run,
		refs = refs,
		bossModel = nil,
		bossHead = nil,
		bossHpFill = nil,
		bossStateLabel = nil,
		telegraphPart = nil,
		stunIcePart = nil,
		pedestalEggVisual = nil,
		pedestalBeam = nil,
		droppedEggVisual = nil,
		droppedPrompt = nil,
		carrierVisuals = {},
		decoyVisuals = {},
		downedBillboards = {},
		lastSyncAt = 0,
		dirtySync = true,
		pendingEvents = {},
	}
end

local function notifyPartyMatesInHub(starter: Player, partyId: string)
	if partyId == "" then
		return
	end
	local remotes = Remotes.ensureServer()
	for _, other in ipairs(Players:GetPlayers()) do
		if
			other ~= starter
			and getPlayerPartyId(other) == partyId
			and other:GetAttribute("Zone") == "Hub"
		then
			remotes.ToastNotify:FireClient(
				other,
				`{starter.DisplayName} started Vault Heist! Click VAULT HEIST to join!`,
				{ 56, 217, 245 }
			)
		end
	end
end

local function buildPlayerSeed(
	player: Player,
	profile: EconomyLogic.PlayerProfile
): VaultHeistLogic.PlayerSeed
	return {
		userId = player.UserId,
		maxHP = tonumber(player:GetAttribute("MaxHP")) or 100,
		orbLevels = VaultHeistLogic.ensureOrbLevels(profile),
	}
end

function VaultHeistService.startRunForPlayer(player: Player)
	if player:GetAttribute("Zone") == "LockedBossPvP" or runByUserId[player.UserId] ~= nil then
		return
	end
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	local partyId = getPlayerPartyId(player)
	local groupKey = VaultHeistLogic.resolveJoinGroupKey(player.UserId, partyId)
	local seed = buildPlayerSeed(player, profile)
	local existing = runByGroupKey[groupKey]
	if
		existing
		and existing.run.phase == "Active"
		and VaultHeistLogic.addPlayerToRun(existing.run, seed)
	then
		enterPlayerIntoVault(player, existing)
		syncRunPlayers(existing)
		return
	end
	nextRunSeq += 1
	local refs = allocateArenaRefs(reserveNextSlot())
	local isStorm = VaultHeistLogic.isHourlyVaultStormActive(os.time())
	local run = VaultHeistLogic.createRun({
		runId = `vh_{nextRunSeq}`,
		groupKey = groupKey,
		chamber = 1,
		mutatorId = VaultHeistLogic.pickChamberMutator(1, isStorm, math.random()),
		isHourlyStorm = isStorm,
		now = os.clock(),
		bossSpawnPos = toVec3(refs.bossSpawn.Position + Vector3.new(0, 4.5, 0)),
		players = { seed },
	})
	local rt = createRunRuntime(run, refs)
	activeRunsById[run.runId] = rt
	runByGroupKey[groupKey] = rt
	bindPedestalPromptForRun(rt)
	buildBossVisualModel(rt)
	updatePedestalVisuals(rt)
	enterPlayerIntoVault(player, rt)
	notifyPartyMatesInHub(player, partyId)
end

local function computeOrbImpactPoint(
	rt: ActiveRunRuntime,
	origin: Vector3,
	dir: Vector3,
	orbId: string
): Vector3
	if orbId == "DashBomb" then
		return origin
	end
	local bossPos = fromVec3(rt.run.boss.pos)
	local flatOrigin = Vector3.new(origin.X, rt.refs.centerPos.Y + 2.5, origin.Z)
	local flatDir = Vector3.new(dir.X, 0, dir.Z)
	local unitDir = if flatDir.Magnitude > 1e-4 then flatDir.Unit else Vector3.zAxis
	local toBoss = bossPos - flatOrigin
	local proj = toBoss:Dot(unitDir)
	if proj > 4 and proj <= 36 and (toBoss - unitDir * proj).Magnitude <= 12 then
		return Vector3.new(bossPos.X, rt.refs.centerPos.Y + 2.5, bossPos.Z)
	end
	local rawTarget = flatOrigin + unitDir * 24
	return Vector3.new(
		math.clamp(
			rawTarget.X,
			rt.refs.centerPos.X - rt.refs.halfExtent,
			rt.refs.centerPos.X + rt.refs.halfExtent
		),
		rt.refs.centerPos.Y + 2.5,
		math.clamp(
			rawTarget.Z,
			rt.refs.centerPos.Z - rt.refs.halfExtent,
			rt.refs.centerPos.Z + rt.refs.halfExtent
		)
	)
end

local function handleThrowOrbAction(
	player: Player,
	rt: ActiveRunRuntime,
	payload: { [string]: any }
)
	local orbId = payload.orbId
	local aimDir = payload.aimDir
	local hrp = getPlayerHRP(player)
	if type(orbId) ~= "string" or typeof(aimDir) ~= "Vector3" or not hrp then
		return
	end
	local origin = hrp.Position + Vector3.new(0, 1.5, 0)
	local impact = computeOrbImpactPoint(rt, origin, aimDir, orbId)
	local ok, reason, events = VaultHeistLogic.executeOrbAction(
		rt.run,
		player.UserId,
		orbId,
		toVec3(origin),
		toVec3(aimDir),
		toVec3(impact),
		os.clock(),
		toVec3(rt.refs.centerPos),
		rt.refs.halfExtent
	)
	if not ok then
		if reason == "OrbLocked" then
			Remotes.ensureServer().ToastNotify
				:FireClient(player, `Unlock {orbId} Orb with Coins first!`, { 250, 204, 21 })
		end
		return
	end
	processRunEvents(rt, events)
	syncRunPlayers(rt)
end

local function handleLeaveOrDeparture(player: Player)
	local rt = runByUserId[player.UserId]
	if not rt then
		return
	end
	runByUserId[player.UserId] = nil
	clearCarrierVisual(rt, player.UserId)
	setPlayerCarryAttributes(player, nil)
	local hrp, hum = getPlayerHRP(player)
	if hum then
		hum.PlatformStand = false
	end
	local dropPos = if hrp then toVec3(hrp.Position) else nil
	local events = VaultHeistLogic.removePlayerFromRun(rt.run, player.UserId, dropPos, os.clock())
	if not processRunEvents(rt, events) then
		updatePedestalVisuals(rt)
		syncRunPlayers(rt)
	end
	if player.Parent == Players and player:GetAttribute("Zone") == "VaultHeist" then
		PlotService.teleportToHubPlot(player)
	end
	syncPlayerState(player)
end

local function handleUpgradeOrbAction(player: Player, orbId: any)
	local profile = DataService.getProfile(player)
	if not profile or type(orbId) ~= "string" then
		return
	end
	local res = VaultHeistLogic.upgradeOrb(profile, orbId)
	local remotes = Remotes.ensureServer()
	if res.ok and res.data then
		local rt = runByUserId[player.UserId]
		if rt and rt.run.players[player.UserId] then
			rt.run.players[player.UserId].orbLevels[orbId] = res.data.newLevel
		end
		DataService.syncToClient(player)
		syncPlayerState(player)
		remotes.ToastNotify:FireClient(
			player,
			`{orbId} Orb upgraded to Lv {res.data.newLevel}!`,
			{ 74, 222, 128 }
		)
	else
		remotes.ToastNotify:FireClient(
			player,
			`Orb upgrade failed: {res.reason or "Unavailable"}`,
			{ 244, 63, 94 }
		)
	end
end

local function isActionRateLimited(userId: number): boolean
	local now = os.clock()
	if now - (actionDebounce[userId] or 0) < ACTION_DEBOUNCE_SEC then
		return true
	end
	actionDebounce[userId] = now
	return false
end

local function onVaultHeistAction(player: Player, payload: any)
	if type(payload) ~= "table" or type(payload.action) ~= "string" then
		return
	end
	if isActionRateLimited(player.UserId) then
		return
	end
	local action = payload.action
	if action == "Start" then
		VaultHeistService.startRunForPlayer(player)
		return
	elseif action == "UpgradeOrb" then
		handleUpgradeOrbAction(player, payload.orbId)
		return
	elseif action == "Leave" then
		handleLeaveOrDeparture(player)
		return
	end
	local rt = runByUserId[player.UserId]
	if not rt then
		return
	end
	local hrp = getPlayerHRP(player)
	if action == "ThrowOrb" then
		handleThrowOrbAction(player, rt, payload)
	elseif action == "GrabEgg" then
		tryPerformGrabEgg(player, rt)
	elseif action == "DropEgg" and hrp then
		local ok, ev =
			VaultHeistLogic.dropEgg(rt.run, player.UserId, toVec3(hrp.Position), os.clock())
		if ok then
			setPlayerCarryAttributes(player, rt)
			processRunEvents(rt, ev)
			syncRunPlayers(rt)
		end
	elseif action == "VoteExtract" or action == "VoteDive" then
		local choice: "Extract" | "Dive" = if action == "VoteDive" then "Dive" else "Extract"
		local ok, ev = VaultHeistLogic.castExtractionVote(
			rt.run,
			player.UserId,
			choice,
			os.clock(),
			toVec3(rt.refs.bossSpawn.Position + Vector3.new(0, 4.5, 0)),
			math.random()
		)
		if ok and not processRunEvents(rt, ev) then
			syncRunPlayers(rt)
		end
	end
end

local function syncBossVisuals(rt: ActiveRunRuntime)
	if not rt.bossModel or not rt.bossHead then
		return
	end
	rt.bossModel:PivotTo(
		CFrame.new(fromVec3(rt.run.boss.pos)) * CFrame.Angles(0, rt.run.boss.facingYaw, 0)
	)
	if rt.bossHpFill then
		local frac = math.clamp(rt.run.boss.hp / math.max(1, rt.run.boss.maxHP), 0, 1)
		rt.bossHpFill.Size = UDim2.fromScale(frac, 1)
	end
	if rt.bossStateLabel then
		local ch = VaultHeistConfigs.getChamber(rt.run.chamber)
		rt.bossStateLabel.Text = `{ch.bossName} [{rt.run.boss.state}]`
	end
	local stunned = rt.run.boss.state == "STUNNED"
	if stunned and not rt.stunIcePart then
		local ice = makeBoxPart(
			rt.refs.visualsFolder,
			"BossCryoBlock",
			Vector3.new(8, 10, 8),
			rt.bossHead.CFrame,
			Color3.fromRGB(125, 249, 255),
			Enum.Material.Ice,
			false
		)
		ice.Transparency = 0.45
		rt.stunIcePart = ice
	elseif not stunned and rt.stunIcePart then
		rt.stunIcePart:Destroy()
		rt.stunIcePart = nil
	elseif rt.stunIcePart then
		rt.stunIcePart.CFrame = rt.bossHead.CFrame
	end
end

local function syncLaserAndDecoyVisuals(rt: ActiveRunRuntime, now: number)
	local paused = now < rt.run.laserPausedUntil
	local mut = VaultHeistConfigs.getMutator(rt.run.mutatorId)
	local sweep = if rt.run.mutatorId == "LaserSweep"
		then math.sin(now * 2.1 * mut.laserSpeedMult) * 18
		else 0
	for i, part in ipairs(rt.refs.laserParts) do
		local orig = rt.refs.laserOrigCFs[i]
		if part.Parent and orig then
			part.CFrame = orig * CFrame.new(sweep, 0, 0)
			part.Color = if paused
				then Color3.fromRGB(100, 235, 255)
				else Color3.fromRGB(255, 45, 95)
			part.Transparency = if paused then 0.72 else 0.16
		end
	end
	local activeDecoys: { [string]: boolean } = {}
	for _, d in ipairs(rt.run.decoys) do
		activeDecoys[d.id] = true
	end
	for id, model in pairs(rt.decoyVisuals) do
		if not activeDecoys[id] then
			model:Destroy()
			rt.decoyVisuals[id] = nil
		end
	end
end

local function updateDownedBillboard(
	rt: ActiveRunRuntime,
	uid: number,
	hrp: BasePart,
	downed: boolean
)
	local existing = rt.downedBillboards[uid]
	if downed and not existing then
		local bb = Instance.new("BillboardGui")
		bb.Adornee = hrp
		bb.Size = UDim2.fromOffset(180, 40)
		bb.StudsOffset = Vector3.new(0, 4.5, 0)
		bb.AlwaysOnTop = true
		bb.Parent = hrp
		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.Font = Enum.Font.FredokaOne
		lbl.TextScaled = true
		lbl.TextColor3 = Color3.fromRGB(255, 96, 96)
		lbl.TextStrokeTransparency = 0.2
		lbl.Text = "DOWNED! REVIVE!"
		lbl.Parent = bb
		rt.downedBillboards[uid] = bb
	elseif not downed and existing then
		existing:Destroy()
		rt.downedBillboards[uid] = nil
	end
end

local function checkPlayerHazardsAndExtraction(
	rt: ActiveRunRuntime,
	uid: number,
	hrp: BasePart,
	pos: VaultHeistLogic.Vec3,
	now: number
): boolean
	for _, laserPart in ipairs(rt.refs.laserParts) do
		local rel = laserPart.CFrame:PointToObjectSpace(hrp.Position)
		local sz = laserPart.Size * 0.5 + Vector3.new(1.5, 2.5, 1.5)
		if math.abs(rel.X) <= sz.X and math.abs(rel.Y) <= sz.Y and math.abs(rel.Z) <= sz.Z then
			local lEv = VaultHeistLogic.onTouchLaserGate(rt.run, uid, now, pos)
			if processRunEvents(rt, lEv) then
				return true
			end
		end
	end
	if rt.run.carrierUserId == uid then
		if (hrp.Position - rt.refs.extractionPad.Position).Magnitude <= 10.5 then
			local _, vEv = VaultHeistLogic.triggerExtractionVote(rt.run, uid, now)
			if processRunEvents(rt, vEv) then
				return true
			end
		end
	end
	return false
end

local function stepRunPhysicsAndInteractions(rt: ActiveRunRuntime, dt: number, now: number)
	local posMap: { [number]: VaultHeistLogic.Vec3 } = {}
	for _, uid in ipairs(rt.run.playerOrder) do
		local plr = Players:GetPlayerByUserId(uid)
		local hrp: BasePart? = nil
		local hum: Humanoid? = nil
		if plr then
			hrp, hum = getPlayerHRP(plr)
		end
		local ps = rt.run.players[uid]
		if plr and hrp and ps then
			local pVec = toVec3(hrp.Position)
			posMap[uid] = pVec
			setPlayerCarryAttributes(plr, rt)
			updateDownedBillboard(rt, uid, hrp, ps.downed)
			if hum then
				hum.PlatformStand = ps.downed
				if hum.Health > 0 then
					hum.Health = math.max(1, math.min(hum.MaxHealth, ps.hp))
				end
			end
			if rt.run.phase == "Active" and not ps.downed then
				if checkPlayerHazardsAndExtraction(rt, uid, hrp, pVec, now) then
					return
				end
			end
		end
	end
	local events = VaultHeistLogic.stepRun(
		rt.run,
		dt,
		now,
		rt.refs.patrolNodes,
		posMap,
		toVec3(rt.refs.centerPos),
		rt.refs.halfExtent,
		toVec3(rt.refs.bossSpawn.Position + Vector3.new(0, 4.5, 0)),
		math.random()
	)
	if processRunEvents(rt, events) then
		return
	end
	syncBossVisuals(rt)
	syncLaserAndDecoyVisuals(rt, now)
	if rt.dirtySync or (now - rt.lastSyncAt) >= 0.12 then
		syncRunPlayers(rt)
	end
end

local function wirePortalInstance(inst: Instance)
	local part = resolveBasePart(inst)
	if not part or part:GetAttribute("VaultPortalWired") == true then
		return
	end
	part:SetAttribute("VaultPortalWired", true)
	part.Touched:Connect(function(hit: BasePart)
		local plr = Players:GetPlayerFromCharacter(hit.Parent)
		if not plr then
			return
		end
		local now = os.clock()
		if (portalDebounce[plr.UserId] or 0) + 1.5 > now then
			return
		end
		portalDebounce[plr.UserId] = now
		VaultHeistService.startRunForPlayer(plr)
	end)
	local p = part:FindFirstChildOfClass("ProximityPrompt") or Instance.new("ProximityPrompt")
	p.ActionText = "Enter Vault Heist"
	p.ObjectText = "0s Instant Co-Op"
	p.HoldDuration = 0
	p.MaxActivationDistance = 14
	p.RequiresLineOfSight = false
	p.Parent = part
	p.Triggered:Connect(VaultHeistService.startRunForPlayer)
end

local function discoverPortals()
	for _, tagged in ipairs(CollectionService:GetTagged("VaultHeistPortal")) do
		wirePortalInstance(tagged)
	end
	local root = PlotService.getMapRoot()
	local hub = if root then root:FindFirstChild("Hub") else nil
	local portals = if hub then hub:FindFirstChild("Portals") else nil
	local portal = if portals then portals:FindFirstChild("Portal_VaultHeist") else nil
	if portal then
		wirePortalInstance(portal)
	end
end

local function bindPlayerListeners(player: Player)
	player:GetAttributeChangedSignal("Zone"):Connect(function()
		if runByUserId[player.UserId] and player:GetAttribute("Zone") ~= "VaultHeist" then
			handleLeaveOrDeparture(player)
		end
	end)
end

function VaultHeistService.setAnnouncementHook(cb: (
	Player,
	string,
	string,
	{ number },
	boolean
) -> ())
	announcementHook = cb
end

function VaultHeistService.setJuiceHook(cb: (string, Vector3?, number?, string?, { number }?) -> ())
	juiceHook = cb
end

function VaultHeistService.setCompletionHook(cb: (Player, number, boolean) -> ())
	completionHook = cb
end

function VaultHeistService.init()
	ensureRemote("VaultHeistAction")
	ensureRemote("VaultHeistSync")
end

function VaultHeistService.start()
	discoverPortals()
	CollectionService:GetInstanceAddedSignal("VaultHeistPortal"):Connect(wirePortalInstance)
	ensureRemote("VaultHeistAction").OnServerEvent:Connect(onVaultHeistAction)

	DataService.onProfileLoaded(function(player: Player, profile: EconomyLogic.PlayerProfile)
		VaultHeistLogic.ensureOrbLevels(profile)
		syncPlayerState(player)
	end)
	Players.PlayerAdded:Connect(bindPlayerListeners)
	for _, plr in ipairs(Players:GetPlayers()) do
		bindPlayerListeners(plr)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		portalDebounce[player.UserId] = nil
		actionDebounce[player.UserId] = nil
		handleLeaveOrDeparture(player)
	end)
	RunService.Heartbeat:Connect(function(rawDt: number)
		local dt = math.min(rawDt, 0.08)
		local now = os.clock()
		local runs: { ActiveRunRuntime } = {}
		for _, rt in pairs(activeRunsById) do
			table.insert(runs, rt)
		end
		for _, rt in ipairs(runs) do
			if activeRunsById[rt.run.runId] == rt then
				stepRunPhysicsAndInteractions(rt, dt, now)
			end
		end
	end)
end

return VaultHeistService
