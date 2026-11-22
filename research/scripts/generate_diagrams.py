"""Render crisp architectural diagrams as high-DPI PNGs for PDF export."""

from __future__ import annotations

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.patches as patches
import matplotlib.pyplot as plt

from generate_charts import PALETTE


def _draw_box(
    ax: plt.Axes,
    x: float,
    y: float,
    w: float,
    h: float,
    text: str,
    fc: str,
    ec: str,
    tc: str = "#1B2A4A",
    fontsize: float = 8.4,
    bold: bool = False,
) -> None:
    """Draw a rounded executive diagram box with centered wrapped text."""
    box = patches.FancyBboxPatch(
        (x, y),
        w,
        h,
        boxstyle="round,pad=0.015,rounding_size=0.025",
        facecolor=fc,
        edgecolor=ec,
        linewidth=1.5,
    )
    ax.add_patch(box)
    ax.text(
        x + w / 2,
        y + h / 2,
        text,
        ha="center",
        va="center",
        color=tc,
        fontsize=fontsize,
        fontweight="bold" if bold else "normal",
        parse_math=False,
    )


def _draw_arrow(
    ax: plt.Axes, x1: float, y1: float, x2: float, y2: float, color: str
) -> None:
    """Draw a clean directional connector arrow between two coordinates."""
    ax.annotate(
        "",
        xy=(x2, y2),
        xytext=(x1, y1),
        arrowprops={"arrowstyle": "-|>,head_width=0.28,head_length=0.45", "color": color, "lw": 1.6},
    )


def diagram_loop_comparison(out_dir: Path) -> Path:
    """Side-by-side comparison of broken GameIdea.txt loop vs. C2: Egg Heist loop."""
    fig, ax = plt.subplots(figsize=(12.0, 6.0))
    ax.set_xlim(-0.02, 1.02)
    ax.set_ylim(-0.02, 1.02)
    ax.axis("off")
    ax.set_title(
        "Gameplay Loop Audit: Preliminary GameIdea.txt (4.22/10) vs. Reimagined C2 Winner (8.43/10)",
        fontsize=12.5,
        fontweight="bold",
        color=PALETTE["navy"],
        pad=10,
    )

    bad_steps = [
        "1. Stationary Target Clicking\n(Zero skill ceiling; unclippable on Moments)",
        "2. Unrestricted Biome Portal\n(Carry-bypass exploit & newbie 1-shot quits)",
        "3. WAIT up to 5 Minutes for Boss\n(Triggers <60s & 61-180s RFY Bounce Penalty)",
        "4. Boss Kill -> Egg Drop\n(No co-op roles; breaks at 1-3 CCU)",
        "5. ??? MISSING EGG PAYOFF LOOP\n+ Multi-Biome Solo Art Burnout & Lootbox Risk",
    ]
    good_steps = [
        "1. Instant 1-4p Vault Elevator\n(Core action in <15s; 1-CCU cold-start proof)",
        "2. Dodge Patrolling Boss + Throw Utility Orbs\n(Decoy / Freeze / Dash — 3s mute clip hook)",
        "3. Grab Heavy Glowing Egg\n(Speed slowdown = intense heist tension)",
        "4. Push-Your-Luck Extraction Vote\n(Extract Safely OR Dive Chamber 2/3 for Mythics)",
        "5. 100% Gameplay-Earned Guardian Hatch\n(Zero lootbox bans -> Hub Display + 12h Offline Cash)",
    ]
    _render_column(ax, 0.03, "Preliminary Concept (DO NOT BUILD AS WRITTEN)", bad_steps, "#FFF1F2", PALETTE["rose"])
    _render_column(ax, 0.52, "Reimagined #1 Winner: C2 Egg Heist (PROTOTYPE FIRST)", good_steps, "#ECFDF5", PALETTE["teal"])

    out_path = out_dir / "07_loop_comparison_diagram.png"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path, dpi=180, bbox_inches="tight", facecolor="white")
    plt.close(fig)
    return out_path


def _render_column(
    ax: plt.Axes, x0: float, heading: str, steps: list[str], fc: str, accent: str
) -> None:
    """Render one vertical sequence column with header badge and arrows."""
    _draw_box(ax, x0, 0.89, 0.45, 0.08, heading, accent, accent, tc="white", fontsize=9.0, bold=True)
    ys = [0.73, 0.56, 0.39, 0.22, 0.04]
    for idx, (y, label) in enumerate(zip(ys, steps)):
        is_last = idx == len(steps) - 1
        _draw_box(ax, x0, y, 0.45, 0.12, label, fc, accent, fontsize=8.3, bold=is_last)
        if idx < len(steps) - 1:
            _draw_arrow(ax, x0 + 0.225, y, x0 + 0.225, ys[idx + 1] + 0.125, accent)


