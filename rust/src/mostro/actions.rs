/// Mostro action dispatch — builds and wraps `mostro_core::Message` values.
///
/// Each function constructs a `Message` using the `mostro-core` types,
/// wraps it as a transport-v2 (NIP-44, signed Kind 14) event via
/// `transport::wrap_mostro_message`, and returns the event JSON ready for
/// publication.
///
/// **Key split.** Mostro-core 0.10 requires two `Keys` values per wrap:
/// `identity_keys` sign the Seal (Kind 13) so the node can tie the rumor to
/// a long-lived pubkey for reputation purposes, while `trade_keys` author
/// the rumor (Kind 1) and produce the inner tuple signature. Callers who
/// want "full-privacy mode" (no reputation) pass `trade_keys` for both
/// arguments — see `api::identity::get_transport_identity_keys`, which
/// applies the runtime privacy toggle.
use anyhow::Result;
use mostro_core::message::{Action, Message, Payload};
use nostr_sdk::prelude::*;
use uuid::Uuid;

use crate::api::types::{NewOrderParams, OrderKind};
use crate::nostr::transport;

// ── Public action builders ────────────────────────────────────────────────────

/// Build and wrap a NewOrder MostroMessage.
///
/// `request_id` is a caller-generated correlation nonce: the daemon echoes it
/// in the `NewOrder` confirmation and in any `CantDo` rejection, which is how
/// `create_order` tells the genuine reply apart from stale relay-replayed
/// events addressed to the same trade key.
///
/// Returns the transport-v2 (NIP-44, signed Kind 14) event JSON ready for publication.
pub async fn new_order(
    identity_keys: &Keys,
    trade_keys: &Keys,
    mostro_pubkey: &PublicKey,
    params: &NewOrderParams,
    trade_index: u32,
    request_id: u64,
) -> Result<String> {
    use mostro_core::order::{Kind, SmallOrder, Status};

    let kind = match params.kind {
        OrderKind::Buy => Kind::Buy,
        OrderKind::Sell => Kind::Sell,
    };

    let fiat_amount = params.fiat_amount.unwrap_or(0.0) as i64;
    let fiat_amount_min = params.fiat_amount_min.map(|v| v as i64);
    let fiat_amount_max = params.fiat_amount_max.map(|v| v as i64);
    let premium = params.premium as i64;

    let small_order = SmallOrder::new(
        None,
        Some(kind),
        Some(Status::Pending),
        params.amount_sats.unwrap_or(0) as i64,
        params.fiat_code.clone(),
        fiat_amount_min,
        fiat_amount_max,
        fiat_amount,
        params.payment_method.clone(),
        premium,
        None,
        None,
        None,
        None,
        None,
    );

    let payload = Some(Payload::Order(small_order));
    let msg = Message::new_order(
        None,
        Some(request_id),
        Some(trade_index as i64),
        Action::NewOrder,
        payload,
    );
    wrap_message_first_contact(identity_keys, trade_keys, mostro_pubkey, &msg).await
}

/// Build and wrap a TakeBuy MostroMessage.
///
/// `request_id` is the correlation nonce echoed by the daemon in its reply —
/// see [`take_order_impl`].
#[allow(clippy::too_many_arguments)]
pub async fn take_buy(
    identity_keys: &Keys,
    trade_keys: &Keys,
    mostro_pubkey: &PublicKey,
    order_id: &str,
    trade_index: u32,
    amount: Option<f64>,
    request_id: u64,
) -> Result<String> {
    take_order_impl(
        identity_keys,
        trade_keys,
        mostro_pubkey,
        order_id,
        trade_index,
        amount,
        None,
        Action::TakeBuy,
        request_id,
    )
    .await
}

/// Build and wrap a TakeSell MostroMessage.
///
/// If `ln_address` is `Some`, it is included in the payload so Mostro can
/// pay the buyer directly (take-sell-ln-address variant). `request_id` is the
/// correlation nonce echoed by the daemon in its reply — see
/// [`take_order_impl`].
#[allow(clippy::too_many_arguments)]
pub async fn take_sell(
    identity_keys: &Keys,
    trade_keys: &Keys,
    mostro_pubkey: &PublicKey,
    order_id: &str,
    trade_index: u32,
    amount: Option<f64>,
    ln_address: Option<&str>,
    request_id: u64,
) -> Result<String> {
    take_order_impl(
        identity_keys,
        trade_keys,
        mostro_pubkey,
        order_id,
        trade_index,
        amount,
        ln_address,
        Action::TakeSell,
        request_id,
    )
    .await
}

