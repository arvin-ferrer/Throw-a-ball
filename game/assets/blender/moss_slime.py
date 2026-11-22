"""Headless Blender builder for MossSlime (Emerald Meadow PvE Mob).

Sculpted glossy gelatin dome (~3.5 studs tall, <1,800 tris) with lush moss crown,
curved dual-leaf sprout, expressive glossy eyes, 4-bone HumanoidRootPart rig, and
3 NLA animation clips (Idle, Hop, Attack).
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

MAT_SLIME_GEL = 0
MAT_SLIME_RIM = 1
MAT_MOSS_DEEP = 2
MAT_MOSS_BRIGHT = 3
MAT_SPROUT_LIME = 4
MAT_EYE_DARK = 5
MAT_EYE_GLINT = 6
MAT_PEBBLE = 7


def create_materials() -> list[bpy.types.Material]:
    return [
        C.make_material("SlimeEmeraldGel", (0.14, 0.78, 0.34), roughness=0.14),
        C.make_material("SlimeBaseRim", (0.08, 0.56, 0.24), roughness=0.18),
        C.make_material("SlimeMossDeep", (0.06, 0.28, 0.12), roughness=0.84),
        C.make_material("SlimeMossBright", (0.16, 0.56, 0.20), roughness=0.76),
        C.make_material("SlimeSproutLime", (0.44, 0.88, 0.24), roughness=0.45),
        C.make_material("SlimeEyeDark", (0.03, 0.04, 0.05), roughness=0.06),
        C.make_material("SlimeEyeGlint", (1.0, 1.0, 1.0), roughness=0.05, emission=(1.0, 1.0, 1.0), emission_strength=1.8),
        C.make_material("SlimePebble", (0.36, 0.40, 0.38), roughness=0.72),
    ]


def build_geometry(bm: bmesh.types.BMesh, bmap: dict[bmesh.types.BMVert, str]) -> None:
    """Build smooth gelatin slime body, mossy crown cap, leaf sprout, and glossy eyes."""
    # Wide bouncy teardrop gel dome resting flush on Z = 0.0 (height ~2.55)
    profile = [
        (1.65, 0.00),
        (2.15, 0.22),
        (2.22, 0.65),
        (2.05, 1.25),
        (1.70, 1.85),
        (1.15, 2.30),
        (0.45, 2.52),
    ]
    C.add_lathe_shell(bm, profile, MAT_SLIME_GEL, segments=18, smooth=True, tag_bone="BodySquash", bone_map=bmap)
    # Cushioned darker-emerald base skirt blobs for playful bouncy silhouette
    for i in range(6):
        ang = math.radians(i * 60.0 + 15.0)
        x, y = 1.92 * math.cos(ang), 1.92 * math.sin(ang)
        C.add_faceted_icosphere(
            bm, 0.55, (x, y, 0.30), MAT_SLIME_RIM, subdivisions=1,
            scale=(1.05, 1.05, 0.55), tag_bone="BodySquash", bone_map=bmap,
        )
    # Cute trapped pebble accents embedded in flanks
    C.add_faceted_icosphere(bm, 0.34, (-1.45, -1.0, 0.95), MAT_PEBBLE, subdivisions=1, scale=(1.1, 0.8, 0.9), tag_bone="BodySquash", bone_map=bmap)
    C.add_faceted_icosphere(bm, 0.28, (1.55, 0.7, 1.10), MAT_PEBBLE, subdivisions=1, scale=(0.9, 1.1, 0.8), tag_bone="BodySquash", bone_map=bmap)

    # Shaggy faceted moss beret cap on top (Z ~ 2.2..2.85)
    cap_clumps = [
        (0.92, (0.0, 0.15, 2.42), (1.35, 1.25, 0.52), MAT_MOSS_DEEP, 3),
        (0.75, (-0.75, -0.25, 2.38), (1.1, 0.95, 0.48), MAT_MOSS_BRIGHT, 5),
        (0.72, (0.72, -0.15, 2.40), (1.05, 1.0, 0.48), MAT_MOSS_BRIGHT, 7),
        (0.60, (0.05, 0.65, 2.36), (1.2, 0.9, 0.45), MAT_MOSS_DEEP, 9),
    ]
    for r, pos, sc, mat, sd in cap_clumps:
        C.add_faceted_icosphere(bm, r, pos, mat, subdivisions=1, scale=sc, noise_amp=0.14, seed=sd, tag_bone="CrownMoss", bone_map=bmap)

    # Iconic curved lofted sprout stem + 2 bold leaves rising to Z ~ 3.55
    stem_rings = [
        ((0.0, 0.0, 2.55), 0.12, 0.12, (0, 0, 0)),
        ((0.0, -0.06, 2.95), 0.09, 0.09, (12, 0, 0)),
        ((0.05, -0.16, 3.30), 0.06, 0.06, (22, 8, 0)),
    ]
    C.add_lofted_tube(bm, stem_rings, MAT_SPROUT_LIME, sides=6, smooth=True, tag_bone="CrownMoss", bone_map=bmap)
    for side in (-1, 1):
        leaf_rings = [
            ((0.04, -0.14, 3.22), 0.06, 0.04, (0, side * 55, 0)),
            ((side * 0.42, -0.22, 3.44), 0.28, 0.08, (10, side * 72, side * 12)),
            ((side * 0.78, -0.28, 3.40), 0.22, 0.06, (14, side * 88, side * 15)),
            ((side * 1.02, -0.32, 3.28), 0.04, 0.03, (18, side * 98, side * 18)),
        ]
        C.add_lofted_tube(bm, leaf_rings, MAT_SPROUT_LIME, sides=6, smooth=True, tag_bone="CrownMoss", bone_map=bmap)

    # Large expressive Adopt-Me/PS99-style glossy eyes facing -Y front
    C.add_expressive_eye(bm, (-0.72, -1.86, 1.32), 0.34, MAT_EYE_DARK, MAT_EYE_GLINT, tag_bone="BodySquash", bone_map=bmap)
    C.add_expressive_eye(bm, (0.72, -1.86, 1.32), 0.34, MAT_EYE_DARK, MAT_EYE_GLINT, tag_bone="BodySquash", bone_map=bmap)
    # Cheeky little curved mouth dimple
    C.add_faceted_box(bm, (0.42, 0.18, 0.12), (0.0, -2.06, 0.88), MAT_EYE_DARK, 0.03, tag_bone="BodySquash", bone_map=bmap)


def build_armature() -> bpy.types.Object:
    arm_data = bpy.data.armatures.new("MossSlimeArmature")
    arm_obj = bpy.data.objects.new("MossSlime", arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones
    root = eb.new("HumanoidRootPart")
    root.head, root.tail = Vector((0, 0, 0)), Vector((0, 0, 1.0))
    body = eb.new("BodySquash")
    body.head, body.tail, body.parent = Vector((0, 0, 0.1)), Vector((0, 0, 2.2)), root
    crown = eb.new("CrownMoss")
    crown.head, crown.tail, crown.parent = Vector((0, 0, 2.2)), Vector((0, 0, 3.4)), body
    core = eb.new("CoreFloat")
    core.head, core.tail, core.parent = Vector((0, 0, 0.8)), Vector((0, 0, 1.5)), body
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm_obj


def author_animations(arm_obj: bpy.types.Object) -> None:
    """Create Idle, Hop, and Attack NLA clips (24 FPS)."""
    def make_clip(name: str, end_f: int, keys: list[tuple[int, dict[str, tuple[tuple[float, float, float], tuple[float, float, float], tuple[float, float, float]]]]]) -> None:
        anim = arm_obj.animation_data or arm_obj.animation_data_create()
        act = bpy.data.actions.new(name=name)
        anim.action = act
        for frame, data in keys:
            for pb in arm_obj.pose.bones:
                pb.rotation_mode = "XYZ"
                loc, rot, scl = data.get(pb.name, ((0, 0, 0), (0, 0, 0), (1, 1, 1)))
                pb.location = Vector(loc)
                pb.rotation_euler = Euler(tuple(math.radians(a) for a in rot), "XYZ")
                pb.scale = Vector(scl)
                pb.keyframe_insert(data_path="location", frame=frame)
                pb.keyframe_insert(data_path="rotation_euler", frame=frame)
                pb.keyframe_insert(data_path="scale", frame=frame)
        C.push_action_to_nla(arm_obj, act, name, end_f)

    make_clip("Idle", 36, [
        (1, {}),
        (18, {"BodySquash": ((0, 0, 0), (0, 0, 0), (1.08, 1.08, 0.88)), "CrownMoss": ((0, 0, 0), (6, 0, 0), (1, 1, 1))}),
        (36, {}),
    ])
    make_clip("Hop", 20, [
        (1, {"BodySquash": ((0, 0, 0), (0, 0, 0), (1.16, 1.16, 0.76))}),
        (9, {"BodySquash": ((0, 0, 1.35), (12, 0, 0), (0.86, 0.86, 1.24)), "CrownMoss": ((0, 0, 0), (-16, 0, 0), (1, 1, 1))}),
        (17, {"BodySquash": ((0, 0, 0), (-4, 0, 0), (1.20, 1.20, 0.72))}),
        (20, {}),
    ])
    make_clip("Attack", 18, [
        (1, {}),
        (6, {"BodySquash": ((0, 0.45, 0), (-14, 0, 0), (1.18, 0.88, 0.82))}),
        (11, {"BodySquash": ((0, -1.10, 0.55), (22, 0, 0), (0.82, 1.28, 0.96)), "CrownMoss": ((0, 0, 0), (-22, 0, 0), (1, 1, 1))}),
        (18, {}),
    ])


def main() -> None:
    C.clear_scene()
    mats = create_materials()
    bm = bmesh.new()
    bmap: dict[bmesh.types.BMVert, str] = {}
    build_geometry(bm, bmap)

    idx_map = C.extract_bone_index_map(bm, bmap)
    mesh_obj = C.finalize_mesh("MossSlime_Mesh", bm, mats)
    arm_obj = build_armature()
    C.assign_bone_weights(mesh_obj, arm_obj, idx_map, "BodySquash")
    author_animations(arm_obj)
    C.reset_pose(arm_obj)

    for tr in arm_obj.animation_data.nla_tracks:
        tr.mute = True
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    C.validate_asset("MossSlime", [mesh_obj], tri_cap=1800, pivot_mode="floor")

    for tr in arm_obj.animation_data.nla_tracks:
        tr.mute = False
    C.export_roblox_asset("MossSlime", [arm_obj, mesh_obj], rigged=True)

    for tr in arm_obj.animation_data.nla_tracks:
        tr.mute = True
    C.reset_pose(arm_obj)
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    C.setup_studio_render([mesh_obj], "MossSlime_preview.png", resolution=640, samples=22, cam_azimuth_deg=-32.0, cam_elev_deg=18.0, distance_mult=2.25)
    print("BLENDER_EXPORT_OK: MossSlime")


if __name__ == "__main__":
    main()