def diagram_rfy_funnel(out_dir: Path) -> Path:
    """Standalone diagram: Post-June 15, 2026 Roblox Two-Stage Home RFY Funnel."""
    fig, ax = plt.subplots(figsize=(12.2, 3.1))
    ax.set_xlim(-0.025, 1.025)
    ax.set_ylim(-0.04, 1.04)
    ax.axis("off")
    ax.set_title(
        "Verified Late-2026 Roblox Two-Stage Home RFY Discovery Funnel (Post-June 15, 2026)",
        fontsize=11.5,
        fontweight="bold",
        color=PALETTE["navy"],
        pad=8,
    )
    boxes = [
        (0.015, "Cold-Start Seed\nShare Links, Moments,\nDiscord Flash Mob,\nStandout Games", "#EFF6FF", PALETTE["blue"]),
        (0.268, "Stage 1: Retrieval\nCustom 16:9 Tile +\nContent Maturity Gate\n(All Traffic Feeds Pool)", "#F0FDF4", PALETTE["teal"]),
        (0.521, "Stage 2: 28d Ranking\nOrganic RFY ONLY!\nPTR + Low <60s Bounce\nPlay Days + Co-Play", "#FEF3C7", PALETTE["amber"]),
        (0.774, "Organic Home Scale\nAge-Cohort Weighted\nAuto-Play Videos (+39%)\n40% Top-100 Are <3mo", "#ECFDF5", PALETTE["emerald"]),
    ]
    for idx, (x, text, fc, ec) in enumerate(boxes):
        _draw_box(ax, x, 0.14, 0.195, 0.72, text, fc, ec, fontsize=8.4, bold=(idx == 3))
        if idx < len(boxes) - 1:
            _draw_arrow(ax, x + 0.214, 0.50, boxes[idx + 1][0] - 0.018, 0.50, PALETTE["navy"])
    return _save_diagram(fig, out_dir / "08_rfy_discovery_funnel.png")


def diagram_validation_roadmap(out_dir: Path) -> Path:
    """Standalone diagram: 30-Day Solo Prototype Validation & Gate 1 Pivot Flow."""
    fig, ax = plt.subplots(figsize=(12.2, 3.8))
    ax.set_xlim(-0.025, 1.025)
    ax.set_ylim(-0.04, 1.04)
    ax.axis("off")
    ax.set_title(
        "30-Day Solo Validation & Pivot Roadmap (Zero Sunk-Cost Fallacy)",
        fontsize=11.5,
        fontweight="bold",
        color=PALETTE["navy"],
        pad=8,
    )
    _draw_box(ax, 0.010, 0.44, 0.155, 0.44, "Days 1–3\n$0 Concept Poll\n(C2 vs C3)\n+ W-8BEN Setup", "#EFF6FF", PALETTE["blue"], fontsize=8.1)
    _draw_box(ax, 0.215, 0.44, 0.160, 0.44, "Days 4–13\n10-Day Greybox C2\n1 Chamber, 1 Boss\nDecoy+Freeze Orbs", "#EFF6FF", PALETTE["blue"], fontsize=8.1)
    _draw_box(ax, 0.425, 0.44, 0.155, 0.44, "Day 14: GATE 1\n20 Silent Testers\n(>=50% Mobile)\n>=70% Run #2?", "#FEF3C7", PALETTE["amber"], fontsize=8.1, bold=True)
    _draw_box(ax, 0.630, 0.56, 0.155, 0.36, "PASS: Days 17–24\nBuild Full MVP\nHub + 12h Offline\n+ ProfileStore", "#ECFDF5", PALETTE["teal"], fontsize=7.9, bold=True)
    _draw_box(ax, 0.835, 0.56, 0.155, 0.36, "Days 25–30\nSoft Launch\n($50-$100 Test)\nGate 4: D1>=13%", "#ECFDF5", PALETTE["emerald"], fontsize=7.9, bold=True)
    _draw_box(ax, 0.630, 0.06, 0.360, 0.34, "FAIL (<45% After 3d Tune): ZERO SUNK-COST PIVOT\nLaunch 7-Day Ultra-Lean Prototype:\nC3 Curve Clash (Duel Pads)", "#FFF1F2", PALETTE["rose"], fontsize=8.0, bold=True)

    _draw_arrow(ax, 0.183, 0.66, 0.197, 0.66, PALETTE["navy"])
    _draw_arrow(ax, 0.393, 0.66, 0.407, 0.66, PALETTE["navy"])
    _draw_arrow(ax, 0.598, 0.72, 0.612, 0.74, PALETTE["teal"])
    _draw_arrow(ax, 0.803, 0.74, 0.817, 0.74, PALETTE["emerald"])
    _draw_arrow(ax, 0.596, 0.48, 0.614, 0.25, PALETTE["rose"])
    return _save_diagram(fig, out_dir / "09_30day_validation_roadmap.png")


