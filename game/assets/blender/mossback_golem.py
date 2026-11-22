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
    """Build Emerald Meadow 3-value palette + saturated Meadow emerald rune glow."""
    return [
        C.make_material("StoneDark", (0.14, 0.17, 0.15), roughness=0.84),
        C.make_material("StoneMid", (0.28, 0.32, 0.29), roughness=0.78),
        C.make_material("StoneLight", (0.44, 0.49, 0.45), roughness=0.72),
        C.make_material("MossDeep", (0.04, 0.28, 0.10), roughness=0.86),
        C.make_material("MossBright", (0.09, 0.56, 0.18), roughness=0.80),
        C.make_material("MossLime", (0.24, 0.80, 0.22), roughness=0.72),
        C.make_material(
            "EmeraldRuneGlow",
            (0.05, 0.96, 0.24),
            roughness=0.16,
            emission=(0.04, 0.96, 0.22),
            emission_strength=1.55,
        ),
        C.make_material("RootBark", (0.24, 0.15, 0.09), roughness=0.86),
    ]


def add_leg(bm: bmesh.types.BMesh, side: int, bmap: dict[bmesh.types.BMVert, str]) -> None:
    """Build one sculpted organic stone pillar leg (Thigh, Shin, Foot) grounded at Z=0."""
    tag = "L" if side < 0 else "R"
    x = side * 1.92
    # Organic arched stone foot resting flush on Z=0 + 3 carved stone toe claws
    foot_rings = [
        ((x, 0.95, 0.56), 0.92, 0.56, (90, 0, 0)),
        ((x, 0.05, 0.64), 1.12, 0.64, (90, 0, 0)),
        ((x, -1.05, 0.58), 1.16, 0.58, (90, 0, 0)),
        ((x, -1.55, 0.42), 0.92, 0.42, (95, 0, 0)),
    ]
    C.add_lofted_tube(bm, foot_rings, MAT_STONE_DARK, sides=10, smooth=False, tag_bone=f"Foot{tag}", bone_map=bmap)
    for tx, ang in [(-0.62, 12), (0.0, 0), (0.62, -12)]:
        C.add_crystal_prism(bm, 0.32, 0.92, (x + tx, -1.85, 0.36), MAT_STONE_LIGHT, sides=5, rot_deg=(78, 0, ang), tag_bone=f"Foot{tag}", bone_map=bmap)
    # Tapered organic stone shin + faceted knee boulder + woven root wrap
    shin_rings = [
        ((x, -0.05, 1.05), 0.95, 1.00, (0, 0, 0)),
        ((x, -0.02, 2.35), 1.12, 1.16, (0, 0, 0)),
        ((x, 0.04, 3.65), 1.06, 1.10, (0, 0, 0)),
    ]
    C.add_lofted_tube(bm, shin_rings, MAT_STONE_MID, sides=9, smooth=False, tag_bone=f"Shin{tag}", bone_map=bmap)
    C.add_faceted_icosphere(bm, 0.78, (x, -0.92, 3.35), MAT_STONE_LIGHT, subdivisions=1, scale=(1.05, 0.68, 0.92), noise_amp=0.08, seed=30 + side, tag_bone=f"Shin{tag}", bone_map=bmap)
    b0 = set(bm.verts)
    C.add_closed_ring(bm, 1.14, 0.14, 0.20, MAT_BARK, (6, side * 8, 0), 12)
    for v in [v for v in bm.verts if v not in b0]:
        v.co += Vector((x, 0.0, 2.15))
        bmap[v] = f"Shin{tag}"
    # Tapered organic thigh blending smoothly into pelvis
    thigh_rings = [
        ((x, 0.05, 3.55), 1.08, 1.10, (0, 0, 0)),
        ((x, 0.12, 4.65), 1.32, 1.34, (0, 0, 0)),
        ((x * 0.90, 0.14, 5.55), 1.05, 1.10, (0, side * -12, 0)),
    ]
    C.add_lofted_tube(bm, thigh_rings, MAT_STONE_DARK, sides=9, smooth=False, tag_bone=f"Thigh{tag}", bone_map=bmap)


