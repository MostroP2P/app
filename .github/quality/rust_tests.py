"""Find the lines of Rust source that belong to tests.

Used by the pull request size check (size_check.py) so that lines inside
`#[cfg(test)]` items, and `#[test]` / `#[tokio::test]` functions, count as
tests even though they live in `rust/src/**/*.rs`.

A small lexer skips strings, raw strings, chars and comments, so braces
inside them never confuse the bracket matching. Standard library only.
"""

from __future__ import annotations

import re

# ---------------------------------------------------------------------------
# Rust lexer (just enough to find attributes and match brackets)
# ---------------------------------------------------------------------------

_RAW_PREFIXES = ("r", "br", "cr")


def _is_ident_start(c: str) -> bool:
    return c == "_" or c.isalpha()


def _is_ident_char(c: str) -> bool:
    return c == "_" or c.isalnum()


def _skip_string(text: str, j: int, line: int):
    """``text[j]`` is the opening quote. Return (index after close, line)."""
    n = len(text)
    j += 1
    while j < n:
        c = text[j]
        if c == "\\":
            if j + 1 < n and text[j + 1] == "\n":
                line += 1
            j += 2
            continue
        if c == '"':
            return j + 1, line
        if c == "\n":
            line += 1
        j += 1
    return n, line


def _skip_raw_string(text: str, j: int, line: int):
    """``text[j]`` is the first ``#`` or the quote after the r prefix.

    Return (index after close, line), or None when this is a raw identifier.
    """
    n = len(text)
    k = 0
    while j < n and text[j] == "#":
        k += 1
        j += 1
    if j >= n or text[j] != '"':
        return None
    close = '"' + "#" * k
    end = text.find(close, j + 1)
    if end < 0:
        end = n
    line += text.count("\n", j, end)
    return min(end + len(close), n), line


def _skip_char_or_lifetime(text: str, i: int):
    """``text[i]`` is a single quote. Return (index after token, kind)."""
    n = len(text)
    if i + 1 < n and text[i + 1] == "\\":
        end = text.find("'", i + 3)
        if end < 0 or end - i > 14:
            return i + 2, "char"
        return end + 1, "char"
    if i + 2 < n and text[i + 2] == "'":
        return i + 3, "char"
    j = i + 1
    while j < n and _is_ident_char(text[j]):
        j += 1
    return max(j, i + 1), "lifetime"


def _lex_ident(text, i, line, toks):
    n = len(text)
    j = i
    while j < n and _is_ident_char(text[j]):
        j += 1
    word = text[i:j]
    nxt = text[j] if j < n else ""
    if word in _RAW_PREFIXES and nxt in '"#':
        res = _skip_raw_string(text, j, line)
        if res is not None:
            toks.append(("str", '"', line))
            return res
        if nxt == "#":  # raw identifier r#name
            k = j + 1
            while k < n and _is_ident_char(text[k]):
                k += 1
            toks.append(("id", text[j + 1:k], line))
            return k, line
    if word in ("b", "c") and nxt == '"':
        end, line2 = _skip_string(text, j, line)
        toks.append(("str", '"', line))
        return end, line2
    if word == "b" and nxt == "'":
        end, _ = _skip_char_or_lifetime(text, j)
        toks.append(("char", "'", line))
        return end, line
    toks.append(("id", word, line))
    return j, line


def _skip_block_comment(text, i, line):
    n = len(text)
    depth, i = 1, i + 2
    while i < n and depth:
        if text.startswith("/*", i):
            depth, i = depth + 1, i + 2
        elif text.startswith("*/", i):
            depth, i = depth - 1, i + 2
        else:
            if text[i] == "\n":
                line += 1
            i += 1
    return i, line


def lex_rust(text: str):
    """Tokenize Rust source into (kind, value, line). Comments are dropped.

    Kinds: id, str, char, lifetime, num, punct. String and char contents are
    not kept, so braces inside them never reach the bracket matcher.
    """
    toks = []
    i, n, line = 0, len(text), 1
    while i < n:
        c = text[i]
        if c == "\n":
            line += 1
            i += 1
        elif c.isspace():
            i += 1
        elif c == "/" and text.startswith("//", i):
            end = text.find("\n", i)
            i = n if end < 0 else end
        elif c == "/" and text.startswith("/*", i):
            i, line = _skip_block_comment(text, i, line)
        elif _is_ident_start(c):
            i, line = _lex_ident(text, i, line, toks)
        elif c == '"':
            toks.append(("str", '"', line))
            i, line = _skip_string(text, i, line)
        elif c == "'":
            end, kind = _skip_char_or_lifetime(text, i)
            toks.append((kind, "'", line))
            i = end
        elif c.isdigit():
            j = i + 1
            while j < n and (_is_ident_char(text[j]) or (
                text[j] == "." and j + 1 < n and text[j + 1].isdigit()
            )):
                j += 1
            toks.append(("num", text[i:j], line))
            i = j
        elif text.startswith("::", i) or text.startswith("=>", i):
            toks.append(("punct", text[i:i + 2], line))
            i += 2
        else:
            toks.append(("punct", c, line))
            i += 1
    return toks


