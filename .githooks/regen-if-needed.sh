#!/usr/bin/env bash
# Shared body for the post-merge and post-checkout hooks.
#
# lib/src/rust/ and lib/l10n/app_localizations*.dart are gitignored, so a pull that
# brings in someone else's rust/src/api/ field or .arb key leaves the local copies
# stale. The failure is loud but misdirected: the analyzer blames whatever *uses* the
# missing field. Regenerate here, right after the tree moved, and only when the
# inputs actually changed so an ordinary pull stays fast.
#
# Usage: regen-if-needed.sh <old-head> <new-head>
set -euo pipefail

old="${1-}"
new="${2-}"

# Nothing to compare (fresh clone, orphan checkout) → nothing to do.
if [[ -z "$old" || -z "$new" || "$old" == "$new" ]]; then
  exit 0
fi
git rev-parse --verify --quiet "$old" >/dev/null || exit 0

changed="$(git diff --name-only "$old" "$new" -- rust/src/api lib/l10n pubspec.yaml)"
[[ -n "$changed" ]] || exit 0

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

if grep -qE '^(rust/src/api/|pubspec\.yaml$)' <<<"$changed"; then
  echo "▶ rust/src/api changed — regenerating flutter_rust_bridge bindings..."
  ./scripts/frb-generate.sh
fi

if grep -qE '^lib/l10n/.*\.arb$' <<<"$changed"; then
  echo "▶ lib/l10n/*.arb changed — regenerating AppLocalizations..."
  flutter gen-l10n
fi
