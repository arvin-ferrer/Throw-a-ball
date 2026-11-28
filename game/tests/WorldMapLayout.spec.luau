--!strict
--[[
	WorldMapLayout.spec.luau
	Unit tests for pure Luau spatial layout of Workspace.BallBrawl_Map_v2:
	- Polar coordinate math & determinism
	- Hub portals & services ring non-overlap and lookups
	- 8 Personal Plots non-overlap, 14 pedestals & Training Range local bounds
	- 3 Biomes + BossPvP Arenas + Hub + VaultHeist AABB non-overlap
	- VaultHeist chamber bounds, tactical coordinate ordering & ring wall transforms
]]

local WorldMapLayout = require("../src/shared/Utils/WorldMapLayout")

local function run(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	assert(ok, `{name}: {err}`)
end

local function dist2D(a: WorldMapLayout.Vec3, b: WorldMapLayout.Vec3): number
	local dx = a[1] - b[1]
	local dz = a[3] - b[3]
	return math.sqrt(dx * dx + dz * dz)
end

local function assertNear(a: number, b: number, eps: number, label: string)
	assert(math.abs(a - b) <= eps, `{label}: expected {b}, got {a}`)
end

local function assertValidRgb(color: { number }, label: string)
	assert(#color == 3, `{label} rgb length 3`)
	for i = 1, 3 do
		assert(color[i] >= 0 and color[i] <= 255, `{label} channel {i} in [0,255]`)
	end
end

run("polarPosition cardinal angles, radius preservation and determinism", function()
	local n = WorldMapLayout.polarPosition(100, 0)
	local e = WorldMapLayout.polarPosition(100, 90, 5)
	local s = WorldMapLayout.polarPosition(100, 180)
	local w = WorldMapLayout.polarPosition(100, -90, -2)

	assertNear(n[1], 0, 1e-6, "N.x")
	assertNear(n[2], 0, 1e-6, "N.y")
	assertNear(n[3], -100, 1e-6, "N.z")
	assertNear(e[1], 100, 1e-6, "E.x")
	assertNear(e[2], 5, 1e-6, "E.y")
	assertNear(e[3], 0, 1e-6, "E.z")
	assertNear(s[1], 0, 1e-6, "S.x")
	assertNear(s[3], 100, 1e-6, "S.z")
	assertNear(w[1], -100, 1e-6, "W.x")
	assertNear(w[2], -2, 1e-6, "W.y")

	local a = WorldMapLayout.polarPosition(68, 37, 3)
	local b = WorldMapLayout.polarPosition(68, 37, 3)
	assert(a[1] == b[1] and a[2] == b[2] and a[3] == b[3], "deterministic output")
	assertNear(dist2D(a, { 0, 0, 0 }), 68, 1e-6, "exact radius")
end)

run("Hub portals and services are unique, well-separated and inside hub boundary", function()
	assert(#WorldMapLayout.PORTALS == 6, "6 portals (Vault + 3 MVP + 2 Coming Soon)")
	assert(#WorldMapLayout.SERVICES == 7, "7 hub services")

	local ringPositions: { { name: string, pos: WorldMapLayout.Vec3 } } = {}
	local seenNames: { [string]: boolean } = {}
	for _, p in ipairs(WorldMapLayout.PORTALS) do
		assert(not seenNames[p.name], `duplicate portal {p.name}`)
		seenNames[p.name] = true
		assertValidRgb(p.color, p.name)
		local pos = WorldMapLayout.polarPosition(WorldMapLayout.PORTAL_RING_RADIUS, p.angleDeg)
		table.insert(ringPositions, { name = p.name, pos = pos })
	end
	local leaderboards = 0
	for _, s in ipairs(WorldMapLayout.SERVICES) do
		assert(not seenNames[s.name], `duplicate service {s.name}`)
		seenNames[s.name] = true
		assertValidRgb(s.color, s.name)
		if s.isLeaderboard then
			leaderboards += 1
		end
		local pos = WorldMapLayout.polarPosition(WorldMapLayout.SERVICE_RING_RADIUS, s.angleDeg)
		table.insert(ringPositions, { name = s.name, pos = pos })
	end
	assert(leaderboards == 1, "exactly 1 leaderboard service")

	for i = 1, #ringPositions do
		assert(
			dist2D(ringPositions[i].pos, { 0, 0, 0 }) < WorldMapLayout.HUB_BOUNDARY_RADIUS,
			`{ringPositions[i].name} inside hub`
		)
		for j = i + 1, #ringPositions do
			local d = dist2D(ringPositions[i].pos, ringPositions[j].pos)
			assert(d > 25, `overlap between {ringPositions[i].name} and {ringPositions[j].name}`)
		end
	end

	local vaultPortal = WorldMapLayout.getPortalByBiomeId("VaultHeist")
	assert(vaultPortal ~= nil and vaultPortal.enabled, "VaultHeist portal enabled")
	local stormPortal = WorldMapLayout.getPortalByBiomeId("StormRuins")
	assert(stormPortal ~= nil and not stormPortal.enabled, "StormRuins coming soon")
	assert(WorldMapLayout.getPortalByBiomeId("NonExistent") == nil, "unknown portal nil")
end)

run(
	"8 Personal Plots are non-overlapping and sit cleanly between service ring and hub wall",
	function()
		local plots = WorldMapLayout.getAllPlots()
		assert(#plots == WorldMapLayout.PLOT_COUNT and #plots == 8, "8 personal plots")

		local halfW = WorldMapLayout.PLOT_SIZE[1] * 0.5
		local halfD = WorldMapLayout.PLOT_SIZE[3] * 0.5
		assert(
			WorldMapLayout.PLOT_RING_RADIUS - halfD > WorldMapLayout.PORTAL_RING_RADIUS,
			"clears inner"
		)
		assert(
			WorldMapLayout.PLOT_RING_RADIUS + halfD < WorldMapLayout.HUB_BOUNDARY_RADIUS,
			"inside wall"
		)

		for i, plot in ipairs(plots) do
			assert(
				plot.plotId == i and plot.plotName == string.format("Plot_%02d", i),
				"plot naming"
			)
			assertNear(
				dist2D(plot.center, { 0, 0, 0 }),
				WorldMapLayout.PLOT_RING_RADIUS,
				1e-6,
				"ring r"
			)
			assert(
				plot.lookAt[1] == 0 and plot.lookAt[2] == 0 and plot.lookAt[3] == 0,
				"faces hub center"
			)
			for j = i + 1, #plots do
				local sep = dist2D(plot.center, plots[j].center)
				assert(sep > halfW * 2, `Plot_{i} and Plot_{j} non-overlapping`)
			end
		end

		for _, badId in ipairs({ 0, -1, 9, 1.5, 0 / 0 }) do
			local ok = pcall(function()
				WorldMapLayout.getPlotTransform(badId)
			end)
			assert(not ok, `invalid plotId {badId} must error`)
		end
	end
)

run("14 Plot Pedestals are valid, non-overlapping and inside plot bounds", function()
	local halfW = WorldMapLayout.PLOT_SIZE[1] * 0.5
	local halfD = WorldMapLayout.PLOT_SIZE[3] * 0.5
	assert(#WorldMapLayout.PLOT_PEDESTALS == WorldMapLayout.PEDESTALS_PER_PLOT, "14 pedestals")
	assert(WorldMapLayout.getPedestalSpec(0) == nil and WorldMapLayout.getPedestalSpec(15) == nil)

	for i, ped in ipairs(WorldMapLayout.PLOT_PEDESTALS) do
		assert(ped.index == i and ped.name == string.format("Pedestal_%02d", i), "pedestal name")
		assert(WorldMapLayout.getPedestalSpec(i) == ped, "getPedestalSpec lookup")
		assert(ped.isBalcony == (i >= 9 and i <= 12), "balcony indices 9..12")
		assert(ped.isVip == (i >= 13), "VIP indices 13..14")
		if ped.isBalcony then
			assert(ped.basePos[2] > 10, "balcony elevated")
		end
		for _, pt in ipairs({ ped.basePos, ped.cashPadPos, ped.petAnchorPos }) do
			assert(math.abs(pt[1]) <= halfW and math.abs(pt[3]) <= halfD, `{ped.name} inside plot`)
		end
		for j = i + 1, #WorldMapLayout.PLOT_PEDESTALS do
			local other = WorldMapLayout.PLOT_PEDESTALS[j]
			if ped.isBalcony == other.isBalcony then
				assert(dist2D(ped.basePos, other.basePos) >= 8, `{ped.name} vs {other.name} spaced`)
			end
		end
	end
end)

run("Training Range offsets fit inside plot and stay separated from pedestals", function()
	local halfW = WorldMapLayout.PLOT_SIZE[1] * 0.5
	local halfD = WorldMapLayout.PLOT_SIZE[3] * 0.5
	local maxPedX = -math.huge
	for _, ped in ipairs(WorldMapLayout.PLOT_PEDESTALS) do
		maxPedX = math.max(maxPedX, ped.basePos[1])
	end

	local tr = WorldMapLayout.TRAINING_RANGE_OFFSETS
	local railHalf = tr.movingGold.railHalfLength
	local mg = tr.movingGold.pos
	local trPts: { WorldMapLayout.Vec3 } = {
		tr.firingPad,
		tr.firingStance,
		tr.upgradeTerminal,
		tr.ownerSign,
		{ mg[1] - railHalf, mg[2], mg[3] },
		{ mg[1] + railHalf, mg[2], mg[3] },
	}
	for _, st in ipairs(tr.staticTargets) do
		table.insert(trPts, st.pos)
	end
	for _, pt in ipairs(trPts) do
		assert(math.abs(pt[1]) <= halfW and math.abs(pt[3]) <= halfD, "training range inside plot")
		assert(pt[1] > maxPedX + 5, "training range separated from pedestals")
	end
end)

run("Hub, Vault, Biomes and Boss Arenas have zero AABB overlap", function()
	local boxes: { { name: string, minX: number, maxX: number, minZ: number, maxZ: number } } = {}
	local function addBox(name: string, cx: number, cz: number, hx: number, hz: number)
		table.insert(
			boxes,
			{ name = name, minX = cx - hx, maxX = cx + hx, minZ = cz - hz, maxZ = cz + hz }
		)
	end
	addBox(
		"Hub",
		0,
		0,
		WorldMapLayout.HUB_FLOOR_SIZE[1] * 0.5,
		WorldMapLayout.HUB_FLOOR_SIZE[3] * 0.5
	)
	local vb = WorldMapLayout.getVaultBounds()
	table.insert(
		boxes,
		{ name = "Vault", minX = vb.minX, maxX = vb.maxX, minZ = vb.minZ, maxZ = vb.maxZ }
	)

	local arenaHalf = WorldMapLayout.ARENA_FLOOR_DIAMETER * 0.5
	for _, biomeId in ipairs({ "EmeraldMeadow", "FrostbiteCavern", "MoltenCaldera" }) do
		local sp = WorldMapLayout.getBiomeSpatial(biomeId)
		local pveSz = WorldMapLayout.getBiomePveSize(biomeId)
		addBox(`{biomeId}_PvE`, sp.pveCenter[1], sp.pveCenter[3], pveSz[1] * 0.5, pveSz[3] * 0.5)
		addBox(`{biomeId}_Arena`, sp.arenaCenter[1], sp.arenaCenter[3], arenaHalf, arenaHalf)
	end
	for i = 1, #boxes do
		for j = i + 1, #boxes do
			local a, b = boxes[i], boxes[j]
			local overlap = a.minX <= b.maxX
				and a.maxX >= b.minX
				and a.minZ <= b.maxZ
				and a.maxZ >= b.minZ
			assert(not overlap, `zone overlap: {a.name} vs {b.name}`)
		end
	end
end)

run("Emerald Meadow 10x placement, future-proof clearances and 56 spawner integrity", function()
	local em = WorldMapLayout.getBiomeSpatial("EmeraldMeadow")
	assert(
		em.pveCenter[1] == 2000 and em.pveCenter[2] == 0 and em.pveCenter[3] == -3500,
		"EmeraldMeadow moved to (2000, 0, -3500)"
	)
	assert(
		em.arenaCenter[1] == 2000 and em.arenaCenter[2] == 0 and em.arenaCenter[3] == 1200,
		"EmeraldMeadow BossPvPArena stays locked at (2000, 0, 1200)"
	)

	local emSize = WorldMapLayout.getBiomePveSize("EmeraldMeadow")
	local areaApprox = emSize[1] * emSize[3]
	assert(areaApprox >= 2000000, `EmeraldMeadow 10x footprint area ({areaApprox}) >= 2,000,000`)

	-- Verify >= 1,500 stud clearance from Hub, Vault, BossPvPArena, current Frostbite, and reserved 10x slots
	local rimHX = WorldMapLayout.EMERALD_MEADOW_CLIFF_RIM_SIZE[1] * 0.5
	local rimHZ = WorldMapLayout.EMERALD_MEADOW_CLIFF_RIM_SIZE[3] * 0.5
	local emMinX, emMaxX = em.pveCenter[1] - rimHX, em.pveCenter[1] + rimHX
	local emMinZ, emMaxZ = em.pveCenter[3] - rimHZ, em.pveCenter[3] + rimHZ

	local function boxGap(minX: number, maxX: number, minZ: number, maxZ: number): number
		local dx = math.max(0, math.max(minX - emMaxX, emMinX - maxX))
		local dz = math.max(0, math.max(minZ - emMaxZ, emMinZ - maxZ))
		return math.sqrt(dx * dx + dz * dz)
	end

	assert(boxGap(-380, 380, -380, 380) >= 1500, "Hub clearance >= 1500 studs")
	assert(boxGap(-60, 60, -960, -840) >= 1500, "VaultHeist clearance >= 1500 studs")
	assert(boxGap(1875, 2125, 1075, 1325) >= 3500, "BossPvPArena clearance >= 3500 studs")
	assert(boxGap(3740, 4260, -260, 260) >= 1500, "Current Frostbite clearance >= 1500 studs")
	assert(
		boxGap(5500 - rimHX, 5500 + rimHX, -3500 - rimHZ, -3500 + rimHZ) >= 1500,
		"Future 10x Frostbite slot clearance >= 1500 studs"
	)

	-- Validate 56 Emerald Meadow spawners
	local emSpawns = WorldMapLayout.getBiomeMobSpawns("EmeraldMeadow")
	assert(#emSpawns == 56, `expected 56 Emerald Meadow spawners, got {#emSpawns}`)
	local slimeCount, boarCount = 0, 0
	local arrival = WorldMapLayout.EMERALD_MEADOW_ARRIVAL_OFFSET
	for i, sp in ipairs(emSpawns) do
		if sp.mobType == "MossSlime" then
			slimeCount += 1
		elseif sp.mobType == "BrambleBoar" then
			boarCount += 1
		else
			error(`unexpected mobType: {sp.mobType}`)
		end
		assert(
			math.abs(sp.offset[1]) <= emSize[1] * 0.5 and math.abs(sp.offset[3]) <= emSize[3] * 0.5,
			`spawner {i} inside valley`
		)
		assert(dist2D(sp.offset, arrival) >= 80, `spawner {i} clear of ArrivalPad`)
		for j = i + 1, #emSpawns do
			assert(dist2D(sp.offset, emSpawns[j].offset) >= 50, `spawner {i} vs {j} spacing >= 50`)
		end
	end
	assert(slimeCount == 28 and boarCount == 28, "balanced 28 MossSlime + 28 BrambleBoar")
	assert(
		#WorldMapLayout.getBiomeMobSpawns("FrostbiteCavern") == WorldMapLayout.MOB_SPAWNS_PER_BIOME,
		"FrostbiteCavern retains default 8 spawns"
	)
end)

run("Biome lookup errors on unknown ID and mob/landmark offsets stay inside rim", function()
	local okBadBiome = pcall(function()
		WorldMapLayout.getBiomeSpatial("UnknownBiome")
	end)
	assert(not okBadBiome, "unknown biome errors")
	assert(#WorldMapLayout.MOB_SPAWN_OFFSETS == WorldMapLayout.MOB_SPAWNS_PER_BIOME)
	for _, off in ipairs(WorldMapLayout.MOB_SPAWN_OFFSETS) do
		assert(dist2D(off, { 0, 0, 0 }) < WorldMapLayout.BIOME_RIM_RADIUS, "mob spawn inside rim")
	end
	for _, off in ipairs(WorldMapLayout.LANDMARK_OFFSETS) do
		assert(dist2D(off, { 0, 0, 0 }) < WorldMapLayout.BIOME_RIM_RADIUS, "landmark inside rim")
	end
end)

run("Vault bounds and tactical coordinate ordering", function()
	local vb = WorldMapLayout.getVaultBounds()
	assert(vb.minX == -60 and vb.maxX == 60 and vb.minZ == -960 and vb.maxZ == -840, "vault AABB")
	assert(WorldMapLayout.isInsideVaultBounds({ -60, 0, -960 }), "min corner inside")
	assert(WorldMapLayout.isInsideVaultBounds({ 60, 5, -840 }), "max corner inside")
	assert(not WorldMapLayout.isInsideVaultBounds({ 60.1, 0, -900 }), "outside maxX")
	assert(not WorldMapLayout.isInsideVaultBounds({ 0, 0, -960.1 }), "outside minZ")

	local vaultPoints: { WorldMapLayout.Vec3 } = {
		WorldMapLayout.VAULT_SPAWN_POS,
		WorldMapLayout.VAULT_EXTRACTION_POS,
		WorldMapLayout.VAULT_BOSS_SPAWN_POS,
		WorldMapLayout.VAULT_EGG_PEDESTAL_POS,
		WorldMapLayout.VAULT_LASER_GATE_POS,
	}
	for _, node in ipairs(WorldMapLayout.VAULT_PATROL_NODES) do
		table.insert(vaultPoints, node)
	end
	for _, pillar in ipairs(WorldMapLayout.VAULT_COVER_PILLARS) do
		table.insert(vaultPoints, pillar)
	end
	for _, pt in ipairs(vaultPoints) do
		assert(WorldMapLayout.isInsideVaultBounds(pt), "vault point inside bounds")
	end
	assert(
		WorldMapLayout.VAULT_SPAWN_POS[3] > WorldMapLayout.VAULT_BOSS_SPAWN_POS[3],
		"spawn south"
	)
	assert(
		WorldMapLayout.VAULT_BOSS_SPAWN_POS[3] > WorldMapLayout.VAULT_LASER_GATE_POS[3],
		"boss mid"
	)
	assert(
		WorldMapLayout.VAULT_LASER_GATE_POS[3] > WorldMapLayout.VAULT_EGG_PEDESTAL_POS[3],
		"laser"
	)
end)

run("Ring wall transform geometry preserves radius, height and center facing", function()
	local walls = WorldMapLayout.getRingWallTransforms({ 100, 10, -200 }, 50, 8, 12, 20, 4)
	assert(#walls == 8, "8 ring segments")
	for i, seg in ipairs(walls) do
		assert(seg.index == i, "sequential index")
		assertNear(dist2D(seg.center, { 100, 0, -200 }), 50, 1e-6, "segment radius")
		assertNear(seg.center[2], 16, 1e-6, "segment y = centerY + height/2")
		assert(
			seg.lookAt[1] == 100 and seg.lookAt[2] == 16 and seg.lookAt[3] == -200,
			"faces center"
		)
		assert(seg.size[1] == 20 and seg.size[2] == 12 and seg.size[3] == 4, "exact size")
	end
end)

print("PASS: WorldMapLayout.spec.luau")
