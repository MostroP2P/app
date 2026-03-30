/// NWC API — Nostr Wallet Connect integration.
///
/// Provides `connect_wallet`, `disconnect_wallet`, `get_wallet`,
/// `get_balance`, and `pay_invoice` functions, plus a status-change stream.
///
/// The underlying NIP-47 protocol exchange is handled by [`crate::nwc::client`].
/// Live relay I/O is deferred to Phase 15+ once the bridge FFI bindings are
/// generated; the API surface is fully functional today for UI integration.
use anyhow::{anyhow, bail, Result};
use std::sync::OnceLock;
use tokio::sync::{broadcast, RwLock};
use tokio::sync::broadcast::error::RecvError;

use crate::api::types::{NwcWalletInfo, PaymentResult, WalletStatus};
use crate::nwc::client::{NwcClient, NwcUri};

// ── Wallet store ──────────────────────────────────────────────────────────────

struct WalletStore {
    client: RwLock<Option<NwcClient>>,
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
    let uri = NwcUri::parse(&nwc_uri)
        .map_err(|e| anyhow!("InvalidNwcUri: {e}"))?;

    let mut client = NwcClient::new(&uri);

    let info = client
        .get_info()
        .await
        .map_err(|e| anyhow!("ConnectionFailed: {e}"))?;

    let store = wallet_store();
    let had_existing = {
        let mut guard = store.client.write().await;
        let had = guard.is_some();
        *guard = Some(client);
        had
    };
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
    {
        let mut guard = store.client.write().await;
        if guard.is_none() {
            bail!("NoWalletConnected: no wallet is currently connected");
        }
        *guard = None;
    }
    store.notify(None);
    Ok(())
}

/// Return current wallet info, or `None` if no wallet is connected.
pub async fn get_wallet() -> Result<Option<NwcWalletInfo>> {
    let guard = wallet_store().client.read().await;
    Ok(guard.as_ref().map(|c| c.info.clone()))
}

/// Query wallet balance in satoshis.
///
/// **Errors**: `NoWalletConnected`, `WalletError`.
pub async fn get_balance() -> Result<Option<u64>> {
    let (status, balance) = {
        let guard = wallet_store().client.read().await;
        let client = guard
            .as_ref()
            .ok_or_else(|| anyhow!("NoWalletConnected: no wallet is currently connected"))?;
        (client.info.status.clone(), client.info.balance_sats)
    };
    if status != WalletStatus::Connected {
        bail!("NoWalletConnected: wallet is not connected");
    }
    Ok(balance)
}

/// Pay a BOLT-11 invoice via the connected NWC wallet.
///
/// **Errors**: `NoWalletConnected`, `InvoiceInvalid`.
pub async fn pay_invoice(bolt11: String) -> Result<PaymentResult> {
    if bolt11.trim().is_empty() {
        bail!("InvoiceInvalid: bolt11 must not be empty");
    }
    let status = {
        let guard = wallet_store().client.read().await;
        guard
            .as_ref()
            .map(|c| c.info.status.clone())
            .ok_or_else(|| anyhow!("NoWalletConnected: no wallet is currently connected"))?
    };
    if status != WalletStatus::Connected {
        return Ok(PaymentResult {
            success: false,
            preimage: None,
            error: Some("NoWalletConnected: wallet is not connected".into()),
        });
    }
    // TODO(Phase 15+): send NIP-47 pay_invoice request and await result.
    Ok(PaymentResult {
        success: false,
        preimage: None,
        error: Some("NotImplemented: NIP-47 pay_invoice not yet wired".into()),
    })
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
mod tests {
    use super::*;
    use std::sync::{Mutex, OnceLock as StdOnceLock};

    /// Serializes tests that modify the global WALLET_STORE so they don't
    /// race with each other (same pattern as `reputation` tests).
    fn wallet_lock() -> &'static Mutex<()> {
        static LOCK: StdOnceLock<Mutex<()>> = StdOnceLock::new();
        LOCK.get_or_init(|| Mutex::new(()))
    }

    fn valid_uri() -> String {
        format!(
            "nostr+walletconnect://{}?relay=wss%3A%2F%2Frelay.example.com&secret={}",
            "a".repeat(64),
            "b".repeat(64)
        )
    }

    #[tokio::test]
    async fn connect_stores_wallet_info() {
        let _g = wallet_lock().lock().unwrap();
        let info = connect_wallet(valid_uri()).await.unwrap();
        assert_eq!(info.status, WalletStatus::Connected);
        assert!(!info.wallet_pubkey.is_empty());
        assert!(!info.relay_urls.is_empty());
        let _ = disconnect_wallet().await;
    }

    #[tokio::test]
    async fn get_wallet_returns_info_after_connect() {
        let _g = wallet_lock().lock().unwrap();
        connect_wallet(valid_uri()).await.unwrap();
        let info = get_wallet().await.unwrap();
        assert!(info.is_some());
        let _ = disconnect_wallet().await;
    }

    #[tokio::test]
    async fn disconnect_clears_wallet() {
        let _g = wallet_lock().lock().unwrap();
        connect_wallet(valid_uri()).await.unwrap();
        disconnect_wallet().await.unwrap();
        let info = get_wallet().await.unwrap();
        assert!(info.is_none());
    }

    #[tokio::test]
    async fn disconnect_errors_when_not_connected() {
        let _g = wallet_lock().lock().unwrap();
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
    async fn pay_invoice_rejects_empty_bolt11() {
        let err = pay_invoice(String::new()).await.unwrap_err();
        assert!(err.to_string().contains("InvoiceInvalid"));
    }

    #[tokio::test]
    async fn invalid_uri_returns_error() {
        let err = connect_wallet("not-a-valid-uri".into()).await.unwrap_err();
        assert!(err.to_string().contains("InvalidNwcUri"));
    }
}
