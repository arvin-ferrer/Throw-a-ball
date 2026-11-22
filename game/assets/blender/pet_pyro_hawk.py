"""Headless Blender builder for PyroHawk (Molten Caldera Pet 2, Issue #17)."""

from __future__ import annotations

import sys
from pathlib import Path

import bmesh
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _common as C  # noqa: E402

MAT_CRIMSON_PLUME = 0
MAT_GOLD_BEAK = 1
MAT_FLAME_GLOW = 2
MAT_OBSIDIAN_TRIM = 3
MAT_EYE_DARK = 4
MAT_EYE_GLINT = 5


def create_materials() -> list[bpy.types.Material]:
    return [
        C.make_material("HawkCrimson", (0.82, 0.14, 0.08), roughness=0.45),
        C.make_material("HawkGoldBeak", (0.98, 0.74, 0.18), roughness=0.22, metallic=0.85),
        C.make_material("HawkFlameGlow", (1.0, 0.48, 0.05), roughness=0.16, emission=(1.0, 0.44, 0.04), emission_strength=2.2),
        C.make_material("HawkObsidian", (0.16, 0.10, 0.10), roughness=0.58),
        C.make_material("HawkEyeDark", (0.03, 0.03, 0.04), roughness=0.06),
        C.make_material("HawkEyeGlint", (1.0, 1.0, 1.0), roughness=0.05, emission=(1.0, 1.0, 1.0), emission_strength=1.9),
    ]


def build_pyro_hawk() -> bpy.types.Object:
    mats = create_materials()
    bm = bmesh.new()
    # Sleek proud chibi phoenix-hawk body on golden talons (Z = 0.25..2.85)
    C.add_lathe_shell(bm, [(0.42, 0.30), (0.86, 0.76), (0.96, 1.44), (0.86, 2.08), (0.68, 2.58), (0.28, 2.80)], MAT_CRIMSON_PLUME, segments=16, scale_xy=(1.0, 0.94), smooth=True)
    C.add_faceted_icosphere(bm, 0.64, (0.0, -0.76, 1.38), MAT_FLAME_GLOW, subdivisions=2, scale=(0.92, 0.50, 1.08))
    # Golden hawk talons flush on Z = 0.0
    for sx in (-1, 1):
        C.add_faceted_box(bm, (0.44, 0.62, 0.30), (sx * 0.38, -0.14, 0.15), MAT_GOLD_BEAK, 0.05, taper_top=(0.82, 0.82))
    # Expressive fierce-cute hawk eyes, gold beak & blazing flame head crest
    C.add_expressive_eye(bm, (-0.38, -0.86, 2.14), 0.19, MAT_EYE_DARK, MAT_EYE_GLINT)
    C.add_expressive_eye(bm, (0.38, -0.86, 2.14), 0.19, MAT_EYE_DARK, MAT_EYE_GLINT)
    C.add_crystal_prism(bm, 0.20, 0.54, (0.0, -1.04, 1.94), MAT_GOLD_BEAK, sides=4, rot_deg=(112, 0, 0))
    # Sweeping fiery crest plumes
    C.add_crystal_prism(bm, 0.20, 0.95, (0.0, 0.05, 3.06), MAT_FLAME_GLOW, sides=5, rot_deg=(-28, 0, 0))
    for sx in (-1, 1):
        C.add_crystal_prism(bm, 0.14, 0.72, (sx * 0.34, 0.12, 2.90), MAT_GOLD_BEAK, sides=4, rot_deg=(-34, sx * 22, 0))
        # Wide spread sculpted crimson + flame-tipped phoenix wings!
        wing_base = [
            ((sx * 0.84, 0.08, 1.72), 0.14, 0.54, (0, sx * 68, 0)),
            ((sx * 1.46, 0.24, 2.00), 0.10, 0.62, (-14, sx * 76, sx * -16)),
            ((sx * 1.96, 0.36, 2.12), 0.05, 0.28, (-18, sx * 86, sx * -20)),
        ]
        C.add_lofted_tube(bm, wing_base, MAT_CRIMSON_PLUME, sides=6, smooth=False)
        C.add_crystal_prism(bm, 0.16, 0.72, (sx * 2.10, 0.42, 2.18), MAT_FLAME_GLOW, sides=4, rot_deg=(-16, sx * 78, 0))
    # Blazing 3-feather tail fan
    for ang in (-24, 0, 24):
        C.add_crystal_prism(bm, 0.18, 0.92, (0.0, 1.08, 0.96), MAT_FLAME_GLOW if ang == 0 else MAT_OBSIDIAN_TRIM, sides=4, rot_deg=(-65, ang, 0))
    return C.finalize_mesh("PyroHawk", bm, mats)


def main() -> None:
    C.clear_scene()
    obj = build_pyro_hawk()
    C.validate_asset("PyroHawk", [obj], tri_cap=2500, pivot_mode="floor")
    C.export_roblox_asset("PyroHawk", [obj], rigged=False)
    C.setup_studio_render([obj], "PyroHawk_preview.png", resolution=640, samples=22, cam_azimuth_deg=-32.0, cam_elev_deg=16.0, distance_mult=2.45)
    print("BLENDER_EXPORT_OK: PyroHawk")


if __name__ == "__main__":
    main()
