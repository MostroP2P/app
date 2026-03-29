/// Deterministic pseudonym identity derived from a Nostr public key.
///
/// The same public key always yields the same `NymIdentity` regardless of
/// device or session. Derivation uses SHA-256 of the 32-byte x-only pubkey:
///
///   hash  = SHA-256(pubkey_bytes)
///   adjective_idx = hash[0] % 64
///   noun_idx      = hash[1] % 64
///   icon_index    = (hash[2] as u16 * 256 + hash[3] as u16) % 37  → 0..=36
///   color_hue     = (hash[4] as u16 * 256 + hash[5] as u16) % 360 → 0..=359
///
/// **Rendering contract (Flutter)**: The icon MUST always be white on the
/// HSV-coloured background circle — see `NymIdentity` doc in types.rs (FR-011c).
use anyhow::{anyhow, Result};
use nostr_sdk::prelude::PublicKey;
use sha2::{Digest, Sha256};

use crate::api::types::NymIdentity;

/// Adjective pool (64 entries, index 0–63).
const ADJECTIVES: [&str; 64] = [
    "amber",  "bold",   "calm",   "dark",   "eager",  "fast",   "gold",   "high",
    "icy",    "just",   "keen",   "lazy",   "mild",   "neat",   "old",    "pale",
    "quick",  "red",    "safe",   "tall",   "urban",  "vast",   "warm",   "young",
    "azure",  "brave",  "cool",   "deep",   "empty",  "free",   "gray",   "hard",
    "iron",   "jade",   "kind",   "lost",   "moon",   "new",    "open",   "pink",
    "quiet",  "rare",   "soft",   "tiny",   "used",   "vivid",  "wide",   "exact",
    "yellow", "zero",   "alien",  "black",  "crisp",  "dusty",  "early",  "fresh",
    "grave",  "heavy",  "ideal",  "jolly",  "knit",   "lean",   "magic",  "noble",
];

/// Noun pool (64 entries, index 0–63).
const NOUNS: [&str; 64] = [
    "ant",    "bird",   "cat",    "deer",   "elk",    "fox",    "goat",   "hawk",
    "ibis",   "jay",    "kite",   "lynx",   "moth",   "newt",   "owl",    "pike",
    "quail",  "raven",  "seal",   "tiger",  "urial",  "vole",   "wolf",   "yak",
    "bear",   "crab",   "duck",   "eagle",  "frog",   "gnu",    "heron",  "impala",
    "jackal", "koala",  "lion",   "mink",   "orca",   "puma",   "quokka", "robin",
    "sloth",  "tapir",  "viper",  "walrus", "xerus",  "zorilla","bison",  "crane",
    "dingo",  "emu",    "ferret", "gecko",  "hippo",  "iguana", "jaguar", "koi",
    "lemur",  "marmot", "narwhal","ocelot", "panda",  "rabbit", "stoat",  "zebu",
];

/// Derive a deterministic `NymIdentity` from a hex-encoded Nostr public key.
pub fn get_nym_identity(pubkey_hex: &str) -> Result<NymIdentity> {
    let pubkey: PublicKey =
        PublicKey::parse(pubkey_hex).map_err(|e| anyhow!("invalid pubkey: {e}"))?;

    let bytes = pubkey.to_bytes(); // 32-byte x-only representation
    let hash: [u8; 32] = Sha256::digest(bytes).into();

    let adjective_idx = (hash[0] as usize) % ADJECTIVES.len();
    let noun_idx = (hash[1] as usize) % NOUNS.len();
    let icon_raw = u16::from_be_bytes([hash[2], hash[3]]);
    let color_raw = u16::from_be_bytes([hash[4], hash[5]]);

    let pseudonym = format!("{}-{}", ADJECTIVES[adjective_idx], NOUNS[noun_idx]);
    let icon_index = (icon_raw % 37) as u8;
    let color_hue = color_raw % 360;

    Ok(NymIdentity {
        pseudonym,
        icon_index,
        color_hue,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn same_pubkey_same_identity() {
        // Use a well-known test pubkey (all-zeros is invalid; use a real one)
        let keys = nostr_sdk::prelude::Keys::generate();
        let hex = keys.public_key().to_hex();

        let a = get_nym_identity(&hex).unwrap();
        let b = get_nym_identity(&hex).unwrap();
        assert_eq!(a.pseudonym, b.pseudonym);
        assert_eq!(a.icon_index, b.icon_index);
        assert_eq!(a.color_hue, b.color_hue);
    }

    #[test]
    fn icon_index_in_range() {
        let keys = nostr_sdk::prelude::Keys::generate();
        let nym = get_nym_identity(&keys.public_key().to_hex()).unwrap();
        assert!(nym.icon_index <= 36);
    }

    #[test]
    fn color_hue_in_range() {
        let keys = nostr_sdk::prelude::Keys::generate();
        let nym = get_nym_identity(&keys.public_key().to_hex()).unwrap();
        assert!(nym.color_hue <= 359);
    }
}
