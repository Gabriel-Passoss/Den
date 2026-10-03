import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path

from support import load, patched

coverage = load("coverage")


def exported(*files):
    return {"data": [{"files": [
        {"filename": name, "summary": {"lines": {"covered": covered, "count": count}}}
        for name, covered, count in files
    ]}]}


def reported(*files, target="Den.app"):
    return {"targets": [{"name": target, "files": [
        {"path": path, "coveredLines": covered, "executableLines": count}
        for path, covered, count in files
    ]}]}


class PackageTotals(unittest.TestCase):
    def test_lines_are_added_up_per_target(self):
        totals = coverage.package_totals(exported(
            ("/repo/Packages/HarnessKit/Sources/HarnessCore/Parsing/JSONValue.swift", 8, 10),
            ("/repo/Packages/HarnessKit/Sources/HarnessCore/Session/Session.swift", 1, 10),
            ("/repo/Packages/HarnessKit/Sources/ClaudeHarness/Session/ClaudeLaunch.swift", 5, 5),
        ))
        self.assertEqual(totals, {"HarnessCore": (9, 20), "ClaudeHarness": (5, 5)})

    def test_tests_and_ungated_targets_are_left_out(self):
        totals = coverage.package_totals(exported(
            ("/repo/Packages/HarnessKit/Tests/HarnessCoreTests/SessionTests.swift", 50, 50),
            ("/repo/Packages/HarnessKit/Sources/HarnessTestSupport/TestTimeout.swift", 3, 4),
            ("/repo/Packages/HarnessKit/Sources/harness-probe/main.swift", 0, 90),
        ))
        self.assertEqual(totals, {})


class AppTotals(unittest.TestCase):
    def test_files_under_a_views_folder_are_left_out(self):
        totals = coverage.app_totals(reported(
            ("/repo/Den/Chat/ViewModels/ChatModel.swift", 80, 100),
            ("/repo/Den/Chat/Views/ChatView.swift", 0, 400),
            ("/repo/Den/Sidebar/Views/SidebarView.swift", 10, 300),
        ))
        self.assertEqual(totals, {"Den": (80, 100)})

    def test_a_file_merely_named_like_a_view_still_counts(self):
        totals = coverage.app_totals(reported(("/repo/Den/App/InspectorView.swift", 0, 200)))
        self.assertEqual(totals, {"Den": (0, 200)})

    def test_other_targets_are_ignored(self):
        totals = coverage.app_totals(reported(("/repo/DenTests/Run/RunStateTests.swift", 40, 40), target="DenTests.xctest"))
        self.assertEqual(coverage.percentages(totals), {})


class Percentages(unittest.TestCase):
    def test_a_target_without_executable_lines_has_no_percentage(self):
        self.assertEqual(coverage.percentages({"HarnessCore": (9, 20), "Den": (0, 0)}), {"HarnessCore": 45.0})


class Failures(unittest.TestCase):
    def test_at_or_above_the_floor_passes(self):
        self.assertEqual(coverage.failures({"Den": 81.0, "HarnessCore": 96.7}, {"Den": 81, "HarnessCore": 96}, ("Den", "HarnessCore")), [])

    def test_below_the_floor_is_reported_with_both_numbers(self):
        self.assertEqual(coverage.failures({"Den": 80.94}, {"Den": 81}, ("Den",)), ["Den: 80.9% is below the floor of 81%"])

    def test_a_target_that_vanished_from_the_report_fails(self):
        self.assertEqual(coverage.failures({}, {"OpenCodeHarness": 64}, ("OpenCodeHarness",)), ["OpenCodeHarness: missing from the coverage report"])

    def test_a_target_without_a_floor_fails(self):
        self.assertEqual(coverage.failures({"Den": 50.0}, {}, ("Den",)), ["Den: no floor recorded; run again with --write-floor"])

    def test_only_the_named_targets_are_checked(self):
        self.assertEqual(coverage.failures({"Den": 90.0}, {"Den": 81, "HarnessCore": 96}, ("Den",)), [])


class Raised(unittest.TestCase):
    def test_the_measured_group_is_rounded_down_and_the_rest_kept(self):
        floors = coverage.raised({"Den": 70, "HarnessCore": 96}, {"Den": 81.97}, ("Den",))
        self.assertEqual(floors, {"Den": 81, "HarnessCore": 96})

    def test_half_a_point_is_left_for_the_run_to_run_wobble(self):
        self.assertEqual(coverage.raised({}, {"Den": 81.01}, ("Den",)), {"Den": 80})


class MissingInputs(unittest.TestCase):
    def test_a_package_tested_without_coverage_is_explained_in_one_line(self):
        with tempfile.TemporaryDirectory() as scratch:
            report = Path(scratch) / "Products/Debug/codecov/HarnessKit.json"
            with self.assertRaises(SystemExit) as stopped:
                coverage.profile_and_bundles(report)
        self.assertIn("run `swift test --enable-code-coverage` first", str(stopped.exception))

    def test_the_profile_and_every_test_bundle_are_found(self):
        with tempfile.TemporaryDirectory() as scratch:
            products = Path(scratch) / "Products/Debug"
            (products / "codecov").mkdir(parents=True)
            (products / "codecov/default.profdata").touch()
            for name in ("HarnessCoreTests", "ClaudeHarnessTests"):
                (products / f"{name}.xctest/Contents/MacOS").mkdir(parents=True)
                (products / f"{name}.xctest/Contents/MacOS/{name}").touch()
            profile, bundles = coverage.profile_and_bundles(products / "codecov/HarnessKit.json")
        self.assertEqual(profile.name, "default.profdata")
        self.assertEqual([bundle.name for bundle in bundles], ["ClaudeHarnessTests", "HarnessCoreTests"])

    def test_the_debug_symbols_beside_a_test_bundle_are_not_taken_for_an_object(self):
        with tempfile.TemporaryDirectory() as scratch:
            products = Path(scratch) / "arm64-apple-macosx/debug"
            (products / "codecov").mkdir(parents=True)
            (products / "codecov/default.profdata").touch()
            binaries = products / "HarnessKitPackageTests.xctest/Contents/MacOS"
            binaries.mkdir(parents=True)
            (binaries / "HarnessKitPackageTests").touch()
            (binaries / "HarnessKitPackageTests.dSYM/Contents").mkdir(parents=True)
            _, bundles = coverage.profile_and_bundles(products / "codecov/HarnessKit.json")
        self.assertEqual([bundle.name for bundle in bundles], ["HarnessKitPackageTests"])

    def test_a_tool_that_fails_is_reported_with_what_it_said(self):
        with self.assertRaises(SystemExit) as stopped:
            coverage.output_of("/bin/sh", "-c", "echo no such bundle >&2; exit 3")
        self.assertIn("/bin/sh -c", str(stopped.exception))
        self.assertIn("no such bundle", str(stopped.exception))


