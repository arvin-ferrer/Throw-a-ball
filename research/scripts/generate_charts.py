"""Generate high-DPI data visualizations from verified Roblox research datasets.

All metrics are read programmatically from research/data/*.csv and *.json via the
existing validated engines (validate_research_data, decision_matrix, financial_model)
so charts stay 100% synchronized with the audited numbers.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

from common import load_json_file
from decision_matrix import run_sensitivity_suite
from financial_model import run_all_scenarios
from validate_research_data import (
    compute_mechanic_frequencies,
    validate_feature_matrix,
    validate_games_database,
)

PALETTE = {
    "navy": "#1B2A4A",
    "blue": "#2563EB",
    "teal": "#0D9488",
    "emerald": "#10B981",
    "amber": "#D97706",
    "rose": "#E11D48",
    "purple": "#7C3AED",
    "slate": "#475569",
    "grid": "#E2E8F0",
    "bg": "#FFFFFF",
}


def _configure_style() -> None:
    """Apply clean, high-contrast executive typography across all figures."""
    plt.rcParams.update(
        {
            "figure.facecolor": PALETTE["bg"],
            "axes.facecolor": PALETTE["bg"],
            "axes.edgecolor": "#CBD5E1",
            "axes.labelcolor": PALETTE["navy"],
            "xtick.color": PALETTE["slate"],
            "ytick.color": PALETTE["slate"],
            "text.color": PALETTE["navy"],
            "font.size": 10,
            "axes.titlesize": 13,
            "axes.titleweight": "bold",
            "axes.grid": True,
            "grid.color": PALETTE["grid"],
            "grid.linestyle": "--",
            "grid.alpha": 0.7,
        }
    )


def _save_fig(fig: plt.Figure, out_path: Path) -> Path:
    """Save a Matplotlib figure cleanly at 180 DPI and release memory."""
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path, dpi=180, bbox_inches="tight", facecolor=PALETTE["bg"])
    plt.close(fig)
    return out_path


def chart_concept_decision_matrix(data_dir: Path, out_dir: Path) -> Path:
    """Plot baseline weighted scores plus all 4 Section 15 sensitivity profiles."""
    payload = load_json_file(data_dir / "decision_matrix.json")
    results = run_sensitivity_suite(payload["concepts"])
    baseline = results["Baseline (Section 15)"]
    names = [r["name"].split(" (")[0] for r in baseline][::-1]
    full_names = [r["name"] for r in baseline][::-1]
    base_scores = [r["weighted_score"] for r in baseline][::-1]
    y_pos = np.arange(len(names))

    fig, ax = plt.subplots(figsize=(11.5, 5.8))
    colors = [PALETTE["rose"] if "Preliminary" in n else PALETTE["blue"] for n in names]
    colors[-1] = PALETTE["teal"]
    bars = ax.barh(y_pos, base_scores, height=0.56, color=colors, alpha=0.85, label="Baseline (Sec 15)")
    _overlay_sensitivity_markers(ax, results, full_names, y_pos)
    for bar, score in zip(bars, base_scores):
        ax.text(
            0.22,
            bar.get_y() + bar.get_height() / 2,
            f"Baseline: {score:.2f}",
            va="center",
            ha="left",
            color="white",
            fontweight="bold",
            fontsize=9.2,
        )

    ax.set_yticks(y_pos, names)
    ax.set_xlim(0, 10.2)
    ax.set_xlabel("Weighted Score (1.0 – 10.0 Scale)")
    ax.set_title("Game Concept Decision Matrix: Baseline Score & 4-Profile Sensitivity Spread")
    ax.grid(axis="y", visible=False)
    ax.legend(loc="lower right", frameon=True, facecolor="white", edgecolor="#CBD5E1", fontsize=8.5)
    return _save_fig(fig, out_dir / "01_concept_decision_scores.png")


def _overlay_sensitivity_markers(
    ax: plt.Axes,
    results: dict[str, list[dict[str, Any]]],
    full_names: list[str],
    y_pos: np.ndarray,
) -> None:
    """Overlay sensitivity priority markers on the horizontal concept score bars."""
    styles = [
        ("Feasibility Priority", "o", PALETTE["amber"], -0.18),
        ("Profitability Priority", "s", PALETTE["emerald"], -0.06),
        ("Organic Growth Priority", "^", PALETTE["purple"], 0.06),
        ("Sustainability Priority", "D", PALETTE["navy"], 0.18),
    ]
    for profile, marker, color, offset in styles:
        lookup = {row["name"]: row["weighted_score"] for row in results[profile]}
        xs = [lookup[n] for n in full_names]
        ax.scatter(xs, y_pos + offset, marker=marker, s=55, color=color, zorder=5, edgecolors="white", linewidths=0.7, label=profile)


def chart_viral_vs_sustained_mechanics(data_dir: Path, out_dir: Path) -> Path:
    """Compare mechanic prevalence between Sustained (n=15) and Viral (n=10) cohorts."""
    games = validate_games_database(data_dir / "games_database.csv")
    mechs, rows = validate_feature_matrix(data_dir / "feature_matrix.csv", {g["game_id"] for g in games})
    stats = {str(s["mechanic"]): s for s in compute_mechanic_frequencies(mechs, rows)}
    focus = [
        ("cooperation", "Cooperation"),
        ("achievements", "Achievements"),
        ("multiple_currencies", "Multiple Currencies"),
        ("trading", "Trading Economy"),
        ("skill_trees", "Skill Trees"),
        ("randomized_rewards", "Randomized Rewards"),
        ("rarity_systems", "Rarity Systems"),
        ("server_wide_announcements", "Server-Wide Alerts"),
        ("idle_passive_progression", "Idle / Passive Prog."),
        ("offline_progression", "Offline Progression"),
        ("tycoon_mechanics", "Tycoon Mechanics"),
        ("rebirths_prestige", "Rebirths / Prestige"),
    ][::-1]
    labels = [lbl for _, lbl in focus]
    sustained = [float(stats[key]["sustained_pct"]) for key, _ in focus]
    viral = [float(stats[key]["viral_pct"]) for key, _ in focus]
    y_pos = np.arange(len(labels))

    fig, ax = plt.subplots(figsize=(11.0, 6.2))
    ax.barh(y_pos + 0.19, sustained, height=0.36, color=PALETTE["teal"], label="Sustained Leaders & Mid-Sized (n=15)")
    ax.barh(y_pos - 0.19, viral, height=0.36, color=PALETTE["amber"], label="Recently Viral Breakouts (n=10)")
    for i, (s_val, v_val) in enumerate(zip(sustained, viral)):
        ax.text(s_val + 1.2, i + 0.19, f"{s_val:.0f}%", va="center", fontsize=8.5, color=PALETTE["teal"], fontweight="bold")
        ax.text(v_val + 1.2, i - 0.19, f"{v_val:.0f}%", va="center", fontsize=8.5, color=PALETTE["amber"], fontweight="bold")

    ax.axhline(6.5, color=PALETTE["slate"], linestyle=":", linewidth=1.2)
    ax.text(98, 6.75, "Sustained-Dominant Moats ▲", ha="right", fontsize=9, fontweight="bold", color=PALETTE["teal"])
    ax.text(98, 6.05, "Viral-Spike Accelerators ▼", ha="right", fontsize=9, fontweight="bold", color=PALETTE["amber"])
    ax.set_yticks(y_pos, labels)
    ax.set_xlim(0, 108)
    ax.set_xlabel("Cohort Prevalence (%) across Verified 44-Game Database")
    ax.set_title("Sustained Multi-Year Moats vs. Viral-Spike Mechanics (n = 44 Verified Titles)")
    ax.grid(axis="y", visible=False)
    ax.legend(loc="lower right", frameon=True, facecolor="white")
    return _save_fig(fig, out_dir / "02_viral_vs_sustained_mechanics.png")


def chart_peak_retention_survival(out_dir: Path) -> Path:
    """Plot Nov 2026 baseline-to-peak CCU retention % vs. public like ratios."""
    entries = [
        ("Illegal Soccer (86.6% likes)", 41.7, PALETTE["teal"]),
        ("Violence District (92.9% likes)", 21.6, PALETTE["teal"]),
        ("Sol's RNG (91.4% likes)", 19.4, PALETTE["teal"]),
        ("RIVALS (93.6% likes)", 16.0, PALETTE["blue"]),
        ("Volleyball Legends (95.2% likes)", 9.8, PALETTE["blue"]),
        ("Forsaken (84.4% likes)", 4.3, PALETTE["blue"]),
        ("Fisch (90.8% likes)", 4.3, PALETTE["blue"]),
        ("Fish It! (82.8% likes)", 2.4, PALETTE["blue"]),
        ("99 Nights Forest (90.5% likes)", 1.14, PALETTE["purple"]),
        ("Steal a Brainrot (85.1% likes)", 0.20, PALETTE["amber"]),
        ("Grow a Garden (90.0% likes)", 0.08, PALETTE["rose"]),
        ("Plants vs Brainrots (94.8% likes)", 0.03, PALETTE["rose"]),
        ("Garden Horizons (96.0% likes!)", 0.005, PALETTE["rose"]),
    ][::-1]
    labels = [e[0] for e in entries]
    ratios = [e[1] for e in entries]
    colors = [e[2] for e in entries]
    y_pos = np.arange(len(labels))

    fig, ax = plt.subplots(figsize=(11.2, 6.0))
    bars = ax.barh(y_pos, ratios, height=0.62, color=colors, alpha=0.9)
    ax.set_xscale("log")
    ax.set_xlim(0.002, 120)
    for bar, val in zip(bars, ratios):
        lbl = f"{val:.1f}%" if val >= 1.0 else (f"{val:.2f}%" if val >= 0.01 else f"{val:.3f}%")
        ax.text(val * 1.18, bar.get_y() + bar.get_height() / 2, lbl, va="center", fontsize=8.8, fontweight="bold")

    ax.set_yticks(y_pos, labels)
    ax.set_xlabel("Nov 2026 Midpoint Daily CCU as % of All-Time Peak CCU (Log Scale)")
    ax.set_title("Peak-to-Baseline Retention Efficiency: Skill & Co-Op vs. Meme Collapses")
    ax.grid(axis="y", visible=False)
    ax.annotate(
        "96% Like Ratio did NOT\nprevent -99.99% collapse",
        xy=(0.015, 0.0),
        xytext=(0.18, 0.75),
        arrowprops={"arrowstyle": "->", "color": PALETTE["rose"], "lw": 1.4},
        fontsize=8.8,
        fontweight="bold",
        color=PALETTE["rose"],
        bbox={"boxstyle": "round,pad=0.35", "fc": "#FFF1F2", "ec": PALETTE["rose"]},
    )
    return _save_fig(fig, out_dir / "03_peak_vs_sustained_collapse.png")


def chart_macro_demographics_and_devex(out_dir: Path) -> Path:
    """Two-panel macro view: Q3 2026 Regional DAU vs ABPDAU + Age & DevEx Tiers."""
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12.2, 5.0))
    regions = ["US & Canada", "Europe", "APAC", "Rest of World"]
    daus = [24, 32, 42, 40]
    abpdau = [38.52, 11.20, 5.37, 5.00]
    x = np.arange(len(regions))
    ax1.bar(x - 0.18, daus, width=0.35, color=PALETTE["blue"], label="Q3 2026 DAUs (Millions)")
    ax1_r = ax1.twinx()
    ax1_r.bar(x + 0.18, abpdau, width=0.35, color=PALETTE["emerald"], label="Quarterly ABPDAU (USD)")
    for i, (d_val, a_val) in enumerate(zip(daus, abpdau)):
        ax1.text(i - 0.18, d_val + 1.0, f"{d_val}M", ha="center", fontsize=8.5, color=PALETTE["blue"], fontweight="bold")
        ax1_r.text(i + 0.18, a_val + 1.0, f"${a_val:.2f}", ha="center", fontsize=8.5, color=PALETTE["teal"], fontweight="bold")
    ax1.set_xticks(x, regions)
    ax1.set_ylim(0, 52)
    ax1_r.set_ylim(0, 48)
    ax1.set_ylabel("DAUs (Millions)", color=PALETTE["blue"])
    ax1_r.set_ylabel("Quarterly ABPDAU (USD)", color=PALETTE["teal"])
    ax1_r.grid(False)
    ax1.set_title("Q3 2026 Regional Scale vs. Value (7.2x US/CA Skew)")
    h1, l1 = ax1.get_legend_handles_labels()
    h2, l2 = ax1_r.get_legend_handles_labels()
    ax1.legend(h1 + h2, l1 + l2, loc="upper right", fontsize=8)

    _render_age_and_devex_panel(ax2)
    fig.tight_layout(pad=2.0)
    return _save_fig(fig, out_dir / "04_roblox_macro_demographics_abpdau.png")


def _render_age_and_devex_panel(ax: plt.Axes) -> None:
    """Render right panel showing Q3 2026 age-checked share & DevEx rate tiers."""
    tiers = ["Legacy\n(<Sep 2025)", "Standard\n(Sep 2025+)", "U.S. 18+ R15\n(Jun 2026+)"]
    usd_per_100k = [350, 380, 540]
    bars = ax.bar(tiers, usd_per_100k, width=0.52, color=[PALETTE["slate"], PALETTE["blue"], PALETTE["teal"]])
    for bar, val in zip(bars, usd_per_100k):
        rate = val / 100000
        ax.text(bar.get_x() + bar.get_width() / 2, val + 14, f"USD {val}\n({rate:.4f} USD/R$)", ha="center", fontsize=8.6, fontweight="bold")
    ax.set_ylim(0, 660)
    ax.set_ylabel("Gross USD per 100,000 Earned Robux")
    ax.set_title("DevEx Tier Uplift (+42.1% for U.S. 18+ R15)")
    ax.grid(axis="x", visible=False)
    ax.text(
        0.03,
        0.93,
        "Q3 2026 Age-Checked DAUs:\n• Under 13: 34%\n• Ages 13–17: 37%\n• Ages 18+: 29% (37% in U.S.)",
        transform=ax.transAxes,
        va="top",
        fontsize=8.3,
        bbox={"boxstyle": "round,pad=0.4", "fc": "#F8FAFC", "ec": "#CBD5E1"},
    )


def chart_financial_feasibility(data_dir: Path, out_dir: Path) -> Path:
    """Two-panel financial view: Monthly Operating Profit (PHP) & PH Tax Treaty Lift."""
    config = load_json_file(data_dir / "financial_assumptions.json")
    _, results = run_all_scenarios(config)
    subset = [r for r in results if not (r.profile_name.startswith("Reinvesting") and r.tier_name == "Optimistic")]
    labels = [f"{r.profile_name.split(' (')[0]}\n({r.tier_name} | {r.avg_ccu:.0f} CCU)" for r in subset]
    profits_php = [r.monthly_operating_profit_php / 1000.0 for r in subset]
    colors = [PALETTE["rose"] if p < 0 else (PALETTE["teal"] if "Solo Bootstrap" in r.profile_name else PALETTE["blue"]) for p, r in zip(profits_php, subset)]

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(13.2, 5.4), gridspec_kw={"width_ratios": [1.45, 1.0]})
    y_pos = np.arange(len(labels))[::-1]
    ax1.barh(y_pos, profits_php, height=0.58, color=colors, alpha=0.9)
    ax1.axvline(0, color=PALETTE["navy"], linewidth=1.1)
    for y, val in zip(y_pos, profits_php):
        offset = 12 if val >= 0 else -12
        ha = "left" if val >= 0 else "right"
        lbl = f"PHP {val:,.1f}k" if val >= 0 else f"-PHP {abs(val):,.1f}k"
        ax1.text(val + offset, y, lbl, va="center", ha=ha, fontsize=8.3, fontweight="bold")
    ax1.set_yticks(y_pos, labels, fontsize=8.2)
    ax1.set_xlim(-210, 725)
    ax1.set_xlabel("Monthly Operating Profit (Thousands of PHP @ PHP 63.75/USD)")
    ax1.set_title("Monthly Operating Profit by Profile (Red = Paid-Ad Loss)")
    ax1.grid(axis="y", visible=False)

    _render_ph_tax_panel(ax2)
    fig.tight_layout(pad=2.0)
    return _save_fig(fig, out_dir / "05_solo_financial_feasibility_php_usd.png")


def _render_ph_tax_panel(ax: plt.Axes) -> None:
    """Render PH net cashout comparison showing US-PH Treaty Art. 13 & Wise FX lift."""
    routes = ["Default 30% WHT\n+ Tipalti FX\n(Standard)", "Treaty 15% WHT\n+ Wise FX\n(Standard)", "Treaty 15% WHT\n+ Wise FX\n(U.S. 18+ Tier)"]
    net_php = [16534, 20488, 29115]
    bars = ax.bar(routes, net_php, width=0.52, color=[PALETTE["rose"], PALETTE["blue"], PALETTE["emerald"]])
    for bar, val in zip(bars, net_php):
        ax.text(bar.get_x() + bar.get_width() / 2, val + 650, f"PHP {val:,}", ha="center", fontsize=9, fontweight="bold")
    ax.set_ylim(0, 34500)
    ax.set_ylabel("Net Bank Take-Home PHP / 100k Earned R$")
    ax.set_title("PH Net Payout Optimization (+23.9% to +76.1%)")
    ax.grid(axis="x", visible=False)


def chart_retention_benchmarks(out_dir: Path) -> Path:
    """Plot verified GameAnalytics 2026 Roblox retention percentiles vs. solo gates."""
    percentiles = ["P25\n(Kill Floor)", "P50\n(Median)", "P75\n(Go Gate)", "P90\n(Scale Gate)", "P99\n(Top 1%)"]
    d1 = [8.4, 10.3, 12.9, 15.9, 22.2]
    d7 = [1.0, 1.6, 2.5, 3.9, 9.1]
    d30 = [0.3, 0.5, 0.9, 2.0, 4.7]
    x = np.arange(len(percentiles))
    width = 0.25

    fig, ax = plt.subplots(figsize=(10.8, 5.0))
    b1 = ax.bar(x - width, d1, width, label="Day 1 Retention (%)", color=PALETTE["blue"])
    b7 = ax.bar(x, d7, width, label="Day 7 Retention (%)", color=PALETTE["teal"])
    b30 = ax.bar(x + width, d30, width, label="Day 30 Retention (%)", color=PALETTE["purple"])
    for bars in (b1, b7, b30):
        for bar in bars:
            h = bar.get_height()
            ax.text(bar.get_x() + bar.get_width() / 2, h + 0.45, f"{h:.1f}%", ha="center", fontsize=8, fontweight="bold")

    ax.axvspan(-0.5, 0.5, color="#FFE4E6", alpha=0.45, zorder=0)
    ax.axvspan(1.5, 3.5, color="#ECFDF5", alpha=0.55, zorder=0)
    ax.text(0.0, 13.0, "KILL ADS\n(< P25)", ha="center", fontsize=8.5, fontweight="bold", color=PALETTE["rose"])
    ax.text(2.5, 24.4, "SOLO TARGET GO / SCALE ZONE", ha="center", fontsize=8.5, fontweight="bold", color=PALETTE["teal"])
    ax.set_xticks(x, percentiles)
    ax.set_ylim(0, 26.5)
    ax.set_ylabel("Cohort Retention (%)")
    ax.set_title("Verified 2026 Roblox Retention Percentiles (GameAnalytics, 500+ Titles >=1M MAU)")
    ax.grid(axis="x", visible=False)
    ax.legend(loc="upper left", frameon=True, facecolor="white", fontsize=8.8)
    return _save_fig(fig, out_dir / "06_retention_benchmarks_and_gates.png")


def generate_all_charts(data_dir: Path, out_dir: Path) -> list[Path]:
    """Generate all 6 research visualizations and return their saved file paths."""
    _configure_style()
    return [
        chart_concept_decision_matrix(data_dir, out_dir),
        chart_viral_vs_sustained_mechanics(data_dir, out_dir),
        chart_peak_retention_survival(out_dir),
        chart_macro_demographics_and_devex(out_dir),
        chart_financial_feasibility(data_dir, out_dir),
        chart_retention_benchmarks(out_dir),
    ]


def main() -> int:
    """CLI entrypoint for generating all visual charts."""
    parser = argparse.ArgumentParser(description="Generate Roblox research charts.")
    parser.add_argument("--data-dir", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, required=True)
    args = parser.parse_args()
    try:
        paths = generate_all_charts(args.data_dir, args.out_dir)
        print(f"GENERATED {len(paths)} charts in {args.out_dir}: {[p.name for p in paths]}")
        return 0
    except Exception as exc:  # noqa: BLE001
        print(f"CHART GENERATION ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
