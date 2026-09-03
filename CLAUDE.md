# appv2 Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-06-26

## Active Technologies
- Rust stable 1.94+ (core); Dart 3.x / Flutter 3.x (UI shell) (004-mostro-p2p-client)
- nostr-sdk 0.44+, mostro-core 0.13.1, flutter_rust_bridge 2.11.1, Riverpod (state),
  go_router (navigation), sqlx (SQLite, native) / indexed_db_futures (IndexedDB, web),
  sembast (Dart UI-layer state), bip32/bip39 (keys), chacha20poly1305 (file encryption)
- Sembast (Dart, all platforms) for UI-layer state; SQLite via `sqlx` (Rust, native) /
  IndexedDB via `indexed_db_futures` (Rust, web) for protocol-layer persistence (004)
- Transport v2 (NIP-44 / signed Kind 14 to the daemon) (005-transport-v2-migration)

## Project Structure

```text
lib/        # Flutter shell (features/, l10n/, src/rust/ = GENERATED)
rust/       # Rust core (src/api/ = bridge surface; nostr/ crypto/ mostro/ db/ nwc/ queue/)
specs/      # 004 = active spec; 005 = transport-v2
.specify/   # ARCHITECTURE, constitution, v1-reference/ (descriptive of v1), prescriptive v2 docs
test/
```

## Commands

```bash
cd rust && cargo build
cd rust && cargo test && cargo clippy      # mandated verify (Rust)
./scripts/frb-generate.sh                   # after ANY change to rust/src/api/
./scripts/build-web.sh                      # web only: compile the Rust core to web/pkg/
flutter analyze && flutter test             # Dart side

# web smoke test — needs a release bundle first (see "Web (wasm)" below):
#   ./scripts/build-web.sh --release
#   flutter build web --release --base-href "/app/" --pwa-strategy=none
cd test/web/smoke && npm ci && npx playwright install chromium && BASE_PATH=/app/ node smoke.mjs
flutter run -d linux|chrome|android         # Rust is a lib — there is no `cargo run`
flutter gen-l10n                            # after editing lib/l10n/*.arb
```

## Web (wasm) — non-obvious constraints
- The Flutter build does **not** compile the Rust core on web. Run `./scripts/build-web.sh`
  (never `flutter_rust_bridge_codegen build-web`: on current nightly it silently emits
  non-shared memory and the FRB worker pool dies with `DataCloneError`).
- The page must be **cross-origin isolated** (`SharedArrayBuffer`). Locally that comes from
  `flutter run -d chrome --web-header ...`; in production from the vendored
  `web/coi-serviceworker.min.js`, which must stay the first script in `web/index.html`.