# ---------------------------------------------------------------------------
# Test-item detection
# ---------------------------------------------------------------------------

_OPEN = {"(": ")", "[": "]", "{": "}"}
_CLOSE = {")", "]", "}"}
_TEST_ATTR_NAMES = {"test", "rstest", "test_case", "wasm_bindgen_test"}
_QUALIFIERS = {"default", "unsafe", "async", "safe"}
_SEMI_ITEMS = {"use", "static", "type", "let"}
_BLOCK_ITEMS = {"fn", "mod", "impl", "struct", "enum", "union", "trait"}
_BLOCK_EXPRS = {"if", "match", "for", "while", "loop"}


def _match(toks, i):
    """Index of the bracket closing the one at ``toks[i]`` (or last index)."""
    depth = 0
    for k in range(i, len(toks)):
        v = toks[k][1] if toks[k][0] == "punct" else None
        if v in _OPEN:
            depth += 1
        elif v in _CLOSE:
            depth -= 1
            if depth == 0:
                return k
    return len(toks) - 1


def _split_args(toks):
    """Split a token list on top-level commas."""
    parts, cur, depth = [], [], 0
    for t in toks:
        v = t[1] if t[0] == "punct" else None
        if v in _OPEN:
            depth += 1
        elif v in _CLOSE:
            depth -= 1
        if v == "," and depth == 0:
            parts.append(cur)
            cur = []
        else:
            cur.append(t)
    if cur:
        parts.append(cur)
    return parts


def _pred_requires_test(toks) -> bool:
    """True when a cfg predicate can only hold in a test build."""
    if not toks or toks[0][0] != "id":
        return False
    name = toks[0][1]
    if len(toks) == 1:
        return name == "test"
    if len(toks) < 3 or toks[1][1] != "(":
        return False  # key = "value" and anything else
    inner = toks[2:_match(toks, 1)]
    args = [a for a in _split_args(inner) if a]
    if name == "all":
        return any(_pred_requires_test(a) for a in args)
    if name == "any":
        return bool(args) and all(_pred_requires_test(a) for a in args)
    return False  # not(...) and unknown predicates


def attr_marks_test(attr) -> bool:
    """``attr`` is the token list between ``#[`` and ``]``."""
    path, k = [], 0
    while k < len(attr) and (attr[k][0] == "id" or attr[k][1] == "::"):
        if attr[k][0] == "id":
            path.append(attr[k][1])
        k += 1
    if not path:
        return False
    if path == ["cfg"]:
        if k < len(attr) and attr[k][1] == "(":
            return _pred_requires_test(attr[k + 1:_match(attr, k)])
        return False
    return path[-1] in _TEST_ATTR_NAMES


def _parse_attr_group(toks, i):
    """Parse consecutive outer attributes from ``toks[i]`` (a ``#``).

    Return (index after the group, is_test).
    """
    is_test = False
    n = len(toks)
    while i + 1 < n and toks[i][1] == "#" and toks[i + 1][1] == "[":
        close = _match(toks, i + 1)
        is_test = is_test or attr_marks_test(toks[i + 2:close])
        i = close + 1
    return i, is_test


def _skip_visibility_and_qualifiers(toks, j):
    n = len(toks)
    if j < n and toks[j][1] == "pub":
        j += 1
        if j < n and toks[j][1] == "(":
            j = _match(toks, j) + 1
    while j < n:
        v = toks[j][1]
        nxt = toks[j + 1][1] if j + 1 < n else ""
        if v in _QUALIFIERS:
            j += 1
        elif v == "const" and nxt in ("fn", "unsafe", "async", "extern"):
            j += 1
        elif v == "extern" and nxt not in ("crate",):
            j += 1
            if j < n and toks[j][0] == "str":
                j += 1
        else:
            break
    return j


def _end_semi(toks, j):
    depth = 0
    for k in range(j, len(toks)):
        v = toks[k][1] if toks[k][0] == "punct" else None
        if v in _OPEN:
            depth += 1
        elif v in _CLOSE:
            depth -= 1
            if depth < 0:
                return max(k - 1, j)
        elif v == ";" and depth == 0:
            return k
    return len(toks) - 1


def _end_item(toks, j):
    """Item ending at ';' (before any block) or at the close of its block."""
    depth = 0
    for k in range(j, len(toks)):
        v = toks[k][1] if toks[k][0] == "punct" else None
        if v == "{" and depth == 0:
            return _match(toks, k)
        if v in _OPEN:
            depth += 1
        elif v in _CLOSE:
            depth -= 1
            if depth < 0:
                return max(k - 1, j)
        elif v == ";" and depth == 0:
            return k
    return len(toks) - 1


