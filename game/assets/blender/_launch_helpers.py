"""Shared Blender 5.x composition & rendering helpers for Ball Brawl launch art."""

from __future__ import annotations

import math
from dataclasses import dataclass
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Vector

import _common as C

UI_DIR = C.ROOT_DIR / "game" / "assets" / "ui"
RENDER_DIR = C.RENDER_DIR
FAST_PREVIEW_DIR = C.RENDER_DIR / "launch_previews"


@dataclass
class ImportedAsset:
    """Handle to a grouped GLB import rooted under an Empty pivot."""

    name: str
    pivot: bpy.types.Object
    objects: list[bpy.types.Object]
    meshes: list[bpy.types.Object]
    armatures: list[bpy.types.Object]


def resolve_output_dir(target_dir: Path, fast: bool) -> Path:
    """Route --fast previews to FAST_PREVIEW_DIR so final assets are never overwritten."""
    return FAST_PREVIEW_DIR if fast else target_dir


def ensure_collection(name: str) -> bpy.types.Collection:
    """Get or create a collection linked to the active scene."""
    coll = bpy.data.collections.get(name)
    if coll is None:
        coll = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(coll)
    return coll


def move_to_collection(objs: list[bpy.types.Object], coll: bpy.types.Collection) -> None:
    """Link objects exclusively into `coll`."""
    for obj in objs:
        for old in list(obj.users_collection):
            old.objects.unlink(obj)
        coll.objects.link(obj)


def _strip_bone_placeholders(objs: list[bpy.types.Object]) -> list[bpy.types.Object]:
    """Remove glTF-imported armature bone-shape placeholder meshes."""
    kept: list[bpy.types.Object] = []
    for obj in objs:
        is_placeholder = (
            obj.type == "MESH"
            and obj.name.startswith("Icosphere")
            and len(obj.data.materials) == 0
        )
        if is_placeholder:
            bpy.data.objects.remove(obj, do_unlink=True)
        else:
            kept.append(obj)
    return kept


def import_glb(filename: str, tag: str, coll_name: str = "Assets") -> ImportedAsset:
    """Import a GLB from EXPORT_DIR under a single controllable Empty pivot."""
    path = C.EXPORT_DIR / filename
    if not path.exists():
        raise FileNotFoundError(f"Missing GLB export: {path}")

    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    bpy.context.view_layer.update()

    new_objs = _strip_bone_placeholders([o for o in bpy.data.objects if o not in before])
    roots = [o for o in new_objs if o.parent is None]

    pivot = bpy.data.objects.new(f"{tag}_Pivot", None)
    pivot.empty_display_type = "PLAIN_AXES"
    coll = ensure_collection(coll_name)
    coll.objects.link(pivot)

    for root in roots:
        mat_w = root.matrix_world.copy()
        root.parent = pivot
        root.matrix_world = mat_w

    move_to_collection(new_objs, coll)
    bpy.context.view_layer.update()
    meshes = [o for o in new_objs if o.type == "MESH"]
    armatures = [o for o in new_objs if o.type == "ARMATURE"]
    return ImportedAsset(tag, pivot, new_objs, meshes, armatures)


def pose_rig_clean(
    arm_obj: bpy.types.Object,
    bone_rots_deg: dict[str, tuple[float, float, float]],
) -> None:
    """Mute baked NLA tracks, reset bones to rest pose, and apply offsets."""
    ad = arm_obj.animation_data
    if ad is not None:
        ad.action = None
        for tr in ad.nla_tracks:
            tr.mute = True
    for pb in arm_obj.pose.bones:
        pb.location = Vector((0.0, 0.0, 0.0))
        pb.rotation_mode = "XYZ"
        pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pb.rotation_euler = Euler((0.0, 0.0, 0.0), "XYZ")
        pb.scale = Vector((1.0, 1.0, 1.0))
    for bname, deg in bone_rots_deg.items():
        pb = arm_obj.pose.bones.get(bname)
        if pb is not None:
            pb.rotation_euler = Euler(tuple(math.radians(a) for a in deg), "XYZ")
    bpy.context.view_layer.update()


