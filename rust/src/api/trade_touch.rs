//! The trade doorbell: "something about this trade changed — read it again".
//!
//! [`TradeUpdate`](crate::api::types::TradeUpdate) cannot play this part. It
//! carries meaning — notifications, navigation and the bell all act on it —
//! so it is emitted only for daemon-driven lifecycle steps, while plenty of
//! writes change what a trade screen shows without being one: a Kind 38383
//! update applied to the row, a hold invoice or an amount arriving, a bond, a
//! wipe. Those used to reach the UI only because every screen polled the
//! bridge once or twice a second (docs/OPTIMIZATION_PLAN.md PR 3.4).
//!
//! A touch says nothing about *what* changed, so ringing too often is
//! harmless — a listener re-reads state it already has — and ringing on every
//! write is the whole contract. A subscriber that fell behind gets a
//! [`TradeTouch`] with no order id: the missed touches are unknowable, so it
//! must re-read everything it shows.

use anyhow::Result;
use tokio::sync::broadcast;

use crate::api::types::TradeTouch;

/// A touch is an order id, and a burst is a few per trade step, so this only
/// overflows for a subscriber that stopped reading — which is what the
/// resync touch is for.
const CAPACITY: usize = 256;

static TOUCHES: std::sync::OnceLock<broadcast::Sender<String>> = std::sync::OnceLock::new();

fn sender() -> &'static broadcast::Sender<String> {
    TOUCHES.get_or_init(|| broadcast::channel(CAPACITY).0)
}

/// Ring the doorbell for `order_id`. Call it after every write that changes
/// what `get_order` or `list_trades` return for that order.
pub(crate) fn touch_trade(order_id: &str) {
    // An error only means nobody is listening.
    let _ = sender().send(order_id.to_string());
}

/// Stream of trade touches; see the module docs.
pub async fn on_trade_touched() -> Result<TradeTouchStream> {
    Ok(TradeTouchStream {
        rx: sender().subscribe(),
    })
}

/// Wrapper for flutter_rust_bridge Dart Stream generation.
pub struct TradeTouchStream {
    rx: broadcast::Receiver<String>,
}

impl TradeTouchStream {
    pub async fn next(&mut self) -> Option<TradeTouch> {
        match self.rx.recv().await {
            Ok(order_id) => Some(TradeTouch {
                order_id: Some(order_id),
            }),
            Err(broadcast::error::RecvError::Lagged(n)) => {
                log::warn!("[trade-touch] stream lagged, {n} touches dropped — asking for a resync");
                Some(TradeTouch { order_id: None })
            }
            Err(broadcast::error::RecvError::Closed) => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The channel is process-wide and tests run in parallel, so each test
    /// reads until it sees its own order id.
    async fn next_for(stream: &mut TradeTouchStream, order_id: &str) -> TradeTouch {
        loop {
            let touch = stream.next().await.expect("the sender is a static");
            if touch.order_id.as_deref() == Some(order_id) {
                return touch;
            }
        }
    }

    #[tokio::test]
    async fn a_touch_reaches_a_subscriber_with_its_order_id() {
        // Arrange
        let mut stream = on_trade_touched().await.unwrap();

        // Act
        touch_trade("touch-order-1");

        // Assert
        let touch = next_for(&mut stream, "touch-order-1").await;
        assert_eq!(touch.order_id.as_deref(), Some("touch-order-1"));
    }

    #[tokio::test]
    async fn a_subscriber_that_fell_behind_is_told_to_resync() {
        // Arrange
        let mut stream = on_trade_touched().await.unwrap();

        // Act: more touches than the channel holds, none of them read.
        for n in 0..=CAPACITY {
            touch_trade(&format!("touch-burst-{n}"));
        }

        // Assert: the first thing it hears is the resync, not a stale id.
        let touch = stream.next().await.unwrap();
        assert_eq!(touch.order_id, None);
    }

    #[tokio::test]
    async fn the_stream_keeps_delivering_after_a_resync() {
        // Arrange
        let mut stream = on_trade_touched().await.unwrap();
        for n in 0..=CAPACITY {
            touch_trade(&format!("touch-flood-{n}"));
        }
        assert_eq!(stream.next().await.unwrap().order_id, None);

        // Act
        touch_trade("touch-after-resync");

        // Assert
        next_for(&mut stream, "touch-after-resync").await;
    }

    #[tokio::test]
    async fn touching_with_no_subscriber_is_not_an_error() {
        touch_trade("touch-nobody-listening");
    }
}
