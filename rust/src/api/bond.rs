//! Anti-abuse bond client handling (`docs/ANTI_ABUSE_BOND.md`).
//!
//! Covers the active node's bond policy (what the UI needs to warn before a
//! take or a create) and the `bond-slashed` forfeiture notice: a best-effort,
//! informational message the daemon sends when the local user's bond is
//! slashed. The notice is broadcast to the Dart notification layer; the tracked
//! order is never mutated (the slashed amount must not overwrite the order's
//! real amount).

use anyhow::{bail, Result};
use tokio::sync::broadcast;
use tokio::sync::broadcast::error::RecvError;

use crate::api::types::{
    BondClaim, BondClaimPhase, BondClaimUpdate, BondPolicyInfo, BondSlashedEvent, OrderStatus,
    SlashCause,
};
use crate::mostro::bond_claims;
use crate::db::Storage;
use crate::mostro::bond_policy;

// ── Node policy ─────────────────────────────────────────────────────────────

/// The active node's advertised bond policy, or `None` before its kind 38385
/// info event has been fetched (startup, node switch, or an unreachable node).
///
/// `None` and `Some(policy = Unsupported)` differ: the first is "not known
/// yet", the second is "known, and the daemon predates bonds".
pub fn get_bond_policy() -> Option<BondPolicyInfo> {
    bond_policy::get_for(&crate::config::active_mostro_pubkey())
}

/// Estimated bond the active node would ask for an order of
/// `order_amount_sats`, for the pre-commit warning. `None` when the policy is
/// unknown, not enabled, or advertises no percentage. Never used to charge
/// anything: the daemon sends the exact bolt11.
pub fn estimate_bond_sats(order_amount_sats: u64) -> Option<u64> {
    let policy = get_bond_policy()?;
    bond_policy::estimate_bond_sats(order_amount_sats, &policy)
}

// ── Maker bond ──────────────────────────────────────────────────────────────

/// Walk away from an order parked at `WaitingMakerBond` without paying the
/// bond (docs/ANTI_ABUSE_BOND.md §6.2). The daemon refuses a cancel in this
/// window and reaps the unpaid order itself, so this only wipes the local
/// row and emits `Canceled` with `UserCanceled`. Markers: `TradeNotFound`,
/// `NotWaitingBond` when the row is not a maker's bond window.
pub async fn abandon_bonded_order(order_id: String) -> Result<()> {
    // Decided under the order's guard, on the row as it is then: a bond
    // that locked meanwhile is a published order, which is refused.
    crate::api::orders::abandon_maker_bond(&order_id).await
}

/// Close the bond window of `order_id` now if its deadline passed unpaid —
/// what the periodic sweep would do on its next pass. The pay-bond screen
/// calls it when its countdown ends, so a row does not linger as "pay
/// deposit" in My Trades for up to a sweep interval. Returns whether the
/// row was closed; a paid, published or still-live window is left alone.
pub async fn close_expired_bond_window(order_id: String) -> Result<bool> {
    let db = crate::db::app_db::db().ok_or_else(|| anyhow::anyhow!("StorageUnavailable"))?;
    let Some(trade) = db.get_trade_by_order_id(&order_id).await? else {
        return Ok(false);
    };
    Ok(crate::api::orders::close_expired_bond_trade(&trade, crate::rt::unix_now()).await)
}

// ── Payout claims (docs/ANTI_ABUSE_BOND.md §6.4) ─────────────────────────────

/// Buffered claim updates; a handful per slash, so a small buffer is ample.
const CLAIM_CHANNEL_CAPACITY: usize = 64;

fn claim_tx() -> &'static broadcast::Sender<BondClaimUpdate> {
    static TX: std::sync::OnceLock<broadcast::Sender<BondClaimUpdate>> = std::sync::OnceLock::new();
    TX.get_or_init(|| broadcast::channel(CLAIM_CHANNEL_CAPACITY).0)
}

/// Broadcast a claim's phase change to any [`BondClaimStream`].
pub(crate) fn emit_claim_update(order_id: &str, phase: BondClaimPhase) {
    let _ = claim_tx().send(BondClaimUpdate {
        order_id: order_id.to_string(),
        phase,
    });
}

