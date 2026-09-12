//! Single-owner registry for per-trade daemon-message subscriptions (#325).
//!
//! Every per-trade watcher (`subscribe_daemon_messages`) owns a relay-side
//! subscription plus, transitively, the pending-request record for its trade
//! key: the watcher's exit path unsubscribes the REQ and purges the record
//! (`purge_detached_pending_request` is documented as "only for the end of
//! the per-trade subscription's lifetime"). Two watchers over the same
//! trade key therefore cannot coexist — the older one's teardown would kill
//! the newer one's live subscription and strand its waiting caller with a
//! `NoDaemonResponse` on a request the daemon actually accepted.
//!
//! Today every caller derives a fresh trade key first, so duplicates cannot
//! happen; the restore apply (#218) breaks that invariant by re-arming
//! watchers for already-covered keys, and it must be idempotent. This
//! registry makes re-arming safe by giving the lifecycle a single owner:
//!
//! * **Idempotence by membership**: [`claim`] admits exactly one owner per
//!   trade key. A second claim is a bounce, not a second watcher.
//! * **A bounce promises coverage that exists.** An entry starts in
//!   [`State::Setup`] — claimed, but the relay-side REQ not yet active. A
//!   concurrent claim landing there parks until the owner reaches
//!   [`State::Live`] (its `client.subscribe` succeeded, [`mark_live`]) or
//!   releases (setup failed, [`release`]), and only then bounces or takes
//!   over. Bouncing during setup would return a promise the owner may never
//!   keep — its setup can still fail, dropping the claim silently — or not
//!   keep *yet*: the REQ is `limit(0)` live-only, so a reply published
//!   before it is active is lost. Both end in the exact `NoDaemonResponse`
//!   this registry exists to prevent.
//! * **A bounce is a lease refresh, not just a dedupe**: the bouncing caller
//!   is promised live coverage, so the bounce marks the key re-armed and the
//!   owner's idle-timeout exit ([`teardown_or_rearm`]) honors the mark by
//!   resetting its timer instead of dismantling. Without this, a re-arm
//!   landing at minute 29 of the owner's 30-minute idle window would be
//!   "covered" for seconds only.
//! * **Teardown is atomic with respect to claims**: the destructive pair
//!   (unsubscribe + purge) runs while holding the registry lock, so a
//!   concurrent claim either bounces first (and the owner keeps running) or
//!   waits and finds the key free (and subscribes from scratch). The chat
//!   guard (`ACTIVE_CHATS`) releases before unsubscribing and leaves exactly
//!   this window open — do not copy that ordering. The purge half of the
//!   pair is *detached-only*: a record with a live waiter belongs to a
//!   caller that registered it before claiming (the create/take ordering)
//!   and may be the very claim parked on this lock, about to subscribe from
//!   scratch — purging it would strand that caller with the
//!   `NoDaemonResponse` this registry exists to prevent.
//! * **An abandoned setup cannot wedge the key.** [`claim`] hands the owner
//!   a [`SetupGuard`]; the normal exits ([`mark_live`], [`release`]) consume
//!   it, and a guard dropped still armed — a panic unwinding the setup (FRB
//!   catches it and reports the error to Dart), a cancelled future — frees
//!   the claim from `Drop`. Without that, the entry would leak in `Setup`
//!   and every later claim for the key — every `take_order`/`create_order`
//!   on it — would park forever.
//!
//! The subscription id is recomputed from the trade pubkey
//! ([`daemon_message_subscription_id`]), so the registry needs no
//! pubkey → id map. Teardown is targeted by construction: it only ever
//! closes the one per-trade id, never the order-book or global DM
//! subscriptions.
//!
//! Lock discipline: the lock is held across the teardown's `unsubscribe`
//! await (a short send), which serializes claims of *all* keys for that
//! moment — fine for a CLOSE message, but do not add long waits under it.
//! Verified against the locked nostr-sdk 0.45.2 (`Relay::unsubscribe` takes
//! the in-process subscriptions `RwLock` and queues the CLOSE via
//! `send_msg(..., None)` — a channel push, never a socket wait); re-verify
//! that on any nostr-sdk bump before trusting this ordering again.

