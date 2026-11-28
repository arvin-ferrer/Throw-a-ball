"""Gate 2 Blender 5.x Rough Low-Poly Blockouts & Scale QA for Emerald Meadow Mobs.

Generates stylized low-poly silhouette blockouts for all 10 Emerald Meadow mob variants
(5 Base Archetypes + 5 Natural Area Elites), plus exact scale/sightline gauges:
  - Standard 5.5-stud Roblox R15 Avatar reference
  - 6W x 9H Cottage/Watchtower Doorway Frame
  - Live-verified Watchtower Balcony Cross-Section (2.3-stud parapet, 6.5-stud roof eave)

Run via:
    python scripts/blender_run.py game/assets/blender/emerald_meadow_mobs_blockout.py

Outputs:
  - game/assets/blender/emerald_meadow_mobs_blockout.blend
  - game/assets/renders/EmeraldMeadow_Mobs_Blockout_Lineup.png
  - game/assets/renders/EmeraldMeadow_Mobs_Blockout_Creatures.png
  - game/assets/renders/EmeraldMeadow_Mobs_Blockout_CastersRuins_Perch.png
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

import _common as C  # noqa: E402

BLEND_OUT = THIS_DIR / "emerald_meadow_mobs_blockout.blend"


def srgb_to_lin(rgb: tuple[int, int, int]) -> tuple[float, float, float]:
    out = []
    for c in rgb:
        v = c / 255.0
        out.append(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4)
    return (out[0], out[1], out[2])


def build_palette() -> tuple[list[bpy.types.Material], dict[str, int]]:
    """Unified Emerald Meadow mob palette aligned with STYLE_GUIDE.md & emerald_meadow_kit.py."""
    specs: list[tuple[str, tuple[int, int, int], float, float, float]] = [
        # (name, sRGB, roughness, metallic, emission_strength)
        ("SlimeGreen", (64, 198, 92), 0.28, 0.0, 0.0),
        ("SlimeDeep", (32, 138, 68), 0.24, 0.0, 0.0),
        ("MossLeaf", (54, 152, 68), 0.72, 0.0, 0.0),
        ("MossBright", (96, 214, 98), 0.62, 0.0, 0.0),
        ("JadeGlow", (34, 238, 128), 0.14, 0.0, 2.3),
        ("GoldMetal", (240, 194, 58), 0.26, 0.88, 0.0),
        ("LotusPetal", (246, 214, 96), 0.42, 0.0, 0.3),
        ("SnapperTeal", (46, 136, 128), 0.48, 0.0, 0.0),
        ("SnapperDeep", (28, 88, 92), 0.56, 0.0, 0.0),
        ("SnapperBelly", (218, 214, 182), 0.66, 0.0, 0.0),
        ("AquaGlow", (56, 224, 248), 0.16, 0.0, 2.2),
        ("BoarHide", (106, 70, 48), 0.78, 0.0, 0.0),
        ("BoarDark", (68, 44, 32), 0.84, 0.0, 0.0),
        ("Ivory", (236, 228, 206), 0.42, 0.0, 0.0),
        ("AmberGlow", (255, 190, 48), 0.16, 0.0, 2.1),
        ("WitchCloak", (44, 78, 62), 0.76, 0.0, 0.0),
        ("WitchPlum", (86, 46, 98), 0.68, 0.0, 0.0),
        ("WitchCrimson", (174, 46, 52), 0.58, 0.0, 0.0),
        ("WitchSkin", (196, 216, 192), 0.58, 0.0, 0.0),
        ("StaffWood", (92, 58, 36), 0.80, 0.0, 0.0),
        ("HexGlow", (198, 72, 255), 0.14, 0.0, 2.5),
        ("StoneBase", (96, 108, 100), 0.84, 0.0, 0.0),
        ("StoneDark", (56, 64, 60), 0.88, 0.0, 0.0),
        ("StoneObsidian", (40, 44, 52), 0.74, 0.0, 0.0),
        ("EyeDark", (18, 20, 24), 0.08, 0.0, 0.0),
        ("EyeWhite", (255, 255, 255), 0.08, 0.0, 0.9),
        ("AvatarRef", (240, 72, 146), 0.38, 0.0, 0.15),
        ("GaugeTimber", (118, 76, 46), 0.76, 0.0, 0.0),
        ("GaugeTimberDk", (76, 48, 30), 0.82, 0.0, 0.0),
        ("GaugeRoof", (184, 58, 50), 0.60, 0.0, 0.0),
    ]
    mats: list[bpy.types.Material] = []
    idx: dict[str, int] = {}
    for i, (name, srgb, rough, metal, em) in enumerate(specs):
        lin = srgb_to_lin(srgb)
        mat = C.make_material(
            f"EMMob_{name}",
            lin,
            roughness=rough,
            metallic=metal,
            emission=lin if em > 0.0 else None,
            emission_strength=em,
        )
        mats.append(mat)
        idx[name] = i
    return mats, idx


def add_cone(
    bm: bmesh.types.BMesh,
    r1: float,
    r2: float,
    depth: float,
    center: tuple[float, float, float],
    mat_idx: int,
    sides: int = 8,
    rot_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
    smooth: bool = False,
) -> None:
    ret = bmesh.ops.create_cone(
        bm, cap_ends=True, cap_tris=False, segments=sides, radius1=r1, radius2=r2, depth=depth
    )
    verts = ret["verts"]
    rot = Euler(tuple(math.radians(a) for a in rot_deg), "XYZ").to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector(center)) @ rot, verts=verts)
    for f in {f for v in verts for f in v.link_faces}:
        f.material_index = mat_idx
        f.smooth = smooth


def ground_and_finalize(
    name: str, bm: bmesh.types.BMesh, mats: list[bpy.types.Material], target_h: float | None = None
) -> bpy.types.Object:
    obj = C.finalize_mesh(name, bm, mats)
    mins, maxs = C.world_bounds([obj])
    cx = (mins.x + maxs.x) * 0.5
    cy = (mins.y + maxs.y) * 0.5
    scale = 1.0
    if target_h is not None and (maxs.z - mins.z) > 1e-4:
        scale = target_h / (maxs.z - mins.z)
    for v in obj.data.vertices:
        v.co.x = (v.co.x - cx) * scale
        v.co.y = (v.co.y - cy) * scale
        v.co.z = (v.co.z - mins.z) * scale
    obj.data.update()
    return obj


# =============================================================================
# 1. MOSS SLIME & ELDER MOSS SLIME
# =============================================================================
def build_moss_slime(mats: list[bpy.types.Material], M: dict[str, int], elite: bool) -> bpy.types.Object:
    bm = bmesh.new()
    body_mat = M["SlimeDeep"] if elite else M["SlimeGreen"]
    profile = [
        (0.05, 0.00),
        (1.42, 0.06),
        (1.68, 0.45),
        (1.70, 1.05),
        (1.48, 1.72),
        (1.06, 2.24),
        (0.54, 2.52),
        (0.06, 2.60),
    ]
    C.add_lathe_shell(bm, profile, body_mat, segments=14, scale_xy=(1.04, 1.0), smooth=True)
    # 4 stubby moss feet
    for sx in (-1.05, 1.05):
        for sy in (-1.05, 0.95):
            C.add_faceted_icosphere(bm, 0.42, (sx, sy, 0.25), M["MossLeaf"], subdivisions=1, scale=(1.2, 1.2, 0.65))
    # Glossy eyes facing -Y
    for sx in (-0.64, 0.64):
        C.add_expressive_eye(bm, (sx, -1.52, 1.18), 0.34, M["EyeDark"], M["EyeWhite"])
    # Crown foliage
    for i in range(5 if elite else 4):
        ang = i * (360.0 / (5 if elite else 4)) + 18.0
        rad = math.radians(ang)
        C.add_faceted_box(
            bm, (0.95, 0.60, 0.28),
            (math.cos(rad) * 0.62, math.sin(rad) * 0.62, 2.50),
            M["MossBright"] if elite else M["MossLeaf"],
            bevel=0.06, rot_deg=(18.0, 0.0, ang), taper_top=(0.75, 0.75),
        )
    if not elite:
        # Cute twin sprout
        add_cone(bm, 0.12, 0.08, 0.65, (0.0, 0.0, 2.85), M["MossLeaf"], sides=6)
        C.add_faceted_box(bm, (0.72, 0.38, 0.14), (-0.36, 0.0, 3.16), M["MossBright"], bevel=0.04, rot_deg=(0, 24, 0))
        C.add_faceted_box(bm, (0.72, 0.38, 0.14), (0.36, 0.0, 3.16), M["MossBright"], bevel=0.04, rot_deg=(0, -24, 0))
    else:
        # Blooming golden lotus crown + glowing jade dew crystal + 3 orbiting moss pebbles
        for i in range(6):
            ang = i * 60.0
            rad = math.radians(ang)
            C.add_faceted_box(
                bm, (0.58, 0.95, 0.18),
                (math.cos(rad) * 0.68, math.sin(rad) * 0.68, 2.74),
                M["LotusPetal"], bevel=0.04, rot_deg=(36.0, 0.0, ang - 90.0), taper_top=(0.55, 0.9),
            )
        C.add_crystal_prism(bm, 0.36, 1.15, (0.0, 0.0, 3.12), M["JadeGlow"], sides=6)
        ring_v = C.add_closed_ring(bm, 0.56, 0.12, 0.16, M["GoldMetal"], segments=12)
        bmesh.ops.translate(bm, verts=ring_v, vec=Vector((0.0, 0.0, 2.62)))
        # Orbiting moss pebbles
        for i in range(3):
            ang = math.radians(i * 120.0 + 30.0)
            C.add_faceted_icosphere(
                bm, 0.34, (math.cos(ang) * 2.10, math.sin(ang) * 2.10, 1.45),
                M["StoneBase"], subdivisions=1, scale=(1.1, 0.95, 0.85),
            )
            C.add_crystal_prism(
                bm, 0.14, 0.42, (math.cos(ang) * 2.10, math.sin(ang) * 2.10, 1.75),
                M["JadeGlow"], sides=5,
            )
    name = "ElderMossSlime" if elite else "MossSlime"
    return ground_and_finalize(name, bm, mats, target_h=4.2 if elite else 3.2)


# =============================================================================
# 2. RIVER SNAPPER & TIDECREST SNAPPER
# =============================================================================
def build_river_snapper(mats: list[bpy.types.Material], M: dict[str, int], elite: bool) -> bpy.types.Object:
    bm = bmesh.new()
    skin = M["SnapperDeep"] if elite else M["SnapperTeal"]
    # Low-slung amphibious torso + tail loft (along Y, facing -Y)
    C.add_lofted_tube(
        bm,
        [
            ((0.0, -2.1, 1.25), 1.05, 0.68, (90, 0, 0)),
            ((0.0, -1.2, 1.42), 1.48, 0.98, (90, 0, 0)),
            ((0.0, 0.1, 1.46), 1.56, 1.08, (90, 0, 0)),
            ((0.0, 1.4, 1.18), 1.12, 0.78, (90, 0, 0)),
            ((0.0, 2.5, 0.82), 0.52, 0.44, (90, 0, 0)),
            ((0.0, 3.2, 0.72), 0.18, 0.24, (90, 0, 0)),
        ],
        skin, sides=8, smooth=False,
    )
    # Cream underbelly
    C.add_faceted_box(bm, (2.1, 2.6, 0.65), (0.0, -0.2, 0.78), M["SnapperBelly"], bevel=0.14)
    # Wide snapping jaw + teeth
    C.add_faceted_box(bm, (2.3, 1.35, 0.62), (0.0, -2.05, 1.52), skin, bevel=0.12, taper_top=(0.82, 0.88))
    C.add_faceted_box(bm, (2.1, 1.25, 0.42), (0.0, -2.00, 0.92), M["SnapperBelly"], bevel=0.08)
    for sx in (-0.75, -0.25, 0.25, 0.75):
        C.add_crystal_prism(bm, 0.11, 0.34, (sx, -2.52, 1.18), M["Ivory"], sides=4, rot_deg=(180, 0, 0))
    # Glowing aqua cheek sacs (ballistic spit glands!)
    sac_r = 0.56 if elite else 0.42
    for sx in (-1.36, 1.36):
        C.add_faceted_icosphere(bm, sac_r, (sx, -1.25, 1.32), M["AquaGlow"], subdivisions=1, scale=(0.85, 1.15, 0.95))
    # Fierce amber eyes
    for sx in (-0.78, 0.78):
        C.add_faceted_icosphere(bm, 0.28, (sx, -1.95, 1.92), M["AmberGlow"], subdivisions=1, scale=(0.95, 0.8, 0.95))
        C.add_faceted_box(bm, (0.58, 0.42, 0.16), (sx, -1.85, 2.18), skin, bevel=0.04, rot_deg=(0, 14 if sx < 0 else -14, 0))
    # 4 splayed amphibious legs (compact enough to clear 6W doorways!)
    for sx in (-1.32, 1.32):
        for sy in (-0.95, 1.05):
            C.add_faceted_box(bm, (0.68, 0.78, 1.18), (sx, sy, 0.62), skin, bevel=0.10, rot_deg=(0, 12 if sx < 0 else -12, 0))
            C.add_faceted_box(bm, (0.86, 1.02, 0.28), (sx * 1.05, sy - 0.14, 0.14), M["SnapperDeep"], bevel=0.05)
    # Dorsal ridge / Elite Aqua Sail-Fin + Slate Armor
    if not elite:
        for idx, sy in enumerate((-1.1, -0.2, 0.7, 1.6)):
            h = 0.85 - idx * 0.10
            C.add_faceted_box(bm, (0.24, 0.62, h), (0.0, sy, 2.42 - idx * 0.16), M["MossBright"], bevel=0.04, taper_top=(0.3, 0.6))
    else:
        # Armored river-slate ridge plates + tall glowing aqua sail-fin + gold jaw horns
        for idx, sy in enumerate((-1.2, -0.3, 0.6, 1.5, 2.3)):
            h = 1.65 - abs(idx - 1.5) * 0.24
            C.add_faceted_box(bm, (0.26, 0.78, h), (0.0, sy, 2.65 - idx * 0.16), M["AquaGlow"], bevel=0.04, taper_top=(0.25, 0.55))
            if idx < 3:
                C.add_faceted_box(bm, (2.1, 0.85, 0.36), (0.0, sy, 2.25 - idx * 0.08), M["StoneDark"], bevel=0.08)
        for sx in (-1.05, 1.05):
            C.add_crystal_prism(bm, 0.22, 0.96, (sx, -1.65, 2.42), M["GoldMetal"], sides=5, rot_deg=(-38, -22 if sx < 0 else 22, 0))
    name = "TidecrestSnapper" if elite else "RiverSnapper"
    return ground_and_finalize(name, bm, mats, target_h=4.0 if elite else 3.1)


# =============================================================================
# 3. BRAMBLE BOAR & THORNBACK ALPHA
# =============================================================================
def build_bramble_boar(mats: list[bpy.types.Material], M: dict[str, int], elite: bool) -> bpy.types.Object:
    bm = bmesh.new()
    hide = M["BoarDark"] if elite else M["BoarHide"]
    # Muscular charging torso loft
    C.add_lofted_tube(
        bm,
        [
            ((0.0, -2.05, 1.72), 0.78, 0.72, (90, 0, 0)),
            ((0.0, -1.20, 1.98), 1.38, 1.25, (90, 0, 0)),
            ((0.0, 0.05, 2.02), 1.48, 1.34, (90, 0, 0)),
            ((0.0, 1.45, 1.88), 1.24, 1.15, (90, 0, 0)),
            ((0.0, 2.25, 1.66), 0.74, 0.70, (90, 0, 0)),
        ],
        hide, sides=8, smooth=False,
    )
    # Snout plate
    C.add_faceted_box(bm, (1.18, 0.55, 0.86), (0.0, -2.35, 1.56), M["BoarHide"], bevel=0.10)
    # Curved tusks
    tusk_s = 1.45 if elite else 1.0
    tusk_mat = M["GoldMetal"] if elite else M["Ivory"]
    for sx in (-1.0, 1.0):
        C.add_lofted_tube(
            bm,
            [
                ((sx * 0.72, -1.95, 1.38), 0.22 * tusk_s, 0.22 * tusk_s, (75, sx * 20, 0)),
                ((sx * 1.18, -2.42, 1.62), 0.16 * tusk_s, 0.16 * tusk_s, (45, sx * 30, 0)),
                ((sx * 1.38, -2.55, 2.38 * (1.12 if elite else 1.0)), 0.05 * tusk_s, 0.05 * tusk_s, (10, sx * 25, 0)),
            ],
            tusk_mat, sides=6, smooth=False,
        )
    # Pointed ears & glowing amber eyes
    for sx in (-0.95, 0.95):
        C.add_crystal_prism(bm, 0.34, 0.92, (sx, -1.35, 2.95), hide, sides=4, rot_deg=(12, -24 if sx < 0 else 24, 0))
        C.add_faceted_box(bm, (0.30, 0.26, 0.24), (sx * 0.88, -1.86, 2.08), M["AmberGlow"], bevel=0.04)
    # 4 sturdy legs + dark hooves
    for sx in (-0.92, 0.92):
        for sy in (-1.05, 1.25):
            C.add_faceted_box(bm, (0.64, 0.72, 1.28), (sx, sy, 0.72), hide, bevel=0.08)
            C.add_faceted_box(bm, (0.72, 0.80, 0.36), (sx, sy - 0.04, 0.18), M["StoneDark"], bevel=0.05)
    # Dorsal mossy bramble armor & thorns
    C.add_faceted_box(bm, (1.85, 2.75, 0.56), (0.0, 0.05, 3.22), M["MossLeaf"], bevel=0.12)
    if not elite:
        for sy, h in ((-0.75, 0.75), (0.15, 0.95), (0.95, 0.70)):
            C.add_crystal_prism(bm, 0.22, h, (0.0, sy, 3.55), M["JadeGlow"] if sy == 0.15 else M["MossBright"], sides=5, rot_deg=(-12, 0, 0))
    else:
        # Heavy stone-bark shoulder mantle + bristling jade crystal spine crest
        C.add_faceted_box(bm, (2.75, 1.75, 1.28), (0.0, -0.65, 2.95), M["StoneBase"], bevel=0.18, taper_top=(0.86, 0.85))
        for sy, h, sx_off in ((-1.10, 1.35, 0.0), (-0.30, 1.55, 0.0), (0.55, 1.25, 0.0), (-0.70, 1.05, -0.88), (-0.70, 1.05, 0.88)):
            C.add_crystal_prism(
                bm, 0.26, h, (sx_off, sy, 3.85 if sx_off == 0 else 3.55),
                M["JadeGlow"], sides=5, rot_deg=(-14, -18 if sx_off < 0 else (18 if sx_off > 0 else 0), 0),
            )
    name = "ThornbackAlpha" if elite else "BrambleBoar"
    return ground_and_finalize(name, bm, mats, target_h=4.8 if elite else 3.8)


# =============================================================================
# 4. MEADOW WITCH & COVEN ARCH-WITCH
# =============================================================================
def build_meadow_witch(mats: list[bpy.types.Material], M: dict[str, int], elite: bool) -> bpy.types.Object:
    bm = bmesh.new()
    cloak_mat = M["WitchPlum"] if elite else M["WitchCloak"]
    hat_mat = M["WitchCrimson"] if elite else M["WitchCloak"]
    # Layered flared witch robe / cloak skirt (grounded)
    add_cone(bm, 1.38 if elite else 1.18, 0.62, 2.85, (0.0, 0.0, 1.48), cloak_mat, sides=8)
    # Torso & shoulder mantle
    C.add_faceted_box(bm, (1.52, 1.05, 1.32), (0.0, 0.0, 3.10), M["WitchCloak"], bevel=0.14, taper_top=(0.88, 0.88))
    if elite:
        # Layered royal mantle shoulder flares + floating jade rune collar
        for sx in (-0.98, 0.98):
            C.add_faceted_box(bm, (0.72, 1.15, 0.56), (sx, 0.0, 3.62), M["WitchCrimson"], bevel=0.08, rot_deg=(0, 22 if sx < 0 else -22, 0))
        for i in range(4):
            ang = math.radians(i * 90.0 + 45.0)
            C.add_crystal_prism(bm, 0.14, 0.48, (math.cos(ang) * 1.18, math.sin(ang) * 1.18, 3.92), M["JadeGlow"], sides=4)
    # Head & glowing eyes (facing -Y)
    C.add_faceted_icosphere(bm, 0.62, (0.0, -0.05, 4.18), M["WitchSkin"], subdivisions=2, scale=(0.95, 0.92, 1.02))
    for sx in (-0.24, 0.24):
        C.add_faceted_icosphere(bm, 0.13, (sx, -0.58, 4.24), M["JadeGlow"] if not elite else M["HexGlow"], subdivisions=1)
    # Wide-brimmed crooked pointed witch hat + gold band & buckle
    add_cone(bm, 1.65 if elite else 1.42, 1.25 if elite else 1.05, 0.24, (0.0, -0.05, 4.62), hat_mat, sides=10)
    hat_ring = C.add_closed_ring(bm, 0.74, 0.12, 0.24, M["GoldMetal"], segments=10)
    bmesh.ops.translate(bm, verts=hat_ring, vec=Vector((0.0, -0.02, 4.78)))
    # Hat spire (crooked tip)
    add_cone(bm, 0.74, 0.34, 1.05, (0.0, 0.02, 5.18), hat_mat, sides=8, rot_deg=(-8, 10, 0))
    add_cone(bm, 0.36, 0.06, 0.82 if elite else 0.62, (0.24, 0.22, 5.90 if elite else 5.80), hat_mat, sides=7, rot_deg=(-22, 24, 0))
    if elite:
        C.add_crystal_prism(bm, 0.18, 0.52, (0.48, 0.38, 6.22), M["GoldMetal"], sides=5, rot_deg=(-20, 20, 0))
    # Sleeved arms
    C.add_faceted_box(bm, (0.46, 0.50, 1.32), (-0.98, -0.18, 2.95), cloak_mat, bevel=0.06, rot_deg=(24, 0, -14))
    C.add_faceted_box(bm, (0.48, 0.52, 1.38), (0.98, -0.45, 3.08), cloak_mat, bevel=0.06, rot_deg=(54, 0, 12))
    # Gnarled arcane staff + glowing ballistic hex orb!
    add_cone(bm, 0.14, 0.10, 4.65, (1.28, -0.92, 2.45), M["StaffWood"], sides=6, rot_deg=(8, -4, 0))
    orb_r = 0.56 if elite else 0.42
    C.add_faceted_icosphere(bm, orb_r, (1.36, -1.16, 4.92), M["HexGlow"], subdivisions=2)
    if elite:
        # Twin-pronged gold staff cradle
        for sx in (-0.42, 0.42):
            C.add_crystal_prism(bm, 0.14, 0.85, (1.36 + sx, -1.16, 4.82), M["GoldMetal"], sides=5, rot_deg=(0, -24 if sx < 0 else 24, 0))
    name = "CovenArchWitch" if elite else "MeadowWitch"
    return ground_and_finalize(name, bm, mats, target_h=6.1 if elite else 5.6)


# =============================================================================
# 5. RUIN SENTINEL & ANCIENT RUIN WARDEN
# =============================================================================
def build_ruin_sentinel(mats: list[bpy.types.Material], M: dict[str, int], elite: bool) -> bpy.types.Object:
    bm = bmesh.new()
    stone = M["StoneObsidian"] if elite else M["StoneBase"]
    trim = M["GoldMetal"] if elite else M["StoneDark"]
    # Stout rune-etched stone legs
    for sx in (-0.82, 0.82):
        C.add_faceted_box(bm, (0.96, 1.08, 1.95), (sx, 0.0, 0.98), M["StoneDark"], bevel=0.10, taper_top=(0.88, 0.88))
        C.add_faceted_box(bm, (1.12, 1.32, 0.45), (sx, -0.10, 0.22), stone, bevel=0.08)
    # Carved monolith torso + glowing jade core
    C.add_faceted_box(bm, (2.45, 1.75, 2.35), (0.0, 0.0, 3.05), stone, bevel=0.20, taper_top=(1.15, 1.08))
    C.add_crystal_prism(bm, 0.56 if elite else 0.42, 1.28, (0.0, -0.88, 3.12), M["JadeGlow"], sides=6, rot_deg=(90, 0, 0))
    C.add_faceted_box(bm, (2.60, 0.42, 0.34), (0.0, -0.78, 2.08), trim, bevel=0.06)
    # Heavy stone pauldrons + moss caps
    for sx in (-1.78, 1.78):
        C.add_faceted_box(bm, (1.35, 1.55, 1.18), (sx, 0.0, 4.18), stone, bevel=0.16)
        C.add_faceted_icosphere(bm, 0.65, (sx, 0.12, 4.78), M["MossLeaf"], subdivisions=1, scale=(1.2, 1.0, 0.55))
        # Chunky forearms + fists
        C.add_faceted_box(bm, (0.96, 1.05, 2.15), (sx * 1.06, -0.18, 2.55), M["StoneDark"], bevel=0.12)
        C.add_faceted_box(bm, (1.14, 1.24, 0.92), (sx * 1.08, -0.28, 1.32), trim if elite else stone, bevel=0.12)
    # Recessed stone head + glowing jade visor
    C.add_faceted_box(bm, (1.42, 1.32, 1.18), (0.0, -0.12, 4.88), stone, bevel=0.14)
    C.add_faceted_box(bm, (1.05, 0.28, 0.28), (0.0, -0.78, 4.92), M["JadeGlow"], bevel=0.03)
    if elite:
        # Horned obsidian-gold ruin crown + twin floating jade shoulder pylons!
        C.add_faceted_box(bm, (1.72, 1.42, 0.36), (0.0, -0.05, 5.56), M["GoldMetal"], bevel=0.06)
        for sx in (-0.65, 0.65):
            C.add_crystal_prism(bm, 0.24, 1.05, (sx, 0.0, 6.08), M["GoldMetal"], sides=5, rot_deg=(-12, -16 if sx < 0 else 16, 0))
        for sx in (-2.55, 2.55):
            C.add_crystal_prism(bm, 0.34, 1.55, (sx, 0.15, 5.35), M["JadeGlow"], sides=6)
            C.add_faceted_box(bm, (0.58, 0.58, 0.36), (sx, 0.15, 4.42), M["GoldMetal"], bevel=0.05)
    name = "AncientWarden" if elite else "RuinSentinel"
    return ground_and_finalize(name, bm, mats, target_h=6.8 if elite else 6.0)


# =============================================================================
# SCALE & SIGHTLINE GAUGES (Avatar 5.5H, Doorway 6x9, Watchtower Balcony)
# =============================================================================
def build_avatar_ref(mats: list[bpy.types.Material], M: dict[str, int], name: str = "Avatar_5_5H") -> bpy.types.Object:
    bm = bmesh.new()
    m = M["AvatarRef"]
    # Standard 5.5-stud Roblox R15 Avatar
    for sx in (-0.52, 0.52):
        C.add_faceted_box(bm, (0.95, 1.0, 2.0), (sx, 0.0, 1.0), m, bevel=0.05)
    C.add_faceted_box(bm, (2.0, 1.0, 2.0), (0.0, 0.0, 3.05), m, bevel=0.06)
    for sx in (-1.48, 1.48):
        C.add_faceted_box(bm, (0.90, 0.95, 1.95), (sx, 0.0, 3.05), m, bevel=0.05)
    C.add_faceted_box(bm, (1.25, 1.25, 1.25), (0.0, 0.0, 4.78), m, bevel=0.14)
    return ground_and_finalize(name, bm, mats, target_h=5.5)


def build_doorway_gauge(mats: list[bpy.types.Material], M: dict[str, int]) -> bpy.types.Object:
    bm = bmesh.new()
    # Exact 6W x 9H open doorway frame from EM_MeadowCottage_A / EM_Watchtower
    C.add_faceted_box(bm, (1.0, 1.2, 9.2), (-3.5, 0.0, 4.6), M["GaugeTimber"], bevel=0.06)
    C.add_faceted_box(bm, (1.0, 1.2, 9.2), (3.5, 0.0, 4.6), M["GaugeTimber"], bevel=0.06)
    C.add_faceted_box(bm, (8.2, 1.4, 1.0), (0.0, 0.0, 9.5), M["GaugeTimberDk"], bevel=0.06)
    return ground_and_finalize("DoorwayGauge_6x9", bm, mats)


def build_watchtower_balcony_gauge(mats: list[bpy.types.Material], M: dict[str, int]) -> bpy.types.Object:
    """Exact Studio-verified Watchtower gallery cutaway: deck top=0 (world 30.3), parapet=2.3, roof eave=6.5."""
    bm = bmesh.new()
    # Deck slab (top surface at Z = 0.0!)
    C.add_faceted_box(bm, (18.2, 10.0, 2.2), (0.0, 2.0, -1.1), M["GaugeTimberDk"], bevel=0.10)
    # Front parapet railing at Y = -3.0 (height 2.3 studs -> top at Z = 2.3!)
    C.add_faceted_box(bm, (18.2, 1.0, 2.3), (0.0, -2.5, 1.15), M["GaugeTimber"], bevel=0.06)
    # Two outer corner posts (Z = 0..6.5)
    for sx in (-8.2, 8.2):
        C.add_faceted_box(bm, (1.6, 1.6, 6.8), (sx, -2.3, 3.4), M["GaugeTimber"], bevel=0.08)
    # Center warm beacon behind witches (Y = +4.5)
    C.add_faceted_box(bm, (3.8, 3.8, 3.4), (0.0, 4.2, 3.1), M["AmberGlow"], bevel=0.08)
    # Overhanging crimson spire roof eave starting at exact Z = 6.5!
    C.add_faceted_box(bm, (19.6, 11.4, 0.8), (0.0, 2.0, 6.9), M["GaugeRoof"], bevel=0.08)
    add_cone(bm, 11.5, 0.6, 7.6, (0.0, 2.0, 11.0), M["GaugeRoof"], sides=4, rot_deg=(0, 0, 45))
    obj = C.finalize_mesh("WatchtowerBalcony_Cutaway", bm, mats)
    return obj


def render_view(
    objs: list[bpy.types.Object],
    filename: str,
    cam_pos: Vector,
    target: Vector,
    res: tuple[int, int] = (1440, 760),
    samples: int = 18,
    lens: float = 42.0,
) -> Path:
    C.clear_studio_rig()
    C.RENDER_DIR.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = False
    scene.cycles.max_bounces = 4
    scene.render.threads_mode = "FIXED"
    scene.render.threads = 6
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "Standard"

    world = bpy.data.worlds.new("BlockoutWorld")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs["Color"].default_value = (0.048, 0.056, 0.068, 1.0)
        bg.inputs["Strength"].default_value = 0.90
    scene.world = world

    mins, maxs = C.world_bounds(objs)
    center = (mins + maxs) * 0.5
    span = max((maxs - mins).length, 10.0)

    bpy.ops.mesh.primitive_plane_add(size=span * 6.0, location=(center.x, center.y, -0.02))
    floor = bpy.context.active_object
    floor.name = "_StudioFloor"
    floor.data.materials.append(C.make_material("_FloorMat", (0.09, 0.105, 0.115), roughness=0.86))

    lights = [
        ("KeyLight", (center.x + span * 0.7, center.y - span * 1.1, span * 0.85), span * 260.0, (1.0, 0.97, 0.92), span * 0.65),
        ("FillLight", (center.x - span * 0.9, center.y - span * 0.6, span * 0.45), span * 115.0, (0.74, 0.88, 1.0), span * 0.85),
        ("RimLight", (center.x, center.y + span * 1.0, span * 0.75), span * 180.0, (0.76, 1.0, 0.88), span * 0.75),
    ]
    for lname, loc, energy, col, lsize in lights:
        ld = bpy.data.lights.new(name=lname, type="AREA")
        ld.energy = energy
        ld.color = col
        ld.size = lsize
        lo = bpy.data.objects.new(name=lname, object_data=ld)
        lo.location = Vector(loc)
        lo.rotation_euler = (target - lo.location).to_track_quat("-Z", "Y").to_euler()
        bpy.context.collection.objects.link(lo)

    cd = bpy.data.cameras.new("PreviewCam")
    cd.lens = lens
    co = bpy.data.objects.new("PreviewCam", cd)
    co.location = cam_pos
    co.rotation_euler = (target - cam_pos).to_track_quat("-Z", "Y").to_euler()
    bpy.context.collection.objects.link(co)
    scene.camera = co

    out_path = C.RENDER_DIR / filename
    scene.render.filepath = str(out_path)
    bpy.ops.render.render(write_still=True)
    return out_path


def main() -> None:
    C.clear_scene()
    mats, M = build_palette()

    # Build all 10 mob blockouts (5 Base + 5 Natural Area Elites)
    specs = [
        ("MossSlime", lambda: build_moss_slime(mats, M, False), (-14.0, -3.5, 0.0)),
        ("ElderMossSlime", lambda: build_moss_slime(mats, M, True), (-14.0, 4.2, 0.0)),
        ("RiverSnapper", lambda: build_river_snapper(mats, M, False), (-7.0, -3.5, 0.0)),
        ("TidecrestSnapper", lambda: build_river_snapper(mats, M, True), (-7.0, 4.2, 0.0)),
        ("BrambleBoar", lambda: build_bramble_boar(mats, M, False), (0.5, -3.5, 0.0)),
        ("ThornbackAlpha", lambda: build_bramble_boar(mats, M, True), (0.5, 4.2, 0.0)),
        ("MeadowWitch", lambda: build_meadow_witch(mats, M, False), (7.8, -3.5, 0.0)),
        ("CovenArchWitch", lambda: build_meadow_witch(mats, M, True), (7.8, 4.2, 0.0)),
        ("RuinSentinel", lambda: build_ruin_sentinel(mats, M, False), (15.0, -3.5, 0.0)),
        ("AncientWarden", lambda: build_ruin_sentinel(mats, M, True), (15.0, 4.2, 0.0)),
    ]

    mob_objs: dict[str, bpy.types.Object] = {}
    for name, fn, loc in specs:
        obj = fn()
        C.validate_asset(name, [obj], tri_cap=2500, pivot_mode="floor")
        obj.location = Vector(loc)
        mob_objs[name] = obj

    # Scale gauges next to lineup
    avatar = build_avatar_ref(mats, M, "Avatar_5_5H_Lineup")
    avatar.location = Vector((-21.0, -3.5, 0.0))
    doorway = build_doorway_gauge(mats, M)
    doorway.location = Vector((-21.0, 4.2, 0.0))

    lineup_all = [avatar, doorway, *mob_objs.values()]

    # Build Watchtower Balcony Perch QA rig off to the right (+34X)
    balcony = build_watchtower_balcony_gauge(mats, M)
    balcony.location = Vector((36.0, 0.0, 0.0))
    perch_arch = build_meadow_witch(mats, M, True)
    perch_arch.name = "Perched_CovenArchWitch"
    perch_arch.location = Vector((33.2, -0.4, 0.0))
    perch_base = build_meadow_witch(mats, M, False)
    perch_base.name = "Perched_MeadowWitch"
    perch_base.location = Vector((38.8, -0.4, 0.0))
    perch_avatar = build_avatar_ref(mats, M, "Avatar_5_5H_Balcony")
    perch_avatar.location = Vector((24.8, -0.4, 0.0))

    # Save .blend for live Blender inspection
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUT))
    print(f"[SAVED] {BLEND_OUT}")

    # Render 1: Full 10-Mob Lineup (Front=Base, Back=Elite) + 5.5H Avatar + 6x9 Doorway
    p1 = render_view(
        lineup_all,
        "EmeraldMeadow_Mobs_Blockout_Lineup.png",
        cam_pos=Vector((-2.5, -45.5, 14.5)),
        target=Vector((-2.5, 0.5, 3.6)),
        res=(1440, 720),
        samples=18,
        lens=31.0,
    )
    print(f"[RENDER] {p1}")

    # Render 2: Close-Up of Pairs 1-3 (Slimes, Snappers, Boars) + Avatar
    creatures = [
        avatar,
        mob_objs["MossSlime"], mob_objs["ElderMossSlime"],
        mob_objs["RiverSnapper"], mob_objs["TidecrestSnapper"],
        mob_objs["BrambleBoar"], mob_objs["ThornbackAlpha"],
    ]
    p2 = render_view(
        creatures,
        "EmeraldMeadow_Mobs_Blockout_Creatures.png",
        cam_pos=Vector((-10.0, -28.0, 9.2)),
        target=Vector((-10.0, 0.5, 2.4)),
        res=(1440, 720),
        samples=18,
        lens=32.0,
    )
    print(f"[RENDER] {p2}")

    # Render 3: Watchtower Balcony Perch QA (Perched Witches behind 2.3H parapet under 6.5H roof + Ruins)
    perch_group = [
        mob_objs["MeadowWitch"], mob_objs["CovenArchWitch"],
        mob_objs["RuinSentinel"], mob_objs["AncientWarden"],
        perch_avatar, balcony, perch_arch, perch_base,
    ]
    p3 = render_view(
        perch_group,
        "EmeraldMeadow_Mobs_Blockout_CastersRuins_Perch.png",
        cam_pos=Vector((24.5, -39.5, 11.2)),
        target=Vector((24.5, 0.8, 4.2)),
        res=(1440, 720),
        samples=18,
        lens=32.0,
    )
    print(f"[RENDER] {p3}")


if __name__ == "__main__":
    main()
