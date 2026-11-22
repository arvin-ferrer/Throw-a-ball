"""Headless Blender builder for MagmaCore (Tier 4 Throwable Ball, 1.4 studs dia)."""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _common as C  # noqa: E402

MAT_MAGMA_GLOW = 0
MAT_OBSIDIAN_PLATE = 1
MAT_EMBER_RIDGE = 2


def build_magma_core() -> bpy.types.Object:
    mats = [
        C.make_material(
            "MagmaGlow",
            (1.0, 0.28, 0.02),
            roughness=0.25,
            emission=(1.0, 0.26, 0.02),
            emission_strength=2.6,
        ),
        C.make_material("ObsidianPlate", (0.09, 0.07, 0.08), roughness=0.58, metallic=0.18),
        C.make_material(
            "EmberRidge",
            (1.0, 0.58, 0.08),
            roughness=0.25,
            emission=(1.0, 0.52, 0.06),
            emission_strength=2.2,
        ),
    ]
    bm = bmesh.new()
    # Glowing molten inner core visible through fissures between dark obsidian plates
    C.add_faceted_icosphere(bm, radius=0.63, center=(0, 0, 0), mat_idx=MAT_MAGMA_GLOW, subdivisions=2)

    # 8 cracked dark obsidian volcanic armor plates wrapping OUTSIDE the core (~1.40 dia)
    octants = [
        (1, 1, 1), (-1, 1, 1), (1, -1, 1), (-1, -1, 1),
        (1, 1, -1), (-1, 1, -1), (1, -1, -1), (-1, -1, -1),
    ]
    for idx, (ox, oy, oz) in enumerate(octants):
        n = Vector((ox, oy, oz)).normalized()
        pos = n * 0.65
        rot = n.to_track_quat("Z", "Y").to_euler()
        rot_deg = tuple(math.degrees(a) for a in rot)
        C.add_faceted_box(
            bm,
            size=(0.58, 0.58, 0.25),
            center=(pos.x, pos.y, pos.z),
            mat_idx=MAT_OBSIDIAN_PLATE,
            bevel=0.045,
            rot_deg=rot_deg,
            taper_top=(0.76, 0.76),
        )
        if idx % 2 == 0:
            rpos = n * 0.76
            C.add_crystal_prism(bm, 0.085, 0.19, (rpos.x, rpos.y, rpos.z), MAT_EMBER_RIDGE, sides=4, rot_deg=rot_deg)

    return C.finalize_mesh("MagmaCore", bm, mats)


def main() -> None:
    C.clear_scene()
    obj = build_magma_core()
    C.validate_asset("MagmaCore", [obj], tri_cap=1200, pivot_mode="center")
    C.export_roblox_asset("MagmaCore", [obj], rigged=False)
    C.setup_studio_render([obj], "MagmaCore_preview.png", resolution=640, samples=20, cam_azimuth_deg=-35.0, cam_elev_deg=22.0, distance_mult=2.3)
    print("BLENDER_EXPORT_OK: MagmaCore")


if __name__ == "__main__":
    main()
