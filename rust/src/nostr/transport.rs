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
/// * `mostro_wrap` / `mostro_unwrap` — the P2P chat envelope
///   (<https://mostro.network/protocol/chat.html>): a kind 14 event signed
///   with `K_sign` (derived from the trade-key ECDH secret, see
///   `crate::crypto::chat_keys`), carrying a NIP-44 encrypted kind 1 event
///   signed by the sender's trade key. Replaced the simplified NIP-59 gift
///   wrap, which allowed unattributable third-party flooding — issue #246.
///
/// There is no third entry point: this client does not speak protocol v1 in
/// either direction, so nothing here reads or writes a gift wrap.
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
/// Delegates to `mostro_core::transport::unwrap_incoming`. This app speaks
/// protocol v2 only: it subscribes to Kind 14 and never to the superseded
/// gift-wrap transport, so the v1 arm of that dispatcher is unreachable here.
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

// ── P2P chat envelope (kind 14 signed with K_sign) ───────────────────────────
//
// Implements the event structure and the crypto-side validation steps of the
// chat spec. The caller (api/messages.rs) owns the stateful steps: outer-id
// LRU, rate-limit budget, durable inner-id dedup, and the `since` cursor.
//
// mostro-core 0.14.1 still ships the superseded gift-wrap chat
// (`wrap_chat_message` / `unwrap_chat_message`); this stays a local
// implementation until the canonical one lands upstream — flagged in #246.

/// Tolerance for clock skew, applied both between the inner and outer
/// `created_at` and against the recipient's own clock.
pub const MAX_CLOCK_SKEW_SECS: u64 = 60;

/// Upper bound on the encrypted payload, enforced on receive before
/// decrypting and on send before publishing (`MessageTooLarge`).
pub const MAX_CONTENT_BYTES: usize = 64 * 1024;

/// Upper bound on the outer event's tag count, enforced before signature
/// verification. The envelope defines exactly one `p` tag (plus optional
/// NIP-13 nonce); anything past this is a peer padding the event with junk
/// tags to inflate pre-decryption work — the ciphertext cap alone does not
/// bound the raw event a relay may deliver.
pub const MAX_OUTER_TAGS: usize = 8;

/// Build the outer kind 14 event carrying an encrypted, trade-key-signed
/// kind 1 event, per the P2P chat spec.
///
/// The inner event authenticates the sender; the outer event authenticates
/// the conversation and is what clients (and relays) filter on. When the
/// connected Mostro requires NIP-13 Proof of Work, the difficulty is applied
/// to the outer event.
///
/// Returns `(outer, inner)` — the caller publishes `outer` and keeps
/// `inner.id` as the message's durable identity (it is what the recipient's
/// replay dedup keys on, so both sides agree on it).
///
/// # Arguments
/// - `sender_trade`: the sender's trade keys, used to sign the inner event.
/// - `conv`: `K_conv`, used to encrypt and as the `p` tag.
/// - `sign`: `K_sign`, used to sign the outer event.
/// - `message`: the plaintext payload (text, or attachment-metadata JSON).
pub async fn mostro_wrap(
    sender_trade: &Keys,
    conv: &Keys,
    sign: &Keys,
    message: &str,
) -> Result<(Event, Event)> {
    // One timestamp for both events: the real moment the message is sent.
    // Recipients reject a mismatch, which is what bounds replays. No NIP-59
    // timestamp tweaking — it would break `since`-based sync.
    let now = Timestamp::now();

    // Signed uniqueness nonce: the inner id is a hash over pubkey, kind,
    // created_at, tags and content — with second-resolution timestamps two
    // intentional identical sends ("yes", "yes") in the same second would
    // otherwise collapse to one id and the receiver's replay dedup would
    // silently drop the second one.
    let nonce: [u8; 8] = rand::random();

    let inner = EventBuilder::text_note(message)
        .tag(Tag::custom(
            TagKind::custom("u"),
            [hex::encode(nonce)],
        ))
        .custom_created_at(now)
        .build(sender_trade.public_key())
        .sign(sender_trade)
        .await
        .map_err(|e| anyhow!("inner event sign failed: {e}"))?;

    // NIP-44 self-encryption: K_conv is both sides of the key exchange.
    let content = nip44::encrypt(
        conv.secret_key(),
        &conv.public_key(),
        inner.as_json(),
        nip44::Version::V2,
    )
    .map_err(|e| anyhow!("NIP-44 encrypt failed: {e}"))?;

    // Reject before publishing what every receiver running this protocol
    // must discard before decrypting — otherwise the sender stores the
    // message as "sent" while the counterparty never sees it. Stable marker:
    // Dart maps `MessageTooLarge` to a localized error.
    if content.len() > MAX_CONTENT_BYTES {
        return Err(anyhow!(
            "MessageTooLarge: encrypted payload is {} bytes, limit {}",
            content.len(),
            MAX_CONTENT_BYTES
        ));
    }

    // Exactly one `p` tag, ours. Anything else could hide the message from
    // the `#p` query a dispute solver uses to rebuild the transcript.
    let builder = EventBuilder::new(Kind::PrivateDirectMessage, content)
        .tag(Tag::public_key(conv.public_key()))
        .custom_created_at(now);

    let pow = crate::mostro::pow::get_pow();
    let builder = if pow > 0 { builder.pow(pow) } else { builder };

    let outer = builder
        .sign_with_keys(sign)
        .map_err(|e| anyhow!("outer event sign failed: {e}"))?;

    Ok((outer, inner))
}

