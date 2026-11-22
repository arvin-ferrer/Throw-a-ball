"""Headless Blender builder for IronSphere (Tier 2 Throwable Ball, 1.2 studs dia)."""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _common as C  # noqa: E402

MAT_IRON_DARK = 0
MAT_IRON_BAND = 1
MAT_RIVET_STEEL = 2


def add_rivet_ring(bm: bmesh.types.BMesh, radius: float, rot_deg: tuple[float, float, float], count: int = 8) -> None:
    """Place bold forged steel rivets evenly around an iron hoop."""
    rot = Euler(tuple(math.radians(a) for a in rot_deg), "XYZ").to_matrix().to_4x4()
    for i in range(count):
        ang = 2.0 * math.pi * i / count + math.pi / count
        p = rot @ Vector((radius * math.cos(ang), radius * math.sin(ang), 0.0))
        C.add_faceted_icosphere(bm, radius=0.048, center=(p.x, p.y, p.z), mat_idx=MAT_RIVET_STEEL, subdivisions=1)


def build_iron_sphere() -> bpy.types.Object:
    mats = [
        C.make_material("IronCore", (0.22, 0.26, 0.31), roughness=0.38, metallic=0.82),
        C.make_material("IronBand", (0.44, 0.49, 0.56), roughness=0.26, metallic=0.90),
        C.make_material("SteelRivet", (0.76, 0.81, 0.88), roughness=0.20, metallic=0.95),
    ]
    bm = bmesh.new()
    C.add_faceted_icosphere(bm, radius=0.53, center=(0, 0, 0), mat_idx=MAT_IRON_DARK, subdivisions=2)
    C.add_closed_ring(bm, radius=0.545, radial_thickness=0.065, axial_width=0.14, mat_idx=MAT_IRON_BAND, rot_deg=(0, 0, 0), segments=18)
    C.add_closed_ring(bm, radius=0.550, radial_thickness=0.065, axial_width=0.14, mat_idx=MAT_IRON_BAND, rot_deg=(90, 0, 0), segments=18)
    add_rivet_ring(bm, radius=0.585, rot_deg=(0, 0, 0), count=8)
    add_rivet_ring(bm, radius=0.590, rot_deg=(90, 0, 0), count=8)
    return C.finalize_mesh("IronSphere", bm, mats)


def main() -> None:
    C.clear_scene()
    obj = build_iron_sphere()
    C.validate_asset("IronSphere", [obj], tri_cap=1200, pivot_mode="center")
    C.export_roblox_asset("IronSphere", [obj], rigged=False)
    C.setup_studio_render([obj], "IronSphere_preview.png", resolution=640, samples=20, cam_azimuth_deg=-35.0, cam_elev_deg=22.0, distance_mult=2.3)
    print("BLENDER_EXPORT_OK: IronSphere")


if __name__ == "__main__":
    main()
