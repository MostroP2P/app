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
#[derive(Debug, Clone)]
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

/// In-memory session store.
pub struct SessionManager {
    sessions: Arc<RwLock<HashMap<String, Session>>>,
}

impl SessionManager {
    pub fn new() -> Self {
        Self {
            sessions: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    /// Create a new session for a trade.
    pub async fn create_session(
        &self,
        order_id: String,
        role: TradeRole,
        trade_key_index: u32,
        order: OrderInfo,
    ) -> Result<Session> {
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

        self.sessions
            .write()
            .await
            .insert(order_id, session.clone());
        Ok(session)
    }

    /// Update an existing session.
    pub async fn update_session(&self, order_id: &str, session: Session) -> Result<()> {
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

    /// Remove sessions older than `timeout_secs` that have no shared key
    /// (i.e., the take action was never acknowledged by Mostro).
    pub async fn cleanup_stale_sessions(&self, timeout_secs: i64) {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs() as i64;

        let mut sessions = self.sessions.write().await;
        sessions.retain(|_, s| {
            // Keep sessions that have a shared key (acknowledged by Mostro)
            // or are younger than the timeout.
            s.shared_key.is_some() || (now - s.created_at) < timeout_secs
        });
    }
}

// ── Global singleton ────────────────────────────────────────────────────────

use tokio::sync::OnceCell;

static SESSION_MGR: OnceCell<SessionManager> = OnceCell::const_new();

/// Get the global session manager.
pub fn session_manager() -> &'static SessionManager {
    if SESSION_MGR.get().is_none() {
        let _ = SESSION_MGR.set(SessionManager::new());
    }
    SESSION_MGR.get().expect("SessionManager not initialized")
}
