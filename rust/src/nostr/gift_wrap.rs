/// NIP-59 Gift Wrap encode/decode.
///
/// Wrapping layers:
///   1. Rumor    — unsigned content event
///   2. Seal     — Kind 13, NIP-44 encrypted rumor, signed by sender key
///   3. Gift Wrap — Kind 1059, NIP-44 encrypted seal, signed by ephemeral key
use anyhow::{anyhow, Result};
use nostr_sdk::prelude::*;

/// Wrap a plaintext message as a NIP-59 Gift Wrap event addressed to
/// `recipient_pubkey`, signed by `sender_keys`.
///
/// When the connected Mostro requires NIP-13 Proof of Work the difficulty
/// is applied to the **gift wrap** (the outer Kind 1059 event).  The daemon
/// validates `event.check_pow(pow)` on the gift wrap before unwrapping.
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
