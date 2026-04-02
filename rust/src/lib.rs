mod frb_generated; /* AUTO INJECTED BY flutter_rust_bridge. This line may not be accurate, and you can change it according to your needs. */
// Mostro Mobile v2 — Rust core
// All Nostr protocol handling, NIP-59, BIP-32 key derivation,
// NWC wallet integration, and relay communication live here.
// Zero crypto in Dart — this is the only source of trust.

pub mod api;
pub mod config;
pub mod crypto;
pub mod db;
pub mod mostro;
pub mod nostr;
pub mod nwc;
pub mod queue;

/// Called once by Flutter during `RustLib.init()` — sets up logging so Rust
/// messages appear in `adb logcat` under the tag `mostro_rust`.
#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    #[cfg(target_os = "android")]
    android_logger::init_once(
        android_logger::Config::default()
            .with_max_level(log::LevelFilter::Debug)
            .with_tag("mostro_rust"),
    );
    log::info!("[init] Rust core initialized");
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
