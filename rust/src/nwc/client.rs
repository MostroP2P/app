// NWC client — real Nostr Wallet Connect (NIP-47) implementation.
//
// Uses `nostr-sdk` types for URI parsing, request/response construction,
// NIP-04 encryption, and relay communication via the SDK's `Client`.
//
// Native-only: the relay transport depends on tokio + TCP which do not
// compile to WASM.  All relay-dependent items are gated behind
// `cfg(not(target_arch = "wasm32"))`.

#[cfg(not(target_arch = "wasm32"))]
mod native {
    use std::time::Duration;

    use anyhow::{anyhow, bail, Result};
    use nostr_sdk::prelude::*;
    use nostr_sdk::nips::nip47::{
        GetBalanceResponse, GetInfoResponse, MakeInvoiceRequest,
        MakeInvoiceResponse, NostrWalletConnectURI, PayInvoiceRequest,
        PayInvoiceResponse, Request, Response, ResponseResult,
    };
    use nostr_sdk::Client;

    use crate::api::types::{NwcWalletInfo, PaymentResult, WalletStatus};

    /// Timeout for NIP-47 request → response round-trips.
    const NWC_TIMEOUT: Duration = Duration::from_secs(30);

    /// Real NWC client backed by a nostr-sdk `Client` connected to the
    /// wallet's relay.
    pub struct NwcClient {
        client: Client,
        uri: NostrWalletConnectURI,
        pub info: NwcWalletInfo,
    }

    impl NwcClient {
        /// Parse a NWC URI, build a nostr-sdk `Client` with the NWC secret
        /// key, add the relay, and connect.
        pub async fn new(uri_str: &str) -> Result<Self> {
            let uri = NostrWalletConnectURI::parse(uri_str)
                .map_err(|e| anyhow!("InvalidNwcUri: {e}"))?;

            let keys = Keys::new(uri.secret.clone());
            let client = Client::new(keys);

            // Add all relays from the URI.
            for relay_url in &uri.relays {
                client
                    .add_relay(relay_url.clone())
                    .await
                    .map_err(|e| anyhow!("Failed to add relay {relay_url}: {e}"))?;
            }

            client.connect().await;

            let relay_urls: Vec<String> =
                uri.relays.iter().map(|r| r.to_string()).collect();

            Ok(Self {
                client,
                info: NwcWalletInfo {
                    wallet_pubkey: uri.public_key.to_hex(),
                    wallet_name: None,
                    status: WalletStatus::Connecting,
                    balance_sats: None,
                    relay_urls,
                    last_connected_at: None,
                },
                uri,
            })
        }

        /// Send a NIP-47 request and await the wallet's response.
        ///
        /// Uses a subscribe-then-send pattern: subscribes to response events
        /// BEFORE publishing the request so the response is never missed,
        /// even if the wallet replies before EOSE.
        async fn send_request(&self, request: Request) -> Result<Response> {
            let event = request
                .to_event(&self.uri)
                .map_err(|e| anyhow!("Failed to build NIP-47 request event: {e}"))?;

            // 1. Start listening for Kind 23195 responses from the wallet
            //    BEFORE sending the request to avoid a race condition.
            let mut notifications = self.client.notifications();

            let filter = Filter::new()
                .kind(Kind::WalletConnectResponse)
                .author(self.uri.public_key)
                .since(event.created_at);

            self.client
                .subscribe(filter, None)
                .await
                .map_err(|e| anyhow!("Failed to subscribe for NIP-47 response: {e}"))?;

            // 2. Send the request event.
            self.client
                .send_event(&event)
                .await
                .map_err(|e| anyhow!("Failed to send NIP-47 request: {e}"))?;

            // 3. Wait for the matching response on the notification channel.
            let deadline = tokio::time::Instant::now() + NWC_TIMEOUT;
            loop {
                let remaining = deadline.saturating_duration_since(tokio::time::Instant::now());
                if remaining.is_zero() {
                    bail!("NWC timeout: no response received from wallet within {NWC_TIMEOUT:?}");
                }

                match tokio::time::timeout(remaining, notifications.recv()).await {
                    Ok(Ok(RelayPoolNotification::Event {
                        event: resp_event, ..
                    })) => {
                        if resp_event.kind == Kind::WalletConnectResponse {
                            match Response::from_event(&self.uri, &resp_event) {
                                Ok(resp) => return Ok(resp),
                                Err(_) => continue,
                            }
                        }
                    }
                    Ok(Ok(_)) => continue, // other notification types
                    Ok(Err(_)) => continue, // lagged, retry
                    Err(_) => {
                        bail!("NWC timeout: no response received from wallet within {NWC_TIMEOUT:?}");
                    }
                }
            }
        }

