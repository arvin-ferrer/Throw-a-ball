--!strict
--[[
	HudIcons.luau
	Resolution-independent procedural vector icons for the Ball Brawl mobile HUD.
	Zero external asset dependencies — razor sharp on phones, tablets, and 4K PC displays.
]]

local Theme = require(script.Parent.Theme)

local HudIcons = {}

local function makeRoot(parent: Instance, name: string, px: number): Frame
	local root = Instance.new("Frame")
	root.Name = name
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(px, px)
	root.Active = false
	root.Parent = parent
	return root
end

local function part(
	parent: Instance,
	name: string,
	size: UDim2,
	pos: UDim2,
	color: Color3,
	radius: number?,
	rot: number?
): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = size
	f.Position = pos
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Rotation = rot or 0
	f.Parent = parent
	if radius and radius > 0 then
		Theme.addCorner(f, radius)
	end
	return f
end

function HudIcons.createCoinIcon(parent: Instance, px: number): Frame
	local root = makeRoot(parent, "CoinIcon", px)

	local outer = part(
		root,
		"Outer",
		UDim2.fromScale(0.92, 0.92),
		UDim2.fromScale(0.5, 0.5),
		Color3.fromRGB(255, 255, 255),
		999
	)
	Theme.addGradient(outer, Theme.Colors.GoldTop, Color3.fromRGB(224, 146, 22), 90)
	Theme.addStroke(outer, Theme.Colors.Ink, 1.8)

	local inner = part(
		outer,
		"Inner",
		UDim2.fromScale(0.62, 0.62),
		UDim2.fromScale(0.5, 0.5),
		Color3.fromRGB(255, 206, 56),
		999
	)
	Theme.addStroke(inner, Color3.fromRGB(204, 128, 18), 1.2)
	return root
end

function HudIcons.createGemIcon(parent: Instance, px: number): Frame
	local root = makeRoot(parent, "GemIcon", px)

	local body = part(
		root,
		"Diamond",
		UDim2.fromScale(0.66, 0.66),
		UDim2.fromScale(0.5, 0.52),
		Color3.fromRGB(255, 255, 255),
		3,
		45
	)
	Theme.addGradient(body, Color3.fromRGB(234, 142, 255), Color3.fromRGB(134, 48, 226), 135)
	Theme.addStroke(body, Theme.Colors.Ink, 1.8)

	part(
		body,
		"Facet",
		UDim2.fromScale(0.42, 0.42),
		UDim2.fromScale(0.36, 0.36),
		Color3.fromRGB(252, 224, 255),
		2
	)
	return root
end

function HudIcons.createShieldIcon(parent: Instance, px: number, accent: Color3): Frame
	local root = makeRoot(parent, "ShieldIcon", px)

	local tip = part(
		root,
		"ShieldTip",
		UDim2.fromScale(0.56, 0.56),
		UDim2.fromScale(0.5, 0.62),
		accent,
		4,
		45
	)
	Theme.addStroke(tip, Theme.Colors.Ink, 2)
	tip.ZIndex = 3

	local top =
		part(root, "ShieldBody", UDim2.fromScale(0.80, 0.54), UDim2.fromScale(0.5, 0.34), accent, 5)
	Theme.addStroke(top, Theme.Colors.Ink, 2)
	top.ZIndex = 4

	local core = part(
		root,
		"ShieldCore",
		UDim2.fromScale(0.62, 0.44),
		UDim2.fromScale(0.5, 0.40),
		accent:Lerp(Color3.fromRGB(20, 48, 32), 0.25),
		4
	)
	core.ZIndex = 5
	local coreTip = part(
		root,
		"ShieldCoreTip",
		UDim2.fromScale(0.42, 0.42),
		UDim2.fromScale(0.5, 0.60),
		accent:Lerp(Color3.fromRGB(20, 48, 32), 0.25),
		3,
		45
	)
	coreTip.ZIndex = 5
	return root
end

