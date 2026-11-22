"""Headless Blender builder for ThornStag (Emerald Meadow Pet 3, Issue #13).

Noble stylized woodland fawn-stag (~3.8 studs tall, <2,500 tris, floor pivot Z=0):
sleek lofted chestnut body, mossy emerald neck ruff, graceful hooves, expressive eyes,
and sweeping branching ivory antlers tipped with glowing emerald blossom buds.
"""

from __future__ import annotations

import sys
from pathlib import Path

import bmesh
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _common as C  # noqa: E402

MAT_COAT_CHESTNUT = 0
MAT_COAT_CREAM = 1
MAT_MOSS_RUFF = 2
MAT_ANTLER_IVORY = 3
MAT_BUD_GLOW = 4
MAT_HOOF_DARK = 5
MAT_EYE_DARK = 6
MAT_EYE_GLINT = 7


def create_materials() -> list[bpy.types.Material]:
    return [
        C.make_material("StagChestnut", (0.62, 0.34, 0.16), roughness=0.58),
        C.make_material("StagCream", (0.94, 0.88, 0.76), roughness=0.55),
        C.make_material("StagMossRuff", (0.12, 0.52, 0.20), roughness=0.72),
        C.make_material("StagAntlerIvory", (0.90, 0.84, 0.70), roughness=0.35),
        C.make_material("StagBudGlow", (0.16, 0.94, 0.48), roughness=0.16, emission=(0.16, 0.94, 0.48), emission_strength=2.3),
        C.make_material("StagHoof", (0.10, 0.08, 0.08), roughness=0.40),
        C.make_material("StagEyeDark", (0.03, 0.03, 0.04), roughness=0.06),
        C.make_material("StagEyeGlint", (1.0, 1.0, 1.0), roughness=0.05, emission=(1.0, 1.0, 1.0), emission_strength=1.8),
    ]