/// Validate an incoming outer event and return the inner event.
///
/// Implements the crypto-side steps of the spec's cheapest-check-first
/// validation order (author, `p` tag, absolute timestamp bound, size, outer
/// signature, decrypt, inner signature, allowed signer, inner kind, relative
/// timestamp bound). Three steps are the **caller's**, because they need
/// state this function does not own: the bounded LRU on the outer id, the
/// rate-limit budget, and the durable dedup on the inner id. A caller that
/// skips the durable inner-id check accepts replays.
///
/// # Arguments
/// - `conv`: `K_conv`, used to decrypt.
/// - `sign_pubkey`: `pub(K_sign)` of this conversation.
/// - `allowed_signers`: the buyer's and the seller's trade pubkeys.
/// - `outer`: the received kind 14 event.
/// - `now`: the recipient's current time, for the absolute timestamp bound.
pub fn mostro_unwrap(
    conv: &Keys,
    sign_pubkey: &PublicKey,
    allowed_signers: &[PublicKey],
    outer: &Event,
    now: Timestamp,
) -> Result<Event> {
    // A third party cannot produce a valid signature for this author, so this
    // check is what makes flooding impossible. Relays enforce it too, via the
    // `authors` filter; we re-check locally.
    if outer.pubkey != *sign_pubkey {
        return Err(anyhow!(
            "outer event is not authored by the conversation signing key"
        ));
    }
    if outer.kind != Kind::PrivateDirectMessage {
        return Err(anyhow!("outer event is not kind 14"));
    }

    // Bound the raw event before any signature work: the ciphertext cap
    // below does not stop a peer from shipping a small ciphertext inside a
    // multi-megabyte event padded with thousands of junk tags, forcing
    // hashing and verification cost per event.
    if outer.tags.len() > MAX_OUTER_TAGS {
        return Err(anyhow!(
            "outer event carries {} tags, limit {}",
            outer.tags.len(),
            MAX_OUTER_TAGS
        ));
    }

    // Exactly one `p` tag, addressing this conversation. Anything else could
    // be a message engineered to stay out of a dispute solver's `#p` query.
    let mut p_tags = outer
        .tags
        .iter()
        .filter(|t| t.kind() == TagKind::p());
    match (p_tags.next().and_then(|t| t.content()), p_tags.next()) {
        (Some(pk), None) if pk == conv.public_key().to_hex() => {}
        _ => {
            return Err(anyhow!(
                "outer event must carry exactly one p tag for this conversation"
            ))
        }
    }

    // Absolute bound against our own clock. Without it a counterparty can
    // date both events far in the future — they agree with each other, so the
    // relative check below passes — and poison the `since` cursor, silencing
    // the conversation until that date. The past is unbounded: catching up
    // after being offline is legitimate.
    if outer.created_at.as_secs() > now.as_secs().saturating_add(MAX_CLOCK_SKEW_SECS) {
        return Err(anyhow!("outer event is dated too far in the future"));
    }

    if outer.content.len() > MAX_CONTENT_BYTES {
        return Err(anyhow!("encrypted payload exceeds the accepted size"));
    }

    outer
        .verify()
        .map_err(|e| anyhow!("outer signature invalid: {e}"))?;

    let decrypted = nip44::decrypt(conv.secret_key(), &conv.public_key(), &outer.content)
        .map_err(|e| anyhow!("NIP-44 decrypt failed: {e}"))?;
    let inner = Event::from_json(&decrypted)
        .map_err(|e| anyhow!("inner event parse failed: {e}"))?;

    // The only authentication of who wrote the message: both parties can sign
    // the outer event, so it cannot tell the two sides apart. Reading the
    // inner pubkey without verifying this signature accepts forged senders.
    inner
        .verify()
        .map_err(|e| anyhow!("inner signature invalid: {e}"))?;
    if !allowed_signers.contains(&inner.pubkey) {
        return Err(anyhow!(
            "inner event is signed by a key that is not a party to this order"
        ));
    }
    if inner.kind != Kind::TextNote {
        return Err(anyhow!("inner event is not kind 1"));
    }

    // Bounds how far back the caller's durable inner-id dedup has to reach: a
    // re-wrap older than the tolerance is stale and rejected here, while one
    // inside the window is caught by that dedup, never by this check.
    let skew = inner
        .created_at
        .as_secs()
        .abs_diff(outer.created_at.as_secs());
    if skew > MAX_CLOCK_SKEW_SECS {
        return Err(anyhow!("inner and outer timestamps disagree — stale re-wrap"));
    }

    Ok(inner)
}

