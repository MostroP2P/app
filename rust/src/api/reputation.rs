/// Reputation API — post-trade rating and privacy mode management.
///
/// After a trade completes both parties are prompted to rate their counterpart
/// (1–5 stars).  Ratings are sent to the Mostro daemon via a `RateUser`
/// action over transport v2 (NIP-44, signed kind 14).
///
/// Privacy mode disables reputation data in both directions — no ratings are
/// sent or received when it is active.
///
/// All state is held in-memory until the DB persistence layer is wired
/// (Phase 12+).
use anyhow::{bail, Result};
use std::collections::HashMap;
use std::sync::{atomic::{AtomicBool, Ordering}, OnceLock};
use tokio::sync::{broadcast, RwLock};
use tokio::sync::broadcast::error::RecvError;

use crate::api::types::{RatingInfo, RatingReceivedEvent};
use crate::db::Storage;

// ── Rating store ──────────────────────────────────────────────────────────────

/// Both sides of a trade's rating, held together under a single map entry so
/// `mine` and `peer` ratings for the same trade never overwrite each other.
struct TradeRatings {
    /// Rating submitted by the local user (`is_mine = true`).
    mine: Option<RatingInfo>,
    /// Rating received from the counterparty (`is_mine = false`).
    peer: Option<RatingInfo>,
}

struct RatingStore {
    /// Per-trade ratings keyed by trade_id.
    ratings: std::sync::Arc<RwLock<HashMap<String, TradeRatings>>>,
    /// Broadcast channel; payload = incoming rating event.
    event_tx: broadcast::Sender<RatingReceivedEvent>,
    /// In-memory privacy mode flag.
    privacy_mode: AtomicBool,
}

impl RatingStore {
    fn new() -> Self {
        let (event_tx, _) = broadcast::channel(32);
        Self {
            ratings: std::sync::Arc::new(RwLock::new(HashMap::new())),
            event_tx,
            privacy_mode: AtomicBool::new(false),
        }
    }

    /// Return the local user's rating for a trade, falling back to the peer's
    /// rating if the local user has not yet submitted one.
    async fn get(&self, trade_id: &str) -> Option<RatingInfo> {
        self.ratings.read().await.get(trade_id).and_then(|r| {
            r.mine.clone().or_else(|| r.peer.clone())
        })
    }

    /// Atomically insert the local user's rating only if one has not been
    /// submitted yet.  Prevents TOCTOU races on concurrent `submit_rating`
    /// calls.  Does not affect the peer side.
    async fn try_insert_mine(&self, info: RatingInfo) -> Result<()> {
        let mut store = self.ratings.write().await;
        let entry = store
            .entry(info.trade_id.clone())
            .or_insert_with(|| TradeRatings { mine: None, peer: None });
        if entry.mine.is_some() {
            bail!(
                "AlreadyRated: a rating has already been submitted for trade {}",
                info.trade_id
            );
        }
        entry.mine = Some(info);
        Ok(())
    }

    /// Remove the local user's reserved rating slot for a trade.
    ///
    /// Called to roll back a slot reservation when the outbound dispatch fails
    /// so the caller can retry.  No-op if no slot exists for the trade.
    async fn remove_mine(&self, trade_id: &str) {
        let mut store = self.ratings.write().await;
        if let Some(entry) = store.get_mut(trade_id) {
            entry.mine = None;
            // Evict the map entry entirely when both sides are empty.
            if entry.peer.is_none() {
                store.remove(trade_id);
            }
        }
    }

    /// Insert or update the peer's incoming rating for a trade.
    /// Can be called multiple times safely (handles re-delivery).
    async fn insert_peer(&self, info: RatingInfo) {
        let mut store = self.ratings.write().await;
        let entry = store
            .entry(info.trade_id.clone())
            .or_insert_with(|| TradeRatings { mine: None, peer: None });
        entry.peer = Some(info);
    }

    /// `true` when the local user's rating slot for `trade_id` is already
    /// populated in memory — the fast path that lets callers skip the DB.
    async fn has_mine(&self, trade_id: &str) -> bool {
        self.ratings
            .read()
            .await
            .get(trade_id)
            .is_some_and(|r| r.mine.is_some())
    }

    /// Populate the local user's rating slot from a durable marker loaded off
    /// disk, without the `AlreadyRated` guard. Silent no-op if a slot is
    /// already present, so a live in-memory rating is never clobbered.
    async fn hydrate_mine(&self, info: RatingInfo) {
        let mut store = self.ratings.write().await;
        let entry = store
            .entry(info.trade_id.clone())
            .or_insert_with(|| TradeRatings { mine: None, peer: None });
        if entry.mine.is_none() {
            entry.mine = Some(info);
        }
    }
}

