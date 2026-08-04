/// Per-trade session state management.
///
/// Each active trade has a `Session` that tracks the order, role, keys,
/// and peer identity. Sessions are created when a trade is taken and
/// cleaned up on completion, cancellation, or timeout.
use anyhow::{anyhow, Result};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;

use crate::api::types::{OrderInfo, OrderStatus, TradeRole};

/// Per-trade session state.
#[derive(Clone)]
pub struct Session {
    pub order_id: String,
    pub role: TradeRole,
    pub trade_key_index: u32,
    /// ECDH shared key with peer (computed when peer pubkey received
    /// from Mostro via `hold-invoice-payment-accepted` action).
    pub shared_key: Option<[u8; 32]>,
    /// ECDH shared key with admin (for dispute chat).
    pub admin_shared_key: Option<[u8; 32]>,
    /// Peer's public key (hex).
    pub peer_pubkey: Option<String>,
    /// Original order snapshot.
    pub order: OrderInfo,
    /// Unix timestamp when the session was created.
    pub created_at: i64,
}

impl std::fmt::Debug for Session {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Session")
            .field("order_id", &self.order_id)
            .field("role", &self.role)
            .field("trade_key_index", &self.trade_key_index)
            .field("shared_key", &self.shared_key.as_ref().map(|_| "<REDACTED>"))
            .field("admin_shared_key", &self.admin_shared_key.as_ref().map(|_| "<REDACTED>"))
            .field("peer_pubkey", &self.peer_pubkey)
            .field("order", &self.order)
            .field("created_at", &self.created_at)
            .finish()
    }
}

// ── Cancel cleanup policy ───────────────────────────────────────────────────

/// How long a session outlives a cancel a `bond-slashed` may still trail.
///
/// Unlike v1, this is not what makes the notice arrive: the per-trade receiver
/// captures its own trade keys and `ensure_global_dm_coverage` retains them for
/// the life of the process, so neither reception nor decryption depends on the
/// session. It is a margin for handling that needs session state.
pub const BOND_SLASH_GRACE_SECS: i64 = 60;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CancelCleanup {
    Immediate,
    Defer,
    /// Dispute and admin states still need the session's keys for the admin chat.
    Keep,
}

/// Decides a session's fate from the order status recorded *before* the cancel
/// was applied.
pub fn cancel_cleanup(status: Option<&OrderStatus>) -> CancelCleanup {
    match status {
        Some(
            OrderStatus::Dispute
            | OrderStatus::CanceledByAdmin
            | OrderStatus::SettledByAdmin
            | OrderStatus::CompletedByAdmin,
        ) => CancelCleanup::Keep,
        Some(OrderStatus::Pending) => CancelCleanup::Immediate,
        _ => CancelCleanup::Defer,
    }
}

/// A pending removal, bound to the session that earned it. An order id is
/// reused across retakes, so the trade key index is what tells the canceled
/// take apart from the one that replaced it.
#[derive(Clone, Copy)]
struct DeferredRemoval {
    deadline: i64,
    trade_key_index: u32,
}

/// Sessions and their pending removals share one lock: a retake racing the
/// grace deadline must never observe one map mid-update against the other.
#[derive(Default)]
struct SessionState {
    sessions: HashMap<String, Session>,
    deferred_removals: HashMap<String, DeferredRemoval>,
}

/// In-memory session store.
pub struct SessionManager {
    state: Arc<RwLock<SessionState>>,
}

impl Default for SessionManager {
    fn default() -> Self { Self::new() }
}

impl SessionManager {
    pub fn new() -> Self {
        Self {
            state: Arc::new(RwLock::new(SessionState::default())),
        }
    }

    fn build_session(
        order_id: &str,
        role: TradeRole,
        trade_key_index: u32,
        order: OrderInfo,
    ) -> Result<Session> {
        if order_id != order.id {
            return Err(anyhow!(
                "order_id mismatch: param='{}' vs order.id='{}'",
                order_id,
                order.id
            ));
        }
        Ok(Session {
            order_id: order_id.to_string(),
            role,
            trade_key_index,
            shared_key: None,
            admin_shared_key: None,
            peer_pubkey: None,
            order,
            created_at: crate::rt::unix_now(),
        })
    }

