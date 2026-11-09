# Contribution Quality Bar — Spec

**Status:** Phase 1 (policy in `CONTRIBUTING.md`, `AGENTS.md` and `CLAUDE.md`, pull
request template, close message), plus the pull request size check of §7.6.
Maintainers apply the rest by hand.
**Adapted from:** the daemon's
[Contribution Quality Bar](https://github.com/MostroP2P/mostro/blob/main/docs/CONTRIBUTION_QUALITY_SPEC.md).
The principle, the layers and the rollout are the same; what changes is
what "evidence" means for a hybrid Rust/Flutter client that runs on six
platforms.
**Initial mode:** label-only (shadow). Nothing is closed automatically
until Phase 4 is explicitly enabled.

## 1. Goal

The app receives pull requests that cost a reviewer more time than they
are worth: fixes for problems that do not exist, changes that fix one
screen and break another, changes tested on one platform that break
another, and descriptions that do not match the diff. Many are generated
with AI tools by authors who have not run the app.

This spec defines a **quality bar a pull request must clear before a
reviewer reads the diff**. The principle is the daemon's:

> A pull request proves by itself that the problem exists and that the
> change does not break anything. If it does not, it is closed without a
> technical review, whoever or whatever wrote it.

Every check below is about evidence the pull request carries (a linked
issue, a test that fails on `main`, a manual test with screenshots that
can be reproduced), never about how the pull request was produced.

### Non-goals

- **Detecting AI-generated code.** Detectors are unreliable, can be
  disputed, and would penalise good contributors who use AI tools. Using
  AI is allowed; the author answers for every line.
- **Closing pull requests with an LLM.** A model may help order the
  queue (§11), but it never closes, blocks or counts toward closing.
  CodeRabbit keeps reviewing as today; its comments are not part of the
  bar.
- **Replacing review.** A pull request that clears the bar still gets a
  full human review. The bar decides whether the review starts.
- **Replacing CI.** Whether a pull request builds, passes `cargo test`,
  `flutter analyze` and `flutter test`, commits its generated code,
  translates every key, and builds for web and iOS is `ci.yml`'s
  question. This spec does not repeat those checks.

## 2. Layers

Cheapest first. Each layer removes pull requests before the next, more
expensive one runs.

| # | Layer | What it catches | Cost | Section |
|---|---|---|---|---|
| 1 | Written policy | Gives a reason to close without debate | Docs only | §3 |
| 2 | Issue before pull request | Fixes for bugs that do not exist, features nobody agreed to | Docs and a label | §4 |
| 3 | Pull request template, with **Manual testing** and **Screenshots** | Authors who do not know which screen or flow they changed, or never ran the app | Docs only | §5, §6 |
| 4 | Triage bot and size check | Missing issue, template, test, screenshots or signatures; pull requests too large to review; silent automation-id changes | Two workflows, no build | §7 |
| 5 | Red test on `main` | Fixes whose test also passes without the fix | Two test runs per fix | §8 |
| 6 | Mortsom e2e gate | "Fixes one flow, breaks another" | Separate spec | §9 |

## 3. Policy

A new section in `CONTRIBUTING.md`, **Contribution quality bar**, states:

1. AI tools are allowed. The author is responsible for every line and
   must be able to explain any of it when a reviewer asks. "The tool
   wrote it" is not an answer.
2. A pull request that does not follow the template, does not link an
   accepted issue when one is required (§4), or fails the checks of §7
   and §8, **is closed without technical review**, with the standard
   message below. It can be reopened once it meets the bar.
3. A pull request whose description does not match its diff, whose
   Manual testing steps do not work when a reviewer follows them, or
   whose screenshots do not match what the branch shows, is closed the
   same way.
4. An account that repeatedly opens pull requests closed under this
   policy may be blocked from the organisation.

The standard close message lives in `.github/quality/close-message.md`,
so maintainers and the bot use the same text:

```markdown
Thanks for the contribution. This pull request is being closed without a
technical review because it does not meet the contribution quality bar
(CONTRIBUTING.md § Contribution quality bar):

<reasons>

You are welcome to reopen it, or open a new one, once it does.
```

### 3.1 Instructions for AI agents

`CONTRIBUTING.md` is the single source of the rules. Coding agents read
`AGENTS.md` (and `CLAUDE.md`, which agents of one vendor load instead), so
`AGENTS.md` gets a short section pointing to it, with the rules an agent
most often breaks stated inline:

```markdown
## Before opening a pull request

If you are an AI agent preparing a pull request, follow
`CONTRIBUTING.md § Contribution quality bar`. In short:

- Link an issue labelled `status: accepted` (`Closes #N`). If there is no
  accepted issue, do not open the pull request; comment on the issue instead.
- Fill in every section of `.github/pull_request_template.md`, including
  Manual testing: steps a person ran by hand in the app built from the
  branch, against a Mostro node, or, for a change with no app flow (CI,
  scripts, tooling, tests only), on the command or workflow it changes.
  Do not present steps nobody ran as results.
- Keep the pull request under 1,500 changed lines, not counting tests,
  generated files, documentation and translations
  (`CONTRIBUTING.md § Pull request size`).
  If the work is larger, split it into pull requests that each build and
  pass the tests on their own.
- Any visible change carries before and after screenshots; write
  `No visible change` only when that is true.
- For a fix, the commits are, in order: `refactor:` commits only if the test
  needs a seam (no behaviour change), then a `test:` commit that adds a
  regression test (Rust or Dart) that fails on `main`, then the fix. If no
  test can fail on `main` (a purely visual or platform-only bug), say why
  under Automated tests; a maintainer decides whether to waive it.
- If you could not build or run the app, say so in the pull request instead
  of claiming results.

A pull request that only changes Markdown files is exempt from the first
four points (see the exemptions in that section); commits are still signed.
```

`CLAUDE.md` gets one line pointing to that section, not a copy of it.
`AGENTS.md` points to `CONTRIBUTING.md`, never to this spec: the spec
describes how the checks work, which an agent does not need in order to
meet them.

This helps an agent that reads its instructions get the pull request
right the first time. Nothing depends on it: the template, the triage
bot and the red test check the result either way.

## 4. Issue before pull request

Every pull request that is not exempt links an issue that a maintainer
has accepted with the new label `status: accepted`. The bug or the
feature is discussed in the issue, where saying "this is not a bug" or
"this is not the design we want" costs one comment instead of a review
of the whole diff.

- **Linking** uses a closing keyword in the description (`Closes #123`,
  `Fixes #123`). The bot reads linked issues through the GraphQL field
  `closingIssuesReferences`, so a plain mention does not count.
