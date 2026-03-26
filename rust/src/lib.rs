mod frb_generated; /* AUTO INJECTED BY flutter_rust_bridge. This line may not be accurate, and you can change it according to your needs. */
pub mod api;
pub mod crypto;
pub mod network;
pub mod protocol;
pub mod storage;

// Feature-gated async runtime.
//
// Native (iOS, Android, macOS, Windows, Linux):
//   tokio multi-threaded runtime — initialized once via OnceLock.
//
// WASM (Web):
//   wasm-bindgen-futures::spawn_local — browser is single-threaded.
//   tokio is NOT available on WASM (requires OS threads).
//
// Constitution: all async Rust code must compile and work on both targets.
// Any new async function MUST be tested on both runtimes.

#[cfg(not(target_arch = "wasm32"))]
#[allow(dead_code)]
mod native {
    use std::sync::OnceLock;
    use tokio::runtime::Runtime;

    static RUNTIME: OnceLock<Runtime> = OnceLock::new();

    pub fn runtime() -> &'static Runtime {
        RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"))
    }
}

// On WASM: use wasm_bindgen_futures::spawn_local(async { ... }) for async tasks.
// Async functions annotated with #[flutter_rust_bridge::frb] are polled automatically
// by the WASM executor — no manual spawning needed for bridge calls.

// flutter_rust_bridge generated boilerplate lives in frb_generated.rs,
// which is emitted by: flutter_rust_bridge_codegen generate  (Phase 2 T023)
// That file includes the proper frb_generated_boilerplate!(...) call with
// the codec and opaque-type arguments required by FRB 2.x.
// Do NOT add frb_generated_boilerplate!() here manually — it requires codegen output.
