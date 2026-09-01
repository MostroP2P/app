# Performance & Scalability Optimization Plan

**Goal:** the app must ingest and display thousands of pending orders and serve hundreds of
thousands of users with zero friction. Stated budget (specs/004 plan.md): cold start < 2 s,
order book load < 3 s, 60 fps on mid-range mobile.

**Method:** the plan is split into phases. Every numbered item is one **atomic PR** — small,
self-contained, independently reviewable. Early phases are easy wins with **no prerequisites**;
later phases are structural changes that build on them. Each item lists the evidence
(file:line as of `main` @ 9465974), the fix, and how to verify it.

**Root cause found (context for the whole plan):** the order book lives in
`Arc<RwLock<Vec<OrderInfo>>>` (`rust/src/api/orders.rs:172-176`) and **every mutation clones
the entire vector and broadcasts it as a full snapshot** over the FRB bridge
(`orders.rs:209-219`). Bulk refetch ingests events one by one (`orders.rs:2745-2758`), so a
cold start with N orders does **O(N²)** clones and N full-book bridge emissions. On the Dart
side, `orderBookProvider` re-materializes every `OrderItem` per emission
(`lib/features/home/providers/home_order_providers.dart:144-163`) and `filteredOrdersProvider`
re-filters and re-sorts everything (`:165-219`). Meanwhile, per-trade 2-second polling loops
(`lib/features/order/providers/trade_state_provider.dart`) run underneath from the bottom nav
bar on every screen. Phases 1–2 remove constant per-event costs; Phase 3 replaces the
snapshot pipeline with deltas (the big lever); Phases 4–5 add persistence, web parity, and
regression protection.

---

## Phase 1 — Quick wins (no prerequisites, hours each)

Independent one-to-few-line fixes. Land in any order.

> **Status: implemented.** PRs #349, #350, #351, #352, #353, #355, #356, #357, #358.
> **#354 (PR 1.6) was opened and then closed** after review showed the bound it added could
> silently truncate the order book while protecting against nothing — see the entry below.
> Two items were withdrawn after measurement rather than implemented — PR 1.10 entirely, and
> parts of 1.5 and 1.11. Each says why, in place. A plan item that turns out to be wrong is
> worth recording as loudly as one that ships, so nobody re-proposes it from the same static
> reading that produced it.

### PR 1.1 — Demote hot-path logging `fix(perf)`
- **Evidence:** `log::info!` per parsed 38383 event (`rust/src/api/orders.rs:3119-3124`, also
  `:3250`, `:2751`); `log::warn!` per trade-key cache miss (`orders.rs:71`) — misses happen for
  *every* stranger's order. Each record is formatted, secret-scrubbed, mutex-buffered and
  streamed to Dart (`rust/src/api/logging.rs:216-300`). Release default level is `Info`.
- **Fix:** demote per-event logs to `debug!`; log one summary per ingest batch
  ("ingested N orders"). Remove the per-miss `warn!`.
- **Verify:** `cargo test && cargo clippy`; manual: refresh order book, log stream shows one
  summary line instead of thousands.

### PR 1.2 — SQLite indexes for trade lookups `fix(db)`
- **Evidence:** `WHERE json_extract(data,'$.order.id') = ?` with no index —
  `rust/src/db/sqlite.rs:498-511` and 5 more sites (`:513-524`, `:526-542`, `:584-597`,
  `:612-626`, `:631-638`). Called from `local_trade_status` (`orders.rs:2246-2253`) for **every
  non-pending 38383 event**. The denormalized `status` column is also unindexed (used by the
  30-min stale sweep via full `list_trades`).
- **Fix:** migration adding
  `CREATE INDEX idx_trades_order_id ON trades(json_extract(data,'$.order.id'))` (SQLite
  expression index) and `CREATE INDEX idx_trades_status ON trades(status)`.
- **Verify:** `EXPLAIN QUERY PLAN` shows index usage; existing db tests pass.

### PR 1.3 — SQLite connection tuning `fix(db)`
- **Evidence:** `rust/src/db/sqlite.rs:17-22` — pool of 4, but `journal_mode=WAL` /
  `foreign_keys=ON` run once on one connection (`foreign_keys` is per-connection → effectively
  off on 3 of 4). No `synchronous=NORMAL`, so every write fsyncs on mobile flash.
- **Fix:** set pragmas via `SqliteConnectOptions` (applied to every pooled connection); add
  `synchronous=NORMAL`.
- **Verify:** `PRAGMA foreign_keys` returns 1 on all connections in a test; write-heavy test
  timing improves.

