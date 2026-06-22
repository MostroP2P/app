/// Mostro message transport.
///
/// Two entry points:
///
/// * `wrap_mostro_message` / `unwrap_mostro_message` — typed Mostro protocol
///   traffic, delegated to `mostro_core::transport` so every Mostro client
///   shares one implementation. This app speaks **protocol v2** (NIP-44
///   direct, signed Kind 14, authored by the trade key); the 3-tuple, identity
///   proof, NIP-44 encryption and event signing/verification all live in
///   mostro-core. See `specs/005-transport-v2-migration/`.
///
/// * `wrap` / `unwrap` — raw JSON content gift-wrapped (NIP-59, Kind 1059),
///   used for NIP-17-style text DMs (P2P chat, dispute admin messages). These
///   are **not** part of the v2 migration: they keep using gift wrap. Their
///   payloads are not `mostro_core::Message` values, so they stay on the
///   local helper — see issue #101, "Scope".
use anyhow::{anyhow, Result};
use mostro_core::message::Message;
use mostro_core::nip59::{UnwrappedMessage, WrapOptions};
use mostro_core::transport::{unwrap_incoming, wrap_message_with, Transport};
use nostr_sdk::prelude::*;

// ── Mostro protocol traffic (typed `Message`) ────────────────────────────────

/// Wrap a `Message` destined for `receiver` (typically the Mostro node) as a
/// protocol-v2 NIP-44 direct event (signed Kind 14, authored by the trade key).
///
/// `trade_keys` author and sign the Kind 14 event and produce the inner trade
/// signature; `identity_keys` produce the in-ciphertext identity proof binding
/// the long-lived identity the node uses to accumulate reputation. For
/// full-privacy mode (no reputation), callers pass the same value for both
/// parameters and no identity proof is attached — see
/// <https://mostro.network/protocol/key_management.html>.
///
/// `pow` (NIP-13) is applied to the Kind 14 event id; the daemon fills its own
/// NIP-40 expiration, so this app always sends `expiration: None`.
pub async fn wrap_mostro_message(
    identity_keys: &Keys,
    trade_keys: &Keys,
    receiver: &PublicKey,
    message: &Message,
    pow: u8,
) -> Result<Event> {
    let opts = WrapOptions {
        pow,
        expiration: None,
        signed: true,
    };
    wrap_message_with(
        Transport::Nip44Direct,
        message,
        identity_keys,
        trade_keys,
        *receiver,
        opts,
    )
    .await
    .map_err(|e| anyhow!("wrap_message failed: {e}"))
}

/// Try to open an incoming Mostro event using `trade_keys`.
///
/// Delegates to `mostro_core::transport::unwrap_incoming`, which dispatches by
/// event kind: a Kind 14 event is opened on the protocol-v2 NIP-44 path, a
/// Kind 1059 event on the legacy gift-wrap path. (This app subscribes only to
/// Kind 14, but the dispatcher accepts both.)
///
/// Returns `Ok(None)` only when the NIP-44 content cannot be decrypted with
/// the given key — the canonical "not addressed to me" signal, used by the
/// global subscription to trial-decrypt across all derived trade keys. Every
/// other failure (invalid event signature, malformed tuple, non-verifying
/// inner signatures) yields `Err`.
///
/// In v2 the Kind 14 event signature is load-bearing and is verified here, so
/// `UnwrappedMessage::sender` (the event author) is cryptographically
/// attributable. `identity` is the proven identity-proof pubkey, or the trade
/// key itself in full-privacy mode. Daemon authentication (matching the author
/// against the active Mostro pubkey) is enforced by the receive handlers and
/// the dispatcher in `api/orders.rs` before routing.
pub async fn unwrap_mostro_message(
    trade_keys: &Keys,
    event: &Event,
) -> Result<Option<UnwrappedMessage>> {
    unwrap_incoming(event, trade_keys)
        .await
        .map_err(|e| anyhow!("unwrap_message failed: {e}"))
}

// ── NIP-17 text DMs (P2P chat, dispute admin) ────────────────────────────────
//
// These wrap arbitrary JSON content in a Kind 14 rumor. Kept as local glue
// until `mostro-core` grows a DM helper or we migrate these off NIP-59.

/// Wrap a plaintext JSON payload as a NIP-59 Gift Wrap event addressed to
/// `recipient_pubkey`, signed by `sender_keys`.
///
/// When the connected Mostro requires NIP-13 Proof of Work the difficulty
/// is applied to the **gift wrap** (the outer Kind 1059 event).
///
/// Returns the serialised `Event` JSON ready for publication.
pub async fn wrap(
    sender_keys: &Keys,
    recipient_pubkey: &PublicKey,
    content: &str,
    kind: Kind,
) -> Result<String> {
    let rumor = EventBuilder::new(kind, content).build(sender_keys.public_key());

    let seal = EventBuilder::seal(sender_keys, recipient_pubkey, rumor)
        .await
        .map_err(|e| anyhow!("NIP-59 seal failed: {e}"))?
        .sign_with_keys(sender_keys)
        .map_err(|e| anyhow!("seal sign failed: {e}"))?;

    let pow = crate::mostro::pow::get_pow();
    let gift_wrap = if pow > 0 {
        // Build the gift wrap manually so we can inject .pow() — the SDK's
        // gift_wrap_from_seal helper doesn't support NIP-13.
        let ephemeral_keys = Keys::generate();
        let encrypted = nip44::encrypt(
            ephemeral_keys.secret_key(),
            recipient_pubkey,
            seal.as_json(),
            nip44::Version::default(),
        )
        .map_err(|e| anyhow!("NIP-44 encrypt failed: {e}"))?;

        EventBuilder::new(Kind::GiftWrap, encrypted)
            .tag(Tag::public_key(*recipient_pubkey))
            .custom_created_at(Timestamp::tweaked(nip59::RANGE_RANDOM_TIMESTAMP_TWEAK))
            .pow(pow)
            .sign_with_keys(&ephemeral_keys)
            .map_err(|e| anyhow!("gift wrap sign+pow failed: {e}"))?
    } else {
        EventBuilder::gift_wrap_from_seal(recipient_pubkey, &seal, [])
            .map_err(|e| anyhow!("NIP-59 gift_wrap failed: {e}"))?
    };

    Ok(gift_wrap.as_json())
}

