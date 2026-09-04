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

// ── Trusted node registry ────────────────────────────────────────────────────

/// Static configuration for a trusted Mostro community node.
///
/// Only the *identity* (pubkey) and region label are compiled in; display
/// metadata (name, picture, about) comes from the node's Nostr kind 0 event —
/// see `crate::api::nodes`.
pub struct TrustedNodeConfig {
    /// Node pubkey, 64-char lowercase hex.
    pub pubkey: &'static str,
    /// Region label: flag emoji + place name (a proper noun, not translated).
    pub region: &'static str,
}

/// Trusted Mostro communities mirrored from mostro.community.
///
/// **Keep in sync** with v1 (`mobile/lib/core/config/communities.dart`) when
/// the community list changes upstream.
pub const TRUSTED_MOSTRO_NODES: &[TrustedNodeConfig] = &[
    TrustedNodeConfig {
        pubkey: "00000235a3e904cfe1213a8a54d6f1ec1bef7cc6bfaabd6193e82931ccf1366a",
        region: "🇨🇺 Cuba",
    },
    TrustedNodeConfig {
        pubkey: "0000cc02101ec29eea9ce623258752b9d7da66c27845ed26846dd0b0fc736b40",
        region: "🇪🇸 España",
    },
    TrustedNodeConfig {
        pubkey: "00000978acc594c506976c655b6decbf2d4af25ffdaa6680f2a9568b0a88441b",
        region: "🇨🇴 Colombia",
    },
    TrustedNodeConfig {
        pubkey: "00007cb3305fb972f5cc83f83a8fbca1e64e93c9d1369880a9fd62ef95d23f91",
        region: "🇧🇴 Bolivia",
    },
    TrustedNodeConfig {
        pubkey: "000009ee1e4b1dc7add19ab30e4ef854d7b562e208b62686fd9002b50b24dabb",
        region: "🇻🇪 Venezuela",
    },
    TrustedNodeConfig {
        pubkey: "b3626fe91b602bdbca3673bec0855221f41dc8f6d0e4027e51eaa525d68d87f2",
        region: "🇦🇷 Argentina",
    },
    TrustedNodeConfig {
        pubkey: "00037abd44e7a846689e230d5446abcd0d56a344fa81fff85c09d1929feda486",
        region: "🇧🇷 Brasil",
    },
    TrustedNodeConfig {
        pubkey: DEFAULT_MOSTRO_PUBKEY,
        region: "🌐",
    },
];

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
/// Any daemon responses still in flight from a previously active
/// daemon will be rejected by `dispatch_mostro_message` once this changes
/// — callers that care about clean handoff should quiesce pending trades
/// before swapping the override.
pub fn set_active_mostro_pubkey(pubkey: Option<String>) {
    *ACTIVE_MOSTRO_PUBKEY.write().unwrap() = pubkey;
}