- **Accepted** means the linked issue carries `status: accepted`. Only
  maintainers apply it, when they agree the problem is real and in
  scope. An issue its author opened minutes before the pull request is
  not accepted until a maintainer says so.
- **UI and design changes** need the accepted issue to show the intended
  result (a mockup, a screenshot of the v1 screen it matches, or a
  reference to `docs/design/`). A redesign nobody asked for is closed
  under §3.2 however well it is built.
- **Exempt** pull requests are listed in §7.3.

## 5. Pull request template

A new file, `.github/pull_request_template.md`. Every `##` heading is
required; the bot (§7) checks that each one is present and not empty or
left with only its placeholder comment. **Screenshots** may say
`No visible change` when that is true.

```markdown
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
branch), same screen, same data. Light and dark theme when colours
change. A screen recording for a change in a flow. Write
"No visible change" otherwise. -->

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
- [ ] Commits are signed
- [ ] I ran the Manual testing steps myself and can explain every line of this diff

## AI assistance

<!-- Did you use AI tools, and for which parts? This is not a reason to
close; it tells the reviewer where to look harder. -->
```

**Affected flow**, **Blast radius** and **Platforms tested** are cheap for
someone who understands the change and hard to fill in convincingly for
someone who does not. A generic or wrong answer is an objective close
reason under §3.

## 6. Manual testing

The **Manual testing** section is a step-by-step procedure that tests
**this specific pull request** end to end, in the app built from the
branch, against a running Mostro node. It serves three purposes:

1. **It lets a reviewer reproduce the change** without reverse-engineering
   the diff.
2. **It turns the description into checkable claims.** Each step has an
   expected result a reviewer can confirm or refute by following it, and
   vague steps are visible at a glance. The steps are evidence, not
   proof that the author ran them (§14). The author's statement that they
   ran it is the checklist item of §5, and a procedure that does not work
   is a close reason (§3.3).
