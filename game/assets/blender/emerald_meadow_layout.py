"""Canonical spatial layout for Emerald Meadow 10x Expansion (Gate 2 & Gate 3).

Coordinate Convention (Roblox Local Space relative to WORLD_CENTER):
- WORLD_CENTER = (2000.0, 0.0, -3500.0)
- Local (lx, lz): +X = East, -Z = North, +Z = South.
- Playable interior: rounded organic valley ~1,720 (E-W) x 1,580 (N-S) studs
  (~2,134,000 sq studs = 10.0x the live 520-stud circular meadow).
- Blender Top-Down Mapping: (bx, by, bz) = (lx, -lz, ly) so North is +Y (up) and East is +X (right).
"""

from __future__ import annotations

import math
import random
from dataclasses import dataclass

WORLD_CENTER = (2000.0, 0.0, -3500.0)
OLD_MEADOW_CENTER = (2000.0, 0.0, 0.0)
OLD_MEADOW_RADIUS = 260.0  # Live Studio PvEGround diameter = 520 studs (~212,372 sq studs)

BOSS_ARENA_CENTER = (2000.0, 0.0, 1200.0)
BOSS_ARENA_RADIUS = 125.0  # Live Studio BossPvPArena AABB 250x250 (LOCKED UNTOUCHED)

VALLEY_RX = 860.0  # E-W semi-axis (1,720 studs)
VALLEY_RZ = 790.0  # N-S semi-axis (1,580 studs)
CLIFF_RING_OFFSET = 38.0  # Outer cliff rim sits ~38 studs outside playable basin

RIVER_BED_Y = -1.8
RIVER_WATER_Y = -0.4
RIVER_HALF_WIDTH = 30.0  # 60 studs wide shallow wadeable river (1.4 studs deep)

ARRIVAL_PAD_LOCAL = (0.0, -675.0)
RETURN_PORTAL_LOCAL = (0.0, -718.0)

RIVER_CONTROL_POINTS: list[tuple[float, float]] = [
    (-815.0, -375.0),
    (-625.0, -295.0),
    (-430.0, -195.0),
    (-225.0, -90.0),
    (-35.0, -145.0),
    (185.0, -75.0),
    (255.0, 130.0),
    (125.0, 325.0),
    (365.0, 425.0),
    (610.0, 445.0),
    (810.0, 385.0),
]


@dataclass(frozen=True)
class BuildingSpec:
    name: str
    kind: str  # CottageA, Watermill, Watchtower, RuinArch, RuinPillar, ReturnPortal, Shrine
    lx: float
    lz: float
    yaw_deg: float  # Rotation around Y (0 = facing +Z South)
    footprint_w: float
    footprint_d: float
    height: float
    district: str


@dataclass(frozen=True)
class BridgeSpec:
    name: str
    kind: str  # StoneBridge, WoodBridge
    lx: float
    lz: float
    yaw_deg: float  # Aligned perpendicular to river tangent
    width: float
    length: float
    crown_y: float


@dataclass(frozen=True)
class SpawnerSpec:
    index: int
    name: str
    mob_type: str  # MossSlime | BrambleBoar
    lx: float
    lz: float
    district: str


@dataclass(frozen=True)
class TreeSpec:
    index: int
    species: str  # Oak | Pine | Birch | ElderOak
    lx: float
    lz: float
    scale: float
    yaw_deg: float


def valley_boundary_radius(angle_rad: float) -> tuple[float, float]:
    """Return organic valley boundary point (lx, lz) for polar angle `angle_rad`."""
    undul = 1.0 + 0.032 * math.cos(3.0 * angle_rad) - 0.022 * math.sin(5.0 * angle_rad)
    return (VALLEY_RX * undul * math.cos(angle_rad), VALLEY_RZ * undul * math.sin(angle_rad))


def valley_polygon(num_pts: int = 96, inset: float = 0.0) -> list[tuple[float, float]]:
    """Return closed-loop polygon of the organic valley boundary."""
    pts: list[tuple[float, float]] = []
    for i in range(num_pts):
        ang = 2.0 * math.pi * i / num_pts
        x, z = valley_boundary_radius(ang)
        if inset != 0.0:
            mag = math.hypot(x, z)
            scale = max(0.1, (mag - inset) / mag)
            x *= scale
            z *= scale
        pts.append((x, z))
    return pts


