"""Game Pass icons, Badge icons, and Cosmetic QA renders for Issue #20."""

from __future__ import annotations

import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Vector

import _common as C
import _launch_helpers as H


def _add_stylized_crown(bm: bmesh.types.BMesh, center: tuple[float, float, float], mat_gold: int, mat_gem: int, scale: float = 1.0) -> None:
    """Append a low-poly golden VIP/Ascension crown onto `bm`."""
    cx, cy, cz = center
    b0 = set(bm.verts)
    C.add_closed_ring(bm, 1.0 * scale, 0.22 * scale, 0.48 * scale, mat_gold, (0, 0, 0), 12)
    bmesh.ops.translate(bm, vec=(cx, cy, cz), verts=[v for v in bm.verts if v not in b0])
    for i in range(5):
        ang = math.radians(i * 72.0 - 90.0)
        px, py = cx + 0.96 * scale * math.cos(ang), cy + 0.96 * scale * math.sin(ang)
        C.add_crystal_prism(bm, 0.24 * scale, 0.85 * scale, (px, py, cz + 0.56 * scale), mat_gold, sides=4, rot_deg=(0, 0, i * 72.0))
        C.add_faceted_icosphere(bm, 0.16 * scale, (px, py, cz + 0.96 * scale), mat_gem, subdivisions=1)


def _add_bullseye_prop(bm: bmesh.types.BMesh, center: tuple[float, float, float], mat_wood: int, mat_ring: int, mat_gold: int) -> None:
    """Append a stylized angled Training Range target disc + post."""
    cx, cy, cz = center
    C.add_faceted_box(bm, (0.38, 0.38, 2.2), (cx, cy + 0.25, cz - 1.4), mat_wood, bevel=0.06)
    for r, thick, m_idx, y_off in [(1.55, 0.34, mat_wood, 0.0), (1.15, 0.38, mat_ring, -0.06), (0.62, 0.42, mat_gold, -0.12)]:
        b0 = set(bm.verts)
        C.add_lathe_shell(bm, [(r, -thick * 0.5), (r, thick * 0.5), (0.04, thick * 0.5)], m_idx, segments=16, smooth=False)
        verts = [v for v in bm.verts if v not in b0]
        bmesh.ops.transform(bm, matrix=Euler((math.radians(90), 0, 0), "XYZ").to_matrix().to_4x4(), verts=verts)
        bmesh.ops.translate(bm, vec=(cx, cy + y_off, cz), verts=verts)


def _add_u_magnet_prop(bm: bmesh.types.BMesh, center: tuple[float, float, float], mat_red: int, mat_tip: int) -> None:
    """Append a chunky stylized low-poly horseshoe magnet."""
    cx, cy, cz = center
    rings: list[tuple[tuple[float, float, float], float, float, tuple[float, float, float]]] = []
    for i in range(13):
        ang = math.pi * i / 12.0
        px, pz = cx + 1.45 * math.cos(ang), cz + 1.55 * math.sin(ang)
        rings.append(((px, cy, pz), 0.42, 0.42, (0.0, -math.degrees(ang), 0.0)))
    C.add_lofted_tube(bm, rings, mat_red, sides=8, smooth=False)
    for sx in (-1.45, 1.45):
        C.add_faceted_box(bm, (0.78, 0.78, 1.15), (cx + sx, cy, cz - 0.58), mat_red, bevel=0.08)
        C.add_faceted_box(bm, (0.82, 0.82, 0.52), (cx + sx, cy, cz - 1.32), mat_tip, bevel=0.06)


def _setup_icon_scene(horizon: tuple[float, float, float], zenith: tuple[float, float, float], samples: int, res_scale: float) -> None:
    """Reset scene for a crisp 512x512 square Game Pass / Badge render."""
    C.clear_scene()
    size = max(64, int(512 * res_scale))
    H.setup_render_pipeline(size, size, samples, exposure=-0.18, bloom_threshold=1.50, bloom_strength=0.16)
    H.set_gradient_world(horizon, zenith, strength=0.58)
    H.add_area_light("IconKey", (-7.5, -12.0, 9.0), (0.0, 0.5, 2.8), 1650.0, (1.0, 0.95, 0.86), 8.0, 8.0)
    H.add_area_light("IconRim", (6.5, 10.5, 9.5), (0.0, 0.5, 2.8), 3000.0, (1.0, 0.78, 0.36), 9.0, 8.0)
    H.add_area_light("IconFill", (-9.0, 6.0, 6.5), (0.0, 0.5, 2.5), 1400.0, (0.34, 0.88, 1.0), 8.0, 8.0)


