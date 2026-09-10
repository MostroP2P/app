//! Default configuration constants for the Mostro network.
//!
//! These are compiled into the app and used on first launch when no
//! user-configured relays or Mostro node exist in the database.

use std::sync::RwLock;

/// Default relay URLs seeded on first launch.
///
/// These are the four relays the default Mostro node lists in its kind 10002
/// relay list (and in the `source` tag of its Kind 38383 events). Public
/// relays rate-limit and cap replays differently — `relay.mostro.network`
/// stops at 300 events, `nos.lol` at 500 — so covering the node's whole set
/// keeps the book reachable when one of them is throttling us.
pub const DEFAULT_RELAYS: &[&str] = &[
    "wss://relay.mostro.network",
    "wss://nos.lol",
    "wss://mostro-p2p.tech",
    "wss://relay.shadowbip.com",
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

static ORDER_EXPIRY_OVERRIDE: RwLock<Option<u64>> = RwLock::new(None);

/// Seconds after creation a new order asks the daemon to expire it, when
/// the Mortsom test environment set one. `None` leaves the expiry to the
/// daemon's own default, as every production build does.
pub fn order_expiry_override() -> Option<u64> {
    *ORDER_EXPIRY_OVERRIDE.read().unwrap()
}

/// Set (or clear) the order expiry the test environment asks for.
pub fn set_order_expiry_override(secs: Option<u64>) {
    *ORDER_EXPIRY_OVERRIDE.write().unwrap() = secs;
}

/// Set (or clear) the active Mostro pubkey override.
///
/// Any daemon responses still in flight from a previously active
/// daemon will be rejected by `dispatch_mostro_message` once this changes
/// — callers that care about clean handoff should quiesce pending trades
/// before swapping the override.
pub fn set_active_mostro_pubkey(pubkey: Option<String>) {
    *ACTIVE_MOSTRO_PUBKEY.write().unwrap() = pubkey;
}
