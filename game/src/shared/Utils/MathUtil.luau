--!strict
--[[
	MathUtil.luau
	Pure Luau math, safety validation (NaN/Inf), Power Rating, throw-speed
	diminishing returns, and compact UI formatting helpers (Lune & Roblox safe).
]]

local MathUtil = {}

MathUtil.BASE_THROW_COOLDOWN = 0.55
MathUtil.MIN_THROW_COOLDOWN = 0.16

function MathUtil.isFinite(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	return value == value and value ~= math.huge and value ~= -math.huge
end

function MathUtil.isPositiveFinite(value: any): boolean
	return MathUtil.isFinite(value) and (value :: number) > 0
end

-- Diminishing returns curve so Throw Speed feels snappier without breaking readability
function MathUtil.computeThrowCooldown(throwSpeedStat: number, bonusMult: number?): number
	local effectiveSpeed = math.max(1.0, throwSpeedStat) * (1 + math.max(0, bonusMult or 0))
	local extra = math.max(0, effectiveSpeed - 1.0)
	local reduction = extra / (extra + 2.5)
	local cd = MathUtil.BASE_THROW_COOLDOWN * (1 - 0.70 * reduction)
	return math.clamp(cd, MathUtil.MIN_THROW_COOLDOWN, MathUtil.BASE_THROW_COOLDOWN)
end

function MathUtil.computeProjectileSpeed(ballBaseSpeed: number, throwSpeedStat: number): number
	local extra = math.max(0, throwSpeedStat - 1.0)
	local speedMult = 1 + 0.35 * (extra / (extra + 3.0))
	return ballBaseSpeed * speedMult
end

function MathUtil.computePowerRating(
	ballDamage: number,
	ballTierMult: number,
	throwSpeed: number,
	maxHP: number,
	activePetIncomeSum: number
): number
	local dps = math.max(1, ballDamage * ballTierMult) / MathUtil.computeThrowCooldown(throwSpeed)
	local score = dps * 1.4 + maxHP * 0.35 + activePetIncomeSum * 0.25
	return math.floor(score + 0.5)
end

function MathUtil.formatNumber(value: number): string
	if not MathUtil.isFinite(value) then
		return "0"
	end
	local absVal = math.abs(value)
	local sign = if value < 0 then "-" else ""
	if absVal >= 1e9 then
		return string.format("%s%.2fB", sign, absVal / 1e9)
	elseif absVal >= 1e6 then
		return string.format("%s%.2fM", sign, absVal / 1e6)
	elseif absVal >= 1e3 then
		return string.format("%s%.1fK", sign, absVal / 1e3)
	end
	return string.format("%s%d", sign, math.floor(absVal + 0.5))
end

function MathUtil.formatClock(seconds: number): string
	local clamped = math.max(0, math.ceil(seconds))
	local mins = math.floor(clamped / 60)
	local secs = clamped % 60
	return string.format("%d:%02d", mins, secs)
end

function MathUtil.distance2D(ax: number, az: number, bx: number, bz: number): number
	local dx = ax - bx
	local dz = az - bz
	return math.sqrt(dx * dx + dz * dz)
end

function MathUtil.distance3D(
	ax: number,
	ay: number,
	az: number,
	bx: number,
	by: number,
	bz: number
): number
	local dx = ax - bx
	local dy = ay - by
	local dz = az - bz
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

return MathUtil
