"""Changed files -> Mortsom scenarios to run (docs/MORTSOM_PR_E2E_SPEC.md § 4).

Pure functions plus a small CLI used by mortsom-pr.yml and, with `main`'s
map, by the verdict. Standard library only.

    select_scenarios.py --map map.toml --catalog scenarios.json \
        --files changed.txt --out selection.json [--full]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tomllib
from functools import lru_cache
from pathlib import Path


class SelectionError(Exception):
    """The map names a tag or scenario the catalog does not have."""


@lru_cache(maxsize=None)
def _glob_regex(pattern):
    """`**/` any directories, `**` anything, `*` and `?` within a segment."""
    out, i, n = [], 0, len(pattern)
    while i < n:
        if pattern.startswith("**/", i):
            out.append("(?:.*/)?")
            i += 3
        elif pattern.startswith("**", i):
            out.append(".*")
            i += 2
        elif pattern[i] == "*":
            out.append("[^/]*")
            i += 1
        elif pattern[i] == "?":
            out.append("[^/]")
            i += 1
        else:
            out.append(re.escape(pattern[i]))
            i += 1
    return re.compile("".join(out) + r"\Z")


def matches(path, patterns):
    return any(_glob_regex(p).match(path) for p in patterns)


def load_map(path):
    return tomllib.loads(Path(path).read_text())


def load_catalog(path):
    return json.loads(Path(path).read_text())


def matching_rules(path, rules):
    return [r for r in rules if matches(path, r.get("paths", []))]


def unmatched(paths, gate_map):
    """Paths no rule covers (the coverage test of § 4.4)."""
    rules = gate_map.get("rule", [])
    return [p for p in paths if not matching_rules(p, rules)]


def _resolve(tags, names, catalog):
    by_name = {s["name"]: s for s in catalog["scenarios"]}
    known_tags = {t for s in catalog["scenarios"] for t in s["tags"]}
    unknown = sorted(set(tags) - known_tags) + sorted(set(names) - set(by_name))
    if unknown:
        raise SelectionError(f"not in scenarios.json: {', '.join(unknown)}")
    chosen = {s["name"] for s in catalog["scenarios"] if set(s["tags"]) & set(tags)}
    return chosen | set(names)


def _runnable_on_linux(entry):
    return not entry["needs"] and not entry["needs_app_wallet"]


def _cap(names, always, limit):
    """Keep `always` first, then catalog order, up to `limit`."""
    if limit is None or len(names) <= limit:
        return names, []
    first = [n for n in names if n in always]
    rest = [n for n in names if n not in always]
    kept = (first + rest)[:max(limit, len(first))]
    return [n for n in names if n in kept], [n for n in names if n not in kept]


def select(files, gate_map, catalog, full=False, cap=True):
    """Return the selection.json document for `files`."""
    settings, rules = gate_map["settings"], gate_map.get("rule", [])
    out = {"mode": "none", "plain": [], "bond": [], "matched_rules": [],
           "uncovered_files": {}, "unmapped_files": [], "not_runnable": [],
           "capped": [], "ignored_files": []}
    remaining = []
    for path in files:
        hits = matching_rules(path, rules)
        if hits and all(r.get("ignore") for r in hits):
            out["ignored_files"].append(path)
        else:
            remaining.append((path, [r for r in hits if not r.get("ignore")]))
    if not remaining and not full:
        return out

    tags, names, matched = set(settings.get("always_tags", [])), set(), []
    is_full = full
    for path, hits in remaining:
        if not hits:
            out["unmapped_files"].append(path)
            continue
        selecting = [r for r in hits if not r.get("uncovered")]
        if not selecting:
            out["uncovered_files"][path] = "; ".join(r["uncovered"] for r in hits)
        for r in selecting:
            is_full = is_full or bool(r.get("full"))
            tags.update(r.get("tags", []))
            names.update(r.get("scenarios", []))
            if r["name"] not in matched:
                matched.append(r["name"])
    out["matched_rules"] = matched

    chosen = {s["name"] for s in catalog["scenarios"]} if is_full else _resolve(tags, names, catalog)
    out["mode"] = "full" if is_full else "subset"
    always = _resolve(settings.get("always_tags", []), [], catalog)
    limit = settings.get("max_scenarios") if cap else None
    for entry in catalog["scenarios"]:
        if entry["name"] not in chosen:
            continue
        if not _runnable_on_linux(entry):
            out["not_runnable"].append(entry["name"])
        else:
            out["bond" if entry["needs_bonded_daemon"] else "plain"].append(entry["name"])
    for key in ("plain", "bond"):
        out[key], dropped = _cap(out[key], always, limit)
        out["capped"] += dropped
    return out


def _write_outputs(selection):
    path = os.environ.get("GITHUB_OUTPUT")
    if not path:
        return
    with open(path, "a") as f:
        f.write(f"mode={selection['mode']}\n")
        f.write(f"plain={' '.join(selection['plain'])}\n")
        f.write(f"bond={' '.join(selection['bond'])}\n")


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--map", required=True)
    p.add_argument("--catalog", required=True)
    p.add_argument("--files", help="file of NUL-separated changed paths (git diff -z)")
    p.add_argument("--out", required=True)
    p.add_argument("--full", action="store_true", help="select everything (the baseline)")
    p.add_argument("--no-cap", action="store_true")
    args = p.parse_args(argv)
    files = [f for f in Path(args.files).read_text().split("\0") if f.strip()] if args.files else []
    try:
        selection = select(files, load_map(args.map), load_catalog(args.catalog),
                           full=args.full, cap=not args.no_cap)
    except SelectionError as e:
        selection = {"mode": "error", "error": str(e), "plain": [], "bond": []}
        print(f"::error::{e}", file=sys.stderr)
    Path(args.out).write_text(json.dumps(selection, indent=2) + "\n")
    _write_outputs(selection)
    print(json.dumps(selection, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
