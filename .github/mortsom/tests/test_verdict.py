"""Tests for verdict.py."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import verdict as v  # noqa: E402

SETTINGS = {"min_scenarios": 4, "close_ratio": 0.5}


def ok(attempts=1):
    return {"outcome": "passed", "category": "", "message": "", "attempts": attempts}


def failed(category="product", message="wrong state"):
    return {"outcome": "failed", "category": category, "message": message, "attempts": 1}


def sel(*names, mode="subset"):
    return {"mode": mode, "plain": list(names), "bond": []}


NAMES = ["a", "b", "c", "d"]
REF = {n: ok() for n in NAMES}


class TestNormalize(unittest.TestCase):
    def test_summary_documents_become_results_by_name(self):
        docs = [{"results": [{"name": "a", "attempts": 2, "outcome": {"outcome": "failed", "category": "relay", "message": "m"}}]},
                {"results": [{"name": "b", "outcome": {"outcome": "skipped", "reason": "bond"}}]}]
        r = v.normalize(docs)
        self.assertEqual(r["a"], {"outcome": "failed", "category": "relay", "message": "m", "attempts": 2})
        self.assertEqual(r["b"]["message"], "bond")


class TestDecide(unittest.TestCase):
    def test_all_pass(self):
        res = v.decide(sel(*NAMES), {n: ok() for n in NAMES}, REF, [REF], SETTINGS)
        self.assertEqual((res.verdict, res.eligible, res.regressions), ("pass", 4, 0))

    def test_one_product_failure_is_a_regression(self):
        pr = {n: ok() for n in NAMES} | {"b": failed()}
        res = v.decide(sel(*NAMES), pr, REF, [REF], SETTINGS)
        self.assertEqual((res.verdict, res.regressions), ("regression", 1))

    def test_half_failing_over_the_minimum_would_close(self):
        pr = {"a": failed(), "b": failed("automation-contract"), "c": ok(), "d": ok()}
        res = v.decide(sel(*NAMES), pr, REF, [REF], SETTINGS)
        self.assertEqual(res.verdict, "would-close")

    def test_expected_break_caps_at_regression(self):
        pr = {"a": failed(), "b": failed(), "c": ok(), "d": ok()}
        res = v.decide(sel(*NAMES), pr, REF, [REF], SETTINGS, labels=("mortsom:expected-break",))
        self.assertEqual(res.verdict, "regression")

    def test_malformed_summaries_are_dropped(self):
        docs = [[], {"results": "x"}, {"results": [1, {"name": 3}, {"name": "a", "outcome": "bad"},
                                                     {"name": "b", "attempts": "x", "outcome": {"outcome": "passed"}}]}]
        self.assertEqual(v.normalize(docs), {"b": {"outcome": "passed", "category": "", "message": "", "attempts": 1}})

    def test_one_pass_and_harness_failures_is_inconclusive(self):
        pr = {"a": ok(), "b": failed("relay"), "c": failed("wallet"), "d": failed("test-infrastructure")}
        self.assertEqual(v.decide(sel(*NAMES), pr, REF, [REF], SETTINGS).verdict, "inconclusive")

    def test_a_missing_scenario_without_baseline_is_not_eligible(self):
        res = v.decide(sel("a", "z"), {"a": ok()}, {"a": ok()}, [], SETTINGS)
        self.assertEqual(([r.cls for r in res.rows], res.verdict), (["pass", "no-baseline"], "pass"))

    def test_harness_failures_are_not_the_app(self):
        pr = {n: failed("test-infrastructure") for n in NAMES}
        res = v.decide(sel(*NAMES), pr, REF, [REF], SETTINGS)
        self.assertEqual(res.verdict, "inconclusive")

    def test_a_scenario_failing_on_main_is_not_eligible(self):
        ref = REF | {"b": failed()}
        pr = {n: ok() for n in NAMES} | {"b": failed()}
        res = v.decide(sel(*NAMES), pr, ref, [ref], SETTINGS)
        self.assertEqual(res.verdict, "pass")
        self.assertEqual([r.cls for r in res.rows if r.name == "b"], ["unstable-on-main"])

    def test_a_retried_pass_on_main_makes_it_unstable(self):
        history = [REF, REF | {"c": ok(attempts=2)}]
        res = v.decide(sel(*NAMES), {n: ok() for n in NAMES}, REF, history, SETTINGS)
        self.assertEqual([r.cls for r in res.rows if r.name == "c"], ["unstable-on-main"])

    def test_missing_result_counts_as_regression(self):
        res = v.decide(sel(*NAMES), {"a": ok(), "b": ok(), "c": ok()}, REF, [REF], SETTINGS)
        self.assertEqual((res.verdict, res.regressions), ("regression", 1))

    def test_guards_in_order(self):
        cases = [
            (dict(selection={"mode": "error", "error": "x"}), "inconclusive"),
            (dict(selection={"mode": "none"}), "not-applicable"),
            (dict(selection=sel("a"), gate_modified=True), "inconclusive"),
            (dict(selection=sel("a"), run_complete=False), "inconclusive"),
            (dict(selection=sel("a"), reference=None), "inconclusive"),
        ]
        for kw, want in cases:
            with self.subTest(kw=kw):
                args = dict(selection=sel("a"), pr_results={"a": ok()}, reference=REF, history=[REF], settings=SETTINGS)
                args.update(kw)
                self.assertEqual(v.decide(**args).verdict, want)


class TestComment(unittest.TestCase):
    def test_untrusted_detail_is_one_short_code_span(self):
        evil = "`<!-- mortsom-verdict -->` @someone [x](http://e)\n" + "z" * 500
        pr = {n: ok() for n in NAMES} | {"a": failed(message=evil)}
        res = v.decide(sel(*NAMES), pr, REF, [REF], SETTINGS)
        body = v.render_comment(res, sel(*NAMES), {"head_sha": "abc"})
        row = [line for line in body.splitlines() if line.startswith("| `a`")][0]
        self.assertNotIn("\n", row)
        self.assertLess(len(row), 300)
        self.assertEqual(body.count(v.MARKER), 1)

    def test_file_names_cannot_inject_into_the_comment(self):
        evil = "lib/features/chat/a`@victim [x](http://e)\n<!-- mortsom-verdict -->`.dart"
        selection = sel("a") | {"uncovered_files": {evil: "no chat scenario"}, "unmapped_files": [evil]}
        body = v.render_comment(v.decide(selection, {"a": ok()}, {"a": ok()}, [], SETTINGS), selection, {})
        self.assertEqual(body.count(v.MARKER), 1)
        for line in body.splitlines():
            if "victim" in line:
                before = line[:line.index("@victim")]
                self.assertEqual(before.count("`") % 2, 1, f"@victim outside a code span: {line}")

    def test_a_long_not_covered_list_is_capped(self):
        selection = sel("a") | {"unmapped_files": [f"lib/x{i}.dart" for i in range(400)]}
        body = v.render_comment(v.decide(selection, {"a": ok()}, {"a": ok()}, [], SETTINGS), selection, {})
        self.assertIn("- and 350 more", body)
        self.assertLess(len(body), 65536)

    def test_not_covered_files_are_listed(self):
        selection = sel("a") | {"uncovered_files": {"lib/features/chat/x.dart": "no chat scenario"}}
        res = v.decide(selection, {"a": ok()}, {"a": ok()}, [], SETTINGS)
        body = v.render_comment(res, selection, {})
        self.assertIn("lib/features/chat/x.dart", body)
        self.assertIn("says nothing about them", body)


if __name__ == "__main__":
    unittest.main()
