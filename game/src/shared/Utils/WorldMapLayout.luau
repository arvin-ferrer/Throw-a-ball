--!strict
--[[
	WorldMapLayout.luau
	Pure Lune-testable spatial coordinates, constants, and geometry specs for
	Workspace.BallBrawl_Map_v2 (Hub Plaza, 8 Plots, 3 Biomes + BossPvPArena, VaultHeist).
]]

export type Vec3 = { number }

export type PortalSpec = {
	name: string,
	biomeId: string,
	enabled: boolean,
	recommendedDamage: number,
	tag: string,
	title: string,
	subtitle: string,
	color: { number },
	angleDeg: number,
}

export type ServiceSpec = {
	name: string,
	serviceId: string,
	tag: string,
	title: string,
	subtitle: string,
	color: { number },
	angleDeg: number,
	isLeaderboard: boolean,
}

export type PlotTransformSpec = {
	plotId: number,
	plotName: string,
	center: Vec3,
	lookAt: Vec3,
	angleDeg: number,
}

export type PedestalSpec = {
	index: number,
	name: string,
	tier: number,
	basePos: Vec3,
	cashPadPos: Vec3,
	petAnchorPos: Vec3,
	isBalcony: boolean,
	isVip: boolean,
}

export type RingSegmentSpec = {
	index: number,
	center: Vec3,
	lookAt: Vec3,
	size: Vec3,
}

export type BiomeSpatialSpec = {
	biomeId: string,
	order: number,
	pveCenter: Vec3,
	arenaCenter: Vec3,
}

export type MobSpawnSpec = {
	offset: Vec3,
	mobType: string?,
	spawnCount: number?,
	escortMobType: string?,
	escortCount: number?,
	isPerched: boolean?,
	perchAxis: Vec3?,
	district: string?,
}

local WorldMapLayout = {}

WorldMapLayout.MAP_NAME = "BallBrawl_Map_v2"
WorldMapLayout.MAP_VERSION = "2.1-emerald-10x"
WorldMapLayout.BIOME_SPACING_X = 2000
WorldMapLayout.ARENA_OFFSET_Z = 1200

WorldMapLayout.EMERALD_MEADOW_PVE_CENTER = { 2000, 0, -3500 } :: Vec3
WorldMapLayout.EMERALD_MEADOW_PVE_SIZE = { 1720, 4, 1580 } :: Vec3
WorldMapLayout.EMERALD_MEADOW_CLIFF_RIM_SIZE = { 1800, 72, 1660 } :: Vec3
WorldMapLayout.EMERALD_MEADOW_ARRIVAL_OFFSET = { 0, 0.3, -675 } :: Vec3
WorldMapLayout.EMERALD_MEADOW_RETURN_OFFSET = { 0, 10, -718 } :: Vec3

WorldMapLayout.FUTURE_10X_BIOME_SLOTS = {
	EmeraldMeadow = { 2000, 0, -3500 },
	FrostbiteCavern = { 5500, 0, -3500 },
	MoltenCaldera = { 9000, 0, -3500 },
} :: { [string]: Vec3 }

WorldMapLayout.HUB_RADIUS = 236
WorldMapLayout.HUB_FLOOR_SIZE = { 490, 4, 490 }
WorldMapLayout.HUB_BOUNDARY_RADIUS = 234
WorldMapLayout.HUB_BOUNDARY_COUNT = 32
WorldMapLayout.PORTAL_RING_RADIUS = 68
WorldMapLayout.SERVICE_RING_RADIUS = 68
WorldMapLayout.PLOT_RING_RADIUS = 166
WorldMapLayout.PLOT_SIZE = { 80, 2, 90 }
WorldMapLayout.PLOT_COUNT = 8
WorldMapLayout.PEDESTALS_PER_PLOT = 14
WorldMapLayout.DEFAULT_UNLOCKED_PEDESTALS = 4

WorldMapLayout.FALLBACK_SPAWN_POS = { 0, 0.5, 24 }
WorldMapLayout.BEACON_POS = { 0, 0, 0 }

