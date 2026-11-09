## Linked issue

Closes #

## Type

<!-- One of: fix, feat, refactor, docs, test, chore, perf, ci -->

## What changes and why

<!-- Two to five sentences. What behaviour changes, and for whom. -->

## Affected flow

<!-- Which screens or routes, which user actions (take an order, pay the
hold invoice, release, open a dispute, restore...) and which order or
dispute statuses does this touch? Name the layer and the files where that
behaviour lives: Rust core (`rust/src/...`), bridge (`rust/src/api/`),
Dart providers or widgets (`lib/features/...`). -->

## Blast radius

<!-- What else reads or writes the state you changed, and why is it not
broken? Consider: persisted data (SQLite/IndexedDB in Rust, Sembast in
Dart) and existing installs upgrading; the generated bindings; the other
platforms (Android, iOS, web/wasm, desktop); background work and push
notifications; localization keys; automation identifiers
(docs/automation-contract.md); what the daemon and the v1 app see on the
wire. -->

## Platforms tested

<!-- Which platforms you ran the Manual testing on (device or emulator,
OS version). A change in platform code (`android/`, `ios/`, `web/`,
`lib/**/…_web.dart`) must be tested on that platform. -->

## Manual testing

<!-- Required. See CONTRIBUTING.md § Manual testing: numbered steps a
reviewer can follow in the app to see this change work, each with its
expected result (with no app flow: on the command or workflow it changes).
For a fix, one step must fail on `main`. -->

### Setup

### Steps

1.

### Not covered

## Screenshots

<!-- Required for any visible change: before (main) and after (this
branch), same screen, same data. Light and dark theme when colour,
contrast or layout change; one at 2x text scale when layout changes.
A screen recording for a change in a flow. Write "No visible change"
otherwise. For a visible change, also list the design-guide rules it
touches (.specify/DESIGN_SYSTEM.md §12). -->

## Automated tests

<!-- The tests you added and what each proves. For a fix: the test that
fails on `main`, or why no test can (CONTRIBUTING.md § Red test). -->

## Checklist

- [ ] `cd rust && cargo fmt --check && cargo clippy -- -D warnings && cargo test` pass locally
- [ ] `dart format --set-exit-if-changed .`, `flutter analyze` and `flutter test` pass locally (`flutter test` summary line pasted under Automated tests)
- [ ] Changed `rust/src/api/` or an `.arb`: regenerated code committed in the same commit (CONTRIBUTING.md § Generated code)
- [ ] New or changed user-facing text: every locale updated, no hardcoded strings
- [ ] Changed an automation identifier: coordinated in the linked issue (docs/automation-contract.md)
- [ ] Protocol or transport change: impact on the daemon and other clients stated (CONTRIBUTING.md § Protocol / Transport Changes)
- [ ] Behaviour or contract change: matching spec under `specs/` or `.specify/` updated
- [ ] At most 1,500 changed lines, not counting tests, generated files and docs (CONTRIBUTING.md § Pull request size), or the description says why it cannot be split
- [ ] Commits are signed
- [ ] I ran the Manual testing steps myself and can explain every line of this diff

## AI assistance

<!-- Did you use AI tools, and for which parts? This is not a reason to
close; it tells the reviewer where to look harder. -->
