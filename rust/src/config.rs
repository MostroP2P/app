/// Default configuration constants for the Mostro network.
///
/// These are compiled into the app and used on first launch when no
/// user-configured relays or Mostro node exist in the database.

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