def valley_area_sq_studs(num_pts: int = 360) -> float:
    """Compute exact polygon area of the playable basin via shoelace formula."""
    pts = valley_polygon(num_pts)
    area = 0.0
    for i in range(len(pts)):
        x1, z1 = pts[i]
        x2, z2 = pts[(i + 1) % len(pts)]
        area += x1 * z2 - x2 * z1
    return abs(area) * 0.5


def is_inside_valley(lx: float, lz: float, margin: float = 0.0) -> bool:
    """Return True if (lx, lz) lies inside the playable valley with `margin` clearance."""
    ang = math.atan2(lz, lx)
    bx, bz = valley_boundary_radius(ang)
    max_r = math.hypot(bx, bz) - margin
    return math.hypot(lx, lz) <= max_r


def _catmull_rom(
    p0: tuple[float, float],
    p1: tuple[float, float],
    p2: tuple[float, float],
    p3: tuple[float, float],
    t: float,
) -> tuple[float, float]:
    t2 = t * t
    t3 = t2 * t
    x = 0.5 * (
        (2.0 * p1[0])
        + (-p0[0] + p2[0]) * t
        + (2.0 * p0[0] - 5.0 * p1[0] + 4.0 * p2[0] - p3[0]) * t2
        + (-p0[0] + 3.0 * p1[0] - 3.0 * p2[0] + p3[0]) * t3
    )
    z = 0.5 * (
        (2.0 * p1[1])
        + (-p0[1] + p2[1]) * t
        + (2.0 * p0[1] - 5.0 * p1[1] + 4.0 * p2[1] - p3[1]) * t2
        + (-p0[1] + 3.0 * p1[1] - 3.0 * p2[1] + p3[1]) * t3
    )
    return (x, z)


def sample_river_spline(samples_per_seg: int = 12) -> list[tuple[float, float]]:
    """Return dense smooth polyline points along the winding shallow river."""
    ctrl = RIVER_CONTROL_POINTS
    padded = [ctrl[0], *ctrl, ctrl[-1]]
    pts: list[tuple[float, float]] = []
    for i in range(len(ctrl) - 1):
        for s in range(samples_per_seg):
            t = s / samples_per_seg
            pts.append(_catmull_rom(padded[i], padded[i + 1], padded[i + 2], padded[i + 3], t))
    pts.append(ctrl[-1])
    return pts


def river_length_studs(pts: list[tuple[float, float]] | None = None) -> float:
    pts = pts or sample_river_spline()
    return sum(math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]) for i in range(len(pts) - 1))


def distance_to_polyline(lx: float, lz: float, poly: list[tuple[float, float]]) -> float:
    """Minimum Euclidean distance from point (lx, lz) to a 2D polyline."""
    best = float("inf")
    for i in range(len(poly) - 1):
        ax, az = poly[i]
        bx, bz = poly[i + 1]
        dx, dz = bx - ax, bz - az
        len_sq = dx * dx + dz * dz
        if len_sq < 1e-9:
            d = math.hypot(lx - ax, lz - az)
        else:
            t = max(0.0, min(1.0, ((lx - ax) * dx + (lz - az) * dz) / len_sq))
            px, pz = ax + t * dx, az + t * dz
            d = math.hypot(lx - px, lz - pz)
        if d < best:
            best = d
    return best


def _river_point_and_normal_yaw(river_pts: list[tuple[float, float]], target_x: float, target_z: float) -> tuple[float, float, float]:
    """Find nearest river spline sample to (target_x, target_z) and perpendicular bridge yaw."""
    best_idx = 0
    best_d = float("inf")
    for i, (rx, rz) in enumerate(river_pts):
        d = math.hypot(rx - target_x, rz - target_z)
        if d < best_d:
            best_d = d
            best_idx = i
    i0 = max(0, best_idx - 1)
    i1 = min(len(river_pts) - 1, best_idx + 1)
    tx = river_pts[i1][0] - river_pts[i0][0]
    tz = river_pts[i1][1] - river_pts[i0][1]
    # Perpendicular across river (nx, nz) = (-tz, tx)
    nx, nz = -tz, tx
    yaw_deg = math.degrees(math.atan2(nx, nz))
    rx, rz = river_pts[best_idx]
    return rx, rz, yaw_deg