### PR 1.4 — O(1) daemon-message dedup `fix(perf)`
- **Evidence:** linear scan of up to 512 hex `String`s under a mutex per kind-14 event
  (`rust/src/api/orders.rs:319-337`, called at `:1249`, `:3043`).
- **Fix:** `HashSet<EventId>` + `VecDeque<EventId>` for eviction order; compare `EventId`
  bytes, not hex strings.
- **Verify:** existing dedup tests; add a unit test for eviction at capacity.

### PR 1.5 — Micro hot-path allocations `fix(perf)`
- **Evidence:** (a) whole `global_dm_keys` `HashMap<String,(Keys,u32)>` cloned per kind-14
  event (`orders.rs:3295`); (b) `lock_order` runs O(n) `retain` over the lock registry on
  every acquisition (`orders.rs:155`).
- **Fix:** (a) resolve the matching key under a short-lived read guard and pass only that
  key on. The guard must **not** be held across the handler: handling a message can reach
  `ensure_global_dm_coverage`, which takes the same lock for writing.
- **Verify:** `cargo test`; no behavior change.
- **(b) withdrawn.** The `retain` is self-limiting: sweeping eagerly is what keeps the
  registry at roughly the number of concurrently-dispatched orders (a handful), so the scan
  runs over a map its own eagerness keeps tiny. Making it periodic trades a tested invariant
  (`the_registry_drops_locks_no_handler_holds`) for no measurable saving, and fails it.

### PR 1.6 — Bound the order-book relay filter `fix(nostr)` — **WITHDRAWN, do not implement**
- **Was implemented as #354, then closed** after review (Codex P1, CodeRabbit Major).
- **The protection was illusory.** `.limit(N)` is a request hint a relay applies to *stored*
  events before EOSE. It bounds nothing after EOSE, and a misbehaving relay — the threat it
  was named for — is not bound by a hint it can ignore.
- **The cost was real.** Both the live subscription and the refetch go through this filter, so
  a relay honouring the limit by returning the newest N truncates the rest: once a node carries
  more than the cap, some pending orders never enter the book and the user sees an incomplete
  market, silently. That is the exact failure this whole effort exists to prevent. A larger N
  only moves the cliff somewhere less tested.
- **`.since()` was never safe either:** order lifetime comes from the daemon's `expiration`
  tag, with no client-side retention policy to derive a cutoff from.
- **If the unbounded replay is to be bounded, it needs pagination or a status-scoped protocol
  query** — and a test with more than N active orders proving completeness.

### PR 1.7 — Surface stream lag instead of swallowing it `fix(observability)`
- **Evidence:** `OrdersStream::next` silently swallows `broadcast::error::RecvError::Lagged`
  (`orders.rs:3506-3508`); channel capacity is 16 (`orders.rs:186`) so a startup burst lags
  every subscriber invisibly. (The trade stream logs it — `orders.rs:3481`.)
- **Fix:** log `Lagged(n)` at warn; raise capacity to 64. (Semantics stay snapshot-safe;
  becomes correctness-critical before Phase 3 deltas land — this PR is a prerequisite there.)
- **Verify:** unit test forcing lag observes the log.

### PR 1.8 — `autoDispose` the derived order providers `fix(ui)`
- **Evidence:** `filteredOrdersProvider` and `orderReasonsProvider` are plain `Provider`s
  (`lib/features/home/providers/home_order_providers.dart:169`,
  `lib/features/home/providers/order_reason_provider.dart:73`) watching the `autoDispose`
  stream — they pin the whole book pipeline alive, so full map+filter+sort runs on every relay
  event even while the user sits in Chat/Settings.
- **Fix:** mark both `.autoDispose`.
- **Verify:** `flutter analyze && flutter test`; DevTools shows the providers dispose when
  leaving Home.

### PR 1.9 — Cheap render wins on the order card `perf(ui)`
- **Evidence:** four `NumberFormat(...)` constructions per card per build
  (`lib/features/home/widgets/order_list_item.dart:62`, `:238`, `:252`, `:281`);
  `_relativeTime` recomputed per build (`:284`); `OrderItem` has no `==`/`hashCode`
  (`home_order_providers.dart:19`) and rows get no `ValueKey`
  (`lib/features/home/screens/home_screen.dart:83-96`) → Flutter can never skip a subtree.
- **Fix:** static per-locale `NumberFormat` cache; add `key: ValueKey(order.id)`.
- **Do NOT precompute `_relativeTime` into `OrderItem`.** It changes as the clock moves even
  when the order does not, so freezing it into immutable item data makes displayed ages go
  stale — and value equality (added in PR 2.7) then actively suppresses the rebuild that would
  have refreshed them. It must stay derived from the current time at render, or move into a
  timer-driven leaf.
