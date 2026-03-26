/// Deterministic pseudonym generation (FR-052 / FR-053).
///
/// `deterministic_nym(pubkey_hex)` derives a stable (adjective, noun, icon, hue)
/// tuple from any Nostr public key using SHA-256.  Same key → same output,
/// always, across sessions and devices.
///
/// Icon contract (FR-011c): icons MUST render white on the HSV-hued background.
use sha2::{Digest, Sha256};

// 50 adjectives (word indices 0-49, derived from hash bytes 0-1)
static ADJECTIVES: &[&str] = &[
    "Ancient", "Bold", "Brave", "Bright", "Calm",
    "Dark", "Deep", "Deft", "Distant", "Eager",
    "Early", "Fast", "Fierce", "Free", "Grim",
    "Hardy", "Hidden", "Hollow", "Iron", "Keen",
    "Late", "Light", "Lone", "Mighty", "Nimble",
    "Noble", "North", "Pale", "Quick", "Quiet",
    "Rapid", "Red", "Remote", "Rough", "Sharp",
    "Silent", "Slim", "Slow", "Sly", "Small",
    "South", "Steel", "Still", "Storm", "Strong",
    "Swift", "True", "Vast", "Wild", "Wise",
];

// 37 nouns — index maps 1:1 to icon_index (0-36)
static NOUNS: &[&str] = &[
    "Badger", "Bear", "Beaver", "Bobcat", "Boar",
    "Buffalo", "Bull", "Cat", "Coyote", "Crane",
    "Deer", "Eagle", "Elk", "Falcon", "Fox",
    "Hawk", "Heron", "Horse", "Jaguar", "Lemur",
    "Lion", "Lynx", "Mink", "Moose", "Otter",
    "Owl", "Panther", "Puma", "Rabbit", "Raccoon",
    "Raven", "Shark", "Squirrel", "Tiger", "Viper",
    "Wolf", "Wolverine",
];

/// Derive (pseudonym, icon_index, color_hue) from a hex-encoded Nostr public key.
///
/// - `pseudonym`  : "Adjective Noun", e.g. "Swift Falcon"
/// - `icon_index` : 0–36 (maps to the 37-entry icon sprite sheet)
/// - `color_hue`  : 0–359 (HSV hue for avatar background)
pub fn deterministic_nym(pubkey_hex: &str) -> (String, u8, u16) {
    let hash = Sha256::digest(pubkey_hex.as_bytes());

    // Adjective: bytes 0-1 as big-endian u16 mod 50
    let adj_seed = u16::from_be_bytes([hash[0], hash[1]]) as usize;
    let adj = ADJECTIVES[adj_seed % ADJECTIVES.len()];

    // Noun / icon: byte 2 mod 37
    let noun_idx = (hash[2] as usize) % NOUNS.len();
    let noun = NOUNS[noun_idx];

    // Hue: bytes 3-4 as big-endian u16 mod 360
    let hue_seed = u16::from_be_bytes([hash[3], hash[4]]);
    let color_hue = hue_seed % 360;

    let pseudonym = format!("{} {}", adj, noun);
    (pseudonym, noun_idx as u8, color_hue)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn same_pubkey_same_result() {
        let pk = "0101010101010101010101010101010101010101010101010101010101010101";
        let (p1, i1, h1) = deterministic_nym(pk);
        let (p2, i2, h2) = deterministic_nym(pk);
        assert_eq!(p1, p2);
        assert_eq!(i1, i2);
        assert_eq!(h1, h2);
    }

    #[test]
    fn icon_index_in_range() {
        let pk = "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890";
        let (_, icon, hue) = deterministic_nym(pk);
        assert!(icon <= 36, "icon_index out of range: {}", icon);
        assert!(hue < 360, "color_hue out of range: {}", hue);
    }
}
