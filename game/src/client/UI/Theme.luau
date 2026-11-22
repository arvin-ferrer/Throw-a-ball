--!strict
--[[
	Theme.luau
	Mobile-first responsive UI tokens and reusable component builders.
	Always uses ResetOnSpawn = false and CoreUISafeInsets for safe phone/tablet/PC layouts.
]]

local Players = game:GetService("Players")

local Theme = {}

Theme.Colors = {
	Panel = Color3.fromRGB(18, 22, 34),
	Card = Color3.fromRGB(28, 35, 52),
	CardAlt = Color3.fromRGB(36, 44, 66),
	Stroke = Color3.fromRGB(72, 88, 122),
	Text = Color3.fromRGB(248, 250, 252),
	Muted = Color3.fromRGB(162, 176, 204),
	Coins = Color3.fromRGB(250, 204, 21),
	Gems = Color3.fromRGB(192, 132, 252),
	Emerald = Color3.fromRGB(52, 211, 153),
	Frost = Color3.fromRGB(56, 189, 248),
	Molten = Color3.fromRGB(251, 113, 42),
	Danger = Color3.fromRGB(239, 68, 68),
	Overcharged = Color3.fromRGB(255, 72, 196),
}

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

function Theme.addCorner(inst: GuiObject, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = inst
end

function Theme.addStroke(inst: GuiObject, color: Color3, thickness: number?)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 1.5
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
end

function Theme.addPadding(inst: GuiObject, px: number)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
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
	f.BackgroundTransparency = 0.08
	f.BorderSizePixel = 0
	f.Parent = parent
	Theme.addCorner(f, radius or 12)
	Theme.addStroke(f, Theme.Colors.Stroke, 1.5)
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
	Theme.addStroke(btn, Color3.fromRGB(255, 255, 255), 1)
	btn.Activated:Connect(onClick)
	return btn
end

return Theme