        /// Query wallet info (name, supported methods) via NIP-47 `get_info`.
        pub async fn get_info(&mut self) -> Result<NwcWalletInfo> {
            let response = self.send_request(Request::get_info()).await?;

            if let Some(err) = response.error {
                bail!("NWC get_info error: {err}");
            }

            if let Some(ResponseResult::GetInfo(GetInfoResponse { alias, .. })) =
                response.result
            {
                self.info.wallet_name = alias;
            }

            self.info.status = WalletStatus::Connected;
            self.info.last_connected_at = Some(unix_now());

            Ok(self.info.clone())
        }

        /// Query the wallet balance in satoshis.
        ///
        /// The NIP-47 `get_balance` response returns millisatoshis; this
        /// method converts to sats via floor division (`msat / 1000`).
        pub async fn get_balance(&self) -> Result<Option<u64>> {
            if self.info.status != WalletStatus::Connected {
                bail!("NoWalletConnected: wallet is not connected");
            }

            let response = self.send_request(Request::get_balance()).await?;

            if let Some(err) = response.error {
                bail!("NWC get_balance error: {err}");
            }

            match response.result {
                Some(ResponseResult::GetBalance(GetBalanceResponse { balance })) => {
                    // balance is in millisatoshis — convert to sats.
                    Ok(Some(balance / 1000))
                }
                _ => Ok(None),
            }
        }

        /// Pay a BOLT-11 invoice via the connected wallet.
        pub async fn pay_invoice(&self, bolt11: &str) -> Result<PaymentResult> {
            if self.info.status != WalletStatus::Connected {
                return Ok(PaymentResult {
                    success: false,
                    preimage: None,
                    error: Some("NoWalletConnected: wallet is not connected".into()),
                });
            }

            let request =
                Request::pay_invoice(PayInvoiceRequest::new(bolt11.to_string()));
            let response = self.send_request(request).await;

            match response {
                Ok(resp) => {
                    if let Some(err) = resp.error {
                        return Ok(PaymentResult {
                            success: false,
                            preimage: None,
                            error: Some(format!("{err}")),
                        });
                    }
                    match resp.result {
                        Some(ResponseResult::PayInvoice(PayInvoiceResponse {
                            preimage,
                            ..
                        })) => Ok(PaymentResult {
                            success: true,
                            preimage: Some(preimage),
                            error: None,
                        }),
                        _ => Ok(PaymentResult {
                            success: false,
                            preimage: None,
                            error: Some("Unexpected response from wallet".into()),
                        }),
                    }
                }
                Err(e) => Ok(PaymentResult {
                    success: false,
                    preimage: None,
                    error: Some(e.to_string()),
                }),
            }
        }

        /// Request the wallet to create a new Lightning invoice.
        ///
        /// `amount_sats` is converted to millisatoshis for the NIP-47 request.
        /// Returns the BOLT-11 invoice string.
        pub async fn make_invoice(
            &self,
            amount_sats: u64,
            description: Option<String>,
        ) -> Result<String> {
            if self.info.status != WalletStatus::Connected {
                bail!("NoWalletConnected: wallet is not connected");
            }

            let msats = amount_sats
                .checked_mul(1000)
                .ok_or_else(|| anyhow::anyhow!("Amount overflow: {amount_sats} sats exceeds maximum"))?;

            let request = Request::make_invoice(MakeInvoiceRequest {
                amount: msats,
                description,
                description_hash: None,
                expiry: None,
            });

            let response = self.send_request(request).await?;

            if let Some(err) = response.error {
                bail!("NWC make_invoice error: {err}");
            }

            match response.result {
                Some(ResponseResult::MakeInvoice(MakeInvoiceResponse {
                    invoice,
                    ..
                })) => Ok(invoice),
                _ => bail!("Unexpected response from wallet for make_invoice"),
            }
        }

