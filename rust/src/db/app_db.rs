/// Global persistent-storage singleton.
///
/// Flutter calls [`init_db`] once on startup with the platform-specific
/// database path.  All Rust API functions that need persistence call [`db()`]
/// to obtain a reference.  If the DB has not been initialised yet (e.g. during
/// unit tests or early in the startup sequence) the call returns `None` and the
/// caller falls back to the in-memory cache.
use anyhow::Result;
use tokio::sync::OnceCell;

#[cfg(not(target_arch = "wasm32"))]
use crate::db::sqlite::SqliteStorage as AppStorage;
#[cfg(target_arch = "wasm32")]
use crate::db::indexeddb::IndexedDbStorage as AppStorage;

static APP_DB: OnceCell<AppStorage> = OnceCell::const_new();

/// The `path` [`init_db`] was called with, kept so other stores can place their
/// own files next to it without a second call from Dart. Device paths are
/// Dart's job (repo architecture rule); deriving a sibling name from one is not.
static APP_DB_PATH: std::sync::OnceLock<String> = std::sync::OnceLock::new();

/// Initialise the persistent store with the given `path`.
///
/// On native platforms `path` is the absolute path to the SQLite file (e.g.
/// `<app_documents>/mostro.db`).  On WASM the argument is used as the
/// IndexedDB database name.
///
/// Subsequent calls are no-ops — the singleton is only written once.
pub async fn init_db(path: &str) -> Result<()> {
    APP_DB
        .get_or_try_init(|| async { AppStorage::open(path).await })
        .await?;
    // Recorded only after the store opened, so a failed init leaves no path
    // behind for a sibling store to build on.
    let _ = APP_DB_PATH.set(path.to_string());
    log::info!("[db] persistent store ready (path={})", path);
    Ok(())
}

/// The path [`init_db`] was given, or `None` before it succeeded.
///
/// Callers that need their own file (e.g. the Cashu proof store) derive a
/// sibling name from it rather than asking Dart for a second path.
pub(crate) fn app_db_path() -> Option<&'static str> {
    APP_DB_PATH.get().map(String::as_str)
}

/// Return a reference to the initialised storage, or `None` if [`init_db`]
/// has not been called yet.
pub(crate) fn db() -> Option<&'static AppStorage> {
    APP_DB.get()
}
