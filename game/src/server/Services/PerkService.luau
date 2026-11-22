--!strict
--[[
	PerkService (Issue #14): applies Active Ball Perks (pure ActivePerks) on the server.
	Followers come from the saved profile (activePetIds), rolls from the server RNG. Every
	extra hit (burn tick, ricochet, splash) goes back through CombatService's damage step, so
	the PvP gate still applies and a burn tick cancels an enemy's 5s egg claim (GDD §8.3).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ActivePerks = require(Shared.Utils.ActivePerks)
local CombatMath = require(Shared.Utils.CombatMath)
local DataService = require(script.Parent.DataService)

type SweepTarget = CombatMath.SweepTarget
type DealDamage = (target: SweepTarget, amount: number) -> ()

local BURN_TICKS = 3
local LEECH_CAP_FRACTION = 0.10 -- of max HP per second ("capped per second", GDD §8.3)
local SHIELD_COOLDOWN = 8 -- one shield per 8s, so fast throws can't chain invulnerability

local PerkService = {}

local rng = Random.new()
local leechWindow: { [Player]: { start: number, healed: number } } = {}
local shieldReadyAt: { [Player]: number } = {}

function PerkService.perksOf(player: Player): ActivePerks.Perks
	local data = DataService.get(player)
	if not data then
		return {}
	end
	local pets = {}
	for _, petId in data.activePetIds do
		local pet = data.petsById[petId]
		if pet then
			table.insert(pets, pet)
		end
	end
	return ActivePerks.resolve(pets)
end

function PerkService.trainingMultiplier(player: Player): number
	return ActivePerks.trainingMultiplier(PerkService.perksOf(player))
end

function PerkService.rollHit(player: Player, baseDamage: number): ActivePerks.HitEffects
	return ActivePerks.onHit(PerkService.perksOf(player), baseDamage, rng:NextNumber())
end

local function humanoidOf(target: SweepTarget): (Humanoid?, BasePart?)
	if target.kind ~= "Player" then
		return nil, nil
	end
	local victim = Players:GetPlayerByUserId(tonumber(target.id) or 0)
	local character = victim and victim.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return character and character:FindFirstChildOfClass("Humanoid"),
		if root and root:IsA("BasePart") then root else nil
end

-- Slow / stun a rival for a while; the latest expiry wins so overlapping effects don't
-- restore speed early.
local function slowPlayer(humanoid: Humanoid, fraction: number, seconds: number)
	local base = humanoid:GetAttribute("BaseWalkSpeed") or humanoid.WalkSpeed
	humanoid:SetAttribute("BaseWalkSpeed", base)
	local untilTime = os.clock() + seconds
	humanoid:SetAttribute("SlowUntil", math.max(humanoid:GetAttribute("SlowUntil") or 0, untilTime))
	humanoid.WalkSpeed = base * (1 - math.clamp(fraction, 0, 1))
	task.delay(seconds, function()
		if os.clock() + 0.01 >= (humanoid:GetAttribute("SlowUntil") or 0) then
			humanoid.WalkSpeed = base
		end
	end)
end

local function nearbyTargets(
	primary: SweepTarget,
	at: CombatMath.Vec3,
	range: number,
	targets: { SweepTarget }
): { SweepTarget }
	local found = {}
	for _, t in targets do
		if
			t.id ~= primary.id
			and t.kind ~= "Target"
			and CombatMath.length(CombatMath.sub(t.position, at)) <= range
		then
			table.insert(found, t)
		end
	end
	table.sort(found, function(a, b)
		return CombatMath.length(CombatMath.sub(a.position, at))
			< CombatMath.length(CombatMath.sub(b.position, at))
	end)
	return found
end

local function leech(attacker: Player, amount: number)
	local humanoid = attacker.Character and attacker.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local now, window = os.clock(), leechWindow[attacker]
	if not window or now - window.start >= 1 then
		window = { start = now, healed = 0 }
		leechWindow[attacker] = window
	end
	local heal = math.min(amount, humanoid.MaxHealth * LEECH_CAP_FRACTION - window.healed)
	if heal > 0 then
		window.healed += heal
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + heal)
	end
end

local function shield(attacker: Player, seconds: number)
	local now = os.clock()
	local character = attacker.Character
	if character and now >= (shieldReadyAt[attacker] or 0) then
		shieldReadyAt[attacker] = now + SHIELD_COOLDOWN
		local field = Instance.new("ForceField")
		field.Visible = true
		field.Parent = character
		task.delay(seconds, function()
			field:Destroy()
		end)
	end
end

local function burn(primary: SweepTarget, fx: ActivePerks.HitEffects, deal: DealDamage)
	local b = fx.burn
	if not b then
		return
	end
	for i = 1, BURN_TICKS do
		task.delay(b.seconds * i / BURN_TICKS, deal, primary, b.totalDamage / BURN_TICKS)
	end
end

-- Everything a hit does besides its main damage.
function PerkService.applySideEffects(
	attacker: Player,
	primary: SweepTarget,
	at: CombatMath.Vec3,
	fx: ActivePerks.HitEffects,
	targets: { SweepTarget },
	deal: DealDamage
)
	local humanoid, root = humanoidOf(primary)
	if humanoid and fx.slow then
		slowPlayer(humanoid, fx.slow.fraction, fx.slow.seconds)
	end
	if humanoid and fx.stunSeconds then
		slowPlayer(humanoid, 1, fx.stunSeconds)
	end
	if root and fx.knockback then
		local away = Vector3.new(root.Position.X - at.X, 0, root.Position.Z - at.Z)
		local dir = if away.Magnitude > 0.01 then away.Unit else Vector3.zAxis
		root.AssemblyLinearVelocity += dir * fx.knockback + Vector3.new(0, 15, 0)
	end
	burn(primary, fx, deal)
	if fx.ricochet then
		local next = nearbyTargets(primary, at, fx.ricochet.range, targets)[1]
		if next then
			deal(next, fx.ricochet.damage)
		end
	end
	if fx.splash then
		for _, t in nearbyTargets(primary, at, fx.splash.radius, targets) do
			deal(t, fx.splash.damage)
		end
	end
	if fx.leech then
		leech(attacker, fx.leech)
	end
	if fx.shieldSeconds then
		shield(attacker, fx.shieldSeconds)
	end
end

Players.PlayerRemoving:Connect(function(player)
	leechWindow[player] = nil
	shieldReadyAt[player] = nil
end)

return PerkService
