"""Pull request size check entry point (docs/CONTRIBUTION_QUALITY_SPEC.md § 7.6).

Runs from quality-size.yml on pull_request_target, from a checkout of `main`.
It never checks out or runs pull request code: the changed files, their
patches and the Rust sources it needs to tell test lines apart come from the
API as data. Standard library only.
"""

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import size_check

QUALITY_DIR = Path(__file__).resolve().parent
BOT_LOGIN = "github-actions[bot]"
CHECK_NAME = "Pull request size"
PER_PAGE = 100


class GitHub:
    """The few REST calls the check needs."""

    def __init__(self, repo, token, api="https://api.github.com"):
        self.repo, self.token, self.api = repo, token, api

    def request(self, method, path, body=None, params=None, raw=False):
        url = self.api + path + ("?" + urllib.parse.urlencode(params) if params else "")
        data = json.dumps(body).encode() if body is not None else None
        accept = "application/vnd.github.raw" if raw else "application/vnd.github+json"
        req = urllib.request.Request(url, data=data, method=method, headers={
            "Authorization": f"Bearer {self.token}",
            "Accept": accept,
            "X-GitHub-Api-Version": "2022-11-28",
        })
        with urllib.request.urlopen(req, timeout=30) as resp:
            payload = resp.read()
        if raw:
            return payload.decode("utf-8", errors="replace")
        return json.loads(payload) if payload else None

    def paginate(self, path, params=None):
        items, page = [], 1
        while True:
            batch = self.request("GET", path, params={**(params or {}), "per_page": PER_PAGE, "page": page})
            items += batch
            if len(batch) < PER_PAGE:
                return items
            page += 1

    def file_text(self, path, ref):
        """The file's text at `ref`, or None when it cannot be read."""
        try:
            return self.request("GET", f"/repos/{self.repo}/contents/{urllib.parse.quote(path)}",
                                params={"ref": ref}, raw=True)
        except urllib.error.HTTPError as e:
            print(f"::warning::could not read {path} at {ref[:12]}: HTTP {e.code}", file=sys.stderr)
            return None

    def merge_base(self, base_sha, head_sha):
        data = self.request("GET", f"/repos/{self.repo}/compare/{base_sha}...{head_sha}")
        return data["merge_base_commit"]["sha"]

    def add_labels(self, number, labels):
        self.request("POST", f"/repos/{self.repo}/issues/{number}/labels", {"labels": list(labels)})

    def remove_label(self, number, label):
        try:
            self.request("DELETE", f"/repos/{self.repo}/issues/{number}/labels/{urllib.parse.quote(label)}")
        except urllib.error.HTTPError as e:
            if e.code != 404:  # already gone
                raise

    def list_comments(self, number):
        return self.paginate(f"/repos/{self.repo}/issues/{number}/comments")

    def create_comment(self, number, body):
        self.request("POST", f"/repos/{self.repo}/issues/{number}/comments", {"body": body})

    def update_comment(self, comment_id, body):
        self.request("PATCH", f"/repos/{self.repo}/issues/comments/{comment_id}", {"body": body})

    def delete_comment(self, comment_id):
        self.request("DELETE", f"/repos/{self.repo}/issues/comments/{comment_id}")

    def create_check_run(self, head_sha, conclusion, title, summary):
        self.request("POST", f"/repos/{self.repo}/check-runs", {
            "name": CHECK_NAME, "head_sha": head_sha, "status": "completed",
            "conclusion": conclusion, "output": {"title": title, "summary": summary},
        })


def pull_request_from_event(event):
    pr = event["pull_request"]
    return size_check.PullRequest(
        number=pr["number"],
        author=pr["user"]["login"],
        labels=tuple(label["name"] for label in pr.get("labels", [])),
        draft=bool(pr.get("draft")),
    )


def changed_files(gh, number):
    return [
        size_check.ChangedFile(
            path=f["filename"], additions=f.get("additions", 0), deletions=f.get("deletions", 0),
            patch=f.get("patch"), previous_path=f.get("previous_filename"), status=f.get("status", "modified"),
        )
        for f in gh.paginate(f"/repos/{gh.repo}/pulls/{number}/files")
    ]


def measure(gh, number, base_sha, head_sha, size_cfg):
    files = changed_files(gh, number)
    needs_source = any(
        f.path.endswith(".rs") and size_check.classify(f.path, size_cfg) == "counted"
        and size_check.matches(f.path, size_cfg.get("rust_inline_tests", []))
        for f in files
    )
    old_ref = gh.merge_base(base_sha, head_sha) if needs_source else base_sha
    return size_check.count(
        files, size_cfg,
        fetch_old=lambda p: gh.file_text(p, old_ref),
        fetch_new=lambda p: gh.file_text(p, head_sha),
    )


def sticky_comments(gh, number):
    return [
        c for c in gh.list_comments(number)
        if c["user"]["login"] == BOT_LOGIN and c["body"].startswith(size_check.MARKER)
    ]


def apply_result(gh, number, head_sha, current_labels, result, cfg):
    """Set or clear the label, keep one comment, report a neutral check run."""
    label = cfg["labels"]["too_large"]
    too_large = result.state == "too_large"
    if too_large and label not in current_labels:
        gh.add_labels(number, [label])
    if not too_large and label in current_labels:
        gh.remove_label(number, label)

    mine = sticky_comments(gh, number)
    if too_large:
        body = size_check.render_comment(result, cfg["labels"]["exempt"])
        if not mine:
            gh.create_comment(number, body)
        elif mine[0]["body"] != body:
            gh.update_comment(mine[0]["id"], body)
    else:
        for c in mine:
            gh.delete_comment(c["id"])

    # Never `failure`: the check informs, it does not block a merge.
    conclusion = "neutral" if too_large else "success"
    title = {
        "ok": "Within the size limit",
        "too_large": f"{result.over_by:,} lines over the limit",
        "exempt": "Exempt",
        "skipped": "Skipped",
    }[result.state]
    try:
        gh.create_check_run(head_sha, conclusion, title, size_check.summary(result))
    except urllib.error.HTTPError as e:
        print(f"::warning::could not create the check run: HTTP {e.code}", file=sys.stderr)


def main():
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    pr = event["pull_request"]
    pull = pull_request_from_event(event)
    if pull.draft:
        print(f"#{pull.number} is a draft; it is checked when marked ready for review.")
        return 0

    cfg = size_check.load_config(QUALITY_DIR / "config.toml")
    gh = GitHub(os.environ["GITHUB_REPOSITORY"], os.environ["GITHUB_TOKEN"])
    head_sha = pr["head"]["sha"]

    breakdown = size_check.count([], cfg["size"], None, None)
    if pull.author not in cfg["authors"]["bots"] and cfg["labels"]["exempt"] not in pull.labels:
        breakdown = measure(gh, pull.number, pr["base"]["sha"], head_sha, cfg["size"])
    result = size_check.evaluate(pull, breakdown, cfg)
    apply_result(gh, pull.number, head_sha, frozenset(pull.labels), result, cfg)

    report = f"## Pull request size of #{pull.number}\n\n{size_check.summary(result)}\n"
    print(report)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as f:
            f.write(report)
    return 0


if __name__ == "__main__":
    sys.exit(main())
