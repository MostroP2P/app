/// Disputes API — open, track, and resolve trade disputes.
///
/// Dispute initiation sends a `Dispute` action to the Mostro daemon via NIP-59
/// Gift Wrap.  Incoming admin actions (`adminTookDispute`, `adminSettled`,
/// `adminCanceled`) update the local `Dispute` record and — for
/// `adminTookDispute` — trigger ECDH admin shared key derivation via the
/// session manager.
///
/// All state is held in-memory until the DB persistence layer is wired
/// (Phase 12+).
use anyhow::{anyhow, bail, Result};
use std::collections::HashMap;
use std::sync::OnceLock;
use tokio::sync::{broadcast, RwLock};
use tokio::sync::broadcast::error::RecvError;

use crate::api::types::{Dispute, DisputeResolution, DisputeStatus};

// ── Dispute store ─────────────────────────────────────────────────────────────

struct DisputeStore {
    /// Disputes keyed by trade_id.
    disputes: std::sync::Arc<RwLock<HashMap<String, Dispute>>>,
    /// Broadcast channel; payload = updated Dispute.
    update_tx: broadcast::Sender<Dispute>,
}

impl DisputeStore {
    fn new() -> Self {
        let (update_tx, _) = broadcast::channel(32);
        Self {
            disputes: std::sync::Arc::new(RwLock::new(HashMap::new())),
            update_tx,
        }
    }

    async fn upsert(&self, dispute: Dispute) {
        {
            let mut store = self.disputes.write().await;
            store.insert(dispute.trade_id.clone(), dispute.clone());
        }
        let _ = self.update_tx.send(dispute);
    }

    async fn get(&self, trade_id: &str) -> Option<Dispute> {
        self.disputes.read().await.get(trade_id).cloned()
    }

    /// Atomically insert a new dispute only if no active (non-Resolved)
    /// dispute exists for the trade. Prevents TOCTOU races on concurrent
    /// `open_dispute` calls.
    async fn try_insert_if_absent_or_resolved(&self, dispute: Dispute) -> Result<Dispute> {
        let mut store = self.disputes.write().await;
        if let Some(existing) = store.get(&dispute.trade_id) {
            if existing.status != DisputeStatus::Resolved {
                bail!(
                    "DisputeAlreadyOpen: dispute already exists for trade {}",
                    dispute.trade_id
                );
            }
        }
        store.insert(dispute.trade_id.clone(), dispute.clone());
        // Notify subscribers after releasing the write lock.
        drop(store);
        let _ = self.update_tx.send(dispute.clone());
        Ok(dispute)
    }
}

// ── Global singleton ──────────────────────────────────────────────────────────

static DISPUTE_STORE: OnceLock<DisputeStore> = OnceLock::new();

fn dispute_store() -> &'static DisputeStore {
    DISPUTE_STORE.get_or_init(DisputeStore::new)
}

// ── Helper ────────────────────────────────────────────────────────────────────

fn unix_now() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64
}

// ── Public API ────────────────────────────────────────────────────────────────

/// Initiate a dispute on an active trade.
///
/// Sends a `Dispute` action to the Mostro daemon via NIP-59 Gift Wrap and
/// creates a local `Dispute` record.
///
/// **Preconditions**: Trade MUST be disputable (funds in escrow). No existing
/// open dispute for this trade.
///
/// **Errors**: `TradeNotDisputable`, `DisputeAlreadyOpen`, `ProtocolError`.
pub async fn open_dispute(trade_id: String, reason: Option<String>) -> Result<Dispute> {
    if trade_id.trim().is_empty() {
        bail!("TradeNotDisputable: trade_id must not be empty");
    }

    // TODO(Phase 12+): Look up session to get trade key + mostro pubkey, then
    // send a Dispute MostroMessage via NIP-59 Gift Wrap.

    let dispute = Dispute {
        id: uuid::Uuid::new_v4().to_string(),
        trade_id: trade_id.clone(),
        status: DisputeStatus::Open,
        initiated_by_me: true,
        reason,
        admin_pubkey: None,
        resolution: None,
        opened_at: unix_now(),
        resolved_at: None,
        is_read: true,
    };

    dispute_store()
        .try_insert_if_absent_or_resolved(dispute)
        .await
}

/// Submit free-text evidence for an open dispute.
///
/// Delivered as an admin-type message in the dispute chat.
///
/// **Errors**: `NoOpenDispute`, `EvidenceEmpty`.
pub async fn submit_evidence(trade_id: String, text: String) -> Result<()> {
    if text.trim().is_empty() {
        bail!("EvidenceEmpty: text must not be empty");
    }

    let dispute = dispute_store()
        .get(&trade_id)
        .await
        .ok_or_else(|| anyhow!("NoOpenDispute: no dispute for trade {trade_id}"))?;

    if dispute.status == DisputeStatus::Resolved {
        bail!("NoOpenDispute: dispute for trade {trade_id} is already resolved");
    }

    // TODO(Phase 12+): Send the text as an admin-type NIP-59 message to the
    // admin's pubkey (stored in dispute.admin_pubkey once assigned).
    let _ = dispute;

    bail!("NotImplemented: evidence submission not yet implemented")
}

/// Get dispute details for a trade.
///
/// Returns `None` if no dispute exists.
pub async fn get_dispute(trade_id: String) -> Result<Option<Dispute>> {
    Ok(dispute_store().get(&trade_id).await)
}

