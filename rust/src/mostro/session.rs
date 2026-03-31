/// Per-trade session state management.
///
/// Each active trade has a `Session` that tracks the order, role, keys,
/// and peer identity. Sessions are created when a trade is taken and
/// cleaned up on completion, cancellation, or timeout.
use anyhow::{anyhow, Result};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;

use crate::api::types::{OrderInfo, TradeRole};

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

/// In-memory session store.
pub struct SessionManager {
    sessions: Arc<RwLock<HashMap<String, Session>>>,
}

impl Default for SessionManager {
    fn default() -> Self { Self::new() }
}

impl SessionManager {
    pub fn new() -> Self {
        Self {
            sessions: Arc::new(RwLock::new(HashMap::new())),
        }
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
        if order_id != order.id {
            return Err(anyhow!(
                "order_id mismatch: param='{}' vs order.id='{}'",
                order_id,
                order.id
            ));
        }

        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs() as i64;

        let session = Session {
            order_id: order_id.clone(),
            role,
            trade_key_index,
            shared_key: None,
            admin_shared_key: None,
            peer_pubkey: None,
            order,
            created_at: now,
        };

        let mut sessions = self.sessions.write().await;
        if sessions.contains_key(&order_id) {
            return Err(anyhow!("SessionAlreadyExists: {}", order_id));
        }
        sessions.insert(order_id, session.clone());
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
        let mut sessions = self.sessions.write().await;
        if !sessions.contains_key(order_id) {
            return Err(anyhow!("SessionNotFound"));
        }
        sessions.insert(order_id.to_string(), session);
        Ok(())
    }

    /// Get a session by order ID.
    pub async fn get_session(&self, order_id: &str) -> Option<Session> {
        self.sessions.read().await.get(order_id).cloned()
    }

    /// Remove a session (on completion, cancellation, or timeout).
    pub async fn remove_session(&self, order_id: &str) {
        self.sessions.write().await.remove(order_id);
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
        let mut sessions = self.sessions.write().await;
        let session = sessions
            .get_mut(order_id)
            .ok_or_else(|| anyhow!("SessionNotFound: {order_id}"))?;
        session.admin_shared_key = Some(key);
        Ok(())
    }

    /// Remove sessions older than `timeout_secs` that have no shared key
    /// (i.e., the take action was never acknowledged by Mostro).
    pub async fn cleanup_stale_sessions(&self, timeout_secs: i64) {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs() as i64;

        let mut sessions = self.sessions.write().await;
        sessions.retain(|_, s| {
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