def add_torso_and_head(bm: bmesh.types.BMesh, bmap: dict[bmesh.types.BMVert, str]) -> None:
    """Build sculpted organic stone torso, emerald rune heart, moss mantle, and stone brow head."""
    # Organic tapered pelvis + mossy stone kilt drape
    pelvis_rings = [
        ((0.0, 0.15, 4.55), 2.10, 1.48, (0, 0, 0)),
        ((0.0, 0.12, 5.65), 2.45, 1.72, (0, 0, 0)),
        ((0.0, 0.10, 6.45), 2.30, 1.68, (0, 0, 0)),
    ]
    C.add_lofted_tube(bm, pelvis_rings, MAT_STONE_DARK, sides=10, smooth=False, tag_bone="Pelvis", bone_map=bmap)
    C.add_faceted_icosphere(bm, 1.15, (0.0, -1.35, 5.10), MAT_MOSS_DEEP, subdivisions=1, scale=(1.15, 0.45, 0.95), noise_amp=0.12, seed=41, tag_bone="Pelvis", bone_map=bmap)

    # Massive heroic V-tapered organic stone torso (lofted 5-ring ribcage)
    torso_rings = [
        ((0.0, 0.12, 6.05), 2.25, 1.65, (0, 0, 0)),
        ((0.0, 0.05, 7.35), 2.95, 2.08, (4, 0, 0)),
        ((0.0, -0.05, 8.85), 3.45, 2.38, (8, 0, 0)),
        ((0.0, -0.15, 10.15), 3.10, 2.15, (12, 0, 0)),
        ((0.0, -0.10, 10.95), 2.05, 1.55, (12, 0, 0)),
    ]
    C.add_lofted_tube(bm, torso_rings, MAT_STONE_MID, sides=12, smooth=False, tag_bone="Chest", bone_map=bmap)
    # Sculpted flanking boulder pec plates framing recessed dark cavity + blazing EMERALD heart
    for sx in (-1, 1):
        C.add_faceted_icosphere(bm, 1.38, (sx * 1.52, -1.78, 8.45), MAT_STONE_LIGHT, subdivisions=1, scale=(0.95, 0.56, 1.05), noise_amp=0.10, seed=50 + sx, tag_bone="Chest", bone_map=bmap)
    C.add_faceted_icosphere(bm, 1.25, (0.0, -1.82, 8.30), MAT_STONE_DARK, subdivisions=1, scale=(1.05, 0.42, 1.05), tag_bone="Chest", bone_map=bmap)
    C.add_crystal_prism(bm, 0.72, 1.95, (0.0, -2.28, 8.38), MAT_CRYSTAL_GLOW, sides=6, rot_deg=(12, 0, 0), tag_bone="Chest", bone_map=bmap)
    for sx in (-1, 1):
        C.add_crystal_prism(bm, 0.34, 1.15, (sx * 0.74, -2.18, 8.20), MAT_CRYSTAL_GLOW, sides=5, rot_deg=(14, sx * -22, 0), tag_bone="Chest", bone_map=bmap)

    # Shaggy multi-tone Meadow moss mantle + blazing emerald dorsal crystal ridge
    moss_clumps = [
        (1.75, (0.0, 1.35, 10.2), (1.60, 1.05, 0.78), MAT_MOSS_DEEP, 1),
        (1.42, (-1.85, 1.05, 10.45), (1.22, 1.02, 0.74), MAT_MOSS_BRIGHT, 2),
        (1.42, (1.85, 1.05, 10.45), (1.22, 1.02, 0.74), MAT_MOSS_BRIGHT, 3),
        (1.25, (0.0, 1.85, 8.65), (1.65, 0.85, 0.92), MAT_MOSS_DEEP, 4),
        (0.98, (-0.95, 1.40, 10.95), (1.12, 0.92, 0.60), MAT_MOSS_LIME, 5),
        (0.95, (1.10, 1.25, 10.90), (1.05, 0.88, 0.58), MAT_MOSS_LIME, 6),
    ]
    for r, pos, sc, mat, sd in moss_clumps:
        C.add_faceted_icosphere(bm, r, pos, mat, subdivisions=2, scale=sc, noise_amp=0.16, seed=sd, tag_bone="Chest", bone_map=bmap)
    for px, py, pz, h, rot in [
        (0.0, 1.15, 11.75, 2.55, (-22, 0, 0)),
        (-1.25, 1.35, 11.25, 1.85, (-26, 20, 0)),
        (1.25, 1.35, 11.25, 1.85, (-26, -20, 0)),
        (0.0, 1.95, 9.75, 1.65, (-48, 0, 0)),
    ]:
        C.add_crystal_prism(bm, 0.44, h, (px, py, pz), MAT_CRYSTAL_GLOW, sides=5, rot_deg=rot, tag_bone="Chest", bone_map=bmap)

    # Sculpted craggy ancient stone Head (organic cranium + overhanging stone brow + carved jaw)
    C.add_faceted_icosphere(bm, 1.42, (0.0, -1.42, 10.48), MAT_STONE_MID, subdivisions=2, scale=(1.04, 0.96, 0.88), noise_amp=0.08, seed=70, tag_bone="Head", bone_map=bmap)
    brow_rings = [
        ((-1.25, -2.05, 10.96), 0.34, 0.42, (0, 90, 12)),
        ((0.0, -2.38, 10.90), 0.38, 0.48, (0, 90, 0)),
        ((1.25, -2.05, 10.96), 0.34, 0.42, (0, 90, -12)),
    ]
    C.add_lofted_tube(bm, brow_rings, MAT_STONE_LIGHT, sides=6, smooth=False, tag_bone="Head", bone_map=bmap)
    jaw_rings = [
        ((-0.95, -1.92, 9.78), 0.32, 0.38, (0, 90, 8)),
        ((0.0, -2.26, 9.64), 0.38, 0.44, (0, 90, 0)),
        ((0.95, -1.92, 9.78), 0.32, 0.38, (0, 90, -8)),
    ]
    C.add_lofted_tube(bm, jaw_rings, MAT_STONE_DARK, sides=6, smooth=False, tag_bone="Head", bone_map=bmap)
    for sx in (-1, 1):
        C.add_crystal_prism(bm, 0.24, 0.54, (sx * 0.56, -2.38, 10.42), MAT_CRYSTAL_GLOW, sides=5, rot_deg=(0, 90, sx * -14), tag_bone="Head", bone_map=bmap)
    C.add_faceted_icosphere(bm, 0.88, (0.12, -1.10, 11.48), MAT_MOSS_BRIGHT, subdivisions=2, scale=(1.32, 1.02, 0.52), noise_amp=0.14, seed=9, tag_bone="Head", bone_map=bmap)


