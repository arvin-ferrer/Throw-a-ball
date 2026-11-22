--!strict
--[[
	ProjectileArc.luau
	Pure Luau ballistic trajectory prediction, swept segment sampling,
	and soft magnetic aim-assist math (PvE/Training vs mild PvP tuning).
	Zero Roblox globals required — runs identically in Roblox Studio and Lune tests.
]]

export type Vec3 = {
	X: number,
	Y: number,
	Z: number,
}

export type ArcConfig = {
	speed: number?,
	gravity: number?,
	maxDuration: number?,
	stepSeconds: number?,
}

export type ArcSegment = {
	startPos: Vec3,
	endPos: Vec3,
	delta: Vec3,
	tStart: number,
	tEnd: number,
}

export type AimCandidate = {
	id: string,
	position: Vec3,
	isPvP: boolean?,
	priority: number?,
}

export type AimAssistMode = "PvE" | "Training" | "PvP"

export type AimAssistConfig = {
	maxAngleDeg: number,
	blendStrength: number,
	maxRange: number,
}

local ProjectileArc = {}

ProjectileArc.DEFAULT_ARC_CONFIG = table.freeze({
	speed = 135,
	gravity = 42,
	maxDuration = 1.6,
	stepSeconds = 0.05,
})

ProjectileArc.AIM_ASSIST_PRESETS = table.freeze({
	PvE = table.freeze({
		maxAngleDeg = 14.0,
		blendStrength = 0.55,
		maxRange = 140,
	}),
	Training = table.freeze({
		maxAngleDeg = 15.0,
		blendStrength = 0.60,
		maxRange = 140,
	}),
	PvP = table.freeze({
		maxAngleDeg = 6.5,
		blendStrength = 0.22,
		maxRange = 110,
	}),
})

function ProjectileArc.vec3(x: number, y: number, z: number): Vec3
	return { X = x, Y = y, Z = z }
end

function ProjectileArc.add(a: Vec3, b: Vec3): Vec3
	return { X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z }
end

function ProjectileArc.sub(a: Vec3, b: Vec3): Vec3
	return { X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }
end

function ProjectileArc.scale(v: Vec3, scalar: number): Vec3
	return { X = v.X * scalar, Y = v.Y * scalar, Z = v.Z * scalar }
end

function ProjectileArc.dot(a: Vec3, b: Vec3): number
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end

function ProjectileArc.magnitude(v: Vec3): number
	return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
end

function ProjectileArc.distance(a: Vec3, b: Vec3): number
	return ProjectileArc.magnitude(ProjectileArc.sub(a, b))
end

function ProjectileArc.normalize(v: Vec3): Vec3
	local mag = ProjectileArc.magnitude(v)
	if mag < 1e-6 then
		return { X = 0, Y = 0, Z = -1 }
	end
	return { X = v.X / mag, Y = v.Y / mag, Z = v.Z / mag }
end

function ProjectileArc.lerp(a: Vec3, b: Vec3, alpha: number): Vec3
	local t = math.clamp(alpha, 0, 1)
	return {
		X = a.X + (b.X - a.X) * t,
		Y = a.Y + (b.Y - a.Y) * t,
		Z = a.Z + (b.Z - a.Z) * t,
	}
end

local function resolveArcParams(config: ArcConfig?): (number, number, number, number)
	local defaults = ProjectileArc.DEFAULT_ARC_CONFIG
	if not config then
		return defaults.speed, defaults.gravity, defaults.maxDuration, defaults.stepSeconds
	end
	return config.speed or defaults.speed,
		config.gravity or defaults.gravity,
		config.maxDuration or defaults.maxDuration,
		math.max(0.01, config.stepSeconds or defaults.stepSeconds)
end

function ProjectileArc.samplePosition(
	origin: Vec3,
	direction: Vec3,
	t: number,
	config: ArcConfig?
): Vec3
	local speed, gravity = resolveArcParams(config)
	local dir = ProjectileArc.normalize(direction)
	local clampedT = math.max(0, t)
	return {
		X = origin.X + dir.X * speed * clampedT,
		Y = origin.Y + dir.Y * speed * clampedT - 0.5 * gravity * clampedT * clampedT,
		Z = origin.Z + dir.Z * speed * clampedT,
	}
