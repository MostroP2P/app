/// NIP-59 Gift Wrap transport.
///
/// Two entry points:
///
/// * `wrap_mostro_message` / `unwrap_mostro_message` — typed Mostro protocol
///   traffic, delegated to `mostro_core::nip59` so every Mostro client shares
///   one NIP-59 implementation (seal construction, ephemeral keys, timestamp
///   tweak, PoW, inner-tuple signing/verification).
///
/// * `wrap` / `unwrap` — raw JSON content wrapped in a Kind 14 rumor, used
///   for NIP-17-style text DMs (P2P chat, dispute admin messages). These
///   payloads are not `mostro_core::Message` values, so they stay on the
///   local helper — see issue #101, "Scope".
use anyhow::{anyhow, Result};
use mostro_core::message::Message;
use mostro_core::nip59::{
    unwrap_message as core_unwrap, wrap_message as core_wrap, UnwrappedMessage, WrapOptions,
};
use nostr_sdk::prelude::*;

// ── Mostro protocol traffic (typed `Message`) ────────────────────────────────

/// Wrap a `Message` destined for `receiver` (typically the Mostro node).
///
/// `trade_keys` author the rumor, sign the Seal, and produce the inner-tuple
/// signature. `pow` is applied to the outer Kind 1059 only.
pub async fn wrap_mostro_message(
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
    core_wrap(message, trade_keys, *receiver, opts)
        .await
        .map_err(|e| anyhow!("wrap_message failed: {e}"))
}

/// Try to open an incoming Kind 1059 event using `trade_keys`.
///
/// Returns `Ok(None)` only when the outer NIP-44 layer cannot be decrypted
/// with the given key — the canonical "not addressed to me" signal, used by
/// the global subscription to trial-decrypt across all derived trade keys.
/// Every other failure (corrupted seal, malformed rumor, bad signature,
/// sender mismatch) surfaces as `Err`.
pub async fn unwrap_mostro_message(
    trade_keys: &Keys,
    event: &Event,
) -> Result<Option<UnwrappedMessage>> {
    core_unwrap(event, trade_keys)
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
        let trade_keys = Keys::generate();
        let receiver_keys = Keys::generate();
        let msg = sample_message(Some(42));

        let event = wrap_mostro_message(&trade_keys, &receiver_keys.public_key(), &msg, 0)
            .await
            .expect("wrap");

        assert_eq!(event.kind, Kind::GiftWrap);

        let unwrapped = unwrap_mostro_message(&receiver_keys, &event)
            .await
            .expect("unwrap result")
            .expect("addressed to us");

        assert_eq!(unwrapped.sender, trade_keys.public_key());
        assert_eq!(
            unwrapped.message.as_json().unwrap(),
            msg.as_json().unwrap(),
        );
        assert!(unwrapped.signature.is_some(), "signed=true by default");
    }

    #[tokio::test]
    async fn unwrap_with_wrong_recipient_returns_none() {
        let trade_keys = Keys::generate();
        let receiver_keys = Keys::generate();
        let stranger_keys = Keys::generate();

        let event =
            wrap_mostro_message(&trade_keys, &receiver_keys.public_key(), &sample_message(None), 0)
                .await
                .expect("wrap");

        let result = unwrap_mostro_message(&stranger_keys, &event)
            .await
            .expect("wrong-recipient must not error");

        assert!(result.is_none(), "Ok(None) signals 'not for us'");
    }

    #[tokio::test]
    async fn pow_is_applied_to_outer_event() {
        let trade_keys = Keys::generate();
        let receiver_keys = Keys::generate();
        let difficulty = 4; // low to keep the test fast

        let event =
            wrap_mostro_message(&trade_keys, &receiver_keys.public_key(), &sample_message(None), difficulty)
                .await
                .expect("wrap with pow");

        let id_bytes = event.id.to_bytes();
        let mut leading_zero_bits: u8 = 0;
        for byte in id_bytes.iter() {
            if *byte == 0 {
                leading_zero_bits += 8;
                continue;
            }
            leading_zero_bits += byte.leading_zeros() as u8;
            break;
        }
        assert!(
            leading_zero_bits >= difficulty,
            "event id {} has {} leading zero bits, expected >= {}",
            event.id.to_hex(),
            leading_zero_bits,
            difficulty,
        );
    }
}