/// A stream of claim phase changes for the Dart layer, the pattern of
/// [`BondSlashedStream`].
pub struct BondClaimStream {
    rx: broadcast::Receiver<BondClaimUpdate>,
}

impl BondClaimStream {
    /// The next claim change; a lag skips ahead rather than ending the stream.
    pub async fn next(&mut self) -> Result<BondClaimUpdate> {
        loop {
            match self.rx.recv().await {
                Ok(update) => return Ok(update),
                Err(RecvError::Lagged(_)) => continue,
                Err(RecvError::Closed) => bail!("BondClaimStream closed: sender dropped"),
            }
        }
    }
}

/// The raw channel, for tests that drain it without awaiting.
#[cfg(test)]
pub(crate) fn subscribe_claim_updates() -> broadcast::Receiver<BondClaimUpdate> {
    claim_tx().subscribe()
}

/// Subscribe to claim phase changes (new claim, submission, ack, payout,
/// expiry).
pub fn on_bond_claim_updated() -> BondClaimStream {
    BondClaimStream {
        rx: claim_tx().subscribe(),
    }
}

/// Persist a claim and keep the claim-node set — what the kind-14 filter
/// and the sender check read — in step with the store.
pub(crate) async fn persist_claim(claim: &BondClaim) -> Result<()> {
    let db = crate::db::app_db::db().ok_or_else(|| anyhow::anyhow!("StorageUnavailable"))?;
    db.save_bond_claim(claim).await?;
    refresh_claim_nodes().await;
    Ok(())
}

/// Rebuild the claim-node set from the store (startup, and after every
/// claim write). A node whose last claim just ended drops off the filter
/// on the next re-subscription; one joining it is picked up the same way.
pub(crate) async fn refresh_claim_nodes() {
    let Some(db) = crate::db::app_db::db() else {
        return;
    };
    let claims = db.list_bond_claims().await.unwrap_or_default();
    let before = bond_claims::claim_node_pubkeys().len();
    let nodes = bond_claims::claim_nodes_of(&claims);
    let changed = nodes.len() != before || nodes.iter().any(|n| !bond_claims::is_claim_node(n));
    bond_claims::set_claim_nodes(nodes);
    if changed {
        crate::api::orders::resubscribe_global_dm_filter().await;
    }
}

/// The claim for `order_id` the user can still act on — or, failing that,
/// the most recently changed one — whichever node issued it.
async fn claim_for_order(order_id: &str) -> Result<Option<BondClaim>> {
    let db = crate::db::app_db::db().ok_or_else(|| anyhow::anyhow!("StorageUnavailable"))?;
    let claims = db.list_bond_claims().await?;
    let mut for_order = claims.into_iter().filter(|c| c.order_id == order_id);
    let first = for_order.next();
    let Some(first) = first else {
        return Ok(None);
    };
    let open = std::iter::once(first.clone())
        .chain(for_order)
        .find(|c| !c.phase.is_terminal());
    Ok(Some(open.unwrap_or(first)))
}

/// Every claim, most recently changed first (My Trades, §8.3).
pub async fn list_bond_claims() -> Result<Vec<BondClaim>> {
    let db = crate::db::app_db::db().ok_or_else(|| anyhow::anyhow!("StorageUnavailable"))?;
    db.list_bond_claims().await
}

/// The claim for one order (the open one when several nodes issued one).
pub async fn get_bond_claim(order_id: String) -> Result<Option<BondClaim>> {
    claim_for_order(&order_id).await
}

