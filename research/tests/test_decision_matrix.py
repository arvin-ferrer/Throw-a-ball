"""Unit tests for decision_matrix.py."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

from common import ResearchDataError
from decision_matrix import (
    BASELINE_WEIGHTS,
    render_sensitivity_markdown,
    run_sensitivity_suite,
    score_concepts,
    validate_weights,
)


def _make_concept(cid: str, name: str, base: float, overrides: dict[str, float] | None = None) -> dict:
    overrides = overrides or {}
    return {
        "id": cid,
        "name": name,
        "overall_confidence": "Medium",
        "scores": {
            crit: {"score": overrides.get(crit, base), "rationale": "test"}
            for crit in BASELINE_WEIGHTS
        },
    }


class TestDecisionMatrix(unittest.TestCase):
    """Verify exact weighting, bounds checks, and sensitivity ranking behavior."""

    def test_baseline_weights_sum_to_one(self) -> None:
        validate_weights(BASELINE_WEIGHTS)

    def test_invalid_weights_raise(self) -> None:
        bad = dict(BASELINE_WEIGHTS)
        bad["player_demand"] = 0.50
        with self.assertRaises(ResearchDataError):
            validate_weights(bad)

    def test_out_of_bounds_score_raises(self) -> None:
        concepts = [_make_concept(f"C{i}", f"Concept {i}", 6.0) for i in range(6)]
        concepts[0]["scores"]["player_demand"]["score"] = 11.0
        with self.assertRaises(ResearchDataError):
            run_sensitivity_suite(concepts)

    def test_sensitivity_shifts_rankings(self) -> None:
        concepts = [
            _make_concept("C0", "Prelim", 5.0),
            _make_concept("C1", "FeasibleChamp", 6.0, {"development_feasibility": 10.0, "monetization_potential": 4.0}),
            _make_concept("C2", "ProfitChamp", 6.0, {"development_feasibility": 4.0, "monetization_potential": 10.0}),
            _make_concept("C3", "ViralChamp", 6.0, {"organic_discovery_potential": 10.0, "viral_and_social_potential": 10.0}),
            _make_concept("C4", "SustainChamp", 6.0, {"long_term_sustainability": 10.0, "player_retention_potential": 10.0}),
            _make_concept("C5", "Balanced", 6.5),
        ]
        results = run_sensitivity_suite(concepts)
        self.assertEqual(results["Feasibility Priority"][0]["name"], "FeasibleChamp")
        self.assertEqual(results["Profitability Priority"][0]["name"], "ProfitChamp")
        self.assertEqual(results["Organic Growth Priority"][0]["name"], "ViralChamp")
        self.assertEqual(results["Sustainability Priority"][0]["name"], "SustainChamp")
        md = render_sensitivity_markdown(results)
        self.assertIn("FeasibleChamp", md)

    def test_deterministic_tie_breaking(self) -> None:
        c_b = _make_concept("CB", "Beta", 7.0)
        c_a = _make_concept("CA", "Alpha", 7.0)
        ranked = score_concepts([c_b, c_a], BASELINE_WEIGHTS)
        self.assertEqual([r["name"] for r in ranked], ["Alpha", "Beta"])


if __name__ == "__main__":
    unittest.main()