WorldMapLayout.BIOME_PVE_SIZE = { 284, 4, 284 }
WorldMapLayout.BIOME_RIM_RADIUS = 136
WorldMapLayout.BIOME_WALL_COUNT = 24
WorldMapLayout.ARENA_FLOOR_DIAMETER = 264
WorldMapLayout.ARENA_ROOM_VOLUME_SIZE = { 264, 140, 264 }
WorldMapLayout.ARENA_ROOM_VOLUME_Y = 60
WorldMapLayout.ARENA_WALL_RADIUS = 126
WorldMapLayout.ARENA_OPTIN_RADIUS = 74
WorldMapLayout.ARENA_PILLAR_RADIUS = 44
WorldMapLayout.ARENA_PILLAR_COUNT = 6
WorldMapLayout.ARENA_OPTIN_COUNT = 8
WorldMapLayout.MOB_SPAWNS_PER_BIOME = 8

WorldMapLayout.VAULT_CENTER = { 0, 0, -900 }
WorldMapLayout.VAULT_FLOOR_SIZE = { 120, 4, 120 }
WorldMapLayout.VAULT_SPAWN_POS = { -18, 0.25, -850 }
WorldMapLayout.VAULT_EXTRACTION_POS = { 18, 0.25, -850 }
WorldMapLayout.VAULT_BOSS_SPAWN_POS = { 0, 0.25, -900 }
WorldMapLayout.VAULT_EGG_PEDESTAL_POS = { 0, 2.0, -942 }
WorldMapLayout.VAULT_LASER_GATE_POS = { 0, 3.2, -922 }
WorldMapLayout.VAULT_LASER_GATE_SIZE = { 48, 6.4, 1.5 }

WorldMapLayout.PORTALS = {
	{
		name = "Portal_VaultHeist",
		biomeId = "VaultHeist",
		enabled = true,
		recommendedDamage = 0,
		tag = "VaultHeistPortal",
		title = "VAULT HEIST",
		subtitle = "Instant Co-Op • 0s Wait!",
		color = { 250, 204, 21 },
		angleDeg = -70,
	},
	{
		name = "Portal_1_EmeraldMeadow",
		biomeId = "EmeraldMeadow",
		enabled = true,
		recommendedDamage = 15,
		tag = "BiomePortal",
		title = "EMERALD MEADOW",
		subtitle = "Rec. 15 DMG",
		color = { 52, 211, 153 },
		angleDeg = -42,
	},
	{
		name = "Portal_2_FrostbiteCavern",
		biomeId = "FrostbiteCavern",
		enabled = true,
		recommendedDamage = 150,
		tag = "BiomePortal",
		title = "FROSTBITE CAVERN",
		subtitle = "Rec. 150 DMG",
		color = { 56, 189, 248 },
		angleDeg = -14,
	},
	{
		name = "Portal_3_MoltenCaldera",
		biomeId = "MoltenCaldera",
		enabled = true,
		recommendedDamage = 1200,
		tag = "BiomePortal",
		title = "MOLTEN CALDERA",
		subtitle = "Rec. 1.2K DMG",
		color = { 251, 113, 42 },
		angleDeg = 14,
	},
	{
		name = "Portal_4_StormRuins",
		biomeId = "StormRuins",
		enabled = false,
		recommendedDamage = 8500,
		tag = "BiomePortal",
		title = "STORM RUINS",
		subtitle = "COMING SOON",
		color = { 129, 140, 248 },
		angleDeg = 42,
	},
	{
		name = "Portal_5_VoidCitadel",
		biomeId = "VoidCitadel",
		enabled = false,
		recommendedDamage = 50000,
		tag = "BiomePortal",
		title = "VOID CITADEL",
		subtitle = "COMING SOON",
		color = { 192, 132, 252 },
		angleDeg = 70,
	},
} :: { PortalSpec }

