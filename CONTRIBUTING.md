# Contributing

Anyone is welcome to contribute to Mostro. If you're looking for somewhere to start, check out the [good first issue](https://github.com/MostroP2P/app/labels/good%20first%20issue) list.

This app is **Mostro v2**: a hybrid client where the Nostr protocol, cryptography, and business logic live in **Rust** and the UI lives in **Flutter/Dart**, bridged by `flutter_rust_bridge`. Please read [AGENTS.md](AGENTS.md) for the project structure, architecture rules, and build/test commands before contributing.

## Language

All contributions must be written in **English** — code, comments, commit messages, branch names, PR titles and descriptions, review comments, issues, and docs. The only exception is user-facing UI copy, which is localized via Flutter l10n ARB files (with English as the source language). See [AGENTS.md](AGENTS.md#language).

## Communication Channels

Most technical discussion happens on the development [Telegram group](https://t.me/mostro_dev); non-technical discussion happens on the [Mostro Telegram group](https://t.me/MostroP2P). Discussion about code changes happens in GitHub issues and pull requests.

## Contributor Workflow

All contributors submit changes via pull requests. The workflow is as follows:

- Fork the repository
- Create a topic branch from the `main` branch, named `type/kebab-desc` (e.g. `feat/order-filters`, `docs/add-agents-contributing`)
- Commit patches using [conventional commits](https://www.conventionalcommits.org/) (`feat`, `fix`, `docs`, `refactor`, `chore`, `test`, …) with an optional scope
- Squash redundant or unnecessary commits
- Submit a pull request from your topic branch back to the `main` branch of the main repository
- Make changes if reviewers request them and request a re-review

Pull requests should be focused on a single change. Do not mix, for example, a refactoring with a bug fix or a new feature. **One PR per feature**; long features are split into phased PRs rather than a single big-bang change. This makes each pull request easier to review.

### The golden rule (architecture)

Every change must respect the layering:

- **Rust** (`rust/src/`) owns the Nostr protocol, cryptography, keys, relays, and business logic.
- **Dart** (`lib/`) owns the UI, navigation, UI state, and device/OS I/O.
- **No cryptography in Dart.** When in doubt: logic → Rust, device I/O → Dart.
- Never hand-edit generated code in `lib/src/rust/`; regenerate it with `./scripts/frb-generate.sh` after any change to `rust/src/api/`.

### Protocol / Transport Changes

Changes that affect Nostr event kinds, tags, or the transport layer are **protocol changes** and deserve extra care:

- **Transport v2** — daemon messages (new-order, take, release, cancel, dispute, rate, invoice, restore) use NIP-44 / signed Kind 14. Peer and dispute chat use the **chat envelope**: a Kind 14 outer event signed with `K_sign`, carrying a NIP-44-encrypted inner Kind 1 signed by the trade key (`specs/004-mostro-p2p-client/contracts/messages.md`). This client speaks protocol v2 only — nothing reads or writes Kind 1059, in either direction, since #246. Keep changes to these paths focused and well-described.
- **Wire compatibility** — wire status strings are kebab-case (e.g. `waiting-buyer-invoice`, `fiat-sent`). Any change to event formats must state its impact on external consumers (the Mostro daemon, other clients, relays).
- **Keep the spec in sync** — specs under `specs/` and `.specify/` are a living artifact. Update the matching spec/contract as part of any behavior or contract change.

## Contribution quality bar

A pull request has to prove two things before a reviewer reads the diff: that the problem it addresses exists, and that the change does not break anything else. The rules below are about the evidence a pull request carries, not about how it was written.

1. **AI tools are allowed.** You are responsible for every line and must be able to explain any of it when a reviewer asks. "The tool wrote it" is not an answer.
2. A pull request that does not follow the [template](#pull-request-template), does not link an [accepted issue](#issue-before-pull-request) when one is required, or does not meet the [Manual testing](#manual-testing), [Screenshots](#screenshots) and [Red test](#red-test) rules below, **is closed without technical review**, with the [standard message](.github/quality/close-message.md). You can reopen it once it meets the bar. Pull requests also keep to the [size limit](#pull-request-size).
3. A pull request whose description does not match its diff, whose Manual testing steps do not work when a reviewer follows them, or whose screenshots do not match what the branch shows, is closed the same way.
4. An account that repeatedly opens pull requests closed under this policy may be blocked from the organisation.

**Exempt** from the accepted issue, the template, Manual testing, Screenshots and the Red test: pull requests that only change Markdown files, pull requests from maintainers and bots, and pull requests a maintainer labels `quality:exempt`. Signed commits and the [size limit](#pull-request-size) apply to everyone but bots.

For now maintainers apply these rules by hand. Automated checks will first only add labels and comments; nothing is closed automatically without a separate, announced decision. The design is in [docs/CONTRIBUTION_QUALITY_SPEC.md](docs/CONTRIBUTION_QUALITY_SPEC.md).

### Issue before pull request

Every pull request that is not [exempt](#contribution-quality-bar) links an issue that a maintainer has labelled `status: accepted`. Discuss the bug or the feature in the issue first: there, "this is not a bug" or "this is not the design we want" costs one comment instead of a review of a whole diff.

- Link it with a closing keyword in the description (`Closes #123`, `Fixes #123`). A plain mention does not count.
- Only maintainers apply `status: accepted`, when they agree the problem is real and in scope. An issue opened minutes before the pull request is not accepted until a maintainer says so.
- A UI or design change needs the issue to show the intended result: a mockup, the v1 screen it matches, or a reference to `docs/design/`. The result must keep the [design guide](.specify/DESIGN_SYSTEM.md): a proposal that breaks one of its MUST rules is declined, or it changes the guide first.
- If there is no accepted issue yet, comment on the issue instead of opening the pull request.

### Pull request size

A pull request has at most **1,500 changed lines** (additions plus deletions), **not counting** tests, generated files and documentation. The limit exists so a reviewer can read the whole change: a large diff gets a shallower review.

- **Tests do not count:** `test/**`, `*_test.dart`, `rust/tests/**`, and `#[cfg(test)]` items and `#[test]` functions inside `rust/src/`. Write as many tests as the change needs.
- **Generated files do not count:** `lib/src/rust/**`, `rust/src/frb_generated.rs`, the generated localizations, lockfiles and golden images.
- **Documentation does not count:** Markdown files, `docs/`, `specs/` and `.specify/`.
- Everything else counts: Rust and Dart production code, platform code, CI and tooling.

Over the limit, split the work into pull requests that each build, pass the tests and can be reviewed on their own, for example one per phase of a feature. If the size cannot be avoided (a bindings regeneration, a migration, a large dependency bump), say why in the description; a maintainer may apply `size:exempt`.

The **Pull request size** check counts the lines on every pull request. Over the limit it adds `quality:too-large` and one comment with the breakdown. It does not block the merge. First-time contributors keep the tighter first pull request limit of 400 changed lines.

### Pull request template

Fill in every section of [`.github/pull_request_template.md`](.github/pull_request_template.md). A section that is missing, empty or left with only its placeholder comment counts as not filled in.

**Affected flow** names the screens or routes, the user actions (take an order, pay the hold invoice, release, open a dispute, restore…) and the order or dispute statuses the change touches, and the layer and files where that behaviour lives: Rust core, bridge (`rust/src/api/`), or Dart providers and widgets. **Blast radius** names what else reads or writes the state you changed (persisted data and existing installs upgrading, generated bindings, the other platforms, background work and push notifications, localization keys, [automation identifiers](docs/automation-contract.md), what the daemon and the v1 app see on the wire) and says why it is not broken. **Platforms tested** says where you ran the Manual testing. A generic or wrong answer in any of them is a reason to close.

### Manual testing

The **Manual testing** section is a step-by-step procedure that tests this specific pull request end to end, in the app built from your branch, against a running Mostro node. **A person runs it by hand** and writes down what they saw; a reviewer must be able to follow the same steps and see the same results.

Mostro's developers also run end-to-end suites with [Mortsom](https://github.com/MostroP2P/mortsom), which drives two copies of the app through complete trades on a regtest stack. Nothing here requires it: you test with the same app a user runs.

- **Setup** says how you built the app (`flutter run` from the branch, which platform and device, debug or release; `./scripts/build-web.sh` for web), which Mostro node and relays when they differ from the defaults, how each actor pays and gets paid (Lightning wallet, NWC or manual invoices), which client each other actor uses (a second copy of this app, the v1 app or mostro-cli), and the state the steps start from (fresh install, existing identity, privacy mode…).
- **Steps** are numbered. Each step names one actor (maker, taker, buyer, seller, solver), one action in the UI, and an `Expected:` line with an observable result: the screen shown, a status or chip, a notification, a chat message, a button enabled or hidden, a payment received in the wallet, or, when the UI does not show it, the order status on the public event (kind 38383).
- **For a fix**, one step is marked **(fails on `main`)** and also says what `main` does instead. If no step fails on `main`, the pull request has not shown that the bug exists.
- **Restart and upgrade**: a change to anything persisted includes a step that quits and relaunches the app, and says whether it was tested as an upgrade of an install made by `main`.
- **Regression**: at least one step exercises a neighbouring flow named in **Blast radius** and shows it behaves as before. It is a step of its own, apart from the steps that show the change, so every procedure has at least two steps.
- **Not covered** lists what the steps do not test and why (for example, "iOS: no Mac available").
- A step that cannot be observed ("the provider is now more robust") is not a step.

A change that does not touch a trade (settings, account, a static screen) only needs the steps that reach the changed screen; it does not need a node and two wallets. The rules above still apply: it has a **Regression** step and, for a fix, a step marked **(fails on `main`)**.

A change with no app flow (a CI workflow, a build or release script, tooling, or tests only) has no screen to reach. Its steps run what the change touches: the command, the script, or the workflow on the branch. Each `Expected:` line names what that run shows: its output, the workflow run and its conclusion, the file it produces. **Setup** says where it ran (OS, tool versions), and a step names who runs it instead of a trade actor. The same rules apply: a **Regression** step on a neighbouring command or job, and, for a fix, a step marked **(fails on `main`)**.

Example, for a fix where privacy mode was lost on restart (#624):

```markdown
### Setup

App built from this branch with `flutter run -d linux` (debug), and on an
Android 15 emulator. Default node and relays. Existing identity, in
Reputation Mode.

### Steps

1. Open Account and select Full Privacy Mode.
   Expected: Full Privacy Mode is selected.
2. Quit the app completely and launch it again; open Account.
   **(fails on `main`)**
   Expected: Full Privacy Mode is still selected.
   On `main`: Reputation Mode is selected again.
3. Regression: select Reputation Mode, quit and relaunch; open Account.
   Expected: Reputation Mode is selected, as on `main`.

### Not covered

That the next trade goes out without the identity key is covered by
`test/core/services/identity_privacy_mode_test.dart`: the app does not
show which key signed a message. Web and iOS not run; no platform code.
```

If you could not build or run the app, say so in the pull request instead of claiming results.

### Screenshots

- Any visible change carries **before** (`main`) and **after** (your branch) screenshots of the same screen with the same data.
- A change of colour, contrast or layout adds both themes, and a phone width when the layout reflows.
- A change of layout adds one screenshot at 2× text scale (the [design guide](.specify/DESIGN_SYSTEM.md) §12).
- A change of copy shows English and at least one other locale.
- A change inside a flow (several screens, an animation, a timing) is a short screen recording instead.
- With no visible change, write `No visible change`. Writing it for a change that is visible is a description that does not match its diff.
- A visible change also names the [design guide](.specify/DESIGN_SYSTEM.md) rules it touches (`DS-CMP-3`, `DS-COL-6`…), any SHOULD it departs from and why, and every new colour token with its contrast test (guide §12).

[Golden tests](docs/golden-tests.md) do not replace screenshots: they catch unintended changes, not whether the new look is the intended one.

### Red test

The regression test of a fix must **fail without the fix and pass with it**. It can be a Rust test (next to the code, in `#[cfg(test)] mod tests`) or a Dart test (under `test/`). The test is separated from the fix by commit:

- In a fix pull request, **the first commit that is not a `refactor:` commit has a subject beginning with `test:`** and only adds the regression test (inside `#[cfg(test)]` modules or under `test/`, no production code, no generated files). Without a seam (next point), it is the pull request's first commit.
- If the test needs a seam the code does not have yet (an injectable function, a `@visibleForTesting` entry point), add it in `refactor:` commits **before** the `test:` commit. Those commits must not change behaviour: with them and the `test:` commit on `main`, the test still fails.
- The fix follows in one or more later commits.
- The `test:` commit is a meaningful commit, not a fixup: do not squash it into the fix. It stays separate until merge; the maintainer may squash when merging.
- Golden tests do not count as the red test: their reference images are generated only in CI. A visual fix adds a widget test that asserts the property (a colour, a visibility, a text) when one can be written.
- When no Rust or Dart test can fail on `main` (a purely visual bug no widget test can observe, or one that only exists on iOS, Android or web), say why under **Automated tests**. A maintainer who agrees labels the pull request `quality:no-red-test`, which waives the `test:` commit and its check. The step marked **(fails on `main`)**, with its screenshots, is then the evidence that the bug exists.
- Check it yourself before opening the pull request: with only the `refactor:` and `test:` commits applied on the current `main`, the new test fails; with the whole pull request, it passes.

## Reviewing Pull Requests

Anyone may participate in peer review, expressed through comments on the pull request. Reviewers typically check the code for obvious errors, test the patch, and opine on its technical merits. Maintainers take peer review into account when determining whether there is consensus to merge. The following language is used within pull-request comments (adapted from the [Bitcoin Core contributor documentation](https://github.com/bitcoin/bitcoin/blob/master/CONTRIBUTING.md#peer-review)):

- `ACK` means "I have tested the code and I agree it should be merged";
- `NACK` means "I disagree this should be merged", and must be accompanied by sound technical justification. NACKs without reasoning may be disregarded;
- `utACK` means "I have not tested the code, but I have reviewed it and it looks OK, I agree it can be merged";
- `Concept ACK` means "I agree with the general principle of this pull request";
- `Nit` refers to trivial, often non-blocking issues.

Reviewers should verify **external contract impact** for any PR that modifies event kinds, tags, or message formats — confirm that the daemon, other clients, and relays are not silently broken. PRs are also reviewed automatically by CodeRabbit.

Pull requests marked `NACK` and/or GitHub's `Changes requested` are closed after 30 days if not addressed.

## Code Formatting & Checks

Run the full verify before committing and before requesting review:

- **Rust:** `cd rust && cargo fmt && cargo clippy && cargo test` — keep the tree `clippy`-clean.
- **Dart:** `dart format .`, then `flutter analyze && flutter test` — keep it analyzer-warning-free.
- **Bindings:** run `./scripts/frb-generate.sh` after any change to `rust/src/api/`. It refuses to generate when your local `flutter_rust_bridge_codegen` does not match the version pinned in `pubspec.yaml`, because a mismatched CLI produces bindings that fail to compile with an error that never mentions versions. **Commit** what it generates, in the same commit as the `api/` change. See [Generated code](#generated-code).
- **Localization:** run `flutter gen-l10n` after editing `lib/l10n/*.arb`, and commit the regenerated `lib/l10n/app_localizations*.dart`.

The repository ships **no git hooks**. These checks run in CI on every pull request. Run them locally before you push.

Clones that ran the old `scripts/setup-hooks.sh`, directly or through `frb-generate.sh`, still have its copies in `.git/hooks/`. Git does not remove those copies when the scripts leave the repository, so they keep regenerating code after pulls and running the old pre-commit checks. Remove them once per clone. This only deletes files that carry the installer's marker, so any hooks of your own stay:

```bash
hooks="$(git rev-parse --git-common-dir)/hooks"
grep -l 'installed by scripts/setup-hooks.sh' "$hooks"/* 2>/dev/null | xargs -r rm --
```

### Generated code

The flutter_rust_bridge bindings (`lib/src/rust/`, `rust/src/frb_generated.rs`) and the localizations (`lib/l10n/app_localizations*.dart`) are **committed**. A fresh clone, a `git pull` or a branch switch builds as-is, with nothing to regenerate first.

One rule keeps this safe: **generated files only change by regenerating them, in the same commit as the source change that caused it.** Never edit them by hand.

| You changed | Run | Commit together |
|---|---|---|
| `rust/src/api/`, or the flutter_rust_bridge pin | `./scripts/frb-generate.sh` | the source + `lib/src/rust/` + `rust/src/frb_generated.rs` |
| `lib/l10n/*.arb` | `flutter gen-l10n` | the `.arb` + `lib/l10n/app_localizations*.dart` |

CI enforces this rule. The Flutter job regenerates both from the pull request's sources and fails with **"Generated code is out of date"** when the result differs from what the PR commits. To fix it, run both commands on your branch and commit the result. The files are marked `linguist-generated` in `.gitattributes`, so GitHub collapses them in PR diffs.

#### Resolving conflicts in generated files

Two branches that both touch `rust/src/api/` or an `.arb` also conflict in the generated files. **Never resolve those conflicts by hand.** A hand-merged file is output no generator produced, and it can compile while being wrong. Resolve the sources, then regenerate:

1. **Resolve the sources first**: `rust/src/api/`, `lib/l10n/*.arb`, `pubspec.yaml`. Then `git add` them.
2. **Take either side of the generated files.** They are about to be overwritten, so it does not matter which side:

   ```bash
   git checkout --theirs -- lib/src/rust rust/src/frb_generated.rs lib/l10n/app_localizations*.dart
   ```

   During a rebase, `--ours` and `--theirs` are swapped compared with a merge. That doesn't matter here either.
3. **Regenerate from the resolved sources:**

   ```bash
   ./scripts/frb-generate.sh
   flutter gen-l10n
   ```

4. **Stage and continue:**

   ```bash
   git add lib/src/rust rust/src/frb_generated.rs lib/l10n
   git rebase --continue   # or `git commit` when merging
   ```

5. **Check the result** with `flutter analyze` before pushing. CI runs the same drift check.

If a commit in the middle of a rebase can't be regenerated (for example, its Rust does not compile yet), take either side, finish the rebase, and regenerate once at the tip. Commit that as `chore: regenerate generated code`. CI checks the tip of the branch.

### Configure Git user name and email metadata

See <https://help.github.com/articles/setting-your-username-in-git/> for instructions.

### Write well-formed commit messages

Beyond the conventional-commits prefix, follow the [seven rules of a great commit message](https://chris.beams.io/posts/git-commit/#seven-rules):

1. Separate subject from body with a blank line
2. Limit the subject line to around 50 characters
3. Use the imperative mood in the subject line
4. Do not end the subject line with a period
5. Wrap the body at 72 characters
6. Use the body to explain what and why vs. how
7. Reference relevant issues in the body

### Keep the git history clean

Keep the git history clear, light, and easily browsable. Pull requests should include only meaningful commits (redundant ones, or ones added after a review, should be squashed) and **no merge commits** — rebase on `main` instead.
