"""Verdict entry point (docs/MORTSOM_PR_E2E_SPEC.md § 7).

Runs from mortsom-verdict.yml on `workflow_run`, from a checkout of `main`.
It never checks out or runs pull request code: artifacts are downloaded as
data (size-limited JSON inside zip files) and the pull request, its files
and the baselines come from the API. Standard library only.
"""

import io
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

import select_scenarios
import verdict

GATE = Path(__file__).resolve().parent
BOT_LOGIN = "github-actions[bot]"
PER_PAGE = 100
MAX_JSON = 2_000_000
GATE_PATHS = (".github/mortsom/", ".github/workflows/mortsom-")
BASELINE_WORKFLOW = "mortsom-baseline.yml"


class GitHub:
    def __init__(self, repo, token, api="https://api.github.com"):
        self.repo, self.token, self.api = repo, token, api

    def _open(self, url, method="GET", body=None, accept="application/vnd.github+json"):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(url, data=data, method=method, headers={
            "Authorization": f"Bearer {self.token}", "Accept": accept,
            "X-GitHub-Api-Version": "2022-11-28"})
        with urllib.request.urlopen(req, timeout=60) as resp:
            return resp.read()

    def request(self, method, path, body=None, params=None):
        url = self.api + path + ("?" + urllib.parse.urlencode(params) if params else "")
        payload = self._open(url, method, body)
        return json.loads(payload) if payload else None

    def paginate(self, path, key=None, params=None, limit=1000):
        items, page = [], 1
        while len(items) < limit:
            batch = self.request("GET", path, params={**(params or {}), "per_page": PER_PAGE, "page": page})
            batch = batch[key] if key else batch
            items += batch
            if len(batch) < PER_PAGE:
                break
            page += 1
        return items

    def artifact_json(self, artifact):
        """{filename: parsed JSON} of one artifact; oversized files are skipped."""
        raw = self._open(artifact["archive_download_url"])
        out = {}
        with zipfile.ZipFile(io.BytesIO(raw)) as z:
            for info in z.infolist():
                if info.filename.endswith(".json") and info.file_size <= MAX_JSON:
                    try:
                        out[info.filename] = json.loads(z.read(info))
                    except (ValueError, UnicodeDecodeError):
                        print(f"::warning::unparsable {info.filename} in {artifact['name']}", file=sys.stderr)
        return out

    def run_artifacts(self, run_id):
        arts = self.paginate(f"/repos/{self.repo}/actions/runs/{run_id}/artifacts", key="artifacts")
        return {a["name"]: a for a in arts if not a.get("expired")}


def find_pull(gh, run):
    """The open pull request whose head is the run's head commit."""
    for pr in run.get("pull_requests") or []:
        return gh.request("GET", f"/repos/{gh.repo}/pulls/{pr['number']}")
    for pr in gh.request("GET", f"/repos/{gh.repo}/commits/{run['head_sha']}/pulls") or []:
        if pr["head"]["sha"] == run["head_sha"] and pr["state"] == "open":
            return pr
    return None


def summaries(gh, artifacts, names):
    docs = []
    for name in names:
        if name in artifacts:
            docs += [d for d in gh.artifact_json(artifacts[name]).values() if isinstance(d, dict)]
    return docs


def run_complete(gh, run_id, selection):
    """Every suite job that had scenarios finished with results."""
    jobs = gh.paginate(f"/repos/{gh.repo}/actions/runs/{run_id}/jobs", key="jobs")
    for stack in ("plain", "bond"):
        if not selection.get(stack):
            continue
        mine = [j for j in jobs if j["name"].startswith(f"{stack} /")]
        if not mine or any(j.get("conclusion") not in ("success", "failure") for j in mine):
            return False
    return True


def first_parents(gh, sha, depth):
    out = []
    for _ in range(depth + 1):
        out.append(sha)
        commit = gh.request("GET", f"/repos/{gh.repo}/commits/{sha}")
        parents = commit.get("parents") or []
        if not parents:
            break
        sha = parents[0]["sha"]
    return out