function HudIcons.setShieldColor(icon: Frame?, color: Color3)
	if not icon then
		return
	end
	local innerCol = color:Lerp(Color3.fromRGB(16, 24, 22), 0.28)
	for _, name in ipairs({ "ShieldBody", "ShieldTip" }) do
		local f = icon:FindFirstChild(name)
		if f and f:IsA("Frame") then
			f.BackgroundColor3 = color
			local st = f:FindFirstChildOfClass("UIStroke")
			if st then
				st.Color = Theme.Colors.Ink
			end
		end
	end
	for _, name in ipairs({ "ShieldCore", "ShieldCoreTip" }) do
		local f = icon:FindFirstChild(name)
		if f and f:IsA("Frame") then
			f.BackgroundColor3 = innerCol
		end
	end
end

function HudIcons.createSpeakerIcon(parent: Instance, px: number): Frame
	local root = makeRoot(parent, "SpeakerIcon", px)

	local col = Color3.fromRGB(245, 248, 255)
	local base = part(root, "Base", UDim2.fromScale(0.24, 0.36), UDim2.fromScale(0.24, 0.5), col, 2)
	Theme.addStroke(base, Theme.Colors.Ink, 1.3)
	local cone = part(root, "Cone", UDim2.fromScale(0.26, 0.56), UDim2.fromScale(0.42, 0.5), col, 3)
	Theme.addStroke(cone, Theme.Colors.Ink, 1.3)
	part(root, "Wave1", UDim2.fromScale(0.10, 0.34), UDim2.fromScale(0.68, 0.5), col, 99)
	part(root, "Wave2", UDim2.fromScale(0.10, 0.58), UDim2.fromScale(0.84, 0.5), col, 99)

	local muteSlash = part(
		root,
		"MuteSlash",
		UDim2.fromScale(0.85, 0.13),
		UDim2.fromScale(0.5, 0.5),
		Theme.Colors.Danger,
		99,
		-45
	)
	Theme.addStroke(muteSlash, Theme.Colors.Ink, 1.2)
	muteSlash.Visible = false
	return root
end

function HudIcons.setSpeakerMuted(icon: Frame?, muted: boolean)
	if not icon then
		return
	end
	local w1 = icon:FindFirstChild("Wave1")
	local w2 = icon:FindFirstChild("Wave2")
	local slash = icon:FindFirstChild("MuteSlash")
	if w1 and w1:IsA("GuiObject") then
		w1.Visible = not muted
	end
	if w2 and w2:IsA("GuiObject") then
		w2.Visible = not muted
	end
	if slash and slash:IsA("GuiObject") then
		slash.Visible = muted
	end
end

function HudIcons.createShopIcon(parent: Instance, px: number): Frame
	local root = makeRoot(parent, "ShopIcon", px)

	local bag = part(
		root,
		"Bag",
		UDim2.fromScale(0.68, 0.58),
		UDim2.fromScale(0.5, 0.64),
		Color3.fromRGB(255, 255, 255),
		999
	)
	Theme.addGradient(bag, Theme.Colors.GoldTop, Theme.Colors.GoldBot, 90)
	Theme.addStroke(bag, Theme.Colors.Ink, 1.8)

	local tie = part(
		root,
		"Tie",
		UDim2.fromScale(0.36, 0.14),
		UDim2.fromScale(0.5, 0.34),
		Theme.Colors.ShopRedTop,
		99
	)
	Theme.addStroke(tie, Theme.Colors.Ink, 1.4)
	local top = part(
		root,
		"Crown",
		UDim2.fromScale(0.42, 0.20),
		UDim2.fromScale(0.5, 0.22),
		Color3.fromRGB(255, 212, 74),
		5
	)
	Theme.addStroke(top, Theme.Colors.Ink, 1.6)
	return root
end