def build_thorn_stag() -> bpy.types.Object:
    mats = create_materials()
    bm = bmesh.new()

    # 1. Sleek lofted fawn body + cream belly & cute tufted tail
    body_rings = [
        ((0.0, 1.12, 1.48), 0.38, 0.36, (90, 0, 0)),
        ((0.0, 0.55, 1.48), 0.60, 0.56, (90, 0, 0)),
        ((0.0, -0.22, 1.52), 0.64, 0.60, (90, 0, 0)),
        ((0.0, -0.82, 1.60), 0.48, 0.46, (90, 0, 0)),
    ]
    C.add_lofted_tube(bm, body_rings, MAT_COAT_CHESTNUT, sides=10, smooth=True)
    C.add_faceted_icosphere(bm, 0.42, (0.0, -0.68, 1.52), MAT_COAT_CREAM, subdivisions=2, scale=(0.9, 0.7, 1.05))
    C.add_faceted_icosphere(bm, 0.24, (0.0, 1.24, 1.66), MAT_COAT_CREAM, subdivisions=1, scale=(0.8, 1.1, 1.2))

    # 2. Four graceful tapered legs with hooves flush on Z = 0.0
    for x, y in [(-0.38, -0.52), (0.38, -0.52), (-0.38, 0.68), (0.38, 0.68)]:
        leg_rings = [
            ((x, y, 1.32), 0.20, 0.22, (0, 0, 0)),
            ((x, y, 0.72), 0.14, 0.15, (0, 0, 0)),
            ((x, y, 0.24), 0.12, 0.13, (0, 0, 0)),
        ]
        C.add_lofted_tube(bm, leg_rings, MAT_COAT_CHESTNUT, sides=8, smooth=True)
        C.add_faceted_box(bm, (0.26, 0.32, 0.26), (x, y - 0.02, 0.13), MAT_HOOF_DARK, 0.03, taper_top=(0.82, 0.82))

    # 3. Proud arched neck + lush mossy shoulder ruff
    neck_rings = [
        ((0.0, -0.62, 1.64), 0.42, 0.42, (20, 0, 0)),
        ((0.0, -0.82, 2.08), 0.32, 0.32, (12, 0, 0)),
        ((0.0, -0.92, 2.48), 0.28, 0.28, (5, 0, 0)),
    ]
    C.add_lofted_tube(bm, neck_rings, MAT_COAT_CHESTNUT, sides=10, smooth=True)
    for ang_deg, sc in [(-45, 0.42), (0, 0.46), (45, 0.42), (180, 0.44)]:
        rad = ang_deg * 3.14159 / 180.0
        C.add_faceted_icosphere(bm, sc, (0.48 * (rad and 1.0 or 0.0) * (1 if ang_deg > 0 else (-1 if ang_deg < 0 else 0)), -0.68 + (0.35 if ang_deg == 180 else -0.25), 1.78), MAT_MOSS_RUFF, subdivisions=1, scale=(1.1, 0.9, 0.65), noise_amp=0.14, seed=abs(ang_deg) + 3)

    # 4. Noble stylized stag head, sleek snout, ears & glossy eyes
    head_rings = [
        ((0.0, -0.68, 2.58), 0.46, 0.44, (90, 0, 0)),
        ((0.0, -1.10, 2.52), 0.44, 0.42, (95, 0, 0)),
        ((0.0, -1.55, 2.38), 0.26, 0.24, (100, 0, 0)),
        ((0.0, -1.78, 2.32), 0.18, 0.16, (100, 0, 0)),
    ]
    C.add_lofted_tube(bm, head_rings, MAT_COAT_CHESTNUT, sides=10, smooth=True)
    C.add_faceted_icosphere(bm, 0.12, (0.0, -1.82, 2.38), MAT_HOOF_DARK, subdivisions=1, scale=(1.1, 0.8, 0.8))
    C.add_expressive_eye(bm, (-0.36, -1.18, 2.66), 0.16, MAT_EYE_DARK, MAT_EYE_GLINT)
    C.add_expressive_eye(bm, (0.36, -1.18, 2.66), 0.16, MAT_EYE_DARK, MAT_EYE_GLINT)

    # 5. Sweeping branching ivory antlers tipped with glowing emerald crystal buds!
    for sx in (-1, 1):
        # Sleek leaf-like deer ears
        ear_rings = [
            ((sx * 0.36, -0.78, 2.82), 0.14, 0.08, (0, sx * 42, 0)),
            ((sx * 0.72, -0.72, 3.04), 0.12, 0.06, (0, sx * 54, 0)),
            ((sx * 0.92, -0.68, 3.12), 0.03, 0.02, (0, sx * 60, 0)),
        ]
        C.add_lofted_tube(bm, ear_rings, MAT_COAT_CHESTNUT, sides=6, smooth=True)
        # Main curved antler beam
        main_beam = [
            ((sx * 0.24, -0.92, 2.88), 0.09, 0.09, (0, sx * 22, 0)),
            ((sx * 0.56, -0.82, 3.28), 0.08, 0.08, (-12, sx * 34, 0)),
            ((sx * 0.92, -0.70, 3.68), 0.06, 0.06, (-18, sx * 24, 0)),
            ((sx * 1.02, -0.62, 4.02), 0.025, 0.025, (-12, sx * 10, 0)),
        ]
        C.add_lofted_tube(bm, main_beam, MAT_ANTLER_IVORY, sides=6, smooth=True)
        # Front brow tine
        tine = [
            ((sx * 0.56, -0.82, 3.28), 0.065, 0.065, (35, sx * 14, 0)),
            ((sx * 0.64, -1.18, 3.58), 0.045, 0.045, (28, sx * 10, 0)),
            ((sx * 0.62, -1.32, 3.78), 0.02, 0.02, (15, sx * 6, 0)),
        ]
        C.add_lofted_tube(bm, tine, MAT_ANTLER_IVORY, sides=6, smooth=True)
        # Glowing emerald crystal buds crowning antler tips
        C.add_crystal_prism(bm, 0.11, 0.28, (sx * 1.04, -0.60, 4.08), MAT_BUD_GLOW, sides=5, rot_deg=(-10, sx * 14, 0))
        C.add_crystal_prism(bm, 0.08, 0.22, (sx * 0.62, -1.36, 3.82), MAT_BUD_GLOW, sides=5, rot_deg=(24, sx * 8, 0))

    return C.finalize_mesh("ThornStag", bm, mats)


def main() -> None:
    C.clear_scene()
    obj = build_thorn_stag()
    C.validate_asset("ThornStag", [obj], tri_cap=2500, pivot_mode="floor")
    C.export_roblox_asset("ThornStag", [obj], rigged=False)
    C.setup_studio_render([obj], "ThornStag_preview.png", resolution=640, samples=22, cam_azimuth_deg=-36.0, cam_elev_deg=16.0, distance_mult=2.25)
    print("BLENDER_EXPORT_OK: ThornStag")


if __name__ == "__main__":
    main()