def render_pass_double_training(out_dir: Path, res_scale: float, samples: int) -> Path:
    """GamePass_DoubleTraining.png (512x512)."""
    _setup_icon_scene((0.12, 0.36, 0.16), (0.03, 0.08, 0.06), samples, res_scale)
    mats = [
        C.make_material("TWood", (0.52, 0.30, 0.14), roughness=0.72),
        C.make_material("TEmerald", (0.14, 0.92, 0.44), roughness=0.16, emission=(0.14, 0.92, 0.44), emission_strength=1.8),
        C.make_material("TGold", (1.0, 0.80, 0.18), roughness=0.22, metallic=0.35, emission=(1.0, 0.76, 0.14), emission_strength=0.45),
    ]
    bm = bmesh.new()
    _add_bullseye_prop(bm, (1.1, 2.4, 2.5), 0, 1, 2)
    for z_off in (4.65, 5.45):
        C.add_faceted_box(bm, (1.1, 0.28, 0.30), (0.68, 1.4, z_off), 2, bevel=0.05, rot_deg=(0, 32, 0))
        C.add_faceted_box(bm, (1.1, 0.28, 0.30), (1.52, 1.4, z_off), 2, bevel=0.05, rot_deg=(0, -32, 0))
    C.finalize_mesh("TrainingProps", bm, mats)
    H.place_asset(H.import_glb("TrainingPup.glb", "PassPup"), loc=(-1.75, -1.2, 0.2), rot_deg=(0, 0, -24), scale=0.96, ground_z=0.0)
    H.place_asset(H.import_glb("IronSphere.glb", "PassIron"), loc=(-0.1, -1.6, 2.15), rot_deg=(12, -20, 20), scale=1.35)
    H.build_energy_trail("DoubleTrainTrail", [(Vector((-3.4, -4.5, 0.9)), 0.06), (Vector((-1.8, -3.0, 1.5)), 0.14), (Vector((-0.3, -1.8, 2.05)), 0.22)], (1.0, 0.72, 0.16), (0.20, 0.94, 0.46), spark_seed=3)
    H.aim_camera("PassCam", (-0.6, -11.4, 3.0), (0.1, 0.6, 2.5), lens=38.0)
    return H.render_to_path(out_dir, "GamePass_DoubleTraining.png")


def render_pass_double_coins_exp(out_dir: Path, res_scale: float, samples: int) -> Path:
    """GamePass_DoubleCoinsExp.png (512x512)."""
    _setup_icon_scene((0.10, 0.28, 0.56), (0.02, 0.06, 0.18), samples, res_scale)
    mats = [
        C.make_material("PStone", (0.16, 0.20, 0.30), roughness=0.65),
        C.make_material("PGold", (1.0, 0.80, 0.18), roughness=0.22, metallic=0.45, emission=(1.0, 0.74, 0.12), emission_strength=0.35),
        C.make_material("PExp", (0.20, 0.92, 1.0), roughness=0.12, emission=(0.20, 0.92, 1.0), emission_strength=2.2),
    ]
    bm = bmesh.new()
    H.add_pedestal_mesh(bm, (0.0, 0.4, 0.0), 2.5, 0.9, 0, 1, 2)
    for pos, rot in [((-1.3, -1.2, 1.25), (68, 12, -18)), ((1.35, -1.1, 1.35), (72, -18, 22)), ((-0.5, -1.65, 1.15), (78, 8, 5)), ((0.6, -1.55, 1.55), (64, -12, 30)), ((0.0, -1.3, 2.25), (74, 24, -10))]:
        H.add_coin_mesh(bm, pos, 1, radius=0.66, half_thick=0.14, rot_deg=rot)
    for cpos, rot in [((-1.95, 0.2, 1.65), (14, -18, 10)), ((1.95, 0.2, 1.75), (-12, 16, -12)), ((0.0, 0.2, 4.9), (0, 0, 22))]:
        C.add_crystal_prism(bm, 0.44, 1.45, cpos, 2, sides=6, rot_deg=rot)
    C.finalize_mesh("CoinsExpProps", bm, mats)
    H.place_asset(H.import_glb("GolemHeart.glb", "PassGolem"), loc=(0.0, 0.4, 1.25), rot_deg=(0, 0, -10), scale=1.08, ground_z=1.25)
    H.add_point_light("CoinFill", (0.0, -4.5, 2.2), 180.0, (1.0, 0.92, 0.72), 1.4)
    H.aim_camera("PassCam", (0.0, -10.8, 3.6), (0.0, 0.4, 2.3), lens=38.0)
    return H.render_to_path(out_dir, "GamePass_DoubleCoinsExp.png")