/// Build and wrap a FiatSent MostroMessage.
pub async fn fiat_sent(
    identity_keys: &Keys,
    trade_keys: &Keys,
    mostro_pubkey: &PublicKey,
    order_id: &str,
    trade_index: u32,
) -> Result<String> {
    simple_action(
        identity_keys,
        trade_keys,
        mostro_pubkey,
        order_id,
        trade_index,
        Action::FiatSent,
    )
    .await
}

/// Build and wrap a Release MostroMessage.
pub async fn release(
    identity_keys: &Keys,
    trade_keys: &Keys,
    mostro_pubkey: &PublicKey,
    order_id: &str,
    trade_index: u32,
) -> Result<String> {
    simple_action(
        identity_keys,
        trade_keys,
        mostro_pubkey,
        order_id,
        trade_index,
        Action::Release,
    )
    .await
}

/// Build and wrap a Cancel MostroMessage.
pub async fn cancel(
    identity_keys: &Keys,
    trade_keys: &Keys,
    mostro_pubkey: &PublicKey,
    order_id: &str,
    trade_index: u32,
) -> Result<String> {
    simple_action(
        identity_keys,
        trade_keys,
        mostro_pubkey,
        order_id,
        trade_index,
        Action::Cancel,
    )
    .await
}

/// Build and wrap a Dispute MostroMessage.
///
/// `request_id` is the correlation nonce the daemon echoes in its reply
/// (`DisputeInitiatedByYou` or `CantDo`); `open_dispute` relies on it to tell
/// the genuine reply apart from stale relay-replayed events. This is why the
/// message is built here instead of through `simple_action`, which sends no
/// nonce.
pub async fn dispute(
    identity_keys: &Keys,
    trade_keys: &Keys,
    mostro_pubkey: &PublicKey,
    order_id: &str,
    trade_index: u32,
    request_id: u64,
) -> Result<String> {
    let id = Uuid::parse_str(order_id)?;
    let msg = Message::new_order(
        Some(id),
        Some(request_id),
        Some(trade_index as i64),
        Action::Dispute,
        None,
    );
    wrap_message(identity_keys, trade_keys, mostro_pubkey, &msg).await
}

/// Build and wrap a RateUser MostroMessage.
///
/// Sends a 1–5 star rating for the counterparty to the Mostro daemon via
/// the transport-v2 (NIP-44, signed Kind 14) wrap after a trade completes.
pub async fn rate_user(
    identity_keys: &Keys,
    trade_keys: &Keys,
    mostro_pubkey: &PublicKey,
    order_id: &str,
    trade_index: u32,
    score: u8,
) -> Result<String> {
    let id = Uuid::parse_str(order_id)?;
    let payload = Some(Payload::RatingUser(score));
    let msg = Message::new_order(
        Some(id),
        None,
        Some(trade_index as i64),
        Action::RateUser,
        payload,
    );
    wrap_message(identity_keys, trade_keys, mostro_pubkey, &msg).await
}

