--!strict
--[[
	ArenaHUDView (Issue #7): builds the arena HUD instances once. Layout rules for phones:
	Scale-based sizes, safe-area insets, touch targets >= 56 px, and the claim button sits
	bottom-centre so it never overlaps the bottom-right jump button.
]]

export type View = {
	gui: ScreenGui,
	banner: Frame,
	bannerTitle: TextLabel,
	bannerTimer: TextLabel,
	bossBar: Frame,
	bossFill: Frame,
	bossText: TextLabel,
	stormPill: TextLabel,
	modal: Frame,
	modalTitle: TextLabel,
	modalTimer: TextLabel,
	modalDetails: TextLabel,
	joinButton: TextButton,
	stayButton: TextButton,
	queuedPill: TextButton,
	claim: Frame,
	claimFill: Frame,
	claimText: TextLabel,
	claimButton: TextButton,
	alert: TextLabel,
}

local TONES: { [string]: Color3 } = {
	Safe = Color3.fromRGB(70, 170, 110),
	Boss = Color3.fromRGB(200, 120, 40),
	PvP = Color3.fromRGB(210, 60, 60),
	SuddenDeath = Color3.fromRGB(150, 40, 200),
	Overcharged = Color3.fromRGB(255, 170, 30),
}

local ArenaHUDView = {}
ArenaHUDView.TONES = TONES

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function frame(
	name: string,
	parent: Instance,
	size: UDim2,
	pos: UDim2,
	anchor: Vector2
): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size, f.Position, f.AnchorPoint = size, pos, anchor
	f.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
	f.BackgroundTransparency = 0.2
	f.BorderSizePixel = 0
	f.Parent = parent
	corner(f, 12)
	return f
end

local function label(name: string, parent: Instance, size: UDim2, pos: UDim2): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size, l.Position = size, pos
	l.BackgroundTransparency = 1
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Font = Enum.Font.GothamBold
	l.TextScaled = true
	l.Text = ""
	l.Parent = parent
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 28
	limit.Parent = l
	return l
end

local function button(
	name: string,
	parent: Instance,
	text: string,
	color: Color3,
	size: UDim2,
	pos: UDim2
): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size, b.Position = size, pos
	b.BackgroundColor3 = color
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBlack
	b.TextScaled = true
	b.Text = text
	b.AutoButtonColor = true
	b.Parent = parent
	corner(b, 10)
	local minimum = Instance.new("UISizeConstraint")
	minimum.MinSize = Vector2.new(56, 56) -- comfortable thumb target
	minimum.Parent = b
	return b
end

local function buildBanner(gui: ScreenGui)
	local banner = frame(
		"Banner",
		gui,
		UDim2.fromScale(0.42, 0.09),
		UDim2.fromScale(0.5, 0.02),
		Vector2.new(0.5, 0)
	)
	local size = Instance.new("UISizeConstraint")
	size.MinSize, size.MaxSize = Vector2.new(260, 56), Vector2.new(560, 96)
	size.Parent = banner
	local title = label("Title", banner, UDim2.fromScale(0.7, 0.55), UDim2.fromScale(0.03, 0.05))
	title.TextXAlignment = Enum.TextXAlignment.Left
	local timer = label("Timer", banner, UDim2.fromScale(0.25, 0.55), UDim2.fromScale(0.72, 0.05))
	local bossBar = frame(
		"BossBar",
		banner,
		UDim2.fromScale(0.94, 0.3),
		UDim2.fromScale(0.03, 0.64),
		Vector2.zero
	)
	bossBar.BackgroundColor3 = Color3.fromRGB(50, 20, 20)
	local bossFill =
		frame("Fill", bossBar, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Vector2.zero)
	bossFill.BackgroundColor3 = Color3.fromRGB(220, 60, 50)
	bossFill.BackgroundTransparency = 0
	local bossText = label("HpText", bossBar, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0))
	bossText.ZIndex = 3
	local storm = label("StormPill", gui, UDim2.fromScale(0.3, 0.045), UDim2.fromScale(0.35, 0.12))
	storm.BackgroundTransparency, storm.BackgroundColor3 = 0.1, TONES.SuddenDeath
	corner(storm, 10)
	return banner, title, timer, bossBar, bossFill, bossText, storm
