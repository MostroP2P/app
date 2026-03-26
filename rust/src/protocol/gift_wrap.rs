/// NIP-59 Gift Wrap — three-layer Nostr event encryption.
///
/// Flow (wrap):
///   1. Caller provides content string and rumor kind.
///   2. Creates unsigned rumor → Seal (Kind 13, NIP-44 encrypted, signed by sender).
///   3. Wraps Seal into Gift Wrap (Kind 1059, signed by ephemeral key).
///      The `p` tag on the Gift Wrap points to recipient; sender identity is hidden.
///
/// Flow (unwrap):
///   1. Recipient receives Kind 1059 Gift Wrap.
///   2. Decrypts to obtain the original rumor.
///
/// per research R3 and mostro-core 0.8.0.
use anyhow::Result;
use nostr_sdk::{EventBuilder, Keys, PublicKey};
use nostr_sdk::nips::nip59::UnwrappedGift;

/// A decrypted rumor extracted from a NIP-59 Gift Wrap.
pub struct DecryptedRumor {
    pub content: String,
    pub kind: u16,
    pub sender_pubkey: String,
    pub created_at: i64,
}

/// Wrap a plaintext content string into a NIP-59 Gift Wrap event (Kind 1059).
/// Returns the signed, publishable event.
pub async fn wrap(
    content: &str,
    rumor_kind: u16,
    sender_keys: &Keys,
    recipient_pubkey: &PublicKey,
) -> Result<nostr_sdk::Event> {
    let rumor = EventBuilder::new(
        nostr_sdk::Kind::from(rumor_kind),
        content,
    )
    .build(sender_keys.public_key());

    let gift_wrap = EventBuilder::gift_wrap(sender_keys, recipient_pubkey, rumor, [])
        .await
        .map_err(|e| anyhow::anyhow!("NIP-59 gift_wrap: {}", e))?;

    Ok(gift_wrap)
}

/// Unwrap a Kind 1059 Gift Wrap event, returning the inner rumor.
pub async fn unwrap(
    gift_wrap_event: &nostr_sdk::Event,
    recipient_keys: &Keys,
) -> Result<DecryptedRumor> {
    let unwrapped = UnwrappedGift::from_gift_wrap(recipient_keys, gift_wrap_event)
        .await
        .map_err(|e| anyhow::anyhow!("NIP-59 unwrap: {}", e))?;

    Ok(DecryptedRumor {
        content: unwrapped.rumor.content.clone(),
        kind: unwrapped.rumor.kind.as_u16(),
        sender_pubkey: unwrapped.sender.to_hex(),
        created_at: unwrapped.rumor.created_at.as_secs() as i64,
    })
}

/// Wrap a mostro-core Message into a Gift Wrap event.
pub async fn wrap_mostro_message(
    message: &mostro_core::message::Message,
    sender_keys: &Keys,
    recipient_pubkey: &PublicKey,
) -> Result<nostr_sdk::Event> {
    let content = message
        .as_json()
        .map_err(|e| anyhow::anyhow!("serialize mostro message: {:?}", e))?;
    // Mostro private messages use rumor kind 1 (short text note) inside gift wrap
    wrap(&content, 1, sender_keys, recipient_pubkey).await
}

/// Decode a mostro-core Message from a decrypted rumor.
pub fn decode_mostro_message(
    rumor: &DecryptedRumor,
) -> Result<mostro_core::message::Message> {
    mostro_core::message::Message::from_json(&rumor.content)
        .map_err(|e| anyhow::anyhow!("deserialize mostro message: {:?}", e))
}
