/// NWC client — URI parsing and wallet operations.
///
/// Parses `nostr+walletconnect://<pubkey>?relay=<url>&secret=<hex>` URIs,
/// holds the parsed credentials, and provides async methods for querying
/// wallet info and paying invoices via the Nostr Wallet Connect protocol.
///
/// Protocol message exchange (NIP-47) is deferred to Phase 15+ when the
/// full Nostr relay connection is wired.  The current implementation holds
/// the parsed state in-memory and returns stub responses that keep the Dart
/// UI functional without a live wallet.
use anyhow::{bail, Result};

use crate::api::types::{NwcWalletInfo, PaymentResult, WalletStatus};

// ── NWC URI ───────────────────────────────────────────────────────────────────

/// Parsed Nostr Wallet Connect URI.
///
/// Format: `nostr+walletconnect://<wallet_pubkey>?relay=<url>&secret=<hex>`
///
/// Multiple `relay=` params are allowed.
#[derive(Clone)]
pub struct NwcUri {
    /// Wallet service Nostr public key (64-char lowercase hex).
    pub wallet_pubkey: String,
    /// At least one relay URL.
    pub relay_urls: Vec<String>,
    /// 64-char hex secret used as the NWC client key.
    pub secret_hex: String,
}

impl std::fmt::Debug for NwcUri {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("NwcUri")
            .field("wallet_pubkey", &self.wallet_pubkey)
            .field("relay_urls", &self.relay_urls)
            .field("secret_hex", &"[REDACTED]")
            .finish()
    }
}

impl NwcUri {
    /// Parse a NWC URI string.
    ///
    /// **Errors**: `InvalidNwcUri` with a reason suffix on any validation failure.
    pub fn parse(uri: &str) -> Result<Self> {
        let uri = uri.trim();
        let rest = uri
            .strip_prefix("nostr+walletconnect://")
            .ok_or_else(|| anyhow::anyhow!("InvalidNwcUri: must start with nostr+walletconnect://"))?;

        // Split pubkey from query string.
        let (pubkey_part, query) = rest.split_once('?').unwrap_or((rest, ""));

        let wallet_pubkey = pubkey_part.trim().to_lowercase();
        if wallet_pubkey.len() != 64 || !wallet_pubkey.chars().all(|c| c.is_ascii_hexdigit()) {
            bail!("InvalidNwcUri: wallet pubkey must be a 64-char hex string");
        }

        let mut relay_urls = Vec::new();
        let mut secret_hex = String::new();

        for param in query.split('&') {
            if let Some(val) = param.strip_prefix("relay=") {
                let relay = urlencoding_decode(val);
                if !relay.starts_with("wss://") && !relay.starts_with("ws://") {
                    bail!("InvalidNwcUri: relay URL must start with wss:// or ws://");
                }
                relay_urls.push(relay);
            } else if let Some(val) = param.strip_prefix("secret=") {
                secret_hex = val.trim().to_lowercase();
            }
        }

        if relay_urls.is_empty() {
            bail!("InvalidNwcUri: at least one relay= parameter is required");
        }

        if secret_hex.len() != 64 || !secret_hex.chars().all(|c| c.is_ascii_hexdigit()) {
            bail!("InvalidNwcUri: secret must be a 64-char hex string");
        }

        Ok(Self {
            wallet_pubkey,
            relay_urls,
            secret_hex,
        })
    }
}

/// Minimal percent-decode for relay URL values (handles `%3A` → `:` etc.).
fn urlencoding_decode(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut chars = s.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '%' {
            let c1 = chars.next();
            let c2 = chars.next();
            match (
                c1.and_then(|ch| ch.to_digit(16)),
                c2.and_then(|ch| ch.to_digit(16)),
            ) {
                (Some(h1), Some(h2)) => {
                    out.push(char::from_u32(h1 * 16 + h2).unwrap_or('%'));
                }
                _ => {
                    out.push('%');
                    if let Some(ch) = c1 {
                        out.push(ch);
                    }
                    if let Some(ch) = c2 {
                        out.push(ch);
                    }
                }
            }
        } else {
            out.push(c);
        }
    }
    out
}

// ── NWC client ────────────────────────────────────────────────────────────────

/// In-memory NWC client holding parsed credentials and wallet state.
pub struct NwcClient {
    pub info: NwcWalletInfo,
    /// NWC client secret key (hex) — used to sign NIP-47 requests.
    pub(super) secret_hex: String,
}

