//! Platform runtime shims.
//!
//! Native builds run on the Tokio runtime; `wasm32` has none, so task spawning
//! and timers are backed by `wasm-bindgen-futures` and `wasmtimer`. Call sites
//! use `crate::rt::{spawn, time}` instead of the `tokio` equivalents so both
//! targets compile from a single source.

/// Spawn a detached background task.
///
/// All current callers are fire-and-forget, so the join handle is intentionally
/// dropped. On `wasm32` this delegates to `spawn_local` (no `Send` bound, since
/// the single-threaded executor never moves the future across threads).
#[cfg(not(target_arch = "wasm32"))]
pub fn spawn<F>(future: F)
where
    F: std::future::Future<Output = ()> + Send + 'static,
{
    tokio::spawn(future);
}

#[cfg(target_arch = "wasm32")]
pub fn spawn<F>(future: F)
where
    F: std::future::Future<Output = ()> + 'static,
{
    wasm_bindgen_futures::spawn_local(future);
}

/// Timer and clock primitives mirroring the subset of `std::time` / `tokio::time`
/// used by the crate.
///
/// `SystemTime`/`UNIX_EPOCH` matter for the wall clock: `std::time::SystemTime::now()`
/// is unimplemented on `wasm32-unknown-unknown` and panics at runtime ("time not
/// implemented on this platform"). `wasmtimer` provides a browser-backed drop-in, so
/// every wall-clock read must go through `crate::rt::time` (or `unix_now()` below).
#[cfg(not(target_arch = "wasm32"))]
pub mod time {
    pub use std::time::{SystemTime, UNIX_EPOCH};
    pub use tokio::time::{sleep, timeout, Duration, Instant};
}

#[cfg(target_arch = "wasm32")]
pub mod time {
    pub use std::time::Duration;
    pub use wasmtimer::std::{Instant, SystemTime, UNIX_EPOCH};
    pub use wasmtimer::tokio::{sleep, timeout};
}

/// Current Unix time in whole seconds, on both native and wasm.
///
/// Returns 0 if the clock is before the Unix epoch (never happens in practice),
/// mirroring the `unwrap_or_default()` behaviour of the call sites this replaces.
pub fn unix_now() -> i64 {
    time::SystemTime::now()
        .duration_since(time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}
