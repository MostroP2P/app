/// Shared Mostro node defaults — mirrors rust/src/config.rs.
///
/// Update both this file and config.rs when the defaults change.
library;

/// Default Mostro daemon public key (64-char hex).
const defaultMostroPubkey =
    '82fa8cb978b43c79b2156585bac2c011176a21d2aead6d9f7c575c005be88390';

/// Default Nostr relay URLs used by the Mostro daemon.
const defaultMostroRelays = [
  'wss://relay.mostro.network',
  'wss://nos.lol',
];