/// Send the daemon the bolt11 for a claim's share (§6.4): publish the
/// `add-bond-invoice` reply **to the node that issued the claim**, mark the
/// claim `Submitted` so the next cadence retry does not re-arm the form,
/// and wait for the daemon's verdict. Markers: `ClaimNotFound`,
/// `ClaimNotClaimable` (already acknowledged, paid or expired),
/// `InvalidInvoice`, `InvoiceAmountMismatch` (a decodable bolt11 for other
/// than the share), `TradeKeyMissing`, `BondClaimRejected` (a `CantDo`
/// the claim cannot explain; it stays `Pending`), `BondClaimExpired` (the
/// deadline passed), `NoDaemonResponse` (the claim stays `Submitted`; the
/// acknowledgement arrives on the global feed).
pub async fn submit_bond_payout_invoice(order_id: String, invoice: String) -> Result<()> {
    use crate::mostro::pending::{
        detach_request_waiter, pending_requests, remove_pending_request, DaemonReply,
        PendingRequest, PendingRequestKind, Wake,
    };
    let bolt11 = invoice.trim().trim_start_matches("lightning:").to_string();
    if bolt11.is_empty() {
        bail!("InvalidInvoice");
    }
    // A decodable bolt11 with an amount must carry exactly the share, in
    // whole sats: a sub-sat remainder is a mismatch too (the daemon pays
    // the principal with fee 0).
    if let Some(decoded) = crate::api::invoice::decode_bolt11(bolt11.clone()) {
        if let Some(msat) = decoded.amount_msat.filter(|m| *m != 0) {
            if let Some(share) = claim_for_order(&order_id).await?.map(|c| c.amount_sats) {
                if msat != share.saturating_mul(1_000) {
                    bail!("InvoiceAmountMismatch");
                }
            }
        }
    }
    let claim = claim_for_order(&order_id)
        .await?
        .ok_or_else(|| anyhow::anyhow!("ClaimNotFound"))?;
    if !matches!(claim.phase, BondClaimPhase::Pending | BondClaimPhase::Submitted) {
        bail!("ClaimNotClaimable");
    }
    let now = crate::rt::unix_now();
    if now > claim.deadline_at {
        let mut expired = claim.clone();
        expired.phase = BondClaimPhase::Expired;
        expired.updated_at = now;
        persist_claim(&expired).await?;
        emit_claim_update(&order_id, BondClaimPhase::Expired);
        bail!("BondClaimExpired");
    }
    let trade_index = crate::api::orders::trade_key_index_of(&order_id)
        .await
        .ok_or_else(|| anyhow::anyhow!("TradeKeyMissing"))?;
    let sender_keys = crate::api::identity::get_active_trade_keys(trade_index).await?;
    let identity_keys = crate::api::identity::get_transport_identity_keys(&sender_keys).await?;
    let node_pubkey = nostr_sdk::prelude::PublicKey::from_hex(&claim.node_pubkey)?;
    let request_id: u64 = {
        use rand::RngCore;
        rand::rngs::OsRng.next_u64().max(1)
    };
    let event_json = crate::mostro::actions::add_bond_invoice(
        &identity_keys,
        &sender_keys,
        &node_pubkey,
        &order_id,
        trade_index,
        &bolt11,
        request_id,
    )
    .await?;
    let trade_pk_hex = sender_keys.public_key().to_hex();
    let (tx, rx) = tokio::sync::oneshot::channel::<Wake>();
    if let Ok(mut map) = pending_requests().lock() {
        map.insert(
            trade_pk_hex.clone(),
            PendingRequest {
                request_id,
                trade_index,
                kind: PendingRequestKind::BondClaimSubmit,
                tx: Some(tx),
            },
        );
    }
    if let Err(e) = crate::api::orders::publish_event_json(&event_json).await {
        remove_pending_request(&trade_pk_hex, request_id);
        return Err(e);
    }
    // Submitted before the wait: a restart in between must not re-arm the
    // form, and the daemon's retry that crosses this reply is a no-op.
    let mut submitted = claim.clone();
    submitted.phase = BondClaimPhase::Submitted;
    submitted.submitted_invoice = Some(bolt11.clone());
    submitted.updated_at = now;
    persist_claim(&submitted).await?;
    emit_claim_update(&order_id, BondClaimPhase::Submitted);
    crate::api::logging::blog_info(
        "bond",
        format!(
            "add-bond-invoice published for order={} node={} trade_index={trade_index}",
            crate::api::logging::short_id(&order_id),
            &claim.node_pubkey[..8.min(claim.node_pubkey.len())],
        ),
    );

    let reply = crate::rt::time::timeout(std::time::Duration::from_secs(10), rx).await;
    if !matches!(reply, Ok(Ok(_))) {
        detach_request_waiter(&trade_pk_hex, request_id);
    }
    match reply {
        Ok(Ok(Wake {
            reply: DaemonReply::Acknowledged,
            ..
        })) => Ok(()),
        Ok(Ok(Wake {
            reply: DaemonReply::Rejected { reason, .. },
            ..
        })) => {
            // The arm persisted nothing for a claim submission: resolve
            // here, from what the claim knows (§6.4).
            let current = claim_for_order(&order_id).await?.unwrap_or(submitted);
            let now = crate::rt::unix_now();
            match bond_claims::resolve_submission_rejection(&current, now) {
                Ok(phase) if phase == current.phase => {
                    bail!("ClaimNotClaimable")
                }
                Ok(phase) => {
                    let mut next = current.clone();
                    next.phase = phase;
                    next.updated_at = now;
                    persist_claim(&next).await?;
                    emit_claim_update(&order_id, phase);
                    bail!("BondClaimExpired")
                }
                Err(marker) => {
                    log::info!("[bond] add-bond-invoice rejected: {reason} — claim stays pending");
                    let mut pending = current.clone();
                    pending.phase = BondClaimPhase::Pending;
                    pending.submitted_invoice = None;
                    pending.updated_at = now;
                    persist_claim(&pending).await?;
                    emit_claim_update(&order_id, BondClaimPhase::Pending);
                    bail!("{marker}")
                }
            }
        }
        Ok(Ok(_)) => Ok(()),
        _ => bail!("NoDaemonResponse"),
    }
}