function HudIcons.createPetsIcon(parent: Instance, px: number): Frame
	local root = makeRoot(parent, "PetsIcon", px)

	local col = Color3.fromRGB(108, 246, 156)
	local pad = part(root, "Pad", UDim2.fromScale(0.46, 0.38), UDim2.fromScale(0.5, 0.68), col, 999)
	Theme.addStroke(pad, Theme.Colors.Ink, 1.6)

	local toes = {
		{ x = 0.22, y = 0.44, r = -22 },
		{ x = 0.40, y = 0.28, r = -8 },
		{ x = 0.60, y = 0.28, r = 8 },
		{ x = 0.78, y = 0.44, r = 22 },
	}
	for i, t in ipairs(toes) do
		local toe = part(
			root,
			`Toe_{i}`,
			UDim2.fromScale(0.18, 0.24),
			UDim2.fromScale(t.x, t.y),
			col,
			999,
			t.r
		)
		Theme.addStroke(toe, Theme.Colors.Ink, 1.5)
	end
	return root
end

function HudIcons.createUpgradesIcon(parent: Instance, px: number): Frame
	local root = makeRoot(parent, "UpgradesIcon", px)

	local col = Color3.fromRGB(118, 212, 255)
	local shaft =
		part(root, "Shaft", UDim2.fromScale(0.28, 0.48), UDim2.fromScale(0.5, 0.66), col, 4)
	Theme.addStroke(shaft, Theme.Colors.Ink, 1.6)
	local wingL =
		part(root, "HeadL", UDim2.fromScale(0.42, 0.18), UDim2.fromScale(0.36, 0.34), col, 4, -45)
	Theme.addStroke(wingL, Theme.Colors.Ink, 1.6)
	local wingR =
		part(root, "HeadR", UDim2.fromScale(0.42, 0.18), UDim2.fromScale(0.64, 0.34), col, 4, 45)
	Theme.addStroke(wingR, Theme.Colors.Ink, 1.6)
	return root
end

function HudIcons.createCodexIcon(parent: Instance, px: number): Frame
	local root = makeRoot(parent, "CodexIcon", px)

	local cover = part(
		root,
		"Cover",
		UDim2.fromScale(0.62, 0.76),
		UDim2.fromScale(0.52, 0.5),
		Color3.fromRGB(255, 255, 255),
		6
	)
	Theme.addGradient(cover, Theme.Colors.TilePurpleTop, Theme.Colors.TilePurpleBot, 90)
	Theme.addStroke(cover, Theme.Colors.Ink, 1.8)

	part(
		cover,
		"Spine",
		UDim2.fromScale(0.18, 0.96),
		UDim2.fromScale(0.12, 0.5),
		Color3.fromRGB(98, 48, 168),
		3
	)
	part(
		cover,
		"Pages",
		UDim2.fromScale(0.62, 0.14),
		UDim2.fromScale(0.56, 0.84),
		Color3.fromRGB(246, 240, 255),
		3
	)
	return root
end

function HudIcons.createReticleIcon(parent: Instance, px: number, color: Color3): Frame
	local root = Instance.new("Frame")
	root.Name = "ReticleIcon"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(px, px)
	root.Parent = parent

	local ring = part(
		root,
		"Ring",
		UDim2.fromScale(0.68, 0.68),
		UDim2.fromScale(0.5, 0.5),
		Color3.fromRGB(0, 0, 0),
		999
	)
	ring.BackgroundTransparency = 1
	Theme.addStroke(ring, color, 1.8)

	part(root, "TickT", UDim2.fromScale(0.10, 0.24), UDim2.fromScale(0.5, 0.14), color, 99)
	part(root, "TickB", UDim2.fromScale(0.10, 0.24), UDim2.fromScale(0.5, 0.86), color, 99)
	part(root, "TickL", UDim2.fromScale(0.24, 0.10), UDim2.fromScale(0.14, 0.5), color, 99)
	part(root, "TickR", UDim2.fromScale(0.24, 0.10), UDim2.fromScale(0.86, 0.5), color, 99)
	part(root, "Dot", UDim2.fromScale(0.18, 0.18), UDim2.fromScale(0.5, 0.5), color, 999)
	return root
