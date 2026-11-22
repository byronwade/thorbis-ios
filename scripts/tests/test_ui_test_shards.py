import tempfile
import unittest
from pathlib import Path

from scripts.ui_test_shards import _mask, shards, test_classes


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

    def plan(self, files: dict[str, str]) -> dict[str, int]:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, text in files.items():
                (root / name).parent.mkdir(parents=True, exist_ok=True)
                (root / name).write_text("import XCTest\n\n" + text)
            return test_classes(root)

    def refusal(self, files: dict[str, str]) -> str:
        with self.assertRaises(SystemExit) as caught:
            self.plan(files)
        return str(caught.exception.code)

    def test_only_classes_with_tests_are_counted(self):
        self.assertEqual(self.plan({
            "Support.swift": "extension XCUIApplication {\n    func helper() {}\n}\n",
            "FlowUITests.swift": (
                "final class FlowUITests: XCTestCase {\n"
                "    func testOpens() {}\n"
                "    @MainActor func testCloses() async throws {}\n"
                "    private func open() {}\n"
                "}\n\n"
                "final class EmptyUITests: XCTestCase {\n"
                "    func helper() {}\n"
                "}\n"
            ),
        }), {"FlowUITests": 2})

    def test_a_subclass_of_a_shared_base_runs_its_own_and_inherited_tests(self):
        self.assertEqual(self.plan({
            "Base.swift": "class BaseUITestCase: XCTestCase {\n    func launch() {}\n}\n",
            "InheritedUITests.swift": (
                "final class InheritedUITests: BaseUITestCase {\n"
                "    func testOne() {}\n"
                "    func testTwo() {}\n"
                "}\n"
            ),
            "SharedUITests.swift": (
                "class SharedChecksUITests: XCTestCase {\n    func testShared() {}\n}\n"
                "final class MoreChecksUITests: SharedChecksUITests {\n    func testMore() {}\n}\n"
            ),
        }), {"InheritedUITests": 2, "SharedChecksUITests": 1, "MoreChecksUITests": 2})

    def test_tests_in_an_extension_in_another_file_count_for_their_class(self):
        self.assertEqual(self.plan({
            "SplitUITests.swift": "final class SplitUITests: XCTestCase {\n    func helper() {}\n}\n",
            "SplitUITests+More.swift": "extension SplitUITests {\n    func testInExtension() {}\n}\n",
            "PlainUITests.swift": "final class PlainUITests: XCTestCase {\n    func testPlain() {}\n}\n",
        }), {"SplitUITests": 1, "PlainUITests": 1})

    def test_classes_in_subfolders_are_read(self):
        self.assertEqual(self.plan({
            "Jobs/JobFlowUITests.swift": "final class JobFlowUITests: XCTestCase {\n    func testOpens() {}\n}\n",
        }), {"JobFlowUITests": 1})

    def test_a_test_class_whose_base_the_planner_cannot_see_is_refused(self):
        message = self.refusal({
            "ElsewhereUITests.swift": "final class ElsewhereUITests: SharedBaseCase {\n    func testOne() {}\n}\n",
        })
        self.assertIn("ElsewhereUITests inherits from SharedBaseCase", message)
        # A class named like a test class is refused even before it declares a test here.
        self.assertIn("LaterUITests inherits from SharedBaseCase", self.refusal({
            "LaterUITests.swift": "final class LaterUITests: SharedBaseCase {}\n",
        }))

    def test_tests_outside_a_test_class_are_refused(self):
        message = self.refusal({
            "Stray.swift": (
                "struct Fixture {\n    func testFixture() {}\n}\n"
                "extension XCTestCase {\n    func testEverywhere() {}\n}\n"
                "func testAtFileScope() {}\n"
                "final class Helper {\n    func testHelper() {}\n}\n"
                "final class FlowUITests: XCTestCase {\n"
                "    func testOpens() {\n        func testInside() {}\n    }\n"
                "}\n"
            ),
        })
        for expected in ("func testFixture", "extension XCTestCase declares testEverywhere",
                         "func testAtFileScope", "Helper declares tests but is not an XCTestCase",
                         "func testInside"):
            self.assertIn(expected, message)

    def test_a_nested_test_class_is_refused(self):
        message = self.refusal({
            "Nested.swift": "enum Group {\n    final class InnerUITests: XCTestCase {\n        func testOne() {}\n    }\n}\n",
        })
        self.assertIn("InnerUITests is nested", message)

    def test_a_class_declared_twice_is_refused(self):
        self.assertIn("declared twice", self.refusal({
            "A.swift": "final class TwiceUITests: XCTestCase {\n    func testA() {}\n}\n",
            "B.swift": "final class TwiceUITests: XCTestCase {\n    func testB() {}\n}\n",
        }))

    def test_type_methods_are_not_tests(self):
        self.assertEqual(self.plan({
            "FlowUITests.swift": (
                "final class FlowUITests: XCTestCase {\n"
                "    static func testFixture() -> String { \"\" }\n"
                "    override class func setUp() {}\n"
                "    func testOpens() {}\n"
                "}\n"
            ),
        }), {"FlowUITests": 1})

    def test_strings_and_comments_cannot_open_or_close_a_class(self):
        self.assertEqual(self.plan({
            "FlowUITests.swift": (
                "// final class FakeUITests: XCTestCase { func testFake() {} }\n"
                "/* nested /* block */ class AlsoFakeUITests: XCTestCase { */\n"
                "final class FlowUITests: XCTestCase {\n"
                "    let reply = #\"{\"items\":[{\"id\":\"\\#(\"}\")\"}]}\"#\n"
                "    let text = \"}} \\(\"{\" + \"}\") func testInString() {\"\n"
                "    let block = \"\"\"\n        }\n        func testInBlock() {}\n        \"\"\"\n"
                "    func testOpens() {}\n"
                "    func testCloses() {}\n"
                "}\n"
            ),
        }), {"FlowUITests": 2})

    def test_mask_keeps_offsets_and_lines(self):
        source = 'let a = "x\\"y" // }\nlet b = #"{"#\n'
        masked = _mask(source)
        self.assertEqual(len(masked), len(source))
        self.assertEqual(masked.count("\n"), source.count("\n"))
        self.assertNotIn("{", masked)
        self.assertNotIn("}", masked)


if __name__ == "__main__":
    unittest.main()
