import contextlib
import io
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from scripts import ui_test_shards
from scripts.ui_test_shards import _mask, main, shards, tablet_classes, test_classes


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

    def tablet_plan(self, files: dict[str, str]) -> dict[str, int]:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, text in files.items():
                (root / name).parent.mkdir(parents=True, exist_ok=True)
                (root / name).write_text("import XCTest\n\n" + text)
            return tablet_classes(root)

    def test_tablet_classes_are_those_whose_code_mentions_the_ipad_layout(self):
        self.assertEqual(self.tablet_plan({
            "Support.swift": "extension XCUIApplication {\n    var usesTabletLayout: Bool { true }\n}\n",
            "PhoneUITests.swift": "final class PhoneUITests: XCTestCase {\n    func testOpens() {}\n}\n",
            "BothUITests.swift": (
                "final class BothUITests: XCTestCase {\n"
                "    func testOpens() { if app.usesTabletLayout { return } }\n"
                "    func testCloses() {}\n"
                "}\n"
            ),
        }), {"BothUITests": 2})

    def test_a_mention_in_a_comment_or_a_string_is_not_an_ipad_path(self):
        self.assertEqual(self.tablet_plan({
            "TalkUITests.swift": (
                "final class TalkUITests: XCTestCase {\n"
                "    // usesTabletLayout is read elsewhere\n"
                "    func testOpens() { print(\"usesTabletLayout\") }\n"
                "}\n"
            ),
        }), {})

    def test_an_extension_or_a_base_class_file_gives_its_class_the_ipad_path(self):
        self.assertEqual(self.tablet_plan({
            "Base.swift": "class BaseUITestCase: XCTestCase {\n    func open() { _ = app.usesTabletLayout }\n}\n",
            "InheritedUITests.swift": "final class InheritedUITests: BaseUITestCase {\n    func testOpens() {}\n}\n",
            "SplitUITests.swift": "final class SplitUITests: XCTestCase {\n    func testOne() {}\n}\n",
            "SplitUITests+Pad.swift": (
                "extension SplitUITests {\n    func testTwo() { _ = app.usesTabletLayout }\n}\n"
            ),
            "PlainUITests.swift": "final class PlainUITests: XCTestCase {\n    func testOpens() {}\n}\n",
        }), {"InheritedUITests": 1, "SplitUITests": 2})

    def test_the_tablet_share_of_this_repository_splits_like_any_other(self):
        classes = tablet_classes()
        self.assertGreater(len(classes), 0)
        self.assertLessEqual(set(classes), set(test_classes()))
        split = shards(classes, 2)
        self.assertEqual(sorted(name for shard in split for name in shard), sorted(classes))

    def test_an_extension_of_a_base_class_gives_its_subclasses_the_ipad_path(self):
        self.assertEqual(self.tablet_plan({
            "Base.swift": "class BaseUITestCase: XCTestCase {\n    func open() {}\n}\n",
            "Base+Pad.swift": "extension BaseUITestCase {\n    func sidebar() { _ = app.usesTabletLayout }\n}\n",
            "InheritedUITests.swift": "final class InheritedUITests: BaseUITestCase {\n    func testOpens() {}\n}\n",
        }), {"InheritedUITests": 1})

    def run_main(self, *arguments: str) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = main(list(arguments))
        return code, out.getvalue(), err.getvalue()

    def test_the_tablet_flag_narrows_the_printed_share_and_the_check(self):
        tablet = tablet_classes()
        printed: list[str] = []
        for index in (1, 2):
            code, out, _ = self.run_main("--tablet", "--shards", "2", "--index", str(index))
            self.assertEqual(code, 0)
            printed += [argument.split("/")[-1] for argument in out.split()]
        self.assertEqual(sorted(printed), sorted(tablet))
        code, out, _ = self.run_main("--tablet", "--shards", "2", "--check")
        self.assertEqual(code, 0)
        self.assertEqual(out.strip(), f"{len(tablet)} classes, {sum(tablet.values())} tests, 2 shards")
        # Without the flag the same commands still cover every class.
        code, out, _ = self.run_main("--shards", "6", "--check")
        self.assertEqual(code, 0)
        self.assertTrue(out.startswith(f"{len(test_classes())} classes, "))

    def test_no_class_with_an_ipad_path_is_an_error_not_an_empty_run(self):
        with mock.patch.object(ui_test_shards, "tablet_classes", return_value={}):
            code, out, err = self.run_main("--tablet", "--shards", "2", "--index", "1")
        self.assertEqual(code, 1)
        self.assertEqual(out, "")
        self.assertIn("usesTabletLayout", err)

    def test_mask_keeps_offsets_and_lines(self):
        source = 'let a = "x\\"y" // }\nlet b = #"{"#\n'
        masked = _mask(source)
        self.assertEqual(len(masked), len(source))
        self.assertEqual(masked.count("\n"), source.count("\n"))
        self.assertNotIn("{", masked)
        self.assertNotIn("}", masked)


if __name__ == "__main__":
    unittest.main()
