"""Headless Blender builder for BrambleBoar (Emerald Meadow PvE Mob).

Pyraxis-grade lofted muscular quadruped (~4.0 studs tall, ~5.6 studs long, <2,500 tris)
with beveled bark-armor shoulder plates, sweeping curved ivory tusks, jagged emerald-briar
dorsal crest, glowing amber eyes, 12-bone HumanoidRootPart rig, and Idle/Walk/Charge/Attack clips.
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

MAT_HIDE_DARK = 0
MAT_HIDE_BARK = 1
MAT_SNOUT_TAN = 2
MAT_TUSK_IVORY = 3
MAT_BRIAR_GREEN = 4
MAT_THORN_GLOW = 5
MAT_EYE_AMBER = 6
MAT_HOOF_DARK = 7


def create_materials() -> list[bpy.types.Material]:
    return [
        C.make_material("BoarHideDark", (0.20, 0.13, 0.09), roughness=0.78),
        C.make_material("BoarArmorBark", (0.34, 0.22, 0.15), roughness=0.70),
        C.make_material("BoarSnoutTan", (0.58, 0.36, 0.26), roughness=0.62),
        C.make_material("BoarTuskIvory", (0.92, 0.87, 0.74), roughness=0.32),
        C.make_material("BoarBriarGreen", (0.10, 0.44, 0.16), roughness=0.72),
        C.make_material("BoarThornGlow", (0.20, 0.92, 0.44), roughness=0.22, emission=(0.18, 0.88, 0.40), emission_strength=1.9),
        C.make_material("BoarEyeAmber", (1.0, 0.68, 0.08), roughness=0.12, emission=(1.0, 0.62, 0.06), emission_strength=2.4),
        C.make_material("BoarHoof", (0.08, 0.07, 0.07), roughness=0.45),
    ]


def add_body_and_crest(bm: bmesh.types.BMesh, bmap: dict[bmesh.types.BMVert, str]) -> None:
    """Loft stout muscular boar torso, beveled Pyraxis-style dorsal bark plates, and briar crest."""
    # Muscular lofted barrel torso running along Y (+Y rear -> -Y chest)
    body_rings = [
        ((0.0, 2.05, 1.95), 0.72, 0.68, (90, 0, 0)),
        ((0.0, 1.35, 2.05), 1.28, 1.18, (90, 0, 0)),
        ((0.0, 0.35, 2.18), 1.48, 1.35, (90, 0, 0)),
        ((0.0, -0.75, 2.25), 1.56, 1.42, (90, 0, 0)),
        ((0.0, -1.55, 2.10), 1.18, 1.08, (90, 0, 0)),
    ]
    C.add_lofted_tube(bm, body_rings, MAT_HIDE_DARK, sides=10, smooth=True, tag_bone="Torso", bone_map=bmap)

    # Pyraxis-style beveled bark armor plates & thorny briar spine ridge
    for idx, (y_pos, z_pos, w, d) in enumerate([(1.15, 3.12, 1.45, 0.85), (0.20, 3.36, 1.75, 0.95), (-0.75, 3.45, 1.85, 0.95)]):
        C.add_faceted_box(bm, (w, d, 0.36), (0.0, y_pos, z_pos), MAT_HIDE_BARK, 0.06, rot_deg=(-6, 0, 0), tag_bone="Torso", bone_map=bmap)
        C.add_faceted_icosphere(bm, 0.48, (0.0, y_pos + 0.05, z_pos + 0.30), MAT_BRIAR_GREEN, subdivisions=1, scale=(1.15, 1.0, 0.55), noise_amp=0.14, seed=10 + idx, tag_bone="Torso", bone_map=bmap)
        C.add_crystal_prism(bm, 0.16, 0.75, (0.0, y_pos, z_pos + 0.58), MAT_THORN_GLOW if idx == 2 else MAT_BRIAR_GREEN, sides=4, rot_deg=(-24, 0, 0), tag_bone="Torso", bone_map=bmap)
        for s in (-1, 1):
            C.add_crystal_prism(bm, 0.12, 0.55, (s * 0.65, y_pos, z_pos + 0.40), MAT_BRIAR_GREEN, sides=4, rot_deg=(-18, s * 28, 0), tag_bone="Torso", bone_map=bmap)

    # Curled lofted tail at rear (+Y)
    tail_rings = [
        ((0.0, 2.02, 2.15), 0.14, 0.14, (75, 0, 0)),
        ((0.0, 2.48, 2.38), 0.11, 0.11, (45, 0, 0)),
        ((0.0, 2.62, 2.75), 0.07, 0.07, (10, 0, 0)),
    ]
    C.add_lofted_tube(bm, tail_rings, MAT_HIDE_BARK, sides=6, smooth=True, tag_bone="Pelvis", bone_map=bmap)


def add_head_and_tusks(bm: bmesh.types.BMesh, bmap: dict[bmesh.types.BMVert, str]) -> None:
    """Build fierce wedge boar head, broad snout, pointed ears, glowing eyes, and curved tusks."""
    head_rings = [
        ((0.0, -1.35, 2.12), 1.12, 1.05, (90, 0, 0)),
        ((0.0, -2.05, 1.98), 1.02, 0.92, (98, 0, 0)),
        ((0.0, -2.70, 1.72), 0.68, 0.60, (102, 0, 0)),
        ((0.0, -3.02, 1.62), 0.52, 0.44, (102, 0, 0)),
    ]
    C.add_lofted_tube(bm, head_rings, MAT_HIDE_BARK, sides=10, smooth=True, tag_bone="Head", bone_map=bmap)
    # Snout nose disk + nostrils
    C.add_faceted_box(bm, (0.86, 0.24, 0.64), (0.0, -3.05, 1.62), MAT_SNOUT_TAN, 0.08, rot_deg=(12, 0, 0), tag_bone="Head", bone_map=bmap)
    for s in (-1, 1):
        C.add_faceted_box(bm, (0.14, 0.12, 0.20), (s * 0.20, -3.18, 1.64), MAT_HOOF_DARK, 0.02, tag_bone="Head", bone_map=bmap)
        # Angled brow armor & glowing amber eyes
        C.add_faceted_box(bm, (0.48, 0.45, 0.20), (s * 0.72, -2.05, 2.48), MAT_HIDE_DARK, 0.04, rot_deg=(14, s * -18, s * 14), tag_bone="Head", bone_map=bmap)
        C.add_faceted_icosphere(bm, 0.20, (s * 0.74, -2.18, 2.26), MAT_EYE_AMBER, subdivisions=1, scale=(0.8, 0.9, 0.8), tag_bone="Head", bone_map=bmap)
        # Flared pointed ears
        ear_rings = [
            ((s * 0.78, -1.62, 2.75), 0.28, 0.14, (0, s * 32, 0)),
            ((s * 1.18, -1.58, 3.22), 0.22, 0.10, (0, s * 42, 0)),
            ((s * 1.42, -1.52, 3.55), 0.05, 0.04, (0, s * 48, 0)),
        ]
        C.add_lofted_tube(bm, ear_rings, MAT_HIDE_DARK, sides=6, smooth=True, tag_bone="Head", bone_map=bmap)
        # Sweeping curved ivory tusks (Pyraxis horn style!)
        tusk_rings = [
            ((s * 0.52, -2.55, 1.42), 0.20, 0.18, (80, s * 35, 0)),
            ((s * 0.96, -2.92, 1.56), 0.16, 0.15, (55, s * 50, 0)),
            ((s * 1.18, -3.12, 2.02), 0.10, 0.10, (25, s * 32, 0)),
            ((s * 1.12, -3.04, 2.52), 0.025, 0.025, (8, s * 10, 0)),
        ]
        C.add_lofted_tube(bm, tusk_rings, MAT_TUSK_IVORY, sides=8, smooth=True, tag_bone="Head", bone_map=bmap)


def add_legs(bm: bmesh.types.BMesh, bmap: dict[bmesh.types.BMVert, str]) -> None:
    """Build 4 stout lofted boar legs tapering into hooves resting flush on Z = 0.0."""
    legs = [
        ("LegFL", -0.95, -1.05),
        ("LegFR", 0.95, -1.05),
        ("LegBL", -0.92, 1.25),
        ("LegBR", 0.92, 1.25),
    ]
    for name, x, y in legs:
        upper_rings = [
            ((x, y, 1.85), 0.48, 0.52, (0, 0, 0)),
            ((x, y, 1.10), 0.36, 0.38, (0, 0, 0)),
            ((x, y, 0.52), 0.30, 0.32, (0, 0, 0)),
        ]
        C.add_lofted_tube(bm, upper_rings, MAT_HIDE_DARK, sides=8, smooth=True, tag_bone=f"{name}_Upper", bone_map=bmap)
        C.add_faceted_box(bm, (0.64, 0.72, 0.54), (x, y - 0.04, 0.27), MAT_HOOF_DARK, 0.06, taper_top=(0.86, 0.86), tag_bone=f"{name}_Hoof", bone_map=bmap)


def build_armature() -> bpy.types.Object:
    arm_data = bpy.data.armatures.new("BrambleBoarArmature")
    arm_obj = bpy.data.objects.new("BrambleBoar", arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    specs = [
        ("HumanoidRootPart", None, (0, 0, 0), (0, 0, 1.0)),
        ("Pelvis", "HumanoidRootPart", (0, 1.4, 2.0), (0, 0.8, 2.1)),
        ("Torso", "Pelvis", (0, 0.8, 2.1), (0, -1.3, 2.15)),
        ("Head", "Torso", (0, -1.3, 2.15), (0, -3.0, 1.7)),
        ("LegFL_Upper", "Torso", (-0.95, -1.05, 1.85), (-0.95, -1.05, 0.55)),
        ("LegFL_Hoof", "LegFL_Upper", (-0.95, -1.05, 0.55), (-0.95, -1.15, 0.0)),
        ("LegFR_Upper", "Torso", (0.95, -1.05, 1.85), (0.95, -1.05, 0.55)),
        ("LegFR_Hoof", "LegFR_Upper", (0.95, -1.05, 0.55), (0.95, -1.15, 0.0)),
        ("LegBL_Upper", "Pelvis", (-0.92, 1.25, 1.85), (-0.92, 1.25, 0.55)),
        ("LegBL_Hoof", "LegBL_Upper", (-0.92, 1.25, 0.55), (-0.92, 1.15, 0.0)),
        ("LegBR_Upper", "Pelvis", (0.92, 1.25, 1.85), (0.92, 1.25, 0.55)),
        ("LegBR_Hoof", "LegBR_Upper", (0.92, 1.25, 0.55), (0.92, 1.15, 0.0)),
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
    """Author Idle, Walk, Charge, and Attack NLA clips (24 FPS)."""
    def make_clip(name: str, end_f: int, keys: list[tuple[int, dict[str, tuple[float, float, float]]]]) -> None:
        anim = arm_obj.animation_data or arm_obj.animation_data_create()
        act = bpy.data.actions.new(name=name)
        anim.action = act
        for frame, rots in keys:
            for pb in arm_obj.pose.bones:
                pb.rotation_mode = "XYZ"
                deg = rots.get(pb.name, (0.0, 0.0, 0.0))
                pb.rotation_euler = Euler(tuple(math.radians(a) for a in deg), "XYZ")
                pb.keyframe_insert(data_path="rotation_euler", frame=frame)
        C.push_action_to_nla(arm_obj, act, name, end_f)

    make_clip("Idle", 38, [
        (1, {}),
        (19, {"Head": (12, 0, 0), "Torso": (-3, 0, 0)}),
        (38, {}),
    ])
    make_clip("Walk", 18, [
        (1, {"LegFL_Upper": (28, 0, 0), "LegBR_Upper": (28, 0, 0), "LegFR_Upper": (-24, 0, 0), "LegBL_Upper": (-24, 0, 0)}),
        (10, {"LegFL_Upper": (-24, 0, 0), "LegBR_Upper": (-24, 0, 0), "LegFR_Upper": (28, 0, 0), "LegBL_Upper": (28, 0, 0)}),
        (18, {"LegFL_Upper": (28, 0, 0), "LegBR_Upper": (28, 0, 0), "LegFR_Upper": (-24, 0, 0), "LegBL_Upper": (-24, 0, 0)}),
    ])
    make_clip("Charge", 14, [
        (1, {"Head": (24, 0, 0), "Torso": (8, 0, 0), "LegFL_Upper": (42, 0, 0), "LegFR_Upper": (38, 0, 0), "LegBL_Upper": (-38, 0, 0), "LegBR_Upper": (-42, 0, 0)}),
        (7, {"Head": (28, 0, 0), "Torso": (-6, 0, 0), "LegFL_Upper": (-40, 0, 0), "LegFR_Upper": (-36, 0, 0), "LegBL_Upper": (40, 0, 0), "LegBR_Upper": (36, 0, 0)}),
        (14, {"Head": (24, 0, 0), "Torso": (8, 0, 0), "LegFL_Upper": (42, 0, 0), "LegFR_Upper": (38, 0, 0), "LegBL_Upper": (-38, 0, 0), "LegBR_Upper": (-42, 0, 0)}),
    ])
    make_clip("Attack", 19, [
        (1, {}),
        (7, {"Head": (32, 0, 0), "Torso": (10, 0, 0)}),
        (12, {"Head": (-36, 0, 0), "Torso": (-12, 0, 0), "LegFL_Upper": (-18, 0, 0), "LegFR_Upper": (-18, 0, 0)}),
        (19, {}),
    ])


def main() -> None:
    C.clear_scene()
    mats = create_materials()
    bm = bmesh.new()
    bmap: dict[bmesh.types.BMVert, str] = {}
    add_body_and_crest(bm, bmap)
    add_head_and_tusks(bm, bmap)
    add_legs(bm, bmap)

    idx_map = C.extract_bone_index_map(bm, bmap)
    mesh_obj = C.finalize_mesh("BrambleBoar_Mesh", bm, mats)
    arm_obj = build_armature()
    C.assign_bone_weights(mesh_obj, arm_obj, idx_map, "Torso")
    author_animations(arm_obj)
    C.reset_pose(arm_obj)

    for tr in arm_obj.animation_data.nla_tracks:
        tr.mute = True
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    C.validate_asset("BrambleBoar", [mesh_obj], tri_cap=2500, pivot_mode="floor")

    for tr in arm_obj.animation_data.nla_tracks:
        tr.mute = False
    C.export_roblox_asset("BrambleBoar", [arm_obj, mesh_obj], rigged=True)

    for tr in arm_obj.animation_data.nla_tracks:
        tr.mute = True
    C.reset_pose(arm_obj)
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    C.setup_studio_render([mesh_obj], "BrambleBoar_preview.png", resolution=640, samples=22, cam_azimuth_deg=-38.0, cam_elev_deg=16.0, distance_mult=2.25)
    print("BLENDER_EXPORT_OK: BrambleBoar")


if __name__ == "__main__":
    main()
