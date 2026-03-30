/// Mostro action dispatch — builds and wraps MostroMessages.
///
/// Each function constructs a `MostroMessage` JSON payload and wraps it
/// via NIP-59 Gift Wrap, returning the event JSON ready for publication.
use anyhow::Result;
use nostr_sdk::prelude::*;
use serde_json::json;

use crate::api::types::OrderKind;
use crate::nostr::gift_wrap;

/// Kind used for Mostro direct messages (NIP-59 inner rumor).
const MOSTRO_DM_KIND: u16 = 38383;

/// Parameters for creating a new order.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct NewOrderParams {
    pub kind: OrderKind,
    pub fiat_amount: Option<f64>,
    pub fiat_amount_min: Option<f64>,
    pub fiat_amount_max: Option<f64>,
    pub fiat_code: String,
    pub payment_method: String,
    pub premium: f64,
    pub amount_sats: Option<u64>,
}

/// Build and wrap a NewOrder MostroMessage.
///
/// Returns the NIP-59 Gift Wrap event JSON ready for publication.
pub async fn new_order(
    sender_keys: &Keys,
    mostro_pubkey: &PublicKey,
    params: &NewOrderParams,
) -> Result<String> {
    let order_content = build_new_order_content(params);
    let payload = json!({
        "order": {
            "version": 1,
            "action": "new-order",
            "content": {
                "order": order_content,
            }
        }
    });

    gift_wrap::wrap(
        sender_keys,
        mostro_pubkey,
        &payload.to_string(),
        Kind::from(MOSTRO_DM_KIND),
    )
    .await
}

/// Build and wrap a TakeBuy MostroMessage.
pub async fn take_buy(
    sender_keys: &Keys,
    mostro_pubkey: &PublicKey,
    order_id: &str,
    amount: Option<f64>,
) -> Result<String> {
    let mut content = json!({ "id": order_id });
    if let Some(amt) = amount {
        content["amount"] = json!(amt);
    }

    let payload = json!({
        "order": {
            "version": 1,
            "action": "take-buy",
            "content": content,
        }
    });

    gift_wrap::wrap(
        sender_keys,
        mostro_pubkey,
        &payload.to_string(),
        Kind::from(MOSTRO_DM_KIND),
    )
    .await
}

/// Build and wrap a TakeSell MostroMessage.
pub async fn take_sell(
    sender_keys: &Keys,
    mostro_pubkey: &PublicKey,
    order_id: &str,
    amount: Option<f64>,
) -> Result<String> {
    let mut content = json!({ "id": order_id });
    if let Some(amt) = amount {
        content["amount"] = json!(amt);
    }

    let payload = json!({
        "order": {
            "version": 1,
            "action": "take-sell",
            "content": content,
        }
    });

    gift_wrap::wrap(
        sender_keys,
        mostro_pubkey,
        &payload.to_string(),
        Kind::from(MOSTRO_DM_KIND),
    )
    .await
}

// ── Helpers ─────────────────────────────────────────────────────────────────

fn build_new_order_content(params: &NewOrderParams) -> serde_json::Value {
    let kind_str = match params.kind {
        OrderKind::Buy => "buy",
        OrderKind::Sell => "sell",
    };

    let mut order = json!({
        "kind": kind_str,
        "fiat_code": params.fiat_code,
        "payment_method": params.payment_method,
        "premium": params.premium,
    });

    if let Some(amt) = params.fiat_amount {
        order["fiat_amount"] = json!(amt);
    }
    if let Some(min) = params.fiat_amount_min {
        order["fiat_amount_min"] = json!(min);
    }
    if let Some(max) = params.fiat_amount_max {
        order["fiat_amount_max"] = json!(max);
    }
    if let Some(sats) = params.amount_sats {
        order["amount"] = json!(sats);
    }

    order
}
