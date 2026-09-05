/// Disputes API — open, track, and resolve trade disputes.
///
/// Dispute initiation sends a `Dispute` action to the Mostro daemon over
/// transport v2 (NIP-44, signed kind 14).  Incoming admin actions (`adminTookDispute`, `adminSettled`,
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

    #[cfg(test)]
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
                //
                // The id is part of that metadata (PR #275 review). The
                // placeholder was minted locally because the peer path never
                // sees the daemon's id, while an accepted open carries it; the
                // window this race lives in is now the whole reply wait, so
                // keeping the placeholder's id would routinely discard the
                // daemon's.
                Some(existing)
                    if is_peer_placeholder(existing)
                        && pending_opens()
                            .lock()
                            .map(|set| set.contains(&dispute.trade_id))
                            .unwrap_or(false) =>
                {
                    existing.id = dispute.id;
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

/// Whether `dispute` is the record `handle_admin_took_dispute` writes when it
/// is the first thing this side hears about the dispute: InReview, not ours,
/// no reason, solver known, and an id minted locally because the peer path
/// never sees the daemon's.
///
/// Both paths that learn a dispute is in fact ours — the post-acceptance
/// insert and the late-acceptance reconciliation — test for exactly this shape
/// before claiming it, so the predicate lives in one place.
fn is_peer_placeholder(dispute: &Dispute) -> bool {
    dispute.status == DisputeStatus::InReview
        && !dispute.initiated_by_me
        && dispute.reason.is_none()
        && dispute.admin_pubkey.is_some()
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
/// Sends a `Dispute` action to the Mostro daemon over transport v2, waits for
/// its reply, and creates the local `Dispute` record **only** once the daemon
/// has accepted it. A publish is not an acceptance: the daemon rejects a
/// dispute the trade is not eligible for with `CantDo`, and persisting on
/// publish left that rejection unreconciled — the dispute stayed locally Open
/// forever (#202).
///
/// **Preconditions**: Trade MUST be disputable (funds in escrow). No existing
/// open dispute for this trade.
///
/// **Errors**: `TradeNotDisputable`, `DisputeAlreadyOpen`, `ProtocolError`,
/// `NoDaemonResponse`, plus daemon `CantDo` reasons passed through.
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
    //
    // Claiming it is also what makes the open single-flight (PR #275 review).
    // The entry check above cannot see a concurrent attempt — neither has
    // persisted anything yet — and both would derive the same trade key, so
    // the second registration would replace the first one's pending record and
    // strand its waiter on a NoDaemonResponse the daemon never caused.
    let fresh = pending_opens()
        .lock()
        .expect("pending_opens poisoned")
        .insert(trade_id.clone());
    if !fresh {
        bail!("DisputeAlreadyOpen: an open_dispute for trade {trade_id} is already in flight");
    }
    let _pending = PendingOpenGuard(trade_id.clone());

    // Dispatch Action::Dispute to Mostro BEFORE creating the local record so
    // that a request the daemon never accepted does not leave an un-retryable
    // "open" slot in the dispute store.
    let trade_index = crate::api::orders::trade_key_for_order(&trade_id)
        .await
        .ok_or_else(|| anyhow!("TradeNotDisputable: no trade key for trade {trade_id}"))?;

    // Correlation nonce for this request. The daemon echoes it in its reply —
    // DisputeInitiatedByYou on acceptance, CantDo on rejection — and only a
    // reply carrying it may resolve the wait below.
    let request_id: u64 = {
        use rand::RngCore;
        rand::rngs::OsRng.next_u64().max(1) // 0 is indistinguishable from "unset"
    };

    let (trade_pk_hex, event_json) = async {
        let sender_keys =
            crate::api::identity::get_active_trade_keys(trade_index).await?;
        let identity_keys =
            crate::api::identity::get_transport_identity_keys(&sender_keys).await?;
        let mostro_pubkey =
            nostr_sdk::prelude::PublicKey::from_hex(&crate::config::active_mostro_pubkey())
                .map_err(|e| anyhow!("invalid mostro pubkey: {e}"))?;
        let event_json = crate::mostro::actions::dispute(
            &identity_keys,
            &sender_keys,
            &mostro_pubkey,
            &trade_id,
            trade_index,
            request_id,
        )
        .await?;
        Ok::<_, anyhow::Error>((sender_keys.public_key().to_hex(), event_json))
    }
    .await
    .map_err(|e| anyhow!("ProtocolError: could not build Dispute message: {e}"))?;

    // Register the pending record BEFORE publishing so the reply cannot race
    // the bookkeeping. The trade key is already subscribed — the trade is
    // active — so no new subscription is needed here.
    let reply_rx = crate::mostro::pending::register_dispute_request(
        trade_pk_hex.clone(),
        request_id,
        trade_index,
    );

    if let Err(e) = crate::api::orders::publish_event(&event_json).await {
        // Roll back only this attempt: if it is a retry, the timed-out attempt
        // it took the key from is still answerable and must stay so.
        crate::mostro::pending::roll_back_dispute_request(&trade_pk_hex, request_id);
        return Err(anyhow!("ProtocolError: publish failed: {e}"));
    }

    log::info!("[disputes] Dispute dispatched for trade={trade_id} — waiting for daemon");

    // Timeout detaches only the waiter: the record survives so a genuine late
    // reply is still recognized as this attempt's, and a stale replay still is
    // not.
    let reply = crate::rt::time::timeout(std::time::Duration::from_secs(10), reply_rx).await;
    if !matches!(reply, Ok(Ok(_))) {
        crate::mostro::pending::detach_request_waiter(&trade_pk_hex, request_id);
    }

    use crate::mostro::pending::{DaemonReply, Wake};
    let dispute_id = match reply {
        Ok(Ok(Wake { reply: DaemonReply::DisputeAccepted { dispute_id }, .. })) => dispute_id,
        Ok(Ok(Wake { reply: DaemonReply::Rejected { reason, message }, .. })) => {
            log::warn!("[disputes] open_dispute rejected for trade={trade_id}: {reason}");
            bail!("{message}");
        }
        Ok(Ok(_)) => bail!("ProtocolError: unexpected daemon reply to Dispute"),
        // The daemon answers a rejected dispute with CantDo, but only for
        // MostroCantDo causes: a duplicate dispute or a DB failure is an
        // internal error it merely logs (mostro src/app.rs, manage_errors),
        // so silence is a real outcome here and not only a lost event.
        _ => {
            log::warn!("[disputes] open_dispute: no daemon response within 10s for trade={trade_id}");
            bail!("NoDaemonResponse");
        }
    };

    // The daemon accepted it — persist the dispute under the id it assigned,
    // which is what the solver and the daemon's Kind 38386 dispute event refer
    // to. An acceptance without that id is malformed and fails closed (PR #275
    // review): `Dispute.id` is contractually the daemon's, and a locally minted
    // one would be indistinguishable from it while being wrong. A conforming
    // daemon always sends it (mostro src/app/dispute.rs,
    // notify_dispute_to_users).
    let Some(dispute_id) = dispute_id else {
        bail!("ProtocolError: daemon accepted the dispute without a dispute id");
    };

    let dispute = Dispute {
        id: dispute_id,
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

    let stored = dispute_store()
        .try_insert_if_absent_or_resolved(dispute)
        .await?;
    persist_dispute_origin(&trade_id).await;
    Ok(stored)
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

    let admin_pubkey = nostr_sdk::prelude::PublicKey::from_hex(admin_pubkey_hex)
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

    // Record it locally so the dispute conversation has history, exactly as a
    // peer message does. Keyed by the inner event id, so our own echo arriving
    // from a relay dedups against this record instead of duplicating it.
    crate::api::messages::store_outgoing_admin_message(&trade_id, &ctx, &text, &inner).await;

    log::info!("[disputes] evidence submitted for trade={trade_id}");
    Ok(())
}

/// Record a dispute the daemon accepted after `open_dispute` had already
/// stopped waiting for the reply.
///
/// The acceptance is genuine — the daemon opened the dispute, told the
/// counterparty, and published its Kind 38386 event — so the reply's status
/// update moves the trade to `Dispute` either way. Dropping the record while
/// letting that through would leave a disputed trade with no dispute to open
/// and no way to reach the solver, which is the same split state this whole
/// change set exists to remove (PR #275 review). The caller saw
/// `NoDaemonResponse`, so the record lands unread.
///
/// The dispute's reason went with the timed-out call and is not recoverable
/// here.
///
/// A solver can be assigned inside the same window, so the record may already
/// exist as the peer-style placeholder — and then it is ours after all
/// (PR #275 review): it is claimed exactly as the post-acceptance insert
/// claims it, keeping the solver and InReview it learned while taking the
/// daemon's id and the initiator flag. The claim needs no in-flight marker
/// here the way that path does; a `DisputeInitiatedByYou` correlated to our
/// own nonce is itself the proof the dispute is ours. Any other existing
/// record — a retry that succeeded, a resolved dispute — is left untouched.
///
/// Fails closed on an acceptance carrying no dispute id, for the same reason
/// `open_dispute` does: the record would claim a daemon id it does not have.
pub(crate) async fn record_late_acceptance(trade_id: &str, dispute_id: Option<String>) {
    let Some(id) = dispute_id else {
        log::warn!(
            "[disputes] late acceptance for trade={trade_id} carried no dispute id — not recorded"
        );
        return;
    };
    let trade_id_for_new = trade_id.to_string();
    let id_for_claim = id.clone();

    let result = dispute_store()
        .upsert_or_update(
            trade_id,
            || Dispute {
                id,
                trade_id: trade_id_for_new,
                status: DisputeStatus::Open,
                initiated_by_me: true,
                reason: None,
                admin_pubkey: None,
                resolution: None,
                opened_at: unix_now(),
                resolved_at: None,
                is_read: false,
            },
            move |existing| {
                if is_peer_placeholder(existing) {
                    existing.id = id_for_claim;
                    existing.initiated_by_me = true;
                }
                Ok(())
            },
        )
        .await;

    match result {
        Ok(()) => {
            // Same as the on-time path: this side opened it, and the replay
            // can never restore that, so the marker must be written here too
            // or a restart would rehydrate the record as peer-opened.
            persist_dispute_origin(trade_id).await;
            log::info!("[disputes] reconciled late daemon acceptance for trade={trade_id}");
        }
        Err(e) => log::warn!(
            "[disputes] could not reconcile late acceptance for trade={trade_id}: {e}"
        ),
    }
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

    // The offline catch-up channel has no `since` (orders.rs), so this action
    // is re-delivered on every reconnect — including for disputes the admin
    // already settled or canceled. Those verdicts are persisted on the trade
    // row by the status-sync arm, so the trade is the durable "this dispute is
    // over" signal: refuse here rather than recreate the record as `InReview`,
    // write the solver key straight back after rehydration just cleared it,
    // and arm a listener nobody is on the other end of (PR #256 review,
    // manual E2E). Best-effort like the rest of persistence: no store, or no
    // persisted trade, means no evidence the dispute ended, so proceed.
    if persisted_order_is_finished(&trade_id).await {
        crate::api::logging::blog_info(
            "disputes",
            format!(
                "skip replayed admin-took-dispute order={}: trade already finished",
                crate::api::logging::short_id(&trade_id),
            ),
        );
        clear_dispute_keys(&trade_id).await;
        return Ok(());
    }

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

/// Persist the solver pubkey as a fallback for when the daemon replay does
/// not bring it back.
///
/// Deliberately narrow: the dispute record stays in memory (its status and
/// resolution come back from daemon events). The solver pubkey normally comes
/// back too — the catch-up channel replays `admin-took-dispute` on every
/// reconnect — but that replay is bounded by relay retention and by the
/// per-subscription result cap, so a long dispute can outlive it. This copy
/// is what re-arms the dispute chat when the replay no longer covers the
/// assignment (PR #256 review, A/B against `main`).
///
/// Best-effort — a storage failure must not undo an already-applied dispute
/// update, and the live listener keeps working for this session.
async fn persist_admin_pubkey(order_id: &str, admin_pubkey_hex: &str) {
    let Some(db) = crate::db::app_db::db() else {
        crate::api::logging::blog_warn(
            "disputes",
            "no store — solver pubkey will not survive a restart".to_string(),
        );
        return;
    };
    if let Err(e) = db
        .set_setting(
            &crate::db::settings_keys::dispute_admin(order_id),
            admin_pubkey_hex,
        )
        .await
    {
        crate::api::logging::blog_warn(
            "disputes",
            format!("could not persist solver pubkey for {order_id}: {e}"),
        );
    }
}

/// `true` when the persisted trade for `order_id` has reached a terminal
/// status (see [`is_order_finished`]). No store, no persisted trade, or a
/// storage error all read as "not finished": absence of evidence must not
/// drop a live assignment.
async fn persisted_order_is_finished(order_id: &str) -> bool {
    let Some(db) = crate::db::app_db::db() else {
        return false;
    };
    match db.get_trade_by_order_id(order_id).await {
        Ok(Some(trade)) => is_order_finished(&trade.order.status),
        Ok(None) => false,
        Err(e) => {
            crate::api::logging::blog_warn(
                "disputes",
                format!("could not read trade for {order_id}: {e}"),
            );
            false
        }
    }
}

/// Persist that this side opened the dispute on `order_id`.
///
/// Same category as the solver pubkey (PR #256 review): the origin is not
/// re-derivable from daemon events, and a rehydrated record that silently
/// claimed "the counterparty opened this" would show the initiator the wrong
/// description. Best-effort like the pubkey.
async fn persist_dispute_origin(order_id: &str) {
    let Some(db) = crate::db::app_db::db() else {
        return;
    };
    if let Err(e) = db
        .set_setting(&crate::db::settings_keys::dispute_mine(order_id), "1")
        .await
    {
        crate::api::logging::blog_warn(
            "disputes",
            format!("could not persist dispute origin for {order_id}: {e}"),
        );
    }
}

/// Drop the persisted dispute keys (solver pubkey, origin marker) for
/// `order_id`.
///
/// The stored solver is what rehydration reads as "this order has a live
/// dispute", so it must not outlive the dispute: left behind, every restart
/// would resurrect a finished dispute as `InReview`, arm a listener for it and
/// keep accepting evidence. Called when a resolution reaches the store, when
/// rehydration meets an already-finished trade, and when a replayed
/// `admin-took-dispute` is refused for one.
///
/// Best-effort like the writes: a storage failure only means the stale key is
/// seen again — and cleared again — on the next pass.
async fn clear_dispute_keys(order_id: &str) {
    let Some(db) = crate::db::app_db::db() else {
        return;
    };
    for key in [
        crate::db::settings_keys::dispute_admin(order_id),
        crate::db::settings_keys::dispute_mine(order_id),
    ] {
        if let Err(e) = db.delete_setting(&key).await {
            crate::api::logging::blog_warn("disputes", format!("could not clear {key}: {e}"));
        }
    }
}

/// `true` when the order reached a state in which no dispute can still be live.
///
/// This is what keeps rehydration from resurrecting finished disputes, and it
/// deliberately reads the *trade* status rather than the dispute record: the
/// daemon's `admin-settled` / `admin-canceled` are persisted by the status-sync
/// arm in `orders.rs`, which does not route them into the dispute store, so the
/// trade row is the durable evidence that the dispute is over.
///
/// Exhaustive on purpose: a variant added later must decide here whether it
/// ends a dispute, instead of silently falling through as "live" and
/// resurrecting closed disputes — the one thing this function exists to
/// prevent.
fn is_order_finished(status: &OrderStatus) -> bool {
    match status {
        OrderStatus::SettledByAdmin
        | OrderStatus::CanceledByAdmin
        | OrderStatus::CompletedByAdmin
        | OrderStatus::Success
        | OrderStatus::Canceled
        | OrderStatus::CooperativelyCanceled
        | OrderStatus::Expired => true,
        OrderStatus::Pending
        | OrderStatus::WaitingBuyerInvoice
        | OrderStatus::WaitingPayment
        | OrderStatus::Active
        | OrderStatus::FiatSent
        | OrderStatus::SettledHoldInvoice
        | OrderStatus::Dispute
        | OrderStatus::InProgress => false,
    }
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
        let admin_pk = nostr_sdk::prelude::PublicKey::from_hex(&admin_pubkey_hex)
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

/// Rebuild dispute records for orders with a persisted solver pubkey.
///
/// This runs before the daemon replay has a chance to: the catch-up channel
/// usually re-delivers `admin-took-dispute` and rebuilds the record on its
/// own, but always with `initiated_by_me: false`, and only while the relays
/// still hold the event. Rehydration restores the persisted origin either way
/// and the solver when the replay no longer covers it.
///
/// Trades are the enumeration source, so no key-prefix scan is needed: each
/// persisted trade is asked whether it has a stored solver. Records already in
/// memory win — they are at least as fresh as storage — and that rule is
/// enforced under the store's single write lock (`upsert_or_update` with a
/// no-op update), not by a check-then-act: an `admin-took-dispute` or an
/// `open_dispute` landing while this pass is awaiting storage must not be
/// clobbered by a stale rehydrated record (PR #256 review).
///
/// Status is `InReview`: a stored solver means one took the dispute, and any
/// later resolution arrives as a daemon event. The origin comes from the
/// persisted marker `open_dispute` writes. Restoring the record is what lets
/// `submit_evidence` work again after a restart, since it refuses without one.
/// Only *unfinished* trades are restored — see [`is_order_finished`]; finished
/// ones have both keys cleared, whether or not a solver ever took the dispute.
///
/// **Web has no rehydration.** `app_bootstrap.dart` skips `initDb` off native, and
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
            crate::api::logging::blog_warn(
                "disputes",
                format!("rehydrate: list_trades failed: {e}"),
            );
            return;
        }
    };

    for trade in trades {
        let order_id = trade.order.id.clone();
        // Cheap skip only — not the guard. The record can still appear while
        // the reads below await; `upsert_or_update` is what makes it win.
        if dispute_store().get(&order_id).await.is_some() {
            continue;
        }

        // The trade already ended — any key left for it is stale. A solver
        // key restored here would recreate the dispute as `InReview` on every
        // single restart, arm a listener nobody is on the other end of, and
        // keep letting evidence be submitted against a closed case. Checked
        // before the solver read so an origin marker whose dispute was never
        // taken is swept too, instead of staying behind forever.
        if is_order_finished(&trade.order.status) {
            if has_dispute_keys(db, &order_id).await {
                crate::api::logging::blog_info(
                    "disputes",
                    format!(
                        "rehydrate: dropping stale dispute keys for finished order={} status={:?}",
                        crate::api::logging::short_id(&order_id),
                        trade.order.status
                    ),
                );
                clear_dispute_keys(&order_id).await;
            }
            continue;
        }

        let admin_hex = match db
            .get_setting(&crate::db::settings_keys::dispute_admin(&order_id))
            .await
        {
            Ok(Some(hex)) => hex,
            Ok(None) => continue,
            Err(e) => {
                crate::api::logging::blog_warn(
                    "disputes",
                    format!("rehydrate: reading solver for {order_id}: {e}"),
                );
                continue;
            }
        };

        let initiated_by_me = match db
            .get_setting(&crate::db::settings_keys::dispute_mine(&order_id))
            .await
        {
            Ok(marker) => marker.is_some(),
            Err(e) => {
                crate::api::logging::blog_warn(
                    "disputes",
                    format!("rehydrate: reading origin for {order_id}: {e}"),
                );
                false
            }
        };

        let make_id = order_id.clone();
        let _ = dispute_store()
            .upsert_or_update(
                &order_id,
                || Dispute {
                    id: uuid::Uuid::new_v4().to_string(),
                    trade_id: make_id,
                    status: DisputeStatus::InReview,
                    initiated_by_me,
                    reason: None,
                    admin_pubkey: Some(admin_hex),
                    resolution: None,
                    opened_at: unix_now(),
                    resolved_at: None,
                    // The pre-restart read state is not recoverable, and this
                    // is an active dispute waiting on the user — default to
                    // unread so it surfaces rather than being silently marked
                    // as seen.
                    is_read: false,
                },
                // Already in memory: at least as fresh as storage, keep it.
                |_| Ok(()),
            )
            .await;
        crate::api::logging::blog_info(
            "disputes",
            format!(
                "rehydrated dispute record order={}",
                crate::api::logging::short_id(&order_id)
            ),
        );
    }
}

/// `true` when either persisted dispute key still exists for `order_id`.
/// Reads only, so a reconnect pass over many finished trades does not turn
/// into a write per trade; a read error counts as present so the key gets a
/// clearing attempt rather than being silently kept.
async fn has_dispute_keys(db: &impl Storage, order_id: &str) -> bool {
    for key in [
        crate::db::settings_keys::dispute_admin(order_id),
        crate::db::settings_keys::dispute_mine(order_id),
    ] {
        match db.get_setting(&key).await {
            Ok(Some(_)) | Err(_) => return true,
            Ok(None) => {}
        }
    }
    false
}

/// Re-arm the dispute-chat listener of every in-review dispute with a known
/// solver. Called when the relay pool comes (back) online, mirroring
/// `resubscribe_active_chats` for the peer channel (PR #254 review): listener
/// startup is best-effort at assignment time and can fail while keys or
/// connectivity are not there yet, and without a rearm path solver replies
/// would stay invisible for the rest of the process. Idempotent — the
/// per-channel single-owner guard makes a spawn for an already-listening
/// dispute a no-op.
pub(crate) async fn resubscribe_active_dispute_chats() {
    // A restart leaves the in-memory store empty, so the loop below would find
    // nothing to re-arm. Refill it from the persisted keys first: the origin
    // is never re-derivable, and the solver pubkey only is while the daemon
    // replay still covers the assignment.
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
    clear_dispute_keys(&trade_id).await;
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

    /// PR #275 review: a second open for the same trade while the first is
    /// still awaiting the daemon must be refused. Both would derive the same
    /// trade key, so letting it through would replace the first attempt's
    /// pending record and strand its waiter.
    #[tokio::test]
    async fn a_second_open_is_refused_while_one_is_in_flight() {
        let trade_id = format!("t-{}", uuid::Uuid::new_v4());
        pending_opens().lock().unwrap().insert(trade_id.clone());
        let _pending = PendingOpenGuard(trade_id.clone());

        let err = open_dispute(trade_id, None).await.unwrap_err();
        assert!(
            err.to_string().contains("already in flight"),
            "expected the in-flight guard to reject it, got: {err}"
        );
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
            peer_rating: None,
            peer_reviews: None,
            peer_days: None,
            rated_at: None,
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
        let peer = format!("peer-{}", uuid::Uuid::new_v4());
        let finished = format!("finished-{}", uuid::Uuid::new_v4());
        let orphan = format!("orphan-{}", uuid::Uuid::new_v4());
        let in_memory = format!("mem-{}", uuid::Uuid::new_v4());
        let stored_solver = "0000000000000000000000000000000000000000000000000000000000000011";
        let fresher_solver = "0000000000000000000000000000000000000000000000000000000000000022";

        for (order_id, status) in [
            (&live, OrderStatus::Dispute),
            (&peer, OrderStatus::Dispute),
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
        // `orphan`: opened by this side, never taken by a solver, then canceled
        // — only the origin marker exists for it.
        db.save_trade(&persisted_trade(&orphan, OrderStatus::Canceled))
            .await
            .unwrap();
        // `live`, `finished` and `orphan` were opened by this side; `peer` was not.
        for order_id in [&live, &finished, &orphan] {
            db.set_setting(&crate::db::settings_keys::dispute_mine(order_id), "1")
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
        assert!(
            restored.initiated_by_me,
            "the origin is persisted too: the initiator must not be told the peer opened it"
        );
        let peer_opened = get_dispute(peer.clone()).await.unwrap().expect("restored");
        assert!(!peer_opened.initiated_by_me);

        // 2. The finished one did not, and its stale keys are gone — otherwise
        //    every later restart resurrects it as InReview.
        assert!(get_dispute(finished.clone()).await.unwrap().is_none());
        for key in [
            crate::db::settings_keys::dispute_admin(&finished),
            crate::db::settings_keys::dispute_mine(&finished),
        ] {
            assert_eq!(
                db.get_setting(&key).await.unwrap(),
                None,
                "the stale key must be cleared, not just skipped"
            );
        }

        // 3. The in-memory record is at least as fresh as storage, so the
        //    older stored solver must not overwrite it.
        let kept = get_dispute(in_memory.clone()).await.unwrap().expect("kept");
        assert_eq!(kept.admin_pubkey.as_deref(), Some(fresher_solver));

        // 4. A finished trade with only the origin marker is swept too — the
        //    terminal check runs before the solver read, so a dispute that
        //    was opened but never taken does not leave its marker behind.
        assert!(get_dispute(orphan.clone()).await.unwrap().is_none());
        assert_eq!(
            db.get_setting(&crate::db::settings_keys::dispute_mine(&orphan))
                .await
                .unwrap(),
            None,
            "an orphan origin marker must be cleared"
        );

        // Cleanup — the rows, not the file: `init_db` is a process-wide
        // OnceCell shared with every later test (see `escrow.rs`).
        for order_id in [&live, &peer, &finished, &orphan, &in_memory] {
            clear_dispute_keys(order_id).await;
            db.delete_trade_by_order_id(order_id).await.unwrap();
        }
    }

    /// PR #256 review, manual E2E: the catch-up channel re-delivers
    /// `admin-took-dispute` on every reconnect, so a second after rehydration
    /// cleared the keys of a finished dispute, the replay recreated the record
    /// as `InReview`, wrote the solver key straight back and armed a listener
    /// — on every startup. The persisted trade status is the guard.
    #[tokio::test]
    async fn a_replayed_admin_took_dispute_is_refused_for_a_finished_trade() {
        let path = std::env::temp_dir()
            .join(format!("mostro_dispute_replay_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let Some(db) = crate::db::app_db::db() else {
            panic!("no store: the replay guard cannot be exercised");
        };

        let finished = format!("replay-finished-{}", uuid::Uuid::new_v4());
        let live = format!("replay-live-{}", uuid::Uuid::new_v4());
        let admin_pk = "0000000000000000000000000000000000000000000000000000000000000033";

        db.save_trade(&persisted_trade(&finished, OrderStatus::CanceledByAdmin))
            .await
            .unwrap();
        db.save_trade(&persisted_trade(&live, OrderStatus::Dispute))
            .await
            .unwrap();
        // Stale keys the replay would otherwise keep alive.
        db.set_setting(&crate::db::settings_keys::dispute_admin(&finished), admin_pk)
            .await
            .unwrap();
        db.set_setting(&crate::db::settings_keys::dispute_mine(&finished), "1")
            .await
            .unwrap();

        // Refused, not an error: a skipped replay is the expected path.
        handle_admin_took_dispute(finished.clone(), admin_pk.to_string())
            .await
            .unwrap();
        assert!(
            get_dispute(finished.clone()).await.unwrap().is_none(),
            "a finished trade must not get its dispute resurrected"
        );
        for key in [
            crate::db::settings_keys::dispute_admin(&finished),
            crate::db::settings_keys::dispute_mine(&finished),
        ] {
            assert_eq!(
                db.get_setting(&key).await.unwrap(),
                None,
                "the refused replay must not leave (or write back) a key"
            );
        }

        // The same message for a trade still under dispute is applied as
        // before — the guard reads the trade, not the message.
        handle_admin_took_dispute(live.clone(), admin_pk.to_string())
            .await
            .unwrap();
        let restored = get_dispute(live.clone()).await.unwrap().expect("applied");
        assert_eq!(restored.admin_pubkey.as_deref(), Some(admin_pk));
        assert_eq!(
            db.get_setting(&crate::db::settings_keys::dispute_admin(&live))
                .await
                .unwrap()
                .as_deref(),
            Some(admin_pk)
        );

        for order_id in [&finished, &live] {
            clear_dispute_keys(order_id).await;
            db.delete_trade_by_order_id(order_id).await.unwrap();
        }
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

        // Exactly what open_dispute persists after the daemon accepts: the id
        // is the daemon's, the placeholder's was minted locally.
        let daemon_dispute_id = uuid::Uuid::new_v4().to_string();
        let own = Dispute {
            id: daemon_dispute_id.clone(),
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
        // PR #275 review: the claim must not discard the daemon's id.
        assert_eq!(
            stored.id, daemon_dispute_id,
            "the claimed placeholder must adopt the daemon's dispute id"
        );
    }

    /// PR #275 review: the daemon's acceptance can land after `open_dispute`
    /// gave up. The status arm that follows moves the trade to Dispute either
    /// way, so the record must exist — otherwise the trade shows as disputed
    /// with no dispute to open and no solver to reach.
    #[tokio::test]
    async fn a_late_acceptance_is_reconciled_into_a_record() {
        // Any SqliteStorage serves (process-wide OnceCell, first caller wins):
        // this test only reads back its own key.
        let path = std::env::temp_dir()
            .join(format!("mostro_dispute_late_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");
        let trade_id = format!("t-{}", uuid::Uuid::new_v4());
        let daemon_dispute_id = uuid::Uuid::new_v4().to_string();

        assert!(get_dispute(trade_id.clone()).await.unwrap().is_none());

        record_late_acceptance(&trade_id, Some(daemon_dispute_id.clone())).await;

        let d = get_dispute(trade_id.clone()).await.unwrap().expect("record created");
        assert_eq!(d.id, daemon_dispute_id, "the daemon's id must be adopted");
        assert_eq!(d.status, DisputeStatus::Open);
        assert!(d.initiated_by_me, "we did open it, late reply or not");
        assert!(!d.is_read, "the caller was told it failed — this is news");

        // PR #256 review: the origin must be persisted on this path too, or a
        // restart rehydrates the dispute as peer-opened.
        assert_eq!(
            db.get_setting(&crate::db::settings_keys::dispute_mine(&trade_id))
                .await
                .unwrap()
                .as_deref(),
            Some("1"),
            "a late acceptance must persist the origin marker"
        );
        clear_dispute_keys(&trade_id).await;
    }

    /// PR #275 review: `Dispute.id` is contractually the daemon's, so an
    /// acceptance that carries no dispute id is malformed and must persist
    /// nothing rather than mint a local id indistinguishable from a real one.
    #[tokio::test]
    async fn a_late_acceptance_without_a_daemon_id_records_nothing() {
        let trade_id = format!("t-{}", uuid::Uuid::new_v4());

        record_late_acceptance(&trade_id, None).await;

        assert!(
            get_dispute(trade_id).await.unwrap().is_none(),
            "a malformed acceptance must not create a record"
        );
    }

    /// PR #275 review round 2: `open_dispute` times out, a solver is assigned
    /// inside the same window — writing the peer-style placeholder — and only
    /// then does the correlated acceptance arrive. The placeholder is ours
    /// after all, so the reconciliation must claim it: the daemon's id and the
    /// initiator flag replace the locally minted ones, and the solver and
    /// InReview it already learned survive.
    #[tokio::test]
    async fn a_late_acceptance_claims_the_admin_took_placeholder() {
        let trade_id = format!("t-{}", uuid::Uuid::new_v4());
        let admin_pk = "000000000000000000000000000000000000000000000000000000000000000a";
        let daemon_dispute_id = uuid::Uuid::new_v4().to_string();

        handle_admin_took_dispute(trade_id.clone(), admin_pk.to_string())
            .await
            .unwrap();
        let placeholder_id = get_dispute(trade_id.clone()).await.unwrap().unwrap().id;

        record_late_acceptance(&trade_id, Some(daemon_dispute_id.clone())).await;

        let d = get_dispute(trade_id).await.unwrap().unwrap();
        assert_ne!(d.id, placeholder_id, "the local id must not survive");
        assert_eq!(d.id, daemon_dispute_id, "the daemon's id must be adopted");
        assert!(d.initiated_by_me, "the acceptance proves the dispute is ours");
        assert_eq!(d.status, DisputeStatus::InReview, "the assignment survives");
        assert_eq!(d.admin_pubkey.as_deref(), Some(admin_pk));
    }

    /// Only the placeholder shape is claimable. A record that is already ours
    /// — a retry that succeeded while the first attempt's reply was still in
    /// flight — must survive the late reply untouched.
    #[tokio::test]
    async fn a_late_acceptance_leaves_a_successful_retry_alone() {
        let trade_id = format!("t-{}", uuid::Uuid::new_v4());
        let before = seed_dispute(&trade_id, Some("no payment".to_string())).await;

        record_late_acceptance(&trade_id, Some(uuid::Uuid::new_v4().to_string())).await;

        let after = get_dispute(trade_id).await.unwrap().unwrap();
        assert_eq!(after.id, before.id, "the retry's record owns the trade");
        assert_eq!(after.reason.as_deref(), Some("no payment"));
        assert_eq!(after.status, DisputeStatus::Open);
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