use std::collections::HashMap;
use std::sync::{Arc, OnceLock};

/// Where a claimed trade key is in its lifecycle.
enum State {
    /// Claimed, but the owner's relay-side REQ is not active yet. Concurrent
    /// claims park on [`Entry::setup_done`] instead of bouncing — see the
    /// module docs for why bouncing here would promise phantom coverage.
    Setup,
    /// REQ active, watcher running. `rearmed` = a claim bounced since the
    /// owner last checked its idle timeout, so that exit must refresh the
    /// lease instead of dismantling.
    Live { rearmed: bool },
}

struct Entry {
    state: State,
    /// The owner's trade index, recorded to make the "same trade pubkey ⇒
    /// same trade index" assumption checkable: a bounce whose caller brings
    /// a different index would hand it a watcher decrypting with the wrong
    /// recipient keys, which today can only mean an identity-derivation bug
    /// upstream — logged loudly, never expected.
    trade_index: u32,
    /// Wakes claims parked on a `Setup` entry once it advances to `Live` or
    /// is released. Notified only while the registry lock is held.
    setup_done: Arc<tokio::sync::Notify>,
}

/// Trade pubkey hex → lifecycle entry. Key present = someone owns (or is
/// setting up) the subscription for that trade key.
static ACTIVE_TRADE_SUBS: OnceLock<tokio::sync::Mutex<HashMap<String, Entry>>> = OnceLock::new();

fn registry() -> &'static tokio::sync::Mutex<HashMap<String, Entry>> {
    ACTIVE_TRADE_SUBS.get_or_init(|| tokio::sync::Mutex::new(HashMap::new()))
}

fn short(key: &str) -> &str {
    key.get(..8).unwrap_or(key)
}

/// Stable, deterministic subscription id for a trade key's daemon-message
/// subscription — recomputable from the pubkey, so ownership needs no id map,
/// and keyed per trade so closing one trade's REQ cannot touch another's.
///
/// NIP-01 caps subscription ids at 64 characters and relays enforce it
/// (`relay.mostro.network` answers CLOSED with "max length 64 chars"); the
/// full 64-hex pubkey would push the id to 78. The first 32 hex characters
/// (128 bits) keep it at 46 and rule out any realistic cross-trade collision.
/// `subscription_ids_fit_nip01` (in `api::orders` tests) pins the bound.
pub(crate) fn daemon_message_subscription_id(
    trade_pubkey_hex: &str,
) -> nostr_sdk::prelude::SubscriptionId {
    let key = trade_pubkey_hex.get(..32).unwrap_or(trade_pubkey_hex);
    nostr_sdk::prelude::SubscriptionId::new(format!("mostro-daemon-{key}"))
}

/// Exclusive ownership of a key's `Setup` phase, returned by [`claim`].
///
/// The owner must end its setup by consuming the guard: [`mark_live`] when
/// `client.subscribe` succeeded, [`release`] on any earlier exit. A guard
/// dropped still armed — a panic unwinding the setup, a cancelled future —
/// frees the claim from `Drop` instead, so parked claims take over rather
/// than hanging forever on a `Setup` entry nobody will ever advance
/// (PR #407 round 2).
#[must_use = "dropping the guard releases the claim — consume it via mark_live or release"]
pub(crate) struct SetupGuard {
    /// `Some` while armed; [`mark_live`]/[`release`] take it, disarming
    /// `Drop`.
    key: Option<String>,
}

impl Drop for SetupGuard {
    fn drop(&mut self) {
        let Some(key) = self.key.take() else { return };
        // Reached only when the setup was abandoned — the normal exits
        // disarm the guard first. While the guard was armed nothing else
        // could remove or replace the entry (claims park on Setup, and
        // teardown paths only run for watchers, which exist past
        // `mark_live`), so the entry is still ours. `Drop` is sync and the
        // registry lock is async: `try_lock` covers the uncontended case,
        // a contended lock falls back to a spawned release. Claims keep
        // parking until that release runs — which is exactly the wake they
        // are waiting for.
        crate::api::logging::blog_warn(
            "orders",
            format!(
                "subscription setup abandoned for trade={} without mark_live/release — freeing the claim",
                short(&key)
            ),
        );
        match registry().try_lock() {
            Ok(mut map) => remove_and_wake(&key, &mut map),
            Err(_) => {
                crate::rt::spawn(async move {
                    remove_and_wake(&key, &mut *registry().lock().await);
                });
            }
        }
    }
}

