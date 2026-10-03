import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path

from support import load, patched

summary = load("summary")
Row = summary.Row

FILE = "Packages/HarnessKit/Sources/HarnessCore/A.swift"


def outcome(result, code="a == b", occurrence=0):
    return {"file": FILE, "line": 1, "offset": 2, "original": "==", "replacement": "!=",
            "code": code, "occurrence": occurrence, "outcome": result}


def accepted(code):
    return (FILE, code, "==", "!=", 0)


def job(name, conclusion, steps=()):
    return {"name": name, "conclusion": conclusion, "url": f"https://ci.example/{name.split()[0].lower()}",
            "steps": [{"name": step, "conclusion": state} for step, state in steps]}


class Percent(unittest.TestCase):
    def test_one_decimal_with_a_comma(self):
        self.assertEqual(summary.percent(96.46), "96,5%")
        self.assertEqual(summary.percent(80), "80,0%")


class CoverageRows(unittest.TestCase):
    ENTRIES = [
        {"name": "HarnessCore", "measured": 96.5, "floor": 96},
        {"name": "ClaudeHarness", "measured": 87.9, "floor": 87},
        {"name": "OpenCodeHarness", "measured": 64.9, "floor": 64},
        {"name": "HarnessProbeArguments", "measured": 91.2, "floor": 90},
        {"name": "Den", "measured": 80.1, "floor": 79},
    ]

    def test_each_target_shows_what_was_measured_beside_its_floor(self):
        self.assertEqual(summary.coverage_rows(self.ENTRIES), [
            Row("Cobertura · HarnessCore", "96,5%", "piso 96%", "✓"),
            Row("Cobertura · ClaudeHarness", "87,9%", "piso 87%", "✓"),
            Row("Cobertura · OpenCodeHarness", "64,9%", "piso 64%", "✓"),
            Row("Cobertura · HarnessProbeArguments", "91,2%", "piso 90%", "✓"),
            Row("Cobertura · app fora de Views", "80,1%", "piso 79%", "✓"),
        ])

    def test_the_order_is_fixed_whatever_order_the_reports_came_in(self):
        gates = [row.gate for row in summary.coverage_rows(list(reversed(self.ENTRIES)))]
        self.assertEqual(gates[0], "Cobertura · HarnessCore")
        self.assertEqual(gates[-1], "Cobertura · app fora de Views")

    def test_a_target_below_its_floor_is_crossed(self):
        rows = summary.coverage_rows([{"name": "Den", "measured": 78.96, "floor": 79}])
        self.assertEqual(rows[-1], Row("Cobertura · app fora de Views", "79,0%", "piso 79%", "✗"))

    def test_a_target_just_on_its_floor_passes(self):
        rows = summary.coverage_rows([{"name": "Den", "measured": 79.0, "floor": 79}])
        self.assertEqual(rows[-1].mark, "✓")

    def test_a_target_nothing_reported_has_no_data(self):
        rows = summary.coverage_rows([])
        self.assertEqual(len(rows), 5)
        self.assertEqual(rows[0], Row("Cobertura · HarnessCore", "sem dados", "sem dados", "—"))

    def test_a_target_measured_without_a_floor_or_the_other_way_round_is_not_judged(self):
        rows = summary.coverage_rows([{"name": "HarnessCore", "measured": None, "floor": 96},
                                      {"name": "Den", "measured": 80.1, "floor": None}])
        self.assertEqual(rows[0], Row("Cobertura · HarnessCore", "sem dados", "piso 96%", "—"))
        self.assertEqual(rows[-1], Row("Cobertura · app fora de Views", "80,1%", "sem dados", "—"))


class MutationRow(unittest.TestCase):
    GATE = "Mutação · linhas do PR"

    def test_survivors_the_baseline_lists_pass(self):
        outcomes = [outcome("killed")] * 4 + [outcome("survived", "s == t"), outcome("survived", "u == v")]
        row = summary.mutation_row(outcomes, {accepted("s == t"), accepted("u == v")})
        self.assertEqual(row, Row(self.GATE, "4 mortos, 2 vivos", "2 no baseline", "✓"))

    def test_a_survivor_the_baseline_does_not_list_fails(self):
        outcomes = [outcome("killed"), outcome("survived", "s == t"), outcome("survived", "new == one")]
        row = summary.mutation_row(outcomes, {accepted("s == t")})
        self.assertEqual(row, Row(self.GATE, "1 morto, 2 vivos", "1 no baseline, 1 novo", "✗"))

    def test_the_second_occurrence_on_a_line_is_not_covered_by_the_first(self):
        row = summary.mutation_row([outcome("survived", "s == t", occurrence=1)], {accepted("s == t")})
        self.assertEqual(row.mark, "✗")

    def test_discarded_mutants_are_counted_apart(self):
        row = summary.mutation_row([outcome("killed"), outcome("discarded"), outcome("discarded")], set())
        self.assertEqual(row, Row(self.GATE, "1 morto, 0 vivos, 2 descartados", "0 no baseline", "✓"))

    def test_a_pull_request_without_mutants_passes_and_says_so(self):
        self.assertEqual(summary.mutation_row([], set()),
                         Row(self.GATE, "nenhum mutante nas linhas alteradas", "—", "✓"))

    def test_without_a_report_there_is_no_data(self):
        self.assertEqual(summary.mutation_row(None, set()), Row(self.GATE, "sem dados", "sem dados", "—"))


