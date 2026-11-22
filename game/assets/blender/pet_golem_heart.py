"""Headless Blender builder for GolemHeart (Emerald Meadow MYTHIC Pet, Issue #13).

Floating mythic pedestal centerpiece (~3.6 studs tall, <2,500 tris, hover pivot):
radiant faceted emerald-jade crystal heart core wrapped in metallic gold filigree,
orbited by 3 hovering mossy stone rune shields/gauntlets and a golden halo ring,
crowned by a 3-point emerald crystal crest.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bmesh
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _common as C  # noqa: E402

MAT_HEART_GLOW = 0
MAT_STONE_DARK = 1
MAT_STONE_MID = 2
MAT_MOSS_BRIGHT = 3
MAT_GOLD_MYTHIC = 4
MAT_EYE_BRIGHT = 5


def create_materials() -> list[bpy.types.Material]:
    return [
        C.make_material("MythicHeartJade", (0.05, 0.76, 0.32), roughness=0.14, emission=(0.06, 0.80, 0.34), emission_strength=1.15),
        C.make_material("MythicStoneDark", (0.16, 0.19, 0.18), roughness=0.80),
        C.make_material("MythicStoneMid", (0.34, 0.38, 0.35), roughness=0.72),
        C.make_material("MythicMoss", (0.16, 0.58, 0.22), roughness=0.76),
        C.make_material("MythicGold", (0.98, 0.76, 0.22), roughness=0.20, metallic=0.94),
        C.make_material("MythicEyeWhite", (0.85, 1.0, 0.92), roughness=0.05, emission=(0.85, 1.0, 0.92), emission_strength=2.8),
    ]


def build_golem_heart() -> bpy.types.Object:
    mats = create_materials()
    bm = bmesh.new()

    # 1. Sculpted faceted emerald crystal Heart Core hovering at Z = 0.50..2.90
    core_profile = [
        (0.10, 0.52),
        (0.58, 1.08),
        (0.92, 1.75),
        (0.86, 2.38),
        (0.45, 2.80),
        (0.10, 2.94),
    ]
    C.add_lathe_shell(bm, core_profile, MAT_HEART_GLOW, segments=8, scale_xy=(1.08, 0.82), smooth=False)
    # Dark stone visor brow & fierce glowing mythic spirit eyes on front (-Y)
    C.add_faceted_box(bm, (1.18, 0.42, 0.48), (0.0, -0.68, 2.02), MAT_STONE_DARK, 0.06, rot_deg=(8, 0, 0))
    C.add_faceted_box(bm, (0.28, 0.18, 0.18), (-0.30, -0.88, 1.98), MAT_EYE_BRIGHT, 0.02, rot_deg=(0, 0, -10))
    C.add_faceted_box(bm, (0.28, 0.18, 0.18), (0.30, -0.88, 1.98), MAT_EYE_BRIGHT, 0.02, rot_deg=(0, 0, 10))

    # 2. Tilted metallic gold mythic aura halo ring orbiting core
    before = set(bm.verts)
    C.add_closed_ring(bm, radius=1.42, radial_thickness=0.11, axial_width=0.14, mat_idx=MAT_GOLD_MYTHIC, rot_deg=(24, -18, 0), segments=22)
    bmesh.ops.translate(bm, vec=(0, 0, 1.82), verts=[v for v in bm.verts if v not in before])

    # 3. Three hovering beveled moss-stone rune shields framing sides & back (clear front face!)
    for i in range(3):
        ang_deg = i * 120.0 + 90.0
        rad = math.radians(ang_deg)
        r = 1.50
        x, y = r * math.cos(rad), r * math.sin(rad)
        z = 1.65 + (0.18 if i == 0 else -0.06)
        C.add_faceted_box(bm, (0.78, 0.44, 1.18), (x, y, z), MAT_STONE_MID, 0.08, rot_deg=(12, 0, ang_deg - 90), taper_top=(0.82, 0.9))
        C.add_faceted_icosphere(bm, 0.34, (x * 1.02, y * 1.02, z + 0.56), MAT_MOSS_BRIGHT, subdivisions=1, scale=(1.1, 0.85, 0.55), noise_amp=0.14, seed=10 + i)
        C.add_faceted_box(bm, (0.24, 0.16, 0.58), (x * 1.12, y * 1.12, z), MAT_GOLD_MYTHIC, 0.03, rot_deg=(12, 0, ang_deg - 90))

    # 4. Regal golden collar & 3-point mythic emerald crystal crown at top (Z ~ 3.65)
    before2 = set(bm.verts)
    C.add_closed_ring(bm, radius=0.52, radial_thickness=0.10, axial_width=0.18, mat_idx=MAT_GOLD_MYTHIC, rot_deg=(0, 0, 0), segments=12)
    bmesh.ops.translate(bm, vec=(0, 0, 2.86), verts=[v for v in bm.verts if v not in before2])
    C.add_crystal_prism(bm, 0.24, 0.85, (0.0, 0.0, 3.25), MAT_HEART_GLOW, sides=6, rot_deg=(0, 0, 0))
    C.add_crystal_prism(bm, 0.16, 0.58, (-0.34, 0.0, 3.12), MAT_HEART_GLOW, sides=5, rot_deg=(0, -24, 0))
    C.add_crystal_prism(bm, 0.16, 0.58, (0.34, 0.0, 3.12), MAT_HEART_GLOW, sides=5, rot_deg=(0, 24, 0))

    return C.finalize_mesh("GolemHeart", bm, mats)


def main() -> None:
    C.clear_scene()
    obj = build_golem_heart()
    C.validate_asset("GolemHeart", [obj], tri_cap=2500, pivot_mode="hover")
    C.export_roblox_asset("GolemHeart", [obj], rigged=False)
    C.setup_studio_render([obj], "GolemHeart_preview.png", resolution=640, samples=22, cam_azimuth_deg=-32.0, cam_elev_deg=18.0, distance_mult=2.25)
    print("BLENDER_EXPORT_OK: GolemHeart")


if __name__ == "__main__":
    main()
