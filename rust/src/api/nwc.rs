/// NWC API — Nostr Wallet Connect integration.
///
/// Provides `connect_wallet`, `disconnect_wallet`, `get_wallet`,
/// `get_balance`, and `pay_invoice` functions, plus a status-change stream.
///
/// The underlying NIP-47 protocol exchange is handled by [`crate::nwc::client`].
use anyhow::{anyhow, bail, Result};
use std::sync::{Arc, OnceLock};
use tokio::sync::{broadcast, RwLock};
use tokio::sync::broadcast::error::RecvError;

use crate::api::types::{NwcWalletInfo, PaymentResult};
use crate::nwc::client::NwcClient;

// ── Wallet store ──────────────────────────────────────────────────────────────

struct WalletStore {
    client: RwLock<Option<Arc<NwcClient>>>,
    status_tx: broadcast::Sender<Option<NwcWalletInfo>>,
}

impl WalletStore {
    fn new() -> Self {
        let (status_tx, _) = broadcast::channel(16);
        Self {
            client: RwLock::new(None),
            status_tx,
        }
    }

    /// Notify all status-change subscribers.
    fn notify(&self, info: Option<NwcWalletInfo>) {
        let _ = self.status_tx.send(info);
    }
}

// ── Global singleton ──────────────────────────────────────────────────────────

static WALLET_STORE: OnceLock<WalletStore> = OnceLock::new();

fn wallet_store() -> &'static WalletStore {
    WALLET_STORE.get_or_init(WalletStore::new)
}

// ── Public API ────────────────────────────────────────────────────────────────

/// Parse and connect a NWC wallet.
///
/// **URI format**: `nostr+walletconnect://<pubkey>?relay=<url>&secret=<hex>`
///
/// Validates the URI, creates an [NwcClient], calls `get_info()` to confirm
/// connectivity, and stores the client in memory.
///
/// **Errors**: `InvalidNwcUri`, `ConnectionFailed`.
pub async fn connect_wallet(nwc_uri: String) -> Result<NwcWalletInfo> {
    let mut client = NwcClient::new(&nwc_uri)
        .await
        .map_err(|e| anyhow!("InvalidNwcUri: {e}"))?;

    let info = client
        .get_info()
        .await
        .map_err(|e| anyhow!("ConnectionFailed: {e}"))?;

    // Fetch initial balance (non-fatal — some wallets don't support it).
    let balance = client.get_balance().await.ok().flatten();
    let info = NwcWalletInfo {
        balance_sats: balance,
        ..info
    };

    let store = wallet_store();
    let (had_existing, old_client) = {
        let mut guard = store.client.write().await;
        let old = guard.take();
        let had = old.is_some();
        *guard = Some(Arc::new(client));
        (had, old)
    };
    // Disconnect the old client outside the lock.
    if let Some(old) = old_client {
        old.disconnect().await;
    }
    // Notify disconnect before the new connection event so listeners can
    // cleanly transition from the old connection to the new one.
    if had_existing {
        store.notify(None);
    }
    store.notify(Some(info.clone()));
    Ok(info)
}

/// Disconnect the current wallet and clear stored credentials.
///
/// **Errors**: `NoWalletConnected`.
pub async fn disconnect_wallet() -> Result<()> {
    let store = wallet_store();
    let old = {
        let mut guard = store.client.write().await;
        guard
            .take()
            .ok_or_else(|| anyhow!("NoWalletConnected: no wallet is currently connected"))?
    };
    old.disconnect().await;
    store.notify(None);
    Ok(())
}

/// Return current wallet info, or `None` if no wallet is connected.
pub async fn get_wallet() -> Result<Option<NwcWalletInfo>> {
    let guard = wallet_store().client.read().await;
    Ok(guard.as_ref().map(|c| c.info.clone()))
}

/// Query wallet balance in satoshis (live from the wallet, not cached).
///
/// **Errors**: `NoWalletConnected`, `WalletError`.
pub async fn get_balance() -> Result<Option<u64>> {
    let client = {
        let guard = wallet_store().client.read().await;
        Arc::clone(
            guard
                .as_ref()
                .ok_or_else(|| anyhow!("NoWalletConnected: no wallet is currently connected"))?,
        )
    };
    client.get_balance().await
}

/// Pay a BOLT-11 invoice via the connected NWC wallet.
///
/// **Errors**: `NoWalletConnected`, `InvoiceInvalid`.
pub async fn pay_invoice(bolt11: String) -> Result<PaymentResult> {
    if bolt11.trim().is_empty() {
        bail!("InvoiceInvalid: bolt11 must not be empty");
    }

    let client = {
        let guard = wallet_store().client.read().await;
        Arc::clone(
            guard
                .as_ref()
                .ok_or_else(|| anyhow!("NoWalletConnected: no wallet is currently connected"))?,
        )
    };

    client.pay_invoice(&bolt11).await
}

/// Request the wallet to create a new Lightning invoice.
///
/// `amount_sats` is the invoice amount in satoshis (converted to msats
/// for the NIP-47 request).  Returns the BOLT-11 invoice string.
///
/// **Errors**: `NoWalletConnected`, `WalletError`.
pub async fn make_invoice(amount_sats: u64, description: Option<String>) -> Result<String> {
    if amount_sats == 0 {
        bail!("InvalidAmount: amount_sats must be greater than zero");
    }
    if amount_sats > u64::MAX / 1000 {
        bail!("InvalidAmount: amount_sats too large");
    }

    let client = {
        let guard = wallet_store().client.read().await;
        Arc::clone(
            guard
                .as_ref()
                .ok_or_else(|| anyhow!("NoWalletConnected: no wallet is currently connected"))?,
        )
    };

    client.make_invoice(amount_sats, description).await
}

