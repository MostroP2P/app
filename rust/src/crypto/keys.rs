/// BIP-39/BIP-32 key derivation for Mostro identity and trade keys.
///
/// Derivation path: `m/44'/1237'/38383'/0/N`
///   - Purpose  44' = BIP-44
///   - Coin     1237' = Nostr
///   - Account  38383' = Mostro
///   - Change   0
///   - Index    N  (0 = identity key, ≥1 = per-trade keys)
///
/// **DO NOT change the derivation path** — it is a protocol constant shared
/// with Mostro daemon and other compliant clients.
use anyhow::{anyhow, Result};
use bip32::{DerivationPath, XPrv};
use bip39::Mnemonic;
use nostr_sdk::prelude::{Keys, SecretKey};
use zeroize::Zeroizing;

const DERIVATION_PREFIX: &str = "m/44'/1237'/38383'/0";

/// Generate a fresh 12-word BIP-39 mnemonic phrase.
pub fn generate_mnemonic() -> Result<Vec<String>> {
    let mnemonic = Mnemonic::generate(12).map_err(|e| anyhow!("mnemonic generation: {e}"))?;
    Ok(mnemonic.words().map(|w| w.to_string()).collect())
}

/// Derive the identity (`N=0`) Nostr `Keys` from a mnemonic.
///
/// **This is also the validation.** Deriving parses the phrase, so a word list
/// with a bad word or a bad checksum fails here with `invalid mnemonic: …`.
/// There is no separate validate-then-derive pair: two parses of the same
/// phrase is two places for "what counts as a valid mnemonic" to be answered.
pub fn derive_master_key(mnemonic_words: &[String]) -> Result<Keys> {
    derive_at_index(mnemonic_words, 0)
}

/// Derive a trade-specific Nostr `Keys` at the given BIP-32 child index.
/// `index` must be ≥ 1; index 0 is reserved for the identity key.
pub fn derive_trade_key(mnemonic_words: &[String], index: u32) -> Result<Keys> {
    if index == 0 {
        return Err(anyhow!("index 0 is reserved for the identity key; use derive_master_key"));
    }
    derive_at_index(mnemonic_words, index)
}

/// Derive the raw BIP-39 seed from a mnemonic — the one place in this file that
/// turns words into a seed.
///
/// It is what [`derive_at_index`] feeds into BIP-32, so identity keys, trade
/// keys and the Cashu wallet all descend from the same bytes with the same
/// empty passphrase (NIP-06). `cdk` derives its blinding secrets from a 64-byte
/// seed, which is what makes the ecash recoverable from the words the user
/// already backed up — one secret to protect, not two.
///
/// Returned in a [`Zeroizing`] wrapper so the copy is wiped when the caller
/// drops it: the seed is the whole account, and it crosses into a third-party
/// crate.
pub fn derive_bip39_seed(mnemonic_words: &[String]) -> Result<Zeroizing<[u8; 64]>> {
    let phrase = mnemonic_words.join(" ");
    let mnemonic = Mnemonic::parse(&phrase).map_err(|e| anyhow!("invalid mnemonic: {e}"))?;
    Ok(Zeroizing::new(mnemonic.to_seed("")))
}

// ── Internal ─────────────────────────────────────────────────────────────────

