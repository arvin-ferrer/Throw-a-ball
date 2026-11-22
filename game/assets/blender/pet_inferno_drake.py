"""Headless Blender builder for InfernoDrake (Molten Caldera MYTHIC Pet, Issue #17).

Mini-Pyraxis Mythic Showpiece (~3.7 studs tall, <2,500 tris, floor pivot Z=0):
honors Pyraxis_live_preview.png in adorable heroic chibi-drake proportions with
lofted obsidian body, stepped dorsal armor plates, curved ivory horns, fiery ember
ridge spikes, spread crimson-orange drake wings, golden mythic halo, and spade tail.
"""

from __future__ import annotations

import sys
from pathlib import Path

import bmesh
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _common as C  # noqa: E402

MAT_DRAKE_OBSIDIAN = 0
MAT_DRAKE_PLATE = 1
MAT_DRAKE_WING = 2
MAT_EMBER_GLOW = 3
MAT_HORN_IVORY = 4
MAT_GOLD_MYTHIC = 5
MAT_EYE_DARK = 6
MAT_EYE_GLINT = 7


def create_materials() -> list[bpy.types.Material]:
    return [
        C.make_material("DrakeObsidian", (0.14, 0.09, 0.09), roughness=0.55, metallic=0.14),
        C.make_material("DrakeBasaltPlate", (0.28, 0.18, 0.14), roughness=0.64),
        C.make_material("DrakeWingMembrane", (0.82, 0.18, 0.04), roughness=0.40),
        C.make_material("DrakeEmberGlow", (1.0, 0.40, 0.04), roughness=0.16, emission=(1.0, 0.36, 0.03), emission_strength=2.3),
        C.make_material("DrakeHornIvory", (0.92, 0.86, 0.74), roughness=0.30),
        C.make_material("DrakeMythicGold", (0.98, 0.78, 0.22), roughness=0.20, metallic=0.88, emission=(1.0, 0.74, 0.18), emission_strength=0.65),
        C.make_material("DrakeEyeDark", (0.04, 0.02, 0.03), roughness=0.06),
        C.make_material("DrakeEyeGlint", (1.0, 0.94, 0.72), roughness=0.05, emission=(1.0, 0.90, 0.65), emission_strength=2.2),
    ]


