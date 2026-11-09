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


def normalize(summaries):
    """`summary.json` documents -> {name: result}."""
    out = {}
    for doc in summaries:
        for r in doc.get("results", []) or []:
            o = r.get("outcome") or {}
            out[str(r.get("name"))] = {
                "outcome": o.get("outcome"),
                "category": o.get("category") or "",
                "message": o.get("message") or o.get("reason") or "",
                "attempts": int(r.get("attempts") or 1),
            }
    return out


def _stable(name, reference, history):
    ref = reference.get(name)
    if not ref or ref["outcome"] != "passed":
        return False
    return all(
        h.get(name, {}).get("outcome") == "passed" and h.get(name, {}).get("attempts", 1) <= 1
        for h in history if name in h
    )


def classify(name, pr, reference, history):
    """One row of § 7.2. `pr` is the pull request result or None."""
    if pr is None:
        return Row(name, "missing")
    detail = pr.get("message", "")
    if pr["outcome"] == "skipped":
        return Row(name, "skipped", detail=detail)
    if name not in reference:
        return Row(name, "no-baseline")
    if not _stable(name, reference, history):
        return Row(name, "unstable-on-main")
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
    if failures and all(r.cls == "harness" for r in failures) and not eligible:
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
    one = one.replace("`", "'").replace("<!--", "<! --")
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
            lines.append(f"| `{r.name}` | {r.category or r.cls} | {_safe(r.detail) or '-'} |")
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
                      ", ".join(f"`{n}`" for n in names), "</details>"]
    uncovered = selection.get("uncovered_files", {})
    unmapped = selection.get("unmapped_files", [])
    if uncovered or unmapped:
        lines += ["", "**Not covered by any scenario** (this verdict says nothing about them):"]
        lines += [f"- `{p}`: {why}" for p, why in uncovered.items()]
        lines += [f"- `{p}`: no rule in `.github/mortsom/map.toml`" for p in unmapped]
    if ctx.get("run_url"):
        lines += ["", f"[Pull request run]({ctx['run_url']})"
                  + (f" · [baseline run]({ctx['baseline_url']})" if ctx.get("baseline_url") else "")]
    lines += ["", "Shadow mode: nothing is blocked or closed. Re-run with a push or the `mortsom:run` label; "
              "see docs/MORTSOM_PR_E2E_SPEC.md § 8 for the labels."]
    return "\n".join(lines)