// ── Forfeiture notice ───────────────────────────────────────────────────────

/// Buffered slash notices; a slash is rare, so a small buffer is ample.
const CHANNEL_CAPACITY: usize = 64;

struct BondStore {
    /// Broadcast channel; payload = incoming bond-slashed notice.
    event_tx: broadcast::Sender<BondSlashedEvent>,
}

static BOND_STORE: std::sync::OnceLock<BondStore> = std::sync::OnceLock::new();

fn bond_store() -> &'static BondStore {
    BOND_STORE.get_or_init(|| {
        let (event_tx, _rx) = broadcast::channel(CHANNEL_CAPACITY);
        BondStore { event_tx }
    })
}

/// Infers the slash cause from the tracked order's current status.
///
/// The daemon sends the resolution message first — `canceled` for a timeout,
/// `admin-settled` / `admin-canceled` for a dispute — and only then the
/// trailing `bond-slashed`. So by the time the notice arrives, the tracked
/// status already reflects the cause. Any dispute/admin state means a
/// dispute-directed slash; everything else (including an unknown status)
/// defaults to a timeout slash.
pub(crate) fn infer_slash_cause(status: Option<&OrderStatus>) -> SlashCause {
    match status {
        Some(
            OrderStatus::Dispute
            | OrderStatus::CanceledByAdmin
            | OrderStatus::SettledByAdmin
            | OrderStatus::CompletedByAdmin,
        ) => SlashCause::Dispute,
        _ => SlashCause::Timeout,
    }
}

/// Broadcasts a `bond-slashed` notice to any active [`BondSlashedStream`].
pub(crate) fn emit_bond_slashed(event: BondSlashedEvent) {
    let _ = bond_store().event_tx.send(event);
}

/// A stream that emits incoming [`BondSlashedEvent`]s for the Dart layer.
pub struct BondSlashedStream {
    rx: broadcast::Receiver<BondSlashedEvent>,
}

impl BondSlashedStream {
    /// Poll for the next incoming bond-slashed notice.
    ///
    /// `RecvError::Lagged` is skipped gracefully rather than ending the stream.
    pub async fn next(&mut self) -> Result<BondSlashedEvent> {
        loop {
            match self.rx.recv().await {
                Ok(event) => return Ok(event),
                Err(RecvError::Lagged(_)) => continue,
                Err(RecvError::Closed) => bail!("BondSlashedStream closed: sender dropped"),
            }
        }
    }
}

