/// Chat key derivation for the P2P chat envelope.
///
/// Implements the "Shared Key" section of the protocol chat spec
/// (<https://mostro.network/protocol/chat.html>): the ECDH secret shared by
/// the two trade keys is split with HKDF-SHA256 (empty salt, domain-separated
/// `info` strings) into two secp256k1 keypairs:
///
/// * `K_conv` — NIP-44 encryption of the payload; `pub(K_conv)` is the
///   conversation address carried in the `p` tag. Disclosed to a solver
///   during a dispute (read-only grant).
/// * `K_sign` — signs the outer kind 14 event; `pub(K_sign)` is the author
///   every client filters on. Never disclosed.
///
/// The ECDH is the raw x-coordinate of the shared point — **not**
/// `ecdh::derive_nip04_shared_key`, which hashes it with SHA-256. The spec's
/// test vector is derived from the raw form; mixing the two silently yields a
/// different conversation.
///
/// Since nostr 0.45 made its `generate_shared_key` crate-private, the
/// derivation is delegated to `mostro_core::chat::derive_chat_keys`, which
/// implements the same HKDF split with the same `info` strings. The test
/// vector below pins that equivalence.
use anyhow::{anyhow, Result};
use nostr_sdk::prelude::*;

/// Derive the domain-separated conversation and signing keys for one order.
///
/// Both parties reach the same pair: the ECDH secret is symmetric, and HKDF
/// is deterministic.
///
/// Returns `(K_conv, K_sign)`.
pub fn derive_chat_keys(own_trade: &Keys, peer_trade: &PublicKey) -> Result<(Keys, Keys)> {
    mostro_core::chat::derive_chat_keys(own_trade, peer_trade)
        .map_err(|e| anyhow!("chat key derivation failed: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    // Trade keys from the spec's test vector.
    const ALICE_SK: &str = "548f68890c49fa42f104c60352395e60ff030b0b407e955f1eed1400d6c0347a";
    const BOB_SK: &str = "f258e73f07386d37133718b6127f873dd7c391b8f43b331ff8254034a13d2943";

    #[test]
    fn derivation_matches_the_spec_test_vector() {
        let alice = Keys::parse(ALICE_SK).unwrap();
        let bob = Keys::parse(BOB_SK).unwrap();

        let (conv, sign) = derive_chat_keys(&alice, &bob.public_key()).unwrap();

        assert_eq!(
            conv.public_key().to_hex(),
            "bceb1cd2a8e98ee9729122a1693edcc39c3ace04582ff96a26705c5e4078a6f2",
            "pub(K_conv) diverges from the spec test vector",
        );
        assert_eq!(
            sign.public_key().to_hex(),
            "1dba04571059183f76b148119cfa6f8004dad30cb4e810180a6df17386a7f0b4",
            "pub(K_sign) diverges from the spec test vector",
        );
    }

    #[test]
    fn both_parties_derive_the_same_pair() {
        let alice = Keys::parse(ALICE_SK).unwrap();
        let bob = Keys::parse(BOB_SK).unwrap();

        let (a_conv, a_sign) = derive_chat_keys(&alice, &bob.public_key()).unwrap();
        let (b_conv, b_sign) = derive_chat_keys(&bob, &alice.public_key()).unwrap();

        assert_eq!(a_conv.public_key(), b_conv.public_key());
        assert_eq!(a_sign.public_key(), b_sign.public_key());
    }

    #[test]
    fn conv_and_sign_keys_differ() {
        let alice = Keys::parse(ALICE_SK).unwrap();
        let bob = Keys::parse(BOB_SK).unwrap();

        let (conv, sign) = derive_chat_keys(&alice, &bob.public_key()).unwrap();
        assert_ne!(conv.public_key(), sign.public_key());
    }

    #[test]
    fn different_orders_yield_different_conversations() {
        // Fresh trade keys — a different order derives unrelated chat keys.
        let alice1 = Keys::generate();
        let alice2 = Keys::generate();
        let bob = Keys::generate();

        let (conv1, _) = derive_chat_keys(&alice1, &bob.public_key()).unwrap();
        let (conv2, _) = derive_chat_keys(&alice2, &bob.public_key()).unwrap();
        assert_ne!(conv1.public_key(), conv2.public_key());
    }
}
