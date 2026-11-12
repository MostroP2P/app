//! Embedded Cashu wallet — phase C2 of `docs/cashu/README.md`.
//!
//! The seller needs ecash **at the node's mint** before they can lock an
//! escrow, and the buyer needs somewhere for redeemed ecash to land, so a
//! minimal wallet is a prerequisite for every later Cashu phase rather than a
//! nice-to-have.
//!
//! Scope, deliberately small: connect to one mint, hold `sat` proofs, receive a
//! token, export a token, re-check proof state, and settle at connect what an
//! interrupted session left half done. Melting to Lightning is phase C3b-1 and
//! NUT-11 locking lives in [`escrow`]; minting from Lightning is phase C3b-2.
//! Multi-mint support is not here.
//!
//! **Native only.** Proof storage is `cdk-sqlite`, which is `rusqlite` and does
//! not build for `wasm32`. The web target gets the typed stub at the bottom of
//! this file — same shape, every call fails with a stable marker — mirroring
//! how `crate::nwc::client` handles the same split. `cdk` itself *does* compile
//! to wasm (verified; see `docs/cashu/cdk-spike.md`), so the web gap is storage
//! alone, and closing it belongs with the rest of IndexedDB in #233.

#[cfg(not(target_arch = "wasm32"))]
pub mod escrow;
#[cfg(not(target_arch = "wasm32"))]
mod in_flight;
#[cfg(not(target_arch = "wasm32"))]
mod mint_clock;
#[cfg(not(target_arch = "wasm32"))]
mod wallet;

#[cfg(not(target_arch = "wasm32"))]
pub use wallet::{
    collect_pending_quotes, ensure_receivable, stored_balance, stored_pending_quotes,
    token_mint_url, CashuWallet, Collect, MeltOutcomeInfo, MeltQuoteInfo, MintCapabilities,
    MintQuoteInfo, MintQuoteStatus, PendingQuotes,
};

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
    pub nut05_bolt11: bool,
    pub melt_min_sats: Option<u64>,
    pub melt_max_sats: Option<u64>,
    pub nut04_bolt11: bool,
    pub mint_min_sats: Option<u64>,
    pub mint_max_sats: Option<u64>,
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

/// See the native [`wallet::MeltQuoteInfo`].
#[cfg(target_arch = "wasm32")]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MeltQuoteInfo {
    pub quote_id: String,
    pub amount_sats: u64,
    pub fee_reserve_sats: u64,
    pub input_fee_sats: u64,
    pub max_total_sats: u64,
}

/// See the native [`wallet::MintQuoteInfo`].
#[cfg(target_arch = "wasm32")]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MintQuoteInfo {
    pub quote_id: String,
    pub invoice: String,
    pub amount_sats: u64,
    pub expires_at: u64,
}

/// See the native [`wallet::MintQuoteStatus`].
#[cfg(target_arch = "wasm32")]
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MintQuoteStatus {
    Waiting,
    Issued { amount_sats: u64 },
    Expired,
}

/// See the native [`wallet::MeltOutcomeInfo`].
#[cfg(target_arch = "wasm32")]
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MeltOutcomeInfo {
    Paid {
        amount_sats: u64,
        fee_paid_sats: u64,
    },
    Pending,
}

/// No proof store on web, so nothing is held there.
#[cfg(target_arch = "wasm32")]
pub async fn stored_balance(_db_path: &str, _mint_url: Option<&str>) -> anyhow::Result<u64> {
    Ok(0)
}

/// See the native [`wallet::PendingQuotes`].
#[cfg(target_arch = "wasm32")]
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct PendingQuotes {
    pub paid_sats: u64,
    pub open: u32,
}

/// No proof store on web, so no invoice pending.
#[cfg(target_arch = "wasm32")]
pub async fn stored_pending_quotes(
    _db_path: &str,
    _mint_url: Option<&str>,
) -> anyhow::Result<PendingQuotes> {
    Ok(PendingQuotes::default())
}

/// See the native [`wallet::Collect`].
#[cfg(target_arch = "wasm32")]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Collect {
    Live,
    Everything,
}

/// No proof store on web, so no quote to collect.
#[cfg(target_arch = "wasm32")]
pub async fn collect_pending_quotes(
    _db_path: &str,
    _seed: &zeroize::Zeroizing<[u8; 64]>,
    _active: Option<&CashuWallet>,
    _which: Collect,
) -> anyhow::Result<u64> {
    Ok(0)
}

