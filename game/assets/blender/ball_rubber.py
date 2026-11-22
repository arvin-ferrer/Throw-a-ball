"""Headless Blender builder for RubberBall (Tier 1 Throwable Ball, 1.1 studs dia)."""

from __future__ import annotations

import sys
from pathlib import Path

import bmesh
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _common as C  # noqa: E402

MAT_RUBBER_RED = 0
MAT_SEAM_CREAM = 1
MAT_RUBBER_DARK = 2


def build_rubber_ball() -> bpy.types.Object:
    mats = [
        C.make_material("RubberCrimson", (0.86, 0.12, 0.12), roughness=0.42),
        C.make_material("RubberCream", (0.95, 0.92, 0.84), roughness=0.50),
        C.make_material("RubberDeepRed", (0.52, 0.06, 0.07), roughness=0.48),
    ]
    bm = bmesh.new()
    # Core faceted athletic sphere + two seamless perpendicular cream cross-seams
    C.add_faceted_icosphere(bm, radius=0.52, center=(0, 0, 0), mat_idx=MAT_RUBBER_RED, subdivisions=2)
    C.add_closed_ring(bm, radius=0.525, radial_thickness=0.044, axial_width=0.095, mat_idx=MAT_SEAM_CREAM, rot_deg=(0, 0, 0), segments=20)
    C.add_closed_ring(bm, radius=0.529, radial_thickness=0.044, axial_width=0.095, mat_idx=MAT_SEAM_CREAM, rot_deg=(90, 0, 0), segments=20)
    # Dark rubber polar valve caps
    C.add_faceted_icosphere(bm, radius=0.14, center=(0, 0, 0.46), mat_idx=MAT_RUBBER_DARK, subdivisions=1, scale=(1.0, 1.0, 0.35))
    C.add_faceted_icosphere(bm, radius=0.14, center=(0, 0, -0.46), mat_idx=MAT_RUBBER_DARK, subdivisions=1, scale=(1.0, 1.0, 0.35))
    return C.finalize_mesh("RubberBall", bm, mats)


def main() -> None:
    C.clear_scene()
    obj = build_rubber_ball()
    C.validate_asset("RubberBall", [obj], tri_cap=1200, pivot_mode="center")
    C.export_roblox_asset("RubberBall", [obj], rigged=False)
    C.setup_studio_render([obj], "RubberBall_preview.png", resolution=640, samples=20, cam_azimuth_deg=-35.0, cam_elev_deg=22.0, distance_mult=2.3)
    print("BLENDER_EXPORT_OK: RubberBall")


if __name__ == "__main__":
    main()