end

function ProjectileArc.sampleVelocity(direction: Vec3, t: number, config: ArcConfig?): Vec3
	local speed, gravity = resolveArcParams(config)
	local dir = ProjectileArc.normalize(direction)
	local clampedT = math.max(0, t)
	return {
		X = dir.X * speed,
		Y = dir.Y * speed - gravity * clampedT,
		Z = dir.Z * speed,
	}
end

function ProjectileArc.buildTrajectoryPoints(
	origin: Vec3,
	direction: Vec3,
	config: ArcConfig?
): { Vec3 }
	local _speed, _gravity, maxDuration, stepSeconds = resolveArcParams(config)
	local stepCount = math.max(1, math.floor((maxDuration / stepSeconds) + 0.5))
	local points: { Vec3 } = {}
	for i = 0, stepCount do
		local t = math.min(maxDuration, i * stepSeconds)
		table.insert(points, ProjectileArc.samplePosition(origin, direction, t, config))
	end
	return points
end

function ProjectileArc.buildSegments(
	origin: Vec3,
	direction: Vec3,
	config: ArcConfig?
): { ArcSegment }
	local _speed, _gravity, maxDuration, stepSeconds = resolveArcParams(config)
	local points = ProjectileArc.buildTrajectoryPoints(origin, direction, config)
	local segments: { ArcSegment } = {}
	for i = 1, #points - 1 do
		local startPos = points[i]
		local endPos = points[i + 1]
		local tStart = math.min(maxDuration, (i - 1) * stepSeconds)
		local tEnd = math.min(maxDuration, i * stepSeconds)
		table.insert(segments, {
			startPos = startPos,
			endPos = endPos,
			delta = ProjectileArc.sub(endPos, startPos),
			tStart = tStart,
			tEnd = tEnd,
		})
	end
	return segments
end

local function resolveAimConfig(modeOrConfig: (AimAssistMode | AimAssistConfig)?): AimAssistConfig
	if type(modeOrConfig) == "table" then
		return modeOrConfig
	end
	if type(modeOrConfig) == "string" then
		local preset = ProjectileArc.AIM_ASSIST_PRESETS[modeOrConfig]
		if preset then
			return preset
		end
	end
	return ProjectileArc.AIM_ASSIST_PRESETS.PvE
end

function ProjectileArc.applyAimAssist(
	origin: Vec3,
	rawDirection: Vec3,
	candidates: { AimCandidate },
	modeOrConfig: (AimAssistMode | AimAssistConfig)?
): (Vec3, AimCandidate?)
	local unitRaw = ProjectileArc.normalize(rawDirection)
	local cfg = resolveAimConfig(modeOrConfig)
	local minCos = math.cos(math.rad(math.clamp(cfg.maxAngleDeg, 0, 89)))
	local bestCandidate: AimCandidate? = nil
	local bestDir: Vec3? = nil
	local bestScore = -math.huge

	for _, candidate in ipairs(candidates) do
		local toTarget = ProjectileArc.sub(candidate.position, origin)
		local dist = ProjectileArc.magnitude(toTarget)
		if dist > 0.001 and dist <= cfg.maxRange then
			local unitTarget = ProjectileArc.scale(toTarget, 1 / dist)
			local cosAngle = ProjectileArc.dot(unitRaw, unitTarget)
			if cosAngle >= minCos then
				local score = cosAngle + (candidate.priority or 0) * 0.01
				if score > bestScore then
					bestScore = score
					bestCandidate = candidate
					bestDir = unitTarget
				end
			end
		end
	end

	if not bestCandidate or not bestDir then
		return unitRaw, nil
	end
	local blended = ProjectileArc.lerp(unitRaw, bestDir, cfg.blendStrength)
	return ProjectileArc.normalize(blended), bestCandidate
end

return ProjectileArc