3. **It is the source of a future per-PR Mortsom scenario** (§9.2).

### 6.1 Rules

- **A person runs the steps by hand** in the app. Mortsom (§9) is an
  internal tool of the Mostro developers; external contributors have no
  access to it and are never asked to use it.
- **Setup** says:
  - how the app was built: `flutter run` from the branch, which platform
    and device, debug or release, and `./scripts/build-web.sh` for web;
  - which Mostro node (its pubkey or "a local mostrod on regtest") and
    which relays, when they differ from the defaults;
  - how each actor pays and gets paid: which Lightning wallet, NWC or
    manual invoices;
  - which client each other actor uses: a second copy of this app, the v1
    app (`MostroP2P/mobile`) or mostro-cli;
  - any state the steps start from: a fresh install, an existing
    identity, an order in a given status, privacy mode on.
- **Steps** are numbered. Each step names **one actor** (maker, taker,
  buyer, seller, solver), **one action in the UI**, and an `Expected:`
  line with **the observable result**: the screen shown, a status or
  chip, a notification, a message in the chat, a button enabled or
  hidden, a payment received in the wallet, or, when the UI does not
  show it, the order status on the public event (kind 38383).
- **For a fix**, one step is marked **(fails on `main`)**. It is the
  step whose result differs between `main` and this pull request, and it
  says what `main` does instead. If no step fails on `main`, the pull
  request has not demonstrated a bug.
- **Restart and upgrade.** A change to anything persisted includes a
  step that kills and relaunches the app, and says whether it was tested
  as an upgrade of an install made by `main`.
- **Regression**: at least one step exercises a neighbouring flow named
  in **Blast radius** and shows it behaves as before. It is a step of its
  own, apart from the steps that show the change, so every procedure has
  at least two steps.
- **Not covered** lists what the steps do not test and why (for example,
  "iOS: no Mac available", "the counterparty on v1").
- A step that cannot be observed ("the provider is now more robust") is
  not a step.

A change that does not touch a trade (settings, account, a static
screen) only needs the steps that reach the changed screen; it does not
need a node and two wallets. The rules above still apply: it has a
**Regression** step and, for a fix, a step marked **(fails on `main`)**.

A change with no app flow (a CI workflow, a build or release script,
tooling, or tests only) has no screen to reach. Its steps run what the
change touches: the command, the script, or the workflow on the branch,
and each `Expected:` line names what that run shows (its output, the
workflow run and its conclusion, the file it produces). **Setup** says
where it ran, and a step names who runs it instead of a trade actor.
The same rules apply, including **Regression** and **(fails on `main`)**.
Without this, a `ci` pull request could not describe its testing
truthfully. The `manual-testing` check (§7.1) needs no special case for
it: it counts steps, `Expected:` lines and the `Regression` step, and
never looks at where they run.

### 6.2 Screenshots

- Any visible change carries **before** (`main`) and **after** (the
  branch) screenshots of the same screen with the same data.
- A change of colour, contrast or layout adds both themes, and a narrow
  width (a phone) when the layout reflows.
- A change of copy shows at least English and one other locale.
- A change inside a flow (several screens, an animation, a timing) is a
  short screen recording instead.
- For a fix, the screenshot of the step marked **(fails on `main`)** is
  the most useful one: it shows the bug.

Golden tests (`docs/golden-tests.md`) do not replace screenshots: they
prove a widget did not change unintentionally, not that the new look is
the intended one.

### 6.3 Example

How [#624](https://github.com/MostroP2P/app/pull/624) (privacy mode is
lost on restart) would have described its manual test:

```markdown
### Setup

App built from the branch of #624 with `flutter run -d linux` (debug),
and on an Android 15 emulator. Default node and relays. Existing
identity, in Reputation Mode.

### Steps

1. Open Account and select Full Privacy Mode.
   Expected: Full Privacy Mode is selected.
2. Quit the app completely and launch it again; open Account.
   **(fails on `main`)**
   Expected: Full Privacy Mode is still selected.
   On `main`: Reputation Mode is selected again, and the next trade is
   signed with the identity key.
3. Regression: select Reputation Mode, quit and relaunch; open Account.
   Expected: Reputation Mode is selected, as on `main`.

### Not covered

That the next trade after the relaunch goes out without the identity
key is shown by `test/core/services/identity_privacy_mode_test.dart`,
not by these steps: the app does not show which key signed a message.
Web and iOS not run; the change has no platform code.
```

