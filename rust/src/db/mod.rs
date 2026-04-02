pub mod app_db;
pub mod schema;
pub mod seeds;
#[cfg(not(target_arch = "wasm32"))]
pub mod sqlite;
#[cfg(target_arch = "wasm32")]
pub mod indexeddb;

use anyhow::Result;

/// Storage trait — implemented by both SQLite (native) and IndexedDB (WASM).
///
/// **Send-safety note**: `#[allow(async_fn_in_trait)]` is used here instead of
/// the `async-trait` crate. The compiler does NOT automatically require the
/// returned futures to be `Send`. Callers that hold `Arc<dyn Storage>` across
/// `.await` points on a multi-threaded executor must ensure concrete
/// implementations return `Send` futures (both `SqliteStorage` and
/// `IndexedDbStorage` do, because `sqlx` and the underlying async runtimes
/// produce `Send` futures). If this trait is ever used with a non-`Send`
/// backend the bound should be relaxed or `#[async_trait]` adopted.
#[allow(async_fn_in_trait)]
pub trait Storage: Send + Sync {
    async fn save_order(&self, order: &crate::api::types::OrderInfo) -> Result<()>;
    async fn get_order(&self, id: &str) -> Result<Option<crate::api::types::OrderInfo>>;
    async fn delete_order(&self, id: &str) -> Result<()>;
    async fn list_orders(&self) -> Result<Vec<crate::api::types::OrderInfo>>;

    async fn save_trade(&self, trade: &crate::api::types::TradeInfo) -> Result<()>;
    async fn get_trade(&self, id: &str) -> Result<Option<crate::api::types::TradeInfo>>;
    async fn list_trades(&self) -> Result<Vec<crate::api::types::TradeInfo>>;

    async fn save_message(&self, msg: &crate::api::types::ChatMessage) -> Result<()>;
    async fn list_messages(&self, trade_id: &str) -> Result<Vec<crate::api::types::ChatMessage>>;
    async fn mark_messages_read(&self, trade_id: &str) -> Result<()>;

    async fn save_relay(&self, relay: &crate::api::types::RelayInfo) -> Result<()>;
    async fn delete_relay(&self, url: &str) -> Result<()>;
    async fn list_relays(&self) -> Result<Vec<crate::api::types::RelayInfo>>;

    async fn save_identity(&self, identity: &crate::api::types::IdentityInfo) -> Result<()>;
    async fn get_identity(&self) -> Result<Option<crate::api::types::IdentityInfo>>;

    async fn save_queued_message(
        &self,
        msg: &crate::queue::outbox::QueuedMessage,
    ) -> Result<()>;
    async fn list_queued_messages(
        &self,
    ) -> Result<Vec<crate::queue::outbox::QueuedMessage>>;
    async fn update_queued_message_status(
        &self,
        id: &str,
        status: crate::api::types::QueuedMessageStatus,
    ) -> Result<()>;
    async fn delete_queued_message(&self, id: &str) -> Result<()>;

    // ── Trade key index ──────────────────────────────────────────────────────

    /// Persist the BIP-32 key index used for `order_id`.
    async fn save_trade_key(&self, order_id: &str, key_index: u32) -> Result<()>;

    /// Retrieve the BIP-32 key index for `order_id`, or `None` if not found.
    async fn get_trade_key(&self, order_id: &str) -> Result<Option<u32>>;

    /// Look up a persisted trade by the order ID it is associated with.
    async fn get_trade_by_order_id(
        &self,
        order_id: &str,
    ) -> Result<Option<crate::api::types::TradeInfo>>;
}