    /// Create a new session for a trade. Returns an error if a session
    /// already exists for this order (indicates duplicate processing).
    pub async fn create_session(
        &self,
        order_id: String,
        role: TradeRole,
        trade_key_index: u32,
        order: OrderInfo,
    ) -> Result<Session> {
        let session = Self::build_session(&order_id, role, trade_key_index, order)?;

        let mut state = self.state.write().await;
        // A session awaiting deferred removal belongs to the canceled take;
        // this one supersedes it, deadline included.
        if state.deferred_removals.remove(&order_id).is_some() {
            state.sessions.remove(&order_id);
        }
        if state.sessions.contains_key(&order_id) {
            return Err(anyhow!("SessionAlreadyExists: {}", order_id));
        }
        state.sessions.insert(order_id, session.clone());
        Ok(session)
    }

    /// Install the session for a take the daemon has already confirmed.
    ///
    /// Unlike [`Self::create_session`] this never yields to what it finds: the
    /// take is accepted, so anything left under this order id belongs to an
    /// earlier one and would otherwise leave the new trade session-less.
    pub async fn install_session(
        &self,
        order_id: String,
        role: TradeRole,
        trade_key_index: u32,
        order: OrderInfo,
    ) -> Result<Session> {
        let session = Self::build_session(&order_id, role, trade_key_index, order)?;

        let mut state = self.state.write().await;
        state.deferred_removals.remove(&order_id);
        if let Some(previous) = state.sessions.insert(order_id.clone(), session.clone()) {
            log::warn!(
                "[session] order={order_id}: replaced a stale session (trade key idx {} -> {})",
                previous.trade_key_index,
                trade_key_index
            );
        }
        Ok(session)
    }

    /// Update an existing session.
    pub async fn update_session(&self, order_id: &str, session: Session) -> Result<()> {
        if session.order_id != order_id {
            return Err(anyhow!(
                "SessionOrderIdMismatch: param='{}' vs session.order_id='{}'",
                order_id,
                session.order_id
            ));
        }
        let mut state = self.state.write().await;
        if !state.sessions.contains_key(order_id) {
            return Err(anyhow!("SessionNotFound"));
        }
        state.sessions.insert(order_id.to_string(), session);
        Ok(())
    }

    /// Get a session by order ID.
    pub async fn get_session(&self, order_id: &str) -> Option<Session> {
        self.state.read().await.sessions.get(order_id).cloned()
    }

    /// Remove a session (on completion, cancellation, or timeout).
    pub async fn remove_session(&self, order_id: &str) {
        let mut state = self.state.write().await;
        state.deferred_removals.remove(order_id);
        state.sessions.remove(order_id);
    }

    /// Whether `trade_key_index` still names the live session for this order.
    ///
    /// An order id outlives the take that used it: after a retake, a delivery
    /// addressed to the previous trade key must not act on the fresh session.
    /// An order with no session — a maker canceling their own listing — has no
    /// generation to contradict.
    pub async fn is_current_generation(&self, order_id: &str, trade_key_index: u32) -> bool {
        match self.state.read().await.sessions.get(order_id) {
            Some(session) => session.trade_key_index == trade_key_index,
            None => true,
        }
    }

    /// Remove the session only while `trade_key_index` still names it.
    pub async fn remove_session_if_current(&self, order_id: &str, trade_key_index: u32) {
        let mut state = self.state.write().await;
        if state
            .sessions
            .get(order_id)
            .is_some_and(|s| s.trade_key_index == trade_key_index)
        {
            state.deferred_removals.remove(order_id);
            state.sessions.remove(order_id);
        }
    }

    /// Defer this session's removal until `delay_secs` from now.
    pub async fn defer_removal(&self, order_id: &str, trade_key_index: u32, delay_secs: i64) {
        let deadline = crate::rt::unix_now() + delay_secs;
        self.state.write().await.deferred_removals.insert(
            order_id.to_string(),
            DeferredRemoval {
                deadline,
                trade_key_index,
            },
        );
    }

