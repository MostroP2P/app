/// Reputation API — post-trade rating and privacy mode management.
///
/// After a trade completes both parties are prompted to rate their counterpart
/// (1–5 stars).  Ratings are sent to the Mostro daemon via a `RateUser`
/// action in a NIP-59 Gift Wrap.
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
}

// ── Global singleton ──────────────────────────────────────────────────────────

static RATING_STORE: OnceLock<RatingStore> = OnceLock::new();

fn rating_store() -> &'static RatingStore {
    RATING_STORE.get_or_init(RatingStore::new)
}

// ── Helper ────────────────────────────────────────────────────────────────────

fn unix_now() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64
}

// ── Public API ────────────────────────────────────────────────────────────────

/// Submit a star rating for the counterparty of a completed trade.
///
/// **Preconditions**:
/// - `score` MUST be in the range 1–5.
/// - The local identity MUST NOT be in privacy mode.
/// - No rating MUST already have been submitted for this trade.
///
/// **Side effects**: Sends a `RateUser` action to the Mostro daemon via
/// NIP-59 Gift Wrap (deferred to Phase 14+ once bridge bindings are ready).
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

    // Send the RateUser message via NIP-59 Gift Wrap.  Roll back the slot
    // reservation if any step fails so the caller can retry after a transient
    // network error without hitting AlreadyRated.
    if let Some(trade_index) = crate::api::orders::trade_key_for_order(&trade_id).await {
        let dispatch_result: anyhow::Result<()> = async {
            let sender_keys =
                crate::api::identity::get_active_trade_keys(trade_index).await?;
            let mostro_pubkey =
                nostr_sdk::PublicKey::from_hex(crate::config::DEFAULT_MOSTRO_PUBKEY)
                    .map_err(|e| anyhow::anyhow!("invalid DEFAULT_MOSTRO_PUBKEY: {e}"))?;
            let event_json = crate::mostro::actions::rate_user(
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
            Ok(()) => log::info!(
                "[reputation] rate_user published trade={trade_id} score={score}"
            ),
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
    tokio::spawn(async move {
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
}