def evaluated_bounds(meshes: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    """Compute world-space min/max corners using evaluated posed meshes."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mins = Vector((1e9, 1e9, 1e9))
    maxs = Vector((-1e9, -1e9, -1e9))
    for obj in meshes:
        eval_obj = obj.evaluated_get(depsgraph)
        me = eval_obj.to_mesh()
        try:
            mw = eval_obj.matrix_world
            for v in me.vertices:
                pt = mw @ v.co
                mins.x, mins.y, mins.z = min(mins.x, pt.x), min(mins.y, pt.y), min(mins.z, pt.z)
                maxs.x, maxs.y, maxs.z = max(maxs.x, pt.x), max(maxs.y, pt.y), max(maxs.z, pt.z)
        finally:
            eval_obj.to_mesh_clear()
    return mins, maxs


def place_asset(
    asset: ImportedAsset,
    loc: tuple[float, float, float],
    rot_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
    scale: float = 1.0,
    ground_z: float | None = None,
) -> ImportedAsset:
    """Position, rotate, scale, and optionally ground an imported asset pivot."""
    asset.pivot.rotation_euler = Euler(tuple(math.radians(a) for a in rot_deg), "XYZ")
    asset.pivot.scale = Vector((scale, scale, scale))
    asset.pivot.location = Vector(loc)
    bpy.context.view_layer.update()
    if ground_z is not None:
        mins, _ = evaluated_bounds(asset.meshes)
        asset.pivot.location.z += ground_z - mins.z
        bpy.context.view_layer.update()
    return asset


def boost_pyraxis_accents(asset: ImportedAsset) -> None:
    """Give Pyraxis's warm volcanic spikes/eyes crisp hero emissive pop under AgX."""
    for m in asset.meshes:
        for mat in m.data.materials:
            if not mat or not mat.use_nodes:
                continue
            bsdf = mat.node_tree.nodes.get("Principled BSDF")
            if not bsdf:
                continue
            col = bsdf.inputs["Base Color"].default_value
            if col[0] > 0.7 and col[1] < 0.35 and col[2] < 0.15:
                em = bsdf.inputs.get("Emission Color") or bsdf.inputs.get("Emission")
                if em:
                    em.default_value = (1.0, 0.34, 0.03, 1.0)
                if "Emission Strength" in bsdf.inputs:
                    bsdf.inputs["Emission Strength"].default_value = 2.0


def _setup_bloom_compositor(sc: bpy.types.Scene, threshold: float, strength: float) -> None:
    """Attach a Blender 5.x Bloom glare compositor node group to `sc`."""
    tree = bpy.data.node_groups.new("LaunchComp", "CompositorNodeTree")
    sc.compositing_node_group = tree
    tree.interface.new_socket(name="Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    rl = tree.nodes.new("CompositorNodeRLayers")
    glare = tree.nodes.new("CompositorNodeGlare")
    glare.inputs["Type"].default_value = "Bloom"
    glare.inputs["Quality"].default_value = "High"
    glare.inputs["Threshold"].default_value = threshold
    glare.inputs["Strength"].default_value = strength
    glare.inputs["Size"].default_value = 0.55
    out = tree.nodes.new("NodeGroupOutput")
    tree.links.new(glare.inputs["Image"], rl.outputs["Image"])
    tree.links.new(out.inputs["Image"], glare.outputs["Image"])


def setup_render_pipeline(
    res_x: int,
    res_y: int,
    samples: int,
    exposure: float = -0.25,
    bloom_threshold: float = 1.55,
    bloom_strength: float = 0.16,
) -> None:
    """Configure Cycles CPU + OpenImageDenoise + AgX High Contrast + Bloom."""
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_adaptive_sampling = True
    sc.cycles.adaptive_threshold = 0.02
    sc.cycles.use_denoising = True
    if hasattr(sc.cycles, "denoiser"):
        sc.cycles.denoiser = "OPENIMAGEDENOISE"
    sc.cycles.max_bounces = 4
    sc.cycles.diffuse_bounces = 2
    sc.cycles.glossy_bounces = 2
    sc.cycles.transmission_bounces = 2
    sc.cycles.caustics_reflective = False
    sc.cycles.caustics_refractive = False
    sc.cycles.use_fast_gi = True
    sc.cycles.fast_gi_method = "REPLACE"
    sc.cycles.ao_bounces_render = 1

    sc.render.threads_mode = "FIXED"
    sc.render.threads = 8
    sc.render.resolution_x = res_x
    sc.render.resolution_y = res_y
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGB"

    sc.view_settings.view_transform = "AgX"
    try:
        sc.view_settings.look = "AgX - High Contrast"
    except TypeError:
        sc.view_settings.look = "None"
    sc.view_settings.exposure = exposure
    _setup_bloom_compositor(sc, bloom_threshold, bloom_strength)


def set_gradient_world(
    horizon_col: tuple[float, float, float],
    zenith_col: tuple[float, float, float],
    strength: float = 0.75,
) -> None:
    """Create a procedural vertical sky gradient world shader."""
    world = bpy.data.worlds.new("LaunchWorld")
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()

    tex = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = (*horizon_col, 1.0)
    ramp.color_ramp.elements[1].position = 0.55
    ramp.color_ramp.elements[1].color = (*zenith_col, 1.0)

    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs["Strength"].default_value = strength
    out = nt.nodes.new("ShaderNodeOutputWorld")

    nt.links.new(sep.inputs["Vector"], tex.outputs["Generated"])
    nt.links.new(ramp.inputs["Fac"], sep.outputs["Z"])
    nt.links.new(bg.inputs["Color"], ramp.outputs["Color"])
    nt.links.new(out.inputs["Surface"], bg.outputs["Background"])
    bpy.context.scene.world = world


def add_area_light(
    name: str,
    loc: tuple[float, float, float],
    target: tuple[float, float, float],
    energy: float,
    color: tuple[float, float, float],
    size: float,
    size_y: float | None = None,
) -> bpy.types.Object:
    """Create a rectangular or disk Area light aimed at `target`."""
    ldata = bpy.data.lights.new(name=name, type="AREA")
    ldata.energy = energy
    ldata.color = color
    if size_y is not None:
        ldata.shape = "RECTANGLE"
        ldata.size = size
        ldata.size_y = size_y
    else:
        ldata.shape = "DISK"
        ldata.size = size
    lobj = bpy.data.objects.new(name=name, object_data=ldata)
    lobj.location = Vector(loc)
    lobj.rotation_euler = (Vector(target) - lobj.location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.collection.objects.link(lobj)
    return lobj


def add_point_light(
    name: str,
    loc: tuple[float, float, float],
    energy: float,
    color: tuple[float, float, float],
    radius: float = 0.6,
) -> bpy.types.Object:
    """Create a localized point accent light."""
    ldata = bpy.data.lights.new(name=name, type="POINT")
    ldata.energy = energy
    ldata.color = color
    ldata.shadow_soft_size = radius
    lobj = bpy.data.objects.new(name=name, object_data=ldata)
    lobj.location = Vector(loc)
    bpy.context.collection.objects.link(lobj)
    return lobj


def aim_camera(
    name: str,
    loc: tuple[float, float, float],
    target: tuple[float, float, float],
    lens: float = 38.0,
    roll_deg: float = 0.0,
) -> bpy.types.Object:
    """Create and activate a camera aimed at `target` with optional roll."""
    cam_data = bpy.data.cameras.new(name)
    cam_data.lens = lens
    cam_data.clip_end = 500.0
    cam_obj = bpy.data.objects.new(name, cam_data)
    cam_obj.location = Vector(loc)
    quat = (Vector(target) - cam_obj.location).to_track_quat("-Z", "Y")
    if abs(roll_deg) > 1e-3:
        quat = quat @ Euler((0.0, 0.0, math.radians(roll_deg)), "XYZ").to_quaternion()
    cam_obj.rotation_euler = quat.to_euler()
    bpy.context.collection.objects.link(cam_obj)
    bpy.context.scene.camera = cam_obj
    return cam_obj


def render_to_path(out_dir: Path, filename: str) -> Path:
    """Render current scene to `<out_dir>/<filename>`."""
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / filename
    bpy.context.scene.render.filepath = str(out)
    bpy.ops.render.render(write_still=True)
    print(f"[RENDER_OK] {out}")
    return out


def build_arena_stage(
    name: str,
    radius: float,
    stone_col: tuple[float, float, float],
    trim_col: tuple[float, float, float],
    rune_col: tuple[float, float, float],
    crystal_specs: list[tuple[float, tuple[float, float, float], float]],
) -> bpy.types.Object:
    """Build a multi-step carved stone boss arena floor with rune rings & pillars."""
    mats = [
        C.make_material(f"{name}_StoneDark", stone_col, roughness=0.82),
        C.make_material(f"{name}_StoneTrim", trim_col, roughness=0.68),
        C.make_material(f"{name}_RuneGlow", rune_col, roughness=0.14, emission=rune_col, emission_strength=2.2),
        C.make_material(f"{name}_GoldTrim", (0.95, 0.74, 0.20), roughness=0.24, metallic=0.90),
    ]
    bm = bmesh.new()
    C.add_lathe_shell(
        bm,
        [(radius * 1.45, -1.2), (radius * 1.45, -0.35), (radius * 1.06, -0.35), (radius * 1.02, 0.0), (0.05, 0.0)],
        0, segments=24, smooth=False,
    )
    C.add_closed_ring(bm, radius * 0.74, 0.34, 0.05, 2, segments=24)
    C.add_closed_ring(bm, radius * 0.42, 0.22, 0.05, 3, segments=24)
    for idx, (ang_deg, ccol, cscale) in enumerate(crystal_specs):
        cmat_idx = len(mats)
        mats.append(C.make_material(f"{name}_Crystal{idx}", ccol, roughness=0.14, emission=ccol, emission_strength=2.1))
        rad = math.radians(ang_deg)
        px, py = radius * 1.06 * math.cos(rad), radius * 1.06 * math.sin(rad)
        p_h = 7.5 * cscale
        C.add_faceted_box(bm, (3.0, 3.0, p_h), (px, py, p_h * 0.5 - 0.35), 1, bevel=0.16, rot_deg=(0, 0, ang_deg), taper_top=(0.76, 0.76))
        C.add_crystal_prism(bm, 1.15 * cscale, 4.4 * cscale, (px, py, p_h + 1.2 * cscale), cmat_idx, sides=6, rot_deg=(8, -6, ang_deg))
        C.add_crystal_prism(bm, 0.75 * cscale, 2.8 * cscale, (px * 0.90, py * 0.90, 1.1 * cscale), cmat_idx, sides=5, rot_deg=(-14, 12, ang_deg))
    return C.finalize_mesh(name, bm, mats)


def build_energy_trail(
    name: str,
    points_radii: list[tuple[Vector, float]],
    core_col: tuple[float, float, float],
    outer_col: tuple[float, float, float],
    spark_seed: int = 1,
) -> bpy.types.Object:
    """Build a sculpted glowing curved ball trajectory wake + faceted energy sparks."""
    mats = [
        C.make_material(f"{name}_Core", core_col, roughness=0.10, emission=core_col, emission_strength=3.0),
        C.make_material(f"{name}_Halo", outer_col, roughness=0.18, emission=outer_col, emission_strength=2.1),
    ]
    bm = bmesh.new()
    rings_core: list[tuple[tuple[float, float, float], float, float, tuple[float, float, float]]] = []
    rings_halo: list[tuple[tuple[float, float, float], float, float, tuple[float, float, float]]] = []
    for idx, (pt, r) in enumerate(points_radii):
        tangent = (points_radii[idx + 1][0] - pt).normalized() if idx < len(points_radii) - 1 else (pt - points_radii[idx - 1][0]).normalized()
        rdeg = tuple(math.degrees(a) for a in tangent.to_track_quat("Z", "Y").to_euler())
        rings_core.append(((pt.x, pt.y, pt.z), r * 0.48, r * 0.48, rdeg))
        rings_halo.append(((pt.x, pt.y, pt.z), r, r * 0.72, rdeg))
    C.add_lofted_tube(bm, rings_core, 0, sides=8, smooth=True)
    C.add_lofted_tube(bm, rings_halo, 1, sides=8, smooth=True)
    for idx in range(len(points_radii) - 1):
        p0, r0 = points_radii[idx]
        p1, r1 = points_radii[idx + 1]
        for sub in (0.33, 0.67):
            ang = idx * 2.1 + sub * 5.0 + spark_seed
            sp = p0.lerp(p1, sub) + Vector((math.cos(ang), math.sin(ang) * 0.6, math.sin(ang * 1.7))) * (max(r0, r1) * 1.45 + 0.35)
            C.add_crystal_prism(bm, 0.14, 0.55, (sp.x, sp.y, sp.z), 0 if (idx % 2 == 0) else 1, sides=4, rot_deg=(ang * 30, ang * 20, 0))
    return C.finalize_mesh(name, bm, mats)


def build_impact_burst(
    name: str,
    pos: tuple[float, float, float],
    aim_dir: tuple[float, float, float],
    core_col: tuple[float, float, float],
    spark_col: tuple[float, float, float],
    scale: float = 1.0,
) -> bpy.types.Object:
    """Build starburst shockwave rings + radial impact crystal sparks."""
    mats = [
        C.make_material(f"{name}_Flash", core_col, roughness=0.08, emission=core_col, emission_strength=3.2),
        C.make_material(f"{name}_Sparks", spark_col, roughness=0.14, emission=spark_col, emission_strength=2.5),
    ]
    bm = bmesh.new()
    quat = Vector(aim_dir).normalized().to_track_quat("Z", "Y")
    rdeg = tuple(math.degrees(a) for a in quat.to_euler())
    C.add_faceted_icosphere(bm, 0.75 * scale, (0, 0, 0), 0, subdivisions=1)
    C.add_closed_ring(bm, 1.9 * scale, 0.14 * scale, 0.12 * scale, 0, rot_deg=rdeg, segments=20)
    C.add_closed_ring(bm, 2.9 * scale, 0.10 * scale, 0.08 * scale, 1, rot_deg=rdeg, segments=24)
    for i in range(12):
        ang = math.radians(i * 30.0)
        d = quat @ Vector((math.cos(ang), math.sin(ang), 0.25 * (1 if i % 2 == 0 else -1))).normalized()
        spos = d * (1.8 * scale)
        C.add_crystal_prism(
            bm, 0.18 * scale, (1.5 + 0.5 * (i % 3)) * scale,
            (spos.x, spos.y, spos.z), i % 2, sides=4,
            rot_deg=tuple(math.degrees(a) for a in d.to_track_quat("Z", "Y").to_euler()),
        )
    obj = C.finalize_mesh(name, bm, mats)
    obj.location = Vector(pos)
    return obj


def build_energy_vortex(
    name: str,
    center: tuple[float, float, float],
    radius: float,
    height: float,
    col_a: tuple[float, float, float],
    col_b: tuple[float, float, float],
) -> bpy.types.Object:
    """Build slender swirling helical energy ribbons & flanking crystals."""
    mats = [
        C.make_material(f"{name}_HelixA", col_a, roughness=0.12, emission=col_a, emission_strength=2.0),
        C.make_material(f"{name}_HelixB", col_b, roughness=0.12, emission=col_b, emission_strength=1.9),
    ]
    bm = bmesh.new()
    cx, cy, cz = center
    for strand in range(2):
        rings: list[tuple[tuple[float, float, float], float, float, tuple[float, float, float]]] = []
        phase = strand * math.pi + 0.35
        for i in range(22):
            t = i / 21.0
            ang = phase + t * math.pi * 2.2
            r_cur = radius * (1.22 - 0.24 * t)
            x, y, z = cx + r_cur * math.cos(ang), cy + r_cur * math.sin(ang), cz + 0.35 + t * height
            rad_tube = 0.065 * math.sin(t * math.pi) + 0.02
            tang = Vector((-math.sin(ang), math.cos(ang), 0.48)).normalized()
            rdeg = tuple(math.degrees(a) for a in tang.to_track_quat("Z", "Y").to_euler())
            rings.append(((x, y, z), rad_tube, rad_tube * 0.55, rdeg))
        C.add_lofted_tube(bm, rings, strand, sides=6, smooth=True)
    for i in range(10):
        ang = math.radians(i * 36.0 + 18.0)
        if math.sin(ang) >= -0.40:
            r_c = radius * (1.35 + 0.16 * (i % 2))
            z_c = cz + 1.1 + (i % 4) * 1.15
            C.add_crystal_prism(bm, 0.20, 0.85, (cx + r_c * math.cos(ang), cy + r_c * math.sin(ang), z_c), i % 2, sides=5, rot_deg=(12, -10, i * 36))
    return C.finalize_mesh(name, bm, mats)


def build_stylized_challenger(
    name: str,
    armor_col: tuple[float, float, float],
    visor_col: tuple[float, float, float],
    scale: float = 1.0,
) -> bpy.types.Object:
    """Build a sculpted low-poly Roblox-proportioned challenger silhouette."""
    mats = [
        C.make_material(f"{name}_Armor", armor_col, roughness=0.52, metallic=0.15),
        C.make_material(f"{name}_Dark", (0.06, 0.07, 0.10), roughness=0.72),
        C.make_material(f"{name}_Visor", visor_col, roughness=0.10, emission=visor_col, emission_strength=2.5),
    ]
    bm = bmesh.new()
    for sx, y_off in ((-0.58, -0.15), (0.58, 0.22)):
        C.add_lofted_tube(bm, [((sx, y_off, 0.0), 0.36, 0.42, (0, 0, 0)), ((sx * 0.92, y_off * 0.5, 1.35), 0.32, 0.34, (0, 0, 0)), ((sx * 0.72, 0.0, 2.35), 0.38, 0.36, (0, 0, 0))], 1, sides=8, smooth=False)
    C.add_lofted_tube(bm, [((0, 0.0, 2.20), 0.72, 0.48, (0, 0, 0)), ((0, -0.08, 3.35), 0.92, 0.58, (8, 0, 0)), ((0, -0.14, 4.05), 0.68, 0.48, (10, 0, 0))], 0, sides=8, smooth=False)
    for sx in (-1, 1):
        C.add_faceted_box(bm, (0.72, 0.72, 0.54), (sx * 1.12, -0.08, 3.72), 0, bevel=0.09, rot_deg=(8, sx * -18, 0))
    C.add_lofted_tube(bm, [((-1.15, -0.10, 3.55), 0.28, 0.28, (0, 0, 0)), ((-1.35, -0.95, 3.25), 0.24, 0.24, (72, 0, 0)), ((-1.05, -1.68, 3.42), 0.26, 0.26, (82, 0, 0))], 1, sides=8, smooth=False)
    C.add_lofted_tube(bm, [((1.15, -0.08, 3.55), 0.28, 0.28, (0, 0, 0)), ((1.48, 0.65, 3.12), 0.24, 0.24, (-55, 0, 0))], 1, sides=8, smooth=False)
    C.add_faceted_box(bm, (1.18, 1.12, 1.16), (0.0, -0.18, 4.72), 0, bevel=0.14, rot_deg=(8, 0, 0))
    C.add_faceted_box(bm, (0.94, 0.28, 0.30), (0.0, -0.68, 4.74), 2, bevel=0.04, rot_deg=(8, 0, 0))
    obj = C.finalize_mesh(name, bm, mats)
    obj.scale = Vector((scale, scale, scale))
    return obj


def add_pedestal_mesh(
    bm: bmesh.types.BMesh,
    center: tuple[float, float, float],
    radius: float,
    height: float,
    mat_stone: int,
    mat_gold: int,
    mat_glow: int,
) -> None:
    """Append a sculpted stepped trophy pedestal onto `bm`."""
    cx, cy, cz = center
    profile = [
        (radius * 1.18, 0.0), (radius * 1.18, height * 0.22), (radius * 0.96, height * 0.34),
        (radius * 0.90, height * 0.78), (radius * 1.06, height * 0.90), (radius * 1.02, height), (0.05, height),
    ]
    C.add_lathe_shell(bm, profile, mat_stone, segments=12, center=(cx, cy, cz), smooth=False)
    b0 = set(bm.verts)
    C.add_closed_ring(bm, radius * 1.05, 0.12, 0.14, mat_gold, (0, 0, 0), 16)
    bmesh.ops.translate(bm, vec=(cx, cy, cz + height * 0.92), verts=[v for v in bm.verts if v not in b0])
    b1 = set(bm.verts)
    C.add_closed_ring(bm, radius * 0.92, 0.10, 0.08, mat_glow, (0, 0, 0), 16)
    bmesh.ops.translate(bm, vec=(cx, cy, cz + height * 0.56), verts=[v for v in bm.verts if v not in b1])


def add_cash_pad_and_loot(
    bm: bmesh.types.BMesh,
    center: tuple[float, float, float],
    mat_pad: int,
    mat_gold: int,
    mat_gem_em: int,
    mat_gem_mag: int,
    seed: int,
) -> None:
    """Append a rich emerald/gold Cash Pad with floating 3D gold coins & Boss Gems."""
    cx, cy, cz = center
    C.add_lathe_shell(bm, [(1.55, 0.0), (1.62, 0.10), (1.35, 0.14), (0.05, 0.14)], mat_pad, segments=12, center=(cx, cy, cz), smooth=False)
    b0 = set(bm.verts)
    C.add_closed_ring(bm, 1.56, 0.18, 0.16, mat_gold, (0, 0, 0), 18)
    bmesh.ops.translate(bm, vec=(cx, cy, cz + 0.09), verts=[v for v in bm.verts if v not in b0])
    b_in = set(bm.verts)
    C.add_closed_ring(bm, 1.05, 0.08, 0.06, mat_gem_em, (0, 0, 0), 16)
    bmesh.ops.translate(bm, vec=(cx, cy, cz + 0.15), verts=[v for v in bm.verts if v not in b_in])
    for i in range(6):
        t = i / 5.0
        ang = seed * 1.3 + i * 1.25
        r_off = 0.22 + 0.48 * math.sin(ang)
        px, py, pz = cx + r_off * math.cos(ang), cy + r_off * math.sin(ang), cz + 0.34 + t * 1.95
        if i % 3 == 2:
            C.add_crystal_prism(bm, 0.21, 0.58, (px, py, pz), mat_gem_em if i % 2 == 0 else mat_gem_mag, sides=6, rot_deg=(12, -15, i * 40))
        else:
            add_coin_mesh(bm, (px, py, pz), mat_gold, radius=0.34, half_thick=0.07, rot_deg=(74, i * 35, math.degrees(ang)))


def add_coin_mesh(
    bm: bmesh.types.BMesh,
    center: tuple[float, float, float],
    mat_gold: int,
    radius: float = 0.5,
    half_thick: float = 0.11,
    rot_deg: tuple[float, float, float] = (90.0, 0.0, 0.0),
) -> None:
    """Append a faceted 3D gold coin disc onto `bm`."""
    before = set(bm.verts)
    C.add_lathe_shell(bm, [(radius * 0.92, -half_thick), (radius, 0.0), (radius * 0.92, half_thick), (0.02, half_thick)], mat_gold, segments=12, smooth=False)
    rot = Euler(tuple(math.radians(a) for a in rot_deg), "XYZ").to_matrix().to_4x4()
    cverts = [v for v in bm.verts if v not in before]
    bmesh.ops.transform(bm, matrix=rot, verts=cverts)
    bmesh.ops.translate(bm, vec=center, verts=cverts)


def _add_hub_scenery(bm: bmesh.types.BMesh, mat_turf: int, mat_stone: int, mat_cloud: int) -> None:
    """Append stylized courtyard hedges, floating islands & clouds."""
    for hx, hy, sc in [(-11.4, -7.0, 1.2), (-11.4, -2.0, 1.0), (11.4, -7.0, 1.2), (11.4, -2.0, 1.0)]:
        C.add_faceted_icosphere(bm, 1.15 * sc, (hx, hy, 0.55 * sc), mat_turf, subdivisions=1, scale=(1.1, 1.2, 0.8), noise_amp=0.12, seed=int(abs(hx + hy)))
    for ix, iy, iz, sc in [(-14, 24, 9.2, 1.1), (15, 25, 9.6, 1.2), (-5, 31, 12.2, 0.9), (6, 32, 12.6, 0.95)]:
        C.add_faceted_icosphere(bm, 2.0 * sc, (ix, iy, iz), mat_cloud, subdivisions=1, scale=(1.8, 1.0, 0.72))
        C.add_faceted_icosphere(bm, 1.4 * sc, (ix + 1.7 * sc, iy, iz - 0.25), mat_cloud, subdivisions=1, scale=(1.5, 0.9, 0.62))
    for fx, fy, fz in [(-19, 22, 4.8), (20, 24, 5.4)]:
        C.add_faceted_box(bm, (5.2, 4.0, 1.2), (fx, fy, fz), mat_turf, bevel=0.14, taper_top=(1.15, 1.15))
        C.add_faceted_box(bm, (4.0, 3.0, 2.2), (fx, fy, fz - 1.4), mat_stone, bevel=0.10, taper_top=(1.4, 1.4))


def build_hub_base_empire(royal_marble: bool = False) -> tuple[bpy.types.Object, list[tuple[float, float, float]]]:
    """Build the 2-tier Hub Base Empire showcase + 6 pedestals + Cash Pads."""
    stone_light = (0.96, 0.95, 0.92) if royal_marble else (0.50, 0.54, 0.60)
    stone_mid = (0.92, 0.90, 0.86) if royal_marble else (0.24, 0.30, 0.39)
    rough = 0.26 if royal_marble else 0.70
    mats = [
        C.make_material("HubStoneLight", stone_light, roughness=rough),
        C.make_material("HubStoneMid", stone_mid, roughness=rough),
        C.make_material("HubTurfEmerald", (0.06, 0.44, 0.14), roughness=0.74),
        C.make_material("HubGold", (0.98, 0.76, 0.16), roughness=0.18, metallic=0.94),
        C.make_material("HubCashPadGlow", (0.01, 0.36, 0.10), roughness=0.22, emission=(0.02, 0.76, 0.22), emission_strength=0.95),
        C.make_material("HubPedestalCyan", (0.98, 0.78, 0.14) if royal_marble else (0.06, 0.72, 0.96), roughness=0.16, emission=(0.98, 0.78, 0.14) if royal_marble else (0.06, 0.72, 0.96), emission_strength=1.2),
        C.make_material("HubGemEmerald", (0.04, 0.88, 0.34), roughness=0.12, emission=(0.04, 0.88, 0.34), emission_strength=1.25),
        C.make_material("HubGemMagenta", (0.78, 0.12, 0.96), roughness=0.12, emission=(0.78, 0.12, 0.96), emission_strength=1.25),
        C.make_material("HubCloudWhite", (0.94, 0.96, 1.0), roughness=0.84),
    ]
    bm = bmesh.new()
    C.add_faceted_box(bm, (38.0, 32.0, 1.4), (0.0, 0.0, -0.70), 2, bevel=0.15)
    C.add_faceted_box(bm, (22.5, 20.0, 0.40), (0.0, -2.2, 0.0), 0, bevel=0.10)
    C.add_faceted_box(bm, (20.0, 9.0, 2.8), (0.0, 5.8, 1.4), 1, bevel=0.14)
    C.add_faceted_box(bm, (20.3, 9.3, 0.26), (0.0, 5.8, 2.8), 3, bevel=0.06)
    for step in range(4):
        C.add_faceted_box(bm, (4.8, 1.05, 0.68), (0.0, -0.3 + step * 0.78, 0.35 + step * 0.66), 0, bevel=0.05)
    for sx in (-9.2, 9.2):
        C.add_faceted_box(bm, (1.8, 1.8, 9.8), (sx, 9.0, 4.9), 1, bevel=0.14, taper_top=(0.82, 0.82))
        C.add_crystal_prism(bm, 0.9, 2.2, (sx, 9.0, 11.1), 5, sides=6)
    pedestals = [((-5.8, -3.5, 0.20), 1.85, 0.78), ((0.0, -4.2, 0.20), 1.95, 0.68), ((5.8, -3.5, 0.20), 1.85, 0.78), ((-5.8, 5.0, 2.92), 2.15, 0.98), ((0.0, 5.6, 2.92), 2.50, 1.35), ((5.8, 5.0, 2.92), 2.15, 0.98)]
    pet_tops: list[tuple[float, float, float]] = []
    for pos, r, h in pedestals:
        add_pedestal_mesh(bm, pos, r, h, 1, 3, 5)
        pet_tops.append((pos[0], pos[1], pos[2] + h))
    for idx, cpos in enumerate([(-5.8, -7.2, 0.20), (0.0, -8.0, 0.20), (5.8, -7.2, 0.20), (-4.5, 0.0, 0.20), (4.5, 0.0, 0.20)]):
        add_cash_pad_and_loot(bm, cpos, 4, 3, 6, 7, seed=idx + 1)
    _add_hub_scenery(bm, 2, 1, 8)
    return C.finalize_mesh("HubBaseEmpire", bm, mats), pet_tops