#[cfg(test)]
mod chat_envelope_tests {
    use super::*;
    use crate::crypto::chat_keys::derive_chat_keys;

    struct Convo {
        alice_trade: Keys,
        bob_trade: Keys,
        conv: Keys,
        sign: Keys,
    }

    fn convo() -> Convo {
        let alice_trade = Keys::generate();
        let bob_trade = Keys::generate();
        let (conv, sign) = derive_chat_keys(&alice_trade, &bob_trade.public_key()).unwrap();
        Convo {
            alice_trade,
            bob_trade,
            conv,
            sign,
        }
    }

    fn unwrap_now(c: &Convo, outer: &Event) -> Result<Event> {
        mostro_unwrap(
            &c.conv,
            &c.sign.public_key(),
            &[c.alice_trade.public_key(), c.bob_trade.public_key()],
            outer,
            Timestamp::now(),
        )
    }

    #[tokio::test]
    async fn round_trip_authenticates_the_sender() {
        let c = convo();
        let (outer, inner) = mostro_wrap(&c.alice_trade, &c.conv, &c.sign, "hola")
            .await
            .unwrap();

        // Wire shape: kind 14 authored by pub(K_sign), one p tag = pub(K_conv),
        // and no field anywhere carrying a trade pubkey.
        assert_eq!(outer.kind, Kind::PrivateDirectMessage);
        assert_eq!(outer.pubkey, c.sign.public_key());
        let outer_json = outer.as_json();
        assert!(!outer_json.contains(&c.alice_trade.public_key().to_hex()));
        assert!(!outer_json.contains(&c.bob_trade.public_key().to_hex()));

        let got = unwrap_now(&c, &outer).unwrap();
        assert_eq!(got.id, inner.id);
        assert_eq!(got.pubkey, c.alice_trade.public_key());
        assert_eq!(got.content, "hola");
    }

    #[tokio::test]
    async fn wrong_outer_author_is_rejected() {
        let c = convo();
        let (_, inner) = mostro_wrap(&c.alice_trade, &c.conv, &c.sign, "hola")
            .await
            .unwrap();

        // A third party re-encrypts a genuine inner event under K_conv (which
        // it could hold after a dispute disclosure) but must sign the outer
        // event with its own key — rejected on the author check.
        let mallory = Keys::generate();
        let content = nip44::encrypt(
            c.conv.secret_key(),
            &c.conv.public_key(),
            inner.as_json(),
            nip44::Version::V2,
        )
        .unwrap();
        let forged = EventBuilder::new(Kind::PrivateDirectMessage, content)
            .tag(Tag::public_key(c.conv.public_key()))
            .custom_created_at(inner.created_at)
            .sign_with_keys(&mallory)
            .unwrap();

        let err = unwrap_now(&c, &forged).unwrap_err().to_string();
        assert!(err.contains("not authored"), "got: {err}");
    }

