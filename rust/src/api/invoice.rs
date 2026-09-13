//! Everything this client decides about a Lightning payment destination —
//! what it is, what it asks for, and whether the daemon would accept it —
//! in one place, on top of the `lightning-invoice` crate.
//!
//! Three callers, one answer: the add-invoice screen (validation row and
//! submit gate), `orders::send_invoice` (invoice vs. Lightning address, and
//! a last refusal before anything is published) and the NWC payer (never
//! hand the wallet something that is not an invoice). Dart no longer looks
//! at the string itself.
//!
//! Advisory only: the daemon remains the authority on whether an invoice is
//! accepted. The checks here reproduce mostrod's `is_valid_invoice` — amount,
//! expiry, remaining lifetime, chain — so the user hears the same refusal
//! locally, without a relay round trip. Nothing here touches the network or
//! a key.

use std::str::FromStr;

use lightning_invoice::{Bolt11Invoice, Currency};

use crate::api::types::{Bolt11Summary, InvoiceProblem, InvoiceVerdict, PaymentDestination};
use crate::db::Storage;

/// The `lightning:` URI scheme a QR code or a wallet share may prepend.
const URI_SCHEME: &str = "lightning:";

/// Human-readable-part prefixes of a BOLT11 invoice: mainnet, testnet /
/// signet (`lntb…`, `lntbs…`), regtest (`lnbcrt…`) and simnet.
const BOLT11_PREFIXES: [&str; 3] = ["lnbc", "lntb", "lnsb"];

/// Amount and expiry of `invoice`, or `None` when it is not a well-formed,
/// correctly signed BOLT11 invoice. A `lightning:` prefix and surrounding
/// whitespace are ignored; case is not significant.
pub fn decode_bolt11(invoice: String) -> Option<Bolt11Summary> {
    summarize(&invoice)
}

/// What `input` is: an invoice, a Lightning address, or neither.
pub fn classify_payment_destination(input: String) -> PaymentDestination {
    classify(&input)
}

/// Judge `input` for a trade that pays `expected_sats` (`None` while the
/// amount is not known yet), against a node on `node_networks` (its
/// `lnd_networks`; empty skips the chain check) that demands
/// `min_remaining_secs` of invoice lifetime (its `invoice_expiration_window`;
/// `None` skips it). `now` is unix seconds — the caller's clock, the same one
/// its countdown runs on.
pub fn check_buyer_invoice(
    input: String,
    expected_sats: Option<u64>,
    node_networks: Vec<String>,
    min_remaining_secs: Option<u64>,
    now: i64,
) -> InvoiceVerdict {
    check(
        classify(&input),
        expected_sats,
        &node_networks,
        min_remaining_secs,
        now,
    )
}

/// `input` without surrounding whitespace or a `lightning:` prefix — what
/// gets sent to the daemon or the wallet, case preserved (BOLT11 allows
/// all-lower or all-upper, and the decoder lowers its own copy).
pub(crate) fn normalize(input: &str) -> &str {
    let trimmed = input.trim();
    match trimmed.get(..URI_SCHEME.len()) {
        Some(head) if head.eq_ignore_ascii_case(URI_SCHEME) => trimmed[URI_SCHEME.len()..].trim(),
        _ => trimmed,
    }
}

pub(crate) fn classify(input: &str) -> PaymentDestination {
    let bare = normalize(input);
    if bare.is_empty() {
        return PaymentDestination::Empty;
    }
    let lower = bare.to_ascii_lowercase();
    if BOLT11_PREFIXES.iter().any(|p| lower.starts_with(p)) {
        return match summarize(bare) {
            Some(summary) => PaymentDestination::Bolt11(summary),
            None => PaymentDestination::MalformedBolt11,
        };
    }
    if is_lightning_address(&lower) {
        return PaymentDestination::LightningAddress(lower);
    }
    PaymentDestination::Unknown
}

/// `user@domain` (LUD-16), on an already lower-cased input: the user part is
/// `a-z0-9-_.+`, the domain is two or more non-empty labels of letters,
/// digits and inner hyphens, ending in an alphabetic TLD — no empty labels
/// (`..`, leading or trailing dot) and no URL delimiters.
fn is_lightning_address(lower: &str) -> bool {
    let Some((user, domain)) = lower.split_once('@') else {
        return false;
    };
    if user.is_empty()
        || !user
            .bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b"._+-".contains(&b))
    {
        return false;
    }
    let labels: Vec<&str> = domain.split('.').collect();
    if labels.len() < 2 {
        return false;
    }
    let label_ok = |label: &str| {
        !label.is_empty()
            && !label.starts_with('-')
            && !label.ends_with('-')
            && label
                .bytes()
                .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
    };
    if !labels.iter().all(|l| label_ok(l)) {
        return false;
    }
    let tld = labels[labels.len() - 1];
    tld.len() >= 2 && tld.bytes().all(|b| b.is_ascii_lowercase())
}

