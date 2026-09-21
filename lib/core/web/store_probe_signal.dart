/// Page signals for the store read-back check (see `store_probe.dart`).
///
/// Kept apart from `bridge_probe.dart`: that one is always published, while
/// this one is published only when the page asks for it, and a flag renamed on
/// one side only should stay contained to this pair of files.
///
/// Off web every function here is a no-op and nothing is ever requested.
library;

export 'store_probe_signal_stub.dart'
    if (dart.library.js_interop) 'store_probe_signal_web.dart';
