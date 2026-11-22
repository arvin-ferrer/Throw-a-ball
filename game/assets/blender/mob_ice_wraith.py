"""Headless Blender builder for IceWraith (Frostbite Cavern PvE Mob 1, Issue #17).

Hovering ragged glacial cloak specter (~4.5 studs tall, <2,500 tris) with hooded
sapphire-ice shroud, floating frost crystal crown, blazing cyan eyes, tapered wispy
ice tail, clawed frost hands, 8-bone HumanoidRootPart rig, and Idle/Glide/Attack clips.
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

MAT_CLOAK_DEEP = 0
MAT_CLOAK_FROST = 1
MAT_ICE_SHARD = 2
MAT_CYAN_GLOW = 3
MAT_VOID_FACE = 4


def create_materials() -> list[bpy.types.Material]:
    return [
        C.make_material("WraithDeepBlue", (0.10, 0.24, 0.44), roughness=0.58),
        C.make_material("WraithFrostTrim", (0.48, 0.78, 0.96), roughness=0.40),
        C.make_material("WraithIceShard", (0.72, 0.95, 1.0), roughness=0.14),
        C.make_material("WraithCyanGlow", (0.24, 0.94, 1.0), roughness=0.12, emission=(0.24, 0.94, 1.0), emission_strength=2.3),
        C.make_material("WraithVoidFace", (0.03, 0.05, 0.09), roughness=0.80),
    ]


def build_geometry(bm: bmesh.types.BMesh, bmap: dict[bmesh.types.BMVert, str]) -> None:
    # Tapered ghostly hovering cloak body (Z = 0.50..3.60)
    cloak_rings = [
        ((0.0, 0.45, 0.55), 0.14, 0.14, (16, 0, 0)),
        ((0.0, 0.18, 1.25), 0.72, 0.62, (8, 0, 0)),
        ((0.0, 0.0, 2.25), 1.05, 0.85, (0, 0, 0)),
        ((0.0, -0.05, 3.25), 1.15, 0.92, (0, 0, 0)),
        ((0.0, -0.10, 3.85), 0.72, 0.65, (0, 0, 0)),
    ]
    C.add_lofted_tube(bm, cloak_rings, MAT_CLOAK_DEEP, sides=10, smooth=True, tag_bone="Torso", bone_map=bmap)
    # Ragged icicle hem shards & floating shoulder ice pauldrons
    for i in range(5):
        ang = math.radians(i * 72.0)
        C.add_crystal_prism(bm, 0.22, 0.95, (0.72 * math.cos(ang), 0.72 * math.sin(ang), 1.05), MAT_ICE_SHARD, sides=4, rot_deg=(180, 0, 0), tag_bone="Tail", bone_map=bmap)
    for sx in (-1, 1):
        C.add_crystal_prism(bm, 0.36, 1.25, (sx * 1.22, 0.0, 3.55), MAT_ICE_SHARD, sides=5, rot_deg=(-12, sx * 34, 0), tag_bone="Torso", bone_map=bmap)
        # Floating spectral frost arms + ice claws
        arm = [
            ((sx * 1.15, -0.15, 3.05), 0.26, 0.24, (40, sx * 25, 0)),
            ((sx * 1.55, -0.85, 2.65), 0.20, 0.20, (70, sx * 10, 0)),
            ((sx * 1.48, -1.45, 2.48), 0.18, 0.16, (85, 0, 0)),
        ]
        C.add_lofted_tube(bm, arm, MAT_CLOAK_FROST, sides=6, smooth=True, tag_bone=f"Arm{'L' if sx < 0 else 'R'}", bone_map=bmap)
        C.add_crystal_prism(bm, 0.12, 0.65, (sx * 1.48, -1.78, 2.45), MAT_CYAN_GLOW, sides=4, rot_deg=(92, 0, 0), tag_bone=f"Arm{'L' if sx < 0 else 'R'}", bone_map=bmap)

    # Hooded wraith head, shadow face cavity, glowing eyes & 3-point frost crown
    C.add_faceted_icosphere(bm, 0.85, (0.0, -0.12, 3.92), MAT_CLOAK_FROST, subdivisions=2, scale=(1.02, 1.12, 1.05), tag_bone="Head", bone_map=bmap)
    C.add_faceted_icosphere(bm, 0.62, (0.0, -0.58, 3.85), MAT_VOID_FACE, subdivisions=1, scale=(0.95, 0.62, 0.95), tag_bone="Head", bone_map=bmap)
    for sx in (-1, 1):
        C.add_faceted_box(bm, (0.28, 0.14, 0.16), (sx * 0.26, -0.96, 3.92), MAT_CYAN_GLOW, 0.02, rot_deg=(0, 0, sx * -14), tag_bone="Head", bone_map=bmap)
    C.add_crystal_prism(bm, 0.20, 0.82, (0.0, -0.05, 4.78), MAT_CYAN_GLOW, sides=5, tag_bone="Head", bone_map=bmap)
    for sx in (-1, 1):
        C.add_crystal_prism(bm, 0.14, 0.56, (sx * 0.44, -0.05, 4.62), MAT_ICE_SHARD, sides=4, rot_deg=(0, sx * 24, 0), tag_bone="Head", bone_map=bmap)


def build_armature() -> bpy.types.Object:
    arm_data = bpy.data.armatures.new("IceWraithArmature")
    arm_obj = bpy.data.objects.new("IceWraith", arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    specs = [
        ("HumanoidRootPart", None, (0, 0, 0), (0, 0, 1.2)),
        ("Torso", "HumanoidRootPart", (0, 0, 1.8), (0, 0, 3.4)),
        ("Head", "Torso", (0, -0.1, 3.4), (0, -0.2, 4.6)),
        ("Tail", "Torso", (0, 0.1, 1.8), (0, 0.45, 0.55)),
        ("ArmL", "Torso", (-1.1, -0.1, 3.0), (-1.5, -1.6, 2.4)),
        ("ArmR", "Torso", (1.1, -0.1, 3.0), (1.5, -1.6, 2.4)),
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
    def clip(name: str, end_f: int, frames: list[tuple[int, dict[str, tuple[float, float, float]], float]]) -> None:
        anim = arm_obj.animation_data or arm_obj.animation_data_create()
        act = bpy.data.actions.new(name=name)
        anim.action = act
        for frame, rots, z_off in frames:
            for pb in arm_obj.pose.bones:
                pb.rotation_mode = "XYZ"
                deg = rots.get(pb.name, (0.0, 0.0, 0.0))
                pb.rotation_euler = Euler(tuple(math.radians(a) for a in deg), "XYZ")
                pb.keyframe_insert(data_path="rotation_euler", frame=frame)
                if pb.name == "Torso":
                    pb.location = Vector((0, 0, z_off))
                    pb.keyframe_insert(data_path="location", frame=frame)
        C.push_action_to_nla(arm_obj, act, name, end_f)

    clip("Idle", 40, [(1, {}, 0.0), (20, {"Tail": (14, 0, 0), "ArmL": (-8, 0, -8), "ArmR": (-8, 0, 8)}, 0.35), (40, {}, 0.0)])
    clip("Glide", 24, [(1, {"Torso": (16, 0, 0), "Tail": (22, 0, 0)}, 0.15), (12, {"Torso": (20, 0, 0), "Tail": (30, 0, 0)}, 0.45), (24, {"Torso": (16, 0, 0), "Tail": (22, 0, 0)}, 0.15)])
    clip("Attack", 20, [(1, {}, 0.0), (7, {"Torso": (-18, 0, 0), "ArmL": (-48, 0, -25), "ArmR": (-48, 0, 25)}, 0.3), (12, {"Torso": (24, 0, 0), "ArmL": (42, 0, 12), "ArmR": (42, 0, -12)}, 0.1), (20, {}, 0.0)])


def main() -> None:
    C.clear_scene()
    mats = create_materials()
    bm = bmesh.new()
    bmap: dict[bmesh.types.BMVert, str] = {}
    build_geometry(bm, bmap)
    idx_map = C.extract_bone_index_map(bm, bmap)
    mesh_obj = C.finalize_mesh("IceWraith_Mesh", bm, mats)
    arm_obj = build_armature()
    C.assign_bone_weights(mesh_obj, arm_obj, idx_map, "Torso")
    author_animations(arm_obj)
    C.reset_pose(arm_obj)
    for tr in arm_obj.animation_data.nla_tracks:
        tr.mute = True
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    C.validate_asset("IceWraith", [mesh_obj], tri_cap=2500, pivot_mode="hover")
    for tr in arm_obj.animation_data.nla_tracks:
        tr.mute = False
    C.export_roblox_asset("IceWraith", [arm_obj, mesh_obj], rigged=True)
    for tr in arm_obj.animation_data.nla_tracks:
        tr.mute = True
    C.reset_pose(arm_obj)
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    C.setup_studio_render([mesh_obj], "IceWraith_preview.png", resolution=640, samples=22, cam_azimuth_deg=-34.0, cam_elev_deg=14.0, distance_mult=2.25)
    print("BLENDER_EXPORT_OK: IceWraith")


if __name__ == "__main__":
    main()
