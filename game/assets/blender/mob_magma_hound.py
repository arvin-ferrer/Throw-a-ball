"""Headless Blender builder for MagmaHound (Molten Caldera PvE Mob 2, Issue #17).

Fierce Pyraxis-grade charred-obsidian volcanic hound (~3.8 studs tall, ~5.8 studs long,
<2,500 tris) with beveled volcanic back plates, blazing molten spine spikes & chest vent,
curved obsidian brow horns, fiery orange eyes, 12-bone HumanoidRootPart rig, and
Idle/Run/Attack clips.
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

MAT_HOUND_OBSIDIAN = 0
MAT_HOUND_BASALT = 1
MAT_LAVA_GLOW = 2
MAT_FANG_IVORY = 3


def create_materials() -> list[bpy.types.Material]:
    return [
        C.make_material("HoundObsidian", (0.11, 0.08, 0.09), roughness=0.58, metallic=0.12),
        C.make_material("HoundBasaltPlate", (0.26, 0.16, 0.13), roughness=0.68),
        C.make_material("HoundLavaGlow", (1.0, 0.34, 0.03), roughness=0.20, emission=(1.0, 0.32, 0.02), emission_strength=2.4),
        C.make_material("HoundFangIvory", (0.90, 0.84, 0.72), roughness=0.32),
    ]


def build_geometry(bm: bmesh.types.BMesh, bmap: dict[bmesh.types.BMVert, str]) -> None:
    body_rings = [
        ((0.0, 1.92, 1.92), 0.56, 0.54, (90, 0, 0)),
        ((0.0, 1.02, 1.96), 0.86, 0.82, (90, 0, 0)),
        ((0.0, -0.18, 2.08), 0.98, 0.94, (90, 0, 0)),
        ((0.0, -1.25, 2.25), 1.10, 1.04, (90, 0, 0)),
        ((0.0, -1.75, 2.34), 0.82, 0.78, (90, 0, 0)),
    ]
    C.add_lofted_tube(bm, body_rings, MAT_HOUND_OBSIDIAN, sides=10, smooth=True, tag_bone="Torso", bone_map=bmap)
    # Glowing magma collar chest vent & stepped Pyraxis dorsal plates + flame spikes
    C.add_faceted_icosphere(bm, 0.72, (0.0, -1.55, 2.02), MAT_LAVA_GLOW, subdivisions=1, scale=(1.05, 0.55, 0.95), tag_bone="Torso", bone_map=bmap)
    for y_p, z_p, h in [(0.75, 2.88, 0.90), (-0.25, 3.08, 1.15), (-1.15, 3.35, 1.38)]:
        C.add_faceted_box(bm, (1.15, 0.72, 0.30), (0.0, y_p, z_p), MAT_HOUND_BASALT, 0.05, tag_bone="Torso", bone_map=bmap)
        C.add_crystal_prism(bm, 0.20, h, (0.0, y_p, z_p + 0.45), MAT_LAVA_GLOW, sides=4, rot_deg=(-28, 0, 0), tag_bone="Torso", bone_map=bmap)

    # Fiery blade-tipped whip tail
    tail = [
        ((0.0, 1.92, 2.02), 0.22, 0.22, (70, 0, 0)),
        ((0.0, 2.68, 2.38), 0.18, 0.18, (50, 0, 0)),
        ((0.0, 3.25, 2.86), 0.12, 0.12, (35, 0, 0)),
    ]
    C.add_lofted_tube(bm, tail, MAT_HOUND_OBSIDIAN, sides=6, smooth=True, tag_bone="Pelvis", bone_map=bmap)
    C.add_crystal_prism(bm, 0.24, 0.65, (0.0, 3.45, 3.08), MAT_LAVA_GLOW, sides=4, rot_deg=(-45, 0, 0), tag_bone="Pelvis", bone_map=bmap)

    # Fierce volcanic hound head, fangs, swept horns & blazing eyes
    head_rings = [
        ((0.0, -1.62, 2.58), 0.84, 0.78, (90, 0, 0)),
        ((0.0, -2.38, 2.52), 0.76, 0.68, (96, 0, 0)),
        ((0.0, -3.18, 2.38), 0.48, 0.42, (98, 0, 0)),
        ((0.0, -3.52, 2.34), 0.34, 0.30, (98, 0, 0)),
    ]
    C.add_lofted_tube(bm, head_rings, MAT_HOUND_BASALT, sides=10, smooth=True, tag_bone="Head", bone_map=bmap)
    for sx in (-1, 1):
        C.add_faceted_box(bm, (0.30, 0.28, 0.18), (sx * 0.58, -2.55, 2.82), MAT_LAVA_GLOW, 0.02, rot_deg=(0, 0, sx * -14), tag_bone="Head", bone_map=bmap)
        C.add_crystal_prism(bm, 0.10, 0.42, (sx * 0.24, -3.28, 2.02), MAT_FANG_IVORY, sides=4, rot_deg=(175, 0, 0), tag_bone="Head", bone_map=bmap)
        horn = [
            ((sx * 0.52, -1.95, 3.12), 0.18, 0.18, (-25, sx * 22, 0)),
            ((sx * 0.78, -1.52, 3.62), 0.12, 0.12, (-45, sx * 26, 0)),
            ((sx * 0.96, -1.08, 3.92), 0.03, 0.03, (-55, sx * 22, 0)),
        ]
        C.add_lofted_tube(bm, horn, MAT_FANG_IVORY, sides=6, smooth=True, tag_bone="Head", bone_map=bmap)

    for name, x, y in [("LegFL", -0.68, -1.18), ("LegFR", 0.68, -1.18), ("LegBL", -0.66, 1.38), ("LegBR", 0.66, 1.38)]:
        leg = [
            ((x, y, 1.85), 0.35, 0.38, (0, 0, 0)),
            ((x, y, 1.05), 0.25, 0.26, (0, 0, 0)),
            ((x, y, 0.34), 0.21, 0.22, (0, 0, 0)),
        ]
        C.add_lofted_tube(bm, leg, MAT_HOUND_OBSIDIAN, sides=8, smooth=True, tag_bone=f"{name}_Upper", bone_map=bmap)
        C.add_faceted_box(bm, (0.48, 0.62, 0.36), (x, y - 0.08, 0.18), MAT_LAVA_GLOW, 0.05, taper_top=(0.82, 0.82), tag_bone=f"{name}_Paw", bone_map=bmap)


def build_armature() -> bpy.types.Object:
    arm_data = bpy.data.armatures.new("MagmaHoundArmature")
    arm_obj = bpy.data.objects.new("MagmaHound", arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    specs = [
        ("HumanoidRootPart", None, (0, 0, 0), (0, 0, 1.0)),
        ("Pelvis", "HumanoidRootPart", (0, 1.5, 1.98), (0, 0.8, 2.02)),
        ("Torso", "Pelvis", (0, 0.8, 2.02), (0, -1.5, 2.35)),
        ("Head", "Torso", (0, -1.5, 2.35), (0, -3.5, 2.35)),
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

    clip("Idle", 36, [(1, {}), (18, {"Head": (-10, 0, -8), "Torso": (-3, 0, 0)}), (36, {})])
    clip("Run", 14, [
        (1, {"LegFL_Upper": (38, 0, 0), "LegFR_Upper": (32, 0, 0), "LegBL_Upper": (-36, 0, 0), "LegBR_Upper": (-40, 0, 0), "Torso": (8, 0, 0)}),
        (7, {"LegFL_Upper": (-36, 0, 0), "LegFR_Upper": (-32, 0, 0), "LegBL_Upper": (38, 0, 0), "LegBR_Upper": (34, 0, 0), "Torso": (-6, 0, 0)}),
        (14, {"LegFL_Upper": (38, 0, 0), "LegFR_Upper": (32, 0, 0), "LegBL_Upper": (-36, 0, 0), "LegBR_Upper": (-40, 0, 0), "Torso": (8, 0, 0)}),
    ])
    clip("Attack", 18, [(1, {}), (6, {"Torso": (-18, 0, 0), "Head": (-14, 0, 0)}), (11, {"Torso": (24, 0, 0), "Head": (18, 0, 0), "LegFL_Upper": (42, 0, 0), "LegFR_Upper": (42, 0, 0)}), (18, {})])


def main() -> None:
    C.clear_scene()
    mats = create_materials()
    bm = bmesh.new()
    bmap: dict[bmesh.types.BMVert, str] = {}
    build_geometry(bm, bmap)
    idx_map = C.extract_bone_index_map(bm, bmap)
    mesh_obj = C.finalize_mesh("MagmaHound_Mesh", bm, mats)
    arm_obj = build_armature()
    C.assign_bone_weights(mesh_obj, arm_obj, idx_map, "Torso")
    author_animations(arm_obj)
    C.reset_pose(arm_obj)
    for tr in arm_obj.animation_data.nla_tracks:
        tr.mute = True
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    C.validate_asset("MagmaHound", [mesh_obj], tri_cap=2500, pivot_mode="floor")
    for tr in arm_obj.animation_data.nla_tracks:
        tr.mute = False
    C.export_roblox_asset("MagmaHound", [arm_obj, mesh_obj], rigged=True)
    for tr in arm_obj.animation_data.nla_tracks:
        tr.mute = True
    C.reset_pose(arm_obj)
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    C.setup_studio_render([mesh_obj], "MagmaHound_preview.png", resolution=640, samples=22, cam_azimuth_deg=-38.0, cam_elev_deg=16.0, distance_mult=2.25)
    print("BLENDER_EXPORT_OK: MagmaHound")


if __name__ == "__main__":
    main()
