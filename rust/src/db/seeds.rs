/// First-launch seed data — populates default relays and Mostro node.
///
/// Called once after DB migration, before relay pool initialization.
/// All operations are idempotent (IF NOT EXISTS / skip-if-present).
use anyhow::Result;

use crate::api::types::{MostroNodeInfo, RelayInfo, RelaySource, RelayStatus};
use crate::config;
use crate::db::Storage;

/// Seed default relays and the default Mostro node if not already present.
pub async fn seed_defaults<S: Storage>(storage: &S) -> Result<()> {
    seed_default_relays(storage).await?;
    seed_default_mostro_node(storage).await?;
    Ok(())
}

/// Seed `DEFAULT_RELAYS` into the relay table if no relays exist yet.
async fn seed_default_relays<S: Storage>(storage: &S) -> Result<()> {
    let existing = storage.list_relays().await?;
    if !existing.is_empty() {
        return Ok(());
    }

    for url in config::DEFAULT_RELAYS {
        let relay = RelayInfo {
            url: url.to_string(),
            is_active: true,
            is_default: true,
            source: RelaySource::Default,
            is_blacklisted: false,
            status: RelayStatus::Disconnected,
            last_connected_at: None,
            last_error: None,
        };
        storage.save_relay(&relay).await?;
    }

    Ok(())
}

/// Seed the default Mostro node if no active node is configured.
async fn seed_default_mostro_node<S: Storage>(storage: &S) -> Result<()> {
    if storage.get_active_mostro_node().await?.is_some() {
        return Ok(());
    }
    let node = get_default_mostro_node();
    storage.save_mostro_node(&node).await?;
    log::info!("[seeds] default Mostro node seeded: {}", node.pubkey);
    Ok(())
}

/// Get the default Mostro node info from compiled constants.
pub fn get_default_mostro_node() -> MostroNodeInfo {
    MostroNodeInfo {
        pubkey: config::DEFAULT_MOSTRO_PUBKEY.to_string(),
        name: Some(config::DEFAULT_MOSTRO_NAME.to_string()),
        version: None,
        expiration_hours: 24,
        expiration_seconds: 900,
        fee_pct: None,
        max_order_amount: None,
        min_order_amount: None,
        supported_currencies: None,
        ln_node_id: None,
        ln_node_alias: None,
        is_active: true,
    }
}