/// Remove `key`'s entry and wake anything parked on it — shared by the two
/// release paths (explicit [`release`], guard [`Drop`]).
fn remove_and_wake(key: &str, map: &mut HashMap<String, Entry>) {
    if let Some(entry) = map.remove(key) {
        entry.setup_done.notify_waiters();
    }
}

/// Claim ownership of `trade_pubkey_hex`'s subscription lifecycle.
///
/// Returns `Some(guard)` when the caller is now the single owner: it must
/// run the setup and then consume the guard via [`mark_live`] (subscribe
/// succeeded) or [`release`] (any earlier exit); an abandoned guard frees
/// the claim from its `Drop` (see [`SetupGuard`]). Returns `None` when a
/// watcher already owns the key **and its REQ is live**: the subscription
/// and pending record stay untouched, and the bounce is recorded as a lease
/// refresh so the owner outlives the caller's interest (see
/// [`teardown_or_rearm`]).
///
/// If the key is claimed but still in setup, this call parks until the owner
/// reaches `Live` (then bounces) or releases (then takes over and returns
/// `Some`) — a bounce is a promise of coverage, and during setup that
/// coverage does not exist yet.
pub(crate) async fn claim(trade_pubkey_hex: &str, trade_index: u32) -> Option<SetupGuard> {
    loop {
        let notify = {
            let mut map = registry().lock().await;
            match map.get_mut(trade_pubkey_hex) {
                None => {
                    map.insert(
                        trade_pubkey_hex.to_string(),
                        Entry {
                            state: State::Setup,
                            trade_index,
                            setup_done: Arc::new(tokio::sync::Notify::new()),
                        },
                    );
                    return Some(SetupGuard {
                        key: Some(trade_pubkey_hex.to_string()),
                    });
                }
                Some(entry) => match &mut entry.state {
                    State::Live { rearmed } => {
                        *rearmed = true;
                        if entry.trade_index != trade_index {
                            crate::api::logging::blog_warn(
                                "orders",
                                format!(
                                    "re-arm for trade={} carries index {} but the live watcher \
                                     decrypts with index {} — identity derivation bug upstream?",
                                    short(trade_pubkey_hex),
                                    trade_index,
                                    entry.trade_index
                                ),
                            );
                        }
                        return None;
                    }
                    State::Setup => entry.setup_done.clone(),
                },
            }
        };

        // Owner mid-setup: park until it reaches Live or releases, then
        // retry the claim from scratch. `enable` registers interest *before*
        // the re-check below, closing the race where the owner's
        // `notify_waiters` (always sent under the registry lock) fires
        // between our check above and the await: either the transition
        // happened before the re-check (we see it and retry immediately) or
        // after (we are already registered and the notify wakes us).
        let notified = notify.notified();
        tokio::pin!(notified);
        notified.as_mut().enable();
        if parked_on_current_setup(trade_pubkey_hex, &notify).await {
            notified.await;
        }
    }
}

/// The predicate a parked claim re-checks after registering interest: is
/// `notify` still the `Setup` gate of the **current** entry for this key?
///
/// Checking only "some entry is in Setup" is not enough. Between cloning the
/// gate and `enable()`, the owner can release — its `notify_waiters` is lost
/// on us, we were not registered yet — and a third claimant can insert a
/// fresh `Setup` entry: same state, different `Notify`. Parking on the stale
/// gate would sleep forever, because nothing ever notifies it again — and a
/// hung claim is a hung API call, since `subscribe_daemon_messages` is
/// awaited by its caller. Pointer identity (`Arc::ptr_eq`) pins "same
/// entry"; ABA is impossible while the caller holds its clone, because the
/// old allocation cannot be reused. On a mismatch the claim loop retries
/// from scratch and does the right thing for whatever it finds: free key,
/// live owner, or the new entry's gate.
async fn parked_on_current_setup(
    trade_pubkey_hex: &str,
    notify: &Arc<tokio::sync::Notify>,
) -> bool {
    registry()
        .lock()
        .await
        .get(trade_pubkey_hex)
        .is_some_and(|e| matches!(e.state, State::Setup) && Arc::ptr_eq(&e.setup_done, notify))
}

