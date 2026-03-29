/// Shared types exposed to Flutter via flutter_rust_bridge.
/// These are the data structures that cross the Rust/Dart boundary.

// ── Enums ────────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum OrderKind {
    Buy,
    Sell,
}

/// Protocol-level order states.
///
/// `PaymentFailed` is NOT a status — it is an Action notification sent when
/// the Lightning payment to the buyer fails. The order remains in
/// `SettledHoldInvoice` when that notification arrives.
///
/// `CooperativelyCanceled` is a **client-side UI state only** — the protocol
/// does not change the order status for cooperative cancellations.
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum OrderStatus {
    Pending,
    WaitingBuyerInvoice,
    WaitingPayment,
    Active,
    FiatSent,
    SettledHoldInvoice,
    Success,
    Canceled,
    Expired,
    /// Client-side UI state only — not a protocol status change.
    CooperativelyCanceled,
    CanceledByAdmin,
    SettledByAdmin,
    CompletedByAdmin,
    Dispute,
    InProgress,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum TradeRole {
    Buyer,
    Seller,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum BuyerStep {
    OrderTaken,
    PayInvoice,
    PaymentLocked,
    FiatSent,
    AwaitingRelease,
    Complete,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum SellerStep {
    OrderPublished,
    TakerFound,
    InvoiceCreated,
    PaymentLocked,
    AwaitingFiat,
    Complete,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum TradeStep {
    Buyer(BuyerStep),
    Seller(SellerStep),
    Disputed,
}

/// Final trade outcomes.
///
/// `PaymentFailed` is intentionally absent — LN payment failures are transient
/// and retried; they are not a terminal trade outcome. The order stays in
/// `SettledHoldInvoice` while retries are in flight.
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum TradeOutcome {
    Success,
    Canceled,
    Expired,
    DisputeWon,
    DisputeLost,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum MessageType {
    Peer,
    Admin,
    System,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum DisputeStatus {
    Open,
    InReview,
    Resolved,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum DisputeResolution {
    FundsToMe,
    FundsToCounterparty,
    CooperativeCancel,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum RelayStatus {
    Connected,
    Disconnected,
    Connecting,
    Error,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum ConnectionState {
    Online,
    Offline,
    Reconnecting,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum QueuedMessageStatus {
    Pending,
    Sent,
    Failed,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum CooperativeCancelState {
    RequestedByMe,
    RequestedByPeer,
    Accepted,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum FileType {
    Image,
    Document,
    Video,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum DownloadStatus {
    Pending,
    Downloading,
    Downloaded,
    Failed,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum WalletStatus {
    Connected,
    Disconnected,
    Connecting,
    Error,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum ThemeMode {
    System,
    Dark,
    Light,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum LogLevel {
    Debug,
    Info,
    Warning,
    Error,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum RelaySource {
    Default,
    MostroDiscovered,
    UserAdded,
}

// ── Structs ───────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct OrderInfo {
    pub id: String,
    pub kind: OrderKind,
    pub status: OrderStatus,
    pub amount_sats: Option<u64>,
    pub fiat_amount: Option<f64>,
    pub fiat_amount_min: Option<f64>,
    pub fiat_amount_max: Option<f64>,
    pub fiat_code: String,
    pub payment_method: String,
    pub premium: f64,
    pub creator_pubkey: String,
    /// Unix timestamp (seconds).
    pub created_at: i64,
    pub expires_at: Option<i64>,
    pub is_mine: bool,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct TradeInfo {
    pub id: String,
    pub order: OrderInfo,
    pub role: TradeRole,
    pub counterparty_pubkey: String,
    pub current_step: TradeStep,
    pub hold_invoice: Option<String>,
    pub buyer_invoice: Option<String>,
    pub trade_key_index: u32,
    pub cooperative_cancel_state: Option<CooperativeCancelState>,
    pub timeout_at: Option<i64>,
    pub started_at: i64,
    pub completed_at: Option<i64>,
    pub outcome: Option<TradeOutcome>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct AttachmentInfo {
    pub file_name: String,
    pub mime_type: String,
    pub file_size: u64,
    pub file_type: FileType,
    pub download_status: DownloadStatus,
    pub local_path: Option<String>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ChatMessage {
    pub id: String,
    pub trade_id: String,
    pub sender_pubkey: String,
    pub content: String,
    pub message_type: MessageType,
    pub is_mine: bool,
    pub is_read: bool,
    pub has_attachment: bool,
    pub attachment: Option<AttachmentInfo>,
    pub created_at: i64,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct RelayInfo {
    pub url: String,
    pub is_active: bool,
    pub is_default: bool,
    pub source: RelaySource,
    pub is_blacklisted: bool,
    pub status: RelayStatus,
    pub last_connected_at: Option<i64>,
    pub last_error: Option<String>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct TradeHistoryEntry {
    pub id: String,
    pub order_kind: OrderKind,
    pub fiat_amount: Option<f64>,
    pub fiat_amount_min: Option<f64>,
    pub fiat_amount_max: Option<f64>,
    pub fiat_code: String,
    pub amount_sats: Option<u64>,
    pub payment_method: String,
    pub counterparty_pubkey: String,
    pub outcome: TradeOutcome,
    pub completed_at: i64,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct IdentityInfo {
    pub public_key: String,
    pub display_name: Option<String>,
    /// Authoritative privacy mode flag. The Settings `privacy_mode` is a
    /// read-only mirror of this value.
    pub privacy_mode: bool,
    pub trade_key_index: u32,
    pub created_at: i64,
}

/// Deterministic pseudonymous identity derived from a public key.
///
/// **Rendering contract**: The icon MUST always be rendered in white
/// (`Colors.white`) over the HSV-colored background circle. The v1
/// implementation had a bug where the icon color matched the background,
/// making it invisible. v2 MUST always use white icon color regardless of
/// `color_hue` (FR-011c).
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct NymIdentity {
    /// Deterministic pseudonym in adjective-noun format.
    pub pseudonym: String,
    /// Icon selector (0–36).
    pub icon_index: u8,
    /// HSV hue (0–359) for the avatar background circle.
    pub color_hue: u16,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct LogEntry {
    pub id: u32,
    pub level: LogLevel,
    pub tag: String,
    pub message: String,
    pub timestamp: i64,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct AppState {
    pub connection: ConnectionState,
    pub has_identity: bool,
    pub has_active_trade: bool,
    pub has_nwc_wallet: bool,
    pub unread_messages: u32,
    pub pending_queue_count: u32,
    pub theme: ThemeMode,
    /// Read-only mirror of `IdentityInfo.privacy_mode`.
    pub privacy_mode: bool,
    pub logging_enabled: bool,
}

/// Mostro daemon node information.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct MostroNodeInfo {
    pub pubkey: String,
    pub name: Option<String>,
    pub version: Option<String>,
    /// Pending order lifetime in hours. Defaults to 24 if omitted by daemon.
    #[serde(default = "default_expiration_hours")]
    pub expiration_hours: u32,
    /// Waiting-state timeout in seconds. Defaults to 900 if omitted by daemon.
    #[serde(default = "default_expiration_seconds")]
    pub expiration_seconds: u32,
    pub fee_pct: Option<f64>,
    pub max_order_amount: Option<u64>,
    pub min_order_amount: Option<u64>,
    pub supported_currencies: Option<Vec<String>>,
    pub ln_node_id: Option<String>,
    pub ln_node_alias: Option<String>,
    pub is_active: bool,
}

fn default_expiration_hours() -> u32 {
    24
}

fn default_expiration_seconds() -> u32 {
    900
}
