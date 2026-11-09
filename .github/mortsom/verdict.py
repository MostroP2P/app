"""Pull request results + baselines -> verdict (docs/MORTSOM_PR_E2E_SPEC.md § 7).

Pure functions over data run_verdict.py fetches. Standard library only.
Results are normalized to {name: {"outcome", "category", "message",
"attempts"}}; every string that came from a run is untrusted.
"""

from __future__ import annotations

from dataclasses import dataclass, field

MARKER = "<!-- mortsom-verdict -->"
APP_CATEGORIES = ("product", "automation-contract")
VERDICT_LABELS = ("mortsom:pass", "mortsom:regression", "mortsom:inconclusive", "mortsom:would-close")
DETAIL_MAX = 200
# Files listed as not covered; the rest are counted, so a large pull request
# cannot push the comment past GitHub's 65,536-character limit.
LIST_MAX = 50


@dataclass
class Row:
    name: str
    cls: str
    category: str = ""
    detail: str = ""
    attempts: int = 1


@dataclass
class Verdict:
    verdict: str
    reason: str = ""
    rows: list = field(default_factory=list)
    eligible: int = 0
    regressions: int = 0

    @property
    def label(self):
        return None if self.verdict == "not-applicable" else f"mortsom:{self.verdict}"


def _attempts(value):
    return value if isinstance(value, int) and not isinstance(value, bool) and value > 0 else 1


def normalize(summaries):
    """`summary.json` documents -> {name: result}. The documents come from a
    run of untrusted code: anything malformed is dropped, never raised."""
    out = {}
    for doc in summaries:
        results = doc.get("results") if isinstance(doc, dict) else None
        for r in results if isinstance(results, list) else []:
            o = r.get("outcome") if isinstance(r, dict) else None
            if not isinstance(o, dict) or not isinstance(r.get("name"), str):
                continue
            out[r["name"]] = {
                "outcome": o.get("outcome") if isinstance(o.get("outcome"), str) else None,
                "category": o.get("category") if isinstance(o.get("category"), str) else "",
                "message": str(o.get("message") or o.get("reason") or ""),
                "attempts": _attempts(r.get("attempts")),
            }
    return out


def built_revisions(summaries):
    """App commits Mortsom recorded as built (`app_build.remote_selection.revision`)."""
    revs = set()
    for doc in summaries:
        build = doc.get("app_build") if isinstance(doc, dict) else None
        sel = build.get("remote_selection") if isinstance(build, dict) else None
        rev = sel.get("revision") if isinstance(sel, dict) else None
        if isinstance(rev, str) and rev:
            revs.add(rev)
    return revs


def _stable(name, reference, history):
    ref = reference.get(name)
    if not ref or ref["outcome"] != "passed":
        return False
    return all(
        h.get(name, {}).get("outcome") == "passed" and h.get(name, {}).get("attempts", 1) <= 1
        for h in history if name in h
    )


def classify(name, pr, reference, history):
    """One row of § 7.2, in the table's order. `pr` is the result or None."""
    if pr is not None and pr["outcome"] == "skipped":
        return Row(name, "skipped", detail=pr.get("message", ""))
    if name not in reference:
        return Row(name, "no-baseline")
    if not _stable(name, reference, history):
        return Row(name, "unstable-on-main")
    if pr is None:
        return Row(name, "missing")
    detail = pr.get("message", "")
    if pr["outcome"] == "passed":
        return Row(name, "pass", attempts=pr.get("attempts", 1))
    category = pr.get("category", "")
    cls = "regression" if category in APP_CATEGORIES else "harness"
    return Row(name, cls, category=category, detail=detail, attempts=pr.get("attempts", 1))