end

function HudIcons.setReticleColor(icon: Frame?, color: Color3)
	if not icon then
		return
	end
	for _, ch in ipairs(icon:GetChildren()) do
		if ch:IsA("Frame") then
			if ch.Name == "Ring" then
				local st = ch:FindFirstChildOfClass("UIStroke")
				if st then
					st.Color = color
				end
			else
				ch.BackgroundColor3 = color
			end
		end
	end
end

function HudIcons.createJumpIcon(parent: Instance, px: number): Frame
	local root = makeRoot(parent, "JumpIcon", px)

	local col = Color3.fromRGB(255, 240, 212)
	local head =
		part(root, "Head", UDim2.fromScale(0.22, 0.22), UDim2.fromScale(0.60, 0.24), col, 999)
	Theme.addStroke(head, Theme.Colors.Ink, 1.5)
	local body =
		part(root, "Torso", UDim2.fromScale(0.20, 0.34), UDim2.fromScale(0.50, 0.50), col, 4, 24)
	Theme.addStroke(body, Theme.Colors.Ink, 1.5)
	local legF =
		part(root, "LegF", UDim2.fromScale(0.14, 0.32), UDim2.fromScale(0.64, 0.72), col, 4, -32)
	Theme.addStroke(legF, Theme.Colors.Ink, 1.4)
	local legB =
		part(root, "LegB", UDim2.fromScale(0.14, 0.30), UDim2.fromScale(0.36, 0.70), col, 4, 42)
	Theme.addStroke(legB, Theme.Colors.Ink, 1.4)
	local arm =
		part(root, "Arm", UDim2.fromScale(0.32, 0.13), UDim2.fromScale(0.36, 0.36), col, 4, -36)
	Theme.addStroke(arm, Theme.Colors.Ink, 1.4)
	return root
end

function HudIcons.createShootIcon(parent: Instance, px: number): Frame
	local root = makeRoot(parent, "ShootIcon", px)

	local col = Color3.fromRGB(255, 248, 232)
	local ring =
		part(root, "Ring", UDim2.fromScale(0.74, 0.74), UDim2.fromScale(0.5, 0.5), col, 999)
	ring.BackgroundTransparency = 1
	Theme.addStroke(ring, col, 1.8, 0.05)

	local core =
		part(root, "BallCore", UDim2.fromScale(0.36, 0.36), UDim2.fromScale(0.5, 0.5), col, 999)
	Theme.addStroke(core, Theme.Colors.Ink, 1.6)
	part(root, "TickT", UDim2.fromScale(0.11, 0.24), UDim2.fromScale(0.5, 0.12), col, 99)
	part(root, "TickB", UDim2.fromScale(0.11, 0.24), UDim2.fromScale(0.5, 0.88), col, 99)
	part(root, "TickL", UDim2.fromScale(0.24, 0.11), UDim2.fromScale(0.12, 0.5), col, 99)
	part(root, "TickR", UDim2.fromScale(0.24, 0.11), UDim2.fromScale(0.88, 0.5), col, 99)
	return root
end

function HudIcons.createDashIcon(parent: Instance, px: number): Frame
	local root = makeRoot(parent, "DashIcon", px)

	local col = Color3.fromRGB(240, 250, 255)
	local chevrons = {
		{ name = "C1T", x = 0.36, y = 0.36, rot = 38 },
		{ name = "C1B", x = 0.36, y = 0.64, rot = -38 },
		{ name = "C2T", x = 0.66, y = 0.36, rot = 38 },
		{ name = "C2B", x = 0.66, y = 0.64, rot = -38 },
	}
	for _, c in ipairs(chevrons) do
		local bar = part(
			root,
			c.name,
			UDim2.fromScale(0.34, 0.14),
			UDim2.fromScale(c.x, c.y),
			col,
			99,
			c.rot
		)
		Theme.addStroke(bar, Theme.Colors.Ink, 1.5, 0)
	end
	return root