    #[tokio::test]
    async fn missing_or_foreign_p_tag_is_rejected() {
        let c = convo();
        let (_, inner) = mostro_wrap(&c.alice_trade, &c.conv, &c.sign, "hola")
            .await
            .unwrap();
        let content = nip44::encrypt(
            c.conv.secret_key(),
            &c.conv.public_key(),
            inner.as_json(),
            nip44::Version::V2,
        )
        .unwrap();

        // No p tag: reaches us via the authors filter, but would be invisible
        // in the #p transcript a dispute solver retrieves.
        let no_p = EventBuilder::new(Kind::PrivateDirectMessage, content.clone())
            .custom_created_at(inner.created_at)
            .sign_with_keys(&c.sign)
            .unwrap();
        assert!(unwrap_now(&c, &no_p).is_err());

        // Foreign p tag: same evasion, pointing elsewhere.
        let foreign = EventBuilder::new(Kind::PrivateDirectMessage, content.clone())
            .tag(Tag::public_key(Keys::generate().public_key()))
            .custom_created_at(inner.created_at)
            .sign_with_keys(&c.sign)
            .unwrap();
        assert!(unwrap_now(&c, &foreign).is_err());

        // Two p tags: ours plus a decoy — "exactly one" is the contract.
        let two = EventBuilder::new(Kind::PrivateDirectMessage, content)
            .tag(Tag::public_key(c.conv.public_key()))
            .tag(Tag::public_key(Keys::generate().public_key()))
            .custom_created_at(inner.created_at)
            .sign_with_keys(&c.sign)
            .unwrap();
        assert!(unwrap_now(&c, &two).is_err());
    }

    #[tokio::test]
    async fn far_future_timestamp_is_rejected() {
        let c = convo();
        // Counterparty dates BOTH events in the future: the relative check
        // passes, only the absolute bound against our clock catches it —
        // this is the cursor-poisoning defence.
        let future = Timestamp::from_secs(Timestamp::now().as_secs() + 7 * 24 * 3600);
        let inner = EventBuilder::text_note("poison")
            .custom_created_at(future)
            .build(c.alice_trade.public_key())
            .sign(&c.alice_trade)
            .await
            .unwrap();
        let content = nip44::encrypt(
            c.conv.secret_key(),
            &c.conv.public_key(),
            inner.as_json(),
            nip44::Version::V2,
        )
        .unwrap();
        let outer = EventBuilder::new(Kind::PrivateDirectMessage, content)
            .tag(Tag::public_key(c.conv.public_key()))
            .custom_created_at(future)
            .sign_with_keys(&c.sign)
            .unwrap();

        let err = unwrap_now(&c, &outer).unwrap_err().to_string();
        assert!(err.contains("future"), "got: {err}");
    }

    #[tokio::test]
    async fn oversized_payload_is_rejected_before_decrypting() {
        let c = convo();
        let big = "x".repeat(MAX_CONTENT_BYTES + 1);
        let outer = EventBuilder::new(Kind::PrivateDirectMessage, big)
            .tag(Tag::public_key(c.conv.public_key()))
            .sign_with_keys(&c.sign)
            .unwrap();

        let err = unwrap_now(&c, &outer).unwrap_err().to_string();
        assert!(err.contains("size"), "got: {err}");
    }

    #[tokio::test]
    async fn inner_signed_by_a_stranger_is_rejected() {
        let c = convo();
        // Outer is genuine (signed with K_sign) but the inner author is not a
        // party to the order — e.g. a solver who obtained K_sign could still
        // not impersonate either side.
        let stranger = Keys::generate();
        let (outer, _) = mostro_wrap(&stranger, &c.conv, &c.sign, "imposter")
            .await
            .unwrap();

        let err = unwrap_now(&c, &outer).unwrap_err().to_string();
        assert!(err.contains("not a party"), "got: {err}");
    }

    #[tokio::test]
    async fn tampered_inner_signature_is_rejected() {
        let c = convo();
        let (_, inner) = mostro_wrap(&c.alice_trade, &c.conv, &c.sign, "hola")
            .await
            .unwrap();

        // Forge the inner: claim Alice's pubkey without her signature.
        let mut forged: serde_json::Value = serde_json::from_str(&inner.as_json()).unwrap();
        forged["content"] = serde_json::json!("I sent the fiat");
        let content = nip44::encrypt(
            c.conv.secret_key(),
            &c.conv.public_key(),
            forged.to_string(),
            nip44::Version::V2,
        )
        .unwrap();
        let outer = EventBuilder::new(Kind::PrivateDirectMessage, content)
            .tag(Tag::public_key(c.conv.public_key()))
            .custom_created_at(inner.created_at)
            .sign_with_keys(&c.sign)
            .unwrap();

        assert!(unwrap_now(&c, &outer).is_err());
    }

