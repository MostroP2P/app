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

    /// Delete the persisted identity row, so a subsequently created or
    /// imported identity starts with a fresh trade key counter.
    async fn delete_identity(&self) -> Result<()>;

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

    /// Reverse lookup: find the order ID associated with a given trade key index.
    async fn get_order_id_by_trade_index(&self, key_index: u32) -> Result<Option<String>>;

    /// Delete the trade key entry for `order_id`.
    async fn delete_trade_key(&self, order_id: &str) -> Result<()>;

    /// Delete ALL trade key entries. Used on identity deletion — the
    /// order→index mappings belong to the removed identity's derivation tree.
    async fn clear_trade_keys(&self) -> Result<()>;

    // ── Settings / Mostro node ────────────────────────────────────────────────

    /// Persist the active Mostro node's pubkey (hex). This is the *identity* of
    /// the selected node — node metadata (kind 0 / 38385) is a separate concern.
    async fn save_active_mostro_pubkey(&self, pubkey: &str) -> Result<()>;

    /// Return the persisted active Mostro node pubkey, or `None` if the user has
    /// not selected one (callers fall back to the compiled-in default).
    async fn get_active_mostro_pubkey(&self) -> Result<Option<String>>;

    /// Look up a persisted trade by the order ID it is associated with.
    async fn get_trade_by_order_id(
        &self,
        order_id: &str,
    ) -> Result<Option<crate::api::types::TradeInfo>>;

    /// Update the order ID inside a persisted trade (e.g. local UUID → daemon UUID).
    ///
    /// Loads the trade whose `order.id == old_order_id`, replaces `order.id`
    /// with `new_order_id`, and re-saves it. No-op when no matching trade exists.
    async fn update_trade_order_id(
        &self,
        old_order_id: &str,
        new_order_id: &str,
    ) -> Result<()>;

    /// Update fields on a persisted trade identified by `order.id`.
    ///
    /// Applies the provided mutations and re-saves. No-op when no matching
    /// trade exists.
    async fn update_trade_fields(
        &self,
        order_id: &str,
        status: Option<crate::api::types::OrderStatus>,
        hold_invoice: Option<String>,
        amount_sats: Option<u64>,
    ) -> Result<()>;
}
