# Working with relays

Rules for any code that subscribes to, or publishes through, the relay pool. Each one exists
because breaking it produced a bug that static checks and a healthy network never show: they
only bite on a phone that changes network, sleeps, or resumes before its sockets are back.

Code: `rust/src/nostr/live_subs.rs` (subscription registry), `rust/src/nostr/relay_pool.rs`
(pool + status monitor), `rust/src/nostr/subscriptions.rs` (per-trade watcher ownership),
`rust/src/api/nostr.rs::resync` (resume).

## 1. What nostr-sdk 0.45 does and does not do

- A **long-lived** subscription (no `close_on`) is re-sent by the SDK on every reconnect — but
  only while it sits in **that relay's** registry.
- A REQ that fails to send (`relay not connected`, `relay is initialized but not ready`) is
  **removed** from that relay's registry (`subscribe_long_lived`). It is not retried. After the
  relay reconnects, the subscription still does not exist there.
- `client.subscribe(..)` returns `Ok` with the refusals inside `output.failed`. An `Ok` does not
  mean anything subscribed.
- `client.unsubscribe(id)` removes the id from every relay's registry, connected or not.
- A subscribe whose id already exists is refused and the **old** filter stays. Replacing a
  filter is therefore CLOSE + REQ.

Put together: **CLOSE + REQ while the pool is offline deletes the subscription everywhere, for
the rest of the session.** That is what a resume does, and it is how the bulk kind-14 feed
(`mostro-dm`) died in the field: a buyer sat on "taken · waiting for payment" and never saw the
daemon's `add-invoice`, because the feed that would have replayed it existed on no relay.

## 2. The rules

1. **Every long-lived subscription goes through `live_subs()`** — `open` (the caller needs
   coverage now; no relay accepting is an error and nothing is recorded) or `replace` (stable
   ids; with the pool offline it is *deferred*, not failed). Never a bare
   `client.subscribe(..).with_id(..)`.
2. **Every unsubscribe of one goes through `live_subs().close`.** The registry remembers what
   should exist; an id closed behind its back is resurrected on the next reconnect, and relays
   cap concurrent REQs — past the cap they answer `CLOSED`, which can take the order book down.
   nostr-sdk drops a `CLOSED` subscription from that relay's registry; `live_subs().on_closed`
   re-issues a recorded one after 30 s, 2 min and 10 min, then waits for the relay's next
   `Connected` (#523). A trade that ends gives its own REQs back at once — its d-tag watcher,
   daemon-message watcher and chats (`release_finished_trade_subscriptions`) — instead of
   holding them until an idle timeout.
3. **Never treat "issued" as "live".** The repair task (`spawn_repair`) attempts to re-issue
   what a relay lacks when the status monitor reports it `Connected` (it can fail or time out,
   and says so in the log); `resync()` runs the same repair for the relays that are already up.
   Code that needs a reply must not assume the REQ is on any particular relay — wait on the
   message, with a timeout.
4. **A live-only filter (`limit(0)`) is not a delivery guarantee.** Whatever is published while
   the socket is down is never delivered on it, reconnect or not. Every such subscription needs
   a replaying counterpart: for daemon messages that is `mostro-dm`, which carries no `since`
   on purpose. Do not add a `since` to it, and do not rely on a per-trade watcher alone.
5. **A replay is not news.** A replaying feed re-delivers history on every (re)issue, per relay.
   Anything it feeds must be idempotent: dedupe by event id, order by the event's `created_at`
   (`status_write_blocked` / `record_status_event`), and emit a `TradeUpdate` only when
   something changed (`sync_trade_fields_if_changed`).
6. **Resume may run before the network is back.** `resync()` waits a bounded time for the
   reconnect and then proceeds whatever the state (`online=false` is a normal outcome). Nothing
   it does may depend on a relay being connected at that moment; what it could not deliver must
   be recoverable on the `Connected` / `Online` transitions (subscription repair, outbox flush).
7. **Publishing: read `output.failed`, not just `Ok`.** Same shape as subscribe. Requests that
   expect a reply register their pending record *before* publishing and hold a subscription that
   is already live (`subscribe_daemon_messages` is awaited first).
8. **One `Client` per concern is allowed, but then it owns its whole lifecycle.** The NWC client
   is separate from the pool and is the one exception to rules 1–2.

`live_subs::tests::no_module_subscribes_or_unsubscribes_behind_the_registry` enforces rules 1–2
statically: it fails on any `.with_id(` / `.unsubscribe(` outside the registry. If it fails on
your change, route the call through `live_subs()` — do not extend the allow-list.

## 3. Diagnosing "the screen did not update"

In the app log (`/logs`, or `adb logcat -s mostro flutter`):

| Line | Meaning |
|---|---|
| `sub <id> failed relay=… err=relay not connected` | The REQ did not reach that relay. Expected offline. `Connected` triggers a repair *attempt*, not a guarantee: look for its outcome, `sub <id> repaired relay=…` or `sub <id> repair failed relay=… err=…`. A failed one is retried on that relay's next `Connected` and on the next `resync()`. |
| `sub <id> deferred: no relay connected` | A `replace` ran fully offline. Same expectation, per relay. |
| `closed sub=<id> relay=… msg=…` then `sub <id> closed by relay=… — repair in Ns` | The relay ended a subscription we still want (often its REQ cap). The repair outcome follows as above. `closed again … no more repairs until it reconnects` means the relay kept refusing: too many REQs are open. |
| `eose sub=mostro-dm relay=…` after a reconnect | The feed exists on that relay. **Its absence after `Connected` is this bug.** |
| `Kind 14 received (global\|per-trade) … age=Ns` | `age` ≈ 0 is live delivery; minutes or more is a replay. |
| `drop ev=… reason=duplicate` | Normal: the global and per-trade loops saw the same event. |
| `[lifecycle] resync: online=false` | Resume ran before the sockets were back (rule 6). |

A daemon message that shows up on the counterparty's log but on neither of yours, while your
relays read `Connected`, means a subscription is missing on them: check for the `eose` line.
