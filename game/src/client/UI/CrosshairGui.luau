--!strict
--[[
	CrosshairGui.luau
	Fixed center-screen FPS crosshair marking the ball's screen launch point.
	Uses IgnoreGuiInset + ScreenInsets.None so (0.5, 0.5) stays permanently aligned with
	the optical viewport center and third-person camera focus across PC, Tablet & Phone.
]]

local Players = game:GetService("Players")

local Theme = require(script.Parent.Theme)

local CrosshairGui = {}

local BASE_GAP = 8
local TARGET_GAP = 6
local MAX_RECOIL = 6
local STROKE_COLOR = Color3.fromRGB(12, 16, 24)
local NORMAL_COLOR = Color3.fromRGB(248, 252, 255)
local TARGET_COLOR = Color3.fromRGB(255, 96, 88)
local HIT_NORMAL_COLOR = Color3.fromRGB(255, 110, 96)
local HIT_CRIT_COLOR = Color3.fromRGB(250, 204, 21)

local crosshairScreen: ScreenGui? = nil
local crosshairRoot: Frame? = nil
local centerDot: Frame? = nil
local tickTop: Frame? = nil
local tickBottom: Frame? = nil
local tickLeft: Frame? = nil
local tickRight: Frame? = nil
local hitGroup: Frame? = nil
local hitBars: { Frame } = {}

local recoilOffset = 0
local hitTimer = 0

local function makeReticleBar(
	parent: Instance,
	name: string,
	w: number,
	h: number,
	rot: number?
): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromOffset(w, h)
	f.BackgroundColor3 = NORMAL_COLOR
	f.BorderSizePixel = 0
	f.Rotation = rot or 0
	f.Active = false
	f.Parent = parent
	Theme.addCorner(f, 2)
	Theme.addStroke(f, STROKE_COLOR, 1.2, 0.1)
	return f
end

local function buildHitMarkerGroup(root: Frame)
	local group = Instance.new("Frame")
	group.Name = "HitMarkerGroup"
	group.AnchorPoint = Vector2.new(0.5, 0.5)
	group.Position = UDim2.fromScale(0.5, 0.5)
	group.Size = UDim2.fromScale(1, 1)
	group.BackgroundTransparency = 1
	group.Active = false
	group.Visible = false
	group.Parent = root
	hitGroup = group

	table.clear(hitBars)
	local specs = {
		{ name = "HitTL", x = -8, y = -8, rot = -45 },
		{ name = "HitTR", x = 8, y = -8, rot = 45 },
		{ name = "HitBL", x = -8, y = 8, rot = 45 },
		{ name = "HitBR", x = 8, y = 8, rot = -45 },
	}
	for _, spec in ipairs(specs) do
		local bar = makeReticleBar(group, spec.name, 2, 8, spec.rot)
		bar.Position = UDim2.new(0.5, spec.x, 0.5, spec.y)
		table.insert(hitBars, bar)
	end
end

local function applyCrosshairColor(col: Color3)
	if centerDot then
		centerDot.BackgroundColor3 = col
	end
	for _, f in ipairs({ tickTop, tickBottom, tickLeft, tickRight }) do
		if f then
			f.BackgroundColor3 = col
		end
	end
end

function CrosshairGui.mount()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("BallBrawl_Crosshair")
	if existing and existing:IsA("ScreenGui") then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "BallBrawl_Crosshair"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 8
	gui.Parent = playerGui
	crosshairScreen = gui

	local root = Instance.new("Frame")
	root.Name = "CrosshairRoot"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(48, 48)
	root.BackgroundTransparency = 1
	root.Active = false
	root.Parent = gui
	crosshairRoot = root

	centerDot = makeReticleBar(root, "CenterDot", 4, 4)
	if centerDot then
		Theme.addCorner(centerDot, 999)
	end
	tickTop = makeReticleBar(root, "TickTop", 2, 7)
	tickBottom = makeReticleBar(root, "TickBottom", 2, 7)
	tickLeft = makeReticleBar(root, "TickLeft", 7, 2)
	tickRight = makeReticleBar(root, "TickRight", 7, 2)
	buildHitMarkerGroup(root)

	recoilOffset = 0
	hitTimer = 0
	CrosshairGui.setState(true, false, 0)
end

function CrosshairGui.pulseRecoil()
	recoilOffset = MAX_RECOIL
end

function CrosshairGui.flashHit(isCrit: boolean)
	hitTimer = 0.16
	local col = if isCrit then HIT_CRIT_COLOR else HIT_NORMAL_COLOR
	for _, bar in ipairs(hitBars) do
		bar.BackgroundColor3 = col
		bar.BackgroundTransparency = 0
	end
	if hitGroup then
		hitGroup.Visible = true
	end
end

function CrosshairGui.setState(visible: boolean, onTarget: boolean, dt: number)
	if not crosshairRoot then
		return
	end
	crosshairRoot.Visible = visible
	if dt > 0 then
		recoilOffset = math.max(0, recoilOffset - dt * 28)
		if hitTimer > 0 then
			hitTimer = math.max(0, hitTimer - dt)
			local alpha = 1 - math.clamp(hitTimer / 0.16, 0, 1)
			for _, bar in ipairs(hitBars) do
				bar.BackgroundTransparency = alpha
			end
			if hitGroup and hitTimer <= 0 then
				hitGroup.Visible = false
			end
		end
	end
	local gap = math.floor((if onTarget then TARGET_GAP else BASE_GAP) + recoilOffset + 0.5)
	if tickTop then
		tickTop.Position = UDim2.new(0.5, 0, 0.5, -gap)
	end
	if tickBottom then
		tickBottom.Position = UDim2.new(0.5, 0, 0.5, gap)
	end
	if tickLeft then
		tickLeft.Position = UDim2.new(0.5, -gap, 0.5, 0)
	end
	if tickRight then
		tickRight.Position = UDim2.new(0.5, gap, 0.5, 0)
	end
	applyCrosshairColor(if onTarget then TARGET_COLOR else NORMAL_COLOR)
end

function CrosshairGui.getScreenGui(): ScreenGui?
	return crosshairScreen
end

return CrosshairGui