def build_bridges(river_pts: list[tuple[float, float]]) -> list[BridgeSpec]:
    specs = [
        ("StoneBridge_1_Mill", "StoneBridge", -430.0, -195.0, 22.0, 74.0, 3.2),
        ("WoodBridge_2_NorthConfluence", "WoodBridge", -170.0, -108.0, 16.0, 66.0, 2.4),
        ("WoodBridge_3_EastConfluence", "WoodBridge", 185.0, -75.0, 16.0, 66.0, 2.4),
        ("StoneBridge_4_SouthCrossing", "StoneBridge", 125.0, 325.0, 22.0, 74.0, 3.2),
    ]
    out: list[BridgeSpec] = []
    for name, kind, tx, tz, w, length, crown_y in specs:
        rx, rz, yaw = _river_point_and_normal_yaw(river_pts, tx, tz)
        out.append(BridgeSpec(name, kind, round(rx, 1), round(rz, 1), round(yaw, 1), w, length, crown_y))
    return out


def build_roads(bridges: list[BridgeSpec]) -> list[list[tuple[float, float]]]:
    """Primary cobblestone & packed-dirt paths linking Arrival Plaza, all 6 districts & 4 bridges."""
    b1, b2, b3, b4 = bridges
    return [
        # Spine North Arrival -> Crossroads -> West Hamlet -> Bridge #1 -> Bramble Thicket -> Bridge #4 -> South Shrine
        [
            (0.0, -695.0),
            (0.0, -560.0),
            (-230.0, -490.0),
            (-420.0, -340.0),
            (b1.lx, b1.lz),
            (-455.0, 35.0),
            (-340.0, 270.0),
            (-115.0, 365.0),
            (b4.lx, b4.lz),
            (295.0, 260.0),
            (310.0, 520.0),
            (55.0, 610.0),
        ],
        # Crossroads -> Bridge #2 -> Central Confluence Sun-Ring -> Bridge #3 -> East Timber Watch -> South Loop
        [
            (0.0, -560.0),
            (-115.0, -340.0),
            (b2.lx, b2.lz),
            (-15.0, 35.0),
            (110.0, 25.0),
            (b3.lx, b3.lz),
            (430.0, -195.0),
            (565.0, -45.0),
            (520.0, 195.0),
            (295.0, 260.0),
        ],
        # North-East shortcut Crossroads -> East Timber Watch
        [
            (0.0, -560.0),
            (265.0, -480.0),
            (470.0, -330.0),
            (430.0, -195.0),
        ],
        # Central Glade South spur -> Bridge #4
        [
            (-15.0, 35.0),
            (-10.0, 195.0),
            (b4.lx, b4.lz),
        ],
    ]