def render_pass_autofire_range(out_dir: Path, res_scale: float, samples: int) -> Path:
    """GamePass_AutoFireRange.png (512x512)."""
    _setup_icon_scene((0.12, 0.10, 0.36), (0.02, 0.03, 0.12), samples, res_scale)
    mats = [
        C.make_material("RetCyan", (0.18, 0.94, 1.0), roughness=0.10, emission=(0.18, 0.94, 1.0), emission_strength=2.5),
        C.make_material("TargetGold", (1.0, 0.78, 0.16), roughness=0.14, emission=(1.0, 0.68, 0.10), emission_strength=1.8),
    ]
    bm = bmesh.new()
    C.add_faceted_icosphere(bm, 1.25, (1.1, 2.2, 3.0), 1, subdivisions=2)
    for r, th in [(1.95, 0.16), (2.75, 0.11)]:
        b0 = set(bm.verts)
        C.add_closed_ring(bm, r, th, 0.14, 0, (90, 0, 0), segments=24)
        bmesh.ops.translate(bm, vec=(1.1, 1.4, 3.0), verts=[v for v in bm.verts if v not in b0])
    C.finalize_mesh("ReticleTarget", bm, mats)
    H.place_asset(H.import_glb("NovaSphere.glb", "TurboNova"), loc=(-1.2, -1.8, 2.9), rot_deg=(18, -24, 24), scale=1.18)
    H.place_asset(H.import_glb("FrostOrb.glb", "TurboFrost"), loc=(-2.2, -0.4, 1.65), rot_deg=(-14, 20, -18), scale=1.05)
    H.build_energy_trail("TurboTrailA", [(Vector((-3.8, -4.4, 2.2)), 0.05), (Vector((-2.4, -3.1, 2.55)), 0.13), (Vector((-1.3, -1.9, 2.88)), 0.20)], (0.22, 0.94, 1.0), (0.10, 0.44, 1.0), spark_seed=4)
    H.build_energy_trail("TurboTrailB", [(Vector((-4.2, -3.0, 1.0)), 0.05), (Vector((-3.1, -1.7, 1.32)), 0.12), (Vector((-2.3, -0.5, 1.62)), 0.18)], (0.35, 0.98, 1.0), (0.18, 0.62, 1.0), spark_seed=9)
    H.aim_camera("PassCam", (-0.4, -10.8, 3.2), (0.0, 0.8, 2.5), lens=38.0, roll_deg=-4.0)
    return H.render_to_path(out_dir, "GamePass_AutoFireRange.png")