end

local function buildModal(gui: ScreenGui)
	local modal = frame(
		"OptInModal",
		gui,
		UDim2.fromScale(0.34, 0.32),
		UDim2.fromScale(0.5, 0.45),
		Vector2.new(0.5, 0.5)
	)
	local size = Instance.new("UISizeConstraint")
	size.MinSize, size.MaxSize = Vector2.new(280, 190), Vector2.new(480, 300)
	size.Parent = modal
	local title = label("Title", modal, UDim2.fromScale(0.9, 0.2), UDim2.fromScale(0.05, 0.05))
	local timer = label("Timer", modal, UDim2.fromScale(0.9, 0.16), UDim2.fromScale(0.05, 0.26))
	local details = label("Details", modal, UDim2.fromScale(0.9, 0.2), UDim2.fromScale(0.05, 0.43))
	details.Font = Enum.Font.Gotham
	local join = button(
		"Join",
		modal,
		"JOIN BOSS",
		TONES.Boss,
		UDim2.fromScale(0.43, 0.24),
		UDim2.fromScale(0.05, 0.7)
	)
	local stay = button(
		"Stay",
		modal,
		"STAY",
		Color3.fromRGB(70, 75, 90),
		UDim2.fromScale(0.43, 0.24),
		UDim2.fromScale(0.52, 0.7)
	)
	local pill = button(
		"QueuedPill",
		gui,
		"",
		TONES.Boss,
		UDim2.fromScale(0.24, 0.06),
		UDim2.fromScale(0.38, 0.13)
	)
	return modal, title, timer, details, join, stay, pill
end

local function buildClaim(gui: ScreenGui)
	local claim = frame(
		"ClaimRing",
		gui,
		UDim2.fromScale(0.32, 0.1),
		UDim2.fromScale(0.5, 0.7),
		Vector2.new(0.5, 0.5)
	)
	local bar =
		frame("Bar", claim, UDim2.fromScale(0.92, 0.32), UDim2.fromScale(0.04, 0.6), Vector2.zero)
	bar.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	local fill = frame("Fill", bar, UDim2.fromScale(0, 1), UDim2.fromScale(0, 0), Vector2.zero)
	fill.BackgroundColor3, fill.BackgroundTransparency = Color3.fromRGB(120, 255, 140), 0
	local text = label("Text", claim, UDim2.fromScale(0.92, 0.5), UDim2.fromScale(0.04, 0.05))
	-- Bottom-centre: thumbs reach it and it stays clear of the bottom-right jump button.
	local hold = button(
		"HoldToClaim",
		gui,
		"HOLD TO CLAIM",
		Color3.fromRGB(60, 170, 90),
		UDim2.fromScale(0.2, 0.1),
		UDim2.fromScale(0.4, 0.82)
	)
	return claim, fill, text, hold
end

function ArenaHUDView.build(parent: Instance): View
	local gui = Instance.new("ScreenGui")
	gui.Name = "ArenaHUD"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets -- notch and top-bar safe
	local banner, title, timer, bossBar, bossFill, bossText, storm = buildBanner(gui)
	local modal, modalTitle, modalTimer, details, join, stay, pill = buildModal(gui)
	local claim, claimFill, claimText, hold = buildClaim(gui)
	local alert =
		label("OverchargedAlert", gui, UDim2.fromScale(0.5, 0.06), UDim2.fromScale(0.25, 0.2))
	alert.TextColor3, alert.Text = TONES.Overcharged, "⚡ OVERCHARGED BOSS — 5-MIN EVENT! ⚡"
	gui.Parent = parent
	return {
		gui = gui,
		banner = banner,
		bannerTitle = title,
		bannerTimer = timer,
		bossBar = bossBar,
		bossFill = bossFill,
		bossText = bossText,
		stormPill = storm,
		modal = modal,
		modalTitle = modalTitle,
		modalTimer = modalTimer,
		modalDetails = details,
		joinButton = join,
		stayButton = stay,
		queuedPill = pill,
		claim = claim,
		claimFill = claimFill,
		claimText = claimText,
		claimButton = hold,
		alert = alert,
	}
end

return ArenaHUDView
