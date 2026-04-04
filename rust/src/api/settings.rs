/// Settings API — user preferences management.
///
/// Holds the in-memory settings store and exposes typed getters/setters
/// that validate inputs before accepting them.  Changes are broadcast to
/// any active [`SettingsStream`] so the UI can react without polling.
use anyhow::{bail, Result};
use std::sync::OnceLock;
use tokio::sync::{broadcast, RwLock};
use tokio::sync::broadcast::error::RecvError;

use crate::api::types::{AppSettings, ThemeMode};
use crate::db::Storage;

// ── SettingsStore ─────────────────────────────────────────────────────────────

struct SettingsStore {
    settings: RwLock<AppSettings>,
    tx: broadcast::Sender<AppSettings>,
}

impl SettingsStore {
    fn new() -> Self {
        let (tx, _) = broadcast::channel(32);
        Self {
            settings: RwLock::new(AppSettings {
                theme: ThemeMode::Dark,
                language: "en".to_string(),
                default_fiat_code: None,
                default_lightning_address: None,
                logging_enabled: false,
                privacy_mode: false,
            }),
            tx,
        }
    }

    async fn read(&self) -> AppSettings {
        let mut s = self.settings.read().await.clone();
        // Sync privacy_mode from authoritative source.
        s.privacy_mode = crate::api::reputation::get_privacy_mode();
        s
    }

    async fn write_with<F>(&self, f: F) -> AppSettings
    where
        F: FnOnce(&mut AppSettings),
    {
        let mut guard = self.settings.write().await;
        f(&mut guard);
        let mut snapshot = guard.clone();
        snapshot.privacy_mode = crate::api::reputation::get_privacy_mode();
        snapshot
    }

    fn notify(&self, snapshot: AppSettings) {
        let _ = self.tx.send(snapshot);
    }
}

// ── Global singleton ──────────────────────────────────────────────────────────

static SETTINGS_STORE: OnceLock<SettingsStore> = OnceLock::new();

fn store() -> &'static SettingsStore {
    SETTINGS_STORE.get_or_init(SettingsStore::new)
}

// ── Validation helpers ────────────────────────────────────────────────────────

/// Supported BCP-47 language codes.
///
/// **Keep in sync** with the Flutter side: `AppLocalizations.supportedLocales`
/// in `lib/l10n/` (or the `flutter_localizations` delegate configuration).
/// Both lists must be updated together when adding a new language.
const SUPPORTED_LOCALES: &[&str] = &["en", "es", "it", "fr", "de"];

fn validate_locale(locale: &str) -> Result<()> {
    if SUPPORTED_LOCALES.contains(&locale) {
        Ok(())
    } else {
        bail!(
            "UnsupportedLocale: '{}' is not supported; must be one of {:?}",
            locale,
            SUPPORTED_LOCALES
        )
    }
}

/// Validates an ISO 4217 fiat code: exactly 3 uppercase ASCII letters.
fn validate_fiat_code(code: &str) -> Result<()> {
    let valid = code.len() == 3 && code.chars().all(|c| c.is_ascii_uppercase());
    if valid {
        Ok(())
    } else {
        bail!(
            "InvalidFiatCode: '{}' must be exactly 3 uppercase ASCII letters (ISO 4217)",
            code
        )
    }
}

/// Validates a Lightning Address in `user@domain` format.
///
/// Requires exactly one `@`, a non-empty local part, and a domain that
/// contains at least one dot with no empty labels and only ASCII
/// alphanumeric/hyphen characters.
fn validate_lightning_address(address: &str) -> Result<()> {
    let trimmed = address.trim();
    let parts: Vec<&str> = trimmed.split('@').collect();
    if parts.len() == 2 && !parts[0].is_empty() && !parts[1].is_empty() {
        let domain = parts[1];
        let labels: Vec<&str> = domain.split('.').collect();
        let valid_domain = labels.len() >= 2
            && labels.iter().all(|label| {
                !label.is_empty()
                    && label.len() <= 63
                    && label
                        .chars()
                        .all(|c| c.is_ascii_alphanumeric() || c == '-')
                    && !label.starts_with('-')
                    && !label.ends_with('-')
            });
        if valid_domain {
            return Ok(());
        }
    }
    bail!(
        "InvalidLightningAddress: '{}' must be in user@domain.tld format",
        address
    )
}

// ── Public API ────────────────────────────────────────────────────────────────

