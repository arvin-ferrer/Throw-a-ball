--!strict
--[[
	ShopCodexGui.luau
	RBLX Essentials cartoon-pop Shop & 19-Species Creature Codex UI:
	- Fail-closed PolicyService compliance (ArePaidRandomItemsRestricted ~= false -> DirectBundles)
	- Displays all 9 joint species x mutation probabilities (100.00% total) pre-purchase on Paid Eggs
	- Flagship Hero Banner Cards + Color-Coded Tile Grid for Game Passes & Boss Gem Cosmetics
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EggConfigs = require(Shared.Configs.EggConfigs)
local MonetizationConfigs = require(Shared.Configs.MonetizationConfigs)
local PetConfigs = require(Shared.Configs.PetConfigs)
local EconomyLogic = require(Shared.Utils.EconomyLogic)
local PolicyLogic = require(Shared.Utils.PolicyLogic)
local Remotes = require(Shared.Net.Remotes)

local HudIcons = require(script.Parent.HudIcons)
local Theme = require(script.Parent.Theme)

local ShopCodexGui = {}

local WHITE = Color3.fromRGB(255, 255, 255)
local MUTED_TOP = Color3.fromRGB(142, 154, 178)
local MUTED_BOT = Color3.fromRGB(104, 116, 140)
local LOCKED_BG = Color3.fromRGB(232, 236, 246)
local TILE_PALETTES = {
	{ top = Theme.Colors.TilePurpleTop, bot = Theme.Colors.TilePurpleBot },
	{ top = Theme.Colors.TileSkyTop, bot = Theme.Colors.TileSkyBot },
	{ top = Theme.Colors.TileGoldTop, bot = Theme.Colors.TileGoldBot },
}
local FLAGSHIP_PASS_KEYS: { [string]: boolean } = {
	DoubleCoinsExp = true,
	DoubleTraining = true,
}

local localPlayer = Players.LocalPlayer
local rootFrame: Frame? = nil
local headerBar: Frame? = nil
local headerTitle: TextLabel? = nil
local scrollBody: ScrollingFrame? = nil
local tabButtons: { [string]: TextButton } = {}
local activeTab = "Shop"
local latestProfile: any = nil

local function applyTextConstraint(lbl: TextLabel | TextButton, minSize: number, maxSize: number)
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
		if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
end

local function addSectionDivider(parent: ScrollingFrame, name: string, order: number)
	local div = Instance.new("Frame")
	div.Name = name
	div.LayoutOrder = order
	div.Size = UDim2.new(1, 0, 0, 3)
	div.BackgroundColor3 = Theme.Colors.Ink
	div.BorderSizePixel = 0
	div.Parent = parent
	Theme.addCorner(div, 999)
end

local function addSectionHeader(
	parent: ScrollingFrame,
	name: string,
	text: string,
	color: Color3,
	order: number
)
	local hdr = Theme.makeLabel(
		parent,
		name,
		text,
		UDim2.fromScale(1, 0),
		UDim2.fromOffset(0, 0),
		13,
		color,
		true
	)
	hdr.LayoutOrder = order
	hdr.TextWrapped = true
	hdr.AutomaticSize = Enum.AutomaticSize.Y
end

local function makeAutoHeroCard(
	parent: ScrollingFrame,
	name: string,
	topCol: Color3,
	botCol: Color3,
	order: number
): (Frame, Frame)
	local card = Theme.makeHeroBannerCard(parent, name, 0, topCol, botCol)
	card.Size = UDim2.fromScale(1, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.LayoutOrder = order
	local gloss = card:FindFirstChild("TopGloss")
	if gloss and gloss:IsA("Frame") then
		gloss.Size = UDim2.new(1, -12, 0, 38)
	end

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.ZIndex = 2
	content.Parent = card
	Theme.addPadding(content, 10, 10)
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 8)
	list.Parent = content
	return card, content
end

local function makeLightDetailBox(parent: Frame, name: string, text: string, order: number)
	local box = Instance.new("Frame")
	box.Name = name
	box.LayoutOrder = order
	box.Size = UDim2.fromScale(1, 0)
	box.AutomaticSize = Enum.AutomaticSize.Y
	box.BackgroundColor3 = Theme.Colors.WindowBg
	box.BackgroundTransparency = 0.03
	box.BorderSizePixel = 0
	box.Parent = parent
	Theme.addCorner(box, 10)
	Theme.addStroke(box, Theme.Colors.Ink, 1.8, 0)
	Theme.addPadding(box, 10, 8)

	local desc = Theme.makeLabel(
		box,
		"Desc",
		text,
		UDim2.fromScale(1, 0),
		UDim2.fromOffset(0, 0),
		12,
		Theme.Colors.TextDark,
		false
	)
	desc.TextWrapped = true
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.AutomaticSize = Enum.AutomaticSize.Y
end

local function formatJointOddsBlock(jointOdds: { PolicyLogic.JointOdd }?): string
	if not jointOdds or #jointOdds == 0 then
		return ""
	end
	local total = 0
	local lines: { string } = {}
	for _, entry in ipairs(jointOdds) do
		total += entry.percent
		local sp = PetConfigs.getSpecies(entry.speciesId)
		local mutSpec = PetConfigs.MUTATIONS[entry.mutationKey]
		local speciesLabel = if sp then sp.displayName else entry.speciesId
		local mutLabel = if mutSpec then mutSpec.displayName else entry.mutationKey
		table.insert(lines, `• {speciesLabel} ({mutLabel}): {entry.formattedPercent}`)
	end
	local header = string.format("Pre-Purchase Odds (%.2f%% Total):", total)
	return header .. "\n" .. table.concat(lines, "\n")
end

local function makeHeroRightColumn(row: Frame): Frame
	local rightCol = Instance.new("Frame")
	rightCol.Name = "RightCol"
	rightCol.BackgroundTransparency = 1
	rightCol.Position = UDim2.fromOffset(58, 0)
	rightCol.Size = UDim2.new(1, -58, 0, 0)
	rightCol.AutomaticSize = Enum.AutomaticSize.Y
	rightCol.Parent = row
	local colList = Instance.new("UIListLayout")
	colList.SortOrder = Enum.SortOrder.LayoutOrder
	colList.HorizontalAlignment = Enum.HorizontalAlignment.Right
	colList.Padding = UDim.new(0, 6)
	colList.Parent = rightCol
	return rightCol
end

local function buildHeroTopRow(
	content: Frame,
	titleText: string,
	btnText: string,
	btnTop: Color3?,
	btnBot: Color3?,
	onClick: () -> ()
): Frame
	local row = Instance.new("Frame")
	row.Name = "HeaderRow"
	row.BackgroundTransparency = 1
	row.LayoutOrder = 1
	row.Size = UDim2.new(1, 0, 0, 56)
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.Parent = content

	local rightCol = makeHeroRightColumn(row)
	local title = Theme.makeLabel(
		rightCol,
		"Name",
		titleText,
		UDim2.fromScale(1, 0),
		UDim2.fromOffset(0, 0),
		18,
		WHITE,
		true
	)
	title.LayoutOrder = 1
	title.TextWrapped = true
	title.AutomaticSize = Enum.AutomaticSize.Y
	Theme.addTextStroke(title, 2, Theme.Colors.Ink)

	local btn = Theme.makeGoldPillButton(
		rightCol,
		"BuyBtn",
		btnText,
		UDim2.fromOffset(132, 48),
		UDim2.fromOffset(0, 0),
		onClick,
		btnTop,
		btnBot
	)
	btn.LayoutOrder = 2
	applyTextConstraint(btn, 10, 15)
	return row
end

local function resolveEggAccent(eggId: string): Color3?
	local cfg = EggConfigs.getEgg(eggId)
	if not cfg then
		return nil
	end
	local c = cfg.primaryColor
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function renderOfferCard(
	parent: ScrollingFrame,
	remotes: any,
	item: PolicyLogic.ShopCatalogItem,
	idx: number,
	order: number
)
	local useMint = idx % 2 == 1
	local topCol = if useMint then Theme.Colors.MintTop else Theme.Colors.LimeTop
	local botCol = if useMint then Theme.Colors.MintBot else Theme.Colors.LimeBot
	local _, content = makeAutoHeroCard(parent, "Offer_" .. item.id, topCol, botCol, order)
	local row = buildHeroTopRow(
		content,
		item.displayName,
		"BUY (ROBUX)",
		Theme.Colors.GoldTop,
		Theme.Colors.GoldBot,
		function()
			remotes.ShopRequest:FireServer("Product", item.devProductId)
		end
	)
	local icon = if item.kind == "PaidEgg"
		then HudIcons.createEggIcon(row, 50, resolveEggAccent(item.id))
		else HudIcons.createStarBurstIcon(row, 50)
	icon.Position = UDim2.fromOffset(0, 4)

	local bodyText = if item.kind == "PaidEgg"
		then formatJointOddsBlock(item.jointOdds)
		else item.description
	makeLightDetailBox(content, "OddsBox", bodyText, 2)
end

local function renderEggSection(
	parent: ScrollingFrame,
	remotes: any,
	restricted: boolean,
	startOrder: number
): number
	local order = startOrder
	local headerText = if restricted
		then "DIRECT NON-RANDOM BUNDLES (Regional Policy Compliance — Zero RNG)"
		else "SHOP EXCLUSIVE EGGS (100.00% Disclosed Odds • Boss Eggs Stay Gameplay-Earned!)"
	addSectionHeader(parent, "ShopHeader", headerText, Theme.Colors.TextDark, order)
	order += 1
	for idx, item in ipairs(PolicyLogic.buildShopOfferings(restricted)) do
		renderOfferCard(parent, remotes, item, idx, order)
		order += 1
	end
	return order
end

local function renderFlagshipPassCard(
	parent: ScrollingFrame,
	remotes: any,
	pass: MonetizationConfigs.GamePassSpec,
	order: number
)
	local owned = localPlayer:GetAttribute(pass.attributeName) == true
	local isCoins = pass.key == "DoubleCoinsExp"
	local topCol = if isCoins then Theme.Colors.LimeTop else Theme.Colors.MintTop
	local botCol = if isCoins then Theme.Colors.LimeBot else Theme.Colors.MintBot
	local btnTop = if owned then MUTED_TOP else Theme.Colors.GoldTop
	local btnBot = if owned then MUTED_BOT else Theme.Colors.GoldBot
	local _, content = makeAutoHeroCard(parent, "Pass_" .. pass.key, topCol, botCol, order)
	local row = buildHeroTopRow(
		content,
		pass.displayName,
		if owned then "OWNED" else "GET PASS",
		btnTop,
		btnBot,
		function()
			if not owned then
				remotes.ShopRequest:FireServer("GamePass", pass.key)
			end
		end
	)
	local icon = if isCoins
		then HudIcons.createCashStackIcon(row, 50)
		else HudIcons.createStarBurstIcon(row, 50)
	icon.Position = UDim2.fromOffset(0, 4)
	makeLightDetailBox(content, "DescBox", pass.description, 2)
end

local function createTileGrid(
	parent: ScrollingFrame,
	name: string,
	cellHeight: number,
	order: number
): Frame
	local grid = Instance.new("Frame")
	grid.Name = name
	grid.LayoutOrder = order
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.fromScale(1, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.Parent = parent

	local metrics = Theme.getLayoutMetrics()
	local cols = if metrics.isCompact then 2 else 3
	local pad = 8
	local gl = Instance.new("UIGridLayout")
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.CellPadding = UDim2.fromOffset(pad, pad)
	gl.CellSize = UDim2.new(1 / cols, -math.ceil(pad * (cols - 1) / cols), 0, cellHeight)
	gl.Parent = grid
	return grid
end

local function createTileIcon(tile: Frame, kind: string, accent: Color3?): Frame
	local icon = if kind == "Cash"
		then HudIcons.createCashStackIcon(tile, 44)
		elseif kind == "Gift" then HudIcons.createGiftIcon(tile, 44)
		elseif kind == "Egg" then HudIcons.createEggIcon(tile, 44, accent)
		else HudIcons.createStarBurstIcon(tile, 44)
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 8)
	icon.ZIndex = 2
	return icon
end

local function addTileLabels(tile: Frame, titleText: string, subText: string)
	local title = Theme.makeLabel(
		tile,
		"Title",
		titleText,
		UDim2.new(1, -12, 0, 32),
		UDim2.fromOffset(6, 54),
		14,
		WHITE,
		true
	)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextWrapped = true
	title.ZIndex = 2
	Theme.addTextStroke(title, 1.8, Theme.Colors.Ink)
	applyTextConstraint(title, 10, 14)

	local sub = Theme.makeLabel(
		tile,
		"Desc",
		subText,
		UDim2.new(1, -12, 0, 26),
		UDim2.fromOffset(6, 86),
		10,
		WHITE,
		false
	)
	sub.TextXAlignment = Enum.TextXAlignment.Center
	sub.TextWrapped = true
	sub.ZIndex = 2
	Theme.addTextStroke(sub, 1.2, Theme.Colors.Ink)
	applyTextConstraint(sub, 8, 10)
end

type TileCardSpec = {
	name: string,
	title: string,
	sub: string,
	iconKind: string,
	paletteIdx: number,
	btnText: string,
	btnTop: Color3,
	btnBot: Color3,
	order: number,
	onClick: () -> (),
}

local function renderTileCard(grid: Frame, spec: TileCardSpec)
	local pal = TILE_PALETTES[((spec.paletteIdx - 1) % #TILE_PALETTES) + 1]
	local tile = Theme.makeTileCard(grid, spec.name, UDim2.fromOffset(140, 172), pal.top, pal.bot)
	tile.LayoutOrder = spec.order
	createTileIcon(tile, spec.iconKind, nil)
	addTileLabels(tile, spec.title, spec.sub)

	local btn = Theme.makeGoldPillButton(
		tile,
		"BuyBtn",
		spec.btnText,
		UDim2.new(1, -12, 0, 48),
		UDim2.new(0, 6, 1, -54),
		spec.onClick,
		spec.btnTop,
		spec.btnBot
	)
	btn.ZIndex = 2
	applyTextConstraint(btn, 9, 14)
end

local function getPassTileIconKind(passKey: string): string
	if passKey == "MagnetCollect" then
		return "Cash"
	elseif passKey == "ExtraPedestals" then
		return "Gift"
	end
	return "Star"
end

local function getSortedGamePasses(): { MonetizationConfigs.GamePassSpec }
	local ordered: { MonetizationConfigs.GamePassSpec } = {}
	for _, pass in pairs(MonetizationConfigs.GAME_PASSES) do
		table.insert(ordered, pass)
	end
	table.sort(ordered, function(a, b)
		return a.passId < b.passId
	end)
	return ordered
end

local function renderPassTile(
	grid: Frame,
	remotes: any,
	pass: MonetizationConfigs.GamePassSpec,
	idx: number
)
	local owned = localPlayer:GetAttribute(pass.attributeName) == true
	renderTileCard(grid, {
		name = "Pass_" .. pass.key,
		title = pass.displayName,
		sub = pass.description,
		iconKind = getPassTileIconKind(pass.key),
		paletteIdx = idx,
		btnText = if owned then "OWNED" else "GET PASS",
		btnTop = if owned then MUTED_TOP else Theme.Colors.GoldTop,
		btnBot = if owned then MUTED_BOT else Theme.Colors.GoldBot,
		order = idx,
		onClick = function()
			if not owned then
				remotes.ShopRequest:FireServer("GamePass", pass.key)
			end
		end,
	})
end

local function renderGamePassSection(
	parent: ScrollingFrame,
	remotes: any,
	startOrder: number
): number
	local order = startOrder
	addSectionDivider(parent, "PassDivider", order)
	order += 1
	addSectionHeader(
		parent,
		"PassHeader",
		"GAME PASSES (Progression & QoL)",
		Theme.Colors.TextDark,
		order
	)
	order += 1

	local tilePasses: { MonetizationConfigs.GamePassSpec } = {}
	for _, pass in ipairs(getSortedGamePasses()) do
		if FLAGSHIP_PASS_KEYS[pass.key] then
			renderFlagshipPassCard(parent, remotes, pass, order)
			order += 1
		else
			table.insert(tilePasses, pass)
		end
	end

	local grid = createTileGrid(parent, "PassTileGrid", 172, order)
	order += 1
	for idx, pass in ipairs(tilePasses) do
		renderPassTile(grid, remotes, pass, idx)
	end
	return order
end

local function getCosmeticIconKind(category: string): string
	if category == "HatchVFX" then
		return "Egg"
	elseif category == "PlotTheme" then
		return "Cash"
	elseif category == "EliminationVFX" then
		return "Star"
	end
	return "Gift"
end

local function getSortedCosmetics(): { MonetizationConfigs.CosmeticSpec }
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
	return ordered
end

local function renderCosmeticTile(
	grid: Frame,
	remotes: any,
	cos: MonetizationConfigs.CosmeticSpec,
	isOwned: boolean,
	isEquipped: boolean,
	idx: number
)
	local btnText = if isEquipped
		then "EQUIPPED"
		elseif isOwned then "EQUIP"
		else `{cos.costGems} Gems`
	local btnTop = if isEquipped
		then MUTED_TOP
		elseif isOwned then Theme.Colors.TileSkyTop
		else Theme.Colors.GoldTop
	local btnBot = if isEquipped
		then MUTED_BOT
		elseif isOwned then Theme.Colors.TileSkyBot
		else Theme.Colors.GoldBot
	renderTileCard(grid, {
		name = "Cos_" .. cos.id,
		title = cos.displayName,
		sub = cos.category,
		iconKind = getCosmeticIconKind(cos.category),
		paletteIdx = idx,
		btnText = btnText,
		btnTop = btnTop,
		btnBot = btnBot,
		order = idx,
		onClick = function()
			if not isEquipped then
				remotes.UpgradeAction:FireServer("BuyCosmetic", cos.id)
			end
		end,
	})
end

local function renderCosmeticSection(
	parent: ScrollingFrame,
	remotes: any,
	startOrder: number
): number
	local order = startOrder
	addSectionDivider(parent, "CosDivider", order)
	order += 1
	addSectionHeader(parent, "CosHeader", "COSMETICS (Boss Gems)", Theme.Colors.TextDark, order)
	order += 1

	local ownedCos = if latestProfile then (latestProfile.ownedCosmetics or {}) else {}
	local grid = createTileGrid(parent, "CosTileGrid", 172, order)
	order += 1
	for idx, cos in ipairs(getSortedCosmetics()) do
		local isOwned = ownedCos[cos.id] == true
		local isEquipped = EconomyLogic.isCosmeticEquipped(latestProfile, cos.id)
		renderCosmeticTile(grid, remotes, cos, isOwned, isEquipped, idx)
	end
	return order
end

local function renderShopTab()
	if not scrollBody then
		return
	end
	local remotes = Remotes.waitClient()
	local restricted = localPlayer:GetAttribute("ArePaidRandomItemsRestricted") ~= false
	local nextOrder = renderEggSection(scrollBody, remotes, restricted, 1)
	nextOrder = renderGamePassSection(scrollBody, remotes, nextOrder)
	renderCosmeticSection(scrollBody, remotes, nextOrder)
end

local function addCodexProgressBar(banner: Frame, unlockedCount: number, totalCount: number)
	local barBg = Instance.new("Frame")
	barBg.Name = "ProgressBg"
	barBg.Position = UDim2.fromOffset(60, 38)
	barBg.Size = UDim2.new(1, -74, 0, 14)
	barBg.BackgroundColor3 = Theme.Colors.Ink
	barBg.BorderSizePixel = 0
	barBg.ZIndex = 2
	barBg.Parent = banner
	Theme.addCorner(barBg, 999)

	local ratio = if totalCount > 0 then math.clamp(unlockedCount / totalCount, 0, 1) else 0
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(ratio, 1)
	fill.BackgroundColor3 = WHITE
	fill.BorderSizePixel = 0
	fill.ZIndex = 3
	fill.Parent = barBg
	Theme.addCorner(fill, 999)
	Theme.addGradient(fill, Theme.Colors.LimeTop, Theme.Colors.LimeBot, 90)
end

local function renderCodexSummary(parent: ScrollingFrame, unlockedCount: number, totalCount: number)
	local banner = Theme.makeHeroBannerCard(
		parent,
		"Summary",
		62,
		Theme.Colors.CodexPurpleTop,
		Theme.Colors.CodexPurpleBot
	)
	banner.LayoutOrder = 1
	local icon = HudIcons.createCodexIcon(banner, 42)
	icon.Position = UDim2.fromOffset(10, 10)
	icon.ZIndex = 2

	local lbl = Theme.makeLabel(
		banner,
		"SummaryText",
		`CREATURE CODEX: {unlockedCount} / {totalCount} DISCOVERED`,
		UDim2.new(1, -68, 0, 26),
		UDim2.fromOffset(60, 8),
		16,
		WHITE,
		true
	)
	lbl.ZIndex = 2
	Theme.addTextStroke(lbl, 2, Theme.Colors.Ink)
	applyTextConstraint(lbl, 11, 16)
	addCodexProgressBar(banner, unlockedCount, totalCount)
end

local function buildCodexHeaderRow(
	card: Frame,
	sp: PetConfigs.PetSpecies,
	discovered: boolean,
	rarityColor: Color3
)
	local topRow = Instance.new("Frame")
	topRow.Name = "TopRow"
	topRow.BackgroundTransparency = 1
	topRow.LayoutOrder = 1
	topRow.Size = UDim2.new(1, 0, 0, 24)
	topRow.Parent = card

	local titleText = if discovered then sp.displayName else `??? ({sp.source})`
	local title = Theme.makeLabel(
		topRow,
		"Name",
		titleText,
		UDim2.new(1, -92, 1, 0),
		UDim2.fromOffset(0, 0),
		15,
		Theme.Colors.TextDark,
		true
	)
	applyTextConstraint(title, 11, 15)

	local badge = Theme.makeLabel(
		topRow,
		"RarityBadge",
		sp.rarity,
		UDim2.fromOffset(86, 22),
		UDim2.new(1, -86, 0, 1),
		11,
		WHITE,
		true
	)
	badge.BackgroundTransparency = 0
	badge.BackgroundColor3 = rarityColor
	badge.TextXAlignment = Enum.TextXAlignment.Center
	Theme.addCorner(badge, 999)
	Theme.addStroke(badge, Theme.Colors.Ink, 1.5, 0)
	Theme.addTextStroke(badge, 1.4, Theme.Colors.Ink)
end

local function renderCodexCard(
	parent: ScrollingFrame,
	sp: PetConfigs.PetSpecies,
	discovered: boolean,
	order: number
)
	local rCol = PetConfigs.RARITY_COLORS[sp.rarity] or { 120, 130, 150 }
	local rarityColor = Color3.fromRGB(rCol[1], rCol[2], rCol[3])
	local card = Instance.new("Frame")
	card.Name = "Codex_" .. sp.id
	card.LayoutOrder = order
	card.Size = UDim2.fromScale(1, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = if discovered then WHITE else LOCKED_BG
	card.BorderSizePixel = 0
	card.Parent = parent
	Theme.addCorner(card, 12)
	Theme.addStroke(card, if discovered then rarityColor else Theme.Colors.TextMutedDark, 2.5, 0)
	Theme.addPadding(card, 12, 8)
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 4)
	list.Parent = card

	buildCodexHeaderRow(card, sp, discovered, rarityColor)
	local meta = Theme.makeLabel(
		card,
		"Meta",
		`Base: {sp.baseRate} Coins/s | Active Perk: {sp.perkLabel} | Source: {sp.source}`,
		UDim2.fromScale(1, 0),
		UDim2.fromOffset(0, 0),
		12,
		Theme.Colors.TextMutedDark,
		false
	)
	meta.LayoutOrder = 2
	meta.TextWrapped = true
	meta.AutomaticSize = Enum.AutomaticSize.Y
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
	renderCodexSummary(scrollBody, unlockedCount, #allSpecies)
	for idx, sp in ipairs(allSpecies) do
		renderCodexCard(scrollBody, sp, unlockedMap[sp.id] == true, idx + 1)
	end
end

local function updateHeaderAndTabStyle()
	local isShop = activeTab == "Shop"
	if headerBar then
		local topCol = if isShop then Theme.Colors.ShopRedTop else Theme.Colors.CodexPurpleTop
		local botCol = if isShop then Theme.Colors.ShopRedBot else Theme.Colors.CodexPurpleBot
		Theme.addGradient(headerBar, topCol, botCol, 90)
	end
	if headerTitle then
		headerTitle.Text = if isShop then "SHOP" else "CREATURE CODEX"
	end
	local shopBtn = tabButtons.Shop
	if shopBtn then
		local topCol = if isShop then Theme.Colors.ShopRedTop else MUTED_TOP
		local botCol = if isShop then Theme.Colors.ShopRedBot else MUTED_BOT
		Theme.addGradient(shopBtn, topCol, botCol, 90)
	end
	local codexBtn = tabButtons.Codex
	if codexBtn then
		local topCol = if isShop then MUTED_TOP else Theme.Colors.CodexPurpleTop
		local botCol = if isShop then MUTED_BOT else Theme.Colors.CodexPurpleBot
		Theme.addGradient(codexBtn, topCol, botCol, 90)
	end
end

local function rerender()
	if not rootFrame or not rootFrame.Visible then
		return
	end
	updateHeaderAndTabStyle()
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
	topCol: Color3,
	botCol: Color3,
	tabId: string,
	order: number
)
	local tb = Theme.makeGoldPillButton(
		tabRow,
		name,
		label,
		UDim2.fromScale(0.48, 1),
		UDim2.fromOffset(0, 0),
		function()
			activeTab = tabId
			rerender()
		end,
		topCol,
		botCol
	)
	tb.LayoutOrder = order
	applyTextConstraint(tb, 11, 15)
	local fx = Instance.new("UIFlexItem")
	fx.FlexMode = Enum.UIFlexMode.Fill
	fx.Parent = tb
	tabButtons[tabId] = tb
end

local function buildHeaderAndTabs(panel: Frame)
	local bar, title = Theme.makeHeaderBanner(
		panel,
		"SHOP",
		Theme.Colors.ShopRedTop,
		Theme.Colors.ShopRedBot,
		function()
			panel.Visible = false
		end
	)
	headerBar = bar
	headerTitle = title

	local tabRow = Instance.new("Frame")
	tabRow.Name = "TabRow"
	tabRow.BackgroundTransparency = 1
	tabRow.Position = UDim2.fromOffset(14, 60)
	tabRow.Size = UDim2.new(1, -28, 0, 44)
	tabRow.Parent = panel
	local tl = Instance.new("UIListLayout")
	tl.FillDirection = Enum.FillDirection.Horizontal
	tl.SortOrder = Enum.SortOrder.LayoutOrder
	tl.Padding = UDim.new(0, 8)
	tl.Parent = tabRow

	buildTabButton(
		tabRow,
		"ShopTab",
		"SHOP & PASSES",
		Theme.Colors.ShopRedTop,
		Theme.Colors.ShopRedBot,
		"Shop",
		1
	)
	buildTabButton(tabRow, "CodexTab", "CREATURE CODEX", MUTED_TOP, MUTED_BOT, "Codex", 2)
end

local function buildScrollContainer(panel: Frame)
	local sc = Instance.new("ScrollingFrame")
	sc.Name = "Body"
	sc.BackgroundTransparency = 1
	sc.BorderSizePixel = 0
	sc.Position = UDim2.fromOffset(12, 112)
	sc.Size = UDim2.new(1, -24, 1, -122)
	sc.CanvasSize = UDim2.fromOffset(0, 0)
	sc.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sc.ScrollBarThickness = 6
	sc.ScrollBarImageColor3 = Theme.Colors.Ink
	sc.Parent = panel
	Theme.addPadding(sc, 4, 4)
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 10)
	list.Parent = sc
	scrollBody = sc
end

function ShopCodexGui.mount()
	local gui = Theme.createScreenGui("BallBrawl_ShopCodex", 22)
	local panel = Theme.makeCartoonWindow(
		gui,
		"ShopPanel",
		UDim2.fromScale(0.92, 0.86),
		UDim2.fromScale(0.5, 0.5),
		16
	)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Visible = false
	local scConstraint = Instance.new("UISizeConstraint")
	scConstraint.MaxSize = Vector2.new(600, 480)
	scConstraint.MinSize = Vector2.new(300, 260)
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