/// Bring the durable "I rated this trade" marker (issue #339) into the
/// in-memory store when the local user rated it in a previous session.
///
/// No-op when the slot is already in memory (the fast path), when persistence
/// is not wired yet, or when the trade was never rated. The persisted marker
/// is authoritative on load; the memory store stays the cache in front of it.
///
/// The score itself is not persisted — the rated state shows only a label, and
/// the sole consumer that matters (`ratedByMeProvider`) reads `is_mine` — so a
/// hydrated rating carries a placeholder score of `0`. Callers must not treat a
/// hydrated `is_mine` rating's score as the note that was actually given.
async fn hydrate_mine_from_db(trade_id: &str) {
    let store = rating_store();
    if store.has_mine(trade_id).await {
        return;
    }
    let Some(db) = crate::db::app_db::db() else {
        return;
    };
    match db.get_trade_by_order_id(trade_id).await {
        Ok(Some(trade)) => {
            if let Some(rated_at) = trade.rated_at {
                store
                    .hydrate_mine(RatingInfo {
                        trade_id: trade_id.to_string(),
                        score: 0,
                        is_mine: true,
                        created_at: rated_at,
                    })
                    .await;
            }
        }
        Ok(None) => {}
        Err(e) => log::warn!("[reputation] hydrate_mine_from_db(trade={trade_id}): {e}"),
    }
}

// ── Global singleton ──────────────────────────────────────────────────────────

static RATING_STORE: OnceLock<RatingStore> = OnceLock::new();

fn rating_store() -> &'static RatingStore {
    RATING_STORE.get_or_init(RatingStore::new)
}

// ── Helper ────────────────────────────────────────────────────────────────────

use crate::rt::unix_now;

// ── Public API ────────────────────────────────────────────────────────────────

/// Submit a star rating for the counterparty of a completed trade.
///
/// **Preconditions**:
/// - `score` MUST be in the range 1–5.
/// - The local identity MUST NOT be in privacy mode.
/// - No rating MUST already have been submitted for this trade.
///
/// **Side effects**: Sends a `RateUser` action to the Mostro daemon via
/// transport v2 (deferred to Phase 14+ once bridge bindings are ready).
///
/// **Errors**: `InvalidScore`, `PrivacyModeEnabled`, `AlreadyRated`.
pub async fn submit_rating(trade_id: String, score: u8) -> Result<()> {
    if !(1u8..=5).contains(&score) {
        bail!("InvalidScore: score must be between 1 and 5, got {score}");
    }

    let store = rating_store();

    if store.privacy_mode.load(Ordering::SeqCst) {
        bail!("PrivacyModeEnabled: cannot submit rating while privacy mode is active");
    }

    // Pull any prior-session rating into memory first, so the guard below fires
    // AlreadyRated across a restart too — otherwise the empty in-memory store
    // would let a second RateUser event go out on the wire (issue #339).
    hydrate_mine_from_db(&trade_id).await;

    // Reserve the slot atomically before attempting any outbound send.
    // This prevents two concurrent submit_rating calls from both reaching
    // publish_event — the second call fails here with AlreadyRated rather than
    // sending a duplicate RateUser message to Mostro.
    store
        .try_insert_mine(RatingInfo {
            trade_id: trade_id.clone(),
            score,
            is_mine: true,
            created_at: unix_now(),
        })
        .await?;

    // Send the RateUser message over transport v2.  Roll back the slot
    // reservation if any step fails so the caller can retry after a transient
    // network error without hitting AlreadyRated.
    if let Some(trade_index) = crate::api::orders::trade_key_for_order(&trade_id).await {
        let dispatch_result: anyhow::Result<()> = async {
            let sender_keys =
                crate::api::identity::get_active_trade_keys(trade_index).await?;
            // Rating is the one action that must land under the long-lived
            // identity key: the privacy-mode check above already refuses to
            // submit when the user opted out of reputation, so here we
            // resolve identity keys unconditionally via the same helper.
            let identity_keys =
                crate::api::identity::get_transport_identity_keys(&sender_keys).await?;
            let mostro_pubkey =
                nostr_sdk::PublicKey::from_hex(&crate::config::active_mostro_pubkey())
                    .map_err(|e| anyhow::anyhow!("invalid mostro pubkey: {e}"))?;
            let event_json = crate::mostro::actions::rate_user(
                &identity_keys,
                &sender_keys,
                &mostro_pubkey,
                &trade_id,
                trade_index,
                score,
            )
            .await?;
            crate::api::orders::publish_event(&event_json).await
        }
        .await;

        match dispatch_result {
            Ok(()) => {
                log::info!(
                    "[reputation] rate_user published trade={trade_id} score={score}"
                );
                // Persist the durable marker so the rated state and the guard
                // above survive a restart (issue #339). Best-effort: the rating
                // already went out on the wire, so a DB miss must not fail it —
                // the in-memory slot still holds it for the rest of the session.
                if let Some(db) = crate::db::app_db::db() {
                    if let Err(e) = db.mark_trade_rated(&trade_id, unix_now()).await {
                        log::warn!(
                            "[reputation] mark_trade_rated(trade={trade_id}) failed: {e}"
                        );
                    }
                }
            }
            Err(e) => {
                // Rollback: remove the reservation so the caller can retry.
                store.remove_mine(&trade_id).await;
                bail!("RateUserDispatchFailed: {e}");
            }
        }
    } else {
        // No trade key for this trade — store locally only (e.g. older session
        // where the key index was not persisted).
        log::warn!(
            "[reputation] no trade key found for trade={trade_id}; rating stored locally only"
        );
    }

    Ok(())
}

