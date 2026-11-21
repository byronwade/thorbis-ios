import tempfile
import unittest
from pathlib import Path

from scripts.ui_test_shards import shards, test_classes


class UITestShardTests(unittest.TestCase):
    def test_every_class_lands_in_exactly_one_shard(self):
        classes = test_classes()
        self.assertGreater(len(classes), 0)
        for count in (1, 2, 6, 8, len(classes)):
            split = shards(classes, count)
            self.assertEqual(len(split), count)
            self.assertEqual(sorted(name for shard in split for name in shard), sorted(classes))

    def test_shards_are_balanced_by_test_count(self):
        classes = {"A": 6, "B": 5, "C": 4, "D": 3, "E": 2, "F": 1}
        split = shards(classes, 3)
        weights = [sum(classes[name] for name in shard) for shard in split]
        self.assertEqual(weights, [7, 7, 7])
        self.assertEqual(split, [["A", "F"], ["B", "E"], ["C", "D"]])

    def test_split_is_the_same_on_every_call(self):
        classes = test_classes()
        self.assertEqual(shards(classes, 6), shards(dict(reversed(list(classes.items()))), 6))

    def test_only_classes_with_tests_are_counted(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Support.swift").write_text(
                "import XCTest\nextension XCUIApplication {\n    func helper() {}\n}\n"
            )
            (root / "FlowUITests.swift").write_text(
                "import XCTest\n\n"
                "final class FlowUITests: XCTestCase {\n"
                "    func testOpens() {}\n"
                "    @MainActor func testCloses() async throws {}\n"
                "    private func open() {}\n"
                "}\n\n"
                "final class EmptyUITests: XCTestCase {\n"
                "    func helper() {}\n"
                "}\n"
            )
            self.assertEqual(test_classes(root), {"FlowUITests": 2})


if __name__ == "__main__":
    unittest.main()
