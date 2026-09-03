//! Escrow-mode surface for the UI — phase C1b of `docs/cashu/README.md`.
//!
//! The domain logic lives in [`crate::mostro::escrow_mode`]; this module is the
//! bridge half: it converts the resolved mode into a Dart-friendly struct,
//! persists the two developer overrides through the settings k/v store, and
//! broadcasts changes so the UI never polls.
//!
//! Two rules this module exists to keep:
//! - **Rust does not translate.** [`EscrowModeInfo::mode`] is a stable marker
//!   (`"unknown" | "lightning" | "cashu"`); Dart maps it to a localized string.
//! - **The gate is `is_cashu_available`, not `mode == "cashu"`.** A node can
//!   advertise Cashu and still publish no usable mint.

use anyhow::{bail, Result};
use tokio::sync::broadcast::error::RecvError;

use crate::api::types::EscrowModeInfo;
use crate::db::{settings_keys, Storage};
use crate::mostro::escrow_mode::{self, EscrowModeOverride, EscrowOverrides};

// ── Conversion ────────────────────────────────────────────────────────────────

fn snapshot() -> EscrowModeInfo {
    let resolved = escrow_mode::get_resolved();
    let overrides = escrow_mode::get_overrides();

    EscrowModeInfo {
        mode: resolved.mode.as_marker().to_string(),
        mint_url: resolved.config.mint_url.clone(),
        escrow_locktime_days: resolved.config.escrow_locktime_days,
        settlement_margin_days: resolved.config.settlement_margin_days,
        is_overridden: resolved.is_overridden,
        // Derived from the resolution above rather than re-reading the globals:
        // `is_cashu_mode()` would take a second read, and a node switch between
        // the two would produce a snapshot whose mode and gate disagree.
        is_cashu_available: resolved.is_cashu_usable(),
        force_cashu_override: matches!(overrides.mode, EscrowModeOverride::ForceCashu),
        mint_url_override: overrides.mint_url,
    }
}

// ── Validation ────────────────────────────────────────────────────────────────

/// Accept only an `http(s)` URL with a host.
///
/// Deliberately strict: the mint override exists to point a tester at a local
/// nutshell, and a typo that silently became the "mint" would surface much
/// later, as a connection failure with no obvious cause.
fn validate_mint_url(url: &str) -> Result<()> {
    // `Url` comes from nostr-sdk's re-export of the `url` crate — no new
    // dependency for one validation.
    let parsed = nostr_sdk::Url::parse(url)
        .map_err(|e| anyhow::anyhow!("InvalidMintUrl: '{url}' is not a URL ({e})"))?;

    if !matches!(parsed.scheme(), "http" | "https") {
        bail!("InvalidMintUrl: '{url}' must use http or https");
    }
    if parsed.host_str().is_none_or(str::is_empty) {
        bail!("InvalidMintUrl: '{url}' has no host");
    }
    Ok(())
}

// ── Public API ────────────────────────────────────────────────────────────────

/// The active node's settlement backend, overrides applied.
pub fn get_escrow_mode() -> EscrowModeInfo {
    snapshot()
}

/// Force the client to treat the active node as running Cashu escrow, or go
/// back to trusting the node's own tags.
///
/// Developer affordance (§4.3): it exists to test against a daemon branch that
/// implements Cashu without publishing the 38385 tags yet. The Flutter surface
/// that calls it is `kDebugMode`-only, so release builds cannot reach it.
pub async fn set_escrow_mode_override(force_cashu: bool) -> Result<()> {
    let mode = if force_cashu {
        EscrowModeOverride::ForceCashu
    } else {
        EscrowModeOverride::Auto
    };

    persist(settings_keys::ESCROW_MODE_OVERRIDE, Some(mode.as_stored())).await?;
    // One field, under one lock: the mint URL is set from the same surface, and
    // a read-modify-write of the whole struct would race with it.
    escrow_mode::update_overrides(|o| o.mode = mode);
    Ok(())
}

