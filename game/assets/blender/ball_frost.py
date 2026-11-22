"""Headless Blender builder for FrostOrb (Tier 3 Throwable Ball, 1.3 studs dia)."""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _common as C  # noqa: E402

MAT_GLACIER_CORE = 0
MAT_ICE_SHARD = 1
MAT_FROST_GLOW = 2


def build_frost_orb() -> bpy.types.Object:
    mats = [
        C.make_material("GlacierCore", (0.10, 0.50, 0.86), roughness=0.18, metallic=0.06),
        C.make_material("IceShard", (0.76, 0.96, 1.0), roughness=0.12, metallic=0.08),
        C.make_material(
            "FrostGlow",
            (0.18, 0.84, 1.0),
            roughness=0.15,
            emission=(0.18, 0.84, 1.0),
            emission_strength=1.7,
        ),
    ]
    bm = bmesh.new()
    # Faceted crystalline core + sleek glowing frost equator band
    C.add_faceted_icosphere(bm, radius=0.49, center=(0, 0, 0), mat_idx=MAT_GLACIER_CORE, subdivisions=2)
    C.add_closed_ring(bm, radius=0.50, radial_thickness=0.055, axial_width=0.09, mat_idx=MAT_FROST_GLOW, rot_deg=(24, -18, 0), segments=16)
    # 8 sharp pale-ice crystal spikes pointing strictly OUTWARD along radial normals
    directions: list[Vector] = [Vector((0, 0, 1)), Vector((0, 0, -1))]
    for i in range(6):
        ang = math.radians(i * 60.0)
        z = 0.25 if i % 2 == 0 else -0.25
        directions.append(Vector((math.cos(ang), math.sin(ang), z)).normalized())
    for n in directions:
        pos = n * 0.49
        rot = n.to_track_quat("Z", "Y").to_euler()
        rot_deg = tuple(math.degrees(a) for a in rot)
        C.add_crystal_prism(bm, 0.14, 0.36, (pos.x, pos.y, pos.z), MAT_ICE_SHARD, sides=5, rot_deg=rot_deg)
    return C.finalize_mesh("FrostOrb", bm, mats)


def main() -> None:
    C.clear_scene()
    obj = build_frost_orb()
    C.validate_asset("FrostOrb", [obj], tri_cap=1200, pivot_mode="center")
    C.export_roblox_asset("FrostOrb", [obj], rigged=False)
    C.setup_studio_render([obj], "FrostOrb_preview.png", resolution=640, samples=20, cam_azimuth_deg=-35.0, cam_elev_deg=22.0, distance_mult=2.3)
    print("BLENDER_EXPORT_OK: FrostOrb")


if __name__ == "__main__":
    main()
