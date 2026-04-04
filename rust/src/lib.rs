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
/// messages appear in `adb logcat` / stderr and are forwarded to the Flutter
/// log stream via `BridgeLogger`.
#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    // Install the log bridge so every log::info!/warn!/error! is forwarded
    // to the Flutter on_log_entry() stream AND printed to stderr (logcat on
    // Android).  Must be called before any other log::set_logger() call.
    api::logging::install_log_bridge();

    log::info!("[init] Rust core initialized");
}

