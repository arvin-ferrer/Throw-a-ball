"""Shared headless Blender 5.x helpers for Ball Brawl: Boss Eggs 3D assets.

Provides deterministic studio lighting, colored PBR preview rendering (Cycles CPU),
faceted/beveled bmesh builders, Roblox stud/triangle/pivot validation, and
Roblox-ready FBX/GLB export presets (-Z forward, +Y up, 1 unit = 1 stud).
"""

from __future__ import annotations

import math
from pathlib import Path
from typing import Iterable

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

ROOT_DIR = Path(__file__).resolve().parents[3]
EXPORT_DIR = ROOT_DIR / "game" / "assets" / "exports"
RENDER_DIR = ROOT_DIR / "game" / "assets" / "renders"


def clear_scene() -> None:
    """Reset Blender to an empty 1-unit-per-stud scene."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "NONE"
    scene.unit_settings.scale_length = 1.0
    scene.render.fps = 24


def make_material(
    name: str,
    color: tuple[float, float, float],
    roughness: float = 0.6,
    metallic: float = 0.0,
    emission: tuple[float, float, float] | None = None,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    """Create a Roblox-safe Principled BSDF material (exports cleanly in FBX & GLB)."""
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic
        if emission and emission_strength > 0.0:
            em_input = bsdf.inputs.get("Emission Color") or bsdf.inputs.get("Emission")
            if em_input:
                em_input.default_value = (*emission, 1.0)
            if "Emission Strength" in bsdf.inputs:
                bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def add_faceted_box(
    bm: bmesh.types.BMesh,
    size: tuple[float, float, float],
    center: tuple[float, float, float],
    mat_idx: int,
    bevel: float = 0.0,
    rot_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
    taper_top: tuple[float, float] = (1.0, 1.0),
    tag_bone: str | None = None,
    bone_map: dict[bmesh.types.BMVert, str] | None = None,
) -> list[bmesh.types.BMVert]:
    """Append a tapered, optionally beveled low-poly box into `bm`."""
    before = set(bm.verts)
    ret = bmesh.ops.create_cube(bm, size=1.0)
    verts = ret["verts"]
    sx, sy, sz = size
    tx, ty = taper_top
    for v in verts:
        if v.co.z > 0.0:
            v.co.x *= tx
            v.co.y *= ty
        v.co.x *= sx
        v.co.y *= sy
        v.co.z *= sz
    if bevel > 0.0:
        edges = list({e for v in verts for e in v.link_edges})
        bmesh.ops.bevel(
            bm,
            geom=edges,
            offset=bevel,
            segments=1,
            affect="EDGES",
            clamp_overlap=True,
        )
    new_verts = [v for v in bm.verts if v not in before]
    rot = Euler(tuple(math.radians(a) for a in rot_deg), "XYZ").to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector(center)) @ rot, verts=new_verts)
    for f in {f for v in new_verts for f in v.link_faces}:
        f.material_index = mat_idx
        f.smooth = False
    if tag_bone and bone_map is not None:
        for v in new_verts:
            bone_map[v] = tag_bone
    return new_verts


def add_faceted_icosphere(
    bm: bmesh.types.BMesh,
    radius: float,
    center: tuple[float, float, float],
    mat_idx: int,
    subdivisions: int = 2,
    scale: tuple[float, float, float] = (1.0, 1.0, 1.0),
    rot_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
    noise_amp: float = 0.0,
    seed: int = 1,
    tag_bone: str | None = None,
    bone_map: dict[bmesh.types.BMVert, str] | None = None,
) -> list[bmesh.types.BMVert]:
    """Append a stylized faceted rock/clump icosphere with optional deterministic crag."""
    ret = bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=radius)
    verts = ret["verts"]
    sx, sy, sz = scale
    for idx, v in enumerate(verts):
        if noise_amp > 0.0:
            h = math.sin(v.co.x * 7.3 + seed * 1.9) * math.cos(v.co.y * 6.1 - seed)
            h2 = math.sin(v.co.z * 8.7 + idx * 0.37 + seed)
            v.co *= 1.0 + noise_amp * (0.6 * h + 0.4 * h2)
        v.co.x *= sx
        v.co.y *= sy
        v.co.z *= sz
    rot = Euler(tuple(math.radians(a) for a in rot_deg), "XYZ").to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector(center)) @ rot, verts=verts)
    for f in {f for v in verts for f in v.link_faces}:
        f.material_index = mat_idx
        f.smooth = False
    if tag_bone and bone_map is not None:
        for v in verts:
            bone_map[v] = tag_bone
    return verts


def add_crystal_prism(
    bm: bmesh.types.BMesh,
    radius: float,
    height: float,
    center: tuple[float, float, float],
    mat_idx: int,
    sides: int = 6,
    rot_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
    tag_bone: str | None = None,
    bone_map: dict[bmesh.types.BMVert, str] | None = None,
) -> list[bmesh.types.BMVert]:
    """Append a pointed low-poly crystal shard/spike."""
    ret = bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=sides,
        radius1=radius,
        radius2=radius * 0.12,
        depth=height,
    )
    verts = ret["verts"]
    rot = Euler(tuple(math.radians(a) for a in rot_deg), "XYZ").to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector(center)) @ rot, verts=verts)
    for f in {f for v in verts for f in v.link_faces}:
        f.material_index = mat_idx
        f.smooth = False
    if tag_bone and bone_map is not None:
        for v in verts:
            bone_map[v] = tag_bone
    return verts


def add_closed_ring(
    bm: bmesh.types.BMesh,
    radius: float,
    radial_thickness: float,
    axial_width: float,
    mat_idx: int,
    rot_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
    segments: int = 20,
) -> list[bmesh.types.BMVert]:
    """Append a seamless closed low-poly rectangular-section ring (zero segment gaps)."""
    r_in = radius - radial_thickness * 0.5
    r_out = radius + radial_thickness * 0.5
    hw = axial_width * 0.5
    profile = [(r_in, -hw), (r_out, -hw), (r_out, hw), (r_in, hw)]
    rings: list[list[bmesh.types.BMVert]] = []
    rot = Euler(tuple(math.radians(a) for a in rot_deg), "XYZ").to_matrix().to_4x4()
    for i in range(segments):
        ang = 2.0 * math.pi * i / segments
        ca, sa = math.cos(ang), math.sin(ang)
        loop = [bm.verts.new(rot @ Vector((r * ca, r * sa, z))) for r, z in profile]
        rings.append(loop)
    all_verts = [v for loop in rings for v in loop]
    for i in range(segments):
        a = rings[i]
        b = rings[(i + 1) % segments]
        for j in range(4):
            jn = (j + 1) % 4
            f = bm.faces.new((a[j], a[jn], b[jn], b[j]))
            f.material_index = mat_idx
            f.smooth = False
    return all_verts


def add_lofted_tube(
    bm: bmesh.types.BMesh,
    rings: list[tuple[tuple[float, float, float], float, float, tuple[float, float, float]]],
    mat_idx: int,
    sides: int = 10,
    smooth: bool = True,
    cap_start: bool = True,
    cap_end: bool = True,
    tag_bone: str | None = None,
    bone_map: dict[bmesh.types.BMVert, str] | None = None,
) -> list[bmesh.types.BMVert]:
    """Loft a tapered organic body, limb, tail, curved tusk, horn, or antler through rings.

    Each ring is ((cx, cy, cz), radius_x, radius_y, (rx_deg, ry_deg, rz_deg)).
    """
    loops: list[list[bmesh.types.BMVert]] = []
    for center, rx, ry, rot_deg in rings:
        rot = Euler(tuple(math.radians(a) for a in rot_deg), "XYZ").to_matrix().to_4x4()
        cvec = Vector(center)
        loop: list[bmesh.types.BMVert] = []
        for i in range(sides):
            ang = 2.0 * math.pi * i / sides
            pt = cvec + (rot @ Vector((rx * math.cos(ang), ry * math.sin(ang), 0.0)))
            loop.append(bm.verts.new(pt))
        loops.append(loop)
    all_verts = [v for loop in loops for v in loop]
    for r_idx in range(len(loops) - 1):
        a, b = loops[r_idx], loops[r_idx + 1]
        for i in range(sides):
            inext = (i + 1) % sides
            f = bm.faces.new((a[i], a[inext], b[inext], b[i]))
            f.material_index = mat_idx
            f.smooth = smooth
    if cap_start and len(loops[0]) >= 3:
        f = bm.faces.new(tuple(reversed(loops[0])))
        f.material_index = mat_idx
        f.smooth = False
    if cap_end and len(loops[-1]) >= 3:
        f = bm.faces.new(tuple(loops[-1]))
        f.material_index = mat_idx
        f.smooth = False
    if tag_bone and bone_map is not None:
        for v in all_verts:
            bone_map[v] = tag_bone
    return all_verts


def add_lathe_shell(
    bm: bmesh.types.BMesh,
    profile: list[tuple[float, float]],
    mat_idx: int,
    segments: int = 16,
    center: tuple[float, float, float] = (0.0, 0.0, 0.0),
    scale_xy: tuple[float, float] = (1.0, 1.0),
    smooth: bool = True,
    tag_bone: str | None = None,
    bone_map: dict[bmesh.types.BMVert, str] | None = None,
) -> list[bmesh.types.BMVert]:
    """Revolve a (radius, z) profile into a smooth sculpted egg, slime dome, or teardrop."""
    cx, cy, cz = center
    sx, sy = scale_xy
    rings: list[list[bmesh.types.BMVert]] = []
    for r, z in profile:
        r_safe = max(r, 0.015)
        loop = [
            bm.verts.new(Vector((
                cx + r_safe * sx * math.cos(2.0 * math.pi * i / segments),
                cy + r_safe * sy * math.sin(2.0 * math.pi * i / segments),
                cz + z,
            )))
            for i in range(segments)
        ]
        rings.append(loop)
    all_verts = [v for loop in rings for v in loop]
    for k in range(len(rings) - 1):
        a, b = rings[k], rings[k + 1]
        for i in range(segments):
            inext = (i + 1) % segments
            f = bm.faces.new((a[i], a[inext], b[inext], b[i]))
            f.material_index = mat_idx
            f.smooth = smooth
    for cap_loop, rev in ((rings[0], True), (rings[-1], False)):
        f = bm.faces.new(tuple(reversed(cap_loop) if rev else cap_loop))
        f.material_index = mat_idx
        f.smooth = False
    if tag_bone and bone_map is not None:
        for v in all_verts:
            bone_map[v] = tag_bone
    return all_verts


def add_expressive_eye(
    bm: bmesh.types.BMesh,
    pos: tuple[float, float, float],
    radius: float,
    dark_mat: int,
    highlight_mat: int,
    tag_bone: str | None = None,
    bone_map: dict[bmesh.types.BMVert, str] | None = None,
) -> None:
    """Add a glossy stylized pet/mob eye with a crisp bright catchlight pip."""
    x, y, z = pos
    add_faceted_icosphere(
        bm, radius, (x, y, z), dark_mat, subdivisions=2,
        scale=(1.0, 0.65, 1.12), tag_bone=tag_bone, bone_map=bone_map,
    )
    add_faceted_icosphere(
        bm, radius * 0.34, (x + radius * 0.28, y - radius * 0.56, z + radius * 0.34),
        highlight_mat, subdivisions=1, tag_bone=tag_bone, bone_map=bone_map,
    )


def extract_bone_index_map(
    bm: bmesh.types.BMesh,
    bone_map: dict[bmesh.types.BMVert, str],
) -> dict[int, str]:
    """Convert BMVert->bone mapping to final vertex index->bone mapping before to_mesh."""
    bm.verts.index_update()
    return {v.index: bname for v, bname in bone_map.items() if v.is_valid}


def finalize_mesh(
    name: str,
    bm: bmesh.types.BMesh,
    materials: list[bpy.types.Material],
) -> bpy.types.Object:
    """Clean normals, build mesh object, attach materials, and link to scene."""
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for mat in materials:
        mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def assign_bone_weights(
    mesh_obj: bpy.types.Object,
    armature_obj: bpy.types.Object,
    bone_map: dict[int, str],
    fallback_bone: str,
) -> None:
    """Bind mesh vertices to exact bone groups (<=4 weights/vert, zero unweighted)."""
    groups: dict[str, bpy.types.VertexGroup] = {}
    for bone in armature_obj.data.bones:
        groups[bone.name] = mesh_obj.vertex_groups.new(name=bone.name)
    for idx in range(len(mesh_obj.data.vertices)):
        bname = bone_map.get(idx, fallback_bone)
        vg = groups.get(bname) or groups[fallback_bone]
        vg.add([idx], 1.0, "REPLACE")
    mod = mesh_obj.modifiers.new(name="Armature", type="ARMATURE")
    mod.object = armature_obj
    mesh_obj.parent = armature_obj


def reset_pose(armature_obj: bpy.types.Object) -> None:
    """Reset all pose bones to neutral rest transforms."""
    for pbone in armature_obj.pose.bones:
        pbone.location = Vector((0.0, 0.0, 0.0))
        pbone.rotation_euler = Euler((0.0, 0.0, 0.0), "XYZ")
        pbone.scale = Vector((1.0, 1.0, 1.0))


def push_action_to_nla(
    armature_obj: bpy.types.Object,
    action: bpy.types.Action,
    clip_name: str,
    end_frame: int,
) -> None:
    """Push a keyed Action onto its own named NLA track (Blender 5.x slot-safe)."""
    anim_data = armature_obj.animation_data
    assert anim_data is not None
    action.name = clip_name
    action.use_fake_user = True
    slot = getattr(anim_data, "action_slot", None)
    track = anim_data.nla_tracks.new()
    track.name = clip_name
    strip = track.strips.new(clip_name, start=1, action=action)
    strip.action_frame_start = 1
    strip.action_frame_end = end_frame
    if slot is not None and hasattr(strip, "action_slot"):
        strip.action_slot = slot
    track.mute = False
    anim_data.action = None


def count_triangles(objs: Iterable[bpy.types.Object]) -> int:
    """Count exact evaluated mesh triangles across all provided mesh objects."""
    total = 0
    for obj in objs:
        if obj.type == "MESH":
            obj.data.calc_loop_triangles()
            total += len(obj.data.loop_triangles)
    return total


def world_bounds(objs: Iterable[bpy.types.Object]) -> tuple[Vector, Vector]:
    """Compute world-space min/max bounding corners across mesh objects."""
    mins = Vector((1e9, 1e9, 1e9))
    maxs = Vector((-1e9, -1e9, -1e9))
    for obj in objs:
        if obj.type != "MESH":
            continue
        for corner in obj.bound_box:
            pt = obj.matrix_world @ Vector(corner)
            mins.x, mins.y, mins.z = min(mins.x, pt.x), min(mins.y, pt.y), min(mins.z, pt.z)
            maxs.x, maxs.y, maxs.z = max(maxs.x, pt.x), max(maxs.y, pt.y), max(maxs.z, pt.z)
    return mins, maxs


def validate_asset(
    name: str,
    objs: list[bpy.types.Object],
    tri_cap: int,
    pivot_mode: str = "floor",
) -> tuple[int, Vector]:
    """Assert triangle budget, stud bounds, and pivot placement; print QA summary."""
    tris = count_triangles(objs)
    assert tris <= tri_cap, f"{name}: {tris} tris exceeds cap {tri_cap}"
    mins, maxs = world_bounds(objs)
    dims = maxs - mins
    center = (mins + maxs) * 0.5
    if pivot_mode == "floor":
        assert abs(mins.z) <= 0.05, f"{name}: floor pivot min_z={mins.z:.3f} (expected ~0)"
        assert abs(center.x) <= 0.8 and abs(center.y) <= 1.0, f"{name}: off-center {center}"
    elif pivot_mode == "hover":
        assert 0.0 <= mins.z <= 0.9, f"{name}: hover pivot min_z={mins.z:.3f} (expected 0..0.9)"
        assert abs(center.x) <= 0.8 and abs(center.y) <= 1.0, f"{name}: off-center {center}"
    elif pivot_mode == "center":
        assert center.length <= 0.1, f"{name}: center pivot offset={center.length:.3f}"
    print(
        f"[QA] {name}: tris={tris}/{tri_cap} | "
        f"dims=({dims.x:.2f}W x {dims.y:.2f}D x {dims.z:.2f}H studs) | "
        f"min_z={mins.z:.2f}"
    )
    return tris, dims


def export_roblox_asset(
    asset_name: str,
    export_objs: list[bpy.types.Object],
    rigged: bool = False,
) -> tuple[Path, Path]:
    """Export selected asset objects to Roblox-ready .fbx and .glb."""
    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in export_objs:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = export_objs[0]

    fbx_path = EXPORT_DIR / f"{asset_name}.fbx"
    glb_path = EXPORT_DIR / f"{asset_name}.glb"

    bpy.ops.export_scene.fbx(
        filepath=str(fbx_path),
        use_selection=True,
        global_scale=1.0,
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_ALL",
        axis_forward="-Z",
        axis_up="Y",
        bake_space_transform=False,
        object_types={"ARMATURE", "MESH"} if rigged else {"MESH"},
        use_armature_deform_only=True,
        add_leaf_bones=False,
        bake_anim=rigged,
        bake_anim_use_nla_strips=rigged,
        bake_anim_use_all_actions=False,
        path_mode="COPY",
        embed_textures=True,
    )
    bpy.ops.export_scene.gltf(
        filepath=str(glb_path),
        use_selection=True,
        export_format="GLB",
        export_yup=True,
        export_materials="EXPORT",
        export_apply=not rigged,
        export_animations=rigged,
        export_nla_strips=rigged,
    )
    return fbx_path, glb_path


def clear_studio_rig() -> None:
    """Remove previously created temporary studio floor, lights, and camera."""
    for name in ("_StudioFloor", "KeyLight", "FillLight", "RimLight", "PreviewCam"):
        obj = bpy.data.objects.get(name)
        if obj is not None:
            bpy.data.objects.remove(obj, do_unlink=True)


def setup_studio_render(
    objs: list[bpy.types.Object],
    filename: str,
    resolution: int = 640,
    samples: int = 24,
    cam_azimuth_deg: float = -36.0,
    cam_elev_deg: float = 18.0,
    distance_mult: float = 2.15,
    add_floor: bool = True,
) -> Path:
    """Render a colored PBR studio preview PNG (Cycles CPU, dark neutral backdrop)."""
    clear_studio_rig()
    RENDER_DIR.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = False
    scene.cycles.max_bounces = 4
    scene.cycles.diffuse_bounces = 2
    scene.cycles.glossy_bounces = 2
    scene.render.threads_mode = "FIXED"
    scene.render.threads = 4
    scene.render.resolution_x = resolution
    scene.render.resolution_y = resolution
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "Standard"

    world = bpy.data.worlds.new("StudioWorld")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs["Color"].default_value = (0.045, 0.052, 0.062, 1.0)
        bg.inputs["Strength"].default_value = 0.85
    scene.world = world

    mins, maxs = world_bounds(objs)
    center = (mins + maxs) * 0.5
    radius = max((maxs - mins).length * 0.5, 0.5)

    if add_floor:
        bpy.ops.mesh.primitive_plane_add(size=radius * 8.0, location=(center.x, center.y, mins.z - 0.01))
        floor = bpy.context.active_object
        floor.name = "_StudioFloor"
        floor.data.materials.append(make_material("_FloorMat", (0.09, 0.10, 0.11), roughness=0.88))

    # 3-point studio lighting (key, cool fill, crisp rim)
    lights = [
        ("KeyLight", "AREA", (radius * 2.2, -radius * 2.4, center.z + radius * 2.1), radius * 160.0, (1.0, 0.96, 0.90), radius * 1.6),
        ("FillLight", "AREA", (-radius * 2.4, -radius * 1.2, center.z + radius * 1.0), radius * 65.0, (0.72, 0.86, 1.0), radius * 2.2),
        ("RimLight", "AREA", (radius * 0.4, radius * 2.6, center.z + radius * 1.8), radius * 120.0, (0.78, 1.0, 0.88), radius * 1.8),
    ]
    for lname, ltype, loc, energy, col, lsize in lights:
        ldata = bpy.data.lights.new(name=lname, type=ltype)
        ldata.energy = energy
        ldata.color = col
        ldata.size = lsize
        lobj = bpy.data.objects.new(name=lname, object_data=ldata)
        lobj.location = Vector(loc)
        lobj.rotation_euler = (center - lobj.location).to_track_quat("-Z", "Y").to_euler()
        bpy.context.collection.objects.link(lobj)

    az = math.radians(cam_azimuth_deg)
    el = math.radians(cam_elev_deg)
    dist = radius * distance_mult
    cam_pos = center + Vector((
        dist * math.cos(el) * math.sin(az),
        -dist * math.cos(el) * math.cos(az),
        dist * math.sin(el),
    ))
    cam_data = bpy.data.cameras.new("PreviewCam")
    cam_data.lens = 48.0
    cam_obj = bpy.data.objects.new("PreviewCam", cam_data)
    cam_obj.location = cam_pos
    cam_obj.rotation_euler = (center - cam_pos).to_track_quat("-Z", "Y").to_euler()
    bpy.context.collection.objects.link(cam_obj)
    scene.camera = cam_obj

    out_path = RENDER_DIR / filename
    scene.render.filepath = str(out_path)
    bpy.ops.render.render(write_still=True)
    return out_path