def _end_expr(toks, j):
    """Field, variant, match arm or statement: ends at ',' / ';' at depth 0."""
    depth = 0
    for k in range(j, len(toks)):
        v = toks[k][1] if toks[k][0] == "punct" else None
        if v == "=>" and depth == 0 and k + 1 < len(toks) and toks[k + 1][1] == "{":
            end = _match(toks, k + 1)
            if end + 1 < len(toks) and toks[end + 1][1] == ",":
                end += 1
            return end
        if v in _OPEN:
            depth += 1
        elif v in _CLOSE:
            depth -= 1
            if depth < 0:
                return max(k - 1, j)
        elif v in (",", ";") and depth == 0:
            return k
    return len(toks) - 1


def _is_macro_call(toks, j):
    """``path::to::name!`` starting at ``toks[j]``."""
    n = len(toks)
    k = j
    while k < n and (toks[k][0] == "id" or toks[k][1] == "::"):
        k += 1
    return k > j and k < n and toks[k][1] == "!"


def _item_end(toks, j):
    """Index of the last token of the item starting at ``toks[j]``."""
    n = len(toks)
    if j >= n:
        return n - 1
    j = _skip_visibility_and_qualifiers(toks, j)
    if j >= n:
        return n - 1
    kind, v = toks[j][0], toks[j][1]
    nxt = toks[j + 1][1] if j + 1 < n else ""
    if v in _SEMI_ITEMS or (v == "const" and nxt != "fn") or (v == "extern" and nxt == "crate"):
        return _end_semi(toks, j)
    if v in _BLOCK_ITEMS or v == "macro_rules" or _is_macro_call(toks, j):
        return _end_item(toks, j)
    if v == "{" or v in _BLOCK_EXPRS:
        return _end_item(toks, j)
    return _end_expr(toks, j)


_DOC_OR_ATTR_LINE = re.compile(r"^\s*(///|#\[)")


def _extend_back(lines, start):
    """Include contiguous doc comments directly above an attribute group."""
    k = start - 1
    while k >= 1 and _DOC_OR_ATTR_LINE.match(lines[k - 1]):
        k -= 1
    return k + 1


def rust_test_regions(text: str):
    """Return sorted, merged (first_line, last_line) ranges of test items."""
    toks = lex_rust(text)
    lines = text.split("\n")
    ranges = []
    i, n = 0, len(toks)
    while i < n:
        t = toks[i]
        if t[1] == "#" and t[0] == "punct" and i + 1 < n and toks[i + 1][1] == "[":
            start_line = t[2]
            after, is_test = _parse_attr_group(toks, i)
            if is_test:
                end = _item_end(toks, after)
                ranges.append((_extend_back(lines, start_line), toks[end][2]))
            i = after
        else:
            i += 1
    ranges.sort()
    merged = []
    for a, b in ranges:
        if merged and a <= merged[-1][1] + 1:
            merged[-1] = (merged[-1][0], max(merged[-1][1], b))
        else:
            merged.append((a, b))
    return merged


def rust_test_lines(text: str) -> set:
    """1-based line numbers inside ``#[cfg(test)]``/``#[test]`` items."""
    out = set()
    for a, b in rust_test_regions(text):
        out.update(range(a, b + 1))
    return out


# ---------------------------------------------------------------------------
# Diff classification
# ---------------------------------------------------------------------------

_HUNK_RE = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")


def parse_diff_lines(diff_text: str):
    """Return (deleted_old_lines, added_new_lines) from a unified diff.

    Works for ``-U0`` and for diffs with context: it walks every hunk body
    using the header's line counts, so content lines that look like headers
    ("--- x", "@@") are never misread. Note: git's numstat is computed from
    the default-context diff, and ``-U0`` can align a few lines differently
    (fewer +/- lines), so the extraction diffs with default context.
    """
    deleted, added = [], []
    lines = diff_text.split("\n")
    i, n = 0, len(lines)
    while i < n:
        m = _HUNK_RE.match(lines[i])
        i += 1
        if not m:
            continue
        o, rem_o = int(m.group(1)), int(m.group(2) or 1)
        nw, rem_n = int(m.group(3)), int(m.group(4) or 1)
        while i < n and (rem_o > 0 or rem_n > 0):
            tag = lines[i][:1]
            if tag == "-":
                deleted.append(o)
                o, rem_o = o + 1, rem_o - 1
            elif tag == "+":
                added.append(nw)
                nw, rem_n = nw + 1, rem_n - 1
            elif tag == " " or lines[i] == "":
                o, nw, rem_o, rem_n = o + 1, nw + 1, rem_o - 1, rem_n - 1
            i += 1  # "\ No newline at end of file" falls through
    return deleted, added
