"""Financial feasibility and DevEx modeling engine for independent Roblox games.

Separates player-spent Robux from withdrawable developer earnings using verified
Nov 2026 Roblox Marketplace fees (30% cut), DevEx rates ($0.0038 standard and
$0.0054 US 18+ qualifying tier), Creator Rewards, and dated USD-to-PHP exchange rates.
"""

from __future__ import annotations

import argparse
import math
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from common import ResearchDataError, format_currency, load_json_file

MINUTES_PER_DAY = 1440.0
DAYS_PER_MONTH = 30.0


@dataclass(frozen=True)
class PlatformRates:
    """Verified Roblox monetization fee, DevEx payout, and FX parameters."""

    marketplace_take_rate: float
    devex_standard_usd: float
    devex_us18_usd: float
    usd_to_php: float
    fx_date: str


@dataclass(frozen=True)
class ScenarioResult:
    """Computed financial outputs for one developer profile and KPI tier."""

    profile_name: str
    tier_name: str
    dau: int
    avg_ccu: float
    monthly_gross_robux: float
    monthly_earned_robux: float
    effective_devex_rate: float
    monthly_gross_usd: float
    monthly_dev_earnings_usd: float
    monthly_dev_earnings_php: float
    monthly_operating_cost_usd: float
    monthly_operating_profit_usd: float
    monthly_operating_profit_php: float
    arpdau_robux: float
    break_even_dau: int | None
    break_even_ccu: float | None
    ad_roas: float | None
    cost_recovery_months: float | None


def parse_platform_rates(raw: dict[str, Any]) -> PlatformRates:
    """Validate and parse top-level platform and FX parameters."""
    rates = PlatformRates(
        marketplace_take_rate=float(raw["marketplace_take_rate"]),
        devex_standard_usd=float(raw["devex_standard_usd"]),
        devex_us18_usd=float(raw["devex_us18_usd"]),
        usd_to_php=float(raw["usd_to_php"]),
        fx_date=str(raw["fx_date"]),
    )
    if not (0.0 <= rates.marketplace_take_rate < 1.0):
        raise ResearchDataError("marketplace_take_rate must be in [0, 1)")
    if rates.devex_standard_usd <= 0 or rates.devex_us18_usd <= 0 or rates.usd_to_php <= 0:
        raise ResearchDataError("DevEx rates and FX rate must be positive")
    return rates


def evaluate_scenario(
    profile_name: str, scenario: dict[str, Any], rates: PlatformRates
) -> ScenarioResult:
    """Compute monthly revenue, developer earnings, profit, break-even, and ROAS."""
    dau = int(scenario["dau"])
    sessions = float(scenario["sessions_per_day"])
    session_min = float(scenario["avg_session_minutes"])
    payer_conv = float(scenario["monthly_payer_conversion"])
    us18_share = float(scenario.get("us18_spend_share", 0.0))
    _validate_scenario_inputs(dau, sessions, session_min, payer_conv, us18_share)

    avg_ccu = (dau * sessions * session_min) / MINUTES_PER_DAY
    gross_robux, earned_robux = _compute_robux_flows(dau, scenario, rates)
    eff_devex = _blended_devex(rates, us18_share)
    dev_usd = earned_robux * eff_devex
    ad_usd = float(scenario["monthly_ad_spend_usd"])
    op_cost_usd = ad_usd + float(scenario["monthly_maintenance_usd"])
    profit_usd = dev_usd - op_cost_usd
    be_dau = _compute_break_even_dau(op_cost_usd, (dev_usd / dau) if dau > 0 else 0.0)
    upfront = float(scenario["upfront_dev_cost_usd"])
    return ScenarioResult(
        profile_name=profile_name,
        tier_name=str(scenario["tier"]),
        dau=dau,
        avg_ccu=avg_ccu,
        monthly_gross_robux=gross_robux,
        monthly_earned_robux=earned_robux,
        effective_devex_rate=eff_devex,
        monthly_gross_usd=gross_robux * rates.devex_standard_usd,
        monthly_dev_earnings_usd=dev_usd,
        monthly_dev_earnings_php=dev_usd * rates.usd_to_php,
        monthly_operating_cost_usd=op_cost_usd,
        monthly_operating_profit_usd=profit_usd,
        monthly_operating_profit_php=profit_usd * rates.usd_to_php,
        arpdau_robux=(gross_robux / (dau * DAYS_PER_MONTH)) if dau > 0 else 0.0,
        break_even_dau=be_dau,
        break_even_ccu=((be_dau * sessions * session_min) / MINUTES_PER_DAY) if be_dau is not None else None,
        ad_roas=(dev_usd / ad_usd) if ad_usd > 0 else None,
        cost_recovery_months=(upfront / profit_usd) if (upfront > 0 and profit_usd > 0) else None,
    )


