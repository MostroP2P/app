//! The service fee the active Mostro node charges, from its Kind 38385 `fee`
//! tag — phase C5 of `docs/cashu/README.md`.
//!
//! Same shape as [`crate::mostro::pow`]: a process-global refreshed by the same
//! capability fetch and cleared on node switch.
//!
//! In Lightning mode the client never needs this — the daemon skims the fee
//! from the payout. In Cashu mode the seller funds the **whole** fee as a
//! separate token at lock time, so the client has to compute the exact figure
//! the daemon expects, and a value off by one satoshi is rejected.

use std::sync::RwLock;

/// The fee as a fraction of the order amount (`0.006` = 0.6%), or `None`
/// before the first successful fetch.
static FEE: RwLock<Option<f64>> = RwLock::new(None);

/// Anything above this is a malformed tag, not a business decision.
const MAX_FEE_FRACTION: f64 = 1.0;

/// Record the fee fraction the node advertises.
///
/// Anything not finite or negative is discarded rather than stored: a garbage
/// fee would silently produce a fee token the daemon rejects, and the seller
/// would see a lock failure with no clue why.
pub fn set_fee(fraction: f64) {
    // Upper bound as well as lower: a malformed tag of `2.0` would be read as
    // 200% and produce a fee token larger than the escrow it accompanies.
    // No plausible node charges more than the whole amount.
    if !fraction.is_finite() || !(0.0..=MAX_FEE_FRACTION).contains(&fraction) {
        log::warn!("[node-fee] ignoring malformed fee fraction: {fraction}");
        return;
    }
    let mut guard = FEE.write().unwrap_or_else(|e| e.into_inner());
    *guard = Some(fraction);
    log::info!("[node-fee] fee fraction set to {fraction}");
}

/// The advertised fee fraction, or `None` if the node published none.
pub fn get_fee() -> Option<f64> {
    *FEE.read().unwrap_or_else(|e| e.into_inner())
}

/// Forget the fee. Called on node switch, so one node's fee is never applied to
/// another's order.
pub fn clear() {
    let mut guard = FEE.write().unwrap_or_else(|e| e.into_inner());
    *guard = None;
}

/// The satoshi fee **one side** of a trade owes on `amount_sats`.
///
/// Must match the daemon's `get_fee` exactly — `(fee * amount) / 2.0`, rounded
/// — because the escrow's fee token is checked for an exact value. Computing it
/// as `round(fee * amount) / 2` instead would differ by a satoshi on half the
/// amounts, and every one of those locks would be rejected.
pub fn split_fee_sats(amount_sats: u64, fraction: f64) -> u64 {
    let rounded = ((fraction * amount_sats as f64) / 2.0).round();
    if !rounded.is_finite() || rounded < 0.0 {
        return 0;
    }
    rounded as u64
}

/// The **whole** Mostro fee the seller funds in Cashu mode: `2 * order.fee`,
/// where `order.fee` is the per-side figure the daemon stored (daemon TA-1f).
///
/// Deliberately expressed as "twice the split fee" rather than "the fee on the
/// amount": the daemon rounds the half, so doubling the rounded half is the
/// only expression that agrees with it.
pub fn total_fee_sats(amount_sats: u64, fraction: f64) -> u64 {
    split_fee_sats(amount_sats, fraction).saturating_mul(2)
}

#[cfg(test)]
mod tests {
    use super::*;

    static GLOBAL: std::sync::Mutex<()> = std::sync::Mutex::new(());

    fn own_the_global() -> std::sync::MutexGuard<'static, ()> {
        let guard = GLOBAL.lock().unwrap_or_else(|e| e.into_inner());
        clear();
        guard
    }

    #[test]
    fn the_fee_is_unknown_until_a_node_advertises_one() {
        let _g = own_the_global();
        assert_eq!(get_fee(), None);

        set_fee(0.006);
        assert_eq!(get_fee(), Some(0.006));

        // A node switch must not carry one node's fee onto another's orders.
        clear();
        assert_eq!(get_fee(), None);
    }

    #[test]
    fn a_malformed_fee_is_discarded_rather_than_stored() {
        // Arrange — a fee that would produce a token the daemon rejects.
        let _g = own_the_global();
        set_fee(0.006);

        // Act / Assert — each bad value leaves the last good one in place.
        // `2.0` is 200%: a fee token twice the escrow, which no node charges.
        for bad in [f64::NAN, f64::INFINITY, -0.01, 2.0] {
            set_fee(bad);
            assert_eq!(get_fee(), Some(0.006), "{bad} must not be stored");
        }
    }

    #[test]
    fn the_split_fee_matches_the_daemons_rounding() {
        // Assert — the daemon computes (fee * amount) / 2.0 and rounds *that*.
        // 500 sat is the case where rounding the whole fee first disagrees,
        // which in production looks like a rejected lock with no explanation.
        assert_eq!(split_fee_sats(10_000, 0.006), 30);
        assert_eq!(split_fee_sats(1_000, 0.006), 3);
        assert_eq!(split_fee_sats(500, 0.006), 2); // 1.5 → 2
        assert_eq!(split_fee_sats(10_000, 0.0), 0);
    }

    #[test]
    fn the_total_fee_is_twice_the_rounded_half() {
        // Assert — doubling the rounded half, not rounding the double: at 500
        // sat the two differ (4 vs 3), and only the former equals what the
        // daemon stored as `2 * order.fee`.
        assert_eq!(total_fee_sats(500, 0.006), 4);
        assert_eq!(total_fee_sats(10_000, 0.006), 60);
        assert_eq!(total_fee_sats(10_000, 0.0), 0);
    }

    #[test]
    fn an_absurd_amount_cannot_overflow_the_fee() {
        // Assert — u64::MAX sats is unreachable, but the arithmetic must not
        // wrap into a small fee if it ever were.
        assert!(total_fee_sats(u64::MAX, 1.0) > 0);
    }
}