def render_pass_magnet_collect(out_dir: Path, res_scale: float, samples: int) -> Path:
    """GamePass_MagnetCollect.png (512x512)."""
    _setup_icon_scene((0.08, 0.34, 0.26), (0.02, 0.08, 0.12), samples, res_scale)
    mats = [
        C.make_material("MagRed", (0.90, 0.16, 0.20), roughness=0.28, metallic=0.2),
        C.make_material("MagTip", (0.92, 0.94, 0.98), roughness=0.22, metallic=0.88),
        C.make_material("MagPad", (0.02, 0.42, 0.14), roughness=0.22, emission=(0.06, 0.84, 0.28), emission_strength=1.2),
        C.make_material("MagGold", (1.0, 0.80, 0.18), roughness=0.22, metallic=0.45, emission=(1.0, 0.74, 0.12), emission_strength=0.35),
        C.make_material("MagGem", (0.78, 0.14, 0.98), roughness=0.12, emission=(0.78, 0.14, 0.98), emission_strength=1.8),
        C.make_material("MagEm", (0.08, 0.92, 0.38), roughness=0.12, emission=(0.08, 0.92, 0.38), emission_strength=1.6),
    ]
    bm = bmesh.new()
    _add_u_magnet_prop(bm, (0.0, 0.4, 4.35), 0, 1)
    H.add_cash_pad_and_loot(bm, (0.0, 0.4, 0.0), 2, 3, 5, 4, seed=5)
    for cx, cz, rot in [(-1.35, 2.15, (65, 20, -25)), (1.35, 2.25, (68, -22, 20)), (0.0, 2.45, (74, 0, 12))]:
        H.add_coin_mesh(bm, (cx, -0.35, cz), 3, radius=0.52, half_thick=0.11, rot_deg=rot)
    obj = C.finalize_mesh("MagnetProps", bm, mats)
    obj.rotation_euler = Euler((math.radians(-10), math.radians(14), 0.0), "XYZ")
    H.add_point_light("MagCoinFill", (0.0, -4.5, 2.2), 180.0, (1.0, 0.92, 0.72), 1.4)
    H.aim_camera("PassCam", (0.0, -10.8, 3.3), (0.0, 0.3, 2.5), lens=38.0)
    return H.render_to_path(out_dir, "GamePass_MagnetCollect.png")


def render_pass_extra_pedestals(out_dir: Path, res_scale: float, samples: int) -> Path:
    """GamePass_ExtraPedestals.png (512x512)."""
    _setup_icon_scene((0.26, 0.10, 0.40), (0.05, 0.02, 0.14), samples, res_scale)
    mats = [
        C.make_material("VipMarble", (0.95, 0.93, 0.89), roughness=0.24),
        C.make_material("VipGold", (0.98, 0.76, 0.18), roughness=0.18, metallic=0.94),
        C.make_material("VipGlow", (0.98, 0.78, 0.18), roughness=0.14, emission=(0.98, 0.78, 0.18), emission_strength=1.6),
        C.make_material("VipRuby", (1.0, 0.24, 0.46), roughness=0.12, emission=(1.0, 0.24, 0.46), emission_strength=2.0),
    ]
    bm = bmesh.new()
    H.add_pedestal_mesh(bm, (-2.05, 0.8, 0.0), 1.65, 1.05, 0, 1, 2)
    H.add_pedestal_mesh(bm, (2.05, 0.8, 0.0), 1.65, 1.05, 0, 1, 2)
    _add_stylized_crown(bm, (0.0, 0.4, 4.9), 1, 3, scale=1.05)
    C.finalize_mesh("VipPedestals", bm, mats)
    H.place_asset(H.import_glb("InfernoDrake.glb", "VipDrake"), loc=(-2.05, 0.8, 1.05), rot_deg=(0, 0, -22), scale=1.02, ground_z=1.05)
    H.place_asset(H.import_glb("CryoTitan.glb", "VipTitan"), loc=(2.05, 0.8, 1.25), rot_deg=(0, 0, 22), scale=0.98, ground_z=1.25)
    H.aim_camera("PassCam", (0.0, -11.4, 3.6), (0.0, 0.8, 2.8), lens=38.0)
    return H.render_to_path(out_dir, "GamePass_ExtraPedestals.png")


def render_badge_first_hatch(out_dir: Path, res_scale: float, samples: int) -> Path:
    """Badge_FirstHatch.png (512x512)."""
    _setup_icon_scene((0.12, 0.40, 0.24), (0.04, 0.10, 0.16), samples, res_scale)
    mats = [
        C.make_material("BStone", (0.18, 0.22, 0.26), roughness=0.72),
        C.make_material("BGold", (0.98, 0.78, 0.20), roughness=0.18, metallic=0.92),
        C.make_material("BGlow", (0.24, 0.96, 0.52), roughness=0.12, emission=(0.24, 0.96, 0.52), emission_strength=2.0),
    ]
    bm = bmesh.new()
    H.add_pedestal_mesh(bm, (0.0, 1.0, 0.0), 2.4, 0.85, 0, 1, 2)
    C.finalize_mesh("HatchDais", bm, mats)
    H.place_asset(H.import_glb("BossEgg_Meadow.glb", "BadgeMeadowEgg"), loc=(0.8, 1.4, 0.85), rot_deg=(4, -6, -18), scale=0.95, ground_z=0.85)
    H.place_asset(H.import_glb("TrainingPup.glb", "BadgePup"), loc=(-1.25, 0.0, 0.85), rot_deg=(0, 0, -24), scale=0.95, ground_z=0.85)
    H.build_energy_vortex("HatchVortex", (0.4, 1.2, 0.85), radius=2.6, height=4.5, col_a=(0.30, 0.98, 0.54), col_b=(1.0, 0.84, 0.22))
    H.aim_camera("BadgeCam", (0.0, -10.8, 3.4), (0.0, 0.8, 2.6), lens=38.0)
    return H.render_to_path(out_dir, "Badge_FirstHatch.png")


