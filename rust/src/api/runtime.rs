/// Shared application runtime — single global state for native platforms.
///
/// Holds the open SQLite connection, in-memory master key, and the relay pool.
/// All API modules (identity, nostr, orders, …) lock this mutex before
/// accessing storage or network state.
///
/// WASM variant: IndexedDB storage, no RelayPool (uses wasm futures instead).
/// Currently only the native variant is fully wired; WASM will follow in Phase 4.
#[cfg(not(target_arch = "wasm32"))]
pub(crate) mod native {
    use std::sync::{Arc, OnceLock};
    use tokio::sync::Mutex;

    use crate::storage::sqlite::SqliteStorage;

    #[flutter_rust_bridge::frb(ignore)]
    pub(crate) struct AppRuntime {
        pub storage: SqliteStorage,
        /// In-memory session master key.  Set by `unlock_with_master_key` or
        /// implicitly by `create_identity` / `import_from_*`.
        /// `None` means the identity is locked (app just launched, no key yet).
        pub master_key: Option<[u8; 32]>,
        /// Cached identity public key (avoids decrypting privkey just for pubkey).
        pub identity_pubkey: Option<String>,
        /// Live relay pool — `None` until `initialize_nostr()` is called.
        /// Wrapped in Arc so the notification-pump task can share ownership.
        pub relay_pool: Option<Arc<crate::network::relay_pool::RelayPool>>,
    }

    static RUNTIME: OnceLock<Mutex<Option<AppRuntime>>> = OnceLock::new();

    pub(crate) fn runtime_lock() -> &'static Mutex<Option<AppRuntime>> {
        RUNTIME.get_or_init(|| Mutex::new(None))
    }
}
