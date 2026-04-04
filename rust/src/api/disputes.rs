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

    #[allow(dead_code)]
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

    /// Atomically update a dispute under the write lock.
    ///
    /// `f` receives a mutable reference to the dispute and should return
    /// `Ok(())` to commit the change or `Err(...)` to abort (no mutation
    /// is persisted).  The broadcast notification is sent **after** the
    /// lock is released.
    async fn update_conditional<F>(&self, trade_id: &str, f: F) -> Result<()>
    where
        F: FnOnce(&mut Dispute) -> Result<()>,
    {
        let updated = {
            let mut store = self.disputes.write().await;
            let dispute = store
                .get_mut(trade_id)
                .ok_or_else(|| anyhow!("DisputeNotFound: no dispute for trade {trade_id}"))?;
            f(dispute)?;
            dispute.clone()
        }; // write lock released here
        let _ = self.update_tx.send(updated);
        Ok(())
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

    // Dispatch Action::Dispute to Mostro BEFORE creating the local record so
    // that a failed publish does not leave an un-retryable "open" slot in the
    // dispute store.  Only on a successful publish do we persist the dispute.
    let trade_index = crate::api::orders::trade_key_for_order(&trade_id)
        .await
        .ok_or_else(|| anyhow!("TradeNotDisputable: no trade key for trade {trade_id}"))?;

    let event_json: String = async {
        let sender_keys =
            crate::api::identity::get_active_trade_keys(trade_index).await?;
        let mostro_pubkey =
            nostr_sdk::PublicKey::from_hex(&crate::config::active_mostro_pubkey())
                .map_err(|e| anyhow!("invalid mostro pubkey: {e}"))?;
        crate::mostro::actions::dispute(&sender_keys, &mostro_pubkey, &trade_id, trade_index)
            .await
    }
    .await
    .map_err(|e| anyhow!("ProtocolError: could not build Dispute message: {e}"))?;

    crate::api::orders::publish_event(&event_json)
        .await
        .map_err(|e| anyhow!("ProtocolError: publish failed: {e}"))?;

    log::info!("[disputes] Dispute dispatched for trade={trade_id}");

    // Publish succeeded — persist the dispute record.
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

    // Admin pubkey must be known (set by handle_admin_took_dispute).
    let admin_pubkey_hex = dispute
        .admin_pubkey
        .as_deref()
        .ok_or_else(|| anyhow!("AdminNotAssigned: dispute has no admin yet"))?;

    let admin_pubkey = nostr_sdk::PublicKey::from_hex(admin_pubkey_hex)
        .map_err(|e| anyhow!("invalid admin pubkey: {e}"))?;

    // Look up the trade key index.
    let trade_index = crate::api::orders::trade_key_for_order(&trade_id)
        .await
        .ok_or_else(|| anyhow!("TradeNotFound: no trade key for {trade_id}"))?;

    let sender_keys = crate::api::identity::get_active_trade_keys(trade_index).await?;

    // Build the evidence payload.
    let payload = serde_json::json!({
        "type": "evidence",
        "trade_id": trade_id,
        "text": text,
    })
    .to_string();

    // Wrap and send as NIP-59 Kind-14 DM to the admin.
    let event_json = crate::nostr::gift_wrap::wrap(
        &sender_keys,
        &admin_pubkey,
        &payload,
        nostr_sdk::Kind::from(14u16),
    )
    .await
    .map_err(|e| anyhow!("gift wrap failed: {e}"))?;

    crate::api::orders::publish_event(&event_json)
        .await
        .map_err(|e| anyhow!("publish failed: {e}"))?;

    log::info!("[disputes] evidence submitted for trade={trade_id}");
    Ok(())
}

/// Get dispute details for a trade.
///
/// Returns `None` if no dispute exists.
pub async fn get_dispute(trade_id: String) -> Result<Option<Dispute>> {
    Ok(dispute_store().get(&trade_id).await)
}

