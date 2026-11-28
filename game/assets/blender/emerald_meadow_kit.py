"""Sculpted stylized low-poly modular 3D environment kit for Emerald Meadow 10x.

Follows game/assets/STYLE_GUIDE.md:
- Lofted multi-ring organic trunks/branches (add_lofted_tube)
- Beveled flat-faceted masonry, timber beams, roofs, boulders, and crystals
- 3-tier color saturation hierarchy & binary metalness
- Multi-mesh per material group so Roblox Studio imports cleanly as named MeshParts
  with crisp per-part Roblox PBR materials & exact sRGB colors
- Grounded floor pivots (min_z = 0.00), 1 Blender unit = 1 Roblox stud

Run via:
    python scripts/blender_run.py game/assets/blender/emerald_meadow_kit.py
"""

from __future__ import annotations

import json
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

EXPORT_DIR = common.EXPORT_DIR
RENDER_DIR = common.RENDER_DIR
MANIFEST_PATH = EXPORT_DIR / "emerald_meadow_kit_manifest.json"


# Canonical sRGB (0..255), linear PBR, Roughness, Metallic, Emission, Roblox Enum.Material
PALETTE: dict[str, dict] = {
    "StoneBase":   {"srgb": (96, 108, 100),  "rough": 0.84, "metal": 0.0,  "em": 0.0, "rbx_mat": "Cobblestone"},
    "StoneDark":   {"srgb": (64, 74, 68),    "rough": 0.88, "metal": 0.0,  "em": 0.0, "rbx_mat": "Rock"},
    "StoneLight":  {"srgb": (152, 160, 148), "rough": 0.78, "metal": 0.0,  "em": 0.0, "rbx_mat": "Slate"},
    "CliffRock":   {"srgb": (82, 96, 86),    "rough": 0.88, "metal": 0.0,  "em": 0.0, "rbx_mat": "Rock"},
    "Plaster":     {"srgb": (228, 220, 198), "rough": 0.82, "metal": 0.0,  "em": 0.0, "rbx_mat": "Plaster"},
    "Timber":      {"srgb": (118, 76, 46),   "rough": 0.76, "metal": 0.0,  "em": 0.0, "rbx_mat": "Wood"},
    "TimberDark":  {"srgb": (78, 50, 32),    "rough": 0.82, "metal": 0.0,  "em": 0.0, "rbx_mat": "WoodPlanks"},
    "BarkOak":     {"srgb": (86, 58, 38),    "rough": 0.88, "metal": 0.0,  "em": 0.0, "rbx_mat": "Wood"},
    "BarkBirch":   {"srgb": (224, 218, 204), "rough": 0.80, "metal": 0.0,  "em": 0.0, "rbx_mat": "Wood"},
    "RoofEmerald": {"srgb": (38, 118, 76),   "rough": 0.62, "metal": 0.0,  "em": 0.0, "rbx_mat": "Slate"},
    "RoofCrimson": {"srgb": (184, 58, 50),   "rough": 0.58, "metal": 0.0,  "em": 0.0, "rbx_mat": "Slate"},
    "LeafOak":     {"srgb": (54, 152, 68),   "rough": 0.72, "metal": 0.0,  "em": 0.0, "rbx_mat": "Grass"},
    "LeafOakHi":   {"srgb": (84, 196, 88),   "rough": 0.68, "metal": 0.0,  "em": 0.0, "rbx_mat": "Grass"},
    "LeafPine":    {"srgb": (32, 98, 56),    "rough": 0.76, "metal": 0.0,  "em": 0.0, "rbx_mat": "Grass"},
    "LeafBirch":   {"srgb": (112, 208, 76),  "rough": 0.68, "metal": 0.0,  "em": 0.0, "rbx_mat": "Grass"},
    "LeafElder":   {"srgb": (36, 186, 108),  "rough": 0.55, "metal": 0.0,  "em": 0.25, "rbx_mat": "Grass"},
    "MossCap":     {"srgb": (62, 148, 72),   "rough": 0.80, "metal": 0.0,  "em": 0.0, "rbx_mat": "Grass"},
    "FlowerGold":  {"srgb": (248, 206, 58),  "rough": 0.45, "metal": 0.0,  "em": 0.0, "rbx_mat": "SmoothPlastic"},
    "FlowerCoral": {"srgb": (246, 108, 134), "rough": 0.45, "metal": 0.0,  "em": 0.0, "rbx_mat": "SmoothPlastic"},
    "IronMetal":   {"srgb": (68, 74, 82),    "rough": 0.34, "metal": 0.88, "em": 0.0, "rbx_mat": "Metal"},
    "GoldTrim":    {"srgb": (236, 190, 56),  "rough": 0.28, "metal": 0.88, "em": 0.0, "rbx_mat": "Metal"},
    "DoorVoid":    {"srgb": (26, 22, 22),    "rough": 0.92, "metal": 0.0,  "em": 0.0, "rbx_mat": "SmoothPlastic"},
    "WarmGlow":    {"srgb": (255, 198, 92),  "rough": 0.16, "metal": 0.0,  "em": 2.3, "rbx_mat": "Neon"},
    "JadeGlow":    {"srgb": (34, 232, 122),  "rough": 0.14, "metal": 0.0,  "em": 2.2, "rbx_mat": "Neon"},
}


def srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def make_pal_material(key: str) -> bpy.types.Material:
    spec = PALETTE[key]
    lin = tuple(srgb_to_linear(v / 255.0) for v in spec["srgb"])
    mat = bpy.data.materials.new(name=f"Mat_{key}")
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*lin, 1.0)
    bsdf.inputs["Roughness"].default_value = spec["rough"]
    bsdf.inputs["Metallic"].default_value = spec["metal"]
    if spec["em"] > 0.0:
        em = bsdf.inputs.get("Emission Color") or bsdf.inputs.get("Emission")
        if em:
            em.default_value = (*lin, 1.0)
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = spec["em"]
    return mat


