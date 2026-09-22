# Releasing

A release is cut by **pushing a tag** `vMAJOR.MINOR.PATCH`. `.github/workflows/release.yml`
does the rest: it builds and signs the Android APKs, builds the Linux, Windows, macOS and iOS
artifacts, writes the release notes, publishes the GitHub release and opens a PR that records
it in `CHANGELOG.md`.

Versions start at **2.0.0** (v1 was the pure-Flutter `MostroP2P/mobile`) and follow
[Semantic Versioning](https://semver.org/): patch for fixes, minor for features.

## Cutting a release

```bash
./scripts/release.sh 2.0.1   # opens the `chore(release): v2.0.1` PR → merge it
./scripts/release.sh 2.0.1   # tags origin/main as v2.0.1 and pushes it → the release runs
# When the run finishes: review and merge the `chore(release): changelog for v2.0.1` PR.
```

`scripts/release.sh` looks at where the release stands and takes the next step, so the same
command serves both runs:

1. **`origin/main` does not carry the version yet** — it branches `chore/release-v2.0.1` off
   `origin/main`, runs `scripts/bump-version.sh` (`pubspec.yaml`, `rust/Cargo.toml`,
   `rust/Cargo.lock`), commits, pushes, opens the PR and returns to the branch you were on.
   It refuses a version that does not move past `main`'s, or a dirty working tree; if a step
   fails midway it returns to your branch and drops the local release branch.
2. **That PR is still open** — it prints the link and does nothing else.
3. **`origin/main` carries the version** — it tags `origin/main` (not your checkout, whatever
   branch you are on) with an annotated `v2.0.1` and pushes the tag.

It never merges a PR and never deletes a tag: a tag that already exists on `origin` is refused
with the commands to remove it. To re-cut a release at a version `main` already carries (e.g.
re-releasing `2.0.0`), step 3 applies directly.

The workflow refuses the tag — before building anything — when:

- it is not `vX.Y.Z` (no `-rc1`, no `+build`);
- the tagged commit is **not on `main`**;
- `pubspec.yaml` or `rust/Cargo.toml` does not already say `X.Y.Z`. The About screen reports
  `CARGO_PKG_VERSION`, so a tag the source disagrees with would ship an app that lies about
  its version. `test/ci/release_workflow_test.dart` keeps the two files equal;
- `MINOR` or `PATCH` is above 99 (see *Android version codes*).

## One-time setup

### Signing key (required)

Android only installs an update signed with the **same certificate** as the installed app.
The key below is therefore the identity of the app for its whole life: **lose it and no
existing user can ever update; leak it and anyone can ship an "update"**. Generate it once,
keep an offline backup, and never commit it (`android/.gitignore` excludes it).

```bash
keytool -genkeypair -v -keystore mostro-release.jks -alias mostro \
  -keyalg RSA -keysize 4096 -validity 10000
base64 -w0 mostro-release.jks        # value of ANDROID_KEYSTORE_FILE
```

Repository secrets (Settings → Secrets and variables → Actions), same names as v1's workflow:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_FILE` | the keystore, base64-encoded |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password |
| `ANDROID_KEY_PASSWORD` | key password |
| `ANDROID_KEY_ALIAS` | key alias (`mostro` above) |

With a secret missing the run fails at "Check signing secrets". There is deliberately no
fallback to the debug key, and the job re-checks the certificate of each finished APK.

To sign a build locally, create `android/key.properties` (`storeFile`, `storePassword`,
`keyPassword`, `keyAlias`); without it a release build uses the debug key, which is fine for
`flutter run --release` and must never be distributed.

### Repository settings

- **Settings → Actions → General → "Allow GitHub Actions to create and approve pull
  requests"** — for the changelog PR. Without it the release is still published and the
  `changelog` job fails with the branch name to open the PR from by hand.
- **Restrict who can release.** Anyone with write access can push a tag, and a `vX.Y.Z` tag on
  `main` is all the workflow asks for. Do both:
  - a **tag ruleset** (Settings → Rules → Rulesets) limiting creation of `v*` to admins;
  - **required reviewers on the `release` environment** (Settings → Environments). The
    `android` job — the only one that sees the signing key — runs in it, so the run then
    waits for an admin's approval before anything is signed. Moving the four secrets from
    repository to environment scope keeps them out of reach of every other workflow.

## What a release contains

| Asset | |
| --- | --- |
| `mostro-vX.Y.Z-arm64-v8a.apk` | 64-bit ARMv8-A — modern phones |
| `mostro-vX.Y.Z-armeabi-v7a.apk` | 32-bit ARMv7-A — old / entry-level phones on a 32-bit Android |
| `mostro-vX.Y.Z.aab` | Android App Bundle for the Play Console (all ABIs, same key) — not installable on a phone |
| `mostro-vX.Y.Z-linux-x64.tar.gz` | the Flutter bundle (`mostro`, `lib/`, `data/`), built on Ubuntu 22.04 → glibc 2.35+ |
| `mostro-vX.Y.Z-windows-x64.zip` | `mostro.exe` and its DLLs — no Authenticode signature (SmartScreen warns) |
| `mostro-vX.Y.Z-macos-universal.zip` | `mostro.app`, arm64 + x86-64, ad-hoc signed, **not notarized** (Gatekeeper blocks a double click) |
| `mostro-vX.Y.Z-ios-unsigned.ipa` | **unsigned**, for sideloading tools that re-sign it; push does not work in a re-signed build |
| `SHA256SUMS.txt` | checksums of the above |

An Android `x86_64` APK is not shipped (an emulator ABI). The file names are a contract between
the workflows and `tool/release/downloads.dart`, which writes the *Downloads* section and the
per-OS instructions; `test/ci/release_workflow_test.dart` holds the two sides equal.

### Desktop and iOS builds

They live in the reusable **`.github/workflows/release-builds.yml`**, called by `release.yml`
and by **`release-dry-run.yml`**. Only the Linux one can be compiled on a contributor's Linux
machine, so the dry run compiles all four — publishing nothing — on any PR that touches the
release workflows, `linux/`, `windows/`, `macos/`, `rust_builder/` or a lockfile. It is
path-filtered, so **never make it a required check**. Edit a build in `release-builds.yml`,
never in a caller, or the dry run stops testing what ships.

**The APKs are the release.** `publish` waits for these builds but only requires `android`: when
one fails, the release goes out with what was built and its notes name the missing platform
instead of linking to a 404. The run ends red; **"Re-run failed jobs"** builds the missing
asset, publishes again and adds it to the same release.

What they are not, and what closing each gap takes:

- **macOS** — no Developer ID, no notarization. Needs an Apple Developer account, the
  certificate as secrets, and a `notarytool` step after the build.
- **Windows** — no code-signing certificate.
- **iOS** — no TestFlight. Needs the same Apple account, a distribution certificate and
  provisioning profile as secrets, and `flutter build ipa` instead of `--no-codesign`.
- **Linux** — a plain bundle: no `.deb`, AppImage or Flatpak.

### Release notes and CHANGELOG.md

Both are printed by `tool/release_notes.dart` from the same data, so they cannot disagree:

- **One entry per merged PR**, from the first-parent history of `previous tag..tag`. `main`
  only moves by merge commit, so this lists PRs by their title and author and leaves out the
  "review round N" commits inside them. A commit pushed straight to `main` is listed by sha.
- Entries are grouped by the **conventional-commit type of the PR title** (`feat`, `fix`,
  `perf`, `refactor`, `docs`, `test`, `build`/`ci`, `chore`, `revert`; `type!:` goes under
  *Breaking Changes*; anything else under *Other Changes*). **A good PR title is the
  changelog line** — fix the title before merging, not the changelog after.
- *Contributors* are the authors of those PRs (bots excluded); *New Contributors* are those
  with no PR merged before this release.
- `chore(release): …` PRs (version bumps, the changelog PR itself) are left out.

`CHANGELOG.md` is generated: fix a wrong entry by re-running the release (below), not by hand.

### Android version codes

`versionCode = MAJOR·10000 + MINOR·100 + PATCH`, to which Flutter's `--split-per-abi` adds
`1000` (v7) or `2000` (v8): `v2.0.1` ships as 21001 and 22001. It is derived from the tag
alone, so it is ordered like the versions whatever branch or rebuild produced it — hence the
limit of 99 on `MINOR` and `PATCH`.

## When a run fails

Nothing is published until the `publish` job, so a failure before it leaves no trace: fix the
cause on `main` and **re-run the workflow** from the Actions tab (same tag, same commit). If
the fix needs a new commit, merge it, delete the tag (`git push origin :v2.0.1 && git tag -d
v2.0.1`) and run `./scripts/release.sh 2.0.1` again: it tags the new `main`. Re-running after a release exists updates its notes and replaces its assets in
place, and the changelog job rewrites that version's section instead of adding a second one.

A PR opened by `GITHUB_TOKEN` does not trigger workflows: **close and reopen** the changelog
PR to start CI on it.
