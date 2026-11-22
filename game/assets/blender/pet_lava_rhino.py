"""Headless Blender builder for LavaRhino (Molten Caldera Pet 3, Issue #17)."""

from __future__ import annotations

import sys
from pathlib import Path

import bmesh
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _common as C  # noqa: E402

MAT_BASALT_HIDE = 0
MAT_OBSIDIAN_ARMOR = 1
MAT_LAVA_GLOW = 2
MAT_HORN_IVORY = 3
MAT_EYE_DARK = 4
MAT_EYE_GLINT = 5


def create_materials() -> list[bpy.types.Material]:
    return [
        C.make_material("RhinoBasalt", (0.24, 0.19, 0.20), roughness=0.72),
        C.make_material("RhinoObsidian", (0.11, 0.08, 0.10), roughness=0.60, metallic=0.14),
        C.make_material("RhinoLavaGlow", (1.0, 0.36, 0.03), roughness=0.18, emission=(1.0, 0.34, 0.03), emission_strength=2.4),
        C.make_material("RhinoHornIvory", (0.94, 0.86, 0.72), roughness=0.28),
        C.make_material("RhinoEyeDark", (0.03, 0.03, 0.04), roughness=0.06),
        C.make_material("RhinoEyeGlint", (1.0, 1.0, 1.0), roughness=0.05, emission=(1.0, 1.0, 1.0), emission_strength=1.8),
    ]


def build_lava_rhino() -> bpy.types.Object:
    mats = create_materials()
    bm = bmesh.new()
    # Stocky chibi armored rhino barrel torso
    C.add_lofted_tube(bm, [((0, 1.18, 1.24), 0.56, 0.52, (90, 0, 0)), ((0, 0.55, 1.28), 0.96, 0.88, (90, 0, 0)), ((0, -0.35, 1.35), 1.04, 0.96, (90, 0, 0)), ((0, -0.95, 1.38), 0.82, 0.78, (90, 0, 0))], MAT_BASALT_HIDE, sides=10, smooth=True)
    # Beveled obsidian dorsal armor saddle + glowing lava crack seam
    C.add_faceted_box(bm, (1.58, 1.35, 0.42), (0.0, 0.08, 2.22), MAT_OBSIDIAN_ARMOR, 0.08)
    C.add_faceted_box(bm, (0.36, 1.28, 0.18), (0.0, 0.08, 2.42), MAT_LAVA_GLOW, 0.03)
    # Four heavy armored rhino feet flush on Z = 0.0
    for x, y in [(-0.66, -0.58), (0.66, -0.58), (-0.64, 0.74), (0.64, 0.74)]:
        C.add_faceted_box(bm, (0.58, 0.62, 0.98), (x, y, 0.56), MAT_BASALT_HIDE, 0.08, taper_top=(0.9, 0.9))
        C.add_faceted_box(bm, (0.62, 0.66, 0.30), (x, y, 0.15), MAT_OBSIDIAN_ARMOR, 0.04)
    # Big armored chibi rhino head, flared ears, glowing eyes & sweeping fiery ivory nose horn!
    C.add_lofted_tube(bm, [((0, -0.82, 1.54), 0.82, 0.76, (90, 0, 0)), ((0, -1.45, 1.50), 0.78, 0.70, (96, 0, 0)), ((0, -1.96, 1.38), 0.56, 0.50, (100, 0, 0))], MAT_BASALT_HIDE, sides=10, smooth=True)
    C.add_faceted_box(bm, (1.28, 0.52, 0.34), (0.0, -1.16, 2.18), MAT_OBSIDIAN_ARMOR, 0.06, rot_deg=(10, 0, 0))
    for sx in (-1, 1):
        C.add_expressive_eye(bm, (sx * 0.68, -1.62, 1.76), 0.19, MAT_EYE_DARK, MAT_EYE_GLINT)
        C.add_crystal_prism(bm, 0.18, 0.54, (sx * 0.68, -1.02, 2.34), MAT_BASALT_HIDE, sides=5, rot_deg=(-12, sx * 24, 0))
    # Iconic sweeping curved front rhino horn + smaller glowing rear horn!
    C.add_lofted_tube(bm, [((0, -1.92, 1.62), 0.28, 0.28, (25, 0, 0)), ((0, -2.14, 2.12), 0.18, 0.18, (8, 0, 0)), ((0, -2.06, 2.66), 0.04, 0.04, (-16, 0, 0))], MAT_HORN_IVORY, sides=8, smooth=True)
    C.add_crystal_prism(bm, 0.16, 0.54, (0.0, -1.56, 2.18), MAT_LAVA_GLOW, sides=5, rot_deg=(12, 0, 0))
    return C.finalize_mesh("LavaRhino", bm, mats)


def main() -> None:
    C.clear_scene()
    obj = build_lava_rhino()
    C.validate_asset("LavaRhino", [obj], tri_cap=2500, pivot_mode="floor")
    C.export_roblox_asset("LavaRhino", [obj], rigged=False)
    C.setup_studio_render([obj], "LavaRhino_preview.png", resolution=640, samples=22, cam_azimuth_deg=-38.0, cam_elev_deg=16.0, distance_mult=2.25)
    print("BLENDER_EXPORT_OK: LavaRhino")


if __name__ == "__main__":
    main()
