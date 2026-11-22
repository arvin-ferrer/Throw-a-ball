"""Headless Blender builder for MossbackGolem (Emerald Meadow Boss).

Builds a stylized low-poly ancient moss-draped stone colossus (~12 studs tall,
<6k tris), 16-bone Roblox armature (root = HumanoidRootPart), and 5 NLA clips
synced to BossAIStateMachine timings (Idle, Walk, GroundSlam, BoulderThrow, Death).
Exports MossbackGolem.fbx + MossbackGolem.glb and renders hero + pose previews.
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

MAT_STONE_DARK = 0
MAT_STONE_MID = 1
MAT_STONE_LIGHT = 2
MAT_MOSS_DEEP = 3
MAT_MOSS_BRIGHT = 4
MAT_MOSS_LIME = 5
MAT_CRYSTAL_GLOW = 6
MAT_BARK = 7


def create_materials() -> list[bpy.types.Material]:
    """Build Emerald Meadow 3-value palette + glowing jade rune crystal."""
    return [
        C.make_material("StoneDark", (0.14, 0.16, 0.15), roughness=0.84),
        C.make_material("StoneMid", (0.28, 0.31, 0.29), roughness=0.78),
        C.make_material("StoneLight", (0.44, 0.47, 0.44), roughness=0.72),
        C.make_material("MossDeep", (0.06, 0.25, 0.11), roughness=0.88),
        C.make_material("MossBright", (0.12, 0.48, 0.18), roughness=0.82),
        C.make_material("MossLime", (0.34, 0.72, 0.22), roughness=0.76),
        C.make_material(
            "JadeRuneGlow",
            (0.10, 0.88, 0.42),
            roughness=0.18,
            emission=(0.10, 0.92, 0.42),
            emission_strength=2.4,
        ),
        C.make_material("RootBark", (0.22, 0.15, 0.10), roughness=0.86),
    ]


def add_leg(bm: bmesh.types.BMesh, side: int, bmap: dict[int, str]) -> None:
    """Build one heavy pillar stone leg (Thigh, Shin, Foot) grounded at Z=0."""
    tag = "L" if side < 0 else "R"
    x = side * 1.85
    # Foot block resting exactly on Z=0..1.25 + 3 blocky stone toes facing -Y
    C.add_faceted_box(bm, (2.1, 2.7, 1.25), (x, -0.25, 0.625), MAT_STONE_DARK, 0.10, taper_top=(0.86, 0.88), tag_bone=f"Foot{tag}", bone_map=bmap)
    for tx in (-0.65, 0.0, 0.65):
        C.add_faceted_box(bm, (0.55, 0.85, 0.75), (x + tx, -1.55, 0.375), MAT_STONE_MID, 0.06, taper_top=(0.8, 0.7), tag_bone=f"Foot{tag}", bone_map=bmap)
    # Shin pillar + knee stone guard + bark vine wrap
    C.add_faceted_box(bm, (1.85, 1.95, 2.55), (x, 0.0, 2.45), MAT_STONE_MID, 0.12, taper_top=(1.08, 1.05), tag_bone=f"Shin{tag}", bone_map=bmap)
    C.add_faceted_box(bm, (1.45, 0.75, 1.15), (x, -1.05, 3.35), MAT_STONE_LIGHT, 0.08, rot_deg=(12, 0, 0), tag_bone=f"Shin{tag}", bone_map=bmap)
    C.add_faceted_box(bm, (2.05, 2.1, 0.42), (x, 0.0, 2.05), MAT_BARK, 0.04, rot_deg=(4, side * 6, 0), tag_bone=f"Shin{tag}", bone_map=bmap)
    # Thigh
    C.add_faceted_box(bm, (2.15, 2.2, 2.05), (x, 0.1, 4.55), MAT_STONE_DARK, 0.14, taper_top=(1.1, 1.05), tag_bone=f"Thigh{tag}", bone_map=bmap)


def add_torso_and_head(bm: bmesh.types.BMesh, bmap: dict[int, str]) -> None:
    """Build pelvis, massive faceted stone chest, glowing emerald core, moss mantle, and head."""
    # Pelvis & mossy stone loin slabs
    C.add_faceted_box(bm, (4.4, 3.0, 1.7), (0, 0.15, 5.45), MAT_STONE_DARK, 0.14, taper_top=(1.12, 1.06), tag_bone="Pelvis", bone_map=bmap)
    C.add_faceted_box(bm, (1.9, 0.55, 1.35), (0, -1.45, 4.95), MAT_MOSS_DEEP, 0.06, rot_deg=(-8, 0, 0), tag_bone="Pelvis", bone_map=bmap)

    # Massive inverted-trapezoid chest
    C.add_faceted_box(bm, (5.2, 3.7, 4.1), (0, 0.1, 8.15), MAT_STONE_MID, 0.22, taper_top=(1.22, 1.12), tag_bone="Chest", bone_map=bmap)
    # Sculpted chest armor plates framing recessed emerald core cavity
    C.add_faceted_box(bm, (1.75, 1.0, 2.4), (-1.55, -1.65, 8.25), MAT_STONE_LIGHT, 0.12, rot_deg=(0, 0, 10), tag_bone="Chest", bone_map=bmap)
    C.add_faceted_box(bm, (1.75, 1.0, 2.4), (1.55, -1.65, 8.25), MAT_STONE_LIGHT, 0.12, rot_deg=(0, 0, -10), tag_bone="Chest", bone_map=bmap)
    C.add_faceted_box(bm, (2.1, 0.8, 1.9), (0, -1.45, 8.2), MAT_STONE_DARK, 0.08, tag_bone="Chest", bone_map=bmap)
    # Glowing emerald chest crystal core + flanking rune shards
    C.add_crystal_prism(bm, 0.72, 1.75, (0, -1.95, 8.25), MAT_CRYSTAL_GLOW, sides=6, rot_deg=(12, 0, 0), tag_bone="Chest", bone_map=bmap)
    C.add_crystal_prism(bm, 0.34, 1.05, (-0.75, -1.85, 8.1), MAT_CRYSTAL_GLOW, sides=5, rot_deg=(15, 22, 0), tag_bone="Chest", bone_map=bmap)
    C.add_crystal_prism(bm, 0.34, 1.05, (0.75, -1.85, 8.1), MAT_CRYSTAL_GLOW, sides=5, rot_deg=(15, -22, 0), tag_bone="Chest", bone_map=bmap)

    # Shaggy layered moss mantle & glowing dorsal crystal spikes across back/top
    moss_clumps = [
        (1.65, (0.0, 1.35, 10.1), (1.55, 1.05, 0.75), MAT_MOSS_DEEP, 1),
        (1.35, (-1.8, 1.05, 10.35), (1.2, 1.0, 0.72), MAT_MOSS_BRIGHT, 2),
        (1.35, (1.8, 1.05, 10.35), (1.2, 1.0, 0.72), MAT_MOSS_BRIGHT, 3),
        (1.15, (0.0, 1.75, 8.75), (1.6, 0.85, 0.9), MAT_MOSS_DEEP, 4),
        (0.95, (-0.9, 1.4, 10.85), (1.1, 0.9, 0.6), MAT_MOSS_LIME, 5),
        (0.90, (1.1, 1.2, 10.8), (1.0, 0.85, 0.55), MAT_MOSS_LIME, 6),
    ]
    for r, pos, sc, mat, sd in moss_clumps:
        C.add_faceted_icosphere(bm, r, pos, mat, subdivisions=1, scale=sc, noise_amp=0.16, seed=sd, tag_bone="Chest", bone_map=bmap)
    # Dorsal jade crystal ridge (echoes Pyraxis silhouette flair)
    C.add_crystal_prism(bm, 0.45, 2.2, (0.0, 1.15, 11.45), MAT_CRYSTAL_GLOW, sides=5, rot_deg=(-22, 0, 0), tag_bone="Chest", bone_map=bmap)
    C.add_crystal_prism(bm, 0.36, 1.65, (-1.1, 1.35, 11.1), MAT_CRYSTAL_GLOW, sides=5, rot_deg=(-26, 18, 0), tag_bone="Chest", bone_map=bmap)
    C.add_crystal_prism(bm, 0.36, 1.65, (1.1, 1.35, 11.1), MAT_CRYSTAL_GLOW, sides=5, rot_deg=(-26, -18, 0), tag_bone="Chest", bone_map=bmap)

    # Low-set heavy stone Head with overhanging brow & glowing eyes
    C.add_faceted_box(bm, (2.35, 2.25, 1.95), (0, -1.25, 10.35), MAT_STONE_MID, 0.14, taper_top=(0.92, 0.92), tag_bone="Head", bone_map=bmap)
    C.add_faceted_box(bm, (2.65, 1.05, 0.65), (0, -2.05, 10.95), MAT_STONE_LIGHT, 0.08, rot_deg=(8, 0, 0), tag_bone="Head", bone_map=bmap)
    C.add_faceted_box(bm, (2.15, 0.65, 0.55), (0, -2.15, 9.65), MAT_STONE_DARK, 0.06, tag_bone="Head", bone_map=bmap)
    C.add_faceted_box(bm, (0.55, 0.32, 0.34), (-0.62, -2.35, 10.42), MAT_CRYSTAL_GLOW, 0.02, tag_bone="Head", bone_map=bmap)
    C.add_faceted_box(bm, (0.55, 0.32, 0.34), (0.62, -2.35, 10.42), MAT_CRYSTAL_GLOW, 0.02, tag_bone="Head", bone_map=bmap)
    C.add_faceted_icosphere(bm, 0.85, (0.15, -0.95, 11.45), MAT_MOSS_BRIGHT, subdivisions=1, scale=(1.35, 1.05, 0.55), noise_amp=0.14, seed=9, tag_bone="Head", bone_map=bmap)


def add_arm(bm: bmesh.types.BMesh, side: int, bmap: dict[int, str]) -> None:
    """Build asymmetrical boulder pauldron (Chest-anchored), heavy arm, and slam gauntlet."""
    tag = "L" if side < 0 else "R"
    sx = side * 3.85
    # Massive craggy boulder pauldron weighted to Chest so it stays upright during overhead slams
    p_z = 9.75 if side < 0 else 9.45
    C.add_faceted_icosphere(bm, 1.75, (sx, 0.05, p_z), MAT_STONE_LIGHT, subdivisions=1, scale=(1.08, 1.0, 0.92), noise_amp=0.16, seed=12 + side, tag_bone="Chest", bone_map=bmap)
    C.add_faceted_icosphere(bm, 1.15, (sx + side * 0.2, 0.25, p_z + 0.85), MAT_MOSS_BRIGHT, subdivisions=1, scale=(1.1, 0.95, 0.55), noise_amp=0.15, seed=20 + side, tag_bone="Chest", bone_map=bmap)
    if side < 0:
        C.add_crystal_prism(bm, 0.38, 1.7, (sx - 0.35, 0.1, p_z + 1.45), MAT_CRYSTAL_GLOW, sides=5, rot_deg=(0, 22, 0), tag_bone="Chest", bone_map=bmap)
    # Upper arm block
    C.add_faceted_box(bm, (1.75, 1.85, 2.6), (side * 4.05, -0.05, 7.65), MAT_STONE_DARK, 0.12, rot_deg=(0, side * -5, 0), tag_bone=f"UpperArm{tag}", bone_map=bmap)
    # Oversized widening stone forearm gauntlet + glowing rune strip
    C.add_faceted_box(bm, (2.25, 2.35, 2.95), (side * 4.35, -0.35, 5.15), MAT_STONE_MID, 0.16, taper_top=(0.82, 0.85), tag_bone=f"Forearm{tag}", bone_map=bmap)
    C.add_faceted_box(bm, (0.35, 0.95, 1.5), (side * 5.45, -0.35, 5.15), MAT_CRYSTAL_GLOW, 0.04, tag_bone=f"Forearm{tag}", bone_map=bmap)
    C.add_faceted_box(bm, (2.42, 2.5, 0.45), (side * 4.35, -0.35, 6.15), MAT_BARK, 0.04, tag_bone=f"Forearm{tag}", bone_map=bmap)
    # Massive flat-knuckled slamming stone fist
    C.add_faceted_box(bm, (2.55, 2.55, 1.95), (side * 4.45, -0.55, 2.95), MAT_STONE_LIGHT, 0.14, taper_top=(0.94, 0.94), tag_bone=f"Hand{tag}", bone_map=bmap)
    # Thumb slab
    C.add_faceted_box(bm, (0.85, 1.05, 1.1), (side * 3.15, -1.35, 2.95), MAT_STONE_MID, 0.08, rot_deg=(12, side * 15, 0), tag_bone=f"Hand{tag}", bone_map=bmap)


def build_armature() -> bpy.types.Object:
    """Create the 16-bone Roblox-compatible Golem armature (root = HumanoidRootPart)."""
    arm_data = bpy.data.armatures.new("MossbackGolemArmature")
    arm_obj = bpy.data.objects.new("MossbackGolem", arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")

    specs = [
        ("HumanoidRootPart", None, (0, 0, 0), (0, 0, 2.0)),
        ("Pelvis", "HumanoidRootPart", (0, 0.1, 4.7), (0, 0.1, 6.2)),
        ("Chest", "Pelvis", (0, 0.1, 6.2), (0, 0.1, 10.2)),
        ("Head", "Chest", (0, -1.1, 9.8), (0, -1.4, 11.4)),
        ("UpperArmL", "Chest", (-3.5, 0.0, 9.4), (-4.1, -0.1, 6.5)),
        ("ForearmL", "UpperArmL", (-4.1, -0.1, 6.5), (-4.4, -0.45, 3.8)),
        ("HandL", "ForearmL", (-4.4, -0.45, 3.8), (-4.45, -0.55, 2.0)),
        ("UpperArmR", "Chest", (3.5, 0.0, 9.4), (4.1, -0.1, 6.5)),
        ("ForearmR", "UpperArmR", (4.1, -0.1, 6.5), (4.4, -0.45, 3.8)),
        ("HandR", "ForearmR", (4.4, -0.45, 3.8), (4.45, -0.55, 2.0)),
        ("ThighL", "Pelvis", (-1.85, 0.1, 5.2), (-1.85, 0.0, 3.6)),
        ("ShinL", "ThighL", (-1.85, 0.0, 3.6), (-1.85, 0.0, 1.2)),
        ("FootL", "ShinL", (-1.85, 0.0, 1.2), (-1.85, -1.4, 0.2)),
        ("ThighR", "Pelvis", (1.85, 0.1, 5.2), (1.85, 0.0, 3.6)),
        ("ShinR", "ThighR", (1.85, 0.0, 3.6), (1.85, 0.0, 1.2)),
        ("FootR", "ShinR", (1.85, 0.0, 1.2), (1.85, -1.4, 0.2)),
    ]
    eb = arm_data.edit_bones
    created: dict[str, bpy.types.EditBone] = {}
    for name, parent, head, tail in specs:
        b = eb.new(name)
        b.head = Vector(head)
        b.tail = Vector(tail)
        if parent:
            b.parent = created[parent]
        created[name] = b
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm_obj


def key_pose(
    arm_obj: bpy.types.Object,
    frame: int,
    rotations: dict[str, tuple[float, float, float]],
    locations: dict[str, tuple[float, float, float]] | None = None,
) -> None:
    """Set XYZ Euler pose rotations/locations and insert keyframes at `frame`."""
    for pbone in arm_obj.pose.bones:
        pbone.rotation_mode = "XYZ"
        deg = rotations.get(pbone.name, (0.0, 0.0, 0.0))
        pbone.rotation_euler = Euler(tuple(math.radians(a) for a in deg), "XYZ")
        pbone.keyframe_insert(data_path="rotation_euler", frame=frame)
        if locations and pbone.name in locations:
            pbone.location = Vector(locations[pbone.name])
            pbone.keyframe_insert(data_path="location", frame=frame)
        elif pbone.name == "Pelvis":
            pbone.location = Vector((0.0, 0.0, 0.0))
            pbone.keyframe_insert(data_path="location", frame=frame)


def build_clip(
    arm_obj: bpy.types.Object,
    clip_name: str,
    end_frame: int,
    frames: list[tuple[int, dict[str, tuple[float, float, float]], dict[str, tuple[float, float, float]] | None]],
) -> None:
    """Author a named animation clip and push it to an NLA track."""
    anim = arm_obj.animation_data or arm_obj.animation_data_create()
    action = bpy.data.actions.new(name=clip_name)
    anim.action = action
    for frame, rots, locs in frames:
        key_pose(arm_obj, frame, rots, locs)
    C.push_action_to_nla(arm_obj, action, clip_name, end_frame)


def author_all_animations(arm_obj: bpy.types.Object) -> None:
    """Create the 5 Mossback Golem NLA clips synced to BossAIStateMachine timings."""
    build_clip(arm_obj, "Idle", 48, [
        (1, {"Chest": (0, 0, 0), "UpperArmL": (4, 0, -5), "UpperArmR": (4, 0, 5)}, None),
        (24, {"Chest": (-4, 0, 0), "Head": (4, 0, 6), "UpperArmL": (8, 0, -9), "UpperArmR": (8, 0, 9)}, {"Pelvis": (0, 0, 0.25)}),
        (48, {"Chest": (0, 0, 0), "UpperArmL": (4, 0, -5), "UpperArmR": (4, 0, 5)}, None),
    ])
    build_clip(arm_obj, "Walk", 29, [
        (1, {"ThighL": (22, 0, 0), "ShinL": (-14, 0, 0), "ThighR": (-18, 0, 0), "UpperArmL": (-16, 0, -5), "UpperArmR": (18, 0, 5), "Chest": (4, 0, -6)}, {"Pelvis": (0, 0, 0.15)}),
        (8, {"ThighL": (0, 0, 0), "ThighR": (0, 0, 0), "Chest": (6, 0, 0)}, {"Pelvis": (0, 0, -0.25)}),
        (15, {"ThighL": (-18, 0, 0), "ThighR": (22, 0, 0), "ShinR": (-14, 0, 0), "UpperArmL": (18, 0, -5), "UpperArmR": (-16, 0, 5), "Chest": (4, 0, 6)}, {"Pelvis": (0, 0, 0.15)}),
        (22, {"ThighL": (0, 0, 0), "ThighR": (0, 0, 0), "Chest": (6, 0, 0)}, {"Pelvis": (0, 0, -0.25)}),
        (29, {"ThighL": (22, 0, 0), "ShinL": (-14, 0, 0), "ThighR": (-18, 0, 0), "UpperArmL": (-16, 0, -5), "UpperArmR": (18, 0, 5), "Chest": (4, 0, -6)}, {"Pelvis": (0, 0, 0.15)}),
    ])
    # GroundSlam: 0-1.20s windup (f1-29), 1.20-1.95s impact hold (f30-47), 1.95-2.75s recover (f47-66)
    build_clip(arm_obj, "GroundSlam", 66, [
        (1, {}, None),
        (28, {"Chest": (-22, 0, 0), "Head": (-14, 0, 0), "UpperArmL": (-145, 0, -16), "ForearmL": (-24, 0, 0), "UpperArmR": (-145, 0, 16), "ForearmR": (-24, 0, 0)}, {"Pelvis": (0, 0, 0.45)}),
        (31, {"Chest": (34, 0, 0), "Head": (18, 0, 0), "UpperArmL": (46, 0, -6), "ForearmL": (18, 0, 0), "UpperArmR": (46, 0, 6), "ForearmR": (18, 0, 0), "ThighL": (-18, 0, 0), "ShinL": (24, 0, 0), "ThighR": (-18, 0, 0), "ShinR": (24, 0, 0)}, {"Pelvis": (0, 0, -1.25)}),
        (47, {"Chest": (30, 0, 0), "UpperArmL": (42, 0, -6), "UpperArmR": (42, 0, 6), "ThighL": (-16, 0, 0), "ShinL": (20, 0, 0), "ThighR": (-16, 0, 0), "ShinR": (20, 0, 0)}, {"Pelvis": (0, 0, -1.1)}),
        (66, {}, None),
    ])
    # BoulderThrow: 0-1.00s windup (f1-24), f24 release, 1.00-1.70s recovery (f24-41)
    build_clip(arm_obj, "BoulderThrow", 41, [
        (1, {}, None),
        (20, {"Chest": (-12, 0, -34), "Head": (0, 0, 26), "UpperArmR": (-118, 0, 24), "ForearmR": (-32, 0, 0), "UpperArmL": (32, 0, -18)}, {"Pelvis": (0, 0, -0.2)}),
        (25, {"Chest": (18, 0, 28), "Head": (0, 0, -18), "UpperArmR": (58, 0, 10), "ForearmR": (12, 0, 0), "UpperArmL": (-28, 0, -14)}, {"Pelvis": (0, 0, -0.35)}),
        (41, {}, None),
    ])
    build_clip(arm_obj, "Death", 48, [
        (1, {}, None),
        (16, {"Chest": (-24, 0, 12), "UpperArmL": (-40, 0, -35), "UpperArmR": (-35, 0, 35)}, {"Pelvis": (0, 0, -0.4)}),
        (36, {"Chest": (68, 0, 8), "Head": (24, 0, 0), "UpperArmL": (72, 0, -28), "UpperArmR": (64, 0, 28), "ThighL": (-36, 0, 0), "ShinL": (54, 0, 0), "ThighR": (-36, 0, 0), "ShinR": (54, 0, 0)}, {"Pelvis": (0, 0, -3.4)}),
        (48, {"Chest": (78, 0, 10), "UpperArmL": (80, 0, -32), "UpperArmR": (72, 0, 32), "ThighL": (-42, 0, 0), "ShinL": (62, 0, 0), "ThighR": (-42, 0, 0), "ShinR": (62, 0, 0)}, {"Pelvis": (0, 0, -3.9)}),
    ])


def render_pose_check(arm_obj: bpy.types.Object, mesh_obj: bpy.types.Object) -> None:
    """Render GroundSlam overhead windup telegraph pose with full fist framing."""
    for track in arm_obj.animation_data.nla_tracks:
        track.mute = track.name != "GroundSlam"
    bpy.context.scene.frame_set(28)
    bpy.context.view_layer.update()
    C.setup_studio_render(
        [mesh_obj],
        "MossbackGolem_poses.png",
        resolution=640,
        samples=20,
        cam_azimuth_deg=-40.0,
        cam_elev_deg=12.0,
        distance_mult=3.25,
    )


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
    mesh_obj = C.finalize_mesh("MossbackGolem_Mesh", bm, mats)
    arm_obj = build_armature()
    C.assign_bone_weights(mesh_obj, arm_obj, idx_map, "Chest")
    author_all_animations(arm_obj)
    C.reset_pose(arm_obj)

    for track in arm_obj.animation_data.nla_tracks:
        track.mute = True
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    C.validate_asset("MossbackGolem", [mesh_obj], tri_cap=6000, pivot_mode="floor")

    for track in arm_obj.animation_data.nla_tracks:
        track.mute = False
    C.export_roblox_asset("MossbackGolem", [arm_obj, mesh_obj], rigged=True)

    # Render hero 3/4 preview in neutral rest stance, then GroundSlam telegraph pose
    for track in arm_obj.animation_data.nla_tracks:
        track.mute = True
    C.reset_pose(arm_obj)
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    C.setup_studio_render(
        [mesh_obj],
        "MossbackGolem_preview.png",
        resolution=768,
        samples=24,
        cam_azimuth_deg=-34.0,
        cam_elev_deg=16.0,
        distance_mult=2.25,
    )
    render_pose_check(arm_obj, mesh_obj)
    print("BLENDER_EXPORT_OK: MossbackGolem")


if __name__ == "__main__":
    main()
