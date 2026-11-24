"""Launch Art Package Renderer for Ball Brawl: Boss Eggs (Issue #20).

Composes exported Roblox-ready .glb assets from `game/assets/exports/` into:
  - 3 high-CTR 16:9 Home Thumbnails + 512x512 Game Icon + 5 Game Pass + 4 Badge icons in `game/assets/ui/`
  - 4 final cosmetic QA renders in `game/assets/renders/`
  - Half-res `--fast` previews routed safely to `game/assets/renders/launch_previews/`

Run via:
  python3 scripts/blender_run.py game/assets/blender/launch_art.py [--fast] [--samples 48] [--only ...]
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _common as C  # noqa: E402
import _launch_helpers as H  # noqa: E402
import launch_extras as E  # noqa: E402


def _setup_brawl_lights() -> None:
    """Configure dramatic volcanic-vs-emerald boss brawl lighting."""
    H.add_area_light("Key", (-15.0, -22.0, 16.0), (0.0, 4.0, 4.8), 2400.0, (1.0, 0.92, 0.80), 11.0, 9.0)
    H.add_area_light("CoolFill", (-22.0, -6.0, 9.0), (-2.0, 5.0, 4.5), 850.0, (0.48, 0.78, 1.0), 12.0, 10.0)
    H.add_area_light("PyraxisRim", (14.0, 18.0, 14.0), (6.0, 7.0, 6.2), 4800.0, (1.0, 0.44, 0.10), 12.0, 9.0)
    H.add_area_light("PyraxisChestFill", (-2.0, -4.0, 4.0), (6.2, 6.8, 4.8), 950.0, (1.0, 0.56, 0.22), 6.0, 6.0)
    H.add_area_light("MossbackRim", (-15.0, 20.0, 12.0), (-9.0, 9.0, 6.5), 2600.0, (0.24, 1.0, 0.48), 10.0, 9.0)
    H.add_point_light("NovaGlow", (-5.8, -11.8, 3.8), 220.0, (0.20, 0.88, 1.0), 1.1)
    H.add_point_light("ImpactGlow", (0.4, -0.6, 4.1), 280.0, (1.0, 0.58, 0.22), 1.4)


def render_boss_brawl(out_dir: Path, res_scale: float, samples: int) -> Path:
    """Scene 1: Thumbnail_01_BossBrawl.png (1920x1080)."""
    C.clear_scene()
    H.setup_render_pipeline(int(1920 * res_scale), int(1080 * res_scale), samples, exposure=-0.22, bloom_threshold=1.55, bloom_strength=0.14)
    H.set_gradient_world((0.14, 0.06, 0.24), (0.03, 0.02, 0.09), strength=0.58)
    H.build_arena_stage("BrawlArena", 26.0, (0.045, 0.048, 0.058), (0.11, 0.12, 0.14), (1.0, 0.36, 0.06), [(132, (0.10, 0.94, 0.34), 1.35), (158, (0.10, 0.94, 0.34), 1.05), (48, (1.0, 0.34, 0.05), 1.40), (22, (1.0, 0.42, 0.08), 1.15)])
    pyraxis = H.import_glb("Pyraxis_RobloxRigged.glb", "Pyraxis")
    H.pose_rig_clean(pyraxis.armatures[0], {"Neck1": (-16, 0, -8), "Head": (-14, 0, -10), "Jaw": (-32, 0, 0)})
    H.boost_pyraxis_accents(pyraxis)
    H.place_asset(pyraxis, loc=(7.4, 6.8, 2.5), rot_deg=(12.0, -8.0, 146.0), scale=0.94, ground_z=1.8)
    mossback = H.import_glb("MossbackGolem.glb", "Mossback")
    H.pose_rig_clean(mossback.armatures[0], {"Chest": (0, 0, -10), "Head": (0, 0, 12)})
    H.place_asset(mossback, loc=(-10.2, 8.8, 0.0), rot_deg=(0.0, 0.0, -24.0), scale=0.92, ground_z=-0.04)
    H.place_asset(H.import_glb("NovaSphere.glb", "NovaHero"), loc=(-6.6, -12.0, 3.3), rot_deg=(18.0, -22.0, 32.0), scale=1.50)
    H.place_asset(H.import_glb("MagmaCore.glb", "MagmaHero"), loc=(-1.2, -10.2, 2.4), rot_deg=(-15.0, 28.0, -18.0), scale=1.28)
    H.build_energy_trail("NovaTrail", [(Vector((-15.5, -18.2, 0.9)), 0.04), (Vector((-12.6, -15.8, 1.65)), 0.12), (Vector((-9.6, -13.6, 2.55)), 0.19), (Vector((-7.1, -12.3, 3.18)), 0.24)], (0.08, 0.86, 1.0), (0.04, 0.36, 1.0), spark_seed=2)
    H.build_energy_trail("MagmaTrail", [(Vector((-8.4, -18.8, 0.5)), 0.04), (Vector((-5.2, -15.4, 1.1)), 0.11), (Vector((-2.6, -12.2, 1.8)), 0.18), (Vector((-1.7, -10.8, 2.25)), 0.21)], (1.0, 0.52, 0.06), (1.0, 0.20, 0.02), spark_seed=7)
    H.build_impact_burst("BossImpact", pos=(4.2, 1.8, 3.0), aim_dir=(-0.7, -0.8, -0.15), core_col=(0.24, 0.94, 1.0), spark_col=(1.0, 0.40, 0.06), scale=0.52)
    _setup_brawl_lights()
    H.aim_camera("BrawlCam", (-14.5, -24.8, 5.5), (-0.6, 3.2, 5.2), lens=32.0, roll_deg=-2.5)
    return H.render_to_path(out_dir, "Thumbnail_01_BossBrawl.png")


def _build_egg_altar() -> bpy.types.Object:
    """Build the carved multi-step gold/basalt Egg Scramble dais & 5s claim ring."""
    bm_ped = bmesh.new()
    ped_mats = [
        C.make_material("AltarBasalt", (0.06, 0.055, 0.08), roughness=0.72),
        C.make_material("AltarGold", (0.98, 0.76, 0.20), roughness=0.20, metallic=0.94),
        C.make_material("ClaimRingGlow", (1.0, 0.54, 0.08), roughness=0.14, emission=(1.0, 0.54, 0.08), emission_strength=2.0),
    ]
    C.add_lathe_shell(bm_ped, [(4.6, 0.0), (4.7, 0.55), (3.8, 0.65), (3.8, 1.25), (3.1, 1.35), (3.1, 1.95), (0.1, 1.95)], 0, segments=12, smooth=False)
    b0 = set(bm_ped.verts)
    C.add_closed_ring(bm_ped, 3.16, 0.22, 0.20, 1, segments=18)
    bmesh.ops.translate(bm_ped, vec=(0, 0, 1.85), verts=[v for v in bm_ped.verts if v not in b0])
    b1 = set(bm_ped.verts)
    C.add_closed_ring(bm_ped, 6.4, 0.22, 0.06, 2, segments=28)
    bmesh.ops.translate(bm_ped, vec=(0, 0, 0.04), verts=[v for v in bm_ped.verts if v not in b1])
    return C.finalize_mesh("EggScrambleAltar", bm_ped, ped_mats)


def _setup_egg_lights() -> None:
    """Configure dramatic rim-dominant lighting for Egg Scramble."""
    H.add_area_light("EggKey", (-6.0, -13.5, 11.0), (0.0, 0.0, 5.2), 1050.0, (1.0, 0.90, 0.76), 7.0, 7.0)
    H.add_area_light("EggRimGold", (0.0, 10.5, 12.0), (0.0, 0.0, 5.4), 3400.0, (1.0, 0.58, 0.14), 9.0, 7.0)
    H.add_area_light("RimVioletL", (-13.0, 21.0, 10.0), (-10.0, 15.0, 6.5), 2400.0, (0.58, 0.26, 1.0), 8.0, 8.0)
    H.add_area_light("RimCyanR", (13.0, 21.0, 10.0), (10.0, 14.5, 6.5), 2400.0, (0.22, 0.88, 1.0), 8.0, 8.0)
    H.add_point_light("EggCoreLight", (0.0, -2.2, 5.2), 240.0, (1.0, 0.64, 0.20), 1.6)


def render_glowing_egg(out_dir: Path, res_scale: float, samples: int) -> Path:
    """Scene 2: Thumbnail_02_GlowingEgg.png (1920x1080)."""
    C.clear_scene()
    H.setup_render_pipeline(int(1920 * res_scale), int(1080 * res_scale), samples, exposure=-0.32, bloom_threshold=1.55, bloom_strength=0.16)
    H.set_gradient_world((0.05, 0.025, 0.11), (0.01, 0.01, 0.035), strength=0.35)
    H.build_arena_stage("ScrambleArena", 24.0, (0.035, 0.035, 0.048), (0.10, 0.10, 0.14), (0.64, 0.22, 1.0), [(138, (0.20, 0.88, 1.0), 1.2), (42, (1.0, 0.42, 0.06), 1.2)])
    _build_egg_altar()
    H.place_asset(H.import_glb("BossEgg_Molten_Overcharged.glb", "HeroOverchargedEgg"), loc=(0.0, 0.0, 1.95), rot_deg=(0.0, 0.0, -18.0), scale=1.50, ground_z=1.95)
    H.build_energy_vortex("OverchargeVortex", (0.0, 0.0, 1.95), 4.6, 7.6, (1.0, 0.44, 0.06), (0.56, 0.22, 1.0))
    yeti = H.import_glb("GlacierYeti.glb", "YetiSilhouette")
    H.pose_rig_clean(yeti.armatures[0], {"Chest": (0, 0, -8), "Head": (0, 0, 8)})
    H.place_asset(yeti, loc=(-10.6, 15.8, 0.0), rot_deg=(0.0, 0.0, -28.0), scale=0.92, ground_z=-0.04)
    wyrm = H.import_glb("ObsidianWyrm.glb", "WyrmSilhouette")
    H.pose_rig_clean(wyrm.armatures[0], {"Neck1": (-10, 0, 10), "Head": (-12, 0, 14), "Jaw": (-28, 0, 0)})
    H.place_asset(wyrm, loc=(10.6, 15.4, 0.0), rot_deg=(0.0, 0.0, 26.0), scale=0.92, ground_z=0.0)
    for cname, cloc, cyaw, acol, vcol, bfile, bloc in [
        ("ChallengerL", (-6.2, -6.8, 0.0), 40.0, (0.05, 0.09, 0.16), (0.28, 0.94, 1.0), "NovaSphere.glb", (-5.2, -5.5, 2.8)),
        ("ChallengerR", (6.2, -6.6, 0.0), -40.0, (0.14, 0.05, 0.09), (1.0, 0.48, 0.10), "MagmaCore.glb", (5.2, -5.3, 2.8)),
    ]:
        ch = H.build_stylized_challenger(cname, acol, vcol, scale=0.82)
        ch.location, ch.rotation_euler = Vector(cloc), Euler((0.0, 0.0, math.radians(cyaw)), "XYZ")
        H.place_asset(H.import_glb(bfile, f"{cname}_Ball"), loc=bloc, scale=0.95)
    _setup_egg_lights()
    H.aim_camera("EggCam", (0.0, -21.2, 5.6), (0.0, 0.2, 4.3), lens=35.0)
    return H.render_to_path(out_dir, "Thumbnail_02_GlowingEgg.png")


def render_base_empire(out_dir: Path, res_scale: float, samples: int) -> Path:
    """Scene 3: Thumbnail_03_BaseEmpire.png (1920x1080)."""
    C.clear_scene()
    H.setup_render_pipeline(int(1920 * res_scale), int(1080 * res_scale), samples, exposure=-0.30, bloom_threshold=1.55, bloom_strength=0.12)
    H.set_gradient_world((0.20, 0.58, 0.94), (0.05, 0.24, 0.68), strength=0.45)
    _, pet_tops = H.build_hub_base_empire(royal_marble=False)
    for fname, tag, top_pos, yaw, sc in [
        ("ThornStag.glb", "Pet_ThornStag", pet_tops[0], 24.0, 1.02),
        ("TrainingPup.glb", "Pet_TrainingPup", pet_tops[1], -10.0, 1.12),
        ("SnowFox.glb", "Pet_SnowFox", pet_tops[2], -24.0, 1.04),
        ("GolemHeart.glb", "Pet_GolemHeart", pet_tops[3], 22.0, 1.08),
        ("InfernoDrake.glb", "Pet_InfernoDrake", pet_tops[4], -14.0, 1.22),
        ("CryoTitan.glb", "Pet_CryoTitan", pet_tops[5], -22.0, 1.08),
    ]:
        is_hover = tag in ("Pet_GolemHeart", "Pet_CryoTitan")
        H.place_asset(H.import_glb(fname, tag), loc=top_pos, rot_deg=(0.0, 0.0, yaw), scale=sc, ground_z=(top_pos[2] + 0.35 if is_hover else top_pos[2]))
    sun_data = bpy.data.lights.new("HubSun", type="SUN")
    sun_data.energy, sun_data.color, sun_data.angle = 1.65, (1.0, 0.95, 0.86), math.radians(3.5)
    sun_obj = bpy.data.objects.new("HubSun", sun_data)
    sun_obj.rotation_euler = Euler((math.radians(48), math.radians(-22), math.radians(38)), "XYZ")
    bpy.context.collection.objects.link(sun_obj)
    H.add_area_light("SkyFill", (16.0, -14.0, 14.0), (0.0, 1.0, 3.2), 1100.0, (0.72, 0.88, 1.0), 16.0, 12.0)
    H.add_area_light("GoldRim", (-4.0, 16.0, 13.0), (0.0, 2.0, 4.2), 1900.0, (1.0, 0.84, 0.52), 18.0, 10.0)
    H.add_point_light("CashPadFill", (0.0, -7.8, 2.2), 120.0, (0.35, 1.0, 0.58), 2.2)
    H.aim_camera("EmpireCam", (0.0, -26.5, 11.8), (0.0, -0.4, 2.6), lens=35.0)
    return H.render_to_path(out_dir, "Thumbnail_03_BaseEmpire.png")


def render_game_icon(out_dir: Path, res_scale: float, samples: int) -> Path:
    """Scene 4: GameIcon_512.png (512x512)."""
    C.clear_scene()
    H.setup_render_pipeline(max(64, int(512 * res_scale)), max(64, int(512 * res_scale)), samples, exposure=-0.20, bloom_threshold=1.50, bloom_strength=0.16)
    H.set_gradient_world((0.36, 0.10, 0.18), (0.06, 0.03, 0.14), strength=0.58)
    pyraxis = H.import_glb("Pyraxis_RobloxRigged.glb", "IconPyraxis")
    H.pose_rig_clean(pyraxis.armatures[0], {"Neck1": (-16, 0, -6), "Head": (-14, 0, -8), "Jaw": (-32, 0, 0)})
    H.boost_pyraxis_accents(pyraxis)
    H.place_asset(pyraxis, loc=(0.2, 6.8, 3.9), rot_deg=(14.0, -8.0, 164.0), scale=0.80)
    H.place_asset(H.import_glb("BossEgg_Molten_Overcharged.glb", "IconEgg"), loc=(2.6, -5.8, 0.1), rot_deg=(6.0, -10.0, -24.0), scale=1.18)
    H.place_asset(H.import_glb("NovaSphere.glb", "IconBall"), loc=(-2.9, -7.8, 2.75), rot_deg=(24.0, -18.0, 32.0), scale=1.48)
    H.build_energy_trail("IconSwoosh", [(Vector((-7.4, -12.6, 0.1)), 0.05), (Vector((-5.4, -10.8, 1.15)), 0.15), (Vector((-3.4, -8.4, 2.45)), 0.25)], (0.08, 0.88, 1.0), (0.04, 0.40, 1.0), spark_seed=5)
    H.add_area_light("IconKey", (-8.0, -14.0, 9.5), (0.0, 0.0, 4.2), 1600.0, (1.0, 0.94, 0.85), 8.0, 8.0)
    H.add_area_light("IconChestFill", (2.5, -6.5, 4.5), (0.2, 5.0, 4.5), 1100.0, (1.0, 0.62, 0.28), 6.0, 6.0)
    H.add_area_light("IconRimHot", (8.5, 13.5, 12.0), (0.4, 6.0, 6.2), 5200.0, (1.0, 0.44, 0.06), 10.0, 9.0)
    H.add_area_light("IconRimCyan", (-10.0, 11.0, 9.5), (-0.5, 5.0, 5.2), 3200.0, (0.26, 0.88, 1.0), 9.0, 8.0)
    H.add_point_light("IconEggGlow", (2.6, -7.2, 3.4), 220.0, (1.0, 0.62, 0.18), 1.4)
    H.add_point_light("IconBallGlow", (-2.9, -7.8, 2.75), 160.0, (0.20, 0.90, 1.0), 1.0)
    H.add_point_light("IconPyraxisBack", (0.2, 11.0, 7.5), 1600.0, (1.0, 0.36, 0.06), 2.5)
    H.aim_camera("IconCam", (-1.0, -19.5, 4.4), (0.0, 0.5, 4.6), lens=38.0, roll_deg=-3.5)
    return H.render_to_path(out_dir, "GameIcon_512.png")


def parse_args(argv: list[str]) -> argparse.Namespace:
    """Parse CLI args passed after `--`."""
    parser = argparse.ArgumentParser(description="Render Ball Brawl launch marketing art.")
    parser.add_argument("--fast", action="store_true", help="Half resolution and 16 samples into launch_previews/.")
    parser.add_argument("--samples", type=int, default=48, help="Cycles sample count.")
    parser.add_argument("--only", type=str, default="", help="Comma-separated: brawl,egg,base,icon,passes,badges,cosmetics")
    return parser.parse_args(argv)


def main() -> None:
    """Render selected launch marketing & QA scenes and report output paths."""
    raw_argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    args = parse_args(raw_argv)
    res_scale = 0.5 if args.fast else 1.0
    samples = 16 if args.fast else args.samples
    ui_out = H.resolve_output_dir(H.UI_DIR, args.fast)
    qa_out = H.resolve_output_dir(H.RENDER_DIR, args.fast)

    groups = {
        "brawl": [(render_boss_brawl, ui_out)],
        "egg": [(render_glowing_egg, ui_out)],
        "base": [(render_base_empire, ui_out)],
        "icon": [(render_game_icon, ui_out)],
        "passes": [(fn, ui_out) for fn in E.PASS_SCENES],
        "badges": [(fn, ui_out) for fn in E.BADGE_SCENES],
        "cosmetics": [(fn, qa_out) for fn in E.COSMETIC_QA_SCENES],
    }
    selected = [k.strip() for k in args.only.split(",") if k.strip()] if args.only else list(groups.keys())
    for key in selected:
        if key not in groups:
            raise ValueError(f"Unknown scene key '{key}'; expected one of {list(groups.keys())}")
        for fn, out_dir in groups[key]:
            fn(out_dir, res_scale, samples)
    print("LAUNCH_ART_OK")


if __name__ == "__main__":
    main()
