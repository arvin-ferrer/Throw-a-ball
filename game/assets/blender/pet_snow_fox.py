"""Headless Blender builder for SnowFox (Frostbite Cavern Pet 1, Issue #17)."""

from __future__ import annotations

import sys
from pathlib import Path

import bmesh
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _common as C  # noqa: E402

MAT_FUR_WHITE = 0
MAT_FROST_TIP = 1
MAT_SCARF_BLUE = 2
MAT_EYE_DARK = 3
MAT_EYE_GLINT = 4
MAT_NOSE_DARK = 5


def create_materials() -> list[bpy.types.Material]:
    return [
        C.make_material("FoxSnowWhite", (0.94, 0.96, 0.99), roughness=0.52),
        C.make_material("FoxIceTip", (0.44, 0.86, 1.0), roughness=0.22, emission=(0.30, 0.82, 1.0), emission_strength=0.8),
        C.make_material("FoxFrostRuff", (0.20, 0.60, 0.92), roughness=0.45),
        C.make_material("FoxEyeDark", (0.03, 0.04, 0.07), roughness=0.06),
        C.make_material("FoxEyeGlint", (1.0, 1.0, 1.0), roughness=0.05, emission=(1.0, 1.0, 1.0), emission_strength=1.8),
        C.make_material("FoxNose", (0.08, 0.12, 0.18), roughness=0.25),
    ]


def build_snow_fox() -> bpy.types.Object:
    mats = create_materials()
    bm = bmesh.new()
    # Sleek cute chibi fox body + fluffy chest ruff
    C.add_lofted_tube(bm, [((0, 0.92, 0.98), 0.42, 0.40, (90, 0, 0)), ((0, 0.35, 1.02), 0.62, 0.56, (90, 0, 0)), ((0, -0.35, 1.08), 0.66, 0.60, (90, 0, 0)), ((0, -0.78, 1.15), 0.48, 0.46, (90, 0, 0))], MAT_FUR_WHITE, sides=10, smooth=True)
    C.add_faceted_icosphere(bm, 0.52, (0.0, -0.68, 1.26), MAT_SCARF_BLUE, subdivisions=1, scale=(1.15, 0.85, 0.72))
    # 4 dainty frosted paws flush on Z = 0.0
    for x, y in [(-0.36, -0.45), (0.36, -0.45), (-0.36, 0.58), (0.36, 0.58)]:
        C.add_lofted_tube(bm, [((x, y, 0.82), 0.20, 0.20, (0, 0, 0)), ((x, y, 0.28), 0.16, 0.18, (0, 0, 0)), ((x, y - 0.03, 0.0), 0.18, 0.22, (0, 0, 0))], MAT_FUR_WHITE, sides=8, smooth=True)
        C.add_faceted_icosphere(bm, 0.17, (x, y - 0.10, 0.12), MAT_FROST_TIP, subdivisions=1, scale=(1.0, 1.0, 0.65))
    # Oversized adorable chibi fox head + pointed snout + glossy eyes
    C.add_lathe_shell(bm, [(0.42, 1.48), (0.78, 1.76), (0.84, 2.12), (0.72, 2.50), (0.42, 2.74), (0.12, 2.82)], MAT_FUR_WHITE, segments=16, center=(0, -0.56, 0), scale_xy=(1.08, 0.96), smooth=True)
    C.add_lofted_tube(bm, [((0, -1.18, 1.98), 0.36, 0.28, (92, 0, 0)), ((0, -1.66, 1.92), 0.16, 0.14, (95, 0, 0))], MAT_FUR_WHITE, sides=8, smooth=True)
    C.add_faceted_icosphere(bm, 0.11, (0.0, -1.72, 1.95), MAT_NOSE_DARK, subdivisions=1)
    C.add_expressive_eye(bm, (-0.38, -1.28, 2.24), 0.20, MAT_EYE_DARK, MAT_EYE_GLINT)
    C.add_expressive_eye(bm, (0.38, -1.28, 2.24), 0.20, MAT_EYE_DARK, MAT_EYE_GLINT)
    # Huge iconic pointed fox ears with glowing frost tips!
    for sx in (-1, 1):
        C.add_lofted_tube(bm, [((sx * 0.48, -0.52, 2.55), 0.26, 0.16, (0, sx * 22, 0)), ((sx * 0.78, -0.48, 3.12), 0.20, 0.11, (0, sx * 26, 0)), ((sx * 0.96, -0.44, 3.55), 0.04, 0.03, (0, sx * 28, 0))], MAT_FUR_WHITE, sides=6, smooth=True)
        C.add_crystal_prism(bm, 0.12, 0.34, (sx * 0.96, -0.44, 3.48), MAT_FROST_TIP, sides=4, rot_deg=(0, sx * 26, 0))
    # Giant lush curved fox tail with frost-cyan plume tip!
    C.add_lofted_tube(bm, [((0, 0.88, 1.08), 0.22, 0.22, (72, 0, 0)), ((0, 1.48, 1.42), 0.48, 0.44, (45, 0, 0)), ((0, 1.72, 2.08), 0.42, 0.38, (12, 0, 0)), ((0, 1.48, 2.62), 0.12, 0.12, (-22, 0, 0))], MAT_FUR_WHITE, sides=10, smooth=True)
    C.add_faceted_icosphere(bm, 0.34, (0.0, 1.56, 2.48), MAT_FROST_TIP, subdivisions=1, scale=(0.95, 0.95, 1.35))
    return C.finalize_mesh("SnowFox", bm, mats)


def main() -> None:
    C.clear_scene()
    obj = build_snow_fox()
    C.validate_asset("SnowFox", [obj], tri_cap=2500, pivot_mode="floor")
    C.export_roblox_asset("SnowFox", [obj], rigged=False)
    C.setup_studio_render([obj], "SnowFox_preview.png", resolution=640, samples=22, cam_azimuth_deg=-36.0, cam_elev_deg=18.0, distance_mult=2.25)
    print("BLENDER_EXPORT_OK: SnowFox")


if __name__ == "__main__":
    main()