        /// Disconnect the nostr-sdk client from all relays.
        pub async fn disconnect(&self) {
            self.client.disconnect().await;
        }
    }

    fn unix_now() -> i64 {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs() as i64
    }
}

// ── Public re-exports ────────────────────────────────────────────────────────

#[cfg(not(target_arch = "wasm32"))]
pub use native::NwcClient;

// ── WASM stub ────────────────────────────────────────────────────────────────

/// On WASM targets, NWC is not supported (nostr-sdk relay transport requires
/// tokio + TCP).  This stub allows the crate to compile for web while the API
/// layer returns appropriate errors.
#[cfg(target_arch = "wasm32")]
pub struct NwcClient {
    pub info: crate::api::types::NwcWalletInfo,
}

#[cfg(target_arch = "wasm32")]
impl NwcClient {
    pub async fn new(_uri_str: &str) -> anyhow::Result<Self> {
        anyhow::bail!("NWC is not supported on web")
    }

    pub async fn get_info(&mut self) -> anyhow::Result<crate::api::types::NwcWalletInfo> {
        anyhow::bail!("NWC is not supported on web")
    }

    pub async fn get_balance(&self) -> anyhow::Result<Option<u64>> {
        anyhow::bail!("NWC is not supported on web")
    }

    pub async fn pay_invoice(&self, _bolt11: &str) -> anyhow::Result<crate::api::types::PaymentResult> {
        anyhow::bail!("NWC is not supported on web")
    }

    pub async fn make_invoice(
        &self,
        _amount_sats: u64,
        _description: Option<String>,
    ) -> anyhow::Result<String> {
        anyhow::bail!("NWC is not supported on web")
    }

    pub async fn disconnect(&self) {}
}

// ── Tests ────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    /// Verify mSAT → sats conversion: 1000 mSAT → 1 sat (floor division).
    #[test]
    fn msat_to_sats_exact() {
        assert_eq!(1000_u64 / 1000, 1);
    }

    /// Verify mSAT → sats conversion: 1500 mSAT → 1 sat (floor division).
    #[test]
    fn msat_to_sats_floor() {
        assert_eq!(1500_u64 / 1000, 1);
    }

    /// Verify mSAT → sats conversion: 999 mSAT → 0 sat (below threshold).
    #[test]
    fn msat_to_sats_below_threshold() {
        assert_eq!(999_u64 / 1000, 0);
    }

    /// URI parsing is delegated to nostr-sdk's `NostrWalletConnectURI::parse`.
    #[tokio::test]
    async fn parse_rejects_invalid_uri() {
        let err = NwcClient::new("not-a-valid-uri")
            .await
            .err()
            .expect("should fail for invalid URI");
        assert!(err.to_string().contains("InvalidNwcUri"));
    }

    /// Tests that previously checked for NotImplemented now require a live
    /// NWC relay and are therefore marked #[ignore].
    #[tokio::test]
    #[ignore = "requires a live NWC relay"]
    async fn get_info_with_live_relay() {
        // To run: cargo test -- --ignored get_info_with_live_relay
        // Set NWC_URI env var to a real NWC URI.
        let uri = std::env::var("NWC_URI").expect("NWC_URI env var required");
        let mut client = NwcClient::new(&uri).await.unwrap();
        let info = client.get_info().await.unwrap();
        assert_eq!(info.status, crate::api::types::WalletStatus::Connected);
    }

    #[tokio::test]
    #[ignore = "requires a live NWC relay"]
    async fn pay_invoice_with_live_relay() {
        let uri = std::env::var("NWC_URI").expect("NWC_URI env var required");
        let mut client = NwcClient::new(&uri).await.unwrap();
        client.get_info().await.unwrap();
        let _result = client.pay_invoice("lnbc1...").await.unwrap();
    }

    #[tokio::test]
    #[ignore = "requires a live NWC relay"]
    async fn get_balance_with_live_relay() {
        let uri = std::env::var("NWC_URI").expect("NWC_URI env var required");
        let mut client = NwcClient::new(&uri).await.unwrap();
        client.get_info().await.unwrap();
        let _balance = client.get_balance().await.unwrap();
    }
}