/// Unwrap a NIP-59 Gift Wrap event using `recipient_keys`.
///
/// Returns the inner rumor as a serialised `UnsignedEvent` JSON string.
pub async fn unwrap(recipient_keys: &Keys, gift_wrap_json: &str) -> Result<String> {
    let event = Event::from_json(gift_wrap_json)
        .map_err(|e| anyhow!("invalid gift wrap JSON: {e}"))?;

    let unwrapped = nip59::extract_rumor(recipient_keys, &event)
        .await
        .map_err(|e| anyhow!("NIP-59 unwrap failed: {e}"))?;

    Ok(unwrapped.rumor.as_json())
}

#[cfg(test)]
mod tests {
    use super::*;
    use mostro_core::message::{Action, MessageKind};
    use uuid::Uuid;

    fn sample_message(request_id: Option<u64>) -> Message {
        Message::Order(MessageKind::new(
            Some(Uuid::parse_str("308e1272-d5f4-47e6-bd97-3504baea9c23").unwrap()),
            request_id,
            Some(1),
            Action::FiatSent,
            None,
        ))
    }

    #[tokio::test]
    async fn roundtrip_preserves_message_and_sender() {
        let identity_keys = Keys::generate();
        let trade_keys = Keys::generate();
        let receiver_keys = Keys::generate();
        let msg = sample_message(Some(42));

        let event = wrap_mostro_message(
            &identity_keys,
            &trade_keys,
            &receiver_keys.public_key(),
            &msg,
            0,
        )
        .await
        .expect("wrap");

        // Protocol v2: a signed Kind 14 event authored by the trade key.
        assert_eq!(event.kind, Kind::PrivateDirectMessage);
        assert_eq!(event.pubkey, trade_keys.public_key());

        let unwrapped = unwrap_mostro_message(&receiver_keys, &event)
            .await
            .expect("unwrap result")
            .expect("addressed to us");

        assert_eq!(unwrapped.sender, trade_keys.public_key());
        assert_eq!(unwrapped.identity, identity_keys.public_key());
        assert_eq!(
            unwrapped.message.as_json().unwrap(),
            msg.as_json().unwrap(),
        );
        assert!(unwrapped.signature.is_some(), "signed=true by default");
    }

    #[tokio::test]
    async fn full_privacy_mode_reuses_trade_key_as_identity() {
        let trade_keys = Keys::generate();
        let receiver_keys = Keys::generate();

        let event = wrap_mostro_message(
            &trade_keys,
            &trade_keys,
            &receiver_keys.public_key(),
            &sample_message(Some(1)),
            0,
        )
        .await
        .expect("wrap");

        let unwrapped = unwrap_mostro_message(&receiver_keys, &event)
            .await
            .expect("unwrap")
            .expect("addressed to us");

        assert_eq!(unwrapped.sender, trade_keys.public_key());
        assert_eq!(unwrapped.identity, trade_keys.public_key());
    }

    #[tokio::test]
    async fn unwrap_with_wrong_recipient_returns_none() {
        let identity_keys = Keys::generate();
        let trade_keys = Keys::generate();
        let receiver_keys = Keys::generate();
        let stranger_keys = Keys::generate();

        let event = wrap_mostro_message(
            &identity_keys,
            &trade_keys,
            &receiver_keys.public_key(),
            &sample_message(None),
            0,
        )
        .await
        .expect("wrap");

        let result = unwrap_mostro_message(&stranger_keys, &event)
            .await
            .expect("wrong-recipient must not error");

        assert!(result.is_none(), "Ok(None) signals 'not for us'");
    }

    #[tokio::test]
    async fn pow_is_applied_to_event() {
        use std::time::Duration;

        let identity_keys = Keys::generate();
        let trade_keys = Keys::generate();
        let receiver_keys = Keys::generate();
        let difficulty: u8 = 4; // low to keep the test fast (avg ~16 tries)

        // Mining is probabilistic — cap wall time so a regression that
        // stalls or loops does not hang CI indefinitely.
        let event = tokio::time::timeout(
            Duration::from_secs(30),
            wrap_mostro_message(
                &identity_keys,
                &trade_keys,
                &receiver_keys.public_key(),
                &sample_message(None),
                difficulty,
            ),
        )
        .await
        .expect("wrap with pow timed out")
        .expect("wrap with pow failed");

        let leading_zero_bits: u32 = event
            .id
            .to_bytes()
            .iter()
            .map(|b| {
                let lz = b.leading_zeros();
                (lz, *b == 0)
            })
            .scan(true, |still_leading, (lz, is_zero)| {
                if !*still_leading {
                    return Some(0u32);
                }
                if !is_zero {
                    *still_leading = false;
                }
                Some(lz)
            })
            .sum();

        assert!(
            leading_zero_bits >= u32::from(difficulty),
            "event id {} has {} leading zero bits, expected >= {}",
            event.id.to_hex(),
            leading_zero_bits,
            difficulty,
        );
    }
}
