# Status Report — MostroP2P/app (v2)

**Date:** 2026-07-07
**Audited branch:** `claude/project-audit-report-em9bjq`
**Method:** every issue verified against the actual source code (Rust `rust/` + Flutter `lib/`), with `file:line` evidence. The issue text was not taken at face value; everything was confirmed against the current code.

---

## Executive summary

- **48 issues** total: 3 closed (fixed) + 45 open.
- Of the 45 open: **~31 NOT implemented**, **7 partial**, **2 are manual QA/a11y chores** (not features), and **1 (#163) appears already resolved** in the code despite still being open.
- **Core trading flow is implemented and solid.** What's missing is mostly **infrastructure (no CI/CD/tests), half-wired features, and parity with the v1 app**.

**Legend:** ✅ implemented · ⚠️ partial · ❌ not implemented · 🔧 manual chore (not a feature)

---

## ✅ What IS implemented

The protocol core and trading flow work. Confirmed by the 3 closed issues and the code structure:

- **Transport v2** (NIP-44 / signed Kind 14 to the daemon; NIP-59 Gift Wrap for peer chat) — issue **#101 closed**.
- **Full order flow**: create / take / fiat-sent / release, with hold invoices.
- **Real-time order book** (Kind 38383) with currency/payment-method/rating/premium filters.
- **Range-price orders** — the code already renders `min – max` (see note on #163 below).
- **Mostro node switching (single-node)** — bug **#158 closed**: persists, rehydrates at startup, and refreshes subscriptions (`set_active_mostro_node`).
- **Phantom orders after timeout** — bug **#157 closed**: the order book is no longer contaminated by local-only orders.
- **Mnemonic identity** (BIP-39/32, NIP-06), secure storage, **NWC**, manual relay management, **PoW (NIP-13)**, About screen, peer-to-peer chat, counterpart rating.
- **Blossom (encrypted attachments) on native**: upload/download with signed Kind-24242 auth — works on native (`reqwest`).

---

## ❌ What is NOT implemented (by milestone)

### M2 — Infrastructure / CI (entirely absent)

| # | Topic | Status | Evidence |
|---|-------|--------|----------|
| #151 | CI (cargo build/test/clippy + flutter analyze/test) | ❌ | **No `.github/` directory at all** |
| #152 | Flutter test base | ❌ | Only the default `widget_test.dart` |
| #153 | Rust E2E tests | ❌ | No `rust/tests/`; only inline unit tests |
| #154 | WASM build + smoke test in CI | ❌ | No CI |
| #155 | Issue/PR templates + CONTRIBUTING.md | ❌ | None exist |
| #156 | Zapstore manifest | ❌ | No `zapstore.yaml` |
| #118 | Release pipeline (APK/iOS/web/desktop) | ❌ | No workflows |
| #119 | Mutation testing | ❌ | No config |

> **The repo has zero CI/CD infrastructure.** The README claims "all CI checks must pass," but that gate does not exist.

### M3 — Protocol gaps

| # | Topic | Status | Evidence |
|---|-------|--------|----------|
| #144 | Central subscription manager + `request_id` tracking | ❌ | Ad-hoc subscriptions; `orders.rs:1141` passes `request_id = None` |
| #145 | Anti-abuse bond (epic) | ❌ | Zero support; `orders.rs:1575` marks it "out of scope" |
| #146 | Relay discovery from the node's info event | ❌ | `config.rs:9` still hardcodes `DEFAULT_RELAYS` |
| #147 | Background service to keep subs alive + silent-push wake | ❌ | FCM scaffolding only; the handler just `debugPrint`s |
| #148 | Timeout detection + session cleanup | ⚠️ | `cleanup_stale_sessions()` (`session.rs:151`) exists but has **no callers** (dead code) |
| #149 | Relay health monitor (latency/reconnect) | ⚠️ | Has status/last_error, but **no RTT and no reconnect counter**; `last_error` is never populated |
| #150 | Blossom HTTP client for WASM/web | ⚠️ | Native complete; WASM branches return `Err("NotImplemented")` (`blossom.rs:117,214`) |

### M4 — Half-wired features (Rust ready, Dart not connected)

| # | Topic | Status | Evidence |
|---|-------|--------|----------|
| #138 | Inbound admin (dispute) chat routing Kind 1059 | ❌ | Derives `adminSharedKey` (`disputes.rs:250`) but nothing subscribes with it |
| #139 | Trade/User Info panels with real data | ❌ | Placeholder dashes (`info_panels.dart:63-197`); ECDH shared key not wired |
| #140 | Encrypted-attachments UI (picker→send_file→decrypt) | ❌ | Stubs; "progress" is a fake `Future.delayed` |
| #141 | Migrate `backup_confirmed` from SharedPreferences to Rust | ❌ | Still in Dart SharedPreferences (`backup_reminder_provider.dart`) |
| #142 | Restore sessions/trades from mnemonic | ❌ | No `lib/features/restore/` module |
| #143 | Wire dispute system end-to-end (list + admin chat) | ⚠️ | List always empty; send/attach are "coming soon" stubs |

### M5 — Multi-node & discovery

| # | Topic | Status | Evidence |
|---|-------|--------|----------|
| #135 | Multi-node management (community list, avatar, trusted badge) | ⚠️ | Only paste-a-pubkey (`mostro_node_selector.dart`); no node list or avatars |
| #136 | Community discovery + selector | ❌ | No `lib/features/community/` |
| #137 | Deep link handler for `mostro:` scheme | ❌ | Only push-tap routing, not the URI scheme; `app_links` not in deps |

### M6 — UX / v1 parity

| # | Topic | Status | Evidence |
|---|-------|--------|----------|
| #162 | Incomplete/inconsistent i18n | ⚠️ | EN=316 keys vs ES/FR/DE/IT=296; many hardcoded English strings |
| #163 | Range price shown as a single amount | ✅ | **Appears already resolved** — code renders `min – max` (see note) |
| #124 | Global offline banner | ❌ | `_watchConnectionState` (`main.dart:182`) only `debugPrint`s in debug |
| #125 | Context-aware cooperative-cancel UX | ❌ | Terminal status only, no Accept/Decline buttons |
| #126 | In-app snackbar for incoming messages outside chat | ❌ | Only an unread badge |
| #127 | "Days of use" filter (maker account age) | ❌ | Not present in `order_filter.dart` |
| #128 | LN address validation + LNURL resolution | ⚠️ | Only a `name@domain` check; no LNURL-pay resolution |
| #129 | Logs screen filters by level and tag | ❌ | Flat list, no filters (`log_report_screen.dart`) |
| #130 | Encrypted images: compression/thumbnail/preview | ❌ | Stub |
| #131 | Configurable history retention | ❌ | Does not exist |
| #132 | Persist custom payment methods as suggestions | ❌ | Per-order only, in memory |
| #133 | Real VAPID key for Web Push | ❌ | Still the literal placeholder `'YOUR_VAPID_KEY'` (`push_notification_service.dart:64`) |
| #134 | CONTACT/CANCEL/OPEN-DISPUTE as visible buttons in Trade Detail | ❌ | Hidden in the ⋮ menu (`trade_detail_screen.dart:548`) |

### M7 — Refactors / docs

| # | Topic | Status | Evidence |
|---|-------|--------|----------|
| #120 | Split `orders.rs` | ❌ | Grew to **2393 LOC**, still monolithic |
| #121 | Split `trade_detail_screen.dart` | ❌ | Still 1155 LOC |
| #122 | Sync `tasks.md` for specs 004/005 | ❌ | All 12 tasks in 005 still `[ ]` despite being merged |
| #123 | README: list supported NIPs and BUDs | ⚠️ | Mentioned in prose; the explicit list (NIP-47/17/40, BUDs) is missing |

### M8 — Product / security / a11y · M9

| # | Topic | Status | Evidence |
|---|-------|--------|----------|
| #114 | Migrate per-trade UI state from polling to push stream | ❌ | Still polls every 1–2s; `on_trade_updated` doesn't exist (the Dart `onTradeUpdated` is dead) |
| #115 | Optional biometric auth | ❌ | `local_auth` isn't even in `pubspec.yaml` |
| #116 | Light-theme visual QA | 🔧 | Manual chore — light theme is wired |
| #117 | Accessibility audit | 🔧 | Incremental chore — `Semantics(` in 10 widgets |

---

## Important note on #163 (range price)

The issue and the README say a `20-60 USD` range shows as `20 USD`, but **in the current code `OrderItem.displayAmount` already renders `min – max`** (`home_order_providers.dart:104-109`), the model carries `fiatAmountMin/Max`, and Rust parses the range from the `fa` tag (`order_events.rs:64,121`). Both the card (`order_list_item.dart:129`) and the detail strip (`trade_detail_screen.dart:644`) use `displayAmount`. **It appears already fixed** — a quick visual check in the app is recommended before closing it, since a specific case (e.g. detail vs. card) might still fail.

---

## Closed issues (already resolved)

| # | Topic | Status |
|---|-------|--------|
| #101 | Migrate gift-wrap transport to mostro-core (wrap/unwrap/validate_response) | ✅ Closed |
| #157 | Phantom orders after timeout / late CantDo from daemon | ✅ Closed |
| #158 | Mostro node change didn't persist / rehydrate / refresh subs | ✅ Closed |

---

## Suggested priorities

1. **Credibility unblocker:** M2 (#151, #152, #153) — no CI and no tests; the biggest structural risk.
2. **"Almost done" features (high ROI):** M4 (#138–#143) — the Rust already exists, only Dart wiring is missing. Disputes (#143/#138) and attachments (#140) are the most visible.
3. **Critical UX parity:** #142 (restore from mnemonic, blocks the v1→v2 migration), #134 (visible action buttons), #162 (i18n).
4. **Verify and close #163** if the visual review confirms it already works.