WorldMapLayout.SERVICES = {
	{
		name = "BallShop",
		serviceId = "BallShop",
		tag = "ServiceInteract",
		title = "BALL SHOP",
		subtitle = "Upgrade Throwables",
		color = { 239, 68, 68 },
		angleDeg = 102,
		isLeaderboard = false,
	},
	{
		name = "EggShop",
		serviceId = "EggShop",
		tag = "ServiceInteract",
		title = "EGG SHOP",
		subtitle = "Permanent & Seasonal",
		color = { 250, 204, 21 },
		angleDeg = 128,
		isLeaderboard = false,
	},
	{
		name = "TraitAltar",
		serviceId = "TraitAltar",
		tag = "ServiceInteract",
		title = "TRAIT ALTAR",
		subtitle = "Reroll Pet Traits",
		color = { 168, 85, 247 },
		angleDeg = 154,
		isLeaderboard = false,
	},
	{
		name = "LeaderboardBoard",
		serviceId = "Leaderboard",
		tag = "LeaderboardBoard",
		title = "SERVER LEADERBOARDS",
		subtitle = "Top Power • Boss Wins • Coins/s",
		color = { 56, 189, 248 },
		angleDeg = 180,
		isLeaderboard = true,
	},
	{
		name = "GemEggCrafter",
		serviceId = "GemEggCrafter",
		tag = "ServiceInteract",
		title = "GEM EGG CRAFTER",
		subtitle = "Craft Biome Eggs",
		color = { 52, 211, 153 },
		angleDeg = -154,
		isLeaderboard = false,
	},
	{
		name = "AscensionShrine",
		serviceId = "AscensionShrine",
		tag = "ServiceInteract",
		title = "ASCENSION SHRINE",
		subtitle = "+25% Coins / Rank",
		color = { 255, 114, 188 },
		angleDeg = -128,
		isLeaderboard = false,
	},
	{
		name = "CodexPavilion",
		serviceId = "CodexPavilion",
		tag = "ServiceInteract",
		title = "CODEX PAVILION",
		subtitle = "Collection Progress",
		color = { 96, 165, 250 },
		angleDeg = -102,
		isLeaderboard = false,
	},
} :: { ServiceSpec }

WorldMapLayout.MOB_SPAWN_OFFSETS = {
	{ -55, 0, 38 },
	{ 55, 0, 38 },
	{ -80, 0, -5 },
	{ 80, 0, -5 },
	{ -35, 0, -20 },
	{ 35, 0, -20 },
	{ -58, 0, -68 },
	{ 58, 0, -68 },
} :: { Vec3 }

WorldMapLayout.EMERALD_MEADOW_RIVER_WAYPOINTS = {
	{ -815, 0, -375 },
	{ -625, 0, -295 },
	{ -430, 0, -195 },
	{ -225, 0, -90 },
	{ -35, 0, -145 },
	{ 185, 0, -75 },
	{ 255, 0, 130 },
	{ 125, 0, 325 },
	{ 365, 0, 425 },
	{ 610, 0, 445 },
	{ 810, 0, 385 },
} :: { Vec3 }

