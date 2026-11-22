"""Unit tests for generate_charts.py."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

from generate_charts import generate_all_charts


class TestGenerateCharts(unittest.TestCase):
    """Verify all 6 PNG visualizations generate cleanly as non-empty valid images."""

    def test_generates_six_valid_png_charts(self) -> None:
        data_dir = Path(__file__).resolve().parents[1] / "data"
        with tempfile.TemporaryDirectory() as tmp:
            paths = generate_all_charts(data_dir, Path(tmp))
            self.assertEqual(len(paths), 6)
            for img_path in paths:
                self.assertTrue(img_path.exists(), f"Missing chart: {img_path}")
                self.assertGreater(img_path.stat().st_size, 15_000)
                with Image.open(img_path) as img:
                    width, height = img.size
                    self.assertGreater(width, 800)
                    self.assertGreater(height, 400)


if __name__ == "__main__":
    unittest.main()
