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
    let stored = db
        .get_setting(&crate::db::settings_keys::invoice_step_start(&order_id))
        .await
        .ok()
        .flatten()?;
    parse_step_start(&stored).map(|(_, ts)| ts)
}

/// Record that the daemon message dated `event_ts` opened `order_id`'s
/// invoice step in `status` (called from the AddInvoice / PayInvoice arms).
///
/// Kept apart from the status cursor, which every later accepted status
/// message advances: a re-sent or follow-up message for the same step must
/// not push the countdown out. The earliest timestamp of a step is kept; a
/// different status opens a new step.
pub(crate) async fn record_invoice_step_start(order_id: &str, status: &str, event_ts: i64) {
    // A message dated beyond the tolerated skew is not a trustworthy start.
    let horizon = crate::rt::unix_now()
        .saturating_add(crate::nostr::transport::MAX_CLOCK_SKEW_SECS as i64);
    if event_ts > horizon {
        return;
    }
    let Some(db) = crate::db::app_db::db() else {
        return;
    };
    let key = crate::db::settings_keys::invoice_step_start(order_id);
    let existing = db.get_setting(&key).await.ok().flatten();
    let Some(value) = next_step_start(existing.as_deref(), status, event_ts) else {
        return;
    };
    if let Err(e) = db.set_setting(&key, &value).await {
        log::warn!("[invoice] could not record step start for order={order_id}: {e}");
    }
}

/// The value to store for a step start of `status` at `event_ts`, or `None`
/// when the stored one already covers it (same status, same or earlier time).
fn next_step_start(existing: Option<&str>, status: &str, event_ts: i64) -> Option<String> {
    if let Some((stored_status, stored_ts)) = existing.and_then(parse_step_start) {
        if stored_status == status && stored_ts <= event_ts {
            return None;
        }
    }
    Some(format!("{status}:{event_ts}"))
}

/// `WaitingPayment:1757712000` → (`WaitingPayment`, 1757712000).
fn parse_step_start(value: &str) -> Option<(&str, i64)> {
    let (status, ts) = value.rsplit_once(':')?;
    Some((status, ts.parse().ok()?))
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
    fn a_later_message_for_the_same_step_does_not_move_its_start() {
        let first = next_step_start(None, "WaitingPayment", 1_000).expect("first write");
        assert_eq!(first, "WaitingPayment:1000");
        // A re-sent or follow-up PayInvoice dated later keeps the start.
        assert_eq!(next_step_start(Some(&first), "WaitingPayment", 1_500), None);
        assert_eq!(next_step_start(Some(&first), "WaitingPayment", 1_000), None);
        // An earlier copy (relay order) moves it back to the true start.
        assert_eq!(
            next_step_start(Some(&first), "WaitingPayment", 900).as_deref(),
            Some("WaitingPayment:900")
        );
    }

    #[test]
    fn a_new_status_opens_a_new_step() {
        let paid = "WaitingPayment:1000";
        assert_eq!(
            next_step_start(Some(paid), "WaitingBuyerInvoice", 1_600).as_deref(),
            Some("WaitingBuyerInvoice:1600")
        );
    }

    #[test]
    fn unreadable_stored_values_are_replaced() {
        assert_eq!(
            next_step_start(Some("garbage"), "WaitingPayment", 5).as_deref(),
            Some("WaitingPayment:5")
        );
        assert_eq!(parse_step_start("WaitingPayment:12"), Some(("WaitingPayment", 12)));
        assert_eq!(parse_step_start("WaitingPayment:x"), None);
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
