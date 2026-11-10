"""Tests for select_scenarios.py."""

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import select_scenarios as s  # noqa: E402


def entry(name, tags, bond=False, needs=(), wallet=False):
    return {"name": name, "family": tags[0], "tags": list(tags), "moves_value": True,
            "needs_solver": False, "needs_app_wallet": wallet, "needs_bonded_daemon": bond,
            "needs": list(needs), "requires": [], "timeout_secs": 60}


CATALOG = {"schema": 1, "mortsom_version": "0", "scenarios": [
    entry("cancel_before_taken", ["cancellation", "smoke"]),
    entry("happy_sell", ["happy-path", "smoke"]),
    entry("range_order", ["happy-path"]),
    entry("dispute_settled", ["dispute"]),
    entry("maker_bond_abandoned", ["bond"], bond=True),
    entry("background_at_taken", ["recovery"], needs=["background"]),
    entry("nwc_cancel_payment", ["recovery"], wallet=True),
    entry("restart_at_taken", ["recovery"]),
]}

MAP = {"settings": {"always_tags": ["smoke"], "max_scenarios": 16}, "rule": [
    {"name": "docs", "paths": ["**/*.md", "docs/**"], "ignore": True},
    {"name": "core", "paths": ["rust/src/db/**"], "full": True},
    {"name": "trades", "paths": ["lib/features/order/**"], "tags": ["happy-path"]},
    {"name": "disputes", "paths": ["lib/features/disputes/**"], "tags": ["dispute"]},
    {"name": "bond", "paths": ["rust/src/api/bond.rs"], "tags": ["bond"]},
    {"name": "account", "paths": ["lib/features/account/**"], "tags": ["recovery"]},
    {"name": "chat", "paths": ["lib/features/chat/**"], "uncovered": "no chat scenario"},
]}


class TestSelect(unittest.TestCase):
    def test_docs_only_selects_nothing(self):
        sel = s.select(["README.md", "docs/x.md"], MAP, CATALOG)
        self.assertEqual((sel["mode"], sel["plain"], sel["bond"]), ("none", [], []))
        self.assertEqual(sel["ignored_files"], ["README.md", "docs/x.md"])

    def test_a_rule_adds_its_tags_to_smoke(self):
        sel = s.select(["lib/features/order/a.dart"], MAP, CATALOG)
        self.assertEqual(sel["mode"], "subset")
        self.assertEqual(sel["plain"], ["cancel_before_taken", "happy_sell", "range_order"])
        self.assertEqual(sel["matched_rules"], ["trades"])

    def test_bond_scenarios_go_to_their_own_stack(self):
        sel = s.select(["rust/src/api/bond.rs"], MAP, CATALOG)
        self.assertEqual(sel["bond"], ["maker_bond_abandoned"])
        self.assertEqual(sel["plain"], ["cancel_before_taken", "happy_sell"])

    def test_scenarios_linux_cannot_run_are_recorded_not_run(self):
        sel = s.select(["lib/features/account/a.dart"], MAP, CATALOG)
        self.assertIn("restart_at_taken", sel["plain"])
        self.assertEqual(sel["not_runnable"], ["background_at_taken", "nwc_cancel_payment"])

    def test_full_rule_selects_every_runnable_scenario(self):
        sel = s.select(["rust/src/db/mod.rs"], MAP, CATALOG)
        self.assertEqual(sel["mode"], "full")
        self.assertEqual(len(sel["plain"]) + len(sel["bond"]) + len(sel["not_runnable"]), 8)

    def test_uncovered_and_unmapped_files_are_reported_and_run_smoke(self):
        sel = s.select(["lib/features/chat/a.dart", "lib/new/x.dart"], MAP, CATALOG)
        self.assertEqual(sel["uncovered_files"], {"lib/features/chat/a.dart": "no chat scenario"})
        self.assertEqual(sel["unmapped_files"], ["lib/new/x.dart"])
        self.assertEqual(sel["plain"], ["cancel_before_taken", "happy_sell"])

    def test_unknown_tag_is_a_selection_error(self):
        bad = {"settings": MAP["settings"], "rule": [{"name": "x", "paths": ["a"], "tags": ["nope"]}]}
        with self.assertRaises(s.SelectionError):
            s.select(["a"], bad, CATALOG)

    def test_cap_keeps_smoke_and_reports_the_rest(self):
        capped = {"settings": {"always_tags": ["smoke"], "max_scenarios": 3}, "rule": MAP["rule"]}
        sel = s.select(["rust/src/db/mod.rs"], capped, CATALOG)
        self.assertEqual(sel["plain"][:2], ["cancel_before_taken", "happy_sell"])
        self.assertEqual(len(sel["plain"]), 3)
        self.assertTrue(sel["capped"])

    def test_the_baseline_is_full_and_never_capped(self):
        capped = {"settings": {"always_tags": ["smoke"], "max_scenarios": 1}, "rule": MAP["rule"]}
        sel = s.select([], capped, CATALOG, full=True, cap=False)
        self.assertEqual((sel["mode"], sel["capped"]), ("full", []))
        self.assertEqual(len(sel["plain"]), 5)

    def test_cli_writes_selection_and_github_outputs(self):
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            (d / "map.toml").write_text('[settings]\nalways_tags = ["smoke"]\n'
                                        '[[rule]]\nname = "t"\npaths = ["lib/**"]\ntags = ["happy-path"]\n')
            (d / "c.json").write_text(json.dumps(CATALOG))
            (d / "f.txt").write_text("lib/a.dart\0")
            out = d / "github_output"
            import os
            os.environ["GITHUB_OUTPUT"] = str(out)
            try:
                s.main(["--map", str(d / "map.toml"), "--catalog", str(d / "c.json"),
                        "--files", str(d / "f.txt"), "--out", str(d / "sel.json")])
            finally:
                del os.environ["GITHUB_OUTPUT"]
            self.assertIn("plain=cancel_before_taken happy_sell range_order", out.read_text())
            self.assertEqual(json.loads((d / "sel.json").read_text())["mode"], "subset")


if __name__ == "__main__":
    unittest.main()