/// Subscribe to incoming `bond-slashed` notices.
pub fn on_bond_slashed() -> BondSlashedStream {
    BondSlashedStream {
        rx: bond_store().event_tx.subscribe(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dispute_and_admin_states_infer_dispute() {
        for status in [
            OrderStatus::Dispute,
            OrderStatus::CanceledByAdmin,
            OrderStatus::SettledByAdmin,
            OrderStatus::CompletedByAdmin,
        ] {
            assert_eq!(infer_slash_cause(Some(&status)), SlashCause::Dispute);
        }
    }

    #[test]
    fn canceled_and_other_states_infer_timeout() {
        for status in [
            OrderStatus::Canceled,
            OrderStatus::InProgress,
            OrderStatus::WaitingPayment,
            OrderStatus::WaitingBuyerInvoice,
            OrderStatus::Active,
        ] {
            assert_eq!(infer_slash_cause(Some(&status)), SlashCause::Timeout);
        }
    }

    #[test]
    fn unknown_status_defaults_to_timeout() {
        assert_eq!(infer_slash_cause(None), SlashCause::Timeout);
    }

    /// A trade row written before the `bond` field existed must still load,
    /// and a row with a bond must round-trip it intact.
    #[test]
    fn trade_rows_round_trip_with_and_without_a_bond() {
        use crate::api::types::{
            BondInfo, BondRole, BondState, BuyerStep, OrderInfo, OrderKind, TradeInfo, TradeRole,
            TradeStep,
        };

        let order = OrderInfo {
            id: "o1".into(),
            kind: OrderKind::Sell,
            status: OrderStatus::WaitingTakerBond,
            amount_sats: Some(100_000),
            fiat_amount: Some(10.0),
            fiat_amount_min: None,
            fiat_amount_max: None,
            fiat_code: "USD".into(),
            payment_method: "cash".into(),
            premium: 0.0,
            creator_pubkey: String::new(),
            created_at: 1,
            expires_at: None,
            is_mine: false,
            rating: 0.0,
            total_reviews: 0,
            days_active: 0,
        };
        let trade = TradeInfo {
            id: "t1".into(),
            order,
            role: TradeRole::Buyer,
            counterparty_pubkey: String::new(),
            current_step: TradeStep::Buyer(BuyerStep::OrderTaken),
            hold_invoice: None,
            buyer_invoice: None,
            trade_key_index: 3,
            cooperative_cancel_state: None,
            timeout_at: None,
            started_at: 1,
            completed_at: None,
            outcome: None,
            peer_rating: None,
            peer_reviews: None,
            peer_days: None,
            rated_at: None,
            bond: Some(BondInfo {
                role: BondRole::Taker,
                amount_sats: 1_000,
                invoice: Some("lnbc10u1...".into()),
                state: BondState::Requested,
                requested_at: 1,
                expires_at: Some(3601),
                locked_at: None,
            }),
        };

        let json = serde_json::to_string(&trade).unwrap();
        let back: TradeInfo = serde_json::from_str(&json).unwrap();
        assert_eq!(back.bond, trade.bond);
        assert_eq!(back.order.status, OrderStatus::WaitingTakerBond);

        // A pre-bond row: strip the field and deserialise again.
        let mut value: serde_json::Value = serde_json::from_str(&json).unwrap();
        value.as_object_mut().unwrap().remove("bond");
        let legacy: TradeInfo = serde_json::from_value(value).unwrap();
        assert_eq!(legacy.bond, None);
    }

    #[test]
    fn the_estimate_reads_the_active_node_policy_only() {
        use crate::api::types::{BondPolicy, BondPolicyInfo};
        let enabled = BondPolicyInfo {
            policy: BondPolicy::Enabled,
            amount_pct: Some(0.01),
            base_amount_sats: Some(1_000),
            ..BondPolicyInfo::default()
        };
        bond_policy::clear();
        assert_eq!(get_bond_policy(), None);
        assert_eq!(estimate_bond_sats(500_000), None);

        // A policy fetched from some other node is not the active node's.
        bond_policy::set_from_tags("not-the-active-node", enabled.clone());
        assert_eq!(get_bond_policy(), None);
        assert_eq!(estimate_bond_sats(500_000), None);

        bond_policy::set_from_tags(&crate::config::active_mostro_pubkey(), enabled);
        assert_eq!(estimate_bond_sats(500_000), Some(5_000));
        assert_eq!(estimate_bond_sats(10), Some(1_000));
        bond_policy::clear();
    }
}