class Main(unittest.TestCase):
    PACKAGE = {"HarnessCore": 96.7, "ClaudeHarness": 87.9, "OpenCodeHarness": 64.9, "HarnessProbeArguments": 91.2}
    FLOORS = {"HarnessCore": 96, "ClaudeHarness": 87, "OpenCodeHarness": 64, "HarnessProbeArguments": 90, "Den": 80}

    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.floor = Path(scratch.name) / ".coverage-floor.json"
        self.bundles = []

    def record(self, floors):
        self.floor.write_text(json.dumps(floors), encoding="utf-8")

    def run_main(self, arguments, package=None, app=None):
        def measure_app(bundle):
            self.bundles.append(bundle)
            return app

        printed, complained = io.StringIO(), io.StringIO()
        with patched(coverage, FLOOR_FILE=self.floor, measure_package=lambda: package, measure_app=measure_app), \
                contextlib.redirect_stdout(printed), contextlib.redirect_stderr(complained):
            status = coverage.main(arguments)
        return status, printed.getvalue(), complained.getvalue()

    def test_every_target_at_or_above_its_floor_passes_and_is_listed(self):
        self.record(self.FLOORS)
        status, printed, complained = self.run_main(["package"], package=self.PACKAGE)
        self.assertEqual(status, 0)
        self.assertEqual(complained, "")
        self.assertIn("OpenCodeHarness          64.9%   floor 64%", printed)
        self.assertEqual(len(printed.splitlines()), 4)

    def test_a_target_below_its_floor_fails_the_run(self):
        self.record(self.FLOORS)
        status, _, complained = self.run_main(["package"], package={**self.PACKAGE, "ClaudeHarness": 86.4})
        self.assertEqual(status, 1)
        self.assertEqual(complained, "ClaudeHarness: 86.4% is below the floor of 87%\n")

    def test_the_app_is_measured_from_the_bundle_it_was_given(self):
        self.record(self.FLOORS)
        status, printed, _ = self.run_main(["app", "build/app.xcresult"], app={"Den": 79.9})
        self.assertEqual(self.bundles, ["build/app.xcresult"])
        self.assertEqual(status, 1)
        self.assertIn("Den                      79.9%   floor 80%", printed)

    def test_the_app_needs_a_bundle(self):
        with self.assertRaises(SystemExit) as stopped:
            self.run_main(["app"])
        self.assertEqual(stopped.exception.code, 2)

    def test_without_a_recorded_floor_the_run_fails_and_says_how_to_record_one(self):
        status, _, complained = self.run_main(["app", "build/app.xcresult"], app={"Den": 81.0})
        self.assertEqual(status, 1)
        self.assertIn("Den: no floor recorded; run again with --write-floor", complained)

    def test_the_report_puts_what_was_measured_beside_each_floor_even_when_the_run_fails(self):
        self.record(self.FLOORS)
        report = self.floor.parent / "out" / "coverage-package.json"
        status, _, _ = self.run_main(["package", "--report", str(report)],
                                     package={**self.PACKAGE, "ClaudeHarness": 86.4})
        self.assertEqual(status, 1)
        self.assertEqual(json.loads(report.read_text(encoding="utf-8")), [
            {"name": "HarnessCore", "measured": 96.7, "floor": 96},
            {"name": "ClaudeHarness", "measured": 86.4, "floor": 87},
            {"name": "OpenCodeHarness", "measured": 64.9, "floor": 64},
            {"name": "HarnessProbeArguments", "measured": 91.2, "floor": 90},
        ])

    def test_the_report_says_null_for_what_was_not_measured_or_has_no_floor(self):
        report = self.floor.parent / "coverage-app.json"
        self.run_main(["app", "build/app.xcresult", "--report", str(report)], app={})
        self.assertEqual(json.loads(report.read_text(encoding="utf-8")),
                         [{"name": "Den", "measured": None, "floor": None}])

    def test_write_floor_records_the_measured_group_and_keeps_the_other(self):
        self.record({"Den": 80, "HarnessCore": 50})
        status, _, _ = self.run_main(["package", "--write-floor"], package=self.PACKAGE)
        self.assertEqual(status, 0)
        self.assertEqual(json.loads(self.floor.read_text(encoding="utf-8")),
                         {"ClaudeHarness": 87, "Den": 80, "HarnessCore": 96, "HarnessProbeArguments": 90, "OpenCodeHarness": 64})
        self.assertTrue(self.floor.read_text(encoding="utf-8").endswith("}\n"))


if __name__ == "__main__":
    unittest.main()
