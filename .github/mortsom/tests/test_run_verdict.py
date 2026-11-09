"""Tests for run_verdict.py with a fake GitHub client."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import run_verdict as rv  # noqa: E402
import verdict  # noqa: E402

SETTINGS = {"baseline_max_distance": 3, "stability_window": 2, "mortsom_ref": "pin",
            "min_scenarios": 4, "close_ratio": 0.5}


def summary(**outcomes):
    return {"results": [{"name": n, "attempts": 1, "outcome": {"outcome": o}} for n, o in outcomes.items()]}


class FakeGitHub:
    repo = "MostroP2P/app"

    def __init__(self, jobs=(), commits=None, runs=(), artifacts=None, files=(), comments=()):
        self.jobs, self.commits, self.runs = list(jobs), commits or {}, list(runs)
        self.artifacts, self.files, self.comments = artifacts or {}, list(files), list(comments)
        self.calls = []

    def paginate(self, path, key=None, params=None, limit=1000):
        if path.endswith("/jobs"):
            return self.jobs
        if "/workflows/" in path:
            return self.runs
        if path.endswith("/files"):
            return self.files
        if path.endswith("/comments"):
            return self.comments
        raise AssertionError(path)

    def request(self, method, path, body=None, params=None):
        self.calls.append((method, path, body))
        if method == "GET" and "/commits/" in path:
            sha = path.rsplit("/", 1)[1]
            parent = self.commits.get(sha)
            return {"parents": [{"sha": parent}] if parent else []}
        return None

    def run_artifacts(self, run_id):
        return {name: {"name": name, "run": run_id} for (rid, name) in self.artifacts if rid == run_id}

    def artifact_json(self, artifact):
        return self.artifacts[(artifact["run"], artifact["name"])]


class TestRunComplete(unittest.TestCase):
    def test_finished_suite_jobs_are_complete(self):
        gh = FakeGitHub(jobs=[{"name": "plain / mobile-v2 on Linux (x)", "conclusion": "failure"}])
        self.assertTrue(rv.run_complete(gh, 1, {"plain": ["a"], "bond": []}, {"plain": {"a": {}}}))

    def test_a_failed_job_without_results_is_incomplete(self):
        gh = FakeGitHub(jobs=[{"name": "plain / mobile-v2 on Linux (x)", "conclusion": "failure"}])
        self.assertFalse(rv.run_complete(gh, 1, {"plain": ["a"], "bond": []}, {"plain": {}}))

    def test_cancelled_or_absent_suite_job_is_incomplete(self):
        gh = FakeGitHub(jobs=[{"name": "plain / mobile-v2 on Linux (x)", "conclusion": "cancelled"}])
        self.assertFalse(rv.run_complete(gh, 1, {"plain": ["a"], "bond": []}, {"plain": {"a": {}}}))
        self.assertFalse(rv.run_complete(FakeGitHub(), 1, {"plain": [], "bond": ["b"]}, {"bond": {"b": {}}}))


class TestFindPull(unittest.TestCase):
    def test_a_run_of_an_older_head_finds_no_pull_request(self):
        class GH(FakeGitHub):
            def request(self, method, path, body=None, params=None):
                if path.endswith("/pulls/7"):
                    return {"number": 7, "state": "open", "head": {"sha": "new"}}
                return []
        self.assertIsNone(rv.find_pull(GH(), {"head_sha": "old", "pull_requests": [{"number": 7}]}))


class TestBaselines(unittest.TestCase):
    def gh(self, meta_ref="pin"):
        commits = {"m0": "m1", "m1": "m2", "m2": "m3"}
        runs = [{"id": 11, "head_sha": "m1", "html_url": "u11"}, {"id": 12, "head_sha": "m2", "html_url": "u12"},
                {"id": 13, "head_sha": "zz", "html_url": "u13"}]
        artifacts = {}
        for rid, outcome in ((11, "passed"), (12, "failed")):
            artifacts[(rid, "mortsom-baseline-meta")] = {"meta.json": {"sha": "x", "mortsom_ref": meta_ref}}
            artifacts[(rid, "mortsom-baseline-plain")] = {"r.json": summary(a=outcome)}
        return FakeGitHub(commits=commits, runs=runs, artifacts=artifacts)

    def test_most_recent_baseline_on_the_first_parent_walk_is_the_reference(self):
        ref, history, base = rv.baselines(self.gh(), "m0", SETTINGS)
        self.assertEqual(ref["a"]["outcome"], "passed")
        self.assertEqual((base["sha"], base["distance"], len(history)), ("m1", 1, 2))

    def test_baselines_of_another_mortsom_are_not_candidates(self):
        ref, history, base = rv.baselines(self.gh(meta_ref="old"), "m0", SETTINGS)
        self.assertEqual((ref, history, base), (None, [], {}))


class TestApply(unittest.TestCase):
    def test_swaps_verdict_labels_and_keeps_one_comment(self):
        mine = {"id": 5, "user": {"login": "github-actions[bot]"}, "body": verdict.MARKER + "\nold"}
        gh = FakeGitHub(comments=[mine])
        rv.apply(gh, 9, ("mortsom:pass", "mortsom:run"), verdict.Verdict("regression"), verdict.MARKER + "\nnew")
        methods = [(m, p.rsplit("/", 1)[-1]) for m, p, _ in gh.calls]
        self.assertIn(("DELETE", "mortsom%3Apass"), methods)
        self.assertIn(("DELETE", "mortsom%3Arun"), methods)
        self.assertIn(("POST", "labels"), methods)
        self.assertIn(("PATCH", "5"), methods)

    def test_not_applicable_only_removes_labels(self):
        gh = FakeGitHub()
        rv.apply(gh, 9, ("mortsom:regression",), verdict.Verdict("not-applicable"), verdict.MARKER)
        posted_labels = [c for c in gh.calls if c[0] == "POST" and c[1].endswith("/labels")]
        self.assertEqual(posted_labels, [])


if __name__ == "__main__":
    unittest.main()