class HookStates(unittest.TestCase):
    def test_each_hook_line_gives_its_result(self):
        text = "\n".join([
            "[INFO] Initializing environment for https://github.com/gitleaks/gitleaks.",
            "check yaml...............................................................Passed",
            "SwiftFormat..............................................................Passed",
            "SwiftLint................................................................Failed",
            "- hook id: swiftlint",
            "Duplicated code (jscpd)..................................................Passed",
            "check for broken symlinks............................(no files to check)Skipped",
        ])
        states = summary.hook_states(text)
        self.assertEqual(states["SwiftFormat"], "success")
        self.assertEqual(states["SwiftLint"], "failure")
        self.assertEqual(states["Duplicated code (jscpd)"], "success")
        self.assertIsNone(states["check for broken symlinks"])
        self.assertNotIn("- hook id: swiftlint", states)

    def test_colour_codes_are_ignored(self):
        text = "SwiftLint................................................................\x1b[42mPassed\x1b[m"
        self.assertEqual(summary.hook_states(text), {"SwiftLint": "success"})


class CheckRow(unittest.TestCase):
    def test_a_passing_check_shows_the_clean_reading(self):
        self.assertEqual(summary.check_row("Lint", "success", "https://ci.example/static", "0 novas", "280 no baseline"),
                         Row("Lint", "0 novas", "280 no baseline", "✓"))

    def test_a_failing_check_links_to_its_job(self):
        self.assertEqual(summary.check_row("Lint", "failure", "https://ci.example/static", "0 novas", "280 no baseline"),
                         Row("Lint", "[falhou](https://ci.example/static)", "280 no baseline", "✗"))

    def test_a_failing_check_without_a_link_still_says_so(self):
        self.assertEqual(summary.check_row("Lint", "failure", None, "0 novas", "280 no baseline").measured, "falhou")

    def test_a_check_that_did_not_finish_has_no_data(self):
        for state in (None, "cancelled", "skipped"):
            self.assertEqual(summary.check_row("Lint", state, None, "0 novas", "280 no baseline"),
                             Row("Lint", "sem dados", "280 no baseline", "—"), state)


