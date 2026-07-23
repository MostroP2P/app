#!/usr/bin/env bash
# Regenerate flutter_rust_bridge bindings, refusing to run when the local codegen CLI
# does not match the version this repository pins.
#
# A mismatched CLI writes lib/src/rust/frb_generated.dart against a different API surface
# than the resolved Dart package. Because that directory is gitignored, the result is a
# build failure that names a Dart parameter and never mentions versions. See issue #205.
#
# Usage:
#   ./scripts/frb-generate.sh          verify, then generate
#   ./scripts/frb-generate.sh --check  verify only, generate nothing
#
# Any other arguments are forwarded to `flutter_rust_bridge_codegen generate`.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# pubspec.yaml is the single source of truth; every other declaration must agree with it.
PUBSPEC='pubspec.yaml'
CARGO_TOML='rust/Cargo.toml'
CI_WORKFLOW='.github/workflows/ci.yml'
GOLDENS_WORKFLOW='.github/workflows/update-goldens.yml'

SEMVER='[0-9]+\.[0-9]+\.[0-9]+'

check_only=false
if [[ "${1-}" == '--check' ]]; then
  check_only=true
  shift
fi

# Print the first capture group of `pattern` in `file`, or nothing if it does not match.
extract_version() {
  local file="$1" pattern="$2"
  [[ -f "$file" ]] || return 0
  sed -nE "s|${pattern}|\1|p" "$file" | head -n 1
}

pinned="$(extract_version "$PUBSPEC" "^[[:space:]]*flutter_rust_bridge:[[:space:]]*\"?(${SEMVER})\"?.*$")"
if [[ -z "$pinned" ]]; then
  echo "✗ Could not read the flutter_rust_bridge version from ${PUBSPEC}." >&2
  echo "  Expected a line like: flutter_rust_bridge: 2.11.1" >&2
  exit 1
fi

# Every other location that restates the pin, and how to read it out of that file.
mismatches=()
check_pin() {
  local file="$1" pattern="$2" found
  found="$(extract_version "$file" "$pattern")"
  if [[ -z "$found" ]]; then
    mismatches+=("${file}: no version found (expected ${pinned})")
  elif [[ "$found" != "$pinned" ]]; then
    mismatches+=("${file}: ${found} (expected ${pinned})")
  fi
}

check_pin "$CARGO_TOML" "^[[:space:]]*flutter_rust_bridge[[:space:]]*=[[:space:]]*\"=?(${SEMVER})\".*$"
check_pin "$CI_WORKFLOW" "^[[:space:]]*FRB_VERSION:[[:space:]]*\"?(${SEMVER})\"?.*$"
check_pin "$GOLDENS_WORKFLOW" "^[[:space:]]*FRB_VERSION:[[:space:]]*\"?(${SEMVER})\"?.*$"

if (( ${#mismatches[@]} > 0 )); then
  echo "✗ flutter_rust_bridge is pinned inconsistently across the repository." >&2
  echo "  ${PUBSPEC} pins ${pinned}, but:" >&2
  printf '    %s\n' "${mismatches[@]}" >&2
  echo >&2
  echo "  A version bump has to move every one of these together." >&2
  exit 1
fi

if ! command -v flutter_rust_bridge_codegen >/dev/null 2>&1; then
  echo "✗ flutter_rust_bridge_codegen is not installed." >&2
  echo >&2
  echo "  Install the pinned version:" >&2
  echo "    cargo install flutter_rust_bridge_codegen --version ${pinned} --locked" >&2
  exit 1
fi

installed="$(flutter_rust_bridge_codegen --version | grep -oE "${SEMVER}" | head -n 1)"
if [[ "$installed" != "$pinned" ]]; then
  echo "✗ flutter_rust_bridge_codegen version mismatch." >&2
  echo "    pinned (${PUBSPEC}): ${pinned}" >&2
  echo "    installed:             ${installed:-unknown}" >&2
  echo >&2
  echo "  Generating with a mismatched CLI produces bindings that fail to compile against" >&2
  echo "  the flutter_rust_bridge Dart package, with an error that never mentions versions." >&2
  echo >&2
  echo "  Fix:" >&2
  echo "    cargo install flutter_rust_bridge_codegen --version ${pinned} --locked" >&2
  exit 1
fi

echo "✓ flutter_rust_bridge ${pinned} — pins agree, CLI matches."

if [[ "$check_only" == true ]]; then
  exit 0
fi

exec flutter_rust_bridge_codegen generate "$@"
