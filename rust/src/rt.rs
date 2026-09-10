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

/// Time provider for `universal-time`, which nostr 0.45 uses for every clock
/// read. On `wasm32-unknown-unknown` that crate has no default source and the
/// build fails at *link* time ("a time provider is required") until the final
/// crate defines one — so this is invisible to `cargo check` and only shows up
/// in `scripts/build-web.sh`. Backed by the same browser clock as
/// [`time`] so both agree on what "now" is.
#[cfg(target_arch = "wasm32")]
mod browser_clock {
    use std::sync::OnceLock;

    use universal_time::{define_time_provider, Instant, MonotonicClock, SystemTime, WallClock};

    struct BrowserClock;

    impl WallClock for BrowserClock {
        fn system_time(&self) -> SystemTime {
            let since_epoch = wasmtimer::std::SystemTime::now()
                .duration_since(wasmtimer::std::UNIX_EPOCH)
                .unwrap_or_default();
            SystemTime::from_unix_duration(since_epoch)
        }
    }

    impl MonotonicClock for BrowserClock {
        fn instant(&self) -> Instant {
            // wasmtimer exposes no raw tick count, so ticks are measured from
            // the first read; only differences between instants are meaningful.
            static ORIGIN: OnceLock<wasmtimer::std::Instant> = OnceLock::new();
            let origin = *ORIGIN.get_or_init(wasmtimer::std::Instant::now);
            Instant::from_ticks(wasmtimer::std::Instant::now().duration_since(origin))
        }
    }

    define_time_provider!(BrowserClock);
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
