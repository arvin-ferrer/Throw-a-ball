"""Headless Blender builder for TrainingPup (Minute-0 Starter Pet, Issue #13).

Heroic chibi athletic hound pup (~2.8 studs tall, <2,500 tris, floor pivot Z=0):
oversized expressive head, floppy lofted chocolate ears, bright red training bandana
with gold ball-tag medal, chunky paws, and a wagging curled tail.
"""

from __future__ import annotations

import sys
from pathlib import Path

import bmesh
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _common as C  # noqa: E402

MAT_FUR_HONEY = 0
MAT_FUR_CREAM = 1
MAT_EAR_CHOCO = 2
MAT_BANDANA_RED = 3
MAT_GOLD_TAG = 4
MAT_EYE_DARK = 5
MAT_EYE_GLINT = 6
MAT_PAW_PAD = 7


def create_materials() -> list[bpy.types.Material]:
    return [
        C.make_material("PupHoneyFur", (0.86, 0.56, 0.24), roughness=0.58),
        C.make_material("PupCreamFur", (0.96, 0.90, 0.78), roughness=0.55),
        C.make_material("PupChocoEar", (0.34, 0.18, 0.10), roughness=0.62),
        C.make_material("PupBandanaRed", (0.88, 0.14, 0.16), roughness=0.45),
        C.make_material("PupGoldTag", (0.98, 0.76, 0.22), roughness=0.22, metallic=0.92),
        C.make_material("PupEyeDark", (0.03, 0.03, 0.04), roughness=0.06),
        C.make_material("PupEyeGlint", (1.0, 1.0, 1.0), roughness=0.05, emission=(1.0, 1.0, 1.0), emission_strength=1.8),
        C.make_material("PupNoseDark", (0.12, 0.07, 0.06), roughness=0.25),
    ]


