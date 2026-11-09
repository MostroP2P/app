"""Pull request size check (docs/CONTRIBUTION_QUALITY_SPEC.md § 7.6).

A pull request has at most `[size].max_lines` changed lines (additions plus
deletions), not counting tests, generated files and documentation. Lines
inside `#[cfg(test)]` items of `rust/src` count as tests.

Pure functions over data the runner (run_size_check.py) fetches from the
API. Standard library only.
"""

from __future__ import annotations

import difflib
import re
import tomllib
from dataclasses import dataclass, field
from functools import lru_cache
from pathlib import Path
from typing import Callable, Optional

import rust_tests

MARKER = "<!-- quality-size -->"

# Order matters: a golden image under test/ is generated, not a test.
CLASSES = ("generated", "tests", "docs")


@dataclass(frozen=True)
class ChangedFile:
    path: str
    additions: int
    deletions: int
    patch: Optional[str] = None
    previous_path: Optional[str] = None
    status: str = "modified"


@dataclass(frozen=True)
class PullRequest:
    number: int
    author: str
    labels: tuple = ()
    draft: bool = False


@dataclass
class Breakdown:
    counted: int = 0
    tests: int = 0
    generated: int = 0
    docs: int = 0
    inline_tests: int = 0
    # Rust files whose test lines could not be told apart (a source that
    # could not be read): every line was counted.
    unparsed: list = field(default_factory=list)

    @property
    def total(self):
        return self.counted + self.tests + self.generated + self.docs


@dataclass(frozen=True)
class Result:
    state: str  # "ok", "too_large", "exempt" or "skipped"
    breakdown: Breakdown
    max_lines: int
    reason: str = ""

    @property
    def over_by(self):
        return max(0, self.breakdown.counted - self.max_lines)


def load_config(path):
    return tomllib.loads(Path(path).read_text())


@lru_cache(maxsize=None)
def _glob_regex(pattern):
    """Translate a path glob: `**/` any directories, `**` anything, `*` and
    `?` within one path segment."""
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


def classify(path, size_cfg):
    """`generated`, `tests`, `docs` or `counted`."""
    for name in CLASSES:
        if matches(path, size_cfg.get(name, [])):
            return name
    return "counted"


def _add(breakdown, cls, lines):
    setattr(breakdown, cls, getattr(breakdown, cls) + lines)


def diff_lines(old_text, new_text):
    """(deleted old line numbers, added new line numbers), 1-based.

    For files whose patch GitHub omits because the diff is too large."""
    old, new = old_text.split("\n"), new_text.split("\n")
    deleted, added = [], []
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, old, new, autojunk=False).get_opcodes():
        if tag in ("replace", "delete"):
            deleted.extend(range(i1 + 1, i2 + 1))
        if tag in ("replace", "insert"):
            added.extend(range(j1 + 1, j2 + 1))
    return deleted, added


def _split_rust(f, fetch_old, fetch_new):
    """(counted, inline_tests) lines of a Rust source, or None if unknown."""
    if f.patch is None:
        old_text = fetch_old(f.previous_path or f.path) if f.status != "added" else ""
        new_text = fetch_new(f.path) if f.status != "removed" else ""
        if old_text is None or new_text is None:
            return None
        deleted, added = diff_lines(old_text, new_text)
    else:
        deleted, added = rust_tests.parse_diff_lines(f.patch)
        old_text = fetch_old(f.previous_path or f.path) if deleted and f.status != "added" else ""
        new_text = fetch_new(f.path) if added and f.status != "removed" else ""
        if old_text is None or new_text is None:
            return None
    old_tests = rust_tests.rust_test_lines(old_text) if deleted else set()
    new_tests = rust_tests.rust_test_lines(new_text) if added else set()
    inline = sum(ln in old_tests for ln in deleted) + sum(ln in new_tests for ln in added)
    return len(deleted) + len(added) - inline, inline


def count(files, size_cfg, fetch_old: Callable, fetch_new: Callable):
    """Split the changed lines of `files` into a Breakdown.

    `fetch_old(path)` / `fetch_new(path)` return the file's text at the
    merge base / head, or None when it cannot be read.
    """
    b = Breakdown()
    inline_globs = size_cfg.get("rust_inline_tests", [])
    for f in files:
        lines = f.additions + f.deletions
        cls = classify(f.path, size_cfg)
        if cls != "counted":
            _add(b, cls, lines)
            continue
        if not (matches(f.path, inline_globs) and f.path.endswith(".rs")):
            b.counted += lines
            continue
        split = _split_rust(f, fetch_old, fetch_new)
        if split is None:
            b.counted += lines
            b.unparsed.append(f.path)
            continue
        counted, inline = split
        b.counted += counted
        b.tests += inline
        b.inline_tests += inline
    return b


def evaluate(pull, breakdown, cfg):
    max_lines = cfg["size"]["max_lines"]
    if pull.author in cfg["authors"]["bots"]:
        return Result("skipped", breakdown, max_lines, "bot author")
    if cfg["labels"]["exempt"] in pull.labels:
        return Result("exempt", breakdown, max_lines, f"`{cfg['labels']['exempt']}`")
    state = "too_large" if breakdown.counted > max_lines else "ok"
    return Result(state, breakdown, max_lines)


def _fmt(n):
    return f"{n:,}"


def table(breakdown):
    rows = [
        "| | Changed lines |",
        "|---|---:|",
        f"| **Counted** | **{_fmt(breakdown.counted)}** |",
        f"| Tests | {_fmt(breakdown.tests)} |",
        f"| of which `#[cfg(test)]` items in `rust/src` | {_fmt(breakdown.inline_tests)} |",
        f"| Generated | {_fmt(breakdown.generated)} |",
        f"| Docs and specs | {_fmt(breakdown.docs)} |",
        f"| Total (as GitHub shows it) | {_fmt(breakdown.total)} |",
    ]
    return "\n".join(rows)


def render_comment(result, exempt_label):
    b = result.breakdown
    parts = [
        MARKER,
        f"**This pull request has {_fmt(b.counted)} changed lines, over the limit of "
        f"{_fmt(result.max_lines)}** (CONTRIBUTING.md § Pull request size). Tests, "
        "generated files and docs do not count.",
        "",
        table(b),
        "",
        "Please split it into smaller pull requests that each build, pass the tests "
        "and can be reviewed on their own, for example one per phase. If the size "
        f"cannot be avoided, explain why and a maintainer may apply `{exempt_label}`.",
    ]
    if b.unparsed:
        files = ", ".join(f"`{p}`" for p in b.unparsed)
        parts += ["", f"Test lines could not be told apart in {files}; all of their lines were counted."]
    return "\n".join(parts)


def summary(result):
    head = {
        "ok": f"{_fmt(result.breakdown.counted)} of {_fmt(result.max_lines)} lines",
        "too_large": f"{_fmt(result.breakdown.counted)} lines, {_fmt(result.over_by)} over the limit",
        "exempt": f"Exempt ({result.reason})",
        "skipped": f"Skipped ({result.reason})",
    }[result.state]
    return head + "\n\n" + table(result.breakdown)