/// Handle an incoming `adminTookDispute` event.
///
/// Extracts the admin pubkey, marks the dispute as `InReview`, and derives
/// the ECDH admin shared key for dispute chat encryption.
pub async fn handle_admin_took_dispute(trade_id: String, admin_pubkey: String) -> Result<()> {
    let admin_pubkey_for_key = admin_pubkey.clone();

    dispute_store()
        .update_conditional(&trade_id, move |dispute| {
            if dispute.status != DisputeStatus::Open {
                return Err(anyhow!(
                    "InvalidState: dispute is not open (current: {:?})",
                    dispute.status
                ));
            }
            dispute.status = DisputeStatus::InReview;
            dispute.admin_pubkey = Some(admin_pubkey);
            dispute.is_read = false;
            Ok(())
        })
        .await?;

    // Derive adminSharedKey and store in session.
    //
    // This key allows the user to decrypt admin messages in the dispute
    // chat (the admin encrypts to the trade pubkey, not the identity key).
    //
    // Best-effort: if no trade key or session exists we log a warning but
    // do not fail — the dispute status update already succeeded.
    let derive_result: Result<()> = async {
        let trade_index = crate::api::orders::trade_key_for_order(&trade_id)
            .await
            .ok_or_else(|| anyhow!("no trade key for trade {trade_id}"))?;
        let trade_keys = crate::api::identity::get_active_trade_keys(trade_index).await?;
        let admin_pk = nostr_sdk::PublicKey::from_hex(&admin_pubkey_for_key)
            .map_err(|e| anyhow!("invalid admin pubkey: {e}"))?;
        let shared_key = crate::crypto::ecdh::derive_nip04_shared_key(&trade_keys, &admin_pk)?;
        crate::mostro::session::session_manager()
            .set_admin_shared_key(&trade_id, shared_key)
            .await?;
        log::info!("[disputes] adminSharedKey derived for trade={trade_id}");
        Ok(())
    }
    .await;

    if let Err(e) = derive_result {
        log::warn!("[disputes] could not derive adminSharedKey for trade={trade_id}: {e}");
    }

    Ok(())
}

/// Handle an incoming `adminSettled` event (admin resolved in buyer's favour).
pub async fn handle_admin_settled(trade_id: String) -> Result<()> {
    resolve_dispute(trade_id, DisputeResolution::FundsToBuyer).await
}

/// Handle an incoming `adminCanceled` event (admin refunded the seller).
pub async fn handle_admin_canceled(trade_id: String) -> Result<()> {
    resolve_dispute(trade_id, DisputeResolution::FundsToSeller).await
}