WorldMapLayout.EMERALD_MEADOW_MOB_SPAWNS = {
	-- District 1: North Gate & Arrival Commons (6 ground pads -> 15 mobs)
	{ offset = { -185, 0, -565 }, mobType = "MossSlime", spawnCount = 3, district = "NorthGate" },
	{ offset = { -110, 0, -475 }, mobType = "MossSlime", spawnCount = 3, district = "NorthGate" },
	{ offset = { 105, 0, -490 }, mobType = "MossSlime", spawnCount = 3, district = "NorthGate" },
	{ offset = { 215, 0, -545 }, mobType = "MossSlime", spawnCount = 2, district = "NorthGate" },
	{
		offset = { -20, 0, -425 },
		mobType = "ElderMossSlime",
		spawnCount = 1,
		escortMobType = "MossSlime",
		escortCount = 1,
		district = "NorthGate",
	},
	{ offset = { 155, 0, -395 }, mobType = "BrambleBoar", spawnCount = 2, district = "NorthGate" },

	-- District 2: Whispering Mill Hamlet (10 ground pads -> 24 mobs)
	{
		offset = { -335, 0, -475 },
		mobType = "MossSlime",
		spawnCount = 3,
		district = "WhisperingMill",
	},
	{
		offset = { -520, 0, -495 },
		mobType = "ElderMossSlime",
		spawnCount = 1,
		escortMobType = "MossSlime",
		escortCount = 2,
		district = "WhisperingMill",
	},
	{
		offset = { -690, 0, -255 },
		mobType = "RiverSnapper",
		spawnCount = 2,
		district = "WhisperingMill",
	},
	{
		offset = { -310, 0, -315 },
		mobType = "RiverSnapper",
		spawnCount = 2,
		district = "WhisperingMill",
	},
	{
		offset = { -570, 0, -25 },
		mobType = "MossSlime",
		spawnCount = 3,
		district = "WhisperingMill",
	},
	{
		offset = { -715, 0, -30 },
		mobType = "MossSlime",
		spawnCount = 2,
		district = "WhisperingMill",
	},
	{
		offset = { -425, 0, -25 },
		mobType = "TidecrestSnapper",
		spawnCount = 1,
		escortMobType = "RiverSnapper",
		escortCount = 2,
		district = "WhisperingMill",
	},
	{
		offset = { -675, 0, 110 },
		mobType = "BrambleBoar",
		spawnCount = 2,
		district = "WhisperingMill",
	},
	{
		offset = { -525, 0, 130 },
		mobType = "ThornbackAlpha",
		spawnCount = 1,
		escortMobType = "BrambleBoar",
		escortCount = 1,
		district = "WhisperingMill",
	},
	{
		offset = { -360, 0, 125 },
		mobType = "BrambleBoar",
		spawnCount = 2,
		district = "WhisperingMill",
	},

	-- District 3: Central Emerald Confluence Glade (10 ground pads -> 21 mobs)
	{
		offset = { -220, 0, 45 },
		mobType = "RiverSnapper",
		spawnCount = 2,
		district = "CentralGlade",
	},
	{
		offset = { -145, 0, 145 },
		mobType = "RuinSentinel",
		spawnCount = 2,
		district = "CentralGlade",
	},
	{
		offset = { 125, 0, 115 },
		mobType = "AncientWarden",
		spawnCount = 1,
		escortMobType = "RuinSentinel",
		escortCount = 1,
		district = "CentralGlade",
	},
	{
		offset = { -95, 0, -285 },
		mobType = "ElderMossSlime",
		spawnCount = 1,
		escortMobType = "MossSlime",
		escortCount = 2,
		district = "CentralGlade",
	},
	{
		offset = { 85, 0, -280 },
		mobType = "RiverSnapper",
		spawnCount = 2,
		district = "CentralGlade",
	},
	{
		offset = { -265, 0, 170 },
		mobType = "BrambleBoar",
		spawnCount = 2,
		district = "CentralGlade",
	},
	{
		offset = { -65, 0, 235 },
		mobType = "MeadowWitch",
		spawnCount = 2,
		district = "CentralGlade",
	},
	{
		offset = { 75, 0, 195 },
		mobType = "TidecrestSnapper",
		spawnCount = 1,
		escortMobType = "RiverSnapper",
		escortCount = 1,
		district = "CentralGlade",
	},
	{
		offset = { 145, 0, -210 },
		mobType = "RiverSnapper",
		spawnCount = 2,
		district = "CentralGlade",
	},
	{
		offset = { 15, 0, -345 },
		mobType = "BrambleBoar",
		spawnCount = 2,
		district = "CentralGlade",
	},

	-- District 4: East Timber Watch & Sunlit Woods (10 ground pads -> 21 mobs + 2 perched)
	{ offset = { 315, 0, -455 }, mobType = "MossSlime", spawnCount = 2, district = "EastWatch" },
	{ offset = { 440, 0, -430 }, mobType = "MeadowWitch", spawnCount = 2, district = "EastWatch" },
	{
		offset = { 345, 0, -295 },
		mobType = "CovenArchWitch",
		spawnCount = 1,
		escortMobType = "MeadowWitch",
		escortCount = 1,
		district = "EastWatch",
	},
	{ offset = { 665, 0, -285 }, mobType = "MeadowWitch", spawnCount = 2, district = "EastWatch" },
	{ offset = { 365, 0, -110 }, mobType = "RiverSnapper", spawnCount = 2, district = "EastWatch" },
	{ offset = { 645, 0, -40 }, mobType = "BrambleBoar", spawnCount = 2, district = "EastWatch" },
	{
		offset = { 735, 0, 65 },
		mobType = "ThornbackAlpha",
		spawnCount = 1,
		escortMobType = "BrambleBoar",
		escortCount = 2,
		district = "EastWatch",
	},
	{ offset = { 600, 0, 145 }, mobType = "RuinSentinel", spawnCount = 2, district = "EastWatch" },
	{ offset = { 390, 0, 155 }, mobType = "RuinSentinel", spawnCount = 2, district = "EastWatch" },
	{ offset = { 695, 0, 255 }, mobType = "BrambleBoar", spawnCount = 2, district = "EastWatch" },

	-- District 5: Bramble Thicket & Mossy Ruins (10 ground pads -> 21 mobs)
	{
		offset = { -595, 0, 250 },
		mobType = "BrambleBoar",
		spawnCount = 2,
		district = "BrambleThicket",
	},
	{
		offset = { -310, 0, 230 },
		mobType = "MossSlime",
		spawnCount = 2,
		district = "BrambleThicket",
	},
	{
		offset = { -175, 0, 315 },
		mobType = "BrambleBoar",
		spawnCount = 2,
		district = "BrambleThicket",
	},
	{
		offset = { -565, 0, 385 },
		mobType = "ThornbackAlpha",
		spawnCount = 1,
		escortMobType = "BrambleBoar",
		escortCount = 2,
		district = "BrambleThicket",
	},
	{
		offset = { -445, 0, 505 },
		mobType = "RuinSentinel",
		spawnCount = 2,
		district = "BrambleThicket",
	},
	{
		offset = { -330, 0, 550 },
		mobType = "BrambleBoar",
		spawnCount = 2,
		district = "BrambleThicket",
	},
	{
		offset = { -225, 0, 405 },
		mobType = "AncientWarden",
		spawnCount = 1,
		escortMobType = "RuinSentinel",
		escortCount = 1,
		district = "BrambleThicket",
	},
	{
		offset = { -135, 0, 585 },
		mobType = "CovenArchWitch",
		spawnCount = 1,
		escortMobType = "MeadowWitch",
		escortCount = 1,
		district = "BrambleThicket",
	},
	{
		offset = { -50, 0, 470 },
		mobType = "BrambleBoar",
		spawnCount = 2,
		district = "BrambleThicket",
	},
	{
		offset = { -40, 0, 355 },
		mobType = "RiverSnapper",
		spawnCount = 2,
		district = "BrambleThicket",
	},

	-- District 6: South Shrine & Twin Watchtower (10 ground pads -> 21 mobs + 2 perched)
	{
		offset = { 485, 0, 285 },
		mobType = "ElderMossSlime",
		spawnCount = 1,
		escortMobType = "MossSlime",
		escortCount = 2,
		district = "SouthOverlook",
	},
	{
		offset = { 345, 0, 210 },
		mobType = "RiverSnapper",
		spawnCount = 2,
		district = "SouthOverlook",
	},
	{
		offset = { 265, 0, 295 },
		mobType = "TidecrestSnapper",
		spawnCount = 1,
		escortMobType = "RiverSnapper",
		escortCount = 1,
		district = "SouthOverlook",
	},
	{
		offset = { 585, 0, 315 },
		mobType = "BrambleBoar",
		spawnCount = 2,
		district = "SouthOverlook",
	},
	{
		offset = { 115, 0, 480 },
		mobType = "MeadowWitch",
		spawnCount = 2,
		district = "SouthOverlook",
	},
	{
		offset = { 240, 0, 465 },
		mobType = "CovenArchWitch",
		spawnCount = 1,
		escortMobType = "MeadowWitch",
		escortCount = 1,
		district = "SouthOverlook",
	},
	{
		offset = { 510, 0, 525 },
		mobType = "RiverSnapper",
		spawnCount = 2,
		district = "SouthOverlook",
	},
	{
		offset = { 140, 0, 625 },
		mobType = "RuinSentinel",
		spawnCount = 2,
		district = "SouthOverlook",
	},
	{
		offset = { -65, 0, 645 },
		mobType = "AncientWarden",
		spawnCount = 1,
		escortMobType = "RuinSentinel",
		escortCount = 1,
		district = "SouthOverlook",
	},
	{
		offset = { 315, 0, 645 },
		mobType = "MeadowWitch",
		spawnCount = 2,
		district = "SouthOverlook",
	},

	-- Perched Killable Watchtower Balcony Spawners (4 pads @ Y = 30.3 -> 4 mobs)
	{
		offset = { 510.6, 30.3, -248.8 },
		mobType = "CovenArchWitch",
		spawnCount = 1,
		isPerched = true,
		perchAxis = { -0.82, 0, -0.57 },
		district = "EastWatch",
	},
	{
		offset = { 519.4, 30.3, -261.2 },
		mobType = "MeadowWitch",
		spawnCount = 1,
		isPerched = true,
		perchAxis = { 0.82, 0, 0.57 },
		district = "EastWatch",
	},
	{
		offset = { 238.1, 30.3, 561.8 },
		mobType = "CovenArchWitch",
		spawnCount = 1,
		isPerched = true,
		perchAxis = { 0.42, 0, -0.91 },
		district = "SouthOverlook",
	},
	{
		offset = { 241.8, 30.3, 571.9 },
		mobType = "MeadowWitch",
		spawnCount = 1,
		isPerched = true,
		perchAxis = { 0.91, 0, 0.42 },
		district = "SouthOverlook",
	},
} :: { MobSpawnSpec }