    /// Settle a deferred removal early. Reports whether one was pending for
    /// this generation; anything else is left untouched. The session is only
    /// dropped while it is still the one the deferral was armed against — a
    /// retake in between keeps its own.
    pub async fn resolve_deferred_removal(&self, order_id: &str, trade_key_index: u32) -> bool {
        let mut state = self.state.write().await;
        let matches = state
            .deferred_removals
            .get(order_id)
            .is_some_and(|d| d.trade_key_index == trade_key_index);
        if !matches {
            return false;
        }
        state.deferred_removals.remove(order_id);
        if state
            .sessions
            .get(order_id)
            .is_some_and(|s| s.trade_key_index == trade_key_index)
        {
            state.sessions.remove(order_id);
        }
        true
    }

    /// Drop every session whose deferred deadline has elapsed. A deadline whose
    /// session has since been replaced is dropped without touching the new one.
    pub async fn reconcile_deferred_removals(&self) {
        let now = crate::rt::unix_now();
        let mut state = self.state.write().await;
        let due: Vec<(String, u32)> = state
            .deferred_removals
            .iter()
            .filter(|(_, d)| now >= d.deadline)
            .map(|(order_id, d)| (order_id.clone(), d.trade_key_index))
            .collect();
        for (order_id, trade_key_index) in due {
            state.deferred_removals.remove(&order_id);
            if state
                .sessions
                .get(&order_id)
                .is_some_and(|s| s.trade_key_index == trade_key_index)
            {
                state.sessions.remove(&order_id);
            }
        }
    }

    /// Store the ECDH admin shared key derived from `adminTookDispute`.
    ///
    /// Called by the event handler when the daemon assigns an admin to the
    /// dispute. The key is derived from the trade BIP-32 key and the admin's
    /// Nostr public key using NIP-44 v2 ECDH.
    pub async fn set_admin_shared_key(
        &self,
        order_id: &str,
        key: [u8; 32],
    ) -> Result<()> {
        let mut state = self.state.write().await;
        let session = state
            .sessions
            .get_mut(order_id)
            .ok_or_else(|| anyhow!("SessionNotFound: {order_id}"))?;
        session.admin_shared_key = Some(key);
        Ok(())
    }

    /// Remove sessions older than `timeout_secs` that have no shared key
    /// (i.e., the take action was never acknowledged by Mostro).
    pub async fn cleanup_stale_sessions(&self, timeout_secs: i64) {
        let now = crate::rt::unix_now();

        let mut state = self.state.write().await;
        state.sessions.retain(|_, s| {
            s.shared_key.is_some() || (now - s.created_at) < timeout_secs
        });
    }
}

// ── Global singleton ────────────────────────────────────────────────────────

use std::sync::OnceLock;

static SESSION_MGR: OnceLock<SessionManager> = OnceLock::new();

/// Get the global session manager.
pub fn session_manager() -> &'static SessionManager {
    SESSION_MGR.get_or_init(SessionManager::new)
}