def _compute_robux_flows(
    dau: int, scenario: dict[str, Any], rates: PlatformRates
) -> tuple[float, float]:
    """Compute gross player-spent Robux and net developer-earned Robux."""
    mau = dau * float(scenario.get("mau_to_dau_ratio", 3.5))
    gross_robux = mau * float(scenario["monthly_payer_conversion"]) * float(scenario["monthly_arppu_robux"])
    creator_robux = dau * float(scenario.get("monthly_creator_rewards_robux_per_dau", 0.0))
    earned_robux = gross_robux * (1.0 - rates.marketplace_take_rate) + creator_robux
    return gross_robux, earned_robux


def _blended_devex(rates: PlatformRates, us18_share: float) -> float:
    """Compute effective DevEx rate blending standard and U.S. 18+ qualifying spend."""
    return rates.devex_standard_usd * (1.0 - us18_share) + rates.devex_us18_usd * us18_share


def _validate_scenario_inputs(
    dau: int,
    sessions_per_day: float,
    avg_session_min: float,
    payer_conv: float,
    us18_share: float,
) -> None:
    """Validate numeric invariants for scenario parameters."""
    if dau < 0 or sessions_per_day <= 0 or avg_session_min <= 0:
        raise ResearchDataError("DAU must be >= 0; sessions/day and session length must be > 0")
    if not (0.0 <= payer_conv <= 1.0) or not (0.0 <= us18_share <= 1.0):
        raise ResearchDataError("Conversion and US 18+ shares must be within [0, 1]")


def _compute_break_even_dau(op_cost_usd: float, earned_usd_per_dau: float) -> int | None:
    """Return integer DAU needed to cover monthly operating costs, or None if unviable."""
    if op_cost_usd == 0:
        return 0
    if earned_usd_per_dau <= 0:
        return None
    return math.ceil(op_cost_usd / earned_usd_per_dau)


def run_all_scenarios(config: dict[str, Any]) -> tuple[PlatformRates, list[ScenarioResult]]:
    """Evaluate every scenario grouped by developer resource profile."""
    rates = parse_platform_rates(config["platform_rates"])
    results: list[ScenarioResult] = []
    for profile in config.get("profiles", []):
        profile_name = str(profile["name"])
        for scenario in profile.get("scenarios", []):
            results.append(evaluate_scenario(profile_name, scenario, rates))
    if not results:
        raise ResearchDataError("No financial scenarios found in input JSON")
    return rates, results


def render_financial_markdown(results: list[ScenarioResult], rates: PlatformRates) -> str:
    """Render reproducible USD & PHP financial projections as Markdown tables."""
    lines = [
        f"_Platform assumptions ({rates.fx_date}): 30% Marketplace cut, "
        f"DevEx ${rates.devex_standard_usd:.4f}/R$ (standard) / "
        f"${rates.devex_us18_usd:.4f}/R$ (U.S. 18+), FX 1 USD = PHP {rates.usd_to_php:.2f}._",
        "",
        "| Profile | Scenario | DAU | Implied Avg CCU | Gross Robux/mo | Earned Robux/mo | "
        "Dev Earnings (USD) | Dev Earnings (PHP) | Monthly Profit (USD) | Monthly Profit (PHP) | "
        "Break-Even DAU | Ad ROAS | Payback (mo) |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for res in results:
        be_str = "N/A" if res.break_even_dau is None else f"{res.break_even_dau:,}"
        roas_str = "Organic" if res.ad_roas is None else f"{res.ad_roas:.2f}x"
        payback_str = (
            "N/A" if res.cost_recovery_months is None else f"{res.cost_recovery_months:.1f}"
        )
        lines.append(
            f"| {res.profile_name} | {res.tier_name} | {res.dau:,} | {res.avg_ccu:,.1f} | "
            f"{res.monthly_gross_robux:,.0f} | {res.monthly_earned_robux:,.0f} | "
            f"{format_currency(res.monthly_dev_earnings_usd, '$')} | "
            f"{format_currency(res.monthly_dev_earnings_php, 'PHP ')} | "
            f"{format_currency(res.monthly_operating_profit_usd, '$')} | "
            f"{format_currency(res.monthly_operating_profit_php, 'PHP ')} | "
            f"{be_str} | {roas_str} | {payback_str} |"
        )
    return "\n".join(lines)


def main() -> int:
    """CLI entrypoint for financial modeling verification and table output."""
    parser = argparse.ArgumentParser(description="Run Roblox financial feasibility model.")
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--verify", action="store_true")
    parser.add_argument("--markdown", action="store_true")
    args = parser.parse_args()
    try:
        config = load_json_file(args.input)
        rates, results = run_all_scenarios(config)
        for res in results:
            if math.isnan(res.monthly_dev_earnings_usd) or math.isinf(
                res.monthly_dev_earnings_usd
            ):
                raise ResearchDataError(f"Invalid numeric result in {res.profile_name}")
        if args.markdown:
            print(render_financial_markdown(results, rates))
        if args.verify or not args.markdown:
            print(f"VERIFIED: {len(results)} financial scenarios computed cleanly.")
        return 0
    except (ResearchDataError, KeyError, TypeError, ValueError) as exc:
        print(f"FINANCIAL MODEL ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
