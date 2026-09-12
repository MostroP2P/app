#!/usr/bin/env bash
# Install this clone's git hooks by copying them into the repository's own
# hooks directory.
#
# Why a copy, and not core.hooksPath=.githooks
# --------------------------------------------
# core.hooksPath pointing at a tracked directory makes git run hook code from
# whatever ref is currently checked out. `gh pr checkout 999` on an outside
# contributor's branch would then execute *their* post-checkout script
# immediately, with no build and no run in between — and reviewing a PR by
# checking it out is about as routine as it gets.
#
# .git/hooks is not tracked, so no ref can write it. Checking out a hostile
# branch stays inert; the hooks change only when someone deliberately runs this
# installer, which is already running a script from the tree.
#
# Idempotent: safe to run on every clone, every time. Re-running refreshes the
# copies, which is how a hook edit in .githooks/ reaches a clone.
#
# Usage:
#   ./scripts/setup-hooks.sh          install or refresh
#   ./scripts/setup-hooks.sh --check  report status only, change nothing
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

SOURCE_DIR='.githooks'

# Entry points git calls, plus the shared body two of them exec by path — it has
# to sit next to them or `dirname "$0"` misses it.
FILES=(pre-commit post-merge post-checkout post-rewrite regen-if-needed.sh)

# Present in every tracked hook. Its absence in an installed file means the file
# is somebody else's, and gets left alone.
MARKER='installed by scripts/setup-hooks.sh'

check_only=false
if [[ "${1-}" == '--check' ]]; then
  check_only=true
elif [[ $# -gt 0 ]]; then
  echo "✗ Unknown argument: $1 (expected --check or nothing)" >&2
  exit 2
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "✗ Not inside a git work tree — nothing to configure." >&2
  exit 1
fi

# --git-common-dir, not --git-path hooks: the latter returns core.hooksPath when
# that is set, which is precisely the value being migrated away from below, and
# the copies would land back in the tracked directory. The common dir is also
# the right answer inside a linked worktree, where hooks are shared.
common_dir="$(git rev-parse --git-common-dir)"
case "$common_dir" in
  /*) ;;
  *) common_dir="$repo_root/$common_dir" ;;
esac
hooks_dir="$common_dir/hooks"

# ── core.hooksPath has to be out of the way, at any scope ────────────────────
# It overrides .git/hooks entirely, so a leftover value means the copies below
# would never run. Read the effective value: a global or worktree-scoped one
# shadows .git/hooks just as a local one does.
configured="$(git config --get core.hooksPath || true)"

if [[ "$configured" == "$SOURCE_DIR" ]]; then
  if $check_only; then
    echo "! core.hooksPath=${SOURCE_DIR}: hooks run from the checked-out ref." >&2
    echo "  Run ./scripts/setup-hooks.sh to move to copies under .git/hooks." >&2
    exit 1
  fi
  echo "▶ core.hooksPath=${SOURCE_DIR} found — this runs hook code from whatever"
  echo "  ref is checked out. Replacing it with copies git cannot rewrite."
  git config --local --unset-all core.hooksPath 2>/dev/null || true
  configured="$(git config --get core.hooksPath || true)"
  if [[ "$configured" == "$SOURCE_DIR" ]]; then
    echo "✗ core.hooksPath is still '${SOURCE_DIR}' from a wider scope." >&2
    echo "  Clear it yourself, e.g. git config --global --unset core.hooksPath" >&2
    exit 1
  fi
fi

# Someone deliberately pointed this clone somewhere of their own; say so rather
# than fight them for it.
if [[ -n "$configured" ]]; then
  echo "! core.hooksPath is set to '${configured}', so ${hooks_dir} is ignored." >&2
  echo "  Leaving it alone. Unset it to use the hooks this repo ships." >&2
  exit 1
fi

# ── compare, then copy ───────────────────────────────────────────────────────
stale=()
foreign=()

for name in "${FILES[@]}"; do
  src="$SOURCE_DIR/$name"
  dst="$hooks_dir/$name"

  if [[ ! -f "$src" ]]; then
    echo "✗ Missing $src — the repo is not in a state this can install from." >&2
    exit 1
  fi

  if [[ -e "$dst" ]] && ! grep -qF "$MARKER" "$dst" 2>/dev/null; then
    foreign+=("$name")
    continue
  fi

  if ! cmp -s "$src" "$dst" 2>/dev/null; then
    stale+=("$name")
  fi
done

if [[ ${#foreign[@]} -gt 0 ]]; then
  echo "! ${hooks_dir} already holds hooks this repo did not install:" >&2
  printf '    %s\n' "${foreign[@]}" >&2
  echo "  Leaving them alone. Move them aside and re-run to install ours." >&2
  exit 1
fi

if [[ ${#stale[@]} -eq 0 ]]; then
  echo "✓ git hooks installed and up to date (${hooks_dir})."
  exit 0
fi

if $check_only; then
  echo "! git hooks are out of date or missing: ${stale[*]}" >&2
  echo "  Run: ./scripts/setup-hooks.sh" >&2
  exit 1
fi

mkdir -p "$hooks_dir"
for name in "${stale[@]}"; do
  cp "$SOURCE_DIR/$name" "$hooks_dir/$name"
  chmod +x "$hooks_dir/$name"
done

echo "✓ git hooks installed (${#stale[@]} file(s) copied to ${hooks_dir})."
echo "  Generated code now regenerates automatically after pull/checkout/rebase."
echo "  They are copies: edit ${SOURCE_DIR}/ and re-run this to refresh them."