def build_buildings() -> list[BuildingSpec]:
    """All avatar-scaled architecture & ruin landmarks across the 6 districts."""
    return [
        # District 1: North Gate & Arrival Commons
        BuildingSpec("ReturnPortalArch", "ReturnPortal", 0.0, -718.0, 0.0, 24.0, 10.0, 22.0, "NorthGate"),
        BuildingSpec("Cottage_N1_Gatehouse", "CottageA", -82.0, -610.0, 22.0, 26.0, 20.0, 16.0, "NorthGate"),
        BuildingSpec("Cottage_N2_Outfitter", "CottageA", 86.0, -605.0, -24.0, 26.0, 20.0, 16.0, "NorthGate"),
        # District 2: Whispering Mill Hamlet (West)
        BuildingSpec("Watermill_W1", "Watermill", -495.0, -162.0, 62.0, 30.0, 22.0, 18.0, "WhisperingMill"),
        BuildingSpec("Cottage_W1_Baker", "CottageA", -575.0, -370.0, 35.0, 26.0, 20.0, 16.0, "WhisperingMill"),
        BuildingSpec("Cottage_W2_Miller", "CottageA", -445.0, -415.0, 10.0, 26.0, 20.0, 16.0, "WhisperingMill"),
        BuildingSpec("Cottage_W3_Riverside", "CottageA", -640.0, -135.0, 82.0, 26.0, 20.0, 16.0, "WhisperingMill"),
        # District 3: Emerald Confluence Glade (Center)
        BuildingSpec("SunRing_Arch_N", "RuinArch", -15.0, -12.0, 0.0, 22.0, 8.0, 18.0, "CentralGlade"),
        BuildingSpec("SunRing_Arch_S", "RuinArch", -15.0, 102.0, 180.0, 22.0, 8.0, 18.0, "CentralGlade"),
        BuildingSpec("SunRing_Pillar_1", "RuinPillar", -65.0, 18.0, 30.0, 6.0, 6.0, 16.0, "CentralGlade"),
        BuildingSpec("SunRing_Pillar_2", "RuinPillar", 35.0, 18.0, -30.0, 6.0, 6.0, 16.0, "CentralGlade"),
        BuildingSpec("SunRing_Pillar_3", "RuinPillar", -65.0, 74.0, 150.0, 6.0, 6.0, 15.0, "CentralGlade"),
        BuildingSpec("SunRing_Pillar_4", "RuinPillar", 35.0, 74.0, -150.0, 6.0, 6.0, 17.0, "CentralGlade"),
        # District 4: East Timber Watch & Sunlit Woods
        BuildingSpec("Watchtower_E1", "Watchtower", 515.0, -255.0, -35.0, 16.0, 16.0, 40.0, "EastWatch"),
        BuildingSpec("Cottage_E1_Ranger", "CottageA", 615.0, -165.0, -65.0, 26.0, 20.0, 16.0, "EastWatch"),
        BuildingSpec("Aqueduct_Arch_1", "RuinArch", 460.0, 35.0, 75.0, 22.0, 8.0, 18.0, "EastWatch"),
        BuildingSpec("Aqueduct_Arch_2", "RuinArch", 495.0, 110.0, 65.0, 22.0, 8.0, 18.0, "EastWatch"),
        # District 5: Bramble Thicket & Mossy Ruins (SW)
        BuildingSpec("Bramble_Arch_1", "RuinArch", -385.0, 315.0, 38.0, 22.0, 8.0, 18.0, "BrambleThicket"),
        BuildingSpec("Bramble_Arch_2", "RuinArch", -290.0, 435.0, -18.0, 22.0, 8.0, 18.0, "BrambleThicket"),
        BuildingSpec("Bramble_Pillar_1", "RuinPillar", -475.0, 240.0, 15.0, 6.0, 6.0, 18.0, "BrambleThicket"),
        BuildingSpec("Bramble_Pillar_2", "RuinPillar", -445.0, 415.0, 45.0, 6.0, 6.0, 14.0, "BrambleThicket"),
        BuildingSpec("Bramble_Pillar_3", "RuinPillar", -190.0, 495.0, -20.0, 6.0, 6.0, 19.0, "BrambleThicket"),
        # District 6: South Shrine & Twin Watchtower (SE/S)
        BuildingSpec("Watchtower_S2", "Watchtower", 245.0, 565.0, 155.0, 16.0, 16.0, 40.0, "SouthOverlook"),
        BuildingSpec("Mossback_Shrine_Overlook", "Shrine", 35.0, 645.0, 180.0, 34.0, 24.0, 24.0, "SouthOverlook"),
        BuildingSpec("Cottage_S1_Keeper", "CottageA", 385.0, 545.0, -145.0, 26.0, 20.0, 16.0, "SouthOverlook"),
    ]


