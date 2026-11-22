"""Headless Blender builder for GlacierYeti (Frostbite Cavern Boss, Issue #17).

Towering stylized frost-furred beast (~12.5 studs tall, <6,000 tris) with swept
glacier-ice horns, jagged translucent-look ice shoulder crystals & dorsal icicles,
blazing cyan eyes/maw, 16-bone HumanoidRootPart rig, and 5 NLA clips (Idle, Walk,
FrostBreath, IcicleSlam, Death).
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

MAT_FUR_WHITE = 0
MAT_FUR_FROST = 1
MAT_SKIN_SLATE = 2
MAT_ICE_SHARD = 3
MAT_ICE_GLOW = 4
MAT_CLAW_IVORY = 5
MAT_MAW_DARK = 6


def create_materials() -> list[bpy.types.Material]:
    return [
        C.make_material("YetiSnowFur", (0.86, 0.92, 0.97), roughness=0.72),
        C.make_material("YetiFrostFur", (0.52, 0.72, 0.88), roughness=0.68),
        C.make_material("YetiSlateSkin", (0.20, 0.28, 0.38), roughness=0.62),
        C.make_material("YetiIceCrystal", (0.48, 0.86, 1.0), roughness=0.12, metallic=0.06),
        C.make_material("YetiCyanGlow", (0.22, 0.92, 1.0), roughness=0.14, emission=(0.20, 0.90, 1.0), emission_strength=2.2),
        C.make_material("YetiClawIvory", (0.88, 0.92, 0.95), roughness=0.28),
        C.make_material("YetiMawDark", (0.06, 0.10, 0.16), roughness=0.50),
    ]


def add_leg(bm: bmesh.types.BMesh, side: int, bmap: dict[bmesh.types.BMVert, str]) -> None:
    tag = "L" if side < 0 else "R"
    x = side * 1.95
    # Heavy snow-beast foot + 3 icy claws resting on Z=0
    C.add_faceted_box(bm, (2.2, 2.75, 1.15), (x, -0.25, 0.575), MAT_SKIN_SLATE, 0.14, taper_top=(0.86, 0.88), tag_bone=f"Foot{tag}", bone_map=bmap)
    for cx in (-0.68, 0.0, 0.68):
        C.add_crystal_prism(bm, 0.24, 0.95, (x + cx, -1.72, 0.36), MAT_CLAW_IVORY, sides=5, rot_deg=(78, 0, 0), tag_bone=f"Foot{tag}", bone_map=bmap)
    # Shaggy lofted shin & thigh
    shin_rings = [
        ((x, -0.1, 1.05), 1.08, 1.12, (0, 0, 0)),
        ((x, 0.05, 2.45), 1.18, 1.22, (0, 0, 0)),
        ((x, 0.12, 3.65), 1.24, 1.28, (0, 0, 0)),
    ]
    C.add_lofted_tube(bm, shin_rings, MAT_FUR_FROST, sides=10, smooth=True, tag_bone=f"Shin{tag}", bone_map=bmap)
    thigh_rings = [
        ((x, 0.12, 3.45), 1.22, 1.26, (0, 0, 0)),
        ((x, 0.18, 4.95), 1.38, 1.40, (0, 0, 0)),
    ]
    C.add_lofted_tube(bm, thigh_rings, MAT_FUR_WHITE, sides=10, smooth=True, tag_bone=f"Thigh{tag}", bone_map=bmap)


def add_torso_and_head(bm: bmesh.types.BMesh, bmap: dict[bmesh.types.BMVert, str]) -> None:
    """Build hulking hunched yeti torso, frost mane, dorsal icicle ridge, and horned skull."""
    torso_rings = [
        ((0.0, 0.25, 4.65), 2.25, 1.75, (0, 0, 0)),
        ((0.0, 0.15, 6.25), 2.75, 2.15, (6, 0, 0)),
        ((0.0, -0.10, 8.25), 3.35, 2.45, (10, 0, 0)),
        ((0.0, -0.35, 10.15), 2.95, 2.15, (14, 0, 0)),
        ((0.0, -0.45, 11.05), 1.85, 1.45, (14, 0, 0)),
    ]
    C.add_lofted_tube(bm, torso_rings, MAT_FUR_WHITE, sides=12, smooth=True, tag_bone="Chest", bone_map=bmap)
    # Recessed slate chest plate + glowing glacier heart rune
    C.add_faceted_icosphere(bm, 1.65, (0.0, -1.85, 8.25), MAT_SKIN_SLATE, subdivisions=2, scale=(1.2, 0.45, 1.1), tag_bone="Chest", bone_map=bmap)
    C.add_crystal_prism(bm, 0.58, 1.55, (0.0, -2.32, 8.35), MAT_ICE_GLOW, sides=6, rot_deg=(12, 0, 0), tag_bone="Chest", bone_map=bmap)
    # Jagged dorsal ice spikes & frost-blue fur mantle across upper back/shoulders
    for idx, (px, py, pz, rot, h) in enumerate([
        (0.0, 1.25, 11.45, (-26, 0, 0), 2.5),
        (-1.35, 1.20, 10.95, (-24, -22, 0), 2.0),
        (1.35, 1.20, 10.95, (-24, 22, 0), 2.0),
        (0.0, 1.85, 9.55, (-46, 0, 0), 1.9),
    ]):
        C.add_crystal_prism(bm, 0.44, h, (px, py, pz), MAT_ICE_SHARD if idx % 2 else MAT_ICE_GLOW, sides=5, rot_deg=rot, tag_bone="Chest", bone_map=bmap)
    for sx in (-1, 1):
        C.add_faceted_icosphere(bm, 1.85, (sx * 3.45, -0.10, 9.85), MAT_FUR_FROST, subdivisions=1, scale=(1.05, 1.0, 0.92), noise_amp=0.14, seed=8 + sx, tag_bone="Chest", bone_map=bmap)
        C.add_crystal_prism(bm, 0.50, 2.1, (sx * 4.05, 0.15, 11.15), MAT_ICE_SHARD, sides=5, rot_deg=(-12, sx * 26, 0), tag_bone="Chest", bone_map=bmap)

    # Fierce low-set yeti head facing -Y + swept curved glacier horns
    C.add_faceted_icosphere(bm, 1.48, (0.0, -1.65, 10.55), MAT_FUR_WHITE, subdivisions=2, scale=(1.08, 0.98, 0.95), tag_bone="Head", bone_map=bmap)
    C.add_faceted_box(bm, (2.15, 1.05, 1.15), (0.0, -2.55, 10.25), MAT_SKIN_SLATE, 0.12, tag_bone="Head", bone_map=bmap)
    C.add_faceted_box(bm, (1.65, 0.52, 0.56), (0.0, -2.85, 9.85), MAT_MAW_DARK, 0.04, tag_bone="Head", bone_map=bmap)
    for sx in (-1, 1):
        # Blazing cyan eyes & angled snow brow
        C.add_faceted_box(bm, (0.52, 0.25, 0.30), (sx * 0.58, -3.02, 10.58), MAT_ICE_GLOW, 0.02, rot_deg=(0, 0, sx * -12), tag_bone="Head", bone_map=bmap)
        C.add_crystal_prism(bm, 0.14, 0.45, (sx * 0.56, -2.98, 9.86), MAT_CLAW_IVORY, sides=4, rot_deg=(12, 0, 0), tag_bone="Head", bone_map=bmap)
        # Sweeping curved Pyraxis-style ram/glacier horns!
        horn_rings = [
            ((sx * 1.15, -1.65, 11.15), 0.42, 0.40, (0, sx * 60, 0)),
            ((sx * 2.15, -1.45, 11.85), 0.32, 0.30, (-14, sx * 42, 0)),
            ((sx * 2.85, -1.75, 12.45), 0.18, 0.18, (22, sx * 18, 0)),
            ((sx * 2.65, -2.15, 12.95), 0.04, 0.04, (40, sx * -10, 0)),
        ]
        C.add_lofted_tube(bm, horn_rings, MAT_ICE_SHARD, sides=8, smooth=True, tag_bone="Head", bone_map=bmap)


def add_arm(bm: bmesh.types.BMesh, side: int, bmap: dict[bmesh.types.BMVert, str]) -> None:
    tag = "L" if side < 0 else "R"
    upper = [
        ((side * 3.75, -0.15, 9.15), 1.18, 1.18, (0, 0, 0)),
        ((side * 4.25, -0.35, 6.85), 1.06, 1.10, (0, 0, 0)),
    ]
    C.add_lofted_tube(bm, upper, MAT_FUR_WHITE, sides=10, smooth=True, tag_bone=f"UpperArm{tag}", bone_map=bmap)
    forearm = [
        ((side * 4.25, -0.35, 6.85), 1.08, 1.10, (0, 0, 0)),
        ((side * 4.65, -0.65, 4.15), 1.38, 1.42, (0, 0, 0)),
    ]
    C.add_lofted_tube(bm, forearm, MAT_FUR_FROST, sides=10, smooth=True, tag_bone=f"Forearm{tag}", bone_map=bmap)
    C.add_crystal_prism(bm, 0.36, 1.45, (side * 5.65, -0.55, 5.25), MAT_ICE_GLOW, sides=5, rot_deg=(0, side * 62, 0), tag_bone=f"Forearm{tag}", bone_map=bmap)
    # Huge clawed ice-knuckle fist
    C.add_faceted_box(bm, (2.45, 2.35, 1.85), (side * 4.72, -0.82, 3.15), MAT_SKIN_SLATE, 0.16, tag_bone=f"Hand{tag}", bone_map=bmap)
    for dy in (-0.65, 0.0, 0.65):
        C.add_crystal_prism(bm, 0.22, 0.92, (side * 4.72, -0.82 + dy, 2.02), MAT_CLAW_IVORY, sides=4, rot_deg=(180, 0, 0), tag_bone=f"Hand{tag}", bone_map=bmap)


def build_armature() -> bpy.types.Object:
    arm_data = bpy.data.armatures.new("GlacierYetiArmature")
    arm_obj = bpy.data.objects.new("GlacierYeti", arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    specs = [
        ("HumanoidRootPart", None, (0, 0, 0), (0, 0, 2.0)),
        ("Pelvis", "HumanoidRootPart", (0, 0.2, 4.7), (0, 0.2, 6.2)),
        ("Chest", "Pelvis", (0, 0.2, 6.2), (0, -0.3, 10.4)),
        ("Head", "Chest", (0, -1.3, 10.1), (0, -2.5, 11.2)),
        ("UpperArmL", "Chest", (-3.5, -0.1, 9.2), (-4.25, -0.35, 6.8)),
        ("ForearmL", "UpperArmL", (-4.25, -0.35, 6.8), (-4.7, -0.75, 4.0)),
        ("HandL", "ForearmL", (-4.7, -0.75, 4.0), (-4.72, -0.82, 2.0)),
        ("UpperArmR", "Chest", (3.5, -0.1, 9.2), (4.25, -0.35, 6.8)),
        ("ForearmR", "UpperArmR", (4.25, -0.35, 6.8), (4.7, -0.75, 4.0)),
        ("HandR", "ForearmR", (4.7, -0.75, 4.0), (4.72, -0.82, 2.0)),
        ("ThighL", "Pelvis", (-1.95, 0.15, 5.0), (-1.95, 0.1, 3.5)),
        ("ShinL", "ThighL", (-1.95, 0.1, 3.5), (-1.95, -0.05, 1.1)),
        ("FootL", "ShinL", (-1.95, -0.05, 1.1), (-1.95, -1.6, 0.2)),
        ("ThighR", "Pelvis", (1.95, 0.15, 5.0), (1.95, 0.1, 3.5)),
        ("ShinR", "ThighR", (1.95, 0.1, 3.5), (1.95, -0.05, 1.1)),
        ("FootR", "ShinR", (1.95, -0.05, 1.1), (1.95, -1.6, 0.2)),
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
    """Author Idle, Walk, FrostBreath, IcicleSlam, and Death NLA clips (24 FPS)."""
    def clip(name: str, end_f: int, frames: list[tuple[int, dict[str, tuple[float, float, float]], tuple[float, float, float] | None]]) -> None:
        anim = arm_obj.animation_data or arm_obj.animation_data_create()
        act = bpy.data.actions.new(name=name)
        anim.action = act
        for frame, rots, pel_loc in frames:
            for pb in arm_obj.pose.bones:
                pb.rotation_mode = "XYZ"
                deg = rots.get(pb.name, (0.0, 0.0, 0.0))
                pb.rotation_euler = Euler(tuple(math.radians(a) for a in deg), "XYZ")
                pb.keyframe_insert(data_path="rotation_euler", frame=frame)
                if pb.name == "Pelvis":
                    pb.location = Vector(pel_loc or (0.0, 0.0, 0.0))
                    pb.keyframe_insert(data_path="location", frame=frame)
        C.push_action_to_nla(arm_obj, act, name, end_f)

    clip("Idle", 48, [
        (1, {"UpperArmL": (6, 0, -6), "UpperArmR": (6, 0, 6)}, None),
        (24, {"Chest": (-6, 0, 0), "Head": (4, 0, 8), "UpperArmL": (12, 0, -10), "UpperArmR": (12, 0, 10)}, (0, 0, 0.22)),
        (48, {"UpperArmL": (6, 0, -6), "UpperArmR": (6, 0, 6)}, None),
    ])
    clip("Walk", 28, [
        (1, {"ThighL": (24, 0, 0), "ThighR": (-20, 0, 0), "UpperArmL": (-18, 0, -6), "UpperArmR": (20, 0, 6), "Chest": (6, 0, -8)}, (0, 0, 0.15)),
        (14, {"ThighL": (-20, 0, 0), "ThighR": (24, 0, 0), "UpperArmL": (20, 0, -6), "UpperArmR": (-18, 0, 6), "Chest": (6, 0, 8)}, (0, 0, 0.15)),
        (28, {"ThighL": (24, 0, 0), "ThighR": (-20, 0, 0), "UpperArmL": (-18, 0, -6), "UpperArmR": (20, 0, 6), "Chest": (6, 0, -8)}, (0, 0, 0.15)),
    ])
    clip("FrostBreath", 54, [
        (1, {}, None),
        (16, {"Chest": (-22, 0, 0), "Head": (-18, 0, 0), "UpperArmL": (-55, 0, -35), "UpperArmR": (-55, 0, 35)}, (0, 0, 0.35)),
        (24, {"Chest": (20, 0, -24), "Head": (12, 0, -20), "UpperArmL": (20, 0, -30), "UpperArmR": (20, 0, 30)}, (0, 0, -0.35)),
        (42, {"Chest": (20, 0, 24), "Head": (12, 0, 20), "UpperArmL": (20, 0, -30), "UpperArmR": (20, 0, 30)}, (0, 0, -0.35)),
        (54, {}, None),
    ])
    clip("IcicleSlam", 60, [
        (1, {}, None),
        (24, {"Chest": (-24, 0, 0), "UpperArmL": (-140, 0, -18), "UpperArmR": (-140, 0, 18)}, (0, 0, 0.45)),
        (28, {"Chest": (34, 0, 0), "UpperArmL": (48, 0, -8), "UpperArmR": (48, 0, 8)}, (0, 0, -1.2)),
        (42, {"Chest": (30, 0, 0), "UpperArmL": (44, 0, -8), "UpperArmR": (44, 0, 8)}, (0, 0, -1.0)),
        (60, {}, None),
    ])
    clip("Death", 48, [
        (1, {}, None),
        (18, {"Chest": (-26, 0, 10), "UpperArmL": (-45, 0, -32), "UpperArmR": (-40, 0, 32)}, (0, 0, -0.4)),
        (48, {"Chest": (76, 0, 12), "UpperArmL": (78, 0, -28), "UpperArmR": (70, 0, 28), "ThighL": (-40, 0, 0), "ShinL": (58, 0, 0), "ThighR": (-40, 0, 0), "ShinR": (58, 0, 0)}, (0, 0, -3.8)),
    ])


def main() -> None:
    C.clear_scene()
    mats = create_materials()
    bm = bmesh.new()
    bmap: dict[bmesh.types.BMVert, str] = {}
    add_leg(bm, -1, bmap)
    add_leg(bm, 1, bmap)
    add_torso_and_head(bm, bmap)
    add_arm(bm, -1, bmap)
    add_arm(bm, 1, bmap)

    idx_map = C.extract_bone_index_map(bm, bmap)
    mesh_obj = C.finalize_mesh("GlacierYeti_Mesh", bm, mats)
    arm_obj = build_armature()
    C.assign_bone_weights(mesh_obj, arm_obj, idx_map, "Chest")
    author_animations(arm_obj)
    C.reset_pose(arm_obj)

    for tr in arm_obj.animation_data.nla_tracks:
        tr.mute = True
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    C.validate_asset("GlacierYeti", [mesh_obj], tri_cap=6000, pivot_mode="floor")

    for tr in arm_obj.animation_data.nla_tracks:
        tr.mute = False
    C.export_roblox_asset("GlacierYeti", [arm_obj, mesh_obj], rigged=True)

    for tr in arm_obj.animation_data.nla_tracks:
        tr.mute = True
    C.reset_pose(arm_obj)
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    C.setup_studio_render([mesh_obj], "GlacierYeti_preview.png", resolution=768, samples=24, cam_azimuth_deg=-34.0, cam_elev_deg=15.0, distance_mult=2.25)
    print("BLENDER_EXPORT_OK: GlacierYeti")


if __name__ == "__main__":
    main()
