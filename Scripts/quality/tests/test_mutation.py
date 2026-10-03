import contextlib
import io
import json
import tempfile
import time
import unittest
from pathlib import Path

from support import load, patched

mutation = load("mutation")


def swaps(source):
    return [(mutant.original, mutant.replacement) for mutant in mutation.mutants_in("File.swift", source)]


def a_mutant(file="Packages/HarnessKit/Sources/HarnessCore/A.swift", line=1, code="a == b", occurrence=0):
    return mutation.Mutant(file, line, 2, "==", "!=", code, occurrence)


class Operators(unittest.TestCase):
    def test_each_operator_is_swapped_for_its_opposite(self):
        self.assertEqual(swaps("a == b"), [("==", "!=")])
        self.assertEqual(swaps("a != b"), [("!=", "==")])
        self.assertEqual(swaps("a < b"), [("<", ">=")])
        self.assertEqual(swaps("a >= b"), [(">=", "<")])
        self.assertEqual(swaps("a > b"), [(">", "<=")])
        self.assertEqual(swaps("a <= b"), [("<=", ">")])
        self.assertEqual(swaps("a && b"), [("&&", "||")])
        self.assertEqual(swaps("a || b"), [("||", "&&")])
        self.assertEqual(swaps("return true"), [("true", "false")])
        self.assertEqual(swaps("flag = false"), [("false", "true")])

    def test_an_operator_that_opens_a_wrapped_line_counts(self):
        self.assertEqual(swaps("let ok = first\n    && second"), [("&&", "||")])

    def test_lookalikes_are_left_alone(self):
        for source in ("func f() -> Bool", "let xs: Array<Int> = []", "for i in 0..<n {}",
                       "a === b", "a !== b", "x >> 2", "x << 2", "let isTrue = falsey", "a ?? b"):
            self.assertEqual(swaps(source), [], source)


class CommentsAndStrings(unittest.TestCase):
    def test_a_line_comment_is_skipped_but_the_code_before_it_is_not(self):
        self.assertEqual(swaps("let a = x < y // was x == y"), [("<", ">=")])

    def test_a_nested_block_comment_is_skipped_to_its_real_end(self):
        self.assertEqual(swaps("/* a == b /* c && d */ e || f */ let g = p > q"), [(">", "<=")])

    def test_a_string_is_skipped(self):
        self.assertEqual(swaps('let s = "a == b && true"'), [])

    def test_an_escaped_quote_does_not_end_the_string(self):
        self.assertEqual(swaps(r'let s = "say \"a == b\" twice"'), [])

    def test_an_interpolation_is_code(self):
        self.assertEqual(swaps(r'let s = "is \(a == b) and \(names["k"] ?? "x == y")"'), [("==", "!=")])

    def test_a_multiline_string_is_skipped(self):
        self.assertEqual(swaps('let s = """\n  a == b\n  "quoted" && true\n  """\nlet t = c != d'), [("!=", "==")])

    def test_a_raw_string_is_skipped_and_only_its_own_interpolation_is_code(self):
        self.assertEqual(swaps(r'let s = #"a == b \(c < d) \#(e > f) "g && h""#'), [(">", "<=")])

    def test_an_unterminated_string_stops_at_the_end_of_its_line(self):
        self.assertEqual(swaps('let s = "a == b\nlet t = c != d'), [("!=", "==")])

    def test_a_macro_is_not_taken_for_a_raw_string(self):
        self.assertEqual(swaps("#expect(a == b)"), [("==", "!=")])

    def test_a_regex_literal_is_skipped(self):
        self.assertEqual(swaps(r"let m = raw.firstMatch(of: /^(\d+) == (\d+)/)"), [])
        self.assertEqual(swaps("let r = /a\\/b == c/\nlet t = x < y"), [("<", ">=")])

    def test_a_regex_literal_after_a_keyword_or_an_operator_is_skipped(self):
        for source in ("return /a == b/", "let m = try /a == b/.firstMatch(in: s)", "case /a == b/: break",
                       "if /x < y/ ~= s {}", "guard s ~= /a && b/ else { return }",
                       "let r = flag ? /a == b/ : /c != d/", "let rs = [/a == b/, /c || d/]"):
            self.assertEqual(swaps(source), [], source)

    def test_an_extended_regex_literal_is_skipped_even_across_lines(self):
        self.assertEqual(swaps("let r = #/a == b/#"), [])
        self.assertEqual(swaps("let r = ##/a == b /# c && d/##\nlet t = x < y"), [("<", ">=")])
        self.assertEqual(swaps("let r = #/\n  a == b\n  c || d\n/#\nlet t = x < y"), [("<", ">=")])

    def test_an_unterminated_extended_regex_stops_at_the_end_of_its_line(self):
        self.assertEqual(swaps("let r = #/a == b\nlet t = c != d"), [("!=", "==")])

    def test_a_division_is_not_taken_for_a_regex_literal(self):
        self.assertEqual(swaps("let same = a / b == c / d"), [("==", "!=")])
        self.assertEqual(swaps("let same = count/2 == limit/2"), [("==", "!=")])
        self.assertEqual(swaps("let same = (a + b)/c == items[0]/d"), [("==", "!=")])