class MultiPartAsset:
    """Collects geometry per palette material so each material exports as a named MeshPart."""

    def __init__(self, asset_name: str) -> None:
        self.asset_name = asset_name
        self.bms: dict[str, bmesh.types.BMesh] = {}

    def bm(self, mat_key: str) -> bmesh.types.BMesh:
        if mat_key not in self.bms:
            self.bms[mat_key] = bmesh.new()
        return self.bms[mat_key]

    def box(
        self,
        mat_key: str,
        size: tuple[float, float, float],
        center: tuple[float, float, float],
        bevel: float = 0.08,
        rot_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
        taper_top: tuple[float, float] = (1.0, 1.0),
    ) -> None:
        common.add_faceted_box(self.bm(mat_key), size, center, 0, bevel=bevel, rot_deg=rot_deg, taper_top=taper_top)

    def ico(
        self,
        mat_key: str,
        radius: float,
        center: tuple[float, float, float],
        subdivisions: int = 2,
        scale: tuple[float, float, float] = (1.0, 1.0, 1.0),
        rot_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
        noise_amp: float = 0.14,
        seed: int = 1,
    ) -> None:
        common.add_faceted_icosphere(
            self.bm(mat_key), radius, center, 0, subdivisions=subdivisions,
            scale=scale, rot_deg=rot_deg, noise_amp=noise_amp, seed=seed,
        )

    def loft(
        self,
        mat_key: str,
        rings: list[tuple[tuple[float, float, float], float, float, tuple[float, float, float]]],
        sides: int = 8,
        smooth: bool = False,
    ) -> None:
        common.add_lofted_tube(self.bm(mat_key), rings, 0, sides=sides, smooth=smooth)

    def crystal(
        self,
        mat_key: str,
        radius: float,
        height: float,
        center: tuple[float, float, float],
        sides: int = 6,
        rot_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
    ) -> None:
        common.add_crystal_prism(self.bm(mat_key), radius, height, center, 0, sides=sides, rot_deg=rot_deg)

    def cone(
        self,
        mat_key: str,
        r1: float,
        r2: float,
        depth: float,
        center: tuple[float, float, float],
        sides: int = 7,
        rot_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
    ) -> None:
        bm = self.bm(mat_key)
        ret = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=sides, radius1=r1, radius2=r2, depth=depth)
        verts = ret["verts"]
        rot = Euler(tuple(math.radians(a) for a in rot_deg), "XYZ").to_matrix().to_4x4()
        bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector(center)) @ rot, verts=verts)
        for f in {f for v in verts for f in v.link_faces}:
            f.material_index = 0
            f.smooth = False

    def gable_prism(
        self,
        mat_key: str,
        width: float,
        depth: float,
        height: float,
        base_z: float,
        center_xy: tuple[float, float] = (0.0, 0.0),
    ) -> None:
        """Clean triangular gable prism along Y (ridge runs along Y, slopes along X)."""
        bm = self.bm(mat_key)
        cx, cy = center_xy
        hw, hd = width * 0.5, depth * 0.5
        v0 = bm.verts.new((cx - hw, cy - hd, base_z))
        v1 = bm.verts.new((cx + hw, cy - hd, base_z))
        v2 = bm.verts.new((cx,      cy - hd, base_z + height))
        v3 = bm.verts.new((cx - hw, cy + hd, base_z))
        v4 = bm.verts.new((cx + hw, cy + hd, base_z))
        v5 = bm.verts.new((cx,      cy + hd, base_z + height))
        faces = [
            (v0, v1, v2),
            (v4, v3, v5),
            (v0, v3, v4, v1),
            (v0, v2, v5, v3),
            (v1, v4, v5, v2),
        ]
        for fverts in faces:
            f = bm.faces.new(fverts)
            f.material_index = 0
            f.smooth = False

    def finalize_and_ground(self) -> list[bpy.types.Object]:
        objs: list[bpy.types.Object] = []
        for mat_key, bm in self.bms.items():
            mat = make_pal_material(mat_key)
            obj = common.finalize_mesh(f"{self.asset_name}__{mat_key}", bm, [mat])
            objs.append(obj)
        # Shift so min_z == 0.00 exactly
        mins, maxs = common.world_bounds(objs)
        dz = -mins.z
        if abs(dz) > 1e-4:
            for obj in objs:
                for v in obj.data.vertices:
                    v.co.z += dz
                obj.data.update()
        return objs


# =============================================================================
# 17 MODULAR EMERALD MEADOW ASSETS
# =============================================================================

