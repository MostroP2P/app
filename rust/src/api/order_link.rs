//! Opening a `mostro:` order link: the format and the lookup are in
//! `nostr::order_link`; this is what the app asks of them.

use anyhow::{anyhow, Result};
use nostr_sdk::prelude::PublicKey;

use crate::api::types::OrderInfo;
use crate::nostr::order_events::parse_order_event;
use crate::nostr::order_link::{find_order_event, OrderLink};

/// The order a `mostro:` link points at, as its node publishes it now.
#[derive(Debug, Clone)]
pub struct OrderLinkTarget {
    /// The newest revision of the order. Its `status` says whether it can
    /// still be taken, its `kind` which side the taker would be on.
    pub order: OrderInfo,
    /// Hex public key of the node that published it.
    pub node_pubkey: String,
    /// Whether that node is the active one. When it is not, nothing was
    /// changed: the caller asks the user before switching nodes, then
    /// resolves the link again.
    pub on_active_node: bool,
}

/// Find the order a `mostro:` link points at.
///
/// The node is the link's `mostro=`, or the active node for a link that
/// names none (daemons before mostro#678). The order is looked up on the
/// pool's relays and on the link's own, which never join the pool. On the
/// active node it is also filed in the order book, through the path the live
/// subscription takes, so Take Order shows it without waiting for the book's
/// feed to reach it — or ever, when only the link's relays hold it.
///
/// **Errors**: `InvalidOrderLink` when the link cannot be read,
/// `OrderLinkNotFound` when no relay answered with the order.
pub async fn resolve_order_link(link: String) -> Result<OrderLinkTarget> {
    let link = OrderLink::parse(&link)?;
    let node = match link.node {
        Some(node) => node,
        None => PublicKey::from_hex(&crate::config::active_mostro_pubkey())?,
    };

    let pool = crate::api::nostr::get_pool().ok().map(|pool| pool.client());
    let pool_relays: Vec<String> = match &pool {
        Some(client) => client
            .relays()
            .await
            .into_keys()
            .map(|url| url.to_string())
            .collect(),
        None => Vec::new(),
    };
    let event = find_order_event(
        pool.as_deref(),
        &link.relays_outside(&pool_relays),
        &node,
        &link.order_id,
    )
    .await
    .ok_or_else(|| anyhow!("OrderLinkNotFound: {}", link.order_id))?;
    let order = parse_order_event(&event, None).ok_or_else(|| {
        anyhow!(
            "OrderLinkNotFound: {} is not a readable order",
            link.order_id
        )
    })?;

    // Read after the lookup: the user may have switched nodes meanwhile, and
    // the book holds the active node's orders only.
    let node_pubkey = node.to_hex();
    let on_active_node = node_pubkey == crate::config::active_mostro_pubkey();
    if on_active_node {
        crate::api::orders::ingest_order_event(&event).await;
    }
    Ok(OrderLinkTarget {
        order,
        node_pubkey,
        on_active_node,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Dart maps the marker to its message; nothing reaches a relay first.
    #[tokio::test]
    async fn an_unreadable_link_is_refused_by_its_marker() {
        let err = resolve_order_link("mostro:not-an-order?relays=wss://nos.lol".into())
            .await
            .unwrap_err();

        assert!(err.to_string().starts_with("InvalidOrderLink"), "{err}");
    }
}
