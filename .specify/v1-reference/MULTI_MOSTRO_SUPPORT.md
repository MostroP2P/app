# Multi-Mostro Instance Support

> **v1 Reference.** Consolidates three v1 docs into a single reference for the v2
> migration: `MULTI_MOSTRO_SUPPORT.md` (node registry + selector), `COMMUNITY_DISCOVERY.md`
> (first-launch community selector), and `DEEP_LINK_MOSTRO_SWITCH.md` (switch via deep link).
> Reorganized by topic; v1 development-process detail (phase status, "files created"
> lists, test-count tables, full localization-key inventories) is omitted.

## Overview

Multi-Mostro support lets a single app installation connect to multiple Mostro
instances (nodes). Users switch between **trusted** (hardcoded) and **custom**
(user-added) nodes, each with its own order book and trading sessions.

A "community" and a "Mostro node" are the **same entity** seen two ways: the node
registry tracks the pubkey and connection concerns, while the community view adds
rich metadata (region, avatar, description, accepted currencies, fee, sats range,
social links) fetched from Nostr. In v1 this is made explicit by deriving the node
registry from the community config (see [Trusted Communities](#trusted-communities)).

There are three entry points for choosing/switching the active node:
1. **First-launch community selector** (onboarding, after the walkthrough).
2. **Settings node selector** (Mostro card → bottom sheet).
3. **Deep link** carrying `mostro=<pubkey>` (confirmation dialog, then switch).

All three converge on the same mutation: `SettingsNotifier.updateMostroInstance()`.

## Core Architecture

### Single Source of Truth

`Settings.mostroPublicKey` is the single source of truth for which node is active.
All downstream systems (relay sync, subscriptions, order management) react to changes
in this field via Riverpod. The node registry and selectors only ever **write** to it
through `updateMostroInstance()`.

### Node Registry

The app maintains a registry of known nodes, each identified by its Nostr hex pubkey:

- **Trusted nodes**: hardcoded in `Config.trustedMostroNodes`, cannot be removed.
- **Custom nodes**: added by users, persisted in SharedPreferences, can be removed.

### Data Flow

```text
Config.trustedMostroNodes ──┐
                             ├──▶ MostroNodesNotifier ──▶ UI (Node / Community Selector)
SharedPreferences (custom) ──┘           │
                                         │ selectNode()
                                         ▼
                               SettingsNotifier.updateMostroInstance()
                                         │
                                         ▼
                               Settings.mostroPublicKey changes
                                         │
                              ┌──────────┼──────────┐
                              ▼          ▼          ▼
                         RelaysNotifier  NostrService  SubscriptionManager
                         (relay sync)   (reconnect)    (resubscribe)
```

### Relay Management Per Node

Relay lists are **not** stored per-node. Relay state is always derived from the
currently active node:

- When the active node changes via `updateMostroInstance()`, blacklisted relays and
  user relays are reset (avoids cross-instance bleed).
- `RelaysNotifier` subscribes to the active node's kind 10002 events and syncs the
  relay list in real time (see [RELAY_SYNC_IMPLEMENTATION.md](./RELAY_SYNC_IMPLEMENTATION.md)).
- Default relays from `Config.nostrRelays` serve as a fallback for any node.

## Trusted Communities

Mirrored from [mostro.community](https://github.com/MostroP2P/community), defined in
`lib/core/config/communities.dart`:

| Region | Pubkey (truncated) | Social |
|--------|-------------------|--------|
| Cuba | `00000235a3e9...1366a` | [Telegram](https://t.me/Cuba_Bitcoin), [Website](https://cubabitcoin.org/kmbalache/) |
| Spain | `0000cc02101e...36b40` | [Telegram](https://t.me/nostromostro) |
| Colombia | `00000978acc5...8441b` | [Telegram](https://t.me/ColombiaP2P), [X](https://x.com/ColombiaP2P) |
| Bolivia | `00007cb3305f...3f91` | [Telegram](https://t.me/btcxbolivia), [X](https://x.com/btcxbolivia), [Instagram](https://www.instagram.com/btcxbolivia) |
| Default | `82fa8cb978b4...8390` | (fallback when user skips) |

**Single source of truth:** `Config.trustedMostroNodes` is **derived from**
`trustedCommunities` at runtime, eliminating duplication between the node system and
the community config. `MostroNodesNotifier` initializes from this list, so all
communities also appear as trusted nodes in the Settings node selector.

## Metadata Fetching

Two metadata layers enrich each node:

- **Kind 0** (Nostr profile): name, about, picture.
- **Kind 38385** (Mostro trade info): accepted currencies, fee, min/max order amount.

### Sources

There are two fetch paths in v1:

- **`MostroNodesNotifier.fetchAllNodeMetadata()` / `fetchNodeMetadata()`** — used by
  the Settings node selector. Fetches kind 0 only, via the app's `NostrService`
  (`fetchEvents(filter)` one-shot with timeout). Triggered fire-and-forget after
  `init()` via `unawaited()`, so it never blocks startup.
- **`CommunityRepository.fetchCommunityMetadata(pubkeys)`** — used by the first-launch
  community selector. Fetches kind 0 **and** kind 38385, via a standalone `dart:io`
  WebSocket independent of `NostrService` (so it works before full app init).
  Connection: `wss://relay.mostro.network`; timeout 10s; partial data is acceptable.

### Subscriptions (CommunityRepository)

Two concurrent REQ messages on a single WebSocket; waits for both EOSE (or timeout),
then closes:

```json
["REQ", "<subId>", {"kinds": [0], "authors": ["<pubkey1>", "<pubkey2>", ...]}]
["REQ", "<subId>", {"kinds": [38385], "authors": ["<pubkey1>", ...], "#y": ["mostro"]}]
```

### Extracted Fields

| Kind | Field / Tag | Usage |
|------|-------------|-------|
| 0 | `name` | Display name (fallback: region from config) |
| 0 | `about` | Description text on card |
| 0 | `picture` | Avatar (HTTPS only, `NymAvatar` fallback) |
| 38385 | `fiat_currencies_accepted` | Comma-separated currency codes shown as tags |
| 38385 | `fee` | Trading fee percentage |
| 38385 | `min_order_amount` | Minimum order in sats |
| 38385 | `max_order_amount` | Maximum order in sats |

### Validation & Resilience

- **Deduplication**: for each kind, keep only the event with the highest `created_at`
  per pubkey (handles multiple relays returning the same event). `limit: 1` is a relay
  hint, not a guarantee, so single-node fetch deduplicates too.
- **Signature verification**: `event.isVerified()` is checked before applying metadata;
  forged events with invalid signatures are logged and skipped.
- **URL sanitization**: `picture` and `website` accept only `https://` URLs;
  `javascript:`, `http://`, `data:`, etc. are rejected (set to `null`).
- **Mounted guard**: fetch methods check `mounted` after the async gap.
- **All errors caught and logged**, never propagated; malformed/missing metadata skipped.

### "All Currencies" Logic

When a kind 38385 event exists (`hasTradeInfo = true`) but `fiat_currencies_accepted`
is empty/absent, the card shows a localized **"All currencies"** tag, mirroring
[mostro.community](https://mostro.community).

## Entry Point 1: First-Launch Community Selector

New users choose a community on first launch, before reaching home. Existing users are
never interrupted — the selector is shown only once after the walkthrough.

### User Flow

```text
New user:       App install ─▶ Walkthrough (complete or skip) ─▶ Community Selector ─▶ Home
Existing user:  App launch   ─▶ Home (auto-migrated, no interruption)
Return later:   Home ─▶ Settings ─▶ Mostro Card ─▶ Node Selector (Entry Point 2)
```

### GoRouter Redirect Chain

In `lib/core/app_routes.dart`, the redirect evaluates two providers in order:

```text
1. firstRunProvider:
   - loading / isFirstRun=true  -> redirect to /walkthrough
   - isFirstRun=false           -> proceed to step 2

2. communitySelectedProvider:
   - loading        -> no redirect (wait; router refreshes on change)
   - data(false)    -> redirect to /community_selector
   - data(true)     -> proceed to requested route
   - error          -> no redirect (don't block on errors)
```

`WalkthroughScreen._onIntroEnd()` navigates to `/community_selector` instead of `/`;
the redirect handles the rest.

### Screen Layout

```text
+-----------------------------+
|  bolt  Choose your community |  <- Title with bolt icon
|  [search] Search...          |  <- Filters by name, region, currency, about
|                               |
|  +-------------------------+  |
|  | Avatar  Name      check |  |  <- CommunityCard (selected state)
|  | Region                   |  |
|  | Description text...      |  |
|  | [USD] [EUR] [CUP]       |  |  <- Currency tags (or "All currencies")
|  | % Fee 1.0%  | Range ... |  |  <- Fee and sats range
|  | tg  x  ig               |  |  <- Social link icons
|  +-------------------------+  |
|  [more cards...]              |
|                               |
|  gear  Use a custom node      |  <- Opens AddCustomNodeDialog
|  [========= Done =========]  |  <- Confirm (visible after selection)
|       Skip for now            |  <- Uses defaultMostroPubkey
+-----------------------------+
```

### States

| State | Behavior |
|-------|----------|
| Loading | Skeleton placeholders (same count as `trustedCommunities`) |
| Error | Cloud-off icon + message + retry (invalidates `communityListProvider`) |
| Data (empty search) | "No communities found" |
| Data | Scrollable list of `CommunityCard` widgets |
| Selecting | Spinner on confirm button, interactions disabled |

### Selection Flow

```dart
_selectAndProceed(pubkey):
  1. _ensureNodeExists(pubkey)    // Add as custom node if unknown (awaited)
  2. nodesNotifier.selectNode()   // -> settingsNotifier.updateMostroInstance()
  3. markCommunitySelected()      // Persist to SharedPreferences
  4. context.go('/')              // Navigate home (if still mounted)
```

- **Skip**: same as confirm but uses `defaultMostroPubkey`.
- **Use custom node**: opens `AddCustomNodeDialog`; if a node was added (detected via
  set-diff on pubkeys), auto-selects it and proceeds.

### CommunityCard

`StatelessWidget` with conditional sections: header (avatar + name + region + check),
about (3 lines, ellipsis), currency tags (or "All currencies"), stats (fee % + sats
range formatted K/M), social icons (Telegram, X, Instagram, …). `AnimatedContainer`
(200ms) for selection state; selected = green border + tint + check icon. Uses
`AppTheme` constants.

### Auto-Migration (existing users)

`CommunitySelectedNotifier._init()`:

1. If `communitySelected` is already `true` -> done.
2. Else if `firstRunComplete` is `true` (user onboarded before this feature existed)
   -> auto-set `communitySelected = true`, skip the selector.
3. Else -> `false` (new user, show selector).

## Entry Point 2: Settings Node Selector

From the Settings **Mostro** card (see [SETTINGS_SCREEN.md](./SETTINGS_SCREEN.md)),
tapping opens `MostroNodeSelector.show(context)` — a bottom sheet listing trusted and
custom nodes.

- Each item: avatar (kind 0 picture or `NymAvatar` fallback), display name, truncated
  pubkey, trusted badge, checkmark for the active node, delete for custom nodes.
- **Add Custom Node** button opens `AddCustomNodeDialog`: accepts hex (64 chars) or
  `npub1…` (auto-converted via `NostrUtils.decodeBech32()`), optional name, inline
  duplicate + format validation. Fire-and-forget metadata fetch after a successful add.
- **`_isSwitching` flag** disables all items + the add button during a switch; the sheet
  closes on completion. Switching triggers session restore (consistent with the prior
  text-field behavior).
- **Cannot delete the active node** (shows a SnackBar); custom-node deletion uses a
  confirmation dialog (consistent with relay deletion).

## Entry Point 3: Deep-Link Instance Switch

When a deep link carries a `mostro=<pubkey>` identifying a different instance than the
current one, the app confirms before switching.

### Format

```text
mostro:<order-id>?relays=<relay1>,<relay2>&mostro=<mostro_pubkey>
```

The `mostro` parameter is optional (backward compatible). When absent, the order is
assumed to belong to the currently selected instance.

### Flow

1. App receives the `mostro:` deep link.
2. `parseMostroUrl` (`nostr_utils.dart`) extracts `orderId`, `relays`, optional `mostroPubkey`.
3. `DeepLinkHandler` compares `mostroPubkey` with `settings.mostroPublicKey`.
4. Same (or absent) -> navigate directly to the order (existing behavior).
5. Different -> show confirmation dialog.
6. Confirm -> `updateMostroInstance(newPubkey)` then navigate.
7. Cancel -> do nothing.

## Model Reference

### MostroNode

```dart
class MostroNode {
  final String pubkey;       // Nostr hex public key (node identity)
  String? name;              // From kind 0 or user-provided
  String? picture;           // From kind 0 metadata
  String? website;           // From kind 0 metadata
  String? about;             // From kind 0 metadata
  final bool isTrusted;      // true = hardcoded, false = custom
  final DateTime? addedAt;   // null for trusted, timestamp for custom
}
```

Equality is based on `pubkey` only. `withMetadata()` supports a `MostroNode.clear`
sentinel to explicitly null a field, while omitting a field preserves the existing value.

### MostroNodesNotifier API

```dart
// Lifecycle
Future<void> init();                                        // Load trusted + custom; auto-import unrecognized active pubkey

// Selection
MostroNode? get selectedNode;                               // Active node from settings
Future<void> selectNode(String pubkey);                     // Switch active node via SettingsNotifier

// CRUD (custom nodes only)
Future<bool> addCustomNode(String pubkey, {String? name});  // Validate (64-hex, no duplicates)
Future<bool> removeCustomNode(String pubkey);               // Remove non-active, non-trusted node
Future<bool> updateCustomNodeName(String pubkey, String newName);

// Metadata (persisted for both custom and trusted nodes)
void updateNodeMetadata(String pubkey, {String? name, ...});
Future<void> fetchAllNodeMetadata();                        // Batch kind 0 (dedup, verify, sanitize)
Future<void> fetchNodeMetadata(String pubkey);              // Single-node kind 0

// Queries
bool isTrustedNode(String pubkey);
List<MostroNode> get trustedNodes;
List<MostroNode> get customNodes;
```

All write operations return `false` on persistence failure **without** updating
in-memory state (persist-before-state pattern → memory never diverges from disk).

### Storage

| Data | Location | Key |
|------|----------|-----|
| Trusted nodes | `Config.trustedMostroNodes` (hardcoded, derived from communities) | N/A |
| Custom nodes | SharedPreferences | `mostro_custom_nodes` |
| Active node | Settings (SharedPreferences) | `mostroPublicKey` |
| Trusted node metadata | SharedPreferences | `trusted_node_metadata` |
| Custom node metadata | within custom nodes JSON | `mostro_custom_nodes` |
| Community selected (onboarding) | SharedPreferences | `community_selected` |

## Error Handling Strategy

The notifier is **resilient** — persistence failures are logged but never crash the app:

| Method | On error | Behavior |
|--------|----------|----------|
| `_loadCustomNodes()` | Returns `[]` | Degrade to trusted-only nodes |
| `_saveCustomNodes()` | Returns `false` | Callers check result before updating state |
| `addCustomNode()` | Returns `false` | Node not added to memory if disk save fails |
| `removeCustomNode()` | Returns `false` | Node stays in memory if disk save fails |
| `updateCustomNodeName()` | Returns `false` | Name unchanged if disk save fails |
| `init()` auto-import save | Ignored | Imported node lives for the session, won't persist |

## Backward Compatibility

1. **Existing users**: a saved `mostroPublicKey` keeps working. If it matches a trusted
   node it's recognized; if it's a valid 64-char hex not matching any trusted node it's
   auto-imported as a custom node; malformed pubkeys are silently skipped.
2. **Environment variable**: `MOSTRO_PUB_KEY` override still works via `Config.mostroPubKey`.
3. **No migration needed**: the system is additive — no existing data is modified/removed.
4. **Settings model unchanged**: `Settings.mostroPublicKey` stays the single source of truth.
5. **Community auto-migration**: users who upgrade from a version without community
   discovery are never shown the first-launch selector (see
   [Auto-Migration](#auto-migration-existing-users)).

## Implementation Note: Subscription Idempotency

`MostroService.init()` cancels its existing orders subscription
(`_ordersSubscription?.cancel()`) at the start, to prevent subscription leaks when
re-invoked from `LifecycleManager.onResumed()`. Relevant to v2: any re-entrant
init/resume path on the relay/subscription layer must be idempotent.

## Out of Scope (v1)

- Decentralized community discovery via a dedicated NIP.
- Real-time updates when a community changes its kind 38385.
- User-created communities (curated list only).
- A dedicated Settings community section (reuses the existing Mostro node selector).
