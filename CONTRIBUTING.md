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
- Never hand-edit generated code in `lib/src/rust/`; regenerate it with `flutter_rust_bridge_codegen generate` after any change to `rust/src/api/`.

### Protocol / Transport Changes

Changes that affect Nostr event kinds, tags, or the transport layer are **protocol changes** and deserve extra care:

- **Transport v2** — daemon messages (new-order, take, release, cancel, dispute, rate, invoice, restore) use NIP-44 / signed Kind 14; peer and dispute chat use NIP-59 gift wrap (Kind 1059). Keep changes to these paths focused and well-described.
- **Wire compatibility** — wire status strings are kebab-case (e.g. `waiting-buyer-invoice`, `fiat-sent`). Any change to event formats must state its impact on external consumers (the Mostro daemon, other clients, relays).
- **Keep the spec in sync** — specs under `specs/` and `.specify/` are a living artifact. Update the matching spec/contract as part of any behavior or contract change.

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
- **Bindings:** run `flutter_rust_bridge_codegen generate` after any change to `rust/src/api/`. The generated `lib/src/rust/` is gitignored and produced on the fly (locally and in CI) — do not commit it.
- **Localization:** run `flutter gen-l10n` after editing `lib/l10n/*.arb`.

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
