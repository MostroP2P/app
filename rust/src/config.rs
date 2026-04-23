//! Default configuration constants for the Mostro network.
//!
//! These are compiled into the app and used on first launch when no
//! user-configured relays or Mostro node exist in the database.

use std::sync::RwLock;

/// Default relay URLs seeded on first launch.
pub const DEFAULT_RELAYS: &[&str] = &[
    "wss://relay.mostro.network",
    "wss://nos.lol",
];

/// Default Mostro daemon public key (hex, 32 bytes).
pub const DEFAULT_MOSTRO_PUBKEY: &str =
    "82fa8cb978b43c79b2156585bac2c011176a21d2aead6d9f7c575c005be88390";

/// Default Mostro daemon display name.
pub const DEFAULT_MOSTRO_NAME: &str = "Mostro";

// ── Runtime pubkey override ──────────────────────────────────────────────────

static ACTIVE_MOSTRO_PUBKEY: RwLock<Option<String>> = RwLock::new(None);

/// Returns the active Mostro pubkey — either the user-selected override or
/// the compiled-in default.
pub fn active_mostro_pubkey() -> String {
    ACTIVE_MOSTRO_PUBKEY
        .read()
        .unwrap()
        .clone()
        .unwrap_or_else(|| DEFAULT_MOSTRO_PUBKEY.to_string())
}

/// Set (or clear) the active Mostro pubkey override.
///
/// Any gift-wrapped responses still in flight from a previously active
/// daemon will be rejected by `dispatch_mostro_message` once this changes
/// — callers that care about clean handoff should quiesce pending trades
/// before swapping the override.
pub fn set_active_mostro_pubkey(pubkey: Option<String>) {
    *ACTIVE_MOSTRO_PUBKEY.write().unwrap() = pubkey;
}