/// Check whether privacy mode is currently enabled.
pub fn get_privacy_mode() -> bool {
    rating_store().privacy_mode.load(Ordering::SeqCst)
}

/// Enable or disable privacy mode.
///
/// When enabled, no reputation data is sent or received in future trades and
/// session recovery becomes unavailable.
///
/// **Errors**: `NoIdentity` (identity check deferred to Phase 14+ bridge).
pub fn set_privacy_mode(enabled: bool) {
    // Best-effort identity check: log a warning if no identity is configured but
    // proceed anyway so the UI setting is never silently stuck.
    crate::rt::spawn(async move {
        if crate::api::identity::get_active_keys().await.is_err() {
            log::warn!("[reputation] set_privacy_mode({enabled}): no identity configured");
        }
    });
    rating_store()
        .privacy_mode
        .store(enabled, Ordering::SeqCst);
}

/// Get the rating submitted or received for a specific trade.
///
/// Returns `None` if no rating exists for the given trade.
pub async fn get_rating_for_trade(trade_id: String) -> Result<Option<RatingInfo>> {
    // Rehydrate from the durable marker so a trade rated in a previous session
    // still resolves as rated after a restart (issue #339); no-op once the slot
    // is in memory.
    hydrate_mine_from_db(&trade_id).await;
    Ok(rating_store().get(&trade_id).await)
}

/// Handle an incoming rating event from the counterparty.
///
/// Records the rating and broadcasts it to any active [RatingStream].
///
/// No-ops silently when privacy mode is active — incoming reputation data is
/// discarded in both directions when the user has opted out.
pub async fn handle_rating_received(
    trade_id: String,
    score: u8,
    from_pubkey: String,
) -> Result<()> {
    if !(1u8..=5).contains(&score) {
        bail!("InvalidScore: received invalid score {score} for trade {trade_id}");
    }

    let store = rating_store();

    // Discard incoming ratings when privacy mode is active.
    if store.privacy_mode.load(Ordering::SeqCst) {
        return Ok(());
    }

    let event = RatingReceivedEvent {
        trade_id: trade_id.clone(),
        score,
        from_pubkey,
    };

    // Record as a peer rating (is_mine = false).
    store
        .insert_peer(RatingInfo {
            trade_id,
            score,
            is_mine: false,
            created_at: unix_now(),
        })
        .await;

    let _ = store.event_tx.send(event);
    Ok(())
}

// ── Stream ────────────────────────────────────────────────────────────────────

/// A stream that emits incoming [RatingReceivedEvent]s.
pub struct RatingStream {
    rx: broadcast::Receiver<RatingReceivedEvent>,
}

impl RatingStream {
    /// Poll for the next incoming rating event.
    ///
    /// `RecvError::Lagged` is handled gracefully: dropped messages are skipped
    /// and the loop continues rather than terminating the stream.
    pub async fn next(&mut self) -> Result<RatingReceivedEvent> {
        loop {
            match self.rx.recv().await {
                Ok(event) => return Ok(event),
                Err(RecvError::Lagged(_)) => continue,
                Err(RecvError::Closed) => bail!("RatingStream closed: channel sender dropped"),
            }
        }
    }
}

/// Subscribe to incoming rating events.
pub fn on_rating_received() -> RatingStream {
    let rx = rating_store().event_tx.subscribe();
    RatingStream { rx }
}