def build_inferno_drake() -> bpy.types.Object:
    mats = create_materials()
    bm = bmesh.new()
    # 1. Plump heroic chibi-dragon seated/standing torso + glowing ember belly
    C.add_lofted_tube(bm, [((0, 0.96, 1.02), 0.44, 0.42, (90, 0, 0)), ((0, 0.35, 1.08), 0.72, 0.66, (90, 0, 0)), ((0, -0.35, 1.24), 0.76, 0.70, (82, 0, 0)), ((0, -0.78, 1.56), 0.52, 0.50, (48, 0, 0))], MAT_DRAKE_OBSIDIAN, sides=10, smooth=True)
    C.add_faceted_icosphere(bm, 0.56, (0.0, -0.66, 1.18), MAT_EMBER_GLOW, subdivisions=1, scale=(0.95, 0.55, 1.05))
    # Pyraxis stepped dorsal armor plates & ember spikes!
    for y_p, z_p, glow in [(0.55, 1.66, False), (0.02, 1.82, True), (-0.42, 1.96, False)]:
        C.add_faceted_box(bm, (0.78, 0.52, 0.22), (0.0, y_p, z_p), MAT_DRAKE_PLATE, 0.04)
        C.add_crystal_prism(bm, 0.12, 0.56, (0.0, y_p, z_p + 0.32), MAT_EMBER_GLOW if glow else MAT_HORN_IVORY, sides=4, rot_deg=(-24, 0, 0))

    # 2. Four sturdy clawed drake legs flush on Z = 0.0
    for x, y in [(-0.48, -0.45), (0.48, -0.45), (-0.46, 0.62), (0.46, 0.62)]:
        C.add_lofted_tube(bm, [((x, y, 0.92), 0.26, 0.26, (0, 0, 0)), ((x, y, 0.32), 0.20, 0.22, (0, 0, 0)), ((x, y - 0.04, 0.0), 0.22, 0.26, (0, 0, 0))], MAT_DRAKE_OBSIDIAN, sides=8, smooth=True)
        C.add_crystal_prism(bm, 0.07, 0.24, (x, y - 0.26, 0.12), MAT_HORN_IVORY, sides=4, rot_deg=(85, 0, 0))

    # 3. Expressive oversized chibi-Pyraxis head, curved ivory horns & fiery snout!
    C.add_lofted_tube(bm, [((0, -0.58, 2.08), 0.66, 0.62, (90, 0, 0)), ((0, -1.12, 2.05), 0.64, 0.58, (94, 0, 0)), ((0, -1.64, 1.94), 0.42, 0.36, (98, 0, 0))], MAT_DRAKE_OBSIDIAN, sides=10, smooth=True)
    C.add_crystal_prism(bm, 0.10, 0.36, (0.0, -1.66, 2.26), MAT_HORN_IVORY, sides=4, rot_deg=(-12, 0, 0))
    for sx in (-1, 1):
        C.add_expressive_eye(bm, (sx * 0.46, -1.24, 2.22), 0.19, MAT_EYE_DARK, MAT_EYE_GLINT)
        # Long swept Pyraxis curved ivory horns!
        C.add_lofted_tube(bm, [((sx * 0.36, -0.78, 2.48), 0.16, 0.16, (-32, sx * 24, 0)), ((sx * 0.68, -0.24, 2.86), 0.11, 0.11, (-48, sx * 30, 0)), ((sx * 0.92, 0.35, 3.16), 0.03, 0.03, (-58, sx * 22, 0))], MAT_HORN_IVORY, sides=6, smooth=True)
        # Spread Pyraxis-style crimson bat-drake wings with dark wing spar!
        C.add_lofted_tube(bm, [((sx * 0.62, 0.05, 1.56), 0.12, 0.52, (0, sx * 68, 0)), ((sx * 1.58, 0.35, 2.15), 0.08, 0.76, (-14, sx * 76, sx * -16)), ((sx * 2.42, 0.58, 2.42), 0.04, 0.28, (-20, sx * 84, sx * -22))], MAT_DRAKE_WING, sides=6, smooth=False)
        C.add_lofted_tube(bm, [((sx * 0.58, -0.05, 1.72), 0.09, 0.09, (0, sx * 66, 0)), ((sx * 2.48, 0.52, 2.66), 0.04, 0.04, (0, sx * 76, 0))], MAT_DRAKE_OBSIDIAN, sides=6, smooth=True)

    # 4. Curled tail with signature Pyraxis glowing orange tail spade + golden mythic halo!
    C.add_lofted_tube(bm, [((0, 0.94, 1.02), 0.26, 0.26, (75, 0, 0)), ((0.18, 1.65, 1.18), 0.18, 0.18, (55, 8, 0)), ((0.32, 2.22, 1.55), 0.10, 0.10, (35, 12, 0))], MAT_DRAKE_OBSIDIAN, sides=8, smooth=True)
    C.add_faceted_box(bm, (0.58, 0.72, 0.14), (0.38, 2.52, 1.76), MAT_EMBER_GLOW, 0.03, rot_deg=(-25, 0, -14), taper_top=(0.65, 0.65))
    b0 = set(bm.verts)
    C.add_closed_ring(bm, 0.62, 0.08, 0.10, MAT_GOLD_MYTHIC, (10, 0, 0), 20)
    bmesh.ops.translate(bm, vec=(0, -0.88, 3.44), verts=[v for v in bm.verts if v not in b0])
    return C.finalize_mesh("InfernoDrake", bm, mats)


def main() -> None:
    C.clear_scene()
    obj = build_inferno_drake()
    C.validate_asset("InfernoDrake", [obj], tri_cap=2500, pivot_mode="floor")
    C.export_roblox_asset("InfernoDrake", [obj], rigged=False)
    C.setup_studio_render([obj], "InfernoDrake_preview.png", resolution=640, samples=22, cam_azimuth_deg=-36.0, cam_elev_deg=18.0, distance_mult=2.25)
    print("BLENDER_EXPORT_OK: InfernoDrake")


if __name__ == "__main__":
    main()