WorldMapLayout.LANDMARK_OFFSETS = {
	{ -96, 0, 56 },
	{ 96, 0, 56 },
	{ 0, 0, -48 },
	{ -96, 0, -56 },
	{ 96, 0, -56 },
	{ 0, 0, -98 },
} :: { Vec3 }

WorldMapLayout.VAULT_PATROL_NODES = {
	{ -42, 0.5, -874 },
	{ 42, 0.5, -874 },
	{ 42, 0.5, -934 },
	{ -42, 0.5, -934 },
} :: { Vec3 }

WorldMapLayout.VAULT_COVER_PILLARS = {
	{ -26, 6, -884 },
	{ 26, 6, -884 },
	{ -26, 6, -922 },
	{ 26, 6, -922 },
} :: { Vec3 }

WorldMapLayout.BIOME_ORDER = {
	EmeraldMeadow = 1,
	FrostbiteCavern = 2,
	MoltenCaldera = 3,
}

local PEDESTAL_COLS = { -24, -14, -4, 6 }

local function makePedestalEntry(index: number, x: number, y: number, z: number): PedestalSpec
	local tier = if index <= 4 then 1 elseif index <= 8 then 2 elseif index <= 12 then 3 else 4
	return {
		index = index,
		name = string.format("Pedestal_%02d", index),
		tier = tier,
		basePos = { x, y + 1.1, z },
		cashPadPos = { x, y + 0.2, z - 5.5 },
		petAnchorPos = { x, y + 3.4, z },
		isBalcony = index >= 9 and index <= 12,
		isVip = index >= 13,
	}