// ── Tests ────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Mutex, OnceLock};

    /// Serializes tests that mutate the global `privacy_mode` flag so they
    /// don't race with each other or with tests that call `submit_rating`.
    fn privacy_lock() -> &'static Mutex<()> {
        static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
        LOCK.get_or_init(|| Mutex::new(()))
    }

    #[tokio::test]
    async fn submit_rating_stores_record() {
        let _guard = privacy_lock().lock().unwrap();
        set_privacy_mode(false); // ensure clean state
        let trade_id = format!("t-{}", uuid::Uuid::new_v4());
        submit_rating(trade_id.clone(), 4).await.unwrap();

        let info = get_rating_for_trade(trade_id.clone()).await.unwrap().unwrap();
        assert_eq!(info.score, 4);
        assert!(info.is_mine);
        assert_eq!(info.trade_id, trade_id);
    }

    #[tokio::test]
    async fn invalid_score_is_rejected() {
        let trade_id = format!("t-{}", uuid::Uuid::new_v4());
        let err = submit_rating(trade_id, 6).await.unwrap_err();
        assert!(err.to_string().contains("InvalidScore"));
    }

    #[tokio::test]
    async fn zero_score_is_rejected() {
        let trade_id = format!("t-{}", uuid::Uuid::new_v4());
        let err = submit_rating(trade_id, 0).await.unwrap_err();
        assert!(err.to_string().contains("InvalidScore"));
    }

    #[tokio::test]
    async fn duplicate_rating_is_rejected() {
        let _guard = privacy_lock().lock().unwrap();
        set_privacy_mode(false); // ensure clean state
        let trade_id = format!("t-{}", uuid::Uuid::new_v4());
        submit_rating(trade_id.clone(), 3).await.unwrap();
        let err = submit_rating(trade_id, 5).await.unwrap_err();
        assert!(err.to_string().contains("AlreadyRated"));
    }

    #[tokio::test]
    async fn privacy_mode_blocks_rating() {
        let _guard = privacy_lock().lock().unwrap();
        set_privacy_mode(true);
        let trade_id = format!("t-{}", uuid::Uuid::new_v4());
        let err = submit_rating(trade_id, 4).await.unwrap_err();
        assert!(err.to_string().contains("PrivacyModeEnabled"));
        set_privacy_mode(false);
    }

    #[tokio::test]
    async fn privacy_mode_toggle() {
        let _guard = privacy_lock().lock().unwrap();
        set_privacy_mode(true);
        assert!(get_privacy_mode());
        set_privacy_mode(false);
        assert!(!get_privacy_mode());
    }

    #[tokio::test]
    async fn handle_rating_received_stores_peer_rating() {
        let _guard = privacy_lock().lock().unwrap();
        set_privacy_mode(false); // ensure clean state
        let trade_id = format!("t-{}", uuid::Uuid::new_v4());
        handle_rating_received(trade_id.clone(), 5, "peer_pubkey_abc".into())
            .await
            .unwrap();

        let info = get_rating_for_trade(trade_id).await.unwrap().unwrap();
        assert_eq!(info.score, 5);
        assert!(!info.is_mine);
    }

    #[tokio::test]
    async fn handle_rating_received_discarded_in_privacy_mode() {
        let _guard = privacy_lock().lock().unwrap();
        set_privacy_mode(true);
        let trade_id = format!("t-{}", uuid::Uuid::new_v4());
        handle_rating_received(trade_id.clone(), 4, "peer_pubkey_xyz".into())
            .await
            .unwrap(); // should succeed (silently discarded)

        let info = get_rating_for_trade(trade_id).await.unwrap();
        assert!(info.is_none(), "peer rating should be discarded in privacy mode");
        set_privacy_mode(false);
    }

    #[tokio::test]
    async fn mine_and_peer_ratings_coexist_for_same_trade() {
        let _guard = privacy_lock().lock().unwrap();
        set_privacy_mode(false);
        let trade_id = format!("t-{}", uuid::Uuid::new_v4());

        // Submit my rating first.
        submit_rating(trade_id.clone(), 4).await.unwrap();

        // Receive peer rating for the same trade.
        handle_rating_received(trade_id.clone(), 5, "peer_pubkey".into())
            .await
            .unwrap();

        // get_rating_for_trade returns mine (preferred).
        let info = get_rating_for_trade(trade_id.clone()).await.unwrap().unwrap();
        assert!(info.is_mine);
        assert_eq!(info.score, 4);

        // Submitting my rating a second time is still rejected.
        let err = submit_rating(trade_id, 3).await.unwrap_err();
        assert!(err.to_string().contains("AlreadyRated"));
    }

    /// `hydrate_mine` seeds an empty slot (the restart case: a marker loaded
    /// off disk populates a fresh in-memory store) but never clobbers a rating
    /// already held for the session — the live score wins over the placeholder.
    #[tokio::test]
    async fn hydrate_mine_seeds_but_never_clobbers() {
        let store = rating_store();
        let trade_id = format!("t-{}", uuid::Uuid::new_v4());

        // Empty slot: hydration seeds it (score 0 placeholder, is_mine).
        assert!(!store.has_mine(&trade_id).await);
        store
            .hydrate_mine(RatingInfo {
                trade_id: trade_id.clone(),
                score: 0,
                is_mine: true,
                created_at: 1_700_000_000,
            })
            .await;
        assert!(store.has_mine(&trade_id).await);
        let info = store.get(&trade_id).await.unwrap();
        assert!(info.is_mine);
        assert_eq!(info.created_at, 1_700_000_000);

        // A subsequent hydrate (e.g. a redundant DB read) is a silent no-op —
        // it must not overwrite the slot already present.
        store
            .hydrate_mine(RatingInfo {
                trade_id: trade_id.clone(),
                score: 5,
                is_mine: true,
                created_at: 42,
            })
            .await;
        let info = store.get(&trade_id).await.unwrap();
        assert_eq!(info.created_at, 1_700_000_000, "hydrate must not clobber");
    }

    /// End-to-end restart coverage (issue #339): a `rated_at` marker persisted
    /// by a previous session — with `RATING_STORE` empty, as it is on a fresh
    /// launch — resolves the trade as rated (AC1) and blocks a second rating
    /// (AC2). Uses a real store via `init_db`, following the `escrow.rs`
    /// precedent; a fresh order id keeps the shared process-wide DB and rating
    /// store uncontaminated by (and from) the other tests in this binary.
    #[tokio::test]
    async fn persisted_marker_survives_restart_and_blocks_second_rating() {
        use crate::api::types::*;

        let _guard = privacy_lock().lock().unwrap();
        set_privacy_mode(false);

        // A real store — the point of the test. `init_db` is a process-wide
        // OnceCell: first caller wins and the rest share it, so leave the file.
        let path = std::env::temp_dir()
            .join(format!("mostro_reputation_rated_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("a real store is the point");

        // Fresh order id → empty RATING_STORE slot (the restart condition) and
        // a DB row no other test touches.
        let order_id = format!("order-{}", uuid::Uuid::new_v4());

        let trade = TradeInfo {
            id: format!("row-{}", uuid::Uuid::new_v4()),
            order: OrderInfo {
                id: order_id.clone(),
                kind: OrderKind::Sell,
                status: OrderStatus::SettledHoldInvoice,
                amount_sats: None,
                fiat_amount: Some(100.0),
                fiat_amount_min: None,
                fiat_amount_max: None,
                fiat_code: "CUP".into(),
                payment_method: "bank".into(),
                premium: 0.0,
                creator_pubkey: "maker".into(),
                created_at: 1,
                expires_at: None,
                is_mine: false,
                rating: 0.0,
                total_reviews: 0,
                days_active: 0,
            },
            role: TradeRole::Buyer,
            counterparty_pubkey: String::new(),
            current_step: TradeStep::Buyer(BuyerStep::OrderTaken),
            hold_invoice: None,
            buyer_invoice: None,
            trade_key_index: 1,
            cooperative_cancel_state: None,
            timeout_at: None,
            started_at: 1,
            completed_at: Some(1),
            outcome: Some(TradeOutcome::Success),
            peer_rating: None,
            peer_reviews: None,
            peer_days: None,
            rated_at: None,
        };
        db.save_trade(&trade).await.unwrap();

        // Simulate a previous session having rated: write the durable marker
        // straight to the row, WITHOUT touching RATING_STORE (that is what a
        // restart wipes).
        let ts = 1_700_000_000;
        db.mark_trade_rated(&order_id, ts).await.unwrap();

        // AC1: with an empty in-memory store, the trade still resolves as rated.
        let info = get_rating_for_trade(order_id.clone())
            .await
            .unwrap()
            .expect("marker rehydrates the rating");
        assert!(info.is_mine, "a rehydrated marker is the local user's rating");
        assert_eq!(info.created_at, ts);

        // AC2: a second rating is refused across the restart — the guard fires
        // before any trade-key lookup or dispatch, so this is deterministic
        // without relays.
        let err = submit_rating(order_id, 4).await.unwrap_err();
        assert!(
            err.to_string().contains("AlreadyRated"),
            "persisted marker must block a second rating, got: {err}"
        );
    }
}
