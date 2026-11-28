"""Gate 3 Final Stylized Low-Poly Mob & Projectile Kit for Emerald Meadow 10x.

Builds all 10 Emerald Meadow mobs (5 Base Archetypes + 5 Natural Area Elites)
plus 4 ballistic projectile meshes following game/assets/STYLE_GUIDE.md:
  Base Mobs:   MossSlime, RiverSnapper, BrambleBoar, MeadowWitch, RuinSentinel
  Elite Mobs:  ElderMossSlime, TidecrestSnapper, ThornbackAlpha, CovenArchWitch, AncientWarden
  Projectiles: Proj_SporeGlob, Proj_AquaGlob, Proj_ArcaneHexOrb, Proj_RuneBoulder

Each mob is exported as:
  1. Multi-submesh material-split GLB (`EM_Mob_<Name>.glb`) where every submesh is named
     `<Name>__<Role>__<PalKey>` so Roblox Studio imports crisp per-part PBR materials
     and wires 60 FPS Motor6D animation joints cleanly.
  2. Rigged FBX (`EM_Mob_<Name>_Rigged.fbx`) with 24 FPS NLA clips (`Idle`, `Walk`, `Attack`).
  3. Complete metadata manifest (`game/assets/exports/emerald_meadow_mobs_manifest.json`).
  4. Studio QA preview renders (`EmeraldMeadow_Mobs_Final_QA.png` & `EmeraldMeadow_Projectiles_QA.png`).

Run via:
    python scripts/blender_run.py game/assets/blender/emerald_meadow_mobs_kit.py
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

import _common as C  # noqa: E402

EXPORT_DIR = C.EXPORT_DIR
RENDER_DIR = C.RENDER_DIR
MANIFEST_PATH = EXPORT_DIR / "emerald_meadow_mobs_manifest.json"


PALETTE: dict[str, dict] = {
    "SlimeGreen":    {"srgb": (64, 198, 92),   "rough": 0.28, "metal": 0.0,  "em": 0.0, "rbx_mat": "SmoothPlastic"},
    "SlimeDeep":     {"srgb": (30, 136, 66),   "rough": 0.24, "metal": 0.0,  "em": 0.0, "rbx_mat": "SmoothPlastic"},
    "MossLeaf":      {"srgb": (54, 152, 68),   "rough": 0.72, "metal": 0.0,  "em": 0.0, "rbx_mat": "Grass"},
    "MossBright":    {"srgb": (96, 214, 98),   "rough": 0.62, "metal": 0.0,  "em": 0.0, "rbx_mat": "Grass"},
    "JadeGlow":      {"srgb": (34, 238, 128),  "rough": 0.14, "metal": 0.0,  "em": 2.3, "rbx_mat": "Neon"},
    "GoldMetal":     {"srgb": (240, 194, 58),  "rough": 0.26, "metal": 0.88, "em": 0.0, "rbx_mat": "Metal"},
    "LotusPetal":    {"srgb": (246, 214, 96),  "rough": 0.42, "metal": 0.0,  "em": 0.3, "rbx_mat": "SmoothPlastic"},
    "SnapperTeal":   {"srgb": (46, 136, 128),  "rough": 0.48, "metal": 0.0,  "em": 0.0, "rbx_mat": "SmoothPlastic"},
    "SnapperDeep":   {"srgb": (26, 86, 90),    "rough": 0.56, "metal": 0.0,  "em": 0.0, "rbx_mat": "SmoothPlastic"},
    "SnapperBelly":  {"srgb": (218, 214, 182), "rough": 0.66, "metal": 0.0,  "em": 0.0, "rbx_mat": "SmoothPlastic"},
    "AquaGlow":      {"srgb": (56, 224, 248),  "rough": 0.16, "metal": 0.0,  "em": 2.2, "rbx_mat": "Neon"},
    "BoarHide":      {"srgb": (108, 70, 48),   "rough": 0.78, "metal": 0.0,  "em": 0.0, "rbx_mat": "Fabric"},
    "BoarDark":      {"srgb": (68, 44, 32),    "rough": 0.84, "metal": 0.0,  "em": 0.0, "rbx_mat": "Fabric"},
    "Ivory":         {"srgb": (236, 228, 206), "rough": 0.42, "metal": 0.0,  "em": 0.0, "rbx_mat": "SmoothPlastic"},
    "AmberGlow":     {"srgb": (255, 190, 48),  "rough": 0.16, "metal": 0.0,  "em": 2.1, "rbx_mat": "Neon"},
    "WitchCloak":    {"srgb": (42, 78, 62),    "rough": 0.76, "metal": 0.0,  "em": 0.0, "rbx_mat": "Fabric"},
    "WitchPlum":     {"srgb": (86, 44, 100),   "rough": 0.68, "metal": 0.0,  "em": 0.0, "rbx_mat": "Fabric"},
    "WitchCrimson":  {"srgb": (176, 46, 52),   "rough": 0.58, "metal": 0.0,  "em": 0.0, "rbx_mat": "Fabric"},
    "WitchSkin":     {"srgb": (196, 216, 192), "rough": 0.58, "metal": 0.0,  "em": 0.0, "rbx_mat": "SmoothPlastic"},
    "StaffWood":     {"srgb": (92, 58, 36),    "rough": 0.80, "metal": 0.0,  "em": 0.0, "rbx_mat": "Wood"},
    "HexGlow":       {"srgb": (198, 72, 255),  "rough": 0.14, "metal": 0.0,  "em": 2.5, "rbx_mat": "Neon"},
    "StoneBase":     {"srgb": (96, 108, 100),  "rough": 0.84, "metal": 0.0,  "em": 0.0, "rbx_mat": "Cobblestone"},
    "StoneDark":     {"srgb": (56, 64, 60),    "rough": 0.88, "metal": 0.0,  "em": 0.0, "rbx_mat": "Rock"},
    "StoneObsidian": {"srgb": (40, 44, 52),    "rough": 0.74, "metal": 0.0,  "em": 0.0, "rbx_mat": "Slate"},
    "EyeDark":       {"srgb": (18, 20, 24),    "rough": 0.08, "metal": 0.0,  "em": 0.0, "rbx_mat": "Glass"},
    "EyeWhite":      {"srgb": (255, 255, 255), "rough": 0.08, "metal": 0.0,  "em": 0.9, "rbx_mat": "Neon"},
}


def srgb_to_lin(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def make_pal_mat(key: str) -> bpy.types.Material:
    spec = PALETTE[key]
    lin = tuple(srgb_to_lin(v / 255.0) for v in spec["srgb"])
    return C.make_material(
        f"EMMobMat_{key}",
        lin,
        roughness=spec["rough"],
        metallic=spec["metal"],
        emission=lin if spec["em"] > 0.0 else None,
        emission_strength=spec["em"],
    )


class RoleAsset:
    """Collects geometry keyed by (role, mat_key) for crisp Roblox MeshParts + Motor6D animation."""

    def __init__(self, asset_name: str, anim_style: str) -> None:
        self.asset_name = asset_name
        self.anim_style = anim_style
        self.bms: dict[tuple[str, str], bmesh.types.BMesh] = {}

    def bm(self, role: str, mat_key: str) -> bmesh.types.BMesh:
        k = (role, mat_key)
        if k not in self.bms:
            self.bms[k] = bmesh.new()
        return self.bms[k]

    def box(
        self, role: str, mat_key: str,
        size: tuple[float, float, float], center: tuple[float, float, float],
        bevel: float = 0.08, rot_deg: tuple[float, float, float] = (0, 0, 0),
        taper_top: tuple[float, float] = (1.0, 1.0),
    ) -> None:
        C.add_faceted_box(self.bm(role, mat_key), size, center, 0, bevel=bevel, rot_deg=rot_deg, taper_top=taper_top)

    def ico(
        self, role: str, mat_key: str,
        radius: float, center: tuple[float, float, float],
        subdivisions: int = 2, scale: tuple[float, float, float] = (1, 1, 1),
        rot_deg: tuple[float, float, float] = (0, 0, 0), noise_amp: float = 0.0, seed: int = 1,
    ) -> None:
        C.add_faceted_icosphere(
            self.bm(role, mat_key), radius, center, 0,
            subdivisions=subdivisions, scale=scale, rot_deg=rot_deg, noise_amp=noise_amp, seed=seed,
        )

    def crystal(
        self, role: str, mat_key: str,
        radius: float, height: float, center: tuple[float, float, float],
        sides: int = 6, rot_deg: tuple[float, float, float] = (0, 0, 0),
    ) -> None:
        C.add_crystal_prism(self.bm(role, mat_key), radius, height, center, 0, sides=sides, rot_deg=rot_deg)

    def loft(
        self, role: str, mat_key: str,
        rings: list[tuple[tuple[float, float, float], float, float, tuple[float, float, float]]],
        sides: int = 8, smooth: bool = False,
    ) -> None:
        C.add_lofted_tube(self.bm(role, mat_key), rings, 0, sides=sides, smooth=smooth)

    def lathe(
        self, role: str, mat_key: str,
        profile: list[tuple[float, float]], segments: int = 16,
        center: tuple[float, float, float] = (0, 0, 0),
        scale_xy: tuple[float, float] = (1, 1), smooth: bool = True,
    ) -> None:
        C.add_lathe_shell(self.bm(role, mat_key), profile, 0, segments=segments, center=center, scale_xy=scale_xy, smooth=smooth)

    def cone(
        self, role: str, mat_key: str,
        r1: float, r2: float, depth: float, center: tuple[float, float, float],
        sides: int = 8, rot_deg: tuple[float, float, float] = (0, 0, 0), smooth: bool = False,
    ) -> None:
        bm = self.bm(role, mat_key)
        ret = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=sides, radius1=r1, radius2=r2, depth=depth)
        verts = ret["verts"]
        rot = Euler(tuple(math.radians(a) for a in rot_deg), "XYZ").to_matrix().to_4x4()
        bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector(center)) @ rot, verts=verts)
        for f in {f for v in verts for f in v.link_faces}:
            f.material_index = 0
            f.smooth = smooth

    def ring(
        self, role: str, mat_key: str,
        radius: float, radial_thick: float, axial_w: float,
        center: tuple[float, float, float], segments: int = 12,
        rot_deg: tuple[float, float, float] = (0, 0, 0),
    ) -> None:
        bm = self.bm(role, mat_key)
        verts = C.add_closed_ring(bm, radius, radial_thick, axial_w, 0, rot_deg=rot_deg, segments=segments)
        bmesh.ops.translate(bm, verts=verts, vec=Vector(center))

    def eye(self, role: str, pos: tuple[float, float, float], radius: float) -> None:
        x, y, z = pos
        self.ico(role, "EyeDark", radius, (x, y, z), subdivisions=2, scale=(1.0, 0.65, 1.12))
        self.ico(role, "EyeWhite", radius * 0.34, (x + radius * 0.28, y - radius * 0.56, z + radius * 0.34), subdivisions=1)

    def finalize(self, target_h: float, pivot_mode: str = "floor") -> tuple[list[bpy.types.Object], Vector]:
        objs: list[bpy.types.Object] = []
        for (role, mat_key), bm in self.bms.items():
            mat = make_pal_mat(mat_key)
            obj = C.finalize_mesh(f"{self.asset_name}__{role}__{mat_key}", bm, [mat])
            objs.append(obj)
        mins, maxs = C.world_bounds(objs)
        cx = (mins.x + maxs.x) * 0.5
        cy = (mins.y + maxs.y) * 0.5
        cur_h = max(1e-4, maxs.z - mins.z)
        sc = target_h / cur_h
        z_ref = mins.z if pivot_mode == "floor" else (mins.z + maxs.z) * 0.5
        for obj in objs:
            for v in obj.data.vertices:
                v.co.x = (v.co.x - cx) * sc
                v.co.y = (v.co.y - cy) * sc
                v.co.z = (v.co.z - z_ref) * sc
            obj.data.update()
        mins2, maxs2 = C.world_bounds(objs)
        return objs, (maxs2 - mins2)


# =============================================================================
# 10 FINAL EMERALD MEADOW MOBS (5 BASE + 5 NATURAL AREA ELITES)
# =============================================================================
def build_slime(elite: bool) -> tuple[RoleAsset, float]:
    name = "ElderMossSlime" if elite else "MossSlime"
    a = RoleAsset(name, "MeadowSlime")
    body = "SlimeDeep" if elite else "SlimeGreen"
    profile = [
        (0.05, 0.00), (1.42, 0.06), (1.68, 0.45), (1.72, 1.05),
        (1.50, 1.72), (1.06, 2.26), (0.54, 2.54), (0.06, 2.62),
    ]
    a.lathe("Body", body, profile, segments=16, scale_xy=(1.04, 1.0), smooth=True)
    # Subtle jelly blush & mossy feet
    for sx in (-1.05, 1.05):
        for sy in (-1.02, 0.95):
            a.ico("Legs", "MossLeaf", 0.42, (sx, sy, 0.25), subdivisions=2, scale=(1.22, 1.18, 0.65), noise_amp=0.10, seed=int(abs(sx * 10 + sy)))
    for sx in (-0.64, 0.64):
        a.eye("Body", (sx, -1.54, 1.20), 0.34)
    # Leaf crown
    count = 6 if elite else 4
    for i in range(count):
        ang = i * (360.0 / count) + 18.0
        rad = math.radians(ang)
        a.box("Crown", "MossBright" if elite else "MossLeaf", (0.92, 0.58, 0.26),
              (math.cos(rad) * 0.62, math.sin(rad) * 0.62, 2.52), bevel=0.06, rot_deg=(18.0, 0.0, ang), taper_top=(0.72, 0.72))
    if not elite:
        a.cone("Crown", "MossLeaf", 0.12, 0.08, 0.66, (0.0, 0.0, 2.86), sides=6)
        a.box("Crown", "MossBright", (0.74, 0.38, 0.14), (-0.36, 0.0, 3.16), bevel=0.04, rot_deg=(0, 24, 0))
        a.box("Crown", "MossBright", (0.74, 0.38, 0.14), (0.36, 0.0, 3.16), bevel=0.04, rot_deg=(0, -24, 0))
    else:
        for i in range(6):
            ang = i * 60.0
            rad = math.radians(ang)
            a.box("Crown", "LotusPetal", (0.58, 0.95, 0.18),
                  (math.cos(rad) * 0.68, math.sin(rad) * 0.68, 2.74), bevel=0.04, rot_deg=(36.0, 0.0, ang - 90.0), taper_top=(0.55, 0.9))
        a.crystal("Crown", "JadeGlow", 0.36, 1.18, (0.0, 0.0, 3.14), sides=6)
        a.ring("Crown", "GoldMetal", 0.56, 0.12, 0.18, (0.0, 0.0, 2.62), segments=12)
        for i in range(3):
            ang = math.radians(i * 120.0 + 30.0)
            a.ico("Orbit", "StoneBase", 0.34, (math.cos(ang) * 2.08, math.sin(ang) * 2.08, 1.45), subdivisions=1, scale=(1.1, 0.95, 0.85), noise_amp=0.12, seed=i + 3)
            a.crystal("Orbit", "JadeGlow", 0.14, 0.44, (math.cos(ang) * 2.08, math.sin(ang) * 2.08, 1.78), sides=5)
    return a, (4.20 if elite else 3.20)


def build_snapper(elite: bool) -> tuple[RoleAsset, float]:
    name = "TidecrestSnapper" if elite else "RiverSnapper"
    a = RoleAsset(name, "MeadowSnapper")
    skin = "SnapperDeep" if elite else "SnapperTeal"
    # Sculpted amphibian torso
    a.loft("Body", skin, [
        ((0.0, -2.05, 1.25), 1.04, 0.68, (90, 0, 0)),
        ((0.0, -1.15, 1.42), 1.46, 0.98, (90, 0, 0)),
        ((0.0, 0.10, 1.46), 1.54, 1.08, (90, 0, 0)),
        ((0.0, 1.35, 1.18), 1.08, 0.78, (90, 0, 0)),
    ], sides=8)
    # Articulated wagging tail
    a.loft("Tail", skin, [
        ((0.0, 1.25, 1.15), 0.96, 0.68, (90, 0, 0)),
        ((0.0, 2.35, 0.86), 0.52, 0.44, (90, 0, 0)),
        ((0.0, 3.15, 0.72), 0.18, 0.24, (90, 0, 0)),
    ], sides=7)
    a.box("Body", "SnapperBelly", (2.05, 2.55, 0.64), (0.0, -0.2, 0.78), bevel=0.14)
    # Upper snout + articulated lower jaw + teeth
    a.box("Head", skin, (2.28, 1.38, 0.64), (0.0, -2.05, 1.54), bevel=0.12, taper_top=(0.82, 0.88))
    a.box("Jaw", "SnapperBelly", (2.08, 1.26, 0.44), (0.0, -2.00, 0.92), bevel=0.08)
    for sx in (-0.75, -0.25, 0.25, 0.75):
        a.crystal("Head", "Ivory", 0.11, 0.34, (sx, -2.52, 1.18), sides=4, rot_deg=(180, 0, 0))
    # Glowing aqua spit cheek sacs
    sac_r = 0.54 if elite else 0.42
    for sx in (-1.34, 1.34):
        a.ico("Head", "AquaGlow", sac_r, (sx, -1.25, 1.32), subdivisions=2, scale=(0.85, 1.15, 0.95))
    # Eyes + brow ridges
    for sx in (-0.78, 0.78):
        a.ico("Head", "AmberGlow", 0.28, (sx, -1.94, 1.92), subdivisions=1, scale=(0.95, 0.8, 0.95))
        a.box("Head", skin, (0.58, 0.44, 0.16), (sx, -1.84, 2.18), bevel=0.04, rot_deg=(0, 14 if sx < 0 else -14, 0))
    # 4 sturdy webbed legs
    for sx in (-1.32, 1.32):
        for sy in (-0.95, 1.05):
            a.box("Legs", skin, (0.68, 0.78, 1.18), (sx, sy, 0.62), bevel=0.10, rot_deg=(0, 12 if sx < 0 else -12, 0))
            a.box("Legs", "SnapperDeep", (0.86, 1.02, 0.28), (sx * 1.05, sy - 0.14, 0.14), bevel=0.05)
    # Dorsal ridge / Elite Aqua Sail-Fin + Slate Armor + Gold Horns
    if not elite:
        for idx, sy in enumerate((-1.1, -0.2, 0.7, 1.6)):
            h = 0.85 - idx * 0.10
            a.box("Body", "MossBright", (0.24, 0.62, h), (0.0, sy, 2.42 - idx * 0.16), bevel=0.04, taper_top=(0.3, 0.6))
    else:
        for idx, sy in enumerate((-1.2, -0.3, 0.6, 1.5, 2.3)):
            h = 1.65 - abs(idx - 1.5) * 0.24
            role_fin = "Tail" if sy >= 1.5 else "Body"
            a.box(role_fin, "AquaGlow", (0.26, 0.78, h), (0.0, sy, 2.65 - idx * 0.16), bevel=0.04, taper_top=(0.25, 0.55))
            if idx < 3:
                a.box("Body", "StoneDark", (2.10, 0.85, 0.36), (0.0, sy, 2.25 - idx * 0.08), bevel=0.08)
        for sx in (-1.05, 1.05):
            a.crystal("Head", "GoldMetal", 0.22, 0.96, (sx, -1.65, 2.42), sides=5, rot_deg=(-38, -22 if sx < 0 else 22, 0))
    return a, (4.00 if elite else 3.10)


def build_boar(elite: bool) -> tuple[RoleAsset, float]:
    name = "ThornbackAlpha" if elite else "BrambleBoar"
    a = RoleAsset(name, "MeadowBoar")
    hide = "BoarDark" if elite else "BoarHide"
    # Charging barrel body
    a.loft("Body", hide, [
        ((0.0, -1.25, 1.98), 1.38, 1.26, (90, 0, 0)),
        ((0.0, 0.05, 2.02), 1.48, 1.34, (90, 0, 0)),
        ((0.0, 1.45, 1.88), 1.24, 1.15, (90, 0, 0)),
        ((0.0, 2.25, 1.66), 0.74, 0.70, (90, 0, 0)),
    ], sides=8)
    # Articulated charging head + snout + tusks + ears + eyes
    a.loft("Head", hide, [
        ((0.0, -2.10, 1.72), 0.82, 0.76, (90, 0, 0)),
        ((0.0, -1.15, 1.98), 1.28, 1.18, (90, 0, 0)),
    ], sides=8)
    a.box("Head", "BoarHide", (1.18, 0.56, 0.86), (0.0, -2.36, 1.56), bevel=0.10)
    tusk_s = 1.42 if elite else 1.0
    tusk_mat = "GoldMetal" if elite else "Ivory"
    for sx in (-1.0, 1.0):
        a.loft("Head", tusk_mat, [
            ((sx * 0.72, -1.95, 1.38), 0.22 * tusk_s, 0.22 * tusk_s, (75, sx * 20, 0)),
            ((sx * 1.18, -2.42, 1.62), 0.16 * tusk_s, 0.16 * tusk_s, (45, sx * 30, 0)),
            ((sx * 1.38, -2.55, 2.38 * (1.12 if elite else 1.0)), 0.05 * tusk_s, 0.05 * tusk_s, (10, sx * 25, 0)),
        ], sides=6)
    for sx in (-0.95, 0.95):
        a.crystal("Head", hide, 0.34, 0.92, (sx, -1.35, 2.95), sides=4, rot_deg=(12, -24 if sx < 0 else 24, 0))
        a.box("Head", "AmberGlow", (0.30, 0.26, 0.24), (sx * 0.88, -1.86, 2.08), bevel=0.04)
    # 4 legs + dark hooves
    for sx in (-0.92, 0.92):
        for sy in (-1.05, 1.25):
            a.box("Legs", hide, (0.64, 0.72, 1.28), (sx, sy, 0.72), bevel=0.08)
            a.box("Legs", "StoneDark", (0.72, 0.80, 0.36), (sx, sy - 0.04, 0.18), bevel=0.05)
    # Dorsal mossy bramble pad + crystals
    a.box("Body", "MossLeaf", (1.85, 2.75, 0.56), (0.0, 0.05, 3.22), bevel=0.12)
    if not elite:
        for sy, h in ((-0.75, 0.75), (0.15, 0.95), (0.95, 0.70)):
            a.crystal("Body", "JadeGlow" if sy == 0.15 else "MossBright", 0.22, h, (0.0, sy, 3.55), sides=5, rot_deg=(-12, 0, 0))
    else:
        a.box("Body", "StoneBase", (2.75, 1.75, 1.28), (0.0, -0.65, 2.95), bevel=0.18, taper_top=(0.86, 0.85))
        for sy, h, sx_off in ((-1.10, 1.35, 0.0), (-0.30, 1.55, 0.0), (0.55, 1.25, 0.0), (-0.70, 1.05, -0.88), (-0.70, 1.05, 0.88)):
            a.crystal("Body", "JadeGlow", 0.26, h, (sx_off, sy, 3.85 if sx_off == 0 else 3.55),
                      sides=5, rot_deg=(-14, -18 if sx_off < 0 else (18 if sx_off > 0 else 0), 0))
    return a, (4.80 if elite else 3.80)


def build_witch(elite: bool) -> tuple[RoleAsset, float]:
    name = "CovenArchWitch" if elite else "MeadowWitch"
    a = RoleAsset(name, "MeadowWitch")
    cloak = "WitchPlum" if elite else "WitchCloak"
    hat = "WitchCrimson" if elite else "WitchCloak"
    # Flared skirt & torso
    a.cone("Body", cloak, 1.38 if elite else 1.18, 0.62, 2.85, (0.0, 0.0, 1.48), sides=10)
    a.box("Body", "WitchCloak", (1.52, 1.05, 1.32), (0.0, 0.0, 3.10), bevel=0.14, taper_top=(0.88, 0.88))
    if elite:
        for sx in (-0.98, 0.98):
            a.box("Body", "WitchCrimson", (0.72, 1.15, 0.56), (sx, 0.0, 3.62), bevel=0.08, rot_deg=(0, 22 if sx < 0 else -22, 0))
        for i in range(4):
            ang = math.radians(i * 90.0 + 45.0)
            a.crystal("Orbit", "JadeGlow", 0.14, 0.48, (math.cos(ang) * 1.18, math.sin(ang) * 1.18, 3.92), sides=4)
    # Head + crooked pointed witch hat + gold band
    a.ico("Head", "WitchSkin", 0.62, (0.0, -0.05, 4.18), subdivisions=2, scale=(0.95, 0.92, 1.02))
    for sx in (-0.24, 0.24):
        a.ico("Head", "HexGlow" if elite else "JadeGlow", 0.13, (sx, -0.58, 4.24), subdivisions=1)
    a.cone("Head", hat, 1.65 if elite else 1.42, 1.25 if elite else 1.05, 0.24, (0.0, -0.05, 4.62), sides=10)
    a.ring("Head", "GoldMetal", 0.74, 0.12, 0.24, (0.0, -0.02, 4.78), segments=10)
    a.cone("Head", hat, 0.74, 0.34, 1.05, (0.0, 0.02, 5.18), sides=8, rot_deg=(-8, 10, 0))
    a.cone("Head", hat, 0.36, 0.06, 0.82 if elite else 0.62, (0.24, 0.22, 5.90 if elite else 5.80), sides=7, rot_deg=(-22, 24, 0))
    if elite:
        a.crystal("Head", "GoldMetal", 0.18, 0.52, (0.48, 0.38, 6.22), sides=5, rot_deg=(-20, 20, 0))
    # Left off-hand sleeve
    a.box("Body", cloak, (0.46, 0.50, 1.32), (-0.98, -0.18, 2.95), bevel=0.06, rot_deg=(24, 0, -14))
    # Right casting arm + gnarled staff + glowing ballistic hex orb!
    a.box("Staff", cloak, (0.48, 0.52, 1.38), (0.98, -0.45, 3.08), bevel=0.06, rot_deg=(54, 0, 12))
    a.cone("Staff", "StaffWood", 0.14, 0.10, 4.65, (1.28, -0.92, 2.45), sides=6, rot_deg=(8, -4, 0))
    orb_r = 0.56 if elite else 0.42
    a.ico("Staff", "HexGlow", orb_r, (1.36, -1.16, 4.92), subdivisions=2)
    if elite:
        for sx in (-0.42, 0.42):
            a.crystal("Staff", "GoldMetal", 0.14, 0.85, (1.36 + sx, -1.16, 4.82), sides=5, rot_deg=(0, -24 if sx < 0 else 24, 0))
    return a, (6.10 if elite else 5.60)


def build_sentinel(elite: bool) -> tuple[RoleAsset, float]:
    name = "AncientWarden" if elite else "RuinSentinel"
    a = RoleAsset(name, "MeadowSentinel")
    stone = "StoneObsidian" if elite else "StoneBase"
    trim = "GoldMetal" if elite else "StoneDark"
    # Stout carved stone legs
    for sx in (-0.82, 0.82):
        a.box("Legs", "StoneDark", (0.96, 1.08, 1.95), (sx, 0.0, 0.98), bevel=0.10, taper_top=(0.88, 0.88))
        a.box("Legs", stone, (1.12, 1.32, 0.45), (sx, -0.10, 0.22), bevel=0.08)
    # Monolith torso + glowing jade chest crystal
    a.box("Body", stone, (2.45, 1.75, 2.35), (0.0, 0.0, 3.05), bevel=0.20, taper_top=(1.15, 1.08))
    a.crystal("Body", "JadeGlow", 0.56 if elite else 0.42, 1.28, (0.0, -0.88, 3.12), sides=6, rot_deg=(90, 0, 0))
    a.box("Body", trim, (2.60, 0.42, 0.34), (0.0, -0.78, 2.08), bevel=0.06)
    # Heavy stone arms + moss pauldrons
    for sx in (-1.78, 1.78):
        a.box("Arms", stone, (1.35, 1.55, 1.18), (sx, 0.0, 4.18), bevel=0.16)
        a.ico("Arms", "MossLeaf", 0.65, (sx, 0.12, 4.78), subdivisions=1, scale=(1.2, 1.0, 0.55), noise_amp=0.12, seed=2)
        a.box("Arms", "StoneDark", (0.96, 1.05, 2.15), (sx * 1.06, -0.18, 2.55), bevel=0.12)
        a.box("Arms", trim if elite else stone, (1.14, 1.24, 0.92), (sx * 1.08, -0.28, 1.32), bevel=0.12)
    # Carved stone head + jade visor + Elite crown & floating shoulder pylons
    a.box("Head", stone, (1.42, 1.32, 1.18), (0.0, -0.12, 4.88), bevel=0.14)
    a.box("Head", "JadeGlow", (1.05, 0.28, 0.28), (0.0, -0.78, 4.92), bevel=0.03)
    if elite:
        a.box("Head", "GoldMetal", (1.72, 1.42, 0.36), (0.0, -0.05, 5.56), bevel=0.06)
        for sx in (-0.65, 0.65):
            a.crystal("Head", "GoldMetal", 0.24, 1.05, (sx, 0.0, 6.08), sides=5, rot_deg=(-12, -16 if sx < 0 else 16, 0))
        for sx in (-2.55, 2.55):
            a.crystal("Orbit", "JadeGlow", 0.34, 1.55, (sx, 0.15, 5.35), sides=6)
            a.box("Orbit", "GoldMetal", (0.58, 0.58, 0.36), (sx, 0.15, 4.42), bevel=0.05)
    return a, (6.80 if elite else 6.00)


# =============================================================================
# 4 BALLISTIC PROJECTILES (CENTER-PIVOT)
# =============================================================================
def build_projectile(proj_id: str) -> tuple[RoleAsset, float]:
    a = RoleAsset(proj_id, "Projectile")
    if proj_id == "Proj_SporeGlob":
        a.ico("Core", "SlimeGreen", 0.85, (0, 0, 0), subdivisions=2, noise_amp=0.16, seed=7)
        for i in range(4):
            ang = math.radians(i * 90)
            a.crystal("Core", "JadeGlow", 0.22, 0.65, (math.cos(ang) * 0.72, math.sin(ang) * 0.72, 0.0), sides=5, rot_deg=(0, 90, i * 90))
        return a, 1.8
    elif proj_id == "Proj_AquaGlob":
        a.ico("Core", "AquaGlow", 0.80, (0, 0, 0), subdivisions=2, scale=(1.0, 1.25, 1.0), noise_amp=0.12, seed=9)
        a.ring("Core", "SnapperTeal", 0.88, 0.16, 0.22, (0, 0, 0), segments=10, rot_deg=(90, 0, 0))
        return a, 1.8
    elif proj_id == "Proj_ArcaneHexOrb":
        a.ico("Core", "HexGlow", 0.88, (0, 0, 0), subdivisions=2)
        a.ring("Core", "GoldMetal", 1.15, 0.14, 0.18, (0, 0, 0), segments=12, rot_deg=(35, 25, 0))
        a.ring("Core", "JadeGlow", 1.15, 0.12, 0.16, (0, 0, 0), segments=12, rot_deg=(-35, -25, 0))
        return a, 2.2
    else:  # Proj_RuneBoulder
        a.ico("Core", "StoneDark", 1.35, (0, 0, 0), subdivisions=2, noise_amp=0.20, seed=13)
        for sx in (-1.0, 1.0):
            a.crystal("Core", "JadeGlow", 0.34, 1.15, (sx * 0.95, 0.0, 0.45), sides=5, rot_deg=(20, sx * 42, 0))
        a.ico("Core", "MossLeaf", 0.65, (0.0, 0.45, 0.95), subdivisions=1, scale=(1.3, 1.0, 0.55))
        return a, 3.0


# =============================================================================
# RIGGED FBX EXPORT (ARMATURE + 24 FPS NLA CLIPS)
# =============================================================================
def build_rig_and_export_fbx(asset_name: str, objs: list[bpy.types.Object], dims: Vector) -> Path:
    """Attach a clean bone hierarchy + 24 FPS Idle/Walk/Attack NLA clips and export rigged FBX."""
    arm_data = bpy.data.armatures.new(f"{asset_name}_Armature")
    arm_obj = bpy.data.objects.new(asset_name, arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones

    h = max(dims.z, 1.0)
    root = eb.new("HumanoidRootPart")
    root.head, root.tail = Vector((0, 0, 0)), Vector((0, 0, h * 0.25))

    roles = sorted({obj.name.split("__")[1] for obj in objs})
    bone_objs: dict[str, bpy.types.EditBone] = {"HumanoidRootPart": root}
    for role in roles:
        b = eb.new(role)
        b.parent = root
        if role in ("Legs",):
            b.head, b.tail = Vector((0, 0, h * 0.25)), Vector((0, 0, 0.05))
        elif role in ("Head", "Crown", "Orbit"):
            b.head, b.tail = Vector((0, 0, h * 0.68)), Vector((0, 0, h * 0.98))
        elif role in ("Staff", "Arms"):
            b.head, b.tail = Vector((0, -0.1, h * 0.56)), Vector((0, -0.3, h * 0.25))
        else:
            b.head, b.tail = Vector((0, 0, h * 0.30)), Vector((0, 0, h * 0.72))
        bone_objs[role] = b
    bpy.ops.object.mode_set(mode="OBJECT")

    for obj in objs:
        role = obj.name.split("__")[1]
        obj.vertex_groups.clear()
        vg = obj.vertex_groups.new(name=role)
        vg.add(range(len(obj.data.vertices)), 1.0, "REPLACE")
        mod = obj.modifiers.new(name="Armature", type="ARMATURE")
        mod.object = arm_obj
        obj.parent = arm_obj

    def make_clip(clip_name: str, end_f: int, keys: list[tuple[int, dict[str, tuple[tuple[float, float, float], tuple[float, float, float]]]]]) -> None:
        anim = arm_obj.animation_data or arm_obj.animation_data_create()
        act = bpy.data.actions.new(name=clip_name)
        anim.action = act
        for frame, data in keys:
            for pb in arm_obj.pose.bones:
                pb.rotation_mode = "XYZ"
                loc, rot = data.get(pb.name, ((0.0, 0.0, 0.0), (0.0, 0.0, 0.0)))
                pb.location = Vector(loc)
                pb.rotation_euler = Euler(tuple(math.radians(a) for a in rot), "XYZ")
                pb.keyframe_insert(data_path="location", frame=frame)
                pb.keyframe_insert(data_path="rotation_euler", frame=frame)
        C.push_action_to_nla(arm_obj, act, clip_name, end_f)

    make_clip("Idle", 36, [
        (1, {}),
        (18, {"Body": ((0, 0, 0.08), (3, 0, 2)), "Head": ((0, 0, 0), (-3, 5, 0)), "Orbit": ((0, 0, 0.12), (0, 0, 180))}),
        (36, {"Orbit": ((0, 0, 0), (0, 0, 360))}),
    ])
    make_clip("Walk", 24, [
        (1, {"Body": ((0, 0, 0.18), (8, 0, 5)), "Legs": ((0, 0, 0.08), (-14, 0, 0)), "Arms": ((0, 0, 0), (16, 0, 0))}),
        (12, {"Body": ((0, 0, 0.18), (8, 0, -5)), "Legs": ((0, 0, 0.08), (14, 0, 0)), "Arms": ((0, 0, 0), (-16, 0, 0))}),
        (24, {"Body": ((0, 0, 0.18), (8, 0, 5)), "Legs": ((0, 0, 0.08), (-14, 0, 0)), "Arms": ((0, 0, 0), (16, 0, 0))}),
    ])
    make_clip("Attack", 18, [
        (1, {}),
        (6, {"Body": ((0, 0.25, 0.12), (-16, 0, 0)), "Staff": ((0, 0, 0.25), (-45, 0, 0)), "Arms": ((0, 0, 0), (-55, 0, 0))}),
        (11, {"Body": ((0, -0.55, 0.0), (24, 0, 0)), "Staff": ((0, 0, 0), (38, 0, 0)), "Arms": ((0, 0, 0), (42, 0, 0))}),
        (18, {}),
    ])
    C.reset_pose(arm_obj)

    bpy.ops.object.select_all(action="DESELECT")
    arm_obj.select_set(True)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = arm_obj
    fbx_path = EXPORT_DIR / f"EM_Mob_{asset_name}_Rigged.fbx"
    bpy.ops.export_scene.fbx(
        filepath=str(fbx_path),
        use_selection=True,
        global_scale=1.0,
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_ALL",
        axis_forward="-Z",
        axis_up="Y",
        object_types={"ARMATURE", "MESH"},
        use_armature_deform_only=True,
        add_leaf_bones=False,
        bake_anim=True,
        bake_anim_use_nla_strips=True,
        bake_anim_use_all_actions=False,
    )
    return fbx_path


def export_glb_only(filepath: Path, objs: list[bpy.types.Object]) -> Path:
    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(
        filepath=str(filepath),
        use_selection=True,
        export_format="GLB",
        export_yup=True,
        export_materials="EXPORT",
        export_apply=True,
        export_animations=False,
    )
    return filepath


def main() -> None:
    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    RENDER_DIR.mkdir(parents=True, exist_ok=True)

    mob_builders = [
        ("MossSlime", lambda: build_slime(False), False),
        ("ElderMossSlime", lambda: build_slime(True), True),
        ("RiverSnapper", lambda: build_snapper(False), False),
        ("TidecrestSnapper", lambda: build_snapper(True), True),
        ("BrambleBoar", lambda: build_boar(False), False),
        ("ThornbackAlpha", lambda: build_boar(True), True),
        ("MeadowWitch", lambda: build_witch(False), False),
        ("CovenArchWitch", lambda: build_witch(True), True),
        ("RuinSentinel", lambda: build_sentinel(False), False),
        ("AncientWarden", lambda: build_sentinel(True), True),
    ]
    proj_ids = ["Proj_SporeGlob", "Proj_AquaGlob", "Proj_ArcaneHexOrb", "Proj_RuneBoulder"]

    manifest: dict = {"palette": PALETTE, "mobs": {}, "projectiles": {}}

    # 1. Export each mob as clean multi-part GLB + rigged FBX
    for name, fn, is_elite in mob_builders:
        C.clear_scene()
        asset, target_h = fn()
        objs, dims = asset.finalize(target_h=target_h, pivot_mode="floor")
        tris, _ = C.validate_asset(name, objs, tri_cap=2500, pivot_mode="floor")
        glb_path = export_glb_only(EXPORT_DIR / f"EM_Mob_{name}.glb", objs)
        fbx_path = build_rig_and_export_fbx(name, objs, dims)
        manifest["mobs"][name] = {
            "glb": glb_path.name,
            "fbx": fbx_path.name,
            "is_elite": is_elite,
            "anim_style": asset.anim_style,
            "tris": tris,
            "size_studs": [round(dims.x, 2), round(dims.z, 2), round(dims.y, 2)],  # Roblox W, H, D
            "ground_offset_y": round(dims.z * 0.5, 2),
            "health_bar_offset_y": round(dims.z * 0.5 + 1.8, 2),
            "submeshes": [o.name for o in objs],
        }

    # 2. Export 4 ballistic projectiles (center-pivot GLB)
    for pid in proj_ids:
        C.clear_scene()
        asset, target_h = build_projectile(pid)
        objs, dims = asset.finalize(target_h=target_h, pivot_mode="center")
        tris, _ = C.validate_asset(pid, objs, tri_cap=1200, pivot_mode="center")
        glb_path = export_glb_only(EXPORT_DIR / f"EM_{pid}.glb", objs)
        manifest["projectiles"][pid] = {
            "glb": glb_path.name,
            "tris": tris,
            "size_studs": [round(dims.x, 2), round(dims.z, 2), round(dims.y, 2)],
            "submeshes": [o.name for o in objs],
        }

    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"[MANIFEST] Wrote {MANIFEST_PATH} ({len(manifest['mobs'])} mobs, {len(manifest['projectiles'])} projectiles)")

    # 3. Render one clean QA showcase of the 4 ballistic projectiles
    C.clear_scene()
    all_proj: list[bpy.types.Object] = []
    for i, pid in enumerate(proj_ids):
        asset, target_h = build_projectile(pid)
        objs, _ = asset.finalize(target_h=target_h, pivot_mode="floor")
        for o in objs:
            o.location.x = (i - 1.5) * 4.5
            all_proj.append(o)
    C.setup_studio_render(all_proj, "EmeraldMeadow_Projectiles_QA.png", resolution=768, samples=20, cam_azimuth_deg=-22.0, cam_elev_deg=18.0, distance_mult=1.85)
    print("[DONE] Gate 3 Blender mob & projectile kit exported successfully.")


if __name__ == "__main__":
    main()