def build_oak_tree() -> MultiPartAsset:
    a = MultiPartAsset("EM_OakTree_Hero")
    # Gnarled flared trunk with clear 8.5-stud walk-under height
    a.loft("BarkOak", [
        ((0.0, 0.0, 0.0), 2.5, 2.3, (0, 0, 0)),
        ((0.1, -0.1, 2.5), 1.8, 1.7, (2, 1, 10)),
        ((-0.2, 0.2, 6.2), 1.45, 1.4, (-2, 3, 25)),
        ((0.0, 0.0, 10.5), 1.25, 1.2, (0, 0, 40)),
        ((0.2, -0.1, 13.5), 0.9, 0.9, (0, 0, 50)),
    ], sides=8)
    # 3 flaring roots
    for i in range(4):
        ang = i * 90 + 25
        rad = math.radians(ang)
        a.box("BarkOak", (2.6, 1.2, 1.6), (math.cos(rad) * 2.0, math.sin(rad) * 2.0, 0.6), bevel=0.2, rot_deg=(0, 18, ang))
    # 2 sturdy upper limbs
    a.loft("BarkOak", [
        ((0.0, 0.0, 9.2), 0.95, 0.95, (0, 28, 15)),
        ((3.4, 1.2, 13.4), 0.65, 0.65, (0, 35, 15)),
    ], sides=6)
    a.loft("BarkOak", [
        ((0.0, 0.0, 9.8), 0.9, 0.9, (0, -28, -25)),
        ((-3.3, -1.6, 13.8), 0.6, 0.6, (0, -34, -25)),
    ], sides=6)
    # Lush clustered low-poly canopy (7 faceted spheres in two greens)
    a.ico("LeafOak", 5.8, (0.0, 0.0, 17.5), subdivisions=2, scale=(1.25, 1.15, 0.85), noise_amp=0.14, seed=11)
    a.ico("LeafOak", 4.6, (4.8, 1.8, 15.2), subdivisions=2, scale=(1.15, 1.05, 0.82), noise_amp=0.15, seed=12)
    a.ico("LeafOak", 4.7, (-4.6, -2.0, 15.6), subdivisions=2, scale=(1.12, 1.10, 0.82), noise_amp=0.14, seed=13)
    a.ico("LeafOak", 4.2, (-1.6, 4.4, 15.4), subdivisions=2, scale=(1.08, 1.08, 0.80), noise_amp=0.15, seed=14)
    a.ico("LeafOak", 4.0, (2.2, -4.3, 15.0), subdivisions=2, scale=(1.10, 1.02, 0.80), noise_amp=0.14, seed=15)
    a.ico("LeafOakHi", 4.4, (0.8, 0.6, 22.2), subdivisions=2, scale=(1.18, 1.12, 0.78), noise_amp=0.13, seed=16)
    a.ico("LeafOakHi", 3.1, (-3.2, 1.5, 19.6), subdivisions=2, scale=(1.10, 1.05, 0.78), noise_amp=0.13, seed=17)
    return a


def build_pine_tree() -> MultiPartAsset:
    a = MultiPartAsset("EM_PineTree_Tall")
    a.loft("BarkOak", [
        ((0.0, 0.0, 0.0), 1.9, 1.9, (0, 0, 0)),
        ((0.0, 0.0, 4.5), 1.4, 1.4, (0, 0, 10)),
        ((0.0, 0.0, 10.5), 1.0, 1.0, (0, 0, 20)),
    ], sides=7)
    # 4 layered jagged evergreen skirts (walk-under starts at Z=7.5)
    tiers = [
        (7.5,  8.2, 2.2, 7.6, 0.0,  "LeafPine"),
        (13.2, 6.8, 1.8, 7.4, 24.0, "LeafPine"),
        (18.6, 5.2, 1.2, 7.0, 48.0, "LeafOak"),
        (23.6, 3.6, 0.3, 6.8, 14.0, "LeafPine"),
    ]
    for z0, r1, r2, h, rotz, m in tiers:
        a.cone(m, r1, r2, h, (0.0, 0.0, z0 + h * 0.5), sides=7, rot_deg=(0, 0, rotz))
    return a


def build_birch_tree() -> MultiPartAsset:
    a = MultiPartAsset("EM_BirchTree_Slender")
    a.loft("BarkBirch", [
        ((0.0, 0.0, 0.0), 1.3, 1.2, (0, 0, 0)),
        ((0.15, 0.0, 4.0), 0.95, 0.92, (0, 2, 15)),
        ((-0.15, 0.15, 8.8), 0.75, 0.72, (2, -2, 30)),
        ((0.1, -0.1, 13.0), 0.52, 0.50, (0, 0, 45)),
    ], sides=7)
    # Dark birch bark knots/stripes
    for z in (2.2, 4.8, 7.4):
        a.box("StoneDark", (1.85, 0.45, 0.55), (0.0, 0.0, z), bevel=0.05, rot_deg=(0, 0, z * 42))
    # Bright airy spring-green crown
    a.ico("LeafBirch", 4.6, (0.0, 0.0, 15.8), subdivisions=2, scale=(1.12, 1.08, 0.92), noise_amp=0.14, seed=21)
    a.ico("LeafBirch", 3.5, (3.2, 1.4, 14.0), subdivisions=2, scale=(1.05, 1.02, 0.86), noise_amp=0.14, seed=22)
    a.ico("LeafBirch", 3.4, (-3.0, -1.6, 14.4), subdivisions=2, scale=(1.08, 1.0, 0.88), noise_amp=0.14, seed=23)
    a.ico("LeafOakHi", 3.2, (0.4, 0.2, 19.6), subdivisions=2, scale=(1.05, 1.02, 0.84), noise_amp=0.12, seed=24)
    return a