- **Known limitation this surfaced (pre-existing, not introduced here):** the card's age text
  only refreshes when the list rebuilds, i.e. on a book emission. On a quiet book the ages
  drift — "5 minutes ago" can sit there considerably longer. True before any of this work and
  unchanged by it; the fix is the timer-driven leaf above, worth its own small PR.
- **Value equality moved to PR 2.7**, where `orderByIdProvider`'s `select` is the caller that
  makes it do something. On its own it saves nothing: Flutter rebuilds a `StatelessWidget`
  whenever its parent does, regardless of field equality.
- **Verify:** `flutter test`; DevTools rebuild counter shows unchanged rows skipped.

### PR 1.10 — Fixed item extent on hot lists `perf(ui)` — **WITHDRAWN, do not implement**
- **Original premise:** order cards are fixed-height by design, so `prototypeItem`/`itemExtent`
  would remove per-scroll layout of unknown-height children. That premise came from the
  skeleton's hard-coded 172 px (`lib/shared/widgets/order_list_skeleton.dart:39`).
- **Measured, and it is false.** Rendering real cards inside a `ListView` at the narrowest
  supported width (320 px) gives **181.1 px** for a plain card but **214.1 px** for an own
  order carrying a reason badge: the pill `Wrap` in `order_list_item.dart:129` drops to a
  second run, exactly as its own comment says it should (shrinking the pills instead
  ellipsized labels on small phones). A fixed extent would clip that card.
- **Outcome:** no change made. The trades list is the other candidate, but it holds a user's
  own trades — tens of rows, not thousands — so no hot list is left to apply this to.
  Revisit only if the card is ever made genuinely uniform, which is a design decision.

### PR 1.11 — Trivial Dart hygiene `chore(ui)`
- **Evidence:** themes rebuilt on every `MostroApp.build` (`lib/core/app.dart:53-54`); three
  un-stored `.listen()` subscriptions in `push_notification_service.dart:79-93` with nothing
  stopping a second `initialize()` from attaching them again.
- **Fix:** memoize both themes in `app_theme.dart` (`ThemeData` is immutable, so every caller
  including the golden harness benefits); guard `initialize()` with its **own** flag —
  `_initialized` cannot be reused, it gates `deleteToken()` and must stay false on the paths
  that bail out early.
- **Verify:** `flutter analyze && flutter test`.
- **`escrowModeProvider` item withdrawn.** Unlike the orders stream, `EscrowModeStream::next`
  returns `Result` and bails on a closed channel (`rust/src/api/escrow.rs:172-182`), so Dart
  sees a thrown error and the loop unwinds — there is no null to check and no hot loop. Its
  non-`autoDispose` lifetime is deliberate: an app-wide capability gate fed by a rare
  wake-up, not a per-screen subscription.

---

## Phase 2 — Targeted fixes (medium effort, still independent)

Each PR stands alone; none requires Phase 3's redesign.