/// The owner's setup succeeded: its `client.subscribe` returned, the REQ is
/// active. Advance `Setup` → `Live` and wake any parked claims — from this
/// point a bounce is backed by a real subscription. Consumes (disarms) the
/// guard: from here the entry belongs to the watcher's exit paths.
pub(crate) async fn mark_live(mut guard: SetupGuard) {
    let Some(key) = guard.key.take() else { return };
    let mut map = registry().lock().await;
    if let Some(entry) = map.get_mut(&key) {
        entry.state = State::Live { rearmed: false };
        entry.setup_done.notify_waiters();
    }
}

/// Release a claim whose watcher never started (setup failed between claim
/// and subscribe). No teardown: there is no REQ to close, and the pending
/// record — if any — belongs to its caller's own rollback/timeout paths.
/// Parked claims are woken and the first to retry becomes the new owner,
/// re-running setup from scratch.
pub(crate) async fn release(mut guard: SetupGuard) {
    let Some(key) = guard.key.take() else { return };
    remove_and_wake(&key, &mut *registry().lock().await);
}

/// The owner's idle-timeout exit: refresh the lease or dismantle, atomically.
///
/// Under the registry lock, either a claim bounced since the last check —
/// clear the mark and return `true`, the watcher resets its idle timer and
/// keeps running — or nobody re-armed and the destructive pair runs while
/// the lock is still held: unsubscribe the relay-side REQ, purge the pending
/// record, release ownership, return `false`. Holding the lock across the
/// pair is what makes a concurrent claim safe: it either lands before (the
/// owner continues) or after (the key is free, it subscribes from scratch) —
/// never in between, where it would trust a subscription about to die.
///
/// Only for the **idle-timeout** exit. Shutdown/channel-closed exits must use
/// [`teardown`]: their notifications receiver is dead, so honoring a re-arm
/// would spin on a closed channel.
pub(crate) async fn teardown_or_rearm(
    client: &nostr_sdk::prelude::Client,
    trade_pubkey_hex: &str,
) -> bool {
    let mut map = registry().lock().await;
    if let Some(Entry {
        state: State::Live { rearmed },
        ..
    }) = map.get_mut(trade_pubkey_hex)
    {
        if *rearmed {
            *rearmed = false;
            crate::api::logging::blog_info(
                "orders",
                format!(
                    "daemon-message watcher lease refreshed for trade={}",
                    short(trade_pubkey_hex)
                ),
            );
            return true;
        }
    }
    dismantle(client, trade_pubkey_hex, &mut map).await;
    false
}

/// Unconditional teardown for Shutdown/channel-closed exits: the pool is
/// going away, every subscription dies with it, and a pending re-arm mark
/// cannot be honored (the watcher's receiver is dead). Coverage after a
/// reconnect is the re-arm paths' job (#218/#291), not this registry's.
pub(crate) async fn teardown(client: &nostr_sdk::prelude::Client, trade_pubkey_hex: &str) {
    let mut map = registry().lock().await;
    dismantle(client, trade_pubkey_hex, &mut map).await;
}