class Positions(unittest.TestCase):
    def test_line_code_and_occurrence_identify_each_mutant(self):
        found = mutation.mutants_in("File.swift", "let x = 1\n    if a == b && c == d {\n")
        self.assertEqual([(mutant.line, mutant.original, mutant.occurrence) for mutant in found],
                         [(2, "==", 0), (2, "&&", 0), (2, "==", 1)])
        self.assertEqual({mutant.code for mutant in found}, {"if a == b && c == d {"})

    def test_the_last_line_needs_no_trailing_newline(self):
        found = mutation.mutants_in("File.swift", "let x = 1\nreturn a < b")
        self.assertEqual([(mutant.line, mutant.code) for mutant in found], [(2, "return a < b")])

    def test_mutated_replaces_only_that_occurrence(self):
        source = "if a == b && c == d {}"
        second = mutation.mutants_in("File.swift", source)[2]
        self.assertEqual(mutation.mutated(source, second), "if a == b && c != d {}")


class ChangedLines(unittest.TestCase):
    def test_added_and_modified_lines_are_collected_per_file(self):
        diff = "\n".join([
            "diff --git a/Packages/HarnessKit/Sources/HarnessCore/A.swift b/Packages/HarnessKit/Sources/HarnessCore/A.swift",
            "--- a/Packages/HarnessKit/Sources/HarnessCore/A.swift",
            "+++ b/Packages/HarnessKit/Sources/HarnessCore/A.swift",
            "@@ -3 +3 @@ func f()",
            "-old",
            "+new",
            "@@ -10,0 +11,3 @@",
            "+one",
            "+two",
            "+three",
        ])
        self.assertEqual(mutation.changed_lines(diff),
                         {"Packages/HarnessKit/Sources/HarnessCore/A.swift": {3, 11, 12, 13}})

    def test_a_hunk_that_only_deletes_changes_no_line(self):
        diff = "+++ b/Sources/A.swift\n@@ -4,2 +3,0 @@\n-gone\n-gone too"
        self.assertEqual(mutation.changed_lines(diff), {"Sources/A.swift": set()})

    def test_a_deleted_file_is_ignored(self):
        diff = "--- a/Sources/A.swift\n+++ /dev/null\n@@ -1,2 +0,0 @@\n-gone\n-gone too"
        self.assertEqual(mutation.changed_lines(diff), {})

    def test_an_empty_diff_changes_nothing(self):
        self.assertEqual(mutation.changed_lines(""), {})