def build_elder_oak() -> MultiPartAsset:
    a = MultiPartAsset("EM_ElderOak_Landmark")
    a.loft("BarkOak", [
        ((0.0, 0.0, 0.0), 5.0, 4.8, (0, 0, 0)),
        ((0.3, -0.2, 4.5), 3.6, 3.4, (2, 1, 12)),
        ((-0.3, 0.3, 10.5), 2.9, 2.8, (-2, 2, 24)),
        ((0.0, 0.0, 16.5), 2.3, 2.2, (0, 0, 36)),
    ], sides=9)
    for i in range(6):
        ang = i * 60 + 15
        rad = math.radians(ang)
        a.box("BarkOak", (5.2, 2.0, 2.8), (math.cos(rad) * 4.0, math.sin(rad) * 4.0, 1.0), bevel=0.3, rot_deg=(0, 22, ang))
    # 3 dramatic sweeping limbs
    for ang in (20, 145, 265):
        rad = math.radians(ang)
        a.loft("BarkOak", [
            ((0.0, 0.0, 13.5), 1.6, 1.6, (0, 0, ang)),
            ((math.cos(rad) * 6.5, math.sin(rad) * 6.5, 19.5), 1.0, 1.0, (0, 0, ang)),
        ], sides=7)
    # Monumental tiered spirit canopy
    a.ico("LeafOak", 9.0, (0.0, 0.0, 24.5), subdivisions=2, scale=(1.35, 1.30, 0.78), noise_amp=0.14, seed=31)
    for idx, (cx, cy, cz, r, m) in enumerate([
        (8.8, 3.4, 21.5, 6.4, "LeafElder"),
        (-8.4, 4.6, 21.8, 6.5, "LeafOak"),
        (-2.2, -9.0, 21.2, 6.2, "LeafElder"),
        (6.0, -6.5, 22.4, 5.6, "LeafOakHi"),
        (0.0, 0.4, 31.0, 6.8, "LeafElder"),
    ]):
        a.ico(m, r, (cx, cy, cz), subdivisions=2, scale=(1.2, 1.15, 0.76), noise_amp=0.14, seed=32 + idx)
    # Glowing emerald spirit crystals nestled in roots
    for ang in (45, 165, 290):
        rad = math.radians(ang)
        a.crystal("JadeGlow", 0.9, 3.4, (math.cos(rad) * 4.8, math.sin(rad) * 4.8, 1.6), sides=5, rot_deg=(12, -10, ang))
    return a


def build_cottage_a() -> MultiPartAsset:
    a = MultiPartAsset("EM_MeadowCottage_A")
    # 26W x 20D x 16.5H, avatar-scaled 6x9 front doorway on -Y face
    a.box("StoneBase", (26.6, 20.6, 2.2), (0, 0, 1.1), bevel=0.18)
    a.box("Plaster", (25.2, 19.2, 9.2), (0, 0, 6.4), bevel=0.12)
    # Corner timber posts & horizontal beams
    for sx in (-12.5, 12.5):
        for sy in (-9.5, 9.5):
            a.box("TimberDark", (1.2, 1.2, 9.6), (sx, sy, 6.6), bevel=0.06)
    a.box("TimberDark", (26.0, 1.0, 1.0), (0, -9.6, 10.6), bevel=0.05)
    a.box("TimberDark", (26.0, 1.0, 1.0), (0, 9.6, 10.6), bevel=0.05)
    # Pitched overhanging emerald-shingle roof (gable prism + flush Y-aligned ridge beam)
    a.gable_prism("RoofEmerald", 29.4, 22.4, 6.4, 10.8)
    a.box("Timber", (1.2, 23.0, 1.0), (0, 0, 17.2), bevel=0.08)  # Ridge beam along Y
    # Stone chimney
    a.box("StoneDark", (3.6, 3.6, 9.5), (7.8, 4.2, 14.5), bevel=0.15)
    a.box("StoneLight", (4.2, 4.2, 0.9), (7.8, 4.2, 19.4), bevel=0.10)
    # Front 6W x 9H doorway frame + porch steps (avatar-scaled!)
    a.box("DoorVoid", (6.0, 0.6, 9.0), (0, -9.55, 4.5), bevel=0.02)
    a.box("Timber", (7.4, 1.4, 1.0), (0, -9.8, 9.3), bevel=0.06)
    a.box("Timber", (1.0, 1.4, 9.2), (-3.4, -9.8, 4.6), bevel=0.06)
    a.box("Timber", (1.0, 1.4, 9.2), (3.4, -9.8, 4.6), bevel=0.06)
    a.box("StoneLight", (8.8, 3.2, 0.8), (0, -11.4, 0.4), bevel=0.08)
    # Warm glowing windows on front & sides
    for wx in (-7.6, 7.6):
        a.box("WarmGlow", (3.6, 0.5, 3.4), (wx, -9.6, 6.2), bevel=0.04)
        a.box("TimberDark", (4.2, 0.8, 0.5), (wx, -9.75, 4.4), bevel=0.03)
    for sx in (-12.6, 12.6):
        a.box("WarmGlow", (0.5, 4.2, 3.4), (sx, 0.0, 6.2), bevel=0.04)
    return a


def build_watermill_b() -> MultiPartAsset:
    a = MultiPartAsset("EM_MeadowWatermill_B")
    # 30W x 22D x 18.5H cozy timber watermill with vertical river wheel on +X side
    a.box("StoneBase", (28.0, 22.0, 3.2), (-1.0, 0, 1.6), bevel=0.20)
    a.box("Plaster", (26.6, 20.6, 9.6), (-1.0, 0, 7.6), bevel=0.12)
    for sx in (-14.2, 12.2):
        for sy in (-10.2, 10.2):
            a.box("TimberDark", (1.3, 1.3, 10.2), (sx, sy, 7.8), bevel=0.06)
    a.gable_prism("RoofEmerald", 31.0, 24.0, 7.0, 12.0, center_xy=(-1.0, 0.0))
    a.box("Timber", (1.3, 24.6, 1.1), (-1.0, 0, 19.0), bevel=0.08)
    # Front 6x9 doorway
    a.box("DoorVoid", (6.0, 0.6, 9.0), (-2.0, -10.25, 4.5), bevel=0.02)
    a.box("Timber", (7.6, 1.6, 1.0), (-2.0, -10.6, 9.4), bevel=0.06)
    a.box("StoneLight", (9.0, 3.4, 0.8), (-2.0, -12.0, 0.4), bevel=0.08)
    a.box("WarmGlow", (4.2, 0.5, 3.6), (6.4, -10.3, 7.2), bevel=0.04)
    a.box("WarmGlow", (4.2, 0.5, 3.6), (-9.6, -10.3, 7.2), bevel=0.04)
    # Vertical Wooden Waterwheel on +X side (radius 6.6, 8 paddles!)
    wx, wy, wz = 14.0, 0.0, 7.0
    a.cone("IronMetal", 1.2, 1.2, 3.8, (wx - 0.6, wy, wz), sides=8, rot_deg=(0, 90, 0))
    for i in range(8):
        ang = i * 45.0
        rad = math.radians(ang)
        # Spoke
        a.box("TimberDark", (0.7, 12.8, 0.8), (wx, wy, wz), bevel=0.04, rot_deg=(ang, 0, 0))
        # Outer rim paddle
        py = wy + math.cos(rad) * 6.2
        pz = wz + math.sin(rad) * 6.2
        a.box("Timber", (2.6, 1.8, 0.6), (wx, py, pz), bevel=0.04, rot_deg=(ang, 0, 0))
    return a


