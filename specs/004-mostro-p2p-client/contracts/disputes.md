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
Send a text message to the solver of an open dispute, in the dispute chat
envelope keyed to the solver. Returns it as stored: an admin-type message,
`is_mine`, identified by its inner event id, so the relay echo dedups
against it. This is the dispute chat's text send path (#143).

**Validation**: `text` MUST not be empty. The dispute MUST exist, not be
resolved, and have a solver (`admin-took-dispute`).

**Errors**: `EvidenceEmpty`, `NoOpenDispute`, `AdminNotAssigned`,
`TradeNotFound`.

---

### share_chat_key_with_solver(trade_id: String) → ChatMessage
Send the solver the key of this trade's peer chat, so they can read what buyer
and seller wrote to each other (#415). It replaces copying the key from the
peer chat and pasting it into the dispute chat.

The message is plain text, `Shared key: <64 hex>`, with a fixed English prefix
the solver recognises in any language. The key is `K_conv`'s secret
(<https://mostro.network/protocol/chat.html>): it decrypts the conversation,
but the outer events are signed with `K_sign`, so it cannot be used to write
into it. It is never the raw ECDH secret, which derives `K_sign` too, and
never the session's NIP-04 shared key, from which `K_conv` cannot be derived.
The trade keys are the order's own, so it opens this conversation and no
other. It is derived in Rust from the trade key and the counterparty (the
session's, else the trade row's) and never crosses the bridge except inside
the message. A counterparty the trade row says cannot be the peer (a
pre-#334 row names the Mostro node) is `NoSharedKey`: its key would open no
conversation.

It goes through the same envelope and storage as `submit_evidence`, but it
counts as sent only once a relay accepted it: otherwise `SendFailed`, nothing
stored and nothing recorded, so the user can try again. Once sent, the
dispute's `chat_key_shared` turns true (told through `on_dispute_updated`) and
the share is persisted as `dispute_key_shared:<order_id>` = the solver's
pubkey, so a restart still shows it. It counts for **that** solver only: a
takeover clears `chat_key_shared`, because the new solver never got the key.
The record only informs: it never refuses another share, since the user may
have sent the key to a solver who then handed the dispute over (Serbero
before a human), or want it sent again. The marker is cleared with the other dispute keys and is identity
scoped. A share sent from another device of the same identity reaches this
one as our own message in the dispute chat; when it is the key and the
solver is the one on record, it is recorded the same way.

**Errors**: `NoOpenDispute`, `AdminNotAssigned`, `TradeNotFound`, `NoSharedKey` (the counterparty is not known, or is the
node), `SendFailed`.

---

### send_dispute_file(trade_id: String, file_bytes: Vec<u8>, file_name: String, upload_id: String) → ChatMessage
Encrypt, upload and send an image or PDF to the solver (#589 phase 3). The
same path as `send_file` in `contracts/messages.md` — checks, Blossom
upload, v1 `image_encrypted` / `file_encrypted` message, progress on
`on_attachment_progress(upload_id)` — with two differences: the file key is
the raw ECDH between the trade key and the **solver's** pubkey (as v1
encrypts dispute-chat files), and nobody is woken (the solver is not a push
client). The file is checked before the dispute, so a file that could never
be sent is refused as such. Returns an admin-type message. The peer cannot
open these files; the solver cannot open the P2P chat's (FR-036).

**Errors**: `FileTooLarge`, `UnsupportedFileType`, `InvalidImage`,
`NoOpenDispute`, `AdminNotAssigned`, `TradeNotFound`, `UploadFailed`,
`SendFailed`.

---

### get_dispute(trade_id: String) → Dispute?
Get dispute details for a trade. Returns null if no dispute exists.

---

### solver_role(trade_id: String, solver_pubkey: String) → SolverRole
Who a solver of `trade_id`'s dispute is, for the label the dispute chat
shows (app#637): `Assistant` when **the dispute's own node** announces
`solver_pubkey` as its Serbero in the info event (kind 38385,
`["serbero", "<hex>"]`, mostro#1009), otherwise `Human`. Another node's
announcement never counts: a key one node runs as its Serbero can be a
person on another node's dispute.

The dispute's node is the authenticated author of its `admin-took-dispute`,
recorded under `dispute_node:<order_id>` (see Persistence and restart). A
dispute with no node recorded — assigned before the app recorded it, until
a replay does — shows `Human`. That node's announcement comes from its
latest capability fetch, which wins (a fetch without the tag, or without an
info event, retracts an older one), or else from its cached info event, so
a dispute of a node the user switched away from keeps its label. A node
outside the registry and not active (a removed custom node) vouches for
nobody. The solver's own profile never counts.

Read at display time rather than stored with a message: a history replay
can land before the capability fetch, and the label corrects itself on the
next read. The dispute chat labels each solver message by its sender, and
shows a system line where a person took the dispute over from Serbero.

## Persistence and restart

The Dispute record is **in-memory by design** — its status and resolution come
back from daemon events, and so, usually, does the solver assignment: the
offline catch-up channel (`orders.rs`, no `since`) replays `admin-took-dispute`
on every reconnect, which rebuilds the record and re-arms the dispute chat on
its own. These facts are persisted anyway:

- the **origin** (whether this side opened the dispute), written by a successful
  `open_dispute` under `dispute_mine:<order_id>` (presence is the value). This
  one is never re-derivable: the replay always rebuilds the record with
  `initiated_by_me: false`.
- the **solver pubkey**, from `admin-took-dispute`, under
  `dispute_admin:<order_id>`. This is a **fallback**, not the primary path: the
  replay is bounded by relay retention and by the per-subscription result cap,
  so a long dispute can outlive it. The stored copy is what re-arms the chat
  when the replay no longer covers the assignment.
- **when that solver was assigned**, under `dispute_admin_at:<order_id>` as
  `<time>:<pubkey>`, so a replayed older assignment is ignored after a restart
  (see Solver takeover).
- the dispute's **node** (hex), the authenticated author of its
  `admin-took-dispute`, under `dispute_node:<order_id>`: only that node's
  Serbero announcement labels the dispute's solvers (see `solver_role`), and
  the user can switch nodes while the dispute lasts.

**Rehydration**: on relay (re)connect, dispute records are rebuilt for persisted
trades that have a stored solver, before dispute-chat listeners are re-armed and
before the replay has had a chance to run. Restored records are `InReview` (a
stored solver means one took the dispute), `initiated_by_me` from the origin
marker, `chat_key_shared` when the share marker names the restored solver,
`reason: null` (not persisted), and **unread** — the pre-restart read
state is not recoverable and an active dispute must surface. Records already in
memory win, enforced under the store's single write lock so a concurrent
`open_dispute` / `admin-took-dispute` is never clobbered. This is what makes
`get_dispute` non-null and `submit_evidence` work again after a restart.

**Terminal states**: the *trade* status, not the dispute record, is the durable
signal that a dispute is over. The daemon's `admin-settled` / `admin-canceled`
are persisted by the order status-sync path, which also routes them into the
dispute store (`apply_admin_verdict`, #596) — that resolves the live record
and tells `on_dispute_updated`, but the record is in memory and gone after a
restart. A trade is finished at `SettledByAdmin`, `CanceledByAdmin`,
`CompletedByAdmin`, `Success`, `Canceled`, `CooperativelyCanceled` or
`Expired`. Three places enforce it, and all three clear both keys:

- rehydration skips a finished trade, and clears any key left for it — the
  origin marker included, so a dispute opened but never taken does not leave
  one behind;
- `admin-took-dispute` is **refused** for a finished trade. Without this the
  replay would, one second after rehydration cleared the keys, recreate the
  record as `InReview`, write the solver key straight back and arm a listener
  nobody is on the other end of — on every startup;
- a resolution reaching the dispute store clears them too: the verdicts are
  routed there since #596.

**Solver takeover**: a dispute can change solver. mostrod lets a write solver
take over an `in-progress` dispute held by a read-only one (for example
[Serbero](https://github.com/MostroP2P/serbero)), and sends both parties a new
`admin-took-dispute` with the new pubkey. The record takes the new solver, and
the dispute chat task, bound to the previous solver's conversation keys, is
stopped before the new one is armed (the handover releases the claim, closes
the old REQ and clears the cursor under the chat guard's lock, so no new task
claims the chat half-way); the chat guard allows one task per order
and channel, so without the stop the new solver's messages would never be read.
The peer chat is not touched. The dispute chat's `since` cursor is cleared,
since it dates the previous conversation and the new solver's clock may be
behind it. A chat task only writes its cursor while it still owns the chat
(checked under the guard's lock), so the stopped task, if it was handling an
event, cannot restore the old cursor. Likewise a task installs its relay
subscription only while it owns the chat: all tasks of a chat share one
subscription id, and a task stopped between its claim and its REQ would
otherwise overwrite the new solver's filter. A listener armed for the previous solver that has not claimed the
chat yet (rehydration on reconnect) cannot claim it: the claim checks the
dispute's current solver under the guard's lock.

Each assignment's time (the event's `created_at`) is recorded, and an
assignment of another solver that is not newer is ignored: the catch-up
channel replays every `admin-took-dispute`, usually newest first, and the
previous solver must not come back. Equal seconds cannot be ordered, so the
current assignment is kept. The time is persisted under
`dispute_admin_at:<order_id>` and seeded again by rehydration, so the replay
order does not matter after a restart either. The persisted value names the
solver it belongs to (`<time>:<pubkey>`), and rehydration ignores it for any
other solver, since the pubkey and the time are separate best-effort writes.
An assignment dated beyond the local clock's skew horizon
(`MAX_CLOCK_SKEW_SECS`) is rejected, like a future-dated chat event: it
cannot be ordered against the others. Deleting the identity forgets
the recorded times with its disputes. Assignments are applied one at
a time (a global lock): the global and per-trade notification tasks can
dispatch two for the same order at once, and the check, the recorded time,
the chat restart and the persisted solver must describe the same assignment.
Rehydration restores each persisted solver and its time under the same lock,
since a replayed older assignment applied half-way would install the previous
solver with the newer time. A chat task's own cleanup likewise releases its
claim and closes its REQ under the chat guard's lock, so a takeover's new task
cannot install its subscription in between and lose it to the late close.

**Unvouched cursor**: a persisted time recorded for the current solver is what
vouches that the dispute chat cursor dates that solver's conversation. A
release before takeover handling persisted the new solver and kept the
previous conversation's cursor, with no time. So wherever a solver is found
without a time recorded for it, the dispute chat is handed over as in a
takeover (task stopped, REQ closed, cursor cleared; the peer chat is not
touched), at the cost of one refetch of that conversation, deduplicated by
event id. Both paths do it: rehydration, for a restored solver, and an
assignment with a time, before it writes that time — the daemon feed opens
before rehydration, so a replayed assignment can be the first to see that
state, and the time it writes would otherwise certify the cursor for good. The
recorded time ends it; it repeats only while no replay brings the assignment
back to record it (rehydration on every restart).

Sending to the solver (`submit_evidence`, `send_dispute_file`) checks both:
a resolved record or a finished trade is `NoOpenDispute`.

**UI wiring**: the dispute chat screen (#143, #589 phase 3) reads the record
with `get_dispute` when it opens and follows `on_dispute_updated`, shows the
`MessageType::Admin` messages, and writes with `submit_evidence` and
`send_dispute_file`. The disputes list is still fed on resume only (#397).
A key button in its app bar sends the solver the P2P chat key after an explicit
confirmation (`share_chat_key_with_solver`, #415). Once `chat_key_shared` is
set it turns lime and says the key was shared, and still sends it again.

**Platform limitation (web)**: persistence is native-only today. The Flutter
shell does not call `init_db` on web, and the IndexedDB store's `list_trades`
is still a stub (#233), so a browser reload loses the solver pubkey and the
dispute chat with it. No change is needed in this module once #233 lands trade
persistence on web.

## Streams

### on_dispute_updated(trade_id: String) → Stream<Dispute>
Emits when dispute status changes (opened, admin message received,
resolved). A subscriber that falls behind the broadcast buffer gets the
record as it stands in place of the updates it missed, so a resolution is
never skipped (#596).