/// Build and wrap an AddInvoice MostroMessage (buyer submits Lightning invoice
/// or LN address).
///
/// For bolt11 invoices the amount is already encoded in the invoice itself, so
/// the third payload field is `None`.  For Lightning Addresses Mostro needs the
/// sats amount in the payload so it can resolve the address and generate the
/// invoice on behalf of the buyer — pass it via `amount_sats`.
///
/// `request_id` is the correlation nonce the daemon echoes in its reply
/// (progression message or CantDo); `send_invoice` relies on it to tell the
/// genuine reply apart from stale relay-replayed events.
#[allow(clippy::too_many_arguments)]
pub async fn add_invoice(
    identity_keys: &Keys,
    trade_keys: &Keys,
    mostro_pubkey: &PublicKey,
    order_id: &str,
    trade_index: u32,
    invoice: &str,
    amount_sats: Option<u64>,
    request_id: u64,
) -> Result<String> {
    let id = Uuid::parse_str(order_id)?;
    // A Lightning Address contains '@'; a bolt11 invoice does not.
    let is_ln_address = invoice.contains('@');
    let amount_field: Option<i64> = if is_ln_address {
        amount_sats.map(|a| a as i64)
    } else {
        None
    };
    let payload = Some(Payload::PaymentRequest(None, invoice.to_string(), amount_field));
    let msg = Message::new_order(
        Some(id),
        Some(request_id),
        Some(trade_index as i64),
        Action::AddInvoice,
        payload,
    );
    wrap_message(identity_keys, trade_keys, mostro_pubkey, &msg).await
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Internal helper for take-buy / take-sell actions.
///
/// `request_id` is the caller-generated correlation nonce: the daemon echoes
/// it in its reply (add-invoice, pay-invoice, pay-bond-invoice, or CantDo),
/// which is how `take_order` tells the genuine reply apart from stale
/// relay-replayed events addressed to the same trade key.
#[allow(clippy::too_many_arguments)]
async fn take_order_impl(
    identity_keys: &Keys,
    trade_keys: &Keys,
    mostro_pubkey: &PublicKey,
    order_id: &str,
    trade_index: u32,
    amount: Option<f64>,
    ln_address: Option<&str>,
    action: Action,
    request_id: u64,
) -> Result<String> {
    let id = Uuid::parse_str(order_id)?;

    let payload = match (amount, ln_address) {
        // LN address + optional range amount
        (amt, Some(addr)) => Some(Payload::PaymentRequest(
            None,
            addr.to_string(),
            amt.map(|a| a as i64),
        )),
        // Range amount only (no LN address)
        (Some(amt), None) => Some(Payload::Amount(amt as i64)),
        // Standard fixed-amount take
        (None, None) => None,
    };

    let msg = Message::new_order(
        Some(id),
        Some(request_id),
        Some(trade_index as i64),
        action,
        payload,
    );
    wrap_message_first_contact(identity_keys, trade_keys, mostro_pubkey, &msg).await
}

/// Helper for actions that only need an order ID and no additional payload.
async fn simple_action(
    identity_keys: &Keys,
    trade_keys: &Keys,
    mostro_pubkey: &PublicKey,
    order_id: &str,
    trade_index: u32,
    action: Action,
) -> Result<String> {
    let id = Uuid::parse_str(order_id)?;
    let msg = Message::new_order(Some(id), None, Some(trade_index as i64), action, None);
    wrap_message(identity_keys, trade_keys, mostro_pubkey, &msg).await
}

/// Wrap `msg` as a transport-v2 (NIP-44, signed Kind 14) event via
/// `transport::wrap_mostro_message`, applying the daemon-advertised PoW
/// difficulty, and return the event JSON.
async fn wrap_message(
    identity_keys: &Keys,
    trade_keys: &Keys,
    mostro_pubkey: &PublicKey,
    msg: &Message,
) -> Result<String> {
    wrap_message_at(
        identity_keys,
        trade_keys,
        mostro_pubkey,
        msg,
        crate::mostro::pow::get_pow(),
    )
    .await
}

/// [`wrap_message`] for a **first-contact** event — one whose visible sender is
/// a trade key the daemon does not yet associate with an active order or
/// dispute: creating an order, taking one, or a restore under a fresh trade
/// key. Those pay `pow_first_contact`, which is never lower than `pow` and is
/// typically higher; mining such an event at `pow` gets it dropped before the
/// daemon decrypts anything, with no reply of any kind, so the caller sees only
/// a timeout (issue #177).
///
/// The difficulty must come from a capability snapshot fetched *from
/// `mostro_pubkey`*: at startup none exists yet, and right after a node switch
/// the store still holds the previous node's values. `first_contact_pow_for`
/// waits for the right generation and fails closed (`PowUnknown`) if it never
/// arrives, rather than mine at a difficulty that may be silently rejected.
async fn wrap_message_first_contact(
    identity_keys: &Keys,
    trade_keys: &Keys,
    mostro_pubkey: &PublicKey,
    msg: &Message,
) -> Result<String> {
    let pow = crate::mostro::pow::first_contact_pow_for(&mostro_pubkey.to_hex()).await?;
    wrap_message_at(identity_keys, trade_keys, mostro_pubkey, msg, pow).await
}

async fn wrap_message_at(
    identity_keys: &Keys,
    trade_keys: &Keys,
    mostro_pubkey: &PublicKey,
    msg: &Message,
    pow: u8,
) -> Result<String> {
    // A node speaking a different wire protocol never decrypts what we send
    // and never answers, so every caller would time out with no way to tell
    // that apart from an unreachable daemon. Refuse up front — for every
    // daemon-bound wrap, first-contact or not — with a marker Dart localizes.
    // Protocol v1 (gift wrap) is being removed, not implemented: this client
    // is v2-native, and the fix for such a node is to run a v2 daemon.
    crate::mostro::protocol_version::ensure_supported(&mostro_pubkey.to_hex()).await?;

    let event =
        transport::wrap_mostro_message(identity_keys, trade_keys, mostro_pubkey, msg, pow).await?;
    Ok(event.as_json())
}

/// Build a `RestoreSession` request (mostro-core `Message::new_restore`).
///
/// Payload MUST be `None` — the daemon rejects any other payload
/// (`MessageKind::verify`). The Seal is signed by the identity key (used by
/// the daemon to look up the user's trades); the rumor is signed by a fresh
/// trade key, and the daemon's restore reply is addressed to that trade key.
/// Returns the transport-v2 (NIP-44, signed Kind 14) event JSON.
pub async fn restore_session(
    identity_keys: &Keys,
    trade_keys: &Keys,
    mostro_pubkey: &PublicKey,
) -> Result<String> {
    // identity_keys sign the Seal (-> event.identity = master key, used by the
    // daemon to look up the user's trades); trade_keys sign the rumor
    // (-> event.sender, the key the daemon replies to). Mirrors new_order.
    let msg = Message::new_restore(None);
    wrap_message_first_contact(identity_keys, trade_keys, mostro_pubkey, &msg).await
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The NIP-13 target difficulty the event was mined at, read from its
    /// nonce tag (`["nonce", "<nonce>", "<target>"]`), or `None` when the
    /// event was not mined at all.
    fn mined_target(json: &str) -> Option<String> {
        let event = Event::from_json(json).unwrap();
        event.tags.iter().find_map(|t| {
            let tag = t.as_slice();
            (tag.first().map(String::as_str) == Some("nonce"))
                .then(|| tag.get(2).cloned())
                .flatten()
        })
    }

    fn sample_params() -> NewOrderParams {
        NewOrderParams {
            kind: OrderKind::Sell,
            fiat_amount: Some(100.0),
            fiat_amount_min: None,
            fiat_amount_max: None,
            fiat_code: "USD".to_string(),
            payment_method: "cashapp".to_string(),
            premium: 0.0,
            amount_sats: None,
        }
    }

    /// Directed PoW-selection coverage (issue #177): create, take, and restore
    /// are first-contact events — their visible sender is a trade key the
    /// daemon does not know yet — so they must mine at `first_contact_pow()`,
    /// not the base difficulty. Distinct values (1 vs 4) make the nonce tag
    /// betray which one was selected; both are low enough to mine instantly.
    #[tokio::test]
    async fn create_take_and_restore_mine_at_the_first_contact_difficulty() {
        use std::time::Duration;

        let identity_keys = Keys::generate();
        let trade_keys = Keys::generate();
        let mostro_pubkey = Keys::generate().public_key();
        let order_id = "94486ae3-4083-4dfe-b543-53fe761025e9";

        let _pow = crate::mostro::pow::test_support::lock_pow();
        crate::mostro::pow::set_pows(&mostro_pubkey.to_hex(), 1, Some(4));
        crate::mostro::protocol_version::set_protocol_version(&mostro_pubkey.to_hex(), Some(2));

        // Mining is probabilistic — cap wall time so a regression that stalls
        // does not hang CI indefinitely.
        let wraps = crate::rt::time::timeout(Duration::from_secs(60), async {
            let create = new_order(
                &identity_keys,
                &trade_keys,
                &mostro_pubkey,
                &sample_params(),
                3,
                42,
            )
            .await
            .unwrap();
            let take = take_sell(
                &identity_keys,
                &trade_keys,
                &mostro_pubkey,
                order_id,
                5,
                None,
                None,
                77,
            )
            .await
            .unwrap();
            let restore = restore_session(&identity_keys, &trade_keys, &mostro_pubkey)
                .await
                .unwrap();
            [("create", create), ("take", take), ("restore", restore)]
        })
        .await
        .expect("first-contact wraps timed out");

        for (name, json) in wraps {
            assert_eq!(
                mined_target(&json).as_deref(),
                Some("4"),
                "{name} must mine at first_contact_pow(), not the base pow"
            );
        }
    }

    /// The counterpart: an action on an order the daemon already knows the
    /// trade key for pays only the base `pow`, never `pow_first_contact`.
    #[tokio::test]
    async fn generic_actions_mine_at_the_base_difficulty() {
        use std::time::Duration;

        let identity_keys = Keys::generate();
        let trade_keys = Keys::generate();
        let mostro_pubkey = Keys::generate().public_key();

        let _pow = crate::mostro::pow::test_support::lock_pow();
        crate::mostro::pow::set_pows(&mostro_pubkey.to_hex(), 1, Some(4));
        crate::mostro::protocol_version::set_protocol_version(&mostro_pubkey.to_hex(), Some(2));

        let json = crate::rt::time::timeout(
            Duration::from_secs(60),
            fiat_sent(
                &identity_keys,
                &trade_keys,
                &mostro_pubkey,
                "94486ae3-4083-4dfe-b543-53fe761025e9",
                5,
            ),
        )
        .await
        .expect("generic wrap timed out")
        .unwrap();

        assert_eq!(
            mined_target(&json).as_deref(),
            Some("1"),
            "a generic action must mine at get_pow()"
        );
    }

    /// The outgoing new-order message must carry the caller's request_id —
    /// it is the correlation nonce the daemon echoes in its reply, and
    /// `create_order` relies on it to tell the genuine reply apart from
    /// stale relay-replayed events.
    #[tokio::test]
    async fn new_order_carries_request_id_and_trade_index() {
        let identity_keys = Keys::generate();
        let trade_keys = Keys::generate();
        let mostro_keys = Keys::generate();

        // First-contact wrapping fails closed until this node's capabilities
        // are published — a test double for the Kind 38385 fetch.
        let _pow = crate::mostro::pow::test_support::lock_pow();
        crate::mostro::pow::set_pows(&mostro_keys.public_key().to_hex(), 0, None);
        crate::mostro::protocol_version::set_protocol_version(
            &mostro_keys.public_key().to_hex(),
            Some(2),
        );

        let params = NewOrderParams {
            kind: OrderKind::Sell,
            fiat_amount: Some(100.0),
            fiat_amount_min: None,
            fiat_amount_max: None,
            fiat_code: "USD".to_string(),
            payment_method: "cashapp".to_string(),
            premium: 0.0,
            amount_sats: None,
        };

        let json = new_order(
            &identity_keys,
            &trade_keys,
            &mostro_keys.public_key(),
            &params,
            3,
            42,
        )
        .await
        .unwrap();

        let event = Event::from_json(&json).unwrap();
        let unwrapped = transport::unwrap_mostro_message(&mostro_keys, &event)
            .await
            .unwrap()
            .expect("message must decrypt for the recipient");

        let kind = unwrapped.message.get_inner_message_kind();
        assert_eq!(kind.request_id, Some(42));
        assert_eq!(kind.trade_index, Some(3));
        assert!(matches!(kind.action, Action::NewOrder));
    }

    /// The outgoing take messages must carry the caller's request_id — the
    /// correlation nonce the daemon echoes in its reply (add-invoice,
    /// pay-invoice, pay-bond-invoice, or CantDo) that `take_order` relies on
    /// to tell the genuine reply apart from stale relay-replayed events.
    #[tokio::test]
    async fn take_messages_carry_request_id_and_order_id() {
        let identity_keys = Keys::generate();
        let trade_keys = Keys::generate();
        let mostro_keys = Keys::generate();
        let order_id = "94486ae3-4083-4dfe-b543-53fe761025e9";

        // First-contact wrapping fails closed until this node's capabilities
        // are published — a test double for the Kind 38385 fetch.
        let _pow = crate::mostro::pow::test_support::lock_pow();
        crate::mostro::pow::set_pows(&mostro_keys.public_key().to_hex(), 0, None);
        crate::mostro::protocol_version::set_protocol_version(
            &mostro_keys.public_key().to_hex(),
            Some(2),
        );

        let json = take_sell(
            &identity_keys,
            &trade_keys,
            &mostro_keys.public_key(),
            order_id,
            5,
            None,
            None,
            77,
        )
        .await
        .unwrap();

        let event = Event::from_json(&json).unwrap();
        let unwrapped = transport::unwrap_mostro_message(&mostro_keys, &event)
            .await
            .unwrap()
            .expect("message must decrypt for the recipient");

        let kind = unwrapped.message.get_inner_message_kind();
        assert_eq!(kind.request_id, Some(77));
        assert_eq!(kind.trade_index, Some(5));
        assert_eq!(kind.id.map(|u| u.to_string()).as_deref(), Some(order_id));
        assert!(matches!(kind.action, Action::TakeSell));

        let json = take_buy(
            &identity_keys,
            &trade_keys,
            &mostro_keys.public_key(),
            order_id,
            6,
            Some(100.0),
            78,
        )
        .await
        .unwrap();

        let event = Event::from_json(&json).unwrap();
        let unwrapped = transport::unwrap_mostro_message(&mostro_keys, &event)
            .await
            .unwrap()
            .expect("message must decrypt for the recipient");

        let kind = unwrapped.message.get_inner_message_kind();
        assert_eq!(kind.request_id, Some(78));
        assert!(matches!(kind.action, Action::TakeBuy));
        assert!(matches!(kind.payload, Some(Payload::Amount(100))));
    }

    /// The outgoing Dispute message must carry the caller's request_id: it is
    /// the nonce the daemon echoes in `DisputeInitiatedByYou` and in `CantDo`,
    /// and `open_dispute` persists nothing without a reply carrying it. A
    /// serialization regression here would otherwise show up only as a 10 s
    /// `NoDaemonResponse` (PR #275 review).
    #[tokio::test]
    async fn dispute_carries_request_id_order_id_and_no_payload() {
        let identity_keys = Keys::generate();
        let trade_keys = Keys::generate();
        let mostro_keys = Keys::generate();
        let order_id = "94486ae3-4083-4dfe-b543-53fe761025e9";

        // First-contact wrapping fails closed until this node's capabilities
        // are published — a test double for the Kind 38385 fetch.
        let _pow = crate::mostro::pow::test_support::lock_pow();
        crate::mostro::pow::set_pows(&mostro_keys.public_key().to_hex(), 0, None);
        crate::mostro::protocol_version::set_protocol_version(
            &mostro_keys.public_key().to_hex(),
            Some(2),
        );

        let json = dispute(
            &identity_keys,
            &trade_keys,
            &mostro_keys.public_key(),
            order_id,
            9,
            4242,
        )
        .await
        .unwrap();

        let event = Event::from_json(&json).unwrap();
        let unwrapped = transport::unwrap_mostro_message(&mostro_keys, &event)
            .await
            .unwrap()
            .expect("message must decrypt for the recipient");

        let kind = unwrapped.message.get_inner_message_kind();
        assert_eq!(kind.request_id, Some(4242));
        assert_eq!(kind.trade_index, Some(9));
        assert_eq!(kind.id.map(|u| u.to_string()).as_deref(), Some(order_id));
        assert!(matches!(kind.action, Action::Dispute));
        assert!(kind.payload.is_none(), "Dispute payload must be None");
        // The rumor is authored by the trade key: that is the pubkey the daemon
        // addresses its reply to, and the key open_dispute correlates on.
        assert_eq!(unwrapped.sender, trade_keys.public_key());
    }

    /// #215 handshake contract: a RestoreSession carries no payload (the daemon
    /// rejects anything else in `MessageKind::verify`), its action is
    /// `RestoreSession`, and the rumor is authored by the trade key — the
    /// `event.sender` the daemon addresses its RestoreData reply to.
    #[tokio::test]
    async fn restore_session_payload_none_action_restore_rumor_by_trade_key() {
        let identity_keys = Keys::generate();
        let trade_keys = Keys::generate();
        let mostro_keys = Keys::generate();

        // First-contact wrapping fails closed until this node's capabilities
        // are published — a test double for the Kind 38385 fetch.
        let _pow = crate::mostro::pow::test_support::lock_pow();
        crate::mostro::pow::set_pows(&mostro_keys.public_key().to_hex(), 0, None);
        crate::mostro::protocol_version::set_protocol_version(
            &mostro_keys.public_key().to_hex(),
            Some(2),
        );

        let json = restore_session(&identity_keys, &trade_keys, &mostro_keys.public_key())
            .await
            .unwrap();
        let event = Event::from_json(&json).unwrap();
        let unwrapped = transport::unwrap_mostro_message(&mostro_keys, &event)
            .await
            .unwrap()
            .expect("message must decrypt for the recipient");
        let kind = unwrapped.message.get_inner_message_kind();
        assert!(kind.payload.is_none(), "RestoreSession payload must be None");
        assert!(matches!(kind.action, Action::RestoreSession));
        // The rumor is authored by the trade key: that is the pubkey the daemon
        // replies to, and what the client subscribes/correlates on.
        assert_eq!(unwrapped.sender, trade_keys.public_key());
        // The Seal carries the identity key: that is what the daemon uses to
        // locate the user's trades. Both halves of the key split matter.
        assert_eq!(unwrapped.identity, identity_keys.public_key());
    }
}