class Rows(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name) / "repo"
        self.reports = Path(scratch.name) / "reports"
        self.root.mkdir()
        self.reports.mkdir()

    def write(self, base, name, content):
        path = base / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content if isinstance(content, str) else json.dumps(content), encoding="utf-8")

    def fill(self, static="success", build="success", unused="success", sanitizer="success", lint_hook="Passed"):
        self.write(self.root, ".swiftlint-baseline.json", [{}] * 280)
        self.write(self.root, ".jscpd-baseline.json", {"version": 1, "fingerprints": {str(n): {} for n in range(65)}})
        self.write(self.root, ".periphery-baseline.json", {"v1": {"usrs": ["a", "b", "c", "d", "e", "f"]}})
        self.write(self.root, ".mutation-baseline.json",
                   [{"file": FILE, "code": "s == t", "original": "==", "replacement": "!=", "occurrence": 0}])
        self.write(self.reports, "gate-coverage-package/coverage-package.json", CoverageRows.ENTRIES[:4])
        self.write(self.reports, "gate-coverage-app/coverage-app.json", CoverageRows.ENTRIES[4:])
        self.write(self.reports, "gate-mutation/mutation.json", [outcome("killed"), outcome("survived", "s == t")])
        self.write(self.reports, "gate-hooks/hooks.txt", "\n".join([
            "SwiftFormat..............................................................Passed",
            f"SwiftLint................................................................{lint_hook}",
            "Duplicated code (jscpd)..................................................Passed",
        ]))
        self.write(self.reports, "quality-jobs.json", {"jobs": [
            job("Format, lint, duplication, secrets", static),
            job("Warnings as errors, unused code", "success" if build == unused == "success" else "failure",
                [("Build everything with warnings as errors", build), ("Look for unused code", unused)]),
        ]})
        self.write(self.reports, "tests-jobs.json", {"jobs": [job("Thread Sanitizer", sanitizer)]})

    def table(self):
        return {row.gate: row for row in summary.rows(self.reports, self.root)}

    def test_every_gate_has_a_row_in_reading_order(self):
        self.fill()
        self.assertEqual([row.gate for row in summary.rows(self.reports, self.root)], [
            "Cobertura · HarnessCore", "Cobertura · ClaudeHarness", "Cobertura · OpenCodeHarness",
            "Cobertura · HarnessProbeArguments", "Cobertura · app fora de Views", "Mutação · linhas do PR",
            "Formatação", "Lint", "Código duplicado", "Warnings como erro", "Código morto", "Thread Sanitizer",
        ])

    def test_a_clean_run_shows_each_reading_beside_its_baseline(self):
        self.fill()
        table = self.table()
        self.assertEqual(table["Mutação · linhas do PR"], Row("Mutação · linhas do PR", "1 morto, 1 vivo", "1 no baseline", "✓"))
        self.assertEqual(table["Formatação"], Row("Formatação", "sem diferenças", "sem baseline", "✓"))
        self.assertEqual(table["Lint"], Row("Lint", "0 novas", "280 no baseline", "✓"))
        self.assertEqual(table["Código duplicado"], Row("Código duplicado", "0 novos", "65 no baseline", "✓"))
        self.assertEqual(table["Warnings como erro"], Row("Warnings como erro", "0 warnings", "sem baseline", "✓"))
        self.assertEqual(table["Código morto"], Row("Código morto", "0 novos", "6 no baseline", "✓"))
        self.assertEqual(table["Thread Sanitizer"], Row("Thread Sanitizer", "0 corridas", "sem baseline", "✓"))
        self.assertEqual({row.mark for row in table.values()}, {"✓"})

    def test_only_the_hook_that_failed_is_crossed(self):
        self.fill(static="failure", lint_hook="Failed")
        table = self.table()
        self.assertEqual(table["Lint"], Row("Lint", "[falhou](https://ci.example/format,)", "280 no baseline", "✗"))
        self.assertEqual(table["Formatação"].mark, "✓")
        self.assertEqual(table["Código duplicado"].mark, "✓")

    def test_a_build_that_fails_leaves_the_unused_code_scan_without_data(self):
        self.fill(build="failure", unused="skipped")
        table = self.table()
        self.assertEqual(table["Warnings como erro"].mark, "✗")
        self.assertEqual(table["Código morto"], Row("Código morto", "sem dados", "6 no baseline", "—"))

    def test_a_data_race_crosses_the_sanitizer(self):
        self.fill(sanitizer="failure")
        self.assertEqual(self.table()["Thread Sanitizer"].mark, "✗")

    def test_with_nothing_collected_every_row_says_so_and_none_is_crossed(self):
        rows = summary.rows(self.reports, self.root)
        self.assertEqual(len(rows), 12)
        self.assertEqual({row.measured for row in rows}, {"sem dados"})
        self.assertEqual({row.mark for row in rows}, {"—"})

    def test_a_report_that_is_not_valid_json_counts_as_missing(self):
        self.fill()
        self.write(self.reports, "gate-mutation/mutation.json", "{ truncated")
        self.assertEqual(self.table()["Mutação · linhas do PR"].measured, "sem dados")


class Render(unittest.TestCase):
    ROWS = [Row("Lint", "0 novas", "280 no baseline", "✓"), Row("Código morto", "sem dados", "6 no baseline", "—")]

    def test_the_comment_starts_with_the_marker_that_finds_it_again(self):
        self.assertTrue(summary.render(self.ROWS, None).startswith(summary.MARKER + "\n## Quality gates\n"))

    def test_each_row_is_a_table_line(self):
        text = summary.render(self.ROWS, None)
        self.assertIn("| Gate | Medido | Linha de base | |\n|---|---|---|:-:|\n", text)
        self.assertIn("| Lint | 0 novas | 280 no baseline | ✓ |\n", text)
        self.assertIn("| Código morto | sem dados | 6 no baseline | — |\n", text)

    def test_the_commit_is_named_when_known(self):
        self.assertTrue(summary.render(self.ROWS, "0123456789abcdef").endswith("commit `0123456`.\n"))
        self.assertNotIn("commit", summary.render(self.ROWS, None))


class Main(unittest.TestCase):
    def test_the_comment_is_printed_for_the_reports_folder_given(self):
        with tempfile.TemporaryDirectory() as scratch:
            printed = io.StringIO()
            with patched(summary, ROOT=Path(scratch)), contextlib.redirect_stdout(printed):
                status = summary.main(["--reports", scratch, "--commit", "abcdef0123"])
        self.assertEqual(status, 0)
        self.assertTrue(printed.getvalue().startswith(summary.MARKER))
        self.assertEqual(printed.getvalue().count("sem dados"), 12 + 9)
        self.assertIn("commit `abcdef0`", printed.getvalue())


if __name__ == "__main__":
    unittest.main()
