# Contract: Disputes API

**Module**: `rust/src/api/disputes.rs`

Dispute initiation, evidence submission, and resolution tracking.

## Functions

### open_dispute(trade_id: String, reason: String?) → Dispute
Initiate a dispute on an active trade.

**Preconditions**: Trade MUST be in a state between `PaymentLocked` and
completion (i.e., funds are in escrow). No existing open dispute on
this trade.

The daemon accepts a dispute only on an `Active` or `FiatSent` order and
answers anything earlier with `CantDo`, so the status already held locally is
checked before publishing. `InProgress` passes: it is the public bucket, i.e. a
trade whose real state is unknown, and that call belongs to the daemon.

The open is **single-flight per trade**: a second call while one is still
awaiting the daemon is refused. Both would derive the same trade key, so the
second registration would replace the first one's pending record and strand its
caller on a timeout the daemon never caused.

**Side effects**: Sends the Dispute action to the Mostro daemon via NIP-44
(Kind 14), carrying a random u64 `request_id` nonce, and waits up to 10 s for
the reply the daemon echoes it in — `DisputeInitiatedByYou` on acceptance,
`CantDo` on rejection. Only the correlated acceptance creates the local
Dispute record; that reply also carries the daemon's dispute UUID, which is
the id the solver and the daemon's Kind 38386 dispute event refer to, so the
record is stored under it. The reply doubles as the status update that moves
the trade to `Disputed` and is processed normally. On rejection or timeout
**the call persists nothing** — a publish is not an acceptance, and the caller
surfaces the error instead of showing a dispute that does not exist.

An acceptance **without** that dispute id is malformed and fails closed: it
persists nothing and reports `ProtocolError`. `Dispute.id` is contractually the
daemon's, and a locally minted id would be indistinguishable from a real one
while being wrong. A conforming daemon always sends it, so this is a
protocol-violation guard rather than a routine path.

An acceptance that arrives **after** the caller timed out is still reconciled:
the daemon did open the dispute, and its reply moves the trade to `Disputed`
either way, so the record is created then (unread, and without the reason,
which went with the timed-out call). Suppressing it would leave a disputed
trade with no dispute to open and no solver to reach. The same missing-id guard
applies.

A solver can be assigned inside that same window, in which case the record
already exists as the peer-style placeholder `admin-took-dispute` writes
(`InReview`, not ours, no reason, solver known, locally minted id). The
reconciliation **claims** it — daemon id and initiator flag replace the local
ones, solver and `InReview` survive — because the correlated acceptance proves
the dispute is ours. Any other existing record (a retry that succeeded, a
resolved dispute) is left untouched.

Retrying after a timeout does not close that window. The retry derives the same
trade key and takes the pending record over, but the attempt it replaces stays
**answerable**: its nonce travels into the new record and a reply echoing it is
still reconciled as a late acceptance, leaving the retry registered for its own
reply. Without that, the daemon could accept the first attempt while the client
had already discarded every way to recognize the answer — the trade would move
to `Disputed` with no dispute record, the split state this whole change set
exists to remove. A retry whose publish fails rolls back only itself and
restores the attempt it replaced.

No retry count changes this: **every** superseded nonce is retained, because
every one of them is still answerable and dropping one turns its acceptance
back into that same bare status update. The list only grows through retries the
user drives, each gated by the 10 s timeout, and a nonce leaves it as soon as
its reply is reconciled. Nothing purges the record itself in the common case:
that only happens when a per-trade daemon subscription exits, and opening a
dispute starts none — a dispute on a trade loaded from the database after a
restart is answered over the global feed — so the record can live for the whole
process.