def render_badge_boss_slayer(out_dir: Path, res_scale: float, samples: int) -> Path:
    """Badge_BossSlayer.png (512x512)."""
    _setup_icon_scene((0.36, 0.09, 0.16), (0.06, 0.02, 0.12), samples, res_scale)
    pyraxis = H.import_glb("Pyraxis_RobloxRigged.glb", "BadgePyraxis")
    H.pose_rig_clean(pyraxis.armatures[0], {"Neck1": (-16, 0, -8), "Head": (-14, 0, -10), "Jaw": (-32, 0, 0)})
    H.boost_pyraxis_accents(pyraxis)
    H.place_asset(pyraxis, loc=(0.7, 4.8, 2.2), rot_deg=(12, -8, 152), scale=0.72)
    H.place_asset(H.import_glb("NovaSphere.glb", "SlayerBall"), loc=(-1.75, -3.4, 1.9), rot_deg=(20, -18, 28), scale=1.22)
    H.build_energy_trail("SlayerTrail", [(Vector((-4.6, -6.8, 0.4)), 0.05), (Vector((-3.2, -5.0, 1.1)), 0.14), (Vector((-1.9, -3.5, 1.82)), 0.22)], (0.14, 0.90, 1.0), (0.08, 0.42, 1.0), spark_seed=6)
    H.build_impact_burst("SlayerBurst", pos=(-0.4, -0.4, 2.6), aim_dir=(-0.5, -0.8, -0.1), core_col=(0.24, 0.94, 1.0), spark_col=(1.0, 0.42, 0.06), scale=0.72)
    H.add_point_light("SlayerBack", (0.6, 8.0, 5.5), 1400.0, (1.0, 0.36, 0.06), 2.2)
    H.aim_camera("BadgeCam", (-0.8, -12.6, 3.0), (0.0, 1.2, 3.1), lens=38.0, roll_deg=-3.0)
    return H.render_to_path(out_dir, "Badge_BossSlayer.png")


def render_badge_ascension(out_dir: Path, res_scale: float, samples: int) -> Path:
    """Badge_Ascension.png (512x512)."""
    _setup_icon_scene((0.34, 0.16, 0.42), (0.08, 0.03, 0.16), samples, res_scale)
    mats = [
        C.make_material("AscStone", (0.14, 0.12, 0.22), roughness=0.62),
        C.make_material("AscGold", (0.98, 0.78, 0.20), roughness=0.16, metallic=0.95),
        C.make_material("AscGlow", (1.0, 0.74, 0.16), roughness=0.12, emission=(1.0, 0.74, 0.16), emission_strength=2.0),
        C.make_material("AscGem", (1.0, 0.26, 0.76), roughness=0.10, emission=(1.0, 0.26, 0.76), emission_strength=2.2),
    ]
    bm = bmesh.new()
    H.add_pedestal_mesh(bm, (0.0, 0.8, 0.0), 2.1, 1.05, 0, 1, 2)
    _add_stylized_crown(bm, (0.0, 0.8, 4.9), 1, 3, scale=1.10)
    C.finalize_mesh("AscDais", bm, mats)
    H.place_asset(H.import_glb("InfernoDrake.glb", "AscDrake"), loc=(0.0, 0.8, 1.05), rot_deg=(0, 0, -14), scale=1.18, ground_z=1.05)
    H.build_energy_vortex("AscVortex", (0.0, 0.8, 1.0), radius=2.6, height=4.6, col_a=(1.0, 0.72, 0.16), col_b=(1.0, 0.30, 0.78))
    H.aim_camera("BadgeCam", (0.0, -10.8, 3.6), (0.0, 0.8, 2.9), lens=38.0)
    return H.render_to_path(out_dir, "Badge_Ascension.png")


