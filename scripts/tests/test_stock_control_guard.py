import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from scripts.lint_stock_controls import PATTERN

ROOT = Path(__file__).resolve().parents[2]


class StockControlGuardTests(unittest.TestCase):
    def run_guard(self, entries):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            sources = root / "Thorbis/Sources"
            sources.mkdir(parents=True)
            shutil.copy(ROOT / "scripts/lint-stock-controls.sh", root / "scripts")
            shutil.copy(ROOT / "scripts/.stock-controls-allowlist", root / "scripts")
            checker = ROOT / "scripts/lint_stock_controls.py"
            if checker.exists():
                shutil.copy(checker, root / "scripts")
            for filename, content in entries.items():
                (sources / filename).write_text(content)
            return subprocess.run(["bash", "scripts/lint-stock-controls.sh"], cwd=root,
                                  capture_output=True, text=True, check=False)

    def test_recorded_control_count_is_permitted(self):
        result = self.run_guard({"PaperJobDetailView.swift": "Menu {\nMenu {\n"})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_new_control_in_an_existing_baseline_file_is_rejected(self):
        # PaperJobDetailView has two recorded occurrences. A third must not
        # inherit blanket permission just because it is in the same file.
        result = self.run_guard({"PaperJobDetailView.swift": "Menu {\nMenu {\nMenu {\n"})
        self.assertNotEqual(result.returncode, 0, result.stdout)

    def test_different_control_in_an_existing_baseline_file_is_rejected(self):
        result = self.run_guard({"PaperJobDetailView.swift": "Menu {\n Picker(\"Other\")\n"})
        self.assertNotEqual(result.returncode, 0, result.stdout)

    def test_control_in_an_unlisted_file_is_rejected(self):
        result = self.run_guard({"Other.swift": "Menu {\n"})
        self.assertNotEqual(result.returncode, 0, result.stdout)

    def test_multiple_controls_on_one_line_are_counted(self):
        self.assertEqual(len(PATTERN.findall(" Menu { Menu {")), 2)
        self.assertEqual(len(PATTERN.findall("Menu {Menu {")), 2)
        self.assertEqual(len(PATTERN.findall(" Picker(\"A\") Picker(\"B\")")), 2)


if __name__ == "__main__":
    unittest.main()
