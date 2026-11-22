"""Unit tests for validate_research_data.py."""

from __future__ import annotations

import csv
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

from common import GAME_CATEGORIES, ResearchDataError
from validate_research_data import (
    EXPECTED_MECHANIC_COUNT,
    REQUIRED_GAME_COLUMNS,
    compute_mechanic_frequencies,
    validate_feature_matrix,
    validate_games_database,
    validate_sources_registry,
)


class TestValidateResearchData(unittest.TestCase):
    """Verify CSV/JSON schema enforcement and mechanic frequency calculations."""

    def _write_fixture(self, root: Path, count: int = 30) -> tuple[Path, Path, Path]:
        games_path = root / "games_database.csv"
        with games_path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=REQUIRED_GAME_COLUMNS)
            writer.writeheader()
            for idx in range(count):
                cat = GAME_CATEGORIES[idx % len(GAME_CATEGORIES)]
                row = {col: "Sample" for col in REQUIRED_GAME_COLUMNS}
                row.update(
                    {
                        "game_id": f"G{idx+1:02d}",
                        "title": f"Game {idx+1}",
                        "category": cat,
                        "collection_date": "2026-11-22",
                        "evidence_level": "Strongly supported by evidence",
                    }
                )
                writer.writerow(row)

        mechanics = [f"mech_{i:02d}" for i in range(EXPECTED_MECHANIC_COUNT)]
        matrix_path = root / "feature_matrix.csv"
        with matrix_path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=["game_id", "title", "category", *mechanics])
            writer.writeheader()
            for idx in range(count):
                row = {
                    "game_id": f"G{idx+1:02d}",
                    "title": f"Game {idx+1}",
                    "category": GAME_CATEGORIES[idx % len(GAME_CATEGORIES)],
                }
                for m_idx, mech in enumerate(mechanics):
                    row[mech] = "1" if (m_idx == 0 or (m_idx == 1 and idx % 2 == 0)) else "0"
                writer.writerow(row)

        sources_path = root / "sources_registry.json"
        sources_path.write_text(
            json.dumps(
                [
                    {
                        "source_id": "S01",
                        "title": "Roblox Creator Hub",
                        "publisher": "Roblox",
                        "tier": "Primary",
                        "collection_date": "2026-11-22",
                        "reference": "create.roblox.com",
                    }
                ]
            ),
            encoding="utf-8",
        )
        return games_path, matrix_path, sources_path

    def test_valid_datasets_pass_and_compute_frequencies(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            games_p, matrix_p, sources_p = self._write_fixture(Path(tmp), count=30)
            games = validate_games_database(games_p)
            self.assertEqual(len(games), 30)
            mechs, rows = validate_feature_matrix(matrix_p, {g["game_id"] for g in games})
            stats = compute_mechanic_frequencies(mechs, rows)
            self.assertEqual(stats[0]["mechanic"], "mech_00")
            self.assertEqual(stats[0]["overall_pct"], 100.0)
            self.assertEqual(stats[1]["mechanic"], "mech_01")
            self.assertEqual(stats[1]["overall_pct"], 50.0)
            sources = validate_sources_registry(sources_p)
            self.assertEqual(len(sources), 1)

    def test_too_few_games_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            games_p, _, _ = self._write_fixture(Path(tmp), count=12)
            with self.assertRaises(ResearchDataError):
                validate_games_database(games_p)

    def test_invalid_binary_value_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            games_p, matrix_p, _ = self._write_fixture(Path(tmp), count=30)
            text = matrix_p.read_text(encoding="utf-8").replace(",1,", ",2,", 1)
            matrix_p.write_text(text, encoding="utf-8")
            games = validate_games_database(games_p)
            with self.assertRaises(ResearchDataError):
                validate_feature_matrix(matrix_p, {g["game_id"] for g in games})


if __name__ == "__main__":
    unittest.main()
