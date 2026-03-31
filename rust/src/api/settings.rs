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
        f(&mut *guard);
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

/// Validates a simple ISO 4217 fiat code: 1–3 uppercase ASCII letters.
fn validate_fiat_code(code: &str) -> Result<()> {
    let valid = !code.is_empty()
        && code.len() <= 3
        && code.chars().all(|c| c.is_ascii_uppercase());
    if valid {
        Ok(())
    } else {
        bail!(
            "InvalidFiatCode: '{}' must be 1–3 uppercase ASCII letters (ISO 4217)",
            code
        )
    }
}

/// Validates a Lightning Address in `user@domain` format.
fn validate_lightning_address(address: &str) -> Result<()> {
    let parts: Vec<&str> = address.splitn(2, '@').collect();
    if parts.len() == 2 && !parts[0].is_empty() && !parts[1].is_empty() {
        Ok(())
    } else {
        bail!(
            "InvalidLightningAddress: '{}' must be in user@domain format",
            address
        )
    }
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
/// **Errors**: `InvalidFiatCode` if `code` is Some but not 1–3 uppercase letters.
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
    if let Some(ref a) = address {
        validate_lightning_address(a)?;
    }
    let snapshot = store()
        .write_with(|s| s.default_lightning_address = address)
        .await;
    store().notify(snapshot);
    Ok(())
}

/// Toggle the in-memory logging flag (not persisted to disk).
pub fn set_logging_enabled(enabled: bool) {
    // Fire-and-forget: spawn onto the runtime since write_with is async.
    // We update synchronously via a blocking write to avoid blocking the
    // caller on an async runtime.
    //
    // Implementation note: we tolerate the brief window where the runtime
    // notification is not sent because log toggling is best-effort.
    let rt = tokio::runtime::Handle::try_current();
    if let Ok(handle) = rt {
        handle.spawn(async move {
            let snapshot = store().write_with(|s| s.logging_enabled = enabled).await;
            store().notify(snapshot);
        });
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
        for locale in SUPPORTED_LOCALES {
            set_language(locale.to_string()).await.unwrap();
        }
        // Restore
        set_language("en".to_string()).await.unwrap();
    }
}
