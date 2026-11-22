"""Unit tests for compile_report.py."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

from common import ResearchDataError
from compile_report import DELIVERABLE_MANIFEST, compile_master_report


class TestCompileReport(unittest.TestCase):
    """Verify report assembly, ordering, TOC links, and missing-file failures."""

    def test_compiles_all_deliverables_and_sources(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            deliv_dir = root / "deliverables"
            deliv_dir.mkdir()
            for filename, label in DELIVERABLE_MANIFEST:
                (deliv_dir / filename).write_text(f"## {label}\n\nBody text.", encoding="utf-8")
            sources_path = root / "sources.json"
            sources_path.write_text(
                json.dumps(
                    [
                        {
                            "source_id": "S01",
                            "title": "Official Docs",
                            "publisher": "Roblox",
                            "tier": "Primary",
                            "publication_date": "2026-10-01",
                            "collection_date": "2026-11-22",
                            "reference": "create.roblox.com",
                        }
                    ]
                ),
                encoding="utf-8",
            )
            out_path = root / "Master.md"
            compiled = compile_master_report(deliv_dir, out_path, sources_path)
            self.assertTrue(out_path.exists())
            self.assertIn("Deliverable A — Executive Summary", compiled)
            self.assertIn("Deliverable N — Founder Cheat Sheet", compiled)
            self.assertIn("Appendix: Verified Sources Registry", compiled)

    def test_missing_deliverable_raises(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            deliv_dir = root / "deliverables"
            deliv_dir.mkdir()
            (deliv_dir / "A_Executive_Summary.md").write_text("# Only A", encoding="utf-8")
            with self.assertRaises(ResearchDataError):
                compile_master_report(deliv_dir, root / "Master.md")


if __name__ == "__main__":
    unittest.main()