/// Return current settings with `privacy_mode` mirrored from the Identity layer.
pub async fn get_settings() -> Result<AppSettings> {
    Ok(store().read().await)
}

/// Update the application theme.
pub async fn set_theme(theme: ThemeMode) -> Result<()> {
    let snapshot = store().write_with(|s| s.theme = theme).await;
    store().notify(snapshot);
    Ok(())
}

/// Update the display language.
///
/// **Errors**: `UnsupportedLocale` if `locale` is not one of `en|es|it|fr|de`.
pub async fn set_language(locale: String) -> Result<()> {
    validate_locale(&locale)?;
    let snapshot = store().write_with(|s| s.language = locale).await;
    store().notify(snapshot);
    Ok(())
}

/// Set or clear the default fiat currency code.
///
/// **Errors**: `InvalidFiatCode` if `code` is Some but not exactly 3 uppercase letters (ISO 4217).
pub async fn set_default_fiat_code(code: Option<String>) -> Result<()> {
    if let Some(ref c) = code {
        validate_fiat_code(c)?;
    }
    let snapshot = store().write_with(|s| s.default_fiat_code = code).await;
    store().notify(snapshot);
    Ok(())
}

/// Set or clear the default Lightning Address.
///
/// **Errors**: `InvalidLightningAddress` if `address` is Some but malformed.
pub async fn set_default_lightning_address(address: Option<String>) -> Result<()> {
    let normalized = address.map(|a| a.trim().to_string());
    if let Some(ref a) = normalized {
        validate_lightning_address(a)?;
    }
    let snapshot = store()
        .write_with(|s| s.default_lightning_address = normalized)
        .await;
    store().notify(snapshot);
    Ok(())
}

/// Set or clear the active Mostro node pubkey.
///
/// Pass `Some("hex...")` to route orders to a custom Mostro node, or `None`
/// to revert to the compiled-in default.
///
/// **Errors**: `InvalidPubkey` if `pubkey` is Some but not a valid 64-char hex key.
pub fn set_mostro_pubkey(pubkey: Option<String>) -> Result<()> {
    if let Some(ref pk) = pubkey {
        nostr_sdk::PublicKey::from_hex(pk)
            .map_err(|e| anyhow::anyhow!("InvalidPubkey: {e}"))?;
    }
    crate::config::set_active_mostro_pubkey(pubkey);
    Ok(())
}

/// Return the currently active Mostro node pubkey (override or default).
pub fn get_mostro_pubkey() -> String {
    crate::config::active_mostro_pubkey()
}

/// Return the active Mostro node info, falling back to the compiled
/// default if none has been persisted yet.
pub async fn get_mostro_node() -> Result<crate::api::types::MostroNodeInfo> {
    if let Some(db) = crate::db::app_db::db() {
        if let Ok(Some(node)) = db.get_active_mostro_node().await {
            return Ok(node);
        }
    }
    Ok(crate::db::seeds::get_default_mostro_node())
}

/// Persist a new active Mostro node selection.
///
/// Also updates the in-memory pubkey override so the relay pool and
/// outgoing events use the new node immediately.
pub async fn set_mostro_node(node: crate::api::types::MostroNodeInfo) -> Result<()> {
    let pubkey = node.pubkey.clone();
    if let Some(db) = crate::db::app_db::db() {
        db.save_mostro_node(&node).await?;
    }
    crate::config::set_active_mostro_pubkey(Some(pubkey));
    Ok(())
}

/// Toggle the in-memory logging flag (not persisted to disk).
///
/// When a Tokio runtime is available the update is dispatched asynchronously
/// and the broadcast notification is sent.  When there is no runtime (e.g.
/// during synchronous tests) we fall back to a blocking write; the broadcast
/// notification is skipped in that path but the flag is always set.
pub fn set_logging_enabled(enabled: bool) {
    // Note: the async path is fire-and-forget (spawn); callers that call
    // get_settings() immediately after may not yet see the updated flag
    // (eventually consistent).  The sync fallback applies the change inline.
    match tokio::runtime::Handle::try_current() {
        Ok(handle) => {
            handle.spawn(async move {
                let snapshot = store().write_with(|s| s.logging_enabled = enabled).await;
                store().notify(snapshot);
            });
        }
        Err(_) => {
            // No async runtime — update the flag synchronously.
            // Notification is intentionally skipped here (best-effort).
            store().settings.blocking_write().logging_enabled = enabled;
        }
    }
}