The local status check and the reply correlation are two layers of the same
concern: the check keeps most rejections off the wire, and the correlation
reconciles the ones that still come back (issues #203 and #202).

The nonce gate is the dispatcher's, shared with the order requests — see
[orders.md](orders.md) "Daemon confirmation & request correlation".

Note: the daemon replies `CantDo` only for `MostroCantDo` causes. A duplicate
dispute or a daemon-side DB failure is an internal error it merely logs, so
those surface as `NoDaemonResponse` rather than a precise reason.

**Errors**: `TradeNotDisputable`, `DisputeAlreadyOpen`, `ProtocolError`,
`NoDaemonResponse`, plus daemon `CantDo` reasons passed through as errors.
`DisputeAlreadyOpen` covers both refusals — a record already exists, or an open
for this trade is still in flight — and Dart maps the marker to one localized
message (`localizedDaemonError`).

---

### submit_evidence(trade_id: String, text: String) → ChatMessage
Submit text evidence for an open dispute. Delivered as an admin-type
message.

**Validation**: `text` MUST not be empty. Dispute MUST be open.

**Errors**: `NoOpenDispute`, `EvidenceEmpty`.

---

### get_dispute(trade_id: String) → Dispute?
Get dispute details for a trade. Returns null if no dispute exists.

## Persistence and restart

The Dispute record is **in-memory by design** — its status and resolution come
back from daemon events, and so, usually, does the solver assignment: the
offline catch-up channel (`orders.rs`, no `since`) replays `admin-took-dispute`
on every reconnect, which rebuilds the record and re-arms the dispute chat on
its own. Two facts are persisted anyway:

- the **origin** (whether this side opened the dispute), written by a successful
  `open_dispute` under `dispute_mine:<order_id>` (presence is the value). This
  one is never re-derivable: the replay always rebuilds the record with
  `initiated_by_me: false`.
- the **solver pubkey**, from `admin-took-dispute`, under
  `dispute_admin:<order_id>`. This is a **fallback**, not the primary path: the
  replay is bounded by relay retention and by the per-subscription result cap,
  so a long dispute can outlive it. The stored copy is what re-arms the chat
  when the replay no longer covers the assignment.

**Rehydration**: on relay (re)connect, dispute records are rebuilt for persisted
trades that have a stored solver, before dispute-chat listeners are re-armed and
before the replay has had a chance to run. Restored records are `InReview` (a
stored solver means one took the dispute), `initiated_by_me` from the origin
marker, `reason: null` (not persisted), and **unread** — the pre-restart read
state is not recoverable and an active dispute must surface. Records already in
memory win, enforced under the store's single write lock so a concurrent
`open_dispute` / `admin-took-dispute` is never clobbered. This is what makes
`get_dispute` non-null and `submit_evidence` work again after a restart.

**Terminal states**: the *trade* status, not the dispute record, is the durable
signal that a dispute is over — the daemon's `admin-settled` / `admin-canceled`
are persisted by the order status-sync path without being routed into the
dispute store. A trade is finished at `SettledByAdmin`, `CanceledByAdmin`,
`CompletedByAdmin`, `Success`, `Canceled`, `CooperativelyCanceled` or
`Expired`. Three places enforce it, and all three clear both keys:

- rehydration skips a finished trade, and clears any key left for it — the
  origin marker included, so a dispute opened but never taken does not leave
  one behind;
- `admin-took-dispute` is **refused** for a finished trade. Without this the
  replay would, one second after rehydration cleared the keys, recreate the
  record as `InReview`, write the solver key straight back and arm a listener
  nobody is on the other end of — on every startup;
- a resolution reaching the dispute store clears them too. Today nothing routes
  the daemon's verdicts there (`handle_admin_settled` / `handle_admin_canceled`
  have no production caller), so in practice the two trade-status guards above
  are what clean up; the resolution path is ready for when that wiring lands.

**UI wiring**: this is the Rust layer only. Nothing in Dart consumes the
rehydrated record yet — `get_dispute`, `submit_evidence` and
`on_dispute_updated` have no callers outside the generated bindings — and the
dispute chat has no UI: `chat_room_screen.dart` renders only peer messages and
`send_message` has no channel parameter, so the solver can be read but not
written to. What lands today is the re-armed listener: solver messages arrive
and persist as `MessageType::Admin`. Repopulating the dispute screen and the
admin chat are the tracked follow-ups. So is one-tap delivery of the P2P
shared key to the solver (#415): Rust will send it over this channel behind an
explicit confirmation in the UI, and the key is never exposed to Dart; that
function and the `Dispute` state it adds are specified when it lands.

**Platform limitation (web)**: persistence is native-only today. The Flutter
shell does not call `init_db` on web, and the IndexedDB store's `list_trades`
is still a stub (#233), so a browser reload loses the solver pubkey and the
dispute chat with it. No change is needed in this module once #233 lands trade
persistence on web.

## Streams

### on_dispute_updated(trade_id: String) → Stream<Dispute>
Emits when dispute status changes (opened, admin message received,
resolved).