/// The pure verdict, so every rule is testable on a synthetic summary.
pub(crate) fn check(
    destination: PaymentDestination,
    expected_sats: Option<u64>,
    node_networks: &[String],
    min_remaining_secs: Option<u64>,
    now: i64,
) -> InvoiceVerdict {
    let plain = |problem: InvoiceProblem| rejected_with(problem, None, None, None, None, None);
    let summary = match destination {
        PaymentDestination::Empty => return InvoiceVerdict::Empty,
        PaymentDestination::Unknown => return plain(InvoiceProblem::Unrecognized),
        PaymentDestination::MalformedBolt11 => return plain(InvoiceProblem::Malformed),
        PaymentDestination::LightningAddress(_) => return InvoiceVerdict::Address,
        PaymentDestination::Bolt11(summary) => summary,
    };

    // An invoice for another chain is refused here rather than when the
    // daemon tries to pay it.
    if !node_networks.is_empty() && !network_matches(&summary.network, node_networks) {
        return rejected_with(
            InvoiceProblem::WrongNetwork,
            None,
            None,
            Some(summary.network),
            node_networks.first().map(|n| n.trim().to_string()),
            None,
        );
    }
    if summary.expires_at <= now {
        return plain(InvoiceProblem::Expired);
    }
    // mostrod's `invoice_expiration_window`: an invoice that expires before
    // the payout could be attempted is refused as invalid by the daemon.
    if let Some(min) = min_remaining_secs {
        let remaining = summary.expires_at.saturating_sub(now);
        if u64::try_from(remaining).unwrap_or(0) < min {
            return rejected_with(
                InvoiceProblem::ExpiresTooSoon,
                None,
                None,
                None,
                None,
                Some(min),
            );
        }
    }
    // An open-amount invoice is the daemon's to accept or refuse.
    let (Some(actual), Some(expected)) = (summary.amount_msat, expected_sats) else {
        return InvoiceVerdict::Unverified;
    };
    // Compared in msat: 250 500 msat is not a 250 sats invoice.
    if Some(actual) != expected.checked_mul(1_000) {
        return rejected_with(
            InvoiceProblem::WrongAmount,
            Some(actual),
            Some(expected),
            None,
            None,
            None,
        );
    }
    InvoiceVerdict::Valid {
        sats: expected,
        expires_at: summary.expires_at,
    }
}

/// A `Rejected` verdict with only the fields the problem's copy needs.
fn rejected_with(
    problem: InvoiceProblem,
    actual_msat: Option<u64>,
    expected_sats: Option<u64>,
    invoice_network: Option<String>,
    node_network: Option<String>,
    min_remaining_secs: Option<u64>,
) -> InvoiceVerdict {
    InvoiceVerdict::Rejected {
        problem,
        actual_msat,
        expected_sats,
        invoice_network,
        node_network,
        min_remaining_secs,
    }
}

