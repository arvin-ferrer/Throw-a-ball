"""Headless Blender builder for AshLizard (Molten Caldera Pet 1, Issue #17)."""

from __future__ import annotations

import sys
from pathlib import Path

import bmesh
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _common as C  # noqa: E402

MAT_ASH_SKIN = 0
MAT_ASH_BELLY = 1
MAT_EMBER_GLOW = 2
MAT_EYE_DARK = 3
MAT_EYE_GLINT = 4


def create_materials() -> list[bpy.types.Material]:
    return [
        C.make_material("LizardCharcoal", (0.20, 0.16, 0.18), roughness=0.58),
        C.make_material("LizardWarmBelly", (0.68, 0.34, 0.18), roughness=0.52),
        C.make_material("LizardEmberFlame", (1.0, 0.38, 0.04), roughness=0.18, emission=(1.0, 0.36, 0.04), emission_strength=2.3),
        C.make_material("LizardEyeDark", (0.03, 0.03, 0.04), roughness=0.06),
        C.make_material("LizardEyeGlint", (1.0, 1.0, 1.0), roughness=0.05, emission=(1.0, 1.0, 1.0), emission_strength=1.8),
    ]


def build_ash_lizard() -> bpy.types.Object:
    mats = create_materials()
    bm = bmesh.new()
    # Chunky adorable salamander body + warm terracotta belly
    C.add_lofted_tube(bm, [((0, 0.96, 0.72), 0.38, 0.34, (90, 0, 0)), ((0, 0.35, 0.80), 0.66, 0.56, (90, 0, 0)), ((0, -0.35, 0.88), 0.68, 0.58, (90, 0, 0)), ((0, -0.82, 0.98), 0.52, 0.46, (90, 0, 0))], MAT_ASH_SKIN, sides=10, smooth=True)
    C.add_faceted_icosphere(bm, 0.54, (0.0, -0.15, 0.65), MAT_ASH_BELLY, subdivisions=1, scale=(1.0, 1.35, 0.65))
    # Glowing ember spots along dorsal back
    for y_p, r in [(0.55, 0.18), (0.05, 0.22), (-0.42, 0.20)]:
        C.add_faceted_icosphere(bm, r, (0.0, y_p, 1.38), MAT_EMBER_GLOW, subdivisions=1, scale=(1.1, 1.1, 0.55))
    # 4 splayed gecko legs flush on Z = 0.0
    for x, y in [(-0.56, -0.45), (0.56, -0.45), (-0.54, 0.58), (0.54, 0.58)]:
        C.add_lofted_tube(bm, [((x * 0.85, y, 0.65), 0.22, 0.22, (0, 0, 0)), ((x, y, 0.24), 0.18, 0.18, (0, 0, 0)), ((x * 1.05, y - 0.04, 0.0), 0.22, 0.26, (0, 0, 0))], MAT_ASH_SKIN, sides=8, smooth=True)
    # Big cute salamander head, glossy wide eyes & glowing dorsal head crest
    C.add_lathe_shell(bm, [(0.42, 0.88), (0.76, 1.18), (0.82, 1.54), (0.68, 1.88), (0.36, 2.08)], MAT_ASH_SKIN, segments=14, center=(0, -0.88, 0), scale_xy=(1.12, 1.05), smooth=True)
    C.add_expressive_eye(bm, (-0.44, -1.56, 1.56), 0.22, MAT_EYE_DARK, MAT_EYE_GLINT)
    C.add_expressive_eye(bm, (0.44, -1.56, 1.56), 0.22, MAT_EYE_DARK, MAT_EYE_GLINT)
    C.add_crystal_prism(bm, 0.16, 0.45, (0.0, -0.78, 2.16), MAT_EMBER_GLOW, sides=5, rot_deg=(-18, 0, 0))
    # Curled tail crowned with a glowing salamander flame tip!
    C.add_lofted_tube(bm, [((0, 0.92, 0.72), 0.30, 0.28, (80, 0, 0)), ((0.22, 1.52, 0.96), 0.22, 0.22, (52, 12, 0)), ((0.38, 1.82, 1.48), 0.12, 0.12, (16, 18, 0))], MAT_ASH_SKIN, sides=8, smooth=True)
    C.add_crystal_prism(bm, 0.28, 0.72, (0.42, 1.86, 1.82), MAT_EMBER_GLOW, sides=5, rot_deg=(-12, 10, 0))
    return C.finalize_mesh("AshLizard", bm, mats)


def main() -> None:
    C.clear_scene()
    obj = build_ash_lizard()
    C.validate_asset("AshLizard", [obj], tri_cap=2500, pivot_mode="floor")
    C.export_roblox_asset("AshLizard", [obj], rigged=False)
    C.setup_studio_render([obj], "AshLizard_preview.png", resolution=640, samples=22, cam_azimuth_deg=-36.0, cam_elev_deg=18.0, distance_mult=2.25)
    print("BLENDER_EXPORT_OK: AshLizard")


if __name__ == "__main__":
    main()