## 7. Triage bot — `quality-triage.yml`

A workflow on `pull_request_target` (types `opened`, `edited`,
`reopened`, `synchronize`, `ready_for_review`). It **never checks out or
runs pull request code**. It reads metadata through the API, and its
workflow and script come from `main`. That is what makes
`pull_request_target`, which has a write token, safe here (§10).

Its checks live in `.github/quality/triage.py` (pure functions over API
data), the API calls and the labelling in `.github/quality/run_triage.py`,
unit tests in `.github/quality/tests/` (run by `quality-scripts.yml`), and
its thresholds in `.github/quality/config.toml`. A draft pull request is
not triaged; `ready_for_review` triggers the first run.

The daemon's bot is the starting point: the scripts are copied from
`MostroP2P/mostro` and adapted, not rewritten. If both keep evolving, a
shared action is extracted later (§15).

### 7.1 Checks

| Check | Passes when | Reason on failure |
|---|---|---|
| `issue` | A closing keyword links an issue labelled `status: accepted` | "No accepted issue is linked" |
| `template` | Every heading of §5 is present, and none is empty or only its placeholder | "Section `<name>` is missing or empty" |
| `manual-testing` | **Steps** has at least 2 numbered steps, each with an `Expected:` line; one of them begins with `Regression`; for type `fix`, another is marked `(fails on main)` | "Manual testing: `<what is missing>`" |
| `screenshots` | The diff touches `lib/` outside `lib/src/rust/` and `lib/l10n/app_localizations*.dart`, and **Screenshots** has an image or video, or says `No visible change` | "Screenshots: this changes the UI layer but shows no screenshot" |
| `fix-has-test` | For type `fix` (template field or `fix` title prefix), the diff adds a Rust test (`#[test]`, `#[tokio::test]`) or a Dart test (`test(`, `testWidgets(` in a `test/**/*_test.dart` file) | "A fix needs a regression test" |
| `automation-ids` | The diff does not remove or rename a constant in `lib/core/automation/automation_ids.dart`, or the pull request carries `automation:coordinated` | "Changes an automation identifier; coordinate it in the issue (docs/automation-contract.md)" |
| `signed` | Every commit is verified (`commit.verification.verified`) | "Commits `<shas>` are not signed" |
| `size` | For a first-time contributor, at most `max_first_pr_lines` (default 400) changed lines, excluding generated files (§7.4) | "First pull requests are limited to 400 changed lines; split it or discuss the scope in the issue" |
| `open-prs` | A first-time contributor has at most `max_open_prs_new` (default 1) other open pull requests | "Please wait until your open pull request is reviewed" |

A first-time contributor is one whose `author_association` is
`FIRST_TIME_CONTRIBUTOR`, `FIRST_TIMER` or `NONE`.

`screenshots` passes on `No visible change` because a bot cannot tell a
visual change from a refactor. A false `No visible change` is a
description that does not match its diff (§3.3).

### 7.2 Result

- All checks pass: label `quality:ok`.
- Any check fails: label `quality:needs-info`, and one comment lists
  every failing reason. The comment is **edited in place** on each run,
  never duplicated, and deleted once every check passes.
- The check run is reported as `neutral`, never `failure`, so it does
  not block a merge. Branch protection (`docs/BRANCH_PROTECTION.md`) is
  not part of this spec.

### 7.3 Exemptions

A pull request skips `issue`, `template`, `manual-testing`,
`screenshots` and `fix-has-test` when any of these holds:

- the author's association is `OWNER`, `MEMBER` or `COLLABORATOR`;
- the author is a bot (`dependabot[bot]`, `github-actions[bot]`,
  including the release workflow's changelog pull requests);
- every changed file is Markdown;
- a maintainer applied the label `quality:exempt`.

A maintainer's `quality:no-red-test` skips only `fix-has-test` and the
red test (§8), for a fix no Rust or Dart test can show failing on `main`:
a purely visual bug no widget test can observe, or one that only exists
on iOS, Android or web. The author says why under **Automated tests**,
and the step marked **(fails on `main`)**, with its screenshots, is the
evidence instead. Every other check still applies.

`signed`, `size`, `open-prs` and `automation-ids` still apply to
everyone except bots.

### 7.4 Generated files

The line count of `size` and the `screenshots` trigger ignore what no
author writes by hand: `lib/src/rust/**`, `rust/src/frb_generated.rs`,
`lib/l10n/app_localizations*.dart`, `lib/l10n/untranslated_messages.txt`,
`pubspec.lock`, `rust/Cargo.lock` and golden images
(`test/**/goldens/*.png`). The list lives in `config.toml`; it is a
superset of the `linguist-generated` entries of `.gitattributes`.

### 7.5 Closing (Phase 4 only)

A daily scheduled job, `quality-stale.yml`, closes pull requests that
have carried `quality:needs-info` for `needs_info_days` (default 7) days
without a new push or an edit to the description, with the standard
message of §3. Before Phase 4 it only applies `quality:would-close` and
comments that the pull request **would** have been closed.

### 7.6 Pull request size — `quality-size.yml`

Every pull request has at most `max_lines` (default 1,500) changed lines,
additions plus deletions, **not counting** tests, generated files,
documentation and translations. The point is a change a reviewer can read whole: the review
of a large diff is shallower, and the bugs of large changes surface later.
It applies to everyone but bots, in addition to the first-time
contributor limit of §7.1.

What does not count, all listed in `.github/quality/config.toml` `[size]`:

- **Tests:** `test/**`, `integration_test/**`, `test_driver/**`,
  `*_test.dart`, `rust/tests/**`, `.github/**/tests/**`, the out-of-line
  modules declared with `#[cfg(test)] mod name;` (listed in `config.toml`,
  kept complete by a unit test that scans `rust/src`), and, line by line, the `#[cfg(test)]`
  items and `#[test]` / `#[tokio::test]` functions inside `rust/src/**/*.rs`.
- **Generated files:** the list of §7.4.
- **Documentation:** `*.md`, `docs/**`, `specs/**`, `.specify/**`.
- **Translations:** `lib/l10n/*.arb`.

The check ships ahead of the triage bot as its own workflow and script
(`run_size_check.py`, pure logic in `size_check.py`, the Rust test-item
detector in `rust_tests.py`, unit tests in `.github/quality/tests/`), with
the same safety model: `pull_request_target`, scripts from `main`, no pull
request code checked out or run. It reads the changed files and their
patches from the API, and for a changed Rust source the file at the merge
base and at the head, to tell test lines apart. When GitHub omits the
patch of a very large file, the check diffs those two versions itself. When
a source cannot be read, every line of that file counts, and the comment
says so.

- Over the limit: label `quality:too-large` and one comment, edited in
  place, with the breakdown (counted, tests, generated, docs,
  translations, total).
- Within the limit, or exempt: the label and the comment are removed.
- The check run `Pull request size` is `neutral` over the limit and
  `success` otherwise, never `failure`: it does not block a merge.
- A maintainer applies `size:exempt` when the size cannot be avoided (a
  bindings regeneration, a migration, a large dependency bump) and the
  description says why.

When the triage bot of §7 lands, the size check can move into it as one
more check; its config section and labels stay the same.

## 8. Red test on `main` — `quality-red-test.yml`

The strongest filter against fixes for problems that do not exist: the
regression test of a fix must **fail without the fix and pass with it**.
A model that invents a bug can rarely write a test that fails on `main`.

The app has two test suites, and the job handles both: Rust tests next
to the code in `rust/src/**` (`#[cfg(test)]` modules; `rust/tests/`
counts too if integration tests are ever added there), and Dart tests
under `test/`.

### 8.1 Commit convention

The test is separated from its fix by commit, as in the daemon:

- In a fix pull request, the **first commit that is not a `refactor:`
  commit has a subject beginning with `test:`** and only adds the
  regression test; without a seam (next point), it is the first commit.
  The fix follows in one or more later commits.
- **Seams go first.** Dart tests often need a seam the code does not
  have yet (an injectable function, a `@visibleForTesting` entry point),
  and a test that calls a seam `main` lacks does not compile there. The
  seam goes in `refactor:` commits **before** the `test:` commit, and
  those commits must not change behaviour. The job runs the test on
  `main` plus those commits (§8.2), so the test still has to fail there.
- The `test:` commit is a meaningful commit in the sense of
  `CONTRIBUTING.md` ("Keep the git history clean"), not a fixup: it is
  not squashed into the fix before review. It stays separate until
  merge, and the maintainer may squash when merging.
- The test commit changes nothing outside `#[cfg(test)]` modules,
  `rust/tests/` and `test/` (§8.2 step 3), so no `.arb` file and no
  generated file: it has to run on the committed bindings of `main`. A
  test module inside `rust/src/api/` is fine: the generated bindings do
  not list test functions, so adding one there needs no regeneration.
- The commits do not need to be on the latest `main`: the job applies
  them to the current base itself.

### 8.2 Algorithm

On `pull_request` (read-only token, no secrets), for a pull request of
type `fix` without `quality:no-red-test` (§7.3):

1. Walk the pull request's commits from the first. Skip leading commits
   whose subject starts with `refactor:`; they are the **prefix**. The
   next commit must start with `test:`; otherwise the result is
   `no-test-commit`.
2. From the test commit's diff, list the tests it adds: in Rust, a `fn`
   preceded by `#[test]` or `#[tokio::test]`, possibly with other
   attributes in between; in Dart, a `test(` or `testWidgets(` call with a
   literal name in a `test/**/*_test.dart` file. If there are none,
   `no-test-commit`. Golden tests (`matchesGoldenFile`) are not
   counted (§14).
3. Check that every hunk of the test commit lies inside a `#[cfg(test)]`
   module, under `rust/tests/`, or under `test/`. Otherwise the result is
   `test-commit-changes-code`.
4. Check out the **current base** (`pull_request.base.sha`) and
   cherry-pick the prefix and the test commit onto it. If a cherry-pick
   conflicts, the result is `test-commit-does-not-apply` (the author
   rebases).
5. On that tree, run only the new tests: `cargo test` in `rust/` filtered
   to the Rust names, and `flutter test --reporter json` on the Dart files
   that contain the new tests, reading the result of each new test from
   the JSON by its full name (group prefix included). If they **do not
   compile**, the result is `test-does-not-compile-on-base`; if every new
   test **passes**, `bug-not-reproduced`. If any fails, continue.
6. On the pull request's merge commit (the `pull_request` default
   checkout), run the same tests. If they pass, the result is
   `bug-reproduced`; otherwise `test-fails-on-head`.