impl NwcClient {
    /// Create a new client from a parsed [NwcUri].
    ///
    /// The wallet `name` and `balance` are populated lazily by [get_info].
    pub fn new(uri: &NwcUri) -> Self {
        Self {
            info: NwcWalletInfo {
                wallet_pubkey: uri.wallet_pubkey.clone(),
                wallet_name: None,
                status: WalletStatus::Connecting,
                balance_sats: None,
                relay_urls: uri.relay_urls.clone(),
                last_connected_at: None,
            },
            secret_hex: uri.secret_hex.clone(),
        }
    }

    /// Query wallet info (name, balance) via NIP-47 `get_info` request.
    ///
    /// TODO(Phase 15+): Send a signed `get_info` NIP-47 request to the
    /// wallet relay and await the response.  Currently marks the wallet as
    /// Connected and returns the info stored on construction.
    pub async fn get_info(&mut self) -> Result<NwcWalletInfo> {
        self.info.status = WalletStatus::Connected;
        self.info.last_connected_at = Some(unix_now());
        Ok(self.info.clone())
    }

    /// Query the wallet balance in satoshis.
    ///
    /// TODO(Phase 15+): Send a signed `get_balance` NIP-47 request.
    pub async fn get_balance(&self) -> Result<Option<u64>> {
        if self.info.status != WalletStatus::Connected {
            bail!("NoWalletConnected: wallet is not connected");
        }
        Ok(self.info.balance_sats)
    }

    /// Pay a BOLT-11 invoice via the connected wallet.
    ///
    /// TODO(Phase 15+): Construct and send a signed `pay_invoice` NIP-47
    /// request, wait for the response event, and return the preimage.
    pub async fn pay_invoice(&self, bolt11: &str) -> Result<PaymentResult> {
        if self.info.status != WalletStatus::Connected {
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
}

fn unix_now() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64
}

// ── Tests ────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    fn valid_pubkey() -> String {
        "a".repeat(64)
    }

    fn valid_secret() -> String {
        "b".repeat(64)
    }

    fn valid_uri() -> String {
        format!(
            "nostr+walletconnect://{}?relay=wss%3A%2F%2Frelay.example.com&secret={}",
            valid_pubkey(),
            valid_secret()
        )
    }

    #[test]
    fn parse_valid_uri() {
        let parsed = NwcUri::parse(&valid_uri()).unwrap();
        assert_eq!(parsed.wallet_pubkey, valid_pubkey());
        assert_eq!(parsed.relay_urls, vec!["wss://relay.example.com"]);
        assert_eq!(parsed.secret_hex, valid_secret());
    }

    #[test]
    fn parse_rejects_missing_prefix() {
        let err = NwcUri::parse("nostr+connect://aaaa").unwrap_err();
        assert!(err.to_string().contains("InvalidNwcUri"));
    }

    #[test]
    fn parse_rejects_short_pubkey() {
        let uri = format!(
            "nostr+walletconnect://short?relay=wss://r.io&secret={}",
            valid_secret()
        );
        let err = NwcUri::parse(&uri).unwrap_err();
        assert!(err.to_string().contains("InvalidNwcUri"));
    }

    #[test]
    fn parse_rejects_missing_relay() {
        let uri = format!(
            "nostr+walletconnect://{}?secret={}",
            valid_pubkey(),
            valid_secret()
        );
        let err = NwcUri::parse(&uri).unwrap_err();
        assert!(err.to_string().contains("relay"));
    }

    #[test]
    fn parse_rejects_invalid_relay_scheme() {
        let uri = format!(
            "nostr+walletconnect://{}?relay=http://relay.io&secret={}",
            valid_pubkey(),
            valid_secret()
        );
        let err = NwcUri::parse(&uri).unwrap_err();
        assert!(err.to_string().contains("relay URL must start"));
    }

    #[test]
    fn parse_rejects_short_secret() {
        let uri = format!(
            "nostr+walletconnect://{}?relay=wss://r.io&secret=abc",
            valid_pubkey()
        );
        let err = NwcUri::parse(&uri).unwrap_err();
        assert!(err.to_string().contains("InvalidNwcUri"));
    }

    #[tokio::test]
    async fn get_info_marks_connected() {
        let uri = NwcUri::parse(&valid_uri()).unwrap();
        let mut client = NwcClient::new(&uri);
        assert_eq!(client.info.status, WalletStatus::Connecting);
        let info = client.get_info().await.unwrap();
        assert_eq!(info.status, WalletStatus::Connected);
        assert!(info.last_connected_at.is_some());
    }

    #[tokio::test]
    async fn pay_invoice_returns_not_implemented() {
        let uri = NwcUri::parse(&valid_uri()).unwrap();
        let mut client = NwcClient::new(&uri);
        client.get_info().await.unwrap();
        let result = client.pay_invoice("lnbc1...").await.unwrap();
        assert!(!result.success);
        assert!(result.error.as_deref().unwrap_or("").contains("NotImplemented"));
    }
}
