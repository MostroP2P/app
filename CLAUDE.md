# appv2 Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-09-17

## Active Technologies
- Rust stable 1.94+ (core); Dart 3.x / Flutter 3.x (UI shell) (004-mostro-p2p-client)
- nostr-sdk 0.45+, mostro-core 0.14.6, flutter_rust_bridge 2.11.1, Riverpod (state),
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
- `cargo check --target wasm32-unknown-unknown` is **not** a substitute for `build-web.sh`: two
  wasm-only requirements fail later than type-checking. `getrandom` (0.2 via bip32/k256, 0.4 via
  nostr's `rand`) needs its JS backend feature enabled in `rust/Cargo.toml`, and nostr 0.45's
  `universal-time` refuses to **link** until the final crate defines a time provider
  (`rt::browser_clock`). Both used to come for free from nostr 0.44 and vanished with 0.45.
- The build itself lives in the reusable **`.github/workflows/web-build.yml`**, called by both
  `ci.yml` (every PR) and `deploy-pages.yml` — edit it there, never in a caller, or the bundle
  CI validates drifts from the one that ships.
- Static greps pass on a page that dies at runtime, so that workflow also runs
  **`test/web/smoke/smoke.mjs`**: it serves the release bundle cross-origin isolated under
  `/app/` and asserts in headless Chrome that the page is isolated, the Flutter view mounted,
  a **Rust bridge call returned**, and nothing errored. The bridge signal comes from
  `lib/core/web/bridge_probe.dart`, which `main()` sets after its first successful Rust call
  (no-op off web) — rename that flag on one side only and the check silently never fires.
  The CI run also sets `SMOKE_BOND_STORE=1`: it seeds bond rows (`test/web/smoke/seed/`) into
  IndexedDB, reloads, and compares them with what `lib/core/web/store_probe.dart` read back.
- **The FCM messaging worker is a second service worker**, `web/firebase-messaging-sw.js`,
  registered from `web/index.html` and `web_push_web.dart` **relative to the base path** under
  the scope `firebase-cloud-messaging-push-scope` — Firebase's default is the origin root, a 404
  under `/app/`, and `firebase_messaging` 15 cannot take a worker path, so the token comes from
  the JS SDK with that registration. Its Firebase config and SDK version are copies that
  `pages_bundle_test.dart` holds equal to `firebase_options.dart` and `firebase_core_web`; CI
  sets `SMOKE_PUSH_WORKER=1` to assert it activates without costing isolation. Web push stays
  off until the build passes `PUSH_WEB_ENABLED` (docs/PUSH_NOTIFICATIONS.md T4.5).

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
- **Even a private item in `rust/src/api/` needs a regen**: the generated Dart lists every
  non-`pub` function and type in its header comments. `frb-generate.sh --check` does **not**
  catch that — it only compares version pins. `scripts/check-generated.sh` does (regenerates and
  diffs, like CI), and runs as a Claude Code `PreToolUse` hook on `git commit`
  (`.claude/settings.json`): it blocks a stale commit and leaves the files regenerated to stage.
  Skip once with `SKIP_GENERATED_CHECK=1` in the command.
- **Generated code is committed:** `lib/src/rust/`, `rust/src/frb_generated.rs` and
  `lib/l10n/app_localizations*.dart`. A pull or branch switch builds as-is. Regenerate in the
  **same commit** as the `rust/src/api/` or `.arb` change that caused it. Never hand-edit or
  hand-merge these files. `ci.yml` ("Check generated code is committed") regenerates both and
  fails on any difference. The fix is to rerun `./scripts/frb-generate.sh` and
  `flutter gen-l10n`, then commit the result.
- **The repo ships no git hooks.** They used to regenerate the ignored copies after a pull.
  Committing the output made them unnecessary, so don't reintroduce them.
- **Conflicts in generated files:** resolve the sources first. Then take either side of the
  generated files (`git checkout --theirs -- <paths>`), regenerate, stage and continue. Full
  procedure: `CONTRIBUTING.md` → "Resolving conflicts in generated files".

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
- **All user-facing strings are Dart-level** (Flutter l10n): `lib/l10n/app_{en,es,fr,de,it,nl}.arb`,
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

## Releases (`docs/RELEASING.md`)
- **A pushed tag `vX.Y.Z` is the release.** `.github/workflows/release.yml` builds two signed
  APKs (`armeabi-v7a`, `arm64-v8a`), publishes the GitHub release and opens the `CHANGELOG.md`
  PR. It refuses a tag that is not on `main` or whose version `pubspec.yaml` **and**
  `rust/Cargo.toml` do not already carry — the About screen shows `CARGO_PKG_VERSION`. Cut a
  release with `./scripts/release.sh X.Y.Z`, run twice: it opens the bump PR
  (`scripts/bump-version.sh`, never one file by hand), then — once merged — tags `origin/main`.
- **Desktop and iOS release builds live in `release-builds.yml`**, a reusable workflow that
  `release.yml` and `release-dry-run.yml` both call — edit a build there, never in a caller.
  The dry run is the only place a Windows, macOS or iOS build is compiled before a release
  (path-filtered PRs; never a required check). `publish` requires only `android`: a failed
  desktop build leaves its asset out and the notes say so. Asset names are a contract with
  `tool/release/downloads.dart`. None of these builds is vendor-signed or notarized.
- **The macOS app is sandboxed**: without `com.apple.security.network.client` in
  `macos/Runner/*.entitlements` it builds, launches and reaches no relay.
- **Release notes and `CHANGELOG.md` are generated** by `tool/release_notes.dart`, one entry
  per merged PR grouped by the conventional-commit type of its **title**. Don't hand-edit
  `CHANGELOG.md`; fix the PR title.
- **Never publish an APK signed with the debug key**, which is what a release build falls back
  to without `android/key.properties`: Android cannot update across a certificate change.
- `ndk.abiFilters` and `--split-per-abi` are mutually exclusive in AGP — keep the guard in
  `android/app/build.gradle.kts` (`test/ci/release_workflow_test.dart`).

## Domain gotchas (durable)
- **Reputation/ratings come from Kind 38383 event tags, not a DB.** In-memory
  `RATING_STORE`/`DISPUTE_STORE` are correct by design — don't invent "persist to DB" tasks.
  Chat history persists to the `messages` table since #246 — on web to the IndexedDB `messages`
  store (#233, closed).
- **On native, relays persist in the `relays` table and grow from the node's kind 10002 list.**
  `initialize(None)` restores the persisted set (or seeds the defaults on a fresh install); the
  active node's NIP-65 list is subscribed live and applied **additively** (never disconnects).
  Removing a `MostroDiscovered` relay blacklists it, re-adding it lifts the blacklist. On **web**
  the same rows live in the IndexedDB `relays` store (#233, closed). Relay persistence stays
  best effort on both targets: a failed write is logged and ignored.
- **A REQ issued while a relay is down never exists on it — reconnect or not** (nostr-sdk 0.45
  drops a failed REQ from that relay's registry). So every long-lived subscription is opened,
  replaced and closed through `nostr::live_subs` (`open` / `replace` / `close`), which records
  the intent and re-issues it per relay as it connects; a bare `client.subscribe(..).with_id(..)`
  or `client.unsubscribe(..)` fails a guard test. A resume that replaced `mostro-dm` offline
  used to leave the session deaf to daemon messages. Rules and log signatures: `docs/RELAYS.md`.
- **Nothing relay-bound may sit in front of `subscribe_orders()` in `on_pool_online`.** The
  capability fetch (Kind 38385) used to, and one relay slow to answer kept the book empty for
  8 s of a cold start (`fetch_events` waits for EOSE from **every** relay). The book subscribes
  first; the fetch reads the replaceable event through `nostr::first_answer::newest_answer`
  (first copy + a short grace) instead. The price of that order: the node's history can replay
  before the capabilities are known, so a receive-path reader of them must wait — today only a
  fresh payout claim's deadline, via `bond_policy::get_for_once_settled`, and whoever opens
  subscriptions ahead of a capability fetch holds a `bond_policy::fetch_pending()` guard.
- **A new identity starts from zero — and every new store must say which side it is on.**
  `delete_identity` (generate *and* import go through it) wipes what the identity produced:
  rows via `Storage::clear_identity_data`, Rust's in-memory stores via `forget_identity_state`,
  relay subscriptions via `release_identity_subscriptions`, and the Dart caches via
  `resetIdentityScopedState` (issue #533). Device preferences stay (relays, node choice,
  push token, overrides). Anything new that holds per-trade or per-identity data — a table, a
  `settings` key family (add its prefix to `IDENTITY_SCOPED_PREFIXES`), a process-wide store,
  a non-`autoDispose` provider — must be added to the matching one, or it leaks into the next
  user's session. The stores are process-wide and tests run in parallel, which is why the
  identity lifecycle test exercises `delete_identity_inner` with injected doubles (#553).
- **`OrderInfo::created_at` is when the order was created, not the event's time.** It comes from
  the NIP-69 `created_at` tag (mostro#971), capped at the event's time and falling back to it on
  older nodes. The event's own `created_at` moves on every revision of the addressable event, so
  anything that must pick the **newest revision** has to read the event, not the order —
  `node_stats::dedup_latest` carries it alongside as `Revision`.
- **Order book is sourced only from daemon Kind 38383 events.** `create_order` waits for daemon
  confirmation; on timeout it returns an error and **persists nothing** (no phantom order).
- **The Kind 38383 `s` tag is never a trade's status.** It is NIP-69's four-bucket public view
  (`pending`, `in-progress`, `success`, `canceled`), and the daemon stops publishing once the
  trade turns private — `active`/`fiat-sent`/`dispute` never reach the wire. So `InProgress`
  means "taken, real state unknown", and a trade's status comes from daemon messages only
  (`wire_status_applies` guards both ingest paths). Treating it as `Active` offers actions the
  daemon rejects with `CantDo` (#203).
- **Bond statuses never reach the wire book.** `WaitingTakerBond` publishes as `pending` (the
  order stays takeable by others until a bond locks) and `WaitingMakerBond` publishes nothing
  (the order is invisible until the maker's bond locks). Both exist only on the local trade row,
  learned from daemon messages. Never derive them from Kind 38383, and never read a `pending`
  book entry as "nobody is paying a bond on it" (`docs/ANTI_ABUSE_BOND.md` §2.7–2.8).
- **Bond payout claims are independent of trades.** A `BondClaim` lives in its own
  `bond_claims` store keyed `node:order`. It outlives the trade row (completed, canceled or
  wiped) and is always submitted to the node that issued it, even after a node switch: the
  kind-14 filter keeps that node as an author while a claim is open, and for its claim window
  plus a 15-day margin after the user switches away. Don't look a claim up through a trade, and don't delete one
  with it (§6.4).
- **Push cannot carry bond events.** The push server only sees kind 14 p-tagged to a trade
  pubkey and sends a content-free wake-up, so no payload can name `add-bond-invoice` or
  `bond-payout-completed`. Bond notices are in-app, from the kind-14 subscription (§8.5).
- **A push is a doorbell, never a courier** (`docs/PUSH_NOTIFICATIONS.md`). It carries a fixed
  title and `data.type ∈ { trade_update, chat_wake }` — no event id, order or sender — so
  nothing may route or decide on payload fields beyond `type`. What the wake was about comes
  from `resync()` and the in-app cards.
- **Push registration is Rust-owned and persisted.** Dart hands over the device token
  (`set_push_token`); `rust/src/api/push.rs` decides which trade pubkeys the server holds it
  for, persisted in `push_registrations`, so a restart, token refresh or opt-out acts on the
  full set. Dart never chooses, holds or edits that set. The one Dart path that POSTs
  `/api/register` is the OS-scheduled refresh (`push_refresh_job.dart`, T1.5): it replays
  exactly what Rust mirrored to `push_mirror.json`, without the core, so registrations outlive
  the server's 48 h TTL while the app stays closed. Keep it — it is required, not a violation.
- **The FCM background handler is display-only.** `push_background_handler.dart` never touches
  the Rust core, the database or protocol state (a test reads its imports); it sets
  `push_wake_pending` and may show the content-free chat-wake notice. Every write happens on
  resume, once, in the foreground core.
- **Trade screens are pushed, not polled — so every trade write must ring.** Rust's
  `api::trade_touch::touch_trade(order_id)` is the doorbell behind `tradeStatusProvider`, the
  invoice providers (`trade_state_provider.dart`) and the trade list (`rawTradesProvider`, which
  coalesces a burst into one read — a restore files its replayed history with touches only): it says "read this order again", carries no
  status and drives no notice — that is `TradeUpdate`'s job, and the two are separate on purpose
  (a Kind 38383 update changes what a screen shows without being a lifecycle step). The
  providers re-read on a touch and otherwise only every 30 s, so a new code path that writes a
  trade row or sets a book entry's status **without** going through `sync_trade_fields_if_changed`,
  `wipe_trade_row`, the save helper, `update_order_status` or `emit_trade_update*` must call
  `touch_trade` itself, or the screen lags by up to the safety interval. Never take a status
  from a pushed payload: a history replay re-emits old transitions (#474) — read it back.
- **Dispute chat must wake, and does not yet.** Same envelope and same mechanism as peer chat:
  it is `p`-tagged to `pub(K_conv)`, which the push server cannot match, so the **sender** calls
  `/api/notify`. For a solver's message the sender is mostrix, which does not yet
  (mostrix#177). Don't make `wake_peer` ring the solver (not a push client), and don't register
  `pub(K_conv)` with the push server as a workaround (§7.3 says why).

<!-- MANUAL ADDITIONS END -->
