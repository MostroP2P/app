pub mod app_db;
pub mod schema;
pub mod seeds;
#[cfg(not(target_arch = "wasm32"))]
pub mod sqlite;
#[cfg(target_arch = "wasm32")]
pub mod indexeddb;

use anyhow::Result;

/// Keys used in the generic key-value settings store.
///
/// Collected here so the namespace is greppable in one place: the store has no
/// schema, so a typo in a key string is a silently-lost preference rather than
/// a compile error.
pub mod settings_keys {
    /// Active Mostro node pubkey (hex). Written through the dedicated
    /// [`super::Storage::save_active_mostro_pubkey`] accessor.
    pub const ACTIVE_MOSTRO_PUBKEY: &str = "active_mostro_pubkey";

    /// User-added Mostro nodes, JSON array of `crate::api::nodes::CustomNode`.
    /// The trusted registry is compiled in (`crate::config::TRUSTED_MOSTRO_NODES`);
    /// only user additions are persisted.
    pub const CUSTOM_MOSTRO_NODES: &str = "custom_mostro_nodes";

    /// Cached kind 0 display metadata for known Mostro nodes, JSON map of
    /// pubkey (hex) → `crate::api::nodes::NodeMetadata`. Refreshed opportunistically
    /// by `refresh_mostro_node_metadata`; stale entries are acceptable.
    pub const MOSTRO_NODE_METADATA: &str = "mostro_node_metadata";

    /// Developer escrow-mode override — `"auto"` or `"force_cashu"`.
    /// See [`crate::mostro::escrow_mode::EscrowModeOverride`].
    pub const ESCROW_MODE_OVERRIDE: &str = "escrow_mode_override";

    /// Developer mint-URL override, pointing Cashu at a local mint instead of
    /// the one the node advertises.
    pub const CASHU_MINT_URL_OVERRIDE: &str = "cashu_mint_url_override";

    /// Per-order chat `since` cursor — the `created_at` (unix seconds, decimal
    /// string) of the newest accepted outer chat event, clamped to the local
    /// clock. Full key is `chat_cursor:<order_id>`; build it with
    /// [`chat_cursor`]. Bounds the chat subscription backlog so a flood is
    /// never re-downloaded on restart (protocol chat spec, issue #246).
    pub const CHAT_CURSOR_PREFIX: &str = "chat_cursor:";

    /// Build the settings key holding the chat `since` cursor for `order_id`.
    pub fn chat_cursor(order_id: &str) -> String {
        format!("{CHAT_CURSOR_PREFIX}{order_id}")
    }

    /// Per-order solver pubkey (hex) for the dispute chat.
    pub const DISPUTE_ADMIN_PREFIX: &str = "dispute_admin:";

    /// Build the settings key holding the dispute solver's pubkey for
    /// `order_id`.
    ///
    /// The dispute record itself stays in memory by design — status and
    /// resolution are re-derivable from daemon events. This pubkey is not: it
    /// arrives exactly once, in `admin-took-dispute`, and without it the
    /// dispute chat keys cannot be derived again after a restart.
    pub fn dispute_admin(order_id: &str) -> String {
        format!("{DISPUTE_ADMIN_PREFIX}{order_id}")
    }

    /// Per-order marker that *this* side opened the dispute.
    pub const DISPUTE_MINE_PREFIX: &str = "dispute_mine:";

    /// Build the settings key marking the dispute on `order_id` as opened by
    /// this side. Like the solver pubkey, the origin is not re-derivable from
    /// daemon events after a restart (PR #256 review), so it is persisted
    /// alongside and read back by rehydration. Presence is the value.
    pub fn dispute_mine(order_id: &str) -> String {
        format!("{DISPUTE_MINE_PREFIX}{order_id}")
    }
}

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

    /// `true` if a message with this id was already accepted and stored.
    ///
    /// This is the **durable inner-event-id dedup** required by the chat spec:
    /// both parties hold `K_sign`, so either can re-wrap a previously received
    /// inner event inside a fresh outer one ("I sent the fiat", replayed). An
    /// in-memory LRU is not enough — an evicted entry makes the message
    /// replayable again — so the check must reach persisted history.
    async fn message_exists(&self, id: &str) -> Result<bool>;

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

    /// Read a value from the generic key-value settings store, or `None` when
    /// the key was never written.
    ///
    /// The store is for small, self-contained preferences — anything with
    /// structure gets its own table. See [`settings_keys`] for the keys in use.
    async fn get_setting(&self, key: &str) -> Result<Option<String>>;

    /// Write a value to the generic key-value settings store, replacing any
    /// previous value for `key`.
    async fn set_setting(&self, key: &str, value: &str) -> Result<()>;

    /// Remove a key from the generic settings store. Absent keys are not an
    /// error — clearing an unset preference is a no-op by design.
    async fn delete_setting(&self, key: &str) -> Result<()>;

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

    /// Delete a persisted trade by the order ID it is associated with.
    ///
    /// Chat messages are keyed separately (`messages.trade_id` holds the
    /// order id, no FK) and are deliberately NOT touched here. No-op when
    /// no matching trade exists.
    async fn delete_trade_by_order_id(&self, order_id: &str) -> Result<()>;

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

    /// Persist the counterparty (taker) reputation snapshot on a trade
    /// identified by `order.id` (issue #305). No-op when no matching trade
    /// exists. `days` saturates at `u32::MAX`; a full-privacy taker sends no
    /// snapshot, so this is only called when one was carried.
    async fn update_trade_peer_reputation(
        &self,
        order_id: &str,
        rating: f64,
        reviews: u32,
        days: u32,
    ) -> Result<()>;

    /// Set the durable "local user rated this trade" marker (`rated_at`, unix
    /// seconds) on the trade identified by `order.id` (issue #339). Written
    /// after `submit_rating` publishes so the rated state and the
    /// duplicate-rating guard survive a restart. No-op when no matching trade
    /// exists.
    async fn mark_trade_rated(&self, order_id: &str, rated_at: i64) -> Result<()>;
}
