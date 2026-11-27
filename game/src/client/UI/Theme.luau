--!strict
--[[
	Theme.luau
	Mobile-first responsive UI tokens, RBLX Essentials cartoon-pop design system,
	legacy glassmorphic slate helpers, and adaptive layout metrics for Phone, Tablet, and PC.
	Always uses ResetOnSpawn = false and CoreUISafeInsets.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
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
	-- RBLX Essentials General UI Kit cartoon-pop tokens
	WindowBg = Color3.fromRGB(248, 250, 255),
	Ink = Color3.fromRGB(18, 22, 32),
	ShopRedTop = Color3.fromRGB(255, 68, 58),
	ShopRedBot = Color3.fromRGB(224, 34, 34),
	HubBlueTop = Color3.fromRGB(56, 172, 255),
	HubBlueBot = Color3.fromRGB(28, 122, 232),
	CodexPurpleTop = Color3.fromRGB(168, 85, 247),
	CodexPurpleBot = Color3.fromRGB(122, 46, 214),
	MintTop = Color3.fromRGB(64, 242, 214),
	MintBot = Color3.fromRGB(32, 206, 236),
	LimeTop = Color3.fromRGB(116, 244, 72),
	LimeBot = Color3.fromRGB(54, 208, 72),
	GoldTop = Color3.fromRGB(255, 222, 74),
	GoldBot = Color3.fromRGB(245, 178, 24),
	TilePurpleTop = Color3.fromRGB(178, 92, 255),
	TilePurpleBot = Color3.fromRGB(130, 52, 226),
	TileSkyTop = Color3.fromRGB(64, 198, 255),
	TileSkyBot = Color3.fromRGB(28, 138, 236),
	TileGoldTop = Color3.fromRGB(255, 214, 68),
	TileGoldBot = Color3.fromRGB(238, 162, 24),
	TextDark = Color3.fromRGB(24, 30, 44),
	TextMutedDark = Color3.fromRGB(78, 90, 114),
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

local function findStrokeByMode(inst: GuiObject, mode: Enum.ApplyStrokeMode): UIStroke?
	for _, child in ipairs(inst:GetChildren()) do
		if child:IsA("UIStroke") and child.ApplyStrokeMode == mode then
			return child
		end
	end
	return nil
end

function Theme.addStroke(
	inst: GuiObject,
	color: Color3,
	thickness: number?,
	transparency: number?
): UIStroke
	local existing = findStrokeByMode(inst, Enum.ApplyStrokeMode.Border)
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

function Theme.addTextStroke(lbl: GuiObject, thickness: number?, color: Color3?): UIStroke
	local existing = findStrokeByMode(lbl, Enum.ApplyStrokeMode.Contextual)
	if existing then
		existing.Color = color or Theme.Colors.Ink
		existing.Thickness = thickness or 2
		existing.Transparency = 0
		return existing
	end
	local s = Instance.new("UIStroke")
	s.Name = "TextStroke"
	s.Color = color or Theme.Colors.Ink
	s.Thickness = thickness or 2
	s.Transparency = 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = lbl
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

local BOUNCE_TWEEN = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function Theme.attachBounce(btn: GuiButton)
	if btn:GetAttribute("HasBounce") == true then
		return
	end
	btn:SetAttribute("HasBounce", true)
	local existing = btn:FindFirstChildOfClass("UIScale")
	local scale = if existing then existing else Instance.new("UIScale")
	scale.Name = "BounceScale"
	scale.Scale = 1
	scale.Parent = btn

	local isHovering = false
	local function tweenTo(target: number)
		TweenService:Create(scale, BOUNCE_TWEEN, { Scale = target }):Play()
	end
	btn.MouseEnter:Connect(function()
		isHovering = true
		tweenTo(1.04)
	end)
	btn.MouseLeave:Connect(function()
		isHovering = false
		tweenTo(1)
	end)
	btn.MouseButton1Down:Connect(function()
		tweenTo(0.94)
	end)
	btn.MouseButton1Up:Connect(function()
		tweenTo(if isHovering then 1.04 else 1)
	end)
end

function Theme.makeCartoonWindow(
	parent: Instance,
	name: string,
	size: UDim2,
	pos: UDim2,
	radius: number?
): Frame
	local win = Instance.new("Frame")
	win.Name = name
	win.Size = size
	win.Position = pos
	win.BackgroundColor3 = Theme.Colors.WindowBg
	win.BackgroundTransparency = 0
	win.BorderSizePixel = 0
	win.ClipsDescendants = true
	win.Parent = parent
	Theme.addCorner(win, radius or 16)
	Theme.addStroke(win, Theme.Colors.Ink, 3, 0)
	return win
end

local function makeBannerCloseButton(bar: Frame, onClose: () -> ()): TextButton
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.fromOffset(44, 44)
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, -8, 0.5, -1)
	closeBtn.BackgroundTransparency = 1
	closeBtn.BorderSizePixel = 0
	closeBtn.Text = "X"
	closeBtn.Font = Enum.Font.FredokaOne
	closeBtn.TextSize = 26
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.AutoLocalize = false
	closeBtn.Parent = bar
	Theme.addTextStroke(closeBtn, 2.2, Theme.Colors.Ink)
	Theme.attachBounce(closeBtn)
	closeBtn.Activated:Connect(onClose)
	return closeBtn
end

function Theme.makeHeaderBanner(
	parent: Instance,
	titleText: string,
	topCol: Color3,
	botCol: Color3,
	onClose: () -> ()
): (Frame, TextLabel, TextButton)
	local bar = Instance.new("Frame")
	bar.Name = "HeaderBanner"
	bar.Size = UDim2.new(1, 0, 0, 52)
	bar.Position = UDim2.fromOffset(0, 0)
	bar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	bar.BorderSizePixel = 0
	bar.Parent = parent
	Theme.addGradient(bar, topCol, botCol, 90)

	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.Size = UDim2.new(1, 0, 0, 3)
	divider.Position = UDim2.new(0, 0, 1, -3)
	divider.BackgroundColor3 = Theme.Colors.Ink
	divider.BorderSizePixel = 0
	divider.ZIndex = 3
	divider.Parent = bar

	local title = Theme.makeLabel(
		bar,
		"Title",
		titleText,
		UDim2.new(1, -68, 1, -4),
		UDim2.fromOffset(18, 0),
		24,
		Color3.fromRGB(255, 255, 255),
		true
	)
	title.TextYAlignment = Enum.TextYAlignment.Center
	Theme.addTextStroke(title, 2.2, Theme.Colors.Ink)
	local closeBtn = makeBannerCloseButton(bar, onClose)
	return bar, title, closeBtn
end

local function addTopGloss(card: Frame, insetX: number, heightScale: number, radius: number)
	local gloss = Instance.new("Frame")
	gloss.Name = "TopGloss"
	gloss.Size = UDim2.new(1, -insetX * 2, heightScale, 0)
	gloss.Position = UDim2.fromOffset(insetX, 4)
	gloss.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	gloss.BackgroundTransparency = 0.78
	gloss.BorderSizePixel = 0
	gloss.Active = false
	gloss.ZIndex = 0
	gloss.Parent = card
	Theme.addCorner(gloss, radius)
end

function Theme.makeHeroBannerCard(
	parent: Instance,
	name: string,
	height: number,
	topCol: Color3,
	botCol: Color3
): Frame
	local card = Instance.new("Frame")
	card.Name = name
	card.Size = UDim2.new(1, 0, 0, height)
	card.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	card.BorderSizePixel = 0
	card.ClipsDescendants = true
	card.Parent = parent
	Theme.addCorner(card, 14)
	Theme.addGradient(card, topCol, botCol, 90)
	Theme.addStroke(card, Theme.Colors.Ink, 2.5, 0)
	addTopGloss(card, 6, 0.42, 10)
	return card
end

function Theme.makeTileCard(
	parent: Instance,
	name: string,
	size: UDim2,
	topCol: Color3,
	botCol: Color3
): Frame
	local card = Instance.new("Frame")
	card.Name = name
	card.Size = size
	card.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	card.BorderSizePixel = 0
	card.ClipsDescendants = true
	card.Parent = parent
	Theme.addCorner(card, 12)
	Theme.addGradient(card, topCol, botCol, 90)
	Theme.addStroke(card, Theme.Colors.Ink, 2.5, 0)
	addTopGloss(card, 4, 0.34, 8)
	return card
end

function Theme.makeGoldPillButton(
	parent: Instance,
	name: string,
	text: string,
	size: UDim2,
	pos: UDim2,
	onClick: () -> (),
	topCol: Color3?,
	botCol: Color3?
): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.Size = size
	btn.Position = pos
	btn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	btn.Text = text
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Font = Enum.Font.FredokaOne
	btn.TextSize = 16
	btn.AutoButtonColor = false
	btn.BorderSizePixel = 0
	btn.AutoLocalize = false
	btn.Parent = parent
	Theme.addCorner(btn, 999)
	Theme.addGradient(btn, topCol or Theme.Colors.GoldTop, botCol or Theme.Colors.GoldBot, 90)
	Theme.addStroke(btn, Theme.Colors.Ink, 2, 0)
	Theme.addTextStroke(btn, 1.8, Theme.Colors.Ink)
	Theme.attachBounce(btn)
	btn.Activated:Connect(onClick)
	return btn
end

return Theme
