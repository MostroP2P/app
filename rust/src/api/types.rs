/// Shared types exposed to Flutter via flutter_rust_bridge.
/// All enums and structs that cross the Rust/Dart boundary are defined here.

// ─── Enums ──────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum OrderKind {
    Buy,
    Sell,
}

/// 15 Mostro-protocol order statuses (from mostro-core).
/// NOTE: PaymentFailed is an Action, NOT a status.
/// NOTE: CooperativelyCanceled is client-side UI only.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
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
    CooperativelyCanceled,
    CanceledByAdmin,
    SettledByAdmin,
    CompletedByAdmin,
    Dispute,
    InProgress,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum TradeRole {
    Buyer,
    Seller,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum BuyerStep {
    OrderTaken,
    PayInvoice,
    PaymentLocked,
    FiatSent,
    AwaitingRelease,
    Complete,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum SellerStep {
    OrderPublished,
    TakerFound,
    InvoiceCreated,
    PaymentLocked,
    AwaitingFiat,
    Complete,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum TradeStep {
    Buyer(BuyerStep),
    Seller(SellerStep),
    Disputed,
}

/// Terminal trade outcomes. PaymentFailed is transient and retried — not a final outcome.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum TradeOutcome {
    Success,
    Canceled,
    Expired,
    DisputeWon,
    DisputeLost,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum MessageType {
    Peer,
    Admin,
    System,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum DisputeStatus {
    Open,
    InReview,
    Resolved,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum DisputeResolution {
    FundsToMe,
    FundsToCounterparty,
    CooperativeCancel,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum RelayStatus {
    Connected,
    Disconnected,
    Connecting,
    Error,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum ConnectionState {
    Online,
    Offline,
    Reconnecting,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum QueuedMessageStatus {
    Pending,
    Sent,
    Failed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum CooperativeCancelState {
    RequestedByMe,
    RequestedByPeer,
    Accepted,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum FileType {
    Image,
    Document,
    Video,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum DownloadStatus {
    Pending,
    Downloading,
    Downloaded,
    Failed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum WalletStatus {
    Connected,
    Disconnected,
    Connecting,
    Error,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum ThemeMode {
    System,
    Dark,
    Light,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum LogLevel {
    Debug,
    Info,
    Warning,
    Error,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum RelaySource {
    Default,
    MostroDiscovered,
    UserAdded,
}

// ─── Structs ─────────────────────────────────────────────────────────────────

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
pub struct AttachmentInfo {
    pub file_name: String,
    pub mime_type: String,
    pub file_size: u64,
    pub file_type: FileType,
    pub download_status: DownloadStatus,
    pub local_path: Option<String>,
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
    pub privacy_mode: bool,
    pub trade_key_index: u32,
    pub created_at: i64,
}

/// Deterministic pseudonym derived from a Nostr public key.
/// All fields are computed from the public key — same key → same result always.
///
/// Flutter rendering contract (FR-011c): icon MUST always render in white
/// (`Colors.white`) over the HSV-colored background. v1 had a bug where
/// the icon color matched the background, making it invisible.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct NymIdentity {
    /// Deterministic adjective-noun pseudonym, e.g. "swift-falcon"
    pub pseudonym: String,
    /// Icon selector 0–36
    pub icon_index: u8,
    /// HSV hue 0–359 for avatar background color
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
    pub privacy_mode: bool,
    pub logging_enabled: bool,
}
