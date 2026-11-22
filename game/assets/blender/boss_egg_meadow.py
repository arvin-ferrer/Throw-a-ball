"""Headless Blender builder for BossEgg_Meadow (Emerald Meadow Prize Boss Egg).

Replaces the grey clay smoke-test egg with a true PvP jackpot trophy (~4.6 studs tall,
<2,500 tris): smooth jade-enamel ovoid seated in a mossy stone & gold chalice nest,
diagonal brushed-gold filigree rings, inlaid glowing emerald front gem, and a 3-point
radiant crystal crown.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bmesh
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _common as C  # noqa: E402

MAT_JADE_SHELL = 0
MAT_STONE_NEST = 1
MAT_MOSS_TRIM = 2
MAT_GOLD_PRIZE = 3
MAT_GEM_GLOW = 4
MAT_VINE_DARK = 5


def create_materials() -> list[bpy.types.Material]:
    return [
        C.make_material("EggJadeEnamel", (0.10, 0.66, 0.34), roughness=0.20),
        C.make_material("EggStoneNest", (0.24, 0.27, 0.25), roughness=0.78),
        C.make_material("EggMossTrim", (0.14, 0.54, 0.20), roughness=0.74),
        C.make_material("EggPrizeGold", (0.96, 0.75, 0.22), roughness=0.22, metallic=0.92),
        C.make_material("EggEmeraldGem", (0.14, 0.96, 0.48), roughness=0.12, emission=(0.14, 0.96, 0.48), emission_strength=2.5),
        C.make_material("EggVineDeep", (0.06, 0.32, 0.14), roughness=0.68),
    ]


def build_prize_egg() -> bpy.types.Object:
    mats = create_materials()
    bm = bmesh.new()

    # 1. Beveled mossy-stone & gold trophy nest collar grounded flush on Z = 0.0
    nest_profile = [
        (1.48, 0.00),
        (1.66, 0.22),
        (1.58, 0.60),
        (1.72, 0.88),
        (1.42, 0.96),
    ]
    C.add_lathe_shell(bm, nest_profile, MAT_STONE_NEST, segments=12, smooth=False)
    C.add_closed_ring(bm, radius=1.64, radial_thickness=0.14, axial_width=0.16, mat_idx=MAT_GOLD_PRIZE, rot_deg=(0, 0, 0), segments=18)
    # Shift gold nest rim up to Z = 0.84
    bmesh.ops.translate(bm, vec=(0, 0, 0.84), verts=bm.verts[-18 * 4 :])

    # Lush moss tufts tucked around the stone chalice nest
    for i in range(6):
        ang = math.radians(i * 60.0 + 25.0)
        x, y = 1.54 * math.cos(ang), 1.54 * math.sin(ang)
        C.add_faceted_icosphere(bm, 0.40, (x, y, 0.52), MAT_MOSS_TRIM, subdivisions=1, scale=(1.15, 1.0, 0.65), noise_amp=0.12, seed=i + 2)

    # 2. Silky-smooth stylized emerald-jade ovoid shell (Z = 0.45..4.15, max r = 1.65)
    egg_profile = [
        (0.75, 0.45),
        (1.38, 0.90),
        (1.64, 1.55),
        (1.62, 2.25),
        (1.38, 2.95),
        (0.95, 3.55),
        (0.45, 3.98),
        (0.10, 4.12),
    ]
    C.add_lathe_shell(bm, egg_profile, MAT_JADE_SHELL, segments=20, smooth=True)

    # 3. Diagonal crossed brushed-gold prize filigree bands hugging the egg
    before = len(bm.verts)
    C.add_closed_ring(bm, radius=1.66, radial_thickness=0.10, axial_width=0.16, mat_idx=MAT_GOLD_PRIZE, rot_deg=(24, 16, 0), segments=20)
    bmesh.ops.translate(bm, vec=(0, 0, 2.12), verts=list(bm.verts)[before:])
    before2 = len(bm.verts)
    C.add_closed_ring(bm, radius=1.67, radial_thickness=0.10, axial_width=0.16, mat_idx=MAT_GOLD_PRIZE, rot_deg=(-24, -14, 0), segments=20)
    bmesh.ops.translate(bm, vec=(0, 0, 2.12), verts=list(bm.verts)[before2:])

    # 4. Ornate gold bezel + glowing emerald centerpiece diamond on front (-Y) & back (+Y)
    for sy in (-1, 1):
        C.add_faceted_box(bm, (0.86, 0.24, 1.10), (0.0, sy * 1.62, 2.15), MAT_GOLD_PRIZE, 0.08, rot_deg=(0, 45, 0))
        C.add_faceted_icosphere(bm, 0.44, (0.0, sy * 1.72, 2.15), MAT_GEM_GLOW, subdivisions=1, scale=(0.82, 0.48, 1.25))

    # 5. Sweeping organic lofted meadow vine curling up one flank
    vine_rings = [
        ((-1.42, -0.52, 0.95), 0.14, 0.14, (0, 20, 0)),
        ((-1.62, 0.25, 1.65), 0.13, 0.13, (-10, 15, 0)),
        ((-1.48, 0.85, 2.45), 0.11, 0.11, (-15, 8, 0)),
        ((-0.96, 0.92, 3.25), 0.09, 0.09, (-12, -10, 0)),
        ((-0.38, 0.48, 3.82), 0.06, 0.06, (0, -25, 0)),
    ]
    C.add_lofted_tube(bm, vine_rings, MAT_VINE_DARK, sides=6, smooth=True)

    # 6. Regal golden crown collar + 3-point glowing emerald crystal crest (top Z ~ 4.75)
    before3 = len(bm.verts)
    C.add_closed_ring(bm, radius=0.68, radial_thickness=0.12, axial_width=0.22, mat_idx=MAT_GOLD_PRIZE, rot_deg=(0, 0, 0), segments=12)
    bmesh.ops.translate(bm, vec=(0, 0, 3.88), verts=list(bm.verts)[before3:])
    C.add_crystal_prism(bm, 0.34, 1.05, (0.0, 0.0, 4.30), MAT_GEM_GLOW, sides=6, rot_deg=(0, 0, 0))
    C.add_crystal_prism(bm, 0.22, 0.72, (-0.42, -0.08, 4.14), MAT_GEM_GLOW, sides=5, rot_deg=(6, -24, 0))
    C.add_crystal_prism(bm, 0.22, 0.72, (0.42, -0.08, 4.14), MAT_GEM_GLOW, sides=5, rot_deg=(6, 24, 0))

    return C.finalize_mesh("BossEgg_Meadow", bm, mats)


def main() -> None:
    C.clear_scene()
    obj = build_prize_egg()
    C.validate_asset("BossEgg_Meadow", [obj], tri_cap=2500, pivot_mode="floor")
    C.export_roblox_asset("BossEgg_Meadow", [obj], rigged=False)
    C.setup_studio_render([obj], "BossEgg_Meadow_preview.png", resolution=768, samples=24, cam_azimuth_deg=-30.0, cam_elev_deg=18.0, distance_mult=2.25)
    print("BLENDER_EXPORT_OK: BossEgg_Meadow")


if __name__ == "__main__":
    main()
