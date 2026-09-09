//! Single-owner registry for per-trade daemon-message subscriptions (#325).
//!
//! Every per-trade watcher (`subscribe_daemon_messages`) owns a relay-side
//! subscription plus, transitively, the pending-request record for its trade
//! key: the watcher's exit path unsubscribes the REQ and purges the record
//! unconditionally (`purge_pending_request` is documented as "only for the
//! end of the per-trade subscription's lifetime"). Two watchers over the same
//! trade key therefore cannot coexist — the older one's teardown would kill
//! the newer one's live subscription and strand its waiting caller with a
//! `NoDaemonResponse` on a request the daemon actually accepted.
//!
//! Today every caller derives a fresh trade key first, so duplicates cannot
//! happen; the restore apply (#218) breaks that invariant by re-arming
//! watchers for already-covered keys, and it must be idempotent. This
//! registry makes re-arming safe by giving the lifecycle a single owner:
//!
//! * **Idempotence by membership**: [`try_claim`] admits exactly one owner
//!   per trade key. A second claim is a bounce, not a second watcher.
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
//!   this window open — do not copy that ordering.
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

use std::collections::HashMap;
use std::sync::OnceLock;

/// Trade pubkey hex → re-armed flag. Key present = the watcher owns the
/// subscription; `true` = a claim bounced since the owner last checked, so
/// its idle-timeout exit must refresh the lease instead of tearing down.
static ACTIVE_TRADE_SUBS: OnceLock<tokio::sync::Mutex<HashMap<String, bool>>> = OnceLock::new();

fn registry() -> &'static tokio::sync::Mutex<HashMap<String, bool>> {
    ACTIVE_TRADE_SUBS.get_or_init(|| tokio::sync::Mutex::new(HashMap::new()))
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

/// Claim ownership of `trade_pubkey_hex`'s subscription lifecycle.
///
/// Returns `true` when the caller is now the single owner and must subscribe
/// and run the watcher. Returns `false` when a watcher already owns the key:
/// the relay-side subscription stays live, the pending record stays intact,
/// and the bounce is recorded as a lease refresh so the owner outlives the
/// caller's interest (see [`teardown_or_rearm`]).
pub(crate) async fn try_claim(trade_pubkey_hex: &str) -> bool {
    let mut map = registry().lock().await;
    match map.get_mut(trade_pubkey_hex) {
        Some(rearmed) => {
            *rearmed = true;
            false
        }
        None => {
            map.insert(trade_pubkey_hex.to_string(), false);
            true
        }
    }
}

/// Release a claim whose watcher never started (setup failed between claim
/// and subscribe). No teardown: there is no REQ to close, and the pending
/// record — if any — belongs to its caller's own rollback/timeout paths.
pub(crate) async fn release(trade_pubkey_hex: &str) {
    registry().lock().await.remove(trade_pubkey_hex);
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
    if let Some(rearmed) = map.get_mut(trade_pubkey_hex) {
        if *rearmed {
            *rearmed = false;
            crate::api::logging::blog_info(
                "orders",
                format!(
                    "daemon-message watcher lease refreshed for trade={}",
                    &trade_pubkey_hex[..8.min(trade_pubkey_hex.len())]
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
    map: &mut HashMap<String, bool>,
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
                &trade_pubkey_hex[..8.min(trade_pubkey_hex.len())]
            ),
        );
    }

    // The subscription bounds the pending record's lifetime: once no reply
    // can be delivered here anymore, a still-unconsumed record (request timed
    // out and no genuine late reply ever arrived) is dead state — drop it,
    // whatever attempt it belongs to.
    crate::mostro::pending::purge_pending_request(trade_pubkey_hex);

    map.remove(trade_pubkey_hex);
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
        assert!(try_claim(&key).await);
        assert!(!try_claim(&key).await);
        release(&key).await;
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

        assert!(try_claim(&key).await);
        assert!(!try_claim(&key).await); // re-arm bounces, marks the lease

        // Idle timeout fires: the mark wins, the owner keeps running…
        assert!(teardown_or_rearm(&client, &key).await);
        // …and the mark is consumed: the next idle timeout dismantles.
        assert!(!teardown_or_rearm(&client, &key).await);

        // Fully released: the key is claimable from scratch (what #218
        // needs after an owner genuinely expires between applies).
        assert!(try_claim(&key).await);
        release(&key).await;
    }

    /// Criterion 2 (#325): re-arming a key with a live owner must not purge
    /// its pending request — the purge belongs exclusively to the final
    /// teardown, after any lease refresh has been honored.
    #[tokio::test]
    async fn pending_record_survives_a_lease_refresh_and_dies_with_teardown() {
        use crate::mostro::pending::{pending_requests, PendingRequest, PendingRequestKind};

        let key = "ac".repeat(32);
        let client = offline_client();

        assert!(try_claim(&key).await);
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
        assert!(!try_claim(&key).await);
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

        assert!(try_claim(&key).await);
        assert!(!try_claim(&key).await); // mark set
        teardown(&client, &key).await;

        // Ownership fully released despite the mark.
        assert!(try_claim(&key).await);
        release(&key).await;
    }

    /// Criterion 3 (#325): teardown is targeted — dismantling one trade's
    /// subscription releases only that key and leaves other owners intact.
    #[tokio::test]
    async fn teardown_of_one_key_leaves_other_owners_intact() {
        let key_a = "ae".repeat(32);
        let key_b = "af".repeat(32);
        let client = offline_client();

        assert!(try_claim(&key_a).await);
        assert!(try_claim(&key_b).await);

        assert!(!teardown_or_rearm(&client, &key_a).await);

        // A is free again; B is still owned.
        assert!(try_claim(&key_a).await);
        assert!(!try_claim(&key_b).await);
        assert!(teardown_or_rearm(&client, &key_b).await); // consume B's mark
        release(&key_a).await;
        assert!(!teardown_or_rearm(&client, &key_b).await);
    }
}