def build_watchtower() -> MultiPartAsset:
    a = MultiPartAsset("EM_Watchtower")
    # 16x16 base x 40H landmark tower with 6x9 front archway
    a.box("StoneDark", (16.4, 16.4, 3.2), (0, 0, 1.6), bevel=0.22)
    a.box("StoneBase", (13.6, 13.6, 26.0), (0, 0, 15.8), bevel=0.25, taper_top=(0.86, 0.86))
    # Stone quoins / accent band
    a.box("StoneLight", (13.0, 13.0, 1.6), (0, 0, 16.5), bevel=0.12)
    # Front 6W x 9H archway entrance
    a.box("DoorVoid", (6.0, 0.8, 9.0), (0, -6.75, 4.5), bevel=0.02)
    a.box("StoneLight", (7.6, 1.6, 1.2), (0, -7.0, 9.4), bevel=0.08)
    # Overhanging wooden lookout gallery (Z=28.5..32.5)
    a.box("TimberDark", (18.2, 18.2, 2.2), (0, 0, 29.2), bevel=0.12)
    # Battlement corner posts & warm lookout beacon
    for sx in (-8.2, 8.2):
        for sy in (-8.2, 8.2):
            a.box("Timber", (1.6, 1.6, 7.6), (sx, sy, 33.8), bevel=0.08)
    a.box("Timber", (18.2, 1.2, 2.4), (0, -8.4, 31.4), bevel=0.06)
    a.box("Timber", (18.2, 1.2, 2.4), (0, 8.4, 31.4), bevel=0.06)
    a.box("Timber", (1.2, 18.2, 2.4), (-8.4, 0, 31.4), bevel=0.06)
    a.box("Timber", (1.2, 18.2, 2.4), (8.4, 0, 31.4), bevel=0.06)
    a.box("WarmGlow", (3.8, 3.8, 3.4), (0, 0, 33.4), bevel=0.08)
    # Dramatic crimson pyramid spire roof (Z=36..44)
    a.cone("RoofCrimson", 13.8, 0.6, 8.8, (0, 0, 41.2), sides=4, rot_deg=(0, 0, 45))
    a.crystal("GoldTrim", 0.7, 3.2, (0, 0, 46.2), sides=6)
    return a


def build_stone_bridge() -> MultiPartAsset:
    a = MultiPartAsset("EM_StoneBridge_Large")
    # 22W x 74L arched stone bridge spanning 60-stud shallow river (aligned along Y)
    segs = 9
    length = 74.0
    width = 22.0
    for i in range(segs):
        t = (i + 0.5) / segs  # 0..1
        y = (t - 0.5) * length
        arch_z = 3.2 * math.sin(t * math.pi)
        slope_deg = math.degrees(math.atan2(3.2 * math.pi * math.cos(t * math.pi), length))
        seg_l = length / segs + 0.8
        # Roadway slab
        a.box("StoneLight", (width - 2.6, seg_l, 1.6), (0, y, arch_z + 0.8), bevel=0.10, rot_deg=(slope_deg, 0, 0))
        # Left & right stone parapets (2.4 studs above deck so camera & throwing stay clear!)
        for sx in (-width * 0.5 + 1.0, width * 0.5 - 1.0):
            a.box("StoneBase", (2.0, seg_l, 3.6), (sx, y, arch_z + 2.2), bevel=0.12, rot_deg=(slope_deg, 0, 0))
    # Heavy stone piers & corner lantern bollards
    for py in (-20.0, 20.0):
        a.box("StoneDark", (width + 1.2, 5.2, 4.0), (0, py, 0.2), bevel=0.18)
    for sx in (-width * 0.5 + 1.0, width * 0.5 - 1.0):
        for py in (-34.0, 0.0, 34.0):
            z_b = 3.2 * math.sin(((py / length) + 0.5) * math.pi)
            a.box("StoneDark", (2.8, 2.8, 5.2), (sx, py, z_b + 2.8), bevel=0.12)
            a.box("WarmGlow", (1.6, 1.6, 1.6), (sx, py, z_b + 6.0), bevel=0.06)
    return a


