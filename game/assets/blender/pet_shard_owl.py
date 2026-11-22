"""Headless Blender builder for ShardOwl (Frostbite Cavern Pet 2, Issue #17)."""

from __future__ import annotations

import sys
from pathlib import Path

import bmesh
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _common as C  # noqa: E402

MAT_OWL_BLUE = 0
MAT_OWL_BELLY = 1
MAT_ICE_CRYSTAL = 2
MAT_GOLD_BEAK = 3
MAT_EYE_GLOW = 4
MAT_EYE_DARK = 5
MAT_EYE_GLINT = 6


def create_materials() -> list[bpy.types.Material]:
    return [
        C.make_material("OwlGlacierBlue", (0.24, 0.56, 0.86), roughness=0.45),
        C.make_material("OwlSnowBelly", (0.90, 0.95, 0.99), roughness=0.52),
        C.make_material("OwlIceShard", (0.64, 0.94, 1.0), roughness=0.14),
        C.make_material("OwlGoldBeak", (0.98, 0.72, 0.16), roughness=0.28, metallic=0.35),
        C.make_material("OwlEyeCyan", (0.28, 0.94, 1.0), roughness=0.10, emission=(0.24, 0.90, 1.0), emission_strength=1.4),
        C.make_material("OwlEyeDark", (0.03, 0.04, 0.07), roughness=0.06),
        C.make_material("OwlEyeGlint", (1.0, 1.0, 1.0), roughness=0.05, emission=(1.0, 1.0, 1.0), emission_strength=1.9),
    ]


def build_shard_owl() -> bpy.types.Object:
    mats = create_materials()
    bm = bmesh.new()
    # Plump round adorable owl body resting on golden talons (Z = 0.25..2.75)
    C.add_lathe_shell(bm, [(0.45, 0.30), (0.92, 0.72), (1.06, 1.38), (0.98, 2.02), (0.76, 2.52), (0.32, 2.74)], MAT_OWL_BLUE, segments=16, scale_xy=(1.04, 0.94), smooth=True)
    C.add_faceted_icosphere(bm, 0.76, (0.0, -0.58, 1.25), MAT_OWL_BELLY, subdivisions=2, scale=(1.0, 0.62, 1.15))
    # Golden owl feet/talons grounded flush on Z = 0.0
    for sx in (-1, 1):
        C.add_faceted_box(bm, (0.48, 0.64, 0.30), (sx * 0.42, -0.14, 0.15), MAT_GOLD_BEAK, 0.05, taper_top=(0.82, 0.82))
    # Huge wise glossy eyes with cyan crystal ring + cute golden hooked beak
    for sx in (-1, 1):
        C.add_faceted_icosphere(bm, 0.34, (sx * 0.42, -0.82, 2.06), MAT_EYE_GLOW, subdivisions=2, scale=(1.0, 0.45, 1.0))
        C.add_expressive_eye(bm, (sx * 0.42, -0.94, 2.06), 0.22, MAT_EYE_DARK, MAT_EYE_GLINT)
        # Faceted ice-crystal ear plumes crowning head
        C.add_crystal_prism(bm, 0.20, 0.78, (sx * 0.68, -0.15, 2.78), MAT_ICE_CRYSTAL, sides=5, rot_deg=(-12, sx * 30, 0))
        # Layered sculpted glacial crystal wings
        wing = [
            ((sx * 0.92, 0.05, 1.65), 0.14, 0.56, (0, sx * 70, 0)),
            ((sx * 1.62, 0.25, 1.52), 0.10, 0.62, (12, sx * 82, sx * -14)),
            ((sx * 2.06, 0.38, 1.28), 0.04, 0.24, (18, sx * 92, sx * -18)),
        ]
        C.add_lofted_tube(bm, wing, MAT_ICE_CRYSTAL, sides=6, smooth=False)
    C.add_crystal_prism(bm, 0.20, 0.46, (0.0, -1.04, 1.82), MAT_GOLD_BEAK, sides=4, rot_deg=(108, 0, 0))
    # Fan tail feathers at rear (+Y)
    for ang in (-22, 0, 22):
        C.add_crystal_prism(bm, 0.18, 0.72, (0.0, 1.05, 0.85), MAT_ICE_CRYSTAL, sides=4, rot_deg=(-65, ang, 0))
    return C.finalize_mesh("ShardOwl", bm, mats)


def main() -> None:
    C.clear_scene()
    obj = build_shard_owl()
    C.validate_asset("ShardOwl", [obj], tri_cap=2500, pivot_mode="floor")
    C.export_roblox_asset("ShardOwl", [obj], rigged=False)
    C.setup_studio_render([obj], "ShardOwl_preview.png", resolution=640, samples=22, cam_azimuth_deg=-32.0, cam_elev_deg=16.0, distance_mult=2.25)
    print("BLENDER_EXPORT_OK: ShardOwl")


if __name__ == "__main__":
    main()
