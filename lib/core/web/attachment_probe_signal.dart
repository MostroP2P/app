/// Page signals for the attachment round trip (see `attachment_probe.dart`).
///
/// Off web every function here is a no-op and nothing is ever requested.
library;

export 'attachment_probe_signal_stub.dart'
    if (dart.library.js_interop) 'attachment_probe_signal_web.dart';