def build_wood_bridge() -> MultiPartAsset:
    a = MultiPartAsset("EM_WoodFootbridge_Small")
    # 16W x 66L rustic timber footbridge (aligned along Y)
    segs = 9
    length = 66.0
    width = 16.0
    for i in range(segs):
        t = (i + 0.5) / segs
        y = (t - 0.5) * length
        arch_z = 2.4 * math.sin(t * math.pi)
        slope_deg = math.degrees(math.atan2(2.4 * math.pi * math.cos(t * math.pi), length))
        seg_l = length / segs + 0.6
        a.box("Timber", (width - 1.4, seg_l, 1.1), (0, y, arch_z + 0.55), bevel=0.06, rot_deg=(slope_deg, 0, 0))
        for sx in (-width * 0.5 + 0.7, width * 0.5 - 0.7):
            a.box("TimberDark", (0.8, seg_l, 0.7), (sx, y, arch_z + 3.0), bevel=0.04, rot_deg=(slope_deg, 0, 0))
    # Support pilings & railing posts
    for py in (-28.0, -14.0, 0.0, 14.0, 28.0):
        z_b = 2.4 * math.sin(((py / length) + 0.5) * math.pi)
        for sx in (-width * 0.5 + 0.7, width * 0.5 - 0.7):
            a.box("TimberDark", (1.3, 1.3, z_b + 5.2), (sx, py, (z_b + 5.2) * 0.5 - 1.4), bevel=0.06)
            if abs(py) in (0.0, 28.0):
                a.box("WarmGlow", (1.1, 1.1, 1.2), (sx, py, z_b + 4.4), bevel=0.04)
    return a


def build_ruin_arch() -> MultiPartAsset:
    a = MultiPartAsset("EM_AncientRuinArch")
    # 22W x 8D x 19H mossy carved stone arch + jade rune keystone
    for sx in (-8.4, 8.4):
        a.box("StoneDark", (5.8, 5.8, 2.4), (sx, 0, 1.2), bevel=0.20)
        a.box("StoneBase", (4.6, 4.6, 13.6), (sx, 0, 9.0), bevel=0.22, taper_top=(0.90, 0.90))
        a.box("StoneLight", (5.6, 5.6, 1.6), (sx, 0, 16.0), bevel=0.14)
    a.box("StoneBase", (23.0, 5.8, 3.2), (0, 0, 18.0), bevel=0.24)
    a.ico("MossCap", 2.4, (-6.2, 0.6, 19.6), subdivisions=2, scale=(1.5, 0.9, 0.55), noise_amp=0.18, seed=41)
    a.ico("MossCap", 2.1, (5.8, -0.4, 19.4), subdivisions=2, scale=(1.4, 0.9, 0.50), noise_amp=0.18, seed=42)
    a.crystal("JadeGlow", 1.3, 3.6, (0, 0, 18.0), sides=6, rot_deg=(0, 0, 0))
    return a


def build_ruin_pillar() -> MultiPartAsset:
    a = MultiPartAsset("EM_AncientRuinPillar")
    a.box("StoneDark", (6.2, 6.2, 2.2), (0, 0, 1.1), bevel=0.22)
    a.box("StoneBase", (4.8, 4.8, 12.8), (0, 0, 8.4), bevel=0.24, taper_top=(0.88, 0.88))
    a.box("StoneLight", (5.4, 5.4, 1.6), (0.3, -0.2, 15.2), bevel=0.18, rot_deg=(5, -7, 12))
    a.ico("MossCap", 2.0, (0.4, 0.2, 16.2), subdivisions=2, scale=(1.1, 1.0, 0.55), noise_amp=0.18, seed=44)
    a.box("JadeGlow", (1.2, 5.1, 2.4), (0, 0, 9.6), bevel=0.06)
    return a


def build_return_portal_arch() -> MultiPartAsset:
    a = MultiPartAsset("EM_ReturnPortalArch")
    # Grand 24W x 10D x 23H portal frame (open 14W x 18H center for Roblox ReturnField!)
    a.box("StoneDark", (24.0, 10.0, 1.4), (0, 0, 0.7), bevel=0.20)
    for sx in (-9.2, 9.2):
        a.box("StoneBase", (4.6, 5.4, 19.0), (sx, 0, 10.6), bevel=0.24, taper_top=(0.86, 0.90))
        a.box("GoldTrim", (5.2, 5.8, 1.2), (sx, 0, 19.8), bevel=0.10)
        a.crystal("JadeGlow", 1.0, 3.2, (sx, 0, 22.0), sides=6)
    a.box("StoneDark", (24.4, 6.2, 3.6), (0, 0, 21.4), bevel=0.26)
    a.box("GoldTrim", (16.0, 6.6, 1.1), (0, 0, 21.4), bevel=0.08)
    a.crystal("JadeGlow", 1.8, 4.6, (0, 0, 25.0), sides=6)
    return a


def build_mossback_shrine() -> MultiPartAsset:
    a = MultiPartAsset("EM_MossbackShrine")
    # Ceremonial South Overlook monument (34W x 24D x 26H)
    a.box("StoneDark", (34.0, 24.0, 2.0), (0, 0, 1.0), bevel=0.24)
    a.box("StoneBase", (28.0, 18.0, 2.0), (0, 0, 2.8), bevel=0.20)
    # Central monolith obelisk + glowing jade heart
    a.box("StoneBase", (7.4, 7.4, 18.0), (0, 2.0, 12.4), bevel=0.28, taper_top=(0.62, 0.62))
    a.crystal("JadeGlow", 2.8, 7.6, (0, 2.0, 24.4), sides=6)
    a.box("GoldTrim", (6.2, 6.2, 1.2), (0, 2.0, 20.8), bevel=0.10)
    # Flanking guardian pillars
    for sx in (-10.8, 10.8):
        a.box("StoneLight", (4.0, 4.0, 11.5), (sx, -4.0, 9.2), bevel=0.18)
        a.box("WarmGlow", (2.0, 2.0, 2.2), (sx, -4.0, 15.8), bevel=0.08)
    a.ico("MossCap", 3.6, (-4.2, 3.6, 5.2), subdivisions=2, scale=(1.3, 1.0, 0.55), noise_amp=0.18, seed=51)
    a.ico("MossCap", 3.2, (4.8, 3.0, 5.0), subdivisions=2, scale=(1.2, 1.0, 0.55), noise_amp=0.18, seed=52)
    return a


