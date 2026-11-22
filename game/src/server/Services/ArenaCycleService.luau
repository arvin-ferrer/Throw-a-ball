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

type ArenaRefs = {
	biomeId: string,
	arenaFolder: Instance,
	bossSpawn: BasePart,
	eggPedestal: BasePart,
	eggPrompt: ProximityPrompt?,
	suddenDeathRing: BasePart?,
	optInSpawns: { BasePart },
	eggVisual: Model?,
}

local ArenaCycleService = {}

local biomeStates: { [string]: ArenaCycleLogic.BiomeArenaState } = {}
local overchargedClock: ArenaCycleLogic.OverchargedClock =
	ArenaCycleLogic.createOverchargedClock(os.clock())
local arenaRefs: { [string]: ArenaRefs } = {}
local playerArenaBiome: { [number]: string } = {}
local spawnBossCallback: ((string, BasePart, number, boolean) -> ())? = nil
local clearBossCallback: ((string) -> ())? = nil
local telemetryCallback: ((string, { [string]: any }) -> ())? = nil

local function discoverArenas()
	local mapRoot = PlotService.getMapRoot()
	local biomesFolder = if mapRoot then mapRoot:FindFirstChild("Biomes") else nil
	if not biomesFolder then
		return
	end
	for _, biomeId in ipairs(BiomeConfigs.ORDERED_MVP_BIOMES) do
		local bFolder = biomesFolder:FindFirstChild(biomeId)
		local arena = if bFolder then bFolder:FindFirstChild("BossPvPArena") else nil
		if arena then
			local bossSpawn = arena:FindFirstChild("BossSpawn")
			local eggPed = arena:FindFirstChild("EggClaimPedestal")
			local sdRing = arena:FindFirstChild("SuddenDeathRingMarker")
			local spawns: { BasePart } = {}
			for _, child in ipairs(arena:GetChildren()) do
				if child:IsA("BasePart") and string.find(child.Name, "OptInSpawn_") then
					table.insert(spawns, child)
				end
			end
			table.sort(spawns, function(a, b)
				return a.Name < b.Name
			end)
			if bossSpawn and bossSpawn:IsA("BasePart") and eggPed and eggPed:IsA("BasePart") then
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
				arenaRefs[biomeId] = {
					biomeId = biomeId,
					arenaFolder = arena,
					bossSpawn = bossSpawn,
					eggPedestal = eggPed,
					eggPrompt = prompt,
					suddenDeathRing = if sdRing and sdRing:IsA("BasePart") then sdRing else nil,
					optInSpawns = spawns,
					eggVisual = nil,
				}
			end
		end
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
	local remotes = Remotes.ensureServer()
	for _, userId in ipairs(userIds) do
		local plr = Players:GetPlayerByUserId(userId)
		local profile = DataService.getProfileByUserId(userId)
		if plr and profile then
			local mult = if DataService.hasPass(plr, "Pass_DoubleCoinsExp") then 2 else 1
			local coins = bossCfg.participationCoins * mult
			local exp = bossCfg.participationExp * mult
			local gems = bossCfg.participationGems
			if winnerId == userId and eggId then
				coins += bossCfg.winnerBonusCoins * mult
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
		end
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
			local phase = ev.payload.phase
			if phase == "Boss_Phase" and ref then
				local playersList: { number } = ev.payload.players or {}
				for i, uid in ipairs(playersList) do
					local plr = Players:GetPlayerByUserId(uid)
					if plr then
						playerArenaBiome[uid] = biomeId
						plr:SetAttribute("Zone", "LockedBossPvP")
						plr:SetAttribute("ActiveBiome", biomeId)
						fullHealPlayer(plr)
						local pad = ref.optInSpawns[((i - 1) % math.max(1, #ref.optInSpawns)) + 1]
						if pad then
							PlotService.teleportCharacter(plr, pad.CFrame)
						end
					end
				end
				if spawnBossCallback then
					spawnBossCallback(
						biomeId,
						ref.bossSpawn,
						ev.payload.bossMaxHP,
						ev.payload.isOvercharged == true
					)
				end
			elseif phase == "PvE_Open" then
				setEggVisual(biomeId, nil, false)
				if clearBossCallback then
					clearBossCallback(biomeId)
				end
				local returnList: { number } = ev.payload.returnPlayers or {}
				for _, uid in ipairs(returnList) do
					playerArenaBiome[uid] = nil
					local plr = Players:GetPlayerByUserId(uid)
					if plr then
						PlotService.teleportToBiomePvE(plr, biomeId)
					end
				end
			end
		elseif ev.kind == "BossDefeated" then
			local biome = BiomeConfigs.BIOMES[biomeId]
			local isOver = ev.payload.isOvercharged == true
			local eggId = if isOver then biome.overchargedEggId else biome.standardEggId
			if clearBossCallback then
				clearBossCallback(biomeId)
			end
			setEggVisual(biomeId, eggId, isOver)
			for _, uid in ipairs(ev.payload.survivors or {}) do
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
		elseif ev.kind == "EggClaimed" then
			awardParticipation(
				biomeId,
				ev.payload.participants or {},
				ev.payload.winnerId,
				ev.payload.eggId
			)
			if telemetryCallback then
				telemetryCallback(
					"EggClaimed",
					{ biomeId = biomeId, isOvercharged = ev.payload.isOvercharged }
				)
			end
		elseif ev.kind == "PlayerEliminated" then
			local uid = ev.payload.userId
			playerArenaBiome[uid] = nil
			local plr = Players:GetPlayerByUserId(uid)
			if plr then
				awardParticipation(biomeId, { uid }, nil, nil)
				PlotService.teleportToBiomePvE(plr, biomeId)
			end
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

function ArenaCycleService.canDealPvPDamage(attacker: Player, victim: Player): boolean
	local b1 = playerArenaBiome[attacker.UserId]
	local b2 = playerArenaBiome[victim.UserId]
	if not b1 or b1 ~= b2 then
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
	if not st then
		return false
	end
	local ok, events = ArenaCycleLogic.applyBossDamage(st, attacker.UserId, damage, os.clock())
	if #events > 0 then
		handleArenaEvents(events)
	end
	return ok
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
		if attacker then
			local bossCfg = BiomeConfigs.getBossForBiome(biomeId)
			local attackerProfile = DataService.getProfile(attacker)
			if bossCfg and attackerProfile then
				attackerProfile.bossGems += bossCfg.pvpKillGems
				DataService.syncToClient(attacker)
				Remotes.ensureServer().ToastNotify
					:FireClient(
						attacker,
						`PvP KO! +{bossCfg.pvpKillGems} Boss Gems!`,
						{ 250, 204, 21 }
					)
			end
		end
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
	end
	discoverArenas()
end

function ArenaCycleService.start()
	local remotes = Remotes.ensureServer()

	remotes.OptInBoss.OnServerEvent:Connect(function(player: Player, biomeId: any, wantsIn: any)
		if type(biomeId) ~= "string" or type(wantsIn) ~= "boolean" then
			return
		end
		local st = biomeStates[biomeId]
		if not st then
			return
		end
		-- Allow opting in from that biome's PvE layer (or Hub for convenience during Overcharged)
		local power = tonumber(player:GetAttribute("PowerRating")) or 10
		if ArenaCycleLogic.setOptIn(st, player.UserId, wantsIn, power) and telemetryCallback then
			telemetryCallback(
				"BossOptIn",
				{ biomeId = biomeId, optedIn = wantsIn, userId = player.UserId }
			)
		end
	end)

	remotes.ClaimEggAction.OnServerEvent:Connect(function(player: Player, action: any)
		if type(action) ~= "string" then
			return
		end
		local biomeId = playerArenaBiome[player.UserId]
		local st = if biomeId then biomeStates[biomeId] else nil
		local ref = if biomeId then arenaRefs[biomeId] else nil
		if not st or not ref then
			return
		end
		if action == "Begin" then
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
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		local now = os.clock()
		for _, st in pairs(biomeStates) do
			local ev = ArenaCycleLogic.removePlayerFromArena(st, player.UserId, now, "Disconnected")
			if #ev > 0 then
				handleArenaEvents(ev)
			end
		end
		playerArenaBiome[player.UserId] = nil
	end)

	-- 4 Hz authoritative arena loop
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
				local st = biomeStates[biomeId]
				local ref = arenaRefs[biomeId]
				local claimDist: number? = nil
				if st.claim.claimerId and ref then
					local claimer = Players:GetPlayerByUserId(st.claim.claimerId)
					local hrp = if claimer and claimer.Character
						then claimer.Character:FindFirstChild("HumanoidRootPart")
						else nil
					claimDist = if hrp and hrp:IsA("BasePart")
						then (hrp.Position - ref.eggPedestal.Position).Magnitude
						else 999
				end
				local ev = ArenaCycleLogic.stepBiome(st, now, claimDist)
				if #ev > 0 then
					handleArenaEvents(ev)
				end
				-- Sudden Death Storm Ring visual & tick damage
				if st.phase == "PvP_EggScramble" and ref and ref.suddenDeathRing then
					local r = st.suddenDeathRadius
					ref.suddenDeathRing.Size = Vector3.new(0.4, r * 2, r * 2)
					if r < BiomeConfigs.SUDDEN_DEATH_START_RADIUS - 0.5 then
						for uid in pairs(st.activePlayers) do
							local plr = Players:GetPlayerByUserId(uid)
							local char = if plr then plr.Character else nil
							local hrp = if char
								then char:FindFirstChild("HumanoidRootPart")
								else nil
							local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
							if plr and hrp and hrp:IsA("BasePart") and hum and hum.Health > 0 then
								local d = MathUtil.distance2D(
									hrp.Position.X,
									hrp.Position.Z,
									ref.eggPedestal.Position.X,
									ref.eggPedestal.Position.Z
								)
								if d > r then
									local tickDmg = hum.MaxHealth
										* BiomeConfigs.SUDDEN_DEATH_DPS_FRACTION
										* 0.25
									hum.Health = math.max(0, hum.Health - tickDmg)
									ArenaCycleService.onPlayerDamagedInPvP(
										plr,
										nil,
										hum.Health <= 0
									)
								end
							end
						end
					end
				end
			end
			updateWorldBoards(now)
			broadcastArenaStates(now)
		end
	end)
end

return ArenaCycleService
