"""Shared constants and safe I/O utilities for Roblox deep research scripts."""

from __future__ import annotations

import csv
import json
from pathlib import Path
from typing import Any

EVIDENCE_LEVELS: frozenset[str] = frozenset(
    {
        "Officially confirmed",
        "Strongly supported by evidence",
        "Observational correlation",
        "Developer-reported experience",
        "Reasonable inference",
        "Speculative hypothesis",
        "Unknown",
    }
)

GAME_CATEGORIES: tuple[str, ...] = (
    "Established market leaders",
    "Recently viral games",
    "Emerging high-growth games",
    "Sustainable mid-sized games",
    "Games with declining popularity",
    "Simple-mechanic disproportionate results",
)

SOURCE_TIERS: frozenset[str] = frozenset({"Primary", "Secondary", "Supplementary"})


class ResearchDataError(ValueError):
    """Raised when research data fails schema or invariant validation."""


def load_json_file(path: Path) -> Any:
    """Load and parse a JSON file with descriptive error reporting."""
    if not path.exists():
        raise ResearchDataError(f"Required JSON file not found: {path}")
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ResearchDataError(f"Invalid JSON in {path}: {exc}") from exc


def load_csv_rows(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    """Load CSV headers and rows as stripped dictionaries."""
    if not path.exists():
        raise ResearchDataError(f"Required CSV file not found: {path}")
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        if not reader.fieldnames:
            raise ResearchDataError(f"CSV file has no header row: {path}")
        headers = [col.strip() for col in reader.fieldnames]
        rows = [
            {key.strip(): (val or "").strip() for key, val in row.items() if key}
            for row in reader
        ]
    return headers, rows


def format_currency(amount: float, symbol: str = "$") -> str:
    """Format numeric currency cleanly with sign before symbol."""
    if amount < 0:
        return f"-{symbol}{abs(amount):,.2f}"
    return f"{symbol}{amount:,.2f}"
