/// Web implementation of the store read-back signals.
///
/// See `store_probe_signal.dart`.
library;

import 'dart:js_interop';
// getProperty / setProperty on a named global.
import 'dart:js_interop_unsafe';

/// Set to `true` by the smoke test, before the page loads, to ask for the
/// read-back. Absent in production, where nothing is read or published.
const kStoreProbeRequestFlag = 'mostroStoreProbeRequested';

/// Set to a JSON summary of the bond rows read back through the bridge.
const kStoreProbeFlag = 'mostroStoreProbe';

/// Set to the error string when reading those rows threw instead.
const kStoreProbeErrorFlag = 'mostroStoreProbeError';

/// Whether the page asked for the store read-back.
bool storeProbeRequested() =>
    globalContext.getProperty<JSAny?>(kStoreProbeRequestFlag.toJS).dartify() ==
    true;

/// Publishes what the persistent store handed back through the bridge, as
/// JSON, so the smoke test can compare it with the rows it seeded.
void markStoreProbe(String json) {
  globalContext.setProperty(kStoreProbeFlag.toJS, json.toJS);
}

/// Publishes a failed store read, with [error] for the CI log.
void markStoreProbeFailed(Object error) {
  globalContext.setProperty(kStoreProbeErrorFlag.toJS, error.toString().toJS);
}