def build_training_pup() -> bpy.types.Object:
    mats = create_materials()
    bm = bmesh.new()

    # 1. Chubby athletic puppy torso (Z = 0.55..1.65) + soft cream chest patch
    body_rings = [
        ((0.0, 0.95, 1.02), 0.45, 0.42, (90, 0, 0)),
        ((0.0, 0.45, 1.05), 0.68, 0.62, (90, 0, 0)),
        ((0.0, -0.25, 1.10), 0.72, 0.66, (90, 0, 0)),
        ((0.0, -0.78, 1.15), 0.52, 0.50, (90, 0, 0)),
    ]
    C.add_lofted_tube(bm, body_rings, MAT_FUR_HONEY, sides=12, smooth=True)
    C.add_faceted_icosphere(bm, 0.48, (0.0, -0.58, 1.02), MAT_FUR_CREAM, subdivisions=2, scale=(0.92, 0.68, 0.95))

    # 2. Four cute sturdy paws resting flush on Z = 0.0
    for x, y in [(-0.42, -0.48), (0.42, -0.48), (-0.42, 0.58), (0.42, 0.58)]:
        leg_rings = [
            ((x, y, 0.85), 0.24, 0.24, (0, 0, 0)),
            ((x, y, 0.32), 0.20, 0.22, (0, 0, 0)),
            ((x, y - 0.04, 0.00), 0.22, 0.26, (0, 0, 0)),
        ]
        C.add_lofted_tube(bm, leg_rings, MAT_FUR_HONEY, sides=8, smooth=True)
        C.add_faceted_icosphere(bm, 0.20, (x, y - 0.14, 0.14), MAT_FUR_CREAM, subdivisions=1, scale=(1.0, 1.0, 0.68))

    # 3. Sporty red training bandana collar + gold miniature ball tag on chest
    before = len(bm.verts)
    C.add_closed_ring(bm, radius=0.56, radial_thickness=0.14, axial_width=0.22, mat_idx=MAT_BANDANA_RED, rot_deg=(18, 0, 0), segments=16)
    bmesh.ops.translate(bm, vec=(0, -0.48, 1.48), verts=list(bm.verts)[before:])
    C.add_crystal_prism(bm, 0.34, 0.52, (0.0, -0.96, 1.24), MAT_BANDANA_RED, sides=3, rot_deg=(165, 0, 0))
    C.add_faceted_icosphere(bm, 0.15, (0.0, -1.04, 1.38), MAT_GOLD_TAG, subdivisions=1)

    # 4. Oversized chibi-heroic head (~50% of silhouette, Z = 1.45..2.85)
    head_profile = [
        (0.45, 1.48),
        (0.76, 1.72),
        (0.84, 2.08),
        (0.76, 2.48),
        (0.48, 2.74),
        (0.14, 2.84),
    ]
    C.add_lathe_shell(bm, head_profile, MAT_FUR_HONEY, segments=16, center=(0.0, -0.58, 0.0), scale_xy=(1.04, 0.96), smooth=True)
    # Soft cream muzzle & cute dark button nose
    C.add_faceted_icosphere(bm, 0.42, (0.0, -1.28, 1.92), MAT_FUR_CREAM, subdivisions=2, scale=(1.15, 0.85, 0.78))
    C.add_faceted_icosphere(bm, 0.15, (0.0, -1.62, 2.06), MAT_PAW_PAD, subdivisions=1, scale=(1.2, 0.85, 0.82))
    # Big joyful glossy eyes with bright catchlights
    C.add_expressive_eye(bm, (-0.38, -1.28, 2.26), 0.21, MAT_EYE_DARK, MAT_EYE_GLINT)
    C.add_expressive_eye(bm, (0.38, -1.28, 2.26), 0.21, MAT_EYE_DARK, MAT_EYE_GLINT)
    # Cute chocolate eyebrow pips
    C.add_faceted_box(bm, (0.24, 0.12, 0.09), (-0.38, -1.26, 2.55), MAT_EAR_CHOCO, 0.03, rot_deg=(0, 12, 0))
    C.add_faceted_box(bm, (0.24, 0.12, 0.09), (0.38, -1.26, 2.55), MAT_EAR_CHOCO, 0.03, rot_deg=(0, -12, 0))

    # 5. Expressive lofted floppy chocolate ears framing silhouette
    for side in (-1, 1):
        ear_rings = [
            ((side * 0.68, -0.56, 2.52), 0.22, 0.16, (0, side * 35, 0)),
            ((side * 1.02, -0.58, 2.22), 0.26, 0.14, (0, side * 12, 0)),
            ((side * 1.12, -0.62, 1.78), 0.22, 0.12, (0, side * -8, 0)),
            ((side * 1.00, -0.64, 1.52), 0.08, 0.06, (0, side * -18, 0)),
        ]
        C.add_lofted_tube(bm, ear_rings, MAT_EAR_CHOCO, sides=8, smooth=True)

    # 6. Happy perky curled tail
    tail_rings = [
        ((0.0, 0.88, 1.18), 0.16, 0.16, (65, 0, 0)),
        ((0.0, 1.24, 1.48), 0.14, 0.14, (35, 0, 0)),
        ((0.0, 1.32, 1.88), 0.10, 0.10, (5, 0, 0)),
        ((0.0, 1.20, 2.10), 0.04, 0.04, (-25, 0, 0)),
    ]
    C.add_lofted_tube(bm, tail_rings, MAT_FUR_HONEY, sides=8, smooth=True)

    return C.finalize_mesh("TrainingPup", bm, mats)


def main() -> None:
    C.clear_scene()
    obj = build_training_pup()
    C.validate_asset("TrainingPup", [obj], tri_cap=2500, pivot_mode="floor")
    C.export_roblox_asset("TrainingPup", [obj], rigged=False)
    C.setup_studio_render([obj], "TrainingPup_preview.png", resolution=640, samples=22, cam_azimuth_deg=-34.0, cam_elev_deg=18.0, distance_mult=2.25)
    print("BLENDER_EXPORT_OK: TrainingPup")


if __name__ == "__main__":
    main()
