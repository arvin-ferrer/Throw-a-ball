"""Headless Blender builder for PebbleCub (Emerald Meadow Pet 1, Issue #13).

Stout chibi stone-bear cub (~2.9 studs tall, <2,500 tris, floor pivot Z=0):
rounded pebble-stone head & cub body, beveled boulder shoulder/back plates echoing
MossbackGolem, emerald moss crest tuft, chunky knockback paws, and expressive eyes.
"""

from __future__ import annotations

import sys
from pathlib import Path

import bmesh
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _common as C  # noqa: E402

MAT_STONE_CUB = 0
MAT_STONE_DARK = 1
MAT_STONE_BELLY = 2
MAT_MOSS_BRIGHT = 3
MAT_JADE_GLOW = 4
MAT_EYE_DARK = 5
MAT_EYE_GLINT = 6


def create_materials() -> list[bpy.types.Material]:
    return [
        C.make_material("CubStoneMid", (0.44, 0.48, 0.46), roughness=0.72),
        C.make_material("CubStoneDark", (0.24, 0.27, 0.26), roughness=0.80),
        C.make_material("CubStoneBelly", (0.68, 0.70, 0.66), roughness=0.66),
        C.make_material("CubMossBright", (0.14, 0.56, 0.20), roughness=0.76),
        C.make_material("CubJadeGlow", (0.14, 0.94, 0.46), roughness=0.16, emission=(0.14, 0.94, 0.46), emission_strength=2.2),
        C.make_material("CubEyeDark", (0.03, 0.04, 0.04), roughness=0.06),
        C.make_material("CubEyeGlint", (1.0, 1.0, 1.0), roughness=0.05, emission=(1.0, 1.0, 1.0), emission_strength=1.8),
    ]


def build_pebble_cub() -> bpy.types.Object:
    mats = create_materials()
    bm = bmesh.new()

    # 1. Plump cub torso (Z = 0.25..1.65) + lighter belly slab
    body_profile = [
        (0.60, 0.28),
        (0.95, 0.65),
        (0.98, 1.15),
        (0.78, 1.55),
        (0.45, 1.72),
    ]
    C.add_lathe_shell(bm, body_profile, MAT_STONE_CUB, segments=14, center=(0.0, 0.10, 0.0), scale_xy=(1.04, 0.96), smooth=True)
    C.add_faceted_icosphere(bm, 0.62, (0.0, -0.58, 0.96), MAT_STONE_BELLY, subdivisions=2, scale=(1.0, 0.52, 1.05))
    # Tiny glowing jade rune gem on chest (links cub visually to Mossback Golem!)
    C.add_crystal_prism(bm, 0.16, 0.34, (0.0, -0.92, 1.08), MAT_JADE_GLOW, sides=5, rot_deg=(80, 0, 0))

    # 2. Chunky heavy knockback paws grounded flush on Z = 0.0
    for sx in (-1, 1):
        # Hind feet
        C.add_faceted_box(bm, (0.64, 0.82, 0.56), (sx * 0.62, 0.24, 0.28), MAT_STONE_DARK, 0.08, taper_top=(0.86, 0.86))
        # Oversized armored front knockback gauntlets/paws
        C.add_faceted_box(bm, (0.62, 0.68, 0.92), (sx * 0.98, -0.34, 0.62), MAT_STONE_DARK, 0.10, rot_deg=(12, sx * -10, 0))
        C.add_faceted_box(bm, (0.58, 0.64, 0.42), (sx * 0.98, -0.46, 0.21), MAT_STONE_BELLY, 0.06)

    # 3. Layered beveled boulder armor plates & moss cape on back
    C.add_faceted_icosphere(bm, 0.68, (0.0, 0.72, 1.38), MAT_STONE_DARK, subdivisions=1, scale=(1.25, 0.85, 0.85), noise_amp=0.12, seed=4)
    C.add_faceted_icosphere(bm, 0.58, (0.0, 0.65, 1.68), MAT_MOSS_BRIGHT, subdivisions=1, scale=(1.35, 0.95, 0.52), noise_amp=0.14, seed=6)
    # Little round pebble tail
    C.add_faceted_icosphere(bm, 0.28, (0.0, 1.04, 0.65), MAT_STONE_BELLY, subdivisions=1)

    # 4. Big adorable chibi bear-cub head (Z = 1.50..2.85)
    head_profile = [
        (0.55, 1.52),
        (0.88, 1.82),
        (0.94, 2.22),
        (0.80, 2.62),
        (0.42, 2.84),
    ]
    C.add_lathe_shell(bm, head_profile, MAT_STONE_CUB, segments=14, center=(0.0, -0.18, 0.0), scale_xy=(1.08, 0.96), smooth=True)
    # Round pebble ears + moss crown tuft
    for sx in (-1, 1):
        C.add_faceted_icosphere(bm, 0.34, (sx * 0.78, -0.14, 2.74), MAT_STONE_DARK, subdivisions=1, scale=(1.0, 0.72, 1.0))
        C.add_faceted_icosphere(bm, 0.18, (sx * 0.76, -0.32, 2.74), MAT_STONE_BELLY, subdivisions=1, scale=(1.0, 0.5, 1.0))
    C.add_faceted_icosphere(bm, 0.42, (0.0, -0.12, 2.86), MAT_MOSS_BRIGHT, subdivisions=1, scale=(1.2, 0.95, 0.55), noise_amp=0.15, seed=9)
    # Snout, nose & glossy chibi eyes
    C.add_faceted_icosphere(bm, 0.38, (0.0, -0.98, 2.02), MAT_STONE_BELLY, subdivisions=2, scale=(1.18, 0.76, 0.78))
    C.add_faceted_icosphere(bm, 0.14, (0.0, -1.26, 2.14), MAT_EYE_DARK, subdivisions=1, scale=(1.3, 0.8, 0.8))
    C.add_expressive_eye(bm, (-0.42, -0.96, 2.34), 0.20, MAT_EYE_DARK, MAT_EYE_GLINT)
    C.add_expressive_eye(bm, (0.42, -0.96, 2.34), 0.20, MAT_EYE_DARK, MAT_EYE_GLINT)

    return C.finalize_mesh("PebbleCub", bm, mats)


def main() -> None:
    C.clear_scene()
    obj = build_pebble_cub()
    C.validate_asset("PebbleCub", [obj], tri_cap=2500, pivot_mode="floor")
    C.export_roblox_asset("PebbleCub", [obj], rigged=False)
    C.setup_studio_render([obj], "PebbleCub_preview.png", resolution=640, samples=22, cam_azimuth_deg=-34.0, cam_elev_deg=18.0, distance_mult=2.25)
    print("BLENDER_EXPORT_OK: PebbleCub")


if __name__ == "__main__":
    main()
