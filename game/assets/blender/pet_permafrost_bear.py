"""Headless Blender builder for PermafrostBear (Frostbite Cavern Pet 3, Issue #17)."""

from __future__ import annotations

import sys
from pathlib import Path

import bmesh
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _common as C  # noqa: E402

MAT_POLAR_WHITE = 0
MAT_FROST_BLUE = 1
MAT_ICE_ARMOR = 2
MAT_CYAN_RUNE = 3
MAT_EYE_DARK = 4
MAT_EYE_GLINT = 5


def create_materials() -> list[bpy.types.Material]:
    return [
        C.make_material("BearPolarWhite", (0.90, 0.94, 0.98), roughness=0.58),
        C.make_material("BearFrostBlue", (0.58, 0.78, 0.94), roughness=0.52),
        C.make_material("BearIceArmor", (0.42, 0.84, 1.0), roughness=0.14),
        C.make_material("BearCyanRune", (0.20, 0.94, 1.0), roughness=0.12, emission=(0.20, 0.92, 1.0), emission_strength=2.1),
        C.make_material("BearEyeDark", (0.03, 0.04, 0.07), roughness=0.06),
        C.make_material("BearEyeGlint", (1.0, 1.0, 1.0), roughness=0.05, emission=(1.0, 1.0, 1.0), emission_strength=1.8),
    ]


def build_permafrost_bear() -> bpy.types.Object:
    mats = create_materials()
    bm = bmesh.new()
    # Stout polar-bear torso + ice shield chest crest
    C.add_lathe_shell(bm, [(0.62, 0.28), (1.02, 0.68), (1.06, 1.24), (0.84, 1.66), (0.48, 1.82)], MAT_POLAR_WHITE, segments=14, center=(0, 0.08, 0), scale_xy=(1.06, 0.98), smooth=True)
    C.add_faceted_box(bm, (0.96, 0.28, 0.96), (0.0, -0.94, 1.06), MAT_ICE_ARMOR, 0.08, rot_deg=(0, 45, 0))
    C.add_crystal_prism(bm, 0.18, 0.38, (0.0, -1.08, 1.12), MAT_CYAN_RUNE, sides=5, rot_deg=(84, 0, 0))
    # Armored polar paws flush on Z = 0.0 + frosted ice shoulder shields
    for sx in (-1, 1):
        C.add_faceted_box(bm, (0.68, 0.86, 0.56), (sx * 0.64, 0.24, 0.28), MAT_FROST_BLUE, 0.08, taper_top=(0.86, 0.86))
        C.add_faceted_box(bm, (0.66, 0.72, 0.96), (sx * 1.04, -0.34, 0.64), MAT_POLAR_WHITE, 0.10, rot_deg=(10, sx * -8, 0))
        C.add_faceted_box(bm, (0.62, 0.68, 0.42), (sx * 1.04, -0.46, 0.21), MAT_ICE_ARMOR, 0.06)
        C.add_crystal_prism(bm, 0.26, 0.82, (sx * 1.12, 0.05, 1.56), MAT_ICE_ARMOR, sides=5, rot_deg=(-12, sx * 30, 0))
    # Cute polar bear head, ears, snout & glossy eyes
    C.add_lathe_shell(bm, [(0.56, 1.60), (0.92, 1.92), (0.98, 2.34), (0.82, 2.74), (0.44, 2.96)], MAT_POLAR_WHITE, segments=14, center=(0, -0.18, 0), scale_xy=(1.08, 0.96), smooth=True)
    for sx in (-1, 1):
        C.add_faceted_icosphere(bm, 0.34, (sx * 0.80, -0.14, 2.86), MAT_POLAR_WHITE, subdivisions=1, scale=(1.0, 0.72, 1.0))
        C.add_faceted_icosphere(bm, 0.18, (sx * 0.78, -0.32, 2.86), MAT_FROST_BLUE, subdivisions=1, scale=(1.0, 0.5, 1.0))
    C.add_crystal_prism(bm, 0.22, 0.72, (0.0, -0.05, 3.16), MAT_ICE_ARMOR, sides=5, rot_deg=(-10, 0, 0))
    C.add_faceted_icosphere(bm, 0.40, (0.0, -1.02, 2.12), MAT_FROST_BLUE, subdivisions=2, scale=(1.18, 0.76, 0.78))
    C.add_faceted_icosphere(bm, 0.14, (0.0, -1.32, 2.24), MAT_EYE_DARK, subdivisions=1, scale=(1.3, 0.8, 0.8))
    C.add_expressive_eye(bm, (-0.42, -1.00, 2.46), 0.20, MAT_EYE_DARK, MAT_EYE_GLINT)
    C.add_expressive_eye(bm, (0.42, -1.00, 2.46), 0.20, MAT_EYE_DARK, MAT_EYE_GLINT)
    return C.finalize_mesh("PermafrostBear", bm, mats)


def main() -> None:
    C.clear_scene()
    obj = build_permafrost_bear()
    C.validate_asset("PermafrostBear", [obj], tri_cap=2500, pivot_mode="floor")
    C.export_roblox_asset("PermafrostBear", [obj], rigged=False)
    C.setup_studio_render([obj], "PermafrostBear_preview.png", resolution=640, samples=22, cam_azimuth_deg=-34.0, cam_elev_deg=18.0, distance_mult=2.25)
    print("BLENDER_EXPORT_OK: PermafrostBear")


if __name__ == "__main__":
    main()