/// Handle an incoming `adminTookDispute` event.
///
/// Extracts the admin pubkey, marks the dispute as `InReview`, and triggers
/// ECDH admin shared key derivation via the session manager.
///
/// TODO(Phase 12+): Derive `adminSharedKey` from trade key + admin pubkey
/// and store in the session via `SessionManager::set_admin_shared_key`.
pub async fn handle_admin_took_dispute(trade_id: String, admin_pubkey: String) -> Result<()> {
    let mut dispute = dispute_store()
        .get(&trade_id)
        .await
        .ok_or_else(|| anyhow!("DisputeNotFound: no dispute for trade {trade_id}"))?;

    if dispute.status != DisputeStatus::Open {
        bail!(
            "InvalidState: dispute for trade {trade_id} is not open (current: {:?})",
            dispute.status
        );
    }

    dispute.status = DisputeStatus::InReview;
    dispute.admin_pubkey = Some(admin_pubkey);
    dispute.is_read = false;
    dispute_store().upsert(dispute).await;

    Ok(())
}

/// Handle an incoming `adminSettled` event (admin resolved in buyer's favour).
pub async fn handle_admin_settled(trade_id: String) -> Result<()> {
    resolve_dispute(trade_id, DisputeResolution::FundsToMe).await
}

/// Handle an incoming `adminCanceled` event (admin refunded the seller).
pub async fn handle_admin_canceled(trade_id: String) -> Result<()> {
    resolve_dispute(trade_id, DisputeResolution::FundsToCounterparty).await
}

async fn resolve_dispute(trade_id: String, resolution: DisputeResolution) -> Result<()> {
    let mut dispute = dispute_store()
        .get(&trade_id)
        .await
        .ok_or_else(|| anyhow!("DisputeNotFound: no dispute for trade {trade_id}"))?;

    if dispute.status == DisputeStatus::Resolved {
        bail!("InvalidState: dispute for trade {trade_id} is already resolved");
    }

    dispute.status = DisputeStatus::Resolved;
    dispute.resolution = Some(resolution);
    dispute.resolved_at = Some(unix_now());
    dispute.is_read = false;
    dispute_store().upsert(dispute).await;

    Ok(())
}

// ── Stream ────────────────────────────────────────────────────────────────────

/// A stream that emits updated [Dispute] records for a specific trade.
pub struct DisputeStream {
    rx: broadcast::Receiver<Dispute>,
    trade_id: String,
}

impl DisputeStream {
    /// Poll for the next dispute update matching this trade.
    ///
    /// `RecvError::Lagged` is handled gracefully: dropped messages are skipped
    /// and the loop continues rather than terminating the stream.
    pub async fn next(&mut self) -> Result<Dispute> {
        loop {
            match self.rx.recv().await {
                Ok(dispute) if dispute.trade_id == self.trade_id => return Ok(dispute),
                Ok(_) => continue, // different trade — keep waiting
                Err(RecvError::Lagged(_)) => continue, // missed messages; keep going
                Err(RecvError::Closed) => bail!("DisputeStream closed: channel sender dropped"),
            }
        }
    }
}

/// Subscribe to dispute updates for a specific trade.
pub async fn on_dispute_updated(trade_id: String) -> Result<DisputeStream> {
    let rx = dispute_store().update_tx.subscribe();
    Ok(DisputeStream { rx, trade_id })
}

// ── Tests ────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn open_dispute_creates_record() {
        let trade_id = format!("t-{}", uuid::Uuid::new_v4());
        let dispute = open_dispute(trade_id.clone(), Some("Price disagreement".into()))
            .await
            .unwrap();

        assert_eq!(dispute.trade_id, trade_id);
        assert_eq!(dispute.status, DisputeStatus::Open);
        assert!(dispute.initiated_by_me);
        assert_eq!(dispute.reason.as_deref(), Some("Price disagreement"));
    }

    #[tokio::test]
    async fn duplicate_dispute_is_rejected() {
        let trade_id = format!("t-{}", uuid::Uuid::new_v4());
        open_dispute(trade_id.clone(), None).await.unwrap();

        let err = open_dispute(trade_id, None).await.unwrap_err();
        assert!(err.to_string().contains("DisputeAlreadyOpen"));
    }

    #[tokio::test]
    async fn empty_evidence_is_rejected() {
        let trade_id = format!("t-{}", uuid::Uuid::new_v4());
        open_dispute(trade_id.clone(), None).await.unwrap();

        let err = submit_evidence(trade_id, "  ".into()).await.unwrap_err();
        assert!(err.to_string().contains("EvidenceEmpty"));
    }

    #[tokio::test]
    async fn admin_took_dispute_sets_in_review() {
        let trade_id = format!("t-{}", uuid::Uuid::new_v4());
        open_dispute(trade_id.clone(), None).await.unwrap();

        handle_admin_took_dispute(trade_id.clone(), "adminpubkey123".into())
            .await
            .unwrap();

        let d = get_dispute(trade_id).await.unwrap().unwrap();
        assert_eq!(d.status, DisputeStatus::InReview);
        assert_eq!(d.admin_pubkey.as_deref(), Some("adminpubkey123"));
    }

    #[tokio::test]
    async fn admin_settled_resolves_dispute() {
        let trade_id = format!("t-{}", uuid::Uuid::new_v4());
        open_dispute(trade_id.clone(), None).await.unwrap();

        handle_admin_settled(trade_id.clone()).await.unwrap();

        let d = get_dispute(trade_id).await.unwrap().unwrap();
        assert_eq!(d.status, DisputeStatus::Resolved);
        assert_eq!(d.resolution, Some(DisputeResolution::FundsToMe));
        assert!(d.resolved_at.is_some());
    }
}