// ── Stream ────────────────────────────────────────────────────────────────────

/// Stream that emits [NwcWalletInfo] (or `None` on disconnect) whenever the
/// wallet connection status changes.
pub struct WalletStatusStream {
    rx: broadcast::Receiver<Option<NwcWalletInfo>>,
}

impl WalletStatusStream {
    /// Poll for the next wallet status change.
    ///
    /// `RecvError::Lagged` is handled gracefully.
    pub async fn next(&mut self) -> Result<Option<NwcWalletInfo>> {
        loop {
            match self.rx.recv().await {
                Ok(info) => return Ok(info),
                Err(RecvError::Lagged(_)) => continue,
                Err(RecvError::Closed) => {
                    bail!("WalletStatusStream closed: channel sender dropped")
                }
            }
        }
    }
}

/// Subscribe to wallet status changes.
pub fn on_wallet_status_changed() -> WalletStatusStream {
    WalletStatusStream {
        rx: wallet_store().status_tx.subscribe(),
    }
}

// ── Tests ────────────────────────────────────────────────────────────────────

#[cfg(test)]
#[allow(clippy::await_holding_lock)]
mod tests {
    use super::*;
    use crate::api::types::WalletStatus;
    use std::sync::{Mutex, OnceLock as StdOnceLock};

    /// Serializes tests that modify the global WALLET_STORE so they don't
    /// race with each other (same pattern as `reputation` tests).
    fn wallet_lock() -> &'static Mutex<()> {
        static LOCK: StdOnceLock<Mutex<()>> = StdOnceLock::new();
        LOCK.get_or_init(|| Mutex::new(()))
    }

    #[tokio::test]
    async fn pay_invoice_rejects_empty_bolt11() {
        let err = pay_invoice(String::new()).await.unwrap_err();
        assert!(err.to_string().contains("InvoiceInvalid"));
    }

    #[tokio::test]
    async fn invalid_uri_returns_error() {
        let err = connect_wallet("not-a-valid-uri".into()).await.unwrap_err();
        assert!(err.to_string().contains("InvalidNwcUri"));
    }

    #[tokio::test]
    async fn disconnect_errors_when_not_connected() {
        let _g = wallet_lock().lock().unwrap();
        // Ensure we start clean.
        let _ = disconnect_wallet().await;
        let err = disconnect_wallet().await.unwrap_err();
        assert!(err.to_string().contains("NoWalletConnected"));
    }

    #[tokio::test]
    async fn pay_invoice_errors_when_not_connected() {
        let _g = wallet_lock().lock().unwrap();
        let _ = disconnect_wallet().await;
        let err = pay_invoice("lnbc1...".into()).await.unwrap_err();
        assert!(err.to_string().contains("NoWalletConnected"));
    }

    #[tokio::test]
    async fn make_invoice_rejects_zero_amount() {
        let err = make_invoice(0, None).await.unwrap_err();
        assert!(err.to_string().contains("InvalidAmount"));
    }

    #[tokio::test]
    async fn make_invoice_rejects_overflow_amount() {
        let err = make_invoice(u64::MAX, None).await.unwrap_err();
        assert!(err.to_string().contains("InvalidAmount"));
    }

    #[tokio::test]
    async fn make_invoice_errors_when_not_connected() {
        let _g = wallet_lock().lock().unwrap();
        let _ = disconnect_wallet().await;
        let err = make_invoice(1000, None).await.unwrap_err();
        assert!(err.to_string().contains("NoWalletConnected"));
    }

    #[tokio::test]
    async fn get_balance_errors_when_not_connected() {
        let _g = wallet_lock().lock().unwrap();
        let _ = disconnect_wallet().await;
        let err = get_balance().await.unwrap_err();
        assert!(err.to_string().contains("NoWalletConnected"));
    }

    // Tests that require a live NWC relay are marked #[ignore].
    // Run them with: cargo test -- --ignored

    #[tokio::test]
    #[ignore = "requires a live NWC relay"]
    async fn connect_stores_wallet_info() {
        let _g = wallet_lock().lock().unwrap();
        let uri = std::env::var("NWC_URI").expect("NWC_URI env var required");
        let info = connect_wallet(uri).await.unwrap();
        assert_eq!(info.status, WalletStatus::Connected);
        assert!(!info.wallet_pubkey.is_empty());
        assert!(!info.relay_urls.is_empty());
        let _ = disconnect_wallet().await;
    }

    #[tokio::test]
    #[ignore = "requires a live NWC relay"]
    async fn get_wallet_returns_info_after_connect() {
        let _g = wallet_lock().lock().unwrap();
        let uri = std::env::var("NWC_URI").expect("NWC_URI env var required");
        connect_wallet(uri).await.unwrap();
        let info = get_wallet().await.unwrap();
        assert!(info.is_some());
        let _ = disconnect_wallet().await;
    }

    #[tokio::test]
    #[ignore = "requires a live NWC relay"]
    async fn disconnect_clears_wallet() {
        let _g = wallet_lock().lock().unwrap();
        let uri = std::env::var("NWC_URI").expect("NWC_URI env var required");
        connect_wallet(uri).await.unwrap();
        disconnect_wallet().await.unwrap();
        let info = get_wallet().await.unwrap();
        assert!(info.is_none());
    }
}