Rust tests that need the Flutter side do not exist (Rust is a library
tested on its own), so a pull request whose tests are only in Rust skips
the Flutter setup and runs in a few minutes on the cargo cache of
`ci.yml`. Dart tests need the Flutter toolchain but no codegen: the
bindings are committed, and step 3 forbids changing them.

After the tests, a workflow step (not the tests) writes `red-test.json`
from the exit codes and reports it recorded: `pr`, `head_sha`,
`base_sha`, `prefix_shas`, the result, the test names and the tail of
each run's output. The job uploads it as an artifact. It has a 45-minute
timeout.

Writing the file from a workflow step keeps honest pull requests honest,
but it is not a guarantee: the tests run pull request code in the same
job. As in the daemon, a forged result is not worth much: the author
already controls the test, and the only result that counts toward
closing is `bug-not-reproduced`, which only hurts the forger.

### 8.3 Verdict — `quality-verdict.yml`

A `workflow_run` workflow that never executes pull request code, treats
the artifact as untrusted data, and verifies that the pull request
belongs to the triggering run before touching it. The artifact must
match an exact schema: missing or unknown fields, a SHA that is not 40
hex characters, a `head_sha` that is not the pull request's current head,
or a result outside the table below reject it, and nothing is labelled.

| Result | Label | Meaning for the reviewer |
|---|---|---|
| `bug-reproduced` | `quality:bug-reproduced` | The test demonstrates both the bug and the fix |
| `bug-not-reproduced` | `quality:bug-not-reproduced` | The test passes without the fix. **Primary close reason** |
| `test-fails-on-head` | `quality:test-fails` | The fix does not make its own test pass |
| `no-test-commit` | `quality:needs-info`, reason added to the triage comment | The §8.1 convention is not followed |
| `test-commit-changes-code` | `quality:needs-info`, reason added to the triage comment | Same |
| `test-commit-does-not-apply` | `quality:needs-info`, reason added to the triage comment | The commits conflict with the current `main`; rebase |
| `test-does-not-compile-on-base` | `quality:red-test-inconclusive` | Usually a missing seam; move it to a `refactor:` commit (§8.1), or a reviewer decides |

