"""Headless Blender builder for NovaSphere (Tier 5 Apex Throwable Ball, 1.5 studs dia)."""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _common as C  # noqa: E402

MAT_COSMIC_CORE = 0
MAT_GOLD_RING = 1
MAT_STARLIGHT_GLOW = 2


def add_ring_nodes(bm: bmesh.types.BMesh, radius: float, rot_deg: tuple[float, float, float]) -> None:
    """Attach 2 glowing starlight orb pips opposite each other on a gold gyro ring."""
    rot = Euler(tuple(math.radians(a) for a in rot_deg), "XYZ").to_matrix().to_4x4()
    for ang in (0.0, math.pi):
        p = rot @ Vector((radius * math.cos(ang), radius * math.sin(ang), 0.0))
        C.add_faceted_icosphere(bm, radius=0.072, center=(p.x, p.y, p.z), mat_idx=MAT_STARLIGHT_GLOW, subdivisions=1)


def build_nova_sphere() -> bpy.types.Object:
    mats = [
        C.make_material("CosmicViolet", (0.18, 0.07, 0.46), roughness=0.20, metallic=0.35),
        C.make_material("NovaGold", (0.98, 0.76, 0.24), roughness=0.22, metallic=0.92),
        C.make_material(
            "StarlightCyan",
            (0.32, 0.92, 1.0),
            roughness=0.10,
            emission=(0.30, 0.92, 1.0),
            emission_strength=2.4,
        ),
    ]
    bm = bmesh.new()
    # Deep violet faceted cosmic core
    C.add_faceted_icosphere(bm, radius=0.49, center=(0, 0, 0), mat_idx=MAT_COSMIC_CORE, subdivisions=2)
    # 6 glowing starlight diamond spikes at cardinal axes
    axes = [
        ((0, 0, 0.50), (0, 0, 0)),
        ((0, 0, -0.50), (180, 0, 0)),
        ((0.50, 0, 0), (0, 90, 0)),
        ((-0.50, 0, 0), (0, -90, 0)),
        ((0, 0.50, 0), (-90, 0, 0)),
        ((0, -0.50, 0), (90, 0, 0)),
    ]
    for pos, rot in axes:
        C.add_crystal_prism(bm, 0.11, 0.24, pos, MAT_STARLIGHT_GLOW, sides=4, rot_deg=rot)
    # Two tilted intersecting seamless metallic gold orbital rings (outer dia ~1.50)
    C.add_closed_ring(bm, radius=0.71, radial_thickness=0.068, axial_width=0.088, mat_idx=MAT_GOLD_RING, rot_deg=(35, 22, 0), segments=22)
    C.add_closed_ring(bm, radius=0.71, radial_thickness=0.068, axial_width=0.088, mat_idx=MAT_GOLD_RING, rot_deg=(-40, 58, 25), segments=22)
    add_ring_nodes(bm, 0.71, (35, 22, 0))
    add_ring_nodes(bm, 0.71, (-40, 58, 25))
    return C.finalize_mesh("NovaSphere", bm, mats)


def main() -> None:
    C.clear_scene()
    obj = build_nova_sphere()
    C.validate_asset("NovaSphere", [obj], tri_cap=1200, pivot_mode="center")
    C.export_roblox_asset("NovaSphere", [obj], rigged=False)
    C.setup_studio_render([obj], "NovaSphere_preview.png", resolution=640, samples=20, cam_azimuth_deg=-35.0, cam_elev_deg=22.0, distance_mult=2.3)
    print("BLENDER_EXPORT_OK: NovaSphere")


if __name__ == "__main__":
    main()
