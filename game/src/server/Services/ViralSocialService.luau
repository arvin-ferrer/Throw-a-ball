--!strict
--[[
	ViralSocialService.luau
	Server-authoritative Retention & Viral Social Engine:
	- Cached pcall-safe Player:IsFriendsWithAsync + Player.PartyId (+10%/ally, cap +30%)
	- Forgiving 7-day cumulative check-in + 3 rotating Daily Quests
	- Non-verbal 4-icon Quick-Ping rate limiter & zone/radius broadcaster
	- Server-wide GlobalAnnouncement celebrations & Hub LeaderboardBoard updater
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RetentionConfigs = require(Shared.Configs.RetentionConfigs)
local EconomyConfigs = require(Shared.Configs.EconomyConfigs)
local EconomyLogic = require(Shared.Utils.EconomyLogic)
local ViralSocialLogic = require(Shared.Utils.ViralSocialLogic)
local MathUtil = require(Shared.Utils.MathUtil)
local Remotes = require(Shared.Net.Remotes)

local DataService = require(script.Parent.DataService)

type FriendEntry = {
	isFriend: boolean,
	fetchedAt: number,
}

type SocialRemotes = {
	QuickPing: RemoteEvent,
	RetentionAction: RemoteEvent,
	RetentionSync: RemoteEvent,
	GlobalAnnouncement: RemoteEvent,
}

local ViralSocialService = {}

local friendCache: { [number]: { [number]: FriendEntry } } = {}
local lastPingByUser: { [number]: number } = {}
local lastRetentionActionByUser: { [number]: number } = {}
local RETENTION_DEBOUNCE_SEC = 0.25
local cachedBonuses: { [number]: ViralSocialLogic.CoOpBonusSummary } = {}
local latestLeaderboards: ViralSocialLogic.LeaderboardBundle = {
	power = {},
	wins = {},
	income = {},
}
local socialRemotes: SocialRemotes? = nil
local isInitialized = false
local isStarted = false

local function ensureRemote(folder: Folder, name: string): RemoteEvent
	local existing = folder:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local re = Instance.new("RemoteEvent")
	re.Name = name
	re.Parent = folder
	return re
end

local function ensureSocialRemotes(): SocialRemotes
	if socialRemotes then
		return socialRemotes
	end
	local folder = Remotes.ensureServer().Folder
	local bundle: SocialRemotes = {
		QuickPing = ensureRemote(folder, "QuickPing"),
		RetentionAction = ensureRemote(folder, "RetentionAction"),
		RetentionSync = ensureRemote(folder, "RetentionSync"),
		GlobalAnnouncement = ensureRemote(folder, "GlobalAnnouncement"),
	}
	socialRemotes = bundle
	return bundle
end

local function getPlayerPartyId(player: Player): string
	local ok, val = pcall(function()
		return (player :: any).PartyId
	end)
	if ok and type(val) == "string" then
		return val
	end
	return ""
end

local function isCachedFriend(uidA: number, uidB: number): boolean
	local row = friendCache[uidA]
	local entry = if row then row[uidB] else nil
	return entry ~= nil and entry.isFriend == true
end

local function storeFriendRelation(uidA: number, uidB: number, isFriend: boolean, now: number)
	local rowA = friendCache[uidA]
	if not rowA then
		rowA = {}
		friendCache[uidA] = rowA
	end
	rowA[uidB] = { isFriend = isFriend, fetchedAt = now }

	local rowB = friendCache[uidB]
	if not rowB then
		rowB = {}
		friendCache[uidB] = rowB
	end
	rowB[uidA] = { isFriend = isFriend, fetchedAt = now }
end

local function computeBonusForPlayer(player: Player): ViralSocialLogic.CoOpBonusSummary
	local uid = player.UserId
	local myPartyId = getPlayerPartyId(player)
	local peers: { ViralSocialLogic.CoOpPeer } = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local otherUid = other.UserId
			table.insert(peers, {
				userId = otherUid,
				isFriend = isCachedFriend(uid, otherUid),
				partyId = getPlayerPartyId(other),
			})
		end
	end
	local summary = ViralSocialLogic.computeCoOpBonus(uid, myPartyId, peers)
	cachedBonuses[uid] = summary
	player:SetAttribute("FriendBonusMult", summary.friendBonusMult)
	player:SetAttribute("FriendCount", summary.friendCount)
	player:SetAttribute("PartySize", summary.partySize)
	return summary
end

local function computePlayerCoinsPerSec(player: Player, profile: any): number
	if type(profile) ~= "table" or type(profile.pets) ~= "table" then
		return 0
	end
	local hasDouble = DataService.hasPass(player, "Pass_DoubleCoinsExp")
	local totalRate = 0
	for _, pet in ipairs(profile.pets) do
		if pet.pedestalIndex ~= nil then
			totalRate += EconomyLogic.computePlacedPetRate(profile, pet, hasDouble)
		end
	end
	return math.floor(totalRate + 0.5)
end

local function computePlayerPower(player: Player, profile: any): number
	local attrPower = tonumber(player:GetAttribute("PowerRating"))
	if attrPower and MathUtil.isFinite(attrPower) then
		return math.max(0, math.floor(attrPower + 0.5))
	end
	if type(profile) ~= "table" then
		return 0
	end
	local ballTier = EconomyConfigs.getBallTierById(profile.ballTierId)
		or EconomyConfigs.BALL_TIERS[1]
	local maxHP = EconomyConfigs.getPlayerMaxHP(profile.level or 1)
	local rate = computePlayerCoinsPerSec(player, profile)
	return MathUtil.computePowerRating(
		profile.ballDamage or EconomyConfigs.STARTER_BALL_DAMAGE,
		ballTier.damageMult,
		profile.throwSpeed or EconomyConfigs.STARTER_THROW_SPEED,
		maxHP,
		rate
	)
end

local function buildSyncPayload(player: Player, profile: any): { [string]: any }
	local now = os.time()
	ViralSocialLogic.ensureSocialProfile(profile, now)
	local daily = ViralSocialLogic.getDailyState(profile, now)
	local bonus = computeBonusForPlayer(player)
	return {
		dailyDay = daily.dailyDay,
		dailyClaimable = daily.dailyClaimable,
		cumulativeDays = daily.cumulativeDays,
		quests = profile.dailyQuests,
		friendBonusMult = bonus.friendBonusMult,
		friendCount = bonus.friendCount,
		partySize = bonus.partySize,
		winStreak = profile.winStreak or 0,
		bestWinStreak = profile.bestWinStreak or 0,
		totalBossWins = profile.totalBossWins or 0,
		leaderboards = latestLeaderboards,
	}
end

local function syncPlayerState(player: Player)
	if not player.Parent then
		return
	end
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	local remotes = ensureSocialRemotes()
	remotes.RetentionSync:FireClient(player, buildSyncPayload(player, profile))
end

local function formatBoardRows(rows: { ViralSocialLogic.LeaderboardRow }, suffix: string): string
	if #rows == 0 then
		return "  No entries yet"
	end
	local lines: { string } = {}
	for i = 1, math.min(3, #rows) do
		local r = rows[i]
		table.insert(
			lines,
			`{r.rank}. {r.displayName} — {MathUtil.formatNumber(r.value)}{suffix}`
		)
	end
	return table.concat(lines, "\n")
end

local function findLeaderboardBoards(): { Instance }
	local boards: { Instance } = {}
	local seen: { [Instance]: boolean } = {}
	for _, tagged in ipairs(CollectionService:GetTagged("LeaderboardBoard")) do
		seen[tagged] = true
		table.insert(boards, tagged)
	end
	local mapRoot = workspace:FindFirstChild("BallBrawl_Map_v2")
	local hub = if mapRoot then mapRoot:FindFirstChild("Hub") else nil
	local services = if hub then hub:FindFirstChild("Services") else nil
	local named = if services then services:FindFirstChild("LeaderboardBoard") else nil
	if named and not seen[named] then
		table.insert(boards, named)
	end
	return boards
end

local function resolveBoardPart(board: Instance): BasePart?
	if board:IsA("BasePart") then
		return board
	end
	if board:IsA("Model") and board.PrimaryPart then
		return board.PrimaryPart
	end
	return board:FindFirstChildWhichIsA("BasePart", true)
end

local function ensureBoardSurfaceGui(board: Instance): SurfaceGui?
	local existing = board:FindFirstChildWhichIsA("SurfaceGui", true)
	if existing then
		return existing
	end
	local part = resolveBoardPart(board)
	if not part then
		return nil
	end
	local sg = Instance.new("SurfaceGui")
	sg.Name = "LeaderboardSurface"
	sg.Face = Enum.NormalId.Front
	sg.Parent = part
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -16, 0.16, 0)
	title.Position = UDim2.fromOffset(8, 6)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 222, 74)
	title.Parent = sg
	local rows = Instance.new("TextLabel")
	rows.Name = "Rows"
	rows.Size = UDim2.new(1, -16, 0.80, 0)
	rows.Position = UDim2.new(0, 8, 0.18, 0)
	rows.BackgroundTransparency = 1
	rows.Font = Enum.Font.GothamBold
	rows.TextScaled = true
	rows.TextYAlignment = Enum.TextYAlignment.Top
	rows.TextColor3 = Color3.fromRGB(248, 250, 252)
	rows.Parent = sg
	return sg
end

local function updateSingleBoardVisual(board: Instance, titleText: string, rowsText: string)
	local sg = ensureBoardSurfaceGui(board)
	if not sg then
		return
	end
	local titleLbl = sg:FindFirstChild("Title", true)
	if titleLbl and titleLbl:IsA("TextLabel") then
		titleLbl.Text = titleText
	end
	local rowsLbl = sg:FindFirstChild("Rows", true)
	if rowsLbl and rowsLbl:IsA("TextLabel") then
		rowsLbl.Text = rowsText
	end
end

local function wireBoardPrompt(board: Instance)
	local part = resolveBoardPart(board)
	if not part or part:FindFirstChildWhichIsA("ProximityPrompt") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LeaderboardPrompt"
	prompt.ActionText = "View Ranks & Daily"
	prompt.ObjectText = "Hub Leaderboards"
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	prompt.Triggered:Connect(function(plr: Player)
		Remotes.ensureServer().ToastNotify
			:FireClient(plr, "OPEN_MODAL:Leaderboard", { 56, 189, 248 })
	end)
end

local function updateHubLeaderboardBoards()
	local titleText = "🏆 LIVE HUB LEADERBOARDS"
	local rowsText = table.concat({
		"⚡ TOP POWER RATING",
		formatBoardRows(latestLeaderboards.power, ""),
		"⚔ TOP BOSS WINS",
		formatBoardRows(latestLeaderboards.wins, " Wins"),
		"💰 TOP COINS/SEC",
		formatBoardRows(latestLeaderboards.income, "/s"),
	}, "\n")
	for _, board in ipairs(findLeaderboardBoards()) do
		updateSingleBoardVisual(board, titleText, rowsText)
		wireBoardPrompt(board)
	end
end

local function refreshLeaderboards(syncClients: boolean)
	local snapshots: { ViralSocialLogic.LeaderboardSnapshot } = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		local profile = DataService.getProfile(plr)
		if profile then
			ViralSocialLogic.ensureSocialProfile(profile)
			table.insert(snapshots, {
				userId = plr.UserId,
				displayName = plr.DisplayName,
				powerRating = computePlayerPower(plr, profile),
				totalBossWins = (profile :: any).totalBossWins or 0,
				coinsPerSec = computePlayerCoinsPerSec(plr, profile),
			})
		end
	end
	latestLeaderboards =
		ViralSocialLogic.computeLeaderboards(snapshots, RetentionConfigs.LEADERBOARD_LIMIT)
	updateHubLeaderboardBoards()
	if syncClients then
		for _, plr in ipairs(Players:GetPlayers()) do
			syncPlayerState(plr)
		end
	end
end

local function shouldFetchFriendPair(uidA: number, uidB: number, now: number): boolean
	local row = friendCache[uidA]
	local entry = if row then row[uidB] else nil
	if not entry then
		return true
	end
	return (now - entry.fetchedAt) >= RetentionConfigs.FRIEND_CACHE_TTL_SEC
end

local function refreshFriendStatusForPlayer(player: Player)
	local uid = player.UserId
	task.spawn(function()
		local now = os.clock()
		local changed = false
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player and player.Parent and other.Parent then
				local otherUid = other.UserId
				if shouldFetchFriendPair(uid, otherUid, now) then
					local ok, isFr = pcall(function()
						return player:IsFriendsWithAsync(otherUid)
					end)
					if player.Parent and other.Parent then
						storeFriendRelation(uid, otherUid, ok and isFr == true, os.clock())
						changed = true
					end
				end
			end
		end
		if player.Parent then
			syncPlayerState(player)
		end
		if changed then
			for _, other in ipairs(Players:GetPlayers()) do
				if other ~= player and other.Parent then
					syncPlayerState(other)
				end
			end
		end
	end)
end

local function getCharacterPosition(player: Player): Vector3
	local char = player.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
	if hrp and hrp:IsA("BasePart") then
		return hrp.Position
	end
	return Vector3.new(0, 5, 0)
end

local function resolvePingWorldPos(
	player: Player,
	rawPos: any
): (Vector3, { x: number, y: number, z: number }?)
	local basePos = getCharacterPosition(player)
	if typeof(rawPos) == "Vector3" then
		local posTbl = { x = rawPos.X, y = rawPos.Y, z = rawPos.Z }
		if
			MathUtil.isFinite(posTbl.x)
			and MathUtil.isFinite(posTbl.y)
			and MathUtil.isFinite(posTbl.z)
		then
			local offset = (rawPos - basePos).Magnitude
			if offset <= RetentionConfigs.QUICK_PING_MAX_OFFSET then
				return rawPos, posTbl
			end
			return basePos, { x = basePos.X, y = basePos.Y, z = basePos.Z }
		end
		return basePos, posTbl
	elseif rawPos ~= nil then
		return basePos, { x = 0 / 0, y = 0, z = 0 }
	end
	return basePos, nil
end

local function broadcastQuickPing(sender: Player, pingId: string, resolvedVec: Vector3)
	local senderZone = tostring(sender:GetAttribute("Zone") or "Hub")
	local senderBiome = tostring(sender:GetAttribute("ActiveBiome") or "")
	local senderPos = { x = resolvedVec.X, y = resolvedVec.Y, z = resolvedVec.Z }
	local outPayload = {
		userId = sender.UserId,
		displayName = sender.DisplayName,
		pingId = pingId,
		worldPos = resolvedVec,
		timestamp = os.time(),
	}
	local remotes = ensureSocialRemotes()
	for _, receiver in ipairs(Players:GetPlayers()) do
		local recvZone = tostring(receiver:GetAttribute("Zone") or "Hub")
		local recvBiome = tostring(receiver:GetAttribute("ActiveBiome") or "")
		local recvVec = getCharacterPosition(receiver)
		local recvPos = { x = recvVec.X, y = recvVec.Y, z = recvVec.Z }
		local allow = receiver == sender
			or ViralSocialLogic.shouldReceivePing(
				senderZone,
				senderBiome,
				senderPos,
				recvZone,
				recvBiome,
				recvPos,
				RetentionConfigs.QUICK_PING_RADIUS
			)
		if allow then
			remotes.QuickPing:FireClient(receiver, outPayload)
		end
	end
end

local function handleQuickPing(player: Player, payload: any)
	if type(payload) ~= "table" then
		return
	end
	local uid = player.UserId
	local now = os.clock()
	local resolvedVec, validationPos = resolvePingWorldPos(player, payload.worldPos)
	local ok =
		ViralSocialLogic.validateQuickPing(payload.pingId, validationPos, lastPingByUser[uid], now)
	if not ok then
		return
	end
	lastPingByUser[uid] = now
	broadcastQuickPing(player, payload.pingId, resolvedVec)
end

local function handleClaimDaily(player: Player, profile: any, now: number)
	local res = ViralSocialLogic.claimDailyReward(profile, now)
	local coreRemotes = Remotes.ensureServer()
	if res.ok and res.reward then
		DataService.syncToClient(player)
		local eggSuffix = if res.reward.eggId then ` + {res.reward.eggId}!` else "!"
		coreRemotes.ToastNotify:FireClient(
			player,
			`DAY {res.dayIndex} CHECK-IN: +{MathUtil.formatNumber(res.reward.coins)} Coins & +{res.reward.gems} Boss Gems{eggSuffix}`,
			{ 250, 204, 21 }
		)
	else
		coreRemotes.ToastNotify:FireClient(
			player,
			"Daily Check-In already claimed today — see you tomorrow!",
			{ 56, 189, 248 }
		)
	end
	syncPlayerState(player)
end

local function handleClaimQuest(player: Player, profile: any, questId: any, now: number)
	if type(questId) ~= "string" then
		return
	end
	local res = ViralSocialLogic.claimQuestReward(profile, questId, now)
	local coreRemotes = Remotes.ensureServer()
	if res.ok and res.quest then
		DataService.syncToClient(player)
		coreRemotes.ToastNotify:FireClient(
			player,
			`QUEST CLAIMED ({res.quest.title}): +{MathUtil.formatNumber(res.quest.rewardCoins)} Coins & +{res.quest.rewardGems} Gems!`,
			{ 74, 222, 128 }
		)
	else
		coreRemotes.ToastNotify:FireClient(
			player,
			`Quest unavailable: {res.reason or "Incomplete"}`,
			{ 239, 68, 68 }
		)
	end
	syncPlayerState(player)
end

local function handleRetentionAction(player: Player, payload: any)
	if type(payload) ~= "table" or type(payload.action) ~= "string" then
		return
	end
	local nowClock = os.clock()
	if nowClock - (lastRetentionActionByUser[player.UserId] or 0) < RETENTION_DEBOUNCE_SEC then
		return
	end
	lastRetentionActionByUser[player.UserId] = nowClock
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	local now = os.time()
	if payload.action == "ClaimDaily" then
		handleClaimDaily(player, profile, now)
	elseif payload.action == "ClaimQuest" then
		handleClaimQuest(player, profile, payload.questId, now)
	elseif payload.action == "RequestState" then
		ViralSocialLogic.ensureDailyQuests(profile, now)
		syncPlayerState(player)
	end
end

local function onPlayerLoaded(player: Player, profile: any)
	local now = os.time()
	ViralSocialLogic.ensureSocialProfile(profile, now)
	player:SetAttribute("WinStreak", (profile :: any).winStreak or 0)
	player:SetAttribute("BestWinStreak", (profile :: any).bestWinStreak or 0)
	refreshLeaderboards(false)
	syncPlayerState(player)
	refreshFriendStatusForPlayer(player)
end

local function bindPlayerSignals(player: Player)
	pcall(function()
		player:GetPropertyChangedSignal("PartyId"):Connect(function()
			for _, plr in ipairs(Players:GetPlayers()) do
				syncPlayerState(plr)
			end
		end)
	end)
	refreshFriendStatusForPlayer(player)
	if DataService.getProfile(player) then
		onPlayerLoaded(player, DataService.getProfile(player))
	end
end

local function cleanupDepartingPlayer(player: Player)
	local uid = player.UserId
	friendCache[uid] = nil
	lastPingByUser[uid] = nil
	lastRetentionActionByUser[uid] = nil
	cachedBonuses[uid] = nil
	for _, row in pairs(friendCache) do
		row[uid] = nil
	end
	refreshLeaderboards(true)
end

function ViralSocialService.getFriendBonusMultiplier(player: Player): number
	if not player then
		return 1.0
	end
	local summary = computeBonusForPlayer(player)
	return summary.friendBonusMult
end

function ViralSocialService.announce(
	category: string,
	headline: string,
	detail: string,
	accent: { number },
	suggestClip: boolean,
	clipLabel: string?
)
	local remotes = ensureSocialRemotes()
	local payload = ViralSocialLogic.buildAnnouncementPayload(
		category,
		headline,
		detail,
		accent,
		suggestClip,
		clipLabel
	)
	remotes.GlobalAnnouncement:FireAllClients(payload)
end

function ViralSocialService.recordProgress(
	player: Player,
	eventType: string,
	amount: number,
	context: { [string]: any }?
)
	if not player or type(eventType) ~= "string" then
		return
	end
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	local safeAmount = if type(amount) == "number" then amount else 1
	local res = ViralSocialLogic.recordProgressEvent(
		profile,
		player.DisplayName,
		eventType,
		safeAmount,
		os.time(),
		context
	)
	player:SetAttribute("WinStreak", (profile :: any).winStreak or 0)
	player:SetAttribute("BestWinStreak", (profile :: any).bestWinStreak or 0)
	for _, ann in ipairs(res.announcements) do
		ViralSocialService.announce(
			ann.category,
			ann.headline,
			ann.detail,
			ann.accent,
			ann.suggestClip,
			ann.clipLabel
		)
	end
	if eventType == "BossWin" or eventType == "OverchargedWin" or eventType == "PvPWin" then
		refreshLeaderboards(true)
	elseif res.questChanged or #res.announcements > 0 then
		syncPlayerState(player)
	end
end

function ViralSocialService.init()
	if isInitialized then
		return
	end
	isInitialized = true
	ensureSocialRemotes()
	updateHubLeaderboardBoards()
end

function ViralSocialService.start()
	if isStarted then
		return
	end
	isStarted = true
	local remotes = ensureSocialRemotes()
	remotes.QuickPing.OnServerEvent:Connect(handleQuickPing)
	remotes.RetentionAction.OnServerEvent:Connect(handleRetentionAction)

	DataService.onProfileLoaded(onPlayerLoaded)
	Players.PlayerAdded:Connect(bindPlayerSignals)
	Players.PlayerRemoving:Connect(cleanupDepartingPlayer)
	for _, plr in ipairs(Players:GetPlayers()) do
		bindPlayerSignals(plr)
	end

	task.spawn(function()
		while true do
			task.wait(5)
			refreshLeaderboards(true)
		end
	end)
end

return ViralSocialService