async fn resolve_dispute(trade_id: String, resolution: DisputeResolution) -> Result<()> {
    dispute_store()
        .update_conditional(&trade_id, move |dispute| {
            if dispute.status == DisputeStatus::Resolved {
                return Err(anyhow!("InvalidState: dispute is already resolved"));
            }
            dispute.status = DisputeStatus::Resolved;
            dispute.resolution = Some(resolution);
            dispute.resolved_at = Some(unix_now());
            dispute.is_read = false;
            Ok(())
        })
        .await
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

    /// Insert a dispute directly into the store, bypassing dispatch.
    ///
    /// Used in unit tests that exercise store operations (admin events,
    /// evidence validation, etc.) without needing a live relay or trade key.
    async fn seed_dispute(trade_id: &str, reason: Option<String>) -> Dispute {
        let dispute = Dispute {
            id: uuid::Uuid::new_v4().to_string(),
            trade_id: trade_id.to_string(),
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
            .expect("seed_dispute: insert failed")
    }

    #[tokio::test]
    async fn open_dispute_requires_trade_key() {
        // open_dispute now dispatches to Mostro before persisting; without a
        // trade key it must return TradeNotDisputable rather than silently
        // storing a local-only dispute that the daemon never received.
        let trade_id = format!("t-{}", uuid::Uuid::new_v4());
        let err = open_dispute(trade_id, Some("Price disagreement".into()))
            .await
            .unwrap_err();
        assert!(
            err.to_string().contains("TradeNotDisputable"),
            "expected TradeNotDisputable, got: {err}"
        );
    }

    #[tokio::test]
    async fn dispute_store_creates_record() {
        let trade_id = format!("t-{}", uuid::Uuid::new_v4());
        let dispute = seed_dispute(&trade_id, Some("Price disagreement".into())).await;

        assert_eq!(dispute.trade_id, trade_id);
        assert_eq!(dispute.status, DisputeStatus::Open);
        assert!(dispute.initiated_by_me);
        assert_eq!(dispute.reason.as_deref(), Some("Price disagreement"));
    }

    #[tokio::test]
    async fn duplicate_dispute_is_rejected() {
        let trade_id = format!("t-{}", uuid::Uuid::new_v4());
        seed_dispute(&trade_id, None).await;

        // Second insert into the same trade must fail.
        let dispute = Dispute {
            id: uuid::Uuid::new_v4().to_string(),
            trade_id: trade_id.clone(),
            status: DisputeStatus::Open,
            initiated_by_me: true,
            reason: None,
            admin_pubkey: None,
            resolution: None,
            opened_at: unix_now(),
            resolved_at: None,
            is_read: true,
        };
        let err = dispute_store()
            .try_insert_if_absent_or_resolved(dispute)
            .await
            .unwrap_err();
        assert!(err.to_string().contains("DisputeAlreadyOpen"));
    }

    #[tokio::test]
    async fn empty_evidence_is_rejected() {
        let trade_id = format!("t-{}", uuid::Uuid::new_v4());
        seed_dispute(&trade_id, None).await;

        let err = submit_evidence(trade_id, "  ".into()).await.unwrap_err();
        assert!(err.to_string().contains("EvidenceEmpty"));
    }

    #[tokio::test]
    async fn submit_evidence_fails_without_admin() {
        let trade_id = format!("t-{}", uuid::Uuid::new_v4());
        seed_dispute(&trade_id, None).await;

        // Dispute is Open but no admin assigned yet — must fail with AdminNotAssigned
        let err = submit_evidence(trade_id, "my evidence text".into())
            .await
            .unwrap_err();
        assert!(
            err.to_string().contains("AdminNotAssigned"),
            "expected AdminNotAssigned, got: {err}"
        );
    }

    #[tokio::test]
    async fn handle_admin_took_dispute_logs_warning_without_identity() {
        // Without a loaded identity, key derivation fails — but the function
        // must still return Ok(()) (best-effort, warning only).
        let trade_id = format!("t-{}", uuid::Uuid::new_v4());
        seed_dispute(&trade_id, None).await;
        // Known valid secp256k1 point (generator G).
        let fake_admin_pk =
            "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798";
        let result = handle_admin_took_dispute(trade_id.clone(), fake_admin_pk.into()).await;
        assert!(result.is_ok(), "expected Ok, got: {:?}", result);

        let d = get_dispute(trade_id).await.unwrap().unwrap();
        assert_eq!(d.status, DisputeStatus::InReview);
        assert_eq!(d.admin_pubkey.as_deref(), Some(fake_admin_pk));
    }

    #[tokio::test]
    async fn admin_took_dispute_sets_in_review() {
        let trade_id = format!("t-{}", uuid::Uuid::new_v4());
        seed_dispute(&trade_id, None).await;

        // "adminpubkey123" is intentionally invalid hex — this test only checks
        // that the dispute store is updated correctly (status → InReview,
        // admin_pubkey stored). ECDH key derivation will fail silently
        // (best-effort, logged as warning) because the string is not a valid
        // secp256k1 pubkey. That is acceptable here.
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
        seed_dispute(&trade_id, None).await;

        handle_admin_settled(trade_id.clone()).await.unwrap();

        let d = get_dispute(trade_id).await.unwrap().unwrap();
        assert_eq!(d.status, DisputeStatus::Resolved);
        assert_eq!(d.resolution, Some(DisputeResolution::FundsToBuyer));
        assert!(d.resolved_at.is_some());
    }
}