end

local function buildPedestalSpecs(): { PedestalSpec }
	local out: { PedestalSpec } = {}
	for i, x in ipairs(PEDESTAL_COLS) do
		table.insert(out, makePedestalEntry(i, x, 0, -26))
	end
	for i, x in ipairs(PEDESTAL_COLS) do
		table.insert(out, makePedestalEntry(4 + i, x, 0, -5))
	end
	for i, x in ipairs(PEDESTAL_COLS) do
		table.insert(out, makePedestalEntry(8 + i, x, 11.25, 33))
	end
	table.insert(out, makePedestalEntry(13, -18, 0, 10))
	table.insert(out, makePedestalEntry(14, 4, 0, 10))
	return out
end

WorldMapLayout.PLOT_PEDESTALS = buildPedestalSpecs()

WorldMapLayout.TRAINING_RANGE_OFFSETS = {
	firingPad = { 25, 0.3, -24 },
	firingStance = { 25, 0.15, -19.5 },
	upgradeTerminal = { 15.5, 2.5, -24 },
	ownerSign = { 25, 11.5, 40 },
	staticTargets = {
		{ name = "Target_Static_1", pos = { 17, 3.2, 12 } },
		{ name = "Target_Static_2", pos = { 25, 3.2, 12 } },
		{ name = "Target_Static_3", pos = { 33, 3.2, 12 } },
	},
	movingGold = {
		name = "Target_MovingGold",
		pos = { 25, 3.6, 26 },
		railHalfLength = 10,
	},
}

function WorldMapLayout.polarPosition(radius: number, angleDeg: number, y: number?): Vec3
	local rad = math.rad(angleDeg)
	return {
		math.sin(rad) * radius,
		y or 0,
		-math.cos(rad) * radius,
	}
end

function WorldMapLayout.getPlotTransform(plotId: number): PlotTransformSpec
	if plotId < 1 or plotId > WorldMapLayout.PLOT_COUNT or math.floor(plotId) ~= plotId then
		error(`Invalid plotId: {plotId}`)
	end
	local angleDeg = (plotId - 1) * (360 / WorldMapLayout.PLOT_COUNT)
	return {
		plotId = plotId,
		plotName = string.format("Plot_%02d", plotId),
		center = WorldMapLayout.polarPosition(WorldMapLayout.PLOT_RING_RADIUS, angleDeg, 0),
		lookAt = { 0, 0, 0 },
		angleDeg = angleDeg,
	}
end

function WorldMapLayout.getAllPlots(): { PlotTransformSpec }
	local out: { PlotTransformSpec } = {}
	for i = 1, WorldMapLayout.PLOT_COUNT do
		table.insert(out, WorldMapLayout.getPlotTransform(i))
	end
	return out
