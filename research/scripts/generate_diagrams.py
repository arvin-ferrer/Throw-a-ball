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


def diagram_master_rfy_pipeline(out_dir: Path) -> Path:
    """Render Deliverable E's Two-Stage Home RFY retrieval and 28-day ranking pipeline."""
    fig, ax = plt.subplots(figsize=(12.4, 4.4))
    ax.set_xlim(-0.02, 1.02)
    ax.set_ylim(-0.04, 1.04)
    ax.axis("off")
    ax.set_title(
        "Late-2026 Home RFY Two-Stage Retrieval & 28-Day Ranking Pipeline (Deliverable E)",
        fontsize=11.5, fontweight="bold", color=PALETTE["navy"], pad=8,
    )
    top = [
        (0.014, "Traffic Sources\nSearch, Ads, Links,\nFriends, Moments", "#EFF6FF", PALETTE["blue"]),
        (0.180, "Stage 1: Retrieval\nCandidate Pool\nGeneration", "#F0FDF4", PALETTE["teal"]),
        (0.346, "Explore Cohort\nAge-Matched Home\nRFY Impressions", "#F0FDF4", PALETTE["teal"]),
        (0.512, "Organic Isolation\nPaid & External\nMetrics Scrubbed", "#FEF3C7", PALETTE["amber"]),
        (0.678, "Stage 2: 28d RFY\nRanking Model", "#FEF3C7", PALETTE["amber"]),
        (0.844, "Expand Home RFY\nBroad Feed Scale", "#ECFDF5", PALETTE["emerald"]),
    ]
    for idx, (x, text, fc, ec) in enumerate(top):
        _draw_box(ax, x, 0.57, 0.124, 0.31, text, fc, ec, fontsize=7.4, bold=(idx >= 4))
        if idx < len(top) - 1:
            _draw_arrow(ax, x + 0.141, 0.725, top[idx + 1][0] - 0.017, 0.725, PALETTE["navy"])
    bottom = [
        (0.014, 0.206, "Eligibility Gates\nCustom 16:9 Tile +\nMaturity + Standards", "#F8FAFC", PALETTE["slate"], 0.242),
        (0.264, 0.220, "Primary Signals: PTR,\nBounce (<60s/61-180s),\n28d Play Days, 60m Cap", "#EFF6FF", PALETTE["blue"], 0.712),
        (0.526, 0.220, "Secondary: Intentional\nCo-Play, Qualified Sess.,\nSpend Days & Robux/User", "#EFF6FF", PALETTE["blue"], 0.742),
        (0.788, 0.196, "Q3 2026 Age-Cohort\nWeighting: 34% <13,\n37% 13-17, 29% 18+", "#ECFDF5", PALETTE["teal"], 0.772),
    ]
    for x, w, text, fc, ec, tx in bottom:
        _draw_box(ax, x, 0.08, w, 0.31, text, fc, ec, fontsize=7.3)
        _draw_arrow(ax, x + w * 0.5, 0.408, tx, 0.553, ec)
    return _save_diagram(fig, out_dir / "11_master_rfy_pipeline.png")


def diagram_gameidea_broken_loop(out_dir: Path) -> Path:
    """Render Deliverable H's audit of the broken preliminary GameIdea.txt loop."""
    fig, ax = plt.subplots(figsize=(12.2, 4.3))
    ax.set_xlim(-0.025, 1.025)
    ax.set_ylim(-0.04, 1.04)
    ax.axis("off")
    ax.set_title(
        "Audit of Preliminary GameIdea.txt Loop & Missing Payoff Link (Deliverable H)",
        fontsize=11.5, fontweight="bold", color=PALETTE["navy"], pad=8,
    )
    row1 = [
        (0.015, "1. Stationary Training\nShoot static targets\n(Zero skill ceiling)", "#EFF6FF", PALETTE["blue"]),
        (0.268, "2. Increase Ball DMG\nLinear stat grind\n(No tactical choices)", "#EFF6FF", PALETTE["blue"]),
        (0.521, "3. Unrestricted Portal\nCarry-bypass & newbie\n1-shot risk", "#FEF3C7", PALETTE["amber"]),
        (0.774, "4. WAIT Up to 5 Min\nSevere <60s & 61-180s\nBounce Trap!", "#FFF1F2", PALETTE["rose"]),
    ]
    row2 = [
        (0.774, "5. Boss Fight\nUndefined combat\ndepth & 1-CCU stall", "#FEF3C7", PALETTE["amber"]),
        (0.521, "6. Boss Egg Drops\nDifficulty-scaled\nrewards", "#EFF6FF", PALETTE["blue"]),
        (0.268, "7. Hatch Egg\nPaid Random Items\ncompliance risk", "#FEF3C7", PALETTE["amber"]),
        (0.015, "8. ??? MISSING PAYOFF\nUnclear impact on\ncombat or progression", "#FFF1F2", PALETTE["rose"]),
    ]
    for idx, (x, text, fc, ec) in enumerate(row1):
        _draw_box(ax, x, 0.56, 0.195, 0.33, text, fc, ec, fontsize=7.9, bold=(idx == 3))
        if idx < len(row1) - 1:
            _draw_arrow(ax, x + 0.214, 0.725, row1[idx + 1][0] - 0.018, 0.725, PALETTE["navy"])
    for idx, (x, text, fc, ec) in enumerate(row2):
        _draw_box(ax, x, 0.09, 0.195, 0.33, text, fc, ec, fontsize=7.9, bold=(idx == 3))
        if idx < len(row2) - 1:
            _draw_arrow(ax, x - 0.018, 0.255, row2[idx + 1][0] + 0.214, 0.255, PALETTE["navy"])
    _draw_arrow(ax, 0.871, 0.542, 0.871, 0.438, PALETTE["rose"])
    ax.annotate(
        "", xy=(0.112, 0.542), xytext=(0.112, 0.438),
        arrowprops={"arrowstyle": "-|>,head_width=0.28,head_length=0.45", "color": PALETTE["rose"], "lw": 1.6, "ls": "--"},
    )
    return _save_diagram(fig, out_dir / "12_gameidea_broken_loop.png")


