"""Headless Blender builder for CryoTitan (Frostbite Cavern MYTHIC Pet, Issue #17)."""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bmesh
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _common as C  # noqa: E402

MAT_SAPPHIRE_CORE = 0
MAT_ICE_SHARD = 1
MAT_SLATE_ARMOR = 2
MAT_SILVER_MYTHIC = 3
MAT_EYE_GLOW = 4


def create_materials() -> list[bpy.types.Material]:
    return [
        C.make_material("CryoSapphire", (0.08, 0.46, 0.88), roughness=0.14, emission=(0.08, 0.48, 0.92), emission_strength=1.15),
        C.make_material("CryoIceShard", (0.62, 0.94, 1.0), roughness=0.12),
        C.make_material("CryoSlateArmor", (0.14, 0.20, 0.30), roughness=0.62, metallic=0.18),
        C.make_material("CryoMythicSilver", (0.86, 0.92, 0.98), roughness=0.18, metallic=0.95),
        C.make_material("CryoEyeBright", (0.60, 0.98, 1.0), roughness=0.05, emission=(0.55, 0.96, 1.0), emission_strength=2.8),
    ]


def build_cryo_titan() -> bpy.types.Object:
    mats = create_materials()
    bm = bmesh.new()
    # Sculpted hovering sapphire cryo-crystal sentinel body (Z = 0.52..3.05)
    C.add_lathe_shell(bm, [(0.12, 0.52), (0.64, 1.12), (0.98, 1.85), (0.90, 2.52), (0.48, 2.95), (0.10, 3.08)], MAT_SAPPHIRE_CORE, segments=8, scale_xy=(1.06, 0.86), smooth=False)
    # Dark slate cryo-knight visor + fierce blazing cyan eyes (unobstructed!)
    C.add_faceted_box(bm, (1.28, 0.46, 0.52), (0.0, -0.74, 2.12), MAT_SLATE_ARMOR, 0.06, rot_deg=(8, 0, 0))
    C.add_faceted_box(bm, (0.30, 0.18, 0.18), (-0.32, -0.96, 2.08), MAT_EYE_GLOW, 0.02, rot_deg=(0, 0, -12))
    C.add_faceted_box(bm, (0.30, 0.18, 0.18), (0.32, -0.96, 2.08), MAT_EYE_GLOW, 0.02, rot_deg=(0, 0, 12))
    # Tilted gleaming silver mythic halo ring
    b0 = set(bm.verts)
    C.add_closed_ring(bm, 1.48, 0.11, 0.14, MAT_SILVER_MYTHIC, (22, 18, 0), 22)
    bmesh.ops.translate(bm, vec=(0, 0, 1.86), verts=[v for v in bm.verts if v not in b0])
    # Flanking crystal ice wing-shields (left, right, rear — clear front face!)
    for i in range(3):
        ang_deg = i * 120.0 + 90.0
        rad = math.radians(ang_deg)
        x, y = 1.54 * math.cos(rad), 1.54 * math.sin(rad)
        z = 1.78 + (0.16 if i == 0 else -0.05)
        C.add_faceted_box(bm, (0.76, 0.36, 1.28), (x, y, z), MAT_SLATE_ARMOR, 0.07, rot_deg=(12, 0, ang_deg - 90), taper_top=(0.75, 0.85))
        C.add_crystal_prism(bm, 0.28, 1.05, (x * 1.04, y * 1.04, z + 0.78), MAT_ICE_SHARD, sides=5, rot_deg=(0, 0, ang_deg))
    # Regal silver crown collar + 3-point cryo crystal spire crown
    b1 = set(bm.verts)
    C.add_closed_ring(bm, 0.56, 0.10, 0.18, MAT_SILVER_MYTHIC, (0, 0, 0), 12)
    bmesh.ops.translate(bm, vec=(0, 0, 2.96), verts=[v for v in bm.verts if v not in b1])
    C.add_crystal_prism(bm, 0.24, 0.96, (0.0, 0.0, 3.42), MAT_ICE_SHARD, sides=6)
    for sx in (-1, 1):
        C.add_crystal_prism(bm, 0.16, 0.68, (sx * 0.38, 0.0, 3.24), MAT_EYE_GLOW, sides=5, rot_deg=(0, sx * 24, 0))
    return C.finalize_mesh("CryoTitan", bm, mats)


def main() -> None:
    C.clear_scene()
    obj = build_cryo_titan()
    C.validate_asset("CryoTitan", [obj], tri_cap=2500, pivot_mode="hover")
    C.export_roblox_asset("CryoTitan", [obj], rigged=False)
    C.setup_studio_render([obj], "CryoTitan_preview.png", resolution=640, samples=22, cam_azimuth_deg=-32.0, cam_elev_deg=18.0, distance_mult=2.25)
    print("BLENDER_EXPORT_OK: CryoTitan")


if __name__ == "__main__":
    main()
