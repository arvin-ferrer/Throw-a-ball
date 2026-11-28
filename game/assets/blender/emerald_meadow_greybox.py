"""Headless Blender 5.3 Gate 2 Greybox Blockout for Emerald Meadow 10x.

Run via:
    python scripts/blender_run.py game/assets/blender/emerald_meadow_greybox.py

Outputs:
- game/assets/blender/emerald_meadow_greybox.blend
- game/assets/renders/EmeraldMeadow_Greybox_TopDown.png
- game/assets/renders/EmeraldMeadow_Greybox_Isometric.png
- game/assets/renders/EmeraldMeadow_Greybox_AvatarScale.png
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

THIS_DIR = Path(__file__).resolve().parent
if str(THIS_DIR) not in sys.path:
    sys.path.insert(0, str(THIS_DIR))

import _common as common
import emerald_meadow_layout as eml

RENDER_DIR = common.RENDER_DIR
BLEND_OUT = THIS_DIR / "emerald_meadow_greybox.blend"


def to_blender_xy(lx: float, lz: float) -> tuple[float, float]:
    """Map Roblox local (lx, lz) -> Blender (x, y) so North (-Z) is +Y (up) and East (+X) is +X."""
    return (lx, -lz)


def set_bsdf_color(mat: bpy.types.Material, rgba: tuple[float, float, float, float], roughness: float = 0.65, emission: float = 0.0) -> None:
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Roughness"].default_value = roughness
    if emission > 0.0:
        em = bsdf.inputs.get("Emission Color") or bsdf.inputs.get("Emission")
        if em:
            em.default_value = rgba
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = emission


def create_materials() -> dict[str, bpy.types.Material]:
    specs = {
        "grass": ((0.18, 0.50, 0.20, 1.0), 0.85, 0.0),
        "cliff": ((0.22, 0.25, 0.23, 1.0), 0.88, 0.0),
        "river_bank": ((0.54, 0.45, 0.30, 1.0), 0.85, 0.0),
        "water": ((0.09, 0.54, 0.72, 1.0), 0.14, 0.15),
        "road": ((0.52, 0.44, 0.31, 1.0), 0.86, 0.0),
        "stone_bridge": ((0.55, 0.56, 0.52, 1.0), 0.75, 0.0),
        "wood_bridge": ((0.40, 0.24, 0.12, 1.0), 0.72, 0.0),
        "cottage_wall": ((0.82, 0.76, 0.64, 1.0), 0.78, 0.0),
        "cottage_roof": ((0.14, 0.44, 0.28, 1.0), 0.65, 0.0),
        "tower_stone": ((0.38, 0.41, 0.40, 1.0), 0.78, 0.0),
        "tower_roof": ((0.68, 0.22, 0.18, 1.0), 0.60, 0.0),
        "ruin_stone": ((0.46, 0.50, 0.47, 1.0), 0.82, 0.0),
        "bark": ((0.28, 0.17, 0.10, 1.0), 0.86, 0.0),
        "birch_bark": ((0.80, 0.78, 0.72, 1.0), 0.80, 0.0),
        "oak_leaf": ((0.14, 0.46, 0.18, 1.0), 0.72, 0.0),
        "pine_leaf": ((0.07, 0.27, 0.14, 1.0), 0.76, 0.0),
        "birch_leaf": ((0.36, 0.68, 0.22, 1.0), 0.68, 0.0),
        "elder_leaf": ((0.08, 0.72, 0.36, 1.0), 0.55, 0.35),
        "emerald_glow": ((0.10, 0.90, 0.45, 1.0), 0.18, 2.0),
        "portal_glow": ((0.18, 0.68, 0.98, 1.0), 0.18, 2.2),
        "spawner_slime": ((0.18, 0.88, 0.40, 1.0), 0.30, 1.4),
        "spawner_boar": ((0.96, 0.66, 0.12, 1.0), 0.30, 1.4),
        "avatar_ref": ((0.95, 0.12, 0.62, 1.0), 0.32, 0.45),
        "doorway_void": ((0.05, 0.06, 0.08, 1.0), 0.95, 0.0),
    }
    mats: dict[str, bpy.types.Material] = {}
    for name, (rgba, rough, em) in specs.items():
        mat = bpy.data.materials.new(name=f"GB_{name}")
        set_bsdf_color(mat, rgba, rough, em)
        mats[name] = mat
    return mats


def add_box(bm: bmesh.types.BMesh, center: tuple[float, float, float], size: tuple[float, float, float], yaw_deg: float, mat_idx: int) -> None:
    ret = bmesh.ops.create_cube(bm, size=1.0)
    verts = ret["verts"]
    sx, sy, sz = size
    for v in verts:
        v.co.x *= sx
        v.co.y *= sy
        v.co.z *= sz
    rot = Euler((0.0, 0.0, math.radians(yaw_deg)), "XYZ").to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector(center)) @ rot, verts=verts)
    for f in {f for v in verts for f in v.link_faces}:
        f.material_index = mat_idx
        f.smooth = False


def add_cylinder(bm: bmesh.types.BMesh, center: tuple[float, float, float], r1: float, r2: float, depth: float, segs: int, mat_idx: int) -> None:
    ret = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r1, radius2=r2, depth=depth)
    verts = ret["verts"]
    bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector(center)), verts=verts)
    for f in {f for v in verts for f in v.link_faces}:
        f.material_index = mat_idx
        f.smooth = False


def add_ribbon(bm: bmesh.types.BMesh, pts_xy: list[tuple[float, float]], half_w: float, z_top: float, thickness: float, mat_idx: int) -> None:
    """Build a continuous non-overlapping quad-strip ribbon along a 2D polyline (zero z-fighting)."""
    n = len(pts_xy)
    if n < 2:
        return
    left_v: list[bmesh.types.BMVert] = []
    right_v: list[bmesh.types.BMVert] = []
    for i in range(n):
        x, y = pts_xy[i]
        if i == 0:
            tx, ty = pts_xy[1][0] - x, pts_xy[1][1] - y
        elif i == n - 1:
            tx, ty = x - pts_xy[n - 2][0], y - pts_xy[n - 2][1]
        else:
            tx, ty = pts_xy[i + 1][0] - pts_xy[i - 1][0], pts_xy[i + 1][1] - pts_xy[i - 1][1]
        mag = math.hypot(tx, ty) or 1.0
        nx, ny = -ty / mag, tx / mag
        left_v.append(bm.verts.new(Vector((x + nx * half_w, y + ny * half_w, z_top))))
        right_v.append(bm.verts.new(Vector((x - nx * half_w, y - ny * half_w, z_top))))
    for i in range(n - 1):
        f = bm.faces.new((left_v[i], right_v[i], right_v[i + 1], left_v[i + 1]))
        f.material_index = mat_idx
        f.smooth = False


def add_avatar_dummy(bm: bmesh.types.BMesh, bx: float, by: float, bz: float, mat_idx: int) -> None:
    """Add a 5.5-stud-tall Roblox R15 reference dummy (feet at bz)."""
    add_box(bm, (bx - 0.5, by, bz + 1.0), (0.85, 0.85, 2.0), 0.0, mat_idx)  # Left leg
    add_box(bm, (bx + 0.5, by, bz + 1.0), (0.85, 0.85, 2.0), 0.0, mat_idx)  # Right leg
    add_box(bm, (bx, by, bz + 3.05), (2.0, 1.0, 2.1), 0.0, mat_idx)         # Torso
    add_box(bm, (bx - 1.45, by, bz + 3.05), (0.8, 0.85, 2.0), 0.0, mat_idx) # Left arm
    add_box(bm, (bx + 1.45, by, bz + 3.05), (0.8, 0.85, 2.0), 0.0, mat_idx) # Right arm
    add_box(bm, (bx, by, bz + 4.8), (1.35, 1.35, 1.4), 0.0, mat_idx)        # Head (top = bz + 5.5)


def build_greybox_scene() -> None:
    common.clear_scene()
    data = eml.build_layout()
    mats = create_materials()
    mat_names = list(mats.keys())
    mat_idx = {name: i for i, name in enumerate(mat_names)}
    mat_list = [mats[name] for name in mat_names]

    # 1. Ground basin + perimeter cliffs
    bm_ground = bmesh.new()
    poly_xy = [to_blender_xy(x, z) for x, z in eml.valley_polygon(96)]
    top_verts = [bm_ground.verts.new(Vector((x, y, 0.0))) for x, y in poly_xy]
    bot_verts = [bm_ground.verts.new(Vector((x, y, -8.0))) for x, y in poly_xy]
    f_top = bm_ground.faces.new(top_verts)
    f_top.material_index = mat_idx["grass"]
    f_bot = bm_ground.faces.new(list(reversed(bot_verts)))
    f_bot.material_index = mat_idx["cliff"]
    for i in range(len(poly_xy)):
        inext = (i + 1) % len(poly_xy)
        f = bm_ground.faces.new((bot_verts[i], bot_verts[inext], top_verts[inext], top_verts[i]))
        f.material_index = mat_idx["cliff"]

    # Outer cliff blocks around valley rim
    cliff_segs = 44
    for i in range(cliff_segs):
        ang = 2.0 * math.pi * i / cliff_segs
        lx, lz = eml.valley_boundary_radius(ang)
        bx, by = to_blender_xy(lx, lz)
        mag = math.hypot(bx, by)
        ox, oy = bx * (mag + 34.0) / mag, by * (mag + 34.0) / mag
        yaw = math.degrees(math.atan2(oy, ox)) + 90.0
        h = 54.0 + 18.0 * math.sin(i * 1.7)
        add_box(bm_ground, (ox, oy, h * 0.5 - 4.0), (145.0, 52.0, h), yaw, mat_idx["cliff"])
    common.finalize_mesh("GB_TerrainAndCliffs", bm_ground, mat_list)

    # 2. River & roads
    bm_water = bmesh.new()
    river_xy = [to_blender_xy(x, z) for x, z in data["river_pts"]]
    add_ribbon(bm_water, river_xy, eml.RIVER_HALF_WIDTH + 9.0, 0.08, 0.4, mat_idx["river_bank"])
    add_ribbon(bm_water, river_xy, eml.RIVER_HALF_WIDTH, 0.25, 0.45, mat_idx["water"])
    for road in data["roads"]:
        road_xy = [to_blender_xy(x, z) for x, z in road]
        add_ribbon(bm_water, road_xy, 9.5, 0.16, 0.24, mat_idx["road"])
    common.finalize_mesh("GB_RiverAndRoads", bm_water, mat_list)

    # 3. Bridges, architecture, ruins, arrival pad, return portal
    bm_arch = bmesh.new()
    for br in data["bridges"]:
        bx, by = to_blender_xy(br.lx, br.lz)
        # yaw in Blender around Z for local Roblox yaw_deg
        byaw = br.yaw_deg
        m_deck = mat_idx["stone_bridge"] if br.kind == "StoneBridge" else mat_idx["wood_bridge"]
        add_box(bm_arch, (bx, by, br.crown_y), (br.width, br.length, 2.2), byaw, m_deck)
        # Parapets
        rad = math.radians(byaw)
        ca, sa = math.cos(rad), math.sin(rad)
        for side in (-1.0, 1.0):
            px = bx + side * (br.width * 0.5 - 0.9) * ca
            py = by + side * (br.width * 0.5 - 0.9) * sa
            add_box(bm_arch, (px, py, br.crown_y + 2.3), (1.6, br.length, 2.6), byaw, m_deck)

    for b in data["buildings"]:
        bx, by = to_blender_xy(b.lx, b.lz)
        byaw = b.yaw_deg
        if b.kind in ("CottageA", "Watermill"):
            add_box(bm_arch, (bx, by, 5.5), (b.footprint_w, b.footprint_d, 11.0), byaw, mat_idx["cottage_wall"])
            # Pitched roof block
            add_box(bm_arch, (bx, by, 13.5), (b.footprint_w + 3.0, b.footprint_d + 3.0, 5.5), byaw, mat_idx["cottage_roof"])
            # Avatar-scaled 6x9 doorway marker on front face
            rad = math.radians(byaw)
            dx = -math.sin(rad) * (b.footprint_d * 0.5 + 0.1)
            dy = -math.cos(rad) * (b.footprint_d * 0.5 + 0.1)
            add_box(bm_arch, (bx + dx, by + dy, 4.5), (6.0, 0.8, 9.0), byaw, mat_idx["doorway_void"])
            if b.kind == "Watermill":
                ret_w = bmesh.ops.create_cone(bm_arch, cap_ends=True, cap_tris=False, segments=14, radius1=6.5, radius2=6.5, depth=2.4)
                w_verts = ret_w["verts"]
                rot_w = Euler((math.radians(90.0), 0.0, math.radians(byaw)), "XYZ").to_matrix().to_4x4()
                wx = bx + math.cos(rad) * (b.footprint_w * 0.5 + 1.4)
                wy = by + math.sin(rad) * (b.footprint_w * 0.5 + 1.4)
                bmesh.ops.transform(bm_arch, matrix=Matrix.Translation(Vector((wx, wy, 6.8))) @ rot_w, verts=w_verts)
                for f in {f for v in w_verts for f in v.link_faces}:
                    f.material_index = mat_idx["wood_bridge"]
                    f.smooth = False
        elif b.kind == "Watchtower":
            add_box(bm_arch, (bx, by, 16.0), (14.0, 14.0, 32.0), byaw, mat_idx["tower_stone"])
            add_box(bm_arch, (bx, by, 33.5), (18.5, 18.5, 3.0), byaw, mat_idx["wood_bridge"])
            add_cylinder(bm_arch, (bx, by, 39.5), 11.5, 0.8, 10.0, 4, mat_idx["tower_roof"])
            add_box(bm_arch, (bx, by - 7.1, 4.5), (6.0, 0.9, 9.0), byaw, mat_idx["doorway_void"])
        elif b.kind == "RuinArch":
            rad = math.radians(byaw)
            ca, sa = math.cos(rad), math.sin(rad)
            for s in (-8.5, 8.5):
                add_box(bm_arch, (bx + s * ca, by + s * sa, 8.0), (4.5, 4.5, 16.0), byaw, mat_idx["ruin_stone"])
            add_box(bm_arch, (bx, by, 17.5), (22.0, 5.5, 3.5), byaw, mat_idx["ruin_stone"])
            add_box(bm_arch, (bx, by, 17.5), (3.5, 6.0, 2.2), byaw, mat_idx["emerald_glow"])
        elif b.kind == "RuinPillar":
            add_box(bm_arch, (bx, by, b.height * 0.5), (5.5, 5.5, b.height), byaw, mat_idx["ruin_stone"])
        elif b.kind == "ReturnPortal":
            add_box(bm_arch, (bx - 9.0, by, 10.0), (4.0, 5.0, 20.0), 0.0, mat_idx["ruin_stone"])
            add_box(bm_arch, (bx + 9.0, by, 10.0), (4.0, 5.0, 20.0), 0.0, mat_idx["ruin_stone"])
            add_box(bm_arch, (bx, by, 21.0), (24.0, 6.0, 4.0), 0.0, mat_idx["ruin_stone"])
            add_box(bm_arch, (bx, by, 10.0), (14.0, 1.4, 18.0), 0.0, mat_idx["portal_glow"])
        elif b.kind == "Shrine":
            add_box(bm_arch, (bx, by, 2.0), (34.0, 24.0, 4.0), byaw, mat_idx["ruin_stone"])
            add_box(bm_arch, (bx, by, 13.0), (7.0, 7.0, 20.0), byaw, mat_idx["tower_stone"])
            add_cylinder(bm_arch, (bx, by, 25.0), 3.8, 0.5, 6.0, 6, mat_idx["emerald_glow"])

    # Arrival Pad
    apx, apy = to_blender_xy(*eml.ARRIVAL_PAD_LOCAL)
    add_cylinder(bm_arch, (apx, apy, 0.4), 11.0, 11.0, 0.8, 20, mat_idx["emerald_glow"])
    common.finalize_mesh("GB_ArchitectureAndLandmarks", bm_arch, mat_list)

    # 4. Multi-Species Trees (~186 trees)
    bm_trees = bmesh.new()
    for tr in data["trees"]:
        bx, by = to_blender_xy(tr.lx, tr.lz)
        s = tr.scale
        if tr.species == "Oak":
            add_cylinder(bm_trees, (bx, by, 6.0 * s), 2.0 * s, 1.4 * s, 12.0 * s, 7, mat_idx["bark"])
            add_cylinder(bm_trees, (bx, by, 16.5 * s), 10.5 * s, 7.2 * s, 9.0 * s, 8, mat_idx["oak_leaf"])
            add_cylinder(bm_trees, (bx, by, 22.5 * s), 7.2 * s, 3.0 * s, 5.5 * s, 7, mat_idx["oak_leaf"])
        elif tr.species == "Pine":
            add_cylinder(bm_trees, (bx, by, 5.5 * s), 1.6 * s, 1.1 * s, 11.0 * s, 6, mat_idx["bark"])
            add_cylinder(bm_trees, (bx, by, 13.0 * s), 9.0 * s, 2.2 * s, 10.0 * s, 7, mat_idx["pine_leaf"])
            add_cylinder(bm_trees, (bx, by, 20.5 * s), 7.0 * s, 1.5 * s, 9.5 * s, 7, mat_idx["pine_leaf"])
            add_cylinder(bm_trees, (bx, by, 27.5 * s), 4.8 * s, 0.4 * s, 8.5 * s, 7, mat_idx["pine_leaf"])
        elif tr.species == "Birch":
            add_cylinder(bm_trees, (bx, by, 6.0 * s), 1.2 * s, 0.8 * s, 12.0 * s, 6, mat_idx["birch_bark"])
            add_cylinder(bm_trees, (bx, by, 15.0 * s), 7.5 * s, 4.5 * s, 9.0 * s, 7, mat_idx["birch_leaf"])
        else:  # ElderOak
            add_cylinder(bm_trees, (bx, by, 8.5 * s), 4.6 * s, 3.0 * s, 17.0 * s, 8, mat_idx["bark"])
            add_cylinder(bm_trees, (bx, by, 23.0 * s), 17.5 * s, 12.0 * s, 12.5 * s, 9, mat_idx["elder_leaf"])
            add_cylinder(bm_trees, (bx, by, 32.0 * s), 11.5 * s, 5.0 * s, 8.0 * s, 8, mat_idx["elder_leaf"])
    common.finalize_mesh("GB_ForestTrees", bm_trees, mat_list)

    # 5. Spawners + 5.5-stud Avatar Scale Reference Dummies
    bm_markers = bmesh.new()
    for sp in data["spawners"]:
        bx, by = to_blender_xy(sp.lx, sp.lz)
        m = mat_idx["spawner_slime"] if sp.mob_type == "MossSlime" else mat_idx["spawner_boar"]
        add_cylinder(bm_markers, (bx, by, 0.55), 7.5, 7.5, 0.9, 14, m)

    # Place 5.5-stud Roblox avatar dummies right next to Watermill doorway, Bridge #1 deck, and East Watchtower!
    b1 = data["bridges"][0]
    b1x, b1y = to_blender_xy(b1.lx, b1.lz)
    add_avatar_dummy(bm_markers, b1x, b1y, b1.crown_y + 1.1, mat_idx["avatar_ref"])            # Standing on Bridge #1 deck
    add_avatar_dummy(bm_markers, -478.0, 152.0, 0.0, mat_idx["avatar_ref"])                    # Standing right in front of Watermill doorway
    add_avatar_dummy(bm_markers, -445.0, 398.0, 0.0, mat_idx["avatar_ref"])                    # Standing outside Cottage_W2 door
    add_avatar_dummy(bm_markers, 515.0, 242.0, 0.0, mat_idx["avatar_ref"])                     # Standing outside Watchtower_E1 door
    common.finalize_mesh("GB_SpawnersAndAvatars", bm_markers, mat_list)

    # Lighting + daylight sky
    world = bpy.data.worlds.new("MeadowDayWorld")
    bpy.context.scene.world = world
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = (0.48, 0.68, 0.92, 1.0)
    bg.inputs[1].default_value = 0.85

    sun_data = bpy.data.lights.new("SunKey", type="SUN")
    sun_data.energy = 3.2
    sun_data.angle = math.radians(2.5)
    sun_obj = bpy.data.objects.new("SunKey", sun_data)
    sun_obj.rotation_euler = Euler((math.radians(48), math.radians(15), math.radians(-38)), "XYZ")
    bpy.context.collection.objects.link(sun_obj)


def setup_render_engine(samples: int = 16, res_x: int = 1440, res_y: int = 960) -> None:
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = False
    scene.cycles.max_bounces = 4
    scene.render.resolution_x = res_x
    scene.render.resolution_y = res_y
    scene.render.image_settings.file_format = "PNG"


def render_camera(name: str, loc: tuple[float, float, float], target: tuple[float, float, float], out_png: Path, ortho_scale: float | None = None, lens: float = 35.0) -> None:
    cam_data = bpy.data.cameras.new(name)
    cam_data.clip_start = 1.0
    cam_data.clip_end = 8000.0
    if ortho_scale is not None:
        cam_data.type = "ORTHO"
        cam_data.ortho_scale = ortho_scale
    else:
        cam_data.type = "PERSP"
        cam_data.lens = lens
    cam_obj = bpy.data.objects.new(name, cam_data)
    cam_obj.location = Vector(loc)
    direction = Vector(target) - Vector(loc)
    cam_obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.collection.objects.link(cam_obj)

    scene = bpy.context.scene
    scene.camera = cam_obj
    scene.render.filepath = str(out_png)
    bpy.ops.render.render(write_still=True)
    print(f"Rendered: {out_png}")


def main() -> None:
    build_greybox_scene()
    RENDER_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUT))
    print(f"Saved greybox .blend: {BLEND_OUT}")

    setup_render_engine(samples=16, res_x=1280, res_y=960)
    render_camera(
        "Cam_TopDown",
        (0.0, 0.0, 2200.0),
        (0.0, 0.0, 0.0),
        RENDER_DIR / "EmeraldMeadow_Greybox_TopDown.png",
        ortho_scale=2050.0,
    )
    setup_render_engine(samples=16, res_x=1440, res_y=860)
    render_camera(
        "Cam_Isometric",
        (-1150.0, -1250.0, 860.0),
        (40.0, -20.0, 0.0),
        RENDER_DIR / "EmeraldMeadow_Greybox_Isometric.png",
        lens=34.0,
    )
    # Close-up Avatar Scale QA: Whispering Mill + Stone Bridge #1 + 5.5-stud magenta dummies!
    render_camera(
        "Cam_AvatarScale",
        (-345.0, 125.0, 34.0),
        (-465.0, 205.0, 8.0),
        RENDER_DIR / "EmeraldMeadow_Greybox_AvatarScale.png",
        lens=36.0,
    )


if __name__ == "__main__":
    main()
