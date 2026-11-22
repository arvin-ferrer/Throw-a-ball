"""Headless Blender builder for CinderImp (Molten Caldera PvE Mob 1, Issue #17).

Nimble mischievous volcanic imp (~3.7 studs tall, <2,500 tris) with charred crimson-obsidian
body, curved swept obsidian horns, blazing magma chest core & eyes, bat-like ember wings,
barbed arrow tail, 10-bone HumanoidRootPart rig, and Idle/Run/Attack clips.
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

MAT_IMP_SKIN = 0
MAT_IMP_OBSIDIAN = 1
MAT_EMBER_GLOW = 2
MAT_WING_RED = 3
MAT_HORN_BONE = 4


def create_materials() -> list[bpy.types.Material]:
    return [
        C.make_material("ImpCrimsonSkin", (0.52, 0.12, 0.08), roughness=0.58),
        C.make_material("ImpObsidian", (0.12, 0.09, 0.10), roughness=0.62),
        C.make_material("ImpEmberGlow", (1.0, 0.42, 0.04), roughness=0.18, emission=(1.0, 0.38, 0.04), emission_strength=2.5),
        C.make_material("ImpWingRed", (0.82, 0.18, 0.05), roughness=0.42),
        C.make_material("ImpHornIvory", (0.88, 0.80, 0.66), roughness=0.35),
    ]


def build_geometry(bm: bmesh.types.BMesh, bmap: dict[bmesh.types.BMVert, str]) -> None:
    # Compact hunched imp torso + glowing molten belly core
    torso = [
        ((0.0, 0.08, 1.05), 0.56, 0.50, (0, 0, 0)),
        ((0.0, 0.0, 1.75), 0.72, 0.60, (8, 0, 0)),
        ((0.0, -0.08, 2.35), 0.64, 0.54, (10, 0, 0)),
    ]
    C.add_lofted_tube(bm, torso, MAT_IMP_SKIN, sides=10, smooth=True, tag_bone="Torso", bone_map=bmap)
    C.add_faceted_icosphere(bm, 0.44, (0.0, -0.45, 1.72), MAT_EMBER_GLOW, subdivisions=1, scale=(0.95, 0.45, 1.1), tag_bone="Torso", bone_map=bmap)

    # Nimble crouched legs & claws flush on Z = 0.0
    for sx in (-1, 1):
        tag = "L" if sx < 0 else "R"
        leg = [
            ((sx * 0.42, 0.05, 1.12), 0.24, 0.26, (0, 0, 0)),
            ((sx * 0.44, -0.08, 0.55), 0.18, 0.20, (0, 0, 0)),
            ((sx * 0.44, 0.0, 0.20), 0.18, 0.20, (0, 0, 0)),
        ]
        C.add_lofted_tube(bm, leg, MAT_IMP_OBSIDIAN, sides=8, smooth=True, tag_bone=f"Leg{tag}", bone_map=bmap)
        C.add_faceted_box(bm, (0.44, 0.62, 0.24), (sx * 0.44, -0.14, 0.12), MAT_IMP_OBSIDIAN, 0.04, tag_bone=f"Leg{tag}", bone_map=bmap)
        # Clawed arms
        arm = [
            ((sx * 0.72, -0.05, 2.22), 0.20, 0.20, (0, sx * 35, 0)),
            ((sx * 1.12, -0.35, 1.75), 0.16, 0.16, (30, sx * 15, 0)),
            ((sx * 1.18, -0.78, 1.48), 0.18, 0.18, (65, 0, 0)),
        ]
        C.add_lofted_tube(bm, arm, MAT_IMP_SKIN, sides=6, smooth=True, tag_bone=f"Arm{tag}", bone_map=bmap)
        C.add_crystal_prism(bm, 0.10, 0.45, (sx * 1.18, -1.02, 1.42), MAT_HORN_BONE, sides=4, rot_deg=(90, 0, 0), tag_bone=f"Arm{tag}", bone_map=bmap)
        # Pyraxis-style bat-like ember wings on back
        wing = [
            ((sx * 0.45, 0.48, 2.15), 0.10, 0.42, (0, sx * 68, 0)),
            ((sx * 1.35, 0.78, 2.65), 0.08, 0.65, (-12, sx * 76, sx * -16)),
            ((sx * 2.05, 0.96, 2.85), 0.04, 0.24, (-18, sx * 84, sx * -20)),
        ]
        C.add_lofted_tube(bm, wing, MAT_WING_RED, sides=6, smooth=False, tag_bone="Torso", bone_map=bmap)

    # Barbed arrow imp tail curving behind +Y
    tail = [
        ((0.0, 0.48, 1.18), 0.12, 0.12, (75, 0, 0)),
        ((0.0, 1.15, 1.25), 0.09, 0.09, (55, 0, 0)),
        ((0.0, 1.62, 1.68), 0.06, 0.06, (25, 0, 0)),
    ]
    C.add_lofted_tube(bm, tail, MAT_IMP_OBSIDIAN, sides=6, smooth=True, tag_bone="Tail", bone_map=bmap)
    C.add_crystal_prism(bm, 0.22, 0.48, (0.0, 1.72, 1.92), MAT_EMBER_GLOW, sides=4, rot_deg=(-25, 0, 0), tag_bone="Tail", bone_map=bmap)

    # Oversized fierce grinning imp head, pointed ears & swept curved horns
    C.add_faceted_icosphere(bm, 0.76, (0.0, -0.18, 2.88), MAT_IMP_SKIN, subdivisions=2, scale=(1.08, 0.96, 0.92), tag_bone="Head", bone_map=bmap)
    for sx in (-1, 1):
        C.add_faceted_box(bm, (0.30, 0.16, 0.20), (sx * 0.30, -0.86, 2.96), MAT_EMBER_GLOW, 0.02, rot_deg=(0, 0, sx * -16), tag_bone="Head", bone_map=bmap)
        ear = [
            ((sx * 0.66, -0.15, 2.95), 0.16, 0.09, (0, sx * 68, 0)),
            ((sx * 1.18, -0.05, 3.16), 0.10, 0.05, (0, sx * 76, 0)),
            ((sx * 1.44, 0.0, 3.24), 0.02, 0.02, (0, sx * 80, 0)),
        ]
        C.add_lofted_tube(bm, ear, MAT_IMP_SKIN, sides=6, smooth=True, tag_bone="Head", bone_map=bmap)
        horn = [
            ((sx * 0.38, -0.22, 3.42), 0.18, 0.18, (-20, sx * 24, 0)),
            ((sx * 0.66, 0.08, 3.82), 0.12, 0.12, (-38, sx * 30, 0)),
            ((sx * 0.86, 0.42, 4.08), 0.03, 0.03, (-50, sx * 24, 0)),
        ]
        C.add_lofted_tube(bm, horn, MAT_IMP_OBSIDIAN, sides=6, smooth=True, tag_bone="Head", bone_map=bmap)


def build_armature() -> bpy.types.Object:
    arm_data = bpy.data.armatures.new("CinderImpArmature")
    arm_obj = bpy.data.objects.new("CinderImp", arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    specs = [
        ("HumanoidRootPart", None, (0, 0, 0), (0, 0, 1.0)),
        ("Torso", "HumanoidRootPart", (0, 0, 1.1), (0, -0.08, 2.35)),
        ("Head", "Torso", (0, -0.08, 2.35), (0, -0.2, 3.5)),
        ("Tail", "Torso", (0, 0.45, 1.18), (0, 1.72, 1.92)),
        ("ArmL", "Torso", (-0.68, -0.05, 2.2), (-1.18, -0.9, 1.45)),
        ("ArmR", "Torso", (0.68, -0.05, 2.2), (1.18, -0.9, 1.45)),
        ("LegL", "HumanoidRootPart", (-0.42, 0.05, 1.12), (-0.44, -0.1, 0.0)),
        ("LegR", "HumanoidRootPart", (0.42, 0.05, 1.12), (0.44, -0.1, 0.0)),
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

    clip("Idle", 32, [(1, {}), (16, {"Torso": (8, 0, 0), "Head": (-8, 0, 10), "Tail": (16, 0, 14)}), (32, {})])
    clip("Run", 14, [
        (1, {"LegL": (34, 0, 0), "LegR": (-30, 0, 0), "ArmL": (-26, 0, 0), "ArmR": (26, 0, 0), "Torso": (14, 0, 0)}),
        (7, {"LegL": (-30, 0, 0), "LegR": (34, 0, 0), "ArmL": (26, 0, 0), "ArmR": (-26, 0, 0), "Torso": (14, 0, 0)}),
        (14, {"LegL": (34, 0, 0), "LegR": (-30, 0, 0), "ArmL": (-26, 0, 0), "ArmR": (26, 0, 0), "Torso": (14, 0, 0)}),
    ])
    clip("Attack", 18, [(1, {}), (6, {"ArmL": (-55, 0, -20), "ArmR": (-55, 0, 20), "Torso": (-16, 0, 0)}), (11, {"ArmL": (48, 0, 10), "ArmR": (48, 0, -10), "Torso": (24, 0, 0)}), (18, {})])


def main() -> None:
    C.clear_scene()
    mats = create_materials()
    bm = bmesh.new()
    bmap: dict[bmesh.types.BMVert, str] = {}
    build_geometry(bm, bmap)
    idx_map = C.extract_bone_index_map(bm, bmap)
    mesh_obj = C.finalize_mesh("CinderImp_Mesh", bm, mats)
    arm_obj = build_armature()
    C.assign_bone_weights(mesh_obj, arm_obj, idx_map, "Torso")
    author_animations(arm_obj)
    C.reset_pose(arm_obj)
    for tr in arm_obj.animation_data.nla_tracks:
        tr.mute = True
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    C.validate_asset("CinderImp", [mesh_obj], tri_cap=2500, pivot_mode="floor")
    for tr in arm_obj.animation_data.nla_tracks:
        tr.mute = False
    C.export_roblox_asset("CinderImp", [arm_obj, mesh_obj], rigged=True)
    for tr in arm_obj.animation_data.nla_tracks:
        tr.mute = True
    C.reset_pose(arm_obj)
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    C.setup_studio_render([mesh_obj], "CinderImp_preview.png", resolution=640, samples=22, cam_azimuth_deg=-34.0, cam_elev_deg=16.0, distance_mult=2.25)
    print("BLENDER_EXPORT_OK: CinderImp")


if __name__ == "__main__":
    main()