/// Register a deferred removal and arm the timer that enforces it.
///
/// Registration is awaited so a `bond-slashed` arriving right after the cancel
/// always finds the deferral armed; only the deadline runs in the background.
pub async fn defer_session_removal(order_id: String, trade_key_index: u32, delay_secs: i64) {
    session_manager()
        .defer_removal(&order_id, trade_key_index, delay_secs)
        .await;
    crate::rt::spawn(async move {
        crate::rt::time::sleep(crate::rt::time::Duration::from_secs(
            delay_secs.max(0) as u64
        ))
        .await;
        session_manager().reconcile_deferred_removals().await;
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::types::OrderKind;

    fn dummy_order_info(id: &str) -> OrderInfo {
        OrderInfo {
            id: id.to_string(),
            kind: OrderKind::Buy,
            status: OrderStatus::Pending,
            fiat_code: "USD".to_string(),
            fiat_amount: Some(100.0),
            fiat_amount_min: None,
            fiat_amount_max: None,
            payment_method: "Bank".to_string(),
            premium: 0.0,
            is_mine: false,
            created_at: 0,
            expires_at: None,
            amount_sats: None,
            creator_pubkey: String::new(),
            rating: 0.0,
            total_reviews: 0,
            days_active: 0,
        }
    }

    /// Trade key indices standing in for the take that got canceled and the
    /// retake that reused its order id.
    const TAKE: u32 = 0;
    const RETAKE: u32 = 7;

    async fn manager_with_session(order_id: &str) -> SessionManager {
        let mgr = SessionManager::new();
        mgr.create_session(
            order_id.to_string(),
            TradeRole::Buyer,
            TAKE,
            dummy_order_info(order_id),
        )
        .await
        .expect("create_session");
        mgr
    }

    #[test]
    fn dispute_and_admin_states_keep_the_session() {
        for status in [
            OrderStatus::Dispute,
            OrderStatus::CanceledByAdmin,
            OrderStatus::SettledByAdmin,
            OrderStatus::CompletedByAdmin,
        ] {
            assert_eq!(cancel_cleanup(Some(&status)), CancelCleanup::Keep);
        }
    }

    #[test]
    fn a_pending_cancel_returns_the_bond_and_drops_the_session() {
        assert_eq!(
            cancel_cleanup(Some(&OrderStatus::Pending)),
            CancelCleanup::Immediate
        );
    }

    #[test]
    fn committed_and_unknown_states_defer() {
        for status in [
            Some(OrderStatus::WaitingBuyerInvoice),
            Some(OrderStatus::WaitingPayment),
            Some(OrderStatus::Active),
            Some(OrderStatus::FiatSent),
            Some(OrderStatus::InProgress),
            None,
        ] {
            assert_eq!(cancel_cleanup(status.as_ref()), CancelCleanup::Defer);
        }
    }

    #[tokio::test]
    async fn a_deferred_session_survives_until_its_deadline() {
        let order_id = "order-deferred";
        let mgr = manager_with_session(order_id).await;

        mgr.defer_removal(order_id, TAKE, BOND_SLASH_GRACE_SECS).await;
        mgr.reconcile_deferred_removals().await;

        assert!(
            mgr.get_session(order_id).await.is_some(),
            "the session must outlive the cancel so a trailing bond-slashed can be decrypted"
        );
    }

    #[tokio::test]
    async fn a_deferred_session_is_dropped_once_the_deadline_passes() {
        let order_id = "order-expired";
        let mgr = manager_with_session(order_id).await;

        mgr.defer_removal(order_id, TAKE, 0).await;
        mgr.reconcile_deferred_removals().await;

        assert!(mgr.get_session(order_id).await.is_none());
    }

    #[tokio::test]
    async fn resolving_a_deferral_drops_the_session_immediately() {
        let order_id = "order-slashed";
        let mgr = manager_with_session(order_id).await;

        mgr.defer_removal(order_id, TAKE, BOND_SLASH_GRACE_SECS).await;

        assert!(mgr.resolve_deferred_removal(order_id, TAKE).await);
        assert!(mgr.get_session(order_id).await.is_none());
    }

    #[tokio::test]
    async fn resolving_without_a_deferral_leaves_the_session_alone() {
        let order_id = "order-live";
        let mgr = manager_with_session(order_id).await;

        assert!(!mgr.resolve_deferred_removal(order_id, TAKE).await);
        assert!(
            mgr.get_session(order_id).await.is_some(),
            "a live trade must not lose its session to an unrelated bond-slashed"
        );
    }

    async fn retake(mgr: &SessionManager, order_id: &str) -> Result<Session> {
        mgr.create_session(
            order_id.to_string(),
            TradeRole::Seller,
            RETAKE,
            dummy_order_info(order_id),
        )
        .await
    }

    /// Retaking the same order inside the grace window must not lose the fresh
    /// session to the canceled take's timer.
    #[tokio::test]
    async fn a_retake_supersedes_the_deferred_session() {
        let order_id = "order-retaken";
        let mgr = manager_with_session(order_id).await;

        mgr.defer_removal(order_id, TAKE, BOND_SLASH_GRACE_SECS).await;
        retake(&mgr, order_id).await.expect("retake");

        mgr.reconcile_deferred_removals().await;

        let session = mgr.get_session(order_id).await.expect("session kept");
        assert_eq!(session.trade_key_index, RETAKE);
    }

    /// A retake landing on an already-elapsed deadline — the window a separate
    /// deferral and session lock left open — still ends up with a live session.
    #[tokio::test]
    async fn a_retake_at_the_deadline_keeps_its_session() {
        let order_id = "order-retaken-late";
        let mgr = manager_with_session(order_id).await;

        mgr.defer_removal(order_id, TAKE, 0).await;
        retake(&mgr, order_id).await.expect("retake");

        mgr.reconcile_deferred_removals().await;

        let session = mgr.get_session(order_id).await.expect("session kept");
        assert_eq!(session.trade_key_index, RETAKE);
    }

    /// A live session is not a stale deferral: the duplicate guard still holds.
    #[tokio::test]
    async fn a_retake_over_a_live_session_is_still_refused() {
        let order_id = "order-live-take";
        let mgr = manager_with_session(order_id).await;

        let err = retake(&mgr, order_id).await.expect_err("duplicate take");

        assert!(err.to_string().contains("SessionAlreadyExists"));
    }

    /// What `create_session` refuses above, an accepted take must not: the
    /// daemon confirmed it, so it takes the order id over whatever it finds.
    #[tokio::test]
    async fn an_accepted_take_installs_its_session_over_a_live_one() {
        let order_id = "order-installed";
        let mgr = manager_with_session(order_id).await;

        mgr.install_session(
            order_id.to_string(),
            TradeRole::Seller,
            RETAKE,
            dummy_order_info(order_id),
        )
        .await
        .expect("install");

        let session = mgr.get_session(order_id).await.expect("session installed");
        assert_eq!(session.trade_key_index, RETAKE);
    }

    #[tokio::test]
    async fn an_installed_session_does_not_inherit_a_pending_deferral() {
        let order_id = "order-installed-deferred";
        let mgr = manager_with_session(order_id).await;

        mgr.defer_removal(order_id, TAKE, 0).await;
        mgr.install_session(
            order_id.to_string(),
            TradeRole::Seller,
            RETAKE,
            dummy_order_info(order_id),
        )
        .await
        .expect("install");

        mgr.reconcile_deferred_removals().await;

        assert!(mgr.get_session(order_id).await.is_some());
    }

    #[tokio::test]
    async fn removing_a_session_clears_its_pending_deferral() {
        let order_id = "order-removed";
        let mgr = manager_with_session(order_id).await;

        mgr.defer_removal(order_id, TAKE, BOND_SLASH_GRACE_SECS).await;
        mgr.remove_session(order_id).await;

        assert!(!mgr.resolve_deferred_removal(order_id, TAKE).await);
    }

    // ── Generation binding ────────────────────────────────────────────────────

    #[tokio::test]
    async fn only_the_live_trade_key_is_the_current_generation() {
        let order_id = "order-generation";
        let mgr = manager_with_session(order_id).await;

        assert!(mgr.is_current_generation(order_id, TAKE).await);
        assert!(!mgr.is_current_generation(order_id, RETAKE).await);
        assert!(
            mgr.is_current_generation("order-never-taken", TAKE).await,
            "an order we never took has no generation to contradict"
        );
    }

    /// The full delayed-delivery sequence: the old take's `canceled` and its
    /// trailing `bond-slashed` both land after the retake replaced the session.
    #[tokio::test]
    async fn a_delayed_cancel_from_the_old_key_spares_the_retaken_session() {
        let order_id = "order-superseded";
        let mgr = manager_with_session(order_id).await;

        mgr.defer_removal(order_id, TAKE, BOND_SLASH_GRACE_SECS).await;
        retake(&mgr, order_id).await.expect("retake");

        // Delayed `canceled` from the old trade key: the dispatcher's gate
        // rejects it before it can arm a deferral against the new session.
        assert!(!mgr.is_current_generation(order_id, TAKE).await);
        // Even if one were armed, neither the trailing notice nor the timer
        // may claim a session of another generation.
        mgr.defer_removal(order_id, TAKE, 0).await;
        mgr.resolve_deferred_removal(order_id, TAKE).await;
        mgr.reconcile_deferred_removals().await;

        let session = mgr.get_session(order_id).await.expect("retake survives");
        assert_eq!(session.trade_key_index, RETAKE);
    }

    #[tokio::test]
    async fn an_immediate_removal_spares_a_session_of_another_generation() {
        let order_id = "order-immediate";
        let mgr = manager_with_session(order_id).await;

        mgr.remove_session_if_current(order_id, RETAKE).await;
        assert!(mgr.get_session(order_id).await.is_some());

        mgr.remove_session_if_current(order_id, TAKE).await;
        assert!(mgr.get_session(order_id).await.is_none());
    }
}