// ── Stream ────────────────────────────────────────────────────────────────────

/// A stream that emits [`AppSettings`] whenever any setting changes.
pub struct SettingsStream {
    rx: broadcast::Receiver<AppSettings>,
}

impl SettingsStream {
    /// Poll for the next settings-changed event.
    ///
    /// [`RecvError::Lagged`] is handled gracefully — dropped snapshots are
    /// skipped and the loop continues rather than terminating the stream.
    pub async fn next(&mut self) -> Result<AppSettings> {
        loop {
            match self.rx.recv().await {
                Ok(settings) => return Ok(settings),
                Err(RecvError::Lagged(_)) => continue,
                Err(RecvError::Closed) => {
                    bail!("SettingsStream closed: channel sender dropped")
                }
            }
        }
    }
}

/// Subscribe to settings-changed events.
pub fn on_settings_changed() -> SettingsStream {
    let rx = store().tx.subscribe();
    SettingsStream { rx }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    /// Serialize tests that mutate the global store to avoid interference.
    fn settings_lock() -> &'static Mutex<()> {
        static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
        LOCK.get_or_init(|| Mutex::new(()))
    }

    #[tokio::test]
    async fn get_settings_returns_defaults() {
        let _g = settings_lock().lock().unwrap();
        let s = get_settings().await.unwrap();
        assert_eq!(s.language, "en");
        assert!(s.default_fiat_code.is_none());
        assert!(s.default_lightning_address.is_none());
    }

    #[tokio::test]
    async fn set_language_valid() {
        let _g = settings_lock().lock().unwrap();
        set_language("es".to_string()).await.unwrap();
        let s = get_settings().await.unwrap();
        assert_eq!(s.language, "es");
        // Restore
        set_language("en".to_string()).await.unwrap();
    }

    #[tokio::test]
    async fn set_language_invalid_rejected() {
        let err = set_language("xx".to_string()).await.unwrap_err();
        assert!(err.to_string().contains("UnsupportedLocale"));
    }

    #[tokio::test]
    async fn set_default_fiat_code_valid() {
        let _g = settings_lock().lock().unwrap();
        set_default_fiat_code(Some("USD".to_string())).await.unwrap();
        let s = get_settings().await.unwrap();
        assert_eq!(s.default_fiat_code.as_deref(), Some("USD"));
        set_default_fiat_code(None).await.unwrap();
    }

    #[tokio::test]
    async fn set_default_fiat_code_lowercase_rejected() {
        let err = set_default_fiat_code(Some("usd".to_string()))
            .await
            .unwrap_err();
        assert!(err.to_string().contains("InvalidFiatCode"));
    }

    #[tokio::test]
    async fn set_default_fiat_code_none_clears() {
        let _g = settings_lock().lock().unwrap();
        set_default_fiat_code(Some("EUR".to_string())).await.unwrap();
        set_default_fiat_code(None).await.unwrap();
        let s = get_settings().await.unwrap();
        assert!(s.default_fiat_code.is_none());
    }

    #[tokio::test]
    async fn set_default_lightning_address_valid() {
        let _g = settings_lock().lock().unwrap();
        set_default_lightning_address(Some("alice@example.com".to_string()))
            .await
            .unwrap();
        let s = get_settings().await.unwrap();
        assert_eq!(
            s.default_lightning_address.as_deref(),
            Some("alice@example.com")
        );
        set_default_lightning_address(None).await.unwrap();
    }

    #[tokio::test]
    async fn set_default_lightning_address_invalid_rejected() {
        let err = set_default_lightning_address(Some("notanaddress".to_string()))
            .await
            .unwrap_err();
        assert!(err.to_string().contains("InvalidLightningAddress"));
    }

    #[tokio::test]
    async fn settings_stream_receives_change() {
        let _g = settings_lock().lock().unwrap();
        let mut stream = on_settings_changed();
        // Set theme to trigger a broadcast.
        set_theme(ThemeMode::Light).await.unwrap();
        let received = stream.next().await.unwrap();
        assert_eq!(received.theme, ThemeMode::Light);
        // Restore
        set_theme(ThemeMode::Dark).await.unwrap();
    }

    #[tokio::test]
    async fn all_supported_locales_accepted() {
        let _g = settings_lock().lock().unwrap();
        for locale in SUPPORTED_LOCALES {
            set_language(locale.to_string()).await.unwrap();
        }
        // Restore
        set_language("en".to_string()).await.unwrap();
    }
}
