pub mod disputes;
pub mod identity;
pub mod logging;
pub mod messages;
pub mod nostr;
pub mod nwc;
pub mod orders;
pub mod reputation;
pub mod settings;
pub mod types;

pub fn get_app_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

/// Initialise the persistent store.
///
/// Must be called once on app startup **before** taking orders or sending
/// invoices.  On native platforms pass the absolute path to the SQLite file
/// (e.g. `<app_documents_dir>/mostro.db`).  On WASM `path` is used as the
/// IndexedDB database name.
///
/// Subsequent calls are no-ops.
pub async fn init_db(path: String) -> anyhow::Result<()> {
    crate::db::app_db::init_db(&path).await
}
