#!/usr/bin/env bash
# Refuse a commit whose generated code is out of date — the local twin of
# CI's "Check generated code is committed" step (.github/workflows/ci.yml).
#
# The generated Dart lists every item of `crate::api`, public or not, in its
# header comments, so even a private helper added to rust/src/api/ changes
# lib/src/rust/ and fails CI before analyze and test run (#544, #546).
# `./scripts/frb-generate.sh --check` does not catch that: it only compares
# the codegen version pins.
#
# Two ways to run it:
#   ./scripts/check-generated.sh           check the working tree, by hand
#   (JSON on stdin)                        as a Claude Code PreToolUse hook on
#                                          Bash; acts only on `git commit`
#
# What it does: when rust/src/api/ or an .arb file differs from HEAD, it
# regenerates (frb-generate.sh, flutter gen-l10n) and fails if that changed
# lib/src/rust, rust/src/frb_generated.rs or lib/l10n. The files are left
# regenerated, so the fix is to stage them and commit again. It compares the
# working tree before and after, not the index: `git add … && git commit`
# is one command, and the add has not run yet when the hook fires.
#
# Exit codes: 0 up to date or nothing to check, 2 out of date or regeneration
# failed (a PreToolUse hook blocks on 2 and shows stderr). Put
# SKIP_GENERATED_CHECK=1 in the command, or the environment, to skip.

set -uo pipefail

GENERATED=(lib/src/rust rust/src/frb_generated.rs lib/l10n)

fail() {
  printf '%s\n' "$@" >&2
  exit 2
}

# ── Hook mode: decide whether this command is a commit, and where ───────────
command_text=''
start_dir="$PWD"
if [[ ! -t 0 ]]; then
  payload="$(cat)"
  if [[ -n "$payload" ]]; then
    command_text="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)"
    hook_cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)"
    [[ -n "$hook_cwd" && -d "$hook_cwd" ]] && start_dir="$hook_cwd"
    # Not a commit: nothing to do. Covers `git commit`, `git -C dir commit`,
    # and a commit after `&&`, `;` or `|`.
    if ! grep -Eq '(^|[;&|[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+commit([[:space:]]|$)' <<<"$command_text"; then
      exit 0
    fi
    # A leading `cd <dir> &&` decides which repository is committed to.
    lead_cd="$(sed -nE 's/^[[:space:]]*cd[[:space:]]+([^;&|[:space:]]+).*/\1/p' <<<"$command_text")"
    if [[ -n "$lead_cd" ]]; then
      lead_cd="${lead_cd/#\~/$HOME}"
      [[ "$lead_cd" != /* ]] && lead_cd="$start_dir/$lead_cd"
      [[ -d "$lead_cd" ]] && start_dir="$lead_cd"
    fi
  fi
fi

[[ "${SKIP_GENERATED_CHECK:-}" == 1 || "$command_text" == *SKIP_GENERATED_CHECK=1* ]] && exit 0

root="$(git -C "$start_dir" rev-parse --show-toplevel 2>/dev/null)" || exit 0
[[ -x "$root/scripts/frb-generate.sh" ]] || exit 0 # not this repository
cd "$root" || exit 0

# ── What would need regenerating ────────────────────────────────────────────
changed="$( { git diff --name-only HEAD; git ls-files --others --exclude-standard; } 2>/dev/null)"
needs_frb=false
needs_l10n=false
grep -q '^rust/src/api/' <<<"$changed" && needs_frb=true
grep -Eq '^lib/l10n/[^/]+\.arb$' <<<"$changed" && needs_l10n=true
[[ "$needs_frb" == false && "$needs_l10n" == false ]] && exit 0

snapshot() {
  { git diff HEAD -- "${GENERATED[@]}"; git ls-files --others --exclude-standard -- "${GENERATED[@]}"; } |
    sha256sum
}

before="$(snapshot)"
if [[ "$needs_frb" == true ]]; then
  if ! out="$(./scripts/frb-generate.sh 2>&1)"; then
    fail "check-generated: ./scripts/frb-generate.sh failed, so the generated" \
      "bindings could not be checked:" "" "$(tail -n 15 <<<"$out")" "" \
      "Fix the generator, or add SKIP_GENERATED_CHECK=1 to the command to skip."
  fi
fi
if [[ "$needs_l10n" == true ]]; then
  if ! out="$(flutter gen-l10n 2>&1)"; then
    fail "check-generated: flutter gen-l10n failed:" "" "$(tail -n 15 <<<"$out")"
  fi
fi
after="$(snapshot)"

if [[ "$before" != "$after" ]]; then
  fail "check-generated: the generated code was out of date — CI's" \
    "\"Check generated code is committed\" step would fail this commit." \
    "It has now been regenerated. Stage the result and commit again:" "" \
    "$(git status --short -- "${GENERATED[@]}")" "" \
    "  git add ${GENERATED[*]}"
fi

# Up to date on disk, but a commit that does not stage it still ships the
# old copy. Only when this command stages nothing itself.
if [[ -n "$command_text" && "$command_text" != *"git add"* ]] &&
  ! git diff --quiet -- "${GENERATED[@]}"; then
  fail "check-generated: the generated code is regenerated on disk but not" \
    "staged, so this commit would ship the old copy:" "" \
    "$(git diff --name-only -- "${GENERATED[@]}")" "" \
    "  git add ${GENERATED[*]}"
fi

exit 0
