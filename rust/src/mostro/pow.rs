/// Global NIP-13 Proof of Work difficulty required by the connected Mostro.
///
/// Set when the relay pool goes online by parsing the `pow` tag from
/// the daemon's Kind 38385 event.  Read by `gift_wrap::wrap` before signing.
use std::sync::atomic::{AtomicU8, Ordering};

static POW_DIFFICULTY: AtomicU8 = AtomicU8::new(0);

/// Store the required PoW difficulty for outgoing events.
pub fn set_pow(difficulty: u8) {
    POW_DIFFICULTY.store(difficulty, Ordering::Relaxed);
    log::info!("[pow] difficulty set to {difficulty}");
}

/// Current PoW difficulty.  Returns 0 when no PoW is required.
pub fn get_pow() -> u8 {
    POW_DIFFICULTY.load(Ordering::Relaxed)
}