def build_spawners(river_pts: list[tuple[float, float]], buildings: list[BuildingSpec]) -> list[SpawnerSpec]:
    """56 logically clustered mob spawners (28 MossSlime + 28 BrambleBoar) across 6 districts."""
    raw: list[tuple[str, str, float, float]] = [
        # District 1: North Gate & Arrival Commons (6 MossSlime — beginner welcome)
        ("NorthGate", "MossSlime", -185.0, -565.0),
        ("NorthGate", "MossSlime", -110.0, -475.0),
        ("NorthGate", "MossSlime", 105.0, -490.0),
        ("NorthGate", "MossSlime", 215.0, -545.0),
        ("NorthGate", "MossSlime", -20.0, -425.0),
        ("NorthGate", "MossSlime", 155.0, -395.0),
        # District 2: Whispering Mill Hamlet (7 MossSlime, 3 BrambleBoar)
        ("WhisperingMill", "MossSlime", -335.0, -475.0),
        ("WhisperingMill", "MossSlime", -520.0, -495.0),
        ("WhisperingMill", "MossSlime", -690.0, -255.0),
        ("WhisperingMill", "MossSlime", -310.0, -315.0),
        ("WhisperingMill", "MossSlime", -570.0, -25.0),
        ("WhisperingMill", "MossSlime", -715.0, -30.0),
        ("WhisperingMill", "MossSlime", -425.0, -25.0),
        ("WhisperingMill", "BrambleBoar", -675.0, 110.0),
        ("WhisperingMill", "BrambleBoar", -525.0, 130.0),
        ("WhisperingMill", "BrambleBoar", -360.0, 125.0),
        # District 3: Central Emerald Confluence Glade (5 MossSlime, 5 BrambleBoar)
        ("CentralGlade", "MossSlime", -220.0, 45.0),
        ("CentralGlade", "MossSlime", -145.0, 145.0),
        ("CentralGlade", "MossSlime", 125.0, 115.0),
        ("CentralGlade", "MossSlime", -95.0, -285.0),
        ("CentralGlade", "MossSlime", 85.0, -280.0),
        ("CentralGlade", "BrambleBoar", -265.0, 170.0),
        ("CentralGlade", "BrambleBoar", -65.0, 235.0),
        ("CentralGlade", "BrambleBoar", 75.0, 195.0),
        ("CentralGlade", "BrambleBoar", 145.0, -210.0),
        ("CentralGlade", "BrambleBoar", 15.0, -345.0),
        # District 4: East Timber Watch & Sunlit Woods (4 MossSlime, 6 BrambleBoar)
        ("EastWatch", "MossSlime", 315.0, -455.0),
        ("EastWatch", "MossSlime", 440.0, -430.0),
        ("EastWatch", "MossSlime", 345.0, -295.0),
        ("EastWatch", "MossSlime", 665.0, -285.0),
        ("EastWatch", "BrambleBoar", 365.0, -110.0),
        ("EastWatch", "BrambleBoar", 645.0, -40.0),
        ("EastWatch", "BrambleBoar", 735.0, 65.0),
        ("EastWatch", "BrambleBoar", 600.0, 145.0),
        ("EastWatch", "BrambleBoar", 390.0, 155.0),
        ("EastWatch", "BrambleBoar", 695.0, 255.0),
        # District 5: Bramble Thicket & Mossy Ruins (3 MossSlime, 7 BrambleBoar)
        ("BrambleThicket", "MossSlime", -595.0, 250.0),
        ("BrambleThicket", "MossSlime", -310.0, 230.0),
        ("BrambleThicket", "MossSlime", -175.0, 315.0),
        ("BrambleThicket", "BrambleBoar", -565.0, 385.0),
        ("BrambleThicket", "BrambleBoar", -445.0, 505.0),
        ("BrambleThicket", "BrambleBoar", -330.0, 550.0),
        ("BrambleThicket", "BrambleBoar", -225.0, 405.0),
        ("BrambleThicket", "BrambleBoar", -135.0, 585.0),
        ("BrambleThicket", "BrambleBoar", -50.0, 470.0),
        ("BrambleThicket", "BrambleBoar", -40.0, 355.0),
        # District 6: South Shrine & Twin Watchtower (3 MossSlime, 7 BrambleBoar)
        ("SouthOverlook", "MossSlime", 485.0, 285.0),
        ("SouthOverlook", "MossSlime", 345.0, 210.0),
        ("SouthOverlook", "MossSlime", 265.0, 295.0),
        ("SouthOverlook", "BrambleBoar", 585.0, 315.0),
        ("SouthOverlook", "BrambleBoar", 115.0, 480.0),
        ("SouthOverlook", "BrambleBoar", 240.0, 465.0),
        ("SouthOverlook", "BrambleBoar", 510.0, 525.0),
        ("SouthOverlook", "BrambleBoar", 140.0, 625.0),
        ("SouthOverlook", "BrambleBoar", -65.0, 645.0),
        ("SouthOverlook", "BrambleBoar", 315.0, 645.0),
    ]
    out: list[SpawnerSpec] = []
    for idx, (district, mob_type, lx, lz) in enumerate(raw, start=1):
        assert is_inside_valley(lx, lz, margin=65.0), f"Spawner {idx} outside valley: {(lx, lz)}"
        rd = distance_to_polyline(lx, lz, river_pts)
        assert rd >= RIVER_HALF_WIDTH + 14.0, f"Spawner {idx} too close to river ({rd:.1f} studs)"
        assert math.hypot(lx - ARRIVAL_PAD_LOCAL[0], lz - ARRIVAL_PAD_LOCAL[1]) >= 85.0, f"Spawner {idx} near arrival"
        for b in buildings:
            bd = math.hypot(lx - b.lx, lz - b.lz)
            min_clear = max(b.footprint_w, b.footprint_d) * 0.5 + 16.0
            assert bd >= min_clear, f"Spawner {idx} collides with {b.name} ({bd:.1f} < {min_clear:.1f})"
        out.append(SpawnerSpec(idx, f"MobSpawn_{idx:02d}", mob_type, lx, lz, district))
    for i in range(len(out)):
        for j in range(i + 1, len(out)):
            sep = math.hypot(out[i].lx - out[j].lx, out[i].lz - out[j].lz)
            assert sep >= 52.0, f"Spawners {out[i].name} & {out[j].name} too close ({sep:.1f})"
    return out