def render_badge_codex_master(out_dir: Path, res_scale: float, samples: int) -> Path:
    """Badge_CodexMaster.png (512x512)."""
    _setup_icon_scene((0.08, 0.22, 0.44), (0.03, 0.03, 0.14), samples, res_scale)
    mats = [
        C.make_material("CDais", (0.10, 0.12, 0.20), roughness=0.68),
        C.make_material("CGold", (0.98, 0.76, 0.20), roughness=0.18, metallic=0.94),
        C.make_material("CCyan", (0.24, 0.92, 1.0), roughness=0.12, emission=(0.24, 0.92, 1.0), emission_strength=2.0),
    ]
    bm = bmesh.new()
    H.add_pedestal_mesh(bm, (0.0, 1.2, 0.0), 2.8, 0.95, 0, 1, 2)
    C.finalize_mesh("CodexDais", bm, mats)
    H.place_asset(H.import_glb("BossEgg_Molten_Overcharged.glb", "CodexEgg"), loc=(0.0, 1.4, 0.95), rot_deg=(0, 0, -16), scale=0.88, ground_z=0.95)
    H.place_asset(H.import_glb("ThornStag.glb", "CodexStag"), loc=(-1.95, 0.2, 0.95), rot_deg=(0, 0, -28), scale=0.78, ground_z=0.95)
    H.place_asset(H.import_glb("SnowFox.glb", "CodexFox"), loc=(1.95, 0.2, 0.95), rot_deg=(0, 0, 28), scale=0.88, ground_z=0.95)
    H.aim_camera("BadgeCam", (0.0, -11.4, 3.6), (0.0, 1.0, 2.7), lens=38.0)
    return H.render_to_path(out_dir, "Badge_CodexMaster.png")


def _setup_qa_scene(horizon: tuple[float, float, float], zenith: tuple[float, float, float], samples: int, res_scale: float) -> None:
    """Reset scene for a 960x540 16:9 cosmetic QA render."""
    C.clear_scene()
    H.setup_render_pipeline(max(128, int(960 * res_scale)), max(72, int(540 * res_scale)), samples, exposure=-0.24, bloom_threshold=1.50, bloom_strength=0.15)
    H.set_gradient_world(horizon, zenith, strength=0.45)


def render_qa_ball_trails(out_dir: Path, res_scale: float, samples: int) -> Path:
    """Cosmetic_BallTrails_QA.png (960x540): PrismTrail & CyberPulse trails."""
    _setup_qa_scene((0.10, 0.06, 0.20), (0.02, 0.02, 0.06), samples, res_scale)
    H.build_arena_stage("TrailQAStage", 18.0, (0.04, 0.045, 0.06), (0.12, 0.13, 0.16), (0.20, 0.86, 1.0), [(135, (0.96, 0.44, 0.72), 1.0), (45, (0.14, 0.84, 0.94), 1.0)])
    for cname, loc, yaw, acol, vcol, bfile, bloc, tpts, c0, c1 in [
        ("PrismThrower", (-5.5, -5.0, 0.0), 22.0, (0.16, 0.06, 0.14), (0.96, 0.44, 0.72), "NovaSphere.glb", (-3.2, 4.5, 3.1), [(Vector((-5.2, -3.5, 2.1)), 0.06), (Vector((-4.3, 0.5, 2.7)), 0.14), (Vector((-3.4, 4.1, 3.05)), 0.22)], (0.96, 0.44, 0.72), (0.72, 0.22, 0.88)),
        ("CyberThrower", (5.5, -5.0, 0.0), -22.0, (0.05, 0.12, 0.18), (0.14, 0.84, 0.94), "FrostOrb.glb", (3.2, 4.5, 3.1), [(Vector((5.2, -3.5, 2.1)), 0.06), (Vector((4.3, 0.5, 2.7)), 0.14), (Vector((3.4, 4.1, 3.05)), 0.22)], (0.14, 0.84, 0.94), (0.06, 0.46, 1.0)),
    ]:
        ch = H.build_stylized_challenger(cname, acol, vcol, scale=0.85)
        ch.location, ch.rotation_euler = Vector(loc), Euler((0, 0, math.radians(yaw)), "XYZ")
        H.place_asset(H.import_glb(bfile, f"{cname}_Ball"), loc=bloc, scale=1.25)
        H.build_energy_trail(f"{cname}_Trail", tpts, c0, c1, spark_seed=3)
    H.add_area_light("QKey", (0.0, -14.0, 12.0), (0.0, 1.0, 2.5), 2200.0, (1.0, 0.95, 0.88), 14.0, 10.0)
    H.add_area_light("QRim", (0.0, 14.0, 10.0), (0.0, 1.0, 2.5), 2400.0, (0.72, 0.90, 1.0), 14.0, 8.0)
    H.aim_camera("QACam", (0.0, -15.5, 5.4), (0.0, 1.2, 2.4), lens=34.0)
    return H.render_to_path(out_dir, "Cosmetic_BallTrails_QA.png")


