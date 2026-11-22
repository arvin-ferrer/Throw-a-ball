"""Weighted concept scoring and sensitivity analysis engine for Deliverable J."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any

from common import ResearchDataError, load_json_file

BASELINE_WEIGHTS: dict[str, float] = {
    "player_demand": 0.15,
    "player_retention_potential": 0.15,
    "development_feasibility": 0.15,
    "core_gameplay_appeal": 0.10,
    "organic_discovery_potential": 0.10,
    "viral_and_social_potential": 0.10,
    "competitive_differentiation": 0.10,
    "monetization_potential": 0.10,
    "long_term_sustainability": 0.05,
}

SENSITIVITY_PROFILES: dict[str, dict[str, float]] = {
    "Baseline (Section 15)": BASELINE_WEIGHTS,
    "Feasibility Priority": {
        "player_demand": 0.10,
        "player_retention_potential": 0.10,
        "development_feasibility": 0.35,
        "core_gameplay_appeal": 0.10,
        "organic_discovery_potential": 0.10,
        "viral_and_social_potential": 0.05,
        "competitive_differentiation": 0.05,
        "monetization_potential": 0.10,
        "long_term_sustainability": 0.05,
    },
    "Profitability Priority": {
        "player_demand": 0.15,
        "player_retention_potential": 0.15,
        "development_feasibility": 0.10,
        "core_gameplay_appeal": 0.05,
        "organic_discovery_potential": 0.05,
        "viral_and_social_potential": 0.05,
        "competitive_differentiation": 0.10,
        "monetization_potential": 0.30,
        "long_term_sustainability": 0.05,
    },
    "Organic Growth Priority": {
        "player_demand": 0.10,
        "player_retention_potential": 0.10,
        "development_feasibility": 0.10,
        "core_gameplay_appeal": 0.10,
        "organic_discovery_potential": 0.25,
        "viral_and_social_potential": 0.25,
        "competitive_differentiation": 0.05,
        "monetization_potential": 0.00,
        "long_term_sustainability": 0.05,
    },
    "Sustainability Priority": {
        "player_demand": 0.10,
        "player_retention_potential": 0.25,
        "development_feasibility": 0.10,
        "core_gameplay_appeal": 0.05,
        "organic_discovery_potential": 0.05,
        "viral_and_social_potential": 0.05,
        "competitive_differentiation": 0.10,
        "monetization_potential": 0.05,
        "long_term_sustainability": 0.25,
    },
}


def validate_weights(weights: dict[str, float]) -> None:
    """Ensure weights cover every criterion and sum to 1.00 within float tolerance."""
    if set(weights.keys()) != set(BASELINE_WEIGHTS.keys()):
        raise ResearchDataError("Weight keys do not match Section 15 criteria")
    if any(val < 0.0 for val in weights.values()):
        raise ResearchDataError("Negative weights are not permitted")
    total = sum(weights.values())
    if abs(total - 1.0) > 1e-6:
        raise ResearchDataError(f"Weights must sum to 1.00, got {total:.6f}")


def validate_concepts(concepts: list[dict[str, Any]]) -> None:
    """Validate that at least 6 concepts exist (preliminary + >=5 alternatives) with 1-10 scores."""
    if len(concepts) < 6:
        raise ResearchDataError(
            f"Expected preliminary concept + at least 5 alternatives (>=6), found {len(concepts)}"
        )
    for concept in concepts:
        name = concept.get("name", "<unnamed>")
        scores = concept.get("scores", {})
        if set(scores.keys()) != set(BASELINE_WEIGHTS.keys()):
            raise ResearchDataError(f"Concept '{name}' is missing Section 15 criteria")
        for criterion, entry in scores.items():
            val = float(entry["score"])
            if not (1.0 <= val <= 10.0):
                raise ResearchDataError(
                    f"Concept '{name}' criterion '{criterion}' score {val} outside [1, 10]"
                )


def score_concepts(
    concepts: list[dict[str, Any]], weights: dict[str, float]
) -> list[dict[str, Any]]:
    """Compute weighted scores (0-10 scale) sorted deterministically descending."""
    validate_weights(weights)
    ranked: list[dict[str, Any]] = []
    for concept in concepts:
        total = sum(
            float(concept["scores"][crit]["score"]) * weight
            for crit, weight in weights.items()
        )
        ranked.append(
            {
                "id": concept["id"],
                "name": concept["name"],
                "weighted_score": round(total, 2),
                "confidence": concept.get("overall_confidence", "Medium"),
            }
        )
    ranked.sort(key=lambda item: (-item["weighted_score"], item["name"]))
    for rank_idx, item in enumerate(ranked, start=1):
        item["rank"] = rank_idx
    return ranked


def run_sensitivity_suite(
    concepts: list[dict[str, Any]]
) -> dict[str, list[dict[str, Any]]]:
    """Run baseline plus all 4 Section 15 sensitivity weightings."""
    validate_concepts(concepts)
    return {
        label: score_concepts(concepts, weights)
        for label, weights in SENSITIVITY_PROFILES.items()
    }


def render_sensitivity_markdown(results: dict[str, list[dict[str, Any]]]) -> str:
    """Render side-by-side rank and score comparison across all 5 weighting profiles."""
    profile_names = list(results.keys())
    concept_names = [row["name"] for row in results[profile_names[0]]]
    lookup = {
        profile: {row["name"]: row for row in rows}
        for profile, rows in results.items()
    }
    header = "| Concept | " + " | ".join(profile_names) + " |"
    sep = "| --- | " + " | ".join(["---:" for _ in profile_names]) + " |"
    lines = [header, sep]
    for name in concept_names:
        cells = [
            f"#{lookup[prof][name]['rank']} ({lookup[prof][name]['weighted_score']:.2f})"
            for prof in profile_names
        ]
        lines.append(f"| {name} | " + " | ".join(cells) + " |")
    return "\n".join(lines)


def main() -> int:
    """CLI entrypoint for decision matrix verification and Markdown output."""
    parser = argparse.ArgumentParser(description="Score Roblox game concepts.")
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--verify", action="store_true")
    parser.add_argument("--markdown", action="store_true")
    args = parser.parse_args()
    try:
        payload = load_json_file(args.input)
        concepts = payload.get("concepts", [])
        results = run_sensitivity_suite(concepts)
        if args.markdown:
            print(render_sensitivity_markdown(results))
        if args.verify or not args.markdown:
            leader = results["Baseline (Section 15)"][0]
            print(
                f"VERIFIED: {len(concepts)} concepts scored across {len(results)} profiles. "
                f"Baseline #1: {leader['name']} ({leader['weighted_score']:.2f}/10)."
            )
        return 0
    except (ResearchDataError, KeyError, TypeError, ValueError) as exc:
        print(f"DECISION MATRIX ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