def decide(selection, pr_results, reference, history, settings, *,
           labels=(), gate_modified=False, run_complete=True):
    """The verdict of § 7.3."""
    if selection.get("mode") == "error":
        return Verdict("inconclusive", f"selection error: {selection.get('error', '')}")
    if selection.get("mode") == "none":
        return Verdict("not-applicable", "no file the gate maps changed")
    if gate_modified:
        return Verdict("inconclusive", "gate-modified: this pull request changes the gate itself")
    if not run_complete:
        return Verdict("inconclusive", "incomplete-run: the app build or a suite job did not finish")
    if reference is None:
        return Verdict("inconclusive", "no-baseline: no baseline of main near the merge-base")
    selected = selection.get("plain", []) + selection.get("bond", [])
    rows = [classify(n, pr_results.get(n), reference, history) for n in selected]
    reg = sum(r.cls in ("regression", "missing") for r in rows)
    eligible = reg + sum(r.cls == "pass" for r in rows)
    v = Verdict("pass", rows=rows, eligible=eligible, regressions=reg)
    failures = [r for r in rows if r.cls in ("regression", "missing", "harness")]
    if failures and all(r.cls == "harness" for r in failures):
        v.verdict, v.reason = "inconclusive", "every failure is the harness, not the app"
        return v
    would_close = eligible >= settings["min_scenarios"] and reg / eligible >= settings["close_ratio"] if eligible else False
    if would_close and "mortsom:expected-break" not in labels:
        v.verdict = "would-close"
    elif reg:
        v.verdict = "regression"
    return v


def _safe(text):
    one = " ".join(str(text).split())[:DETAIL_MAX]
    one = one.replace("`", "'").replace("<!--", "<! --").replace("|", "/")
    return f"`{one}`" if one else ""


def _names(rows, cls):
    return [r.name for r in rows if r.cls == cls]


def render_comment(v, selection, ctx):
    """The sticky comment of § 7.4. `ctx` holds commits and links."""
    head = {
        "pass": "Every eligible scenario passed.",
        "regression": f"{v.regressions} of {v.eligible} eligible scenarios regressed.",
        "would-close": f"{v.regressions} of {v.eligible} eligible scenarios regressed, at or over the closing threshold.",
        "inconclusive": f"Inconclusive: {v.reason}.",
        "not-applicable": "No change the gate maps; nothing ran.",
    }[v.verdict]
    lines = [MARKER, f"### Mortsom e2e: `{v.verdict}`", "", head, ""]
    lines.append(
        f"App `{ctx.get('head_sha', '')[:12]}` · Mortsom `{ctx.get('mortsom_ref', '')[:12]}` · "
        f"baseline `{ctx.get('baseline_sha', '')[:12] or 'none'}`"
        + (f" ({ctx['distance']} commits from the merge-base)" if ctx.get("distance") is not None else "")
    )
    regs = [r for r in v.rows if r.cls in ("regression", "missing")]
    if regs:
        lines += ["", "| Scenario | Category | Detail |", "|---|---|---|"]
        for r in regs:
            lines.append(f"| {_safe(r.name)} | {_safe(r.category or r.cls)} | {_safe(r.detail) or '-'} |")
    groups = [
        ("Passed", _names(v.rows, "pass")),
        ("Harness failures (not the app)", _names(v.rows, "harness")),
        ("Skipped", _names(v.rows, "skipped")),
        ("Unstable on main", _names(v.rows, "unstable-on-main")),
        ("No baseline yet", _names(v.rows, "no-baseline")),
        ("Not runnable on Linux", selection.get("not_runnable", [])),
        ("Not run (over max_scenarios)", selection.get("capped", [])),
    ]
    for title, names in groups:
        if names:
            lines += ["", f"<details><summary>{title} ({len(names)})</summary>", "",
                      ", ".join(_safe(n) for n in names), "</details>"]
    uncovered = selection.get("uncovered_files", {})
    unmapped = selection.get("unmapped_files", [])
    if uncovered or unmapped:
        lines += ["", "**Not covered by any scenario** (this verdict says nothing about them):"]
        entries = [(p, why) for p, why in uncovered.items()]
        entries += [(p, "no rule in `.github/mortsom/map.toml`") for p in unmapped]
        lines += [f"- {_safe(p)}: {why}" for p, why in entries[:LIST_MAX]]
        if len(entries) > LIST_MAX:
            lines.append(f"- and {len(entries) - LIST_MAX} more")
    if ctx.get("run_url"):
        lines += ["", f"[Pull request run]({ctx['run_url']})"
                  + (f" · [baseline run]({ctx['baseline_url']})" if ctx.get("baseline_url") else "")]
    lines += ["", "Shadow mode: nothing is blocked or closed. Re-run with a push or the `mortsom:run` label; "
              "see docs/MORTSOM_PR_E2E_SPEC.md § 8 for the labels."]
    return "\n".join(lines)
