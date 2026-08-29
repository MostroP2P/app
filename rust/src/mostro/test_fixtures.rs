//! Shared `mostro_core` fixtures for the protocol modules' unit tests.
//!
//! `SmallOrder::new` takes fifteen positional arguments, only two of which
//! any of these tests care about. Both `pending` (classifying a take reply)
//! and `status` (syncing an add-invoice) need one, so the constructor lives
//! here instead of being spelled out — differently — in each test module.

/// A `SmallOrder` carrying just `status` and `amount`; every other field is
/// the same inert placeholder for all callers.
pub(crate) fn small_order_with(
    status: mostro_core::order::Status,
    amount: i64,
) -> mostro_core::order::SmallOrder {
    mostro_core::order::SmallOrder::new(
        None,
        Some(mostro_core::order::Kind::Sell),
        Some(status),
        amount,
        "USD".to_string(),
        None,
        None,
        100,
        "bank".to_string(),
        0,
        None,
        None,
        None,
        None,
        None,
    )
}
