"""Headless Blender builder for MossbackBoulder (Mossback Golem rolling projectile).

Builds a chunky faceted moss-and-crystal stone boulder (6.4 studs diameter,
<1,000 tris, geometric center pivot at (0,0,0) for wobble-free rolling spin).
"""

from __future__ import annotations

import sys
from pathlib import Path

import bmesh
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _common as C  # noqa: E402

MAT_STONE_DARK = 0
MAT_STONE_MID = 1
MAT_MOSS_DEEP = 2
MAT_MOSS_BRIGHT = 3
MAT_JADE_GLOW = 4


def create_materials() -> list[bpy.types.Material]:
    return [
        C.make_material("BoulderStoneDark", (0.15, 0.17, 0.16), roughness=0.86),
        C.make_material("BoulderStoneMid", (0.31, 0.34, 0.31), roughness=0.80),
        C.make_material("BoulderMossDeep", (0.06, 0.26, 0.11), roughness=0.88),
        C.make_material("BoulderMossBright", (0.16, 0.54, 0.20), roughness=0.80),
        C.make_material(
            "BoulderJadeGlow",
            (0.18, 0.96, 0.52),
            roughness=0.18,
            emission=(0.20, 1.0, 0.55),
            emission_strength=4.0,
        ),
    ]


def build_boulder() -> bpy.types.Object:
    mats = create_materials()
    bm = bmesh.new()

    # Main craggy faceted rock core (~6.0 studs diameter)
    C.add_faceted_icosphere(
        bm, radius=2.85, center=(0, 0, 0), mat_idx=MAT_STONE_MID,
        subdivisions=2, noise_amp=0.14, seed=7,
    )
    # Recessed dark basalt slabs for rock-face tonal contrast
    slabs = [
        (1.45, (1.55, -1.2, 0.8), (1.0, 0.85, 0.75), 11),
        (1.35, (-1.6, 1.15, -0.7), (0.95, 0.9, 0.8), 13),
        (1.30, (0.3, 1.65, 1.25), (1.1, 0.75, 0.85), 17),
        (1.35, (-0.5, -1.6, -1.2), (1.0, 0.8, 0.8), 19),
    ]
    for r, pos, sc, sd in slabs:
        C.add_faceted_icosphere(bm, r, pos, MAT_STONE_DARK, subdivisions=1, scale=sc, noise_amp=0.12, seed=sd)

    # Bold high-contrast moss patches across opposite faces so rolling spin reads cleanly
    moss = [
        (1.25, (0.2, -1.9, 1.4), (1.2, 0.65, 0.85), MAT_MOSS_BRIGHT, 21),
        (1.20, (-1.9, -0.6, 1.3), (0.75, 1.15, 0.8), MAT_MOSS_DEEP, 23),
        (1.25, (1.85, 0.9, -1.1), (0.8, 1.1, 0.85), MAT_MOSS_BRIGHT, 25),
        (1.15, (-0.4, 1.95, -1.2), (1.1, 0.65, 0.85), MAT_MOSS_DEEP, 27),
    ]
    for r, pos, sc, mat, sd in moss:
        C.add_faceted_icosphere(bm, r, pos, mat, subdivisions=1, scale=sc, noise_amp=0.15, seed=sd)

    # Glowing emerald crystal shards jutting out to ~3.25 stud radius
    shards = [
        ((0.0, 0.0, 2.75), (8, -10, 0), 0.48, 1.25),
        ((0.0, 0.0, -2.75), (172, 12, 0), 0.45, 1.20),
        ((2.70, -0.5, 0.3), (12, 82, 0), 0.46, 1.20),
        ((-2.70, 0.4, -0.3), (-14, -84, 0), 0.46, 1.20),
        ((0.4, -2.68, -0.4), (98, 10, 0), 0.44, 1.15),
        ((-0.4, 2.68, 0.4), (-96, -8, 0), 0.44, 1.15),
    ]
    for pos, rot, rad, h in shards:
        C.add_crystal_prism(bm, rad, h, pos, MAT_JADE_GLOW, sides=5, rot_deg=rot)

    return C.finalize_mesh("MossbackBoulder", bm, mats)


def main() -> None:
    C.clear_scene()
    obj = build_boulder()
    C.validate_asset("MossbackBoulder", [obj], tri_cap=1000, pivot_mode="center")
    C.export_roblox_asset("MossbackBoulder", [obj], rigged=False)
    C.setup_studio_render(
        [obj],
        "MossbackBoulder_preview.png",
        resolution=640,
        samples=20,
        cam_azimuth_deg=-35.0,
        cam_elev_deg=20.0,
        distance_mult=2.2,
    )
    print("BLENDER_EXPORT_OK: MossbackBoulder")


if __name__ == "__main__":
    main()