end

local WHITE = Color3.fromRGB(255, 255, 255)

local function gradPart(
	parent: Instance,
	name: string,
	size: UDim2,
	pos: UDim2,
	topCol: Color3,
	botCol: Color3,
	radius: number?,
	rot: number?,
	strokeW: number?
): Frame
	local f = part(parent, name, size, pos, WHITE, radius, rot)
	Theme.addGradient(f, topCol, botCol, 90)
	if strokeW and strokeW > 0 then
		Theme.addStroke(f, Theme.Colors.Ink, strokeW)
	end
	return f
end

local function addSparkle(parent: Instance, x: number, y: number, zIndex: number)
	local pos = UDim2.fromScale(x, y)
	local spH = part(parent, "SparkleH", UDim2.fromScale(0.24, 0.08), pos, WHITE, 99)
	spH.ZIndex = zIndex
	local spV = part(parent, "SparkleV", UDim2.fromScale(0.08, 0.24), pos, WHITE, 99)
	spV.ZIndex = zIndex
end

local function addStarRay(wrap: Frame, index: number)
	local deg = index * 72
	local rad = math.rad(deg - 90)
	local sz = UDim2.fromScale(0.35, 0.35)
	local pos = UDim2.fromScale(0.5 + math.cos(rad) * 0.21, 0.5 + math.sin(rad) * 0.21)
	local out = part(wrap, `RayOut_{index}`, sz, pos, Theme.Colors.GoldBot, 4, deg + 45)
	out.ZIndex = 1
	Theme.addStroke(out, Theme.Colors.Ink, 2.4)
	local fill = gradPart(
		wrap,
		`RayFill_{index}`,
		sz,
		pos,
		Theme.Colors.GoldTop,
		Theme.Colors.GoldBot,
		4,
		deg + 45
	)
	fill.ZIndex = 2
end

--[[
	Dual-pass 5-point star silhouette: back stroked layer establishes a continuous dark
	cartoon outline while the unstroked front gold fill fuses all interior seams cleanly.
]]
function HudIcons.createStarBurstIcon(parent: Instance, px: number): Frame
	local root = makeRoot(parent, "StarBurstIcon", px)
	local wrap =
		part(root, "StarWrap", UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), WHITE, 0, -12)
	wrap.BackgroundTransparency = 1
	for i = 0, 4 do
		addStarRay(wrap, i)
	end
	local core = gradPart(
		wrap,
		"Core",
		UDim2.fromScale(0.48, 0.48),
		UDim2.fromScale(0.5, 0.5),
		Theme.Colors.GoldTop,
		Theme.Colors.GoldBot,
		999
	)
	core.ZIndex = 2
	local shine = part(
		wrap,
		"Shine",
		UDim2.fromScale(0.18, 0.11),
		UDim2.fromScale(0.40, 0.36),
		Color3.fromRGB(255, 252, 224),
		999,
		-28
	)
	shine.BackgroundTransparency = 0.2
	shine.ZIndex = 3
	return root
end

function HudIcons.createCashStackIcon(parent: Instance, px: number): Frame
	local root = makeRoot(parent, "CashStackIcon", px)
	local bTop, bBot = Color3.fromRGB(72, 224, 96), Color3.fromRGB(30, 158, 62)
	local bSz, bPos = UDim2.fromScale(0.76, 0.44), UDim2.fromScale(0.52, 0.62)
	local backBill = gradPart(root, "BackBill", bSz, bPos, bTop, bBot, 6, 8, 2.2)
	backBill.ZIndex = 1

	local fSz, fPos = UDim2.fromScale(0.78, 0.46), UDim2.fromScale(0.48, 0.44)
	local fBot = Color3.fromRGB(36, 184, 68)
	local frontBill =
		gradPart(root, "FrontBill", fSz, fPos, Theme.Colors.LimeTop, fBot, 6, -10, 2.2)
	frontBill.ZIndex = 2

	local center = UDim2.fromScale(0.5, 0.5)
	local em = part(
		frontBill,
		"Emblem",
		UDim2.fromScale(0.26, 0.56),
		center,
		Color3.fromRGB(174, 255, 146),
		999
	)
	em.ZIndex = 3

	local bandSz = UDim2.fromScale(0.24, 1.04)
	local band = gradPart(
		frontBill,
		"GoldBand",
		bandSz,
		center,
		Theme.Colors.GoldTop,
		Theme.Colors.GoldBot,
		3,
		0,
		1.8
	)
	band.ZIndex = 4
	return root
