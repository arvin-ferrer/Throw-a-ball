"""Headless Blender builder for BossEgg_Frostbite (Frostbite Cavern Standard Boss Egg)."""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bmesh
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _common as C  # noqa: E402

MAT_ICE_SHELL = 0
MAT_STONE_NEST = 1
MAT_SNOW_TRIM = 2
MAT_SILVER_PRIZE = 3
MAT_GEM_CYAN = 4
MAT_ICE_CRYSTAL = 5


def create_materials() -> list[bpy.types.Material]:
    return [
        C.make_material("EggFrostSapphire", (0.12, 0.52, 0.88), roughness=0.16),
        C.make_material("EggFrostStone", (0.22, 0.28, 0.36), roughness=0.72),
        C.make_material("EggSnowTrim", (0.88, 0.94, 0.98), roughness=0.55),
        C.make_material("EggFrostSilver", (0.82, 0.88, 0.95), roughness=0.20, metallic=0.92),
        C.make_material("EggCyanGem", (0.20, 0.92, 1.0), roughness=0.10, emission=(0.20, 0.92, 1.0), emission_strength=2.3),
        C.make_material("EggIceCrystal", (0.68, 0.94, 1.0), roughness=0.12),
    ]


def build_egg() -> bpy.types.Object:
    mats = create_materials()
    bm = bmesh.new()
    # Frosted slate & silver chalice nest grounded flush at Z = 0.0
    C.add_lathe_shell(bm, [(1.48, 0.0), (1.66, 0.22), (1.58, 0.60), (1.72, 0.88), (1.42, 0.96)], MAT_STONE_NEST, segments=12, smooth=False)
    b0 = set(bm.verts)
    C.add_closed_ring(bm, 1.64, 0.14, 0.16, MAT_SILVER_PRIZE, (0, 0, 0), 18)
    bmesh.ops.translate(bm, vec=(0, 0, 0.84), verts=[v for v in bm.verts if v not in b0])
    for i in range(6):
        ang = math.radians(i * 60.0 + 25.0)
        C.add_crystal_prism(bm, 0.28, 0.72, (1.55 * math.cos(ang), 1.55 * math.sin(ang), 0.52), MAT_ICE_CRYSTAL, sides=5, rot_deg=(0, 0, i * 60))

    # Glossy sapphire-ice ovoid shell
    C.add_lathe_shell(bm, [(0.75, 0.45), (1.38, 0.90), (1.64, 1.55), (1.62, 2.25), (1.38, 2.95), (0.95, 3.55), (0.45, 3.98), (0.10, 4.12)], MAT_ICE_SHELL, segments=20, smooth=True)
    # Crossed silver filigree rings
    for rot in ((24, 16, 0), (-24, -14, 0)):
        b1 = set(bm.verts)
        C.add_closed_ring(bm, 1.66, 0.10, 0.16, MAT_SILVER_PRIZE, rot, 20)
        bmesh.ops.translate(bm, vec=(0, 0, 2.12), verts=[v for v in bm.verts if v not in b1])
    # Silver bezel + glowing glacier diamond front/back
    for sy in (-1, 1):
        C.add_faceted_box(bm, (0.86, 0.24, 1.10), (0.0, sy * 1.62, 2.15), MAT_SILVER_PRIZE, 0.08, rot_deg=(0, 45, 0))
        C.add_faceted_icosphere(bm, 0.44, (0.0, sy * 1.72, 2.15), MAT_GEM_CYAN, subdivisions=1, scale=(0.82, 0.48, 1.25))
    # Silver collar + 3-point icicle crown
    b2 = set(bm.verts)
    C.add_closed_ring(bm, 0.68, 0.12, 0.22, MAT_SILVER_PRIZE, (0, 0, 0), 12)
    bmesh.ops.translate(bm, vec=(0, 0, 3.88), verts=[v for v in bm.verts if v not in b2])
    C.add_crystal_prism(bm, 0.34, 1.15, (0.0, 0.0, 4.35), MAT_GEM_CYAN, sides=6)
    C.add_crystal_prism(bm, 0.22, 0.78, (-0.42, -0.08, 4.16), MAT_ICE_CRYSTAL, sides=5, rot_deg=(6, -24, 0))
    C.add_crystal_prism(bm, 0.22, 0.78, (0.42, -0.08, 4.16), MAT_ICE_CRYSTAL, sides=5, rot_deg=(6, 24, 0))
    return C.finalize_mesh("BossEgg_Frostbite", bm, mats)


def main() -> None:
    C.clear_scene()
    obj = build_egg()
    C.validate_asset("BossEgg_Frostbite", [obj], tri_cap=2500, pivot_mode="floor")
    C.export_roblox_asset("BossEgg_Frostbite", [obj], rigged=False)
    C.setup_studio_render([obj], "BossEgg_Frostbite_preview.png", resolution=640, samples=22, cam_azimuth_deg=-30.0, cam_elev_deg=18.0, distance_mult=2.25)
    print("BLENDER_EXPORT_OK: BossEgg_Frostbite")


if __name__ == "__main__":
    main()