class Discover(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.root = Path(self.scratch.name)
        self.addCleanup(self.scratch.cleanup)
        self.write("HarnessCore/A.swift", "let a = x == y\nlet b = p < q\n")
        self.write("HarnessCore/Nested/B.swift", "let c = true\n")
        self.write("HarnessTestSupport/Support.swift", "let d = x == y\n")
        self.write("harness-probe/main.swift", "let e = x == y\n")

    def write(self, name, text):
        path = self.root / mutation.SOURCES / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def found(self, lines=None):
        return [(mutant.file, mutant.line) for mutant in mutation.discover(self.root, lines)]

    def test_every_source_file_but_the_excluded_targets(self):
        self.assertEqual(self.found(), [
            ("Packages/HarnessKit/Sources/HarnessCore/A.swift", 1),
            ("Packages/HarnessKit/Sources/HarnessCore/A.swift", 2),
            ("Packages/HarnessKit/Sources/HarnessCore/Nested/B.swift", 1),
        ])

    def test_only_the_changed_lines_when_given(self):
        lines = {"Packages/HarnessKit/Sources/HarnessCore/A.swift": {2},
                 "Packages/HarnessKit/Sources/HarnessTestSupport/Support.swift": {1}}
        self.assertEqual(self.found(lines), [("Packages/HarnessKit/Sources/HarnessCore/A.swift", 2)])

    def test_nothing_changed_means_no_mutants(self):
        self.assertEqual(self.found({}), [])


class Evaluate(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.workspace = Path(self.scratch.name)
        self.addCleanup(self.scratch.cleanup)
        self.path = self.workspace / "Sources/HarnessCore/A.swift"
        self.path.parent.mkdir(parents=True)
        self.path.write_text("a == b", encoding="utf-8")
        self.seen = []

    def outcome(self, builds, passes):
        def build():
            self.seen.append(self.path.read_text())
            return builds

        return mutation.evaluate([a_mutant()], self.workspace, build, lambda: passes)[0][1]

    def test_a_mutant_that_does_not_compile_is_discarded(self):
        self.assertEqual(self.outcome(builds=False, passes=True), "discarded")

    def test_a_mutant_the_tests_catch_is_killed(self):
        self.assertEqual(self.outcome(builds=True, passes=False), "killed")

    def test_a_mutant_the_tests_miss_survives(self):
        self.assertEqual(self.outcome(builds=True, passes=True), "survived")

    def test_the_build_sees_the_mutated_file_and_the_original_comes_back(self):
        self.outcome(builds=True, passes=True)
        self.assertEqual(self.seen, ["a != b"])
        self.assertEqual(self.path.read_text(), "a == b")

    def test_the_original_comes_back_even_when_the_run_blows_up(self):
        def explode():
            raise RuntimeError("swift went away")

        with self.assertRaises(RuntimeError):
            mutation.evaluate([a_mutant()], self.workspace, explode, lambda: True)
        self.assertEqual(self.path.read_text(), "a == b")

    def test_text_outside_ascii_comes_back_byte_for_byte(self):
        original = 'a == b // "não é → igual"\r\n'.encode("utf-8")
        self.path.write_bytes(original)
        self.outcome(builds=True, passes=True)
        self.assertEqual(self.path.read_bytes(), original)

    def test_each_outcome_is_announced_as_it_happens(self):
        announced = []
        mutation.evaluate([a_mutant()], self.workspace, lambda: True, lambda: False,
                          lambda mutant, outcome: announced.append((mutant.line, outcome)))
        self.assertEqual(announced, [(1, "killed")])


class Baseline(unittest.TestCase):
    def test_a_recorded_survivor_is_accepted_wherever_its_line_moved_to(self):
        baseline = {mutation.key(a_mutant(line=10))}
        self.assertEqual(mutation.unaccepted([(a_mutant(line=42), "survived")], baseline), [])

    def test_a_survivor_on_other_code_is_not_accepted(self):
        baseline = {mutation.key(a_mutant(code="a == b"))}
        fresh = a_mutant(code="c == d")
        self.assertEqual(mutation.unaccepted([(fresh, "survived")], baseline), [fresh])

    def test_the_second_occurrence_on_a_line_is_its_own_entry(self):
        baseline = {mutation.key(a_mutant(occurrence=0))}
        second = a_mutant(occurrence=1)
        self.assertEqual(mutation.unaccepted([(second, "survived")], baseline), [second])

    def test_killed_and_discarded_mutants_never_fail_the_run(self):
        self.assertEqual(mutation.unaccepted([(a_mutant(), "killed"), (a_mutant(), "discarded")], set()), [])

    def test_rebasing_adds_survivors_drops_what_died_and_keeps_what_did_not_run(self):
        untouched, died, survived = a_mutant(code="u == v"), a_mutant(code="k == l"), a_mutant(code="s == t")
        baseline = {mutation.key(untouched), mutation.key(died)}
        self.assertEqual(mutation.rebased(baseline, [(died, "killed"), (survived, "survived")]),
                         {mutation.key(untouched), mutation.key(survived)})

    def test_the_file_round_trips_sorted_and_ends_with_a_newline(self):
        with tempfile.TemporaryDirectory() as scratch:
            path = Path(scratch) / "baseline.json"
            baseline = {mutation.key(a_mutant(code="z == y")), mutation.key(a_mutant(code="a == b"))}
            mutation.write_baseline(path, baseline)
            text = path.read_text()
            self.assertTrue(text.endswith("]\n"))
            self.assertLess(text.index("a == b"), text.index("z == y"))
            self.assertEqual(mutation.read_baseline(path), baseline)

    def test_a_missing_file_is_an_empty_baseline(self):
        self.assertEqual(mutation.read_baseline(Path("/nonexistent/baseline.json")), set())


class Commands(unittest.TestCase):
    def test_a_command_that_exits_zero_succeeds(self):
        self.assertTrue(mutation.succeeds(["/usr/bin/true"]))

    def test_a_command_that_exits_non_zero_does_not(self):
        self.assertFalse(mutation.succeeds(["/usr/bin/false"]))

    def test_a_command_that_hangs_is_killed_with_its_children_and_counts_as_a_failure(self):
        with tempfile.TemporaryDirectory() as scratch:
            marker = Path(scratch) / "child-finished"
            started = time.monotonic()
            hung = mutation.succeeds(["/bin/sh", "-c", f"(sleep 1; touch {marker}) & sleep 30"], timeout=0.2)
            self.assertFalse(hung)
            self.assertLess(time.monotonic() - started, 1)
            time.sleep(1.5)
            self.assertFalse(marker.exists())

    def test_a_base_that_git_does_not_know_is_explained_with_what_git_said(self):
        with self.assertRaises(SystemExit) as stopped:
            mutation.diff_since("no-such-ref-anywhere")
        self.assertIn("merge-base no-such-ref-anywhere HEAD failed", str(stopped.exception))


class Main(unittest.TestCase):
    FILE = "Packages/HarnessKit/Sources/HarnessCore/A.swift"
    CHANGED = f"+++ b/{FILE}\n@@ -1 +1 @@\n+let same = a == b"

    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name)
        source = self.root / self.FILE
        source.parent.mkdir(parents=True)
        source.write_text("let same = a == b\n", encoding="utf-8")
        self.baseline = self.root / ".mutation-baseline.json"
        self.builds = 0

    def run_main(self, arguments, clean=True, mutants_pass=True, diff=""):
        test_runs = []

        def succeeds(command, timeout=None):
            if command[1] == "build":
                self.builds += 1
                return True
            test_runs.append(command)
            return clean if len(test_runs) == 1 else mutants_pass

        printed, complained = io.StringIO(), io.StringIO()
        with patched(mutation, ROOT=self.root, BASELINE_FILE=self.baseline,
                     succeeds=succeeds, diff_since=lambda base: diff), \
                contextlib.redirect_stdout(printed), contextlib.redirect_stderr(complained):
            status = mutation.main(arguments)
        return status, printed.getvalue(), complained.getvalue()

    def test_a_change_without_mutants_passes_and_builds_nothing(self):
        status, printed, _ = self.run_main(["--base", "origin/main"], diff="")
        self.assertEqual(status, 0)
        self.assertIn("no mutants in scope", printed)
        self.assertEqual(self.builds, 0)

    def test_a_package_that_fails_before_any_mutation_stops_the_run_with_2(self):
        status, _, complained = self.run_main(["--all", "--write-baseline"], clean=False)
        self.assertEqual(status, 2)
        self.assertIn("must build and pass its tests before it is mutated", complained)
        self.assertFalse(self.baseline.exists())

    def test_a_survivor_outside_the_baseline_fails_the_run_and_is_named(self):
        status, printed, complained = self.run_main(["--all"])
        self.assertEqual(status, 1)
        self.assertIn("0 killed, 1 survived, 0 discarded", printed)
        self.assertIn(f"survived: {self.FILE}:1  == → !=", complained)
        self.assertIn("let same = a == b", complained)

    def test_a_killed_mutant_passes_the_run(self):
        status, printed, complained = self.run_main(["--all"], mutants_pass=False)
        self.assertEqual(status, 0)
        self.assertIn("1 killed, 0 survived, 0 discarded", printed)
        self.assertEqual(complained, "")

    def test_only_the_changed_lines_are_mutated_under_base(self):
        (self.root / self.FILE).write_text("let same = a == b\nlet other = c != d\n", encoding="utf-8")
        _, printed, _ = self.run_main(["--base", "origin/main"], diff=self.CHANGED)
        self.assertIn("1 mutants", printed)
        self.assertNotIn("!= → ==", printed)

    def test_write_baseline_accepts_the_survivor_for_the_next_run(self):
        self.assertEqual(self.run_main(["--all", "--write-baseline"])[0], 0)
        self.assertEqual(len(mutation.read_baseline(self.baseline)), 1)
        self.assertEqual(self.run_main(["--all"])[0], 0)

    def test_base_merges_into_the_baseline_and_all_replaces_it(self):
        elsewhere = mutation.key(a_mutant(file="Packages/HarnessKit/Sources/HarnessCore/Gone.swift"))
        mutation.write_baseline(self.baseline, {elsewhere})
        self.run_main(["--base", "origin/main", "--write-baseline"], diff=self.CHANGED)
        merged = mutation.read_baseline(self.baseline)
        self.assertIn(elsewhere, merged)
        self.assertEqual(len(merged), 2)
        self.run_main(["--all", "--write-baseline"])
        replaced = mutation.read_baseline(self.baseline)
        self.assertNotIn(elsewhere, replaced)
        self.assertEqual(len(replaced), 1)

    def test_the_report_lists_every_outcome_and_creates_its_folder(self):
        report = self.root / "out" / "deep" / "report.json"
        self.run_main(["--all", "--report", str(report)], mutants_pass=False)
        outcomes = json.loads(report.read_text(encoding="utf-8"))
        self.assertEqual([(entry["file"], entry["line"], entry["original"], entry["outcome"]) for entry in outcomes],
                         [(self.FILE, 1, "==", "killed")])

    def test_the_package_in_the_repository_is_never_the_one_mutated(self):
        self.run_main(["--all"])
        self.assertEqual((self.root / self.FILE).read_text(encoding="utf-8"), "let same = a == b\n")


if __name__ == "__main__":
    unittest.main()
