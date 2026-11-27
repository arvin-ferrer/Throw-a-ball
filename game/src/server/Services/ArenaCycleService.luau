--!strict
--[[
	ArenaCycleService.luau
	Server-authoritative 3-Phase Biome Arena FSM + 5-Minute Overcharged Global Scheduler.
	Manages Opt-In, Locked Boss Room teleports, Full Heal + 3s grace, Server-Owned 5.0s Egg Claim,
	75s Sudden Death Storm Ring, and anti-desync PvP immunity guards.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BiomeConfigs = require(Shared.Configs.BiomeConfigs)
local EconomyConfigs = require(Shared.Configs.EconomyConfigs)
local EconomyLogic = require(Shared.Utils.EconomyLogic)
local ArenaCycleLogic = require(Shared.Utils.ArenaCycleLogic)
local MathUtil = require(Shared.Utils.MathUtil)
local ProceduralModels = require(Shared.Utils.ProceduralModels)
local Remotes = require(Shared.Net.Remotes)

local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local ViralSocialService = require(script.Parent.ViralSocialService)

type ArenaRefs = {
	biomeId: string,
	arenaFolder: Instance,
	bossSpawn: BasePart,
	eggPedestal: BasePart,
	eggPrompt: ProximityPrompt?,
	suddenDeathRing: BasePart?,
	roomVolume: BasePart?,
	arenaFloor: BasePart?,
	optInSpawns: { BasePart },
	eggVisual: Model?,
}

local ROOM_VOLUME_NAMES = {
	"RoomVolume",
	"ArenaVolume",
	"RoomBounds",
	"ArenaBounds",
	"BossRoomVolume",
}

local ArenaCycleService = {}

local biomeStates: { [string]: ArenaCycleLogic.BiomeArenaState } = {}
local overchargedClock: ArenaCycleLogic.OverchargedClock =
	ArenaCycleLogic.createOverchargedClock(os.clock())
local arenaRefs: { [string]: ArenaRefs } = {}
local playerArenaBiome: { [number]: string } = {}
local paidParticipantsByBiome: { [string]: { [number]: boolean } } = {}
local spawnBossCallback: ((string, BasePart, number, boolean) -> ())? = nil
local clearBossCallback: ((string) -> ())? = nil
local telemetryCallback: ((string, { [string]: any }) -> ())? = nil

local function findArenaRoomVolume(arena: Instance): BasePart?
	for _, name in ipairs(ROOM_VOLUME_NAMES) do
		local found = arena:FindFirstChild(name)
		if found and found:IsA("BasePart") then
			return found
		end
	end
	for _, child in ipairs(arena:GetChildren()) do
		if child:IsA("BasePart") and child:GetAttribute("IsRoomVolume") == true then
			return child
		end
	end
	return nil
end

local function configureArenaPrompt(eggPed: BasePart): ProximityPrompt?
	local prompt = eggPed:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		local created = Instance.new("ProximityPrompt")
		created.Name = "Prompt"
		created.Parent = eggPed
		prompt = created
	end
	if prompt then
		prompt.ActionText = "Hold 5s to Claim Egg"
		prompt.ObjectText = "Boss Egg"
		prompt.HoldDuration = 0.05
		prompt.MaxActivationDistance = BiomeConfigs.EGG_CLAIM_RADIUS
		prompt.Enabled = false
	end
	return prompt
end

local function discoverSingleArena(biomesFolder: Instance, biomeId: string)
	local bFolder = biomesFolder:FindFirstChild(biomeId)
	local arena = if bFolder then bFolder:FindFirstChild("BossPvPArena") else nil
	if not arena then
		return
	end
	local bossSpawn = arena:FindFirstChild("BossSpawn")
	local eggPed = arena:FindFirstChild("EggClaimPedestal")
	if
		not bossSpawn
		or not bossSpawn:IsA("BasePart")
		or not eggPed
		or not eggPed:IsA("BasePart")
	then
		return
	end
	local sdRing = arena:FindFirstChild("SuddenDeathRingMarker")
	local arenaFloor = arena:FindFirstChild("ArenaFloor")
	local spawns: { BasePart } = {}
	for _, child in ipairs(arena:GetChildren()) do
		if child:IsA("BasePart") and string.find(child.Name, "OptInSpawn_") then
			table.insert(spawns, child)
		end
	end
	table.sort(spawns, function(a, b)
		return a.Name < b.Name
	end)
	arenaRefs[biomeId] = {
		biomeId = biomeId,
		arenaFolder = arena,
		bossSpawn = bossSpawn,
		eggPedestal = eggPed,
		eggPrompt = configureArenaPrompt(eggPed),
		suddenDeathRing = if sdRing and sdRing:IsA("BasePart") then sdRing else nil,
		roomVolume = findArenaRoomVolume(arena),
		arenaFloor = if arenaFloor and arenaFloor:IsA("BasePart") then arenaFloor else nil,
		optInSpawns = spawns,
		eggVisual = nil,
	}
end

local function discoverArenas()
	local mapRoot = PlotService.getMapRoot()
	local biomesFolder = if mapRoot then mapRoot:FindFirstChild("Biomes") else nil
	if not biomesFolder then
		return
	end
	for _, biomeId in ipairs(BiomeConfigs.ORDERED_MVP_BIOMES) do
		discoverSingleArena(biomesFolder, biomeId)
	end
end

local function setEggVisual(biomeId: string, eggId: string?, isOvercharged: boolean)
	local ref = arenaRefs[biomeId]
	if not ref then
		return
	end
	if ref.eggVisual then
		ref.eggVisual:Destroy()
		ref.eggVisual = nil
	end
	if eggId then
		local vis = ProceduralModels.createEggVisual(eggId, isOvercharged)
		vis:PivotTo(ref.eggPedestal.CFrame * CFrame.new(0, 3.8, 0))
		vis.Parent = ref.arenaFolder
		ref.eggVisual = vis
		if ref.eggPrompt then
			ref.eggPrompt.Enabled = true
		end
	elseif ref.eggPrompt then
		ref.eggPrompt.Enabled = false
	end
end

local function fullHealPlayer(player: Player)
	local char = player.Character
	local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
	local profile = DataService.getProfile(player)
	if hum and profile then
		local maxHP = EconomyConfigs.getPlayerMaxHP(profile.level)
		hum.MaxHealth = maxHP
		hum.Health = maxHP
	end
end

local function payoutSingleParticipant(
	userId: number,
	bossCfg: any,
	winnerId: number?,
	eggId: string?
)
	local plr = Players:GetPlayerByUserId(userId)
	local profile = DataService.getProfileByUserId(userId)
	if not plr or not profile then
		return
	end
	local passMult = if DataService.hasPass(plr, "Pass_DoubleCoinsExp") then 2 else 1
	local friendMult = ViralSocialService.getFriendBonusMultiplier(plr)
	local mult = passMult * friendMult
	local coins = math.floor(bossCfg.participationCoins * mult + 0.5)
	local exp = math.floor(bossCfg.participationExp * mult + 0.5)
	local gems = bossCfg.participationGems
	local wonEgg = winnerId == userId and eggId ~= nil
	local remotes = Remotes.ensureServer()
	if wonEgg and eggId then
		coins += math.floor(bossCfg.winnerBonusCoins * mult + 0.5)
		gems += bossCfg.winnerBonusGems
		profile.eggs[eggId] = (profile.eggs[eggId] or 0) + 1
		remotes.ToastNotify:FireClient(
			plr,
			`BOSS EGG WON! +{MathUtil.formatNumber(coins)} Coins, +{gems} Boss Gems & {eggId}!`,
			{ 250, 204, 21 }
		)
	else
		remotes.ToastNotify:FireClient(
			plr,
			`Boss Brawl Payout: +{MathUtil.formatNumber(coins)} Coins, +{exp} EXP, +{gems} Boss Gems!`,
			{ 56, 189, 248 }
		)
	end
	profile.coins += coins
	profile.bossGems += gems
	EconomyLogic.addExp(profile, exp)
	DataService.syncToClient(plr)
	if telemetryCallback then
		telemetryCallback("ArenaParticipation", { userId = userId, value = 1 })
		if wonEgg then
			telemetryCallback("ArenaWin", { userId = userId, value = 1 })
		end
	end
end

local function awardParticipation(
	biomeId: string,
	userIds: { number },
	winnerId: number?,
	eggId: string?
)
	local bossCfg = BiomeConfigs.getBossForBiome(biomeId)
	if not bossCfg then
		return
	end
	local paidMap = paidParticipantsByBiome[biomeId]
	if not paidMap then
		paidMap = {}
		paidParticipantsByBiome[biomeId] = paidMap
	end
	for _, userId in ipairs(userIds) do
		if not paidMap[userId] then
			paidMap[userId] = true
			payoutSingleParticipant(userId, bossCfg, winnerId, eggId)
		end
	end
end

local function onBossPhaseAdmitted(biomeId: string, ref: ArenaRefs, payload: { [string]: any })
	paidParticipantsByBiome[biomeId] = {}
	local playersList: { number } = payload.players or {}
	for i, uid in ipairs(playersList) do
		local plr = Players:GetPlayerByUserId(uid)
		local hum = if plr and plr.Character
			then plr.Character:FindFirstChildOfClass("Humanoid")
			else nil
		local pad = if #ref.optInSpawns > 0
			then ref.optInSpawns[((i - 1) % #ref.optInSpawns) + 1]
			else nil
		if plr and hum and hum.Health > 0 and pad and not playerArenaBiome[uid] then
			playerArenaBiome[uid] = biomeId
			plr:SetAttribute("Zone", "LockedBossPvP")
			plr:SetAttribute("ActiveBiome", biomeId)
			fullHealPlayer(plr)
			PlotService.teleportCharacter(plr, pad.CFrame)
		else
			local st = biomeStates[biomeId]
			if st then
				ArenaCycleLogic.removePlayerFromArena(st, uid, os.clock(), "Unavailable")
			end
		end
	end
	if spawnBossCallback then
		spawnBossCallback(biomeId, ref.bossSpawn, payload.bossMaxHP, payload.isOvercharged == true)
	end
end

local function isPlayerZoneEligibleForOptIn(player: Player, biomeId: string): boolean
	if playerArenaBiome[player.UserId] ~= nil then
		return false
	end
	if player:GetAttribute("Zone") == "LockedBossPvP" then
		return false
	end
	local zone = tostring(player:GetAttribute("Zone") or "Hub")
	local activeBiome = tostring(player:GetAttribute("ActiveBiome") or "")
	return ArenaCycleLogic.isZoneEligibleForOptIn(zone, activeBiome, biomeId)
end

local function recordOptInOffers(biomeId: string)
	local st = biomeStates[biomeId]
	if not st or not telemetryCallback then
		return
	end
	for _, plr in ipairs(Players:GetPlayers()) do
		if isPlayerZoneEligibleForOptIn(plr, biomeId) then
			if ArenaCycleLogic.markOptInOffered(st, plr.UserId) then
				telemetryCallback("BossFightOffered", { userId = plr.UserId, value = 1 })
			end
		end
	end
end

local function emitOptInDecisions(decisions: any)
	if type(decisions) ~= "table" then
		return
	end
	for _, d in ipairs(decisions) do
		if telemetryCallback then
			local val = if d.optedIn then 1 else 0
			telemetryCallback("BossOptInDecision", { userId = d.userId, value = val })
			if d.optedIn then
				telemetryCallback("BossOptInAccepted", { userId = d.userId, value = 1 })
			end
		end
		if d.optedIn then
			local plr = Players:GetPlayerByUserId(d.userId)
			if plr then
				ViralSocialService.recordProgress(plr, "BossOptIn", 1)
			end
		end
	end
end

local function onPhaseChangedEvent(biomeId: string, ref: ArenaRefs?, payload: { [string]: any })
	local phase = payload.phase
	emitOptInDecisions(payload.optInDecisions)
	if phase == "OptIn_Window" then
		recordOptInOffers(biomeId)
	elseif phase == "Boss_Phase" and ref then
		onBossPhaseAdmitted(biomeId, ref, payload)
	elseif phase == "PvE_Open" then
		if payload.reason == "ScrambleTimeout" then
			awardParticipation(biomeId, payload.participants or {}, nil, nil)
		end
		paidParticipantsByBiome[biomeId] = {}
		setEggVisual(biomeId, nil, false)
		if clearBossCallback then
			clearBossCallback(biomeId)
		end
		for _, uid in ipairs(payload.returnPlayers or {}) do
			playerArenaBiome[uid] = nil
			local plr = Players:GetPlayerByUserId(uid)
			if plr then
				if payload.reason == "ScrambleTimeout" then
					Remotes.ensureServer().ToastNotify
						:FireClient(
							plr,
							"Egg Scramble timed out! Returning to PvE.",
							{ 248, 113, 113 }
						)
				end
				PlotService.teleportToBiomePvE(plr, biomeId)
			end
		end
	end
end

local function onBossDefeatedEvent(biomeId: string, payload: { [string]: any })
	local remotes = Remotes.ensureServer()
	local biome = BiomeConfigs.BIOMES[biomeId]
	local isOver = payload.isOvercharged == true
	local eggId = if isOver then biome.overchargedEggId else biome.standardEggId
	if clearBossCallback then
		clearBossCallback(biomeId)
	end
	setEggVisual(biomeId, eggId, isOver)
	for _, uid in ipairs(payload.survivors or {}) do
		local plr = Players:GetPlayerByUserId(uid)
		if plr then
			fullHealPlayer(plr)
			remotes.ToastNotify:FireClient(
				plr,
				"BOSS DEFEATED! Full Healed! 3s before Uncapped PvP Egg Scramble!",
				{ 250, 204, 21 }
			)
		end
	end
end

local function notifyEggClaimedSocial(biomeId: string, payload: { [string]: any }, ref: ArenaRefs?)
	local winner = Players:GetPlayerByUserId(payload.winnerId)
	if not winner then
		return
	end
	local bossCfg = BiomeConfigs.getBossForBiome(biomeId)
	local isOver = payload.isOvercharged == true
	local evType = if isOver then "OverchargedWin" else "BossWin"
	ViralSocialService.recordProgress(winner, evType, 1, {
		isOvercharged = isOver,
		bossName = if bossCfg then bossCfg.displayName else biomeId,
	})
	DataService.syncToClient(winner)
	local remotes = Remotes.ensureServer()
	remotes.CombatJuiceEvent:FireAllClients({
		kind = "EggClaim",
		worldPos = if ref then ref.eggPedestal.Position else nil,
		killerName = winner.DisplayName,
		label = `{winner.DisplayName} claimed {tostring(payload.eggId or "Boss Egg")}!`,
		accent = { 84, 242, 152 },
	})
	local prof = DataService.getProfile(winner)
	remotes.CombatJuiceEvent:FireAllClients({
		kind = "StreakUpdate",
		userId = winner.UserId,
		killerName = winner.DisplayName,
		streak = if prof then prof.winStreak else 0,
	})
end

local function onPlayerEliminatedEvent(biomeId: string, payload: { [string]: any })
	local uid = payload.userId
	playerArenaBiome[uid] = nil
	local plr = Players:GetPlayerByUserId(uid)
	if not plr then
		return
	end
	if payload.reason == "Died" then
		ViralSocialService.recordProgress(plr, "BossLoss", 1)
		DataService.syncToClient(plr)
		Remotes.ensureServer().CombatJuiceEvent:FireAllClients({
			kind = "StreakUpdate",
			userId = plr.UserId,
			killerName = plr.DisplayName,
			streak = 0,
		})
	end
	if payload.reason ~= "OutOfBounds" or payload.phase == "PvP_EggScramble" then
		awardParticipation(biomeId, { uid }, nil, nil)
	end
	if payload.reason ~= "OutOfBounds" or plr:GetAttribute("Zone") == "LockedBossPvP" then
		PlotService.teleportToBiomePvE(plr, biomeId)
	end
end

local function handleArenaEvents(events: { ArenaCycleLogic.ArenaEvent })
	local remotes = Remotes.ensureServer()
	for _, ev in ipairs(events) do
		local biomeId = ev.biomeId
		local ref = arenaRefs[biomeId]
		if ev.kind == "OverchargedGlobalAlert" then
			remotes.ToastNotify:FireAllClients(
				"⚡ 5-MINUTE OVERCHARGED BOSS EVENT! Overcharged Bosses spawned in ALL 3 Biomes!",
				{ 255, 72, 196 }
			)
		elseif ev.kind == "PhaseChanged" then
			onPhaseChangedEvent(biomeId, ref, ev.payload)
		elseif ev.kind == "BossDefeated" then
			onBossDefeatedEvent(biomeId, ev.payload)
		elseif ev.kind == "EggClaimed" then
			awardParticipation(
				biomeId,
				ev.payload.participants or {},
				ev.payload.winnerId,
				ev.payload.eggId
			)
			notifyEggClaimedSocial(biomeId, ev.payload, ref)
			if telemetryCallback then
				telemetryCallback("EggClaimed", {
					userId = ev.payload.winnerId,
					biomeId = biomeId,
					isOvercharged = ev.payload.isOvercharged,
				})
			end
		elseif ev.kind == "PlayerEliminated" then
			onPlayerEliminatedEvent(biomeId, ev.payload)
		elseif ev.kind == "ClaimCanceled" then
			local plr = Players:GetPlayerByUserId(ev.payload.userId)
			if plr then
				remotes.ToastNotify:FireClient(
					plr,
					`Egg Claim interrupted ({ev.payload.reason})!`,
					{ 239, 68, 68 }
				)
			end
		end
	end
end

local function updateWorldBoards(now: number)
	local overLeft = math.max(0, overchargedClock.nextEventAt - now)
	local clockText = `OVERCHARGED EVENT\n{MathUtil.formatClock(overLeft)}`
	for _, board in ipairs(CollectionService:GetTagged("OverchargedClockBoard")) do
		local lbl = board:FindFirstChildWhichIsA("TextLabel", true)
		if lbl then
			lbl.Text = clockText
		end
	end

	-- Count PvE players per biome & update PortalInfoBoard
	local pveCounts: { [string]: number } = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		local b = tostring(plr:GetAttribute("ActiveBiome") or "")
		if b ~= "" then
			pveCounts[b] = (pveCounts[b] or 0) + 1
		end
	end
	for _, board in ipairs(CollectionService:GetTagged("PortalInfoBoard")) do
		local model = board.Parent
		local biomeId = if model then tostring(model:GetAttribute("BiomeId") or "") else ""
		local st = biomeStates[biomeId]
		local lbl = board:FindFirstChildWhichIsA("TextLabel", true)
		if st and lbl then
			local left = math.max(0, st.phaseEndsAt - now)
			lbl.Text =
				`{st.phase} ({MathUtil.formatClock(left)}) • Players: {pveCounts[biomeId] or 0}`
		end
	end
end

local function broadcastArenaStates(now: number)
	local remotes = Remotes.ensureServer()
	local summary: { [string]: any } = {}
	for _, biomeId in ipairs(BiomeConfigs.ORDERED_MVP_BIOMES) do
		local st = biomeStates[biomeId]
		local qCount, qMaxPower = ArenaCycleLogic.getQueueSummary(st)
		summary[biomeId] = {
			phase = st.phase,
			timeRemaining = math.max(0, st.phaseEndsAt - now),
			isOvercharged = st.isOvercharged,
			queueCount = qCount,
			queueMaxPower = qMaxPower,
			bossHP = st.bossHP,
			bossMaxHP = st.bossMaxHP,
			pvpGraceRemaining = math.max(0, st.pvpStartedAt - now),
			claimerId = st.claim.claimerId,
			claimProgress = st.claim.progress,
			suddenDeathRadius = st.suddenDeathRadius,
		}
	end
	remotes.ArenaStateSync:FireAllClients({
		overchargedRemaining = math.max(0, overchargedClock.nextEventAt - now),
		biomes = summary,
	})
end

function ArenaCycleService.setBossHooks(
	onSpawn: (string, BasePart, number, boolean) -> (),
	onClear: (string) -> ()
)
	spawnBossCallback = onSpawn
	clearBossCallback = onClear
end

function ArenaCycleService.setTelemetryHook(cb: (string, { [string]: any }) -> ())
	telemetryCallback = cb
end

function ArenaCycleService.getBiomeState(biomeId: string): ArenaCycleLogic.BiomeArenaState?
	return biomeStates[biomeId]
end

function ArenaCycleService.getPlayerArenaBiome(userId: number): string?
	return playerArenaBiome[userId]
end

local function computePartHalfY(part: BasePart): number
	local cf = part.CFrame
	local sz = part.Size
	return 0.5
		* (
			math.abs(cf.XVector.Y) * sz.X
			+ math.abs(cf.YVector.Y) * sz.Y
			+ math.abs(cf.ZVector.Y) * sz.Z
		)
end

local function isInsideFloorPart(floor: BasePart, pos: Vector3): boolean
	local sz = floor.Size
	local floorTopY = floor.Position.Y + computePartHalfY(floor)
	local rel = floor.CFrame:PointToObjectSpace(pos)
	local isCyl = floor:IsA("Part") and floor.Shape == Enum.PartType.Cylinder
	if isCyl then
		if math.abs(floor.CFrame.XVector.Y) >= 0.7 then
			return ArenaCycleLogic.isInsideFloorFootprint(
				rel.Y,
				rel.Z,
				sz.Y,
				sz.Z,
				pos.Y,
				floorTopY,
				true,
				120
			)
		end
		local dx = pos.X - floor.Position.X
		local dz = pos.Z - floor.Position.Z
		local span = math.max(sz.X, sz.Z)
		return ArenaCycleLogic.isInsideFloorFootprint(
			dx,
			dz,
			span,
			span,
			pos.Y,
			floorTopY,
			true,
			120
		)
	end
	return ArenaCycleLogic.isInsideFloorFootprint(
		rel.X,
		rel.Z,
		sz.X,
		sz.Z,
		pos.Y,
		floorTopY,
		false,
		120
	)
end

local function isPositionInArenaRoom(ref: ArenaRefs, pos: Vector3): boolean
	if ref.roomVolume and ref.roomVolume.Parent then
		local vol = ref.roomVolume
		local rel = vol.CFrame:PointToObjectSpace(pos)
		local sz = vol.Size
		local isCyl = vol:IsA("Part") and vol.Shape == Enum.PartType.Cylinder
		return ArenaCycleLogic.isInsideVolumeBounds(rel.X, rel.Y, rel.Z, sz.X, sz.Y, sz.Z, isCyl)
	end
	if ref.arenaFloor and ref.arenaFloor.Parent then
		return isInsideFloorPart(ref.arenaFloor, pos)
	end
	local c = ref.eggPedestal.Position
	local roomRadius = BiomeConfigs.SUDDEN_DEATH_START_RADIUS + 25
	return ArenaCycleLogic.isInsideArenaBounds(pos.X, pos.Y, pos.Z, c.X, c.Y, c.Z, roomRadius, 120)
end

local function hasLivingCharacterInArena(player: Player, biomeId: string): boolean
	if player:GetAttribute("Zone") ~= "LockedBossPvP" then
		return false
	end
	if player:GetAttribute("ActiveBiome") ~= biomeId then
		return false
	end
	local ref = arenaRefs[biomeId]
	if not ref then
		return false
	end
	local char = player.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
	local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
	if not hrp or not hrp:IsA("BasePart") or not hum or hum.Health <= 0 then
		return false
	end
	return isPositionInArenaRoom(ref, hrp.Position)
end

function ArenaCycleService.canDealPvPDamage(attacker: Player, victim: Player): boolean
	local b1 = playerArenaBiome[attacker.UserId]
	local b2 = playerArenaBiome[victim.UserId]
	if not b1 or b1 ~= b2 then
		return false
	end
	if not hasLivingCharacterInArena(attacker, b1) or not hasLivingCharacterInArena(victim, b1) then
		return false
	end
	local st = biomeStates[b1]
	if not st then
		return false
	end
	return ArenaCycleLogic.canDealPvPDamage(st, attacker.UserId, victim.UserId, os.clock())
end

function ArenaCycleService.damageBoss(biomeId: string, attacker: Player, damage: number): boolean
	local st = biomeStates[biomeId]
	if not st or not hasLivingCharacterInArena(attacker, biomeId) then
		return false
	end
	local ok, events = ArenaCycleLogic.applyBossDamage(st, attacker.UserId, damage, os.clock())
	if #events > 0 then
		handleArenaEvents(events)
	end
	return ok
end

local function handlePvpLethalSocial(victim: Player, attacker: Player?, koPos: Vector3?)
	local remotes = Remotes.ensureServer()
	ViralSocialService.recordProgress(victim, "PvPLoss", 1)
	DataService.syncToClient(victim)
	remotes.CombatJuiceEvent:FireAllClients({
		kind = "StreakUpdate",
		userId = victim.UserId,
		killerName = victim.DisplayName,
		streak = 0,
	})
	remotes.CombatJuiceEvent:FireAllClients({
		kind = "Kill",
		worldPos = koPos,
		killerName = if attacker then attacker.DisplayName else nil,
		victimName = victim.DisplayName,
		accent = { 255, 84, 112 },
	})
	if attacker then
		ViralSocialService.recordProgress(attacker, "PvPWin", 1)
		DataService.syncToClient(attacker)
		local prof = DataService.getProfile(attacker)
		remotes.CombatJuiceEvent:FireAllClients({
			kind = "StreakUpdate",
			userId = attacker.UserId,
			killerName = attacker.DisplayName,
			streak = if prof then prof.winStreak else 0,
		})
	end
end

function ArenaCycleService.onPlayerDamagedInPvP(victim: Player, attacker: Player?, lethal: boolean)
	local biomeId = playerArenaBiome[victim.UserId]
	if not biomeId then
		return
	end
	local st = biomeStates[biomeId]
	if not st then
		return
	end
	local intEv = ArenaCycleLogic.onPlayerDamagedInPvP(st, victim.UserId)
	handleArenaEvents(intEv)
	if lethal then
		local char = victim.Character
		local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
		local koPos = if hrp and hrp:IsA("BasePart") then hrp.Position else nil
		if attacker then
			local bossCfg = BiomeConfigs.getBossForBiome(biomeId)
			local attackerProfile = DataService.getProfile(attacker)
			if bossCfg and attackerProfile then
				attackerProfile.bossGems += bossCfg.pvpKillGems
				Remotes.ensureServer().ToastNotify
					:FireClient(
						attacker,
						`PvP KO! +{bossCfg.pvpKillGems} Boss Gems!`,
						{ 250, 204, 21 }
					)
			end
		end
		handlePvpLethalSocial(victim, attacker, koPos)
		local remEv =
			ArenaCycleLogic.removePlayerFromArena(st, victim.UserId, os.clock(), "Eliminated")
		handleArenaEvents(remEv)
	end
end

function ArenaCycleService.forceOverchargedNow()
	overchargedClock.nextEventAt = os.clock()
end

function ArenaCycleService.init()
	local now = os.clock()
	overchargedClock = ArenaCycleLogic.createOverchargedClock(now)
	for _, biomeId in ipairs(BiomeConfigs.ORDERED_MVP_BIOMES) do
		biomeStates[biomeId] = ArenaCycleLogic.createBiomeState(biomeId, now)
		paidParticipantsByBiome[biomeId] = {}
	end
	discoverArenas()
end

local function removeFighterFromAll(player: Player, reason: string)
	local now = os.clock()
	for _, st in pairs(biomeStates) do
		local ev = ArenaCycleLogic.removePlayerFromArena(st, player.UserId, now, reason)
		if #ev > 0 then
			handleArenaEvents(ev)
		end
	end
	playerArenaBiome[player.UserId] = nil
end

local function watchFighterLifecycle(player: Player)
	local function bindCharacter(char: Model)
		local hum = char:WaitForChild("Humanoid", 10)
		if hum and hum:IsA("Humanoid") then
			hum.Died:Connect(function()
				removeFighterFromAll(player, "Died")
			end)
		end
	end
	player.CharacterAdded:Connect(function(char: Model)
		removeFighterFromAll(player, "Respawned")
		bindCharacter(char)
	end)
	if player.Character then
		task.spawn(bindCharacter, player.Character)
	end
end

local function handleOptInRequest(player: Player, biomeId: any, wantsIn: any)
	if type(biomeId) ~= "string" or type(wantsIn) ~= "boolean" then
		return
	end
	local st = biomeStates[biomeId]
	if not st or playerArenaBiome[player.UserId] ~= nil then
		return
	end
	if player:GetAttribute("Zone") == "LockedBossPvP" then
		return
	end
	local eligible = isPlayerZoneEligibleForOptIn(player, biomeId)
	local alreadyQueued = st.queuedPlayers[player.UserId] ~= nil
	if not eligible and not (not wantsIn and alreadyQueued) then
		return
	end
	if eligible and ArenaCycleLogic.markOptInOffered(st, player.UserId) and telemetryCallback then
		telemetryCallback("BossFightOffered", { userId = player.UserId, value = 1 })
	end
	local power = tonumber(player:GetAttribute("PowerRating")) or 10
	ArenaCycleLogic.switchOptIn(biomeStates, biomeId, player.UserId, wantsIn, power)
end

local function handleClaimEggAction(player: Player, action: any)
	if type(action) ~= "string" then
		return
	end
	local biomeId = playerArenaBiome[player.UserId]
	local st = if biomeId then biomeStates[biomeId] else nil
	local ref = if biomeId then arenaRefs[biomeId] else nil
	if not biomeId or not st or not ref then
		return
	end
	if action == "Begin" then
		if not hasLivingCharacterInArena(player, biomeId) then
			return
		end
		local char = player.Character
		local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
		if hrp and hrp:IsA("BasePart") then
			local dist = (hrp.Position - ref.eggPedestal.Position).Magnitude
			ArenaCycleLogic.beginEggClaim(st, player.UserId, dist, os.clock())
		end
	elseif action == "Cancel" then
		local ev = ArenaCycleLogic.cancelEggClaim(st, player.UserId, "Released")
		handleArenaEvents(ev)
	end
end

local function isEntrantReady(biomeId: string, userId: number): boolean
	local ref = arenaRefs[biomeId]
	if not ref or #ref.optInSpawns == 0 or playerArenaBiome[userId] ~= nil then
		return false
	end
	local plr = Players:GetPlayerByUserId(userId)
	local hum = if plr and plr.Character
		then plr.Character:FindFirstChildOfClass("Humanoid")
		else nil
	return plr ~= nil and hum ~= nil and hum.Health > 0
end

local function stepSuddenDeathStorm(st: ArenaCycleLogic.BiomeArenaState, ref: ArenaRefs)
	if st.phase ~= "PvP_EggScramble" then
		return
	end
	local r = st.suddenDeathRadius
	if ref.suddenDeathRing then
		ref.suddenDeathRing.Size = Vector3.new(0.4, r * 2, r * 2)
	end
	if r >= BiomeConfigs.SUDDEN_DEATH_START_RADIUS - 0.5 then
		return
	end
	local activeIds: { number } = {}
	for uid in pairs(st.activePlayers) do
		table.insert(activeIds, uid)
	end
	for _, uid in ipairs(activeIds) do
		local plr = Players:GetPlayerByUserId(uid)
		if plr and st.activePlayers[uid] and hasLivingCharacterInArena(plr, st.biomeId) then
			local char = plr.Character
			local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
			local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
			if hrp and hrp:IsA("BasePart") and hum and hum.Health > 0 then
				local d = MathUtil.distance2D(
					hrp.Position.X,
					hrp.Position.Z,
					ref.eggPedestal.Position.X,
					ref.eggPedestal.Position.Z
				)
				if d > r then
					local tickDmg = hum.MaxHealth * BiomeConfigs.SUDDEN_DEATH_DPS_FRACTION * 0.25
					hum.Health = math.max(0, hum.Health - tickDmg)
					ArenaCycleService.onPlayerDamagedInPvP(plr, nil, hum.Health <= 0)
				end
			end
		end
	end
end

local function reconcileArenaEntrants(
	biomeId: string,
	st: ArenaCycleLogic.BiomeArenaState,
	now: number
)
	local activeIds: { number } = {}
	for uid in pairs(st.activePlayers) do
		table.insert(activeIds, uid)
	end
	for _, uid in ipairs(activeIds) do
		local plr = Players:GetPlayerByUserId(uid)
		if not plr or not hasLivingCharacterInArena(plr, biomeId) then
			local remEv = ArenaCycleLogic.removePlayerFromArena(st, uid, now, "OutOfBounds")
			if #remEv > 0 then
				handleArenaEvents(remEv)
			end
		end
	end
end

local function resolveClaimerDistance(
	biomeId: string,
	st: ArenaCycleLogic.BiomeArenaState,
	ref: ArenaRefs?
): number?
	if not st.claim.claimerId or not ref then
		return nil
	end
	local claimer = Players:GetPlayerByUserId(st.claim.claimerId)
	if not claimer or not hasLivingCharacterInArena(claimer, biomeId) then
		return BiomeConfigs.EGG_CLAIM_RADIUS + 1
	end
	local hrp = if claimer.Character
		then claimer.Character:FindFirstChild("HumanoidRootPart")
		else nil
	return if hrp and hrp:IsA("BasePart")
		then (hrp.Position - ref.eggPedestal.Position).Magnitude
		else BiomeConfigs.EGG_CLAIM_RADIUS + 1
end

local function stepSingleBiome(biomeId: string, now: number)
	local st = biomeStates[biomeId]
	local ref = arenaRefs[biomeId]
	if st.phase == "OptIn_Window" then
		recordOptInOffers(biomeId)
		if now >= st.phaseEndsAt then
			ArenaCycleLogic.pruneQueuedPlayers(st, function(uid: number): boolean
				return isEntrantReady(biomeId, uid)
			end)
		end
	end
	local claimDist = resolveClaimerDistance(biomeId, st, ref)
	local ev = ArenaCycleLogic.stepBiome(st, now, claimDist)
	if #ev > 0 then
		handleArenaEvents(ev)
	end
	if ref and (st.phase == "Boss_Phase" or st.phase == "PvP_EggScramble") then
		reconcileArenaEntrants(biomeId, st, now)
	end
	if ref and st.phase == "PvP_EggScramble" then
		stepSuddenDeathStorm(st, ref)
	end
end

function ArenaCycleService.start()
	local remotes = Remotes.ensureServer()
	remotes.OptInBoss.OnServerEvent:Connect(handleOptInRequest)
	remotes.ClaimEggAction.OnServerEvent:Connect(handleClaimEggAction)

	Players.PlayerAdded:Connect(watchFighterLifecycle)
	for _, plr in ipairs(Players:GetPlayers()) do
		watchFighterLifecycle(plr)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		removeFighterFromAll(player, "Disconnected")
	end)

	task.spawn(function()
		while true do
			task.wait(0.25)
			local now = os.clock()
			local ocEvents =
				ArenaCycleLogic.stepOverchargedClock(overchargedClock, biomeStates, now)
			if #ocEvents > 0 then
				handleArenaEvents(ocEvents)
			end
			for _, biomeId in ipairs(BiomeConfigs.ORDERED_MVP_BIOMES) do
				stepSingleBiome(biomeId, now)
			end
			updateWorldBoards(now)
			broadcastArenaStates(now)
		end
	end)
end

return ArenaCycleService