def build_trees(
    river_pts: list[tuple[float, float]],
    roads: list[list[tuple[float, float]]],
    buildings: list[BuildingSpec],
    spawners: list[SpawnerSpec],
    bridges: list[BridgeSpec],
) -> list[TreeSpec]:
    """Deterministic multi-species forest placement (~186 trees: 6 Elder Oaks, 45 Birches, 65 Pines, 70 Oaks)."""
    rng = random.Random(20261128)
    trees: list[TreeSpec] = []

    def is_clear(lx: float, lz: float, min_river: float, min_tree: float) -> bool:
        if not is_inside_valley(lx, lz, margin=36.0):
            return False
        if distance_to_polyline(lx, lz, river_pts) < min_river:
            return False
        if math.hypot(lx - ARRIVAL_PAD_LOCAL[0], lz - ARRIVAL_PAD_LOCAL[1]) < 62.0:
            return False
        if math.hypot(lx - RETURN_PORTAL_LOCAL[0], lz - RETURN_PORTAL_LOCAL[1]) < 48.0:
            return False
        for road in roads:
            if distance_to_polyline(lx, lz, road) < 26.0:
                return False
        for br in bridges:
            if math.hypot(lx - br.lx, lz - br.lz) < 52.0:
                return False
        for b in buildings:
            if math.hypot(lx - b.lx, lz - b.lz) < max(b.footprint_w, b.footprint_d) * 0.5 + 22.0:
                return False
        for sp in spawners:
            if math.hypot(lx - sp.lx, lz - sp.lz) < 28.0:
                return False
        for tr in trees:
            if math.hypot(lx - tr.lx, lz - tr.lz) < min_tree:
                return False
        return True

    # 1. 6 Hero Elder Oaks anchoring iconic landmarks (all verified clear of river, roads, buildings, spawners)
    elder_spots = [
        (45.0, -38.0, 1.12),     # Central Confluence Glade
        (-545.0, -95.0, 1.05),   # Whispering Mill South Bank Overlook (dry ground!)
        (-495.0, 325.0, 1.15),   # Bramble Thicket Ancient Heart
        (-210.0, 565.0, 1.08),   # SW Ruin Sanctuary
        (585.0, -335.0, 1.06),   # East Watch Hilltop
        (160.0, 680.0, 1.12),    # South Shrine Twin Sentinel
    ]
    for lx, lz, sc in elder_spots:
        assert distance_to_polyline(lx, lz, river_pts) >= RIVER_HALF_WIDTH + 18.0, f"ElderOak too close to river: {(lx, lz)}"
        trees.append(TreeSpec(len(trees) + 1, "ElderOak", lx, lz, sc, round(rng.uniform(0, 360), 1)))

    # 2. 45 River Birches hugging both banks of the winding shallow river
    attempts = 0
    birch_count = 0
    while birch_count < 45 and attempts < 4000:
        attempts += 1
        rx, rz = rng.choice(river_pts[4:-4])
        ang = rng.uniform(0.0, 2.0 * math.pi)
        dist = rng.uniform(RIVER_HALF_WIDTH + 16.0, RIVER_HALF_WIDTH + 54.0)
        lx = rx + math.cos(ang) * dist
        lz = rz + math.sin(ang) * dist
        if is_clear(lx, lz, RIVER_HALF_WIDTH + 14.0, 30.0):
            trees.append(TreeSpec(len(trees) + 1, "Birch", round(lx, 1), round(lz, 1), round(rng.uniform(0.88, 1.18), 2), round(rng.uniform(0, 360), 1)))
            birch_count += 1

    # 3. 65 Tall Valley Pines banking the outer valley slopes & perimeter cliff foothills
    attempts = 0
    pine_count = 0
    while pine_count < 65 and attempts < 5000:
        attempts += 1
        ang = rng.uniform(0.0, 2.0 * math.pi)
        bx, bz = valley_boundary_radius(ang)
        frac = rng.uniform(0.76, 0.94)
        lx, lz = bx * frac, bz * frac
        if is_clear(lx, lz, RIVER_HALF_WIDTH + 22.0, 34.0):
            trees.append(TreeSpec(len(trees) + 1, "Pine", round(lx, 1), round(lz, 1), round(rng.uniform(0.90, 1.24), 2), round(rng.uniform(0, 360), 1)))
            pine_count += 1

    # 4. 70 Hero Meadow Oaks distributed in natural groves across the interior meadow
    grove_centers = [
        (-280.0, -540.0),
        (275.0, -565.0),
        (-670.0, -345.0),
        (-625.0, 45.0),
        (-345.0, 40.0),
        (325.0, -335.0),
        (685.0, -110.0),
        (615.0, 225.0),
        (-530.0, 455.0),
        (-265.0, 505.0),
        (420.0, 585.0),
        (-85.0, 560.0),
        (170.0, 165.0),
        (-165.0, -245.0),
    ]
    attempts = 0
    oak_count = 0
    while oak_count < 70 and attempts < 6000:
        attempts += 1
        if rng.random() < 0.72:
            gx, gz = rng.choice(grove_centers)
            lx = gx + rng.gauss(0.0, 95.0)
            lz = gz + rng.gauss(0.0, 95.0)
        else:
            ang = rng.uniform(0.0, 2.0 * math.pi)
            r = math.sqrt(rng.uniform(0.05, 0.78))
            bx, bz = valley_boundary_radius(ang)
            lx, lz = bx * r, bz * r
        if is_clear(lx, lz, RIVER_HALF_WIDTH + 24.0, 36.0):
            trees.append(TreeSpec(len(trees) + 1, "Oak", round(lx, 1), round(lz, 1), round(rng.uniform(0.86, 1.22), 2), round(rng.uniform(0, 360), 1)))
            oak_count += 1

    return trees


