--!strict
--[[
	HudGui.luau
	Responsive mobile-first HUD: top-left stat chips, right-side menu dock,
	bottom-right Throw & Dash buttons (clear of JumpButton), and onboarding guide pill.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MathUtil = require(Shared.Utils.MathUtil)
local Remotes = require(Shared.Net.Remotes)

local Theme = require(script.Parent.Theme)

local HudGui = {}

local statLabels: { [string]: TextLabel } = {}
local hubReturnBtn: TextButton? = nil
local guideBanner: TextLabel? = nil
local dashBtn: TextButton? = nil
local throwCallback: (() -> ())? = nil
local dashCallback: (() -> ())? = nil
local openModalCallback: ((string) -> ())? = nil

local function buildStatChips(gui: ScreenGui)
	local bar = Theme.makeFrame(
		gui,
		"StatsBar",
		UDim2.fromOffset(250, 126),
		UDim2.fromOffset(10, 10),
		Theme.Colors.Panel,
		12
	)
	Theme.addPadding(bar, 8)
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(112, 32)
	layout.CellPadding = UDim2.fromOffset(6, 6)
	layout.Parent = bar

	local specs = {
		{ key = "Coins", label = "Coins: 0", color = Theme.Colors.Coins },
		{ key = "Gems", label = "Gems: 0", color = Theme.Colors.Gems },
		{ key = "BallDamage", label = "DMG: 5", color = Theme.Colors.Molten },
		{ key = "Power", label = "PWR: 10", color = Theme.Colors.Frost },
		{ key = "Level", label = "Lv 1 (100 HP)", color = Theme.Colors.Emerald },
		{ key = "Speed", label = "SPD: 1.0x", color = Theme.Colors.Text },
	}
	for _, s in ipairs(specs) do
		local chip = Theme.makeFrame(
			bar,
			s.key .. "Chip",
			UDim2.fromOffset(112, 32),
			UDim2.fromOffset(0, 0),
			Theme.Colors.Card,
			8
		)
		local lbl = Theme.makeLabel(
			chip,
			"Value",
			s.label,
			UDim2.fromScale(1, 1),
			UDim2.fromOffset(6, 0),
			13,
			s.color,
			true
		)
		statLabels[s.key] = lbl
	end
end

local function buildMenuDock(gui: ScreenGui)
	local dock = Instance.new("Frame")
	dock.Name = "MenuDock"
	dock.BackgroundTransparency = 1
	dock.AnchorPoint = Vector2.new(1, 0.5)
	dock.Position = UDim2.new(1, -12, 0.45, 0)
	dock.Size = UDim2.fromOffset(116, 250)
	dock.Parent = gui

	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Right
	list.Parent = dock

	local buttons = {
		{ id = "Pets", text = "PETS [P]", color = Theme.Colors.Emerald },
		{ id = "Upgrades", text = "UPGRADES", color = Theme.Colors.Frost },
		{ id = "Shop", text = "SHOP", color = Theme.Colors.Coins },
		{ id = "Codex", text = "CODEX", color = Theme.Colors.Gems },
	}
	for _, b in ipairs(buttons) do
		Theme.makeButton(
			dock,
			b.id .. "Btn",
			b.text,
			UDim2.fromOffset(112, 42),
			UDim2.fromOffset(0, 0),
			b.color,
			function()
				if openModalCallback then
					openModalCallback(b.id)
				end
			end
		)
	end

	hubReturnBtn = Theme.makeButton(
		dock,
		"ReturnHubBtn",
		"HUB PLOT",
		UDim2.fromOffset(112, 42),
		UDim2.fromOffset(0, 0),
		Theme.Colors.Molten,
		function()
			Remotes.waitClient().TeleportZone:FireServer("Hub")
		end
	)
	if hubReturnBtn then
		hubReturnBtn.Visible = false
	end
end

local function buildCombatButtons(gui: ScreenGui)
	-- Positioned above/left of Roblox mobile JumpButton for comfortable thumb reach
	local holder = Instance.new("Frame")
	holder.Name = "ActionButtons"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(1, 1)
	holder.Position = UDim2.new(1, -110, 1, -18)
	holder.Size = UDim2.fromOffset(160, 80)
	holder.Parent = gui

	local throwBtn = Theme.makeButton(
		holder,
		"ThrowBtn",
		"THROW",
		UDim2.fromOffset(74, 74),
		UDim2.fromOffset(82, 0),
		Theme.Colors.Molten,
		function()
			if throwCallback then
				throwCallback()
			end
		end
	)
	Theme.addCorner(throwBtn, 37)

	dashBtn = Theme.makeButton(
		holder,
		"DashBtn",
		"DASH\n[Q]",
		UDim2.fromOffset(66, 66),
		UDim2.fromOffset(6, 8),
		Theme.Colors.Frost,
		function()
			if dashCallback then
				dashCallback()
			end
		end
	)
	if dashBtn then
		Theme.addCorner(dashBtn, 33)
	end
end

function HudGui.mount(callbacks: {
	onThrow: () -> (),
	onDash: () -> (),
	onOpenModal: (string) -> (),
})
	throwCallback = callbacks.onThrow
	dashCallback = callbacks.onDash
	openModalCallback = callbacks.onOpenModal

	local gui = Theme.createScreenGui("BallBrawl_HUD", 10)
	buildStatChips(gui)
	buildMenuDock(gui)
	buildCombatButtons(gui)

	local bannerFrame = Theme.makeFrame(
		gui,
		"OnboardingGuide",
		UDim2.fromOffset(420, 36),
		UDim2.new(0.5, -210, 1, -48),
		Theme.Colors.Panel,
		10
	)
	guideBanner = Theme.makeLabel(
		bannerFrame,
		"GuideText",
		"Step 1: Walk to Pedestal #1 & press Hatch for your FREE Starter Egg!",
		UDim2.fromScale(1, 1),
		UDim2.fromOffset(0, 0),
		14,
		Theme.Colors.Coins,
		true
	)
	if guideBanner then
		guideBanner.TextXAlignment = Enum.TextXAlignment.Center
	end
end

function HudGui.updateProfile(profile: any, powerRating: number, maxHP: number)
	if statLabels.Coins then
		statLabels.Coins.Text = `Coins: {MathUtil.formatNumber(profile.coins or 0)}`
	end
	if statLabels.Gems then
		statLabels.Gems.Text = `Gems: {MathUtil.formatNumber(profile.bossGems or 0)}`
	end
	if statLabels.BallDamage then
		statLabels.BallDamage.Text = `DMG: {MathUtil.formatNumber(profile.ballDamage or 5)}`
	end
	if statLabels.Power then
		statLabels.Power.Text = `PWR: {MathUtil.formatNumber(powerRating or 0)}`
	end
	if statLabels.Level then
		statLabels.Level.Text = `Lv {profile.level or 1} ({maxHP or 100} HP)`
	end
	if statLabels.Speed then
		statLabels.Speed.Text = string.format("SPD: %.2fx", profile.throwSpeed or 1.0)
	end
	if guideBanner and guideBanner.Parent and guideBanner.Parent:IsA("GuiObject") then
		if not profile.starterEggHatched then
			guideBanner.Parent.Visible = true
			guideBanner.Text = "Step 1: Press [E] at Pedestal #1 to hatch your FREE Starter Egg!"
		elseif (profile.ballDamage or 5) < 15 then
			guideBanner.Parent.Visible = true
			guideBanner.Text = "Step 2: Step onto your Training Pad & throw balls to reach 15 DMG!"
		elseif (profile.level or 1) < 2 then
			guideBanner.Parent.Visible = true
			guideBanner.Text = "Step 3: Walk into Portal 1 (Emerald Meadow) for PvE & Boss Brawl!"
		else
			guideBanner.Parent.Visible = false
		end
	end
end

function HudGui.updateZone(zone: string)
	if hubReturnBtn then
		hubReturnBtn.Visible = zone == "BiomePvE"
	end
end

function HudGui.setDashCooldown(remaining: number)
	if not dashBtn then
		return
	end
	if remaining > 0.05 then
		dashBtn.Text = string.format("%.1fs", remaining)
		dashBtn.BackgroundColor3 = Theme.Colors.CardAlt
	else
		dashBtn.Text = "DASH\n[Q]"
		dashBtn.BackgroundColor3 = Theme.Colors.Frost
	end
end

Players.LocalPlayer:GetAttributeChangedSignal("Zone"):Connect(function()
	HudGui.updateZone(tostring(Players.LocalPlayer:GetAttribute("Zone") or "Hub"))
end)

return HudGui