end

function HudIcons.createEggIcon(parent: Instance, px: number, accent: Color3?): Frame
	local root = makeRoot(parent, "EggIcon", px)
	local base = accent or Color3.fromRGB(255, 206, 152)
	local topCol = base:Lerp(WHITE, 0.28)
	local botCol = base:Lerp(Color3.fromRGB(48, 32, 64), 0.22)
	local spotCol = base:Lerp(Theme.Colors.Ink, 0.2)

	local egg = gradPart(
		root,
		"EggBody",
		UDim2.fromScale(0.66, 0.84),
		UDim2.fromScale(0.5, 0.52),
		topCol,
		botCol,
		999,
		0,
		2.2
	)
	egg.ZIndex = 1

	local spotA =
		part(egg, "SpotA", UDim2.fromScale(0.22, 0.18), UDim2.fromScale(0.68, 0.64), spotCol, 999)
	spotA.BackgroundTransparency = 0.45
	local spotB =
		part(egg, "SpotB", UDim2.fromScale(0.16, 0.14), UDim2.fromScale(0.32, 0.72), spotCol, 999)
	spotB.BackgroundTransparency = 0.5
	local gloss =
		part(egg, "Gloss", UDim2.fromScale(0.18, 0.28), UDim2.fromScale(0.34, 0.28), WHITE, 999, 22)
	gloss.BackgroundTransparency = 0.16
	addSparkle(root, 0.80, 0.22, 4)
	return root
end

local function addGiftRibbon(parent: Frame, name: string)
	local sz = UDim2.fromScale(0.24, 1)
	local center = UDim2.fromScale(0.5, 0.5)
	gradPart(parent, name, sz, center, Theme.Colors.ShopRedTop, Theme.Colors.ShopRedBot, 2, 0, 1.5)
end

function HudIcons.createGiftIcon(parent: Instance, px: number): Frame
	local root = makeRoot(parent, "GiftIcon", px)
	local bowSz = UDim2.fromScale(0.28, 0.20)
	local bowL =
		part(root, "BowL", bowSz, UDim2.fromScale(0.37, 0.20), Theme.Colors.ShopRedTop, 999, -24)
	bowL.ZIndex = 1
	Theme.addStroke(bowL, Theme.Colors.Ink, 2)
	local bowR =
		part(root, "BowR", bowSz, UDim2.fromScale(0.63, 0.20), Theme.Colors.ShopRedTop, 999, 24)
	bowR.ZIndex = 1
	Theme.addStroke(bowR, Theme.Colors.Ink, 2)

	local boxTop, boxBot = Color3.fromRGB(255, 198, 56), Color3.fromRGB(242, 118, 28)
	local box = gradPart(
		root,
		"Box",
		UDim2.fromScale(0.66, 0.50),
		UDim2.fromScale(0.5, 0.68),
		boxTop,
		boxBot,
		6,
		0,
		2.2
	)
	box.ZIndex = 2
	addGiftRibbon(box, "Ribbon")

	local lid = gradPart(
		root,
		"Lid",
		UDim2.fromScale(0.76, 0.22),
		UDim2.fromScale(0.5, 0.37),
		Theme.Colors.GoldTop,
		Color3.fromRGB(255, 162, 32),
		5,
		0,
		2.2
	)
	lid.ZIndex = 3
	addGiftRibbon(lid, "Knot")
	return root
end

return HudIcons
