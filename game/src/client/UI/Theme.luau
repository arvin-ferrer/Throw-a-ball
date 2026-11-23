--!strict
--[[
	Theme.luau
	Mobile-first responsive UI tokens, glassmorphic dark-slate styling,
	and adaptive layout metrics for Phone (Landscape/Portrait), Tablet, and PC.
	Always uses ResetOnSpawn = false and CoreUISafeInsets.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

export type LayoutMetrics = {
	viewport: Vector2,
	isCompact: boolean,
	isPortrait: boolean,
	isTouch: boolean,
}

local Theme = {}

Theme.Colors = {
	Panel = Color3.fromRGB(22, 26, 36),
	PanelTop = Color3.fromRGB(32, 38, 52),
	PanelBottom = Color3.fromRGB(16, 20, 29),
	Card = Color3.fromRGB(18, 22, 32),
	CardAlt = Color3.fromRGB(34, 41, 56),
	Stroke = Color3.fromRGB(70, 82, 104),
	StrokeSoft = Color3.fromRGB(52, 62, 82),
	Text = Color3.fromRGB(248, 250, 252),
	Muted = Color3.fromRGB(186, 198, 218),
	Coins = Color3.fromRGB(252, 198, 62),
	Gems = Color3.fromRGB(196, 132, 255),
	Emerald = Color3.fromRGB(84, 232, 132),
	Frost = Color3.fromRGB(92, 204, 255),
	Molten = Color3.fromRGB(242, 122, 42),
	Danger = Color3.fromRGB(244, 86, 78),
	Overcharged = Color3.fromRGB(255, 114, 188),
	OverchargedBgTop = Color3.fromRGB(98, 24, 58),
	OverchargedBgBot = Color3.fromRGB(66, 14, 42),
	OverchargedStroke = Color3.fromRGB(186, 56, 118),
}

function Theme.getLayoutMetrics(): LayoutMetrics
	local cam = workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.new(1280, 720)
	local isPortrait = vp.Y > vp.X
	local isSmallDisplay = false
	pcall(function()
		isSmallDisplay = GuiService.ViewportDisplaySize == Enum.DisplaySize.Small
	end)
	local isCompact = isSmallDisplay or vp.X < 920 or vp.Y < 500
	local isTouch = UserInputService.PreferredInput == Enum.PreferredInput.Touch
	return {
		viewport = vp,
		isCompact = isCompact,
		isPortrait = isPortrait,
		isTouch = isTouch,
	}
end

function Theme.createScreenGui(name: string, displayOrder: number): ScreenGui
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild(name)
	if existing and existing:IsA("ScreenGui") then
		existing:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = displayOrder
	gui.Parent = playerGui
	return gui
end

function Theme.addCorner(inst: GuiObject, radius: number): UICorner
	local existing = inst:FindFirstChildOfClass("UICorner")
	if existing then
		existing.CornerRadius = UDim.new(0, radius)
		return existing
	end
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = inst
	return c
end

function Theme.addStroke(
	inst: GuiObject,
	color: Color3,
	thickness: number?,
	transparency: number?
): UIStroke
	local existing = inst:FindFirstChildOfClass("UIStroke")
	if existing then
		existing.Color = color
		existing.Thickness = thickness or 1.5
		existing.Transparency = transparency or 0
		return existing
	end
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 1.5
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = inst
	return s
end

function Theme.addGradient(
	inst: GuiObject,
	topColor: Color3,
	bottomColor: Color3,
	rotation: number?
): UIGradient
	local existing = inst:FindFirstChildOfClass("UIGradient")
	if existing then
		existing:Destroy()
	end
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(topColor, bottomColor)
	g.Rotation = rotation or 90
	g.Parent = inst
	return g
end

function Theme.addPadding(inst: GuiObject, px: number, py: number?)
	local p = Instance.new("UIPadding")
	local v = py or px
	p.PaddingTop = UDim.new(0, v)
	p.PaddingBottom = UDim.new(0, v)
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.Parent = inst
end

function Theme.makeFrame(
	parent: Instance,
	name: string,
	size: UDim2,
	pos: UDim2,
	bgColor: Color3?,
	radius: number?
): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = pos
	f.BackgroundColor3 = bgColor or Theme.Colors.Panel
	f.BackgroundTransparency = 0.06
	f.BorderSizePixel = 0
	f.Parent = parent
	Theme.addCorner(f, radius or 12)
	Theme.addStroke(f, Theme.Colors.Stroke, 1.5, 0.12)
	return f
end

function Theme.makeGlossyPanel(
	parent: Instance,
	name: string,
	size: UDim2,
	pos: UDim2,
	radius: number?
): Frame
	local f = Theme.makeFrame(parent, name, size, pos, Color3.fromRGB(255, 255, 255), radius or 14)
	f.BackgroundTransparency = 0.05
	Theme.addGradient(f, Theme.Colors.PanelTop, Theme.Colors.PanelBottom, 90)
	Theme.addStroke(f, Theme.Colors.Stroke, 1.6, 0.08)
	return f
end

function Theme.makeLabel(
	parent: Instance,
	name: string,
	text: string,
	size: UDim2,
	pos: UDim2,
	textSize: number,
	color: Color3?,
	bold: boolean?
): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.Name = name
	lbl.BackgroundTransparency = 1
	lbl.Size = size
	lbl.Position = pos
	lbl.Text = text
	lbl.TextColor3 = color or Theme.Colors.Text
	lbl.Font = if bold then Enum.Font.FredokaOne else Enum.Font.GothamMedium
	lbl.TextSize = textSize
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.AutoLocalize = false
	lbl.Parent = parent
	return lbl
end

function Theme.makeButton(
	parent: Instance,
	name: string,
	text: string,
	size: UDim2,
	pos: UDim2,
	bgColor: Color3,
	onClick: () -> ()
): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.Size = size
	btn.Position = pos
	btn.BackgroundColor3 = bgColor
	btn.Text = text
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Font = Enum.Font.FredokaOne
	btn.TextSize = 15
	btn.AutoButtonColor = true
	btn.BorderSizePixel = 0
	btn.AutoLocalize = false
	btn.Parent = parent
	Theme.addCorner(btn, 10)
	Theme.addStroke(btn, Color3.fromRGB(255, 255, 255), 1.2, 0.45)
	btn.Activated:Connect(onClick)
	return btn
end

return Theme
