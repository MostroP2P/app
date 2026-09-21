#!/usr/bin/env bash
# Set the app version everywhere it is declared, ahead of tagging a release.
#
# The release workflow refuses a tag whose version the tagged source does not already
# carry (docs/RELEASING.md): the About screen shows CARGO_PKG_VERSION from rust/Cargo.toml,
# and local builds read pubspec.yaml. Commit the result through a PR, then tag its merge.
#
# Usage:
#   ./scripts/bump-version.sh 2.0.1
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

version="${1:-}"
if ! [[ "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "usage: $0 MAJOR.MINOR.PATCH   (got '${version}')" >&2
  exit 64
fi
major=${BASH_REMATCH[1]} minor=${BASH_REMATCH[2]} patch=${BASH_REMATCH[3]}

# Same Android versionCode scheme as .github/workflows/release.yml.
if [ "$minor" -gt 99 ] || [ "$patch" -gt 99 ]; then
  echo "MINOR and PATCH must stay below 100 (versionCode scheme, docs/RELEASING.md)." >&2
  exit 64
fi
build_number=$((major * 10000 + minor * 100 + patch))

# perl, not `sed -i`: the in-place flag and the `0,/re/` address differ between GNU and BSD
# (macOS) sed, and maintainers release from both. Each substitution must match, or the
# file's shape changed and a version would stay stale while this script reports success.
perl -pi -e "\$n += s/^version: .*/version: ${version}+${build_number}/; END { exit(\$n ? 0 : 1) }" pubspec.yaml \
  || { echo "no 'version:' line in pubspec.yaml" >&2; exit 65; }
# Only the [package] version: the first `version =` line of the manifest.
perl -pi -e "\$done ||= s/^version = \".*\"/version = \"${version}\"/; END { exit(\$done ? 0 : 1) }" rust/Cargo.toml \
  || { echo "no [package] version in rust/Cargo.toml" >&2; exit 65; }
# The crate's own entry in the lockfile, so `cargo build --locked` (CI) still passes.
perl -0pi -e "\$n = s/(name = \"rust\"\nversion = \")[^\"]*/\${1}${version}/; END { exit(\$n ? 0 : 1) }" rust/Cargo.lock \
  || { echo "no rust crate entry in rust/Cargo.lock" >&2; exit 65; }

echo "Version set to ${version} (build ${build_number}):"
git --no-pager diff --stat -- pubspec.yaml rust/Cargo.toml rust/Cargo.lock
