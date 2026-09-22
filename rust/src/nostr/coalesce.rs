//! Collapse a burst of requests for the same relay-side refresh into one.
//!
//! Re-issuing a long-lived subscription is a CLOSE plus a REQ on every relay,
//! and for a filter without `since` each REQ makes every relay replay its
//! whole stored history again. Several callers asking for that within moments
//! of each other — trade keys derived back to back, relays flapping in
//! lockstep — should cost one round, carrying the state as it is when the
//! window closes (docs/OPTIMIZATION_PLAN.md PR 3.6 and the gap left by 2.5).

use std::future::Future;
use std::sync::atomic::{AtomicBool, Ordering};

use crate::rt::time::Duration;
use crate::rt::MaybeSend;

/// One per refresh being coalesced; lives in a `static`.
pub(crate) struct Coalesced {
    armed: AtomicBool,
}

impl Coalesced {
    pub(crate) const fn new() -> Self {
        Self {
            armed: AtomicBool::new(false),
        }
    }

    /// Ask for `run` to happen `window` from now, unless a run is already
    /// armed — then this request rides along with it. Returns at once.
    ///
    /// The window is disarmed **before** `run` starts, so a request arriving
    /// while it is in flight arms a new one: `run` reads its input when it
    /// executes, and that request's change may have missed the read.
    pub(crate) fn request<F, Fut>(&'static self, window: Duration, run: F)
    where
        F: FnOnce() -> Fut + MaybeSend + 'static,
        Fut: Future<Output = ()> + MaybeSend + 'static,
    {
        if self.armed.swap(true, Ordering::AcqRel) {
            return;
        }
        crate::rt::spawn(async move {
            crate::rt::time::sleep(window).await;
            self.armed.store(false, Ordering::Release);
            run().await;
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::AtomicUsize;
    use std::sync::Arc;

    const WINDOW: Duration = Duration::from_millis(40);

    fn counter() -> (Arc<AtomicUsize>, impl Fn() -> std::future::Ready<()> + Clone + Send + 'static)
    {
        let runs = Arc::new(AtomicUsize::new(0));
        let sink = runs.clone();
        (runs, move || {
            sink.fetch_add(1, Ordering::SeqCst);
            std::future::ready(())
        })
    }

    async fn settle() {
        tokio::time::sleep(WINDOW * 4).await;
    }

    #[tokio::test]
    async fn a_burst_of_requests_runs_once() {
        // Arrange
        static BURST: Coalesced = Coalesced::new();
        let (runs, run) = counter();

        // Act
        for _ in 0..10 {
            BURST.request(WINDOW, run.clone());
        }
        settle().await;

        // Assert
        assert_eq!(runs.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn a_request_returns_before_the_run_happens() {
        // Arrange
        static DEFERRED: Coalesced = Coalesced::new();
        let (runs, run) = counter();

        // Act
        DEFERRED.request(WINDOW, run);

        // Assert
        assert_eq!(runs.load(Ordering::SeqCst), 0, "the caller must not wait");
        settle().await;
        assert_eq!(runs.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn a_request_after_the_window_closed_runs_again() {
        // Arrange
        static TWICE: Coalesced = Coalesced::new();
        let (runs, run) = counter();
        TWICE.request(WINDOW, run.clone());
        settle().await;

        // Act
        TWICE.request(WINDOW, run);
        settle().await;

        // Assert
        assert_eq!(runs.load(Ordering::SeqCst), 2);
    }

    /// The run reads its input when it starts; a change landing after that
    /// read must not be swallowed by the run still in flight.
    #[tokio::test]
    async fn a_request_during_a_run_arms_another() {
        // Arrange
        static OVERLAP: Coalesced = Coalesced::new();
        let runs = Arc::new(AtomicUsize::new(0));
        let slow = {
            let runs = runs.clone();
            move || async move {
                runs.fetch_add(1, Ordering::SeqCst);
                tokio::time::sleep(WINDOW * 3).await;
            }
        };
        OVERLAP.request(WINDOW, slow.clone());
        tokio::time::sleep(WINDOW * 2).await; // first run is now in flight

        // Act
        OVERLAP.request(WINDOW, slow);
        tokio::time::sleep(WINDOW * 8).await;

        // Assert
        assert_eq!(runs.load(Ordering::SeqCst), 2);
    }
}