def baselines(gh, merge_base, settings):
    """(reference results, history, meta) of § 7.1."""
    walk = first_parents(gh, merge_base, settings["baseline_max_distance"])
    runs = gh.paginate(f"/repos/{gh.repo}/actions/workflows/{BASELINE_WORKFLOW}/runs", key="workflow_runs",
                       params={"branch": "main", "status": "completed"}, limit=60)
    by_sha = {}
    for r in runs:
        by_sha.setdefault(r["head_sha"], r)
    found = []
    for distance, sha in enumerate(walk):
        if sha not in by_sha or len(found) >= settings["stability_window"]:
            continue
        run = by_sha[sha]
        arts = gh.run_artifacts(run["id"])
        meta = next(iter(gh.artifact_json(arts["mortsom-baseline-meta"]).values()), {}) if "mortsom-baseline-meta" in arts else {}
        if meta.get("mortsom_ref") != settings["mortsom_ref"]:
            continue
        results = verdict.normalize(summaries(gh, arts, ["mortsom-baseline-plain", "mortsom-baseline-bond"]))
        if results:
            found.append({"sha": sha, "distance": distance, "url": run["html_url"], "results": results})
    if not found:
        return None, [], {}
    return found[0]["results"], [f["results"] for f in found], found[0]


def apply(gh, number, labels, v, body):
    for label in verdict.VERDICT_LABELS:
        if label in labels and label != v.label:
            remove_label(gh, number, label)
    if v.label and v.label not in labels:
        gh.request("POST", f"/repos/{gh.repo}/issues/{number}/labels", {"labels": [v.label]})
    if "mortsom:run" in labels:
        remove_label(gh, number, "mortsom:run")
    mine = [c for c in gh.paginate(f"/repos/{gh.repo}/issues/{number}/comments")
            if c["user"]["login"] == BOT_LOGIN and c["body"].startswith(verdict.MARKER)]
    if not mine:
        gh.request("POST", f"/repos/{gh.repo}/issues/{number}/comments", {"body": body})
    elif mine[0]["body"] != body:
        gh.request("PATCH", f"/repos/{gh.repo}/issues/comments/{mine[0]['id']}", {"body": body})


def remove_label(gh, number, label):
    try:
        gh.request("DELETE", f"/repos/{gh.repo}/issues/{number}/labels/{urllib.parse.quote(label)}")
    except urllib.error.HTTPError as e:
        if e.code != 404:
            raise


def evaluate(gh, run, pull):
    gate_map = select_scenarios.load_map(GATE / "map.toml")
    catalog = select_scenarios.load_catalog(GATE / "scenarios.json")
    settings = gate_map["settings"]
    files = []
    for f in gh.paginate(f"/repos/{gh.repo}/pulls/{pull['number']}/files", limit=3000):
        files.append(f["filename"])
        if f.get("previous_filename"):
            files.append(f["previous_filename"])
    try:
        selection = select_scenarios.select(files, gate_map, catalog)
    except select_scenarios.SelectionError as e:
        selection = {"mode": "error", "error": str(e), "plain": [], "bond": []}
    labels = tuple(label["name"] for label in pull.get("labels", []))
    if "mortsom:skip" in labels:
        return selection, verdict.Verdict("not-applicable", "mortsom:skip"), {}
    if selection["mode"] in ("none", "error"):
        return selection, verdict.decide(selection, {}, None, [], settings, labels=labels), {}
    artifacts = gh.run_artifacts(run["id"])
    pr_results = verdict.normalize(summaries(gh, artifacts, ["mortsom-pr-plain", "mortsom-pr-bond"]))
    merge_base = gh.request("GET", f"/repos/{gh.repo}/compare/main...{run['head_sha']}")["merge_base_commit"]["sha"]
    reference, history, base = baselines(gh, merge_base, settings)
    v = verdict.decide(
        selection, pr_results, reference, history, settings, labels=labels,
        gate_modified=any(p.startswith(GATE_PATHS) for p in files),
        run_complete=run_complete(gh, run["id"], selection))
    ctx = {"head_sha": run["head_sha"], "mortsom_ref": settings["mortsom_ref"], "run_url": run["html_url"],
           "baseline_sha": base.get("sha", ""), "distance": base.get("distance"), "baseline_url": base.get("url")}
    return selection, v, ctx


def main():
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    run = event["workflow_run"]
    gh = GitHub(os.environ["GITHUB_REPOSITORY"], os.environ["GITHUB_TOKEN"])
    pull = find_pull(gh, run)
    if pull is None:
        print(f"No open pull request has head {run['head_sha']}; nothing to report.")
        return 0
    if run.get("conclusion") == "skipped":
        print("The pull request run was skipped (draft, Dependabot or mortsom:skip).")
    selection, v, ctx = evaluate(gh, run, pull)
    body = verdict.render_comment(v, selection, ctx)
    labels = tuple(label["name"] for label in pull.get("labels", []))
    apply(gh, pull["number"], labels, v, body)
    report = f"## Mortsom verdict for #{pull['number']}: {v.verdict}\n\n{body}\n"
    print(report)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as f:
            f.write(report)
    return 0


if __name__ == "__main__":
    sys.exit(main())
