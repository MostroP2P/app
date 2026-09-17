/// Web implementation of the bridge readiness probe.
///
/// See `bridge_probe.dart` for why the probe exists.
///
/// Two globals rather than one tri-state value, so the smoke test can poll for
/// success and still fail fast — with a reason — when the bridge is broken:
///
/// ```js
/// await page.waitForFunction(
///   () => window.mostroBridgeReady === true || window.mostroBridgeError,
/// );
/// ```
library;

import 'dart:js_interop';
// setProperty — "unsafe" only in the sense of a dynamically-keyed property,
// which is exactly what writing a named global is.
import 'dart:js_interop_unsafe';

/// Set to `true` once startup has finished, bridge calls included.
const kBridgeReadyFlag = 'mostroBridgeReady';

/// Set to the error string when a bridge call or startup itself failed.
const kBridgeErrorFlag = 'mostroBridgeError';

/// Publishes that startup finished, so the Rust bridge answered too.
void markBridgeReady() {
  globalContext.setProperty(kBridgeReadyFlag.toJS, true.toJS);
}

/// Publishes a failure, with [error] for the CI log.
///
/// Either a bridge call the app survives (startup keeps going, degraded) or a
/// fatal startup failure the guard caught. A build that reaches here is not
/// deployable either way.
void markBridgeFailed(Object error) {
  globalContext.setProperty(kBridgeErrorFlag.toJS, error.toString().toJS);
}
