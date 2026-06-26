/// First-launch seed data — populates default relays and Mostro node.
///
/// Called once after DB migration, before relay pool initialization.
/// All operations are idempotent (IF NOT EXISTS / skip-if-present).
use anyhow::Result;

use crate::api::types::{RelayInfo, RelaySource, RelayStatus};
use crate::config;
use crate::db::Storage;

/// Seed default relays if not already present.
pub async fn seed_defaults<S: Storage>(storage: &S) -> Result<()> {
    seed_default_relays(storage).await?;
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