> **Status: implemented.** PRs #360–#369. All independent of each other except
> **PR 2.2 (#361), which is stacked on PR 2.1 (#360)** — it builds on the deferred-upsert
> primitive introduced there, so the "fully independent" claim below is not quite true for
> that pair. Two sub-items were withdrawn after inspection (2.3's `local_trade_status`
> memoization, 2.10's history cap) and two plan premises turned out to be wrong (2.8's
> `_CountdownChip`, and the assumption in 2.9 that keying could reuse the same store). Each
> is recorded in place.

### PR 2.1 — Batch bulk ingest: one broadcast per refetch `fix(perf)`
- **Evidence:** `refetch_active_node_orders` loops `ingest_order_event` per event
  (`orders.rs:2745-2758`); each upsert clones + broadcasts the whole book → **O(N²)** on cold
  start, node switch (`orders.rs:2872`) and every pull-to-refresh (`orders.rs:2720`). With
  2000 orders: ~2M struct clones and ~2000 full-book bridge emissions.
- **Fix:** ingest the batch into the book without broadcasting, then emit **one** snapshot
  (`set_orders`-style) at the end.
- **Verify:** Rust test: N-event refetch produces exactly 1 broadcast; pull-to-refresh with a
  large fixture no longer stalls.
- **Impact:** the single biggest defect fix in the plan. Do this first in Phase 2.

### PR 2.2 — Coalesce live broadcasts (debounce) `perf(bridge)`
- **Evidence:** one relay event ⇒ one full-book clone ⇒ one bridge emission
  (`orders.rs:3111` → `:3216` → `:209-219`). No throttling/batching exists anywhere in the
  bridge path.
- **Fix:** coalesce mutations in a ~200 ms window and emit at most one snapshot per tick
  (skip when nothing changed). Keeps snapshot semantics — safe before deltas exist.
- **Verify:** Rust test: 100 upserts within the window ⇒ 1 emission carrying the final state.

### PR 2.3 — Negative cache for trade-key lookups `perf(ingest)`
- **Evidence:** `get_trade_key_index` at `orders.rs:3137` misses for every stranger's order →
  one SQLite/IndexedDB round trip per relay event (`lookup_trade_key_index`,
  `orders.rs:79-100`); `local_trade_status` (`orders.rs:2246`) adds a second read for
  non-pending events.
- **Fix:** cache negative results for content keys (bounded set, invalidated by
  `store_trade_key_index` — the only absent→present path). Never cache on a read *error*: an
  error is not evidence of absence, and a false negative strands the order as "not ours".
- **Verify:** Rust test: storing a key clears its recorded miss; the miss set stays bounded.
- **`local_trade_status` memoization withdrawn.** That lookup goes through
  `get_trade_by_order_id`, which PR 1.2 gives a real index — a keyed read, not a full scan.
  Re-measure after #350 rather than adding pass-scoped state on spec.

### PR 2.4 — Prune terminal orders; bound the book `fix(memory)`
- **Evidence:** nothing evicts canceled/expired/success orders from the `Vec`
  (`orders.rs:174`; only user-cancel paths remove, `:1113`, `:1483`). Non-pending entries
  inflate every clone and bridge payload forever; Dart filters them out per emission
  (`home_order_providers.dart:177`).
- **Fix:** drop hard-terminal orders (reuse `is_hard_terminal`) and expired-pending on ingest;
  cap total book size defensively.
- **Verify:** Rust test: ingest terminal status ⇒ order leaves the book; long-session memory
  stays flat.

### PR 2.5 — Fix the connection-state resubscribe storm `fix(relay)`
- **Evidence:** `relay_pool.rs:211-214` broadcasts on **any** relay status change even when the
  derived state is unchanged (`Online → Online`); each event drives a 10 s `fetch_events`, an
  outbox flush and full resubscribes (`rust/src/api/nostr.rs:51-69`). One flapping relay at
  the 2 s poll interval (`relay_pool.rs:22`) reproduces this indefinitely.
- **Fix:** only send when the derived `ConnectionState` actually changed; debounce the
  Online handler.
- **Verify:** Rust test with a mock flapping relay: exactly one resubscribe cycle.

### PR 2.6 — Close relay-side subscriptions on task exit `fix(relay)`
- **Evidence:** `subscribe_daemon_messages` (`orders.rs:1203`) and `subscribe_single_order`
  (`orders.rs:2376`) open auto-ID relay subscriptions; the tasks exit after 30-min idle
  (`:1213`, `:2387`) but never `client.unsubscribe(...)`. Relays cap concurrent REQs
  (~10–20); overflow gets `CLOSED` (only logged, `orders.rs:3345-3357`) and can kill the
  order-book subscription itself.
- **Fix:** stable subscription IDs (`order-{id}`) + `unsubscribe` on task exit/timeout.
- **Verify:** Rust test asserting unsubscribe is issued; manual: relay REQ count stays bounded
  across many takes.

### PR 2.7 — Order-by-id index provider; kill O(N) scans in screens `perf(ui)`
- **Evidence:** `trade_detail_screen.dart:542-543` and `take_order_screen.dart:210` do
  `ref.watch(orderBookProvider)` + linear `where` scans of the whole book;
  `trade_state_header.dart:29-49` re-runs on every book emission and falls back to
  `getOrder()`+`listTrades()`.
- **Fix:** add `orderByIdProvider` (family) backed by a `Map<String, OrderItem>` index built
  once per emission; screens watch only their order.
- **Verify:** widget tests; DevTools: detail screens no longer rebuild on unrelated book
  events.

### PR 2.8 — Isolate the 1 Hz countdowns `perf(ui)`
- **Evidence:** `Timer.periodic(1 s) → setState` on the full 1332-line `TradeDetailScreen`
  (`trade_detail_screen.dart:161`) and on `take_order_screen.dart:92`; `_CountdownChip` never
  stops for non-expiring orders (`trade_state_header.dart:262-276`). Both screens also use
  eager `ListView(children:)` (`:571`, `:235`).
- **Fix:** move the remaining duration into a `ValueNotifier` and the countdown block into a
  `ValueListenableBuilder`. In Trade Detail the `showTimer` condition must stop reading the
  ticking value (move the zero check inside the builder), or the screen keeps rebuilding.
- **Verify:** capture the `AppBar` widget instance, pump two ticks, assert it is *identical* —
  Flutter allocates fresh widget objects per build, so a surviving instance proves the screen
  did not rebuild.
- **`_CountdownChip` item withdrawn.** It does not "never stop": it cancels its timer once
  `expiresAt` has passed (`trade_state_header.dart:271-273`). A chip counting down to a future
  deadline ticking once a second is the feature.

### PR 2.9 — Notifications store: keyed records + single transaction `fix(storage)`
- **Evidence:** Sembast `intMapStoreFactory` with lookup-by-`Finder(Filter.equals('id',…))`
  per write (`lib/features/notifications/providers/notifications_provider.dart:80-89`, `:110`)
  → full-store scan per write; `markAllAsRead()` fires N independent saves → O(N²), N
  transactions, un-awaited (`:242-250`); state list grows forever (`:161`).
- **Fix:** key records by notification id under a **new store name**, plus a one-time
  migration; wrap `markAllAsRead` in one `db.transaction`.
- **The migration is the hard part**, and two obvious shortcuts are both wrong: reading an
  int-keyed record through a `StoreRef<String, …>` throws (so an upgrade loses history or
  crashes on open), and pointing both `StoreRef`s at the *same* store name makes the
  migration's cleanup delete the records it just wrote.
- **Verify:** a test that writes through the old int-keyed store and asserts the records
  survive — this is the difference between a perf fix and silent data loss.

### PR 2.10 — Chat-screen hot-path hygiene `perf(chat)`
- **Evidence:** `_messages.any(...)` O(N) dedupe per incoming message
  (`chat_room_screen.dart:145`), full sort at `:87`, `_markRead()` bridge call per message
  (`:148`), autoscroll animation per message (`:161`), unbounded `_messages` (`:48`).
- **Fix:** `Set<String>` of seen ids; debounce `_markRead`; autoscroll only when the reader
  was already pinned to the bottom — and read that position **before** `setState` adds the
  message, or the new message has already extended `maxScrollExtent` and the check always
  says "not at bottom".
- **Verify:** the follow decision extracted as a pure function and tested at its boundaries.
  `ChatRoomScreen` needs `RustLib.init()` and has no harness, so the dedupe and debounce are
  verified by reading — building that harness deserves its own PR.
- **History cap withdrawn.** Chat history is bounded by one trade's lifetime — tens of
  messages. Silently dropping a counterparty's messages from a screen someone may need as a
  record of a trade is a worse failure than the memory it saves. Do it as real pagination.

---

## Phase 3 — Structural: delta pipeline & push-based state (the big lever)

Ordered; 3.2 depends on 3.1, 3.3 on 3.2. Requires PR 1.7 (lag visibility) first.

### PR 3.1 — `feat(core): HashMap order book + delta broadcast type`
- **Evidence:** `Vec` + full-snapshot `broadcast::Sender<Vec<OrderInfo>>`
  (`orders.rs:172-186`); O(n) `find` per upsert (`:211`); a delta model already exists for
  trades (`TradeUpdate {order_id, status}`, `orders.rs:3472`) and is the pattern to copy.
- **Fix:** `HashMap<String, OrderInfo>` book; broadcast
  `enum OrderBookDelta { Upserted(OrderInfo), Removed(String), Snapshot }`. Internal only —
  the existing FRB stream keeps emitting snapshots (built from deltas) so nothing downstream
  changes yet. **Lagged now means "resync via `get_orders`"** — handle it explicitly.
- **A resync needs a boundary, not just a refetch.** `get_orders()` reads the book at some
  instant; a mutation landing between that read and the subscriber resuming is either lost or
  applied out of order. Carry a monotonic revision on the book: the snapshot states the
  revision it was taken at, each delta carries its own, and a subscriber applies only deltas
  newer than its snapshot. Without that, lag recovery silently diverges from the book —
  which is worse than today, where dropping a snapshot is harmless because the next one is
  complete.
- **Verify:** Rust unit tests for upsert/remove, and for a lag→resync that interleaves a
  mutation with the snapshot read.

### PR 3.2 — `feat(bridge): delta stream over FRB`
- **Fix:** new `on_order_deltas()` stream in `rust/src/api/orders.rs` emitting the delta enum;
  `get_orders()` stays as the initial-snapshot call. Run `./scripts/frb-generate.sh`. Keep the
  old snapshot stream one release for fallback, then remove.
- **Verify:** `--check` codegen clean; Dart integration test: initial snapshot + applied
  deltas ≡ Rust book state.

### PR 3.3 — `feat(ui): incremental order state in Dart`
- **Evidence:** full re-map per emission (`home_order_providers.dart:144-163`); full
  re-filter+re-sort (`:165-219`) including per-order `split(',')` set allocations
  (`:196-203`); Rust-side `OrderFilters` + filter/sort (`orders.rs:165-170`, `:235-278`) is
  **dead code** — every caller passes `filters: null`, and the two sides even sort differently
  (Rust: expiry asc; Dart: createdAt desc).
- **Fix:** `orderBookProvider` maintains `Map<String, OrderItem>` and applies deltas;
  `filteredOrdersProvider` updates incrementally (re-evaluate only the changed order except on
  filter changes); precompute the payment-method token set once per `OrderItem`. Decide one
  sort order and delete the dead Rust filter path (or wire it up — decide in review).
- **Verify:** provider unit tests; 3k-order fixture: one incoming event causes O(1) work.

### PR 3.4 — `feat(ui): replace per-trade polling with the push stream`
- **Evidence:** bottom nav (every screen) keeps N infinite 2 s `getOrder()` polls alive
  (`bottom_nav_bar.dart:33` → `trades_providers.dart:237-252` →
  `trade_state_provider.dart:17-52`); pay-invoice screen runs **two** full `listTrades()`
  reads per second (`trade_state_provider.dart:108`, `:130`). A push stream already exists
  (`on_trade_updated`, `orders.rs:3460`).
- **Fix:** derive `tradeStatusProvider`, the nav badge, and the invoice providers from
  `tradeUpdatesProvider`; keep one lazy `getOrder()` for initial value. Delete the polling
  loops.
- **Two blockers to clear first — polling is currently masking both.**
  1. **The stream is lossy and non-replaying.** `TradeUpdatesStream::next` discards `Lagged`
     (`orders.rs:3460-3484`), and a `tokio::broadcast` holds nothing for a subscriber that
     was not listening yet, so updates emitted while no provider is mounted are simply gone.
     A one-shot `getOrder()` closes only the *initial* gap. Make the stream stateful, or
     resync from the book/DB after lag, resume and resubscribe, **before** deleting the polls.
  2. **The payload is too thin for the pay-invoice screen.** `TradeUpdate` carries
     `{order_id, status}`, but `PayLightningInvoiceScreen` needs `TradeInfo.hold_invoice` and
     `TradeInfo.order.amount_sats`. Removing `listTrades()` without widening the payload (or
     adding a reliable `TradeInfo` cache) leaves that screen with no invoice and no amount.
- **Verify:** widget tests; idle bridge-call count on Trades drops to ~0; **plus** a test that
  a status change emitted while the provider is unmounted is still reflected when it remounts.

### PR 3.5 — `feat(core): chat room summaries in one call`
- **Evidence:** rooms hydration does 2 bridge calls per trade in an unbounded `Future.wait`,
  then filters full message history in Dart per room
  (`lib/features/chat/providers/chat_providers.dart:243-256`, `:206`, `:224`).
- **Fix:** Rust `list_chat_rooms()` returning `{trade_id, last_message, unread_count, nym}`
  per room in one bridge call. Regen bindings.
- **Verify:** Rust + widget tests; chat screen open with 100 trades = 1 bridge call.

### PR 3.6 — `fix(relay): bound the global DM filter & key derivation`
- **Evidence:** kind-14 `#p` filter carries one pubkey per lifetime trade and the whole REQ is
  re-sent to all relays on every newly derived key (`orders.rs:2934-2947`, `:2912-2922`);
  `build_trade_key_map` derives keys sequentially, awaiting each (`orders.rs:2981-2997`).
- **Fix (revised after review):** debounce the resubscribes and derive keys concurrently.
  **Do not cap coverage by local trade status.** `specs/004-mostro-p2p-client/contracts/orders.md:267-284`
  requires deriving every known key and rebuilding the filter from the full map, and for good
  reason: after a restore, a database loss, or an incomplete rehydration the client cannot know
  which older keys still belong to live trades until it receives and decrypts their messages.
  Pruning locally makes an older active trade permanently deaf to its status and invoice
  messages — unrecoverably, since nothing later re-adds the key.
- **A real bound needs server-assisted discovery or a resync design**, not local status
  pruning. Until then the filter's size is the cost of correctness.
- **Verify:** Rust test: resubscribes are coalesced under a burst of new keys; coverage still
  includes every known key.

### PR 3.7 — `feat(ui): two-phase startup`
- **Evidence:** `runApp` is blocked by sequential awaits including relay-pool network init
  (`lib/core/app_bootstrap.dart:47-190`, esp. `nostr_api.initialize` at `:160`).
- **Fix:** first frame after `RustLib.init()` + prefs; relay init, identity and DB rehydrate
  move behind a post-first-frame loading state.
- **Verify:** cold-start trace: first frame well under the 2 s budget on a mid-range device.

### PR 3.8 — `perf(bridge): windowed order queries` — **CONDITIONAL, measure first**
- **Why this entry exists:** "infinite scroll" — fetch a page, show a skeleton, fetch the next
  page as the user scrolls — keeps being proposed for the order book, from the same static
  reading each time. Recorded here so the reasoning is not redone.
- **The list is already lazy.** Home renders through `ListView.separated` with an
  `itemBuilder` (`lib/features/home/screens/home_screen.dart:83`): Flutter builds only the
  visible cards plus `cacheExtent` of look-ahead, which is exactly the "prefetch a bit more
  than the viewport" behaviour. The initial skeleton exists too (`home_screen.dart:256`).
  Ten thousand orders in memory do not slow the scroll itself.
- **The network cannot be paged.** The book is one relay subscription on kind 38383 filtered
  by author (`rust/src/api/orders.rs:1227`). Nostr has no offset or cursor; `.limit()` is a
  hint that truncates the market silently (PR 1.6, withdrawn); `since`/`until` windows do
  not work either because the UI filters by currency, payment method and side, and filtering
  needs the whole set. The payload is small anyway — a thousand events is about a megabyte.
- **What actually hurts at 1k orders** is the root cause at the top of this document: full
  `Vec` clones and full-snapshot bridge emissions per mutation, O(N²) bulk ingest, and Dart
  re-mapping, re-filtering and re-sorting the entire book per emission. PR 2.1/2.2 make that
  O(N) and Phase 3 makes it O(1) per event. Paging the list would fix none of it.
- **The one variant that can pay off is paging the bridge, not the relay:** filter and sort
  in Rust, and have Dart hold a window instead of the whole book. That bounds Dart memory
  and per-emission work once the book is tens of thousands of entries. It depends on the
  `HashMap` book (3.1) and the delta stream (3.2), and its natural first step is the
  decision PR 3.3 already forces: the Rust `OrderFilters` path is dead code today — wiring
  it up (rather than deleting it) is what makes a windowed query possible later.
- **The window must be revision-consistent, not positional.** A naive
  `get_orders(filters, offset, limit)` over the live sorted book is wrong: an order arriving,
  expiring or changing rank *before* the offset shifts the boundary, and the next request
  skips or repeats entries. The contract, if this is ever built:
  - `get_orders_window(filters, cursor, limit) -> { revision, items, next_cursor }`. The
    cursor is a **keyset** (sort key + order id of the last item), never an offset, so
    mutations before the window cannot move it. `revision` is the book revision PR 3.1
    already introduces.
  - Dart keeps `(filters, revision, items)` and applies only deltas with a newer revision,
    the same rule as the snapshot/delta resync in 3.1. Per delta: *before* the window — no
    membership change (keyset cursor); *inside* — upsert in place, or evict when the order no
    longer matches the filters or its sort key leaves the window; *after* — ignore until the
    next page is requested. A `Removed` for an unknown id is a no-op.
  - When evictions shrink the window below `limit`, refill by requesting from the current
    `next_cursor`; on a lagged stream, refetch the window from its first cursor and rebase
    on the returned `revision`.
- **Trigger:** implement only if the PR 5.2 large-book widget tests show Dart-side cost
  (memory or per-delta work) at 10k orders after Phase 3 lands. If they do not, this stays
  unimplemented, like 1.6 and 1.10.
- **Verify (if triggered):** Rust tests that a window over the filtered/sorted book matches
  a full filter+sort, and that an insertion, removal and rank change landing *before*,
  *inside* and *after* the window between two page requests yield neither a skipped nor a
  duplicated order across the concatenated pages; Dart tests that scrolling past the window
  requests the next one from `next_cursor`, that a delta inside the window updates in place
  or evicts, that an eviction below `limit` triggers a refill, and that a stale-revision
  delta is dropped.

---

## Phase 4 — Persistence & web parity (most work; depends on Phase 3 shape)

### PR 4.1 — `feat(db): persist the order book for instant cold start`
- **Evidence:** the book is memory-only on all platforms; a dead `orders` table + unused
  `save_order`/`list_orders` already exist (`rust/src/db/sqlite.rs:146-190`, zero callers).
  Every cold start refetches the entire book from relays (10 s timeout path,
  `orders.rs:2732`).
- **Fix:** persist deltas (batched, one transaction per coalesce tick from PR 2.2); on start,
  render from disk immediately and reconcile with the relay refetch. **Design note:** this
  intentionally revisits the "order book is sourced only from daemon events" rule — the relay
  stays the source of truth; disk is a cache. Needs a short design proposal before code
  (repo working agreement).
- **The cache must be keyed by node identity.** `OrderBook::clear()` exists precisely because
  a node switch has to drop the previous node's orders. Rendering a persisted cache before
  reconciliation completes would put them straight back — mixing two nodes' markets in one
  list. The active daemon pubkey belongs in the cache key.
- **Verify:** cold start with 3k cached orders renders instantly offline; reconcile test; and
  a node switch *before* the refetch completes shows none of the previous node's orders.

### PR 4.2 — `feat(web): real IndexedDB backend` (issue #233)
- **Evidence:** `rust/src/db/indexeddb.rs` opens the DB per operation (`:55-72`), stubs
  trades/identity (`:140-239`), and `list_messages` full-scans + JSON-parses the entire store
  (`:157-167`).
- **Fix:** cache the DB handle; implement the trades store; index messages by `trade_id`;
  batch writes. Split into 2–3 PRs if large.
- **Verify:** web smoke test (`test/web/smoke/smoke.mjs`) + new wasm-target unit tests.

### PR 4.3 — `perf(ingest): parse events in one tag pass`
- **Evidence:** `parse_order_event` does a linear tag scan per field (~10 fields × ~15 tags,
  `rust/src/nostr/order_events.rs:27-33`, `:56-74`); rating tag JSON-parsed per event (`:88`).
- **Fix:** single pass over `event.tags` into a builder; parse rating JSON only when present.
- **Verify:** existing parser tests + a micro-benchmark (Phase 5 harness).

### PR 4.4 — `fix(memory): prune long-lived global stores`
- **Evidence:** `RATING_STORE` (`reputation.rs:34`), `TRADE_KEY_MAP` (`orders.rs:35`),
  `GLOBAL_DM_KEYS` (`orders.rs:2899`), `PENDING_REQUESTS` (`mostro/pending.rs:133`) grow for
  the process lifetime; `hydrate_mine_from_db` runs per `get_rating_for_trade` with no
  negative caching (`reputation.rs:137-161`, `:311`).
- **Fix:** bounded sizes / TTL eviction tied to terminal-trade cleanup; cache "not rated".
- **Verify:** long-session memory profile flat.

---

## Phase 5 — Scale validation & regression protection

### PR 5.1 — `test(bench): Rust benchmark harness + large fixtures`
- Criterion benches for: ingest of 5k-event batch, upsert into a 5k book, event parsing.
  Shared fixture generator for realistic 38383 events. No perf tests exist today anywhere.

### PR 5.2 — `test(ui): large-book widget & scroll tests`
- Widget tests driving `orderBookProvider` with 3k–10k orders; assert frame budget with
  `flutter test --profile` timeline / `flutter_driver` scroll test; provider unit tests
  asserting O(1) work per delta (locks in Phase 3).

### PR 5.3 — `ci: perf smoke gates`
- Wire 5.1 benches (threshold-based, not absolute) and the 5.2 timeline test into `ci.yml`;
  extend the web smoke test with a large-book scenario so wasm-boundary regressions surface.

---

## Suggested sequencing & expected effect

| Milestone | After | User-visible effect |
|---|---|---|
| M1 | Phase 1 | Log/DB/alloc overhead gone; smoother lists; fewer wasted rebuilds |
| M2 | PR 2.1 + 2.2 | Cold start / refresh / node-switch stalls eliminated (O(N²) → O(N)) |
| M3 | Phase 2 done | No resubscribe storms, no relay REQ leaks, chat/notifications snappy |
| M4 | Phase 3 done | Per-event cost O(1); idle bridge traffic ~0; scales to 10k+ orders |
| M5 | Phase 4 done | Instant cold start; web on par with native |
| M6 | Phase 5 done | Scale regressions blocked in CI |

**Review guidance per PR:** conventional commits, one concern per PR, branch
`perf/`-or-`fix/`+kebab, PR to `main` via gh + CodeRabbit. Rust PRs: `cargo test && cargo
clippy` (+ `./scripts/frb-generate.sh` when `rust/src/api/` changes). Dart PRs:
`flutter analyze && flutter test`. Web-touching PRs: run the web smoke test.
