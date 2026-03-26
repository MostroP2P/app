/// Storage abstraction layer.
///
/// Defines the async Storage trait implemented by:
///   - SqliteStorage   (native: iOS, Android, macOS, Windows, Linux)
///   - IndexedDbStorage (WASM: Web)
///
/// Feature-gated: #[cfg(not(target_arch = "wasm32"))] for sqlite,
///                #[cfg(target_arch = "wasm32")]       for indexeddb.
#[cfg(not(target_arch = "wasm32"))]
pub mod sqlite;
#[cfg(target_arch = "wasm32")]
pub mod indexeddb;


#[derive(Debug, thiserror::Error)]
pub enum StorageError {
    #[error("record not found")]
    NotFound,
    #[error("constraint violation: {0}")]
    Constraint(String),
    #[cfg(not(target_arch = "wasm32"))]
    #[error("sqlx: {0}")]
    Sqlx(#[from] sqlx::Error),
    #[error("serialization: {0}")]
    Serde(#[from] serde_json::Error),
    #[error("storage: {0}")]
    Other(String),
}

pub type StorageResult<T> = Result<T, StorageError>;

// ─── Identity ────────────────────────────────────────────────────────────────

pub struct IdentityRecord {
    pub id: String,
    pub public_key: String,
    pub encrypted_private_key: Vec<u8>,
    pub mnemonic_hash: String,
    pub display_name: Option<String>,
    pub created_at: i64,
    pub last_used_at: i64,
    pub trade_key_index: u32,
    pub privacy_mode: bool,
    pub derivation_path: String,
}

// ─── Order ───────────────────────────────────────────────────────────────────

pub struct OrderRecord {
    pub id: String,
    pub kind: String,
    pub status: String,
    pub amount_sats: Option<i64>,
    pub fiat_amount: Option<f64>,
    pub fiat_amount_min: Option<f64>,
    pub fiat_amount_max: Option<f64>,
    pub fiat_code: String,
    pub payment_method: String,
    pub premium: f64,
    pub creator_pubkey: String,
    pub created_at: i64,
    pub expires_at: Option<i64>,
    pub nostr_event_id: Option<String>,
    pub is_mine: bool,
    pub cached_at: i64,
}

// ─── Trade ───────────────────────────────────────────────────────────────────

pub struct TradeRecord {
    pub id: String,
    pub order_id: String,
    pub role: String,
    pub counterparty_pubkey: String,
    pub current_step: String,
    pub hold_invoice: Option<String>,
    pub buyer_invoice: Option<String>,
    pub trade_key_index: u32,
    pub cooperative_cancel_state: Option<String>,
    pub timeout_at: Option<i64>,
    pub started_at: i64,
    pub completed_at: Option<i64>,
    pub outcome: Option<String>,
}

// ─── Message ─────────────────────────────────────────────────────────────────

pub struct MessageRecord {
    pub id: String,
    pub trade_id: String,
    pub sender_pubkey: String,
    pub content_encrypted: Vec<u8>,
    pub message_type: String,
    pub is_mine: bool,
    pub is_read: bool,
    pub attachment_id: Option<String>,
    pub created_at: i64,
}

// ─── MessageQueue ─────────────────────────────────────────────────────────────

pub struct QueuedMessage {
    pub id: String,
    pub event_json: String,
    pub target_relays: String,
    pub status: String,
    pub attempts: i32,
    pub created_at: i64,
    pub last_attempt_at: Option<i64>,
}

// ─── Settings ─────────────────────────────────────────────────────────────────

pub struct SettingRecord {
    pub key: String,
    pub value: String,
}

// ─── NWC Wallet ───────────────────────────────────────────────────────────────

pub struct NwcWalletRecord {
    pub id: String,
    pub nwc_uri_encrypted: Vec<u8>,
    pub alias: Option<String>,
    pub relay_urls: String,
    pub wallet_pubkey: String,
    pub is_active: bool,
    pub created_at: i64,
}

// ─── File Attachment ──────────────────────────────────────────────────────────

pub struct FileAttachmentRecord {
    pub id: String,
    pub message_id: String,
    pub trade_id: String,
    pub file_name: String,
    pub mime_type: String,
    pub file_size: i64,
    pub blossom_url: Option<String>,
    pub local_path: Option<String>,
    pub download_status: String,
    pub upload_complete: bool,
    pub created_at: i64,
}

// ─── Rating ───────────────────────────────────────────────────────────────────

pub struct RatingRecord {
    pub id: String,
    pub trade_id: String,
    pub rater_pubkey: String,
    pub rated_pubkey: String,
    pub score: i32,
    pub created_at: i64,
}

// ─── Dispute ──────────────────────────────────────────────────────────────────

pub struct DisputeRecord {
    pub id: String,
    pub trade_id: String,
    pub order_id: String,
    pub raised_by_pubkey: String,
    pub status: String,
    pub resolution: Option<String>,
    pub admin_pubkey: Option<String>,
    pub evidence_urls: Option<String>,
    pub notes: Option<String>,
    pub created_at: i64,
    pub resolved_at: Option<i64>,
}

// ─── Relay ────────────────────────────────────────────────────────────────────

pub struct RelayRecord {
    pub id: String,
    pub url: String,
    pub is_active: bool,
    pub is_default: bool,
    pub source: String,
    pub is_blacklisted: bool,
    pub last_connected_at: Option<i64>,
    pub last_error: Option<String>,
}

// ─── Storage Trait ────────────────────────────────────────────────────────────

/// Async storage abstraction. Implemented for SQLite (native) and IndexedDB (WASM).
pub trait Storage: Send + Sync {
    // --- Identity ---
    fn save_identity(
        &self,
        record: IdentityRecord,
    ) -> impl std::future::Future<Output = StorageResult<()>> + Send;
    fn get_identity(
        &self,
    ) -> impl std::future::Future<Output = StorageResult<Option<IdentityRecord>>> + Send;
    fn update_trade_key_index(
        &self,
        index: u32,
    ) -> impl std::future::Future<Output = StorageResult<()>> + Send;
    fn delete_identity(&self) -> impl std::future::Future<Output = StorageResult<()>> + Send;

    // --- Orders ---
    fn upsert_order(
        &self,
        record: OrderRecord,
    ) -> impl std::future::Future<Output = StorageResult<()>> + Send;
    fn get_order(
        &self,
        id: &str,
    ) -> impl std::future::Future<Output = StorageResult<Option<OrderRecord>>> + Send;
    fn list_orders(
        &self,
        status: Option<&str>,
    ) -> impl std::future::Future<Output = StorageResult<Vec<OrderRecord>>> + Send;
    fn delete_order(
        &self,
        id: &str,
    ) -> impl std::future::Future<Output = StorageResult<()>> + Send;

    // --- Trades ---
    fn save_trade(
        &self,
        record: TradeRecord,
    ) -> impl std::future::Future<Output = StorageResult<()>> + Send;
    fn get_trade(
        &self,
        id: &str,
    ) -> impl std::future::Future<Output = StorageResult<Option<TradeRecord>>> + Send;
    fn get_active_trade(
        &self,
    ) -> impl std::future::Future<Output = StorageResult<Option<TradeRecord>>> + Send;
    fn update_trade(
        &self,
        record: TradeRecord,
    ) -> impl std::future::Future<Output = StorageResult<()>> + Send;

    // --- Messages ---
    fn save_message(
        &self,
        record: MessageRecord,
    ) -> impl std::future::Future<Output = StorageResult<()>> + Send;
    fn list_messages(
        &self,
        trade_id: &str,
    ) -> impl std::future::Future<Output = StorageResult<Vec<MessageRecord>>> + Send;
    fn mark_messages_read(
        &self,
        trade_id: &str,
    ) -> impl std::future::Future<Output = StorageResult<()>> + Send;
    fn get_unread_count(
        &self,
        trade_id: &str,
    ) -> impl std::future::Future<Output = StorageResult<u32>> + Send;

    // --- Settings ---
    fn set_setting(
        &self,
        key: &str,
        value: &str,
    ) -> impl std::future::Future<Output = StorageResult<()>> + Send;
    fn get_setting(
        &self,
        key: &str,
    ) -> impl std::future::Future<Output = StorageResult<Option<String>>> + Send;

    // --- Message Queue ---
    fn enqueue_message(
        &self,
        record: QueuedMessage,
    ) -> impl std::future::Future<Output = StorageResult<()>> + Send;
    fn list_pending_messages(
        &self,
    ) -> impl std::future::Future<Output = StorageResult<Vec<QueuedMessage>>> + Send;
    fn update_message_status(
        &self,
        id: &str,
        status: &str,
        attempts: i32,
    ) -> impl std::future::Future<Output = StorageResult<()>> + Send;
    fn prune_sent_messages(
        &self,
        older_than: i64,
    ) -> impl std::future::Future<Output = StorageResult<()>> + Send;

    // --- NWC Wallets ---
    fn save_wallet(
        &self,
        record: NwcWalletRecord,
    ) -> impl std::future::Future<Output = StorageResult<()>> + Send;
    fn get_active_wallet(
        &self,
    ) -> impl std::future::Future<Output = StorageResult<Option<NwcWalletRecord>>> + Send;
    fn delete_wallet(
        &self,
        id: &str,
    ) -> impl std::future::Future<Output = StorageResult<()>> + Send;

    // --- File Attachments ---
    fn save_attachment(
        &self,
        record: FileAttachmentRecord,
    ) -> impl std::future::Future<Output = StorageResult<()>> + Send;
    fn get_attachment(
        &self,
        id: &str,
    ) -> impl std::future::Future<Output = StorageResult<Option<FileAttachmentRecord>>> + Send;
    fn update_attachment_status(
        &self,
        id: &str,
        status: &str,
        local_path: Option<&str>,
    ) -> impl std::future::Future<Output = StorageResult<()>> + Send;

    // --- Ratings ---
    fn save_rating(
        &self,
        record: RatingRecord,
    ) -> impl std::future::Future<Output = StorageResult<()>> + Send;
    fn list_ratings_for_pubkey(
        &self,
        pubkey: &str,
    ) -> impl std::future::Future<Output = StorageResult<Vec<RatingRecord>>> + Send;

    // --- Disputes ---
    fn save_dispute(
        &self,
        record: DisputeRecord,
    ) -> impl std::future::Future<Output = StorageResult<()>> + Send;
    fn get_dispute(
        &self,
        id: &str,
    ) -> impl std::future::Future<Output = StorageResult<Option<DisputeRecord>>> + Send;
    fn update_dispute(
        &self,
        record: DisputeRecord,
    ) -> impl std::future::Future<Output = StorageResult<()>> + Send;

    // --- Relays ---
    fn upsert_relay(
        &self,
        record: RelayRecord,
    ) -> impl std::future::Future<Output = StorageResult<()>> + Send;
    fn list_relays(
        &self,
    ) -> impl std::future::Future<Output = StorageResult<Vec<RelayRecord>>> + Send;
    fn delete_relay(
        &self,
        url: &str,
    ) -> impl std::future::Future<Output = StorageResult<()>> + Send;
}