/// Whether an invoice for `invoice_network` can be paid by a node that lists
/// `node_networks` (its `lnd_networks`). LND names testnet generations
/// `testnet`, `testnet3`, `testnet4`; BOLT11 tells them all `lntb`.
fn network_matches(invoice_network: &str, node_networks: &[String]) -> bool {
    fn family(name: &str) -> String {
        let lower = name.trim().to_ascii_lowercase();
        if lower.starts_with("testnet") {
            "testnet".to_string()
        } else {
            lower
        }
    }
    let wanted = family(invoice_network);
    node_networks.iter().any(|n| family(n) == wanted)
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
    let bare = normalize(input);
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

/// BOLT11 spec test vectors, shared with the tests of the callers.
#[cfg(test)]
pub(crate) mod test_vectors {
    /// "Please send $3 for a cup of coffee to the same peer, within one
    /// minute" — 2 500 µBTC (250 000 sats), timestamp 1496314658, expiry 60 s.
    pub(crate) const COFFEE: &str = "lnbc2500u1pvjluezsp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygspp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdq5xysxxatsyp3k7enxv4jsxqzpu9qrsgquk0rl77nj30yxdy8j9vdx85fkpmdla2087ne0xh8nhedh8w27kyke0lp53ut353s06fv3qfegext0eh0ymjpf39tuven09sam30g4vgpfna3rh";
}

#[cfg(test)]
mod tests {
    use super::test_vectors::COFFEE;
    use super::*;

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

    // ── classify ────────────────────────────────────────────────────────────

    #[test]
    fn tells_the_shapes_apart() {
        assert_eq!(classify("  "), PaymentDestination::Empty);
        assert_eq!(classify("lightning:"), PaymentDestination::Empty);
        assert!(matches!(classify(COFFEE), PaymentDestination::Bolt11(_)));
        assert!(matches!(
            classify(&format!("lightning:{}", COFFEE.to_ascii_uppercase())),
            PaymentDestination::Bolt11(_)
        ));
        assert_eq!(classify("lnbc2500u1abc"), PaymentDestination::MalformedBolt11);
        assert_eq!(classify("LNTB1abc"), PaymentDestination::MalformedBolt11);
        assert_eq!(
            classify("satoshi@example.com"),
            PaymentDestination::LightningAddress("satoshi@example.com".into())
        );
        assert_eq!(classify("LNURL1DP68GURN"), PaymentDestination::Unknown);
        assert_eq!(classify("hello"), PaymentDestination::Unknown);
        assert_eq!(classify("user@nodomain"), PaymentDestination::Unknown);
    }

    #[test]
    fn accepts_well_formed_lightning_addresses() {
        for address in [
            "satoshi@example.com",
            "a.b+c_d-e@sub.my-wallet.io",
            "USER@Example.COM",
        ] {
            assert!(
                matches!(classify(address), PaymentDestination::LightningAddress(_)),
                "{address}"
            );
        }
        assert_eq!(
            classify(" USER@Example.COM "),
            PaymentDestination::LightningAddress("user@example.com".into()),
            "normalized to lower case for the daemon"
        );
    }

    #[test]
    fn refuses_addresses_with_malformed_domains() {
        for address in [
            "user@example..com",     // consecutive dots
            "user@.example.com",     // leading dot
            "user@example.com.",     // trailing dot
            "user@-example.com",     // label starting with a hyphen
            "user@exam_ple.com",     // invalid host character
            "user@example.com/path", // URL delimiter
            "user@example.com?x=1",
            "us@er@example.com",
            "@example.com",
            "user@example.c1", // numeric TLD
        ] {
            assert_eq!(classify(address), PaymentDestination::Unknown, "{address}");
        }
    }

    #[test]
    fn normalize_strips_the_scheme_and_keeps_the_case() {
        assert_eq!(normalize("  lightning:LNBC1ABC \n"), "LNBC1ABC");
        assert_eq!(normalize("LIGHTNING: lnbc1abc"), "lnbc1abc");
        assert_eq!(normalize("satoshi@example.com"), "satoshi@example.com");
    }

    // ── check ───────────────────────────────────────────────────────────────

    const NOW: i64 = 1_700_000_000;

    fn bolt11(sats: Option<u64>) -> PaymentDestination {
        bolt11_msat(sats.map(|s| s * 1_000))
    }

    fn bolt11_msat(msat: Option<u64>) -> PaymentDestination {
        PaymentDestination::Bolt11(Bolt11Summary {
            amount_msat: msat,
            expires_at: NOW + 600,
            network: "mainnet".into(),
        })
    }

    fn expiring_at(expires_at: i64) -> PaymentDestination {
        PaymentDestination::Bolt11(Bolt11Summary {
            amount_msat: Some(250_000),
            expires_at,
            network: "mainnet".into(),
        })
    }

    fn on_network(network: &str) -> PaymentDestination {
        PaymentDestination::Bolt11(Bolt11Summary {
            amount_msat: Some(250_000),
            expires_at: NOW + 600,
            network: network.into(),
        })
    }

    fn verdict(destination: PaymentDestination) -> InvoiceVerdict {
        check(destination, Some(250), &[], None, NOW)
    }

    fn problem_of(verdict: &InvoiceVerdict) -> Option<InvoiceProblem> {
        match verdict {
            InvoiceVerdict::Rejected { problem, .. } => Some(*problem),
            _ => None,
        }
    }

    #[test]
    fn says_nothing_for_an_empty_field() {
        assert_eq!(verdict(PaymentDestination::Empty), InvoiceVerdict::Empty);
    }

    #[test]
    fn accepts_an_unexpired_invoice_for_the_trade_amount() {
        assert_eq!(
            verdict(bolt11(Some(250))),
            InvoiceVerdict::Valid {
                sats: 250,
                expires_at: NOW + 600
            }
        );
    }

    #[test]
    fn names_the_amounts_of_a_wrong_amount_invoice() {
        match verdict(bolt11(Some(300))) {
            InvoiceVerdict::Rejected {
                problem: InvoiceProblem::WrongAmount,
                actual_msat: Some(300_000),
                expected_sats: Some(250),
                ..
            } => {}
            other => panic!("{other:?}"),
        }
    }

    #[test]
    fn a_sub_sat_remainder_is_a_wrong_amount_not_a_rounded_match() {
        assert_eq!(
            problem_of(&verdict(bolt11_msat(Some(250_500)))),
            Some(InvoiceProblem::WrongAmount)
        );
    }

    #[test]
    fn refuses_an_expired_invoice_before_comparing_amounts() {
        let expired = PaymentDestination::Bolt11(Bolt11Summary {
            amount_msat: Some(300_000),
            expires_at: NOW,
            network: "mainnet".into(),
        });
        assert_eq!(problem_of(&verdict(expired)), Some(InvoiceProblem::Expired));
    }

    /// mostrod's `invoice_expiration_window`: a live invoice with too little
    /// lifetime left is refused as invalid by the daemon, so it is refused
    /// here too — and only when the node published the window.
    #[test]
    fn refuses_an_invoice_that_expires_before_the_node_window() {
        let soon = expiring_at(NOW + 600);
        match check(soon.clone(), Some(250), &[], Some(3_600), NOW) {
            InvoiceVerdict::Rejected {
                problem: InvoiceProblem::ExpiresTooSoon,
                min_remaining_secs: Some(3_600),
                ..
            } => {}
            other => panic!("{other:?}"),
        }
        let valid = InvoiceVerdict::Valid {
            sats: 250,
            expires_at: NOW + 600,
        };
        assert_eq!(
            check(soon.clone(), Some(250), &[], Some(600), NOW),
            valid,
            "exactly the window is enough"
        );
        assert_eq!(
            check(soon, Some(250), &[], None, NOW),
            valid,
            "no window advertised, no rule"
        );
    }

    #[test]
    fn refuses_an_invoice_for_another_network_than_the_node() {
        let mainnet = vec!["mainnet".to_string()];
        match check(on_network("testnet"), Some(250), &mainnet, None, NOW) {
            InvoiceVerdict::Rejected {
                problem: InvoiceProblem::WrongNetwork,
                invoice_network: Some(inv),
                node_network: Some(node),
                ..
            } => {
                assert_eq!(inv, "testnet");
                assert_eq!(node, "mainnet");
            }
            other => panic!("{other:?}"),
        }
    }

    #[test]
    fn a_matching_or_unknown_node_network_does_not_block() {
        let valid = InvoiceVerdict::Valid {
            sats: 250,
            expires_at: NOW + 600,
        };
        let testnet3 = vec![" testnet3 ".to_string()];
        assert_eq!(
            check(on_network("testnet"), Some(250), &testnet3, None, NOW),
            valid,
            "every testnet generation is lntb"
        );
        let many = vec!["mainnet".to_string(), "regtest".to_string()];
        assert_eq!(
            check(on_network("regtest"), Some(250), &many, None, NOW),
            valid
        );
        assert_eq!(
            check(on_network("signet"), Some(250), &[], None, NOW),
            valid,
            "a node that lists no network is not checked"
        );
    }

    #[test]
    fn calls_an_undecodable_invoice_malformed_and_the_rest_unrecognized() {
        assert_eq!(
            problem_of(&verdict(PaymentDestination::MalformedBolt11)),
            Some(InvoiceProblem::Malformed)
        );
        assert_eq!(
            problem_of(&verdict(PaymentDestination::Unknown)),
            Some(InvoiceProblem::Unrecognized)
        );
    }

    #[test]
    fn leaves_the_invoice_to_the_daemon_when_it_cannot_judge() {
        assert_eq!(verdict(bolt11(None)), InvoiceVerdict::Unverified);
        assert_eq!(
            check(bolt11(Some(250)), None, &[], None, NOW),
            InvoiceVerdict::Unverified
        );
    }

    #[test]
    fn an_address_is_accepted_as_such() {
        assert_eq!(
            verdict(PaymentDestination::LightningAddress("a@b.io".into())),
            InvoiceVerdict::Address
        );
    }

    #[test]
    fn the_bridge_entry_points_agree_with_the_pure_rules() {
        assert!(matches!(
            classify_payment_destination(COFFEE.into()),
            PaymentDestination::Bolt11(_)
        ));
        // The spec vector expired in 2017; the rule that fires first says so.
        assert_eq!(
            problem_of(&check_buyer_invoice(
                COFFEE.into(),
                Some(250_000),
                vec![],
                None,
                NOW
            )),
            Some(InvoiceProblem::Expired)
        );
    }
}
