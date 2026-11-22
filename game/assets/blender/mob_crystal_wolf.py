"""Headless Blender builder for CrystalWolf (Frostbite Cavern PvE Mob 2, Issue #17).

Sleek Pyraxis-grade lofted frost wolf (~3.8 studs tall, ~5.8 studs long, <2,500 tris)
with jagged glacier-crystal shoulder mane & dorsal ice shards, pointed ears, glowing
cyan eyes, bushy crystal-tipped tail, 12-bone HumanoidRootPart rig, and Idle/Run/Attack clips.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _common as C  # noqa: E402

MAT_FUR_BLUE = 0
MAT_FUR_WHITE = 1
MAT_ICE_SHARD = 2
MAT_CYAN_GLOW = 3
MAT_PAW_DARK = 4


def create_materials() -> list[bpy.types.Material]:
    return [
        C.make_material("WolfFrostBlue", (0.26, 0.44, 0.66), roughness=0.64),
        C.make_material("WolfSnowBelly", (0.86, 0.93, 0.98), roughness=0.58),
        C.make_material("WolfIceShard", (0.64, 0.92, 1.0), roughness=0.14),
        C.make_material("WolfCyanGlow", (0.22, 0.94, 1.0), roughness=0.12, emission=(0.22, 0.94, 1.0), emission_strength=2.3),
        C.make_material("WolfPawDark", (0.10, 0.14, 0.22), roughness=0.45),
    ]


def build_geometry(bm: bmesh.types.BMesh, bmap: dict[bmesh.types.BMVert, str]) -> None:
    # Sleek agile lofted wolf body
    body_rings = [
        ((0.0, 1.95, 1.95), 0.56, 0.54, (90, 0, 0)),
        ((0.0, 1.05, 1.98), 0.86, 0.82, (90, 0, 0)),
        ((0.0, -0.15, 2.08), 0.96, 0.92, (90, 0, 0)),
        ((0.0, -1.25, 2.25), 1.06, 1.02, (90, 0, 0)),
        ((0.0, -1.75, 2.35), 0.78, 0.76, (90, 0, 0)),
    ]
    C.add_lofted_tube(bm, body_rings, MAT_FUR_BLUE, sides=10, smooth=True, tag_bone="Torso", bone_map=bmap)
    # Fluffy white chest ruff + jagged glacier crystal mane & spine shards
    C.add_faceted_icosphere(bm, 0.86, (0.0, -1.48, 2.02), MAT_FUR_WHITE, subdivisions=1, scale=(1.08, 0.85, 1.05), tag_bone="Torso", bone_map=bmap)
    for y_p, z_p, h, glow in [(0.75, 2.95, 0.95, False), (-0.25, 3.15, 1.15, False), (-1.15, 3.45, 1.45, True)]:
        C.add_crystal_prism(bm, 0.22, h, (0.0, y_p, z_p), MAT_CYAN_GLOW if glow else MAT_ICE_SHARD, sides=5, rot_deg=(-28, 0, 0), tag_bone="Torso", bone_map=bmap)
        for sx in (-1, 1):
            C.add_crystal_prism(bm, 0.16, h * 0.75, (sx * 0.65, y_p, z_p - 0.18), MAT_ICE_SHARD, sides=4, rot_deg=(-22, sx * 36, 0), tag_bone="Torso", bone_map=bmap)

    # Bushy swept crystal-tipped wolf tail
    tail_rings = [
        ((0.0, 1.92, 2.05), 0.26, 0.26, (70, 0, 0)),
        ((0.0, 2.65, 2.45), 0.42, 0.38, (55, 0, 0)),
        ((0.0, 3.25, 2.95), 0.28, 0.26, (40, 0, 0)),
        ((0.0, 3.58, 3.32), 0.06, 0.06, (30, 0, 0)),
    ]
    C.add_lofted_tube(bm, tail_rings, MAT_FUR_WHITE, sides=8, smooth=True, tag_bone="Pelvis", bone_map=bmap)
    C.add_crystal_prism(bm, 0.16, 0.62, (0.0, 3.62, 3.38), MAT_ICE_SHARD, sides=5, rot_deg=(-45, 0, 0), tag_bone="Pelvis", bone_map=bmap)

    # Sleek angular wolf head, ears & glowing eyes facing -Y
    head_rings = [
        ((0.0, -1.62, 2.62), 0.82, 0.78, (90, 0, 0)),
        ((0.0, -2.35, 2.58), 0.76, 0.70, (95, 0, 0)),
        ((0.0, -3.15, 2.42), 0.42, 0.38, (98, 0, 0)),
        ((0.0, -3.52, 2.36), 0.26, 0.24, (98, 0, 0)),
    ]
    C.add_lofted_tube(bm, head_rings, MAT_FUR_BLUE, sides=10, smooth=True, tag_bone="Head", bone_map=bmap)
    C.add_faceted_icosphere(bm, 0.16, (0.0, -3.56, 2.44), MAT_PAW_DARK, subdivisions=1, scale=(1.1, 0.8, 0.8), tag_bone="Head", bone_map=bmap)
    for sx in (-1, 1):
        C.add_faceted_box(bm, (0.28, 0.28, 0.18), (sx * 0.56, -2.55, 2.84), MAT_CYAN_GLOW, 0.02, rot_deg=(0, 0, sx * -14), tag_bone="Head", bone_map=bmap)
        ear = [
            ((sx * 0.52, -1.95, 3.18), 0.22, 0.12, (0, sx * 16, 0)),
            ((sx * 0.68, -1.92, 3.72), 0.16, 0.08, (0, sx * 20, 0)),
            ((sx * 0.78, -1.88, 4.08), 0.03, 0.02, (0, sx * 22, 0)),
        ]
        C.add_lofted_tube(bm, ear, MAT_FUR_BLUE, sides=6, smooth=True, tag_bone="Head", bone_map=bmap)

    # Four athletic lofted wolf legs flush on Z = 0.0
    for name, x, y in [("LegFL", -0.68, -1.18), ("LegFR", 0.68, -1.18), ("LegBL", -0.66, 1.38), ("LegBR", 0.66, 1.38)]:
        leg = [
            ((x, y, 1.85), 0.34, 0.38, (0, 0, 0)),
            ((x, y, 1.05), 0.24, 0.26, (0, 0, 0)),
            ((x, y, 0.34), 0.20, 0.22, (0, 0, 0)),
        ]
        C.add_lofted_tube(bm, leg, MAT_FUR_BLUE, sides=8, smooth=True, tag_bone=f"{name}_Upper", bone_map=bmap)
        C.add_faceted_box(bm, (0.46, 0.62, 0.36), (x, y - 0.08, 0.18), MAT_PAW_DARK, 0.05, taper_top=(0.82, 0.82), tag_bone=f"{name}_Paw", bone_map=bmap)


def build_armature() -> bpy.types.Object:
    arm_data = bpy.data.armatures.new("CrystalWolfArmature")
    arm_obj = bpy.data.objects.new("CrystalWolf", arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    specs = [
        ("HumanoidRootPart", None, (0, 0, 0), (0, 0, 1.0)),
        ("Pelvis", "HumanoidRootPart", (0, 1.5, 1.98), (0, 0.8, 2.02)),
        ("Torso", "Pelvis", (0, 0.8, 2.02), (0, -1.5, 2.35)),
        ("Head", "Torso", (0, -1.5, 2.35), (0, -3.5, 2.4)),
        ("LegFL_Upper", "Torso", (-0.68, -1.18, 1.85), (-0.68, -1.18, 0.35)),
        ("LegFL_Paw", "LegFL_Upper", (-0.68, -1.18, 0.35), (-0.68, -1.35, 0.0)),
        ("LegFR_Upper", "Torso", (0.68, -1.18, 1.85), (0.68, -1.18, 0.35)),
        ("LegFR_Paw", "LegFR_Upper", (0.68, -1.18, 0.35), (0.68, -1.35, 0.0)),
        ("LegBL_Upper", "Pelvis", (-0.66, 1.38, 1.85), (-0.66, 1.38, 0.35)),
        ("LegBL_Paw", "LegBL_Upper", (-0.66, 1.38, 0.35), (-0.66, 1.25, 0.0)),
        ("LegBR_Upper", "Pelvis", (0.66, 1.38, 1.85), (0.66, 1.38, 0.35)),
        ("LegBR_Paw", "LegBR_Upper", (0.66, 1.38, 0.35), (0.66, 1.25, 0.0)),
    ]
    eb = arm_data.edit_bones
    created: dict[str, bpy.types.EditBone] = {}
    for name, parent, h, t in specs:
        b = eb.new(name)
        b.head, b.tail = Vector(h), Vector(t)
        if parent:
            b.parent = created[parent]
        created[name] = b
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm_obj


def author_animations(arm_obj: bpy.types.Object) -> None:
    def clip(name: str, end_f: int, frames: list[tuple[int, dict[str, tuple[float, float, float]]]]) -> None:
        anim = arm_obj.animation_data or arm_obj.animation_data_create()
        act = bpy.data.actions.new(name=name)
        anim.action = act
        for frame, rots in frames:
            for pb in arm_obj.pose.bones:
                pb.rotation_mode = "XYZ"
                deg = rots.get(pb.name, (0.0, 0.0, 0.0))
                pb.rotation_euler = Euler(tuple(math.radians(a) for a in deg), "XYZ")
                pb.keyframe_insert(data_path="rotation_euler", frame=frame)
        C.push_action_to_nla(arm_obj, act, name, end_f)

    clip("Idle", 36, [(1, {}), (18, {"Head": (-8, 0, 8), "Torso": (-3, 0, 0)}), (36, {})])
    clip("Run", 14, [
        (1, {"LegFL_Upper": (38, 0, 0), "LegFR_Upper": (32, 0, 0), "LegBL_Upper": (-36, 0, 0), "LegBR_Upper": (-40, 0, 0), "Torso": (8, 0, 0)}),
        (7, {"LegFL_Upper": (-36, 0, 0), "LegFR_Upper": (-32, 0, 0), "LegBL_Upper": (38, 0, 0), "LegBR_Upper": (34, 0, 0), "Torso": (-6, 0, 0)}),
        (14, {"LegFL_Upper": (38, 0, 0), "LegFR_Upper": (32, 0, 0), "LegBL_Upper": (-36, 0, 0), "LegBR_Upper": (-40, 0, 0), "Torso": (8, 0, 0)}),
    ])
    clip("Attack", 18, [(1, {}), (6, {"Torso": (-16, 0, 0), "Head": (-14, 0, 0)}), (11, {"Torso": (22, 0, 0), "Head": (18, 0, 0), "LegFL_Upper": (40, 0, 0), "LegFR_Upper": (40, 0, 0)}), (18, {})])


def main() -> None:
    C.clear_scene()
    mats = create_materials()
    bm = bmesh.new()
    bmap: dict[bmesh.types.BMVert, str] = {}
    build_geometry(bm, bmap)
    idx_map = C.extract_bone_index_map(bm, bmap)
    mesh_obj = C.finalize_mesh("CrystalWolf_Mesh", bm, mats)
    arm_obj = build_armature()
    C.assign_bone_weights(mesh_obj, arm_obj, idx_map, "Torso")
    author_animations(arm_obj)
    C.reset_pose(arm_obj)
    for tr in arm_obj.animation_data.nla_tracks:
        tr.mute = True
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    C.validate_asset("CrystalWolf", [mesh_obj], tri_cap=2500, pivot_mode="floor")
    for tr in arm_obj.animation_data.nla_tracks:
        tr.mute = False
    C.export_roblox_asset("CrystalWolf", [arm_obj, mesh_obj], rigged=True)
    for tr in arm_obj.animation_data.nla_tracks:
        tr.mute = True
    C.reset_pose(arm_obj)
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    C.setup_studio_render([mesh_obj], "CrystalWolf_preview.png", resolution=640, samples=22, cam_azimuth_deg=-38.0, cam_elev_deg=16.0, distance_mult=2.25)
    print("BLENDER_EXPORT_OK: CrystalWolf")


if __name__ == "__main__":
    main()
