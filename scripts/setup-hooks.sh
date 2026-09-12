#!/usr/bin/env bash
# Point this clone's git hooks at .githooks/.
#
# The hooks themselves live in .githooks/ and are useless until core.hooksPath names
# that directory — a clone that never runs this keeps regenerating nothing after a pull
# and hits the stale-bindings build failure described in .githooks/regen-if-needed.sh.
#
# Idempotent: safe to run on every clone, every time.
#
# Usage:
#   ./scripts/setup-hooks.sh          install (no-op when already installed)
#   ./scripts/setup-hooks.sh --check  report status only, change nothing
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

WANT='.githooks'

check_only=false
if [[ "${1-}" == '--check' ]]; then
  check_only=true
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "✗ Not inside a git work tree — nothing to configure." >&2
  exit 1
fi

current="$(git config --local --get core.hooksPath || true)"

if [[ "$current" == "$WANT" ]]; then
  echo "✓ git hooks already installed (core.hooksPath=${WANT})."
  exit 0
fi

# Someone deliberately pointed this clone elsewhere; say so rather than overwrite it.
if [[ -n "$current" ]]; then
  echo "! core.hooksPath is set to '${current}', not '${WANT}'." >&2
  echo "  Leaving it alone. Run: git config core.hooksPath ${WANT}" >&2
  exit 1
fi

if $check_only; then
  echo "! git hooks are NOT installed. Run: ./scripts/setup-hooks.sh" >&2
  exit 1
fi

git config core.hooksPath "$WANT"
echo "✓ git hooks installed (core.hooksPath=${WANT})."
echo "  Generated code now regenerates automatically after pull/checkout/rebase."
