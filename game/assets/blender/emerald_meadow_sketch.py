"""Generate the Gate 2 to-scale 2D Top-Down Layout Sketch PNG for Emerald Meadow 10x.

Outputs:
- game/assets/renders/EmeraldMeadow_10x_LayoutSketch.png
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.patches as patches
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
import numpy as np

THIS_DIR = Path(__file__).resolve().parent
if str(THIS_DIR) not in sys.path:
    sys.path.insert(0, str(THIS_DIR))

import emerald_meadow_layout as eml

ROOT_DIR = THIS_DIR.parents[2]
OUT_PNG = ROOT_DIR / "game" / "assets" / "renders" / "EmeraldMeadow_10x_LayoutSketch.png"


def _draw_rotated_rect(ax, cx: float, cz: float, w: float, d: float, yaw_deg: float, **kwargs) -> None:
    rad = math.radians(yaw_deg)
    ca, sa = math.cos(rad), math.sin(rad)
    hw, hd = w * 0.5, d * 0.5
    corners = [(-hw, -hd), (hw, -hd), (hw, hd), (-hw, hd)]
    pts = [(cx + x * ca + z * sa, cz - x * sa + z * ca) for x, z in corners]
    ax.add_patch(patches.Polygon(pts, closed=True, **kwargs))


def render_sketch(out_path: Path = OUT_PNG) -> Path:
    data = eml.build_layout()
    cx, _, cz = eml.WORLD_CENTER

    fig = plt.figure(figsize=(20, 12.5), dpi=160, facecolor="#14181F")
    gs = fig.add_gridspec(2, 2, width_ratios=[1.65, 1.0], height_ratios=[1.15, 1.0], wspace=0.14, hspace=0.18)

    ax = fig.add_subplot(gs[:, 0])
    ax_world = fig.add_subplot(gs[0, 1])
    ax_info = fig.add_subplot(gs[1, 1])

    # =========================================================================
    # PANEL 1: TO-SCALE 10x EMERALD MEADOW VALLEY TOP-DOWN BLUEPRINT
    # =========================================================================
    ax.set_facecolor("#1B222C")

    # Outer cliff rim polygon
    outer_poly = [(cx + x, cz + z) for x, z in eml.valley_polygon(120, inset=-eml.CLIFF_RING_OFFSET)]
    inner_poly = [(cx + x, cz + z) for x, z in eml.valley_polygon(120, inset=0.0)]
    ax.add_patch(patches.Polygon(outer_poly, closed=True, facecolor="#4B5650", edgecolor="#7D8C82", linewidth=2.2, zorder=1))
    ax.add_patch(patches.Polygon(inner_poly, closed=True, facecolor="#4E9F58", edgecolor="#3B7A43", linewidth=1.6, zorder=2))

    # Subtle elevation/meadow rings for visual warmth
    mid_poly = [(cx + x, cz + z) for x, z in eml.valley_polygon(96, inset=120.0)]
    ax.add_patch(patches.Polygon(mid_poly, closed=True, facecolor="#5BB164", edgecolor="none", alpha=0.55, zorder=2.2))

    # Old 520-stud meadow circle overlaid at EXACT SCALE for 10x comparison!
    old_circle = patches.Circle(
        (cx, cz),
        eml.OLD_MEADOW_RADIUS,
        facecolor="none",
        edgecolor="#FFFFFF",
        linestyle="--",
        linewidth=2.0,
        alpha=0.88,
        zorder=8,
    )
    ax.add_patch(old_circle)
    ax.text(
        cx,
        cz - eml.OLD_MEADOW_RADIUS - 20,
        "OLD 520-STUD MEADOW FOOTPRINT (1× = 212k sq studs)",
        color="#FFFFFF",
        fontsize=8.3,
        fontweight="bold",
        ha="center",
        va="bottom",
        bbox=dict(boxstyle="round,pad=0.25", facecolor="#14181F", edgecolor="#FFFFFF", alpha=0.80, lw=0.9),
        zorder=12,
    )

    # Winding shallow river (bank + water)
    rx = [cx + p[0] for p in data["river_pts"]]
    rz = [cz + p[1] for p in data["river_pts"]]
    ax.plot(rx, rz, color="#C8B68A", linewidth=19.0, solid_capstyle="round", zorder=3)
    ax.plot(rx, rz, color="#33B6D4", linewidth=14.0, solid_capstyle="round", zorder=3.5)
    ax.plot(rx, rz, color="#83E5F7", linewidth=4.5, solid_capstyle="round", alpha=0.55, zorder=3.6)

    # Cobblestone & dirt road network
    for road in data["roads"]:
        px = [cx + p[0] for p in road]
        pz = [cz + p[1] for p in road]
        ax.plot(px, pz, color="#B79E76", linewidth=5.2, solid_capstyle="round", alpha=0.88, zorder=4)
        ax.plot(px, pz, color="#D4C29F", linewidth=2.0, linestyle=":", alpha=0.75, zorder=4.1)

    # Arrival Pad & Return Portal Plaza
    ax.add_patch(patches.Circle((cx + eml.ARRIVAL_PAD_LOCAL[0], cz + eml.ARRIVAL_PAD_LOCAL[1]), 22, facecolor="#26E88A", edgecolor="#FFFFFF", lw=1.8, zorder=9))
    ax.text(cx + eml.ARRIVAL_PAD_LOCAL[0] + 34, cz + eml.ARRIVAL_PAD_LOCAL[1], "ARRIVAL PAD\n(2000, -4175)", color="#A7F3D0", fontsize=7.5, fontweight="bold", va="center", zorder=12)

    # Bridges
    for br in data["bridges"]:
        col = "#D4CFC2" if br.kind == "StoneBridge" else "#9E6B3F"
        edge = "#4B524E" if br.kind == "StoneBridge" else "#5B3B1E"
        _draw_rotated_rect(ax, cx + br.lx, cz + br.lz, br.width + 6, br.length + 4, br.yaw_deg, facecolor=col, edgecolor=edge, linewidth=1.6, zorder=6)
        label_short = br.name.split("_")[0][:1] + br.name.split("_")[1]
        ax.text(cx + br.lx, cz + br.lz, label_short, color="#14181F", fontsize=7.2, fontweight="bold", ha="center", va="center", zorder=11)

    # Buildings & Ruins
    b_styles = {
        "CottageA": ("#E08A47", "#5A2F12"),
        "Watermill": ("#F59E0B", "#6B3807"),
        "Watchtower": ("#F43F5E", "#FFFFFF"),
        "RuinArch": ("#94A3B8", "#334155"),
        "RuinPillar": ("#CBD5E1", "#475569"),
        "ReturnPortal": ("#38BDF8", "#FFFFFF"),
        "Shrine": ("#34D399", "#064E3B"),
    }
    for b in data["buildings"]:
        fc, ec = b_styles[b.kind]
        _draw_rotated_rect(ax, cx + b.lx, cz + b.lz, max(b.footprint_w, 16), max(b.footprint_d, 14), b.yaw_deg, facecolor=fc, edgecolor=ec, linewidth=1.4, zorder=7)

    # Multi-Species Trees (~186 trees)
    tree_styles = {
        "Oak": ("#2D7A38", 13.0, 0.88),
        "Pine": ("#1B5130", 11.5, 0.90),
        "Birch": ("#7AD659", 10.0, 0.90),
        "ElderOak": ("#14E374", 22.0, 0.95),
    }
    for tr in data["trees"]:
        fc, rad, alpha = tree_styles[tr.species]
        ec = "#D9F99D" if tr.species == "ElderOak" else "#10321A"
        lw = 1.6 if tr.species == "ElderOak" else 0.55
        ax.add_patch(patches.Circle((cx + tr.lx, cz + tr.lz), rad * tr.scale, facecolor=fc, edgecolor=ec, lw=lw, alpha=alpha, zorder=5))

    # 56 Mob Spawners
    for sp in data["spawners"]:
        col = "#4ADE80" if sp.mob_type == "MossSlime" else "#FBBF24"
        edge = "#064E3B" if sp.mob_type == "MossSlime" else "#78350F"
        ax.scatter([cx + sp.lx], [cz + sp.lz], s=58, c=col, edgecolors=edge, linewidths=1.1, zorder=10)

    # District Callout Badges
    district_labels = [
        ("1. NORTH GATE & ARRIVAL\n(6 Slime Spawners)", 0, -610),
        ("2. WHISPERING MILL HAMLET\n(Watermill, 3 Cottages, 10 Spawners)", -535, -310),
        ("3. EMERALD CONFLUENCE\n(Sun-Ring Ruins, Elder Oak, 10 Spawners)", -25, 115),
        ("4. EAST TIMBER WATCH\n(Watchtower #1, Aqueduct, 10 Spawners)", 535, -185),
        ("5. BRAMBLE THICKET RUINS\n(Colonnade, Crystals, 10 Spawners)", -390, 465),
        ("6. SOUTH SHRINE OVERLOOK\n(Watchtower #2, Shrine, 10 Spawners)", 250, 625),
    ]
    for txt, lx, lz in district_labels:
        ax.text(
            cx + lx,
            cz + lz,
            txt,
            color="#F8FAFC",
            fontsize=7.6,
            fontweight="bold",
            ha="center",
            va="center",
            bbox=dict(boxstyle="round,pad=0.3", facecolor="#0F172A", edgecolor="#34D399", alpha=0.82, lw=1.0),
            zorder=13,
        )

    # North/South orientation note: invert Y so -Z (North) is UP, +Z (South) is DOWN!
    ax.set_xlim(cx - 960, cx + 960)
    ax.set_ylim(cz + 900, cz - 900)
    ax.set_aspect("equal")
    ax.grid(True, color="#FFFFFF", alpha=0.14, linestyle="-", linewidth=0.6)
    ax.set_xticks(np.arange(1000, 3001, 200))
    ax.set_yticks(np.arange(-4400, -2599, 200))
    ax.tick_params(colors="#CBD5E1", labelsize=8)
    ax.set_xlabel("Roblox World X (studs)  →  East", color="#E2E8F0", fontsize=10, fontweight="bold")
    ax.set_ylabel("Roblox World Z (studs)  (North ↑ / South ↓)", color="#E2E8F0", fontsize=10, fontweight="bold")
    ax.set_title(
        f"EMERALD MEADOW 10× REBUILD — TOP-DOWN LAYOUT SKETCH\n"
        f"Center (2000, 0, -3500) · Playable Area {data['valley_area']/1e6:.2f}M sq studs ({data['area_multiplier']:.1f}× Live Meadow)",
        color="#34D399",
        fontsize=12.5,
        fontweight="bold",
        pad=12,
    )

    # Scale bar (200 studs)
    sb_x, sb_z = cx - 870, cz + 835
    ax.plot([sb_x, sb_x + 200], [sb_z, sb_z], color="#FFFFFF", lw=3.0, zorder=14)
    ax.text(sb_x + 100, sb_z - 22, "200 STUDS (~36 Roblox Avatars)", color="#FFFFFF", fontsize=8, fontweight="bold", ha="center", zorder=14)

    # =========================================================================
    # PANEL 2: WORLD CONTEXT INSET (CLEARANCES & FUTURE 10x BIOME SLOTS)
    # =========================================================================
    ax_world.set_facecolor("#1B222C")
    # Hub
    ax_world.add_patch(patches.Rectangle((-380, -380), 760, 760, facecolor="#3B82F6", edgecolor="#93C5FD", alpha=0.75, lw=1.4))
    ax_world.text(0, 0, "HUB\n(0,0)", color="#FFFFFF", fontsize=7.5, fontweight="bold", ha="center", va="center")
    # VaultHeist
    ax_world.add_patch(patches.Rectangle((-60, -960), 120, 120, facecolor="#A855F7", edgecolor="#E9D5FF", alpha=0.85, lw=1.2))
    ax_world.text(0, -1080, "VaultHeist", color="#E9D5FF", fontsize=7, ha="center")
    # Untouched Boss Arenas (Z = +1200)
    for bx, label in [(2000, "Emerald Boss\n(UNTOUCHED)"), (4000, "Frost Boss"), (6000, "Molten Boss")]:
        ec = "#F43F5E" if bx == 2000 else "#94A3B8"
        ax_world.add_patch(patches.Circle((bx, 1200), 160, facecolor="#EF4444" if bx == 2000 else "#64748B", edgecolor=ec, alpha=0.9, lw=1.6))
        ax_world.text(bx, 1580, label, color="#FCA5A5" if bx == 2000 else "#CBD5E1", fontsize=7, fontweight="bold", ha="center")

    # Old Emerald Meadow (removed) & current Frostbite / Molten
    ax_world.add_patch(patches.Circle((2000, 0), 260, facecolor="none", edgecolor="#94A3B8", linestyle=":", lw=1.4))
    ax_world.text(2000, 0, "Old Meadow\n(Replaced)", color="#94A3B8", fontsize=6.5, ha="center", va="center")
    ax_world.add_patch(patches.Circle((4000, 0), 260, facecolor="#38BDF8", edgecolor="#BAE6FD", alpha=0.55, lw=1.2))
    ax_world.text(4000, 0, "Frostbite\n(Current)", color="#E0F2FE", fontsize=6.5, ha="center", va="center")
    ax_world.add_patch(patches.Circle((6000, 0), 260, facecolor="#FB923C", edgecolor="#FED7AA", alpha=0.55, lw=1.2))
    ax_world.text(6000, 0, "Molten\n(Current)", color="#FFEDD5", fontsize=6.5, ha="center", va="center")

    # NEW 10x Emerald Meadow at (2000, -3500)
    ax_world.add_patch(patches.Ellipse((2000, -3500), 1800, 1660, facecolor="#22C55E", edgecolor="#86EFAC", alpha=0.85, lw=2.0))
    ax_world.text(2000, -3500, "NEW 10×\nMEADOW\n(2000,-3500)", color="#052E16", fontsize=6.7, fontweight="bold", ha="center", va="center")

    # Future 10x Reserved Slots (Frostbite & Molten)
    for fx, lbl, col in [(5500, "Reserved Future 10×\nFrostbite (5500, -3500)", "#38BDF8"), (9000, "Reserved Future 10×\nMolten (9000, -3500)", "#FB923C")]:
        ax_world.add_patch(patches.Ellipse((fx, -3500), 1800, 1660, facecolor="none", edgecolor=col, linestyle="--", alpha=0.75, lw=1.4))
        ax_world.text(fx, -3500, lbl, color=col, fontsize=6.8, fontweight="bold", ha="center", va="center")

    # Clearance annotation arrow to BossPvPArena
    ax_world.annotate(
        "",
        xy=(2000, 1050),
        xytext=(2000, -2670),
        arrowprops=dict(arrowstyle="<->", color="#FDE047", lw=1.6, ls="--"),
    )
    ax_world.text(2150, -820, "3,745 studs clear\nto BossPvPArena\n(Server Teleport Only)", color="#FDE047", fontsize=7.2, fontweight="bold", va="center")

    # Clearance arrow to Future Frostbite
    ax_world.annotate(
        "",
        xy=(4600, -3500),
        xytext=(2900, -3500),
        arrowprops=dict(arrowstyle="<->", color="#7DD3FC", lw=1.4, ls="--"),
    )
    ax_world.text(3750, -3880, "1,700 studs\nclear", color="#7DD3FC", fontsize=7, fontweight="bold", ha="center")

    ax_world.set_xlim(-1000, 10400)
    ax_world.set_ylim(2100, -4900)
    ax_world.set_aspect("equal")
    ax_world.grid(True, color="#FFFFFF", alpha=0.10, lw=0.5)
    ax_world.tick_params(colors="#CBD5E1", labelsize=7.5)
    ax_world.set_title("WORLD MAP CONTEXT & FUTURE 10× BIOME SLOTS", color="#F8FAFC", fontsize=10.5, fontweight="bold", pad=8)

    # =========================================================================
    # PANEL 3: LEGEND & ENGINEERING SUMMARY
    # =========================================================================
    ax_info.set_facecolor("#1B222C")
    ax_info.axis("off")

    legend_handles = [
        patches.Patch(facecolor="#4E9F58", edgecolor="#3B7A43", label="Playable Meadow (Y = 0, flat combat ground)"),
        patches.Patch(facecolor="#4B5650", edgecolor="#7D8C82", label="Outer Tiered Valley Cliffs (48–78 studs tall)"),
        Line2D([0], [0], color="#33B6D4", lw=6, label="Shallow Winding River (~2,100 studs, 1.4-stud wadeable depth)"),
        Line2D([0], [0], color="#B79E76", lw=4, label="Cobblestone & Dirt Path Loop connecting all 6 districts"),
        patches.Patch(facecolor="#D4CFC2", edgecolor="#4B524E", label="Stone Arch Bridges (2×: S1, S4 — 22W × 74L)"),
        patches.Patch(facecolor="#9E6B3F", edgecolor="#5B3B1E", label="Timber Footbridges (2×: W2, W3 — 16W × 66L)"),
        patches.Patch(facecolor="#E08A47", edgecolor="#5A2F12", label="Meadow Cottages (7×) & Watermill (1×) — 6×9 doors"),
        patches.Patch(facecolor="#F43F5E", edgecolor="#FFFFFF", label="Watchtowers (2×, 40 studs tall) · Ruins & Shrine"),
        Line2D([0], [0], marker="o", color="none", markerfacecolor="#2D7A38", markersize=8, label="Trees (~186 total): 70 Oaks, 65 Pines, 45 Birches, 6 Elder Oaks"),
        Line2D([0], [0], marker="o", color="none", markerfacecolor="#4ADE80", markeredgecolor="#064E3B", markersize=8, label="MossSlime Spawners (28 pads)"),
        Line2D([0], [0], marker="o", color="none", markerfacecolor="#FBBF24", markeredgecolor="#78350F", markersize=8, label="BrambleBoar Spawners (28 pads)"),
        Line2D([0], [0], marker="o", color="none", markerfacecolor="#26E88A", markeredgecolor="#FFFFFF", markersize=9, label="ArrivalPad (2000, -4175) & ReturnPortal (2000, -4218)"),
    ]
    ax_info.legend(
        handles=legend_handles,
        loc="upper left",
        bbox_to_anchor=(0.01, 0.99),
        frameon=True,
        facecolor="#14181F",
        edgecolor="#334155",
        labelcolor="#E2E8F0",
        fontsize=8.3,
        title="BLUEPRINT LEGEND",
        title_fontsize=9.5,
    )
    ax_info.get_legend().get_title().set_color("#34D399")
    ax_info.get_legend().get_title().set_fontweight("bold")

    summary_txt = (
        "AVATAR SCALE & GAMEPLAY CHECKS (5.5-STUD ROBLOX R15)\n"
        "• Playable Basin: 1,720 × 1,580 studs (2.13M sq studs = 10.0× live 520-stud circle)\n"
        "• Doorways: 6W × 9H · Cottages: 26W × 20D × 16H · Watchtowers: 16×16×40H\n"
        "• River: 60W, bed Y = -1.8, water Y = -0.4 (1.4-stud ankle-deep, zero drowning)\n"
        "• Trees: 186 instanced trees with 7–10 stud walk-under trunk clearance\n"
        "• Teleports: ArrivalPad + ReturnPortal + RequestStreamAroundAsync hardened"
    )
    ax_info.text(
        0.02,
        0.03,
        summary_txt,
        transform=ax_info.transAxes,
        color="#CBD5E1",
        fontsize=8.0,
        va="bottom",
        ha="left",
        family="monospace",
        bbox=dict(boxstyle="round,pad=0.45", facecolor="#0F172A", edgecolor="#475569", lw=1.0),
    )

    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path, dpi=160, bbox_inches="tight", facecolor=fig.get_facecolor())
    plt.close(fig)
    print(f"Saved 2D layout sketch: {out_path}")
    return out_path


if __name__ == "__main__":
    render_sketch()
