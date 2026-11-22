"""Unit tests for financial_model.py."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

from common import ResearchDataError
from financial_model import PlatformRates, evaluate_scenario, parse_platform_rates, render_financial_markdown


class TestFinancialModel(unittest.TestCase):
    """Verify DevEx rates, Marketplace cut, DAU->CCU math, and edge cases."""

    def setUp(self) -> None:
        self.rates = PlatformRates(
            marketplace_take_rate=0.30,
            devex_standard_usd=0.0038,
            devex_us18_usd=0.0054,
            usd_to_php=58.50,
            fx_date="2026-11-22",
        )

    def test_standard_devex_and_marketplace_cut(self) -> None:
        scenario = {
            "tier": "Moderate",
            "dau": 1000,
            "mau_to_dau_ratio": 4.0,
            "sessions_per_day": 1.5,
            "avg_session_minutes": 16.0,
            "monthly_payer_conversion": 0.025,
            "monthly_arppu_robux": 400.0,
            "monthly_creator_rewards_robux_per_dau": 5.0,
            "us18_spend_share": 0.0,
            "monthly_ad_spend_usd": 50.0,
            "monthly_maintenance_usd": 10.0,
            "upfront_dev_cost_usd": 300.0,
        }
        res = evaluate_scenario("Solo", scenario, self.rates)
        # MAU = 4000; payers = 100; gross = 40,000 R$; net purchase = 28,000 + 5,000 CR = 33,000 R$
        self.assertAlmostEqual(res.monthly_gross_robux, 40000.0)
        self.assertAlmostEqual(res.monthly_earned_robux, 33000.0)
        self.assertAlmostEqual(res.monthly_dev_earnings_usd, 33000.0 * 0.0038)
        self.assertAlmostEqual(res.monthly_dev_earnings_php, 33000.0 * 0.0038 * 58.50)
        self.assertAlmostEqual(res.avg_ccu, (1000 * 1.5 * 16.0) / 1440.0)
        self.assertAlmostEqual(res.monthly_operating_profit_usd, 33000.0 * 0.0038 - 60.0)
        self.assertIsNotNone(res.break_even_dau)
        self.assertAlmostEqual(res.ad_roas or 0.0, (33000.0 * 0.0038) / 50.0)

    def test_blended_us18_devex_rate(self) -> None:
        scenario = {
            "tier": "Optimistic",
            "dau": 1000,
            "mau_to_dau_ratio": 3.0,
            "sessions_per_day": 1.0,
            "avg_session_minutes": 14.4,
            "monthly_payer_conversion": 0.05,
            "monthly_arppu_robux": 1000.0,
            "monthly_creator_rewards_robux_per_dau": 0.0,
            "us18_spend_share": 0.25,
            "monthly_ad_spend_usd": 0.0,
            "monthly_maintenance_usd": 0.0,
            "upfront_dev_cost_usd": 0.0,
        }
        res = evaluate_scenario("Solo Zero", scenario, self.rates)
        expected_rate = 0.0038 * 0.75 + 0.0054 * 0.25
        self.assertAlmostEqual(res.effective_devex_rate, expected_rate)
        self.assertEqual(res.break_even_dau, 0)
        self.assertIsNone(res.ad_roas)
        self.assertIsNone(res.cost_recovery_months)

    def test_zero_revenue_break_even_is_none(self) -> None:
        scenario = {
            "tier": "ZeroPayer",
            "dau": 500,
            "sessions_per_day": 1.0,
            "avg_session_minutes": 10.0,
            "monthly_payer_conversion": 0.0,
            "monthly_arppu_robux": 0.0,
            "monthly_ad_spend_usd": 100.0,
            "monthly_maintenance_usd": 20.0,
            "upfront_dev_cost_usd": 500.0,
        }
        res = evaluate_scenario("Fail", scenario, self.rates)
        self.assertIsNone(res.break_even_dau)
        self.assertIsNone(res.cost_recovery_months)
        self.assertLess(res.monthly_operating_profit_usd, 0.0)

    def test_invalid_rates_rejected(self) -> None:
        with self.assertRaises(ResearchDataError):
            parse_platform_rates(
                {
                    "marketplace_take_rate": 1.2,
                    "devex_standard_usd": 0.0038,
                    "devex_us18_usd": 0.0054,
                    "usd_to_php": 58.0,
                    "fx_date": "2026-11-22",
                }
            )

    def test_markdown_renderer_contains_php_and_usd(self) -> None:
        scenario = {
            "tier": "Conservative",
            "dau": 200,
            "sessions_per_day": 1.2,
            "avg_session_minutes": 10.0,
            "monthly_payer_conversion": 0.015,
            "monthly_arppu_robux": 250.0,
            "monthly_ad_spend_usd": 0.0,
            "monthly_maintenance_usd": 5.0,
            "upfront_dev_cost_usd": 100.0,
        }
        md = render_financial_markdown([evaluate_scenario("Solo", scenario, self.rates)], self.rates)
        self.assertIn("PHP ", md)
        self.assertIn("$0.0038/R$", md)


if __name__ == "__main__":
    unittest.main()
