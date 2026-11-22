--!strict
--[[
	CashPadView (Issue #11): pure display rules for Cash Pads and hatch reveals, so the client
	controllers only draw. Colours are plain {r,g,b} tables (0-1) to stay Roblox-free.
]]

-- selene: allow(incorrect_standard_library_use) -- string require: same path in Lune and Roblox
local ArenaHUDViewModel = require("./ArenaHUDViewModel")

export type RGB = { r: number, g: number, b: number }

local CashPadView = {}

local REVEAL_SECONDS = 3
local EASE_RATE = 6 -- per second: a visible climb, settled within ~0.2s
local BEAMS: { [string]: RGB } = {
	Normal = { r = 0.85, g = 0.95, b = 1.0 },
	Shiny = { r = 0.55, g = 0.95, b = 1.0 },
	Golden = { r = 1.0, g = 0.82, b = 0.25 },
	Overcharged = { r = 1.0, g = 0.45, b = 0.1 },
	VoidTouched = { r = 0.6, g = 0.25, b = 1.0 },
}

local function isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

-- What the pad holds right now, assuming the last server value plus local earning.
function CashPadView.predict(stored: number, rate: number, elapsed: number, cap: number): number
	if not isFinite(stored) then
		return 0 -- corrupt value: show nothing rather than a made-up prediction
	end
	local base = math.max(0, stored)
	local gain = if isFinite(rate)
			and rate > 0
			and isFinite(elapsed)
			and elapsed > 0
		then rate * elapsed
		else 0
	return math.min(cap, base + gain)
end

-- Smooth counter: climbs toward the target, drops at once (a sweep empties the pad).
function CashPadView.ease(shown: number, target: number, dt: number): number
	if target <= shown or math.abs(target - shown) < 0.1 then
		return target
	end
	return shown + (target - shown) * math.min(1, EASE_RATE * math.max(0, dt))
end

function CashPadView.chimePitch(streak: number): number
	if not isFinite(streak) or streak < 1 then
		return 1
	end
	return math.min(1.8, 1 + 0.08 * (math.floor(streak) - 1))
end

function CashPadView.beamColor(mutation: string): RGB
	return BEAMS[mutation] or BEAMS.Normal
end

function CashPadView.revealSeconds(): number
	return REVEAL_SECONDS
end

function CashPadView.label(stored: number, rate: number): string
	return `{ArenaHUDViewModel.formatNumber(stored)}\n+{ArenaHUDViewModel.formatNumber(rate)}/s`
end

return CashPadView
