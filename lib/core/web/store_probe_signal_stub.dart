/// Non-web implementation of the store read-back signals.
///
/// See `store_probe_signal.dart`.
library;

/// Never requested off web.
bool storeProbeRequested() => false;

/// No-op off web.
void markStoreProbe(String json) {}

/// No-op off web.
void markStoreProbeFailed(Object error) {}
