--!strict
--[[
	CombatService (Issue #5): the only place ball damage is decided. Validates ThrowBall
	intent (CombatMath), sweeps PR #22's arc against players, boss, mobs and training
	targets, lets real map geometry block the ball, then applies server-side damage.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfigs = require(Shared.Configs.CombatConfigs)
local CombatMath = require(Shared.Utils.CombatMath)
local Remotes = require(Shared.Net.Remotes)

type Vec3 = CombatMath.Vec3
type SweepTarget = CombatMath.SweepTarget

export type Hooks = {
	canDealPvPDamage: (attacker: Player, victim: Player) -> boolean,
	notifyPvPDamage: (victim: Player, amount: number, attacker: Player?) -> (),
	getFighterBiome: (player: Player) -> string?,
	getBossTarget: (biomeId: string) -> SweepTarget?,
	damageBoss: (biomeId: string, amount: number, attackerId: number) -> (),
	-- Mobs the attacker may hit: same biome PvE layer, never from inside a locked room.
	getMobTargets: (attacker: Player) -> { SweepTarget },
	-- On a kill: the mob kind and its biome's PvE damage multiplier (GDD §6: 1.5x–6x).
	damageMob: (mobId: string, amount: number, attacker: Player) -> (string?, number?),
	grantCoins: (player: Player, amount: number, reason: string) -> (),
	getTrainingMultiplier: (player: Player) -> number, -- Soft Ascension bonus
}

local THROW = CombatConfigs.Throw
local TRAINING = CombatConfigs.Training
local PAD_TAGS = { "TrainingFiringPad", "TrainingPad" } -- map contract + PR #22's tag
local TARGET_TAGS = { "TrainingTarget", "MovingGoldTarget" }

local CombatService = {}

local hooks: Hooks? = nil
local remotesFolder: Folder? = nil
local rateStates: { [Player]: CombatMath.ThrowRateState } = {}

-- Player stats --------------------------------------------------------------------------------
-- Training stats live in Player attributes; EconomyService loads and persists them (#9).

local function stat(player: Player, name: string, default: any): any
	local value = player:GetAttribute(name)
	return if value == nil then default else value
end

local function initStats(player: Player)
	player:SetAttribute("BallDamage", stat(player, "BallDamage", THROW.DEFAULT_BASE_BALL_DAMAGE))
	player:SetAttribute("ThrowSpeed", stat(player, "ThrowSpeed", 0))
	player:SetAttribute("BallTier", stat(player, "BallTier", "RubberBall"))
	player:SetAttribute("Level", stat(player, "Level", 1))
	player:SetAttribute("Exp", stat(player, "Exp", 0))
end

function CombatService.grantExp(player: Player, amount: number)
	local level, exp, maxHp =
		CombatMath.applyExp(stat(player, "Level", 1), stat(player, "Exp", 0), amount)
	player:SetAttribute("Level", level)
	player:SetAttribute("Exp", exp)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.MaxHealth ~= maxHp then
		humanoid.MaxHealth = maxHp
	end
end

local function addStat(player: Player, name: string, amount: number)
	player:SetAttribute(name, stat(player, name, 0) + amount)
end

-- Targets ---------------------------------------------------------------------------------------

local function toVec3(v: Vector3): Vec3
	return { X = v.X, Y = v.Y, Z = v.Z }
end

local function rootOf(player: Player): BasePart?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Only opponents this attacker may legally hit are solid to the ball; everyone else (Hub,
-- PvE, dead, grace period) is see-through, so they can't soak a throw meant for the boss.
local function playerTargets(attacker: Player): { SweepTarget }
	local targets = {}
	local h = hooks :: Hooks
	for _, other in Players:GetPlayers() do
		local root = rootOf(other)
		if other ~= attacker and root and h.canDealPvPDamage(attacker, other) then
			local id, radius = tostring(other.UserId), THROW.PLAYER_HIT_RADIUS_STUDS
			table.insert(
				targets,
				{ id = id, kind = "Player", position = toVec3(root.Position), radius = radius }
			)
		end
	end
	return targets
end

local function trainingTargets(): ({ SweepTarget }, { [string]: BasePart })
	local targets, byId = {}, {}
	for _, tag in TARGET_TAGS do
		for _, part in CollectionService:GetTagged(tag) do
			if part:IsA("BasePart") and not byId[part:GetFullName()] then
				local id = part:GetFullName()
				byId[id] = part
				local radius = math.max(part.Size.X, part.Size.Y, part.Size.Z) / 2
				table.insert(
					targets,
					{ id = id, kind = "Target", position = toVec3(part.Position), radius = radius }
				)
			end
		end
	end
	return targets, byId
end

local function gatherTargets(attacker: Player): ({ SweepTarget }, { [string]: BasePart })
	local targets = playerTargets(attacker)
	local h = hooks :: Hooks
	local biomeId = h.getFighterBiome(attacker)
	local boss = biomeId and h.getBossTarget(biomeId)
	if boss then
		table.insert(targets, boss)
	end
	local mobs: { SweepTarget } = if biomeId then {} else h.getMobTargets(attacker)
	for _, mob in mobs do
		table.insert(targets, mob)
	end
	local training, byId = trainingTargets()
	for _, t in training do
		table.insert(targets, t)
	end
	return targets, byId
end

-- Sweep --------------------------------------------------------------------------------------

-- Only real map geometry blocks a ball. Characters and training targets are resolved as
-- spheres instead (boss and mob parts are CanQuery=false, so rays never see them).
local function worldParams(): RaycastParams
	local ignore: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	for _, tag in TARGET_TAGS do
		for _, part in CollectionService:GetTagged(tag) do
			table.insert(ignore, part)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true -- decorations without collision never block a ball
	return params
end

local function earliestTarget(
	seg: CombatMath.ArcSegment,
	ballRadius: number,
	targets: { SweepTarget },
	excludeId: string
): (number?, SweepTarget?)
	local bestS: number?, best: SweepTarget? = nil, nil
	for _, t in targets do
		if t.id ~= excludeId then
			local s = CombatMath.intersectSegmentSphere(
				seg.startPos,
				seg.endPos,
				t.position,
				t.radius + ballRadius
			)
			if s and (bestS == nil or s < bestS) then
				bestS, best = s, t
			end
		end
	end
	return bestS, best
end

-- Segment by segment along PR #22's arc: the earliest of (target sphere, real map
-- geometry via raycast) wins, so a wall between thrower and target always stops the ball.
local function sweep(
	attacker: Player,
	origin: Vec3,
	dir: Vec3,
	speed: number,
	targets: { SweepTarget }
): CombatMath.SweepHit
	local cfg = {
		speed = speed,
		gravity = THROW.GRAVITY,
		maxDuration = THROW.MAX_FLIGHT_SECONDS,
		stepSeconds = THROW.SWEEP_STEP_SECONDS,
	}
	local tier = CombatConfigs.BallTiers[stat(attacker, "BallTier", "RubberBall")]
		or CombatConfigs.BallTiers.RubberBall
	local params = worldParams()
	for _, seg in CombatMath.buildArcSegments(origin, dir, cfg) do
		local a = Vector3.new(seg.startPos.X, seg.startPos.Y, seg.startPos.Z)
		local delta = Vector3.new(seg.endPos.X, seg.endPos.Y, seg.endPos.Z) - a
		local ray = Workspace:Raycast(a, delta, params)
		local worldS = if ray then (ray.Position - a).Magnitude / delta.Magnitude else nil
		local targetS, target =
			earliestTarget(seg, tier.ballRadius, targets, tostring(attacker.UserId))
		local span = seg.tEnd - seg.tStart
		if ray and worldS and (targetS == nil or worldS < targetS) then
			return {
				hit = true,
				hitKind = "World",
				hitPosition = toVec3(ray.Position),
				t = seg.tStart + span * worldS,
			}
		elseif targetS and target then
			local at = CombatMath.lerp(seg.startPos, seg.endPos, targetS)
			return {
				hit = true,
				hitKind = target.kind,
				target = target,
				hitPosition = at,
				t = seg.tStart + span * targetS,
			}
		end
	end
	return { hit = false, hitKind = "None" }
end

-- Applying hits -------------------------------------------------------------------------------

local function plotOf(inst: Instance): Instance?
	local node: Instance? = inst
	while node and node:GetAttribute("PlotId") == nil do
		node = node.Parent
	end
	return node
end

-- The attacker must stand on a firing pad of the same plot as the target they hit.
local function onOwnPad(attacker: Player, target: BasePart): boolean
	local root = rootOf(attacker)
	local plot = plotOf(target)
	if not (root and plot) then
		return false
	end
	for _, tag in PAD_TAGS do
		for _, pad in CollectionService:GetTagged(tag) do
			if pad:IsA("BasePart") and pad:IsDescendantOf(plot) then
				local half = pad.Size / 2
					+ Vector3.new(TRAINING.PAD_HORIZONTAL_MARGIN, 0, TRAINING.PAD_HORIZONTAL_MARGIN)
				local box = {
					center = toVec3(pad.Position),
					halfSize = toVec3(half),
					minY = TRAINING.PAD_MIN_Y,
					maxY = TRAINING.PAD_MAX_Y,
					ownerUserId = tonumber(plot:GetAttribute("OwnerUserId")) or 0,
				}
				if
					CombatMath.isPointOnOwnedPad(toVec3(root.Position), attacker.UserId, box, false)
				then
					return true
				end
			end
		end
	end
	return false
end

local function hitTrainingTarget(attacker: Player, part: BasePart)
	if not onOwnPad(attacker, part) then
		return
	end
	local range = part:FindFirstAncestor("TrainingRange")
	local tier = tostring(range and range:GetAttribute("TargetTier") or "WoodenDummy")
	local damageGain, speedGain =
		CombatMath.computeTrainingGain(tier, CollectionService:HasTag(part, "MovingGoldTarget"))
	local multiplier = (hooks :: Hooks).getTrainingMultiplier(attacker)
	addStat(attacker, "BallDamage", damageGain * multiplier)
	addStat(attacker, "ThrowSpeed", speedGain * multiplier)
end

local function applyHit(
	attacker: Player,
	hit: CombatMath.SweepHit,
	damage: number,
	byId: { [string]: BasePart }
)
	local h = hooks :: Hooks
	local target = hit.target
	if not target then
		return
	end
	if target.kind == "Player" then
		local victim = Players:GetPlayerByUserId(tonumber(target.id) or 0)
		local humanoid = victim
			and victim.Character
			and victim.Character:FindFirstChildOfClass("Humanoid")
		if victim and humanoid and h.canDealPvPDamage(attacker, victim) then
			humanoid:TakeDamage(damage)
			h.notifyPvPDamage(victim, damage, attacker)
		end
	elseif target.kind == "Boss" and h.getFighterBiome(attacker) == target.id then
		h.damageBoss(target.id, damage, attacker.UserId)
	elseif target.kind == "Mob" then
		local killed, biomeMultiplier = h.damageMob(target.id, damage, attacker)
		if killed then
			local exp, progress, coins = CombatMath.computeMobRewards(killed, biomeMultiplier or 1)
			CombatService.grantExp(attacker, exp)
			addStat(attacker, "BallDamage", progress)
			h.grantCoins(attacker, coins, "MobKill")
		end
	elseif target.kind == "Target" and byId[target.id] then
		hitTrainingTarget(attacker, byId[target.id])
	end
end

local function onThrowBall(player: Player, payload: unknown)
	local root = rootOf(player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not (root and humanoid and humanoid.Health > 0 and hooks and remotesFolder) then
		return
	end
	local rate = rateStates[player] or CombatMath.newRateState()
	rateStates[player] = rate
	local throwSpeed = stat(player, "ThrowSpeed", 0)
	local valid = CombatMath.validateThrowPayload(
		payload,
		toVec3(root.Position),
		rate,
		throwSpeed,
		os.clock()
	)
	if not valid.ok or not valid.origin or not valid.direction then
		return
	end
	local o = valid.origin
	local toOrigin = Vector3.new(o.X, o.Y, o.Z) - root.Position
	if toOrigin.Magnitude > 0.05 and Workspace:Raycast(root.Position, toOrigin, worldParams()) then
		return -- release point behind cover: an origin can't be smuggled through a wall
	end
	local speed =
		CombatMath.computeProjectileSpeed(stat(player, "BallTier", "RubberBall"), throwSpeed)
	local targets, byId = gatherTargets(player)
	-- shortcut: hits resolve instantly along the arc (no travel delay); fine for the ~1s flights here.
	local hit = sweep(player, valid.origin, valid.direction, speed, targets)
	local damage = CombatMath.computeBallDamage(
		stat(player, "BallDamage", 0),
		stat(player, "BallTier", "RubberBall")
	)
	applyHit(player, hit, damage, byId)
	Remotes.getEvent(remotesFolder, Remotes.Names.BallHit):FireAllClients({
		attackerUserId = player.UserId,
		origin = valid.origin,
		direction = valid.direction,
		speed = speed,
		hitKind = hit.hitKind,
		hitPosition = hit.hitPosition,
		flightSeconds = hit.t,
	})
end

-- Public API -------------------------------------------------------------------------------------

function CombatService.init(folder: Folder, serviceHooks: Hooks)
	remotesFolder = folder
	hooks = serviceHooks
	Remotes.getEvent(folder, Remotes.Names.ThrowBall).OnServerEvent:Connect(onThrowBall)
	Players.PlayerAdded:Connect(initStats)
	for _, player in Players:GetPlayers() do
		initStats(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		rateStates[player] = nil
	end)
end

return CombatService
