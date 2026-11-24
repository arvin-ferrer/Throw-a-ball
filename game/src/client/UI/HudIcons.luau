--!strict
--[[
	HudIcons.luau
	Resolution-independent procedural vector icons for the Ball Brawl mobile HUD.
	Zero external asset dependencies — razor sharp on phones, tablets, and 4K PC displays.
]]

local Theme = require(script.Parent.Theme)

local HudIcons = {}

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
	local root = Instance.new("Frame")
	root.Name = "CoinIcon"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(px, px)
	root.Parent = parent

	local outer = part(
		root,
		"Outer",
		UDim2.fromScale(0.92, 0.92),
		UDim2.fromScale(0.5, 0.5),
		Color3.fromRGB(255, 255, 255),
		999
	)
	Theme.addGradient(outer, Color3.fromRGB(255, 224, 96), Color3.fromRGB(224, 146, 22), 90)
	Theme.addStroke(outer, Color3.fromRGB(168, 98, 12), 1.5)

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
	local root = Instance.new("Frame")
	root.Name = "GemIcon"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(px, px)
	root.Parent = parent

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
	Theme.addStroke(body, Color3.fromRGB(246, 204, 255), 1.2)

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
	local root = Instance.new("Frame")
	root.Name = "ShieldIcon"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(px, px)
	root.Parent = parent

	-- Pointed bottom tip behind shield body
	local tip = part(
		root,
		"ShieldTip",
		UDim2.fromScale(0.56, 0.56),
		UDim2.fromScale(0.5, 0.62),
		accent,
		4,
		45
	)
	Theme.addStroke(tip, accent:Lerp(Color3.fromRGB(255, 255, 255), 0.55), 1.8)
	tip.ZIndex = 3

	-- Upper shield crest covering top half of the diamond
	local top =
		part(root, "ShieldBody", UDim2.fromScale(0.80, 0.54), UDim2.fromScale(0.5, 0.34), accent, 5)
	Theme.addStroke(top, accent:Lerp(Color3.fromRGB(255, 255, 255), 0.55), 1.8)
	top.ZIndex = 4

	-- Clean glossy inner core to blend upper crest + lower point seamlessly
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
	local rim = color:Lerp(Color3.fromRGB(255, 255, 255), 0.55)
	local innerCol = color:Lerp(Color3.fromRGB(16, 24, 22), 0.28)
	for _, name in ipairs({ "ShieldBody", "ShieldTip" }) do
		local f = icon:FindFirstChild(name)
		if f and f:IsA("Frame") then
			f.BackgroundColor3 = color
			local st = f:FindFirstChildOfClass("UIStroke")
			if st then
				st.Color = rim
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
	local root = Instance.new("Frame")
	root.Name = "SpeakerIcon"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(px, px)
	root.Parent = parent

	local col = Color3.fromRGB(235, 242, 255)
	part(root, "Base", UDim2.fromScale(0.24, 0.36), UDim2.fromScale(0.24, 0.5), col, 2)
	part(root, "Cone", UDim2.fromScale(0.26, 0.56), UDim2.fromScale(0.42, 0.5), col, 3)
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
	local root = Instance.new("Frame")
	root.Name = "ShopIcon"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(px, px)
	root.Parent = parent

	local bag = part(
		root,
		"Bag",
		UDim2.fromScale(0.68, 0.58),
		UDim2.fromScale(0.5, 0.64),
		Color3.fromRGB(255, 255, 255),
		999
	)
	Theme.addGradient(bag, Color3.fromRGB(255, 224, 108), Color3.fromRGB(218, 152, 34), 90)
	Theme.addStroke(bag, Color3.fromRGB(132, 82, 16), 1.4)

	local tie = part(
		root,
		"Tie",
		UDim2.fromScale(0.36, 0.14),
		UDim2.fromScale(0.5, 0.34),
		Color3.fromRGB(172, 106, 22),
		99
	)
	Theme.addStroke(tie, Color3.fromRGB(118, 70, 14), 1)
	local top = part(
		root,
		"Crown",
		UDim2.fromScale(0.42, 0.20),
		UDim2.fromScale(0.5, 0.22),
		Color3.fromRGB(248, 206, 78),
		5
	)
	Theme.addStroke(top, Color3.fromRGB(132, 82, 16), 1.2)
	return root
end

function HudIcons.createPetsIcon(parent: Instance, px: number): Frame
	local root = Instance.new("Frame")
	root.Name = "PetsIcon"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(px, px)
	root.Parent = parent

	local col = Color3.fromRGB(108, 246, 156)
	local strokeCol = Color3.fromRGB(22, 92, 52)
	local pad = part(root, "Pad", UDim2.fromScale(0.46, 0.38), UDim2.fromScale(0.5, 0.68), col, 999)
	Theme.addStroke(pad, strokeCol, 1.3)

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
		Theme.addStroke(toe, strokeCol, 1.2)
	end
	return root
