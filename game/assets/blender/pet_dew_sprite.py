"""Headless Blender builder for DewSprite (Emerald Meadow Pet 2, Issue #13).

Floating luminous water-drop fairy spirit (~3.1 studs tall, <2,500 tris, hover pivot):
silky sculpted turquoise teardrop body, fluttering curved emerald leaf wings, golden
dewdrop crown halo, large glossy joyful eyes, and orbiting water-droplet wisps.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bmesh
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _common as C  # noqa: E402

MAT_DEW_AQUA = 0
MAT_DEW_GLOW = 1
MAT_LEAF_WING = 2
MAT_GOLD_HALO = 3
MAT_EYE_DARK = 4
MAT_EYE_GLINT = 5
MAT_CHEEK_PINK = 6


def create_materials() -> list[bpy.types.Material]:
    return [
        C.make_material("DewAquaGel", (0.14, 0.82, 0.88), roughness=0.10),
        C.make_material("DewAquaGlow", (0.30, 0.96, 1.0), roughness=0.08, emission=(0.24, 0.92, 0.96), emission_strength=2.0),
        C.make_material("DewLeafWing", (0.20, 0.82, 0.34), roughness=0.35),
        C.make_material("DewGoldHalo", (0.98, 0.78, 0.26), roughness=0.22, metallic=0.92),
        C.make_material("DewEyeDark", (0.03, 0.05, 0.08), roughness=0.06),
        C.make_material("DewEyeGlint", (1.0, 1.0, 1.0), roughness=0.05, emission=(1.0, 1.0, 1.0), emission_strength=1.9),
        C.make_material("DewCheekBlush", (0.98, 0.54, 0.68), roughness=0.40),
    ]


def build_dew_sprite() -> bpy.types.Object:
    mats = create_materials()
    bm = bmesh.new()

    # 1. Silky sculpted teardrop water-spirit body hovering cleanly at Z = 0.45..2.85
    drop_profile = [
        (0.28, 0.48),
        (0.76, 0.78),
        (1.02, 1.22),
        (0.98, 1.72),
        (0.72, 2.22),
        (0.36, 2.66),
        (0.08, 2.96),
    ]
    C.add_lathe_shell(bm, drop_profile, MAT_DEW_AQUA, segments=18, smooth=True)

    # 2. Expressive glossy eyes & cute rosy blush cheeks facing -Y front
    C.add_expressive_eye(bm, (-0.36, -0.88, 1.48), 0.21, MAT_EYE_DARK, MAT_EYE_GLINT)
    C.add_expressive_eye(bm, (0.36, -0.88, 1.48), 0.21, MAT_EYE_DARK, MAT_EYE_GLINT)
    for sx in (-1, 1):
        C.add_faceted_icosphere(bm, 0.13, (sx * 0.56, -0.84, 1.24), MAT_CHEEK_PINK, subdivisions=1, scale=(1.2, 0.5, 0.8))

    # 3. Graceful sculpted emerald leaf-wings (upper large + lower small pair)
    for sx in (-1, 1):
        upper_wing = [
            ((sx * 0.65, 0.48, 1.62), 0.12, 0.06, (0, sx * 55, 0)),
            ((sx * 1.28, 0.68, 2.02), 0.42, 0.08, (-12, sx * 68, sx * -15)),
            ((sx * 1.88, 0.82, 2.24), 0.34, 0.06, (-16, sx * 76, sx * -20)),
            ((sx * 2.28, 0.90, 2.30), 0.05, 0.03, (-18, sx * 84, sx * -22)),
        ]
        C.add_lofted_tube(bm, upper_wing, MAT_LEAF_WING, sides=8, smooth=True)
        lower_wing = [
            ((sx * 0.62, 0.45, 1.24), 0.10, 0.05, (0, sx * 65, 0)),
            ((sx * 1.15, 0.64, 1.10), 0.28, 0.06, (10, sx * 85, sx * -14)),
            ((sx * 1.56, 0.74, 0.96), 0.05, 0.03, (14, sx * 96, sx * -16)),
        ]
        C.add_lofted_tube(bm, lower_wing, MAT_LEAF_WING, sides=6, smooth=True)

    # 4. Floating golden dew-crown halo + glowing crown droplet
    before = len(bm.verts)
    C.add_closed_ring(bm, radius=0.52, radial_thickness=0.07, axial_width=0.08, mat_idx=MAT_GOLD_HALO, rot_deg=(12, 0, 0), segments=18)
    bmesh.ops.translate(bm, vec=(0, 0, 3.06), verts=list(bm.verts)[before:])
    C.add_crystal_prism(bm, 0.12, 0.32, (0.0, -0.48, 3.16), MAT_DEW_GLOW, sides=5, rot_deg=(12, 0, 0))

    # 5. Three tiny orbiting glowing water-droplet wisps near base
    for i in range(3):
        ang = math.radians(i * 120.0 + 30.0)
        C.add_faceted_icosphere(bm, 0.16, (1.28 * math.cos(ang), 1.28 * math.sin(ang), 0.78 + 0.12 * i), MAT_DEW_GLOW, subdivisions=1, scale=(0.85, 0.85, 1.25))

    return C.finalize_mesh("DewSprite", bm, mats)


def main() -> None:
    C.clear_scene()
    obj = build_dew_sprite()
    C.validate_asset("DewSprite", [obj], tri_cap=2500, pivot_mode="hover")
    C.export_roblox_asset("DewSprite", [obj], rigged=False)
    C.setup_studio_render([obj], "DewSprite_preview.png", resolution=640, samples=22, cam_azimuth_deg=-30.0, cam_elev_deg=16.0, distance_mult=2.25)
    print("BLENDER_EXPORT_OK: DewSprite")


if __name__ == "__main__":
    main()