fn derive_at_index(mnemonic_words: &[String], index: u32) -> Result<Keys> {
    // The same seed the Cashu wallet is handed — derived here rather than
    // re-parsed, so there is one definition of "the seed of this mnemonic" and
    // this path gets the zeroizing wrapper too.
    let seed = derive_bip39_seed(mnemonic_words)?;

    let path_str = format!("{}/{}", DERIVATION_PREFIX, index);
    let path: DerivationPath = path_str
        .parse()
        .map_err(|e| anyhow!("derivation path parse: {e}"))?;

    let xprv = XPrv::derive_from_path(seed.as_slice(), &path)
        .map_err(|e| anyhow!("BIP-32 derive error: {e}"))?;

    // k256 signing key → raw 32-byte secret
    let raw: [u8; 32] = xprv.private_key().to_bytes().into();
    let secret = SecretKey::from_slice(&raw).map_err(|e| anyhow!("invalid secret key: {e}"))?;
    Ok(Keys::new(secret))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The canonical BIP-39 test mnemonic, valid checksum and all.
    fn abandon_mnemonic() -> Vec<String> {
        "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
            .split(' ')
            .map(str::to_string)
            .collect()
    }

    #[test]
    fn round_trip_mnemonic_generates_stable_keys() {
        let words = generate_mnemonic().unwrap();
        assert_eq!(words.len(), 12);

        let k1 = derive_master_key(&words).unwrap();
        let k2 = derive_master_key(&words).unwrap();
        assert_eq!(k1.public_key(), k2.public_key());
    }

    /// The import path relies on derivation to reject a bad phrase — it no
    /// longer validates separately first. If that ever stops being true, a
    /// typo'd word becomes some other user's key rather than an error.
    #[test]
    fn deriving_refuses_a_phrase_that_is_not_a_mnemonic() {
        // Arrange — real BIP-39 words, wrong checksum; then a word that is not
        // in the list at all. The dialog that feeds this only checks the shape
        // (12 or 24 alphabetic words), so both reach Rust.
        let bad_checksum: Vec<String> = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon"
            .split(' ')
            .map(str::to_string)
            .collect();
        let not_a_word: Vec<String> = "mostro abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
            .split(' ')
            .map(str::to_string)
            .collect();

        // Act / Assert
        for words in [&bad_checksum, &not_a_word] {
            let err = derive_master_key(words).unwrap_err();
            assert!(
                err.to_string().contains("invalid mnemonic"),
                "got {err}"
            );
            assert!(derive_trade_key(words, 1).is_err());
        }

        // And an empty list is not a mnemonic either — an nsec-imported
        // identity stores no words.
        assert!(derive_master_key(&[]).is_err());
    }

    #[test]
    fn trade_key_differs_from_identity_key() {
        let words = generate_mnemonic().unwrap();
        let identity = derive_master_key(&words).unwrap();
        let trade = derive_trade_key(&words, 1).unwrap();
        assert_ne!(identity.public_key(), trade.public_key());
    }

    /// The Cashu wallet seeds itself from this, so it is not enough that the
    /// derivation is stable — it has to be *the* BIP-39 seed, or the ecash is
    /// recoverable only by this app and the user's 12 words buy them nothing in
    /// any other wallet. The vector is the canonical all-`abandon` mnemonic
    /// with an empty passphrase.
    #[test]
    fn the_bip39_seed_matches_the_standard_vector() {
        // Arrange
        let words = abandon_mnemonic();

        // Act
        let seed = derive_bip39_seed(&words).unwrap();

        // Assert
        assert_eq!(
            hex::encode(*seed),
            "5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc19a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4"
        );
    }

    /// The derivation path is a protocol constant shared with the daemon, so
    /// what comes out of it is one too: if these change, every existing user's
    /// identity and trade keys change with them and their account is gone. The
    /// other tests here only check that the derivation agrees with itself,
    /// which a rewrite of this file would also do.
    #[test]
    fn the_derived_keys_are_pinned_to_their_path() {
        // Arrange
        let words = abandon_mnemonic();

        // Act / Assert — m/44'/1237'/38383'/0/{0,1} for the canonical mnemonic.
        assert_eq!(
            derive_master_key(&words).unwrap().public_key().to_hex(),
            "faa27ea81c85e00798598b46d1f36c1700221a1242b563861fa536dc2314f1df"
        );
        assert_eq!(
            derive_trade_key(&words, 1).unwrap().public_key().to_hex(),
            "f5afa0b09d50fc78d3b3836122b43105a018a30e5ab3eccb36480a525271f3f1"
        );
    }

    #[test]
    fn a_mnemonic_that_is_not_one_is_refused() {
        // Assert — the seed derivation validates rather than hashing whatever
        // it was handed; an nsec-imported identity has no words at all.
        assert!(derive_bip39_seed(&[]).is_err());
        assert!(derive_bip39_seed(&["not".to_string(), "a".to_string(), "mnemonic".to_string()]).is_err());
    }

    #[test]
    fn different_indices_produce_different_keys() {
        let words = generate_mnemonic().unwrap();
        let k1 = derive_trade_key(&words, 1).unwrap();
        let k2 = derive_trade_key(&words, 2).unwrap();
        assert_ne!(k1.public_key(), k2.public_key());
    }
}
