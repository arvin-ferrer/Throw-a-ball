--!strict
--[[
	ShopCodexGui.luau
	PolicyService-Compliant Shop & Full 19-Species Codex UI:
	- Automatically swaps Paid Random Eggs -> Direct Non-Random Bundles when ArePaidRandomItemsRestricted == true
	- Displays exact 100.0% server-driven Pet & Mutation odds on every Paid Egg card
	- Lists all 5 Game Passes (reading Pass_* attributes) & Gem Cosmetics
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetConfigs = require(Shared.Configs.PetConfigs)
local MonetizationConfigs = require(Shared.Configs.MonetizationConfigs)
local PolicyLogic = require(Shared.Utils.PolicyLogic)
local Remotes = require(Shared.Net.Remotes)

local Theme = require(script.Parent.Theme)

local ShopCodexGui = {}

local localPlayer = Players.LocalPlayer
local rootFrame: Frame? = nil
local scrollBody: ScrollingFrame? = nil
local activeTab = "Shop"
local latestProfile: any = nil

local function clearScroll()
	if not scrollBody then
		return
	end
	for _, c in ipairs(scrollBody:GetChildren()) do
		if not c:IsA("UIListLayout") then
			c:Destroy()
		end
	end
end

local function formatOddsLine(oddsList: { any }?): string
	if not oddsList then
		return ""
	end
	local parts: { string } = {}
	for _, entry in ipairs(oddsList) do
		table.insert(parts, string.format("%s %.1f%%", entry.id, entry.percent))
	end
	return table.concat(parts, " | ")
end

local function renderShopTab()
	if not scrollBody then
		return
	end
	local remotes = Remotes.waitClient()
	local restricted = localPlayer:GetAttribute("ArePaidRandomItemsRestricted") == true

	local headerText = if restricted
		then "DIRECT NON-RANDOM BUNDLES (Regional Policy Compliance — Zero RNG)"
		else "SHOP EXCLUSIVE EGGS (100.0% Disclosed Odds • Boss Eggs Stay 100% Gameplay-Earned!)"
	Theme.makeLabel(
		scrollBody,
		"ShopHeader",
		headerText,
		UDim2.new(1, -8, 0, 26),
		UDim2.fromOffset(0, 0),
		13,
		Theme.Colors.Coins,
		true
	)

	local offerings = PolicyLogic.buildShopOfferings(restricted)
	for _, item in ipairs(offerings) do
		local card = Theme.makeFrame(
			scrollBody,
			"Offer_" .. item.id,
			UDim2.new(1, -8, 0, 96),
			UDim2.fromOffset(0, 0),
			Theme.Colors.Card,
			10
		)
		Theme.makeLabel(
			card,
			"Name",
			item.displayName,
			UDim2.new(0.68, 0, 0, 24),
			UDim2.fromOffset(10, 6),
			15,
			Theme.Colors.Text,
			true
		)
		local detail = if item.kind == "DirectBundle"
			then `Guaranteed: {item.guaranteedPetId} + {item.guaranteedBallSkin} (No RNG)`
			else `Pets (100%): {formatOddsLine(item.petOdds)}\nMutations (100%): {formatOddsLine(
				item.mutationOdds
			)}`
		local desc = Theme.makeLabel(
			card,
			"Desc",
			detail,
			UDim2.new(0.68, 0, 0, 56),
			UDim2.fromOffset(10, 30),
			11,
			Theme.Colors.Muted,
			false
		)
		desc.TextWrapped = true
		Theme.makeButton(
			card,
			"BuyBtn",
			"BUY (ROBUX)",
			UDim2.fromOffset(128, 38),
			UDim2.new(1, -140, 0, 28),
			Theme.Colors.Emerald,
			function()
				remotes.ShopRequest:FireServer("Product", item.devProductId)
			end
		)
	end

	Theme.makeLabel(
		scrollBody,
		"PassHeader",
		"GAME PASSES (Progression & QoL)",
		UDim2.new(1, -8, 0, 24),
		UDim2.fromOffset(0, 0),
		14,
		Theme.Colors.Frost,
		true
	)
	for _, pass in pairs(MonetizationConfigs.GAME_PASSES) do
		local owned = localPlayer:GetAttribute(pass.attributeName) == true
		local card = Theme.makeFrame(
			scrollBody,
			"Pass_" .. pass.key,
			UDim2.new(1, -8, 0, 58),
			UDim2.fromOffset(0, 0),
			Theme.Colors.Card,
			10
		)
		Theme.makeLabel(
			card,
			"Title",
			pass.displayName,
			UDim2.new(0.66, 0, 0, 22),
			UDim2.fromOffset(10, 6),
			14,
			Theme.Colors.Text,
			true
		)
		Theme.makeLabel(
			card,
			"Desc",
			pass.description,
			UDim2.new(0.66, 0, 0, 26),
			UDim2.fromOffset(10, 28),
			11,
			Theme.Colors.Muted,
			false
		)
		Theme.makeButton(
			card,
			"BuyBtn",
			if owned then "OWNED" else "GET PASS",
			UDim2.fromOffset(116, 36),
			UDim2.new(1, -128, 0, 11),
			if owned then Theme.Colors.CardAlt else Theme.Colors.Coins,
			function()
				if not owned then
					remotes.ShopRequest:FireServer("GamePass", pass.key)
				end
			end
		)
	end

	Theme.makeLabel(
		scrollBody,
		"CosHeader",
		"COSMETICS (Boss Gems)",
		UDim2.new(1, -8, 0, 24),
		UDim2.fromOffset(0, 0),
		14,
		Theme.Colors.Gems,
		true
	)
	local ownedCos = if latestProfile then (latestProfile.ownedCosmetics or {}) else {}
	for _, cos in pairs(MonetizationConfigs.COSMETICS) do
		local isOwned = ownedCos[cos.id] == true
		local card = Theme.makeFrame(
			scrollBody,
			"Cos_" .. cos.id,
			UDim2.new(1, -8, 0, 50),
			UDim2.fromOffset(0, 0),
			Theme.Colors.Card,
			10
		)
		Theme.makeLabel(
			card,
			"Title",
			`{cos.displayName} [{cos.category}]`,
			UDim2.fromScale(0.66, 1),
			UDim2.fromOffset(10, 0),
			14,
			Theme.Colors.Text,
			true
		)
		Theme.makeButton(
			card,
			"Btn",
			if isOwned then "EQUIP" else `{cos.costGems} Gems`,
			UDim2.fromOffset(116, 32),
			UDim2.new(1, -128, 0, 9),
			if isOwned then Theme.Colors.Frost else Theme.Colors.Gems,
			function()
				remotes.UpgradeAction:FireServer("BuyCosmetic", cos.id)
			end
		)
	end
end

local function renderCodexTab()
	if not scrollBody then
		return
	end
	local unlockedMap = if latestProfile then (latestProfile.codexUnlocked or {}) else {}
	local allSpecies = PetConfigs.getAllSpeciesOrdered()
	local unlockedCount = 0
	for _, sp in ipairs(allSpecies) do
		if unlockedMap[sp.id] then
			unlockedCount += 1
		end
	end
	Theme.makeLabel(
		scrollBody,
		"Summary",
		`CREATURE CODEX: {unlockedCount} / {#allSpecies} DISCOVERED`,
		UDim2.new(1, -8, 0, 26),
		UDim2.fromOffset(0, 0),
		15,
		Theme.Colors.Gems,
		true
	)

	for _, sp in ipairs(allSpecies) do
		local discovered = unlockedMap[sp.id] == true
		local card = Theme.makeFrame(
			scrollBody,
			"Codex_" .. sp.id,
			UDim2.new(1, -8, 0, 54),
			UDim2.fromOffset(0, 0),
			if discovered then Theme.Colors.Card else Theme.Colors.Panel,
			10
		)
		local rCol = PetConfigs.RARITY_COLORS[sp.rarity] or { 200, 200, 200 }
		Theme.makeLabel(
			card,
			"Name",
			if discovered
				then `{sp.displayName} [{sp.rarity}]`
				else `??? [{sp.rarity} — {sp.source}]`,
			UDim2.new(0.65, 0, 0, 24),
			UDim2.fromOffset(12, 6),
			14,
			Color3.fromRGB(rCol[1], rCol[2], rCol[3]),
			true
		)
		Theme.makeLabel(
			card,
			"Meta",
			`Base: {sp.baseRate} Coins/s | Active Perk: {sp.perkLabel} | Source: {sp.source}`,
			UDim2.new(1, -24, 0, 20),
			UDim2.fromOffset(12, 28),
			11,
			Theme.Colors.Muted,
			false
		)
	end
end

local function rerender()
	if not rootFrame or not rootFrame.Visible then
		return
	end
	clearScroll()
	if activeTab == "Shop" then
		renderShopTab()
	else
		renderCodexTab()
	end
end

function ShopCodexGui.mount()
	local gui = Theme.createScreenGui("BallBrawl_ShopCodex", 22)
	local panel = Theme.makeGlossyPanel(
		gui,
		"ShopPanel",
		UDim2.fromScale(0.92, 0.86),
		UDim2.fromScale(0.5, 0.5),
		16
	)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Visible = false
	local scConstraint = Instance.new("UISizeConstraint")
	scConstraint.MaxSize = Vector2.new(580, 440)
	scConstraint.MinSize = Vector2.new(300, 250)
	scConstraint.Parent = panel
	rootFrame = panel

	Theme.makeLabel(
		panel,
		"Title",
		"SHOP & CREATURE CODEX",
		UDim2.new(1, -68, 0, 34),
		UDim2.fromOffset(16, 10),
		18,
		Theme.Colors.Coins,
		true
	)
	Theme.makeButton(
		panel,
		"CloseBtn",
		"X",
		UDim2.fromOffset(40, 40),
		UDim2.new(1, -48, 0, 6),
		Theme.Colors.Danger,
		function()
			panel.Visible = false
		end
	)

	local tabRow = Instance.new("Frame")
	tabRow.Name = "TabRow"
	tabRow.BackgroundTransparency = 1
	tabRow.Position = UDim2.fromOffset(14, 52)
	tabRow.Size = UDim2.new(1, -28, 0, 34)
	tabRow.Parent = panel
	local tl = Instance.new("UIListLayout")
	tl.FillDirection = Enum.FillDirection.Horizontal
	tl.Padding = UDim.new(0, 8)
	tl.Parent = tabRow

	local function addTab(name: string, label: string, color: Color3, tabId: string)
		local tb = Theme.makeButton(
			tabRow,
			name,
			label,
			UDim2.fromScale(0.48, 1),
			UDim2.fromOffset(0, 0),
			color,
			function()
				activeTab = tabId
				rerender()
			end
		)
		local fx = Instance.new("UIFlexItem")
		fx.FlexMode = Enum.UIFlexMode.Fill
		fx.Parent = tb
	end
	addTab("ShopTab", "SHOP & PASSES", Theme.Colors.Coins, "Shop")
	addTab("CodexTab", "CREATURE CODEX", Theme.Colors.Gems, "Codex")

	local sc = Instance.new("ScrollingFrame")
	sc.Name = "Body"
	sc.BackgroundTransparency = 1
	sc.Position = UDim2.fromOffset(12, 94)
	sc.Size = UDim2.new(1, -24, 1, -106)
	sc.CanvasSize = UDim2.fromOffset(0, 0)
	sc.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sc.ScrollBarThickness = 6
	sc.Parent = panel
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.Parent = sc
	scrollBody = sc

	localPlayer:GetAttributeChangedSignal("ArePaidRandomItemsRestricted"):Connect(rerender)
end

function ShopCodexGui.open(tabName: string)
	activeTab = tabName
	if rootFrame then
		rootFrame.Visible = true
		rerender()
	end
end

function ShopCodexGui.close()
	if rootFrame then
		rootFrame.Visible = false
	end
end

function ShopCodexGui.setProfile(profile: any)
	latestProfile = profile
	rerender()
end

return ShopCodexGui
