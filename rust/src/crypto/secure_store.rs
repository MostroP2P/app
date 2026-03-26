/// Platform secure storage bridge.
///
/// Stores sensitive key material in the platform's secure enclave/keychain:
///   iOS/macOS  → Keychain Services
///   Android    → Android Keystore + EncryptedSharedPreferences
///   Windows    → Windows Credential Manager (DPAPI)
///   Linux      → libsecret (GNOME Keyring / KWallet)
///   Web        → SubtleCrypto + encrypted IndexedDB
///
/// The Rust layer only stores the master encryption key here; actual key
/// bytes are wrapped with this key before being persisted in the DB.
///
/// per research R5.
use anyhow::Result;

/// Store `value` bytes under `key` in the platform secure storage.
/// `key` should be a short, stable identifier (e.g. "mostro_master_key").
pub fn store(key: &str, value: &[u8]) -> Result<()> {
    platform_store(key, value)
}

/// Load bytes previously stored under `key`.
/// Returns `None` if the key does not exist.
pub fn load(key: &str) -> Result<Option<Vec<u8>>> {
    platform_load(key)
}

/// Remove a key from secure storage.
pub fn remove(key: &str) -> Result<()> {
    platform_remove(key)
}

// ─── Platform implementations ────────────────────────────────────────────────

#[cfg(target_os = "ios")]
mod platform {
    use anyhow::{bail, Context, Result};

    // On iOS we delegate to Flutter's flutter_secure_storage via the method channel.
    // Rust calls are synchronous placeholders; the actual Keychain writes happen on
    // the Flutter side. For now these are stubs; real IPC is wired in Phase 3 T029.
    pub fn store(_key: &str, _value: &[u8]) -> Result<()> {
        // TODO Phase 3: call via FFI callback into Flutter secure_storage
        Ok(())
    }
    pub fn load(_key: &str) -> Result<Option<Vec<u8>>> {
        Ok(None)
    }
    pub fn remove(_key: &str) -> Result<()> {
        Ok(())
    }
}

#[cfg(target_os = "android")]
mod platform {
    use anyhow::Result;
    // Same as iOS — delegated to Flutter secure_storage in Phase 3.
    pub fn store(_key: &str, _value: &[u8]) -> Result<()> { Ok(()) }
    pub fn load(_key: &str) -> Result<Option<Vec<u8>>> { Ok(None) }
    pub fn remove(_key: &str) -> Result<()> { Ok(()) }
}

#[cfg(target_os = "macos")]
mod platform {
    use anyhow::Result;
    pub fn store(_key: &str, _value: &[u8]) -> Result<()> { Ok(()) }
    pub fn load(_key: &str) -> Result<Option<Vec<u8>>> { Ok(None) }
    pub fn remove(_key: &str) -> Result<()> { Ok(()) }
}

#[cfg(target_os = "windows")]
mod platform {
    use anyhow::Result;
    pub fn store(_key: &str, _value: &[u8]) -> Result<()> { Ok(()) }
    pub fn load(_key: &str) -> Result<Option<Vec<u8>>> { Ok(None) }
    pub fn remove(_key: &str) -> Result<()> { Ok(()) }
}

#[cfg(target_os = "linux")]
mod platform {
    use anyhow::Result;
    pub fn store(_key: &str, _value: &[u8]) -> Result<()> { Ok(()) }
    pub fn load(_key: &str) -> Result<Option<Vec<u8>>> { Ok(None) }
    pub fn remove(_key: &str) -> Result<()> { Ok(()) }
}

#[cfg(target_arch = "wasm32")]
mod platform {
    use anyhow::Result;
    // Web: SubtleCrypto + encrypted IndexedDB — implemented in Phase 3 T029.
    pub fn store(_key: &str, _value: &[u8]) -> Result<()> { Ok(()) }
    pub fn load(_key: &str) -> Result<Option<Vec<u8>>> { Ok(None) }
    pub fn remove(_key: &str) -> Result<()> { Ok(()) }
}

// Fallback for any unrecognized platform (e.g. integration test host)
#[cfg(not(any(
    target_os = "ios",
    target_os = "android",
    target_os = "macos",
    target_os = "windows",
    target_os = "linux",
    target_arch = "wasm32"
)))]
mod platform {
    use anyhow::Result;
    pub fn store(_key: &str, _value: &[u8]) -> Result<()> { Ok(()) }
    pub fn load(_key: &str) -> Result<Option<Vec<u8>>> { Ok(None) }
    pub fn remove(_key: &str) -> Result<()> { Ok(()) }
}

fn platform_store(key: &str, value: &[u8]) -> Result<()> {
    platform::store(key, value)
}

fn platform_load(key: &str) -> Result<Option<Vec<u8>>> {
    platform::load(key)
}

fn platform_remove(key: &str) -> Result<()> {
    platform::remove(key)
}
