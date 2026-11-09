"""Tests for run_size_check.py with a fake GitHub client."""

import sys
import unittest
from pathlib import Path

QUALITY_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(QUALITY_DIR))

import run_size_check  # noqa: E402
import size_check  # noqa: E402

CFG = size_check.load_config(QUALITY_DIR / "config.toml")


class FakeGitHub:
    repo = "MostroP2P/app"

    def __init__(self, comments=(), files=(), texts=None):
        self.comments = [dict(c) for c in comments]
        self.files = list(files)
        self.texts = texts or {}
        self.calls = []

    def paginate(self, path, params=None):
        assert path.endswith("/files"), path
        return self.files

    def file_text(self, path, ref):
        self.calls.append(("text", path, ref))
        return self.texts.get((path, ref))

    def merge_base(self, base, head):
        return "mb"

    def add_labels(self, number, labels):
        self.calls.append(("add", tuple(labels)))

    def remove_label(self, number, label):
        self.calls.append(("remove", label))

    def list_comments(self, number):
        return self.comments

    def create_comment(self, number, body):
        self.calls.append(("create", body))

    def update_comment(self, comment_id, body):
        self.calls.append(("update", comment_id))

    def delete_comment(self, comment_id):
        self.calls.append(("delete", comment_id))

    def create_check_run(self, head_sha, conclusion, title, summary):
        self.calls.append(("check", conclusion, title))


def result(state, counted=2000):
    b = size_check.Breakdown()
    b.counted = counted
    return size_check.Result(state, b, 1500)


def mine(body):
    return {"id": 7, "user": {"login": "github-actions[bot]"}, "body": body}


class TestApplyResult(unittest.TestCase):
    def test_too_large_adds_label_comment_and_neutral_check(self):
        gh = FakeGitHub()
        run_size_check.apply_result(gh, 1, "sha", frozenset(), result("too_large"), CFG)
        kinds = [c[0] for c in gh.calls]
        self.assertIn(("add", ("quality:too-large",)), gh.calls)
        self.assertIn("create", kinds)
        self.assertEqual([c for c in gh.calls if c[0] == "check"][0][1], "neutral")

    def test_comment_is_edited_not_duplicated(self):
        gh = FakeGitHub(comments=[mine(size_check.MARKER + "\nold")])
        run_size_check.apply_result(gh, 1, "sha", frozenset({"quality:too-large"}), result("too_large"), CFG)
        kinds = [c[0] for c in gh.calls]
        self.assertIn("update", kinds)
        self.assertNotIn("create", kinds)
        self.assertNotIn("add", kinds)

    def test_ok_clears_label_and_comment(self):
        gh = FakeGitHub(comments=[mine(size_check.MARKER + "\nold"), {"id": 8, "user": {"login": "bob"}, "body": size_check.MARKER}])
        run_size_check.apply_result(gh, 1, "sha", frozenset({"quality:too-large"}), result("ok", 10), CFG)
        self.assertIn(("remove", "quality:too-large"), gh.calls)
        self.assertIn(("delete", 7), gh.calls)
        self.assertNotIn(("delete", 8), gh.calls)
        self.assertEqual([c for c in gh.calls if c[0] == "check"][0][1], "success")

    def test_exempt_clears_label(self):
        gh = FakeGitHub()
        run_size_check.apply_result(gh, 1, "sha", frozenset({"quality:too-large"}), result("exempt"), CFG)
        self.assertIn(("remove", "quality:too-large"), gh.calls)


class TestMeasure(unittest.TestCase):
    def test_reads_rust_sources_at_merge_base_and_head(self):
        patch = "@@ -0,0 +1,3 @@\n+fn a() {}\n+#[test]\n+fn t() {}"
        files = [{"filename": "rust/src/x.rs", "additions": 3, "deletions": 0, "patch": patch, "status": "added"}]
        gh = FakeGitHub(files=files, texts={("rust/src/x.rs", "head"): "fn a() {}\n#[test]\nfn t() {}\n"})
        b = run_size_check.measure(gh, 1, "base", "head", CFG["size"])
        self.assertEqual((b.counted, b.inline_tests), (1, 2))

    def test_no_rust_means_no_source_reads(self):
        files = [{"filename": "lib/a.dart", "additions": 3, "deletions": 1, "patch": "@@"}]
        gh = FakeGitHub(files=files)
        b = run_size_check.measure(gh, 1, "base", "head", CFG["size"])
        self.assertEqual(b.counted, 4)
        self.assertEqual([c for c in gh.calls if c[0] == "text"], [])


if __name__ == "__main__":
    unittest.main()
