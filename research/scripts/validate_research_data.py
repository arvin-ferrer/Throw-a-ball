"""Schema validator and feature-frequency analyzer for Roblox research datasets."""

from __future__ import annotations

import argparse
import re
import sys
from collections import Counter
from pathlib import Path

from common import (
    EVIDENCE_LEVELS,
    GAME_CATEGORIES,
    SOURCE_TIERS,
    ResearchDataError,
    load_csv_rows,
    load_json_file,
)

ISO_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")

REQUIRED_GAME_COLUMNS: tuple[str, ...] = (
    "game_id",
    "title",
    "developer",
    "category",
    "release_date",
    "genre",
    "current_ccu",
    "peak_ccu",
    "total_visits",
    "recent_visit_growth",
    "like_ratio",
    "favorites",
    "growth_trajectory",
    "avg_session_duration",
    "update_frequency",
    "monetization_methods",
    "core_loop",
    "progression_systems",
    "social_mechanics",
    "unique_selling_prop",
    "dev_complexity",
    "collection_date",
    "evidence_level",
    "source_refs",
)

EXPECTED_MECHANIC_COUNT = 41


def validate_games_database(path: Path) -> list[dict[str, str]]:
    """Validate competitive game database schema, category coverage, and evidence tags."""
    headers, rows = load_csv_rows(path)
    missing = [col for col in REQUIRED_GAME_COLUMNS if col not in headers]
    if missing:
        raise ResearchDataError(f"games_database.csv missing columns: {missing}")
    if not (30 <= len(rows) <= 50):
        raise ResearchDataError(
            f"Expected 30-50 games per Research.txt Section 3, found {len(rows)}"
        )
    seen_ids: set[str] = set()
    category_counts: Counter[str] = Counter()
    for idx, row in enumerate(rows, start=2):
        _validate_single_game_row(row, idx, seen_ids, category_counts)
    missing_cats = [cat for cat in GAME_CATEGORIES if category_counts[cat] == 0]
    if missing_cats:
        raise ResearchDataError(f"Missing required game categories: {missing_cats}")
    return rows


def _validate_single_game_row(
    row: dict[str, str],
    line_no: int,
    seen_ids: set[str],
    category_counts: Counter[str],
) -> None:
    """Validate required fields and constraints for one game record."""
    game_id = row["game_id"]
    if not game_id or game_id in seen_ids:
        raise ResearchDataError(f"Line {line_no}: empty or duplicate game_id '{game_id}'")
    seen_ids.add(game_id)
    for col in REQUIRED_GAME_COLUMNS:
        if not row.get(col):
            raise ResearchDataError(f"Line {line_no} ({game_id}): blank field '{col}'")
    if row["category"] not in GAME_CATEGORIES:
        raise ResearchDataError(f"Line {line_no}: invalid category '{row['category']}'")
    if not ISO_DATE_RE.match(row["collection_date"]):
        raise ResearchDataError(
            f"Line {line_no}: collection_date '{row['collection_date']}' must be YYYY-MM-DD"
        )
    if row["evidence_level"] not in EVIDENCE_LEVELS:
        raise ResearchDataError(
            f"Line {line_no}: invalid evidence_level '{row['evidence_level']}'"
        )
    category_counts[row["category"]] += 1


def validate_feature_matrix(
    path: Path, valid_game_ids: set[str]
) -> tuple[list[str], list[dict[str, str]]]:
    """Validate 41-mechanic feature matrix alignment and binary values (0/1)."""
    headers, rows = load_csv_rows(path)
    if "game_id" not in headers or "category" not in headers:
        raise ResearchDataError("feature_matrix.csv must contain game_id and category")
    mechanic_cols = [col for col in headers if col not in ("game_id", "title", "category")]
    if len(mechanic_cols) != EXPECTED_MECHANIC_COUNT:
        raise ResearchDataError(
            f"Expected {EXPECTED_MECHANIC_COUNT} mechanic columns, found {len(mechanic_cols)}"
        )
    matrix_ids: set[str] = set()
    for idx, row in enumerate(rows, start=2):
        gid = row["game_id"]
        if gid not in valid_game_ids:
            raise ResearchDataError(f"feature_matrix line {idx}: unknown game_id '{gid}'")
        matrix_ids.add(gid)
        for mech in mechanic_cols:
            if row[mech] not in ("0", "1"):
                raise ResearchDataError(
                    f"feature_matrix line {idx} ({gid}, {mech}): expected '0' or '1', got '{row[mech]}'"
                )
    if matrix_ids != valid_game_ids:
        raise ResearchDataError("feature_matrix game_ids do not match games_database.csv")
    return mechanic_cols, rows