/// Point Cashu at a specific mint instead of the one the node advertises.
///
/// `None` (or a blank string) clears the override, restoring the node's value.
///
/// **Errors**: `InvalidMintUrl` when the URL is not an `http(s)` URL with a host.
pub async fn set_cashu_mint_url_override(mint_url: Option<String>) -> Result<()> {
    let normalized = mint_url
        .map(|u| u.trim().to_string())
        .filter(|u| !u.is_empty());

    if let Some(ref url) = normalized {
        validate_mint_url(url)?;
    }

    persist(settings_keys::CASHU_MINT_URL_OVERRIDE, normalized.as_deref()).await?;
    escrow_mode::update_overrides(|o| o.mint_url = normalized);
    Ok(())
}

/// Load the persisted overrides into memory.
///
/// Call once at startup, after `init_db` and **before** the relay pool starts,
/// so the first capability fetch already resolves against the user's overrides.
/// No-op when the DB is unavailable (the `Auto` default then applies, which
/// keeps every Cashu path shut).
pub async fn rehydrate_escrow_overrides() -> Result<()> {
    let Some(db) = crate::db::app_db::db() else {
        return Ok(());
    };

    let mode = match db.get_setting(settings_keys::ESCROW_MODE_OVERRIDE).await? {
        Some(stored) => EscrowModeOverride::from_stored(&stored),
        None => EscrowModeOverride::Auto,
    };

    // A persisted mint URL is re-validated rather than trusted: the rules can
    // tighten between releases, and a stored value that no longer passes them
    // must be dropped, not silently used.
    let mint_url = db
        .get_setting(settings_keys::CASHU_MINT_URL_OVERRIDE)
        .await?
        .filter(|url| match validate_mint_url(url) {
            Ok(()) => true,
            Err(e) => {
                log::warn!("[escrow] discarding persisted mint override: {e}");
                false
            }
        });

    escrow_mode::set_overrides(EscrowOverrides { mode, mint_url });
    Ok(())
}

/// Write (or remove) a settings key, tolerating an uninitialised DB.
///
/// A missing DB is not an error: the in-memory override still applies for this
/// session, exactly as on web, where the IndexedDB backend is a stub (#233).
async fn persist(key: &str, value: Option<&str>) -> Result<()> {
    let Some(db) = crate::db::app_db::db() else {
        log::warn!("[escrow] no DB — '{key}' applies to this session only");
        return Ok(());
    };
    match value {
        Some(v) => db.set_setting(key, v).await,
        None => db.delete_setting(key).await,
    }
}

// ── Stream ────────────────────────────────────────────────────────────────────

/// A stream that emits the resolved escrow mode whenever it changes: a
/// capability fetch, a node switch, or an override flip.
pub struct EscrowModeStream {
    rx: tokio::sync::broadcast::Receiver<()>,
}

impl EscrowModeStream {
    /// Poll for the next escrow-mode-changed event.
    ///
    /// A lagged receiver skips the dropped snapshots and continues: the value
    /// is a current-state snapshot, so only the latest one matters.
    pub async fn next(&mut self) -> Result<EscrowModeInfo> {
        loop {
            match self.rx.recv().await {
                // The event is a bare wake-up; the snapshot is rebuilt from the
                // globals so the override fields can never disagree with the
                // mode inside the same struct.
                Ok(()) => return Ok(snapshot()),
                Err(RecvError::Lagged(_)) => continue,
                Err(RecvError::Closed) => {
                    bail!("EscrowModeStream closed: channel sender dropped")
                }
            }
        }
    }
}

