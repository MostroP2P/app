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

use crate::api::types::{Dispute, DisputeResolution, DisputeStatus, OrderStatus};
use crate::db::Storage;

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

    async fn all(&self) -> Vec<Dispute> {
        self.disputes.read().await.values().cloned().collect()
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
        let stored = {
            let mut store = self.disputes.write().await;
            match store.get_mut(&dispute.trade_id) {
                // `admin-took-dispute` landed between our publish and this
                // insert (PR #253 review): the handler stored a placeholder —
                // InReview, not ours, no reason, solver known. Claim it
                // instead of failing: keep the solver and the InReview status
                // it already learned, restore our initiator metadata.
                Some(existing)
                    if existing.status == DisputeStatus::InReview
                        && !existing.initiated_by_me
                        && existing.reason.is_none()
                        && existing.admin_pubkey.is_some()
                        && pending_opens()
                            .lock()
                            .map(|set| set.contains(&dispute.trade_id))
                            .unwrap_or(false) =>
                {
                    existing.initiated_by_me = true;
                    existing.reason = dispute.reason;
                    existing.clone()
                }
                Some(existing) if existing.status != DisputeStatus::Resolved => {
                    bail!(
                        "DisputeAlreadyOpen: dispute already exists for trade {}",
                        dispute.trade_id
                    );
                }
                _ => {
                    store.insert(dispute.trade_id.clone(), dispute.clone());
                    dispute
                }
            }
        }; // write lock released here
        let _ = self.update_tx.send(stored.clone());
        Ok(stored)
    }

    /// Atomically create the dispute when the trade has none, or update the
    /// existing record, under **one** write lock. `make` builds the new
    /// record; `update` mutates the existing one, and its error aborts
    /// without touching the store. One lock scope on purpose (PR #253
    /// review): an incoming `admin-took-dispute` races `open_dispute`'s
    /// post-publish insert, and a check-then-act here would let either side
    /// overwrite the other. The broadcast fires after the lock is released.
    async fn upsert_or_update<M, U>(&self, trade_id: &str, make: M, update: U) -> Result<()>
    where
        M: FnOnce() -> Dispute,
        U: FnOnce(&mut Dispute) -> Result<()>,
    {
        let stored = {
            let mut store = self.disputes.write().await;
            match store.get_mut(trade_id) {
                Some(dispute) => {
                    update(dispute)?;
                    dispute.clone()
                }
                None => {
                    let dispute = make();
                    store.insert(trade_id.to_string(), dispute.clone());
                    dispute
                }
            }
        }; // write lock released here
        let _ = self.update_tx.send(stored);
        Ok(())
    }
}

// ── Global singleton ──────────────────────────────────────────────────────────

static DISPUTE_STORE: OnceLock<DisputeStore> = OnceLock::new();

/// Trades with an `open_dispute` call currently in flight (between its
/// entry check and its post-publish insert). The admin-took placeholder may
/// only be claimed as ours while this marker is held — a placeholder that
/// exists with no owned in-flight attempt is a genuinely peer-opened dispute
/// and must stay peer-owned (PR #253 review).
static PENDING_OPENS: OnceLock<std::sync::Mutex<std::collections::HashSet<String>>> =
    OnceLock::new();

fn pending_opens() -> &'static std::sync::Mutex<std::collections::HashSet<String>> {
    PENDING_OPENS.get_or_init(|| std::sync::Mutex::new(std::collections::HashSet::new()))
}

/// Removes the pending-open marker on every exit path of `open_dispute`.
struct PendingOpenGuard(String);

impl Drop for PendingOpenGuard {
    fn drop(&mut self) {
        if let Ok(mut set) = pending_opens().lock() {
            set.remove(&self.0);
        }
    }
}

fn dispute_store() -> &'static DisputeStore {
    DISPUTE_STORE.get_or_init(DisputeStore::new)
}

// ── Helper ────────────────────────────────────────────────────────────────────

use crate::rt::unix_now;