def validate_sources_registry(path: Path) -> list[dict[str, str]]:
    """Validate centralized source registry entries and source tiers."""
    data = load_json_file(path)
    if not isinstance(data, list) or not data:
        raise ResearchDataError("sources_registry.json must be a non-empty JSON list")
    seen: set[str] = set()
    required = ("source_id", "title", "publisher", "tier", "collection_date", "reference")
    for idx, item in enumerate(data):
        for field in required:
            if not item.get(field):
                raise ResearchDataError(f"Source entry {idx}: missing '{field}'")
        sid = item["source_id"]
        if sid in seen:
            raise ResearchDataError(f"Duplicate source_id: {sid}")
        seen.add(sid)
        if item["tier"] not in SOURCE_TIERS:
            raise ResearchDataError(f"Source {sid}: invalid tier '{item['tier']}'")
        if not ISO_DATE_RE.match(item["collection_date"]):
            raise ResearchDataError(f"Source {sid}: invalid collection_date")
    return data


def compute_mechanic_frequencies(
    mechanic_cols: list[str], rows: list[dict[str, str]]
) -> list[dict[str, float | int | str]]:
    """Calculate overall and cohort prevalence rates for every tracked mechanic."""
    total = len(rows)
    viral_rows = [r for r in rows if r["category"] == "Recently viral games"]
    leader_rows = [
        r
        for r in rows
        if r["category"] in ("Established market leaders", "Sustainable mid-sized games")
    ]
    simple_rows = [
        r for r in rows if r["category"] == "Simple-mechanic disproportionate results"
    ]
    stats: list[dict[str, float | int | str]] = []
    for mech in mechanic_cols:
        count = sum(int(r[mech]) for r in rows)
        stats.append(
            {
                "mechanic": mech,
                "count": count,
                "overall_pct": round(100.0 * count / total, 1) if total else 0.0,
                "viral_pct": _cohort_pct(viral_rows, mech),
                "sustained_pct": _cohort_pct(leader_rows, mech),
                "simple_pct": _cohort_pct(simple_rows, mech),
            }
        )
    return sorted(stats, key=lambda item: (-int(item["count"]), str(item["mechanic"])))


def _cohort_pct(rows: list[dict[str, str]], mechanic: str) -> float:
    """Compute prevalence percentage within a category cohort."""
    if not rows:
        return 0.0
    return round(100.0 * sum(int(r[mechanic]) for r in rows) / len(rows), 1)


def render_frequency_markdown(stats: list[dict[str, float | int | str]], total: int) -> str:
    """Render computed feature frequencies as a Markdown table."""
    lines = [
        "| Mechanic | Count (n=" + str(total) + ") | Overall % | Viral % | Sustained % | Simple-Hit % |",
        "| --- | ---: | ---: | ---: | ---: | ---: |",
    ]
    for item in stats:
        lines.append(
            f"| {item['mechanic']} | {item['count']} | {item['overall_pct']:.1f}% | "
            f"{item['viral_pct']:.1f}% | {item['sustained_pct']:.1f}% | {item['simple_pct']:.1f}% |"
        )
    return "\n".join(lines)


def main() -> int:
    """CLI entrypoint for dataset validation and frequency reporting."""
    parser = argparse.ArgumentParser(description="Validate Roblox research datasets.")
    parser.add_argument("--data-dir", type=Path, required=True)
    parser.add_argument("--print-frequencies", action="store_true")
    args = parser.parse_args()
    try:
        games = validate_games_database(args.data_dir / "games_database.csv")
        game_ids = {row["game_id"] for row in games}
        mechanics, matrix_rows = validate_feature_matrix(
            args.data_dir / "feature_matrix.csv", game_ids
        )
        sources = validate_sources_registry(args.data_dir / "sources_registry.json")
        stats = compute_mechanic_frequencies(mechanics, matrix_rows)
        if args.print_frequencies:
            print(render_frequency_markdown(stats, len(games)))
        print(
            f"VALID: {len(games)} games, {len(mechanics)} mechanics, {len(sources)} sources."
        )
        return 0
    except ResearchDataError as exc:
        print(f"VALIDATION FAILED: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
