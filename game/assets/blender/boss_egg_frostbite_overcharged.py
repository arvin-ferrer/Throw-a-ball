"""Headless Blender builder for BossEgg_Frostbite_Overcharged (5-Min Overcharged Variant)."""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bmesh
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _common as C  # noqa: E402

MAT_VOID_FROST = 0
MAT_GOLD_OVERCHARGE = 1
MAT_CYAN_SURGE = 2
MAT_SOLAR_GLOW = 3
MAT_STONE_DARK = 4


def create_materials() -> list[bpy.types.Material]:
    return [
        C.make_material("EggOverchargeIndigo", (0.10, 0.14, 0.44), roughness=0.14, metallic=0.25),
        C.make_material("EggOverchargeGold", (0.98, 0.78, 0.20), roughness=0.18, metallic=0.95),
        C.make_material("EggOverchargeCyan", (0.20, 0.94, 1.0), roughness=0.10, emission=(0.20, 0.94, 1.0), emission_strength=2.5),
        C.make_material("EggOverchargeSolar", (1.0, 0.68, 0.10), roughness=0.14, emission=(1.0, 0.64, 0.08), emission_strength=2.4),
        C.make_material("EggOverchargeStone", (0.12, 0.14, 0.22), roughness=0.70),
    ]


def build_egg() -> bpy.types.Object:
    mats = create_materials()
    bm = bmesh.new()
    # Royal dark-stone & radiant gold Overcharged pedestal chalice grounded at Z = 0.0
    C.add_lathe_shell(bm, [(1.55, 0.0), (1.74, 0.24), (1.64, 0.64), (1.80, 0.92), (1.46, 0.98)], MAT_STONE_DARK, segments=12, smooth=False)
    b0 = set(bm.verts)
    C.add_closed_ring(bm, 1.72, 0.16, 0.18, MAT_GOLD_OVERCHARGE, (0, 0, 0), 18)
    bmesh.ops.translate(bm, vec=(0, 0, 0.88), verts=[v for v in bm.verts if v not in b0])
    for i in range(6):
        ang = math.radians(i * 60.0)
        C.add_crystal_prism(bm, 0.26, 0.95, (1.64 * math.cos(ang), 1.64 * math.sin(ang), 0.72), MAT_CYAN_SURGE if i % 2 == 0 else MAT_SOLAR_GLOW, sides=5, rot_deg=(0, 0, i * 60))

    # Deep void-frost indigo metallic enamel egg
    C.add_lathe_shell(bm, [(0.75, 0.45), (1.38, 0.90), (1.64, 1.55), (1.62, 2.25), (1.38, 2.95), (0.95, 3.55), (0.45, 3.98), (0.10, 4.12)], MAT_VOID_FROST, segments=20, smooth=True)
    # Twin dramatic floating tilted Overcharged gold + electric-cyan gyro rings!
    for r, rot, mat in [(2.12, (26, 18, 0), MAT_GOLD_OVERCHARGE), (2.22, (-32, -22, 15), MAT_CYAN_SURGE)]:
        b1 = set(bm.verts)
        C.add_closed_ring(bm, r, 0.11, 0.14, mat, rot, 24)
        bmesh.ops.translate(bm, vec=(0, 0, 2.25), verts=[v for v in bm.verts if v not in b1])
    # Blazing front/back Overcharged star core gem in gold bezel
    for sy in (-1, 1):
        C.add_faceted_box(bm, (0.96, 0.28, 1.24), (0.0, sy * 1.64, 2.22), MAT_GOLD_OVERCHARGE, 0.08, rot_deg=(0, 45, 0))
        C.add_faceted_icosphere(bm, 0.50, (0.0, sy * 1.76, 2.22), MAT_SOLAR_GLOW, subdivisions=1, scale=(0.86, 0.52, 1.30))
    # Grand 5-point Overcharged lightning crystal crown (Z ~ 5.05)
    b2 = set(bm.verts)
    C.add_closed_ring(bm, 0.74, 0.14, 0.24, MAT_GOLD_OVERCHARGE, (0, 0, 0), 12)
    bmesh.ops.translate(bm, vec=(0, 0, 3.90), verts=[v for v in bm.verts if v not in b2])
    C.add_crystal_prism(bm, 0.36, 1.42, (0.0, 0.0, 4.48), MAT_SOLAR_GLOW, sides=6)
    for sx in (-1, 1):
        C.add_crystal_prism(bm, 0.24, 1.05, (sx * 0.46, -0.08, 4.28), MAT_CYAN_SURGE, sides=5, rot_deg=(6, sx * 24, 0))
        C.add_crystal_prism(bm, 0.18, 0.78, (sx * 0.78, 0.0, 4.08), MAT_GOLD_OVERCHARGE, sides=4, rot_deg=(0, sx * 42, 0))
    return C.finalize_mesh("BossEgg_Frostbite_Overcharged", bm, mats)


def main() -> None:
    C.clear_scene()
    obj = build_egg()
    C.validate_asset("BossEgg_Frostbite_Overcharged", [obj], tri_cap=2500, pivot_mode="floor")
    C.export_roblox_asset("BossEgg_Frostbite_Overcharged", [obj], rigged=False)
    C.setup_studio_render([obj], "BossEgg_Frostbite_Overcharged_preview.png", resolution=640, samples=22, cam_azimuth_deg=-30.0, cam_elev_deg=18.0, distance_mult=2.25)
    print("BLENDER_EXPORT_OK: BossEgg_Frostbite_Overcharged")


if __name__ == "__main__":
    main()
