"""Headless Blender 5.3 verification template: generates a stylized low-poly Boss Egg (.glb + PNG)."""

from __future__ import annotations

import math
from pathlib import Path

import bpy


def clear_scene() -> None:
    """Remove default objects for a clean procedural asset build."""
    bpy.ops.wm.read_factory_settings(use_empty=True)


def build_stylized_egg() -> bpy.types.Object:
    """Create a stylized faceted low-poly Boss Egg scaled for Roblox (~2.4 studs tall)."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=12, radius=1.0, location=(0, 0, 1.2))
    egg = bpy.context.active_object
    egg.name = "BossEgg_Meadow"
    for v in egg.data.vertices:
        z = v.co.z
        taper = 0.72 if z > 0 else 1.05
        v.co.x *= taper
        v.co.y *= taper
        v.co.z *= 1.25
    bpy.ops.object.shade_flat()

    mat = bpy.data.materials.new(name="MeadowEggMat")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (0.16, 0.78, 0.45, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.35
    egg.data.materials.append(mat)
    return egg


def setup_camera_and_light() -> None:
    """Place a studio key light and 3/4 preview camera."""
    bpy.ops.object.light_add(type="SUN", location=(4, -4, 6))
    bpy.context.active_object.data.energy = 3.0

    bpy.ops.object.camera_add(location=(3.5, -3.5, 2.6), rotation=(math.radians(68), 0, math.radians(45)))
    bpy.context.scene.camera = bpy.context.active_object


def export_and_render(root: Path) -> None:
    """Export Roblox-ready GLB and render a compact preview PNG for Gemini Visual QA."""
    export_dir = root / "game" / "assets" / "exports"
    render_dir = root / "game" / "assets" / "renders"
    export_dir.mkdir(parents=True, exist_ok=True)
    render_dir.mkdir(parents=True, exist_ok=True)

    bpy.ops.export_scene.gltf(filepath=str(export_dir / "BossEgg_Meadow.glb"), export_format="GLB")

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.render.filepath = str(render_dir / "BossEgg_Meadow_preview.png")
    bpy.ops.render.render(write_still=True)


def main() -> None:
    root = Path(__file__).resolve().parents[3]
    clear_scene()
    build_stylized_egg()
    setup_camera_and_light()
    export_and_render(root)
    print("BLENDER_EXPORT_OK")


if __name__ == "__main__":
    main()
