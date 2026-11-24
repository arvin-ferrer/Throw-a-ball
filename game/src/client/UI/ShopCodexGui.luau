--!strict
--[[
	ShopCodexGui.luau
	PolicyService-Compliant Shop & Full 19-Species Codex UI:
	- Automatically swaps Paid Random Eggs -> Direct Non-Random Bundles when ArePaidRandomItemsRestricted ~= false
	- Displays exact 100.0% server-driven Pet & Mutation odds on every Paid Egg card
	- Lists all 5 Game Passes (reading Pass_* attributes) & Gem Cosmetics
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetConfigs = require(Shared.Configs.PetConfigs)
local MonetizationConfigs = require(Shared.Configs.MonetizationConfigs)
local EconomyLogic = require(Shared.Utils.EconomyLogic)
local PolicyLogic = require(Shared.Utils.PolicyLogic)
local Remotes = require(Shared.Net.Remotes)

local Theme = require(script.Parent.Theme)

local ShopCodexGui = {}

local localPlayer = Players.LocalPlayer
local rootFrame: Frame? = nil
local scrollBody: ScrollingFrame? = nil
local activeTab = "Shop"
local latestProfile: any = nil

local function applyTextConstraint(lbl: TextLabel, minSize: number, maxSize: number)
	lbl.TextScaled = true
	local tc = Instance.new("UITextSizeConstraint")
	tc.MinTextSize = minSize
	tc.MaxTextSize = maxSize
	tc.Parent = lbl
end

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
		local sp = PetConfigs.getSpecies(entry.id)
		local label = if sp then sp.displayName else entry.id
		table.insert(parts, string.format("%s %.1f%%", label, entry.percent))
	end
	return table.concat(parts, " | ")
end

local function makeShopCardRow(
	parent: ScrollingFrame,
	name: string,
	height: number,
	btnText: string,
	btnWidth: number,
	btnColor: Color3,
	onClick: () -> ()
): Frame
	local card = Theme.makeFrame(
		parent,
		name,
		UDim2.new(1, -8, 0, height),
		UDim2.fromOffset(0, 0),
		Theme.Colors.Card,
		10
	)
	local btn = Theme.makeButton(
		card,
		"BuyBtn",
		btnText,
		UDim2.fromOffset(btnWidth, 44),
		UDim2.new(1, -(btnWidth + 10), 0.5, -22),
		btnColor,
		onClick
	)
	applyTextConstraint(btn :: any, 10, 14)
	return card
end

local function renderOfferCard(
	parent: ScrollingFrame,
	remotes: any,
	item: PolicyLogic.ShopCatalogItem
)
	local card = makeShopCardRow(
		parent,
		"Offer_" .. item.id,
		108,
		"BUY (ROBUX)",
		116,
		Theme.Colors.Emerald,
		function()
			remotes.ShopRequest:FireServer("Product", item.devProductId)
		end
	)
	local title = Theme.makeLabel(
		card,
		"Name",
		item.displayName,
		UDim2.new(1, -144, 0, 24),
		UDim2.fromOffset(10, 6),
		15,
		Theme.Colors.Text,
		true
	)
	applyTextConstraint(title, 10, 15)
	local detail = if item.kind == "DirectBundle"
		then item.description
		else `Pets (100%): {formatOddsLine(item.petOdds)}\nMutations (100%): {formatOddsLine(
			item.mutationOdds
		)}`
	local desc = Theme.makeLabel(
		card,
		"Desc",
		detail,
		UDim2.new(1, -144, 0, 68),
		UDim2.fromOffset(10, 32),
		11,
		Theme.Colors.Muted,
		false
	)
	desc.TextWrapped = true
	applyTextConstraint(desc, 8, 12)
end

local function renderEggSection(parent: ScrollingFrame, remotes: any, restricted: boolean)
	local headerText = if restricted
		then "DIRECT NON-RANDOM BUNDLES (Regional Policy Compliance — Zero RNG)"
		else "SHOP EXCLUSIVE EGGS (100.0% Disclosed Odds • Boss Eggs Stay 100% Gameplay-Earned!)"
	local hdr = Theme.makeLabel(
		parent,
		"ShopHeader",
		headerText,
		UDim2.new(1, -8, 0, 32),
		UDim2.fromOffset(0, 0),
		13,
		Theme.Colors.Coins,
		true
	)
	hdr.TextWrapped = true
	applyTextConstraint(hdr, 9, 13)
	for _, item in ipairs(PolicyLogic.buildShopOfferings(restricted)) do
		renderOfferCard(parent, remotes, item)
	end
end

local function renderGamePassCard(
	parent: ScrollingFrame,
	remotes: any,
	pass: MonetizationConfigs.GamePassSpec
)
	local owned = localPlayer:GetAttribute(pass.attributeName) == true
	local card = makeShopCardRow(
		parent,
		"Pass_" .. pass.key,
		68,
		if owned then "OWNED" else "GET PASS",
		104,
		if owned then Theme.Colors.CardAlt else Theme.Colors.Coins,
		function()
			if not owned then
				remotes.ShopRequest:FireServer("GamePass", pass.key)
			end
		end
	)
	local title = Theme.makeLabel(
		card,
		"Title",
		pass.displayName,
		UDim2.new(1, -130, 0, 22),
		UDim2.fromOffset(10, 6),
		14,
		Theme.Colors.Text,
		true
	)
	applyTextConstraint(title, 10, 14)
	local desc = Theme.makeLabel(
		card,
		"Desc",
		pass.description,
		UDim2.new(1, -130, 0, 34),
		UDim2.fromOffset(10, 28),
		11,
		Theme.Colors.Muted,
		false
	)
	desc.TextWrapped = true
	applyTextConstraint(desc, 8, 11)
end

local function renderGamePassSection(parent: ScrollingFrame, remotes: any)
	Theme.makeLabel(
		parent,
		"PassHeader",
		"GAME PASSES (Progression & QoL)",
		UDim2.new(1, -8, 0, 24),
		UDim2.fromOffset(0, 0),
		14,
		Theme.Colors.Frost,
		true
	)
	local ordered: { MonetizationConfigs.GamePassSpec } = {}
	for _, pass in pairs(MonetizationConfigs.GAME_PASSES) do
		table.insert(ordered, pass)
	end
	table.sort(ordered, function(a, b)
		return a.passId < b.passId
	end)
	for _, pass in ipairs(ordered) do
		renderGamePassCard(parent, remotes, pass)
	end
end

local function renderCosmeticCard(
	parent: ScrollingFrame,
	remotes: any,
	cos: MonetizationConfigs.CosmeticSpec,
	isOwned: boolean,
	isEquipped: boolean
)
	local btnText = if isEquipped
		then "EQUIPPED"
		elseif isOwned then "EQUIP"
		else `{cos.costGems} Gems`
	local btnColor = if isEquipped
		then Theme.Colors.CardAlt
		elseif isOwned then Theme.Colors.Frost
		else Theme.Colors.Gems
	local card = makeShopCardRow(parent, "Cos_" .. cos.id, 58, btnText, 104, btnColor, function()
		if not isEquipped then
			remotes.UpgradeAction:FireServer("BuyCosmetic", cos.id)
		end
	end)
	local title = Theme.makeLabel(
		card,
		"Title",
		`{cos.displayName} [{cos.category}]`,
		UDim2.new(1, -130, 1, -8),
		UDim2.fromOffset(10, 4),
		14,
		Theme.Colors.Text,
		true
	)
	title.TextWrapped = true
	applyTextConstraint(title, 9, 14)
end

local function renderCosmeticSection(parent: ScrollingFrame, remotes: any)
	Theme.makeLabel(
		parent,
		"CosHeader",
		"COSMETICS (Boss Gems)",
		UDim2.new(1, -8, 0, 24),
		UDim2.fromOffset(0, 0),
		14,
		Theme.Colors.Gems,
		true
	)
	local ordered: { MonetizationConfigs.CosmeticSpec } = {}
	for _, cos in pairs(MonetizationConfigs.COSMETICS) do
		table.insert(ordered, cos)
	end
	table.sort(ordered, function(a, b)
		if a.costGems ~= b.costGems then
			return a.costGems < b.costGems
		end
		return a.id < b.id
	end)
	local ownedCos = if latestProfile then (latestProfile.ownedCosmetics or {}) else {}
	for _, cos in ipairs(ordered) do
		local isOwned = ownedCos[cos.id] == true
		local isEquipped = EconomyLogic.isCosmeticEquipped(latestProfile, cos.id)
		renderCosmeticCard(parent, remotes, cos, isOwned, isEquipped)
	end
end

local function renderShopTab()
	if not scrollBody then
		return
	end
	local remotes = Remotes.waitClient()
	local restricted = localPlayer:GetAttribute("ArePaidRandomItemsRestricted") ~= false
	renderEggSection(scrollBody, remotes, restricted)
	renderGamePassSection(scrollBody, remotes)
	renderCosmeticSection(scrollBody, remotes)
end

local function renderCodexCard(
	parent: ScrollingFrame,
	sp: PetConfigs.PetSpecies,
	discovered: boolean
)
	local card = Theme.makeFrame(
		parent,
		"Codex_" .. sp.id,
		UDim2.new(1, -8, 0, 62),
		UDim2.fromOffset(0, 0),
		if discovered then Theme.Colors.Card else Theme.Colors.Panel,
		10
	)
	local rCol = PetConfigs.RARITY_COLORS[sp.rarity] or { 200, 200, 200 }
	local title = Theme.makeLabel(
		card,
		"Name",
		if discovered then `{sp.displayName} [{sp.rarity}]` else `??? [{sp.rarity} — {sp.source}]`,
		UDim2.new(1, -24, 0, 22),
		UDim2.fromOffset(12, 6),
		14,
		Color3.fromRGB(rCol[1], rCol[2], rCol[3]),
		true
	)
	applyTextConstraint(title, 10, 14)
	local meta = Theme.makeLabel(
		card,
		"Meta",
		`Base: {sp.baseRate} Coins/s | Active Perk: {sp.perkLabel} | Source: {sp.source}`,
		UDim2.new(1, -24, 0, 28),
		UDim2.fromOffset(12, 28),
		11,
		Theme.Colors.Muted,
		false
	)
	meta.TextWrapped = true
	applyTextConstraint(meta, 8, 11)
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
	local summary = Theme.makeLabel(
		scrollBody,
		"Summary",
		`CREATURE CODEX: {unlockedCount} / {#allSpecies} DISCOVERED`,
		UDim2.new(1, -8, 0, 26),
		UDim2.fromOffset(0, 0),
		15,
		Theme.Colors.Gems,
		true
	)
	applyTextConstraint(summary, 11, 15)
	for _, sp in ipairs(allSpecies) do
		renderCodexCard(scrollBody, sp, unlockedMap[sp.id] == true)
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

local function buildTabButton(
	tabRow: Frame,
	name: string,
	label: string,
	color: Color3,
	tabId: string
)
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
	applyTextConstraint(tb :: any, 10, 14)
	local fx = Instance.new("UIFlexItem")
	fx.FlexMode = Enum.UIFlexMode.Fill
	fx.Parent = tb
end

local function buildHeaderAndTabs(panel: Frame)
	local title = Theme.makeLabel(
		panel,
		"Title",
		"SHOP & CREATURE CODEX",
		UDim2.new(1, -72, 0, 34),
		UDim2.fromOffset(16, 10),
		18,
		Theme.Colors.Coins,
		true
	)
	applyTextConstraint(title, 12, 18)
	Theme.makeButton(
		panel,
		"CloseBtn",
		"X",
		UDim2.fromOffset(44, 44),
		UDim2.new(1, -50, 0, 6),
		Theme.Colors.Danger,
		function()
			panel.Visible = false
		end
	)
	local tabRow = Instance.new("Frame")
	tabRow.Name = "TabRow"
	tabRow.BackgroundTransparency = 1
	tabRow.Position = UDim2.fromOffset(14, 54)
	tabRow.Size = UDim2.new(1, -28, 0, 36)
	tabRow.Parent = panel
	local tl = Instance.new("UIListLayout")
	tl.FillDirection = Enum.FillDirection.Horizontal
	tl.Padding = UDim.new(0, 8)
	tl.Parent = tabRow
	buildTabButton(tabRow, "ShopTab", "SHOP & PASSES", Theme.Colors.Coins, "Shop")
	buildTabButton(tabRow, "CodexTab", "CREATURE CODEX", Theme.Colors.Gems, "Codex")
end

local function buildScrollContainer(panel: Frame)
	local sc = Instance.new("ScrollingFrame")
	sc.Name = "Body"
	sc.BackgroundTransparency = 1
	sc.Position = UDim2.fromOffset(12, 98)
	sc.Size = UDim2.new(1, -24, 1, -110)
	sc.CanvasSize = UDim2.fromOffset(0, 0)
	sc.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sc.ScrollBarThickness = 6
	sc.Parent = panel
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.Parent = sc
	scrollBody = sc
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

	buildHeaderAndTabs(panel)
	buildScrollContainer(panel)
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
