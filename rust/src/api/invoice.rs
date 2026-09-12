//! Local reading of a BOLT11 invoice, so the add-invoice screen can tell the
//! buyer what is wrong with it before the daemon does.
//!
//! Advisory only: the daemon remains the authority on whether an invoice is
//! accepted. Nothing here touches the network or a key.

use std::str::FromStr;

use lightning_invoice::{Bolt11Invoice, Currency};

use crate::api::types::Bolt11Summary;
use crate::db::Storage;

/// The `lightning:` URI scheme a QR code or a wallet share may prepend.
const URI_SCHEME: &str = "lightning:";

/// Amount and expiry of `invoice`, or `None` when it is not a well-formed,
/// correctly signed BOLT11 invoice. A `lightning:` prefix and surrounding
/// whitespace are ignored; case is not significant.
pub fn decode_bolt11(invoice: String) -> Option<Bolt11Summary> {
    summarize(&invoice)
}

/// Unix seconds (the node's clock) of the daemon message that moved
/// `order_id` into its current status, or `None` when none was recorded.
/// Native (SQLite) and web (IndexedDB, since #246) both persist it.
///
/// mostrod times a waiting step from `taken_at` (`scheduler.rs`), which this
/// message carries; the invoice screens add the node's `expiration_seconds`
/// to it for their countdown.
pub async fn trade_step_started_at(order_id: String) -> Option<i64> {
    let db = crate::db::app_db::db()?;
    db.get_setting(&crate::db::settings_keys::status_cursor(&order_id))
        .await
        .ok()
        .flatten()?
        .parse()
        .ok()
}

fn summarize(input: &str) -> Option<Bolt11Summary> {
    let trimmed = input.trim();
    let bare = match trimmed.get(..URI_SCHEME.len()) {
        Some(head) if head.eq_ignore_ascii_case(URI_SCHEME) => &trimmed[URI_SCHEME.len()..],
        _ => trimmed,
    };
    let parsed = Bolt11Invoice::from_str(&bare.to_ascii_lowercase()).ok()?;
    let created = parsed.duration_since_epoch().as_secs();
    let expires = created.saturating_add(parsed.expiry_time().as_secs());
    Some(Bolt11Summary {
        amount_msat: parsed.amount_milli_satoshis(),
        expires_at: i64::try_from(expires).unwrap_or(i64::MAX),
        network: lnd_network_name(parsed.currency()).to_string(),
    })
}

fn lnd_network_name(currency: Currency) -> &'static str {
    match currency {
        Currency::Bitcoin => "mainnet",
        Currency::BitcoinTestnet => "testnet",
        Currency::Regtest => "regtest",
        Currency::Signet => "signet",
        Currency::Simnet => "simnet",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// BOLT11 spec test vector: "Please send $3 for a cup of coffee to the
    /// same peer, within one minute" — 2 500 µBTC (250 000 sats), timestamp
    /// 1496314658, expiry 60 s.
    const COFFEE: &str = "lnbc2500u1pvjluezsp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygspp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdq5xysxxatsyp3k7enxv4jsxqzpu9qrsgquk0rl77nj30yxdy8j9vdx85fkpmdla2087ne0xh8nhedh8w27kyke0lp53ut353s06fv3qfegext0eh0ymjpf39tuven09sam30g4vgpfna3rh";

    /// BOLT11 spec test vector with no amount ("donation").
    const DONATION: &str = "lnbc1pvjluezsp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygspp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdpl2pkx2ctnv5sxxmmwwd5kgetjypeh2ursdae8g6twvus8g6rfwvs8qun0dfjkxaq9qrsgq357wnc5r2ueh7ck6q93dj32dlqnls087fxdwk8qakdyafkq3yap9us6v52vjjsrvywa6rt52cm9r9zqt8r2t7mlcwspyetp5h2tztugp9lfyql";

    #[test]
    fn reads_amount_and_expiry() {
        let summary = summarize(COFFEE).expect("spec vector decodes");
        assert_eq!(summary.amount_msat, Some(250_000_000));
        assert_eq!(summary.expires_at, 1_496_314_658 + 60);
        assert_eq!(summary.network, "mainnet");
    }

    #[test]
    fn an_invoice_without_amount_reports_none() {
        let summary = summarize(DONATION).expect("spec vector decodes");
        assert_eq!(summary.amount_msat, None);
    }

    #[test]
    fn every_currency_maps_to_an_lnd_network_name() {
        assert_eq!(lnd_network_name(Currency::Bitcoin), "mainnet");
        assert_eq!(lnd_network_name(Currency::BitcoinTestnet), "testnet");
        assert_eq!(lnd_network_name(Currency::Regtest), "regtest");
        assert_eq!(lnd_network_name(Currency::Signet), "signet");
        assert_eq!(lnd_network_name(Currency::Simnet), "simnet");
    }

    #[test]
    fn ignores_scheme_case_and_whitespace() {
        let wrapped = format!("  LIGHTNING:{}\n", COFFEE.to_ascii_uppercase());
        assert_eq!(summarize(&wrapped), summarize(COFFEE));
    }

    #[test]
    fn rejects_what_is_not_an_invoice() {
        assert!(summarize("").is_none());
        assert!(summarize("lnbc1short").is_none());
        assert!(summarize("satoshi@example.com").is_none());
        // One flipped character breaks the checksum.
        let corrupted = COFFEE.replacen("lnbc2500u1", "lnbc2500u2", 1);
        assert!(summarize(&corrupted).is_none());
    }
}
