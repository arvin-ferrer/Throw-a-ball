"""Headless Blender builder for BossEgg_Molten (Molten Caldera Standard Boss Egg)."""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bmesh
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _common as C  # noqa: E402

MAT_CRIMSON_SHELL = 0
MAT_OBSIDIAN_NEST = 1
MAT_GOLD_PRIZE = 2
MAT_LAVA_GEM = 3
MAT_EMBER_SPIKE = 4


def create_materials() -> list[bpy.types.Material]:
    return [
        C.make_material("EggMoltenCrimson", (0.64, 0.10, 0.06), roughness=0.22),
        C.make_material("EggObsidianNest", (0.12, 0.09, 0.10), roughness=0.68, metallic=0.14),
        C.make_material("EggMoltenGold", (0.96, 0.72, 0.18), roughness=0.20, metallic=0.92),
        C.make_material("EggLavaGem", (1.0, 0.36, 0.04), roughness=0.14, emission=(1.0, 0.34, 0.03), emission_strength=2.5),
        C.make_material("EggEmberSpike", (1.0, 0.62, 0.08), roughness=0.18, emission=(1.0, 0.56, 0.06), emission_strength=2.1),
    ]


def build_egg() -> bpy.types.Object:
    mats = create_materials()
    bm = bmesh.new()
    # Dark obsidian basalt & molten-gold chalice nest grounded at Z = 0.0
    C.add_lathe_shell(bm, [(1.48, 0.0), (1.66, 0.22), (1.58, 0.60), (1.72, 0.88), (1.42, 0.96)], MAT_OBSIDIAN_NEST, segments=12, smooth=False)
    b0 = set(bm.verts)
    C.add_closed_ring(bm, 1.64, 0.14, 0.16, MAT_GOLD_PRIZE, (0, 0, 0), 18)
    bmesh.ops.translate(bm, vec=(0, 0, 0.84), verts=[v for v in bm.verts if v not in b0])
    for i in range(6):
        ang = math.radians(i * 60.0 + 25.0)
        C.add_crystal_prism(bm, 0.28, 0.70, (1.56 * math.cos(ang), 1.56 * math.sin(ang), 0.54), MAT_OBSIDIAN_NEST, sides=4, rot_deg=(0, 0, i * 60))

    # Glossy volcanic crimson ovoid shell
    C.add_lathe_shell(bm, [(0.75, 0.45), (1.38, 0.90), (1.64, 1.55), (1.62, 2.25), (1.38, 2.95), (0.95, 3.55), (0.45, 3.98), (0.10, 4.12)], MAT_CRIMSON_SHELL, segments=20, smooth=True)
    # Crossed obsidian & molten-gold armor ribs
    for rot, mat in [((24, 16, 0), MAT_GOLD_PRIZE), ((-24, -14, 0), MAT_OBSIDIAN_NEST)]:
        b1 = set(bm.verts)
        C.add_closed_ring(bm, 1.66, 0.11, 0.18, mat, rot, 20)
        bmesh.ops.translate(bm, vec=(0, 0, 2.12), verts=[v for v in bm.verts if v not in b1])
    for sy in (-1, 1):
        C.add_faceted_box(bm, (0.88, 0.24, 1.12), (0.0, sy * 1.62, 2.15), MAT_GOLD_PRIZE, 0.08, rot_deg=(0, 45, 0))
        C.add_faceted_icosphere(bm, 0.45, (0.0, sy * 1.72, 2.15), MAT_LAVA_GEM, subdivisions=1, scale=(0.82, 0.48, 1.25))
    # Golden collar + 3-point volcanic flame crystal crown
    b2 = set(bm.verts)
    C.add_closed_ring(bm, 0.68, 0.12, 0.22, MAT_GOLD_PRIZE, (0, 0, 0), 12)
    bmesh.ops.translate(bm, vec=(0, 0, 3.88), verts=[v for v in bm.verts if v not in b2])
    C.add_crystal_prism(bm, 0.34, 1.15, (0.0, 0.0, 4.35), MAT_LAVA_GEM, sides=6)
    C.add_crystal_prism(bm, 0.22, 0.78, (-0.42, -0.08, 4.16), MAT_EMBER_SPIKE, sides=5, rot_deg=(6, -24, 0))
    C.add_crystal_prism(bm, 0.22, 0.78, (0.42, -0.08, 4.16), MAT_EMBER_SPIKE, sides=5, rot_deg=(6, 24, 0))
    return C.finalize_mesh("BossEgg_Molten", bm, mats)


def main() -> None:
    C.clear_scene()
    obj = build_egg()
    C.validate_asset("BossEgg_Molten", [obj], tri_cap=2500, pivot_mode="floor")
    C.export_roblox_asset("BossEgg_Molten", [obj], rigged=False)
    C.setup_studio_render([obj], "BossEgg_Molten_preview.png", resolution=640, samples=22, cam_azimuth_deg=-30.0, cam_elev_deg=18.0, distance_mult=2.25)
    print("BLENDER_EXPORT_OK: BossEgg_Molten")


if __name__ == "__main__":
    main()