/// Mirrors the daemon's own precondition: it only accepts a dispute on an
/// Active or FiatSent order, and answers anything earlier with `CantDo`
/// (issue #203). `InProgress` is the public order-book bucket — a trade whose
/// real state we don't know — so that call is left to the daemon.
fn status_allows_dispute(status: &crate::api::types::OrderStatus) -> bool {
    use crate::api::types::OrderStatus;
    matches!(
        status,
        OrderStatus::Active | OrderStatus::FiatSent | OrderStatus::InProgress
    )
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

    // A record that already exists at entry — whatever its origin, including
    // a peer-opened dispute whose status update we may have missed — means
    // this is not a fresh open: fail before publishing a duplicate request
    // the daemon will reject by status (PR #253 review).
    if let Some(existing) = dispute_store().get(&trade_id).await {
        if existing.status != DisputeStatus::Resolved {
            bail!("DisputeAlreadyOpen: dispute already exists for trade {trade_id}");
        }
    }
    if let Some(status) = crate::api::orders::local_trade_status(&trade_id).await {
        if !status_allows_dispute(&status) {
            bail!("TradeNotDisputable: trade {trade_id} is {status:?}");
        }
    }

    // Mark this process's concrete in-flight open attempt: only while the
    // marker is held may the post-publish insert claim an admin-took
    // placeholder as ours. Dropped on every exit path.
    pending_opens()
        .lock()
        .expect("pending_opens poisoned")
        .insert(trade_id.clone());
    let _pending = PendingOpenGuard(trade_id.clone());

    // Dispatch Action::Dispute to Mostro BEFORE creating the local record so
    // that a failed publish does not leave an un-retryable "open" slot in the
    // dispute store.  Only on a successful publish do we persist the dispute.
    let trade_index = crate::api::orders::trade_key_for_order(&trade_id)
        .await
        .ok_or_else(|| anyhow!("TradeNotDisputable: no trade key for trade {trade_id}"))?;

    let event_json: String = async {
        let sender_keys =
            crate::api::identity::get_active_trade_keys(trade_index).await?;
        let identity_keys =
            crate::api::identity::get_transport_identity_keys(&sender_keys).await?;
        let mostro_pubkey =
            nostr_sdk::PublicKey::from_hex(&crate::config::active_mostro_pubkey())
                .map_err(|e| anyhow!("invalid mostro pubkey: {e}"))?;
        crate::mostro::actions::dispute(
            &identity_keys,
            &sender_keys,
            &mostro_pubkey,
            &trade_id,
            trade_index,
        )
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

    // Same envelope as the peer chat, keyed to the solver instead of the
    // counterparty: inner kind 1 signed by our trade key, NIP-44 under K_conv,
    // inside a kind 14 signed with K_sign and p-tagged to pub(K_conv). No gift
    // wrap and no ephemeral key — see
    // <https://mostro.network/protocol/dispute_chat.html>.
    //
    // The text travels as the message itself rather than a hand-rolled
    // {"type":"evidence"} JSON: this is a conversation with the solver, and
    // that shape had no reader on the other side of the envelope.
    let ctx = crate::api::messages::admin_chat_context(trade_index, &admin_pubkey).await?;
    let inner = crate::api::messages::publish_chat_payload_for(&ctx, &text).await?;

    // Interop dual-write (PR #254 review): the current solver client
    // (mostrix) still reads only NIP-59 gift wrap — its envelope migration is
    // tracked in mostrix#102. Until the deprecation date the evidence also
    // goes out in the pre-migration shape it understands, gift-wrapped
    // straight to the solver. Best-effort: the envelope copy above is the
    // durable one, and this copy disappears with the dual-read window.
    if crate::rt::unix_now() < crate::api::messages::LEGACY_CHAT_DEPRECATION_TS {
        let legacy_send: Result<()> = async {
            let sender_keys = crate::api::identity::get_active_trade_keys(trade_index).await?;
            let payload = serde_json::json!({
                "type": "evidence",
                "trade_id": trade_id,
                "text": text,
            })
            .to_string();
            let event_json = crate::nostr::gift_wrap::wrap(
                &sender_keys,
                &admin_pubkey,
                &payload,
                nostr_sdk::Kind::from(14u16),
            )
            .await
            .map_err(|e| anyhow!("legacy wrap failed: {e}"))?;
            crate::api::orders::publish_event(&event_json)
                .await
                .map_err(|e| anyhow!("legacy publish failed: {e}"))?;
            Ok(())
        }
        .await;
        if let Err(e) = legacy_send {
            log::warn!("[disputes] legacy evidence copy not sent trade={trade_id}: {e}");
        }
    }

    // Record it locally so the dispute conversation has history, exactly as a
    // peer message does. Keyed by the inner event id, so our own echo arriving
    // from a relay dedups against this record instead of duplicating it.
    crate::api::messages::store_outgoing_admin_message(&trade_id, &ctx, &text, &inner).await;

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

    // The daemon sends `admin-took-dispute` to BOTH parties, and the side that
    // did not open the dispute has no local record — an update alone would
    // fail with DisputeNotFound and the admin pubkey would be lost. That
    // pubkey is the only way to reach the solver, so create the record when
    // it is missing. Create-or-update runs under ONE store write lock (PR
    // #253 review): a separate check-then-act races `open_dispute`'s
    // post-publish insert in both directions — it could overwrite the
    // initiator's fresh record, or insert first and make the initiator's own
    // insert fail with its metadata lost.
    let trade_id_for_new = trade_id.clone();
    let admin_for_new = admin_pubkey.clone();
    dispute_store()
        .upsert_or_update(
            &trade_id,
            || {
                log::info!(
                    "[disputes] created record for peer-opened dispute trade={trade_id_for_new}"
                );
                Dispute {
                    id: uuid::Uuid::new_v4().to_string(),
                    trade_id: trade_id_for_new.clone(),
                    status: DisputeStatus::InReview,
                    initiated_by_me: false,
                    reason: None,
                    admin_pubkey: Some(admin_for_new),
                    resolution: None,
                    opened_at: unix_now(),
                    resolved_at: None,
                    is_read: false,
                }
            },
            move |dispute| {
                if dispute.status == DisputeStatus::InReview {
                    // Same-solver replay: the daemon resends the assignment
                    // (reconnect backfill, or deliberately); it is the retry
                    // path for the best-effort key derivation and must
                    // succeed. Exact-event replays never reach here — the
                    // receive path dedups by event id — so an InReview
                    // record with a different pubkey is a genuinely newer
                    // assignment: the daemon lets a write-capable solver
                    // take over an in-progress dispute from a read-only one
                    // (mostro admin_take_dispute.rs, pubkey_event_can_solve)
                    // and notifies both parties with the new pubkey. Keeping
                    // the old key would leave the actual solver unreachable
                    // (PR #253 review).
                    if dispute.admin_pubkey.as_deref() != Some(admin_pubkey.as_str()) {
                        dispute.admin_pubkey = Some(admin_pubkey);
                        dispute.is_read = false;
                    }
                    return Ok(());
                }
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
            },
        )
        .await?;

    persist_admin_pubkey(&trade_id, &admin_pubkey_for_key).await;
    derive_admin_shared_key(&trade_id, &admin_pubkey_for_key).await
}

/// Persist the solver pubkey so the dispute chat survives a restart.
///
/// Deliberately narrow: the dispute record stays in memory (its status and
/// resolution come back from daemon events), but this pubkey arrives exactly
/// once and cannot be re-derived. Without it, a restart mid-dispute leaves the
/// party unable to reach the solver at all.
///
/// Best-effort — a storage failure must not undo an already-applied dispute
/// update, and the live listener keeps working for this session.
async fn persist_admin_pubkey(order_id: &str, admin_pubkey_hex: &str) {
    let Some(db) = crate::db::app_db::db() else {
        log::warn!("[disputes] no store — solver pubkey will not survive a restart");
        return;
    };
    if let Err(e) = db
        .set_setting(
            &crate::db::settings_keys::dispute_admin(order_id),
            admin_pubkey_hex,
        )
        .await
    {
        log::warn!("[disputes] could not persist solver pubkey for {order_id}: {e}");
    }
}

/// Drop the persisted solver pubkey for `order_id`.
///
/// The stored key is what rehydration reads as "this order has a live
/// dispute", so it must not outlive the dispute: left behind, every restart
/// would resurrect a finished dispute as `InReview`, arm a listener for it and
/// keep accepting evidence. Called both when a resolution reaches the store and
/// when rehydration meets an already-finished trade.
///
/// Best-effort like the write: a storage failure only means the stale key is
/// seen again — and cleared again — on the next pass.
async fn clear_admin_pubkey(order_id: &str) {
    let Some(db) = crate::db::app_db::db() else {
        return;
    };
    if let Err(e) = db
        .delete_setting(&crate::db::settings_keys::dispute_admin(order_id))
        .await
    {
        log::warn!("[disputes] could not clear solver pubkey for {order_id}: {e}");
    }
}

/// `true` when the order reached a state in which no dispute can still be live.
///
/// This is what keeps rehydration from resurrecting finished disputes, and it
/// deliberately reads the *trade* status rather than the dispute record: the
/// daemon's `admin-settled` / `admin-canceled` are persisted by the status-sync
/// arm in `orders.rs`, which does not route them into the dispute store, so the
/// trade row is the durable evidence that the dispute is over.
fn is_order_finished(status: &OrderStatus) -> bool {
    matches!(
        status,
        OrderStatus::SettledByAdmin
            | OrderStatus::CanceledByAdmin
            | OrderStatus::CompletedByAdmin
            | OrderStatus::Success
            | OrderStatus::Canceled
            | OrderStatus::CooperativelyCanceled
            | OrderStatus::Expired
    )
}


/// Derive the dispute-chat keys for `trade_id` and start listening.
///
/// Both sides ECDH their trade key against the solver's pubkey and split the
/// secret with HKDF exactly as the peer chat does, so `derive_chat_keys` is
/// reused unchanged — the only difference is whose pubkey goes in
/// (<https://mostro.network/protocol/dispute_chat.html>).
///
/// Best-effort: if no trade key exists yet this logs a warning but does not
/// fail. The dispute record and the solver pubkey are already stored, so a
/// later reconnect can start the listener; losing the derivation must not lose
/// the pubkey with it.
async fn derive_admin_shared_key(trade_id: &str, admin_pubkey_hex: &str) -> Result<()> {
    let trade_id = trade_id.to_string();
    let admin_pubkey_hex = admin_pubkey_hex.to_string();

    let start_result: Result<()> = async {
        let trade_index = crate::api::orders::trade_key_for_order(&trade_id)
            .await
            .ok_or_else(|| anyhow!("no trade key for trade {trade_id}"))?;
        let trade_keys = crate::api::identity::get_active_trade_keys(trade_index).await?;
        let admin_pk = nostr_sdk::PublicKey::from_hex(&admin_pubkey_hex)
            .map_err(|e| anyhow!("invalid admin pubkey: {e}"))?;
        let (conv, sign) = crate::crypto::chat_keys::derive_chat_keys(&trade_keys, &admin_pk)?;

        // Own task, like the peer chat: the guard inside is keyed per channel,
        // so this never collides with the peer conversation of the same order.
        crate::rt::spawn(crate::api::messages::subscribe_incoming_chat(
            crate::api::messages::ChatChannel::Dispute,
            trade_id.clone(),
            trade_keys,
            admin_pk,
            conv,
            sign,
        ));
        log::info!("[disputes] dispute chat listening for trade={trade_id}");
        Ok(())
    }
    .await;

    if let Err(e) = start_result {
        log::warn!("[disputes] could not start dispute chat for trade={trade_id}: {e}");
    }

    Ok(())
}

/// Re-arm the dispute-chat listener of every in-review dispute with a known
/// solver. Called when the relay pool comes (back) online, mirroring
/// `resubscribe_active_chats` for the peer channel (PR #254 review): listener
/// startup is best-effort at assignment time and can fail while keys or
/// connectivity are not there yet, and without a rearm path solver replies
/// would stay invisible for the rest of the process. Idempotent — the
/// per-channel single-owner guard makes a spawn for an already-listening
/// dispute a no-op.
/// Rebuild dispute records for orders with a persisted solver pubkey.
///
/// Trades are the enumeration source, so no key-prefix scan is needed: each
/// persisted trade is asked whether it has a stored solver. Records already in
/// memory win — they are at least as fresh as storage.
///
/// Status is `InReview`: a stored solver means one took the dispute, and any
/// later resolution arrives as a daemon event. Restoring the record is what
/// lets `submit_evidence` work again after a restart, since it refuses without
/// one. Only *unfinished* trades are restored — see [`is_order_finished`].
///
/// **Web has no rehydration.** `lib/main.dart` skips `initDb` off native, and
/// the IndexedDB store's `list_trades` is still the empty stub of #233, so both
/// the store lookup and the enumeration source are missing there. A browser
/// reload therefore still loses the solver pubkey; the persistence path lights
/// up on web once #233 lands trade persistence, with no change needed here.
async fn rehydrate_disputes_from_storage() {
    let Some(db) = crate::db::app_db::db() else {
        return;
    };
    let trades = match db.list_trades().await {
        Ok(t) => t,
        Err(e) => {
            log::warn!("[disputes] rehydrate: list_trades failed: {e}");
            return;
        }
    };

    for trade in trades {
        let order_id = trade.order.id.clone();
        if dispute_store().get(&order_id).await.is_some() {
            continue;
        }
        let admin_hex = match db
            .get_setting(&crate::db::settings_keys::dispute_admin(&order_id))
            .await
        {
            Ok(Some(hex)) => hex,
            Ok(None) => continue,
            Err(e) => {
                log::warn!("[disputes] rehydrate: reading solver for {order_id}: {e}");
                continue;
            }
        };

        // The trade already ended — the solver key is stale. Restoring it here
        // would recreate the dispute as `InReview` on every single restart,
        // arm a listener nobody is on the other end of, and keep letting
        // evidence be submitted against a closed case. Clear it instead.
        if is_order_finished(&trade.order.status) {
            log::info!(
                "[disputes] rehydrate: dropping stale solver for finished order={order_id} status={:?}",
                trade.order.status
            );
            clear_admin_pubkey(&order_id).await;
            continue;
        }

        dispute_store()
            .upsert(Dispute {
                id: uuid::Uuid::new_v4().to_string(),
                trade_id: order_id.clone(),
                status: DisputeStatus::InReview,
                initiated_by_me: false,
                reason: None,
                admin_pubkey: Some(admin_hex),
                resolution: None,
                opened_at: unix_now(),
                resolved_at: None,
                // The pre-restart read state is not recoverable, and this is
                // an active dispute waiting on the user — default to unread so
                // it surfaces rather than being silently marked as seen.
                is_read: false,
            })
            .await;
        log::info!("[disputes] rehydrated dispute record order={order_id}");
    }
}

pub(crate) async fn resubscribe_active_dispute_chats() {
    // A restart leaves the in-memory store empty, so the loop below would find
    // nothing to re-arm. Refill it from the persisted solver pubkeys first —
    // that is the one piece of a dispute that cannot be re-derived.
    rehydrate_disputes_from_storage().await;

    for dispute in dispute_store().all().await {
        if dispute.status != DisputeStatus::InReview {
            continue;
        }
        let Some(admin) = dispute.admin_pubkey.clone() else {
            continue;
        };
        let _ = derive_admin_shared_key(&dispute.trade_id, &admin).await;
    }
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
        .await?;

    // The dispute is over, so the solver pubkey has nothing left to unlock —
    // and leaving it stored would have the next restart rehydrate this exact
    // dispute back to `InReview`. Only on success: a rejected resolution left
    // the dispute live.
    clear_admin_pubkey(&trade_id).await;
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

    #[test]
    fn only_a_funded_trade_is_disputable() {
        use crate::api::types::OrderStatus as S;

        for allowed in [S::Active, S::FiatSent, S::InProgress] {
            assert!(status_allows_dispute(&allowed), "{allowed:?} must pass");
        }
        for rejected in [
            S::Pending,
            S::WaitingBuyerInvoice,
            S::WaitingPayment,
            S::Canceled,
            S::Success,
            S::Dispute,
        ] {
            assert!(
                !status_allows_dispute(&rejected),
                "{rejected:?} must not reach the daemon"
            );
        }
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
    async fn the_solver_pubkey_outlives_the_in_memory_record() {
        // The dispute record is in-memory by design, so a restart drops it.
        // The solver pubkey must not go with it: it arrives once, in
        // admin-took-dispute, and without it the chat keys cannot be derived
        // again — the party would be left unable to reach the solver.
        let path = std::env::temp_dir()
            .join(format!("mostro_dispute_kv_{}.db", std::process::id()));
        let _ = std::fs::remove_file(&path);
        let db = crate::db::sqlite::SqliteStorage::open(path.to_str().unwrap())
            .await
            .unwrap();

        let order_id = "order-dispute-1";
        let admin_pk = "0000000000000000000000000000000000000000000000000000000000000003";
        let key = crate::db::settings_keys::dispute_admin(order_id);

        assert_eq!(db.get_setting(&key).await.unwrap(), None);

        db.set_setting(&key, admin_pk).await.unwrap();

        // Reopen: this is the restart the persistence exists for.
        drop(db);
        let db = crate::db::sqlite::SqliteStorage::open(path.to_str().unwrap())
            .await
            .unwrap();
        assert_eq!(db.get_setting(&key).await.unwrap().as_deref(), Some(admin_pk));

        drop(db);
        let _ = std::fs::remove_file(&path);
    }

    /// A persisted trade for `order_id` in `status`, so `list_trades` — the
    /// enumeration source rehydration walks — has something to return.
    fn persisted_trade(order_id: &str, status: OrderStatus) -> crate::api::types::TradeInfo {
        use crate::api::types::*;
        TradeInfo {
            id: order_id.to_string(),
            order: OrderInfo {
                id: order_id.to_string(),
                kind: OrderKind::Sell,
                status,
                amount_sats: None,
                fiat_amount: None,
                fiat_amount_min: None,
                fiat_amount_max: None,
                fiat_code: "VES".into(),
                payment_method: "bank".into(),
                premium: 0.0,
                creator_pubkey: "maker".into(),
                created_at: 1,
                expires_at: None,
                is_mine: true,
                rating: 0.0,
                total_reviews: 0,
                days_active: 0,
            },
            role: TradeRole::Buyer,
            counterparty_pubkey: "peer".into(),
            current_step: TradeStep::Buyer(BuyerStep::FiatSent),
            hold_invoice: None,
            buyer_invoice: None,
            trade_key_index: 1,
            cooperative_cancel_state: None,
            timeout_at: None,
            started_at: 1,
            completed_at: None,
            outcome: None,
        }
    }

    /// End-to-end over `rehydrate_disputes_from_storage`: a restart is exactly
    /// an empty in-memory store plus whatever the trades table and the settings
    /// KV kept, so all three of its rules are exercised against the real store
    /// rather than against the helpers in isolation.
    ///
    /// One test, not three: rehydration is a single pass over every persisted
    /// trade, and `app_db` is a process-wide `OnceCell` — splitting it would
    /// have each case re-walk the others' rows for no added coverage.
    #[tokio::test]
    async fn rehydration_restores_live_disputes_and_clears_finished_ones() {
        // `init_db` is a OnceCell: the first test to call it wins, and any
        // SqliteStorage serves — this asserts about its own order ids only, so
        // rows other tests may have left behind are irrelevant.
        let path = std::env::temp_dir()
            .join(format!("mostro_dispute_rehydrate_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let Some(db) = crate::db::app_db::db() else {
            panic!("no store: rehydration cannot be exercised");
        };

        let live = format!("live-{}", uuid::Uuid::new_v4());
        let finished = format!("finished-{}", uuid::Uuid::new_v4());
        let in_memory = format!("mem-{}", uuid::Uuid::new_v4());
        let stored_solver = "0000000000000000000000000000000000000000000000000000000000000011";
        let fresher_solver = "0000000000000000000000000000000000000000000000000000000000000022";

        for (order_id, status) in [
            (&live, OrderStatus::Dispute),
            (&finished, OrderStatus::SettledByAdmin),
            (&in_memory, OrderStatus::Dispute),
        ] {
            db.save_trade(&persisted_trade(order_id, status))
                .await
                .unwrap();
            db.set_setting(
                &crate::db::settings_keys::dispute_admin(order_id),
                stored_solver,
            )
            .await
            .unwrap();
        }

        // The record that survived in memory — it must win over storage.
        let mut live_record = seed_dispute(&in_memory, None).await;
        live_record.admin_pubkey = Some(fresher_solver.to_string());
        live_record.status = DisputeStatus::InReview;
        dispute_store().upsert(live_record).await;

        rehydrate_disputes_from_storage().await;

        // 1. The live dispute came back — this is what makes the dispute chat
        //    reachable and `submit_evidence` work again after a restart.
        let restored = get_dispute(live.clone()).await.unwrap().expect("restored");
        assert_eq!(restored.status, DisputeStatus::InReview);
        assert_eq!(restored.admin_pubkey.as_deref(), Some(stored_solver));
        assert!(!restored.is_read, "an active dispute must surface as unread");

        // 2. The finished one did not, and its stale key is gone — otherwise
        //    every later restart resurrects it as InReview.
        assert!(get_dispute(finished.clone()).await.unwrap().is_none());
        assert_eq!(
            db.get_setting(&crate::db::settings_keys::dispute_admin(&finished))
                .await
                .unwrap(),
            None,
            "the stale solver key must be cleared, not just skipped"
        );

        // 3. The in-memory record is at least as fresh as storage, so the
        //    older stored solver must not overwrite it.
        let kept = get_dispute(in_memory.clone()).await.unwrap().expect("kept");
        assert_eq!(kept.admin_pubkey.as_deref(), Some(fresher_solver));
    }

    #[test]
    fn finished_orders_are_not_rehydrated() {
        // The admin verdicts are the ones that end a dispute, and `orders.rs`
        // persists them on the trade even though nothing routes them into the
        // dispute store — so they are what rehydration has to check.
        for status in [
            OrderStatus::SettledByAdmin,
            OrderStatus::CanceledByAdmin,
            OrderStatus::CompletedByAdmin,
            OrderStatus::Success,
            OrderStatus::Canceled,
            OrderStatus::CooperativelyCanceled,
            OrderStatus::Expired,
        ] {
            assert!(is_order_finished(&status), "{status:?} should be finished");
        }
    }

    #[test]
    fn a_live_dispute_is_still_rehydrated() {
        // The whole point of the feature: an order still under dispute (or
        // otherwise mid-flight) must come back after a restart.
        for status in [
            OrderStatus::Dispute,
            OrderStatus::InProgress,
            OrderStatus::Active,
            OrderStatus::FiatSent,
            OrderStatus::SettledHoldInvoice,
        ] {
            assert!(!is_order_finished(&status), "{status:?} should stay live");
        }
    }

    #[test]
    fn each_order_gets_its_own_solver_key() {
        // One party can have several disputed orders, each with its own solver.
        assert_ne!(
            crate::db::settings_keys::dispute_admin("order-a"),
            crate::db::settings_keys::dispute_admin("order-b")
        );
        assert!(crate::db::settings_keys::dispute_admin("order-a")
            .starts_with(crate::db::settings_keys::DISPUTE_ADMIN_PREFIX));
    }

    #[tokio::test]
    async fn a_peer_opened_dispute_still_records_the_solver() {
        // The party that did not open the dispute has no local record when
        // `admin-took-dispute` arrives. Dropping it there would lose the only
        // pubkey that can establish the dispute chat.
        let trade_id = format!("t-{}", uuid::Uuid::new_v4());
        let admin_pk = "0000000000000000000000000000000000000000000000000000000000000002";

        assert!(get_dispute(trade_id.clone()).await.unwrap().is_none());

        handle_admin_took_dispute(trade_id.clone(), admin_pk.to_string())
            .await
            .unwrap();

        let dispute = get_dispute(trade_id).await.unwrap().expect("record created");
        assert_eq!(dispute.admin_pubkey.as_deref(), Some(admin_pk));
        assert_eq!(dispute.status, DisputeStatus::InReview);
        assert!(!dispute.initiated_by_me);
        assert!(!dispute.is_read, "a new solver assignment is unread");
    }

    /// PR #253 race, direction 1: `admin-took-dispute` lands between
    /// `open_dispute`'s publish and its post-publish insert. The insert must
    /// claim the handler's placeholder — keeping the solver and the InReview
    /// status it already learned — instead of failing DisputeAlreadyOpen and
    /// losing the initiator's metadata.
    #[tokio::test]
    async fn open_dispute_insert_claims_the_admin_took_placeholder() {
        let trade_id = format!("t-{}", uuid::Uuid::new_v4());
        let admin_pk = "0000000000000000000000000000000000000000000000000000000000000003";

        handle_admin_took_dispute(trade_id.clone(), admin_pk.to_string())
            .await
            .unwrap();

        // Model the in-flight open_dispute call that raced the assignment:
        // its pending marker is what authorizes the claim.
        pending_opens().lock().unwrap().insert(trade_id.clone());
        let _pending = PendingOpenGuard(trade_id.clone());

        // Exactly what open_dispute persists after a successful publish.
        let own = Dispute {
            id: uuid::Uuid::new_v4().to_string(),
            trade_id: trade_id.clone(),
            status: DisputeStatus::Open,
            initiated_by_me: true,
            reason: Some("no payment".to_string()),
            admin_pubkey: None,
            resolution: None,
            opened_at: unix_now(),
            resolved_at: None,
            is_read: true,
        };
        let stored = dispute_store()
            .try_insert_if_absent_or_resolved(own)
            .await
            .expect("the placeholder must be claimed, not rejected");

        assert!(stored.initiated_by_me, "initiator metadata must be restored");
        assert_eq!(stored.reason.as_deref(), Some("no payment"));
        assert_eq!(
            stored.status,
            DisputeStatus::InReview,
            "the solver assignment must survive the claim"
        );
        assert_eq!(stored.admin_pubkey.as_deref(), Some(admin_pk));
    }

    /// PR #253 race, direction 2: the initiator's record already exists when
    /// `admin-took-dispute` arrives. The atomic create-or-update must update
    /// it in place — never replace it with a peer-side placeholder
    /// (`initiated_by_me: false`, `reason: None`).
    #[tokio::test]
    async fn admin_took_preserves_the_initiators_metadata() {
        let trade_id = format!("t-{}", uuid::Uuid::new_v4());
        let admin_pk = "0000000000000000000000000000000000000000000000000000000000000004";
        seed_dispute(&trade_id, Some("no payment".to_string())).await;

        handle_admin_took_dispute(trade_id.clone(), admin_pk.to_string())
            .await
            .unwrap();

        let d = get_dispute(trade_id).await.unwrap().unwrap();
        assert!(d.initiated_by_me, "the initiator flag must be preserved");
        assert_eq!(d.reason.as_deref(), Some("no payment"));
        assert_eq!(d.status, DisputeStatus::InReview);
        assert_eq!(d.admin_pubkey.as_deref(), Some(admin_pk));
    }

    /// PR #253 review round 2 (ermeme): a placeholder with NO owned
    /// in-flight open attempt is a genuinely peer-opened dispute — the
    /// insert must preserve it and reject, never rewrite it as ours.
    #[tokio::test]
    async fn a_peer_owned_placeholder_is_not_claimed_without_a_pending_open() {
        let trade_id = format!("t-{}", uuid::Uuid::new_v4());
        let admin_pk = "0000000000000000000000000000000000000000000000000000000000000006";

        handle_admin_took_dispute(trade_id.clone(), admin_pk.to_string())
            .await
            .unwrap();

        let own = Dispute {
            id: uuid::Uuid::new_v4().to_string(),
            trade_id: trade_id.clone(),
            status: DisputeStatus::Open,
            initiated_by_me: true,
            reason: Some("mine".to_string()),
            admin_pubkey: None,
            resolution: None,
            opened_at: unix_now(),
            resolved_at: None,
            is_read: true,
        };
        let err = dispute_store()
            .try_insert_if_absent_or_resolved(own)
            .await
            .unwrap_err();
        assert!(err.to_string().contains("DisputeAlreadyOpen"), "got: {err}");

        let d = get_dispute(trade_id).await.unwrap().unwrap();
        assert!(!d.initiated_by_me, "peer ownership must be preserved");
        assert!(d.reason.is_none());
        assert_eq!(d.admin_pubkey.as_deref(), Some(admin_pk));
    }

    /// PR #253 review round 2 (ermeme): the daemon may reassign an
    /// in-progress dispute to a different write-capable solver and resend
    /// admin-took-dispute — the new pubkey must replace the old one, or the
    /// actual solver is unreachable.
    #[tokio::test]
    async fn a_solver_reassignment_replaces_the_stored_pubkey() {
        let trade_id = format!("t-{}", uuid::Uuid::new_v4());
        let first = "0000000000000000000000000000000000000000000000000000000000000007";
        let second = "0000000000000000000000000000000000000000000000000000000000000008";
        seed_dispute(&trade_id, None).await;

        handle_admin_took_dispute(trade_id.clone(), first.to_string())
            .await
            .unwrap();
        handle_admin_took_dispute(trade_id.clone(), second.to_string())
            .await
            .expect("reassignment must be accepted");

        let d = get_dispute(trade_id).await.unwrap().unwrap();
        assert_eq!(d.status, DisputeStatus::InReview);
        assert_eq!(d.admin_pubkey.as_deref(), Some(second));
        assert!(!d.is_read, "a reassignment is news the user has not seen");
    }

    /// PR #253 review round 2 (ermeme): a replayed assignment for the same
    /// solver is the retry path for the best-effort key derivation and must
    /// be idempotent, not InvalidState.
    #[tokio::test]
    async fn a_same_solver_assignment_replay_is_idempotent() {
        let trade_id = format!("t-{}", uuid::Uuid::new_v4());
        let admin_pk = "0000000000000000000000000000000000000000000000000000000000000009";
        seed_dispute(&trade_id, None).await;

        handle_admin_took_dispute(trade_id.clone(), admin_pk.to_string())
            .await
            .unwrap();
        handle_admin_took_dispute(trade_id.clone(), admin_pk.to_string())
            .await
            .expect("same-solver replay must be an idempotent retry");

        let d = get_dispute(trade_id).await.unwrap().unwrap();
        assert_eq!(d.status, DisputeStatus::InReview);
        assert_eq!(d.admin_pubkey.as_deref(), Some(admin_pk));
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
    async fn key_derivation_failure_does_not_block_dispute_status_update() {
        // Verifies the best-effort contract: even when adminSharedKey derivation
        // fails (here because there is no registered trade key for this trade_id,
        // so `trade_key_for_order` returns None), the function must still:
        //   1. Return Ok(())
        //   2. Set the dispute status to InReview
        //   3. Store the admin pubkey
        //
        // The derivation failure path reached here is "no trade key" (the most
        // common failure mode in tests). In production the equivalent happens
        // when the session has been cleaned up before adminTookDispute arrives.
        // The important invariant is that the store update is never rolled back
        // by a derivation error.
        let trade_id = format!("t-{}", uuid::Uuid::new_v4());
        seed_dispute(&trade_id, None).await;
        // Generator point G — a known valid secp256k1 pubkey.
        let fake_admin_pk =
            "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798";
        // No trade key registered for trade_id → trade_key_for_order returns
        // None → derivation returns Err → logged as warning, not propagated.
        let result = handle_admin_took_dispute(trade_id.clone(), fake_admin_pk.into()).await;
        assert!(result.is_ok(), "expected Ok(()) despite derivation failure, got: {:?}", result);

        let d = get_dispute(trade_id).await.unwrap().unwrap();
        assert_eq!(d.status, DisputeStatus::InReview, "dispute must be InReview after admin took it");
        assert_eq!(d.admin_pubkey.as_deref(), Some(fake_admin_pk), "admin pubkey must be stored");
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
