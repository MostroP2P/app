"""Tests for size_check.py: classification, counting and the verdict."""

import sys
import unittest
from pathlib import Path

QUALITY_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(QUALITY_DIR))

import size_check  # noqa: E402
from size_check import ChangedFile, PullRequest  # noqa: E402

CFG = size_check.load_config(QUALITY_DIR / "config.toml")
SIZE = CFG["size"]


def no_source(_path):
    raise AssertionError("no source should be fetched")


class TestGlob(unittest.TestCase):
    def test_double_star_slash_matches_root_and_nested(self):
        self.assertTrue(size_check.matches("README.md", ["**/*.md"]))
        self.assertTrue(size_check.matches("lib/a/b.md", ["**/*.md"]))

    def test_single_star_stays_in_one_segment(self):
        self.assertTrue(size_check.matches("lib/l10n/app_localizations_es.dart", ["lib/l10n/app_localizations*.dart"]))
        self.assertFalse(size_check.matches("lib/l10n/x/app_localizations.dart", ["lib/l10n/app_localizations*.dart"]))

    def test_trailing_double_star(self):
        self.assertTrue(size_check.matches("lib/src/rust/api/orders.dart", ["lib/src/rust/**"]))
        self.assertFalse(size_check.matches("lib/src/rusty.dart", ["lib/src/rust/**"]))


class TestClassify(unittest.TestCase):
    def test_classes(self):
        cases = {
            "lib/src/rust/api/orders.dart": "generated",
            "rust/src/frb_generated.rs": "generated",
            "pubspec.lock": "generated",
            "test/features/order/goldens/card.png": "generated",
            "test/features/order/order_test.dart": "tests",
            "lib/features/order/widget_test.dart": "tests",
            "rust/tests/restore.rs": "tests",
            "docs/RELAYS.md": "docs",
            "README.md": "docs",
            "specs/004-mostro-p2p-client/plan.md": "docs",
            ".specify/memory/constitution.md": "docs",
            "lib/features/order/order_screen.dart": "counted",
            "rust/src/mostro/fsm.rs": "counted",
            "pubspec.yaml": "counted",
            ".github/workflows/ci.yml": "counted",
        }
        for path, want in cases.items():
            with self.subTest(path=path):
                self.assertEqual(size_check.classify(path, SIZE), want)


class TestCount(unittest.TestCase):
    def test_excluded_classes_do_not_count(self):
        files = [
            ChangedFile("lib/features/a.dart", 100, 20),
            ChangedFile("test/a_test.dart", 300, 0),
            ChangedFile("lib/src/rust/api/x.dart", 900, 50),
            ChangedFile("docs/X.md", 40, 2),
        ]
        b = size_check.count(files, SIZE, no_source, no_source)
        self.assertEqual((b.counted, b.tests, b.generated, b.docs), (120, 300, 950, 42))
        self.assertEqual(b.total, 1412)

    def test_inline_rust_tests_count_as_tests(self):
        old = "fn a() {}\n#[cfg(test)]\nmod tests {\n    fn t() {}\n}\n"
        new = "fn a2() {}\nfn b() {}\n#[cfg(test)]\nmod tests {\n    fn t() {}\n    fn u() {}\n}\n"
        patch = "@@ -1,5 +1,7 @@\n-fn a() {}\n+fn a2() {}\n+fn b() {}\n #[cfg(test)]\n mod tests {\n     fn t() {}\n+    fn u() {}\n }"
        f = ChangedFile("rust/src/mostro/fsm.rs", 3, 1, patch=patch)
        b = size_check.count([f], SIZE, lambda p: old, lambda p: new)
        self.assertEqual((b.counted, b.tests, b.inline_tests, b.unparsed), (3, 1, 1, []))

    def test_rename_reads_old_text_from_previous_path(self):
        seen = []
        f = ChangedFile("rust/src/b.rs", 0, 1, patch="@@ -1 +0,0 @@\n-fn a() {}",
                        previous_path="rust/src/a.rs", status="renamed")
        size_check.count([f], SIZE, lambda p: seen.append(p) or "fn a() {}\n", no_source)
        self.assertEqual(seen, ["rust/src/a.rs"])

    def test_missing_patch_is_diffed_from_both_versions(self):
        old = "fn a() {}\n#[cfg(test)]\nmod tests {\n    fn t() {}\n}\n"
        new = "fn a() {}\nfn b() {}\n#[cfg(test)]\nmod tests {\n    fn t() {}\n    fn u() {}\n    fn v() {}\n}\n"
        f = ChangedFile("rust/src/api/orders.rs", 3, 0, patch=None)
        b = size_check.count([f], SIZE, lambda p: old, lambda p: new)
        self.assertEqual((b.counted, b.inline_tests, b.unparsed), (1, 2, []))

    def test_missing_patch_and_unreadable_source_counts_every_line(self):
        f = ChangedFile("rust/src/api/orders.rs", 2000, 10, patch=None)
        b = size_check.count([f], SIZE, lambda p: None, lambda p: None)
        self.assertEqual((b.counted, b.unparsed), (2010, ["rust/src/api/orders.rs"]))

    def test_unreadable_source_counts_every_line(self):
        f = ChangedFile("rust/src/api/orders.rs", 1, 0, patch="@@ -0,0 +1 @@\n+fn x() {}")
        b = size_check.count([f], SIZE, no_source, lambda p: None)
        self.assertEqual((b.counted, b.unparsed), (1, ["rust/src/api/orders.rs"]))

    def test_rust_outside_src_is_counted_without_fetching(self):
        f = ChangedFile("rust/build.rs", 5, 5, patch="@@ -1 +1 @@\n-a\n+b")
        b = size_check.count([f], SIZE, no_source, no_source)
        self.assertEqual(b.counted, 10)


class TestDiffLines(unittest.TestCase):
    def test_replace_insert_delete(self):
        self.assertEqual(size_check.diff_lines("a\nb\nc", "a\nB\nc\nd"), ([2], [2, 4]))


class TestEvaluate(unittest.TestCase):
    def breakdown(self, counted):
        b = size_check.Breakdown()
        b.counted = counted
        return b

    def test_at_the_limit_is_ok(self):
        r = size_check.evaluate(PullRequest(1, "alice"), self.breakdown(1500), CFG)
        self.assertEqual(r.state, "ok")

    def test_over_the_limit(self):
        r = size_check.evaluate(PullRequest(1, "alice"), self.breakdown(1501), CFG)
        self.assertEqual((r.state, r.over_by), ("too_large", 1))

    def test_exempt_label(self):
        r = size_check.evaluate(PullRequest(1, "alice", labels=("size:exempt",)), self.breakdown(9000), CFG)
        self.assertEqual(r.state, "exempt")

    def test_bot_is_skipped(self):
        r = size_check.evaluate(PullRequest(1, "github-actions[bot]"), self.breakdown(9000), CFG)
        self.assertEqual(r.state, "skipped")

    def test_comment_names_the_limit_and_the_exempt_label(self):
        b = self.breakdown(2000)
        b.unparsed = ["rust/src/api/orders.rs"]
        r = size_check.evaluate(PullRequest(1, "alice"), b, CFG)
        body = size_check.render_comment(r, "size:exempt")
        self.assertTrue(body.startswith(size_check.MARKER))
        for text in ("2,000 changed lines", "1,500", "`size:exempt`", "`rust/src/api/orders.rs`"):
            self.assertIn(text, body)


if __name__ == "__main__":
    unittest.main()