    #[tokio::test]
    async fn stale_rewrap_outside_the_window_is_rejected() {
        let c = convo();
        let (_, inner) = mostro_wrap(&c.alice_trade, &c.conv, &c.sign, "fiat sent")
            .await
            .unwrap();

        // Bob re-wraps Alice's genuine old message in a fresh outer event
        // dated outside the tolerance window: the relative bound rejects it.
        let later = Timestamp::from_secs(inner.created_at.as_secs() + MAX_CLOCK_SKEW_SECS + 10);
        let content = nip44::encrypt(
            c.conv.secret_key(),
            &c.conv.public_key(),
            inner.as_json(),
            nip44::Version::V2,
        )
        .unwrap();
        let rewrap = EventBuilder::new(Kind::PrivateDirectMessage, content)
            .tag(Tag::public_key(c.conv.public_key()))
            .custom_created_at(later)
            .sign_with_keys(&c.sign)
            .unwrap();

        let err = mostro_unwrap(
            &c.conv,
            &c.sign.public_key(),
            &[c.alice_trade.public_key(), c.bob_trade.public_key()],
            &rewrap,
            later,
        )
        .unwrap_err()
        .to_string();
        assert!(err.contains("stale"), "got: {err}");
    }

    #[tokio::test]
    async fn identical_same_second_sends_keep_distinct_identities() {
        let c = convo();
        // Two rapid "yes" messages: without the signed nonce they would share
        // one inner id and the receiver's dedup would drop the second.
        let (o1, i1) = mostro_wrap(&c.alice_trade, &c.conv, &c.sign, "yes")
            .await
            .unwrap();
        let (o2, i2) = mostro_wrap(&c.alice_trade, &c.conv, &c.sign, "yes")
            .await
            .unwrap();

        assert_ne!(i1.id, i2.id, "identical sends collapsed to one inner id");
        assert!(unwrap_now(&c, &o1).is_ok());
        assert!(unwrap_now(&c, &o2).is_ok());
    }

    #[tokio::test]
    async fn oversized_message_is_refused_at_send_time() {
        let c = convo();
        // Large enough that the NIP-44 ciphertext exceeds what any receiver
        // accepts — must fail with the stable marker instead of publishing.
        let big = "x".repeat(60 * 1024);
        let err = mostro_wrap(&c.alice_trade, &c.conv, &c.sign, &big)
            .await
            .unwrap_err()
            .to_string();
        assert!(err.contains("MessageTooLarge"), "got: {err}");

        // A comfortably large message still round-trips (largest-accepted
        // boundary is fuzzy by design: NIP-44 padding + JSON escaping).
        let ok = "y".repeat(30 * 1024);
        let (outer, _) = mostro_wrap(&c.alice_trade, &c.conv, &c.sign, &ok)
            .await
            .unwrap();
        let inner = unwrap_now(&c, &outer).unwrap();
        assert_eq!(inner.content, ok);
    }

    #[tokio::test]
    async fn junk_tag_padding_is_rejected_before_verification() {
        let c = convo();
        let (_, inner) = mostro_wrap(&c.alice_trade, &c.conv, &c.sign, "hola")
            .await
            .unwrap();
        let content = nip44::encrypt(
            c.conv.secret_key(),
            &c.conv.public_key(),
            inner.as_json(),
            nip44::Version::V2,
        )
        .unwrap();

        // Small ciphertext, huge tag list — the raw-event bound must trip.
        let mut builder = EventBuilder::new(Kind::PrivateDirectMessage, content)
            .tag(Tag::public_key(c.conv.public_key()));
        for i in 0..2000 {
            builder = builder.tag(Tag::custom(
                TagKind::custom("x"),
                [format!("junk-{i}")],
            ));
        }
        let padded = builder
            .custom_created_at(inner.created_at)
            .sign_with_keys(&c.sign)
            .unwrap();

        let err = unwrap_now(&c, &padded).unwrap_err().to_string();
        assert!(err.contains("tags"), "got: {err}");
    }

    #[tokio::test]
    async fn conv_key_alone_cannot_author_into_the_conversation() {
        // Dispute disclosure grant: K_conv decrypts, but an outer event signed
        // with K_conv (instead of K_sign) is rejected — read-only access.
        let c = convo();
        let (_, inner) = mostro_wrap(&c.alice_trade, &c.conv, &c.sign, "hola")
            .await
            .unwrap();
        let content = nip44::encrypt(
            c.conv.secret_key(),
            &c.conv.public_key(),
            inner.as_json(),
            nip44::Version::V2,
        )
        .unwrap();
        let signed_with_conv = EventBuilder::new(Kind::PrivateDirectMessage, content)
            .tag(Tag::public_key(c.conv.public_key()))
            .custom_created_at(inner.created_at)
            .sign_with_keys(&c.conv)
            .unwrap();

        assert!(unwrap_now(&c, &signed_with_conv).is_err());
    }
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
        let event = crate::rt::time::timeout(
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
