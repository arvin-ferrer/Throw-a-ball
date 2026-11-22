"""Unit tests for build_pdf.py and generate_diagrams.py."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

from build_pdf import build_pdf, preprocess_markdown_for_pdf
from generate_diagrams import generate_all_diagrams


class TestBuildPdf(unittest.TestCase):
    """Verify diagram rendering, Markdown preprocessing, and PDF generation."""

    def test_generates_all_four_architecture_diagrams(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            paths = generate_all_diagrams(Path(tmp))
            self.assertEqual(len(paths), 4)
            for path in paths:
                self.assertTrue(path.exists())
                with Image.open(path) as img:
                    self.assertGreater(img.width, 1000)

    def test_preprocess_strips_mermaid_normalizes_alerts_and_emojis(self) -> None:
        sample = (
            "> [!TIP]\n> Save taxes.\n\n"
            "```mermaid\nxychart-beta\n  bar [1, 2]\n```\n"
            "See [Report](foo.md). ❌ Cut item & 🎯 Ping.\n"
        )
        out = preprocess_markdown_for_pdf(sample, Path("/tmp/charts"))
        self.assertNotIn("```mermaid", out)
        self.assertIn("**TIP:**", out)
        self.assertIn("See Report.", out)
        self.assertIn("[CUT] Cut item & [Target] Ping.", out)
        self.assertNotIn("foo.md", out)

    def test_builds_valid_pdf_with_wide_table_and_currency(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            charts = root / "charts"
            md = root / "sample.md"
            md.write_text(
                "# Test Report\n\nDollar pairs: $1.697B and $403M at ₱63.75/$1.\n\n"
                "| Col A | Col B | Col C | Col D | Col E | Col F |\n"
                "| :--- | :--- | :--- | :--- | :--- | :--- |\n"
                "| One | Two | Three | Four | Five | Six |\n",
                encoding="utf-8",
            )
            pdf_out = root / "out.pdf"
            build_pdf(md, charts, pdf_out)
            self.assertTrue(pdf_out.exists())
            raw = pdf_out.read_bytes()
            self.assertTrue(raw.startswith(b"%PDF-"))
            self.assertGreater(len(raw), 5_000)


if __name__ == "__main__":
    unittest.main()
