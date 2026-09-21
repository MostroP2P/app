//! Recovery from a trade-key counter the daemon has already passed.
//!
//! The daemon keeps each identity's last trade index and refuses any new
//! order or take whose index is not above it with `CantDo(InvalidTradeIndex)`.
//! The local counter falls behind whenever the same seed trades elsewhere —
//! another device, or v1 of the app — or when it was imported without a
//! restore. A refused request is therefore retried once, after raising the
//! counter to the daemon's own figure (`LastTradeIndex`).

use std::future::Future;

use anyhow::Result;

/// The marker the order paths return for `CantDo(InvalidTradeIndex)`. Dart
/// maps it to a localized message (`daemon_errors.dart`).
pub const INVALID_TRADE_INDEX: &str = "InvalidTradeIndex";

/// True when [error] is the daemon's refusal of a stale trade index.
pub fn is_invalid_trade_index(error: &anyhow::Error) -> bool {
    error.to_string() == INVALID_TRADE_INDEX
}

/// Runs [attempt]; if the daemon refuses its trade index, runs [resync] and,
/// when that raised the counter, [attempt] once more.
///
/// [resync] returns the daemon's counter, or `None` when the daemon gave no
/// usable answer — then a retry would derive the next local index and be
/// refused the same way, so the original error is returned instead. Any other
/// error, and a second refusal, are returned as they are: there is never more
/// than one retry.
pub async fn retry_after_resync<T, A, AF, R, RF>(mut attempt: A, resync: R) -> Result<T>
where
    A: FnMut() -> AF,
    AF: Future<Output = Result<T>>,
    R: FnOnce() -> RF,
    RF: Future<Output = Result<Option<u32>>>,
{
    let first = attempt().await;
    let Err(error) = &first else { return first };
    if !is_invalid_trade_index(error) {
        return first;
    }
    match resync().await {
        Ok(Some(counter)) => {
            crate::api::logging::blog_warn(
                "orders",
                format!("{INVALID_TRADE_INDEX}: counter resynced to {counter}; retrying once"),
            );
            attempt().await
        }
        Ok(None) => {
            crate::api::logging::blog_warn(
                "orders",
                format!("{INVALID_TRADE_INDEX}: daemon gave no counter; not retrying"),
            );
            first
        }
        Err(e) => {
            crate::api::logging::blog_warn(
                "orders",
                format!("{INVALID_TRADE_INDEX}: resync failed ({e}); not retrying"),
            );
            first
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    fn refused() -> anyhow::Error {
        anyhow::anyhow!(INVALID_TRADE_INDEX)
    }

    #[tokio::test]
    async fn retries_once_after_a_resync_that_raised_the_counter() {
        let attempts = AtomicUsize::new(0);
        let resyncs = AtomicUsize::new(0);

        let result = retry_after_resync(
            || {
                let n = attempts.fetch_add(1, Ordering::SeqCst);
                async move {
                    if n == 0 {
                        Err(refused())
                    } else {
                        Ok("order")
                    }
                }
            },
            || {
                resyncs.fetch_add(1, Ordering::SeqCst);
                async { Ok(Some(7)) }
            },
        )
        .await;

        assert_eq!(result.unwrap(), "order");
        assert_eq!(attempts.load(Ordering::SeqCst), 2);
        assert_eq!(resyncs.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn never_retries_more_than_once() {
        let attempts = AtomicUsize::new(0);

        let result: Result<()> = retry_after_resync(
            || {
                attempts.fetch_add(1, Ordering::SeqCst);
                async { Err(refused()) }
            },
            || async { Ok(Some(7)) },
        )
        .await;

        assert!(is_invalid_trade_index(&result.unwrap_err()));
        assert_eq!(attempts.load(Ordering::SeqCst), 2);
    }

    #[tokio::test]
    async fn does_not_retry_when_the_daemon_gives_no_counter() {
        let attempts = AtomicUsize::new(0);

        let result: Result<()> = retry_after_resync(
            || {
                attempts.fetch_add(1, Ordering::SeqCst);
                async { Err(refused()) }
            },
            || async { Ok(None) },
        )
        .await;

        assert!(is_invalid_trade_index(&result.unwrap_err()));
        assert_eq!(attempts.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn does_not_retry_when_the_resync_fails() {
        let attempts = AtomicUsize::new(0);

        let result: Result<()> = retry_after_resync(
            || {
                attempts.fetch_add(1, Ordering::SeqCst);
                async { Err(refused()) }
            },
            || async { Err(anyhow::anyhow!("relay down")) },
        )
        .await;

        assert!(is_invalid_trade_index(&result.unwrap_err()));
        assert_eq!(attempts.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn other_errors_neither_resync_nor_retry() {
        let attempts = AtomicUsize::new(0);
        let resyncs = AtomicUsize::new(0);

        let result: Result<()> = retry_after_resync(
            || {
                attempts.fetch_add(1, Ordering::SeqCst);
                async { Err(anyhow::anyhow!("NoDaemonResponse")) }
            },
            || {
                resyncs.fetch_add(1, Ordering::SeqCst);
                async { Ok(Some(7)) }
            },
        )
        .await;

        assert_eq!(result.unwrap_err().to_string(), "NoDaemonResponse");
        assert_eq!(attempts.load(Ordering::SeqCst), 1);
        assert_eq!(resyncs.load(Ordering::SeqCst), 0);
    }
}