def render_qa_supernova_hatch(out_dir: Path, res_scale: float, samples: int) -> Path:
    """Cosmetic_SupernovaHatch_QA.png (960x540): SupernovaHatch beam + shockwave + burst."""
    _setup_qa_scene((0.20, 0.10, 0.24), (0.03, 0.02, 0.09), samples, res_scale)
    mats = [
        C.make_material("HStone", (0.18, 0.20, 0.26), roughness=0.72),
        C.make_material("HGold", (0.98, 0.78, 0.18), roughness=0.20, metallic=0.92),
        C.make_material("HBeam", (0.98, 0.80, 0.14), roughness=0.08, emission=(0.98, 0.80, 0.14), emission_strength=2.0),
        C.make_material("HPink", (0.96, 0.44, 0.72), roughness=0.10, emission=(0.96, 0.44, 0.72), emission_strength=2.2),
    ]
    bm = bmesh.new()
    C.add_faceted_box(bm, (22.0, 22.0, 0.6), (0.0, 0.0, -0.3), 0, bevel=0.12)
    H.add_pedestal_mesh(bm, (0.0, 0.0, 0.0), 2.4, 1.0, 0, 1, 2)
    C.add_lathe_shell(bm, [(1.35, 1.0), (1.35, 18.0), (0.05, 18.0)], 2, segments=16, smooth=True)
    C.add_closed_ring(bm, 4.6, 0.25, 0.20, 3, (0, 0, 0), segments=28)
    C.finalize_mesh("HatchQAStage", bm, mats)
    H.place_asset(H.import_glb("BossEgg_Molten.glb", "QAHatchEgg"), loc=(0.0, 0.0, 1.1), rot_deg=(0, 0, -18), scale=1.15, ground_z=1.1)
    H.build_impact_burst("SupernovaBurst", pos=(0.0, 0.0, 3.0), aim_dir=(0, -1, 0.2), core_col=(1.0, 0.84, 0.22), spark_col=(0.96, 0.44, 0.72), scale=1.25)
    H.add_area_light("HKey", (-9.0, -12.0, 10.0), (0.0, 0.0, 3.0), 2000.0, (1.0, 0.94, 0.86), 10.0, 8.0)
    H.add_point_light("HGlow", (0.0, -1.0, 3.2), 360.0, (1.0, 0.80, 0.20), 1.8)
    H.aim_camera("QACam", (0.0, -16.5, 5.2), (0.0, 0.0, 3.6), lens=34.0)
    return H.render_to_path(out_dir, "Cosmetic_SupernovaHatch_QA.png")