def build_layout() -> dict:
    """Return the complete, validated Emerald Meadow 10x layout bundle."""
    river_pts = sample_river_spline(12)
    bridges = build_bridges(river_pts)
    roads = build_roads(bridges)
    buildings = build_buildings()
    spawners = build_spawners(river_pts, buildings)
    trees = build_trees(river_pts, roads, buildings, spawners, bridges)
    area = valley_area_sq_studs()
    old_area = math.pi * OLD_MEADOW_RADIUS * OLD_MEADOW_RADIUS
    return {
        "world_center": WORLD_CENTER,
        "valley_area": area,
        "old_area": old_area,
        "area_multiplier": area / old_area,
        "river_pts": river_pts,
        "river_length": river_length_studs(river_pts),
        "bridges": bridges,
        "roads": roads,
        "buildings": buildings,
        "spawners": spawners,
        "trees": trees,
    }


if __name__ == "__main__":
    data = build_layout()
    species_counts: dict[str, int] = {}
    for t in data["trees"]:
        species_counts[t.species] = species_counts.get(t.species, 0) + 1
    mob_counts: dict[str, int] = {}
    for s in data["spawners"]:
        mob_counts[s.mob_type] = mob_counts.get(s.mob_type, 0) + 1
    print(f"Playable Valley Area: {data['valley_area']:,.0f} sq studs ({data['area_multiplier']:.2f}x old {data['old_area']:,.0f})")
    print(f"Winding River Length: {data['river_length']:,.0f} studs ({len(data['bridges'])} bridges)")
    print(f"Buildings & Ruins:    {len(data['buildings'])}")
    print(f"Spawners ({len(data['spawners'])}):       {mob_counts}")
    print(f"Trees ({len(data['trees'])}):         {species_counts}")