def build_perimeter_cliff() -> MultiPartAsset:
    a = MultiPartAsset("EM_PerimeterCliff_Segment")
    # 135W x 54D x 64H dramatic tiered valley bluff replacing blocky RimWalls
    a.box("CliffRock", (134.0, 48.0, 34.0), (0, 4.0, 17.0), bevel=2.8, taper_top=(0.86, 0.78))
    a.box("StoneDark", (84.0, 38.0, 54.0), (-16.0, 10.0, 27.0), bevel=3.2, taper_top=(0.68, 0.65), rot_deg=(0, 0, 4))
    a.box("CliffRock", (74.0, 34.0, 46.0), (26.0, 8.0, 23.0), bevel=2.8, taper_top=(0.72, 0.68), rot_deg=(0, 0, -5))
    # Lush grassy cliff terrace caps!
    a.box("MossCap", (116.0, 38.0, 3.6), (0, 2.0, 34.8), bevel=1.2)
    a.box("LeafOak", (56.0, 24.0, 3.2), (-16.0, 10.0, 54.6), bevel=1.0)
    a.box("MossCap", (52.0, 22.0, 3.0), (26.0, 8.0, 46.6), bevel=1.0)
    return a


def build_moss_boulder() -> MultiPartAsset:
    a = MultiPartAsset("EM_MossBoulder_Cluster")
    a.ico("CliffRock", 5.2, (0.0, 0.0, 3.0), subdivisions=2, scale=(1.28, 1.05, 0.78), noise_amp=0.18, seed=61)
    a.ico("StoneDark", 3.4, (4.4, -2.0, 2.0), subdivisions=2, scale=(1.15, 0.95, 0.75), noise_amp=0.18, seed=62)
    a.ico("StoneBase", 2.6, (-4.2, 2.2, 1.6), subdivisions=1, scale=(1.10, 1.0, 0.72), noise_amp=0.16, seed=63)
    a.ico("MossCap", 4.0, (-0.2, 0.1, 5.2), subdivisions=2, scale=(1.18, 0.96, 0.42), noise_amp=0.16, seed=64)
    return a


def build_emerald_crystal() -> MultiPartAsset:
    a = MultiPartAsset("EM_EmeraldCrystal_Outcrop")
    a.ico("StoneDark", 4.0, (0, 0, 1.8), subdivisions=2, scale=(1.25, 1.15, 0.62), noise_amp=0.18, seed=71)
    a.crystal("JadeGlow", 1.7, 9.2, (0.0, 0.0, 5.6), sides=6, rot_deg=(6, -5, 10))
    a.crystal("JadeGlow", 1.2, 6.4, (2.2, 0.8, 4.0), sides=6, rot_deg=(18, 22, 45))
    a.crystal("JadeGlow", 1.1, 5.8, (-2.0, -1.2, 3.8), sides=6, rot_deg=(-20, -16, -30))
    a.crystal("JadeGlow", 0.85, 4.4, (0.4, -2.2, 3.0), sides=5, rot_deg=(-26, 8, 15))
    return a


def build_foliage_cluster() -> MultiPartAsset:
    a = MultiPartAsset("EM_FoliageCluster")
    a.ico("LeafOak", 2.4, (0.0, 0.0, 1.4), subdivisions=2, scale=(1.25, 1.15, 0.72), noise_amp=0.16, seed=81)
    a.ico("LeafBirch", 1.8, (2.2, 1.0, 1.1), subdivisions=1, scale=(1.15, 1.05, 0.72), noise_amp=0.16, seed=82)
    a.ico("LeafOakHi", 1.7, (-2.0, -0.8, 1.0), subdivisions=1, scale=(1.10, 1.10, 0.68), noise_amp=0.16, seed=83)
    # Wildflower pops
    for fx, fy, fz, m in [
        (0.6, -1.4, 2.6, "FlowerGold"),
        (-1.4, 1.0, 2.2, "FlowerCoral"),
        (2.4, 0.8, 2.1, "FlowerGold"),
        (-2.2, -1.2, 1.9, "FlowerCoral"),
    ]:
        a.ico(m, 0.45, (fx, fy, fz), subdivisions=1, scale=(1.0, 1.0, 0.7), noise_amp=0.05, seed=84)
    return a


def build_lantern_post() -> MultiPartAsset:
    a = MultiPartAsset("EM_LanternPost")
    # 11-stud warm road & bridge lantern post
    a.box("StoneBase", (2.0, 2.0, 1.6), (0, 0, 0.8), bevel=0.14)
    a.box("TimberDark", (0.95, 0.95, 9.6), (0, 0, 5.8), bevel=0.06)
    a.box("Timber", (0.75, 3.2, 0.75), (0, -1.2, 10.0), bevel=0.05)
    a.box("IronMetal", (1.6, 1.6, 0.5), (0, -2.4, 9.4), bevel=0.04)
    a.box("WarmGlow", (1.2, 1.2, 1.6), (0, -2.4, 8.4), bevel=0.04)
    a.box("IronMetal", (1.5, 1.5, 0.4), (0, -2.4, 7.5), bevel=0.04)
    return a