def diagram_c2_core_loop(out_dir: Path) -> Path:
    """Standalone diagram: C2 Egg Heist 6-step extraction & push-your-luck loop."""
    fig, ax = plt.subplots(figsize=(12.2, 4.3))
    ax.set_xlim(-0.025, 1.025)
    ax.set_ylim(-0.04, 1.04)
    ax.axis("off")
    ax.set_title(
        "C2: Egg Heist: Boss Vault — Core 6-Step Extraction & Push-Your-Luck Loop",
        fontsize=11.5,
        fontweight="bold",
        color=PALETTE["navy"],
        pad=8,
    )
    top = [
        (0.015, "1. Personal Vault Hub\nClaim <=12h Offline Cash\nEquip & Upgrade Orbs", "#EFF6FF", PALETTE["blue"]),
        (0.268, "2. Instant 1-4p Elevator\n0s Wait | Solo or Party\nDynamic 1-4p Scaling", "#F0FDF4", PALETTE["teal"]),
        (0.521, "3. Active Boss Heist\nDodge Patrol & Traps\nDecoy / Freeze / Dash Orbs", "#FEF3C7", PALETTE["amber"]),
        (0.774, "4. Heavy Glowing Egg\n-22% to -32% Sprint Slow\nRace Closing Laser Gate", "#FFF1F2", PALETTE["rose"]),
    ]
    for idx, (x, text, fc, ec) in enumerate(top):
        _draw_box(ax, x, 0.56, 0.195, 0.34, text, fc, ec, fontsize=8.1, bold=(idx == 3))
        if idx < len(top) - 1:
            _draw_arrow(ax, x + 0.214, 0.73, top[idx + 1][0] - 0.018, 0.73, PALETTE["navy"])

    _draw_box(ax, 0.521, 0.08, 0.448, 0.34, "5. EXTRACTION PAD VOTE (Push-Your-Luck)\nExtract Safely (Bank 100%)  OR  Dive Chamber 2/3/5\n(Multiplied Mythic & Mutated Odds; Wipe = Lose Run Loot)", "#FEF3C7", PALETTE["amber"], fontsize=8.1, bold=True)
    _draw_box(ax, 0.015, 0.08, 0.448, 0.34, "6. Hub Hatch, Codex & Flex (100% Earned-Only)\nHatch Vault Guardians -> 8 Display Pedestals + Companion Perk\n3-to-1 Deterministic Fusion -> Upgrade Orbs for Deeper Dives", "#ECFDF5", PALETTE["emerald"], fontsize=8.1, bold=True)

    _draw_arrow(ax, 0.871, 0.542, 0.871, 0.440, PALETTE["rose"])
    _draw_arrow(ax, 0.618, 0.440, 0.618, 0.542, PALETTE["amber"])
    _draw_arrow(ax, 0.503, 0.25, 0.481, 0.25, PALETTE["emerald"])
    _draw_arrow(ax, 0.112, 0.440, 0.112, 0.542, PALETTE["teal"])
    return _save_diagram(fig, out_dir / "10_c2_core_gameplay_loop.png")


def _save_diagram(fig: plt.Figure, out_path: Path) -> Path:
    """Save figure cleanly to disk and close it."""
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path, dpi=180, bbox_inches="tight", facecolor="white")
    plt.close(fig)
    return out_path


def generate_all_diagrams(out_dir: Path) -> list[Path]:
    """Generate all four architectural PNG diagrams for PDF embedding."""
    return [
        diagram_loop_comparison(out_dir),
        diagram_rfy_funnel(out_dir),
        diagram_validation_roadmap(out_dir),
        diagram_c2_core_loop(out_dir),
    ]
