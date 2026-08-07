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
/// Sends a `Dispute` action to the Mostro daemon, waits for its reply, and
/// creates the local `Dispute` record **only** once the daemon has accepted
/// it. A publish is not an acceptance: the daemon rejects a dispute the trade
/// is not eligible for with `CantDo`, and persisting on publish left that
/// rejection unreconciled — the dispute stayed locally Open forever (#202).
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
            nostr_sdk::PublicKey::from_hex(&crate::config::active_mostro_pubkey())
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
    let reply_rx =
        crate::api::orders::register_dispute_request(trade_pk_hex.clone(), request_id, trade_index);

    if let Err(e) = crate::api::orders::publish_event(&event_json).await {
        crate::api::orders::remove_pending_request(&trade_pk_hex, request_id);
        return Err(anyhow!("ProtocolError: publish failed: {e}"));
    }

    log::info!("[disputes] Dispute dispatched for trade={trade_id} — waiting for daemon");

    // Timeout detaches only the waiter: the record survives so a genuine late
    // reply is still recognized as this attempt's, and a stale replay still is
    // not.
    let reply = crate::rt::time::timeout(std::time::Duration::from_secs(10), reply_rx).await;
    if !matches!(reply, Ok(Ok(_))) {
        crate::api::orders::detach_request_waiter(&trade_pk_hex, request_id);
    }

    let dispute_id = match reply {
        Ok(Ok(crate::api::orders::DaemonReply::DisputeAccepted { dispute_id })) => dispute_id,
        Ok(Ok(crate::api::orders::DaemonReply::Rejected { reason, message })) => {
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
        Ok(()) => log::info!(
            "[disputes] reconciled late daemon acceptance for trade={trade_id}"
        ),
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

    derive_admin_shared_key(&trade_id, &admin_pubkey_for_key).await
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
pub(crate) async fn resubscribe_active_dispute_chats() {
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
        let trade_id = format!("t-{}", uuid::Uuid::new_v4());
        let daemon_dispute_id = uuid::Uuid::new_v4().to_string();

        assert!(get_dispute(trade_id.clone()).await.unwrap().is_none());

        record_late_acceptance(&trade_id, Some(daemon_dispute_id.clone())).await;

        let d = get_dispute(trade_id).await.unwrap().expect("record created");
        assert_eq!(d.id, daemon_dispute_id, "the daemon's id must be adopted");
        assert_eq!(d.status, DisputeStatus::Open);
        assert!(d.initiated_by_me, "we did open it, late reply or not");
        assert!(!d.is_read, "the caller was told it failed — this is news");
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