def diagram_c2_mvp_dependency_dag(out_dir: Path) -> Path:
    """Render Deliverable K's 8-module 145-hour C2 Egg Heist MVP build dependency DAG."""
    fig, ax = plt.subplots(figsize=(12.4, 4.1))
    ax.set_xlim(-0.02, 1.02)
    ax.set_ylim(-0.04, 1.04)
    ax.axis("off")
    ax.set_title(
        "C2: Egg Heist: Boss Vault — 8-Module Solo MVP Build Dependency DAG (~145 Hours)",
        fontsize=11.5, fontweight="bold", color=PALETTE["navy"], pad=8,
    )
    nodes = [
        (0.014, 0.34, "1. Core Throw/Orb\n& Carry Physics\n(18h)", "#EFF6FF", PALETTE["blue"], True),
        (0.180, 0.57, "2. Modular Boss\nPatrol/Stun AI\n(18h)", "#F0FDF4", PALETTE["teal"], False),
        (0.180, 0.11, "3. Vault Hub +\n12h Offline Store\n(20h)", "#F0FDF4", PALETTE["teal"], False),
        (0.346, 0.57, "4. Data-Driven\n3-Chamber Loop\n(22h)", "#FEF3C7", PALETTE["amber"], False),
        (0.346, 0.11, "5. Earned Eggs +\n20-Guardian Table\n(16h)", "#FEF3C7", PALETTE["amber"], False),
        (0.512, 0.34, "6. Mobile UI, Codex\n& 4-Icon Ping Wheel\n(20h)", "#EFF6FF", PALETTE["blue"], False),
        (0.678, 0.34, "7. Ethical Shop +\nAnalyticsService\n(16h)", "#F0FDF4", PALETTE["teal"], False),
        (0.844, 0.34, "8. 2GB Android QA\n& Packaging\n(15h)", "#ECFDF5", PALETTE["emerald"], True),
    ]
    for x, y, text, fc, ec, bold in nodes:
        _draw_box(ax, x, y, 0.124, 0.31, text, fc, ec, fontsize=7.4, bold=bold)
    edges = [(0, 1), (0, 2), (1, 3), (2, 4), (3, 5), (4, 5), (5, 6), (6, 7)]
    for src_i, dst_i in edges:
        sx, sy = nodes[src_i][0] + 0.141, nodes[src_i][1] + 0.155
        dx, dy = nodes[dst_i][0] - 0.017, nodes[dst_i][1] + 0.155
        _draw_arrow(ax, sx, sy, dx, dy, PALETTE["navy"])
    return _save_diagram(fig, out_dir / "13_c2_mvp_dependency_dag.png")


def generate_all_diagrams(out_dir: Path) -> list[Path]:
    """Generate the four executive visual summary PNG diagrams for PDF embedding."""
    return [
        diagram_loop_comparison(out_dir),
        diagram_rfy_funnel(out_dir),
        diagram_validation_roadmap(out_dir),
        diagram_c2_core_loop(out_dir),
    ]


def generate_report_diagrams(out_dir: Path) -> list[Path]:
    """Generate the three master-report architectural PNG diagrams for PDF embedding."""
    return [
        diagram_master_rfy_pipeline(out_dir),
        diagram_gameidea_broken_loop(out_dir),
        diagram_c2_mvp_dependency_dag(out_dir),
    ]