end

function HudIcons.createUpgradesIcon(parent: Instance, px: number): Frame
	local root = Instance.new("Frame")
	root.Name = "UpgradesIcon"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(px, px)
	root.Parent = parent

	local col = Color3.fromRGB(118, 212, 255)
	local strokeCol = Color3.fromRGB(26, 78, 138)
	local shaft =
		part(root, "Shaft", UDim2.fromScale(0.28, 0.48), UDim2.fromScale(0.5, 0.66), col, 4)
	Theme.addStroke(shaft, strokeCol, 1.2)
	local wingL =
		part(root, "HeadL", UDim2.fromScale(0.42, 0.18), UDim2.fromScale(0.36, 0.34), col, 4, -45)
	Theme.addStroke(wingL, strokeCol, 1.2)
	local wingR =
		part(root, "HeadR", UDim2.fromScale(0.42, 0.18), UDim2.fromScale(0.64, 0.34), col, 4, 45)
	Theme.addStroke(wingR, strokeCol, 1.2)
	return root
end

function HudIcons.createCodexIcon(parent: Instance, px: number): Frame
	local root = Instance.new("Frame")
	root.Name = "CodexIcon"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(px, px)
	root.Parent = parent

	local cover = part(
		root,
		"Cover",
		UDim2.fromScale(0.62, 0.76),
		UDim2.fromScale(0.52, 0.5),
		Color3.fromRGB(255, 255, 255),
		6
	)
	Theme.addGradient(cover, Color3.fromRGB(200, 146, 255), Color3.fromRGB(132, 74, 216), 90)
	Theme.addStroke(cover, Color3.fromRGB(78, 36, 138), 1.4)

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
		Color3.fromRGB(238, 224, 255),
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
	local root = Instance.new("Frame")
	root.Name = "JumpIcon"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(px, px)
	root.Parent = parent

	local col = Color3.fromRGB(255, 240, 212)
	local stroke = Color3.fromRGB(142, 54, 12)
	local head =
		part(root, "Head", UDim2.fromScale(0.22, 0.22), UDim2.fromScale(0.60, 0.24), col, 999)
	Theme.addStroke(head, stroke, 1.2)
	local body =
		part(root, "Torso", UDim2.fromScale(0.20, 0.34), UDim2.fromScale(0.50, 0.50), col, 4, 24)
	Theme.addStroke(body, stroke, 1.2)
	local legF =
		part(root, "LegF", UDim2.fromScale(0.14, 0.32), UDim2.fromScale(0.64, 0.72), col, 4, -32)
	Theme.addStroke(legF, stroke, 1.1)
	local legB =
		part(root, "LegB", UDim2.fromScale(0.14, 0.30), UDim2.fromScale(0.36, 0.70), col, 4, 42)
	Theme.addStroke(legB, stroke, 1.1)
	local arm =
		part(root, "Arm", UDim2.fromScale(0.32, 0.13), UDim2.fromScale(0.36, 0.36), col, 4, -36)
	Theme.addStroke(arm, stroke, 1.1)
	return root
end

function HudIcons.createShootIcon(parent: Instance, px: number): Frame
	local root = Instance.new("Frame")
	root.Name = "ShootIcon"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(px, px)
	root.Active = false
	root.Parent = parent

	local col = Color3.fromRGB(255, 248, 232)
	local stroke = Color3.fromRGB(122, 42, 8)
	local ring =
		part(root, "Ring", UDim2.fromScale(0.74, 0.74), UDim2.fromScale(0.5, 0.5), col, 999)
	ring.BackgroundTransparency = 1
	Theme.addStroke(ring, col, 1.6, 0.08)

	local core =
		part(root, "BallCore", UDim2.fromScale(0.36, 0.36), UDim2.fromScale(0.5, 0.5), col, 999)
	Theme.addStroke(core, stroke, 1.2)
	part(root, "TickT", UDim2.fromScale(0.11, 0.24), UDim2.fromScale(0.5, 0.12), col, 99)
	part(root, "TickB", UDim2.fromScale(0.11, 0.24), UDim2.fromScale(0.5, 0.88), col, 99)
	part(root, "TickL", UDim2.fromScale(0.24, 0.11), UDim2.fromScale(0.12, 0.5), col, 99)
	part(root, "TickR", UDim2.fromScale(0.24, 0.11), UDim2.fromScale(0.88, 0.5), col, 99)
	return root
end

function HudIcons.createDashIcon(parent: Instance, px: number): Frame
	local root = Instance.new("Frame")
	root.Name = "DashIcon"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(px, px)
	root.Active = false
	root.Parent = parent

	local col = Color3.fromRGB(240, 250, 255)
	local stroke = Color3.fromRGB(18, 58, 108)
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
		Theme.addStroke(bar, stroke, 1.0, 0.2)
	end
	return root
end

return HudIcons
