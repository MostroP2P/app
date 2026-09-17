/// Health signal published to the page once startup has finished.
///
/// On web the app ships as a wasm bundle whose worst failure mode is silent: a
/// toolchain or bundling regression kills flutter_rust_bridge's worker pool
/// (`DataCloneError`) while the DOM still looks perfectly healthy — the blank
/// page documented in `CLAUDE.md` under "Web (wasm) — non-obvious constraints".
/// Nothing observable from outside the app tells that apart from a working
/// build, so startup publishes that it finished — which takes real bridge calls
/// — or the cause when it failed, and the headless smoke test in CI waits for
/// either (issue #154). Finished, not just "the bridge answered": the smoke
/// test stops watching at this signal, so a later failure would go unseen.
///
/// Off web this is a no-op: there is no page to publish to, and the native
/// targets fail loudly at build time instead.
library;

export 'bridge_probe_stub.dart'
    if (dart.library.js_interop) 'bridge_probe_web.dart';