BUILDERS = [
    ("EM_OakTree_Hero", build_oak_tree, 2500),
    ("EM_PineTree_Tall", build_pine_tree, 1500),
    ("EM_BirchTree_Slender", build_birch_tree, 1800),
    ("EM_ElderOak_Landmark", build_elder_oak, 3200),
    ("EM_MeadowCottage_A", build_cottage_a, 2400),
    ("EM_MeadowWatermill_B", build_watermill_b, 2800),
    ("EM_Watchtower", build_watchtower, 2400),
    ("EM_StoneBridge_Large", build_stone_bridge, 2600),
    ("EM_WoodFootbridge_Small", build_wood_bridge, 2400),
    ("EM_AncientRuinArch", build_ruin_arch, 1600),
    ("EM_AncientRuinPillar", build_ruin_pillar, 1200),
    ("EM_ReturnPortalArch", build_return_portal_arch, 1800),
    ("EM_MossbackShrine", build_mossback_shrine, 2000),
    ("EM_PerimeterCliff_Segment", build_perimeter_cliff, 1400),
    ("EM_MossBoulder_Cluster", build_moss_boulder, 1200),
    ("EM_EmeraldCrystal_Outcrop", build_emerald_crystal, 1000),
    ("EM_FoliageCluster", build_foliage_cluster, 1000),
    ("EM_LanternPost", build_lantern_post, 800),
]


def export_glb_only(asset_name: str, objs: list[bpy.types.Object]) -> Path:
    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objs:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    glb_path = EXPORT_DIR / f"{asset_name}.glb"
    bpy.ops.export_scene.gltf(
        filepath=str(glb_path),
        use_selection=True,
        export_format="GLB",
        export_yup=True,
        export_materials="EXPORT",
        export_apply=True,
        export_animations=False,
    )
    return glb_path


def render_kit_showcase() -> Path:
    """Arrange all 18 assets in a clean 3-row Cycles studio showcase render for Visual QA."""
    common.clear_scene()
    all_objs: list[bpy.types.Object] = []
    # 3 rows (excluding giant PerimeterCliff which gets scaled 0.35x strictly for the lineup)
    positions = [
        # Row 0 (front): props & trees
        ("EM_LanternPost", (-68, -32, 0), 1.0),
        ("EM_FoliageCluster", (-52, -32, 0), 1.0),
        ("EM_MossBoulder_Cluster", (-34, -32, 0), 1.0),
        ("EM_EmeraldCrystal_Outcrop", (-16, -32, 0), 1.0),
        ("EM_BirchTree_Slender", (6, -32, 0), 1.0),
        ("EM_OakTree_Hero", (32, -32, 0), 1.0),
        ("EM_PineTree_Tall", (58, -32, 0), 1.0),
        # Row 1 (mid): architecture & ruins
        ("EM_AncientRuinPillar", (-64, 4, 0), 1.0),
        ("EM_AncientRuinArch", (-40, 4, 0), 1.0),
        ("EM_MeadowCottage_A", (-4, 4, 0), 1.0),
        ("EM_MeadowWatermill_B", (36, 4, 0), 1.0),
        ("EM_Watchtower", (70, 4, 0), 1.0),
        # Row 2 (back): hero landmarks & bridges
        ("EM_ReturnPortalArch", (-62, 52, 0), 1.0),
        ("EM_MossbackShrine", (-22, 52, 0), 1.0),
        ("EM_ElderOak_Landmark", (22, 52, 0), 1.0),
        ("EM_WoodFootbridge_Small", (68, 52, 0), 0.72),
    ]
    builder_map = {name: fn for name, fn, _ in BUILDERS}
    for name, (px, py, pz), sc in positions:
        asset = builder_map[name]()
        objs = asset.finalize_and_ground()
        for o in objs:
            o.scale = (sc, sc, sc)
            o.location = (px, py, pz)
            all_objs.append(o)
    bpy.context.view_layer.update()
    return common.setup_studio_render(
        all_objs,
        "EmeraldMeadow_Kit_QA.png",
        resolution=1280,
        samples=20,
        cam_azimuth_deg=-12.0,
        cam_elev_deg=24.0,
        distance_mult=1.55,
        add_floor=True,
    )


def main() -> None:
    extra = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    only_names = set(extra) - {"--skip-render"}
    skip_render = "--skip-render" in extra
    manifest: dict[str, dict] = json.loads(MANIFEST_PATH.read_text(encoding="utf-8")) if (only_names and MANIFEST_PATH.exists()) else {"palette": PALETTE, "assets": {}}
    for asset_name, builder_fn, tri_cap in BUILDERS:
        if only_names and asset_name not in only_names:
            continue
        common.clear_scene()
        asset = builder_fn()
        objs = asset.finalize_and_ground()
        tris = common.count_triangles(objs)
        assert tris <= tri_cap, f"{asset_name}: {tris} tris > cap {tri_cap}"
        mins, maxs = common.world_bounds(objs)
        dims = maxs - mins
        assert abs(mins.z) <= 0.05, f"{asset_name}: min_z={mins.z:.3f}"
        glb_path = export_glb_only(asset_name, objs)
        submeshes = [o.name for o in objs]
        manifest["assets"][asset_name] = {
            "glb": str(glb_path.name),
            "tris": tris,
            "size_studs": [round(dims.x, 2), round(dims.z, 2), round(dims.y, 2)],  # Roblox X, Y(up), Z
            "blender_dims": [round(dims.x, 2), round(dims.y, 2), round(dims.z, 2)],
            "submeshes": submeshes,
        }
        print(
            f"[KIT] {asset_name:28s} | tris={tris:4d}/{tri_cap:4d} | "
            f"studs=({dims.x:5.1f}W x {dims.y:5.1f}D x {dims.z:5.1f}H) | parts={len(submeshes)}"
        )

    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"Wrote manifest: {MANIFEST_PATH} ({len(manifest['assets'])} assets)")
    if not skip_render:
        qa_png = render_kit_showcase()
        print(f"Rendered Kit QA showcase: {qa_png}")


if __name__ == "__main__":
    main()