/// The destructive pair plus release, under the caller-held registry lock.
async fn dismantle(
    client: &nostr_sdk::prelude::Client,
    trade_pubkey_hex: &str,
    map: &mut HashMap<String, Entry>,
) {
    // Drop the relay-side REQ. Without this the task exits but the
    // subscription lives on: relays cap concurrent REQs, and once past the
    // cap they answer CLOSED — which can take the order-book feed down
    // with it.
    if let Err(e) = client
        .unsubscribe(&daemon_message_subscription_id(trade_pubkey_hex))
        .await
    {
        crate::api::logging::blog_warn(
            "orders",
            format!(
                "daemon-message unsubscribe failed for trade={}: {e}",
                short(trade_pubkey_hex)
            ),
        );
    }

    // The subscription bounds the pending record's lifetime: once no reply
    // can be delivered here anymore, a still-unconsumed record (request
    // timed out and no genuine late reply ever arrived) is dead state —
    // drop it. But only a *detached* record (`tx: None`, its 10 s timeout
    // ran) is dead: one with a live waiter belongs to a caller that
    // registered it before calling `subscribe_daemon_messages` (the
    // create/take ordering) and may be parked on this very lock, about to
    // subscribe from scratch — purging it would strand that caller with a
    // `NoDaemonResponse` on a request the daemon accepted.
    crate::mostro::pending::purge_detached_pending_request(trade_pubkey_hex);

    // Defensive: a watcher only exists past `mark_live`, so nothing should
    // be parked here — but if an entry ever were still in Setup, leaving its
    // waiters asleep would strand them forever.
    remove_and_wake(trade_pubkey_hex, map);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn offline_client() -> nostr_sdk::prelude::Client {
        // No relays: unsubscribe is a no-op send, so teardown paths run
        // without network.
        nostr_sdk::prelude::Client::default()
    }

    /// Criterion 1 (#325): subscribing twice for the same trade key must
    /// yield one owner — the second claim bounces instead of spawning a
    /// second watcher whose exit path would destroy the first one's state.
    #[tokio::test]
    async fn second_claim_bounces_off_the_single_owner() {
        let key = "aa".repeat(32);
        let guard = claim(&key, 1).await.expect("first claim owns the key");
        mark_live(guard).await;
        assert!(claim(&key, 1).await.is_none());
        teardown(&offline_client(), &key).await;
    }

    /// The bounce is a lease refresh: the owner's next idle-timeout exit
    /// keeps the watcher alive instead of dismantling, so a re-arm landing
    /// at minute 29 of the idle window still gets durable coverage
    /// (criterion 4 — one live subscription per recovered key AFTER the
    /// apply, not for the seconds until the old timer fires).
    #[tokio::test]
    async fn a_bounce_refreshes_the_owners_lease() {
        let key = "ab".repeat(32);
        let client = offline_client();

        let guard = claim(&key, 1).await.expect("first claim owns the key");
        mark_live(guard).await;
        assert!(claim(&key, 1).await.is_none()); // re-arm bounces, marks the lease

        // Idle timeout fires: the mark wins, the owner keeps running…
        assert!(teardown_or_rearm(&client, &key).await);
        // …and the mark is consumed: the next idle timeout dismantles.
        assert!(!teardown_or_rearm(&client, &key).await);

        // Fully released: the key is claimable from scratch (what #218
        // needs after an owner genuinely expires between applies).
        let guard = claim(&key, 1).await.expect("key must be free again");
        release(guard).await;
    }

    /// Criterion 2 (#325): re-arming a key with a live owner must not purge
    /// its pending request — the purge belongs exclusively to the final
    /// teardown, after any lease refresh has been honored.
    #[tokio::test]
    async fn pending_record_survives_a_lease_refresh_and_dies_with_teardown() {
        use crate::mostro::pending::{pending_requests, PendingRequest, PendingRequestKind};

        let key = "ac".repeat(32);
        let client = offline_client();

        let guard = claim(&key, 1).await.expect("first claim owns the key");
        mark_live(guard).await;
        pending_requests().lock().unwrap().insert(
            key.clone(),
            PendingRequest {
                request_id: 7,
                trade_index: 1,
                kind: PendingRequestKind::Take,
                tx: None,
            },
        );

        // Re-arm, then idle timeout: lease refreshed, record intact.
        assert!(claim(&key, 1).await.is_none());
        assert!(teardown_or_rearm(&client, &key).await);
        assert!(pending_requests().lock().unwrap().contains_key(&key));

        // No re-arm this time: teardown purges the record with the REQ.
        assert!(!teardown_or_rearm(&client, &key).await);
        assert!(!pending_requests().lock().unwrap().contains_key(&key));
    }

    /// Shutdown tears down even with a re-arm mark pending: the pool is
    /// going away and the watcher's receiver is dead, so the mark cannot be
    /// honored — coverage after reconnect belongs to the re-arm paths.
    #[tokio::test]
    async fn shutdown_teardown_ignores_a_pending_rearm() {
        let key = "ad".repeat(32);
        let client = offline_client();

        let guard = claim(&key, 1).await.expect("first claim owns the key");
        mark_live(guard).await;
        assert!(claim(&key, 1).await.is_none()); // mark set
        teardown(&client, &key).await;

        // Ownership fully released despite the mark.
        let guard = claim(&key, 1).await.expect("key must be free again");
        release(guard).await;
    }

    /// Criterion 3 (#325): teardown is targeted — dismantling one trade's
    /// subscription releases only that key and leaves other owners intact.
    #[tokio::test]
    async fn teardown_of_one_key_leaves_other_owners_intact() {
        let key_a = "ae".repeat(32);
        let key_b = "af".repeat(32);
        let client = offline_client();

        let guard_a = claim(&key_a, 1).await.expect("A claims");
        mark_live(guard_a).await;
        let guard_b = claim(&key_b, 2).await.expect("B claims");
        mark_live(guard_b).await;

        assert!(!teardown_or_rearm(&client, &key_a).await);

        // A is free again; B is still owned.
        let guard_a = claim(&key_a, 1).await.expect("A must be free again");
        assert!(claim(&key_b, 2).await.is_none());
        assert!(teardown_or_rearm(&client, &key_b).await); // consume B's mark
        release(guard_a).await;
        assert!(!teardown_or_rearm(&client, &key_b).await);
    }

    /// The claim→subscribe window (review round 1): a claim landing while
    /// the owner is still in Setup must not bounce — it parks until the
    /// owner reaches Live, so the coverage it is promised exists by the
    /// time it returns.
    #[tokio::test]
    async fn claim_during_setup_parks_until_the_owner_is_live() {
        let key = "ba".repeat(32);

        let guard = claim(&key, 1).await.expect("owner claims"); // Setup, no mark_live yet

        let contender = {
            let key = key.clone();
            tokio::spawn(async move { claim(&key, 1).await })
        };
        // Give the contender every chance to (wrongly) bounce early.
        for _ in 0..20 {
            tokio::task::yield_now().await;
        }
        assert!(
            !contender.is_finished(),
            "a claim during setup must park, not bounce off a REQ that is not live yet"
        );

        mark_live(guard).await;
        assert!(
            contender.await.unwrap().is_none(),
            "once the owner is live, the parked claim bounces — coverage now exists"
        );

        // The parked bounce counted as a re-arm: the lease is marked.
        let client = offline_client();
        assert!(teardown_or_rearm(&client, &key).await);
        assert!(!teardown_or_rearm(&client, &key).await);
    }

    /// Review round 2: the re-check a parked claim runs after `enable()`
    /// must pin the *entry*, not just the state. If the owner released (its
    /// notify lost before we registered) and a third claimant re-claimed the
    /// key, the key is again in `Setup` but behind a fresh gate — parking on
    /// the stale one would sleep forever on a `Notify` nobody will fire.
    #[tokio::test]
    async fn parked_recheck_rejects_a_replaced_setup_entry() {
        let key = "bc".repeat(32);

        let guard1 = claim(&key, 1).await.expect("E1 claims"); // E1: Setup
        let stale = registry()
            .lock()
            .await
            .get(&key)
            .unwrap()
            .setup_done
            .clone();
        assert!(parked_on_current_setup(&key, &stale).await);

        // Owner's setup fails: entry gone, its notify lost for anyone who
        // had not registered yet.
        release(guard1).await;
        assert!(!parked_on_current_setup(&key, &stale).await);

        // A third claimant re-claims: Setup again, but a different entry.
        let guard2 = claim(&key, 1).await.expect("key is free again");
        assert!(
            !parked_on_current_setup(&key, &stale).await,
            "same state, different entry: the stale gate must be rejected so the claim retries"
        );
        let current = registry()
            .lock()
            .await
            .get(&key)
            .unwrap()
            .setup_done
            .clone();
        assert!(parked_on_current_setup(&key, &current).await);

        // Once Live, nobody parks: the claim loop bounces instead.
        mark_live(guard2).await;
        assert!(!parked_on_current_setup(&key, &current).await);
        teardown(&offline_client(), &key).await;
    }

    /// The other half of the window: the owner's setup fails and releases.
    /// The parked claim must not be dropped with it — it retries, finds the
    /// key free, and becomes the new owner, so somebody actually subscribes.
    #[tokio::test]
    async fn claim_during_setup_takes_over_when_the_owner_releases() {
        let key = "bb".repeat(32);

        let guard = claim(&key, 1).await.expect("owner claims"); // owner: Setup

        let contender = {
            let key = key.clone();
            tokio::spawn(async move { claim(&key, 1).await })
        };
        for _ in 0..20 {
            tokio::task::yield_now().await;
        }
        assert!(!contender.is_finished());

        release(guard).await; // owner's setup failed
        let takeover = contender
            .await
            .unwrap()
            .expect("the parked claim must take over a released key and run setup itself");
        release(takeover).await;
    }

    /// Review round 2 (blocking): the teardown's purge must spare a pending
    /// record whose waiter is still attached. Its caller registered the
    /// record *before* calling `subscribe_daemon_messages` (the create/take
    /// ordering) and may be parked on the registry lock while this very
    /// dismantle runs — purging its record would strand it with a
    /// `NoDaemonResponse` on a request the daemon accepted.
    #[tokio::test]
    async fn dismantle_spares_a_pending_record_with_a_live_waiter() {
        use crate::mostro::pending::{pending_requests, PendingRequest, PendingRequestKind};

        let key = "ag".repeat(32);
        let client = offline_client();

        let guard = claim(&key, 1).await.expect("first claim owns the key");
        mark_live(guard).await;
        let (tx, _rx) = tokio::sync::oneshot::channel();
        pending_requests().lock().unwrap().insert(
            key.clone(),
            PendingRequest {
                request_id: 9,
                trade_index: 1,
                kind: PendingRequestKind::Take,
                tx: Some(tx),
            },
        );

        // Idle timeout, no re-arm: ownership released, REQ closed…
        assert!(!teardown_or_rearm(&client, &key).await);
        // …but the record with a live waiter survives for its caller.
        assert!(pending_requests().lock().unwrap().contains_key(&key));

        // Once the 10 s timeout detaches the waiter, the record is dead
        // state again and the next teardown drops it.
        pending_requests().lock().unwrap().get_mut(&key).unwrap().tx = None;
        let guard = claim(&key, 1).await.expect("key was released");
        mark_live(guard).await;
        assert!(!teardown_or_rearm(&client, &key).await);
        assert!(!pending_requests().lock().unwrap().contains_key(&key));
    }

    /// Review round 2: a guard dropped without `mark_live`/`release` — a
    /// panic unwinding the setup, a cancelled future — must free the key.
    /// Leaking the `Setup` entry would park every later claim (and thus
    /// every take/create on the key) forever, with no log and no recovery
    /// short of a restart.
    #[tokio::test]
    async fn dropped_setup_guard_frees_the_key() {
        let key = "ah".repeat(32);

        let guard = claim(&key, 1).await.expect("first claim owns the key");
        drop(guard); // abandoned setup

        let guard = claim(&key, 1)
            .await
            .expect("an abandoned setup must leave the key claimable");
        release(guard).await;
    }

    /// The parked contender is who the guard exists for: when the owner's
    /// setup is abandoned, the contender must take over, not hang.
    #[tokio::test]
    async fn parked_claim_takes_over_when_the_owners_guard_drops() {
        let key = "ai".repeat(32);

        let guard = claim(&key, 1).await.expect("owner claims"); // Setup

        let contender = {
            let key = key.clone();
            tokio::spawn(async move { claim(&key, 1).await })
        };
        for _ in 0..20 {
            tokio::task::yield_now().await;
        }
        assert!(!contender.is_finished());

        drop(guard); // owner's setup abandoned mid-flight
        let takeover = contender
            .await
            .unwrap()
            .expect("the parked claim must take over after the guard's Drop released the key");
        release(takeover).await;
    }
}