def add_arm(bm: bmesh.types.BMesh, side: int, bmap: dict[bmesh.types.BMVert, str]) -> None:
    """Build asymmetrical craggy boulder pauldron, organic muscular stone arm, and slam gauntlet."""
    tag = "L" if side < 0 else "R"
    sx = side * 3.82
    p_z = 9.85 if side < 0 else 9.55
    C.add_faceted_icosphere(bm, 1.82, (sx, 0.05, p_z), MAT_STONE_LIGHT, subdivisions=2, scale=(1.08, 1.0, 0.92), noise_amp=0.16, seed=12 + side, tag_bone="Chest", bone_map=bmap)
    C.add_faceted_icosphere(bm, 1.22, (sx + side * 0.2, 0.25, p_z + 0.85), MAT_MOSS_BRIGHT, subdivisions=2, scale=(1.12, 0.96, 0.55), noise_amp=0.15, seed=20 + side, tag_bone="Chest", bone_map=bmap)
    C.add_crystal_prism(bm, 0.40, 1.85 if side < 0 else 1.35, (sx + side * 0.35, 0.1, p_z + 1.45), MAT_CRYSTAL_GLOW, sides=5, rot_deg=(0, side * -22, 0), tag_bone="Chest", bone_map=bmap)

    # Tapered organic stone upper arm (zero boxes)
    upper = [
        ((side * 3.85, -0.02, 9.05), 1.08, 1.12, (0, side * -6, 0)),
        ((side * 4.18, -0.14, 7.65), 1.12, 1.16, (0, side * -8, 0)),
        ((side * 4.28, -0.26, 6.45), 0.96, 1.02, (0, side * -5, 0)),
    ]
    C.add_lofted_tube(bm, upper, MAT_STONE_DARK, sides=9, smooth=False, tag_bone=f"UpperArm{tag}", bone_map=bmap)

    # Widening sculpted boulder forearm gauntlet + embedded emerald rune crystal + vine cuff
    forearm = [
        ((side * 4.26, -0.24, 6.55), 1.02, 1.06, (0, 0, 0)),
        ((side * 4.42, -0.38, 5.25), 1.36, 1.40, (0, 0, 0)),
        ((side * 4.52, -0.52, 3.85), 1.44, 1.48, (0, 0, 0)),
    ]
    C.add_lofted_tube(bm, forearm, MAT_STONE_MID, sides=9, smooth=False, tag_bone=f"Forearm{tag}", bone_map=bmap)
    C.add_crystal_prism(bm, 0.42, 1.65, (side * 5.65, -0.38, 5.15), MAT_CRYSTAL_GLOW, sides=5, rot_deg=(0, side * 58, 0), tag_bone=f"Forearm{tag}", bone_map=bmap)
    b0 = set(bm.verts)
    C.add_closed_ring(bm, 1.24, 0.15, 0.22, MAT_BARK, (4, side * -8, 0), 12)
    for v in [v for v in bm.verts if v not in b0]:
        v.co += Vector((side * 4.34, -0.32, 6.08))
        bmap[v] = f"Forearm{tag}"

    # Sculpted organic boulder slamming fist + carved knuckle crest + tapered stone thumb
    C.add_faceted_icosphere(bm, 1.48, (side * 4.55, -0.58, 2.88), MAT_STONE_LIGHT, subdivisions=2, scale=(1.02, 1.04, 0.88), noise_amp=0.10, seed=80 + side, tag_bone=f"Hand{tag}", bone_map=bmap)
    for ky in (-0.58, 0.0, 0.58):
        C.add_faceted_icosphere(bm, 0.46, (side * 4.65, -0.58 + ky, 1.88), MAT_STONE_MID, subdivisions=1, scale=(0.95, 0.78, 0.85), tag_bone=f"Hand{tag}", bone_map=bmap)
    thumb = [
        ((side * 3.55, -1.15, 3.25), 0.48, 0.48, (35, side * -25, 0)),
        ((side * 3.25, -1.65, 2.55), 0.34, 0.36, (45, side * -18, 0)),
    ]
    C.add_lofted_tube(bm, thumb, MAT_STONE_MID, sides=7, smooth=False, tag_bone=f"Hand{tag}", bone_map=bmap)


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
