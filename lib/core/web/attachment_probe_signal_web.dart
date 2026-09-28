/// Web implementation of the attachment probe signals.
///
/// See `attachment_probe_signal.dart`.
library;

import 'dart:js_interop';
// getProperty / setProperty on a named global.
import 'dart:js_interop_unsafe';

/// Set by the smoke test, before the page loads, to the base URL of the
/// Blossom endpoint it serves. Absent in production.
const kAttachmentProbeServerFlag = 'mostroAttachmentProbeServer';

/// Set to `true` once the round trip succeeded.
const kAttachmentProbeFlag = 'mostroAttachmentProbe';

/// Set to the error string when it failed instead.
const kAttachmentProbeErrorFlag = 'mostroAttachmentProbeError';

/// The server the smoke test asked the round trip to run against, if any.
String? attachmentProbeServer() {
  final value =
      globalContext
          .getProperty<JSAny?>(kAttachmentProbeServerFlag.toJS)
          .dartify();
  return value is String && value.isNotEmpty ? value : null;
}

void markAttachmentProbe() {
  globalContext.setProperty(kAttachmentProbeFlag.toJS, true.toJS);
}

void markAttachmentProbeFailed(Object error) {
  globalContext.setProperty(
    kAttachmentProbeErrorFlag.toJS,
    error.toString().toJS,
  );
}