def render_qa_void_shatter(out_dir: Path, res_scale: float, samples: int) -> Path:
    """Cosmetic_VoidShatter_QA.png (960x540): VoidShatter PvP Elimination VFX."""
    _setup_qa_scene((0.12, 0.04, 0.24), (0.02, 0.01, 0.08), samples, res_scale)
    H.build_arena_stage("VoidQAStage", 18.0, (0.035, 0.035, 0.055), (0.10, 0.10, 0.15), (0.66, 0.34, 0.98), [(135, (0.66, 0.34, 0.98), 1.15), (45, (0.54, 0.36, 0.96), 1.15)])
    att = H.build_stylized_challenger("VoidAttacker", (0.08, 0.06, 0.16), (0.66, 0.34, 0.98), scale=0.88)
    att.location, att.rotation_euler = Vector((-5.5, -2.5, 0.0)), Euler((0, 0, math.radians(-55)), "XYZ")
    H.place_asset(H.import_glb("NovaSphere.glb", "VoidBall"), loc=(-2.2, -0.8, 2.4), scale=1.15)
    H.build_energy_trail("VoidThrowTrail", [(Vector((-4.6, -2.1, 2.0)), 0.06), (Vector((-3.4, -1.4, 2.2)), 0.13), (Vector((-2.2, -0.8, 2.4)), 0.20)], (0.66, 0.34, 0.98), (0.38, 0.18, 0.88), spark_seed=8)
    H.build_impact_burst("VoidShatterBurst", pos=(2.4, 1.2, 3.85), aim_dir=(-0.7, -0.5, 0.1), core_col=(0.66, 0.34, 0.98), spark_col=(0.90, 0.72, 1.0), scale=1.25)
    H.add_area_light("VKey", (-8.0, -13.0, 11.0), (0.0, 0.0, 2.8), 2000.0, (0.94, 0.90, 1.0), 12.0, 9.0)
    H.add_point_light("VGlow", (2.4, 1.2, 3.85), 420.0, (0.66, 0.34, 0.98), 1.6)
    H.aim_camera("QACam", (0.0, -16.8, 5.4), (0.0, 0.6, 2.6), lens=34.0)
    return H.render_to_path(out_dir, "Cosmetic_VoidShatter_QA.png")


def render_qa_royal_marble_plot(out_dir: Path, res_scale: float, samples: int) -> Path:
    """Cosmetic_RoyalMarblePlot_QA.png (960x540): RoyalMarblePlot theme + untouched pets."""
    _setup_qa_scene((0.20, 0.58, 0.94), (0.05, 0.24, 0.68), samples, res_scale)
    _, pet_tops = H.build_hub_base_empire(royal_marble=True)
    for fname, tag, top_pos, yaw, sc in [
        ("ThornStag.glb", "MPet_Stag", pet_tops[0], 24.0, 1.02),
        ("TrainingPup.glb", "MPet_Pup", pet_tops[1], -10.0, 1.12),
        ("SnowFox.glb", "MPet_Fox", pet_tops[2], -24.0, 1.04),
        ("GolemHeart.glb", "MPet_Golem", pet_tops[3], 22.0, 1.08),
        ("InfernoDrake.glb", "MPet_Drake", pet_tops[4], -14.0, 1.22),
        ("CryoTitan.glb", "MPet_Titan", pet_tops[5], -22.0, 1.08),
    ]:
        is_hover = tag in ("MPet_Golem", "MPet_Titan")
        H.place_asset(H.import_glb(fname, tag), loc=top_pos, rot_deg=(0, 0, yaw), scale=sc, ground_z=(top_pos[2] + 0.35 if is_hover else top_pos[2]))
    sun = bpy.data.lights.new("HubSun", type="SUN")
    sun.energy, sun.color, sun.angle = 1.65, (1.0, 0.95, 0.86), math.radians(3.5)
    sobj = bpy.data.objects.new("HubSun", sun)
    sobj.rotation_euler = Euler((math.radians(48), math.radians(-22), math.radians(38)), "XYZ")
    bpy.context.collection.objects.link(sobj)
    H.add_area_light("SkyFill", (16.0, -14.0, 14.0), (0.0, 1.0, 3.2), 1100.0, (0.72, 0.88, 1.0), 16.0, 12.0)
    H.add_area_light("GoldRim", (-4.0, 16.0, 13.0), (0.0, 2.0, 4.2), 1900.0, (1.0, 0.84, 0.52), 18.0, 10.0)
    H.aim_camera("QACam", (0.0, -26.5, 11.8), (0.0, -0.4, 2.6), lens=35.0)
    return H.render_to_path(out_dir, "Cosmetic_RoyalMarblePlot_QA.png")


PASS_SCENES = [
    render_pass_double_training,
    render_pass_double_coins_exp,
    render_pass_autofire_range,
    render_pass_magnet_collect,
    render_pass_extra_pedestals,
]
BADGE_SCENES = [
    render_badge_first_hatch,
    render_badge_boss_slayer,
    render_badge_ascension,
    render_badge_codex_master,
]
COSMETIC_QA_SCENES = [
    render_qa_ball_trails,
    render_qa_supernova_hatch,
    render_qa_void_shatter,
    render_qa_royal_marble_plot,
]