/// Nothing to refuse on web: every receive fails later, as unsupported.
#[cfg(target_arch = "wasm32")]
pub fn ensure_receivable(_encoded: &str) -> anyhow::Result<()> {
    Ok(())
}

/// No token decoding on web either: the wallet it would bind cannot run there.
#[cfg(target_arch = "wasm32")]
pub fn token_mint_url(_encoded: &str) -> anyhow::Result<String> {
    anyhow::bail!("CashuUnsupportedOnWeb")
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
            nut05_bolt11: false,
            melt_min_sats: None,
            melt_max_sats: None,
            nut04_bolt11: false,
            mint_min_sats: None,
            mint_max_sats: None,
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

    pub async fn sweep_spent_proofs(&self) -> anyhow::Result<()> {
        anyhow::bail!("CashuUnsupportedOnWeb")
    }

    pub async fn finalize_pending_melts(&self) -> anyhow::Result<()> {
        anyhow::bail!("CashuUnsupportedOnWeb")
    }

    pub async fn melt_quote(&self, _invoice: &str) -> anyhow::Result<MeltQuoteInfo> {
        anyhow::bail!("CashuUnsupportedOnWeb")
    }

    pub async fn melt(
        &self,
        _quote_id: &str,
        _max_total_sats: u64,
    ) -> anyhow::Result<MeltOutcomeInfo> {
        anyhow::bail!("CashuUnsupportedOnWeb")
    }

    pub async fn pending_quotes(&self) -> anyhow::Result<PendingQuotes> {
        anyhow::bail!("CashuUnsupportedOnWeb")
    }

    pub async fn mint_quote(&self, _amount_sats: u64) -> anyhow::Result<MintQuoteInfo> {
        anyhow::bail!("CashuUnsupportedOnWeb")
    }

    pub async fn claim_mint_quote(&self, _quote_id: &str) -> anyhow::Result<MintQuoteStatus> {
        anyhow::bail!("CashuUnsupportedOnWeb")
    }

    // Escrow half (C4/C5). Same shape as the native `escrow` module so the
    // bridge layer compiles unchanged; a wallet can never exist here, so none
    // of these is reachable in practice.

    pub async fn build_escrow_token(
        &self,
        _amount_sats: u64,
        _parties: &escrow::EscrowParties,
        _locktime: u64,
    ) -> anyhow::Result<String> {
        anyhow::bail!("CashuUnsupportedOnWeb")
    }

    pub async fn build_fee_token(
        &self,
        _amount_sats: u64,
        _mostro: &escrow::CashuPublicKey,
    ) -> anyhow::Result<String> {
        anyhow::bail!("CashuUnsupportedOnWeb")
    }

    pub async fn verify_escrow_token(
        &self,
        _encoded: &str,
        _parties: &escrow::EscrowParties,
        _expected_amount: u64,
        _min_locktime: u64,
    ) -> anyhow::Result<()> {
        anyhow::bail!("CashuUnsupportedOnWeb")
    }
}

/// Escrow primitives on web: the types exist so the bridge layer is one
/// codebase, but nothing can be built without a wallet.
#[cfg(target_arch = "wasm32")]
pub mod escrow {
    /// Stand-in for `cdk`'s compressed key. Web never reaches the mint, so the
    /// hex is carried verbatim rather than parsed.
    pub type CashuPublicKey = String;

    #[derive(Debug, Clone, PartialEq, Eq)]
    pub struct EscrowParties {
        pub buyer: CashuPublicKey,
        pub seller: CashuPublicKey,
        pub mostro: CashuPublicKey,
    }

    impl EscrowParties {
        /// Applies the same `02` prefix and the same length check as the native
        /// implementation, so a malformed key is rejected identically on both
        /// targets rather than only where cdk is present.
        pub fn from_xonly_hex(
            buyer: &str,
            seller: &str,
            mostro: &str,
        ) -> anyhow::Result<Self> {
            let map = |hex: &str| -> anyhow::Result<CashuPublicKey> {
                let hex = hex.trim();
                if hex.len() != 64 || !hex.chars().all(|c| c.is_ascii_hexdigit()) {
                    anyhow::bail!("InvalidTradeKey: expected 64 hex characters, got {hex:?}");
                }
                Ok(format!("02{hex}"))
            };
            Ok(Self {
                buyer: map(buyer)?,
                seller: map(seller)?,
                mostro: map(mostro)?,
            })
        }
    }

    #[derive(Debug, Clone, PartialEq, Eq)]
    pub struct ProofSignature {
        pub secret: String,
        pub signature: String,
    }
}