When the prefix is not empty, the verdict comment lists its commits: a
`refactor:` commit that smuggles in the fix makes the test pass on the
"base", so it cannot produce `bug-reproduced` by itself, but the
reviewer still checks that it does not change behaviour.

`bug-not-reproduced` is only a label until Phase 4. Even then it never
closes a pull request by itself: it adds a failing reason to the triage
comment, and the 7-day timer of §7.5 applies, so an author whose test
was simply wrong has time to correct it.

### 8.4 What it does not prove

A test that fails on `main` for an unrelated reason passes this layer.
It filters out invented bugs; it does not prove the fix is right, nor
that it works on a platform the test does not run on. The reviewer still
reads the test, and the Manual testing covers the platforms.

## 9. Mortsom

[Mortsom](https://github.com/MostroP2P/mortsom) drives two real
copies of the app through complete trades against a regtest stack, on
Linux and web. It already builds the app from a pull request
(`mortsom run --ref <PR URL>`), and the UI contract it relies on is
`docs/automation-contract.md`.

### 9.1 Gate on pull requests (separate spec)

The daemon runs its e2e harness on pull requests and labels the result
(`ORTSOM_PR_E2E_SPEC.md` in `MostroP2P/mostro`). The equivalent here
runs the Mortsom scenarios selected by what a pull request touches and
labels regressions. It needs its own spec, written in this repository
before it is built; this spec only reserves its place in the layers and
its labels (`mortsom:*`).

### 9.2 Per-PR scenario from the Manual testing steps (future)

The daemon plans a fixed-vocabulary block (`ortsom-steps`) that turns
the Manual testing steps into a scenario. The same idea applies here once
the gate of §9.1 is live. The vocabulary has to be Mortsom's actor
actions and assertions, so it is defined in the Mortsom repository, not
here. Until then, Manual testing stays prose.

## 10. Security

- `quality-triage.yml` runs on `pull_request_target` with
  `pull-requests: write`, `issues: write`, `checks: write` (for the
  neutral check run of §7.2) and `contents: read`. It checks out `main`
  only, never the pull request's head or merge ref, and never
  interpolates the title, the description or branch names into shell:
  they reach `triage.py` through environment variables and are parsed
  there, with a 64 KiB limit on the description.
- `quality-red-test.yml` builds and runs pull request code, so it runs
  on `pull_request` with a read-only token and no secrets, like
  `ci.yml`. The repository's approval requirement for first-time
  contributors applies to it.
- `quality-verdict.yml` follows the two-workflow pattern: the untrusted
  run produces an artifact, the privileged run only reads it as data.
- On `pull_request` a pull request can modify the workflow that tests it
  and forge its artifact. A pull request that touches `.github/quality/**`
  or any `quality-*.yml` therefore gets no `quality:bug-reproduced`
  label; the verdict adds `quality:needs-info` with the reason "changes
  the quality workflows" and leaves it to a maintainer.
- Screenshots and recordings are links the bot only checks for
  presence; it never downloads them.

## 11. Optional: LLM triage (out of scope)

A model that reads the issue, the description and the code and answers
"does the described problem exist?" could help order the review queue.
If one is ever added, it only applies an informational label
(`quality:llm-doubt`) and **never** closes, blocks or counts toward
§7.5.

## 12. Labels

| Label | Applied by | Meaning |
|---|---|---|
| `status: accepted` | Maintainer | The issue describes a real problem in scope |
| `quality:ok` | Triage bot | Every §7 check passes |
| `quality:needs-info` | Triage bot, verdict | At least one check fails; the comment says which |
| `quality:would-close` | Stale job (shadow) | Would have been closed by §7.5 |
| `quality:exempt` | Maintainer | Skip the content checks (§7.3) |
| `quality:no-red-test` | Maintainer | A fix no Rust or Dart test can show failing on `main`; skip `fix-has-test` and §8 (§7.3) |
| `automation:coordinated` | Maintainer | An automation-id change was agreed with the Mortsom owners |
| `quality:bug-reproduced` | Verdict | The §8 test fails on `main` and passes on head |
| `quality:bug-not-reproduced` | Verdict | The §8 test passes on `main` |
| `quality:test-fails` | Verdict | The §8 test fails on head |
| `quality:red-test-inconclusive` | Verdict | The §8 test does not compile without the fix |
| `quality:too-large` | Size check | More changed lines than §7.6 allows |
| `size:exempt` | Maintainer | The size cannot be avoided; skip §7.6 |
| `mortsom:*` | Mortsom verdict | §9.1, defined in its own spec |

## 13. Rollout

| Phase | Repository | Content |
|---|---|---|
| 0 | app | This spec (lands together with Phase 1) |
| 1 | app | `CONTRIBUTING.md` sections (quality bar, Manual testing, Screenshots, red test commit convention), the `AGENTS.md` section of §3.1 and its pointer in `CLAUDE.md`, `.github/pull_request_template.md`, `.github/quality/close-message.md`, labels. Maintainers apply the policy by hand |
| 1b | app | `quality-size.yml`, `size_check.py` with tests, `config.toml` (§7.6). Labels and comment only, `neutral` check run |
| 2 | app | `quality-triage.yml`, `triage.py` with tests, `config.toml`, adapted from the daemon's. **Shadow**: labels and comment only, `neutral` check run |
| 3 | app | `quality-red-test.yml` and `quality-verdict.yml`. **Shadow** |
| 4 | app | Enforcement: `quality-stale.yml` closes after 7 days of `quality:needs-info`. Needs a separate, explicit decision after reviewing the shadow labels |
| 5 | mortsom, then app | §9: the PR gate spec and runner, then the per-PR steps |

Phase 1 is documentation only, and it should already remove most of the
pull requests this spec is about: a required accepted issue, a Manual
testing section that must name a step failing on `main`, and before and
after screenshots are enough to close them with a clear, written reason.

### Exit criteria for Phase 4

- At least 4 weeks of shadow labels.
- Every `quality:would-close` of that period reviewed by a maintainer,
  with at most one a maintainer would not have closed.
- The standard close message approved by at least two maintainers.

## 14. Known gaps

- **Golden tests cannot be red tests.** Reference images are generated
  only in CI (`docs/golden-tests.md`), so a golden test in a `test:`
  commit has no image to fail against on `main`. A visual fix proves
  itself with a widget test that asserts the property (a colour, a
  visibility, a text) when one can be written, and otherwise with the
  screenshots of its **(fails on `main`)** step under
  `quality:no-red-test` (§7.3).
- **Platform bugs.** A bug that only exists on iOS, Android or web
  cannot fail in a Linux CI job. The red test proves what the shared
  logic does; the Manual testing on that platform, with its screenshots,
  is the evidence for the rest, and for the whole of a bug no shared test
  can reach (`quality:no-red-test`, §7.3).
- **Seams can hide the fix.** The `refactor:` prefix of §8.1 is trusted
  not to change behaviour; the reviewer checks it.
- **`fix-has-test` fails open on large diffs.** GitHub omits the patch of
  a very large file, and the bot then cannot rule out a test in it, so
  it passes. The red test reads the commits themselves.
- **The type is self-declared.** A fix described as `feat` skips the
  `(fails on main)` step and `fix-has-test`. A wrong type is a close
  reason under §3.3.
- **A description can be fabricated,** screenshots included. The defence
  is a reviewer following the steps, and §3.3 makes a procedure that does
  not work a close reason.
- **Manual testing needs a Mostro node and two wallets.** That is the
  real cost of testing a trade, and the reason §6.1 accepts any node
  and network. A change that does not touch a trade needs neither
  (§6.1), but keeps its Regression step.
- **The review load moves; it does not disappear.** Accepting issues
  (§4) is new work for maintainers. It is cheaper than reviewing diffs,
  but it is not free.

## 15. Open questions

1. **Signed commits.** Phase 1 requires them, as the daemon does, and
   maintainers check them by hand until the bot reports them (Phase 2).
   Should an unsigned commit be a close reason before then?
2. **A node for contributors.** Should the maintainers publish a
   testnet/signet Mostro node and relay for Manual testing, so
   contributors do not need to run a daemon?
3. **Shared bot.** Copy the daemon's `triage.py` now and extract a shared
   action later, or extract it first and use it from both repositories?