- `main` deploys to <https://mostro.network/app/> via `.github/workflows/deploy-pages.yml`
  (`--base-href` for the sub-path, `--pwa-strategy=none` so Flutter's service worker does not
  take the isolation shim's scope). Every one of these, when wrong, yields a **blank page** —
  `test/web/pages_bundle_test.dart` guards them statically.
- The build itself lives in the reusable **`.github/workflows/web-build.yml`**, called by both
  `ci.yml` (every PR) and `deploy-pages.yml` — edit it there, never in a caller, or the bundle
  CI validates drifts from the one that ships.
- Static greps pass on a page that dies at runtime, so that workflow also runs
  **`test/web/smoke/smoke.mjs`**: it serves the release bundle cross-origin isolated under
  `/app/` and asserts in headless Chrome that the page is isolated, the Flutter view mounted,
  a **Rust bridge call returned**, and nothing errored. The bridge signal comes from
  `lib/core/web/bridge_probe.dart`, which `main()` sets after its first successful Rust call
  (no-op off web) — rename that flag on one side only and the check silently never fires.

## Code Style

Rust stable 1.94+; Dart 3.x / Flutter 3.x: standard conventions.

<!-- MANUAL ADDITIONS START -->

## What this repo is
Mostro v2 — a client for **Mostro**, a P2P Bitcoin/Lightning exchange protocol
over Nostr. It re-architects the v1 app (`MostroP2P/mobile`, pure Flutter/Dart):
v1's `dart_nostr` was outdated and limited, so v2 moves all protocol/crypto/relay
logic to **Rust** (the well-maintained `nostr-sdk`) and keeps the **UI in Flutter**,
bridged by flutter_rust_bridge.

## Working agreement (read first)
- **Propose before editing.** Default to presenting the approach first — option(s) + why +
  pros/cons when there's a real trade-off — and wait for an explicit go-ahead before changing
  code. "Implement X" / "fix Y" is itself authorization for that scope; trivial edits you
  explicitly asked for don't need a round-trip; reserve pros/cons for genuine trade-offs.
  (For curated docs this is stricter — see Docs below.)
- **Verify, never invent.** Never assert a fact about this repo (how something works, where
  data lives, what's implemented) without confirming via tools — or ask. Don't turn
  "data-model lists X" into "X is implemented/persisted."

## Architecture — the golden rule
- **Rust** (`rust/src/`): Nostr protocol, cryptography, keys, relays, business logic.
- **Dart** (`lib/`): UI, navigation, UI state, device/OS I/O.
- **No crypto in Dart.** When in doubt: logic → Rust, device I/O → Dart.
- Authority: `.specify/ARCHITECTURE.md` + constitution Principle I.

## Generated code (don't corrupt it)
- `lib/src/rust/` is **generated by flutter_rust_bridge — never edit by hand.**
- Run `./scripts/frb-generate.sh` after any change to `rust/src/api/`. It refuses to run when
  your local codegen CLI does not match the version pinned in `pubspec.yaml` — generating with
  a mismatched CLI yields bindings that fail to compile, with an error that never mentions
  versions (see issue #205). `--check` verifies without generating.
- FRB scans only `crate::api` → changes in `nostr/`, `crypto/`, `mostro/`, etc. need no regen.
- **Regenerate after pulling, too — not just after your own edits.** `lib/src/rust/` and
  `lib/l10n/app_localizations*.dart` are gitignored, so a `git pull` that brings in someone
  else's `rust/src/api/` field or `.arb` key leaves your copies stale. CI regenerates both
  before it analyses (`ci.yml` → `frb-generate.sh`, `flutter gen-l10n`), so green CI proves
  nothing about your checkout. The failure is loud but misdirected — the analyzer blames
  whatever *uses* the missing field, so a stale `TradeInfo` reads as a broken test helper
  rather than as out-of-date bindings. If `flutter analyze` reports a field or l10n getter
  that plainly exists in `rust/src/api/types.rs` or `lib/l10n/*.arb`, regenerate before
  believing it.

## Transport (protocol v2)
- **Daemon messages** (new-order, take, release, cancel, dispute, rate, invoice, restore):
  **NIP-44 / signed Kind 14** (transport v2), via `wrap_mostro_message`/`unwrap_mostro_message`.
- **Peer chat**: **chat envelope** (kind 14 signed with `K_sign`, NIP-44 inner kind 1
  signed by the trade key — <https://mostro.network/protocol/chat.html>), via
  `mostro_wrap`/`mostro_unwrap` + `crypto/chat_keys.rs`. NIP-59 is gone from this
  channel in **both** directions (gift-wrap flood attack, issue #246).
- **Dispute admin chat**: the **same chat envelope**, keyed to the solver's pubkey
  (<https://mostro.network/protocol/dispute_chat.html> — "no gift wrap and no
  ephemeral key"). The interop dual-path for gift-wrap-only solvers is gone too;
  until mostrix#102 ships, such a solver is not reachable from here.
- **This client speaks protocol v2 only** — nothing reads or writes kind 1059.
- All live in `rust/src/nostr/transport.rs`. Daemon traffic is subscribed by
  `orders.rs::subscribe_daemon_messages` (per trade) and `handle_global_daemon_message`
  (global). Nothing in the v2 paths is named "gift wrap" any more — where that term
  still appears it refers to the superseded v1 transport on purpose.
- Wire status strings are **kebab-case** (`waiting-buyer-invoice`, `fiat-sent`).

## Translations
- **All user-facing strings are Dart-level** (Flutter l10n): `lib/l10n/app_{en,es,fr,de,it}.arb`,
  config `l10n.yaml`, generated `AppLocalizations` via `flutter gen-l10n`, used with
  `AppLocalizations.of(context)`.
- **Rust does not translate.** Rust returns data or a stable marker/code (e.g. `NoDaemonResponse`);
  Dart maps it to a localized string. Don't hardcode user-facing prose in Rust.
  (Known debt: some `CantDo` errors still return English prose directly — should become markers.)

## Docs — keep them in sync
- Hierarchy: `.specify/v1-reference/` = **descriptive of v1** (parity target);
  `specs/004` + `.specify/*` = **prescriptive for v2** (what/how to build). Specs are a
  **living artifact** — update the matching spec/contract as part of any behavior/contract change.
- For **curated reference docs** (`.specify/v1-reference/`, `.specify/*`): **propose edits first**.
- Update this `CLAUDE.md` when guidelines, tooling, or core tech change.

## Reference checkouts (when in doubt)
- **UX / feature parity** → `~/mobile` (v1, full-Flutter — github.com/MostroP2P/mobile).
- **Protocol / wire behavior** → `~/mostro-cli` (also `mostro-core`-based, like this app).
- **Caveat:** mobile hand-rolls crypto/protocol in Dart; here `nostr-sdk` (Rust) provides much
  of it, so the v2 implementation can legitimately differ — don't copy v1 blindly.

## Workflow
- **One PR per feature.** Long features → several **phased PRs** (`feat(usN): phase X` →
  `fix(phaseX): review round N`). Not big-bang.
- Conventional commits (`feat/fix/docs/refactor/chore(scope)`), branches `type/kebab-desc`,
  everything via **PR to `main`** (gh CLI) + CodeRabbit review.

## Domain gotchas (durable)
- **Reputation/ratings come from Kind 38383 event tags, not a DB.** In-memory
  `RATING_STORE`/`DISPUTE_STORE` are correct by design — don't invent "persist to DB" tasks.
  Chat history persists to the `messages` table since #246 (web still memory-only, #233).
- **Order book is sourced only from daemon Kind 38383 events.** `create_order` waits for daemon
  confirmation; on timeout it returns an error and **persists nothing** (no phantom order).
- **The Kind 38383 `s` tag is never a trade's status.** It is NIP-69's four-bucket public view
  (`pending`, `in-progress`, `success`, `canceled`), and the daemon stops publishing once the
  trade turns private — `active`/`fiat-sent`/`dispute` never reach the wire. So `InProgress`
  means "taken, real state unknown", and a trade's status comes from daemon messages only
  (`wire_status_applies` guards both ingest paths). Treating it as `Active` offers actions the
  daemon rejects with `CantDo` (#203).

<!-- MANUAL ADDITIONS END -->
