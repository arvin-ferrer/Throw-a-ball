"""Headless Blender 5.x pipeline for ForestMonster (Emerald Meadow PvE Mob).

Imports `game/assets/exports/forest_monster.glb`, enhances its stylized PBR materials
with rich woodland bark, emerald moss, forest leaf pauldrons, and bioluminescent
jade-emerald eyes/mushrooms, binds all 8 meshes to a 6-bone Roblox-ready Armature
(`HumanoidRootPart -> Legs / Torso -> Arms / Foliage / Moss`), authors 3 looping
24 FPS NLA clips (`Idle`, `Walk`, `Attack`), exports `ForestMonster_Rigged.glb` and
`ForestMonster_Rigged.fbx`, and renders `game/assets/renders/ForestMonster_preview.png`.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bpy
from mathutils import Euler, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _common as C  # noqa: E402

SOURCE_GLB = C.EXPORT_DIR / "forest_monster.glb"
TARGET_HEIGHT_STUDS = 9.10

MESH_TO_BONE = {
    "Torso_Head_Antlers_Bark": "Torso",
    "Arms_Claws_Bark": "Arms",
    "Legs_Roots_Bark": "Legs",
    "Moss_Drape_Patches": "Moss",
    "Foliage_Shoulders_Vines": "Foliage",
    "Bioluminescent_Eyes_Mushrooms": "Torso",
    "Mushroom_Stems": "Torso",
    "Mouth_Eye_Hollows": "Torso",
}


def build_materials() -> dict[str, bpy.types.Material]:
    """Create stylized PBR materials aligned with STYLE_GUIDE.md."""
    return {
        "Torso_Head_Antlers_Bark": C.make_material("ForestBarkTorso", (0.21, 0.11, 0.055), roughness=0.78),
        "Arms_Claws_Bark": C.make_material("ForestBarkArms", (0.16, 0.085, 0.042), roughness=0.80),
        "Legs_Roots_Bark": C.make_material("ForestBarkLegs", (0.13, 0.070, 0.035), roughness=0.84),
        "Moss_Drape_Patches": C.make_material("ForestMossEmerald", (0.09, 0.42, 0.06), roughness=0.82),
        "Foliage_Shoulders_Vines": C.make_material("ForestFoliageCanopy", (0.045, 0.28, 0.045), roughness=0.72),
        "Bioluminescent_Eyes_Mushrooms": C.make_material(
            "ForestBioGlowJade",
            (0.14, 1.0, 0.34),
            roughness=0.16,
            emission=(0.12, 1.0, 0.32),
            emission_strength=2.4,
        ),
        "Mushroom_Stems": C.make_material(
            "ForestMushroomStem",
            (0.58, 0.88, 0.56),
            roughness=0.48,
            emission=(0.10, 0.32, 0.14),
            emission_strength=0.45,
        ),
        "Mouth_Eye_Hollows": C.make_material("ForestHollowDark", (0.015, 0.012, 0.010), roughness=0.96),
    }


def import_and_prepare_meshes() -> list[bpy.types.Object]:
    """Import forest_monster.glb, scale to stud target height, ground at Z=0, and color."""
    assert SOURCE_GLB.exists(), f"Missing source GLB: {SOURCE_GLB}"
    bpy.ops.import_scene.gltf(filepath=str(SOURCE_GLB))

    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    assert meshes, "No meshes found inside forest_monster.glb"

    # Unparent cleanly while keeping world transforms, then remove empty wrapper nodes
    for obj in meshes:
        world_mat = obj.matrix_world.copy()
        obj.parent = None
        obj.matrix_world = world_mat
    for obj in list(bpy.context.scene.objects):
        if obj.type != "MESH":
            bpy.data.objects.remove(obj, do_unlink=True)

    mins, maxs = C.world_bounds(meshes)
    cur_h = max(0.01, maxs.z - mins.z)
    scale_factor = TARGET_HEIGHT_STUDS / cur_h
    center_xy = Vector(((mins.x + maxs.x) * 0.5, (mins.y + maxs.y) * 0.5, mins.z))

    mats = build_materials()
    for obj in meshes:
        obj.location = (obj.location - center_xy) * scale_factor
        obj.scale = obj.scale * scale_factor
    bpy.context.view_layer.update()

    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    for obj in meshes:
        mat = mats.get(obj.name)
        if mat:
            obj.data.materials.clear()
            obj.data.materials.append(mat)
    return meshes


def build_armature(scale_ref: float) -> bpy.types.Object:
    """Create 6-bone Roblox-ready Armature aligned to Forest Monster anatomy."""
    s = scale_ref / 3.91
    arm_data = bpy.data.armatures.new("ForestMonsterArmature")
    arm_obj = bpy.data.objects.new("ForestMonster", arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones

    root = eb.new("HumanoidRootPart")
    root.head, root.tail = Vector((0, 0, 0)), Vector((0, 0, 1.0 * s))

    legs = eb.new("Legs")
    legs.head, legs.tail, legs.parent = Vector((0, 0, 1.22 * s)), Vector((0, 0, 0.15 * s)), root

    torso = eb.new("Torso")
    torso.head, torso.tail, torso.parent = Vector((0, 0, 1.15 * s)), Vector((0, 0, 3.10 * s)), root

    arms = eb.new("Arms")
    arms.head, arms.tail, arms.parent = Vector((0, -0.15 * s, 2.25 * s)), Vector((0, -0.35 * s, 0.60 * s)), torso

    foliage = eb.new("Foliage")
    foliage.head, foliage.tail, foliage.parent = Vector((0, 0.08 * s, 2.45 * s)), Vector((0, 0.12 * s, 3.25 * s)), torso

    moss = eb.new("Moss")
    moss.head, moss.tail, moss.parent = Vector((0, 0.18 * s, 2.20 * s)), Vector((0, 0.28 * s, 2.95 * s)), torso

    bpy.ops.object.mode_set(mode="OBJECT")
    return arm_obj


def bind_meshes_to_armature(arm_obj: bpy.types.Object, meshes: list[bpy.types.Object]) -> None:
    """Bind each mesh part cleanly with 1.0 rigid weight to its anatomical bone."""
    for obj in meshes:
        bone_name = MESH_TO_BONE.get(obj.name, "Torso")
        obj.vertex_groups.clear()
        vg = obj.vertex_groups.new(name=bone_name)
        vg.add(range(len(obj.data.vertices)), 1.0, "REPLACE")
        mod = obj.modifiers.new(name="Armature", type="ARMATURE")
        mod.object = arm_obj
        obj.parent = arm_obj


def author_animations(arm_obj: bpy.types.Object) -> None:
    """Author looping 24 FPS Idle, Walk, and Attack NLA clips."""
    def make_clip(
        name: str,
        end_f: int,
        keys: list[tuple[int, dict[str, tuple[tuple[float, float, float], tuple[float, float, float]]]]],
    ) -> None:
        anim = arm_obj.animation_data or arm_obj.animation_data_create()
        act = bpy.data.actions.new(name=name)
        anim.action = act
        for frame, data in keys:
            for pb in arm_obj.pose.bones:
                pb.rotation_mode = "XYZ"
                loc, rot = data.get(pb.name, ((0.0, 0.0, 0.0), (0.0, 0.0, 0.0)))
                pb.location = Vector(loc)
                pb.rotation_euler = Euler(tuple(math.radians(a) for a in rot), "XYZ")
                pb.keyframe_insert(data_path="location", frame=frame)
                pb.keyframe_insert(data_path="rotation_euler", frame=frame)
        C.push_action_to_nla(arm_obj, act, name, end_f)

    make_clip("Idle", 48, [
        (1, {}),
        (16, {
            "Torso": ((0, 0, 0.12), (4, 9, 2.5)),
            "Arms": ((0, 0, 0), (-6, 3, 2)),
            "Foliage": ((0, 0, 0), (4, 2, 3)),
            "Moss": ((0, 0, 0), (2.5, 0, 1.5)),
        }),
        (34, {
            "Torso": ((0, 0, -0.06), (-2.5, -10, -2.5)),
            "Arms": ((0, 0, 0), (5, -3, -2)),
            "Foliage": ((0, 0, 0), (-3.5, -2, -2.5)),
            "Moss": ((0, 0, 0), (-2, 0, -1.5)),
        }),
        (48, {}),
    ])

    make_clip("Walk", 24, [
        (1, {
            "Torso": ((0, 0, 0.24), (10, 9, 8)),
            "Arms": ((0, 0, 0), (20, 10, 6)),
            "Legs": ((0, 0, 0.12), (0, -10, -10)),
            "Foliage": ((0, 0, 0), (8, 3, 6)),
        }),
        (7, {
            "Torso": ((0, 0, 0.04), (13, 0, 0)),
            "Arms": ((0, 0, 0), (0, -8, 0)),
            "Legs": ((0, 0, 0.0), (0, 0, 0)),
            "Foliage": ((0, 0, 0), (-6, 0, -4)),
        }),
        (13, {
            "Torso": ((0, 0, 0.24), (10, -9, -8)),
            "Arms": ((0, 0, 0), (-20, -10, -6)),
            "Legs": ((0, 0, 0.12), (0, 10, 10)),
            "Foliage": ((0, 0, 0), (8, -3, -6)),
        }),
        (19, {
            "Torso": ((0, 0, 0.04), (13, 0, 0)),
            "Arms": ((0, 0, 0), (0, 8, 0)),
            "Legs": ((0, 0, 0.0), (0, 0, 0)),
            "Foliage": ((0, 0, 0), (-6, 0, 4)),
        }),
        (24, {
            "Torso": ((0, 0, 0.24), (10, 9, 8)),
            "Arms": ((0, 0, 0), (20, 10, 6)),
            "Legs": ((0, 0, 0.12), (0, -10, -10)),
            "Foliage": ((0, 0, 0), (8, 3, 6)),
        }),
    ])

    make_clip("Attack", 18, [
        (1, {}),
        (6, {
            "Torso": ((0, 0.30, 0.22), (-22, 0, 0)),
            "Arms": ((0, 0, 0), (-52, 0, 0)),
            "Foliage": ((0, 0, 0), (14, 0, 0)),
        }),
        (11, {
            "Torso": ((0, -0.65, -0.08), (28, 0, 0)),
            "Arms": ((0, 0, 0), (36, 0, 0)),
            "Foliage": ((0, 0, 0), (-16, 0, 0)),
        }),
        (18, {}),
    ])


def main() -> None:
    C.clear_scene()
    meshes = import_and_prepare_meshes()
    arm_obj = build_armature(TARGET_HEIGHT_STUDS)
    bind_meshes_to_armature(arm_obj, meshes)
    author_animations(arm_obj)

    C.validate_asset("ForestMonster_Rigged", meshes, tri_cap=20000, pivot_mode="floor")
    fbx_path, glb_path = C.export_roblox_asset("ForestMonster_Rigged", [arm_obj, *meshes], rigged=True)
    render_path = C.setup_studio_render(meshes, "ForestMonster_preview.png", resolution=640, samples=22, cam_azimuth_deg=-28.0, cam_elev_deg=14.0, distance_mult=2.25)
    print(f"[DONE] Exported {fbx_path.name}, {glb_path.name}, and {render_path.name}")


if __name__ == "__main__":
    main()
