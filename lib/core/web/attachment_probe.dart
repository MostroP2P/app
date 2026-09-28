/// Attachment round trip for the headless web smoke test (#589 phase 4).
///
/// On the web a file travels through the browser's `fetch`, from a
/// cross-origin isolated page to a Blossom server on another origin, and its
/// encrypted copy is cached in IndexedDB. A release build that breaks any of
/// that still loads and passes the bridge probe. So with `SMOKE_ATTACHMENTS=1`
/// the smoke test serves a Blossom endpoint on a second origin, names it
/// before the page loads, and waits for this to report the round trip:
/// encrypt, upload, download against the hash, cache, read back, decrypt
/// (`attachment_web_probe` in `rust/src/api/messages.rs`).
///
/// Only on request, like `store_probe.dart`: a production launch never
/// uploads anything.
library;

import 'package:mostro/core/web/attachment_probe_signal.dart';
import 'package:mostro/src/rust/api/messages.dart' as messages_api;

export 'package:mostro/core/web/attachment_probe_signal.dart'
    show attachmentProbeServer;

/// Runs the round trip against [server] and publishes how it went.
Future<void> publishAttachmentProbe(String server) async {
  try {
    await messages_api.attachmentWebProbe(server: server);
    markAttachmentProbe();
  } catch (e) {
    markAttachmentProbeFailed(e);
  }
}