end

function WorldMapLayout.getBiomeSpatial(biomeId: string): BiomeSpatialSpec
	local order = WorldMapLayout.BIOME_ORDER[biomeId]
	if not order then
		error(`Unknown biomeId: {biomeId}`)
	end
	local x = order * WorldMapLayout.BIOME_SPACING_X
	local pveCenter: Vec3 = if biomeId == "EmeraldMeadow"
		then {
			WorldMapLayout.EMERALD_MEADOW_PVE_CENTER[1],
			WorldMapLayout.EMERALD_MEADOW_PVE_CENTER[2],
			WorldMapLayout.EMERALD_MEADOW_PVE_CENTER[3],
		}
		else { x, 0, 0 }
	return {
		biomeId = biomeId,
		order = order,
		pveCenter = pveCenter,
		arenaCenter = { x, 0, WorldMapLayout.ARENA_OFFSET_Z },
	}
end

function WorldMapLayout.getBiomePveSize(biomeId: string): Vec3
	if biomeId == "EmeraldMeadow" then
		return {
			WorldMapLayout.EMERALD_MEADOW_PVE_SIZE[1],
			WorldMapLayout.EMERALD_MEADOW_PVE_SIZE[2],
			WorldMapLayout.EMERALD_MEADOW_PVE_SIZE[3],
		}
	end
	return {
		WorldMapLayout.BIOME_PVE_SIZE[1],
		WorldMapLayout.BIOME_PVE_SIZE[2],
		WorldMapLayout.BIOME_PVE_SIZE[3],
	}
end

function WorldMapLayout.getBiomeMobSpawns(biomeId: string): { MobSpawnSpec }
	if biomeId == "EmeraldMeadow" then
		return WorldMapLayout.EMERALD_MEADOW_MOB_SPAWNS
	end
	local out: { MobSpawnSpec } = {}
	for _, off in ipairs(WorldMapLayout.MOB_SPAWN_OFFSETS) do
		table.insert(out, { offset = off, mobType = nil })
	end
	return out
end

function WorldMapLayout.getBiomeArrivalAndReturnOffsets(biomeId: string): (Vec3, Vec3)
	if biomeId == "EmeraldMeadow" then
		return WorldMapLayout.EMERALD_MEADOW_ARRIVAL_OFFSET,
			WorldMapLayout.EMERALD_MEADOW_RETURN_OFFSET
	end
	return { 0, 0.25, 96 }, { 0, 5.2, 114 }
end

function WorldMapLayout.getRingWallTransforms(
	center: Vec3,
	radius: number,
	count: number,
	height: number,
	width: number,
	thickness: number
): { RingSegmentSpec }
	local out: { RingSegmentSpec } = {}
	local yPos = center[2] + height * 0.5
	for i = 1, count do
		local angle = (i - 1) * (360 / count)
		local off = WorldMapLayout.polarPosition(radius, angle, yPos)
		table.insert(out, {
			index = i,
			center = { center[1] + off[1], off[2], center[3] + off[3] },
			lookAt = { center[1], yPos, center[3] },
			size = { width, height, thickness },
		})
	end
	return out
end

function WorldMapLayout.getVaultBounds(): {
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
}
	local cx = WorldMapLayout.VAULT_CENTER[1]
	local cz = WorldMapLayout.VAULT_CENTER[3]
	local hx = WorldMapLayout.VAULT_FLOOR_SIZE[1] * 0.5
	local hz = WorldMapLayout.VAULT_FLOOR_SIZE[3] * 0.5
	return {
		minX = cx - hx,
		maxX = cx + hx,
		minZ = cz - hz,
		maxZ = cz + hz,
	}
end

function WorldMapLayout.isInsideVaultBounds(pos: Vec3): boolean
	local b = WorldMapLayout.getVaultBounds()
	return pos[1] >= b.minX and pos[1] <= b.maxX and pos[3] >= b.minZ and pos[3] <= b.maxZ
end

function WorldMapLayout.getPortalByBiomeId(biomeId: string): PortalSpec?
	for _, spec in ipairs(WorldMapLayout.PORTALS) do
		if spec.biomeId == biomeId then
			return spec
		end
	end
	return nil
end

function WorldMapLayout.getPedestalSpec(index: number): PedestalSpec?
	return WorldMapLayout.PLOT_PEDESTALS[index]
end

return WorldMapLayout
