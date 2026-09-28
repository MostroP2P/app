/// Non-web implementation of the attachment probe signals.
///
/// See `attachment_probe_signal.dart`.
library;

/// Never requested off web.
String? attachmentProbeServer() => null;

/// No-op off web.
void markAttachmentProbe() {}

/// No-op off web.
void markAttachmentProbeFailed(Object error) {}
