//! Embedded Cashu wallet — phase C2 of `docs/cashu/README.md`.
//!
//! The seller needs ecash **at the node's mint** before they can lock an
//! escrow, and the buyer needs somewhere for redeemed ecash to land, so a
//! minimal wallet is a prerequisite for every later Cashu phase rather than a
//! nice-to-have.
//!
//! Scope, deliberately small: connect to one mint, hold `sat` proofs, receive a
//! token, export a token, and re-check proof state. Melting to Lightning,
//! multi-mint support and NUT-11 locking are later phases.
//!
//! **Native only.** Proof storage is `cdk-sqlite`, which is `rusqlite` and does
//! not build for `wasm32`. The web target gets the typed stub at the bottom of
//! this file — same shape, every call fails with a stable marker — mirroring
//! how `crate::nwc::client` handles the same split. `cdk` itself *does* compile
//! to wasm (verified; see `docs/cashu/cdk-spike.md`), so the web gap is storage
//! alone, and closing it belongs with the rest of IndexedDB in #233.

#[cfg(not(target_arch = "wasm32"))]
mod wallet;

#[cfg(not(target_arch = "wasm32"))]
pub use wallet::{CashuWallet, MintCapabilities};

// ── WASM stub ────────────────────────────────────────────────────────────────

/// What a mint advertises that this client needs. See the native
/// [`wallet::MintCapabilities`] for the real definition.
#[cfg(target_arch = "wasm32")]
#[derive(Debug, Clone, Default)]
pub struct MintCapabilities {
    pub nut07_state_check: bool,
    pub nut11_p2pk: bool,
    pub nut12_dleq: bool,
    pub has_sat_keyset: bool,
}

#[cfg(target_arch = "wasm32")]
impl MintCapabilities {
    pub fn is_usable(&self) -> bool {
        false
    }

    pub fn missing(&self) -> Vec<&'static str> {
        vec!["storage"]
    }
}

/// Web build: no proof storage, so no wallet. Every call fails with the
/// `CashuUnsupportedOnWeb` marker, which Dart maps to a localized string —
/// Rust does not translate.
#[cfg(target_arch = "wasm32")]
pub struct CashuWallet;

#[cfg(target_arch = "wasm32")]
impl CashuWallet {
    pub async fn connect(
        _mint_url: &str,
        _seed: zeroize::Zeroizing<[u8; 64]>,
        _db_path: &str,
    ) -> anyhow::Result<Self> {
        anyhow::bail!("CashuUnsupportedOnWeb")
    }

    pub fn mint_url(&self) -> &str {
        ""
    }

    /// Never called — `connect` cannot succeed here — but it answers instead of
    /// panicking, so "this cannot happen" has one meaning in this file rather
    /// than two.
    pub fn capabilities(&self) -> &MintCapabilities {
        const NONE: &MintCapabilities = &MintCapabilities {
            nut07_state_check: false,
            nut11_p2pk: false,
            nut12_dleq: false,
            has_sat_keyset: false,
        };
        NONE
    }

    pub async fn balance(&self) -> anyhow::Result<u64> {
        anyhow::bail!("CashuUnsupportedOnWeb")
    }

    pub async fn receive_token(&self, _encoded: &str) -> anyhow::Result<u64> {
        anyhow::bail!("CashuUnsupportedOnWeb")
    }

    pub async fn create_token(&self, _amount_sats: u64) -> anyhow::Result<String> {
        anyhow::bail!("CashuUnsupportedOnWeb")
    }

    pub async fn check_proofs_state(&self) -> anyhow::Result<u64> {
        anyhow::bail!("CashuUnsupportedOnWeb")
    }
}