/// Subscribe to escrow-mode changes.
pub fn on_escrow_mode_changed() -> EscrowModeStream {
    EscrowModeStream {
        rx: escrow_mode::subscribe(),
    }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use crate::mostro::escrow_mode::{CashuNodeConfig, EscrowMode};

    /// The escrow globals are process-wide; serialize the tests that write them
    /// and start each one from a freshly-launched app's state.
    ///
    /// The lock itself lives in `mostro::escrow_mode`, next to the state it
    /// guards, and is shared with that module's own tests. A private lock here
    /// only serialized this module and raced the other one (#309).
    fn escrow_lock() -> std::sync::MutexGuard<'static, ()> {
        escrow_mode::lock_globals_for_test()
    }

    #[tokio::test]
    async fn a_fresh_client_reports_unknown_and_no_cashu() {
        // Arrange
        let _g = escrow_lock();

        // Act
        let info = get_escrow_mode();

        // Assert — the marker is stable, and the gate is shut.
        assert_eq!(info.mode, "unknown");
        assert!(!info.is_cashu_available);
        assert!(!info.is_overridden);
        assert!(!info.force_cashu_override);
        assert_eq!(info.mint_url, None);
    }

    #[tokio::test]
    async fn a_cashu_node_is_reported_with_its_parameters() {
        // Arrange
        let _g = escrow_lock();
        escrow_mode::set_from_tags(
            EscrowMode::Cashu,
            CashuNodeConfig {
                mint_url: Some("https://mint.example.com".to_string()),
                escrow_locktime_days: Some(15),
                settlement_margin_days: Some(3),
            },
        );

        // Act
        let info = get_escrow_mode();

        // Assert
        assert_eq!(info.mode, "cashu");
        assert_eq!(info.mint_url.as_deref(), Some("https://mint.example.com"));
        assert_eq!(info.escrow_locktime_days, Some(15));
        assert_eq!(info.settlement_margin_days, Some(3));
        assert!(info.is_cashu_available);
        assert!(!info.is_overridden);
    }

    #[tokio::test]
    async fn forcing_cashu_without_a_mint_does_not_open_the_gate() {
        // Arrange — a Lightning node and a developer who forgot the mint.
        let _g = escrow_lock();
        escrow_mode::set_from_tags(EscrowMode::Lightning, CashuNodeConfig::default());

        // Act
        set_escrow_mode_override(true).await.unwrap();
        let info = get_escrow_mode();

        // Assert — the mode is reported honestly, but nothing may run: there is
        // no mint to connect to.
        assert_eq!(info.mode, "cashu");
        assert!(info.is_overridden);
        assert!(!info.is_cashu_available);

        // Act — now with a mint.
        set_cashu_mint_url_override(Some("http://localhost:3338".to_string()))
            .await
            .unwrap();

        // Assert
        let info = get_escrow_mode();
        assert!(info.is_cashu_available);
        assert_eq!(info.mint_url.as_deref(), Some("http://localhost:3338"));
        assert_eq!(
            info.mint_url_override.as_deref(),
            Some("http://localhost:3338")
        );
    }

    #[tokio::test]
    async fn turning_the_override_off_restores_what_the_node_said() {
        // Arrange
        let _g = escrow_lock();
        escrow_mode::set_from_tags(EscrowMode::Lightning, CashuNodeConfig::default());
        set_escrow_mode_override(true).await.unwrap();
        set_cashu_mint_url_override(Some("http://localhost:3338".to_string()))
            .await
            .unwrap();

        // Act
        set_escrow_mode_override(false).await.unwrap();

        // Assert — the mint override is independent and survives; the mode is
        // the node's again.
        let info = get_escrow_mode();
        assert_eq!(info.mode, "lightning");
        assert!(!info.is_cashu_available);
        assert_eq!(
            info.mint_url_override.as_deref(),
            Some("http://localhost:3338")
        );
    }

    #[tokio::test]
    async fn a_blank_mint_override_clears_it() {
        // Arrange
        let _g = escrow_lock();
        set_cashu_mint_url_override(Some("http://localhost:3338".to_string()))
            .await
            .unwrap();

        // Act
        set_cashu_mint_url_override(Some("   ".to_string()))
            .await
            .unwrap();

        // Assert
        assert_eq!(get_escrow_mode().mint_url_override, None);
    }

    #[tokio::test]
    async fn a_malformed_mint_override_is_rejected_and_changes_nothing() {
        // Arrange
        let _g = escrow_lock();
        set_cashu_mint_url_override(Some("https://mint.example.com".to_string()))
            .await
            .unwrap();

        // Act / Assert — every rejected shape.
        for bad in ["not a url", "ftp://mint.example.com", "file:///etc/passwd"] {
            let err = set_cashu_mint_url_override(Some(bad.to_string()))
                .await
                .unwrap_err();
            assert!(
                err.to_string().contains("InvalidMintUrl"),
                "expected InvalidMintUrl for {bad:?}, got {err}"
            );
        }

        // Assert — a rejected write leaves the previous value in place.
        assert_eq!(
            get_escrow_mode().mint_url_override.as_deref(),
            Some("https://mint.example.com")
        );
    }

    #[tokio::test]
    async fn overrides_survive_a_restart_through_the_settings_store() {
        // Arrange — a real store, so this covers the persist/rehydrate pair
        // rather than just the halves. Without an initialised DB the setters
        // apply in memory only, which is the web behaviour (#233) and would
        // make this test pass for the wrong reason.
        let _g = escrow_lock();
        let path = std::env::temp_dir().join(format!(
            "mostro_escrow_rehydrate_{}.db",
            std::process::id()
        ));
        // `init_db` is a OnceCell — the first test to call it wins and the rest
        // share that store, which is what we want: this test needs *a* real
        // store, not its own.
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        assert!(
            crate::db::app_db::db().is_some(),
            "a real settings store is the point of this test"
        );

        // Act — the developer sets both overrides.
        set_escrow_mode_override(true).await.unwrap();
        set_cashu_mint_url_override(Some("http://localhost:3338".to_string()))
            .await
            .unwrap();

        // Act — the app restarts: memory is empty, only the store survives.
        escrow_mode::set_overrides(EscrowOverrides::default());
        assert!(!get_escrow_mode().force_cashu_override, "precondition");
        rehydrate_escrow_overrides().await.unwrap();

        // Assert — both came back.
        let info = get_escrow_mode();
        assert!(info.force_cashu_override);
        assert_eq!(
            info.mint_url_override.as_deref(),
            Some("http://localhost:3338")
        );

        // Cleanup — clear the overrides, but leave the file alone. `init_db`
        // is a process-wide OnceCell: deleting the file here would leave every
        // later test holding a pool onto a database that no longer has tables.
        set_escrow_mode_override(false).await.unwrap();
        set_cashu_mint_url_override(None).await.unwrap();
    }

    #[tokio::test]
    async fn setting_one_override_never_clobbers_the_other() {
        // Arrange — the read-modify-write hazard: both fields are written from
        // the same screen, and the mode setter used to overwrite the whole
        // struct with a separately-read copy.
        let _g = escrow_lock();
        set_cashu_mint_url_override(Some("http://localhost:3338".to_string()))
            .await
            .unwrap();

        // Act
        set_escrow_mode_override(true).await.unwrap();

        // Assert — the mint override is still there.
        let info = get_escrow_mode();
        assert!(info.force_cashu_override);
        assert_eq!(
            info.mint_url_override.as_deref(),
            Some("http://localhost:3338"),
            "setting the mode must not drop the mint override"
        );
    }

    #[tokio::test]
    async fn the_stream_emits_a_consistent_snapshot() {
        // Arrange
        let _g = escrow_lock();
        let mut stream = on_escrow_mode_changed();

        // Act
        escrow_mode::set_from_tags(
            EscrowMode::Cashu,
            CashuNodeConfig {
                mint_url: Some("https://mint.example.com".to_string()),
                ..Default::default()
            },
        );

        // Assert
        let info = stream.next().await.unwrap();
        assert_eq!(info.mode, "cashu");
        assert!(info.is_cashu_available);
    }
}
